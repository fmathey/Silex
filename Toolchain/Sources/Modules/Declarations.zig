const Types = @import("Types.zig");
const Support = @import("Support.zig");
const std = Types.std;
const Ast = Types.Ast;
const ProjectModule = Types.ProjectModule;
const Source = Types.Source;
const Allocator = Types.Allocator;
const File = Types.File;
const Kind = Types.Kind;
const VisitState = Types.VisitState;
const Declaration = Types.Declaration;
const Export = Types.Export;
const ModuleBinding = Types.ModuleBinding;
const QualifiedTarget = Types.QualifiedTarget;
const Dependency = Types.Dependency;
const UseBinding = Types.UseBinding;
const FileInfo = Types.FileInfo;
const pathHasQualifier = Support.pathHasQualifier;
const sourceFileIndex = Support.sourceFileIndex;
const appendFunctions = Support.appendFunctions;
const appendProtocolReferences = Support.appendProtocolReferences;
const lastSegment = Support.lastSegment;
const parentModuleName = Support.parentModuleName;
const sameModuleParent = Support.sameModuleParent;
const moduleUseAt = Support.moduleUseAt;
const moduleBindingAt = Support.moduleBindingAt;
const loadOnlyUseAt = Support.loadOnlyUseAt;
const declarationPositions = Support.declarationPositions;
const typeNameToReturnType = Support.typeNameToReturnType;
pub fn transformExtension(self: anytype, extension: Ast.Extension, declaring_module_index: usize) !Ast.Extension {
    const declaration = try self.resolveName(extension.position.file, extension.target, .structure, extension.target_position);
    const target_is_class = self.declarationIsClass(declaration);
    var conformances: std.ArrayList(Ast.ProtocolReference) = .empty;
    const conformance_visible_files = try self.extensionVisibleFiles(
        declaring_module_index,
        extension.position.file,
        true,
    );
    for (extension.conformances) |conformance| {
        const protocol = try self.resolveName(extension.position.file, conformance.name, .protocol, conformance.position);
        try conformances.append(self.allocator, .{
            .name = protocol.canonical_name,
            .position = conformance.position,
            .extension_visible_files = conformance_visible_files,
            .extension_module_name = self.project.modules[declaring_module_index].name,
        });
    }
    var methods: std.ArrayList(Ast.Function) = .empty;
    for (extension.methods) |method| {
        const previous_type_parameters = self.current_type_parameters;
        self.current_type_parameters = method.type_parameters;
        defer self.current_type_parameters = previous_type_parameters;
        var transformed = try self.transformFunctionBody(method, method.name);
        transformed.type_parameters = try self.transformTypeParameters(method.type_parameters);
        if (transformed.member_visibility == null) {
            transformed.member_visibility = if (target_is_class) .private_access else .public_access;
            if (!target_is_class) transformed.is_public = true;
        }
        transformed.extension_visible_files = try self.extensionVisibleFiles(
            declaring_module_index,
            extension.position.file,
            transformed.is_public,
        );
        transformed.extension_module_name = self.project.modules[declaring_module_index].name;
        try methods.append(self.allocator, transformed);
    }
    var result = extension;
    result.target = declaration.canonical_name;
    result.conformances = try conformances.toOwnedSlice(self.allocator);
    result.methods = try methods.toOwnedSlice(self.allocator);
    return result;
}

pub fn extensionVisibleFiles(
    self: anytype,
    declaring_module_index: usize,
    declaring_file_index: usize,
    is_public: bool,
) ![]const usize {
    var result: std.ArrayList(usize) = .empty;
    for (self.file_infos) |file| {
        var visible = file.module_index == declaring_module_index;
        if (!visible and is_public) {
            for (self.files[file.file_index].activated_files) |activated_file| {
                if (activated_file == declaring_file_index) {
                    visible = true;
                    break;
                }
            }
        }
        if (visible) try result.append(self.allocator, file.file_index);
    }
    return result.toOwnedSlice(self.allocator);
}

pub fn collectDeclarations(self: anytype) !void {
    for (self.files) |file| {
        const module_name = self.project.modules[file.module_index].name;
        for (file.program.enums) |enum_value| {
            try self.addDeclaration(file.module_index, module_name, enum_value.name, .structure, enum_value.is_public, enum_value.name_position);
        }
        for (file.program.protocols) |protocol| {
            try self.addDeclaration(file.module_index, module_name, protocol.name, .protocol, protocol.is_public, protocol.name_position);
        }
        for (file.program.structures) |structure| {
            try self.addDeclaration(file.module_index, module_name, structure.name, .structure, structure.is_public, structure.name_position);
        }
        for (file.program.functions) |function| {
            const canonical = if (self.project.single_file or
                (file.module_index == self.project.target_module and std.mem.eql(u8, function.name, "main")))
                function.name
            else if (std.mem.eql(u8, function.name, lastSegment(module_name)))
                module_name
            else
                try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, function.name });
            try self.addDeclarationWithCanonical(file.module_index, function.name, canonical, .function, function.is_public, function.name_position);
        }
        for (file.program.uses) |use_value| switch (use_value.target) {
            .declaration => {},
            .type => |aliased_type| {
                const source_name = use_value.alias.?;
                const canonical = if (self.project.single_file)
                    source_name
                else if (std.mem.eql(u8, source_name, lastSegment(module_name)))
                    module_name
                else
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, source_name });
                try self.declarations.append(self.allocator, .{
                    .module_index = file.module_index,
                    .source_name = source_name,
                    .canonical_name = canonical,
                    .kind = .type_alias,
                    .is_public = use_value.is_public,
                    .position = use_value.position,
                    .aliased_type = aliased_type,
                });
            },
        };
    }
    for (self.declarations.items) |*declaration| {
        if (declaration.is_public) try self.addExport(declaration.module_index, declaration.source_name, declaration, declaration.position);
    }
}

pub fn addDeclaration(
    self: anytype,
    module_index: usize,
    module_name: []const u8,
    source_name: []const u8,
    kind: Kind,
    is_public: bool,
    position: Source.Position,
) !void {
    const canonical = if (self.project.single_file)
        source_name
    else if (std.mem.eql(u8, source_name, lastSegment(module_name)))
        module_name
    else
        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, source_name });
    try self.addDeclarationWithCanonical(module_index, source_name, canonical, kind, is_public, position);
}

pub fn addDeclarationWithCanonical(
    self: anytype,
    module_index: usize,
    source_name: []const u8,
    canonical_name: []const u8,
    kind: Kind,
    is_public: bool,
    position: Source.Position,
) !void {
    if ((kind == .structure or kind == .protocol or kind == .type_alias) and std.mem.eql(u8, source_name, "Result")) {
        return self.fail(position, "name 'Result' is reserved");
    }
    if (kind == .function and std.mem.eql(u8, source_name, "map_error")) {
        return self.fail(position, "name 'map_error' is reserved");
    }
    for (self.declarations.items) |existing| {
        if (existing.kind == .type_alias) continue;
        if (existing.module_index == module_index and std.mem.eql(u8, existing.source_name, source_name)) {
            if (existing.kind == .function and kind == .function) continue;
            const message = try std.fmt.allocPrint(self.allocator, "{s} '{s}' is already declared in module '{s}'", .{
                @tagName(kind), source_name, self.project.modules[module_index].name,
            });
            return self.fail(position, message);
        }
    }
    try self.declarations.append(self.allocator, .{
        .module_index = module_index,
        .source_name = source_name,
        .canonical_name = canonical_name,
        .kind = kind,
        .is_public = is_public,
        .position = position,
    });
}

pub fn collectModuleBindings(self: anytype) !void {
    var infos = try self.allocator.alloc(FileInfo, self.files.len);
    for (self.files, 0..) |file, file_index| {
        var module_bindings: std.ArrayList(ModuleBinding) = .empty;
        for (file.program.uses) |use_value| {
            if (loadOnlyUseAt(self.files[file_index], use_value.position)) continue;
            const path = switch (use_value.target) {
                .declaration => |value| value,
                .type => continue,
            };
            const module_index = (try self.moduleIndexFromUsePath(module_bindings.items, path)) orelse
                self.siblingModuleIndex(file.module_index, path) orelse continue;
            if (use_value.is_public) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "module '{s}' cannot be re-exported with 'public use'",
                    .{self.project.modules[module_index].name},
                );
                return self.fail(use_value.position, message);
            }
            if (module_index == file.module_index) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "module '{s}' cannot use itself",
                    .{self.project.modules[module_index].name},
                );
                return self.fail(use_value.position, message);
            }
            const qualifier = use_value.alias orelse lastSegment(path);
            for (module_bindings.items) |existing| {
                if (std.mem.eql(u8, existing.qualifier, qualifier)) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "module qualifier '{s}' is already declared",
                        .{qualifier},
                    );
                    return self.fail(use_value.position, message);
                }
            }
            if (self.findDirect(file.module_index, qualifier, null) != null) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "module qualifier '{s}' collides with a module declaration",
                    .{qualifier},
                );
                return self.fail(use_value.position, message);
            }
            try module_bindings.append(self.allocator, .{
                .module_index = module_index,
                .qualifier = qualifier,
                .position = use_value.position,
            });
        }
        infos[file_index] = .{
            .file_index = file_index,
            .module_index = file.module_index,
            .program = file.program,
            .module_bindings = try module_bindings.toOwnedSlice(self.allocator),
        };
        for (infos[file_index].module_bindings) |binding| {
            try infos[file_index].dependencies.append(self.allocator, .{
                .module_index = binding.module_index,
                .position = binding.position,
            });
        }
        for (file.dependency_modules) |module_index| {
            if (module_index == file.module_index) continue;
            var present = false;
            for (infos[file_index].dependencies.items) |dependency| {
                if (dependency.module_index == module_index) {
                    present = true;
                    break;
                }
            }
            if (!present) try infos[file_index].dependencies.append(self.allocator, .{
                .module_index = module_index,
                .position = .{ .file = file_index, .line = 1, .column = 1 },
            });
        }
        for (file.program.uses) |use_value| {
            if (loadOnlyUseAt(self.files[file_index], use_value.position)) continue;
            if (moduleUseAt(&infos[file_index], use_value.position)) continue;
            const path = switch (use_value.target) {
                .declaration => |value| value,
                .type => |aliased_type| {
                    try self.appendTypeDependencies(&infos[file_index], aliased_type, use_value.position);
                    continue;
                },
            };
            const target = try self.qualifiedUseTarget(&infos[file_index], path) orelse continue;
            const module_index = target.module_index;
            if (module_index == file.module_index) continue;
            try infos[file_index].dependencies.append(self.allocator, .{
                .module_index = module_index,
                .position = use_value.position,
            });
        }
    }
    self.file_infos = infos;
}

pub fn appendTypeDependencies(
    self: anytype,
    file: *FileInfo,
    type_name: Ast.TypeName,
    position: Source.Position,
) !void {
    switch (type_name) {
        .structure => |name| try self.appendNamedTypeDependency(file, name, position),
        .generic_structure => |generic| {
            try self.appendNamedTypeDependency(file, generic.name, position);
            for (generic.arguments) |argument| try self.appendTypeDependencies(file, argument, position);
        },
        .list, .optional => |contained| try self.appendTypeDependencies(file, contained.*, position),
        .fixed_array => |array| try self.appendTypeDependencies(file, array.element.*, position),
        .reference => |reference| try self.appendTypeDependencies(file, reference.target.*, position),
        .function => |function| {
            for (function.parameters) |parameter| try self.appendTypeDependencies(file, parameter, position);
            if (function.return_type) |return_type| try self.appendTypeDependencies(file, return_type.*, position);
        },
        else => {},
    }
}

pub fn appendNamedTypeDependency(
    self: anytype,
    file: *FileInfo,
    name: []const u8,
    position: Source.Position,
) !void {
    if (std.mem.indexOfScalar(u8, name, '.') == null) return;
    const target = try self.qualifiedUseTarget(file, name) orelse return;
    if (target.module_index == file.module_index) return;
    try file.dependencies.append(self.allocator, .{
        .module_index = target.module_index,
        .position = position,
    });
}

pub fn moduleOrder(self: anytype) ![]const usize {
    const states = try self.allocator.alloc(VisitState, self.project.modules.len);
    @memset(states, .fresh);
    var stack: std.ArrayList(usize) = .empty;
    var result: std.ArrayList(usize) = .empty;
    for (0..self.project.modules.len) |module_index| try self.visitModule(module_index, states, &stack, &result);
    return result.toOwnedSlice(self.allocator);
}

pub fn visitModule(
    self: anytype,
    module_index: usize,
    states: []VisitState,
    stack: *std.ArrayList(usize),
    result: *std.ArrayList(usize),
) !void {
    if (states[module_index] == .done) return;
    if (states[module_index] == .visiting) {
        var message: std.ArrayList(u8) = .empty;
        try message.appendSlice(self.allocator, "module dependency cycle: ");
        var started = false;
        for (stack.items) |entry| {
            if (entry == module_index) started = true;
            if (started) try message.appendSlice(
                self.allocator,
                try std.fmt.allocPrint(self.allocator, "{s} -> ", .{self.project.modules[entry].name}),
            );
        }
        try message.appendSlice(self.allocator, self.project.modules[module_index].name);
        const position = self.firstDependencyPosition(stack.items[stack.items.len - 1], module_index);
        return self.fail(position, try message.toOwnedSlice(self.allocator));
    }
    states[module_index] = .visiting;
    try stack.append(self.allocator, module_index);
    for (self.file_infos) |file| if (file.module_index == module_index) {
        for (file.dependencies.items) |dependency| {
            if (dependency.module_index != module_index) {
                const is_sibling_cycle = states[dependency.module_index] == .visiting and
                    self.project.modules[dependency.module_index].package_index ==
                        self.project.modules[module_index].package_index and
                    sameModuleParent(
                        self.project.modules[dependency.module_index].name,
                        self.project.modules[module_index].name,
                    );
                if (is_sibling_cycle) continue;
                try self.visitModule(dependency.module_index, states, stack, result);
            }
        }
    };
    _ = stack.pop();
    states[module_index] = .done;
    try result.append(self.allocator, module_index);
}

pub fn firstDependencyPosition(self: anytype, from: usize, to: usize) Source.Position {
    for (self.file_infos) |file| if (file.module_index == from) {
        for (file.dependencies.items) |dependency| if (dependency.module_index == to) return dependency.position;
    };
    return .{ .line = 1, .column = 1 };
}

pub fn collectModuleUses(self: anytype, module_index: usize) !void {
    try self.collectModuleTypeAliases(module_index);
    try self.collectModuleUsesWithVisibility(module_index, true);
    try self.collectModuleUsesWithVisibility(module_index, false);
}

pub fn collectModuleTypeAliases(self: anytype, module_index: usize) !void {
    for (self.file_infos) |*file| {
        if (file.module_index != module_index) continue;
        for (file.program.uses) |use_value| switch (use_value.target) {
            .declaration => {},
            .type => {
                const local_name = use_value.alias.?;
                try self.validateLocalBinding(file, local_name, use_value.position);
                const declaration = self.findDirectByPosition(use_value.position, .type_alias).?;
                try file.uses.append(self.allocator, .{
                    .local_name = local_name,
                    .declaration = declaration,
                    .position = use_value.position,
                });
            },
        };
    }
}

pub fn collectModuleUsesWithVisibility(self: anytype, module_index: usize, is_public: bool) !void {
    for (self.file_infos) |*file| {
        if (file.module_index != module_index) continue;
        for (file.program.uses) |use_value| {
            if (loadOnlyUseAt(self.files[file.file_index], use_value.position)) continue;
            if (use_value.is_public != is_public) continue;
            const path = switch (use_value.target) {
                .declaration => |value| value,
                .type => continue,
            };
            if (moduleUseAt(file, use_value.position)) {
                if (is_public) continue;
                const binding = moduleBindingAt(file, use_value.position) orelse unreachable;
                const module_name = self.project.modules[binding.module_index].name;
                const principal_name = lastSegment(module_name);
                var principals: std.ArrayList(*const Declaration) = .empty;
                for (self.declarations.items) |*declaration| {
                    if (declaration.module_index == binding.module_index and
                        declaration.is_public and
                        std.mem.eql(u8, declaration.source_name, principal_name) and
                        std.mem.eql(u8, declaration.canonical_name, module_name))
                    {
                        try principals.append(self.allocator, declaration);
                    }
                }
                if (principals.items.len != 0) {
                    const local_name = use_value.alias orelse lastSegment(path);
                    try self.validateIntroducedName(file, local_name, use_value.position);
                    for (principals.items) |declaration| try file.uses.append(self.allocator, .{
                        .local_name = local_name,
                        .declaration = declaration,
                        .position = use_value.position,
                    });
                }
                continue;
            }
            const declarations = try self.resolveUses(file, path, use_value.position);
            const local_name = use_value.alias orelse lastSegment(path);
            try self.validateLocalBinding(file, local_name, use_value.position);
            for (declarations) |declaration| {
                try file.uses.append(self.allocator, .{
                    .local_name = local_name,
                    .declaration = declaration,
                    .position = use_value.position,
                });
                if (is_public) try self.addExport(module_index, local_name, declaration, use_value.position);
            }
        }
    }
}

pub fn validateLocalBinding(self: anytype, file: *const FileInfo, name: []const u8, position: Source.Position) !void {
    try self.validateIntroducedName(file, name, position);
    for (file.module_bindings) |binding| if (std.mem.eql(u8, binding.qualifier, name)) {
        const message = try std.fmt.allocPrint(self.allocator, "name '{s}' collides with a module alias", .{name});
        return self.fail(position, message);
    };
}

pub fn validateIntroducedName(self: anytype, file: *const FileInfo, name: []const u8, position: Source.Position) !void {
    if (std.mem.eql(u8, name, "Result")) return self.fail(position, "name 'Result' is reserved");
    if (std.mem.eql(u8, name, "map_error")) return self.fail(position, "name 'map_error' is reserved");
    for (file.uses.items) |existing| if (std.mem.eql(u8, existing.local_name, name)) {
        const message = try std.fmt.allocPrint(self.allocator, "name '{s}' is already introduced by use", .{name});
        return self.fail(position, message);
    };
    if (self.findDirect(file.module_index, name, null) != null) {
        const message = try std.fmt.allocPrint(self.allocator, "name '{s}' collides with a module declaration", .{name});
        return self.fail(position, message);
    }
}

pub fn addExport(self: anytype, module_index: usize, name: []const u8, declaration: *const Declaration, position: Source.Position) !void {
    for (self.exports.items) |existing| {
        if (existing.module_index == module_index and std.mem.eql(u8, existing.public_name, name)) {
            if (existing.declaration == declaration) return;
            if (existing.declaration.kind == .function and declaration.kind == .function) continue;
            const message = try std.fmt.allocPrint(self.allocator, "public name '{s}' is ambiguous in module '{s}'", .{
                name, self.project.modules[module_index].name,
            });
            return self.fail(position, message);
        }
    }
    try self.exports.append(self.allocator, .{
        .module_index = module_index,
        .public_name = name,
        .declaration = declaration,
        .position = position,
    });
}

pub fn validateNamespaceCollisions(self: anytype) !void {
    for (self.declarations.items) |declaration| {
        if (std.mem.eql(u8, declaration.canonical_name, self.project.modules[declaration.module_index].name)) continue;
        if (self.findModule(declaration.canonical_name) == null) continue;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "declaration '{s}' collides with namespace '{s}'",
            .{ declaration.canonical_name, declaration.canonical_name },
        );
        return self.fail(declaration.position, message);
    }
    for (self.file_infos) |file| {
        const module_name = self.project.modules[file.module_index].name;
        const principal_name = lastSegment(module_name);
        for (file.program.enums) |enum_value| {
            if (!std.mem.eql(u8, enum_value.name, principal_name)) continue;
            for (enum_value.variants) |variant| {
                try self.validatePrincipalMemberCollision(
                    file.module_index,
                    module_name,
                    variant.name,
                    variant.position,
                );
            }
        }
        for (file.program.structures) |structure| {
            if (!std.mem.eql(u8, structure.name, principal_name)) continue;
            for (structure.fields) |field| {
                if (field.is_static) try self.validatePrincipalMemberCollision(file.module_index, module_name, field.name, field.position);
            }
            for (structure.methods) |method| {
                if (method.is_static) try self.validatePrincipalMemberCollision(file.module_index, module_name, method.name, method.name_position);
            }
        }
    }
}

pub fn validatePrincipalMemberCollision(
    self: anytype,
    module_index: usize,
    module_name: []const u8,
    member_name: []const u8,
    position: Source.Position,
) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, member_name });
    if (self.findModule(path) == null and self.findDirect(module_index, member_name, null) == null) return;
    return self.fail(position, try std.fmt.allocPrint(
        self.allocator,
        "static member '{s}' of principal declaration '{s}' collides with namespace or declaration '{s}'",
        .{ member_name, module_name, path },
    ));
}
