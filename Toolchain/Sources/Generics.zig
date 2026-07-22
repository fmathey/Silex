const std = @import("std");
const Ast = @import("Ast.zig");
const Parser = @import("Parser.zig").Parser;
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

const result_type_parameters = [_]Ast.TypeParameter{
    .{ .name = "T", .position = .{ .line = 1, .column = 1 } },
    .{ .name = "E", .position = .{ .line = 1, .column = 1 } },
};
const result_success_types = [_]Ast.TypeName{.{ .type_parameter = "T" }};
const result_failure_types = [_]Ast.TypeName{.{ .type_parameter = "E" }};
const result_variants = [_]Ast.EnumVariant{
    .{ .name = "success", .position = .{ .line = 1, .column = 1 }, .associated_types = &result_success_types },
    .{ .name = "failure", .position = .{ .line = 1, .column = 1 }, .associated_types = &result_failure_types },
};
const intrinsic_result = Ast.Enum{
    .is_public = true,
    .position = .{ .line = 1, .column = 1 },
    .name = "Result",
    .name_position = .{ .line = 1, .column = 1 },
    .type_parameters = &result_type_parameters,
    .variants = &result_variants,
};

const intrinsic_function_source =
    \\func map_error<T, E, F>(result:Result<T,E>, transform:func(E) F) Result<T,F> {
    \\    match move result {
    \\        success(var value) => { return Result<T,F>.success(move value) }
    \\        failure(var error) => {
    \\            return Result<T,F>.failure(transform(move error))
    \\        }
    \\    }
    \\    panic("invalid intrinsic Result variant")
    \\}
    \\func map_error<E, F>(result:Result<void,E>, transform:func(E) F) Result<void,F> {
    \\    match move result {
    \\        success => { return Result<void,F>.success() }
    \\        failure(var error) => {
    \\            return Result<void,F>.failure(transform(move error))
    \\        }
    \\    }
    \\    panic("invalid intrinsic Result variant")
    \\}
;

const FunctionSpecialization = struct {
    template_position: Source.Position,
    name: []const u8,
    state: State,
};

const MethodSpecialization = struct {
    target_name: []const u8,
    template_position: Source.Position,
    name: []const u8,
    state: State,
    method: ?Ast.Function = null,
};

pub const Specializer = struct {
    allocator: Allocator,
    program: Ast.Program,
    enums: std.ArrayList(Ast.Enum) = .empty,
    structures: std.ArrayList(Ast.Structure) = .empty,
    functions: std.ArrayList(Ast.Function) = .empty,
    function_templates: []const Ast.Function = &.{},
    enum_specializations: std.ArrayList(EnumSpecialization) = .empty,
    structure_specializations: std.ArrayList(StructureSpecialization) = .empty,
    function_specializations: std.ArrayList(FunctionSpecialization) = .empty,
    method_specializations: std.ArrayList(MethodSpecialization) = .empty,
    active_constraint_protocols: []const []const u8 = &.{},
    active_extension_visibility_file: ?usize = null,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, program: Ast.Program) Specializer {
        return .{ .allocator = allocator, .program = program };
    }

    pub fn specialize(self: *Specializer) SpecializeError!Ast.Program {
        var intrinsic_parser = Parser.init(self.allocator, intrinsic_function_source);
        const intrinsic_program = intrinsic_parser.parse() catch |err| {
            self.diagnostic = intrinsic_parser.diagnostic;
            return err;
        };
        var function_templates: std.ArrayList(Ast.Function) = .empty;
        try function_templates.appendSlice(self.allocator, intrinsic_program.functions);
        try function_templates.appendSlice(self.allocator, self.program.functions);
        self.function_templates = try function_templates.toOwnedSlice(self.allocator);

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

        for (self.method_specializations.items) |specialization| {
            const method = specialization.method orelse continue;
            for (self.structures.items) |*structure| {
                if (!std.mem.eql(u8, structure.name, specialization.target_name)) continue;
                var methods: std.ArrayList(Ast.Function) = .empty;
                try methods.appendSlice(self.allocator, structure.methods);
                try methods.append(self.allocator, method);
                structure.methods = try methods.toOwnedSlice(self.allocator);
                break;
            }
        }

        var protocols: std.ArrayList(Ast.Protocol) = .empty;
        for (self.program.protocols) |protocol| {
            var requirements: std.ArrayList(Ast.Function) = .empty;
            for (protocol.requirements) |requirement| {
                try requirements.append(self.allocator, try self.rewriteFunction(requirement, &.{}));
            }
            var rewritten = protocol;
            rewritten.requirements = try requirements.toOwnedSlice(self.allocator);
            try protocols.append(self.allocator, rewritten);
        }

        return .{
            .enums = try self.enums.toOwnedSlice(self.allocator),
            .protocols = try protocols.toOwnedSlice(self.allocator),
            .extensions = self.program.extensions,
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
        if (std.mem.eql(u8, name, "Result")) return &intrinsic_result;
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
        if (std.mem.eql(u8, template_name, "map_error")) {
            if (arguments.len == 3 and arguments[0] == .void) {
                return self.fail(position, "map_error for Result<void,E> expects 2 type arguments: E and F");
            }
            if (arguments.len >= 2 and arguments[arguments.len - 1] == .void) {
                return self.fail(position, "map_error target error type cannot be 'void'");
            }
        }
        const name = try self.genericTypeName(template_name, arguments);
        var generic_count: usize = 0;
        var matching_count: usize = 0;
        var expected_arity: ?usize = null;
        var arities_match = true;

        for (self.function_templates) |*function| {
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
        try self.validateTypeArgumentConstraints(template.type_parameters, arguments, position);
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

        var concrete = try self.rewriteFunction(template, bindings);
        concrete.name = name;
        concrete.type_parameters = &.{};
        try self.functions.append(self.allocator, concrete);
        self.function_specializations.items[specialization_index].state = .done;
    }

    fn instantiateMethods(
        self: *Specializer,
        template_name: []const u8,
        arguments: []const Ast.TypeName,
        visibility_file: usize,
        position: Source.Position,
    ) SpecializeError![]const u8 {
        const name = try self.genericTypeName(template_name, arguments);
        var generic_count: usize = 0;
        var matching_arity: usize = 0;
        var expected_arity: ?usize = null;
        var arities_match = true;
        var instantiated = false;
        var constrained_candidate: ?*const Ast.Function = null;
        for (self.program.extensions) |extension| {
            for (extension.methods) |*method| {
                if (method.type_parameters.len == 0 or
                    !std.mem.eql(u8, method.name, template_name)) continue;
                if (method.extension_visible_files) |visible_files| {
                    if (!fileSetContains(visible_files, visibility_file)) continue;
                }
                generic_count += 1;
                if (expected_arity) |expected| {
                    if (expected != method.type_parameters.len) arities_match = false;
                } else expected_arity = method.type_parameters.len;
                if (method.type_parameters.len != arguments.len) continue;
                matching_arity += 1;
                constrained_candidate = method;
                if (!self.typeArgumentsSatisfyConstraints(method.type_parameters, arguments, visibility_file)) continue;
                try self.instantiateMethod(extension.target, method.*, arguments, name, position);
                instantiated = true;
            }
        }
        if (generic_count != 0 and matching_arity == 0) {
            if (arities_match) {
                const count = expected_arity.?;
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic extension method '{s}' expects {d} type argument{s}, found {d}",
                    .{ template_name, count, if (count == 1) "" else "s", arguments.len },
                );
                return self.fail(position, message);
            }
            const message = try std.fmt.allocPrint(self.allocator, "no generic extension method '{s}' accepts {d} type arguments", .{ template_name, arguments.len });
            return self.fail(position, message);
        }
        if (!instantiated and constrained_candidate != null) {
            try self.validateTypeArgumentConstraints(constrained_candidate.?.type_parameters, arguments, position);
        }
        return name;
    }

    fn genericExtensionMethodRequiresArguments(self: *const Specializer, name: []const u8, visibility_file: usize) bool {
        var generic_visible = false;
        for (self.program.structures) |structure| {
            for (structure.methods) |method| {
                if (method.type_parameters.len == 0 and std.mem.eql(u8, method.name, name)) return false;
            }
        }
        for (self.program.extensions) |extension| {
            for (extension.methods) |method| {
                if (!std.mem.eql(u8, method.name, name)) continue;
                if (method.extension_visible_files) |visible_files| {
                    if (!fileSetContains(visible_files, visibility_file)) continue;
                }
                if (method.type_parameters.len == 0) return false;
                generic_visible = true;
            }
        }
        return generic_visible;
    }

    fn instantiateMethod(
        self: *Specializer,
        target_name: []const u8,
        template: Ast.Function,
        arguments: []const Ast.TypeName,
        name: []const u8,
        position: Source.Position,
    ) SpecializeError!void {
        for (self.method_specializations.items) |specialization| {
            if (!positionsEqual(specialization.template_position, template.name_position)) continue;
            if (std.mem.eql(u8, specialization.name, name)) return;
            if (specialization.state == .visiting) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "generic extension method '{s}' recursively expands with different type arguments",
                    .{template.name},
                );
                return self.fail(position, message);
            }
        }

        const specialization_index = self.method_specializations.items.len;
        try self.method_specializations.append(self.allocator, .{
            .target_name = target_name,
            .template_position = template.name_position,
            .name = name,
            .state = .visiting,
        });
        const bindings = try self.allocator.alloc(Binding, arguments.len);
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

        var concrete = try self.rewriteFunction(template, bindings);
        concrete.name = name;
        concrete.type_parameters = &.{};
        self.method_specializations.items[specialization_index].method = concrete;
        self.method_specializations.items[specialization_index].state = .done;
    }

    fn typeArgumentsSatisfyConstraints(
        self: *const Specializer,
        parameters: []const Ast.TypeParameter,
        arguments: []const Ast.TypeName,
        source_file: usize,
    ) bool {
        for (parameters, arguments) |parameter, argument| {
            const constraint = parameter.constraint orelse continue;
            if (!self.typeConformsTo(argument, constraint.name, source_file)) return false;
        }
        return true;
    }

    fn validateTypeArgumentConstraints(
        self: *Specializer,
        parameters: []const Ast.TypeParameter,
        arguments: []const Ast.TypeName,
        position: Source.Position,
    ) SpecializeError!void {
        for (parameters, arguments) |parameter, argument| {
            const constraint = parameter.constraint orelse continue;
            if (self.typeConformsTo(argument, constraint.name, position.file)) continue;
            var argument_name: std.ArrayList(u8) = .empty;
            try appendTypeName(self.allocator, &argument_name, argument);
            const message = try std.fmt.allocPrint(
                self.allocator,
                "type argument '{s}' does not conform to protocol '{s}' required by '{s}'",
                .{ try argument_name.toOwnedSlice(self.allocator), constraint.name, parameter.name },
            );
            return self.fail(position, message);
        }
    }

    fn typeConformsTo(
        self: *const Specializer,
        value: Ast.TypeName,
        protocol_name: []const u8,
        source_file: usize,
    ) bool {
        const structure_name = switch (value) {
            .structure => |name| name,
            else => return false,
        };
        return self.structureConformsTo(structure_name, protocol_name, source_file, 0);
    }

    fn structureConformsTo(
        self: *const Specializer,
        structure_name: []const u8,
        protocol_name: []const u8,
        source_file: usize,
        depth: usize,
    ) bool {
        if (depth > self.program.structures.len + self.structures.items.len) return false;
        const structure = self.findAvailableStructure(structure_name) orelse return false;
        for (structure.conformances) |conformance| {
            if (!std.mem.eql(u8, conformance.name, protocol_name)) continue;
            if (conformance.extension_visible_files) |visible_files| {
                if (depth != 0 or !fileSetContains(visible_files, source_file)) continue;
            }
            return true;
        }
        if (structure.base) |base| {
            // Before module resolution, the parser temporarily stores a
            // first protocol in the base slot because ':' is intentionally
            // ambiguous between a class parent and a protocol.
            if (self.findProtocol(base.name) != null) {
                return std.mem.eql(u8, base.name, protocol_name);
            }
            return self.structureConformsTo(base.name, protocol_name, source_file, depth + 1);
        }
        return false;
    }

    fn findAvailableStructure(self: *const Specializer, name: []const u8) ?*const Ast.Structure {
        for (self.structures.items) |*structure| {
            if (std.mem.eql(u8, structure.name, name)) return structure;
        }
        for (self.program.structures) |*structure| {
            if (std.mem.eql(u8, structure.name, name)) return structure;
        }
        return null;
    }

    fn findProtocol(self: *const Specializer, name: []const u8) ?*const Ast.Protocol {
        for (self.program.protocols) |*protocol| {
            if (std.mem.eql(u8, protocol.name, name)) return protocol;
        }
        return null;
    }

    fn hasVisibleGenericFunction(
        self: *const Specializer,
        name: []const u8,
        visible_declarations: ?[]const Source.Position,
    ) bool {
        for (self.function_templates) |function| {
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

    fn activeConstraintRequires(self: *const Specializer, method_name: []const u8) bool {
        for (self.active_constraint_protocols) |protocol_name| {
            const protocol = self.findProtocol(protocol_name) orelse continue;
            for (protocol.requirements) |requirement| {
                if (std.mem.eql(u8, requirement.name, method_name)) return true;
            }
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

fn fileSetContains(files: []const usize, target: usize) bool {
    for (files) |file| if (file == target) return true;
    return false;
}

fn positionsEqual(left: Source.Position, right: Source.Position) bool {
    return left.file == right.file and left.line == right.line and left.column == right.column;
}

fn typeNameToReturnType(value: Ast.TypeName) Ast.ReturnType {
    return switch (value) {
        .void => .void,
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
        .view => |element| .{ .view = element },
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
        .void => try output.appendSlice(allocator, "void"),
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
        .view => |element| {
            try appendTypeName(allocator, output, element.*);
            try output.appendSlice(allocator, "[..]");
        },
        .reference => |reference| {
            try output.append(allocator, if (reference.mutable) '&' else '@');
            try appendTypeName(allocator, output, reference.target.*);
        },
        .function => |function| {
            try output.appendSlice(allocator, "func(");
            for (function.parameters, function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (mode == .borrow) try output.append(allocator, '@');
                if (mode == .mutable_reference) try output.append(allocator, '&');
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

test "specialize protocol constrained generic functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User : Named { func name() str { return "Ada" } }
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { print(label<User>(User())) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    var found = false;
    for (program.functions) |function| {
        if (std.mem.startsWith(u8, function.name, "label<")) found = true;
    }
    try std.testing.expect(found);
}

test "specialize generic types in protocol requirements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Reader { func read(buffer:&uint8[..]) Result<int,str> }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 1), program.protocols.len);
    try std.testing.expect(program.protocols[0].requirements[0].return_type == .structure);
    try std.testing.expect(std.mem.startsWith(
        u8,
        program.protocols[0].requirements[0].return_type.structure,
        "Result<int, str>",
    ));
}

test "reject a type argument without declared protocol conformance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User { func name() str { return "Ada" } }
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { print(label<User>(User())) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    try std.testing.expectError(error.InvalidSource, specializer.specialize());
    try std.testing.expectEqualStrings(
        "type argument 'User' does not conform to protocol 'Named' required by 'T'",
        specializer.diagnostic.?.message,
    );
}

test "accept inherited protocol conformance for a type argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\class Entity : Named { public func name() str { return "entity" } }
        \\class Player : Entity {}
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { var player = Player(); print(label<Player>(player)) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    _ = try specializer.specialize();
}

test "specialize a constrained generic enum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User : Named { func name() str { return "Ada" } }
        \\enum Event<T : Named> { value(T) }
        \\func main() { let event = Event<User>.value(User()) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 1), program.enums.len);
}

test "specialize generic extension methods and reuse identical calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Catalog {}
        \\extend Catalog {
        \\    func identity<T>(value:T) T { return value }
        \\    func select<Key, Value>(key:Key, value:Value?) Value? { return value }
        \\    func transform<T>(values:T[], callback:func(T) T) T? {
        \\        let first:T = values[0]
        \\        return callback(first)
        \\    }
        \\    func repeat<T>(value:T, count:int) T {
        \\        if count == 0 { return value }
        \\        return self.repeat<T>(value, count - 1)
        \\    }
        \\}
        \\func main() {
        \\    var catalog = Catalog()
        \\    print(catalog.identity<int>(1))
        \\    print(catalog.identity<int>(2))
        \\    print(catalog.identity<str>("ok"))
        \\    let selected = catalog.select<int, str>(1, "value")
        \\    let transformed = catalog.transform<int>([1], func(value:int) int { return value })
        \\    print(catalog.repeat<int>(3, 1))
        \\}
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 5), program.structures[0].methods.len);
    try std.testing.expectEqualStrings("identity<int>", program.structures[0].methods[0].name);
    try std.testing.expectEqualStrings("identity<str>", program.structures[0].methods[1].name);
    try std.testing.expectEqualStrings("select<int, str>", program.structures[0].methods[2].name);
    try std.testing.expectEqualStrings("transform<int>", program.structures[0].methods[3].name);
    try std.testing.expectEqualStrings("repeat<int>", program.structures[0].methods[4].name);
}

test "diagnose generic extension method arguments and constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var missing_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity(1)) }
    );
    var missing = Specializer.init(allocator, try missing_parser.parse());
    try std.testing.expectError(error.InvalidSource, missing.specialize());
    try std.testing.expectEqualStrings("generic extension method 'identity' requires explicit type arguments", missing.diagnostic.?.message);

    var arity_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity<int, str>(1)) }
    );
    var arity = Specializer.init(allocator, try arity_parser.parse());
    try std.testing.expectError(error.InvalidSource, arity.specialize());
    try std.testing.expectEqualStrings("generic extension method 'identity' expects 1 type argument, found 2", arity.diagnostic.?.message);

    var constraint_parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct Box {}
        \\struct Value {}
        \\extend Box { func label<T:Named>(value:T) str { return value.name() } }
        \\func main() { var box = Box(); print(box.label<Value>(Value())) }
    );
    var constraint = Specializer.init(allocator, try constraint_parser.parse());
    try std.testing.expectError(error.InvalidSource, constraint.specialize());
    try std.testing.expectEqualStrings(
        "type argument 'Value' does not conform to protocol 'Named' required by 'T'",
        constraint.diagnostic.?.message,
    );

    var concrete_parser = Parser.init(allocator,
        \\struct Box { func identity(value:int) int { return value } }
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity(1)) }
    );
    var concrete = Specializer.init(allocator, try concrete_parser.parse());
    const concrete_program = try concrete.specialize();
    try std.testing.expectEqual(@as(usize, 1), concrete_program.structures[0].methods.len);

    var expansion_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box {
        \\    func expand<T>(value:T) { self.expand<T[]>([value]) }
        \\}
        \\func main() { var box = Box(); box.expand<int>(1) }
    );
    var expansion = Specializer.init(allocator, try expansion_parser.parse());
    try std.testing.expectError(error.InvalidSource, expansion.specialize());
    try std.testing.expectEqualStrings(
        "generic extension method 'expand' recursively expands with different type arguments",
        expansion.diagnostic.?.message,
    );
}
