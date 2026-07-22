const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("../Ast.zig");
const NativeInterface = @import("../NativeInterface.zig");
const Semantic = @import("../Semantic.zig");
const Source = @import("../Source.zig");
const Types = @import("Types.zig");

const Allocator = std.mem.Allocator;
const GenerateError = Allocator.Error;
const NativeResultShape = Types.NativeResultShape;
const NativeResultOwnedAction = Types.NativeResultOwnedAction;
pub fn generateStructureEqualitySignature(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.Structure,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "bool ");
    try self.generateStructureEqualityName(allocator, output, structure.generated_name);
    try output.appendSlice(allocator, "(const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " left");
    try output.appendSlice(allocator, ", const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " right");
    try output.append(allocator, ')');
}

pub fn generateStructureEqualityName(_: anytype, allocator: Allocator, output: *std.ArrayList(u8), generated_name: []const u8) !void {
    try output.appendSlice(allocator, "silexEqual");
    try output.appendSlice(allocator, generated_name);
}

pub fn generateStructureOperatorEqualitySignature(
    _: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.Structure,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "bool operator==(const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " left");
    try output.appendSlice(allocator, ", const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " right");
    try output.append(allocator, ')');
}

pub fn generateStructureFieldEquality(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    field: Semantic.StructureField,
) !void {
    switch (field.type) {
        .function => try output.appendSlice(allocator, "false"),
        .structure => |structure_type| {
            if (structure_type.is_class) {
                try output.appendSlice(allocator, "left.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " == right.");
                try output.appendSlice(allocator, field.generated_name);
            } else {
                try self.generateStructureEqualityName(allocator, output, structure_type.generated_name);
                try output.appendSlice(allocator, "(left.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ", right.");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            }
        },
        .optional => |contained| if (contained.* == .structure and !contained.*.structure.is_class) {
            try output.appendSlice(allocator, "((!left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && !right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value()) || (left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && ");
            try self.generateStructureEqualityName(allocator, output, contained.*.structure.generated_name);
            try output.appendSlice(allocator, "(*left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ", *right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ")))");
        } else {
            try output.appendSlice(allocator, "left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " == right.");
            try output.appendSlice(allocator, field.generated_name);
        },
        else => {
            try output.appendSlice(allocator, "left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " == right.");
            try output.appendSlice(allocator, field.generated_name);
        },
    }
}

pub fn generateStatements(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    statements: []const Semantic.Statement,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    for (statements) |statement| {
        try self.generateStatement(allocator, output, statement, indentation, is_main);
    }
}

pub fn generateTryPreludes(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    expression: *const Semantic.Expression,
    indentation: usize,
) GenerateError!void {
    switch (expression.value) {
        .move_expression => |move_value| try self.generateTryPreludes(allocator, output, move_value.operand, indentation),
        .borrow_expression => |borrow_value| try self.generateTryPreludes(allocator, output, borrow_value.operand, indentation),
        .try_expression => |try_value| {
            try self.generateTryPreludes(allocator, output, try_value.operand, indentation);
            if (expression.type != .void) {
                try self.indent(allocator, output, indentation);
                try output.appendSlice(allocator, "std::optional<");
                try self.appendCppType(allocator, output, expression.type);
                try output.append(allocator, '>');
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value;\n");
            }
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "{\n");
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "    auto ");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, try_value.operand);
            try output.appendSlice(allocator, ";\n");
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "    if (");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) return ", .{try_value.failure_variant_index}));
            try output.appendSlice(allocator, try_value.return_enum_generated_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}, ", .{try_value.failure_variant_index}));
            try output.appendSlice(allocator, "std::move(");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, ".get<");
            try self.appendCppType(allocator, output, try_value.error_type);
            try output.appendSlice(allocator, ">(0))};\n");
            if (expression.type != .void) {
                try self.indent(allocator, output, indentation);
                try output.appendSlice(allocator, "    ");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value.emplace(std::move(");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, ".get<");
                try self.appendCppType(allocator, output, expression.type);
                try output.appendSlice(allocator, ">(0)));\n");
            }
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .string_length => |value| try self.generateTryPreludes(allocator, output, value, indentation),
        .sequence_literal => |values| for (values) |value| try self.generateTryPreludes(allocator, output, value, indentation),
        .collection_method => |method| {
            try self.generateTryPreludes(allocator, output, method.object, indentation);
            for (method.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation);
        },
        .call => |call| for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation),
        .value_call => |call| {
            try self.generateTryPreludes(allocator, output, call.callee, indentation);
            if (call.owner) |owner| try self.generateTryPreludes(allocator, output, owner, indentation);
            for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation);
        },
        .lambda, .function_reference => {},
        .method_call => |call| {
            try self.generateTryPreludes(allocator, output, call.object, indentation);
            for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation);
        },
        .protocol_method_call => |call| {
            try self.generateTryPreludes(allocator, output, call.object, indentation);
            for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation);
        },
        .static_method_call => |call| for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation),
        .super_method_call => |call| for (call.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation),
        .cascade => |cascade| {
            try self.generateTryPreludes(allocator, output, cascade.object, indentation);
            for (cascade.operations) |operation| switch (operation) {
                .method_call => |call| try self.generateTryPreludes(allocator, output, call, indentation),
                .field_assignment => |assignment| try self.generateTryPreludes(allocator, output, assignment.value, indentation),
            };
        },
        .class_initializer => |initializer| for (initializer.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation),
        .structure_initializer => |initializer| for (initializer.fields) |field| try self.generateTryPreludes(allocator, output, field, indentation),
        .enum_initializer => |initializer| for (initializer.arguments) |argument| try self.generateTryPreludes(allocator, output, argument, indentation),
        .enum_raw_value => |value| try self.generateTryPreludes(allocator, output, value, indentation),
        .match_expression => |match_value| try self.generateTryPreludes(allocator, output, match_value.subject, indentation),
        .member_access => |member| try self.generateTryPreludes(allocator, output, member.object, indentation),
        .bound_function => |member| try self.generateTryPreludes(allocator, output, member.object, indentation),
        .adapt_function => |value| try self.generateTryPreludes(allocator, output, value, indentation),
        .optional_wrap => |value| try self.generateTryPreludes(allocator, output, value, indentation),
        .safe_access => |access| {
            try self.generateTryPreludes(allocator, output, access.receiver, indentation);
            try self.generateTryPreludes(allocator, output, access.end, indentation);
        },
        .index_access => |access| {
            try self.generateTryPreludes(allocator, output, access.object, indentation);
            try self.generateTryPreludes(allocator, output, access.index, indentation);
        },
        .slice_access => |access| {
            try self.generateTryPreludes(allocator, output, access.object, indentation);
            try self.generateTryPreludes(allocator, output, access.start, indentation);
            try self.generateTryPreludes(allocator, output, access.end, indentation);
        },
        .unary => |unary| try self.generateTryPreludes(allocator, output, unary.operand, indentation),
        .binary => |binary| {
            try self.generateTryPreludes(allocator, output, binary.left, indentation);
            try self.generateTryPreludes(allocator, output, binary.right, indentation);
        },
        .conversion => |conversion| try self.generateTryPreludes(allocator, output, conversion.operand, indentation),
        .protocol_conversion => |conversion| try self.generateTryPreludes(allocator, output, conversion.operand, indentation),
        .integer, .floating, .boolean, .null, .string, .cascade_target, .variable, .self, .owner_self, .static_field_access, .optional_unwrap => {},
    }
}

pub fn generateStatement(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    statement: Semantic.Statement,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    switch (statement) {
        .print => |argument| {
            try self.generateTryPreludes(allocator, output, argument, indentation);
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "std::cout << ");
            if (argument.type == .bool) try output.append(allocator, '(');
            if (argument.type == .int8 or argument.type == .uint8) try output.appendSlice(allocator, "static_cast<int>(");
            try self.generateExpression(allocator, output, argument);
            if (argument.type == .int8 or argument.type == .uint8) try output.append(allocator, ')');
            if (argument.type == .bool) try output.appendSlice(allocator, " ? \"true\" : \"false\")");
            try output.appendSlice(allocator, " << '\\n';\n");
        },
        .assertion => |assertion| {
            try self.generateTryPreludes(allocator, output, assertion.condition, indentation);
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "if (!");
            try self.generateCondition(allocator, output, .{ .expression = assertion.condition });
            try output.appendSlice(allocator, ") assertionRuntimeError(");
            try self.appendCppSourceLocation(allocator, output, assertion.position);
            try output.appendSlice(allocator, ", ");
            try self.generateExpression(allocator, output, assertion.message);
            try output.appendSlice(allocator, ");\n");
        },
        .panic_statement => |panic_value| {
            try self.generateTryPreludes(allocator, output, panic_value.message, indentation);
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "panicRuntimeError(");
            try self.appendCppSourceLocation(allocator, output, panic_value.position);
            try output.appendSlice(allocator, ", ");
            try self.generateExpression(allocator, output, panic_value.message);
            try output.appendSlice(allocator, ");\n");
        },
        .variable_declaration => |declaration| {
            try self.generateTryPreludes(allocator, output, declaration.initializer, indentation);
            try self.indent(allocator, output, indentation);
            if (declaration.capture_box.*) {
                try output.appendSlice(allocator, "auto ");
                try output.appendSlice(allocator, declaration.generated_name);
                try output.appendSlice(allocator, " = silexMake<SilexBinding<");
                try self.appendCppType(allocator, output, declaration.type);
                try output.appendSlice(allocator, ">>(");
                try self.generateExpression(allocator, output, declaration.initializer);
                try output.append(allocator, ')');
            } else {
                if (declaration.mutability == .immutable and declaration.type != .reference and !declaration.is_noncopyable) {
                    try output.appendSlice(allocator, "const ");
                }
                try self.appendCppType(allocator, output, declaration.type);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, declaration.generated_name);
                try output.appendSlice(allocator, " = ");
                try self.generateExpression(allocator, output, declaration.initializer);
            }
            try output.appendSlice(allocator, ";\n");
        },
        .assignment => |assignment| {
            try self.generateTryPreludes(allocator, output, assignment.target, indentation);
            if (assignment.value) |value| try self.generateTryPreludes(allocator, output, value, indentation);
            try self.indent(allocator, output, indentation);
            const checked_integer = self.isInteger(assignment.target.type) and assignment.operator != .assign;
            try self.generateExpression(allocator, output, assignment.target);
            if (checked_integer) {
                try output.appendSlice(allocator, " = ");
                try output.appendSlice(allocator, self.checkedAssignmentFunction(assignment.operator));
                try output.append(allocator, '(');
                try self.generateExpression(allocator, output, assignment.target);
                try output.appendSlice(allocator, ", ");
                if (assignment.value) |value| {
                    try self.generateExpression(allocator, output, value);
                } else {
                    try self.generateIntegerOne(allocator, output, assignment.target.type);
                }
                try self.generateRuntimeArguments(allocator, output, assignment.position, assignment.target.type);
                try output.append(allocator, ')');
            } else switch (assignment.operator) {
                .assign, .add, .subtract, .multiply, .divide => {
                    try output.appendSlice(allocator, self.assignmentOperatorText(assignment.operator));
                    try self.generateExpression(allocator, output, assignment.value.?);
                },
                .increment => try output.appendSlice(allocator, "++"),
                .decrement => try output.appendSlice(allocator, "--"),
            }
            try output.appendSlice(allocator, ";\n");
        },
        .if_statement => |if_statement| {
            switch (if_statement.condition) {
                .expression => |condition| try self.generateTryPreludes(allocator, output, condition, indentation),
                .binding => |binding| try self.generateTryPreludes(allocator, output, binding.source, indentation),
            }
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "if ");
            try self.generateCondition(allocator, output, if_statement.condition);
            try output.appendSlice(allocator, " {\n");
            try self.generateConditionalBindingDeclaration(allocator, output, if_statement.condition, indentation + 1);
            try self.generateStatements(allocator, output, if_statement.body, indentation + 1, is_main);
            try self.indent(allocator, output, indentation);
            for (if_statement.alternatives) |alternative| {
                try output.appendSlice(allocator, "} else if ");
                try self.generateCondition(allocator, output, alternative.condition);
                try output.appendSlice(allocator, " {\n");
                try self.generateConditionalBindingDeclaration(allocator, output, alternative.condition, indentation + 1);
                try self.generateStatements(allocator, output, alternative.body, indentation + 1, is_main);
                try self.indent(allocator, output, indentation);
            }
            if (if_statement.else_body) |else_body| {
                try output.appendSlice(allocator, "} else {\n");
                try self.generateStatements(allocator, output, else_body, indentation + 1, is_main);
                try self.indent(allocator, output, indentation);
            }
            try output.appendSlice(allocator, "}\n");
        },
        .while_statement => |while_statement| {
            if (while_statement.condition == .binding) {
                const binding = while_statement.condition.binding;
                try self.indent(allocator, output, indentation);
                try output.appendSlice(allocator, "while (true) {\n");
                try self.generateTryPreludes(allocator, output, while_statement.condition.binding.source, indentation + 1);
                try self.indent(allocator, output, indentation + 1);
                try output.appendSlice(allocator, switch (binding.mode) {
                    .copy, .move => "auto ",
                    .borrow => "const auto& ",
                });
                try output.appendSlice(allocator, binding.temporary_name);
                try output.appendSlice(allocator, " = ");
                try self.generateExpression(allocator, output, binding.source);
                try output.appendSlice(allocator, ";\n");
                try self.indent(allocator, output, indentation + 1);
                try output.appendSlice(allocator, "if (!");
                try output.appendSlice(allocator, binding.temporary_name);
                try output.appendSlice(allocator, ".has_value()) break;\n");
                try self.generateConditionalBindingDeclaration(allocator, output, while_statement.condition, indentation + 1);
                try self.generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
                try self.indent(allocator, output, indentation);
                try output.appendSlice(allocator, "}\n");
                return;
            }
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "while (true) {\n");
            try self.generateTryPreludes(allocator, output, while_statement.condition.expression, indentation + 1);
            try self.indent(allocator, output, indentation + 1);
            try output.appendSlice(allocator, "if (!");
            try self.generateCondition(allocator, output, while_statement.condition);
            try output.appendSlice(allocator, ") break;\n");
            try self.generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .for_statement => |for_statement| {
            switch (for_statement.source) {
                .collection => |collection| try self.generateTryPreludes(allocator, output, collection, indentation),
                .integer_range => |range| {
                    try self.generateTryPreludes(allocator, output, range.start, indentation);
                    try self.generateTryPreludes(allocator, output, range.end, indentation);
                },
            }
            switch (for_statement.source) {
                .collection => |collection| {
                    try self.indent(allocator, output, indentation);
                    try output.appendSlice(allocator, "for (");
                    try output.appendSlice(allocator, switch (for_statement.binding) {
                        .read => if (for_statement.element_noncopyable) "const auto& " else "auto ",
                        .immutable => "const auto& ",
                        .mutable => "auto& ",
                    });
                    try output.appendSlice(allocator, for_statement.generated_name);
                    if (for_statement.capture_box.*) try output.appendSlice(allocator, "Input");
                    try output.appendSlice(allocator, " : ");
                    try self.generateExpression(allocator, output, collection);
                    try output.appendSlice(allocator, ") {\n");
                    if (for_statement.capture_box.*) {
                        try self.indent(allocator, output, indentation + 1);
                        try output.appendSlice(allocator, "auto ");
                        try output.appendSlice(allocator, for_statement.generated_name);
                        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
                        try self.appendCppType(allocator, output, for_statement.element_type);
                        try output.appendSlice(allocator, ">>(");
                        try output.appendSlice(allocator, for_statement.generated_name);
                        try output.appendSlice(allocator, "Input);\n");
                    }
                    try self.generateStatements(allocator, output, for_statement.body, indentation + 1, is_main);
                    try self.indent(allocator, output, indentation);
                    try output.appendSlice(allocator, "}\n");
                },
                .integer_range => |range| try self.generateIntegerRangeStatement(
                    allocator,
                    output,
                    for_statement,
                    range,
                    indentation,
                    is_main,
                ),
            }
        },
        .break_statement => {
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "break;\n");
        },
        .continue_statement => {
            try self.indent(allocator, output, indentation);
            try output.appendSlice(allocator, "continue;\n");
        },
        .return_statement => |value| {
            if (value) |expression| try self.generateTryPreludes(allocator, output, expression, indentation);
            try self.indent(allocator, output, indentation);
            if (value) |expression| {
                try output.appendSlice(allocator, "return ");
                try self.generateExpression(allocator, output, expression);
                try output.appendSlice(allocator, ";\n");
            } else {
                try output.appendSlice(allocator, if (is_main) "return 0;\n" else "return;\n");
            }
        },
        .expression_statement => |expression| {
            if (expression.value == .match_expression and expression.type == .void) {
                try self.generateImperativeMatch(allocator, output, expression.value.match_expression, indentation, is_main);
                return;
            }
            try self.generateTryPreludes(allocator, output, expression, indentation);
            try self.indent(allocator, output, indentation);
            try self.generateExpression(allocator, output, expression);
            try output.appendSlice(allocator, ";\n");
        },
    }
}

pub fn generateMatchBindings(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    match_value: Semantic.Expression.Match,
    branch: Semantic.Expression.Match.Branch,
    multiline: bool,
    indentation: usize,
) GenerateError!void {
    for (branch.bindings, 0..) |binding, binding_index| {
        if (multiline) try self.indent(allocator, output, indentation);
        if (binding.capture_box.*) {
            try output.appendSlice(allocator, "auto ");
            try output.appendSlice(allocator, binding.generated_name);
            try output.appendSlice(allocator, " = silexMake<SilexBinding<");
            try self.appendCppType(allocator, output, binding.type);
            try output.appendSlice(allocator, ">>(");
        } else {
            if (match_value.mode == .borrow) try output.appendSlice(allocator, "const ");
            if (binding.mutability == .immutable and match_value.mode == .copy) try output.appendSlice(allocator, "const ");
            try self.appendCppType(allocator, output, binding.type);
            if (match_value.mode == .borrow) try output.append(allocator, '&');
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, binding.generated_name);
            try output.appendSlice(allocator, " = ");
        }
        if (match_value.mode == .move) try output.appendSlice(allocator, "std::move(");
        try output.appendSlice(allocator, match_value.temporary_name);
        try output.appendSlice(allocator, ".get<");
        try self.appendCppType(allocator, output, binding.type);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ">({d})", .{binding_index}));
        if (match_value.mode == .move) try output.append(allocator, ')');
        if (binding.capture_box.*) try output.append(allocator, ')');
        try output.appendSlice(allocator, if (multiline) ";\n" else "; ");
    }
}

pub fn generateImperativeMatch(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    match_value: Semantic.Expression.Match,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "{\n");
    try self.generateTryPreludes(allocator, output, match_value.subject, indentation + 1);
    try self.indent(allocator, output, indentation + 1);
    try output.appendSlice(allocator, switch (match_value.mode) {
        .copy => "const auto ",
        .move => "auto ",
        .borrow => "const auto& ",
    });
    try output.appendSlice(allocator, match_value.temporary_name);
    try output.appendSlice(allocator, " = ");
    try self.generateExpression(allocator, output, match_value.subject);
    try output.appendSlice(allocator, ";\n");
    for (match_value.branches, 0..) |branch, branch_index| {
        try self.indent(allocator, output, indentation + 1);
        if (branch.variant_index) |variant_index| {
            if (branch_index != 0) try output.appendSlice(allocator, "else ");
            try output.appendSlice(allocator, "if (");
            try output.appendSlice(allocator, match_value.temporary_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) {{\n", .{variant_index}));
        } else {
            try output.appendSlice(allocator, if (branch_index == 0) "{\n" else "else {\n");
        }
        try self.generateMatchBindings(allocator, output, match_value, branch, true, indentation + 2);
        switch (branch.body) {
            .statements => |statements| try self.generateStatements(allocator, output, statements, indentation + 2, is_main),
            .expression => unreachable,
        }
        try self.indent(allocator, output, indentation + 1);
        try output.appendSlice(allocator, "}\n");
    }
    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "}\n");
}

pub fn generateIntegerRangeStatement(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    for_statement: Semantic.Statement.For,
    range: Semantic.Statement.For.IntegerRange,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    std.debug.assert(!for_statement.capture_box.*);
    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, " = ");
    try self.generateExpression(allocator, output, range.start);
    try output.appendSlice(allocator, ";\n");

    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, " = ");
    try self.generateExpression(allocator, output, range.end);
    try output.appendSlice(allocator, ";\n");

    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_step_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, " < ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, " ? 1 : -1;\n");

    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "for (std::int64_t ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, "; ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " != ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, "; ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " += ");
    try output.appendSlice(allocator, range.generated_step_name);
    try output.appendSlice(allocator, ") {\n");

    try self.indent(allocator, output, indentation + 1);
    if (for_statement.binding != .mutable) try output.appendSlice(allocator, "const ");
    try output.appendSlice(allocator, "std::int64_t ");
    try output.appendSlice(allocator, for_statement.generated_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, ";\n");
    try self.generateStatements(allocator, output, for_statement.body, indentation + 1, is_main);
    try self.indent(allocator, output, indentation);
    try output.appendSlice(allocator, "}\n");
}

pub fn generateCondition(self: anytype, allocator: Allocator, output: *std.ArrayList(u8), condition: Semantic.Statement.Condition) !void {
    if (condition == .binding) {
        const binding = condition.binding;
        try output.appendSlice(allocator, switch (binding.mode) {
            .copy, .move => "(auto ",
            .borrow => "(const auto& ",
        });
        try output.appendSlice(allocator, binding.temporary_name);
        try output.appendSlice(allocator, " = ");
        try self.generateExpression(allocator, output, binding.source);
        try output.appendSlice(allocator, "; ");
        try output.appendSlice(allocator, binding.temporary_name);
        try output.appendSlice(allocator, ".has_value())");
        return;
    }
    const expression = condition.expression;
    const already_parenthesized = expression.value == .binary or expression.value == .unary;
    if (!already_parenthesized) try output.append(allocator, '(');
    try self.generateExpression(allocator, output, expression);
    if (!already_parenthesized) try output.append(allocator, ')');
}

pub fn generateConditionalBindingDeclaration(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    condition: Semantic.Statement.Condition,
    indentation: usize,
) !void {
    if (condition != .binding) return;
    const binding = condition.binding;
    try self.indent(allocator, output, indentation);
    if (binding.capture_box.*) {
        try output.appendSlice(allocator, "auto ");
        try output.appendSlice(allocator, binding.generated_name);
        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
        try self.appendCppType(allocator, output, binding.type);
        try output.appendSlice(allocator, ">>(*");
        try output.appendSlice(allocator, binding.temporary_name);
        try output.append(allocator, ')');
    } else {
        if (binding.mode == .borrow) try output.appendSlice(allocator, "const ");
        if (binding.mutability == .immutable and binding.mode == .copy) try output.appendSlice(allocator, "const ");
        try self.appendCppType(allocator, output, binding.type);
        if (binding.mode == .borrow) try output.append(allocator, '&');
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, binding.generated_name);
        try output.appendSlice(allocator, if (binding.mode == .move) " = std::move(*" else " = *");
        try output.appendSlice(allocator, binding.temporary_name);
        if (binding.mode == .move) try output.append(allocator, ')');
    }
    try output.appendSlice(allocator, ";\n");
}

pub fn generateExpression(self: anytype, allocator: Allocator, output: *std.ArrayList(u8), expression: *const Semantic.Expression) !void {
    switch (expression.value) {
        .integer => |value| {
            const literal = if (self.isUnsignedInteger(expression.type))
                try std.fmt.allocPrint(allocator, "{s}{{{d}ULL}}", .{ self.cppType(expression.type), value })
            else
                try std.fmt.allocPrint(allocator, "{s}{{{d}}}", .{ self.cppType(expression.type), value });
            try output.appendSlice(allocator, literal);
        },
        .floating => |lexeme| {
            try output.appendSlice(allocator, self.cppType(expression.type));
            try output.append(allocator, '{');
            try output.appendSlice(allocator, lexeme);
            try output.appendSlice(allocator, if (expression.type == .float) "F}" else "}");
        },
        .boolean => |value| try output.appendSlice(allocator, if (value) "true" else "false"),
        .null => try output.appendSlice(allocator, "std::nullopt"),
        .string => |value| {
            try output.appendSlice(allocator, "std::string{");
            try self.appendCppByteStringLiteral(allocator, output, value);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", {d}}}", .{value.len}));
        },
        .string_length => |argument| {
            try output.appendSlice(allocator, "silexStringLength(");
            try self.generateExpression(allocator, output, argument);
            try output.append(allocator, ')');
        },
        .protocol_method_call => |call| {
            try self.generateExpression(allocator, output, call.object);
            try output.append(allocator, '.');
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .sequence_literal => |values| {
            if (expression.type == .list) {
                try output.appendSlice(allocator, "silexMakeList<");
                try self.appendCppType(allocator, output, expression.type.list.*);
                try output.appendSlice(allocator, ">(");
            } else {
                try self.appendCppType(allocator, output, expression.type);
                try output.append(allocator, '{');
            }
            for (values, 0..) |value, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, value);
            }
            try output.append(allocator, if (expression.type == .list) ')' else '}');
        },
        .cascade_target => try output.appendSlice(allocator, "silexCascadeValue"),
        .cascade => |cascade| {
            try output.appendSlice(allocator, "silexCascade(");
            try self.generateExpression(allocator, output, cascade.object);
            try output.appendSlice(allocator, ", [&](auto& silexCascadeValue) {");
            for (cascade.operations) |operation| switch (operation) {
                .method_call => |method| {
                    try self.generateExpression(allocator, output, method);
                    try output.append(allocator, ';');
                },
                .field_assignment => |assignment| {
                    try output.appendSlice(allocator, "silexCascadeValue.");
                    try output.appendSlice(allocator, assignment.generated_name);
                    try output.appendSlice(allocator, " = ");
                    try self.generateExpression(allocator, output, assignment.value);
                    try output.append(allocator, ';');
                },
            };
            try output.appendSlice(allocator, " })");
        },
        .collection_method => |method| {
            switch (method.operation) {
                .count => {
                    try output.appendSlice(allocator, "silexCollectionCount(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".size(), ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .is_empty => {
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".empty()");
                },
                .append => {
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".push_back(");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .append_range => {
                    try output.appendSlice(allocator, "silexListAppendRange(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .prepend => {
                    try output.appendSlice(allocator, "silexListPrepend(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .insert => {
                    try output.appendSlice(allocator, "silexListInsert(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .take, .take_first => {
                    try output.appendSlice(allocator, "silexListTake(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    if (method.operation == .take) {
                        try self.generateExpression(allocator, output, method.arguments[0]);
                    } else {
                        try output.appendSlice(allocator, "std::int64_t{0}");
                    }
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .take_last => {
                    try output.appendSlice(allocator, "silexListTakeLast(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .replace => {
                    try output.appendSlice(allocator, "silexCollectionReplace(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .swap => {
                    try output.appendSlice(allocator, "silexCollectionSwap(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .reverse => {
                    try output.appendSlice(allocator, "silexCollectionReverse(");
                    try self.generateExpression(allocator, output, method.object);
                    try output.append(allocator, ')');
                },
                .clear => {
                    try self.generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".clear()");
                },
            }
        },
        .index_access => |access| {
            try output.appendSlice(allocator, "silexCollectionAt(");
            try self.generateExpression(allocator, output, access.object);
            try output.appendSlice(allocator, ", ");
            try self.generateExpression(allocator, output, access.index);
            try output.appendSlice(allocator, ", ");
            try self.appendCppSourceLocation(allocator, output, expression.position);
            try output.append(allocator, ')');
        },
        .slice_access => |access| {
            try output.appendSlice(allocator, if (access.borrowed and access.mutable) "([&]() { auto& silexSliceValues = " else "([&]() { const auto& silexSliceValues = ");
            try self.generateExpression(allocator, output, access.object);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceStart = ");
            try self.generateExpression(allocator, output, access.start);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceEnd = ");
            try self.generateExpression(allocator, output, access.end);
            try output.appendSlice(allocator, if (!access.borrowed)
                "; return silexCollectionSlice(silexSliceValues, silexSliceStart, silexSliceEnd); }())"
            else if (access.mutable)
                "; return silexCollectionMutableView(silexSliceValues, silexSliceStart, silexSliceEnd); }())"
            else
                "; return silexCollectionReadView(silexSliceValues, silexSliceStart, silexSliceEnd); }())");
        },
        .try_expression => |try_value| {
            if (expression.type == .void) {
                try output.appendSlice(allocator, "(void)0");
            } else {
                try output.appendSlice(allocator, "std::move(*");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value)");
            }
        },
        .move_expression => |move_value| {
            try output.appendSlice(allocator, "std::move(");
            try self.generateExpression(allocator, output, move_value.operand);
            try output.append(allocator, ')');
        },
        .borrow_expression => |borrow_value| {
            if (expression.type == .reference and expression.type.reference.target.* != .view) try output.append(allocator, '&');
            try self.generateExpression(allocator, output, borrow_value.operand);
        },
        .variable => |variable| {
            try output.appendSlice(allocator, variable.generated_name);
            if (variable.capture_box.*) try output.appendSlice(allocator, "->value");
        },
        .self => if (self.isClassType(expression.type))
            try output.appendSlice(allocator, "silexShare(this)")
        else
            try output.appendSlice(allocator, "*this"),
        .owner_self => try output.appendSlice(allocator, "silexOwner"),
        .call => |call| {
            if (call.is_native) {
                try self.generateNativeFunctionCall(allocator, output, call, expression.type);
            } else {
                try output.appendSlice(allocator, call.generated_name);
                try output.append(allocator, '(');
                for (call.arguments, 0..) |argument, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try self.generateExpression(allocator, output, argument);
                }
                try output.append(allocator, ')');
            }
        },
        .value_call => |call| {
            try self.generateExpression(allocator, output, call.callee);
            try output.append(allocator, '(');
            if (call.owner) |owner| {
                if (owner.value == .self) {
                    try output.appendSlice(allocator, "*this");
                } else if (owner.value == .owner_self) {
                    try output.appendSlice(allocator, "silexOwner");
                } else {
                    if (self.isClassType(owner.type)) try output.append(allocator, '*');
                    try self.generateExpression(allocator, output, owner);
                }
            }
            for (call.arguments, 0..) |argument, index| {
                if (index != 0 or call.owner != null) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .lambda => |lambda| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try self.appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.append(allocator, '[');
            var capture_index: usize = 0;
            if (lambda.captures_self) {
                try output.appendSlice(allocator, "this");
                capture_index += 1;
            }
            for (lambda.captures) |capture| {
                if (capture_index != 0) try output.appendSlice(allocator, ", ");
                if (!capture.by_value) try output.append(allocator, '&');
                try output.appendSlice(allocator, capture.generated_name);
                capture_index += 1;
            }
            try output.appendSlice(allocator, "](");
            var parameter_index: usize = 0;
            if (expression.type.function.owner) |owner| {
                try output.appendSlice(allocator, owner.generated_name);
                try output.appendSlice(allocator, "& silexOwner");
                parameter_index += 1;
            }
            for (lambda.parameters) |parameter| {
                if (parameter_index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter.type, parameter.mode);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
                parameter_index += 1;
            }
            try output.appendSlice(allocator, ") {\n");
            try self.generateCapturedParameterBindings(allocator, output, lambda.parameters, 1);
            try self.generateStatements(allocator, output, lambda.statements, 1, false);
            try output.append(allocator, '}');
            for (lambda.captures) |capture| {
                if (!capture.by_value) continue;
                try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, capture.generated_name);
            }
            if (lambda.captures_self and lambda.self_is_class) {
                try output.appendSlice(allocator, ", silexShare(this)");
            }
            try output.append(allocator, ')');
        },
        .method_call => |call| {
            if (call.object.value == .owner_self) {
                try output.appendSlice(allocator, "silexOwner.");
            } else if (call.object.value != .self) {
                try self.generateExpression(allocator, output, call.object);
                try output.appendSlice(allocator, if (self.isClassType(call.object.type)) "->" else ".");
            }
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .static_method_call => |call| {
            try output.appendSlice(allocator, call.owner_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .static_field_access => |access| {
            try output.appendSlice(allocator, access.owner_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, access.generated_name);
        },
        .super_method_call => |call| {
            try output.appendSlice(allocator, call.base_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .class_initializer => |initializer| {
            if (self.isClassType(expression.type)) {
                try output.appendSlice(allocator, "silexMake<");
                try output.appendSlice(allocator, initializer.generated_name);
                try output.appendSlice(allocator, ">(");
            } else {
                try output.appendSlice(allocator, initializer.generated_name);
                try output.append(allocator, '(');
            }
            for (initializer.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .structure_initializer => |initializer| {
            if (self.isClassType(expression.type)) {
                try output.appendSlice(allocator, "silexMake<");
                try output.appendSlice(allocator, initializer.generated_name);
                try output.appendSlice(allocator, ">(");
            } else {
                try output.appendSlice(allocator, initializer.generated_name);
                try output.append(allocator, '{');
            }
            for (initializer.fields, 0..) |field, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, field);
            }
            try output.append(allocator, if (self.isClassType(expression.type)) ')' else '}');
        },
        .enum_initializer => |initializer| {
            try output.appendSlice(allocator, initializer.enum_generated_name);
            try output.append(allocator, '{');
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "std::size_t{{{d}}}", .{initializer.variant_index}));
            for (initializer.arguments) |argument| {
                try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, argument);
            }
            try output.append(allocator, '}');
        },
        .enum_raw_value => |value| {
            try self.generateExpression(allocator, output, value);
            try output.appendSlice(allocator, ".rawValue()");
        },
        .match_expression => |match_value| {
            try output.appendSlice(allocator, "([&]() { ");
            try output.appendSlice(allocator, switch (match_value.mode) {
                .copy => "const auto ",
                .move => "auto ",
                .borrow => "const auto& ",
            });
            try output.appendSlice(allocator, match_value.temporary_name);
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, match_value.subject);
            try output.appendSlice(allocator, "; ");
            for (match_value.branches, 0..) |branch, branch_index| {
                if (branch.variant_index) |variant_index| {
                    if (branch_index != 0) try output.appendSlice(allocator, " else ");
                    try output.appendSlice(allocator, "if (");
                    try output.appendSlice(allocator, match_value.temporary_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) {{ ", .{variant_index}));
                } else {
                    try output.appendSlice(allocator, if (branch_index == 0) "{ " else " else { ");
                }
                try self.generateMatchBindings(allocator, output, match_value, branch, false, 0);
                switch (branch.body) {
                    .expression => |value| {
                        try output.appendSlice(allocator, "return ");
                        try self.generateExpression(allocator, output, value);
                        try output.appendSlice(allocator, "; }");
                    },
                    .statements => unreachable,
                }
            }
            try output.appendSlice(allocator, " std::abort(); }())");
        },
        .member_access => |member| {
            if (member.object.value == .owner_self) {
                try output.appendSlice(allocator, "silexOwner.");
            } else if (member.object.value != .self) {
                if (member.object.type == .reference and self.isClassType(member.object.type.reference.target.*)) {
                    try output.appendSlice(allocator, "(*");
                    try self.generateExpression(allocator, output, member.object);
                    try output.appendSlice(allocator, ")->");
                } else {
                    try self.generateExpression(allocator, output, member.object);
                    try output.appendSlice(allocator, if (self.isClassType(member.object.type) or member.object.type == .reference) "->" else ".");
                }
            }
            try output.appendSlice(allocator, member.generated_name);
        },
        .bound_function => |member| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try self.appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.appendSlice(allocator, if (self.isClassType(member.object.type))
                "[silexBoundOwner = "
            else
                "[&silexBoundOwner = ");
            try self.generateExpression(allocator, output, member.object);
            try output.appendSlice(allocator, "](");
            for (expression.type.function.parameters, expression.type.function.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexBoundArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, if (self.isClassType(member.object.type))
                ") { return silexBoundOwner->"
            else
                ") { return silexBoundOwner.");
            try output.appendSlice(allocator, member.generated_name);
            try output.appendSlice(allocator, if (self.isClassType(member.object.type))
                "(*silexBoundOwner"
            else
                "(silexBoundOwner");
            for (expression.type.function.parameters, 0..) |_, index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", silexBoundArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }");
            if (self.isClassType(member.object.type)) {
                try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, member.object);
            }
            try output.append(allocator, ')');
        },
        .function_reference => |generated_name| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try self.appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">([](");
            for (expression.type.function.parameters, expression.type.function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexFunctionArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return ");
            try output.appendSlice(allocator, generated_name);
            try output.append(allocator, '(');
            for (expression.type.function.parameters, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexFunctionArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); })");
        },
        .adapt_function => |value| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try self.appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.appendSlice(allocator, "[silexCallback = ");
            try self.generateExpression(allocator, output, value);
            try output.appendSlice(allocator, "](");
            const function = expression.type.function;
            try output.appendSlice(allocator, function.owner.?.generated_name);
            try output.appendSlice(allocator, "&");
            for (function.parameters, function.parameter_modes, 0..) |parameter_type, mode, index| {
                try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexAdaptedArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return silexCallback(");
            for (function.parameters, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexAdaptedArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }, ");
            try self.generateExpression(allocator, output, value);
            try output.append(allocator, ')');
        },
        .optional_wrap => |value| {
            try self.appendCppType(allocator, output, expression.type);
            try output.append(allocator, '{');
            try self.generateExpression(allocator, output, value);
            try output.append(allocator, '}');
        },
        .optional_unwrap => |variable| {
            try output.appendSlice(allocator, "(*");
            try output.appendSlice(allocator, variable.generated_name);
            if (variable.capture_box.*) try output.appendSlice(allocator, "->value");
            try output.append(allocator, ')');
        },
        .safe_access => |access| {
            try output.appendSlice(allocator, "[&]()");
            if (expression.type != .void) {
                try output.appendSlice(allocator, " -> ");
                try self.appendCppType(allocator, output, expression.type);
            }
            try output.appendSlice(allocator, " { auto&& silexOptionalValue = ");
            try self.generateExpression(allocator, output, access.receiver);
            if (expression.type == .void) {
                try output.appendSlice(allocator, "; if (silexOptionalValue.has_value()) { ");
                try self.generateExpression(allocator, output, access.end);
                try output.appendSlice(allocator, "; } }()");
            } else {
                try output.appendSlice(allocator, "; if (!silexOptionalValue.has_value()) return std::nullopt; return ");
                try self.generateExpression(allocator, output, access.end);
                try output.appendSlice(allocator, "; }()");
            }
        },
        .unary => |unary| {
            if (unary.operator == .numeric_negate and self.isInteger(expression.type) and unary.operand.value == .integer) {
                const magnitude = unary.operand.value.integer;
                const minimum_magnitude = self.integerMinimumMagnitude(expression.type);
                if (magnitude == minimum_magnitude) {
                    try output.appendSlice(allocator, "std::numeric_limits<");
                    try output.appendSlice(allocator, self.cppType(expression.type));
                    try output.appendSlice(allocator, ">::min()");
                } else {
                    const literal = try std.fmt.allocPrint(allocator, "{s}{{-{d}}}", .{ self.cppType(expression.type), magnitude });
                    try output.appendSlice(allocator, literal);
                }
                return;
            } else if (unary.operator == .numeric_negate and self.isInteger(expression.type)) {
                try output.appendSlice(allocator, "checkedNegate(");
            } else if (unary.operator == .dereference) {
                try output.appendSlice(allocator, "(*");
            } else if (unary.operator == .borrow) {
                if (expression.type == .reference and expression.type.reference.target.* != .view) try output.append(allocator, '&');
                try self.generateExpression(allocator, output, unary.operand);
                return;
            } else {
                try output.appendSlice(allocator, if (unary.operator == .logical_not) "(!" else "(-");
            }
            try self.generateExpression(allocator, output, unary.operand);
            if (unary.operator == .numeric_negate and self.isInteger(expression.type)) {
                try self.generateRuntimeArguments(allocator, output, expression.position, expression.type);
            }
            try output.append(allocator, ')');
        },
        .binary => |binary| {
            if (self.isInteger(expression.type) and self.isArithmetic(binary.operator)) {
                try output.appendSlice(allocator, self.checkedBinaryFunction(binary.operator));
                try output.append(allocator, '(');
                try self.generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, binary.right);
                try self.generateRuntimeArguments(allocator, output, expression.position, expression.type);
                try output.append(allocator, ')');
            } else if (self.isShift(binary.operator)) {
                try output.appendSlice(allocator, self.checkedShiftFunction(binary.operator));
                try output.append(allocator, '(');
                try self.generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, binary.right);
                try self.generateRuntimeArguments(allocator, output, expression.position, expression.type);
                try output.append(allocator, ')');
            } else if ((binary.operator == .equal or binary.operator == .not_equal) and binary.left.type == .optional and
                binary.right.type == .optional and binary.left.value != .null and binary.right.value != .null and
                binary.left.type.optional.* == .structure and !binary.left.type.optional.*.structure.is_class)
            {
                try output.append(allocator, '(');
                if (binary.operator == .not_equal) try output.append(allocator, '!');
                try output.appendSlice(allocator, "[&]() { const auto& silexOptionalLeft = ");
                try self.generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, "; const auto& silexOptionalRight = ");
                try self.generateExpression(allocator, output, binary.right);
                try output.appendSlice(allocator, "; return (!silexOptionalLeft.has_value() && !silexOptionalRight.has_value()) || (silexOptionalLeft.has_value() && silexOptionalRight.has_value() && ");
                try self.generateStructureEqualityName(allocator, output, binary.left.type.optional.*.structure.generated_name);
                try output.appendSlice(allocator, "(*silexOptionalLeft, *silexOptionalRight)); }())");
            } else if ((binary.operator == .equal or binary.operator == .not_equal) and binary.left.type == .structure and
                !binary.left.type.structure.is_class)
            {
                const structure_type = binary.left.type.structure;
                try output.append(allocator, '(');
                if (binary.operator == .not_equal) try output.append(allocator, '!');
                try self.generateStructureEqualityName(allocator, output, structure_type.generated_name);
                try output.append(allocator, '(');
                try self.generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try self.generateExpression(allocator, output, binary.right);
                try output.appendSlice(allocator, "))");
            } else {
                try output.append(allocator, '(');
                try self.generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, self.operatorText(binary.operator));
                try self.generateExpression(allocator, output, binary.right);
                try output.append(allocator, ')');
            }
        },
        .conversion => |conversion| {
            if (self.isClassType(conversion.target_type)) {
                try self.generateExpression(allocator, output, conversion.operand);
                return;
            }
            try output.appendSlice(allocator, "checkedConvert<");
            try output.appendSlice(allocator, self.cppType(conversion.target_type));
            try output.appendSlice(allocator, ">(");
            try self.generateExpression(allocator, output, conversion.operand);
            try self.generateRuntimeArguments(allocator, output, expression.position, conversion.operand.type);
            try output.appendSlice(allocator, ", \"");
            try output.appendSlice(allocator, self.silexTypeName(conversion.target_type));
            try output.appendSlice(allocator, "\")");
        },
        .protocol_conversion => |conversion| {
            try output.appendSlice(allocator, expression.type.protocol.generated_name);
            try output.appendSlice(allocator, "::make(");
            try self.generateExpression(allocator, output, conversion.operand);
            try output.appendSlice(allocator, ", &");
            try output.appendSlice(allocator, conversion.witness_name);
            try output.append(allocator, ')');
        },
    }
}
