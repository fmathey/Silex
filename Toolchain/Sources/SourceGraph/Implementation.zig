pub const std = @import("std");
pub const build_options = @import("build_options");
pub const Ast = @import("../Ast.zig");
pub const LexerModule = @import("../Lexer.zig");
pub const ModuleDiscovery = @import("../ModuleDiscovery.zig");
pub const ModuleManifest = @import("../ModuleManifest.zig");
pub const Modules = @import("../Modules.zig");
pub const PackageGraph = @import("../PackageGraph.zig");
pub const ParserModule = @import("../Parser.zig");
pub const ProjectModule = @import("../Project.zig");
pub const Source = @import("../Source.zig");
pub const StandardLibrary = @import("../StandardLibrary.zig");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;
pub const EnvironMap = std.process.Environ.Map;

pub const ModuleBuilder = struct {
    name: []const u8,
    available_sources: std.ArrayList(UnitSource) = .empty,
    sources: std.ArrayList([]const u8) = .empty,
    provider: Provider,
    module_root: []const u8,
    package_name: ?[]const u8 = null,
    catalog_complete: bool = false,
    selected: bool = false,
    native_runtime_name: ?[]const u8 = null,
    module_manifest_path: ?[]const u8 = null,
    native_module_directory: ?[]const u8 = null,
    package_index: usize = 0,
};

pub const UnitSource = struct {
    name: []const u8,
    path: []const u8,
};

pub const NamespaceLocation = struct {
    sources: []const []const u8,
    has_directory: bool,
};

pub const UnitTarget = struct {
    module_index: usize,
    source_index: usize,
};

pub const Selection = union(enum) {
    module: usize,
    units: struct {
        items: []const UnitTarget,
        load_only: bool,
    },
};

pub const FileState = struct {
    use_edges: std.ArrayList(usize) = .empty,
    activation_roots: std.ArrayList(usize) = .empty,
    load_only_uses: std.ArrayList(Source.Position) = .empty,
};

pub const NativeRuntime = struct {
    module_name: []const u8,
    module_directory: []const u8,
    manifest_path: []const u8,
};

pub const Provider = enum { application, local, package, distributed };

pub fn canonicalPath(allocator: Allocator, io: Io, path: []const u8) ![]const u8 {
    return Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch |err| switch (err) {
        error.FileNotFound => {
            const parent = std.fs.path.dirname(path) orelse ".";
            const canonical_parent = try Io.Dir.cwd().realPathFileAlloc(io, parent, allocator);
            return std.fs.path.join(allocator, &.{ canonical_parent, std.fs.path.basename(path) });
        },
        else => |other| return other,
    };
}

pub const ModuleAlias = struct {
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

pub const Overlay = struct {
    path: []const u8,
    text: []const u8,
};

pub const Mode = enum { compiler, editor };

pub const Loader = struct {
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    source_paths: std.ArrayList([]const u8) = .empty,
    source_contents: std.ArrayList([]const u8) = .empty,
    files: std.ArrayList(Modules.File) = .empty,
    file_states: std.ArrayList(FileState) = .empty,
    diagnostic: ?Source.Diagnostic = null,
    package_graph: ?PackageGraph.Graph = null,
    overlays: []const Overlay = &.{},
    mode: Mode = .compiler,

    pub fn init(allocator: Allocator, io: Io, environ_map: *const EnvironMap) Loader {
        return .{ .allocator = allocator, .io = io, .environ_map = environ_map };
    }

    pub fn load(self: *Loader, input_path: []const u8) !Loaded {
        const project = try ProjectModule.load(self.allocator, self.io, input_path);
        const project_root = std.fs.path.dirname(input_path) orelse ".";
        return self.loadProject(project, project_root);
    }

    pub fn loadProject(
        self: *Loader,
        initial_project: ProjectModule.Project,
        project_root: []const u8,
    ) !Loaded {
        var project = initial_project;
        self.package_graph = try PackageGraph.resolve(
            self.allocator,
            self.io,
            self.environ_map,
            project_root,
            if (self.mode == .editor) .editor else .normal,
        );
        const loads_local_modules = project.single_file;
        var modules: std.ArrayList(ModuleBuilder) = .empty;
        for (project.modules) |module| {
            var available_sources: std.ArrayList(UnitSource) = .empty;
            for (module.sources) |source_path| try self.addAvailableSource(
                &available_sources,
                source_path,
                .{ .line = 1, .column = 1 },
                module.name,
            );
            try modules.append(self.allocator, .{
                .name = module.name,
                .available_sources = available_sources,
                .provider = .application,
                .module_root = project_root,
                .catalog_complete = true,
                .package_index = 0,
            });
        }
        _ = try self.selectModule(&modules, project.target_module, .{ .line = 1, .column = 1 });

        var file_index: usize = 0;
        while (file_index < self.files.items.len) : (file_index += 1) {
            const file = self.files.items[file_index];
            const package_index = modules.items[file.module_index].package_index;
            var module_aliases: std.ArrayList(ModuleAlias) = .empty;
            for (file.program.uses) |use_value| {
                const path = switch (use_value.target) {
                    .declaration => |value| value,
                    .type => continue,
                };
                const canonical_path = try canonicalUsePath(
                    self.allocator,
                    module_aliases.items,
                    path,
                );
                const selection = try self.resolveSelection(
                    &modules,
                    project_root,
                    canonical_path,
                    use_value.position,
                    loads_local_modules,
                    package_index,
                    file.module_index,
                );
                const roots = try self.selectSelection(&modules, selection, use_value.position);
                try self.appendRoots(&self.file_states.items[file_index].use_edges, roots);
                try self.appendRoots(&self.file_states.items[file_index].activation_roots, roots);
                switch (selection) {
                    .module => |module_index| {
                        try module_aliases.append(self.allocator, .{
                            .qualifier = use_value.alias orelse lastSegment(path),
                            .module_name = modules.items[module_index].name,
                        });
                    },
                    .units => |units| if (units.load_only) try self.file_states.items[file_index].load_only_uses.append(
                        self.allocator,
                        use_value.position,
                    ),
                }
            }
            for (file.program.uses) |use_value| switch (use_value.target) {
                .declaration => {},
                .type => |aliased_type| try self.selectTypeUseDependencies(
                    &modules,
                    project_root,
                    module_aliases.items,
                    aliased_type,
                    use_value.position,
                    loads_local_modules,
                    package_index,
                    file.module_index,
                    &self.file_states.items[file_index],
                ),
            };
            try self.selectQualifiedDependencies(
                &modules,
                project_root,
                file_index,
                loads_local_modules,
                package_index,
                module_aliases.items,
            );
        }

        try self.finishActivationClosures();

        var project_modules: std.ArrayList(ProjectModule.Module) = .empty;
        for (modules.items) |*module| try project_modules.append(self.allocator, .{
            .name = module.name,
            .sources = try module.sources.toOwnedSlice(self.allocator),
            .package_index = module.package_index,
            .native_runtime_name = module.native_runtime_name,
            .module_manifest_path = module.module_manifest_path,
            .native_module_directory = module.native_module_directory,
            .origin = switch (module.provider) {
                .application => .application,
                .local => .local,
                .package => .package,
                .distributed => .distributed,
            },
        });
        project.modules = try project_modules.toOwnedSlice(self.allocator);
        project.single_file = loads_local_modules and self.files.items.len == 1;
        return self.finish(project);
    }

    fn addAvailableSource(
        self: *Loader,
        sources: *std.ArrayList(UnitSource),
        source_path: []const u8,
        position: Source.Position,
        module_name: []const u8,
    ) !void {
        const basename = std.fs.path.basename(source_path);
        const unit_name = basename[0 .. basename.len - ".sx".len];
        for (sources.items) |source| if (std.mem.eql(u8, source.name, unit_name)) {
            if (std.mem.eql(u8, source.path, source_path)) return;
            return self.fail(position, try std.fmt.allocPrint(
                self.allocator,
                "namespace '{s}' has multiple source providers",
                .{module_name},
            ));
        };
        try sources.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, unit_name),
            .path = source_path,
        });
    }

    fn ensureCatalog(self: *Loader, module: *ModuleBuilder, position: Source.Position) !void {
        if (module.catalog_complete) return;
        const location = try namespaceLocation(
            self.allocator,
            self.io,
            module.module_root,
            module.package_name,
            module.name,
        );
        if (!location.has_directory and location.sources.len == 0) {
            const expected_path = if (module.package_name) |name|
                try packageModulePath(self.allocator, module.module_root, name, module.name)
            else
                try localModulePath(self.allocator, module.module_root, module.name);
            return self.moduleNotFound(position, module.name, expected_path, null);
        }
        if (location.sources.len > 1) return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "namespace '{s}' has multiple source providers '{s}' and '{s}'",
            .{ module.name, location.sources[0], location.sources[1] },
        ));
        if (location.sources.len == 1) try self.addAvailableSource(
            &module.available_sources,
            location.sources[0],
            position,
            module.name,
        );
        module.catalog_complete = true;
    }

    fn ensureRuntime(self: *Loader, module: *ModuleBuilder) !void {
        if (module.selected) return;
        const native_runtime = try findNativeRuntimeInPackage(
            self.allocator,
            self.io,
            module.module_root,
            module.package_name,
            module.name,
        );
        if (native_runtime) |runtime| {
            module.native_runtime_name = runtime.module_name;
            module.module_manifest_path = runtime.manifest_path;
            module.native_module_directory = runtime.module_directory;
        }
        module.selected = true;
    }

    fn selectModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        module_index: usize,
        position: Source.Position,
    ) ![]const usize {
        try self.ensureCatalog(&modules.items[module_index], position);
        try self.ensureRuntime(&modules.items[module_index]);
        var roots: std.ArrayList(usize) = .empty;
        for (modules.items[module_index].available_sources.items, 0..) |_, source_index| {
            try roots.append(self.allocator, try self.selectUnit(modules, .{
                .module_index = module_index,
                .source_index = source_index,
            }));
        }
        return roots.toOwnedSlice(self.allocator);
    }

    fn selectUnit(self: *Loader, modules: *std.ArrayList(ModuleBuilder), target: UnitTarget) !usize {
        const module = &modules.items[target.module_index];
        try self.ensureRuntime(module);
        const unit = module.available_sources.items[target.source_index];
        if (self.findLoadedFile(unit.path)) |file_index| return file_index;
        try module.sources.append(self.allocator, unit.path);
        return self.appendFile(unit.path, target.module_index, unit.name);
    }

    fn selectSelection(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        selection: Selection,
        position: Source.Position,
    ) ![]const usize {
        return switch (selection) {
            .module => |module_index| self.selectModule(modules, module_index, position),
            .units => |units| block: {
                var roots: std.ArrayList(usize) = .empty;
                for (units.items) |target| try roots.append(self.allocator, try self.selectUnit(modules, target));
                break :block roots.toOwnedSlice(self.allocator);
            },
        };
    }

    fn appendRoots(self: *Loader, destination: *std.ArrayList(usize), roots: []const usize) !void {
        for (roots) |root| {
            var found = false;
            for (destination.items) |existing| if (existing == root) {
                found = true;
                break;
            };
            if (!found) try destination.append(self.allocator, root);
        }
    }

    fn ensureNamedModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_name: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
    ) !usize {
        if (findModule(modules.items, module_name)) |module_index| {
            if (self.moduleAccessible(modules.items[module_index], package_index)) return module_index;
        }
        try self.loadNamedModule(modules, project_root, module_name, position, loads_local_modules, package_index);
        return findModule(modules.items, module_name) orelse unreachable;
    }

    fn resolveSelection(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        canonical_path: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
        current_module_index: usize,
    ) !Selection {
        if (try self.moduleExists(modules.items, project_root, canonical_path, loads_local_modules, package_index)) {
            const module_index = try self.ensureNamedModule(
                modules,
                project_root,
                canonical_path,
                position,
                loads_local_modules,
                package_index,
            );
            try self.validateNamespaceDeclarationCollision(
                modules,
                project_root,
                canonical_path,
                position,
                loads_local_modules,
                package_index,
            );
            return .{ .module = module_index };
        }

        if (std.mem.indexOfScalar(u8, canonical_path, '.') == null) {
            const current_name = modules.items[current_module_index].name;
            if (parentModuleName(current_name)) |parent| {
                const sibling_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ parent, canonical_path });
                if (try self.moduleExists(
                    modules.items,
                    project_root,
                    sibling_name,
                    loads_local_modules,
                    package_index,
                )) return .{ .module = try self.ensureNamedModule(
                    modules,
                    project_root,
                    sibling_name,
                    position,
                    loads_local_modules,
                    package_index,
                ) };
            }
            if (self.package_graph.?.explicit and
                self.package_graph.?.findPackage(canonical_path) != null and
                self.package_graph.?.directDependency(package_index, canonical_path) == null)
            {
                try self.transitiveVisibilityError(position, package_index, canonical_path);
                unreachable;
            }
            return self.resolveDeclaration(modules, current_module_index, canonical_path, position, true, true);
        }
        var candidate = canonical_path;
        while (std.mem.lastIndexOfScalar(u8, candidate, '.')) |separator| {
            candidate = candidate[0..separator];
            if (!try self.moduleExists(modules.items, project_root, candidate, loads_local_modules, package_index)) continue;
            const module_index = try self.ensureNamedModule(
                modules,
                project_root,
                candidate,
                position,
                loads_local_modules,
                package_index,
            );
            const remainder = canonical_path[candidate.len + 1 ..];
            if (std.mem.indexOfScalar(u8, remainder, '.') != null) continue;
            const internal_access = modules.items[module_index].package_index ==
                modules.items[current_module_index].package_index and
                sameModuleParent(modules.items[module_index].name, modules.items[current_module_index].name);
            return self.resolveDeclaration(
                modules,
                module_index,
                remainder,
                position,
                module_index == current_module_index or internal_access,
                module_index == current_module_index,
            );
        }
        const package_name = firstSegment(canonical_path);
        if (self.package_graph.?.explicit and
            self.package_graph.?.findPackage(package_name) != null and
            self.package_graph.?.directDependency(package_index, package_name) == null)
        {
            try self.transitiveVisibilityError(position, package_index, package_name);
            unreachable;
        }
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "unknown use target '{s}'",
            .{canonical_path},
        ));
    }

    fn validateNamespaceDeclarationCollision(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        namespace: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
    ) !void {
        const parent = parentModuleName(namespace) orelse return;
        if (!try self.moduleExists(modules.items, project_root, parent, loads_local_modules, package_index)) return;
        const parent_index = try self.ensureNamedModule(
            modules,
            project_root,
            parent,
            position,
            loads_local_modules,
            package_index,
        );
        try self.ensureCatalog(&modules.items[parent_index], position);
        if (modules.items[parent_index].available_sources.items.len != 1) return;
        const child = lastSegment(namespace);
        if (!try self.unitDeclares(modules.items[parent_index].available_sources.items[0].path, child, false)) return;
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "namespace '{s}' conflicts with declaration '{s}' in namespace '{s}'",
            .{ namespace, child, parent },
        ));
    }

    fn resolveDeclaration(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        module_index: usize,
        name: []const u8,
        position: Source.Position,
        private_access: bool,
        allow_semantic_resolution: bool,
    ) !Selection {
        try self.ensureCatalog(&modules.items[module_index], position);
        if (modules.items[module_index].available_sources.items.len == 1 and
            try self.unitDeclares(
                modules.items[module_index].available_sources.items[0].path,
                name,
                !private_access,
            )) return .{ .units = .{
            .items = try self.allocator.dupe(UnitTarget, &.{.{
                .module_index = module_index,
                .source_index = 0,
            }}),
            .load_only = false,
        } };
        if (allow_semantic_resolution) return .{ .units = .{
            .items = &.{},
            .load_only = false,
        } };
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "namespace '{s}' has no selectable declaration '{s}'",
            .{ modules.items[module_index].name, name },
        ));
    }

    fn unitDeclares(self: *Loader, source_path: []const u8, name: []const u8, public_only: bool) !bool {
        const source = self.readSource(source_path) catch return false;
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |source_line| {
            const line = std.mem.trim(u8, source_line, " \t\r");
            if (!std.mem.startsWith(u8, line, "public use ")) continue;
            const declaration = line["public use ".len..];
            const alias_marker = std.mem.indexOf(u8, declaration, " as ");
            const exported_name = if (alias_marker) |index|
                std.mem.trim(u8, declaration[index + " as ".len ..], " \t\r")
            else block: {
                const target_end = std.mem.indexOfAny(u8, declaration, " <\t\r") orelse declaration.len;
                break :block lastSegment(declaration[0..target_end]);
            };
            if (std.mem.eql(u8, exported_name, name)) return true;
        }
        var lexer = LexerModule.Lexer.init(source);
        var depth: usize = 0;
        var is_public = false;
        while (true) {
            const token = lexer.next() catch return false;
            if (token.tag == .end) return false;
            if (token.tag == .left_brace) {
                depth += 1;
                is_public = false;
                continue;
            }
            if (token.tag == .right_brace) {
                depth -|= 1;
                is_public = false;
                continue;
            }
            if (depth != 0) continue;
            if (token.tag == .keyword_public) {
                is_public = true;
                continue;
            }
            const declares = token.tag == .keyword_struct or token.tag == .keyword_class or
                token.tag == .keyword_protocol or token.tag == .keyword_enum or token.tag == .keyword_func;
            if (declares) {
                const declared = lexer.next() catch return false;
                if (declared.tag == .identifier and std.mem.eql(u8, declared.lexeme, name) and
                    (!public_only or is_public)) return true;
            }
            is_public = false;
        }
    }

    fn findLoadedFile(self: *const Loader, source_path: []const u8) ?usize {
        for (self.source_paths.items, 0..) |loaded, index| {
            if (std.mem.eql(u8, loaded, source_path)) return index;
        }
        return null;
    }

    fn selectTypeUseDependencies(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_aliases: []const ModuleAlias,
        type_name: Ast.TypeName,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
        current_module_index: usize,
        state: *FileState,
    ) !void {
        switch (type_name) {
            .structure => |name| {
                if (std.mem.indexOfScalar(u8, name, '.') != null) {
                    const canonical = try canonicalUsePath(self.allocator, module_aliases, name);
                    const selection = try self.resolveSelection(
                        modules,
                        project_root,
                        canonical,
                        position,
                        loads_local_modules,
                        package_index,
                        current_module_index,
                    );
                    const roots = try self.selectSelection(modules, selection, position);
                    try self.appendRoots(&state.use_edges, roots);
                    try self.appendRoots(&state.activation_roots, roots);
                }
            },
            .generic_structure => |generic| {
                if (std.mem.indexOfScalar(u8, generic.name, '.') != null) {
                    const canonical = try canonicalUsePath(self.allocator, module_aliases, generic.name);
                    const selection = try self.resolveSelection(
                        modules,
                        project_root,
                        canonical,
                        position,
                        loads_local_modules,
                        package_index,
                        current_module_index,
                    );
                    const roots = try self.selectSelection(modules, selection, position);
                    try self.appendRoots(&state.use_edges, roots);
                    try self.appendRoots(&state.activation_roots, roots);
                }
                for (generic.arguments) |argument| try self.selectTypeUseDependencies(
                    modules,
                    project_root,
                    module_aliases,
                    argument,
                    position,
                    loads_local_modules,
                    package_index,
                    current_module_index,
                    state,
                );
            },
            .list, .optional => |contained| try self.selectTypeUseDependencies(
                modules,
                project_root,
                module_aliases,
                contained.*,
                position,
                loads_local_modules,
                package_index,
                current_module_index,
                state,
            ),
            .fixed_array => |array| try self.selectTypeUseDependencies(
                modules,
                project_root,
                module_aliases,
                array.element.*,
                position,
                loads_local_modules,
                package_index,
                current_module_index,
                state,
            ),
            .reference => |reference| try self.selectTypeUseDependencies(
                modules,
                project_root,
                module_aliases,
                reference.target.*,
                position,
                loads_local_modules,
                package_index,
                current_module_index,
                state,
            ),
            .function => |function| {
                for (function.parameters) |parameter| try self.selectTypeUseDependencies(
                    modules,
                    project_root,
                    module_aliases,
                    parameter,
                    position,
                    loads_local_modules,
                    package_index,
                    current_module_index,
                    state,
                );
                if (function.return_type) |return_type| try self.selectTypeUseDependencies(
                    modules,
                    project_root,
                    module_aliases,
                    return_type.*,
                    position,
                    loads_local_modules,
                    package_index,
                    current_module_index,
                    state,
                );
            },
            else => {},
        }
    }

    fn selectQualifiedDependencies(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        file_index: usize,
        loads_local_modules: bool,
        package_index: usize,
        module_aliases: []const ModuleAlias,
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

            if (try canonicalAliasedPath(self.allocator, module_aliases, path.items)) |canonical| {
                const roots = try self.selectLongestQualifiedTarget(
                    modules,
                    project_root,
                    canonical,
                    tokens.items[index].position,
                    loads_local_modules,
                    package_index,
                    file.module_index,
                );
                try self.appendRoots(&self.file_states.items[file_index].use_edges, roots);
                try self.appendRoots(&self.file_states.items[file_index].activation_roots, roots);
            }
            index = end + 1;
        }
    }

    fn selectLongestQualifiedTarget(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        canonical_path: []const u8,
        position: Source.Position,
        loads_local_modules: bool,
        package_index: usize,
        current_module_index: usize,
    ) ![]const usize {
        var candidate = canonical_path;
        while (true) {
            const selection = self.resolveSelection(
                modules,
                project_root,
                candidate,
                position,
                loads_local_modules,
                package_index,
                current_module_index,
            ) catch |err| switch (err) {
                error.InvalidSource => {
                    self.diagnostic = null;
                    const separator = std.mem.lastIndexOfScalar(u8, candidate, '.') orelse return &.{};
                    candidate = candidate[0..separator];
                    continue;
                },
                else => |other| return other,
            };
            return self.selectSelection(modules, selection, position);
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
        if (!ModuleDiscovery.isModuleName(module_name)) return false;
        if (findModule(modules, module_name)) |module_index| {
            return self.moduleAccessible(modules[module_index], package_index);
        }
        if (StandardLibrary.isReservedModule(module_name)) {
            const library_root = StandardLibrary.root(self.allocator, self.io) catch return false;
            return namespaceExists(self.allocator, self.io, library_root, null, module_name);
        }
        if (self.package_graph.?.explicit) return self.explicitModuleExists(project_root, module_name, package_index);
        if (loads_local_modules and
            try namespaceExists(self.allocator, self.io, project_root, null, module_name))
        {
            return true;
        }
        const library_root = StandardLibrary.root(self.allocator, self.io) catch return false;
        return namespaceExists(self.allocator, self.io, library_root, null, module_name);
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
            if (loads_local_modules) {
                if (try namespaceExists(self.allocator, self.io, project_root, null, module_name)) {
                    const library_root = StandardLibrary.root(self.allocator, self.io) catch {
                        return self.loadDistributedModule(modules, module_name, position);
                    };
                    if (try namespaceExists(self.allocator, self.io, library_root, null, module_name)) {
                        return self.multipleProviders(position, module_name);
                    }
                }
            }
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
        const has_local = try namespaceExists(self.allocator, self.io, project_root, null, module_name);
        const library_root = StandardLibrary.root(self.allocator, self.io) catch |err| {
            if (has_local) return self.loadModule(modules, project_root, null, module_name, position, .local, 0);
            return err;
        };
        const has_distributed = try namespaceExists(self.allocator, self.io, library_root, null, module_name);
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
        if (!try namespaceExists(self.allocator, self.io, library_root, null, module_name)) {
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
                return namespaceExists(self.allocator, self.io, package.root, name, module_name);
            }
        }
        if (graph.directDependency(package_index, firstSegment(module_name))) |dependency_index| {
            const dependency = graph.packages[dependency_index];
            return namespaceExists(self.allocator, self.io, dependency.root, dependency.name.?, module_name);
        }
        if (package_index == 0) {
            return namespaceExists(self.allocator, self.io, project_root, null, module_name);
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
                if (!try namespaceExists(self.allocator, self.io, package.root, name, module_name)) {
                    return self.moduleNotFound(position, module_name, path, null);
                }
                return self.loadModule(modules, package.root, name, module_name, position, .package, package_index);
            }
        }

        const dependency_index = graph.directDependency(package_index, firstSegment(module_name));
        const local_path = if (package_index == 0)
            try localModulePath(self.allocator, project_root, module_name)
        else
            null;
        const has_local = if (local_path != null)
            try namespaceExists(self.allocator, self.io, project_root, null, module_name)
        else
            false;
        if (dependency_index) |index| {
            const dependency = graph.packages[index];
            const dependency_path = try packageModulePath(self.allocator, dependency.root, dependency.name.?, module_name);
            const has_dependency = try namespaceExists(
                self.allocator,
                self.io,
                dependency.root,
                dependency.name.?,
                module_name,
            );
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
            "package '{s}' cannot use transitive package '{s}' without declaring it directly",
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

        try modules.append(self.allocator, .{
            .name = module_name,
            .provider = provider,
            .module_root = module_root,
            .package_name = package_name,
            .package_index = package_index,
        });
    }

    fn appendFile(self: *Loader, source_path: []const u8, module_index: usize, unit_name: []const u8) !usize {
        const source = self.readSource(source_path) catch |err| {
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
        try self.files.append(self.allocator, .{
            .module_index = module_index,
            .unit_name = unit_name,
            .program = program,
        });
        try self.file_states.append(self.allocator, .{});
        return file_index;
    }

    fn readSource(self: *Loader, source_path: []const u8) ![]const u8 {
        for (self.overlays) |overlay| {
            if (std.mem.eql(u8, overlay.path, source_path)) return overlay.text;
            const canonical = canonicalPath(self.allocator, self.io, source_path) catch continue;
            if (std.mem.eql(u8, overlay.path, canonical)) return overlay.text;
        }
        return Io.Dir.cwd().readFileAlloc(
            self.io,
            source_path,
            self.allocator,
            .limited(16 * 1024 * 1024),
        );
    }

    fn finishActivationClosures(self: *Loader) !void {
        for (self.files.items, 0..) |*file, file_index| {
            var dependency_modules: std.ArrayList(usize) = .empty;
            for (self.file_states.items[file_index].use_edges.items) |dependency_file| {
                const dependency_module = self.files.items[dependency_file].module_index;
                if (dependency_module == file.module_index) continue;
                var present = false;
                for (dependency_modules.items) |existing| if (existing == dependency_module) {
                    present = true;
                    break;
                };
                if (!present) try dependency_modules.append(self.allocator, dependency_module);
            }
            file.dependency_modules = try dependency_modules.toOwnedSlice(self.allocator);
            var activated: std.ArrayList(usize) = .empty;
            for (self.file_states.items[file_index].activation_roots.items) |root| {
                var pending: std.ArrayList(usize) = .empty;
                try pending.append(self.allocator, root);
                while (pending.pop()) |current| {
                    var visited = false;
                    for (activated.items) |existing| if (existing == current) {
                        visited = true;
                        break;
                    };
                    if (visited) continue;
                    try activated.append(self.allocator, current);
                    for (self.file_states.items[current].use_edges.items) |dependency| {
                        try pending.append(self.allocator, dependency);
                    }
                }
            }
            file.activated_files = try activated.toOwnedSlice(self.allocator);
            file.load_only_uses = try self.file_states.items[file_index].load_only_uses.toOwnedSlice(self.allocator);
        }
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

pub fn findModule(modules: []const ModuleBuilder, name: []const u8) ?usize {
    for (modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, name)) return index;
    }
    return null;
}

pub fn findUnit(sources: []const UnitSource, name: []const u8) ?usize {
    for (sources, 0..) |source, index| {
        if (std.mem.eql(u8, source.name, name)) return index;
    }
    return null;
}

pub fn graphDependencyConflictsWithModule(
    graph: PackageGraph.Graph,
    package_index: usize,
    module: ModuleBuilder,
) bool {
    const dependency_index = graph.directDependency(package_index, firstSegment(module.name)) orelse return false;
    return dependency_index != module.package_index;
}

pub fn moduleNameFromUse(path: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[0..separator];
}

pub fn canonicalUsePath(
    allocator: Allocator,
    aliases: []const ModuleAlias,
    path: []const u8,
) ![]const u8 {
    var matched_qualifier: ?[]const u8 = null;
    var matched_module: ?[]const u8 = null;
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

pub fn canonicalAliasedPath(
    allocator: Allocator,
    aliases: []const ModuleAlias,
    path: []const u8,
) !?[]const u8 {
    var matched: ?ModuleAlias = null;
    for (aliases) |alias| {
        if (!pathHasQualifier(path, alias.qualifier)) continue;
        if (matched == null or alias.qualifier.len > matched.?.qualifier.len) matched = alias;
    }
    const alias = matched orelse return null;
    const canonical: []const u8 = try std.fmt.allocPrint(allocator, "{s}.{s}", .{
        alias.module_name,
        path[alias.qualifier.len + 1 ..],
    });
    return canonical;
}

pub fn pathHasQualifier(path: []const u8, qualifier: []const u8) bool {
    return std.mem.startsWith(u8, path, qualifier) and
        path.len > qualifier.len and path[qualifier.len] == '.';
}

pub fn lastSegment(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[separator + 1 ..];
}

pub fn parentModuleName(path: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[0..separator];
}

pub fn sameModuleParent(left: []const u8, right: []const u8) bool {
    const left_parent = parentModuleName(left) orelse return false;
    const right_parent = parentModuleName(right) orelse return false;
    return std.mem.eql(u8, left_parent, right_parent);
}

pub fn firstSegment(path: []const u8) []const u8 {
    const separator = std.mem.indexOfScalar(u8, path, '.') orelse return path;
    return path[0..separator];
}

pub fn moduleBelongsToPackage(module_name: []const u8, package_name: []const u8) bool {
    return std.mem.eql(u8, module_name, package_name) or
        (std.mem.startsWith(u8, module_name, package_name) and
            module_name.len > package_name.len and
            module_name[package_name.len] == '.');
}

pub fn packageModulePath(
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

pub fn localModulePath(allocator: Allocator, root: []const u8, module_name: []const u8) ![]const u8 {
    const relative_path = try allocator.dupe(u8, module_name);
    defer allocator.free(relative_path);
    for (relative_path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return std.fs.path.join(allocator, &.{ root, relative_path });
}

pub fn namespaceLocation(
    allocator: Allocator,
    io: Io,
    module_root: []const u8,
    package_name: ?[]const u8,
    module_name: []const u8,
) !NamespaceLocation {
    const relative_name = if (package_name) |name| block: {
        std.debug.assert(moduleBelongsToPackage(module_name, name));
        if (std.mem.eql(u8, module_name, name)) {
            break :block "";
        }
        break :block module_name[name.len + 1 ..];
    } else module_name;

    if (relative_name.len == 0) return .{
        .sources = &.{},
        .has_directory = try isDirectory(io, module_root),
    };

    const directory_path = try localModulePath(allocator, module_root, relative_name);
    var sources: std.ArrayList([]const u8) = .empty;
    var has_compact_descendant = false;
    var stem_start: usize = 0;
    while (true) {
        const prefix_name = if (stem_start == 0) "" else relative_name[0 .. stem_start - 1];
        const stem = relative_name[stem_start..];
        const physical_parent = if (prefix_name.len == 0)
            module_root
        else
            try localModulePath(allocator, module_root, prefix_name);
        const filename = try std.fmt.allocPrint(allocator, "{s}.sx", .{stem});
        const source_path = try std.fs.path.join(allocator, &.{ physical_parent, filename });
        if (try isFile(io, source_path)) try sources.append(allocator, source_path);
        if (!has_compact_descendant) has_compact_descendant = try compactDescendantExists(io, physical_parent, stem);

        const separator = std.mem.indexOfScalarPos(u8, relative_name, stem_start, '.') orelse break;
        stem_start = separator + 1;
    }
    return .{
        .sources = try sources.toOwnedSlice(allocator),
        .has_directory = try isDirectory(io, directory_path) or has_compact_descendant,
    };
}

pub fn compactDescendantExists(io: Io, directory_path: []const u8, stem: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    defer directory.close(io);
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
        const source_stem = entry.name[0 .. entry.name.len - ".sx".len];
        if (source_stem.len > stem.len and std.mem.startsWith(u8, source_stem, stem) and source_stem[stem.len] == '.') {
            return true;
        }
    }
    return false;
}

pub fn namespaceExists(
    allocator: Allocator,
    io: Io,
    module_root: []const u8,
    package_name: ?[]const u8,
    module_name: []const u8,
) !bool {
    const location = try namespaceLocation(allocator, io, module_root, package_name, module_name);
    return location.has_directory or location.sources.len != 0;
}

pub fn isFile(io: Io, path: []const u8) !bool {
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    return stat.kind == .file;
}

pub fn isDirectory(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

pub fn findNativeRuntime(
    allocator: Allocator,
    io: Io,
    module_root: []const u8,
    module_name: []const u8,
) !?NativeRuntime {
    return findNativeRuntimeInPackage(allocator, io, module_root, null, module_name);
}

pub fn findNativeRuntimeInPackage(
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

pub fn nativeModuleManifestPath(allocator: Allocator, io: Io, module_directory: []const u8) !?[]const u8 {
    try ModuleManifest.rejectLegacyInDirectory(allocator, io, module_directory);
    const path = try ModuleManifest.manifestPath(allocator, module_directory);
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
