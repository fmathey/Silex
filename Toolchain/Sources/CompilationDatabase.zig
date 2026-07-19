const std = @import("std");
const NativeCommand = @import("NativeCommand.zig");
const NativeDependency = @import("NativeDependency.zig");
const TargetModule = @import("Target.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Scope = enum { project, distributed };

const Entry = struct {
    directory: []const u8,
    arguments: []const []const u8,
    file: []const u8,
};

pub fn write(
    allocator: Allocator,
    io: Io,
    artifact_root: []const u8,
    zig_path: []const u8,
    target: TargetModule.Target,
    compiler_flags: []const []const u8,
    runtimes: []const NativeDependency.ModuleRuntime,
    scope: Scope,
    editor_interface_root: ?[]const u8,
) !?[]const u8 {
    var entries: std.ArrayList(Entry) = .empty;
    const directory = try Io.Dir.cwd().realPathFileAlloc(
        io,
        if (artifact_root.len == 0) "." else artifact_root,
        allocator,
    );
    defer allocator.free(directory);
    for (runtimes) |runtime| {
        const selected = switch (scope) {
            .project => runtime.origin == .project,
            .distributed => runtime.origin == .distributed,
        };
        if (!selected) continue;
        var editor_runtime = runtime;
        if (editor_interface_root) |root| {
            var include_dirs: std.ArrayList([]const u8) = .empty;
            try include_dirs.append(allocator, root);
            try include_dirs.appendSlice(allocator, runtime.include_dirs);
            editor_runtime.include_dirs = try include_dirs.toOwnedSlice(allocator);
        }
        for (runtime.sources) |source| {
            try entries.append(allocator, .{
                .directory = directory,
                .arguments = try NativeCommand.compileArguments(
                    allocator,
                    zig_path,
                    target,
                    compiler_flags,
                    editor_runtime,
                    source,
                    null,
                ),
                .file = source.path,
            });
        }
    }
    if (entries.items.len == 0) return null;

    const contents = try std.json.Stringify.valueAlloc(allocator, entries.items, .{
        .whitespace = .indent_2,
    });
    const with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{contents});
    const path = try std.fs.path.join(allocator, &.{ artifact_root, "compile_commands.json" });
    const temporary_path = try std.fs.path.join(allocator, &.{ artifact_root, "compile_commands.json.tmp" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = temporary_path, .data = with_newline });
    errdefer Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
    try Io.Dir.cwd().rename(temporary_path, .cwd(), path, io);
    return path;
}

test "write native C and C++ compilation entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const database_allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Runtime.c", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Runtime.cpp", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Distributed.cpp", .data = "" });
    const root = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    defer std.testing.allocator.free(root);
    const c_source = try std.fs.path.join(std.testing.allocator, &.{ root, "Runtime.c" });
    defer std.testing.allocator.free(c_source);
    const cpp_source = try std.fs.path.join(std.testing.allocator, &.{ root, "Runtime.cpp" });
    defer std.testing.allocator.free(cpp_source);
    const distributed_source = try std.fs.path.join(std.testing.allocator, &.{ root, "Distributed.cpp" });
    defer std.testing.allocator.free(distributed_source);
    const runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Probe",
        .module_directory = root,
        .manifest_path = "@Module.json",
        .origin = .project,
        .sources = &.{
            .{ .kind = .c, .path = c_source },
            .{ .kind = .cpp, .path = cpp_source },
        },
        .include_dirs = &.{"Includes"},
        .defines = &.{.{ .name = "MODE", .value = "editor" }},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const distributed_runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Distributed",
        .module_directory = root,
        .manifest_path = "Distributed/@Module.json",
        .origin = .distributed,
        .sources = &.{.{ .kind = .cpp, .path = distributed_source }},
        .include_dirs = &.{},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };

    const path = (try write(
        database_allocator,
        std.testing.io,
        root,
        "/distribution/toolchain/zig/zig",
        TargetModule.Target.native(),
        &.{"-O2"},
        &.{ runtime, distributed_runtime },
        .project,
        ".silex/interfaces",
    )).?;
    const contents = try Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, contents, "\"directory\""));
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"cc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"c++\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"-std=c++23\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"-I.silex/interfaces\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"-IIncludes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"-DMODE=editor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"-O2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Distributed.cpp") == null);

    const distributed_path = (try write(
        database_allocator,
        std.testing.io,
        root,
        "/distribution/toolchain/zig/zig",
        TargetModule.Target.native(),
        &.{},
        &.{ runtime, distributed_runtime },
        .distributed,
        ".silex/interfaces",
    )).?;
    const distributed_contents = try Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        distributed_path,
        std.testing.allocator,
        .limited(64 * 1024),
    );
    defer std.testing.allocator.free(distributed_contents);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, distributed_contents, "\"directory\""));
    try std.testing.expect(std.mem.indexOf(u8, distributed_contents, "Distributed.cpp") != null);
    try std.testing.expect(std.mem.indexOf(u8, distributed_contents, "Runtime.cpp") == null);
}

test "do not create a compilation database without native sources" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    defer std.testing.allocator.free(root);

    try std.testing.expect((try write(
        std.testing.allocator,
        std.testing.io,
        root,
        "/distribution/toolchain/zig/zig",
        TargetModule.Target.native(),
        &.{},
        &.{},
        .project,
        null,
    )) == null);
    try std.testing.expectError(
        error.FileNotFound,
        temporary.dir.access(std.testing.io, "compile_commands.json", .{}),
    );
}
