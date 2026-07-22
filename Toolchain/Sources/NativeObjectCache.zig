const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const NativeDependency = @import("NativeDependency.zig");
const NativeCommand = @import("NativeCommand.zig");
const PackageGraph = @import("PackageGraph.zig");
const TargetModule = @import("Target.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnvironMap = std.process.Environ.Map;

pub const format = "v1";

pub const Entry = struct {
    origin: NativeDependency.RuntimeOrigin,
    package_index: usize,
    manifest_path: []const u8,
    package_label: []const u8,
    key: [64]u8,
    object_count: usize,
};

pub const Plan = struct {
    entries: []const Entry,
};

pub const Prepared = struct {
    objects: []const []const u8,
    compiled_packages: []const []const u8,
    reused_packages: []const []const u8,
};

pub fn makePlan(
    allocator: Allocator,
    io: Io,
    graph: PackageGraph.Graph,
    runtimes: []const NativeDependency.ModuleRuntime,
    target: TargetModule.Target,
    compiler_flags: []const []const u8,
) !Plan {
    var entries: std.ArrayList(Entry) = .empty;
    for (runtimes) |runtime| {
        if (runtime.sources.len == 0 or runtime.origin == .project) continue;
        for (entries.items) |entry| {
            if (entryOwnsRuntime(entry, runtime)) break;
        } else {
            const package_root = switch (runtime.origin) {
                .project => unreachable,
                .package => graph.packages[runtime.package_index].root,
                .distributed => std.fs.path.dirname(runtime.manifest_path) orelse runtime.module_directory,
            };
            const package_label = switch (runtime.origin) {
                .project => unreachable,
                .package => graph.packageLabel(runtime.package_index),
                .distributed => runtime.module_name,
            };

            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update("silex-native-object-cache-");
            hasher.update(format);
            hasher.update("\x00owner\x00");
            hasher.update(@tagName(runtime.origin));
            hasher.update("\x00label\x00");
            hasher.update(package_label);
            if (runtime.origin == .package) {
                hasher.update("\x00version\x00");
                hasher.update(graph.packages[runtime.package_index].version orelse "");
            }
            hasher.update("\x00silex-");
            hasher.update(build_options.silex_version);
            hasher.update("\x00zig-");
            hasher.update(builtin.zig_version_string);
            hashTarget(&hasher, target);
            for (compiler_flags) |flag| {
                hasher.update("\x00flag\x00");
                hasher.update(flag);
            }

            var object_count: usize = 0;
            for (runtimes) |owned_runtime| {
                if (!sameOwner(runtime, owned_runtime)) continue;
                object_count += owned_runtime.sources.len;
                try hashRuntimeInputs(
                    allocator,
                    io,
                    &hasher,
                    package_root,
                    owned_runtime,
                );
            }

            var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
            hasher.final(&digest);
            try entries.append(allocator, .{
                .origin = runtime.origin,
                .package_index = runtime.package_index,
                .manifest_path = runtime.manifest_path,
                .package_label = package_label,
                .key = std.fmt.bytesToHex(digest, .lower),
                .object_count = object_count,
            });
        }
    }
    return .{ .entries = try entries.toOwnedSlice(allocator) };
}

pub fn prepareShared(
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    zig_path: []const u8,
    target: TargetModule.Target,
    target_name: []const u8,
    compiler_flags: []const []const u8,
    runtimes: []const NativeDependency.ModuleRuntime,
    plan: Plan,
    backend_log_path: []const u8,
    progress: std.Progress.Node,
) !Prepared {
    const root = try objectCacheRoot(allocator, environ_map);
    const target_root = try std.fs.path.join(allocator, &.{ root, format, target_name });
    try Io.Dir.cwd().createDirPath(io, target_root);

    var objects: std.ArrayList([]const u8) = .empty;
    var compiled: std.ArrayList([]const u8) = .empty;
    var reused: std.ArrayList([]const u8) = .empty;
    for (plan.entries) |entry| {
        const entry_path = try std.fs.path.join(allocator, &.{ target_root, &entry.key });
        if (try entryComplete(allocator, io, entry_path, entry.object_count)) {
            try reused.append(allocator, entry.package_label);
            for (0..entry.object_count) |_| progress.completeOne();
        } else {
            const lock = try acquireEntryLock(allocator, io, target_root, &entry.key);
            defer if (lock) |file| file.close(io);
            if (try entryComplete(allocator, io, entry_path, entry.object_count)) {
                try reused.append(allocator, entry.package_label);
                for (0..entry.object_count) |_| progress.completeOne();
            } else {
                Io.Dir.cwd().deleteTree(io, entry_path) catch {};
                const published = try compileAndPublish(
                    allocator,
                    io,
                    zig_path,
                    target,
                    compiler_flags,
                    runtimes,
                    entry,
                    target_root,
                    entry_path,
                    backend_log_path,
                    progress,
                );
                if (published) {
                    try compiled.append(allocator, entry.package_label);
                } else {
                    try reused.append(allocator, entry.package_label);
                }
            }
        }
        for (0..entry.object_count) |object_index| {
            try objects.append(allocator, try objectPath(allocator, entry_path, object_index));
        }
    }
    return .{
        .objects = try objects.toOwnedSlice(allocator),
        .compiled_packages = try compiled.toOwnedSlice(allocator),
        .reused_packages = try reused.toOwnedSlice(allocator),
    };
}

fn acquireEntryLock(
    allocator: Allocator,
    io: Io,
    target_root: []const u8,
    key: []const u8,
) !?Io.File {
    const filename = try std.fmt.allocPrint(allocator, ".{s}.lock", .{key});
    const path = try std.fs.path.join(allocator, &.{ target_root, filename });
    return acquireExclusiveLock(io, path);
}

pub fn acquireExclusiveLock(io: Io, path: []const u8) !?Io.File {
    return Io.Dir.cwd().createFile(io, path, .{
        .read = true,
        .truncate = false,
        .lock = .exclusive,
    }) catch |err| switch (err) {
        error.FileLocksUnsupported => null,
        else => |other| return other,
    };
}

pub fn objectCacheRoot(allocator: Allocator, environ_map: *const EnvironMap) ![]const u8 {
    return objectCacheRootForOs(allocator, environ_map, builtin.os.tag);
}

fn objectCacheRootForOs(
    allocator: Allocator,
    environ_map: *const EnvironMap,
    os_tag: std.Target.Os.Tag,
) ![]const u8 {
    const root = try userCacheRootForOs(allocator, environ_map, os_tag);
    return std.fs.path.join(allocator, &.{ root, "objects" });
}

pub fn compilerCacheRoot(
    allocator: Allocator,
    environ_map: *const EnvironMap,
    target_name: []const u8,
    lane: usize,
) ![]const u8 {
    const root = try userCacheRootForOs(allocator, environ_map, builtin.os.tag);
    const lane_name = try std.fmt.allocPrint(allocator, "lane-{d}", .{lane});
    return std.fs.path.join(allocator, &.{
        root,
        "compiler",
        "v1",
        builtin.zig_version_string,
        target_name,
        lane_name,
    });
}

fn userCacheRootForOs(
    allocator: Allocator,
    environ_map: *const EnvironMap,
    os_tag: std.Target.Os.Tag,
) ![]const u8 {
    if (environ_map.get("SILEX_HOME")) |silex_home| {
        return std.fs.path.join(allocator, &.{ silex_home, "cache" });
    }
    if (os_tag == .windows) {
        if (environ_map.get("LOCALAPPDATA")) |local| {
            return std.fs.path.join(allocator, &.{ local, "Silex", "cache" });
        }
        const profile = environ_map.get("USERPROFILE") orelse return error.UserCacheUnavailable;
        return std.fs.path.join(allocator, &.{ profile, ".silex", "cache" });
    }
    const home = environ_map.get("HOME") orelse return error.UserCacheUnavailable;
    return std.fs.path.join(allocator, &.{ home, ".silex", "cache" });
}

fn compileAndPublish(
    allocator: Allocator,
    io: Io,
    zig_path: []const u8,
    target: TargetModule.Target,
    compiler_flags: []const []const u8,
    runtimes: []const NativeDependency.ModuleRuntime,
    entry: Entry,
    target_root: []const u8,
    entry_path: []const u8,
    backend_log_path: []const u8,
    progress: std.Progress.Node,
) !bool {
    var random_bytes: [8]u8 = undefined;
    io.random(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);
    const temporary_name = try std.fmt.allocPrint(allocator, ".{s}.tmp-{s}", .{ &entry.key, &random_hex });
    const temporary_path = try std.fs.path.join(allocator, &.{ target_root, temporary_name });
    try Io.Dir.cwd().createDirPath(io, temporary_path);
    errdefer Io.Dir.cwd().deleteTree(io, temporary_path) catch {};

    var requests: std.ArrayList(NativeCommand.CompileRequest) = .empty;
    var object_index: usize = 0;
    for (runtimes) |runtime| {
        if (!entryOwnsRuntime(entry, runtime)) continue;
        for (runtime.sources) |source| {
            const destination = try objectPath(allocator, temporary_path, object_index);
            try requests.append(allocator, .{
                .runtime = runtime,
                .source = source,
                .output_path = destination,
            });
            object_index += 1;
        }
    }
    std.debug.assert(object_index == entry.object_count);
    try NativeCommand.compileObjects(
        allocator,
        io,
        zig_path,
        target,
        compiler_flags,
        requests.items,
        backend_log_path,
        progress,
    );
    const marker = try std.fmt.allocPrint(allocator, "{d}\n", .{entry.object_count});
    const marker_path = try std.fs.path.join(allocator, &.{ temporary_path, ".complete" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = marker_path, .data = marker });

    return publishTemporary(allocator, io, temporary_path, entry_path, entry.object_count);
}

fn publishTemporary(
    allocator: Allocator,
    io: Io,
    temporary_path: []const u8,
    entry_path: []const u8,
    object_count: usize,
) !bool {
    Io.Dir.cwd().renamePreserve(temporary_path, .cwd(), entry_path, io) catch |err| switch (err) {
        error.PathAlreadyExists => return useConcurrentPublication(
            allocator,
            io,
            temporary_path,
            entry_path,
            object_count,
        ),
        error.PermissionDenied, error.OperationUnsupported => {
            Io.Dir.cwd().rename(temporary_path, .cwd(), entry_path, io) catch |fallback_err| switch (fallback_err) {
                error.DirNotEmpty, error.PermissionDenied, error.AccessDenied => return useConcurrentPublication(
                    allocator,
                    io,
                    temporary_path,
                    entry_path,
                    object_count,
                ),
                else => |other| return other,
            };
            return true;
        },
        else => |other| return other,
    };
    return true;
}

fn useConcurrentPublication(
    allocator: Allocator,
    io: Io,
    temporary_path: []const u8,
    entry_path: []const u8,
    object_count: usize,
) !bool {
    Io.Dir.cwd().deleteTree(io, temporary_path) catch {};
    if (!try entryComplete(allocator, io, entry_path, object_count)) return error.SharedObjectCacheIncomplete;
    return false;
}

fn entryComplete(allocator: Allocator, io: Io, entry_path: []const u8, expected_count: usize) !bool {
    const marker_path = try std.fs.path.join(allocator, &.{ entry_path, ".complete" });
    const marker = Io.Dir.cwd().readFileAlloc(io, marker_path, allocator, .limited(64)) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    const count = std.fmt.parseUnsigned(usize, std.mem.trim(u8, marker, " \t\r\n"), 10) catch return false;
    if (count != expected_count) return false;
    for (0..expected_count) |object_index| {
        const path = try objectPath(allocator, entry_path, object_index);
        const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return false,
            else => |other| return other,
        };
        if (stat.kind != .file) return false;
    }
    return true;
}

fn objectPath(allocator: Allocator, directory: []const u8, index: usize) ![]const u8 {
    const name = try std.fmt.allocPrint(allocator, "object-{d}.o", .{index});
    return std.fs.path.join(allocator, &.{ directory, name });
}

fn sameOwner(left: NativeDependency.ModuleRuntime, right: NativeDependency.ModuleRuntime) bool {
    if (left.origin != right.origin) return false;
    return switch (left.origin) {
        .project => false,
        .package => left.package_index == right.package_index,
        .distributed => std.mem.eql(u8, left.manifest_path, right.manifest_path),
    };
}

fn entryOwnsRuntime(entry: Entry, runtime: NativeDependency.ModuleRuntime) bool {
    if (entry.origin != runtime.origin) return false;
    return switch (entry.origin) {
        .project => false,
        .package => entry.package_index == runtime.package_index,
        .distributed => std.mem.eql(u8, entry.manifest_path, runtime.manifest_path),
    };
}

fn hashRuntimeInputs(
    allocator: Allocator,
    io: Io,
    hasher: *std.crypto.hash.sha2.Sha256,
    package_root: []const u8,
    runtime: NativeDependency.ModuleRuntime,
) !void {
    hasher.update("\x00runtime\x00");
    for (runtime.include_dirs, 0..) |include_dir, index| {
        hasher.update("\x00include-order\x00");
        var index_buffer: [32]u8 = undefined;
        hasher.update(std.fmt.bufPrint(&index_buffer, "{d}", .{index}) catch unreachable);
        if (relativeWithin(package_root, include_dir)) |relative| hasher.update(relative);
    }
    for (runtime.defines) |define| {
        hasher.update("\x00define\x00");
        hasher.update(define.name);
        hasher.update("=");
        hasher.update(define.value);
    }

    var visited: std.ArrayList([]const u8) = .empty;
    for (runtime.sources) |source| {
        hasher.update("\x00source-kind\x00");
        hasher.update(@tagName(source.kind));
        try hashInputFile(
            allocator,
            io,
            hasher,
            package_root,
            runtime.include_dirs,
            source.path,
            &visited,
        );
    }
}

fn hashInputFile(
    allocator: Allocator,
    io: Io,
    hasher: *std.crypto.hash.sha2.Sha256,
    package_root: []const u8,
    include_dirs: []const []const u8,
    path: []const u8,
    visited: *std.ArrayList([]const u8),
) !void {
    const canonical = try Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
    for (visited.items) |existing| if (std.mem.eql(u8, existing, canonical)) return;
    try visited.append(allocator, canonical);

    const contents = try Io.Dir.cwd().readFileAlloc(io, canonical, allocator, .limited(16 * 1024 * 1024));
    hasher.update("\x00input\x00");
    if (logicalPath(package_root, include_dirs, canonical)) |logical| hasher.update(logical);
    hasher.update("\x00");
    hasher.update(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const include = parseInclude(line) orelse continue;
        const resolved = try resolveInclude(allocator, io, canonical, include_dirs, include.path, include.quoted) orelse continue;
        try hashInputFile(allocator, io, hasher, package_root, include_dirs, resolved, visited);
    }
}

const Include = struct {
    path: []const u8,
    quoted: bool,
};

fn parseInclude(line: []const u8) ?Include {
    var remaining = std.mem.trimStart(u8, line, " \t");
    if (remaining.len == 0 or remaining[0] != '#') return null;
    remaining = std.mem.trimStart(u8, remaining[1..], " \t");
    if (!std.mem.startsWith(u8, remaining, "include")) return null;
    remaining = std.mem.trimStart(u8, remaining["include".len..], " \t");
    if (remaining.len < 3) return null;
    const closing: u8 = switch (remaining[0]) {
        '"' => '"',
        '<' => '>',
        else => return null,
    };
    const end = std.mem.indexOfScalarPos(u8, remaining, 1, closing) orelse return null;
    return .{ .path = remaining[1..end], .quoted = remaining[0] == '"' };
}

fn resolveInclude(
    allocator: Allocator,
    io: Io,
    including_file: []const u8,
    include_dirs: []const []const u8,
    include_path: []const u8,
    quoted: bool,
) !?[]const u8 {
    if (quoted) {
        const directory = std.fs.path.dirname(including_file) orelse ".";
        const candidate = try std.fs.path.join(allocator, &.{ directory, include_path });
        if (try regularFile(io, candidate)) return candidate;
    }
    for (include_dirs) |include_dir| {
        const candidate = try std.fs.path.join(allocator, &.{ include_dir, include_path });
        if (try regularFile(io, candidate)) return candidate;
    }
    return null;
}

fn logicalPath(package_root: []const u8, include_dirs: []const []const u8, path: []const u8) ?[]const u8 {
    if (relativeWithin(package_root, path)) |relative| return relative;
    for (include_dirs) |include_dir| if (relativeWithin(include_dir, path)) |relative| return relative;
    return std.fs.path.basename(path);
}

fn relativeWithin(root: []const u8, path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, root)) return null;
    if (path.len == root.len) return "";
    if (path[root.len] != std.fs.path.sep) return null;
    return path[root.len + 1 ..];
}

fn regularFile(io: Io, path: []const u8) !bool {
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    return stat.kind == .file;
}

fn hashTarget(hasher: *std.crypto.hash.sha2.Sha256, target: TargetModule.Target) void {
    hasher.update("\x00target\x00");
    hasher.update(@tagName(target.cpu_arch));
    hasher.update("-");
    hasher.update(@tagName(target.os_tag));
    hasher.update("-");
    hasher.update(@tagName(target.abi));
    if (target.zig_triple) |triple| {
        hasher.update("\x00triple\x00");
        hasher.update(triple);
    }
}

test "include parser recognizes literal C and C++ includes" {
    try std.testing.expectEqualStrings("Private.h", parseInclude(" # include \"Private.h\"").?.path);
    try std.testing.expectEqualStrings("Vendor/Public.hpp", parseInclude("#include <Vendor/Public.hpp>").?.path);
    try std.testing.expect(parseInclude("#include HEADER_NAME") == null);
}

test "completion marker requires every expected object" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    defer std.testing.allocator.free(root);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = ".complete", .data = "2\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "object-0.o", .data = "first" });
    try std.testing.expect(!(try entryComplete(std.testing.allocator, std.testing.io, root, 2)));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "object-1.o", .data = "second" });
    try std.testing.expect(try entryComplete(std.testing.allocator, std.testing.io, root, 2));
}

test "package object key follows native inputs but ignores Silex-only changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Source.c",
        .data = "#include <Header.h>\nint value(void) { return VALUE; }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Header.h", .data = "#define VALUE 1\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Only.sx", .data = "public func value() int { return 1 }\n" });
    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const source = try std.fs.path.join(allocator, &.{ root, "Source.c" });
    const graph: PackageGraph.Graph = .{
        .explicit = true,
        .packages = &.{.{
            .name = "Fixture",
            .version = "1.0.0",
            .root = root,
            .manifest_path = null,
            .dependencies = &.{},
            .first_chain = "application",
            .origin = .root,
        }},
    };
    const runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Fixture",
        .module_directory = root,
        .manifest_path = "@Module.json",
        .sources = &.{.{ .kind = .c, .path = source }},
        .include_dirs = &.{root},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const first = try makePlan(allocator, std.testing.io, graph, &.{runtime}, TargetModule.Target.native(), &.{"-O2"});

    try temporary.dir.createDir(std.testing.io, "Copy", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Copy/Source.c",
        .data = "#include <Header.h>\nint value(void) { return VALUE; }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Copy/Header.h", .data = "#define VALUE 1\n" });
    const copy_root = try std.fs.path.join(allocator, &.{ root, "Copy" });
    const copy_source = try std.fs.path.join(allocator, &.{ copy_root, "Source.c" });
    const copy_graph: PackageGraph.Graph = .{
        .explicit = true,
        .packages = &.{.{
            .name = "Fixture",
            .version = "1.0.0",
            .root = copy_root,
            .manifest_path = null,
            .dependencies = &.{},
            .first_chain = "application",
            .origin = .root,
        }},
    };
    const copy_runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Fixture",
        .module_directory = copy_root,
        .manifest_path = "@Module.json",
        .sources = &.{.{ .kind = .c, .path = copy_source }},
        .include_dirs = &.{copy_root},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const copied = try makePlan(allocator, std.testing.io, copy_graph, &.{copy_runtime}, TargetModule.Target.native(), &.{"-O2"});
    try std.testing.expectEqualSlices(u8, &first.entries[0].key, &copied.entries[0].key);

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Only.sx", .data = "public func value() int { return 2 }\n" });
    const after_silex = try makePlan(allocator, std.testing.io, graph, &.{runtime}, TargetModule.Target.native(), &.{"-O2"});
    try std.testing.expectEqualSlices(u8, &first.entries[0].key, &after_silex.entries[0].key);

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Header.h", .data = "#define VALUE 2\n" });
    const after_header = try makePlan(allocator, std.testing.io, graph, &.{runtime}, TargetModule.Target.native(), &.{"-O2"});
    try std.testing.expect(!std.mem.eql(u8, &first.entries[0].key, &after_header.entries[0].key));

    const linux = try TargetModule.Target.parse(allocator, std.testing.io, "x86_64-linux-musl");
    const other_target = try makePlan(allocator, std.testing.io, graph, &.{runtime}, linux, &.{"-O2"});
    try std.testing.expect(!std.mem.eql(u8, &after_header.entries[0].key, &other_target.entries[0].key));
    const other_flags = try makePlan(
        allocator,
        std.testing.io,
        graph,
        &.{runtime},
        TargetModule.Target.native(),
        &.{"-O3"},
    );
    try std.testing.expect(!std.mem.eql(u8, &after_header.entries[0].key, &other_flags.entries[0].key));

    var versioned_packages = [_]PackageGraph.Package{graph.packages[0]};
    versioned_packages[0].version = "2.0.0";
    const versioned_graph: PackageGraph.Graph = .{
        .explicit = true,
        .packages = &versioned_packages,
    };
    const other_version = try makePlan(
        allocator,
        std.testing.io,
        versioned_graph,
        &.{runtime},
        TargetModule.Target.native(),
        &.{"-O2"},
    );
    try std.testing.expect(!std.mem.eql(u8, &after_header.entries[0].key, &other_version.entries[0].key));
}

test "distributed runtimes are shared independently from project runtimes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Project.c", .data = "int project(void) { return 1; }\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "STD.c", .data = "int library(void) { return 2; }\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "@Module.json", .data = "{}\n" });
    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const project_source = try std.fs.path.join(allocator, &.{ root, "Project.c" });
    const distributed_source = try std.fs.path.join(allocator, &.{ root, "STD.c" });
    const manifest = try std.fs.path.join(allocator, &.{ root, "@Module.json" });
    const graph: PackageGraph.Graph = .{
        .explicit = true,
        .packages = &.{.{
            .name = null,
            .version = null,
            .root = root,
            .manifest_path = null,
            .dependencies = &.{},
            .first_chain = "application",
            .origin = .root,
        }},
    };
    const project_runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Application",
        .module_directory = root,
        .manifest_path = manifest,
        .origin = .project,
        .sources = &.{.{ .kind = .c, .path = project_source }},
        .include_dirs = &.{root},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const distributed_runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "STD",
        .module_directory = root,
        .manifest_path = manifest,
        .origin = .distributed,
        .sources = &.{.{ .kind = .c, .path = distributed_source }},
        .include_dirs = &.{root},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };

    const plan = try makePlan(
        allocator,
        std.testing.io,
        graph,
        &.{ project_runtime, distributed_runtime },
        TargetModule.Target.native(),
        &.{},
    );
    try std.testing.expectEqual(@as(usize, 1), plan.entries.len);
    try std.testing.expectEqual(NativeDependency.RuntimeOrigin.distributed, plan.entries[0].origin);
    try std.testing.expectEqualStrings("STD", plan.entries[0].package_label);
    try std.testing.expectEqual(@as(usize, 1), plan.entries[0].object_count);
}

test "Windows object cache falls back from LOCALAPPDATA to USERPROFILE" {
    var environment = EnvironMap.init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("LOCALAPPDATA", "local-data");
    try environment.put("USERPROFILE", "profile");
    const local = try objectCacheRootForOs(std.testing.allocator, &environment, .windows);
    defer std.testing.allocator.free(local);
    const expected_local = try std.fs.path.join(
        std.testing.allocator,
        &.{ "local-data", "Silex", "cache", "objects" },
    );
    defer std.testing.allocator.free(expected_local);
    try std.testing.expectEqualStrings(expected_local, local);

    _ = environment.remove("LOCALAPPDATA");
    const profile = try objectCacheRootForOs(std.testing.allocator, &environment, .windows);
    defer std.testing.allocator.free(profile);
    const expected_profile = try std.fs.path.join(
        std.testing.allocator,
        &.{ "profile", ".silex", "cache", "objects" },
    );
    defer std.testing.allocator.free(expected_profile);
    try std.testing.expectEqualStrings(expected_profile, profile);
}
