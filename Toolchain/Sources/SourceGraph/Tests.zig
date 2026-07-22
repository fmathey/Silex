const std = @import("std");
const build_options = @import("build_options");
const ModuleDiscovery = @import("../ModuleDiscovery.zig");
const ModuleManifest = @import("../ModuleManifest.zig");
const ProjectModule = @import("../Project.zig");
const Implementation = @import("Implementation.zig");
const EnvironMap = Implementation.EnvironMap;
const ModuleBuilder = Implementation.ModuleBuilder;
const UnitSource = Implementation.UnitSource;
const NamespaceLocation = Implementation.NamespaceLocation;
const UnitTarget = Implementation.UnitTarget;
const Selection = Implementation.Selection;
const FileState = Implementation.FileState;
const NativeRuntime = Implementation.NativeRuntime;
const Provider = Implementation.Provider;
const canonicalPath = Implementation.canonicalPath;
const ModuleAlias = Implementation.ModuleAlias;
const Loaded = Implementation.Loaded;
const Overlay = Implementation.Overlay;
const Mode = Implementation.Mode;
const Loader = Implementation.Loader;
const findModule = Implementation.findModule;
const findUnit = Implementation.findUnit;
const graphDependencyConflictsWithModule = Implementation.graphDependencyConflictsWithModule;
const moduleNameFromUse = Implementation.moduleNameFromUse;
const canonicalUsePath = Implementation.canonicalUsePath;
const canonicalAliasedPath = Implementation.canonicalAliasedPath;
const pathHasQualifier = Implementation.pathHasQualifier;
const lastSegment = Implementation.lastSegment;
const parentModuleName = Implementation.parentModuleName;
const sameModuleParent = Implementation.sameModuleParent;
const firstSegment = Implementation.firstSegment;
const moduleBelongsToPackage = Implementation.moduleBelongsToPackage;
const packageModulePath = Implementation.packageModulePath;
const localModulePath = Implementation.localModulePath;
const namespaceLocation = Implementation.namespaceLocation;
const compactDescendantExists = Implementation.compactDescendantExists;
const namespaceExists = Implementation.namespaceExists;
const isFile = Implementation.isFile;
const isDirectory = Implementation.isDirectory;
const findNativeRuntime = Implementation.findNativeRuntime;
const findNativeRuntimeInPackage = Implementation.findNativeRuntimeInPackage;
const nativeModuleManifestPath = Implementation.nativeModuleManifestPath;
test "native runtime uses @Module.json and ignores metadata-only or incorrectly cased manifests" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "Library/Parent/Child");
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Parent/Child/module.json",
        .data = "{\"native\":{}}",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Parent/Child/@Module.json",
        .data = "{\"author\":\"Child author\"}",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Parent/@Module.json",
        .data = "{\"native\":{}}",
    });
    const library_root = try std.fs.path.join(allocator, &.{
        ".zig-cache",
        "tmp",
        &temporary.sub_path,
        "Library",
    });
    const runtime = (try findNativeRuntime(
        allocator,
        std.testing.io,
        library_root,
        "Parent.Child",
    )).?;
    const expected_directory = try std.fs.path.join(allocator, &.{ library_root, "Parent" });

    try std.testing.expectEqualStrings("Parent", runtime.module_name);
    try std.testing.expectEqualStrings(expected_directory, runtime.module_directory);
    try std.testing.expect(std.mem.endsWith(u8, runtime.manifest_path, "Parent/@Module.json"));

    try temporary.dir.createDir(std.testing.io, "Library/Metadata", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Metadata/@Module.json",
        .data = "{\"description\":\"No native runtime\"}",
    });
    try std.testing.expect(try findNativeRuntime(
        allocator,
        std.testing.io,
        library_root,
        "Metadata",
    ) == null);

    try temporary.dir.createDir(std.testing.io, "Library/Legacy", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Legacy/Native.json",
        .data = "{\"native\":{}}",
    });
    try std.testing.expect(try findNativeRuntime(
        allocator,
        std.testing.io,
        library_root,
        "Legacy",
    ) == null);

    try temporary.dir.createDir(std.testing.io, "Library/OldManifest", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/OldManifest/Module.json",
        .data = "{\"native\":{}}",
    });
    try std.testing.expectError(error.Reported, findNativeRuntime(
        allocator,
        std.testing.io,
        library_root,
        "OldManifest",
    ));
}

test "local module paths follow their logical segments" {
    if (!build_options.run_source_graph_tests) return;
    const path = try localModulePath(std.testing.allocator, "Sandbox", "Math.Geometry");
    defer std.testing.allocator.free(path);
    const expected = try std.fs.path.join(std.testing.allocator, &.{ "Sandbox", "Math", "Geometry" });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, path);
}

test "use paths select a declaration from their parent module" {
    if (!build_options.run_source_graph_tests) return;
    try std.testing.expectEqualStrings("Math.Geometry", moduleNameFromUse("Math.Geometry.Ray").?);
    try std.testing.expect(moduleNameFromUse("Vec3") == null);
}

test "use paths expand module aliases" {
    if (!build_options.run_source_graph_tests) return;
    const aliases = &[_]ModuleAlias{
        .{ .qualifier = "Standard", .module_name = "STD" },
        .{ .qualifier = "Time", .module_name = "STD.Time" },
    };

    const standard = try canonicalUsePath(std.testing.allocator, aliases, "Standard.Time");
    defer std.testing.allocator.free(standard);
    try std.testing.expectEqualStrings("STD.Time", standard);
    const expanded = try canonicalUsePath(std.testing.allocator, aliases, "Time.Stopwatch");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("STD.Time.Stopwatch", expanded);
}

test "qualified paths expand parent module aliases" {
    if (!build_options.run_source_graph_tests) return;
    const aliases = &[_]ModuleAlias{.{ .qualifier = "Standard", .module_name = "STD" }};

    const canonical = (try canonicalAliasedPath(
        std.testing.allocator,
        aliases,
        "Standard.Time.Stopwatch",
    )).?;
    defer std.testing.allocator.free(canonical);
    try std.testing.expectEqualStrings("STD.Time.Stopwatch", canonical);
    try std.testing.expect(try canonicalAliasedPath(std.testing.allocator, aliases, "stopwatch.start") == null);
}

test "nested and dotted files provide the same logical namespace and compact parents" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "Nested/STD/Console");
    try temporary.dir.createDirPath(std.testing.io, "Dotted/STD");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Nested/STD/Console/Session.sx", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Dotted/STD/Console.Session.sx", .data = "" });
    const temporary_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const nested_root = try std.fs.path.join(allocator, &.{ temporary_root, "Nested" });
    const dotted_root = try std.fs.path.join(allocator, &.{ temporary_root, "Dotted" });

    const nested = try namespaceLocation(allocator, std.testing.io, nested_root, null, "STD.Console.Session");
    const dotted = try namespaceLocation(allocator, std.testing.io, dotted_root, null, "STD.Console.Session");
    try std.testing.expectEqual(@as(usize, 1), nested.sources.len);
    try std.testing.expectEqual(@as(usize, 1), dotted.sources.len);
    try std.testing.expect(try namespaceExists(allocator, std.testing.io, dotted_root, null, "STD.Console"));

    try temporary.dir.createDir(std.testing.io, "Dotted/STD/Console", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Dotted/STD/Console/Session.sx", .data = "" });
    const collision = try namespaceLocation(allocator, std.testing.io, dotted_root, null, "STD.Console.Session");
    try std.testing.expectEqual(@as(usize, 2), collision.sources.len);
}

test "a file and directory can materialize the same namespace node" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "STD/Algorithms");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "STD/Algorithms.sx", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "STD/Algorithms/Sort.sx", .data = "" });
    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const parent = try namespaceLocation(allocator, std.testing.io, root, null, "STD.Algorithms");
    const child = try namespaceLocation(allocator, std.testing.io, root, null, "STD.Algorithms.Sort");
    try std.testing.expectEqual(@as(usize, 1), parent.sources.len);
    try std.testing.expect(parent.has_directory);
    try std.testing.expectEqual(@as(usize, 1), child.sources.len);
}

test "file namespace selection loads only its transitive sibling closure" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App.Main","modules":[
        \\  {"name":"Lib","sources":["Alpha.sx","Internal.sx","AlphaExtensions.sx","Broken.sx"]},
        \\  {"name":"App","sources":["Main.sx"]}
        \\]}
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Main.sx",
        .data = "use Lib.Alpha\nfunc main() { print(Alpha.value()) }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Alpha.sx",
        .data = "use Internal\nuse AlphaExtensions\npub struct Alpha { static func value() int { return Internal.helper() } }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Internal.sx",
        .data = "func helper() int { return 42 }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "AlphaExtensions.sx",
        .data = "use Alpha\nextend Alpha { public func doubled() int { return 84 } }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Broken.sx",
        .data = "public struct Broken {\n",
    });

    var environ = EnvironMap.init(allocator);
    const project_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path, "project.json" });
    var loader = Loader.init(allocator, std.testing.io, &environ);
    const loaded = try loader.load(project_path);

    try std.testing.expectEqual(@as(usize, 4), loaded.files.len);
    try std.testing.expectEqualStrings("Main", loaded.files[0].unit_name);
    try std.testing.expectEqualStrings("Alpha", loaded.files[1].unit_name);
    try std.testing.expectEqualStrings("Internal", loaded.files[2].unit_name);
    try std.testing.expectEqualStrings("AlphaExtensions", loaded.files[3].unit_name);
    try std.testing.expectEqualSlices(usize, &.{ 1, 3, 2 }, loaded.files[0].activated_files);
}

test "a differently named declaration is not searched in a neighboring file" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App.Main","modules":[
        \\  {"name":"Lib","sources":["API.sx","Neighbor.sx"]},
        \\  {"name":"App","sources":["Main.sx"]}
        \\]}
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Main.sx",
        .data = "use Lib.Renamed\nfunc main() { let value = Renamed() }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "API.sx",
        .data = "public struct Renamed {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Neighbor.sx",
        .data = "public struct Neighbor {}\n",
    });

    var environ = EnvironMap.init(allocator);
    const project_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path, "project.json" });
    var loader = Loader.init(allocator, std.testing.io, &environ);
    try std.testing.expectError(error.InvalidSource, loader.load(project_path));
    try std.testing.expect(std.mem.indexOf(u8, loader.diagnostic.?.message, "unknown use target 'Lib.Renamed'") != null);
}

test "a declaration in a neighboring file does not collide with a file namespace" {
    if (!build_options.run_source_graph_tests) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App.Main","modules":[
        \\  {"name":"Lib","sources":["Thing.sx","Other.sx"]},
        \\  {"name":"App","sources":["Main.sx"]}
        \\]}
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = "use Lib.Thing\nfunc main() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Thing.sx", .data = "func helper() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Other.sx", .data = "public struct Thing {}\n" });

    var environ = EnvironMap.init(allocator);
    const project_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path, "project.json" });
    var loader = Loader.init(allocator, std.testing.io, &environ);
    const loaded = try loader.load(project_path);
    try std.testing.expectEqual(@as(usize, 2), loaded.files.len);
    try std.testing.expectEqualStrings("Thing", loaded.files[1].unit_name);
}
