const std = @import("std");
const Ast = @import("Ast.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const SpecializeError = Source.Error || Allocator.Error;

const Binding = struct {
    name: []const u8,
    value: Ast.TypeName,
};

const State = enum { visiting, done };

const StructureSpecialization = struct {
    template_name: []const u8,
    name: []const u8,
    state: State,
};

const EnumSpecialization = struct {
    template_name: []const u8,
    name: []const u8,
    state: State,
};

const FunctionSpecialization = struct {
    template_position: Source.Position,
    name: []const u8,
    state: State,
};

pub const Specializer = struct {
    allocator: Allocator,
    program: Ast.Program,
    enums: std.ArrayList(Ast.Enum) = .empty,
    structures: std.ArrayList(Ast.Structure) = .empty,
    functions: std.ArrayList(Ast.Function) = .empty,
    enum_specializations: std.ArrayList(EnumSpecialization) = .empty,
    structure_specializations: std.ArrayList(StructureSpecialization) = .empty,
    function_specializations: std.ArrayList(FunctionSpecialization) = .empty,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, program: Ast.Program) Specializer {
        return .{ .allocator = allocator, .program = program };
    }

    pub fn specialize(self: *Specializer) SpecializeError!Ast.Program {
        for (self.program.enums) |enum_value| {
            if (enum_value.type_parameters.len != 0) continue;
            try self.enums.append(self.allocator, try self.rewriteEnum(enum_value, &.{}));
        }
        for (self.program.structures) |structure| {
            if (structure.type_parameters.len != 0) continue;
            const concrete = try self.rewriteStructure(structure, &.{});
            try self.structures.append(self.allocator, concrete);
        }

        for (self.program.functions) |function| {
            if (function.type_parameters.len != 0) continue;
            try self.functions.append(self.allocator, try self.rewriteFunction(function, &.{}));
        }

        return .{
            .enums = try self.enums.toOwnedSlice(self.allocator),
            .structures = try self.structures.toOwnedSlice(self.allocator),
            .functions = try self.functions.toOwnedSlice(self.allocator),
        };
    }

    fn rewriteEnum(
        self: *Specializer,
        enum_value: Ast.Enum,
        bindings: []const Binding,
    ) SpecializeError!Ast.Enum {
        var variants: std.ArrayList(Ast.EnumVariant) = .empty;
        for (enum_value.variants) |variant| {
            var associated_types: std.ArrayList(Ast.TypeName) = .empty;
            for (variant.associated_types) |associated_type| {
                try associated_types.append(self.allocator, try self.rewriteType(associated_type, bindings, variant.position));
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

    fn rewriteStructure(
        self: *Specializer,
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

    fn rewriteFunction(
        self: *Specializer,
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

    fn rewriteType(
        self: *Specializer,
        value: Ast.TypeName,
        bindings: []const Binding,
        position: Source.Position,
    ) SpecializeError!Ast.TypeName {
        return switch (value) {
            .structure => |name| structure: {
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
            .fixed_array => |array| .{ .fixed_array = .{
                .element = try self.rewriteTypePointer(array.element.*, bindings, position),
                .length = array.length,
            } },
            .reference => |reference| .{ .reference = .{
                .target = try self.rewriteTypePointer(reference.target.*, bindings, position),
                .mutable = reference.mutable,
            } },
            .function => |function| function_type: {
                var parameters: std.ArrayList(Ast.TypeName) = .empty;
                for (function.parameters) |parameter| {
                    try parameters.append(self.allocator, try self.rewriteType(parameter, bindings, position));
                }
                break :function_type .{ .function = .{
                    .parameters = try parameters.toOwnedSlice(self.allocator),
                    .parameter_is_mutable_references = try self.allocator.dupe(bool, function.parameter_is_mutable_references),
                    .return_type = if (function.return_type) |return_type| try self.rewriteTypePointer(return_type.*, bindings, position) else null,
                } };
            },
            .optional => |contained| .{ .optional = try self.rewriteTypePointer(contained.*, bindings, position) },
            else => value,
        };
    }

    fn rewriteTypePointer(
        self: *Specializer,
        value: Ast.TypeName,
        bindings: []const Binding,
        position: Source.Position,
    ) SpecializeError!*Ast.TypeName {
        const result = try self.allocator.create(Ast.TypeName);
        result.* = try self.rewriteType(value, bindings, position);
        return result;
    }

    fn rewriteReturnType(
        self: *Specializer,
        value: Ast.ReturnType,
        bindings: []const Binding,
        position: Source.Position,
    ) SpecializeError!Ast.ReturnType {
        return switch (value) {
            .structure => |name| type_result: {
                const rewritten = try self.rewriteType(.{ .structure = name }, bindings, position);
                break :type_result .{ .structure = rewritten.structure };
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
            .fixed_array => |array| .{ .fixed_array = .{
                .element = try self.rewriteTypePointer(array.element.*, bindings, position),
                .length = array.length,
            } },
            .reference => |reference| .{ .reference = .{
                .target = try self.rewriteTypePointer(reference.target.*, bindings, position),
                .mutable = reference.mutable,
            } },
            .function => |function| .{ .function = (try self.rewriteType(.{ .function = function }, bindings, position)).function },
            .optional => |contained| .{ .optional = try self.rewriteTypePointer(contained.*, bindings, position) },
            else => value,
        };
    }

    fn instantiate(
        self: *Specializer,
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

        var concrete = try self.rewriteStructure(template.*, bindings);
        concrete.name = name;
        concrete.type_parameters = &.{};
        try self.structures.append(self.allocator, concrete);
        self.structure_specializations.items[specialization_index].state = .done;
        return name;
    }

    fn instantiateEnum(
        self: *Specializer,
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

    fn rewriteStatements(
        self: *Specializer,
        statements: []const Ast.Statement,
        bindings: []const Binding,
    ) SpecializeError![]const Ast.Statement {
        var result: std.ArrayList(Ast.Statement) = .empty;
        for (statements) |statement| try result.append(self.allocator, try self.rewriteStatement(statement, bindings));
        return result.toOwnedSlice(self.allocator);
    }

    fn rewriteStatement(
        self: *Specializer,
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
                .mutability = value.mutability,
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

    fn rewriteCondition(
        self: *Specializer,
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

    fn rewriteExpression(
        self: *Specializer,
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
                    .parameters = try parameters.toOwnedSlice(self.allocator),
                    .return_type = try self.rewriteReturnType(lambda.return_type, bindings, lambda.position),
                    .statements = try self.rewriteStatements(lambda.statements, bindings),
                } };
            },
            .method_call => |call| .{ .method_call = .{
                .object = try self.rewriteExpression(call.object, bindings),
                .name = call.name,
                .name_position = call.name_position,
                .type_arguments = try self.rewriteTypes(call.type_arguments, bindings, call.name_position),
                .arguments = try self.rewriteExpressions(call.arguments, bindings),
                .named_fields = if (call.named_fields) |fields| try self.rewriteFieldInitializers(fields, bindings) else null,
            } },
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
            .class_initializer => |initializer| .{ .class_initializer = .{
                .name = initializer.name,
                .name_position = initializer.name_position,
                .arguments = try self.rewriteExpressions(initializer.arguments, bindings),
            } },
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

    fn rewriteExpressions(
        self: *Specializer,
        expressions: []const *Ast.Expression,
        bindings: []const Binding,
    ) SpecializeError![]const *Ast.Expression {
        var result: std.ArrayList(*Ast.Expression) = .empty;
        for (expressions) |expression| try result.append(self.allocator, try self.rewriteExpression(expression, bindings));
        return result.toOwnedSlice(self.allocator);
    }

    fn rewriteFieldInitializers(
        self: *Specializer,
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

    fn rewriteTypes(
        self: *Specializer,
        values: []const Ast.TypeName,
        bindings: []const Binding,
        position: Source.Position,
    ) SpecializeError![]const Ast.TypeName {
        var result: std.ArrayList(Ast.TypeName) = .empty;
        for (values) |value| try result.append(self.allocator, try self.rewriteType(value, bindings, position));
        return result.toOwnedSlice(self.allocator);
    }

    fn findTemplate(self: *const Specializer, name: []const u8) ?*const Ast.Structure {
        for (self.program.structures) |*structure| {
            if (structure.type_parameters.len != 0 and std.mem.eql(u8, structure.name, name)) return structure;
        }
        return null;
    }

    fn findEnumTemplate(self: *const Specializer, name: []const u8) ?*const Ast.Enum {
        for (self.program.enums) |*enum_value| {
            if (enum_value.type_parameters.len != 0 and std.mem.eql(u8, enum_value.name, name)) return enum_value;
        }
        return null;
    }

    fn findConcreteEnum(self: *const Specializer, name: []const u8) ?*const Ast.Enum {
        for (self.program.enums) |*enum_value| {
            if (enum_value.type_parameters.len == 0 and std.mem.eql(u8, enum_value.name, name)) return enum_value;
        }
        return null;
    }

    fn findConcreteStructure(self: *const Specializer, name: []const u8) ?*const Ast.Structure {
        for (self.program.structures) |*structure| {
            if (structure.type_parameters.len == 0 and std.mem.eql(u8, structure.name, name)) return structure;
        }
        return null;
    }

    fn instantiateFunctions(
        self: *Specializer,
        template_name: []const u8,
        arguments: []const Ast.TypeName,
        visible_declarations: ?[]const Source.Position,
        position: Source.Position,
    ) SpecializeError![]const u8 {
        const name = try self.genericTypeName(template_name, arguments);
        var generic_count: usize = 0;
        var matching_count: usize = 0;
        var expected_arity: ?usize = null;
        var arities_match = true;

        for (self.program.functions) |*function| {
            if (function.type_parameters.len == 0 or
                !std.mem.eql(u8, function.name, template_name) or
                !functionIsVisible(function.*, visible_declarations)) continue;
            generic_count += 1;
            if (expected_arity) |expected| {
                if (expected != function.type_parameters.len) arities_match = false;
            } else expected_arity = function.type_parameters.len;
            if (function.type_parameters.len != arguments.len) continue;
            matching_count += 1;
            try self.instantiateFunction(function.*, arguments, name, position);
        }

        if (generic_count == 0) {
            const message = if (self.hasVisibleConcreteFunction(template_name, visible_declarations))
                try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept type arguments", .{template_name})
            else
                try std.fmt.allocPrint(self.allocator, "unknown generic function '{s}'", .{template_name});
            return self.fail(position, message);
        }
        if (matching_count == 0) {
            const message = if (arities_match)
                try std.fmt.allocPrint(
                    self.allocator,
                    "generic function '{s}' expects {d} type argument{s}, found {d}",
                    .{ template_name, expected_arity.?, if (expected_arity.? == 1) "" else "s", arguments.len },
                )
            else
                try std.fmt.allocPrint(
                    self.allocator,
                    "generic function '{s}' has no overload accepting {d} type arguments",
                    .{ template_name, arguments.len },
                );
            return self.fail(position, message);
        }
        return name;
    }

    fn instantiateFunction(
        self: *Specializer,
        template: Ast.Function,
        arguments: []const Ast.TypeName,
        name: []const u8,
        position: Source.Position,
    ) SpecializeError!void {
        for (self.function_specializations.items) |specialization| {
            if (!positionsEqual(specialization.template_position, template.name_position)) continue;
            if (std.mem.eql(u8, specialization.name, name)) return;
            if (specialization.state == .visiting) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic function '{s}' recursively expands with different type arguments",
                    .{template.name},
                );
                return self.fail(position, message);
            }
        }

        const specialization_index = self.function_specializations.items.len;
        try self.function_specializations.append(self.allocator, .{
            .template_position = template.name_position,
            .name = name,
            .state = .visiting,
        });
        const bindings = try self.allocator.alloc(Binding, arguments.len);
        for (template.type_parameters, arguments, 0..) |parameter, argument, index| {
            bindings[index] = .{ .name = parameter.name, .value = argument };
        }

        var concrete = try self.rewriteFunction(template, bindings);
        concrete.name = name;
        concrete.type_parameters = &.{};
        try self.functions.append(self.allocator, concrete);
        self.function_specializations.items[specialization_index].state = .done;
    }

    fn hasVisibleGenericFunction(
        self: *const Specializer,
        name: []const u8,
        visible_declarations: ?[]const Source.Position,
    ) bool {
        for (self.program.functions) |function| {
            if (function.type_parameters.len != 0 and
                std.mem.eql(u8, function.name, name) and
                functionIsVisible(function, visible_declarations)) return true;
        }
        return false;
    }

    fn hasVisibleConcreteFunction(
        self: *const Specializer,
        name: []const u8,
        visible_declarations: ?[]const Source.Position,
    ) bool {
        for (self.program.functions) |function| {
            if (function.type_parameters.len == 0 and
                std.mem.eql(u8, function.name, name) and
                functionIsVisible(function, visible_declarations)) return true;
        }
        return false;
    }

    fn genericTypeName(
        self: *Specializer,
        template_name: []const u8,
        arguments: []const Ast.TypeName,
    ) Allocator.Error![]const u8 {
        var output: std.ArrayList(u8) = .empty;
        try output.appendSlice(self.allocator, template_name);
        try output.append(self.allocator, '<');
        for (arguments, 0..) |argument, index| {
            if (index != 0) try output.appendSlice(self.allocator, ", ");
            try appendTypeName(self.allocator, &output, argument);
        }
        try output.append(self.allocator, '>');
        return output.toOwnedSlice(self.allocator);
    }

    fn fail(self: *Specializer, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn functionIsVisible(function: Ast.Function, visible_declarations: ?[]const Source.Position) bool {
    const positions = visible_declarations orelse return true;
    for (positions) |position| {
        if (positionsEqual(position, function.name_position)) return true;
    }
    return false;
}

fn positionsEqual(left: Source.Position, right: Source.Position) bool {
    return left.file == right.file and left.line == right.line and left.column == right.column;
}

fn typeNameToReturnType(value: Ast.TypeName) Ast.ReturnType {
    return switch (value) {
        .int => .int,
        .int8 => .int8,
        .int16 => .int16,
        .int32 => .int32,
        .int64 => .int64,
        .uint => .uint,
        .uint8 => .uint8,
        .uint16 => .uint16,
        .uint32 => .uint32,
        .uint64 => .uint64,
        .float => .float,
        .float32 => .float32,
        .float64 => .float64,
        .bool => .bool,
        .str => .str,
        .structure => |name| .{ .structure = name },
        .list => |element| .{ .list = element },
        .fixed_array => |array| .{ .fixed_array = array },
        .reference => |reference| .{ .reference = reference },
        .function => |function| .{ .function = function },
        .optional => |contained| .{ .optional = contained },
        .generic_structure, .type_parameter => unreachable,
    };
}

fn appendTypeName(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    value: Ast.TypeName,
) Allocator.Error!void {
    switch (value) {
        .int => try output.appendSlice(allocator, "int"),
        .int8 => try output.appendSlice(allocator, "int8"),
        .int16 => try output.appendSlice(allocator, "int16"),
        .int32 => try output.appendSlice(allocator, "int32"),
        .int64 => try output.appendSlice(allocator, "int64"),
        .uint => try output.appendSlice(allocator, "uint"),
        .uint8 => try output.appendSlice(allocator, "uint8"),
        .uint16 => try output.appendSlice(allocator, "uint16"),
        .uint32 => try output.appendSlice(allocator, "uint32"),
        .uint64 => try output.appendSlice(allocator, "uint64"),
        .float => try output.appendSlice(allocator, "float"),
        .float32 => try output.appendSlice(allocator, "float32"),
        .float64 => try output.appendSlice(allocator, "float64"),
        .bool => try output.appendSlice(allocator, "bool"),
        .str => try output.appendSlice(allocator, "str"),
        .structure => |name| try output.appendSlice(allocator, name),
        .generic_structure => |generic| {
            try output.appendSlice(allocator, generic.name);
            try output.append(allocator, '<');
            for (generic.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendTypeName(allocator, output, argument);
            }
            try output.append(allocator, '>');
        },
        .type_parameter => |name| try output.appendSlice(allocator, name),
        .list => |element| {
            try appendTypeName(allocator, output, element.*);
            try output.appendSlice(allocator, "[]");
        },
        .fixed_array => |array| {
            try appendTypeName(allocator, output, array.element.*);
            try output.append(allocator, '[');
            try output.appendSlice(allocator, array.length);
            try output.append(allocator, ']');
        },
        .reference => |reference| {
            try output.append(allocator, if (reference.mutable) '&' else '@');
            try appendTypeName(allocator, output, reference.target.*);
        },
        .function => |function| {
            try output.appendSlice(allocator, "func(");
            for (function.parameters, function.parameter_is_mutable_references, 0..) |parameter, is_mutable_reference, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (is_mutable_reference) try output.append(allocator, '&');
                try appendTypeName(allocator, output, parameter);
            }
            try output.append(allocator, ')');
            if (function.return_type) |return_type| {
                try output.append(allocator, ' ');
                try appendTypeName(allocator, output, return_type.*);
            }
        },
        .optional => |contained| {
            try appendTypeName(allocator, output, contained.*);
            try output.append(allocator, '?');
        },
    }
}
