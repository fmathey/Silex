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
pub fn transformStructure(self: anytype, structure: Ast.Structure) !Ast.Structure {
    const previous_type_parameters = self.current_type_parameters;
    self.current_type_parameters = structure.type_parameters;
    defer self.current_type_parameters = previous_type_parameters;
    const declaration = self.findDirectByPosition(structure.name_position, .structure).?;
    var fields: std.ArrayList(Ast.StructureField) = .empty;
    for (structure.fields) |field| {
        var copy = field;
        copy.type = try self.transformType(field.type, field.position);
        if (field.initializer) |initializer| copy.initializer = try self.transformExpression(initializer);
        try fields.append(self.allocator, copy);
    }
    var methods: std.ArrayList(Ast.Function) = .empty;
    for (structure.methods) |method| try methods.append(self.allocator, try self.transformFunctionBody(method, method.name));
    var constructors: std.ArrayList(Ast.Constructor) = .empty;
    for (structure.constructors) |constructor| {
        try self.pushLocalScope();
        defer self.popLocalScope();
        var parameters: std.ArrayList(Ast.Parameter) = .empty;
        for (constructor.parameters) |parameter| {
            var copy = parameter;
            copy.type = try self.transformType(parameter.type, parameter.position);
            try parameters.append(self.allocator, copy);
            try self.declareLocal(parameter.name, parameter.position);
        }
        try constructors.append(self.allocator, .{
            .visibility = constructor.visibility,
            .position = constructor.position,
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .super_arguments = if (constructor.super_arguments) |arguments| try self.transformExpressions(arguments) else null,
            .super_position = constructor.super_position,
            .statements = try self.transformStatementsInCurrentScope(constructor.statements),
        });
    }
    var result = structure;
    result.name = declaration.canonical_name;
    result.module_name = self.project.modules[declaration.module_index].name;
    var module_files: std.ArrayList(usize) = .empty;
    for (self.file_infos) |file| {
        if (self.internalAccess(&file, declaration.module_index)) {
            try module_files.append(self.allocator, file.file_index);
        }
    }
    result.module_files = try module_files.toOwnedSlice(self.allocator);
    result.type_parameters = try self.transformTypeParameters(structure.type_parameters);
    var conformances: std.ArrayList(Ast.ProtocolReference) = .empty;
    if (structure.base) |base| {
        const kind = try self.visibleDeclarationKind(structure.position.file, base.name);
        if (kind == .protocol) {
            const protocol = try self.resolveName(structure.position.file, base.name, .protocol, base.position);
            result.base = null;
            try conformances.append(self.allocator, .{ .name = protocol.canonical_name, .position = base.position });
        } else {
            result.base = .{
                .name = (try self.resolveName(structure.position.file, base.name, .structure, base.position)).canonical_name,
                .position = base.position,
            };
        }
    }
    for (structure.conformances) |conformance| {
        const protocol = try self.resolveName(structure.position.file, conformance.name, .protocol, conformance.position);
        try conformances.append(self.allocator, .{ .name = protocol.canonical_name, .position = conformance.position });
    }
    result.conformances = try conformances.toOwnedSlice(self.allocator);
    result.fields = try fields.toOwnedSlice(self.allocator);
    result.constructors = try constructors.toOwnedSlice(self.allocator);
    if (structure.drop) |drop| {
        try self.pushLocalScope();
        defer self.popLocalScope();
        result.drop = .{
            .position = drop.position,
            .statements = try self.transformStatementsInCurrentScope(drop.statements),
        };
    }
    result.methods = try methods.toOwnedSlice(self.allocator);
    return result;
}

pub fn transformProtocol(self: anytype, protocol: Ast.Protocol) !Ast.Protocol {
    const declaration = self.findDirectByPosition(protocol.name_position, .protocol).?;
    var requirements: std.ArrayList(Ast.Function) = .empty;
    for (protocol.requirements) |requirement| {
        try requirements.append(self.allocator, try self.transformFunctionBody(requirement, requirement.name));
    }
    var result = protocol;
    result.name = declaration.canonical_name;
    result.requirements = try requirements.toOwnedSlice(self.allocator);
    return result;
}

pub fn transformEnum(self: anytype, enum_value: Ast.Enum) !Ast.Enum {
    const previous_type_parameters = self.current_type_parameters;
    self.current_type_parameters = enum_value.type_parameters;
    defer self.current_type_parameters = previous_type_parameters;
    const declaration = self.findDirectByPosition(enum_value.name_position, .structure).?;
    var variants: std.ArrayList(Ast.EnumVariant) = .empty;
    for (enum_value.variants) |variant| {
        var associated_types: std.ArrayList(Ast.TypeName) = .empty;
        for (variant.associated_types) |associated_type| {
            try associated_types.append(self.allocator, try self.transformType(associated_type, variant.position));
        }
        try variants.append(self.allocator, .{
            .name = variant.name,
            .position = variant.position,
            .associated_types = try associated_types.toOwnedSlice(self.allocator),
            .raw_value = if (variant.raw_value) |raw_value| try self.transformExpression(raw_value) else null,
        });
    }
    var result = enum_value;
    result.name = declaration.canonical_name;
    result.type_parameters = try self.transformTypeParameters(enum_value.type_parameters);
    result.variants = try variants.toOwnedSlice(self.allocator);
    return result;
}

pub fn transformFunction(self: anytype, function: Ast.Function) !Ast.Function {
    const previous_type_parameters = self.current_type_parameters;
    self.current_type_parameters = function.type_parameters;
    defer self.current_type_parameters = previous_type_parameters;
    const declaration = self.findDirectByPosition(function.name_position, .function).?;
    var result = try self.transformFunctionBody(function, declaration.canonical_name);
    result.module_name = self.project.modules[declaration.module_index].name;
    result.type_parameters = try self.transformTypeParameters(function.type_parameters);
    return result;
}

pub fn transformTypeParameters(self: anytype, parameters: []const Ast.TypeParameter) ![]const Ast.TypeParameter {
    var result: std.ArrayList(Ast.TypeParameter) = .empty;
    for (parameters) |parameter| {
        var copy = parameter;
        if (parameter.constraint) |constraint| {
            const protocol = try self.resolveName(parameter.position.file, constraint.name, .protocol, constraint.position);
            copy.constraint = .{ .name = protocol.canonical_name, .position = constraint.position };
        }
        try result.append(self.allocator, copy);
    }
    return result.toOwnedSlice(self.allocator);
}

pub fn transformFunctionBody(self: anytype, function: Ast.Function, name: []const u8) !Ast.Function {
    try self.pushLocalScope();
    defer self.popLocalScope();
    var parameters: std.ArrayList(Ast.Parameter) = .empty;
    for (function.parameters) |parameter| {
        var copy = parameter;
        copy.type = try self.transformType(parameter.type, parameter.position);
        try parameters.append(self.allocator, copy);
        try self.declareLocal(parameter.name, parameter.position);
    }
    var result = function;
    result.name = name;
    result.return_type = try self.transformReturnType(function.return_type, function.position);
    result.parameters = try parameters.toOwnedSlice(self.allocator);
    result.statements = try self.transformStatementsInCurrentScope(function.statements);
    return result;
}

pub fn transformType(self: anytype, value: Ast.TypeName, position: Source.Position) anyerror!Ast.TypeName {
    return switch (value) {
        .structure => |name| if (self.isCurrentTypeParameter(name))
            .{ .type_parameter = name }
        else if (std.mem.eql(u8, name, "Result"))
            value
        else if (try self.visibleTypeAlias(position.file, name)) |alias|
            try self.resolveAliasType(alias)
        else type_name: {
            const kind = try self.visibleDeclarationKind(position.file, name);
            if (kind == .protocol) {
                break :type_name .{ .structure = (try self.resolveName(position.file, name, .protocol, position)).canonical_name };
            }
            break :type_name .{ .structure = (try self.resolveName(position.file, name, .structure, position)).canonical_name };
        },
        .generic_structure => |generic| generic_type: {
            if (self.isCurrentTypeParameter(generic.name)) {
                return self.fail(position, "a type parameter cannot accept type arguments");
            }
            var arguments: std.ArrayList(Ast.TypeName) = .empty;
            for (generic.arguments) |argument| try arguments.append(self.allocator, try self.transformType(argument, position));
            if (std.mem.eql(u8, generic.name, "Result")) {
                break :generic_type .{ .generic_structure = .{
                    .name = "Result",
                    .arguments = try arguments.toOwnedSlice(self.allocator),
                } };
            }
            const declaration = try self.resolveName(position.file, generic.name, .structure, position);
            break :generic_type .{ .generic_structure = .{
                .name = declaration.canonical_name,
                .arguments = try arguments.toOwnedSlice(self.allocator),
            } };
        },
        .type_parameter => value,
        .list => |element| .{ .list = try self.transformTypePointer(element.*, position) },
        .view => |element| .{ .view = try self.transformTypePointer(element.*, position) },
        .fixed_array => |array| .{ .fixed_array = .{
            .element = try self.transformTypePointer(array.element.*, position),
            .length = array.length,
        } },
        .reference => |reference| .{ .reference = .{
            .target = try self.transformTypePointer(reference.target.*, position),
            .mutable = reference.mutable,
            .provenance = reference.provenance,
            .generic_target = reference.generic_target,
        } },
        .function => |function| function_type: {
            var parameters: std.ArrayList(Ast.TypeName) = .empty;
            for (function.parameters) |parameter| try parameters.append(self.allocator, try self.transformType(parameter, position));
            break :function_type .{ .function = .{
                .deferred = function.deferred,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .parameter_modes = try self.allocator.dupe(Ast.ParameterMode, function.parameter_modes),
                .return_type = if (function.return_type) |return_type| try self.transformTypePointer(return_type.*, position) else null,
            } };
        },
        .optional => |contained| .{ .optional = try self.transformTypePointer(contained.*, position) },
        else => value,
    };
}

pub fn transformTypePointer(self: anytype, value: Ast.TypeName, position: Source.Position) anyerror!*Ast.TypeName {
    const result = try self.allocator.create(Ast.TypeName);
    result.* = try self.transformType(value, position);
    return result;
}

pub fn transformTypeArguments(
    self: anytype,
    arguments: []const Ast.TypeName,
    position: Source.Position,
) anyerror![]const Ast.TypeName {
    var result: std.ArrayList(Ast.TypeName) = .empty;
    for (arguments) |argument| try result.append(self.allocator, try self.transformType(argument, position));
    return result.toOwnedSlice(self.allocator);
}

pub fn transformReturnType(self: anytype, value: Ast.ReturnType, position: Source.Position) !Ast.ReturnType {
    return switch (value) {
        .structure => |name| type_result: {
            const transformed = try self.transformType(.{ .structure = name }, position);
            break :type_result typeNameToReturnType(transformed);
        },
        .generic_structure => |generic| .{ .generic_structure = (try self.transformType(.{ .generic_structure = generic }, position)).generic_structure },
        .type_parameter => value,
        .function => |function| .{ .function = (try self.transformType(.{ .function = function }, position)).function },
        .reference => |reference| .{ .reference = .{
            .target = try self.transformTypePointer(reference.target.*, position),
            .mutable = reference.mutable,
            .provenance = reference.provenance,
            .generic_target = reference.generic_target,
        } },
        .optional => |contained| .{ .optional = try self.transformTypePointer(contained.*, position) },
        else => value,
    };
}

pub fn isCurrentTypeParameter(self: anytype, name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '.') != null) return false;
    for (self.current_type_parameters) |parameter| {
        if (std.mem.eql(u8, parameter.name, name)) return true;
    }
    return false;
}

pub fn visibleTypeAlias(
    self: anytype,
    file_index: usize,
    name: []const u8,
) !?*const Declaration {
    const file = &self.file_infos[file_index];
    if (std.mem.indexOfScalar(u8, name, '.') == null) {
        for (file.uses.items) |binding| {
            if (binding.declaration.kind == .type_alias and std.mem.eql(u8, binding.local_name, name)) {
                return binding.declaration;
            }
        }
        return null;
    }
    const target = try self.qualifiedExpressionTarget(file, name) orelse return null;
    const export_value = self.findExport(target.module_index, target.public_name, .type_alias) orelse return null;
    return export_value.declaration;
}

pub fn resolveAliasType(self: anytype, declaration: *const Declaration) anyerror!Ast.TypeName {
    for (self.alias_stack.items) |active| {
        if (active == declaration) {
            const message = try std.fmt.allocPrint(self.allocator, "type alias cycle involving '{s}'", .{declaration.source_name});
            return self.fail(declaration.position, message);
        }
    }
    try self.alias_stack.append(self.allocator, declaration);
    defer _ = self.alias_stack.pop();
    return self.transformType(declaration.aliased_type.?, declaration.position);
}

pub fn validateTypeAliases(self: anytype) !void {
    for (self.declarations.items) |*declaration| {
        if (declaration.kind != .type_alias) continue;
        const resolved = try self.resolveAliasType(declaration);
        try self.validateAliasedType(resolved, declaration.position);
    }
}

pub fn validateAliasedType(self: anytype, value: Ast.TypeName, position: Source.Position) !void {
    switch (value) {
        .structure => |name| {
            const declaration = self.findDeclarationByCanonicalName(name, .structure) orelse return;
            const parameter_count = self.namedTypeParameterCount(declaration.position);
            if (parameter_count != 0) {
                const declaration_kind = if (self.declarationIsEnum(declaration)) "enum" else "struct";
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic {s} '{s}' requires {d} type argument{s}",
                    .{ declaration_kind, name, parameter_count, if (parameter_count == 1) "" else "s" },
                );
                return self.fail(position, message);
            }
        },
        .generic_structure => |generic| {
            if (std.mem.eql(u8, generic.name, "Result")) {
                if (generic.arguments.len != 2) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "generic enum 'Result' expects 2 type arguments, found {d}",
                        .{generic.arguments.len},
                    );
                    return self.fail(position, message);
                }
                for (generic.arguments) |argument| try self.validateAliasedType(argument, position);
                return;
            }
            const declaration = self.findDeclarationByCanonicalName(generic.name, .structure) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "unknown generic struct '{s}'", .{generic.name});
                return self.fail(position, message);
            };
            const parameter_count = self.namedTypeParameterCount(declaration.position);
            if (parameter_count != generic.arguments.len) {
                const declaration_kind = if (self.declarationIsEnum(declaration)) "enum" else "struct";
                const message = if (parameter_count == 0)
                    try std.fmt.allocPrint(self.allocator, "{s} '{s}' does not accept type arguments", .{ declaration_kind, generic.name })
                else
                    try std.fmt.allocPrint(
                        self.allocator,
                        "generic {s} '{s}' expects {d} type argument{s}, found {d}",
                        .{ declaration_kind, generic.name, parameter_count, if (parameter_count == 1) "" else "s", generic.arguments.len },
                    );
                return self.fail(position, message);
            }
            for (generic.arguments) |argument| try self.validateAliasedType(argument, position);
        },
        .list, .optional => |contained| try self.validateAliasedType(contained.*, position),
        .fixed_array => |array| try self.validateAliasedType(array.element.*, position),
        .reference => |reference| try self.validateAliasedType(reference.target.*, position),
        .function => |function| {
            for (function.parameters) |parameter| try self.validateAliasedType(parameter, position);
            if (function.return_type) |return_type| try self.validateAliasedType(return_type.*, position);
        },
        else => {},
    }
}

pub fn findDeclarationByCanonicalName(self: anytype, name: []const u8, kind: Kind) ?*const Declaration {
    for (self.declarations.items) |*declaration| {
        if (declaration.kind == kind and std.mem.eql(u8, declaration.canonical_name, name)) return declaration;
    }
    return null;
}

pub fn namedTypeParameterCount(self: anytype, position: Source.Position) usize {
    for (self.files) |file| for (file.program.enums) |enum_value| {
        if (enum_value.name_position.file == position.file and enum_value.name_position.line == position.line and
            enum_value.name_position.column == position.column) return enum_value.type_parameters.len;
    };
    for (self.files) |file| for (file.program.structures) |structure| {
        if (structure.name_position.file == position.file and structure.name_position.line == position.line and
            structure.name_position.column == position.column) return structure.type_parameters.len;
    };
    return 0;
}

pub fn transformStatement(self: anytype, statement: Ast.Statement) anyerror!Ast.Statement {
    return switch (statement) {
        .print => |value| .{ .print = .{ .position = value.position, .argument = try self.transformExpression(value.argument) } },
        .assertion => |value| .{ .assertion = .{
            .position = value.position,
            .condition = try self.transformExpression(value.condition),
            .message = try self.transformExpression(value.message),
        } },
        .panic_statement => |value| .{ .panic_statement = .{
            .position = value.position,
            .message = try self.transformExpression(value.message),
        } },
        .variable_declaration => |value| declaration: {
            var copy = value;
            if (value.annotation) |annotation| copy.annotation = try self.transformType(annotation, value.name_position);
            if (value.initializer) |initializer| copy.initializer = try self.transformExpression(initializer);
            try self.declareLocal(value.name, value.name_position);
            break :declaration .{ .variable_declaration = copy };
        },
        .assignment => |value| .{ .assignment = .{
            .position = value.position,
            .target = try self.transformExpression(value.target),
            .operator = value.operator,
            .value = if (value.value) |expression| try self.transformExpression(expression) else null,
        } },
        .if_statement => |value| .{ .if_statement = .{
            .position = value.position,
            .condition = try self.transformCondition(value.condition),
            .body = try self.transformConditionalBody(value.body, value.condition),
            .alternatives = alternatives: {
                var alternatives: std.ArrayList(Ast.Statement.If.Alternative) = .empty;
                for (value.alternatives) |alternative| try alternatives.append(self.allocator, .{
                    .condition = try self.transformCondition(alternative.condition),
                    .body = try self.transformConditionalBody(alternative.body, alternative.condition),
                });
                break :alternatives try alternatives.toOwnedSlice(self.allocator);
            },
            .else_body = if (value.else_body) |body| try self.transformStatements(body) else null,
        } },
        .while_statement => |value| .{ .while_statement = .{
            .position = value.position,
            .condition = try self.transformCondition(value.condition),
            .body = try self.transformConditionalBody(value.body, value.condition),
        } },
        .for_statement => |value| .{ .for_statement = .{
            .position = value.position,
            .name = value.name,
            .name_position = value.name_position,
            .binding = value.binding,
            .source = switch (value.source) {
                .collection => |collection| .{ .collection = try self.transformExpression(collection) },
                .integer_range => |range| .{ .integer_range = .{
                    .start = try self.transformExpression(range.start),
                    .end = try self.transformExpression(range.end),
                } },
            },
            .body = try self.transformForBody(value.body, value.name, value.name_position),
        } },
        .break_statement => |position| .{ .break_statement = position },
        .continue_statement => |position| .{ .continue_statement = position },
        .return_statement => |value| .{ .return_statement = .{
            .position = value.position,
            .value = if (value.value) |expression| try self.transformExpression(expression) else null,
        } },
        .expression_statement => |value| .{ .expression_statement = try self.transformExpression(value) },
    };
}

pub fn transformStatements(self: anytype, statements: []const Ast.Statement) anyerror![]const Ast.Statement {
    try self.pushLocalScope();
    defer self.popLocalScope();
    return self.transformStatementsInCurrentScope(statements);
}

pub fn transformCondition(self: anytype, condition: Ast.Statement.Condition) anyerror!Ast.Statement.Condition {
    return switch (condition) {
        .expression => |expression| .{ .expression = try self.transformExpression(expression) },
        .binding => |binding| .{ .binding = .{
            .position = binding.position,
            .name = binding.name,
            .name_position = binding.name_position,
            .mutability = binding.mutability,
            .source = try self.transformExpression(binding.source),
        } },
    };
}

pub fn transformConditionalBody(
    self: anytype,
    statements: []const Ast.Statement,
    condition: Ast.Statement.Condition,
) anyerror![]const Ast.Statement {
    try self.pushLocalScope();
    defer self.popLocalScope();
    if (condition == .binding) try self.declareLocal(condition.binding.name, condition.binding.name_position);
    return self.transformStatementsInCurrentScope(statements);
}

pub fn transformStatementsInCurrentScope(self: anytype, statements: []const Ast.Statement) anyerror![]const Ast.Statement {
    var result: std.ArrayList(Ast.Statement) = .empty;
    for (statements) |statement| try result.append(self.allocator, try self.transformStatement(statement));
    return result.toOwnedSlice(self.allocator);
}

pub fn transformForBody(
    self: anytype,
    statements: []const Ast.Statement,
    name: []const u8,
    position: Source.Position,
) anyerror![]const Ast.Statement {
    try self.pushLocalScope();
    defer self.popLocalScope();
    try self.declareLocal(name, position);
    return self.transformStatementsInCurrentScope(statements);
}

pub fn transformExpression(self: anytype, expression: *const Ast.Expression) anyerror!*Ast.Expression {
    var result = try self.allocator.create(Ast.Expression);
    result.position = expression.position;
    result.value = switch (expression.value) {
        .identifier => |name| identifier: {
            if (self.findLocal(name)) break :identifier .{ .identifier = name };
            if ((try self.visibleDeclarationKind(expression.position.file, name)) == .function) {
                const declarations = try self.visibleFunctionDeclarations(expression.position.file, name, expression.position);
                break :identifier .{ .identifier = declarations[0].canonical_name };
            }
            break :identifier .{ .identifier = name };
        },
        .call => |call| call: {
            const type_arguments = try self.transformTypeArguments(call.type_arguments, call.name_position);
            if (std.mem.eql(u8, call.name, "map_error") and call.named_fields != null) {
                return self.fail(call.name_position, "function 'map_error' does not accept named arguments");
            }
            if (call.named_fields) |fields| {
                if (try self.visibleTypeAlias(expression.position.file, call.name)) |alias| {
                    break :call try self.transformAliasInvocation(alias, call.name, call.name_position, type_arguments, call.arguments, fields);
                }
                if ((try self.visibleDeclarationKind(expression.position.file, call.name)) == .function) {
                    const message = try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept named arguments; named fields initialize a struct", .{call.name});
                    return self.fail(call.name_position, message);
                }
                const declaration = try self.resolveName(expression.position.file, call.name, .structure, call.name_position);
                break :call .{ .structure_initializer = .{
                    .name = declaration.canonical_name,
                    .name_position = call.name_position,
                    .type_arguments = type_arguments,
                    .fields = try self.transformFieldInitializers(fields),
                } };
            }
            const arguments = try self.transformExpressions(call.arguments);
            if (std.mem.eql(u8, call.name, "map_error") or std.mem.eql(u8, call.name, "dispatch_callbacks")) {
                break :call .{ .call = .{
                    .name = call.name,
                    .name_position = call.name_position,
                    .type_arguments = type_arguments,
                    .arguments = arguments,
                    .visible_declarations = null,
                } };
            }
            if (self.findLocal(call.name)) {
                if (type_arguments.len != 0) return self.fail(call.name_position, "a callable value cannot accept type arguments");
                break :call .{ .call = .{
                    .name = call.name,
                    .name_position = call.name_position,
                    .arguments = arguments,
                    .visible_declarations = null,
                } };
            }
            if (try self.visibleTypeAlias(expression.position.file, call.name)) |alias| {
                break :call try self.transformAliasInvocation(alias, call.name, call.name_position, type_arguments, call.arguments, null);
            }
            if ((try self.visibleDeclarationKind(expression.position.file, call.name)) == .structure) {
                const declaration = try self.resolveName(expression.position.file, call.name, .structure, call.name_position);
                if (self.declarationIsClass(declaration) or self.declarationHasConstructors(declaration)) {
                    if (self.declarationIsClass(declaration) and type_arguments.len != 0) return self.fail(call.name_position, "generic classes are not supported");
                    break :call .{ .class_initializer = .{
                        .name = declaration.canonical_name,
                        .name_position = call.name_position,
                        .type_arguments = type_arguments,
                        .arguments = arguments,
                    } };
                }
                if (arguments.len != 0) {
                    const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' requires named fields such as 'field:value'", .{call.name});
                    return self.fail(call.name_position, message);
                }
                break :call .{ .structure_initializer = .{
                    .name = declaration.canonical_name,
                    .name_position = call.name_position,
                    .type_arguments = type_arguments,
                    .fields = &.{},
                } };
            }
            const declarations = try self.visibleFunctionDeclarations(expression.position.file, call.name, call.name_position);
            break :call .{ .call = .{
                .name = declarations[0].canonical_name,
                .name_position = call.name_position,
                .type_arguments = type_arguments,
                .arguments = arguments,
                .visible_declarations = try declarationPositions(self.allocator, declarations),
            } };
        },
        .value_call => |call| .{ .value_call = .{
            .callee = try self.transformExpression(call.callee),
            .parenthesis_position = call.parenthesis_position,
            .arguments = try self.transformExpressions(call.arguments),
        } },
        .lambda => |lambda| lambda_expression: {
            try self.pushLocalScope();
            defer self.popLocalScope();
            var parameters: std.ArrayList(Ast.Parameter) = .empty;
            for (lambda.parameters) |parameter| {
                var copy = parameter;
                copy.type = try self.transformType(parameter.type, parameter.position);
                try parameters.append(self.allocator, copy);
                try self.declareLocal(parameter.name, parameter.position);
            }
            break :lambda_expression .{ .lambda = .{
                .position = lambda.position,
                .deferred = lambda.deferred,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .return_type = try self.transformReturnType(lambda.return_type, lambda.position),
                .statements = try self.transformStatementsInCurrentScope(lambda.statements),
            } };
        },
        .sequence_literal => |values| .{ .sequence_literal = try self.transformExpressions(values) },
        .structure_initializer => |initializer| .{ .structure_initializer = .{
            .name = (try self.resolveName(expression.position.file, initializer.name, .structure, initializer.name_position)).canonical_name,
            .name_position = initializer.name_position,
            .type_arguments = try self.transformTypeArguments(initializer.type_arguments, initializer.name_position),
            .fields = try self.transformFieldInitializers(initializer.fields),
        } },
        .class_initializer => |initializer| .{ .class_initializer = .{
            .name = (try self.resolveName(expression.position.file, initializer.name, .structure, initializer.name_position)).canonical_name,
            .name_position = initializer.name_position,
            .type_arguments = try self.transformTypeArguments(initializer.type_arguments, initializer.name_position),
            .arguments = try self.transformExpressions(initializer.arguments),
        } },
        .method_call => |call| method: {
            const type_arguments = try self.transformTypeArguments(call.type_arguments, call.name_position);
            if (try self.expressionPath(call.object)) |prefix| {
                const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, call.name });
                const qualified_kind = if (self.looksQualified(expression.position.file, path))
                    try self.visibleDeclarationKind(expression.position.file, path)
                else
                    null;
                if (qualified_kind == .function) {
                    if (call.named_fields != null) {
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "function '{s}' does not accept named arguments; named fields initialize a struct",
                            .{path},
                        );
                        return self.fail(call.name_position, message);
                    }
                    const declarations = try self.visibleFunctionDeclarations(
                        expression.position.file,
                        path,
                        call.name_position,
                    );
                    break :method .{ .call = .{
                        .name = declarations[0].canonical_name,
                        .name_position = call.name_position,
                        .type_arguments = type_arguments,
                        .arguments = try self.transformExpressions(call.arguments),
                        .visible_declarations = try declarationPositions(self.allocator, declarations),
                    } };
                }
                if (qualified_kind == null) {
                    if (try self.staticOwnerType(
                        expression.position.file,
                        prefix,
                        call.name_position,
                    )) |owner| {
                        if (call.named_fields != null) return self.fail(call.name_position, "static methods do not accept named arguments");
                        if (type_arguments.len != 0) return self.fail(call.name_position, "generic methods are not supported");
                        break :method .{ .static_method_call = .{
                            .owner = owner,
                            .owner_position = call.object.position,
                            .name = call.name,
                            .name_position = call.name_position,
                            .arguments = try self.transformExpressions(call.arguments),
                        } };
                    }
                }
                if (self.looksQualified(expression.position.file, path)) {
                    if (try self.visibleTypeAlias(expression.position.file, path)) |alias| {
                        break :method try self.transformAliasInvocation(alias, path, call.name_position, type_arguments, call.arguments, call.named_fields);
                    }
                    if (call.named_fields) |fields| {
                        if ((try self.visibleDeclarationKind(expression.position.file, path)) == .function) {
                            const message = try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept named arguments; named fields initialize a struct", .{path});
                            return self.fail(call.name_position, message);
                        }
                        const declaration = try self.resolveName(expression.position.file, path, .structure, call.name_position);
                        break :method .{ .structure_initializer = .{
                            .name = declaration.canonical_name,
                            .name_position = call.name_position,
                            .type_arguments = type_arguments,
                            .fields = try self.transformFieldInitializers(fields),
                        } };
                    }
                    if ((try self.visibleDeclarationKind(expression.position.file, path)) == .structure) {
                        const declaration = try self.resolveName(expression.position.file, path, .structure, call.name_position);
                        if (self.declarationIsClass(declaration) or self.declarationHasConstructors(declaration)) {
                            if (self.declarationIsClass(declaration) and type_arguments.len != 0) return self.fail(call.name_position, "generic classes are not supported");
                            break :method .{ .class_initializer = .{
                                .name = declaration.canonical_name,
                                .name_position = call.name_position,
                                .type_arguments = type_arguments,
                                .arguments = try self.transformExpressions(call.arguments),
                            } };
                        }
                        if (call.arguments.len != 0) {
                            const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' requires named fields such as 'field:value'", .{path});
                            return self.fail(call.name_position, message);
                        }
                        break :method .{ .structure_initializer = .{
                            .name = declaration.canonical_name,
                            .name_position = call.name_position,
                            .type_arguments = type_arguments,
                            .fields = &.{},
                        } };
                    }
                    const declarations = try self.visibleFunctionDeclarations(expression.position.file, path, call.name_position);
                    break :method .{ .call = .{
                        .name = declarations[0].canonical_name,
                        .name_position = call.name_position,
                        .type_arguments = type_arguments,
                        .arguments = try self.transformExpressions(call.arguments),
                        .visible_declarations = try declarationPositions(self.allocator, declarations),
                    } };
                }
            }
            if (call.named_fields != null) {
                return self.fail(call.name_position, "named arguments require a struct invocation");
            }
            break :method .{ .method_call = .{
                .object = try self.transformExpression(call.object),
                .name = call.name,
                .name_position = call.name_position,
                .type_arguments = type_arguments,
                .arguments = try self.transformExpressions(call.arguments),
            } };
        },
        .static_method_call => |call| .{ .static_method_call = .{
            .owner = try self.transformType(call.owner, call.owner_position),
            .owner_position = call.owner_position,
            .name = call.name,
            .name_position = call.name_position,
            .arguments = try self.transformExpressions(call.arguments),
            .named_fields = if (call.named_fields) |fields| try self.transformFieldInitializers(fields) else null,
        } },
        .static_field_access => |access| .{ .static_field_access = .{
            .owner = try self.transformType(access.owner, access.owner_position),
            .owner_position = access.owner_position,
            .name = access.name,
            .name_position = access.name_position,
        } },
        .super_method_call => |call| .{ .super_method_call = .{
            .position = call.position,
            .name = call.name,
            .name_position = call.name_position,
            .arguments = try self.transformExpressions(call.arguments),
            .named_fields = if (call.named_fields) |fields| try self.transformFieldInitializers(fields) else null,
        } },
        .cascade => |cascade| cascade_expression: {
            var operations: std.ArrayList(Ast.Expression.Cascade.Operation) = .empty;
            for (cascade.operations) |operation| {
                try operations.append(self.allocator, switch (operation) {
                    .method_call => |call| .{ .method_call = .{
                        .name = call.name,
                        .name_position = call.name_position,
                        .arguments = try self.transformExpressions(call.arguments),
                    } },
                    .field_assignment => |assignment| .{ .field_assignment = .{
                        .name = assignment.name,
                        .name_position = assignment.name_position,
                        .value = try self.transformExpression(assignment.value),
                    } },
                });
            }
            break :cascade_expression .{ .cascade = .{
                .object = try self.transformExpression(cascade.object),
                .operations = try operations.toOwnedSlice(self.allocator),
            } };
        },
        .member_access => |member| member_access: {
            if (try self.expressionPath(member.object)) |prefix| {
                const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name });
                if (self.looksQualified(expression.position.file, path) and
                    (try self.visibleDeclarationKind(expression.position.file, path)) == .function)
                {
                    const declarations = try self.visibleFunctionDeclarations(expression.position.file, path, member.name_position);
                    break :member_access .{ .identifier = declarations[0].canonical_name };
                }
                if (try self.staticOwnerType(expression.position.file, prefix, member.name_position)) |owner| {
                    break :member_access .{ .static_field_access = .{
                        .owner = owner,
                        .owner_position = member.object.position,
                        .name = member.name,
                        .name_position = member.name_position,
                    } };
                }
            }
            break :member_access .{ .member_access = .{
                .object = try self.transformExpression(member.object),
                .name = member.name,
                .name_position = member.name_position,
            } };
        },
        .safe_member_access => |member| .{ .safe_member_access = .{
            .object = try self.transformExpression(member.object),
            .name = member.name,
            .name_position = member.name_position,
            .arguments = if (member.arguments) |arguments| try self.transformExpressions(arguments) else null,
            .named_fields = if (member.named_fields) |fields| try self.transformFieldInitializers(fields) else null,
        } },
        .index_access => |access| .{ .index_access = .{
            .object = try self.transformExpression(access.object),
            .index = try self.transformExpression(access.index),
            .bracket_position = access.bracket_position,
        } },
        .slice_access => |access| .{ .slice_access = .{
            .object = try self.transformExpression(access.object),
            .start = try self.transformExpression(access.start),
            .end = try self.transformExpression(access.end),
            .bracket_position = access.bracket_position,
        } },
        .try_expression => |try_value| .{ .try_expression = .{
            .operator_position = try_value.operator_position,
            .operand = try self.transformExpression(try_value.operand),
        } },
        .move_expression => |move_value| .{ .move_expression = .{
            .operator_position = move_value.operator_position,
            .operand = try self.transformExpression(move_value.operand),
        } },
        .borrow_expression => |borrow_value| .{ .borrow_expression = .{
            .operator_position = borrow_value.operator_position,
            .operand = try self.transformExpression(borrow_value.operand),
        } },
        .unary => |unary| .{ .unary = .{
            .operator = unary.operator,
            .operator_position = unary.operator_position,
            .operand = try self.transformExpression(unary.operand),
        } },
        .binary => |binary| .{ .binary = .{
            .operator = binary.operator,
            .operator_position = binary.operator_position,
            .left = try self.transformExpression(binary.left),
            .right = try self.transformExpression(binary.right),
        } },
        .match_expression => |match_value| match_expression: {
            var branches: std.ArrayList(Ast.Expression.Match.Branch) = .empty;
            for (match_value.branches) |branch| {
                try self.pushLocalScope();
                defer self.popLocalScope();
                for (branch.bindings) |binding| try self.declareLocal(binding.name, binding.position);
                try branches.append(self.allocator, .{
                    .variant = branch.variant,
                    .variant_position = branch.variant_position,
                    .bindings = branch.bindings,
                    .body = switch (branch.body) {
                        .expression => |body| .{ .expression = try self.transformExpression(body) },
                        .statements => |body| .{ .statements = try self.transformStatementsInCurrentScope(body) },
                    },
                });
            }
            break :match_expression .{ .match_expression = .{
                .subject = try self.transformExpression(match_value.subject),
                .branches = try branches.toOwnedSlice(self.allocator),
            } };
        },
        else => expression.value,
    };
    return result;
}

pub fn transformExpressions(self: anytype, values: []const *Ast.Expression) anyerror![]const *Ast.Expression {
    var result: std.ArrayList(*Ast.Expression) = .empty;
    for (values) |value| try result.append(self.allocator, try self.transformExpression(value));
    return result.toOwnedSlice(self.allocator);
}

pub fn transformFieldInitializers(self: anytype, values: []const Ast.Expression.FieldInitializer) anyerror![]const Ast.Expression.FieldInitializer {
    var result: std.ArrayList(Ast.Expression.FieldInitializer) = .empty;
    for (values) |value| try result.append(self.allocator, .{
        .name = value.name,
        .position = value.position,
        .value = try self.transformExpression(value.value),
    });
    return result.toOwnedSlice(self.allocator);
}

pub fn transformAliasInvocation(
    self: anytype,
    alias: *const Declaration,
    display_name: []const u8,
    position: Source.Position,
    type_arguments: []const Ast.TypeName,
    arguments: []const *Ast.Expression,
    named_fields: ?[]const Ast.Expression.FieldInitializer,
) anyerror!Ast.Expression.Value {
    if (type_arguments.len != 0) {
        const message = try std.fmt.allocPrint(self.allocator, "type alias '{s}' does not accept type arguments", .{display_name});
        return self.fail(position, message);
    }
    const resolved = try self.resolveAliasType(alias);
    return switch (resolved) {
        .generic_structure => |generic| generic_initializer: {
            const declaration = self.findDeclarationByCanonicalName(generic.name, .structure).?;
            if (self.declarationHasConstructors(declaration) and named_fields == null) {
                break :generic_initializer .{ .class_initializer = .{
                    .name = generic.name,
                    .name_position = position,
                    .type_arguments = generic.arguments,
                    .arguments = try self.transformExpressions(arguments),
                } };
            }
            if (arguments.len != 0) {
                const message = try std.fmt.allocPrint(self.allocator, "struct alias '{s}' requires named fields such as 'field:value'", .{display_name});
                return self.fail(position, message);
            }
            break :generic_initializer .{ .structure_initializer = .{
                .name = generic.name,
                .name_position = position,
                .type_arguments = generic.arguments,
                .fields = if (named_fields) |fields| try self.transformFieldInitializers(fields) else &.{},
            } };
        },
        .structure => |name| structure_initializer: {
            if (named_fields) |fields| {
                break :structure_initializer .{ .structure_initializer = .{
                    .name = name,
                    .name_position = position,
                    .fields = try self.transformFieldInitializers(fields),
                } };
            }
            const declaration = self.findDeclarationByCanonicalName(name, .structure).?;
            if (self.declarationIsClass(declaration) or self.declarationHasConstructors(declaration)) {
                break :structure_initializer .{ .class_initializer = .{
                    .name = name,
                    .name_position = position,
                    .arguments = try self.transformExpressions(arguments),
                } };
            }
            if (arguments.len != 0) {
                const message = try std.fmt.allocPrint(self.allocator, "struct alias '{s}' requires named fields such as 'field:value'", .{display_name});
                return self.fail(position, message);
            }
            break :structure_initializer .{ .structure_initializer = .{
                .name = name,
                .name_position = position,
                .fields = &.{},
            } };
        },
        else => {
            const message = try std.fmt.allocPrint(self.allocator, "type alias '{s}' cannot be used as a function or value", .{display_name});
            return self.fail(position, message);
        },
    };
}
