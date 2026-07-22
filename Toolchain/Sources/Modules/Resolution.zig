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
pub fn resolveUses(
    self: anytype,
    file: *const FileInfo,
    path: []const u8,
    position: Source.Position,
) ![]const *const Declaration {
    if (std.mem.lastIndexOfScalar(u8, path, '.') == null) {
        var used: std.ArrayList(*const Declaration) = .empty;
        for (file.uses.items) |binding| {
            if (std.mem.eql(u8, binding.local_name, path)) try used.append(self.allocator, binding.declaration);
        }
        if (used.items.len != 0) return used.toOwnedSlice(self.allocator);
        const declarations = try self.declarationsNamed(file.module_index, path, null, false);
        if (declarations.len != 0) return declarations;
        const message = try std.fmt.allocPrint(self.allocator, "unknown declaration '{s}'", .{path});
        return self.fail(position, message);
    }
    const target = try self.qualifiedUseTarget(file, path) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown declaration '{s}'", .{path});
        return self.fail(position, message);
    };
    const is_current = target.module_index == file.module_index;
    const internal_access = self.internalAccess(file, target.module_index);
    const declarations = try self.declarationsNamed(
        target.module_index,
        target.public_name,
        null,
        !is_current and !internal_access,
    );
    if (declarations.len != 0) return declarations;
    if (!is_current and !internal_access and
        (try self.declarationsNamed(target.module_index, target.public_name, null, false)).len != 0)
    {
        const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
            target.public_name, self.project.modules[target.module_index].name,
        });
        return self.fail(position, message);
    }
    const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
        self.project.modules[target.module_index].name, target.public_name,
    });
    return self.fail(position, message);
}

pub fn expressionPath(self: anytype, expression: *const Ast.Expression) !?[]const u8 {
    return switch (expression.value) {
        .identifier => |name| name,
        .member_access => |member| if (try self.expressionPath(member.object)) |prefix|
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name })
        else
            null,
        else => null,
    };
}

pub fn staticOwnerType(
    self: anytype,
    file_index: usize,
    path: []const u8,
    position: Source.Position,
) !?Ast.TypeName {
    const head_end = std.mem.indexOfScalar(u8, path, '.') orelse path.len;
    if (self.findLocal(path[0..head_end])) return null;
    if (try self.visibleTypeAlias(file_index, path)) |alias| return @as(?Ast.TypeName, try self.resolveAliasType(alias));
    if ((try self.visibleDeclarationKind(file_index, path)) != .structure) return null;
    const declaration = try self.resolveName(file_index, path, .structure, position);
    return .{ .structure = declaration.canonical_name };
}

pub fn looksQualified(self: anytype, file_index: usize, path: []const u8) bool {
    const file = self.file_infos[file_index];
    for (file.module_bindings) |binding| {
        if (pathHasQualifier(path, binding.qualifier)) return true;
    }
    return pathHasQualifier(path, self.project.modules[file.module_index].name);
}

pub fn visibleDeclarationKind(self: anytype, file_index: usize, name: []const u8) !?Kind {
    const file = &self.file_infos[file_index];
    if (std.mem.indexOfScalar(u8, name, '.') == null) {
        if (self.findDirect(file.module_index, name, null)) |declaration| return declaration.kind;
        for (file.uses.items) |binding| {
            if (std.mem.eql(u8, binding.local_name, name)) return binding.declaration.kind;
        }
        return null;
    }
    const target = try self.qualifiedExpressionTarget(file, name) orelse return null;
    if (self.findDirect(target.module_index, target.public_name, null)) |declaration| return declaration.kind;
    return null;
}

pub fn visibleFunctionDeclarations(
    self: anytype,
    file_index: usize,
    name: []const u8,
    position: Source.Position,
) ![]const *const Declaration {
    const file = &self.file_infos[file_index];
    if (std.mem.indexOfScalar(u8, name, '.') == null) {
        const direct = try self.declarationsNamed(file.module_index, name, .function, false);
        if (direct.len != 0) return direct;
        var used: std.ArrayList(*const Declaration) = .empty;
        for (file.uses.items) |binding| {
            if (binding.declaration.kind == .function and std.mem.eql(u8, binding.local_name, name)) {
                try used.append(self.allocator, binding.declaration);
            }
        }
        if (used.items.len != 0) return used.toOwnedSlice(self.allocator);
        _ = try self.resolveName(file_index, name, .function, position);
        unreachable;
    }

    if (try self.qualifiedExpressionTarget(file, name)) |target| {
        const private_access = self.internalAccess(file, target.module_index);
        const declarations = try self.declarationsNamed(
            target.module_index,
            target.public_name,
            .function,
            !private_access,
        );
        if (declarations.len != 0) return declarations;
    }
    _ = try self.resolveName(file_index, name, .function, position);
    unreachable;
}

pub fn resolveName(self: anytype, file_index: usize, name: []const u8, kind: Kind, position: Source.Position) !*const Declaration {
    const file = &self.file_infos[file_index];
    if (std.mem.indexOfScalar(u8, name, '.') != null) return self.resolveQualified(file, name, kind, position);
    if (self.findDirect(file.module_index, name, kind)) |declaration| return declaration;
    for (file.uses.items) |binding| {
        if (std.mem.eql(u8, binding.local_name, name) and binding.declaration.kind == kind) return binding.declaration;
    }
    if (kind == .protocol) {
        if (self.findDirect(file.module_index, name, null) != null) {
            return self.fail(position, try std.fmt.allocPrint(self.allocator, "declaration '{s}' is not a protocol", .{name}));
        }
        for (file.uses.items) |binding| {
            if (std.mem.eql(u8, binding.local_name, name)) {
                return self.fail(position, try std.fmt.allocPrint(self.allocator, "declaration '{s}' is not a protocol", .{name}));
            }
        }
    }
    const label = switch (kind) {
        .structure => "type",
        .protocol => "protocol",
        .function => "function",
        .type_alias => "type alias",
    };
    const message = try std.fmt.allocPrint(self.allocator, "unknown {s} '{s}'", .{ label, name });
    return self.fail(position, message);
}

pub fn resolveQualified(
    self: anytype,
    file: *const FileInfo,
    path: []const u8,
    kind: ?Kind,
    position: Source.Position,
) !*const Declaration {
    if (try self.qualifiedExpressionTarget(file, path)) |target| {
        if (std.mem.indexOfScalar(u8, target.public_name, '.') != null) {
            return self.fail(
                position,
                try std.fmt.allocPrint(self.allocator, "unknown qualified path '{s}'", .{path}),
            );
        }
        const internal_access = self.internalAccess(file, target.module_index);
        if (target.module_index == file.module_index or internal_access) {
            if (self.findDirect(target.module_index, target.public_name, kind)) |declaration| return declaration;
        } else if (self.findExport(target.module_index, target.public_name, kind)) |export_value| {
            return export_value.declaration;
        }
        if (target.module_index != file.module_index and self.findDirect(target.module_index, target.public_name, kind) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
                target.public_name, self.project.modules[target.module_index].name,
            });
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
            self.project.modules[target.module_index].name, target.public_name,
        });
        return self.fail(position, message);
    }
    for (self.project.modules, 0..) |module, module_index| {
        if (pathHasQualifier(path, module.name) and module_index != file.module_index) {
            const message = try std.fmt.allocPrint(self.allocator, "module '{s}' is not used in this file", .{module.name});
            return self.fail(position, message);
        }
    }
    const message = try std.fmt.allocPrint(self.allocator, "unknown qualified path '{s}'", .{path});
    return self.fail(position, message);
}

pub fn moduleIndexFromUsePath(
    self: anytype,
    bindings: []const ModuleBinding,
    path: []const u8,
) !?usize {
    if (try self.canonicalPathFromBindings(bindings, path)) |canonical| {
        return self.findModule(canonical);
    }
    return self.findModule(path);
}

pub fn siblingModuleIndex(self: anytype, current_module_index: usize, name: []const u8) ?usize {
    if (std.mem.indexOfScalar(u8, name, '.') != null) return null;
    const parent = parentModuleName(self.project.modules[current_module_index].name) orelse return null;
    for (self.project.modules, 0..) |module, index| {
        if (!sameModuleParent(module.name, self.project.modules[current_module_index].name)) continue;
        if (std.mem.eql(u8, lastSegment(module.name), name) and
            module.package_index == self.project.modules[current_module_index].package_index)
        {
            _ = parent;
            return index;
        }
    }
    return null;
}

pub fn qualifiedUseTarget(self: anytype, file: *const FileInfo, path: []const u8) !?QualifiedTarget {
    if (try self.canonicalPathFromBindings(file.module_bindings, path)) |canonical| {
        if (self.longestModuleTarget(canonical)) |target| return target;
    }
    return self.longestModuleTarget(path);
}

pub fn qualifiedExpressionTarget(self: anytype, file: *const FileInfo, path: []const u8) !?QualifiedTarget {
    if (try self.canonicalPathFromBindings(file.module_bindings, path)) |canonical| {
        return self.longestModuleTarget(canonical);
    }
    const current_name = self.project.modules[file.module_index].name;
    if (pathHasQualifier(path, current_name)) {
        if (self.longestModuleTarget(path)) |target| return target;
    }
    return null;
}

pub fn canonicalPathFromBindings(
    self: anytype,
    bindings: []const ModuleBinding,
    path: []const u8,
) !?[]const u8 {
    var matched: ?ModuleBinding = null;
    for (bindings) |binding| {
        if (!pathHasQualifier(path, binding.qualifier)) continue;
        if (matched == null or binding.qualifier.len > matched.?.qualifier.len) matched = binding;
    }
    const binding = matched orelse return null;
    const canonical: []const u8 = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{
        self.project.modules[binding.module_index].name,
        path[binding.qualifier.len + 1 ..],
    });
    return canonical;
}

pub fn longestModuleTarget(self: anytype, canonical_path: []const u8) ?QualifiedTarget {
    for (self.project.modules, 0..) |module, module_index| {
        if (!std.mem.eql(u8, canonical_path, module.name)) continue;
        const principal_name = lastSegment(module.name);
        for (self.declarations.items) |declaration| {
            if (declaration.module_index == module_index and
                std.mem.eql(u8, declaration.source_name, principal_name) and
                std.mem.eql(u8, declaration.canonical_name, module.name))
            {
                return .{ .module_index = module_index, .public_name = principal_name };
            }
        }
        return null;
    }
    var matched_index: ?usize = null;
    for (self.project.modules, 0..) |module, module_index| {
        if (!pathHasQualifier(canonical_path, module.name)) continue;
        if (matched_index == null or module.name.len > self.project.modules[matched_index.?].name.len) {
            matched_index = module_index;
        }
    }
    const module_index = matched_index orelse return null;
    const module_name = self.project.modules[module_index].name;
    return .{
        .module_index = module_index,
        .public_name = canonical_path[module_name.len + 1 ..],
    };
}

pub fn findModule(self: anytype, name: []const u8) ?usize {
    for (self.project.modules, 0..) |module, index| if (std.mem.eql(u8, module.name, name)) return index;
    return null;
}

pub fn internalAccess(self: anytype, file: *const FileInfo, target_module_index: usize) bool {
    if (target_module_index == file.module_index) return true;
    const source = self.project.modules[file.module_index];
    const target = self.project.modules[target_module_index];
    if (source.package_index != target.package_index or !sameModuleParent(source.name, target.name)) return false;
    for (file.dependencies.items) |dependency| {
        if (dependency.module_index == target_module_index) return true;
    }
    return false;
}

pub fn declarationsNamed(
    self: anytype,
    module_index: usize,
    name: []const u8,
    kind: ?Kind,
    public_only: bool,
) ![]const *const Declaration {
    var result: std.ArrayList(*const Declaration) = .empty;
    if (public_only) {
        for (self.exports.items) |*export_value| {
            if (export_value.module_index == module_index and
                std.mem.eql(u8, export_value.public_name, name) and
                (kind == null or export_value.declaration.kind == kind.?))
            {
                try result.append(self.allocator, export_value.declaration);
            }
        }
    } else {
        for (self.declarations.items) |*declaration| {
            if (declaration.kind != .type_alias and declaration.module_index == module_index and
                std.mem.eql(u8, declaration.source_name, name) and
                (kind == null or declaration.kind == kind.?))
            {
                try result.append(self.allocator, declaration);
            }
        }
    }
    return result.toOwnedSlice(self.allocator);
}

pub fn findDirect(self: anytype, module_index: usize, name: []const u8, kind: ?Kind) ?*const Declaration {
    for (self.declarations.items) |*declaration| {
        if (kind == null and declaration.kind == .type_alias) continue;
        if (declaration.module_index == module_index and (kind == null or declaration.kind == kind.?) and
            std.mem.eql(u8, declaration.source_name, name)) return declaration;
    }
    return null;
}

pub fn findDirectByPosition(self: anytype, position: Source.Position, kind: Kind) ?*const Declaration {
    for (self.declarations.items) |*declaration| {
        if (declaration.kind == kind and declaration.position.file == position.file and
            declaration.position.line == position.line and declaration.position.column == position.column) return declaration;
    }
    return null;
}

pub fn declarationIsClass(self: anytype, declaration: *const Declaration) bool {
    if (declaration.kind != .structure) return false;
    for (self.files) |file| {
        for (file.program.structures) |structure| {
            if (structure.name_position.file == declaration.position.file and
                structure.name_position.line == declaration.position.line and
                structure.name_position.column == declaration.position.column)
            {
                return structure.is_class;
            }
        }
    }
    return false;
}

pub fn declarationHasConstructors(self: anytype, declaration: *const Declaration) bool {
    if (declaration.kind != .structure) return false;
    for (self.files) |file| {
        for (file.program.structures) |structure| {
            if (structure.name_position.file == declaration.position.file and
                structure.name_position.line == declaration.position.line and
                structure.name_position.column == declaration.position.column)
            {
                return structure.constructors.len != 0;
            }
        }
    }
    return false;
}

pub fn declarationIsEnum(self: anytype, declaration: *const Declaration) bool {
    if (declaration.kind != .structure) return false;
    for (self.files) |file| for (file.program.enums) |enum_value| {
        if (enum_value.name_position.file == declaration.position.file and
            enum_value.name_position.line == declaration.position.line and
            enum_value.name_position.column == declaration.position.column) return true;
    };
    return false;
}

pub fn findExport(self: anytype, module_index: usize, name: []const u8, kind: ?Kind) ?*const Export {
    for (self.exports.items) |*export_value| {
        if (export_value.module_index == module_index and (kind == null or export_value.declaration.kind == kind.?) and
            std.mem.eql(u8, export_value.public_name, name)) return export_value;
    }
    return null;
}

pub fn pushLocalScope(self: anytype) !void {
    try self.local_scopes.append(self.allocator, .empty);
}

pub fn popLocalScope(self: anytype) void {
    _ = self.local_scopes.pop();
}

pub fn declareLocal(self: anytype, name: []const u8, position: Source.Position) !void {
    if (std.mem.eql(u8, name, "map_error")) return self.fail(position, "name 'map_error' is reserved");
    try self.local_scopes.items[self.local_scopes.items.len - 1].append(self.allocator, name);
}

pub fn findLocal(self: anytype, name: []const u8) bool {
    var scope_index = self.local_scopes.items.len;
    while (scope_index != 0) {
        scope_index -= 1;
        for (self.local_scopes.items[scope_index].items) |local| {
            if (std.mem.eql(u8, local, name)) return true;
        }
    }
    return false;
}

pub fn fail(self: anytype, position: Source.Position, message: []const u8) Source.Error {
    self.diagnostic = .{ .position = position, .message = message };
    return error.InvalidSource;
}
