const std = @import("std");
const ModuleManifest = @import("ModuleManifest.zig");
const TargetModule = @import("Target.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Dependency = struct {
    name: []const u8,
    manifest_path: []const u8,
    sources: []const []const u8,
    targets: []const []const u8,

    pub fn supports(self: Dependency, allocator: Allocator, target: TargetModule.Target) !bool {
        const target_name = try target.cacheName(allocator);
        for (self.targets) |supported_target| {
            if (std.mem.eql(u8, supported_target, target_name)) return true;
        }
        return false;
    }
};

pub const SourceKind = enum { c, cpp, objective_c, objective_cpp };

pub const SourceFile = struct {
    kind: SourceKind,
    path: []const u8,
};

pub const Define = struct {
    name: []const u8,
    value: []const u8,
};

pub const RuntimeOrigin = enum { project, package, distributed };

pub const ModuleRuntime = struct {
    module_name: []const u8,
    module_directory: []const u8,
    manifest_path: []const u8,
    package_index: usize = 0,
    origin: RuntimeOrigin = .package,
    provides: []const []const u8 = &.{},
    sources: []const SourceFile,
    include_dirs: []const []const u8,
    public_include_dirs: []const []const u8 = &.{},
    defines: []const Define,
    public_defines: []const Define = &.{},
    system_libraries: []const []const u8,
    frameworks: []const []const u8,
};

pub const ModuleRuntimeDiagnostic = union(enum) {
    duplicate_source: struct {
        path: []const u8,
        first_level: []const u8,
        repeated_level: []const u8,
    },
};

const Manifest = struct {
    name: []const u8,
    sources: []const []const u8,
    targets: []const []const u8,
};

const SourceLists = struct {
    c: []const []const u8 = &.{},
    cpp: []const []const u8 = &.{},
    objective_c: []const []const u8 = &.{},
    objective_cpp: []const []const u8 = &.{},
};

const RuntimeConfiguration = struct {
    sources: SourceLists = .{},
    include_dirs: []const []const u8 = &.{},
    public_include_dirs: []const []const u8 = &.{},
    defines: std.json.Value = .{ .object = .empty },
    public_defines: std.json.Value = .{ .object = .empty },
    system_libraries: []const []const u8 = &.{},
    frameworks: []const []const u8 = &.{},
};

const NativeRoot = struct {
    provides: []const []const u8 = &.{},
    sources: SourceLists = .{},
    include_dirs: []const []const u8 = &.{},
    public_include_dirs: []const []const u8 = &.{},
    defines: std.json.Value = .{ .object = .empty },
    public_defines: std.json.Value = .{ .object = .empty },
    system_libraries: []const []const u8 = &.{},
    frameworks: []const []const u8 = &.{},
    targets: std.json.Value = .{ .object = .empty },

    fn configuration(self: NativeRoot) RuntimeConfiguration {
        return .{
            .sources = self.sources,
            .include_dirs = self.include_dirs,
            .public_include_dirs = self.public_include_dirs,
            .defines = self.defines,
            .public_defines = self.public_defines,
            .system_libraries = self.system_libraries,
            .frameworks = self.frameworks,
        };
    }
};

const RuntimeComposition = struct {
    sources: std.ArrayList(SourceFile) = .empty,
    source_levels: std.ArrayList([]const u8) = .empty,
    include_dirs: std.ArrayList([]const u8) = .empty,
    defines: std.ArrayList(Define) = .empty,
    public_include_dirs: std.ArrayList([]const u8) = .empty,
    public_defines: std.ArrayList(Define) = .empty,
    system_libraries: std.ArrayList([]const u8) = .empty,
    frameworks: std.ArrayList([]const u8) = .empty,
};

pub fn load(allocator: Allocator, io: Io, manifest_path: []const u8) !Dependency {
    const contents = try Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024));
    const manifest = try std.json.parseFromSliceLeaky(Manifest, allocator, contents, .{
        .allocate = .alloc_always,
    });
    if (manifest.name.len == 0 or manifest.sources.len == 0 or manifest.targets.len == 0) {
        return error.IncompleteNativeDependency;
    }

    const manifest_dir = std.fs.path.dirname(manifest_path) orelse ".";
    const sources = try allocator.alloc([]const u8, manifest.sources.len);
    for (manifest.sources, 0..) |source, index| {
        sources[index] = try std.fs.path.join(allocator, &.{ manifest_dir, source });
    }

    return .{
        .name = manifest.name,
        .manifest_path = manifest_path,
        .sources = sources,
        .targets = manifest.targets,
    };
}

pub fn validateModuleNative(allocator: Allocator, value: std.json.Value) !void {
    const root = try parseNativeRoot(allocator, value);
    try validateNativeRoot(allocator, root);
}

pub fn loadModuleRuntime(
    allocator: Allocator,
    io: Io,
    module_name: []const u8,
    module_directory: []const u8,
    package_root: []const u8,
    manifest_path: []const u8,
    target: TargetModule.Target,
    diagnostic: *?ModuleRuntimeDiagnostic,
) !ModuleRuntime {
    diagnostic.* = null;
    const manifest = try ModuleManifest.load(allocator, io, manifest_path);
    const native_value = manifest.native orelse return error.InvalidModuleManifest;
    const root = try parseNativeRoot(allocator, native_value);
    try validateNativeRoot(allocator, root);
    const target_name = try target.cacheName(allocator);
    const os_name = @tagName(target.os_tag);
    const targets = switch (root.targets) {
        .object => |object| object,
        else => return error.InvalidModuleManifest,
    };

    var composition: RuntimeComposition = .{};
    try appendConfiguration(
        allocator,
        io,
        module_directory,
        package_root,
        "native",
        root.configuration(),
        &composition,
        diagnostic,
    );
    if (targets.get(os_name)) |os_value| {
        const level = try std.fmt.allocPrint(allocator, "targets.{s}", .{os_name});
        try appendConfiguration(
            allocator,
            io,
            module_directory,
            package_root,
            level,
            try parseConfiguration(allocator, os_value),
            &composition,
            diagnostic,
        );
    }
    if (targets.get(target_name)) |target_value| {
        const level = try std.fmt.allocPrint(allocator, "targets.{s}", .{target_name});
        try appendConfiguration(
            allocator,
            io,
            module_directory,
            package_root,
            level,
            try parseConfiguration(allocator, target_value),
            &composition,
            diagnostic,
        );
    }

    var provides: std.ArrayList([]const u8) = .empty;
    try appendLinkNames(allocator, root.provides, &provides);
    var defines: std.ArrayList(Define) = .empty;
    try defines.appendSlice(allocator, composition.public_defines.items);
    for (composition.defines.items) |define| try appendCompatibleDefine(allocator, define, &defines);
    return .{
        .module_name = module_name,
        .module_directory = module_directory,
        .manifest_path = manifest_path,
        .provides = try provides.toOwnedSlice(allocator),
        .sources = try composition.sources.toOwnedSlice(allocator),
        .include_dirs = try composition.include_dirs.toOwnedSlice(allocator),
        .public_include_dirs = try composition.public_include_dirs.toOwnedSlice(allocator),
        .defines = try defines.toOwnedSlice(allocator),
        .public_defines = try composition.public_defines.toOwnedSlice(allocator),
        .system_libraries = try composition.system_libraries.toOwnedSlice(allocator),
        .frameworks = try composition.frameworks.toOwnedSlice(allocator),
    };
}

fn parseConfiguration(allocator: Allocator, value: std.json.Value) !RuntimeConfiguration {
    return std.json.parseFromValueLeaky(RuntimeConfiguration, allocator, value, .{
        .ignore_unknown_fields = false,
    });
}

fn parseNativeRoot(allocator: Allocator, value: std.json.Value) !NativeRoot {
    return std.json.parseFromValueLeaky(NativeRoot, allocator, value, .{
        .ignore_unknown_fields = false,
    });
}

fn validateNativeRoot(allocator: Allocator, root: NativeRoot) !void {
    for (root.provides) |name| if (!isLinkName(name)) return error.InvalidModuleManifest;
    try validateConfiguration(root.configuration());
    const targets = switch (root.targets) {
        .object => |object| object,
        else => return error.InvalidModuleManifest,
    };
    var iterator = targets.iterator();
    while (iterator.next()) |entry| {
        if (!isTargetSelector(entry.key_ptr.*)) return error.InvalidModuleManifest;
        try validateConfiguration(try parseConfiguration(allocator, entry.value_ptr.*));
    }
}

fn validateConfiguration(configuration: RuntimeConfiguration) !void {
    for (configuration.sources.c) |path| try validateModulePath(path);
    for (configuration.sources.cpp) |path| try validateModulePath(path);
    for (configuration.sources.objective_c) |path| try validateModulePath(path);
    for (configuration.sources.objective_cpp) |path| try validateModulePath(path);
    for (configuration.include_dirs) |path| try validateModulePath(path);
    for (configuration.public_include_dirs) |path| try validateModulePath(path);

    const defines = switch (configuration.defines) {
        .object => |object| object,
        else => return error.InvalidModuleManifest,
    };
    var define_iterator = defines.iterator();
    while (define_iterator.next()) |entry| {
        if (!isLinkName(entry.key_ptr.*)) return error.InvalidModuleManifest;
        if (entry.value_ptr.* != .string) return error.InvalidModuleManifest;
    }
    const public_defines = switch (configuration.public_defines) {
        .object => |object| object,
        else => return error.InvalidModuleManifest,
    };
    var public_define_iterator = public_defines.iterator();
    while (public_define_iterator.next()) |entry| {
        if (!isLinkName(entry.key_ptr.*)) return error.InvalidModuleManifest;
        if (entry.value_ptr.* != .string) return error.InvalidModuleManifest;
    }
    for (configuration.system_libraries) |name| if (!isLinkName(name)) return error.InvalidModuleManifest;
    for (configuration.frameworks) |name| if (!isLinkName(name)) return error.InvalidModuleManifest;
}

fn validateModulePath(path: []const u8) !void {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return error.InvalidModuleManifest;
    var components = std.mem.tokenizeAny(u8, path, "/\\");
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidModuleManifest;
    }
}

fn isTargetSelector(selector: []const u8) bool {
    if (std.meta.stringToEnum(std.Target.Os.Tag, selector) != null) return true;
    var separator_count: usize = 0;
    for (selector) |character| if (character == '-') {
        separator_count += 1;
    };
    if (separator_count < 2) return false;
    _ = std.Target.Query.parse(.{ .arch_os_abi = selector }) catch return false;
    return true;
}

fn appendConfiguration(
    allocator: Allocator,
    io: Io,
    module_directory: []const u8,
    package_root: []const u8,
    level: []const u8,
    configuration: RuntimeConfiguration,
    composition: *RuntimeComposition,
    diagnostic: *?ModuleRuntimeDiagnostic,
) !void {
    try appendSources(allocator, io, module_directory, level, .c, configuration.sources.c, composition, diagnostic);
    try appendSources(allocator, io, module_directory, level, .cpp, configuration.sources.cpp, composition, diagnostic);
    try appendSources(allocator, io, module_directory, level, .objective_c, configuration.sources.objective_c, composition, diagnostic);
    try appendSources(allocator, io, module_directory, level, .objective_cpp, configuration.sources.objective_cpp, composition, diagnostic);
    for (configuration.include_dirs) |path| {
        const resolved = try resolveModulePath(allocator, io, module_directory, path);
        const stat = try Io.Dir.cwd().statFile(io, resolved, .{});
        if (stat.kind != .directory) return error.InvalidModuleManifest;
        try appendUnique(allocator, &composition.include_dirs, resolved);
    }
    for (configuration.public_include_dirs) |path| {
        const resolved = try resolveModulePath(allocator, io, package_root, path);
        const stat = try Io.Dir.cwd().statFile(io, resolved, .{});
        if (stat.kind != .directory) return error.InvalidModuleManifest;
        try appendUnique(allocator, &composition.include_dirs, resolved);
        try appendUnique(allocator, &composition.public_include_dirs, resolved);
    }
    try appendDefines(allocator, configuration.defines, &composition.defines);
    try appendDefines(allocator, configuration.public_defines, &composition.public_defines);
    try appendLinkNames(allocator, configuration.system_libraries, &composition.system_libraries);
    try appendLinkNames(allocator, configuration.frameworks, &composition.frameworks);
}

fn appendSources(
    allocator: Allocator,
    io: Io,
    module_directory: []const u8,
    level: []const u8,
    kind: SourceKind,
    paths: []const []const u8,
    composition: *RuntimeComposition,
    diagnostic: *?ModuleRuntimeDiagnostic,
) !void {
    for (paths) |path| {
        const resolved = try resolveModulePath(allocator, io, module_directory, path);
        const stat = try Io.Dir.cwd().statFile(io, resolved, .{});
        if (stat.kind != .file) return error.InvalidModuleManifest;
        for (composition.sources.items, 0..) |source, index| {
            if (!std.mem.eql(u8, source.path, resolved)) continue;
            diagnostic.* = .{ .duplicate_source = .{
                .path = resolved,
                .first_level = composition.source_levels.items[index],
                .repeated_level = level,
            } };
            return error.DuplicateNativeSource;
        }
        try composition.sources.append(allocator, .{ .kind = kind, .path = resolved });
        try composition.source_levels.append(allocator, level);
    }
}

fn appendDefines(allocator: Allocator, value: std.json.Value, defines: *std.ArrayList(Define)) !void {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidModuleManifest,
    };
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        const define_value = switch (entry.value_ptr.*) {
            .string => |string| string,
            else => return error.InvalidModuleManifest,
        };
        if (!isLinkName(entry.key_ptr.*)) return error.InvalidModuleManifest;
        var replaced = false;
        for (defines.items) |*define| {
            if (!std.mem.eql(u8, define.name, entry.key_ptr.*)) continue;
            define.value = define_value;
            replaced = true;
            break;
        }
        if (!replaced) try defines.append(allocator, .{ .name = entry.key_ptr.*, .value = define_value });
    }
}

fn appendCompatibleDefine(allocator: Allocator, value: Define, defines: *std.ArrayList(Define)) !void {
    for (defines.items) |existing| {
        if (!std.mem.eql(u8, existing.name, value.name)) continue;
        if (!std.mem.eql(u8, existing.value, value.value)) return error.ConflictingNativeDefine;
        return;
    }
    try defines.append(allocator, value);
}

fn appendLinkNames(allocator: Allocator, names: []const []const u8, result: *std.ArrayList([]const u8)) !void {
    for (names) |name| {
        if (!isLinkName(name)) return error.InvalidModuleManifest;
        try appendUnique(allocator, result, name);
    }
}

fn appendUnique(allocator: Allocator, result: *std.ArrayList([]const u8), value: []const u8) !void {
    for (result.items) |existing| if (std.mem.eql(u8, existing, value)) return;
    try result.append(allocator, value);
}

fn resolveModulePath(allocator: Allocator, io: Io, module_directory: []const u8, path: []const u8) ![]const u8 {
    try validateModulePath(path);
    const joined = try std.fs.path.join(allocator, &.{ module_directory, path });
    const canonical_module_directory = try Io.Dir.cwd().realPathFileAlloc(io, module_directory, allocator);
    const canonical_path = try Io.Dir.cwd().realPathFileAlloc(io, joined, allocator);
    if (!isPathWithin(canonical_module_directory, canonical_path)) return error.InvalidModuleManifest;
    return canonical_path;
}

fn isPathWithin(root: []const u8, path: []const u8) bool {
    return std.mem.startsWith(u8, path, root) and path.len > root.len and path[root.len] == std.fs.path.sep;
}

fn isLinkName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '_' and character != '+' and character != '-' and character != '.') return false;
    }
    return true;
}

test "dependency declares supported targets" {
    const dependency: Dependency = .{
        .name = "example",
        .manifest_path = "example.json",
        .sources = &.{"example.cpp"},
        .targets = &.{"x86_64-linux-musl"},
    };
    const target = try TargetModule.Target.parse(std.testing.allocator, std.testing.io, "x86_64-linux-musl");
    defer std.testing.allocator.free(target.zig_triple.?);

    try std.testing.expect(try dependency.supports(std.testing.allocator, target));
    try std.testing.expect(!try dependency.supports(std.testing.allocator, TargetModule.Target.native()));
}

test "module native root applies to an explicit target without overrides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Module.cpp", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "@Module.json",
        .data = "{\"native\":{\"sources\":{\"cpp\":[\"Module.cpp\"]}}}",
    });
    const directory = try testModuleDirectory(allocator, temporary.sub_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ directory, "@Module.json" });
    const target = try TargetModule.Target.parse(allocator, std.testing.io, "riscv64-linux-musl");
    var diagnostic: ?ModuleRuntimeDiagnostic = null;
    const runtime = try loadModuleRuntime(
        allocator,
        std.testing.io,
        "Portable",
        directory,
        directory,
        manifest_path,
        target,
        &diagnostic,
    );

    try std.testing.expect(diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), runtime.sources.len);
    try std.testing.expectEqual(SourceKind.cpp, runtime.sources[0].kind);
    try std.testing.expectEqualStrings("Module.cpp", std.fs.path.basename(runtime.sources[0].path));
}

test "OS and exact target overrides compose in order and normalize options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Includes", .default_dir);
    for ([_][]const u8{ "Common.cpp", "Linux.cpp", "Exact.cpp" }) |source| {
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = source, .data = "" });
    }
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "@Module.json",
        .data =
        \\{
        \\  "native": {
        \\    "sources": { "cpp": ["Common.cpp"] },
        \\    "include_dirs": ["Includes"],
        \\    "defines": { "MODE": "root", "ROOT": "1" },
        \\    "system_libraries": ["m"],
        \\    "frameworks": ["ExampleKit"],
        \\    "targets": {
        \\      "linux": {
        \\        "sources": { "cpp": ["Linux.cpp"] },
        \\        "include_dirs": ["Includes"],
        \\        "defines": { "MODE": "os" },
        \\        "system_libraries": ["m"]
        \\      },
        \\      "x86_64-linux-musl": {
        \\        "sources": { "cpp": ["Exact.cpp"] },
        \\        "defines": { "MODE": "triple" },
        \\        "system_libraries": ["pthread"],
        \\        "frameworks": ["ExampleKit"]
        \\      }
        \\    }
        \\  }
        \\}
        ,
    });
    const directory = try testModuleDirectory(allocator, temporary.sub_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ directory, "@Module.json" });
    const target = try TargetModule.Target.parse(allocator, std.testing.io, "x86_64-linux-musl");
    var diagnostic: ?ModuleRuntimeDiagnostic = null;
    const runtime = try loadModuleRuntime(
        allocator,
        std.testing.io,
        "Layered",
        directory,
        directory,
        manifest_path,
        target,
        &diagnostic,
    );

    try std.testing.expectEqual(@as(usize, 3), runtime.sources.len);
    try std.testing.expectEqualStrings("Common.cpp", std.fs.path.basename(runtime.sources[0].path));
    try std.testing.expectEqualStrings("Linux.cpp", std.fs.path.basename(runtime.sources[1].path));
    try std.testing.expectEqualStrings("Exact.cpp", std.fs.path.basename(runtime.sources[2].path));
    try std.testing.expectEqual(@as(usize, 1), runtime.include_dirs.len);
    try std.testing.expectEqual(@as(usize, 2), runtime.defines.len);
    try std.testing.expectEqualStrings("MODE", runtime.defines[0].name);
    try std.testing.expectEqualStrings("triple", runtime.defines[0].value);
    try std.testing.expectEqualStrings("ROOT", runtime.defines[1].name);
    try std.testing.expectEqualStrings("1", runtime.defines[1].value);
    try std.testing.expectEqualSlices([]const u8, &.{ "m", "pthread" }, runtime.system_libraries);
    try std.testing.expectEqualSlices([]const u8, &.{"ExampleKit"}, runtime.frameworks);
}

test "SDL-shaped native configuration selects common and OS files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "Vendor/SDL/include");
    try temporary.dir.createDirPath(std.testing.io, "Vendor/SDL/src/video/cocoa");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Vendor/SDL/src/SDL.c", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Vendor/SDL/src/video/cocoa/SDL_cocoa.m", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "@Module.json",
        .data =
        \\{
        \\  "native": {
        \\    "sources": { "c": ["Vendor/SDL/src/SDL.c"] },
        \\    "include_dirs": ["Vendor/SDL/include"],
        \\    "targets": {
        \\      "macos": {
        \\        "sources": { "objective_c": ["Vendor/SDL/src/video/cocoa/SDL_cocoa.m"] },
        \\        "frameworks": ["Cocoa"]
        \\      }
        \\    }
        \\  }
        \\}
        ,
    });
    const directory = try testModuleDirectory(allocator, temporary.sub_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ directory, "@Module.json" });
    const target = try TargetModule.Target.parse(allocator, std.testing.io, "aarch64-macos-none");
    var diagnostic: ?ModuleRuntimeDiagnostic = null;
    const runtime = try loadModuleRuntime(
        allocator,
        std.testing.io,
        "SDL",
        directory,
        directory,
        manifest_path,
        target,
        &diagnostic,
    );

    try std.testing.expectEqual(@as(usize, 2), runtime.sources.len);
    try std.testing.expectEqual(SourceKind.c, runtime.sources[0].kind);
    try std.testing.expectEqual(SourceKind.objective_c, runtime.sources[1].kind);
    try std.testing.expectEqual(@as(usize, 1), runtime.include_dirs.len);
    try std.testing.expectEqualSlices([]const u8, &.{"Cocoa"}, runtime.frameworks);
}

test "duplicate canonical source reports both configuration levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Runtime.c", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "@Module.json",
        .data =
        \\{
        \\  "native": {
        \\    "sources": { "c": ["Runtime.c"] },
        \\    "targets": {
        \\      "linux": { "sources": { "cpp": ["Runtime.c"] } }
        \\    }
        \\  }
        \\}
        ,
    });
    const directory = try testModuleDirectory(allocator, temporary.sub_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ directory, "@Module.json" });
    const target = try TargetModule.Target.parse(allocator, std.testing.io, "x86_64-linux-musl");
    var diagnostic: ?ModuleRuntimeDiagnostic = null;

    try std.testing.expectError(error.DuplicateNativeSource, loadModuleRuntime(
        allocator,
        std.testing.io,
        "Duplicate",
        directory,
        directory,
        manifest_path,
        target,
        &diagnostic,
    ));
    const duplicate = diagnostic.?.duplicate_source;
    try std.testing.expectEqualStrings("Runtime.c", std.fs.path.basename(duplicate.path));
    try std.testing.expectEqualStrings("native", duplicate.first_level);
    try std.testing.expectEqualStrings("targets.linux", duplicate.repeated_level);
}

fn testModuleDirectory(allocator: Allocator, temporary_sub_path: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temporary_sub_path });
}
