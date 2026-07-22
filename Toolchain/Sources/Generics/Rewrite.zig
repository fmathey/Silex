const Types = @import("Types.zig");
const Support = @import("Support.zig");
const std = Types.std;
const Ast = Types.Ast;
const Parser = Types.Parser;
const Source = Types.Source;
const Allocator = Types.Allocator;
const SpecializeError = Types.SpecializeError;
const Binding = Types.Binding;
const State = Types.State;
const StructureSpecialization = Types.StructureSpecialization;
const EnumSpecialization = Types.EnumSpecialization;
const result_type_parameters = Types.result_type_parameters;
const result_success_types = Types.result_success_types;
const result_failure_types = Types.result_failure_types;
const result_variants = Types.result_variants;
const intrinsic_result = Types.intrinsic_result;
const intrinsic_function_source = Types.intrinsic_function_source;
const FunctionSpecialization = Types.FunctionSpecialization;
const MethodSpecialization = Types.MethodSpecialization;
const functionIsVisible = Support.functionIsVisible;
const fileSetContains = Support.fileSetContains;
const positionsEqual = Support.positionsEqual;
const typeNameToReturnType = Support.typeNameToReturnType;
const appendTypeName = Support.appendTypeName;
pub fn rewriteEnum(
    self: anytype,
    enum_value: Ast.Enum,
    bindings: []const Binding,
) SpecializeError!Ast.Enum {
    var variants: std.ArrayList(Ast.EnumVariant) = .empty;
    for (enum_value.variants) |variant| {
        var associated_types: std.ArrayList(Ast.TypeName) = .empty;
        for (variant.associated_types) |associated_type| {
            const rewritten = try self.rewriteType(associated_type, bindings, variant.position);
            if (rewritten == .void) continue;
            try associated_types.append(self.allocator, rewritten);
        }
        try variants.append(self.allocator, .{
            .name = variant.name,
            .position = variant.position,
            .associated_types = try associated_types.toOwnedSlice(self.allocator),
            .raw_value = if (variant.raw_value) |raw_value| try self.rewriteExpression(raw_value, bindings) else null,
        });
    }
    var result = enum_value;
    result.type_parameters = &.{};
    result.variants = try variants.toOwnedSlice(self.allocator);
    return result;
}

pub fn rewriteStructure(
    self: anytype,
    structure: Ast.Structure,
    bindings: []const Binding,
) SpecializeError!Ast.Structure {
    var fields: std.ArrayList(Ast.StructureField) = .empty;
    for (structure.fields) |field| {
        var copy = field;
        copy.type = try self.rewriteType(field.type, bindings, field.position);
        if (field.initializer) |initializer| copy.initializer = try self.rewriteExpression(initializer, bindings);
        try fields.append(self.allocator, copy);
    }

    var constructors: std.ArrayList(Ast.Constructor) = .empty;
    for (structure.constructors) |constructor| {
        var parameters: std.ArrayList(Ast.Parameter) = .empty;
        for (constructor.parameters) |parameter| {
            var copy = parameter;
            copy.type = try self.rewriteType(parameter.type, bindings, parameter.position);
            try parameters.append(self.allocator, copy);
        }
        try constructors.append(self.allocator, .{
            .visibility = constructor.visibility,
            .position = constructor.position,
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .super_arguments = if (constructor.super_arguments) |arguments| try self.rewriteExpressions(arguments, bindings) else null,
            .super_position = constructor.super_position,
            .statements = try self.rewriteStatements(constructor.statements, bindings),
        });
    }

    var methods: std.ArrayList(Ast.Function) = .empty;
    for (structure.methods) |method| {
        if (method.type_parameters.len != 0) continue;
        try methods.append(self.allocator, try self.rewriteFunction(method, bindings));
    }

    var result = structure;
    result.type_parameters = &.{};
    result.fields = try fields.toOwnedSlice(self.allocator);
    result.constructors = try constructors.toOwnedSlice(self.allocator);
    if (structure.drop) |drop| result.drop = .{
        .position = drop.position,
        .statements = try self.rewriteStatements(drop.statements, bindings),
    };
    result.methods = try methods.toOwnedSlice(self.allocator);
    return result;
}

pub fn rewriteFunction(
    self: anytype,
    function: Ast.Function,
    bindings: []const Binding,
) SpecializeError!Ast.Function {
    var parameters: std.ArrayList(Ast.Parameter) = .empty;
    for (function.parameters) |parameter| {
        var copy = parameter;
        copy.type = try self.rewriteType(parameter.type, bindings, parameter.position);
        try parameters.append(self.allocator, copy);
    }
    var result = function;
    result.type_parameters = &.{};
    result.return_type = try self.rewriteReturnType(function.return_type, bindings, function.position);
    result.parameters = try parameters.toOwnedSlice(self.allocator);
    result.statements = try self.rewriteStatements(function.statements, bindings);
    return result;
}

pub fn rewriteType(
    self: anytype,
    value: Ast.TypeName,
    bindings: []const Binding,
    position: Source.Position,
) SpecializeError!Ast.TypeName {
    return switch (value) {
        .structure => |name| structure: {
            for (bindings) |binding| {
                if (std.mem.eql(u8, binding.name, name)) return binding.value;
            }
            if (self.findEnumTemplate(name)) |template| {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic enum '{s}' requires {d} type argument{s}",
                    .{ name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s" },
                );
                return self.fail(position, message);
            }
            if (self.findTemplate(name)) |template| {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic struct '{s}' requires {d} type argument{s}",
                    .{ name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s" },
                );
                return self.fail(position, message);
            }
            break :structure value;
        },
        .generic_structure => |generic| generic_type: {
            var arguments: std.ArrayList(Ast.TypeName) = .empty;
            for (generic.arguments) |argument| {
                try arguments.append(self.allocator, try self.rewriteType(argument, bindings, position));
            }
            const name = if (self.findEnumTemplate(generic.name) != null or self.findConcreteEnum(generic.name) != null)
                try self.instantiateEnum(generic.name, arguments.items, position)
            else
                try self.instantiate(generic.name, arguments.items, position);
            break :generic_type .{ .structure = name };
        },
        .type_parameter => |name| {
            for (bindings) |binding| {
                if (std.mem.eql(u8, binding.name, name)) return binding.value;
            }
            const message = try std.fmt.allocPrint(self.allocator, "unknown type parameter '{s}'", .{name});
            return self.fail(position, message);
        },
        .list => |element| .{ .list = try self.rewriteTypePointer(element.*, bindings, position) },
        .view => |element| .{ .view = try self.rewriteTypePointer(element.*, bindings, position) },
        .fixed_array => |array| .{ .fixed_array = .{
            .element = try self.rewriteTypePointer(array.element.*, bindings, position),
            .length = array.length,
        } },
        .reference => |reference| .{ .reference = .{
            .target = try self.rewriteTypePointer(reference.target.*, bindings, position),
            .mutable = reference.mutable,
            .provenance = reference.provenance,
            .generic_target = reference.generic_target or reference.target.* == .type_parameter,
        } },
        .function => |function| function_type: {
            var parameters: std.ArrayList(Ast.TypeName) = .empty;
            for (function.parameters) |parameter| {
                try parameters.append(self.allocator, try self.rewriteType(parameter, bindings, position));
            }
            break :function_type .{ .function = .{
                .deferred = function.deferred,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .parameter_modes = try self.allocator.dupe(Ast.ParameterMode, function.parameter_modes),
                .return_type = if (function.return_type) |return_type| try self.rewriteTypePointer(return_type.*, bindings, position) else null,
            } };
        },
        .optional => |contained| .{ .optional = try self.rewriteTypePointer(contained.*, bindings, position) },
        else => value,
    };
}

pub fn rewriteTypePointer(
    self: anytype,
    value: Ast.TypeName,
    bindings: []const Binding,
    position: Source.Position,
) SpecializeError!*Ast.TypeName {
    const result = try self.allocator.create(Ast.TypeName);
    result.* = try self.rewriteType(value, bindings, position);
    return result;
}

pub fn rewriteReturnType(
    self: anytype,
    value: Ast.ReturnType,
    bindings: []const Binding,
    position: Source.Position,
) SpecializeError!Ast.ReturnType {
    return switch (value) {
        .structure => |name| type_result: {
            const rewritten = try self.rewriteType(.{ .structure = name }, bindings, position);
            break :type_result typeNameToReturnType(rewritten);
        },
        .generic_structure => |generic| type_result: {
            const rewritten = try self.rewriteType(.{ .generic_structure = generic }, bindings, position);
            break :type_result .{ .structure = rewritten.structure };
        },
        .type_parameter => |name| type_result: {
            const rewritten = try self.rewriteType(.{ .type_parameter = name }, bindings, position);
            break :type_result typeNameToReturnType(rewritten);
        },
        .list => |element| .{ .list = try self.rewriteTypePointer(element.*, bindings, position) },
        .view => |element| .{ .view = try self.rewriteTypePointer(element.*, bindings, position) },
        .fixed_array => |array| .{ .fixed_array = .{
            .element = try self.rewriteTypePointer(array.element.*, bindings, position),
            .length = array.length,
        } },
        .reference => |reference| .{ .reference = .{
            .target = try self.rewriteTypePointer(reference.target.*, bindings, position),
            .mutable = reference.mutable,
            .provenance = reference.provenance,
            .generic_target = reference.generic_target or reference.target.* == .type_parameter,
        } },
        .function => |function| .{ .function = (try self.rewriteType(.{ .function = function }, bindings, position)).function },
        .optional => |contained| .{ .optional = try self.rewriteTypePointer(contained.*, bindings, position) },
        else => value,
    };
}

pub fn instantiate(
    self: anytype,
    template_name: []const u8,
    arguments: []const Ast.TypeName,
    position: Source.Position,
) SpecializeError![]const u8 {
    const template = self.findTemplate(template_name) orelse {
        if (self.findConcreteStructure(template_name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' does not accept type arguments", .{template_name});
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "unknown generic struct '{s}'", .{template_name});
        return self.fail(position, message);
    };
    if (arguments.len != template.type_parameters.len) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "generic struct '{s}' expects {d} type argument{s}, found {d}",
            .{ template_name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s", arguments.len },
        );
        return self.fail(position, message);
    }
    try self.validateTypeArgumentConstraints(template.type_parameters, arguments, position);
    const name = try self.genericTypeName(template_name, arguments);
    for (self.structure_specializations.items) |specialization| {
        if (std.mem.eql(u8, specialization.name, name)) return specialization.name;
        if (specialization.state == .visiting and std.mem.eql(u8, specialization.template_name, template_name)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "generic struct '{s}' recursively expands with different type arguments",
                .{template_name},
            );
            return self.fail(position, message);
        }
    }

    const specialization_index = self.structure_specializations.items.len;
    try self.structure_specializations.append(self.allocator, .{
        .template_name = template_name,
        .name = name,
        .state = .visiting,
    });
    var bindings = try self.allocator.alloc(Binding, arguments.len);
    for (template.type_parameters, arguments, 0..) |parameter, argument, index| {
        bindings[index] = .{ .name = parameter.name, .value = argument };
    }

    var constraint_protocols: std.ArrayList([]const u8) = .empty;
    for (template.type_parameters) |parameter| {
        if (parameter.constraint) |constraint| try constraint_protocols.append(self.allocator, constraint.name);
    }
    const previous_constraints = self.active_constraint_protocols;
    const previous_visibility_file = self.active_extension_visibility_file;
    self.active_constraint_protocols = try constraint_protocols.toOwnedSlice(self.allocator);
    self.active_extension_visibility_file = position.file;
    defer {
        self.active_constraint_protocols = previous_constraints;
        self.active_extension_visibility_file = previous_visibility_file;
    }

    var concrete = try self.rewriteStructure(template.*, bindings);
    concrete.name = name;
    concrete.type_parameters = &.{};
    try self.structures.append(self.allocator, concrete);
    self.structure_specializations.items[specialization_index].state = .done;
    return name;
}

pub fn instantiateEnum(
    self: anytype,
    template_name: []const u8,
    arguments: []const Ast.TypeName,
    position: Source.Position,
) SpecializeError![]const u8 {
    const template = self.findEnumTemplate(template_name) orelse {
        if (self.findConcreteEnum(template_name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' does not accept type arguments", .{template_name});
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "unknown generic enum '{s}'", .{template_name});
        return self.fail(position, message);
    };
    if (arguments.len != template.type_parameters.len) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "generic enum '{s}' expects {d} type argument{s}, found {d}",
            .{ template_name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s", arguments.len },
        );
        return self.fail(position, message);
    }
    try self.validateTypeArgumentConstraints(template.type_parameters, arguments, position);
    for (arguments, 0..) |argument, index| {
        if (argument != .void) continue;
        if (!std.mem.eql(u8, template_name, "Result")) {
            return self.fail(position, "void cannot be used as a type argument");
        }
        if (index != 0) return self.fail(position, "Result error type cannot be 'void'");
    }

    const name = try self.genericTypeName(template_name, arguments);
    for (self.enum_specializations.items) |specialization| {
        if (std.mem.eql(u8, specialization.name, name)) return specialization.name;
        if (specialization.state == .visiting and std.mem.eql(u8, specialization.template_name, template_name)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "generic enum '{s}' recursively expands with different type arguments",
                .{template_name},
            );
            return self.fail(position, message);
        }
    }

    const specialization_index = self.enum_specializations.items.len;
    try self.enum_specializations.append(self.allocator, .{
        .template_name = template_name,
        .name = name,
        .state = .visiting,
    });
    const bindings = try self.allocator.alloc(Binding, arguments.len);
    for (template.type_parameters, arguments, 0..) |parameter, argument, index| {
        bindings[index] = .{ .name = parameter.name, .value = argument };
    }

    var concrete = try self.rewriteEnum(template.*, bindings);
    concrete.name = name;
    concrete.type_parameters = &.{};
    try self.enums.append(self.allocator, concrete);
    self.enum_specializations.items[specialization_index].state = .done;
    return name;
}

pub fn rewriteStatements(
    self: anytype,
    statements: []const Ast.Statement,
    bindings: []const Binding,
) SpecializeError![]const Ast.Statement {
    var result: std.ArrayList(Ast.Statement) = .empty;
    for (statements) |statement| try result.append(self.allocator, try self.rewriteStatement(statement, bindings));
    return result.toOwnedSlice(self.allocator);
}

pub fn rewriteStatement(
    self: anytype,
    statement: Ast.Statement,
    bindings: []const Binding,
) SpecializeError!Ast.Statement {
    return switch (statement) {
        .print => |value| .{ .print = .{ .position = value.position, .argument = try self.rewriteExpression(value.argument, bindings) } },
        .assertion => |value| .{ .assertion = .{
            .position = value.position,
            .condition = try self.rewriteExpression(value.condition, bindings),
            .message = try self.rewriteExpression(value.message, bindings),
        } },
        .panic_statement => |value| .{ .panic_statement = .{
            .position = value.position,
            .message = try self.rewriteExpression(value.message, bindings),
        } },
        .variable_declaration => |value| declaration: {
            var copy = value;
            if (value.annotation) |annotation| copy.annotation = try self.rewriteType(annotation, bindings, value.name_position);
            if (value.initializer) |initializer| copy.initializer = try self.rewriteExpression(initializer, bindings);
            break :declaration .{ .variable_declaration = copy };
        },
        .assignment => |value| .{ .assignment = .{
            .position = value.position,
            .target = try self.rewriteExpression(value.target, bindings),
            .operator = value.operator,
            .value = if (value.value) |expression| try self.rewriteExpression(expression, bindings) else null,
        } },
        .if_statement => |value| if_statement: {
            var alternatives: std.ArrayList(Ast.Statement.If.Alternative) = .empty;
            for (value.alternatives) |alternative| try alternatives.append(self.allocator, .{
                .condition = try self.rewriteCondition(alternative.condition, bindings),
                .body = try self.rewriteStatements(alternative.body, bindings),
            });
            break :if_statement .{ .if_statement = .{
                .position = value.position,
                .condition = try self.rewriteCondition(value.condition, bindings),
                .body = try self.rewriteStatements(value.body, bindings),
                .alternatives = try alternatives.toOwnedSlice(self.allocator),
                .else_body = if (value.else_body) |body| try self.rewriteStatements(body, bindings) else null,
            } };
        },
        .while_statement => |value| .{ .while_statement = .{
            .position = value.position,
            .condition = try self.rewriteCondition(value.condition, bindings),
            .body = try self.rewriteStatements(value.body, bindings),
        } },
        .for_statement => |value| .{ .for_statement = .{
            .position = value.position,
            .name = value.name,
            .name_position = value.name_position,
            .binding = value.binding,
            .source = switch (value.source) {
                .collection => |collection| .{ .collection = try self.rewriteExpression(collection, bindings) },
                .integer_range => |range| .{ .integer_range = .{
                    .start = try self.rewriteExpression(range.start, bindings),
                    .end = try self.rewriteExpression(range.end, bindings),
                } },
            },
            .body = try self.rewriteStatements(value.body, bindings),
        } },
        .break_statement => |position| .{ .break_statement = position },
        .continue_statement => |position| .{ .continue_statement = position },
        .return_statement => |value| .{ .return_statement = .{
            .position = value.position,
            .value = if (value.value) |expression| try self.rewriteExpression(expression, bindings) else null,
        } },
        .expression_statement => |expression| .{ .expression_statement = try self.rewriteExpression(expression, bindings) },
    };
}

pub fn rewriteCondition(
    self: anytype,
    condition: Ast.Statement.Condition,
    bindings: []const Binding,
) SpecializeError!Ast.Statement.Condition {
    return switch (condition) {
        .expression => |expression| .{ .expression = try self.rewriteExpression(expression, bindings) },
        .binding => |binding| .{ .binding = .{
            .position = binding.position,
            .name = binding.name,
            .name_position = binding.name_position,
            .mutability = binding.mutability,
            .source = try self.rewriteExpression(binding.source, bindings),
        } },
    };
}

pub fn rewriteExpression(
    self: anytype,
    expression: *const Ast.Expression,
    bindings: []const Binding,
) SpecializeError!*Ast.Expression {
    const result = try self.allocator.create(Ast.Expression);
    result.position = expression.position;
    result.value = switch (expression.value) {
        .sequence_literal => |values| .{ .sequence_literal = try self.rewriteExpressions(values, bindings) },
        .call => |call| function_call: {
            const type_arguments = try self.rewriteTypes(call.type_arguments, bindings, call.name_position);
            const name = if (type_arguments.len != 0)
                try self.instantiateFunctions(call.name, type_arguments, call.visible_declarations, call.name_position)
            else no_type_arguments: {
                if (self.hasVisibleGenericFunction(call.name, call.visible_declarations) and
                    !self.hasVisibleConcreteFunction(call.name, call.visible_declarations))
                {
                    const message = try std.fmt.allocPrint(self.allocator, "generic function '{s}' requires explicit type arguments", .{call.name});
                    return self.fail(call.name_position, message);
                }
                break :no_type_arguments call.name;
            };
            break :function_call .{ .call = .{
                .name = name,
                .name_position = call.name_position,
                .type_arguments = &.{},
                .arguments = try self.rewriteExpressions(call.arguments, bindings),
                .named_fields = if (call.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
                .visible_declarations = call.visible_declarations,
            } };
        },
        .value_call => |call| .{ .value_call = .{
            .callee = try self.rewriteExpression(call.callee, bindings),
            .parenthesis_position = call.parenthesis_position,
            .arguments = try self.rewriteExpressions(call.arguments, bindings),
        } },
        .lambda => |lambda| lambda_expression: {
            var parameters: std.ArrayList(Ast.Parameter) = .empty;
            for (lambda.parameters) |parameter| {
                var copy = parameter;
                copy.type = try self.rewriteType(parameter.type, bindings, parameter.position);
                try parameters.append(self.allocator, copy);
            }
            break :lambda_expression .{ .lambda = .{
                .position = lambda.position,
                .deferred = lambda.deferred,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .return_type = try self.rewriteReturnType(lambda.return_type, bindings, lambda.position),
                .statements = try self.rewriteStatements(lambda.statements, bindings),
            } };
        },
        .method_call => |call| method_call: {
            const type_arguments = try self.rewriteTypes(call.type_arguments, bindings, call.name_position);
            const visibility_file = if (self.activeConstraintRequires(call.name))
                self.active_extension_visibility_file
            else
                call.extension_visibility_file;
            const name = if (type_arguments.len != 0)
                try self.instantiateMethods(call.name, type_arguments, visibility_file orelse call.name_position.file, call.name_position)
            else no_type_arguments: {
                if (self.genericExtensionMethodRequiresArguments(call.name, visibility_file orelse call.name_position.file)) {
                    const message = try std.fmt.allocPrint(self.allocator, "generic extension method '{s}' requires explicit type arguments", .{call.name});
                    return self.fail(call.name_position, message);
                }
                break :no_type_arguments call.name;
            };
            break :method_call .{ .method_call = .{
                .object = try self.rewriteExpression(call.object, bindings),
                .name = name,
                .name_position = call.name_position,
                .extension_visibility_file = visibility_file,
                .type_arguments = type_arguments,
                .arguments = try self.rewriteExpressions(call.arguments, bindings),
                .named_fields = if (call.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
            } };
        },
        .static_method_call => |call| .{ .static_method_call = .{
            .owner = try self.rewriteType(call.owner, bindings, call.owner_position),
            .owner_position = call.owner_position,
            .name = call.name,
            .name_position = call.name_position,
            .arguments = try self.rewriteExpressions(call.arguments, bindings),
            .named_fields = if (call.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
        } },
        .static_field_access => |access| .{ .static_field_access = .{
            .owner = try self.rewriteType(access.owner, bindings, access.owner_position),
            .owner_position = access.owner_position,
            .name = access.name,
            .name_position = access.name_position,
        } },
        .super_method_call => |call| .{ .super_method_call = .{
            .position = call.position,
            .name = call.name,
            .name_position = call.name_position,
            .arguments = try self.rewriteExpressions(call.arguments, bindings),
            .named_fields = if (call.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
        } },
        .cascade => |cascade| cascade_expression: {
            var operations: std.ArrayList(Ast.Expression.Cascade.Operation) = .empty;
            for (cascade.operations) |operation| try operations.append(self.allocator, switch (operation) {
                .method_call => |call| .{ .method_call = .{
                    .name = call.name,
                    .name_position = call.name_position,
                    .extension_visibility_file = if (self.activeConstraintRequires(call.name))
                        self.active_extension_visibility_file
                    else
                        call.extension_visibility_file,
                    .arguments = try self.rewriteExpressions(call.arguments, bindings),
                } },
                .field_assignment => |assignment| .{ .field_assignment = .{
                    .name = assignment.name,
                    .name_position = assignment.name_position,
                    .value = try self.rewriteExpression(assignment.value, bindings),
                } },
            });
            break :cascade_expression .{ .cascade = .{
                .object = try self.rewriteExpression(cascade.object, bindings),
                .operations = try operations.toOwnedSlice(self.allocator),
            } };
        },
        .class_initializer => |initializer| initializer_expression: {
            const arguments = try self.rewriteTypes(initializer.type_arguments, bindings, initializer.name_position);
            const name = if (arguments.len != 0)
                try self.instantiate(initializer.name, arguments, initializer.name_position)
            else if (self.findTemplate(initializer.name)) |template| {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic struct '{s}' requires {d} type argument{s}",
                    .{ initializer.name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s" },
                );
                return self.fail(initializer.name_position, message);
            } else initializer.name;
            break :initializer_expression .{ .class_initializer = .{
                .name = name,
                .name_position = initializer.name_position,
                .type_arguments = &.{},
                .arguments = try self.rewriteExpressions(initializer.arguments, bindings),
            } };
        },
        .structure_initializer => |initializer| initializer_expression: {
            const arguments = try self.rewriteTypes(initializer.type_arguments, bindings, initializer.name_position);
            const name = if (arguments.len != 0)
                try self.instantiate(initializer.name, arguments, initializer.name_position)
            else if (self.findTemplate(initializer.name)) |template| {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic struct '{s}' requires {d} type argument{s}",
                    .{ initializer.name, template.type_parameters.len, if (template.type_parameters.len == 1) "" else "s" },
                );
                return self.fail(initializer.name_position, message);
            } else initializer.name;
            break :initializer_expression .{ .structure_initializer = .{
                .name = name,
                .name_position = initializer.name_position,
                .type_arguments = &.{},
                .fields = try self.rewriteFieldInitializers(initializer.fields, bindings),
            } };
        },
        .member_access => |member| .{ .member_access = .{
            .object = try self.rewriteExpression(member.object, bindings),
            .name = member.name,
            .name_position = member.name_position,
        } },
        .safe_member_access => |member| .{ .safe_member_access = .{
            .object = try self.rewriteExpression(member.object, bindings),
            .name = member.name,
            .name_position = member.name_position,
            .arguments = if (member.arguments) |arguments| try self.rewriteExpressions(arguments, bindings) else null,
            .named_fields = if (member.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
        } },
        .index_access => |access| .{ .index_access = .{
            .object = try self.rewriteExpression(access.object, bindings),
            .index = try self.rewriteExpression(access.index, bindings),
            .bracket_position = access.bracket_position,
        } },
        .slice_access => |access| .{ .slice_access = .{
            .object = try self.rewriteExpression(access.object, bindings),
            .start = try self.rewriteExpression(access.start, bindings),
            .end = try self.rewriteExpression(access.end, bindings),
            .bracket_position = access.bracket_position,
        } },
        .try_expression => |try_value| .{ .try_expression = .{
            .operator_position = try_value.operator_position,
            .operand = try self.rewriteExpression(try_value.operand, bindings),
        } },
        .unary => |unary| .{ .unary = .{
            .operator = unary.operator,
            .operator_position = unary.operator_position,
            .operand = try self.rewriteExpression(unary.operand, bindings),
        } },
        .conversion => |conversion| .{ .conversion = .{
            .operand = try self.rewriteExpression(conversion.operand, bindings),
            .target_type = try self.rewriteType(conversion.target_type, bindings, conversion.as_position),
            .as_position = conversion.as_position,
        } },
        .binary => |binary| .{ .binary = .{
            .operator = binary.operator,
            .operator_position = binary.operator_position,
            .left = try self.rewriteExpression(binary.left, bindings),
            .right = try self.rewriteExpression(binary.right, bindings),
        } },
        .match_expression => |match_value| match_expression: {
            var branches: std.ArrayList(Ast.Expression.Match.Branch) = .empty;
            for (match_value.branches) |branch| {
                try branches.append(self.allocator, .{
                    .variant = branch.variant,
                    .variant_position = branch.variant_position,
                    .bindings = branch.bindings,
                    .body = switch (branch.body) {
                        .expression => |body| .{ .expression = try self.rewriteExpression(body, bindings) },
                        .statements => |body| .{ .statements = try self.rewriteStatements(body, bindings) },
                    },
                });
            }
            break :match_expression .{ .match_expression = .{
                .subject = try self.rewriteExpression(match_value.subject, bindings),
                .branches = try branches.toOwnedSlice(self.allocator),
            } };
        },
        else => expression.value,
    };
    return result;
}

pub fn rewriteExpressions(
    self: anytype,
    expressions: []const *Ast.Expression,
    bindings: []const Binding,
) SpecializeError![]const *Ast.Expression {
    var result: std.ArrayList(*Ast.Expression) = .empty;
    for (expressions) |expression| try result.append(self.allocator, try self.rewriteExpression(expression, bindings));
    return result.toOwnedSlice(self.allocator);
}

pub fn rewriteFieldInitializers(
    self: anytype,
    fields: []const Ast.Expression.FieldInitializer,
    bindings: []const Binding,
) SpecializeError![]const Ast.Expression.FieldInitializer {
    var result: std.ArrayList(Ast.Expression.FieldInitializer) = .empty;
    for (fields) |field| try result.append(self.allocator, .{
        .name = field.name,
        .position = field.position,
        .value = try self.rewriteExpression(field.value, bindings),
    });
    return result.toOwnedSlice(self.allocator);
}

pub fn rewriteTypes(
    self: anytype,
    values: []const Ast.TypeName,
    bindings: []const Binding,
    position: Source.Position,
) SpecializeError![]const Ast.TypeName {
    var result: std.ArrayList(Ast.TypeName) = .empty;
    for (values) |value| try result.append(self.allocator, try self.rewriteType(value, bindings, position));
    return result.toOwnedSlice(self.allocator);
}
