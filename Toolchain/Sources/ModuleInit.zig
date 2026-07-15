const std = @import("std");
const ModuleManifest = @import("ModuleManifest.zig");
const NativeDependency = @import("NativeDependency.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const native_manifest =
    \\{
    \\  "native": {
    \\    "sources": {
    \\      "cpp": [
    \\        "Module.cpp"
    \\      ]
    \\    }
    \\  }
    \\}
    \\
;

const native_source =
    \\// Implement the native functions declared by this module's Silex sources here.
    \\
;

const Outcome = enum {
    created_manifest,
    manifest_exists,
    created_native_manifest,
    updated_native_manifest,
    native_exists,
};

const Result = struct {
    outcome: Outcome,
    native_source_created: bool = false,
};

const PathState = enum { missing, file, directory, other };

pub fn run(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: module init expects a directory path\n", .{});
        return 1;
    }
    if (args[0].len == 0 or std.mem.startsWith(u8, args[0], "-")) {
        std.debug.print("silex: module init expects a directory path before options\n", .{});
        return 1;
    }

    var native = false;
    if (args.len > 2) {
        std.debug.print("silex: module init accepts one directory path and only the '--native' option\n", .{});
        return 1;
    }
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--native")) {
            native = true;
        } else if (std.mem.startsWith(u8, args[1], "-")) {
            std.debug.print("silex: module init does not accept option '{s}'\n", .{args[1]});
            return 1;
        } else {
            std.debug.print("silex: module init accepts exactly one directory path\n", .{});
            return 1;
        }
    }

    const directory_path = args[0];
    const manifest_path = try std.fs.path.join(allocator, &.{ directory_path, "Module.json" });
    const source_path = try std.fs.path.join(allocator, &.{ directory_path, "Module.cpp" });
    const result = initialize(allocator, io, directory_path, native) catch |err| switch (err) {
        error.ModulePathCollision => {
            std.debug.print("silex: module path exists and is not a directory: {s}\n", .{directory_path});
            return 1;
        },
        error.ManifestPathCollision => {
            std.debug.print("silex: Module.json path exists and is not a file: {s}\n", .{manifest_path});
            return 1;
        },
        error.NativeSourcePathCollision => {
            std.debug.print("silex: Module.cpp path exists and is not a file: {s}\n", .{source_path});
            return 1;
        },
        error.InvalidModuleManifest => {
            std.debug.print("silex: invalid module manifest: {s}\n", .{manifest_path});
            return 1;
        },
        else => |other| return other,
    };

    switch (result.outcome) {
        .created_manifest => std.debug.print("Created module manifest: {s}\n", .{manifest_path}),
        .manifest_exists => std.debug.print("Module manifest already exists: {s}\n", .{manifest_path}),
        .created_native_manifest => std.debug.print("Created native module manifest: {s}\n", .{manifest_path}),
        .updated_native_manifest => std.debug.print("Updated module manifest with native configuration: {s}\n", .{manifest_path}),
        .native_exists => std.debug.print("Native module already initialized: {s}\n", .{manifest_path}),
    }
    if (result.outcome == .created_native_manifest or result.outcome == .updated_native_manifest) {
        if (result.native_source_created) {
            std.debug.print("Created native source: {s}\n", .{source_path});
        } else {
            std.debug.print("Kept existing native source: {s}\n", .{source_path});
        }
    }
    return 0;
}

fn initialize(allocator: Allocator, io: Io, directory_path: []const u8, native: bool) !Result {
    const directory_state = try pathState(io, directory_path);
    if (directory_state != .missing and directory_state != .directory) return error.ModulePathCollision;

    const manifest_path = try std.fs.path.join(allocator, &.{ directory_path, "Module.json" });
    const manifest_state = if (directory_state == .directory) try pathState(io, manifest_path) else .missing;
    if (manifest_state != .missing and manifest_state != .file) return error.ManifestPathCollision;

    const manifest = if (manifest_state == .file)
        ModuleManifest.load(allocator, io, manifest_path) catch return error.InvalidModuleManifest
    else
        null;
    if (manifest) |existing| {
        if (existing.native) |native_value| {
            NativeDependency.validateModuleNative(allocator, native_value) catch return error.InvalidModuleManifest;
            return .{ .outcome = if (native) .native_exists else .manifest_exists };
        }
        if (!native) return .{ .outcome = .manifest_exists };
    } else if (!native) {
        try Io.Dir.cwd().createDirPath(io, directory_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_path, .data = "{}\n" });
        return .{ .outcome = .created_manifest };
    }

    const source_path = try std.fs.path.join(allocator, &.{ directory_path, "Module.cpp" });
    const source_state = if (directory_state == .directory) try pathState(io, source_path) else .missing;
    if (source_state != .missing and source_state != .file) return error.NativeSourcePathCollision;

    const contents = if (manifest) |existing|
        try nativeManifestWithMetadata(allocator, existing)
    else
        native_manifest;
    try Io.Dir.cwd().createDirPath(io, directory_path);
    if (source_state == .missing) try Io.Dir.cwd().writeFile(io, .{ .sub_path = source_path, .data = native_source });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_path, .data = contents });
    return .{
        .outcome = if (manifest == null) .created_native_manifest else .updated_native_manifest,
        .native_source_created = source_state == .missing,
    };
}

fn nativeManifestWithMetadata(allocator: Allocator, manifest: ModuleManifest.Manifest) ![]const u8 {
    const GeneratedManifest = struct {
        author: ?[]const u8,
        description: ?[]const u8,
        name: ?[]const u8,
        version: ?[]const u8,
        dependencies: ?std.json.Value,
        native: struct {
            sources: struct {
                cpp: []const []const u8,
            },
        },
    };
    const value: GeneratedManifest = .{
        .author = manifest.author,
        .description = manifest.description,
        .name = manifest.name,
        .version = manifest.version,
        .dependencies = manifest.dependencies,
        .native = .{ .sources = .{ .cpp = &.{"Module.cpp"} } },
    };
    const json = try std.json.Stringify.valueAlloc(allocator, value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    return std.fmt.allocPrint(allocator, "{s}\n", .{json});
}

fn pathState(io: Io, path: []const u8) !PathState {
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return .missing,
        error.NotDir => return .other,
        else => |other| return other,
    };
    return switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        else => .other,
    };
}

test "plain initialization creates only an empty manifest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try testPath(allocator, temporary.sub_path, "Core");

    const result = try initialize(allocator, std.testing.io, directory, false);

    try std.testing.expectEqual(Outcome.created_manifest, result.outcome);
    const contents = try Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.json" }), allocator, .limited(1024));
    try std.testing.expectEqualStrings("{}\n", contents);
    try std.testing.expectEqual(PathState.missing, try pathState(std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.cpp" })));
}

test "native initialization creates the portable manifest and marker source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try testPath(allocator, temporary.sub_path, "Core");

    const result = try initialize(allocator, std.testing.io, directory, true);

    try std.testing.expectEqual(Outcome.created_native_manifest, result.outcome);
    try std.testing.expect(result.native_source_created);
    const manifest = try Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.json" }), allocator, .limited(1024));
    try std.testing.expectEqualStrings(native_manifest, manifest);
    const source = try Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.cpp" }), allocator, .limited(1024));
    try std.testing.expectEqualStrings(native_source, source);
}

test "plain initialization preserves an existing Silex module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "Core", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Core/Runtime.sx", .data = "pub func value() int { return 1 }\n" });
    const directory = try testPath(allocator, temporary.sub_path, "Core");

    _ = try initialize(allocator, std.testing.io, directory, false);

    const source = try temporary.dir.readFileAlloc(std.testing.io, "Core/Runtime.sx", allocator, .limited(1024));
    try std.testing.expectEqualStrings("pub func value() int { return 1 }\n", source);
}

test "native initialization preserves metadata and existing Module.cpp" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "Core", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Core/Module.json",
        .data = "{\"author\":\"Ada\",\"description\":\"Core utilities\",\"name\":\"Core\",\"version\":\"1.2.3\",\"dependencies\":{}}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Core/Module.cpp", .data = "existing\n" });
    const directory = try testPath(allocator, temporary.sub_path, "Core");

    const result = try initialize(allocator, std.testing.io, directory, true);

    try std.testing.expectEqual(Outcome.updated_native_manifest, result.outcome);
    try std.testing.expect(!result.native_source_created);
    const source = try temporary.dir.readFileAlloc(std.testing.io, "Core/Module.cpp", allocator, .limited(1024));
    try std.testing.expectEqualStrings("existing\n", source);
    const manifest = try ModuleManifest.load(allocator, std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.json" }));
    try std.testing.expectEqualStrings("Ada", manifest.author.?);
    try std.testing.expectEqualStrings("Core utilities", manifest.description.?);
    try std.testing.expectEqualStrings("Core", manifest.name.?);
    try std.testing.expectEqualStrings("1.2.3", manifest.version.?);
    try std.testing.expect(manifest.dependencies != null);
    try std.testing.expect(manifest.native != null);
}

test "existing native configuration is not changed and creates no source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "Core", .default_dir);
    const original = "{\"native\":{\"sources\":{\"c\":[\"Runtime.c\"]}}}\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Core/Module.json", .data = original });
    const directory = try testPath(allocator, temporary.sub_path, "Core");

    const result = try initialize(allocator, std.testing.io, directory, true);

    try std.testing.expectEqual(Outcome.native_exists, result.outcome);
    const contents = try temporary.dir.readFileAlloc(std.testing.io, "Core/Module.json", allocator, .limited(1024));
    try std.testing.expectEqualStrings(original, contents);
    try std.testing.expectEqual(PathState.missing, try pathState(std.testing.io, try std.fs.path.join(allocator, &.{ directory, "Module.cpp" })));
}

test "invalid manifest and native source collision write nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "Invalid", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Invalid/Module.json", .data = "not json\n" });
    const invalid_directory = try testPath(allocator, temporary.sub_path, "Invalid");
    try std.testing.expectError(error.InvalidModuleManifest, initialize(allocator, std.testing.io, invalid_directory, true));
    try std.testing.expectEqual(PathState.missing, try pathState(std.testing.io, try std.fs.path.join(allocator, &.{ invalid_directory, "Module.cpp" })));

    try temporary.dir.createDir(std.testing.io, "Collision", .default_dir);
    try temporary.dir.createDir(std.testing.io, "Collision/Module.cpp", .default_dir);
    const collision_directory = try testPath(allocator, temporary.sub_path, "Collision");
    try std.testing.expectError(error.NativeSourcePathCollision, initialize(allocator, std.testing.io, collision_directory, true));
    try std.testing.expectEqual(PathState.missing, try pathState(std.testing.io, try std.fs.path.join(allocator, &.{ collision_directory, "Module.json" })));

    try temporary.dir.createDir(std.testing.io, "ManifestCollision", .default_dir);
    try temporary.dir.createDir(std.testing.io, "ManifestCollision/Module.json", .default_dir);
    const manifest_collision_directory = try testPath(allocator, temporary.sub_path, "ManifestCollision");
    try std.testing.expectError(error.ManifestPathCollision, initialize(allocator, std.testing.io, manifest_collision_directory, false));
}

fn testPath(allocator: Allocator, temporary_sub_path: []const u8, name: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temporary_sub_path, name });
}
