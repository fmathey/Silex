const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const CppGenerator = @import("CppGenerator.zig");
const Generics = @import("Generics.zig");
const Semantic = @import("Semantic.zig");
const TargetModule = @import("Target.zig");
const NativeDependency = @import("NativeDependency.zig");
const NativeObjectCache = @import("NativeObjectCache.zig");
const ModuleManifest = @import("ModuleManifest.zig");
const PackageGraph = @import("PackageGraph.zig");
const ProjectModule = @import("Project.zig");
const Modules = @import("Modules.zig");
const SourceGraph = @import("SourceGraph.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const cache_format = "v41";
pub const cache_entry_limit = 8;

const NativeConfiguration = enum {
    unoptimized,
    optimized,

    fn compilerFlags(self: NativeConfiguration) []const []const u8 {
        return switch (self) {
            .unoptimized => &.{},
            .optimized => &.{ "-O2", "-fno-finite-loops" },
        };
    }
};

const default_native_configuration: NativeConfiguration = .optimized;

pub const Compilation = struct {
    executable_path: []const u8,
    cpp_path: []const u8,
    artifact_root: []const u8,
    program_name: []const u8,
    cache_hit: bool,
    compiled_packages: []const []const u8,
    reused_packages: []const []const u8,
    target: TargetModule.Target,
};

pub fn compile(
    allocator: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    input_path: []const u8,
    target: TargetModule.Target,
    native_dependencies: []const NativeDependency.Dependency,
) !Compilation {
    var loader = SourceGraph.Loader.init(allocator, io, environ_map);
    const loaded = loader.load(input_path) catch |err| switch (err) {
        error.InvalidSource => return report(loader.source_paths.items, loader.diagnostic.?),
        else => |other| return other,
    };
    const project = loaded.project;
    const source_paths = loaded.source_paths;
    const source_contents = loaded.source_contents;
    const files = loaded.files;
    const module_runtimes = try loadModuleRuntimes(allocator, io, project, loaded.package_graph, target);
    const object_plan = try NativeObjectCache.makePlan(
        allocator,
        io,
        loaded.package_graph,
        module_runtimes,
        target,
        default_native_configuration.compilerFlags(),
    );
    const native_module_names = try nativeModuleNames(allocator, project);
    const canonical_source_paths = try canonicalizeSourcePaths(allocator, io, source_paths);
    var resolver = Modules.Resolver.init(allocator, project, files);
    const ast = resolver.resolve() catch |err| switch (err) {
        error.InvalidSource => return report(source_paths, resolver.diagnostic.?),
        else => |other| return other,
    };

    var specializer = Generics.Specializer.init(allocator, ast);
    const specialized_ast = specializer.specialize() catch |err| switch (err) {
        error.InvalidSource => return report(source_paths, specializer.diagnostic.?),
        else => |other| return other,
    };

    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = native_module_names;
    const program = analyzer.analyze(specialized_ast) catch |err| switch (err) {
        error.InvalidSource => return report(source_paths, analyzer.diagnostic.?),
        else => |other| return other,
    };

    const cpp = try CppGenerator.generateWithSources(allocator, program, canonical_source_paths);
    const artifact_root = "";
    const program_name = project.program_name;
    const target_name = try target.cacheName(allocator);
    if (target.cppBackendUnavailableReason()) |reason| {
        std.debug.print("silex: target '{s}' is unavailable: {s}\n", .{ target_name, reason });
        return error.Reported;
    }
    for (native_dependencies) |dependency| {
        if (!try dependency.supports(allocator, target)) {
            std.debug.print("silex: native dependency '{s}' does not support target '{s}'\n", .{
                dependency.name,
                target_name,
            });
            return error.Reported;
        }
    }
    const cache_key = try cacheKey(
        allocator,
        io,
        cpp,
        project,
        canonical_source_paths,
        source_contents,
        target,
        native_dependencies,
        object_plan,
        module_runtimes,
        default_native_configuration,
    );
    const legacy_cache_root = try std.fs.path.join(allocator, &.{ artifact_root, ".silex", "cache" });
    Io.Dir.cwd().deleteTree(io, legacy_cache_root) catch |err| {
        std.debug.print("silex: warning: unable to remove legacy project cache: {t}\n", .{err});
    };
    const cache_root = try std.fs.path.join(allocator, &.{ artifact_root, ".silex", "build" });
    const version_cache_dir = try std.fs.path.join(allocator, &.{ cache_root, cache_format });
    const target_cache_dir = try std.fs.path.join(allocator, &.{ version_cache_dir, target_name });
    try Io.Dir.cwd().createDirPath(io, target_cache_dir);
    cleanObsoleteCacheLayouts(allocator, io, cache_root) catch |err| {
        std.debug.print("silex: warning: unable to remove obsolete cache layouts: {t}\n", .{err});
    };

    const cache_dir = try std.fs.path.join(allocator, &.{ target_cache_dir, &cache_key });
    try Io.Dir.cwd().createDirPath(io, cache_dir);

    const cpp_path = try std.fs.path.join(allocator, &.{ cache_dir, "Generated.cpp" });
    const executable_path = try std.fs.path.join(allocator, &.{ cache_dir, program_name });
    const temporary_name = try std.fmt.allocPrint(allocator, "{s}.tmp", .{program_name});
    const temporary_executable_path = try std.fs.path.join(allocator, &.{ cache_dir, temporary_name });
    const backend_log_path = try std.fs.path.join(allocator, &.{ cache_dir, "Backend.log" });
    const cache_hit = try fileExists(io, executable_path) and !requiresFinalRelink(module_runtimes);
    const access_path = try std.fs.path.join(allocator, &.{ cache_dir, ".access" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = access_path, .data = "" });
    pruneTargetCache(allocator, io, target_cache_dir, &cache_key, cache_entry_limit) catch |err| {
        std.debug.print("silex: warning: unable to prune compilation cache: {t}\n", .{err});
    };

    var compiled_packages: []const []const u8 = &.{};
    var reused_packages: []const []const u8 = &.{};
    if (!cache_hit) {
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = cpp_path, .data = cpp });
        const zig_path = resolveZig(allocator, io) catch {
            std.debug.print(
                "silex: bundled Zig toolchain was not found; reinstall Silex or rebuild it for development\n",
                .{},
            );
            return error.Reported;
        };
        const local_runtime_objects = try compileLocalRuntimeObjects(
            allocator,
            io,
            zig_path,
            target,
            target_name,
            module_runtimes,
            cache_dir,
            backend_log_path,
        );
        const shared = NativeObjectCache.prepareShared(
            allocator,
            io,
            environ_map,
            zig_path,
            target,
            target_name,
            default_native_configuration.compilerFlags(),
            module_runtimes,
            object_plan,
            backend_log_path,
        ) catch |err| switch (err) {
            error.NativeObjectCompilationFailed => {
                reportNativeBackendFailure(target_name, backend_log_path);
                return error.Reported;
            },
            else => |other| return other,
        };
        compiled_packages = shared.compiled_packages;
        reused_packages = shared.reused_packages;
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(allocator, &.{ zig_path, "c++" });
        if (target.zig_triple) |triple| try arguments.appendSlice(allocator, &.{ "-target", triple });
        try arguments.appendSlice(allocator, default_native_configuration.compilerFlags());
        try arguments.appendSlice(allocator, &.{ "-std=c++23", "-Wno-nullability-completeness", cpp_path });
        for (native_dependencies) |dependency| try arguments.appendSlice(allocator, dependency.sources);
        try arguments.appendSlice(allocator, local_runtime_objects);
        try arguments.appendSlice(allocator, shared.objects);
        var linked_libraries: std.ArrayList([]const u8) = .empty;
        var linked_frameworks: std.ArrayList([]const u8) = .empty;
        var runtime_link_index = module_runtimes.len;
        while (runtime_link_index > 0) {
            runtime_link_index -= 1;
            const runtime = module_runtimes[runtime_link_index];
            for (runtime.system_libraries) |library| if (try appendUniqueName(allocator, &linked_libraries, library)) {
                try arguments.append(allocator, try std.fmt.allocPrint(allocator, "-l{s}", .{library}));
            };
            for (runtime.frameworks) |framework| if (try appendUniqueName(allocator, &linked_frameworks, framework)) {
                try arguments.appendSlice(allocator, &.{ "-framework", framework });
            };
        }
        try arguments.appendSlice(allocator, &.{ "-o", temporary_executable_path });

        const result = try std.process.run(allocator, io, .{
            .argv = arguments.items,
            .stdout_limit = .limited(16 * 1024 * 1024),
            .stderr_limit = .limited(16 * 1024 * 1024),
        });
        if (exitCode(result.term) != 0) {
            Io.Dir.cwd().deleteFile(io, temporary_executable_path) catch {};
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = backend_log_path, .data = result.stderr });
            reportMissingNativeFunction(program.functions, result.stderr);
            reportNativeBackendFailure(target_name, backend_log_path);
            return error.Reported;
        }
        if (result.stdout.len > 0) try Io.File.stdout().writeStreamingAll(io, result.stdout);
        if (result.stderr.len > 0) try Io.File.stderr().writeStreamingAll(io, result.stderr);
        try Io.Dir.cwd().rename(temporary_executable_path, .cwd(), executable_path, io);
    }
    Io.Dir.cwd().deleteFile(io, backend_log_path) catch {};

    return .{
        .executable_path = executable_path,
        .cpp_path = cpp_path,
        .artifact_root = artifact_root,
        .program_name = program_name,
        .cache_hit = cache_hit,
        .compiled_packages = compiled_packages,
        .reused_packages = reused_packages,
        .target = target,
    };
}

fn nativeModuleNames(allocator: Allocator, project: ProjectModule.Project) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (project.modules) |module| {
        if (module.module_manifest_path != null) try names.append(allocator, module.name);
    }
    return names.toOwnedSlice(allocator);
}

fn loadModuleRuntimes(
    allocator: Allocator,
    io: Io,
    project: ProjectModule.Project,
    package_graph: PackageGraph.Graph,
    target: TargetModule.Target,
) ![]const NativeDependency.ModuleRuntime {
    var loaded_runtimes: std.ArrayList(NativeDependency.ModuleRuntime) = .empty;
    for (package_graph.packages, 0..) |package, package_index| {
        const manifest_path = package.manifest_path orelse continue;
        const manifest = ModuleManifest.load(allocator, io, manifest_path) catch |err| {
            std.debug.print("silex: invalid module manifest at '{s}': {t}\n", .{ manifest_path, err });
            return error.Reported;
        };
        if (manifest.native == null) continue;
        const runtime_name = package.name orelse project.modules[project.target_module].name;
        try appendModuleRuntime(
            allocator,
            io,
            &loaded_runtimes,
            runtime_name,
            package.root,
            package.root,
            manifest_path,
            package_index,
            target,
        );
    }
    for (project.modules) |module| {
        const manifest_path = module.module_manifest_path orelse continue;
        try appendModuleRuntime(
            allocator,
            io,
            &loaded_runtimes,
            module.native_runtime_name orelse module.name,
            module.native_module_directory.?,
            package_graph.packages[module.package_index].root,
            manifest_path,
            module.package_index,
            target,
        );
    }

    try validateNativeProviders(package_graph, loaded_runtimes.items);
    try validatePackagePublicDefines(allocator, package_graph, loaded_runtimes.items);

    var package_order: std.ArrayList(usize) = .empty;
    const visited = try allocator.alloc(bool, package_graph.packages.len);
    @memset(visited, false);
    try appendPackageOrder(allocator, package_graph, 0, visited, &package_order);

    var runtimes: std.ArrayList(NativeDependency.ModuleRuntime) = .empty;
    for (package_order.items) |package_index| {
        for (loaded_runtimes.items) |runtime| {
            if (runtime.package_index != package_index) continue;
            try runtimes.append(allocator, try applyDirectNativeInterface(
                allocator,
                package_graph,
                loaded_runtimes.items,
                runtime,
            ));
        }
    }
    return runtimes.toOwnedSlice(allocator);
}

fn appendModuleRuntime(
    allocator: Allocator,
    io: Io,
    runtimes: *std.ArrayList(NativeDependency.ModuleRuntime),
    runtime_name: []const u8,
    module_directory: []const u8,
    package_root: []const u8,
    manifest_path: []const u8,
    package_index: usize,
    target: TargetModule.Target,
) !void {
    for (runtimes.items) |runtime| if (std.mem.eql(u8, runtime.manifest_path, manifest_path)) return;
    var diagnostic: ?NativeDependency.ModuleRuntimeDiagnostic = null;
    var runtime = NativeDependency.loadModuleRuntime(
        allocator,
        io,
        runtime_name,
        module_directory,
        package_root,
        manifest_path,
        target,
        &diagnostic,
    ) catch |err| switch (err) {
        error.DuplicateNativeSource => {
            const duplicate = diagnostic.?.duplicate_source;
            std.debug.print(
                "silex: native module '{s}' repeats source '{s}' in '{s}' and '{s}'\n",
                .{ runtime_name, duplicate.path, duplicate.first_level, duplicate.repeated_level },
            );
            return error.Reported;
        },
        else => {
            std.debug.print("silex: invalid module manifest for module '{s}' at '{s}': {t}\n", .{
                runtime_name,
                manifest_path,
                err,
            });
            return error.Reported;
        },
    };
    runtime.package_index = package_index;
    try runtimes.append(allocator, runtime);
}

const PublicDefineRequirement = struct {
    define: NativeDependency.Define,
    package_index: usize,
};

fn appendPackageOrder(
    allocator: Allocator,
    graph: PackageGraph.Graph,
    package_index: usize,
    visited: []bool,
    order: *std.ArrayList(usize),
) !void {
    if (visited[package_index]) return;
    visited[package_index] = true;
    for (graph.packages[package_index].dependencies) |dependency| {
        try appendPackageOrder(allocator, graph, dependency.package_index, visited, order);
    }
    try order.append(allocator, package_index);
}

fn validateNativeProviders(
    graph: PackageGraph.Graph,
    runtimes: []const NativeDependency.ModuleRuntime,
) !void {
    for (runtimes, 0..) |runtime, runtime_index| for (runtime.provides) |provided| {
        for (runtimes[0..runtime_index]) |existing| {
            if (existing.package_index == runtime.package_index) continue;
            for (existing.provides) |existing_provided| {
                if (!std.mem.eql(u8, existing_provided, provided)) continue;
                std.debug.print(
                    "silex: native identity '{s}' is provided by both {s} and {s}\n",
                    .{
                        provided,
                        graph.packages[existing.package_index].first_chain,
                        graph.packages[runtime.package_index].first_chain,
                    },
                );
                return error.Reported;
            }
        }
    };
}

fn validatePackagePublicDefines(
    allocator: Allocator,
    graph: PackageGraph.Graph,
    runtimes: []const NativeDependency.ModuleRuntime,
) !void {
    for (graph.packages) |package| {
        var requirements: std.ArrayList(PublicDefineRequirement) = .empty;
        for (package.dependencies) |dependency| {
            for (runtimes) |runtime| {
                if (runtime.package_index != dependency.package_index) continue;
                for (runtime.public_defines) |define| {
                    for (requirements.items) |existing| {
                        if (!std.mem.eql(u8, existing.define.name, define.name)) continue;
                        if (std.mem.eql(u8, existing.define.value, define.value)) break;
                        std.debug.print(
                            "silex: package {s} requires conflicting public define '{s}': '{s}' from {s} and '{s}' from {s}\n",
                            .{
                                package.first_chain,
                                define.name,
                                existing.define.value,
                                graph.packages[existing.package_index].first_chain,
                                define.value,
                                graph.packages[dependency.package_index].first_chain,
                            },
                        );
                        return error.Reported;
                    } else try requirements.append(allocator, .{
                        .define = define,
                        .package_index = dependency.package_index,
                    });
                }
            }
        }
    }
}

fn applyDirectNativeInterface(
    allocator: Allocator,
    graph: PackageGraph.Graph,
    runtimes: []const NativeDependency.ModuleRuntime,
    runtime: NativeDependency.ModuleRuntime,
) !NativeDependency.ModuleRuntime {
    var include_dirs: std.ArrayList([]const u8) = .empty;
    try include_dirs.appendSlice(allocator, runtime.include_dirs);
    var defines: std.ArrayList(NativeDependency.Define) = .empty;
    try defines.appendSlice(allocator, runtime.defines);

    for (graph.packages[runtime.package_index].dependencies) |dependency| {
        for (runtimes) |dependency_runtime| {
            if (dependency_runtime.package_index != dependency.package_index) continue;
            for (dependency_runtime.public_include_dirs) |include_dir| {
                _ = try appendUniqueName(allocator, &include_dirs, include_dir);
            }
            for (dependency_runtime.public_defines) |define| {
                for (defines.items) |existing| {
                    if (!std.mem.eql(u8, existing.name, define.name)) continue;
                    if (std.mem.eql(u8, existing.value, define.value)) break;
                    std.debug.print(
                        "silex: native module '{s}' defines '{s}={s}' but direct dependency {s} requires '{s}={s}'\n",
                        .{
                            runtime.module_name,
                            existing.name,
                            existing.value,
                            graph.packages[dependency.package_index].first_chain,
                            define.name,
                            define.value,
                        },
                    );
                    return error.Reported;
                } else try defines.append(allocator, define);
            }
        }
    }

    var composed = runtime;
    composed.include_dirs = try include_dirs.toOwnedSlice(allocator);
    composed.defines = try defines.toOwnedSlice(allocator);
    return composed;
}

fn appendUniqueName(
    allocator: Allocator,
    values: *std.ArrayList([]const u8),
    value: []const u8,
) !bool {
    for (values.items) |existing| if (std.mem.eql(u8, existing, value)) return false;
    try values.append(allocator, value);
    return true;
}

fn compileLocalRuntimeObjects(
    allocator: Allocator,
    io: Io,
    zig_path: []const u8,
    target: TargetModule.Target,
    target_name: []const u8,
    runtimes: []const NativeDependency.ModuleRuntime,
    cache_dir: []const u8,
    backend_log_path: []const u8,
) ![]const []const u8 {
    var objects: std.ArrayList([]const u8) = .empty;
    for (runtimes, 0..) |runtime, runtime_index| {
        if (runtime.package_index != 0) continue;
        for (runtime.sources, 0..) |source, source_index| {
            const object_name = try std.fmt.allocPrint(allocator, "native-{d}-{d}.o", .{ runtime_index, source_index });
            const object_path = try std.fs.path.join(allocator, &.{ cache_dir, object_name });
            var arguments: std.ArrayList([]const u8) = .empty;
            const driver = switch (source.kind) {
                .c, .objective_c => "cc",
                .cpp, .objective_cpp => "c++",
            };
            try arguments.appendSlice(allocator, &.{ zig_path, driver });
            if (target.zig_triple) |triple| try arguments.appendSlice(allocator, &.{ "-target", triple });
            try arguments.appendSlice(allocator, default_native_configuration.compilerFlags());
            if (source.kind == .cpp or source.kind == .objective_cpp) {
                try arguments.appendSlice(allocator, &.{ "-std=c++23", "-Wno-nullability-completeness" });
            }
            for (runtime.include_dirs) |include_dir| try arguments.append(allocator, try std.fmt.allocPrint(allocator, "-I{s}", .{include_dir}));
            for (runtime.defines) |define| try arguments.append(
                allocator,
                try std.fmt.allocPrint(allocator, "-D{s}={s}", .{ define.name, define.value }),
            );
            try arguments.appendSlice(allocator, &.{ "-c", source.path, "-o", object_path });

            const result = try std.process.run(allocator, io, .{
                .argv = arguments.items,
                .stdout_limit = .limited(16 * 1024 * 1024),
                .stderr_limit = .limited(16 * 1024 * 1024),
            });
            if (exitCode(result.term) != 0) {
                try Io.Dir.cwd().writeFile(io, .{ .sub_path = backend_log_path, .data = result.stderr });
                reportNativeBackendFailure(target_name, backend_log_path);
                return error.Reported;
            }
            if (result.stdout.len > 0) try Io.File.stdout().writeStreamingAll(io, result.stdout);
            if (result.stderr.len > 0) try Io.File.stderr().writeStreamingAll(io, result.stderr);
            try objects.append(allocator, object_path);
        }
    }
    return objects.toOwnedSlice(allocator);
}

fn reportNativeBackendFailure(target_name: []const u8, backend_log_path: []const u8) void {
    std.debug.print(
        "silex: native compilation failed for target '{s}'; target support, SDKs, or native sources may be unavailable or incomplete\n",
        .{target_name},
    );
    std.debug.print("silex: backend details: {s}\n", .{backend_log_path});
}

fn reportMissingNativeFunction(functions: []const Semantic.Function, backend_output: []const u8) void {
    for (functions) |function| {
        if (!function.is_native or std.mem.indexOf(u8, backend_output, function.generated_name) == null) continue;
        std.debug.print(
            "silex: native function '{s}.{s}' requires C symbol '{s}'\n",
            .{ function.native_module_name.?, function.native_function_name.?, function.generated_name },
        );
    }
}

fn requiresFinalRelink(runtimes: []const NativeDependency.ModuleRuntime) bool {
    for (runtimes) |runtime| {
        if (runtime.system_libraries.len > 0 or runtime.frameworks.len > 0) return true;
    }
    return false;
}

pub fn runProcess(io: Io, arguments: []const []const u8) !std.process.Child.Term {
    var child = try std.process.spawn(io, .{
        .argv = arguments,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    defer child.kill(io);
    return child.wait(io);
}

pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

pub fn defaultOutputPath(
    allocator: Allocator,
    artifact_root: []const u8,
    program_name: []const u8,
) ![]const u8 {
    return std.fs.path.join(allocator, &.{ artifact_root, ".silex", "bin", program_name });
}

pub fn cleanArtifacts(allocator: Allocator, io: Io, artifact_root: []const u8) !bool {
    const cache_path = try std.fs.path.join(allocator, &.{ artifact_root, ".silex" });
    _ = Io.Dir.cwd().statFile(io, cache_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    try Io.Dir.cwd().deleteTree(io, cache_path);
    return true;
}

pub fn copyArtifact(io: Io, source_path: []const u8, destination_path: []const u8) !void {
    if (std.fs.path.dirname(destination_path)) |directory| {
        if (directory.len > 0) try Io.Dir.cwd().createDirPath(io, directory);
    }
    try Io.Dir.copyFile(.cwd(), source_path, .cwd(), destination_path, io, .{ .make_path = true });
}

fn report(source_paths: []const []const u8, diagnostic: @import("Source.zig").Diagnostic) error{Reported} {
    const source_path = if (diagnostic.position.file < source_paths.len) source_paths[diagnostic.position.file] else source_paths[0];
    std.debug.print("{s}:{d}:{d}: error: {s}\n", .{
        source_path,
        diagnostic.position.line,
        diagnostic.position.column,
        diagnostic.message,
    });
    return error.Reported;
}

fn cacheKey(
    allocator: Allocator,
    io: Io,
    cpp: []const u8,
    project: ProjectModule.Project,
    source_paths: []const []const u8,
    source_contents: []const []const u8,
    target: TargetModule.Target,
    native_dependencies: []const NativeDependency.Dependency,
    object_plan: NativeObjectCache.Plan,
    module_runtimes: []const NativeDependency.ModuleRuntime,
    native_configuration: NativeConfiguration,
) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("silex-cache-");
    hasher.update(cache_format);
    hasher.update("\x00");
    hasher.update(builtin.zig_version_string);
    hasher.update("\x00");
    hasher.update(@tagName(native_configuration));
    hasher.update("\x00");
    hasher.update(@tagName(target.cpu_arch));
    hasher.update("\x00");
    hasher.update(@tagName(target.os_tag));
    hasher.update("\x00");
    hasher.update(@tagName(target.abi));
    if (target.zig_triple) |triple| {
        hasher.update("\x00");
        hasher.update(triple);
    }
    hasher.update("\x00");
    hasher.update(cpp);
    for (project.modules) |module| {
        hasher.update("\x00module\x00");
        hasher.update(module.name);
    }
    for (source_paths, source_contents) |source_path, source| {
        hasher.update("\x00source\x00");
        hasher.update(source_path);
        hasher.update("\x00");
        hasher.update(source);
    }
    for (native_dependencies) |dependency| {
        hasher.update("\x00");
        hasher.update(dependency.name);
        for (dependency.sources) |source_path| {
            const source = try Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(16 * 1024 * 1024));
            hasher.update("\x00");
            hasher.update(source_path);
            hasher.update("\x00");
            hasher.update(source);
        }
    }
    for (object_plan.entries) |entry| {
        hasher.update("\x00native-object-set\x00");
        hasher.update(&entry.key);
    }
    for (module_runtimes) |runtime| {
        for (runtime.system_libraries) |library| {
            hasher.update("\x00system-library\x00");
            hasher.update(library);
        }
        for (runtime.frameworks) |framework| {
            hasher.update("\x00framework\x00");
            hasher.update(framework);
        }
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn canonicalizeSourcePaths(allocator: Allocator, io: Io, source_paths: []const []const u8) ![]const []const u8 {
    const canonical = try allocator.alloc([]const u8, source_paths.len);
    for (source_paths, 0..) |source_path, index| {
        canonical[index] = try Io.Dir.cwd().realPathFileAlloc(io, source_path, allocator);
    }
    return canonical;
}

fn cleanObsoleteCacheLayouts(allocator: Allocator, io: Io, cache_root: []const u8) !void {
    var directory = try Io.Dir.cwd().openDir(io, cache_root, .{ .iterate = true });
    defer directory.close(io);

    try cleanObsoleteCacheLayoutsInDir(allocator, io, directory);
}

fn cleanObsoleteCacheLayoutsInDir(allocator: Allocator, io: Io, directory: Io.Dir) !void {
    var obsolete_names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, cache_format)) continue;
        try obsolete_names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    for (obsolete_names.items) |name| try directory.deleteTree(io, name);
}

const CacheEntry = struct {
    name: []const u8,
    modified: i96,
};

fn pruneTargetCache(
    allocator: Allocator,
    io: Io,
    target_cache_dir: []const u8,
    active_key: []const u8,
    maximum_entries: usize,
) !void {
    var directory = try Io.Dir.cwd().openDir(io, target_cache_dir, .{ .iterate = true });
    defer directory.close(io);

    try pruneTargetCacheInDir(allocator, io, directory, active_key, maximum_entries);
}

fn pruneTargetCacheInDir(
    allocator: Allocator,
    io: Io,
    directory: Io.Dir,
    active_key: []const u8,
    maximum_entries: usize,
) !void {
    var entries: std.ArrayList(CacheEntry) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        if (!isCacheKeyName(entry.name)) continue;
        const stat = try directory.statFile(io, entry.name, .{});
        if (stat.kind != .directory) continue;
        const access_path = try std.fs.path.join(allocator, &.{ entry.name, ".access" });
        const modified = directory.statFile(io, access_path, .{}) catch |err| switch (err) {
            error.FileNotFound => stat,
            else => |other| return other,
        };
        try entries.append(allocator, .{
            .name = try allocator.dupe(u8, entry.name),
            .modified = modified.mtime.nanoseconds,
        });
    }
    if (entries.items.len <= maximum_entries) return;

    std.mem.sort(CacheEntry, entries.items, {}, struct {
        fn lessThan(_: void, left: CacheEntry, right: CacheEntry) bool {
            if (left.modified != right.modified) return left.modified < right.modified;
            return std.mem.lessThan(u8, left.name, right.name);
        }
    }.lessThan);

    var remaining = entries.items.len;
    for (entries.items) |entry| {
        if (remaining <= maximum_entries) break;
        if (std.mem.eql(u8, entry.name, active_key)) continue;
        try directory.deleteTree(io, entry.name);
        remaining -= 1;
    }
}

fn isCacheKeyName(name: []const u8) bool {
    if (name.len != std.crypto.hash.sha2.Sha256.digest_length * 2) return false;
    for (name) |character| {
        if (!std.ascii.isDigit(character) and !(character >= 'a' and character <= 'f')) return false;
    }
    return true;
}

fn resolveZig(allocator: Allocator, io: Io) ![]const u8 {
    const executable_dir = try std.process.executableDirPathAlloc(io, allocator);
    const zig_name = if (builtin.os.tag == .windows) "zig.exe" else "zig";
    const bundled_path = try std.fs.path.resolve(allocator, &.{
        executable_dir,
        "..",
        "toolchain",
        "zig",
        zig_name,
    });
    if (try fileExists(io, bundled_path)) return bundled_path;

    if (build_options.developer_zig.len > 0 and try fileExists(io, build_options.developer_zig)) {
        return build_options.developer_zig;
    }
    return error.ZigToolchainNotFound;
}

fn fileExists(io: Io, path: []const u8) !bool {
    Io.Dir.cwd().access(io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    return true;
}

test "cache key follows generated content" {
    const target = TargetModule.Target.native();
    const project = testProject();
    const plan: NativeObjectCache.Plan = .{ .entries = &.{} };
    const first = try cacheKey(std.testing.allocator, std.testing.io, "first", project, &.{"Test.sx"}, &.{"source"}, target, &.{}, plan, &.{}, .optimized);
    const repeated = try cacheKey(std.testing.allocator, std.testing.io, "first", project, &.{"Test.sx"}, &.{"source"}, target, &.{}, plan, &.{}, .optimized);
    const changed = try cacheKey(std.testing.allocator, std.testing.io, "second", project, &.{"Test.sx"}, &.{"source"}, target, &.{}, plan, &.{}, .optimized);
    const changed_source = try cacheKey(std.testing.allocator, std.testing.io, "first", project, &.{"Test.sx"}, &.{"changed source"}, target, &.{}, plan, &.{}, .optimized);
    try std.testing.expectEqualSlices(u8, &first, &repeated);
    try std.testing.expect(!std.mem.eql(u8, &first, &changed));
    try std.testing.expect(!std.mem.eql(u8, &first, &changed_source));
}

test "cache key separates native configurations" {
    const target = TargetModule.Target.native();
    const project = testProject();
    const plan: NativeObjectCache.Plan = .{ .entries = &.{} };
    const optimized = try cacheKey(std.testing.allocator, std.testing.io, "program", project, &.{"Test.sx"}, &.{"source"}, target, &.{}, plan, &.{}, .optimized);
    const unoptimized = try cacheKey(std.testing.allocator, std.testing.io, "program", project, &.{"Test.sx"}, &.{"source"}, target, &.{}, plan, &.{}, .unoptimized);
    try std.testing.expect(!std.mem.eql(u8, &optimized, &unoptimized));
}

test "native system linkage always reruns the final link" {
    const runtime = NativeDependency.ModuleRuntime{
        .module_name = "Example",
        .module_directory = "Example",
        .manifest_path = "Example/Module.json",
        .sources = &.{},
        .include_dirs = &.{},
        .defines = &.{},
        .system_libraries = &.{"m"},
        .frameworks = &.{},
    };
    try std.testing.expect(requiresFinalRelink(&.{runtime}));
    try std.testing.expect(!requiresFinalRelink(&.{}));
}

test "cache pruning keeps the active entry and a bounded history" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    for ("012345678") |character| {
        var name: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
        @memset(&name, character);
        try temporary.dir.createDir(std.testing.io, &name, .default_dir);
    }
    const active_key = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    try temporary.dir.createDir(std.testing.io, active_key, .default_dir);
    try temporary.dir.createDir(std.testing.io, "notes", .default_dir);

    try pruneTargetCacheInDir(std.testing.allocator, std.testing.io, temporary.dir, active_key, 3);

    var cache_entry_count: usize = 0;
    var active_found = false;
    var notes_found = false;
    var iterator = temporary.dir.iterateAssumeFirstIteration();
    while (try iterator.next(std.testing.io)) |entry| {
        if (isCacheKeyName(entry.name)) cache_entry_count += 1;
        if (std.mem.eql(u8, entry.name, active_key)) active_found = true;
        if (std.mem.eql(u8, entry.name, "notes")) notes_found = true;
    }
    try std.testing.expectEqual(@as(usize, 3), cache_entry_count);
    try std.testing.expect(active_found);
    try std.testing.expect(notes_found);
}

test "cache migration removes obsolete layouts only" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, cache_format, .default_dir);
    try temporary.dir.createDir(std.testing.io, "v11", .default_dir);
    try temporary.dir.createDir(std.testing.io, "aarch64-macos-none", .default_dir);

    try cleanObsoleteCacheLayoutsInDir(std.testing.allocator, std.testing.io, temporary.dir);

    _ = try temporary.dir.statFile(std.testing.io, cache_format, .{});
    try std.testing.expectError(error.FileNotFound, temporary.dir.statFile(std.testing.io, "v11", .{}));
    try std.testing.expectError(error.FileNotFound, temporary.dir.statFile(std.testing.io, "aarch64-macos-none", .{}));
}

test "clean removes all Silex artifacts" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, ".silex/build/v15");
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = ".silex/build/v15/probe",
        .data = "cached",
    });
    const artifact_root = try std.fs.path.join(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &temporary.sub_path,
    });
    defer std.testing.allocator.free(artifact_root);

    try std.testing.expect(try cleanArtifacts(std.testing.allocator, std.testing.io, artifact_root));
    try std.testing.expect(!(try cleanArtifacts(std.testing.allocator, std.testing.io, artifact_root)));
}

fn testProject() ProjectModule.Project {
    return .{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = true,
    };
}

test "default native configuration preserves non-termination while optimizing" {
    const flags = default_native_configuration.compilerFlags();
    try std.testing.expectEqual(@as(usize, 2), flags.len);
    try std.testing.expectEqualStrings("-O2", flags[0]);
    try std.testing.expectEqualStrings("-fno-finite-loops", flags[1]);
}

test "default output belongs to current project" {
    const output = try defaultOutputPath(std.testing.allocator, "", "Main");
    defer std.testing.allocator.free(output);
    const expected = try std.fmt.allocPrint(std.testing.allocator, ".silex{c}bin{c}Main", .{
        std.fs.path.sep,
        std.fs.path.sep,
    });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, output);
}
