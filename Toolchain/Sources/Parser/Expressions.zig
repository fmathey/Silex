const std = @import("std");
const Ast = @import("../Ast.zig");
const LexerModule = @import("../Lexer.zig");
const Source = @import("../Source.zig");

const Allocator = std.mem.Allocator;
const Token = LexerModule.Token;
const TokenTag = LexerModule.TokenTag;
const ParseError = Source.Error || Allocator.Error;

fn isComparisonOperator(tag: TokenTag) bool {
    return switch (tag) {
        .less, .less_equal, .greater, .greater_equal => true,
        else => false,
    };
}

pub fn parseExpression(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    return self.parseCascade(try self.parseLogicalOr(allow_line_breaks));
}

pub fn parseCascade(self: anytype, object: *Ast.Expression) ParseError!*Ast.Expression {
    if (self.current.tag != .dot_dot) return object;

    var operations: std.ArrayList(Ast.Expression.Cascade.Operation) = .empty;
    while (self.current.tag == .dot_dot) {
        try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected member name after '..'");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();

        if (self.current.tag == .left_parenthesis) {
            try self.advance();
            var arguments: std.ArrayList(*Ast.Expression) = .empty;
            while (self.current.tag != .right_parenthesis) {
                try arguments.append(self.allocator, try self.parseExpression(true));
                if (self.current.tag != .comma) break;
                try self.advance();
            }
            try self.expect(.right_parenthesis, "expected ')' after cascade method arguments");
            try operations.append(self.allocator, .{ .method_call = .{
                .name = name,
                .name_position = name_position,
                .arguments = try arguments.toOwnedSlice(self.allocator),
            } });
            continue;
        }

        if (self.current.tag != .equal) return self.fail("expected '(' or '=' after cascade member");
        try self.advance();
        try operations.append(self.allocator, .{ .field_assignment = .{
            .name = name,
            .name_position = name_position,
            .value = try self.parseLogicalOr(false),
        } });
    }

    const cascade = try self.newExpression(.{
        .position = object.position,
        .value = .{ .cascade = .{
            .object = object,
            .operations = try operations.toOwnedSlice(self.allocator),
        } },
    });
    return if (self.current.tag == .dot) self.parsePostfix(cascade) else cascade;
}

pub fn parseLogicalOr(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseLogicalAnd(allow_line_breaks);
    while (self.current.tag == .pipe_pipe and self.canContinueExpression(allow_line_breaks)) {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseLogicalAnd(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseLogicalAnd(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseEquality(allow_line_breaks);
    while (self.current.tag == .amp_amp and self.canContinueExpression(allow_line_breaks)) {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseEquality(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseEquality(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseComparison(allow_line_breaks);
    while ((self.current.tag == .equal_equal or self.current.tag == .bang_equal) and
        self.canContinueExpression(allow_line_breaks))
    {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseComparison(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseComparison(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseBitXor(allow_line_breaks);
    while (isComparisonOperator(self.current.tag) and self.canContinueExpression(allow_line_breaks)) {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseBitXor(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseBitXor(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseBitAnd(allow_line_breaks);
    while (self.current.tag == .caret and self.canContinueExpression(allow_line_breaks)) {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseBitAnd(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseBitAnd(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseShift(allow_line_breaks);
    while (self.current.tag == .amp and self.canContinueExpression(allow_line_breaks)) {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseShift(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseShift(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseAdditive(allow_line_breaks);
    while ((self.current.tag == .shift_left or self.current.tag == .shift_right) and
        self.canContinueExpression(allow_line_breaks))
    {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseAdditive(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseAdditive(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseMultiplicative(allow_line_breaks);
    while ((self.current.tag == .plus or self.current.tag == .minus) and
        self.canContinueExpression(allow_line_breaks))
    {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseMultiplicative(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseMultiplicative(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    var expression = try self.parseUnary(allow_line_breaks);
    while ((self.current.tag == .star or self.current.tag == .slash or self.current.tag == .percent) and
        self.canContinueExpression(allow_line_breaks))
    {
        const operator_token = self.current;
        try self.advance();
        const right = try self.parseUnary(allow_line_breaks);
        expression = try self.binaryExpression(expression, right, operator_token);
    }
    return expression;
}

pub fn parseUnary(self: anytype, allow_line_breaks: bool) ParseError!*Ast.Expression {
    if (self.current.tag == .at) {
        const operator_position = self.current.position;
        try self.advance();
        const operand = try self.parseUnary(allow_line_breaks);
        return self.newExpression(.{
            .position = operator_position,
            .value = .{ .borrow_expression = .{
                .operator_position = operator_position,
                .operand = operand,
            } },
        });
    }
    if (self.current.tag == .keyword_move) {
        const operator_position = self.current.position;
        try self.advance();
        const operand = try self.parseUnary(allow_line_breaks);
        return self.newExpression(.{
            .position = operator_position,
            .value = .{ .move_expression = .{
                .operator_position = operator_position,
                .operand = operand,
            } },
        });
    }
    if (self.current.tag == .keyword_try) {
        const operator_position = self.current.position;
        try self.advance();
        const operand = try self.parseUnary(allow_line_breaks);
        return self.newExpression(.{
            .position = operator_position,
            .value = .{ .try_expression = .{
                .operator_position = operator_position,
                .operand = operand,
            } },
        });
    }
    if (self.current.tag != .bang and self.current.tag != .minus and
        self.current.tag != .amp) return self.parseConversion();

    const operator_token = self.current;
    try self.advance();
    const operator: Ast.UnaryOperator = switch (operator_token.tag) {
        .bang => .logical_not,
        .minus => .numeric_negate,
        .amp => .borrow,
        else => unreachable,
    };
    const operand = try self.parseUnary(allow_line_breaks);
    return self.newExpression(.{
        .position = operator_token.position,
        .value = .{ .unary = .{
            .operator = operator,
            .operator_position = operator_token.position,
            .operand = operand,
        } },
    });
}

pub fn parseConversion(self: anytype) ParseError!*Ast.Expression {
    var expression = try self.parsePrimary();
    while (self.current.tag == .keyword_as) {
        const as_position = self.current.position;
        try self.advance();
        const target_type = try self.parseTypeNameAfter("expected scalar type after 'as'");
        expression = try self.newExpression(.{
            .position = expression.position,
            .value = .{ .conversion = .{
                .operand = expression,
                .target_type = target_type,
                .as_position = as_position,
            } },
        });
    }
    return expression;
}

pub fn parsePrimary(self: anytype) ParseError!*Ast.Expression {
    const token = self.current;
    switch (token.tag) {
        .integer => {
            try self.advance();
            return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .{ .integer = token.lexeme } }));
        },
        .floating => {
            try self.advance();
            return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .{ .floating = token.lexeme } }));
        },
        .keyword_true, .keyword_false => {
            try self.advance();
            return self.parsePostfix(try self.newExpression(.{
                .position = token.position,
                .value = .{ .boolean = token.tag == .keyword_true },
            }));
        },
        .keyword_null => {
            try self.advance();
            return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .null }));
        },
        .string => {
            try self.advance();
            return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .{ .string = token.lexeme } }));
        },
        .left_bracket => return self.parsePostfix(try self.parseSequenceLiteral()),
        .keyword_func => return self.parsePostfix(try self.parseLambda(false)),
        .keyword_deferred => {
            try self.advance();
            if (self.current.tag != .keyword_func) return self.fail("expected 'func' after 'deferred'");
            return self.parsePostfix(try self.parseLambda(true));
        },
        .keyword_super => return self.parseSuperMethodCall(),
        .keyword_match => return self.parsePostfix(try self.parseMatchExpression()),
        .identifier, .keyword_self => {
            return self.parseIdentifierExpression();
        },
        .left_parenthesis => {
            try self.advance();
            const expression = try self.parseExpression(true);
            try self.expect(.right_parenthesis, "expected ')'");
            return self.parsePostfix(expression);
        },
        else => return self.fail("expected expression"),
    }
}

pub fn parseMatchExpression(self: anytype) ParseError!*Ast.Expression {
    const position = self.current.position;
    try self.expect(.keyword_match, "expected 'match'");
    const subject = try self.parseExpression(false);
    try self.expect(.left_brace, "expected '{' after match expression");
    var branches: std.ArrayList(Ast.Expression.Match.Branch) = .empty;
    var statement_bodies: ?bool = null;
    while (self.current.tag != .right_brace and self.current.tag != .end) {
        const is_else = self.current.tag == .keyword_else;
        if (!is_else and self.current.tag != .identifier) return self.fail("expected enum variant or 'else' in match");
        const variant: ?[]const u8 = if (is_else) null else self.current.lexeme;
        const variant_position = self.current.position;
        try self.advance();
        var bindings: std.ArrayList(Ast.Expression.Match.Binding) = .empty;
        if (self.current.tag == .left_parenthesis) {
            if (is_else) return self.fail("an else match branch cannot bind associated values");
            try self.advance();
            if (self.current.tag == .right_parenthesis) return self.fail("a variant without associated values does not use parentheses in match");
            while (true) {
                const mutability: Ast.Mutability = if (self.current.tag == .keyword_var) mutability: {
                    try self.advance();
                    break :mutability .mutable;
                } else if (self.current.tag == .keyword_let) mutability: {
                    try self.advance();
                    break :mutability .immutable;
                } else .immutable;
                if (self.current.tag != .identifier) return self.fail("expected associated value binding");
                try bindings.append(self.allocator, .{
                    .name = self.current.lexeme,
                    .position = self.current.position,
                    .mutability = mutability,
                });
                try self.advance();
                if (self.current.tag != .comma) break;
                try self.advance();
                if (self.current.tag == .right_parenthesis) return self.fail("expected associated value binding after ','");
            }
            try self.expect(.right_parenthesis, "expected ')' after match bindings");
        }
        try self.expect(.fat_arrow, "expected '=>' after match pattern");
        const uses_statements = self.current.tag == .left_brace;
        if (statement_bodies) |expected| {
            if (expected != uses_statements) return self.fail("match branches cannot mix expressions and blocks");
        } else statement_bodies = uses_statements;
        const body: Ast.Expression.Match.Body = if (uses_statements) block_body: {
            const statements = try self.parseBlock();
            try self.expectStatementTerminator();
            break :block_body .{ .statements = statements };
        } else expression_body: {
            const value = try self.parseExpression(false);
            try self.expectStatementTerminator();
            break :expression_body .{ .expression = value };
        };
        try branches.append(self.allocator, .{
            .variant = variant,
            .variant_position = variant_position,
            .bindings = try bindings.toOwnedSlice(self.allocator),
            .body = body,
        });
        if (is_else and self.current.tag != .right_brace) return self.fail("else must be the last match branch");
    }
    try self.expect(.right_brace, "expected '}' after match branches");
    if (branches.items.len == 0) return self.failAt(position, "a match requires at least one branch");
    return self.newExpression(.{
        .position = position,
        .value = .{ .match_expression = .{
            .subject = subject,
            .branches = try branches.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn parseSuperMethodCall(self: anytype) ParseError!*Ast.Expression {
    const position = self.current.position;
    try self.advance();
    try self.expect(.dot, "expected '.' after 'super'");
    if (self.current.tag != .identifier) return self.fail("expected method name after 'super.'");
    const name = self.current.lexeme;
    const name_position = self.current.position;
    try self.advance();
    if (self.current.tag != .left_parenthesis) return self.fail("'super' can only call a base method");
    const invocation = try self.parseInvocationArguments();
    return self.parsePostfix(try self.newExpression(.{
        .position = position,
        .value = .{ .super_method_call = .{
            .position = position,
            .name = name,
            .name_position = name_position,
            .arguments = switch (invocation) {
                .positional => |arguments| arguments,
                .named => &.{},
            },
            .named_fields = switch (invocation) {
                .positional => null,
                .named => |fields| fields,
            },
        } },
    }));
}

pub fn parseLambda(self: anytype, deferred: bool) ParseError!*Ast.Expression {
    const position = self.current.position;
    try self.expect(.keyword_func, "expected 'func'");
    const parameters = try self.parseParameters();
    const return_type: Ast.ReturnType = if (self.current.tag == .left_brace)
        .void
    else
        try self.parseReturnType();
    return self.newExpression(.{
        .position = position,
        .value = .{ .lambda = .{
            .position = position,
            .deferred = deferred,
            .parameters = parameters,
            .return_type = return_type,
            .statements = try self.parseBlock(),
        } },
    });
}

pub fn parseSequenceLiteral(self: anytype) ParseError!*Ast.Expression {
    const position = self.current.position;
    try self.expect(.left_bracket, "expected '['");
    var values: std.ArrayList(*Ast.Expression) = .empty;
    while (self.current.tag != .right_bracket) {
        try values.append(self.allocator, try self.parseExpression(true));
        if (self.current.tag != .comma) break;
        try self.advance();
    }
    try self.expect(.right_bracket, "expected ']' after sequence literal");
    return self.newExpression(.{ .position = position, .value = .{ .sequence_literal = try values.toOwnedSlice(self.allocator) } });
}

pub fn parseIdentifierExpression(self: anytype) ParseError!*Ast.Expression {
    const token = self.current;
    try self.advance();
    return self.parseIdentifierExpressionAfterToken(token);
}

pub fn parseIdentifierExpressionAfterToken(self: anytype, token: Token) ParseError!*Ast.Expression {
    if (token.tag != .keyword_self and self.current.tag == .less and self.genericStaticMemberFollows()) {
        const arguments = try self.parseTypeArguments(token.lexeme);
        return self.parsePostfix(try self.parseStaticMember(.{ .generic_structure = .{
            .name = token.lexeme,
            .arguments = arguments,
        } }, token.position));
    }
    const type_arguments = if (token.tag != .keyword_self and self.current.tag == .less and self.genericInvocationFollows())
        try self.parseTypeArguments(null)
    else
        &.{};
    var expression = if (token.tag == .keyword_self)
        try self.newExpression(.{ .position = token.position, .value = .self })
    else if (self.current.tag == .left_parenthesis)
        try self.parseCallAfterName(token.lexeme, token.position, type_arguments)
    else if (type_arguments.len != 0)
        return self.fail("type arguments must be followed by an invocation")
    else
        try self.newExpression(.{ .position = token.position, .value = .{ .identifier = token.lexeme } });

    expression = try self.parsePostfix(expression);
    if (self.current.tag == .left_brace and try self.looksLikeLegacyStructureInitializer()) {
        return self.fail("structure initializers use 'Type(...)', not 'Type { ... }'");
    }
    return expression;
}

pub fn parsePostfix(self: anytype, initial: *Ast.Expression) ParseError!*Ast.Expression {
    var expression = initial;
    while (self.current.tag == .dot or self.current.tag == .question_dot or self.current.tag == .left_bracket or self.current.tag == .left_parenthesis) {
        if (self.current.tag == .left_parenthesis) {
            const position = self.current.position;
            const arguments = try self.parseCallArguments();
            expression = try self.newExpression(.{
                .position = expression.position,
                .value = .{ .value_call = .{
                    .callee = expression,
                    .parenthesis_position = position,
                    .arguments = arguments,
                } },
            });
            continue;
        }
        if (self.current.tag == .left_bracket) {
            const bracket_position = self.current.position;
            try self.advance();
            const first = try self.parseExpression(true);
            if (self.current.tag == .colon) {
                try self.advance();
                const end = try self.parseExpression(true);
                try self.expect(.right_bracket, "expected ']' after collection slice");
                expression = try self.newExpression(.{
                    .position = expression.position,
                    .value = .{ .slice_access = .{
                        .object = expression,
                        .start = first,
                        .end = end,
                        .bracket_position = bracket_position,
                    } },
                });
            } else {
                try self.expect(.right_bracket, "expected ']' after collection index");
                expression = try self.newExpression(.{
                    .position = expression.position,
                    .value = .{ .index_access = .{
                        .object = expression,
                        .index = first,
                        .bracket_position = bracket_position,
                    } },
                });
            }
            continue;
        }
        const safe = self.current.tag == .question_dot;
        try self.advance();
        if (self.current.tag != .identifier) return self.fail(if (safe) "expected member name after '?.'" else "expected field name after '.'");
        const name = self.current.lexeme;
        const position = self.current.position;
        try self.advance();
        if (!safe and self.current.tag == .less and self.genericStaticMemberFollows()) {
            const prefix = (try self.expressionPath(expression)) orelse return self.fail("a generic type qualifier must be a name");
            const owner_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, name });
            const arguments = try self.parseTypeArguments(owner_name);
            expression = try self.parseStaticMember(.{ .generic_structure = .{
                .name = owner_name,
                .arguments = arguments,
            } }, expression.position);
            continue;
        }
        const type_arguments = if (!safe and self.current.tag == .less and self.genericInvocationFollows())
            try self.parseTypeArguments(null)
        else
            &.{};
        if (self.current.tag == .left_parenthesis) {
            if (safe) {
                const invocation = try self.parseInvocationArguments();
                expression = try self.newExpression(.{ .position = expression.position, .value = .{ .safe_member_access = .{
                    .object = expression,
                    .name = name,
                    .name_position = position,
                    .arguments = switch (invocation) {
                        .positional => |values| values,
                        .named => &.{},
                    },
                    .named_fields = switch (invocation) {
                        .positional => null,
                        .named => |fields| fields,
                    },
                } } });
            } else expression = try self.parseMethodCall(expression, name, position, type_arguments);
        } else if (type_arguments.len != 0) {
            return self.fail("type arguments must be followed by an invocation");
        } else {
            expression = try self.newExpression(.{
                .position = expression.position,
                .value = if (safe) .{ .safe_member_access = .{
                    .object = expression,
                    .name = name,
                    .name_position = position,
                } } else .{ .member_access = .{
                    .object = expression,
                    .name = name,
                    .name_position = position,
                } },
            });
        }
    }
    return expression;
}

pub fn parseStaticMember(self: anytype, owner: Ast.TypeName, owner_position: Source.Position) ParseError!*Ast.Expression {
    try self.expect(.dot, "expected '.' after static member type");
    if (self.current.tag != .identifier) return self.fail("expected static member name after type");
    const name = self.current.lexeme;
    const name_position = self.current.position;
    try self.advance();
    if (self.current.tag == .left_parenthesis) {
        const invocation = try self.parseInvocationArguments();
        return self.newExpression(.{
            .position = owner_position,
            .value = .{ .static_method_call = .{
                .owner = owner,
                .owner_position = owner_position,
                .name = name,
                .name_position = name_position,
                .arguments = switch (invocation) {
                    .positional => |values| values,
                    .named => &.{},
                },
                .named_fields = switch (invocation) {
                    .positional => null,
                    .named => |fields| fields,
                },
            } },
        });
    }
    return self.newExpression(.{
        .position = owner_position,
        .value = .{ .static_field_access = .{
            .owner = owner,
            .owner_position = owner_position,
            .name = name,
            .name_position = name_position,
        } },
    });
}

pub fn parseCallAfterName(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    type_arguments: []const Ast.TypeName,
) ParseError!*Ast.Expression {
    const arguments = try self.parseInvocationArguments();
    return self.newExpression(.{
        .position = position,
        .value = .{ .call = .{
            .name = name,
            .name_position = position,
            .type_arguments = type_arguments,
            .arguments = switch (arguments) {
                .positional => |values| values,
                .named => &.{},
            },
            .named_fields = switch (arguments) {
                .positional => null,
                .named => |fields| fields,
            },
        } },
    });
}

pub const InvocationArguments = union(enum) {
    positional: []const *Ast.Expression,
    named: []const Ast.Expression.FieldInitializer,
};

pub fn parseInvocationArguments(self: anytype) ParseError!InvocationArguments {
    try self.expect(.left_parenthesis, "expected '('");
    if (self.current.tag == .right_parenthesis) {
        try self.advance();
        return .{ .positional = &.{} };
    }

    if (try self.currentStartsNamedField()) {
        var fields: std.ArrayList(Ast.Expression.FieldInitializer) = .empty;
        while (true) {
            if (!(try self.currentStartsNamedField())) {
                return self.fail("cannot mix positional arguments and named fields");
            }
            const field_name = self.current.lexeme;
            const field_position = self.current.position;
            try self.advance();
            try self.expect(.colon, "expected ':' after field name");
            if (self.current.tag == .comma or self.current.tag == .right_parenthesis) {
                return self.fail("expected value after ':'");
            }
            try fields.append(self.allocator, .{
                .name = field_name,
                .position = field_position,
                .value = try self.parseExpression(true),
            });
            if (self.current.tag != .comma) break;
            try self.advance();
            if (self.current.tag == .right_parenthesis) break;
        }
        try self.expect(.right_parenthesis, "expected ')' after invocation");
        return .{ .named = try fields.toOwnedSlice(self.allocator) };
    }

    var values: std.ArrayList(*Ast.Expression) = .empty;
    while (true) {
        try values.append(self.allocator, try self.parseExpression(true));
        if (self.current.tag != .comma) break;
        try self.advance();
        if (try self.currentStartsNamedField()) {
            return self.fail("cannot mix positional arguments and named fields");
        }
    }
    try self.expect(.right_parenthesis, "expected ')' after invocation");
    return .{ .positional = try values.toOwnedSlice(self.allocator) };
}

pub fn currentStartsNamedField(self: anytype) ParseError!bool {
    if (self.current.tag != .identifier) return false;
    var lexer = self.lexer;
    return (try lexer.next()).tag == .colon;
}

pub fn looksLikeLegacyStructureInitializer(self: anytype) ParseError!bool {
    if (self.current.tag != .left_brace) return false;
    var lexer = self.lexer;
    if ((try lexer.next()).tag != .identifier) return false;
    return (try lexer.next()).tag == .colon;
}

pub fn parseCallArguments(self: anytype) ParseError![]const *Ast.Expression {
    try self.expect(.left_parenthesis, "expected '('");
    var arguments: std.ArrayList(*Ast.Expression) = .empty;
    while (self.current.tag != .right_parenthesis) {
        try arguments.append(self.allocator, try self.parseExpression(true));
        if (self.current.tag != .comma) break;
        try self.advance();
    }
    try self.expect(.right_parenthesis, "expected ')'");
    return arguments.toOwnedSlice(self.allocator);
}

pub fn parseMethodCall(
    self: anytype,
    object: *Ast.Expression,
    name: []const u8,
    position: Source.Position,
    type_arguments: []const Ast.TypeName,
) ParseError!*Ast.Expression {
    const arguments = try self.parseInvocationArguments();
    return self.newExpression(.{
        .position = object.position,
        .value = .{ .method_call = .{
            .object = object,
            .name = name,
            .name_position = position,
            .type_arguments = type_arguments,
            .arguments = switch (arguments) {
                .positional => |values| values,
                .named => &.{},
            },
            .named_fields = switch (arguments) {
                .positional => null,
                .named => |fields| fields,
            },
        } },
    });
}

pub fn parseTypeParameters(self: anytype, declaration_kind: []const u8) ParseError![]const Ast.TypeParameter {
    try self.expect(.less, "expected '<'");
    if (self.current.tag == .greater or self.current.tag == .shift_right) {
        const message = try std.fmt.allocPrint(self.allocator, "a generic {s} requires at least one type parameter", .{declaration_kind});
        return self.fail(message);
    }
    var parameters: std.ArrayList(Ast.TypeParameter) = .empty;
    while (true) {
        if (self.current.tag != .identifier) return self.fail("expected type parameter name");
        if (std.mem.eql(u8, self.current.lexeme, "Result")) return self.fail("type name 'Result' is reserved");
        for (parameters.items) |parameter| {
            if (std.mem.eql(u8, parameter.name, self.current.lexeme)) {
                return self.fail("type parameter is already declared");
            }
        }
        try parameters.append(self.allocator, .{
            .name = self.current.lexeme,
            .position = self.current.position,
        });
        try self.advance();
        if (self.current.tag == .colon) {
            try self.advance();
            const constraint_position = self.current.position;
            parameters.items[parameters.items.len - 1].constraint = .{
                .name = try self.parseQualifiedName("expected protocol name after ':'"),
                .position = constraint_position,
            };
        }
        if (self.current.tag != .comma) break;
        try self.advance();
        if (self.current.tag == .greater or self.current.tag == .shift_right) {
            return self.fail("expected type parameter name after ','");
        }
    }
    try self.expectTypeArgumentClose();
    return parameters.toOwnedSlice(self.allocator);
}

pub fn parseTypeArguments(self: anytype, owner_name: ?[]const u8) ParseError![]const Ast.TypeName {
    try self.expect(.less, "expected '<'");
    if (self.current.tag == .greater or self.current.tag == .shift_right) {
        return self.fail("type arguments cannot be empty");
    }
    var arguments: std.ArrayList(Ast.TypeName) = .empty;
    while (true) {
        if (self.current.tag == .keyword_void) {
            if (owner_name == null or !std.mem.eql(u8, owner_name.?, "Result")) {
                return self.fail("void cannot be used as a type argument");
            }
            if (arguments.items.len != 0) return self.fail("Result error type cannot be 'void'");
            try arguments.append(self.allocator, .void);
            try self.advance();
        } else try arguments.append(self.allocator, try self.parseTypeNameAfter("expected type argument"));
        if (self.current.tag != .comma) break;
        try self.advance();
        if (self.current.tag == .greater or self.current.tag == .shift_right) {
            return self.fail("expected type argument after ','");
        }
    }
    try self.expectTypeArgumentClose();
    return arguments.toOwnedSlice(self.allocator);
}

pub fn expectTypeArgumentClose(self: anytype) ParseError!void {
    if (self.current.tag == .greater) {
        try self.advance();
        return;
    }
    if (self.current.tag == .shift_right) {
        const token = self.current;
        self.previous = .{ .tag = .greater, .lexeme = token.lexeme[0..1], .position = token.position, .start = token.start, .end = token.start + 1 };
        self.current = .{
            .tag = .greater,
            .lexeme = token.lexeme[1..2],
            .start = token.start + 1,
            .end = token.end,
            .position = .{
                .file = token.position.file,
                .line = token.position.line,
                .column = token.position.column + 1,
            },
        };
        return;
    }
    return self.fail("expected '>' after type arguments");
}

pub fn genericInvocationFollows(self: anytype) bool {
    var probe = self.*;
    _ = probe.parseTypeArguments(null) catch return self.malformedGenericSuffixFollows(.left_parenthesis);
    return probe.current.tag == .left_parenthesis;
}

pub fn genericStaticMemberFollows(self: anytype) bool {
    var probe = self.*;
    _ = probe.parseTypeArguments(null) catch return self.malformedGenericSuffixFollows(.dot);
    if (probe.current.tag != .dot) return false;
    probe.advance() catch return false;
    return probe.current.tag == .identifier;
}

pub fn malformedGenericSuffixFollows(self: anytype, suffix: TokenTag) bool {
    if (self.current.tag != .less) return false;
    var lexer = self.lexer;
    var depth: usize = 1;
    while (depth != 0) {
        const token = lexer.next() catch return false;
        switch (token.tag) {
            .less => depth += 1,
            .greater => depth -= 1,
            .shift_right => {
                if (depth < 2) return false;
                depth -= 2;
            },
            .end => return false,
            else => {},
        }
    }
    if ((lexer.next() catch return false).tag != suffix) return false;
    return suffix != .dot or (lexer.next() catch return false).tag == .identifier;
}

pub fn expressionPath(self: anytype, expression: *const Ast.Expression) ParseError!?[]const u8 {
    return switch (expression.value) {
        .identifier => |name| name,
        .member_access => |member| if (try self.expressionPath(member.object)) |prefix|
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name })
        else
            null,
        else => null,
    };
}

pub fn binaryExpression(
    self: anytype,
    left: *Ast.Expression,
    right: *Ast.Expression,
    operator_token: Token,
) ParseError!*Ast.Expression {
    const operator: Ast.BinaryOperator = switch (operator_token.tag) {
        .pipe_pipe => .logical_or,
        .amp_amp => .logical_and,
        .equal_equal => .equal,
        .bang_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,
        .plus => .add,
        .minus => .subtract,
        .shift_left => .shift_left,
        .shift_right => .shift_right,
        .amp => .bit_and,
        .caret => .bit_xor,
        .star => .multiply,
        .slash => .divide,
        .percent => .remainder,
        else => unreachable,
    };
    return self.newExpression(.{
        .position = left.position,
        .value = .{ .binary = .{
            .operator = operator,
            .operator_position = operator_token.position,
            .left = left,
            .right = right,
        } },
    });
}
