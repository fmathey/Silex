const std = @import("std");
const Ast = @import("Ast.zig");
const LexerModule = @import("Lexer.zig");
const ModuleManifest = @import("ModuleManifest.zig");
const Modules = @import("Modules.zig");
const PackageGraph = @import("PackageGraph.zig");
const ParserModule = @import("Parser.zig");
const ProjectModule = @import("Project.zig");
const Source = @import("Source.zig");
const StandardLibrary = @import("StandardLibrary.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnvironMap = std.process.Environ.Map;

const ModuleBuilder = struct {
    name: []const u8,
    sources: std.ArrayList([]const u8) = .empty,
    provider: Provider,
    native_runtime_name: ?[]const u8 = null,
    module_manifest_path: ?[]const u8 = null,
    native_module_directory: ?[]const u8 = null,
    package_index: usize = 0,
};

const NativeRuntime = struct {
    module_name: []const u8,
    module_directory: []const u8,
    manifest_path: []const u8,
};

const Provider = enum { application, local, package, distributed };

const ModuleAlias = struct {
    qualifier: []const u8,
    module_name: []const u8,
};

pub const Loaded = struct {
    project: ProjectModule.Project,
    package_graph: PackageGraph.Graph,
    source_paths: []const []const u8,
    source_contents: []const []const u8,
    files: []const Modules.File,
};

pub const Loader = struct {
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    source_paths: std.ArrayList([]const u8) = .empty,
    source_contents: std.ArrayList([]const u8) = .empty,
    files: std.ArrayList(Modules.File) = .empty,
    diagnostic: ?Source.Diagnostic = null,
    package_graph: ?PackageGraph.Graph = null,

    pub fn init(allocator: Allocator, io: Io, environ_map: *const EnvironMap) Loader {
        return .{ .allocator = allocator, .io = io, .environ_map = environ_map };
    }

    pub fn load(self: *Loader, input_path: []const u8) !Loaded {
        var project = try ProjectModule.load(self.allocator, self.io, input_path);
        const project_root = std.fs.path.dirname(input_path) orelse ".";
        self.package_graph = try PackageGraph.resolve(self.allocator, self.io, self.environ_map, project_root, .normal);
        const loads_local_modules = project.single_file;
        var modules: std.ArrayList(ModuleBuilder) = .empty;
        for (project.modules) |module| {
            var sources: std.ArrayList([]const u8) = .empty;
            try sources.appendSlice(self.allocator, module.sources);
            const root_package_name = self.package_graph.?.packages[0].name;
            const native_runtime = if (root_package_name) |package_name|
                if (moduleBelongsToPackage(module.name, package_name))
                    try findNativeRuntimeInPackage(
                        self.allocator,
                        self.io,
                        self.package_graph.?.packages[0].root,
                        package_name,
                        module.name,
                    )
                else if (loads_local_modules)
                    null
                else
                    try findNativeRuntime(self.allocator, self.io, project_root, module.name)
            else if (loads_local_modules)
                null
            else
                try findNativeRuntime(self.allocator, self.io, project_root, module.name);
            try modules.append(self.allocator, .{
                .name = module.name,
                .sources = sources,
                .provider = .application,
                .package_index = 0,
                .native_runtime_name = if (native_runtime) |runtime| runtime.module_name else null,
                .module_manifest_path = if (native_runtime) |runtime| runtime.manifest_path else null,
                .native_module_directory = if (native_runtime) |runtime| runtime.module_directory else null,
            });
        }
        for (project.modules, 0..) |module, module_index| for (module.sources) |source_path| {
            try self.appendFile(source_path, module_index);
        };

        var file_index: usize = 0;
        while (file_index < self.files.items.len) : (file_index += 1) {
            const file = self.files.items[file_index];
            const package_index = modules.items[file.module_index].package_index;
            for (file.program.imports) |import_value| {
                if (StandardLibrary.isReservedModule(import_value.path)) {
                    try self.loadDistributedModule(&modules, import_value.path, import_value.position);
                } else if (self.package_graph.?.explicit) {
                    try self.loadExplicitModule(&modules, project_root, import_value.path, import_value.position, package_index);
                } else if (loads_local_modules) {
                    try self.loadLocalOrDistributedModule(&modules, project_root, import_value.path, import_value.position);
                } else {
                    try self.loadDistributedModule(&modules, import_value.path, import_value.position);
                }
            }
            var module_aliases: std.ArrayList(ModuleAlias) = .empty;
            for (file.program.uses) |use_value| {
                const canonical_path = try canonicalUsePath(
                    self.allocator,
                    file.program.imports,
                    module_aliases.items,
                    use_value.path,
                );
                if (try self.loadUseDependency(
                    &modules,
                    project_root,
                    canonical_path,
                    use_value.position,
                    loads_local_modules,
                    package_index,
                )) |module_name| {
                    try module_aliases.append(self.allocator, .{
                        .qualifier = use_value.alias orelse lastSegment(use_value.path),
                        .module_name = module_name,
                    });
                }
            }
            try self.loadQualifiedDependencies(
                &modules,
                project_root,
                file_index,
                loads_local_modules,
                package_index,
            );
        }

        var project_modules: std.ArrayList(ProjectModule.Module) = .empty;
        for (modules.items) |*module| try project_modules.append(self.allocator, .{
            .name = module.name,
            .sources = try module.sources.toOwnedSlice(self.allocator),
            .package_index = module.package_index,
            .native_runtime_name = module.native_runtime_name,
            .module_manifest_path = module.module_manifest_path,
            .native_module_directory = module.native_module_directory,
        });
        project.modules = try project_modules.toOwnedSlice(self.allocator);
        project.single_file = loads_local_modules and self.files.items.len == 1;
        return self.finish(project);
    }

    fn loadUseDependency(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        canonical_path: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
    ) !?[]const u8 {
        if (try self.moduleExists(modules.items, project_root, canonical_path, loads_local_modules, package_index)) {
            try self.loadNamedModule(modules, project_root, canonical_path, position, loads_local_modules, package_index);
            return canonical_path;
        }
        const module_name = moduleNameFromUse(canonical_path) orelse return null;
        try self.loadNamedModule(modules, project_root, module_name, position, loads_local_modules, package_index);
        return null;
    }

    fn loadQualifiedDependencies(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        file_index: usize,
        loads_local_modules: bool,
        package_index: usize,
    ) !void {
        const file = self.files.items[file_index];
        var lexer = LexerModule.Lexer.initFile(self.source_contents.items[file_index], file_index);
        var tokens: std.ArrayList(LexerModule.Token) = .empty;
        while (true) {
            const token = try lexer.next();
            if (token.tag == .end) break;
            try tokens.append(self.allocator, token);
        }

        var index: usize = 0;
        while (index + 2 < tokens.items.len) {
            if (tokens.items[index].tag != .identifier or
                tokens.items[index + 1].tag != .dot or
                tokens.items[index + 2].tag != .identifier)
            {
                index += 1;
                continue;
            }

            var path: std.ArrayList(u8) = .empty;
            try path.appendSlice(self.allocator, tokens.items[index].lexeme);
            var end = index;
            while (end + 2 < tokens.items.len and
                tokens.items[end + 1].tag == .dot and
                tokens.items[end + 2].tag == .identifier)
            {
                try path.append(self.allocator, '.');
                try path.appendSlice(self.allocator, tokens.items[end + 2].lexeme);
                end += 2;
            }

            if (try canonicalImportedPath(self.allocator, file.program.imports, path.items)) |canonical| {
                try self.loadLongestQualifiedModule(
                    modules,
                    project_root,
                    canonical,
                    tokens.items[index].position,
                    loads_local_modules,
                    package_index,
                );
            }
            index = end + 1;
        }
    }

    fn loadLongestQualifiedModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        canonical_path: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
    ) !void {
        var candidate = canonical_path;
        while (true) {
            if (try self.moduleExists(modules.items, project_root, candidate, loads_local_modules, package_index)) {
                try self.loadNamedModule(modules, project_root, candidate, position, loads_local_modules, package_index);
                return;
            }
            const separator = std.mem.lastIndexOfScalar(u8, candidate, '.') orelse return;
            candidate = candidate[0..separator];
        }
    }

    fn moduleExists(
        self: *Loader,
        modules: []const ModuleBuilder,
        project_root: []const u8,
        module_name: []const u8,
        loads_local_modules: bool,
        package_index: usize,
    ) !bool {
        if (findModule(modules, module_name)) |module_index| {
            return self.moduleAccessible(modules[module_index], package_index);
        }
        if (StandardLibrary.isReservedModule(module_name)) {
            const library_root = StandardLibrary.root(self.allocator, self.io) catch return false;
            return isDirectory(self.io, try localModulePath(self.allocator, library_root, module_name));
        }
        if (self.package_graph.?.explicit) return self.explicitModuleExists(project_root, module_name, package_index);
        if (loads_local_modules and
            try isDirectory(self.io, try localModulePath(self.allocator, project_root, module_name)))
        {
            return true;
        }
        const library_root = StandardLibrary.root(self.allocator, self.io) catch return false;
        return isDirectory(self.io, try localModulePath(self.allocator, library_root, module_name));
    }

    fn loadNamedModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_name: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
    ) !void {
        if (StandardLibrary.isReservedModule(module_name)) {
            return self.loadDistributedModule(modules, module_name, position);
        }
        if (self.package_graph.?.explicit) {
            return self.loadExplicitModule(modules, project_root, module_name, position, package_index);
        }
        if (loads_local_modules) {
            return self.loadLocalOrDistributedModule(modules, project_root, module_name, position);
        }
        return self.loadDistributedModule(modules, module_name, position);
    }

    fn loadLocalOrDistributedModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_name: []const u8,
        position: Source.Position,
    ) !void {
        const local_path = try localModulePath(self.allocator, project_root, module_name);
        const has_local = try isDirectory(self.io, local_path);
        const library_root = StandardLibrary.root(self.allocator, self.io) catch |err| {
            if (has_local) return self.loadModule(modules, project_root, null, module_name, position, .local, 0);
            return err;
        };
        const distributed_path = try localModulePath(self.allocator, library_root, module_name);
        const has_distributed = try isDirectory(self.io, distributed_path);
        if (has_local and has_distributed) return self.multipleProviders(position, module_name);
        if (findModule(modules.items, module_name) != null and !has_distributed) return;
        if (has_local) return self.loadModule(modules, project_root, null, module_name, position, .local, 0);
        if (has_distributed) return self.loadModule(modules, library_root, null, module_name, position, .distributed, 0);
        const message = try std.fmt.allocPrint(
            self.allocator,
            "local module '{s}' was not found at '{s}'",
            .{ module_name, local_path },
        );
        return self.fail(position, message);
    }

    fn loadDistributedModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        module_name: []const u8,
        position: Source.Position,
    ) !void {
        const library_root = StandardLibrary.root(self.allocator, self.io) catch {
            if (findModule(modules.items, module_name) != null) return;
            const message = try std.fmt.allocPrint(
                self.allocator,
                "distributed library required by module '{s}' was not found; reinstall Silex",
                .{module_name},
            );
            return self.fail(position, message);
        };
        const directory_path = try localModulePath(self.allocator, library_root, module_name);
        if (!try isDirectory(self.io, directory_path)) {
            if (findModule(modules.items, module_name) != null) return;
            const message = try std.fmt.allocPrint(self.allocator, "module '{s}' was not found", .{module_name});
            return self.fail(position, message);
        }
        try self.loadModule(modules, library_root, null, module_name, position, .distributed, 0);
    }

    fn moduleAccessible(self: *Loader, module: ModuleBuilder, package_index: usize) bool {
        const graph = self.package_graph.?;
        if (!graph.explicit) return true;
        if (module.provider == .distributed and StandardLibrary.isReservedModule(module.name)) return true;
        if (module.package_index == package_index) return true;
        const root_name = firstSegment(module.name);
        return graph.directDependency(package_index, root_name) == module.package_index;
    }

    fn explicitModuleExists(
        self: *Loader,
        project_root: []const u8,
        module_name: []const u8,
        package_index: usize,
    ) !bool {
        const graph = self.package_graph.?;
        const package = graph.packages[package_index];
        if (package.name) |name| {
            if (moduleBelongsToPackage(module_name, name)) {
                return isDirectory(self.io, try packageModulePath(self.allocator, package.root, name, module_name));
            }
        }
        if (graph.directDependency(package_index, firstSegment(module_name))) |dependency_index| {
            const dependency = graph.packages[dependency_index];
            return isDirectory(self.io, try packageModulePath(self.allocator, dependency.root, dependency.name.?, module_name));
        }
        if (package_index == 0) {
            return isDirectory(self.io, try localModulePath(self.allocator, project_root, module_name));
        }
        return false;
    }

    fn loadExplicitModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_name: []const u8,
        position: Source.Position,
        package_index: usize,
    ) !void {
        if (StandardLibrary.isReservedModule(module_name)) {
            return self.loadDistributedModule(modules, module_name, position);
        }
        if (findModule(modules.items, module_name)) |existing_index| {
            if (self.moduleAccessible(modules.items[existing_index], package_index)) {
                if (graphDependencyConflictsWithModule(
                    self.package_graph.?,
                    package_index,
                    modules.items[existing_index],
                )) return self.multipleProviders(position, module_name);
                return;
            }
            return self.transitiveVisibilityError(position, package_index, firstSegment(module_name));
        }

        const graph = self.package_graph.?;
        const package = graph.packages[package_index];
        if (package.name) |name| {
            if (moduleBelongsToPackage(module_name, name)) {
                const path = try packageModulePath(self.allocator, package.root, name, module_name);
                if (!try isDirectory(self.io, path)) return self.moduleNotFound(position, module_name, path, null);
                return self.loadModule(modules, package.root, name, module_name, position, .package, package_index);
            }
        }

        const dependency_index = graph.directDependency(package_index, firstSegment(module_name));
        const local_path = if (package_index == 0)
            try localModulePath(self.allocator, project_root, module_name)
        else
            null;
        const has_local = if (local_path) |path| try isDirectory(self.io, path) else false;
        if (dependency_index) |index| {
            const dependency = graph.packages[index];
            const dependency_path = try packageModulePath(self.allocator, dependency.root, dependency.name.?, module_name);
            const has_dependency = try isDirectory(self.io, dependency_path);
            if (has_local and has_dependency) return self.multipleProviders(position, module_name);
            if (!has_dependency) return self.moduleNotFound(position, module_name, dependency_path, null);
            return self.loadModule(modules, dependency.root, dependency.name.?, module_name, position, .package, index);
        }
        if (has_local) return self.loadModule(modules, project_root, null, module_name, position, .local, 0);
        if (graph.findPackage(firstSegment(module_name)) != null) {
            return self.transitiveVisibilityError(position, package_index, firstSegment(module_name));
        }
        const missing_path = local_path orelse try localModulePath(self.allocator, package.root, module_name);
        return self.moduleNotFound(position, module_name, missing_path, null);
    }

    fn transitiveVisibilityError(
        self: *Loader,
        position: Source.Position,
        package_index: usize,
        dependency_name: []const u8,
    ) !void {
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "package '{s}' cannot import transitive package '{s}' without declaring it directly",
            .{ self.package_graph.?.packageLabel(package_index), dependency_name },
        ));
    }

    fn loadModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        module_root: []const u8,
        package_name: ?[]const u8,
        module_name: []const u8,
        position: Source.Position,
        provider: Provider,
        package_index: usize,
    ) !void {
        if (findModule(modules.items, module_name)) |existing_index| {
            if (modules.items[existing_index].provider != provider or
                modules.items[existing_index].package_index != package_index)
            {
                return self.multipleProviders(position, module_name);
            }
            return;
        }

        const directory_path = if (package_name) |name|
            try packageModulePath(self.allocator, module_root, name, module_name)
        else
            try localModulePath(self.allocator, module_root, module_name);
        var directory = Io.Dir.cwd().openDir(self.io, directory_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {
                return self.moduleNotFound(position, module_name, directory_path, null);
            },
            else => |other| return other,
        };
        defer directory.close(self.io);

        var source_names: std.ArrayList([]const u8) = .empty;
        var iterator = directory.iterateAssumeFirstIteration();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
            try source_names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }
        std.mem.sort([]const u8, source_names.items, {}, struct {
            fn lessThan(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.lessThan);

        const module_index = modules.items.len;
        const native_runtime = try findNativeRuntimeInPackage(self.allocator, self.io, module_root, package_name, module_name);
        try modules.append(self.allocator, .{
            .name = module_name,
            .provider = provider,
            .package_index = package_index,
            .native_runtime_name = if (native_runtime) |runtime| runtime.module_name else null,
            .module_manifest_path = if (native_runtime) |runtime| runtime.manifest_path else null,
            .native_module_directory = if (native_runtime) |runtime| runtime.module_directory else null,
        });
        for (source_names.items) |source_name| {
            const source_path = try std.fs.path.join(self.allocator, &.{ directory_path, source_name });
            try modules.items[module_index].sources.append(self.allocator, source_path);
            try self.appendFile(source_path, module_index);
        }
    }

    fn appendFile(self: *Loader, source_path: []const u8, module_index: usize) !void {
        const source = Io.Dir.cwd().readFileAlloc(self.io, source_path, self.allocator, .limited(16 * 1024 * 1024)) catch |err| {
            std.debug.print("silex: unable to read '{s}': {t}\n", .{ source_path, err });
            return error.Reported;
        };
        const file_index = self.source_paths.items.len;
        try self.source_paths.append(self.allocator, source_path);
        try self.source_contents.append(self.allocator, source);
        var parser = ParserModule.Parser.initFile(self.allocator, source, file_index);
        const program = parser.parse() catch |err| switch (err) {
            error.InvalidSource => {
                self.diagnostic = parser.diagnostic.?;
                return error.InvalidSource;
            },
            else => |other| return other,
        };
        try self.files.append(self.allocator, .{ .module_index = module_index, .program = program });
    }

    fn finish(self: *Loader, project: ProjectModule.Project) !Loaded {
        return .{
            .project = project,
            .package_graph = self.package_graph.?,
            .source_paths = try self.source_paths.toOwnedSlice(self.allocator),
            .source_contents = try self.source_contents.toOwnedSlice(self.allocator),
            .files = try self.files.toOwnedSlice(self.allocator),
        };
    }

    fn fail(self: *Loader, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }

    fn multipleProviders(self: *Loader, position: Source.Position, module_name: []const u8) !void {
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "module '{s}' has multiple providers",
            .{module_name},
        ));
    }

    fn moduleNotFound(
        self: *Loader,
        position: Source.Position,
        module_name: []const u8,
        local_path: []const u8,
        distributed_path: ?[]const u8,
    ) !void {
        const message = if (distributed_path) |path|
            try std.fmt.allocPrint(
                self.allocator,
                "module '{s}' was not found locally at '{s}' or in the distributed library at '{s}'",
                .{ module_name, local_path, path },
            )
        else
            try std.fmt.allocPrint(self.allocator, "module '{s}' was not found at '{s}'", .{ module_name, local_path });
        return self.fail(position, message);
    }
};

fn findModule(modules: []const ModuleBuilder, name: []const u8) ?usize {
    for (modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, name)) return index;
    }
    return null;
}

fn graphDependencyConflictsWithModule(
    graph: PackageGraph.Graph,
    package_index: usize,
    module: ModuleBuilder,
) bool {
    const dependency_index = graph.directDependency(package_index, firstSegment(module.name)) orelse return false;
    return dependency_index != module.package_index;
}

fn moduleNameFromUse(path: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[0..separator];
}

fn canonicalUsePath(
    allocator: Allocator,
    imports: []const Ast.Import,
    aliases: []const ModuleAlias,
    path: []const u8,
) ![]const u8 {
    var matched_qualifier: ?[]const u8 = null;
    var matched_module: ?[]const u8 = null;
    for (imports) |import_value| {
        const qualifier = import_value.alias orelse import_value.path;
        if (!pathHasQualifier(path, qualifier)) continue;
        if (matched_qualifier == null or qualifier.len > matched_qualifier.?.len) {
            matched_qualifier = qualifier;
            matched_module = import_value.path;
        }
    }
    for (aliases) |alias| {
        if (!pathHasQualifier(path, alias.qualifier)) continue;
        if (matched_qualifier == null or alias.qualifier.len > matched_qualifier.?.len) {
            matched_qualifier = alias.qualifier;
            matched_module = alias.module_name;
        }
    }
    const qualifier = matched_qualifier orelse return path;
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{
        matched_module.?,
        path[qualifier.len + 1 ..],
    });
}

fn canonicalImportedPath(
    allocator: Allocator,
    imports: []const Ast.Import,
    path: []const u8,
) !?[]const u8 {
    var matched: ?Ast.Import = null;
    for (imports) |import_value| {
        const qualifier = import_value.alias orelse import_value.path;
        if (!pathHasQualifier(path, qualifier)) continue;
        if (matched == null) {
            matched = import_value;
            continue;
        }
        const matched_qualifier = matched.?.alias orelse matched.?.path;
        if (qualifier.len > matched_qualifier.len) matched = import_value;
    }
    const import_value = matched orelse return null;
    const qualifier = import_value.alias orelse import_value.path;
    const canonical: []const u8 = try std.fmt.allocPrint(allocator, "{s}.{s}", .{
        import_value.path,
        path[qualifier.len + 1 ..],
    });
    return canonical;
}

fn pathHasQualifier(path: []const u8, qualifier: []const u8) bool {
    return std.mem.startsWith(u8, path, qualifier) and
        path.len > qualifier.len and path[qualifier.len] == '.';
}

fn lastSegment(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[separator + 1 ..];
}

fn firstSegment(path: []const u8) []const u8 {
    const separator = std.mem.indexOfScalar(u8, path, '.') orelse return path;
    return path[0..separator];
}

fn moduleBelongsToPackage(module_name: []const u8, package_name: []const u8) bool {
    return std.mem.eql(u8, module_name, package_name) or
        (std.mem.startsWith(u8, module_name, package_name) and
            module_name.len > package_name.len and
            module_name[package_name.len] == '.');
}

fn packageModulePath(
    allocator: Allocator,
    package_root: []const u8,
    package_name: []const u8,
    module_name: []const u8,
) ![]const u8 {
    std.debug.assert(moduleBelongsToPackage(module_name, package_name));
    if (std.mem.eql(u8, module_name, package_name)) return allocator.dupe(u8, package_root);
    const relative_name = module_name[package_name.len + 1 ..];
    return localModulePath(allocator, package_root, relative_name);
}

fn localModulePath(allocator: Allocator, root: []const u8, module_name: []const u8) ![]const u8 {
    const relative_path = try allocator.dupe(u8, module_name);
    for (relative_path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return std.fs.path.join(allocator, &.{ root, relative_path });
}

fn isDirectory(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

fn findNativeRuntime(
    allocator: Allocator,
    io: Io,
    module_root: []const u8,
    module_name: []const u8,
) !?NativeRuntime {
    return findNativeRuntimeInPackage(allocator, io, module_root, null, module_name);
}

fn findNativeRuntimeInPackage(
    allocator: Allocator,
    io: Io,
    module_root: []const u8,
    package_name: ?[]const u8,
    module_name: []const u8,
) !?NativeRuntime {
    var candidate_name = module_name;
    while (true) {
        const candidate_directory = if (package_name) |name|
            try packageModulePath(allocator, module_root, name, candidate_name)
        else
            try localModulePath(allocator, module_root, candidate_name);
        if (try nativeModuleManifestPath(allocator, io, candidate_directory)) |manifest_path| {
            return .{
                .module_name = candidate_name,
                .module_directory = candidate_directory,
                .manifest_path = manifest_path,
            };
        }
        const separator = std.mem.lastIndexOfScalar(u8, candidate_name, '.') orelse return null;
        candidate_name = candidate_name[0..separator];
    }
}

fn nativeModuleManifestPath(allocator: Allocator, io: Io, module_directory: []const u8) !?[]const u8 {
    const path = try std.fs.path.join(allocator, &.{ module_directory, "Module.json" });
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    if (stat.kind != .file) return null;
    const manifest = ModuleManifest.load(allocator, io, path) catch |err| {
        std.debug.print("silex: invalid module manifest at '{s}': {t}\n", .{ path, err });
        return error.Reported;
    };
    return if (manifest.native != null) path else null;
}

test "native runtime ignores metadata-only and incorrectly cased child manifests" {
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
        .sub_path = "Library/Parent/Child/Module.json",
        .data = "{\"author\":\"Child author\"}",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Parent/Module.json",
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
    try std.testing.expect(std.mem.endsWith(u8, runtime.manifest_path, "Parent/Module.json"));

    try temporary.dir.createDir(std.testing.io, "Library/Metadata", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Metadata/Module.json",
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
}

test "local module paths follow their logical segments" {
    const path = try localModulePath(std.testing.allocator, "Sandbox", "Math.Geometry");
    defer std.testing.allocator.free(path);
    const expected = try std.fs.path.join(std.testing.allocator, &.{ "Sandbox", "Math", "Geometry" });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, path);
}

test "use paths select a declaration from their parent module" {
    try std.testing.expectEqualStrings("Math.Geometry", moduleNameFromUse("Math.Geometry.Ray").?);
    try std.testing.expect(moduleNameFromUse("Vec3") == null);
}

test "use paths expand import and module aliases" {
    const imports = &[_]Ast.Import{.{
        .path = "STD",
        .alias = "Standard",
        .position = .{ .line = 1, .column = 1 },
    }};
    const aliases = &[_]ModuleAlias{.{ .qualifier = "Random", .module_name = "STD.Random" }};

    const imported = try canonicalUsePath(std.testing.allocator, imports, &.{}, "Standard.Random");
    defer std.testing.allocator.free(imported);
    try std.testing.expectEqualStrings("STD.Random", imported);
    const expanded = try canonicalUsePath(std.testing.allocator, imports, aliases, "Random.Generator");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("STD.Random.Generator", expanded);
}

test "qualified paths expand parent import aliases" {
    const imports = &[_]Ast.Import{.{
        .path = "STD",
        .alias = "Standard",
        .position = .{ .line = 1, .column = 1 },
    }};

    const canonical = (try canonicalImportedPath(
        std.testing.allocator,
        imports,
        "Standard.Time.Stopwatch",
    )).?;
    defer std.testing.allocator.free(canonical);
    try std.testing.expectEqualStrings("STD.Time.Stopwatch", canonical);
    try std.testing.expect(try canonicalImportedPath(std.testing.allocator, imports, "stopwatch.start") == null);
}
