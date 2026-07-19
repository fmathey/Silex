const std = @import("std");
const Ast = @import("Ast.zig");
const LexerModule = @import("Lexer.zig");
const ModuleDiscovery = @import("ModuleDiscovery.zig");
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

const UnitSource = struct {
    name: []const u8,
    path: []const u8,
};

const UnitTarget = struct {
    module_index: usize,
    source_index: usize,
};

const Selection = union(enum) {
    module: usize,
    units: struct {
        items: []const UnitTarget,
        load_only: bool,
    },
};

const FileState = struct {
    use_edges: std.ArrayList(usize) = .empty,
    activation_roots: std.ArrayList(usize) = .empty,
    load_only_uses: std.ArrayList(Source.Position) = .empty,
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
    file_states: std.ArrayList(FileState) = .empty,
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
                "module '{s}' has multiple source units named '{s}'",
                .{ module_name, unit_name },
            ));
        };
        try sources.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, unit_name),
            .path = source_path,
        });
    }

    fn ensureCatalog(self: *Loader, module: *ModuleBuilder, position: Source.Position) !void {
        if (module.catalog_complete) return;
        const directory_path = if (module.package_name) |name|
            try packageModulePath(self.allocator, module.module_root, name, module.name)
        else
            try localModulePath(self.allocator, module.module_root, module.name);
        var directory = Io.Dir.cwd().openDir(self.io, directory_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return self.moduleNotFound(position, module.name, directory_path, null),
            else => |other| return other,
        };
        defer directory.close(self.io);
        var names: std.ArrayList([]const u8) = .empty;
        var iterator = directory.iterateAssumeFirstIteration();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) {
                try names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
            }
        }
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.lessThan);
        for (names.items) |name| try self.addAvailableSource(
            &module.available_sources,
            try std.fs.path.join(self.allocator, &.{ directory_path, name }),
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
            return .{ .module = try self.ensureNamedModule(
                modules,
                project_root,
                canonical_path,
                position,
                loads_local_modules,
                package_index,
            ) };
        }

        if (std.mem.indexOfScalar(u8, canonical_path, '.') == null) {
            if (self.package_graph.?.explicit and
                self.package_graph.?.findPackage(canonical_path) != null and
                self.package_graph.?.directDependency(package_index, canonical_path) == null)
            {
                try self.transitiveVisibilityError(position, package_index, canonical_path);
                unreachable;
            }
            return self.resolveUnitOrDeclaration(modules, current_module_index, canonical_path, position, true);
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
            return self.resolveUnitOrDeclaration(
                modules,
                module_index,
                remainder,
                position,
                module_index == current_module_index,
            );
        }
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "unknown use target '{s}'",
            .{canonical_path},
        ));
    }

    fn resolveUnitOrDeclaration(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        module_index: usize,
        name: []const u8,
        position: Source.Position,
        same_module: bool,
    ) !Selection {
        if (!modules.items[module_index].catalog_complete) {
            const module = &modules.items[module_index];
            const directory_path = if (module.package_name) |package_name|
                try packageModulePath(self.allocator, module.module_root, package_name, module.name)
            else
                try localModulePath(self.allocator, module.module_root, module.name);
            const filename = try std.fmt.allocPrint(self.allocator, "{s}.sx", .{name});
            const exact_path = try std.fs.path.join(self.allocator, &.{ directory_path, filename });
            const stat = Io.Dir.cwd().statFile(self.io, exact_path, .{}) catch null;
            if (stat != null and stat.?.kind == .file) {
                try self.addAvailableSource(&module.available_sources, exact_path, position, module.name);
                const source_index = module.available_sources.items.len - 1;
                const homonymous = try self.unitDeclares(exact_path, name, !same_module);
                return .{ .units = .{
                    .items = try self.allocator.dupe(UnitTarget, &.{.{
                        .module_index = module_index,
                        .source_index = source_index,
                    }}),
                    .load_only = same_module or !homonymous,
                } };
            }
        }
        try self.ensureCatalog(&modules.items[module_index], position);
        const exact_unit = findUnit(modules.items[module_index].available_sources.items, name);
        var declarations: std.ArrayList(UnitTarget) = .empty;
        for (modules.items[module_index].available_sources.items, 0..) |unit, source_index| {
            if (try self.unitDeclares(unit.path, name, !same_module)) try declarations.append(self.allocator, .{
                .module_index = module_index,
                .source_index = source_index,
            });
        }
        if (exact_unit) |source_index| {
            for (declarations.items) |declaration| if (declaration.source_index != source_index) {
                return self.fail(position, try std.fmt.allocPrint(
                    self.allocator,
                    "use target '{s}.{s}' is ambiguous between source unit '{s}' and a declaration from another unit",
                    .{ modules.items[module_index].name, name, name },
                ));
            };
            const homonymous = for (declarations.items) |declaration| {
                if (declaration.source_index == source_index) break true;
            } else false;
            return .{ .units = .{
                .items = try self.allocator.dupe(UnitTarget, &.{.{
                    .module_index = module_index,
                    .source_index = source_index,
                }}),
                .load_only = same_module or !homonymous,
            } };
        }
        if (declarations.items.len != 0) return .{ .units = .{
            .items = try declarations.toOwnedSlice(self.allocator),
            .load_only = false,
        } };
        if (same_module) return .{ .units = .{
            .items = &.{},
            .load_only = false,
        } };
        return self.fail(position, try std.fmt.allocPrint(
            self.allocator,
            "module '{s}' has no source unit or selectable declaration '{s}'",
            .{ modules.items[module_index].name, name },
        ));
    }

    fn unitDeclares(self: *Loader, source_path: []const u8, name: []const u8, public_only: bool) !bool {
        const source = Io.Dir.cwd().readFileAlloc(self.io, source_path, self.allocator, .limited(16 * 1024 * 1024)) catch return false;
        if (public_only) {
            var lines = std.mem.splitScalar(u8, source, '\n');
            while (lines.next()) |source_line| {
                const line = std.mem.trim(u8, source_line, " \t\r");
                if (!std.mem.startsWith(u8, line, "pub use ")) continue;
                const declaration = line["pub use ".len..];
                const alias_marker = std.mem.indexOf(u8, declaration, " as ");
                const exported_name = if (alias_marker) |index|
                    std.mem.trim(u8, declaration[index + " as ".len ..], " \t\r")
                else block: {
                    const target_end = std.mem.indexOfAny(u8, declaration, " <\t\r") orelse declaration.len;
                    break :block lastSegment(declaration[0..target_end]);
                };
                if (std.mem.eql(u8, exported_name, name)) return true;
            }
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
            if (token.tag == .keyword_pub) {
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
                try self.selectLongestQualifiedTarget(
                    modules,
                    project_root,
                    canonical,
                    tokens.items[index].position,
                    loads_local_modules,
                    package_index,
                    file.module_index,
                );
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
    ) !void {
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
                    const separator = std.mem.lastIndexOfScalar(u8, candidate, '.') orelse return;
                    candidate = candidate[0..separator];
                    continue;
                },
                else => |other| return other,
            };
            _ = try self.selectSelection(modules, selection, position);
            return;
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
            if (loads_local_modules) {
                const local_path = try localModulePath(self.allocator, project_root, module_name);
                if (try isDirectory(self.io, local_path)) {
                    const library_root = StandardLibrary.root(self.allocator, self.io) catch {
                        return self.loadDistributedModule(modules, module_name, position);
                    };
                    const distributed_path = try localModulePath(self.allocator, library_root, module_name);
                    if (try isDirectory(self.io, distributed_path)) {
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
        try self.files.append(self.allocator, .{
            .module_index = module_index,
            .unit_name = unit_name,
            .program = program,
        });
        try self.file_states.append(self.allocator, .{});
        return file_index;
    }

    fn finishActivationClosures(self: *Loader) !void {
        for (self.files.items, 0..) |*file, file_index| {
            var activated: std.ArrayList(usize) = .empty;
            for (self.file_states.items[file_index].activation_roots.items) |root| {
                const activation_module = self.files.items[root].module_index;
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
                        if (self.files.items[dependency].module_index == activation_module) {
                            try pending.append(self.allocator, dependency);
                        }
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

fn findModule(modules: []const ModuleBuilder, name: []const u8) ?usize {
    for (modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, name)) return index;
    }
    return null;
}

fn findUnit(sources: []const UnitSource, name: []const u8) ?usize {
    for (sources, 0..) |source, index| {
        if (std.mem.eql(u8, source.name, name)) return index;
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

fn canonicalAliasedPath(
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

test "native runtime uses @Module.json and ignores metadata-only or incorrectly cased manifests" {
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

test "use paths expand module aliases" {
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

test "source unit selection loads only its transitive sibling closure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App","modules":[
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
        .data = "use Internal\nuse AlphaExtensions\npub struct Alpha { static func value() int { return helper() } }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Internal.sx",
        .data = "func helper() int { return 42 }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "AlphaExtensions.sx",
        .data = "use Alpha\nextend Alpha { pub func doubled() int { return 84 } }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Broken.sx",
        .data = "pub struct Broken {\n",
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

test "a differently named declaration selects its providing source unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App","modules":[
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
        .data = "pub struct Renamed {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Neighbor.sx",
        .data = "pub struct Neighbor {}\n",
    });

    var environ = EnvironMap.init(allocator);
    const project_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path, "project.json" });
    var loader = Loader.init(allocator, std.testing.io, &environ);
    const loaded = try loader.load(project_path);

    try std.testing.expectEqual(@as(usize, 2), loaded.files.len);
    try std.testing.expectEqualStrings("API", loaded.files[1].unit_name);
}

test "a source unit and declaration from another unit are ambiguous" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data =
        \\{"target":"App","modules":[
        \\  {"name":"Lib","sources":["Thing.sx","Other.sx"]},
        \\  {"name":"App","sources":["Main.sx"]}
        \\]}
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = "use Lib.Thing\nfunc main() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Thing.sx", .data = "func helper() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Other.sx", .data = "pub struct Thing {}\n" });

    var environ = EnvironMap.init(allocator);
    const project_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path, "project.json" });
    var loader = Loader.init(allocator, std.testing.io, &environ);
    try std.testing.expectError(error.InvalidSource, loader.load(project_path));
    try std.testing.expect(std.mem.indexOf(u8, loader.diagnostic.?.message, "is ambiguous") != null);
}
