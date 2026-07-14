const std = @import("std");
const Ast = @import("Ast.zig");
const LexerModule = @import("Lexer.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const Token = LexerModule.Token;
const TokenTag = LexerModule.TokenTag;
const ParseError = Source.Error || Allocator.Error;

pub const Parser = struct {
    allocator: Allocator,
    lexer: LexerModule.Lexer,
    current: Token = undefined,
    previous: Token = undefined,
    started: bool = false,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, source: []const u8) Parser {
        return .{ .allocator = allocator, .lexer = .init(source) };
    }

    pub fn initFile(allocator: Allocator, source: []const u8, file: usize) Parser {
        return .{ .allocator = allocator, .lexer = .initFile(source, file) };
    }

    pub fn parse(self: *Parser) !Ast.Program {
        try self.advance();
        var imports: std.ArrayList(Ast.Import) = .empty;
        var uses: std.ArrayList(Ast.Use) = .empty;
        var structures: std.ArrayList(Ast.Structure) = .empty;
        var functions: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .end) {
            if (self.current.tag == .keyword_import) {
                try imports.append(self.allocator, try self.parseImport());
            } else if (self.current.tag == .keyword_use) {
                try uses.append(self.allocator, try self.parseUse(false));
            } else if (self.current.tag == .keyword_pub) {
                try self.advance();
                if (self.current.tag == .keyword_use) {
                    try uses.append(self.allocator, try self.parseUse(true));
                } else if (self.current.tag == .keyword_struct) {
                    try structures.append(self.allocator, try self.parseStructure(true));
                } else if (self.current.tag == .keyword_func) {
                    try functions.append(self.allocator, try self.parseFunction(true));
                } else return self.fail("expected 'struct', 'func', or 'use' after 'pub'");
            } else if (self.current.tag == .keyword_struct) {
                try structures.append(self.allocator, try self.parseStructure(false));
            } else if (self.current.tag == .keyword_func) {
                try functions.append(self.allocator, try self.parseFunction(false));
            } else {
                return self.fail("expected import, use, struct, or func declaration");
            }
        }
        return .{
            .imports = try imports.toOwnedSlice(self.allocator),
            .uses = try uses.toOwnedSlice(self.allocator),
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
    }

    fn parseImport(self: *Parser) ParseError!Ast.Import {
        const position = self.current.position;
        try self.advance();
        const path = try self.parseQualifiedName("expected module name after 'import'");
        const alias = try self.parseOptionalAlias();
        try self.expectStatementTerminator();
        return .{ .path = path, .alias = alias, .position = position };
    }

    fn parseUse(self: *Parser, is_public: bool) ParseError!Ast.Use {
        const position = self.current.position;
        try self.advance();
        const path = try self.parseQualifiedName("expected declaration path after 'use'");
        const alias = try self.parseOptionalAlias();
        try self.expectStatementTerminator();
        return .{ .path = path, .alias = alias, .is_public = is_public, .position = position };
    }

    fn parseOptionalAlias(self: *Parser) ParseError!?[]const u8 {
        if (self.current.tag != .keyword_as) return null;
        try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected alias after 'as'");
        const alias = self.current.lexeme;
        try self.advance();
        return alias;
    }

    fn parseQualifiedName(self: *Parser, message: []const u8) ParseError![]const u8 {
        if (self.current.tag != .identifier) return self.fail(message);
        var result = self.current.lexeme;
        try self.advance();
        while (self.current.tag == .dot) {
            try self.advance();
            if (self.current.tag != .identifier) return self.fail("expected name after '.'");
            result = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ result, self.current.lexeme });
            try self.advance();
        }
        return result;
    }

    fn parseStructure(self: *Parser, is_public: bool) ParseError!Ast.Structure {
        const position = self.current.position;
        try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected struct name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        try self.expect(.left_brace, "expected '{'");
        var fields: std.ArrayList(Ast.StructureField) = .empty;
        var methods: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            if (self.current.tag == .keyword_func) {
                try methods.append(self.allocator, try self.parseFunction(false));
                continue;
            }
            if (self.current.tag != .identifier) return self.fail("expected field name");
            const field_name = self.current.lexeme;
            const field_position = self.current.position;
            try self.advance();
            try self.expect(.colon, "expected ':' after field name");
            const field_type = try self.parseTypeName();
            var initializer: ?*Ast.Expression = null;
            if (self.current.tag == .equal) {
                try self.advance();
                initializer = try self.parseExpression(false);
            }
            try fields.append(self.allocator, .{
                .name = field_name,
                .position = field_position,
                .type = field_type,
                .initializer = initializer,
            });
            try self.expectStatementTerminator();
        }
        try self.expect(.right_brace, "expected '}'");
        return .{
            .is_public = is_public,
            .position = position,
            .name = name,
            .name_position = name_position,
            .fields = try fields.toOwnedSlice(self.allocator),
            .methods = try methods.toOwnedSlice(self.allocator),
        };
    }

    fn parseFunction(self: *Parser, is_public: bool) ParseError!Ast.Function {
        const position = self.current.position;
        try self.expect(.keyword_func, "expected 'func'");
        if (self.current.tag != .identifier) return self.fail("expected function name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        const parameters = try self.parseParameters();
        const return_type: Ast.ReturnType = if (self.current.tag == .left_brace)
            .void
        else
            try self.parseReturnType();
        return .{
            .is_public = is_public,
            .position = position,
            .name = name,
            .name_position = name_position,
            .return_type = return_type,
            .parameters = parameters,
            .statements = try self.parseBlock(),
        };
    }

    fn parseReturnType(self: *Parser) ParseError!Ast.ReturnType {
        if (self.current.tag == .keyword_void) {
            try self.advance();
            return .void;
        }
        const type_name = try self.parseTypeNameAfter("expected function return type");
        return switch (type_name) {
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
        };
    }

    fn parseParameters(self: *Parser) ParseError![]const Ast.Parameter {
        try self.expect(.left_parenthesis, "expected '('");
        var parameters: std.ArrayList(Ast.Parameter) = .empty;
        while (self.current.tag != .right_parenthesis) {
            if (self.current.tag != .identifier) return self.fail("expected parameter name");
            const name = self.current.lexeme;
            const position = self.current.position;
            try self.advance();
            try self.expect(.colon, "expected ':' after parameter name");
            const is_mutable_reference = self.current.tag == .amp;
            if (is_mutable_reference) try self.advance();
            try parameters.append(self.allocator, .{
                .name = name,
                .position = position,
                .type = try self.parseTypeName(),
                .is_mutable_reference = is_mutable_reference,
            });
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        try self.expect(.right_parenthesis, "expected ')'");
        return parameters.toOwnedSlice(self.allocator);
    }

    fn parseBlock(self: *Parser) ParseError![]const Ast.Statement {
        try self.expect(.left_brace, "expected '{'");
        var statements: std.ArrayList(Ast.Statement) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            try statements.append(self.allocator, try self.parseStatement());
        }
        try self.expect(.right_brace, "expected '}'");
        return statements.toOwnedSlice(self.allocator);
    }

    fn parseStatement(self: *Parser) ParseError!Ast.Statement {
        return switch (self.current.tag) {
            .keyword_print => self.parsePrint(),
            .keyword_let => self.parseVariableDeclaration(.immutable),
            .keyword_var => self.parseVariableDeclaration(.mutable),
            .keyword_if => self.parseIf(),
            .keyword_while => self.parseWhile(),
            .keyword_for => self.parseFor(),
            .keyword_break => self.parseLoopControl(.break_statement),
            .keyword_continue => self.parseLoopControl(.continue_statement),
            .keyword_return => self.parseReturn(),
            .identifier, .keyword_self => self.parseIdentifierStatement(),
            else => self.fail("expected statement"),
        };
    }

    fn parsePrint(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '('");
        const argument = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')'");
        try self.expectStatementTerminator();
        return .{ .print = .{ .position = position, .argument = argument } };
    }

    fn parseVariableDeclaration(self: *Parser, mutability: Ast.Mutability) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();

        if (self.current.tag != .identifier) return self.fail("expected variable name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();

        var annotation: ?Ast.TypeName = null;
        if (self.current.tag == .colon) {
            try self.advance();
            annotation = try self.parseTypeName();
        }

        var initializer: ?*Ast.Expression = null;
        if (self.current.tag == .equal) {
            try self.advance();
            initializer = try self.parseExpression(false);
        } else if (annotation == null) {
            return self.failAt(name_position, "variable declaration requires a type or initializer");
        }
        try self.expectStatementTerminator();
        return .{ .variable_declaration = .{
            .position = position,
            .name = name,
            .name_position = name_position,
            .mutability = mutability,
            .annotation = annotation,
            .initializer = initializer,
        } };
    }

    fn parseTypeName(self: *Parser) ParseError!Ast.TypeName {
        return self.parseTypeNameAfter("expected type name after ':'");
    }

    fn parseTypeNameAfter(self: *Parser, message: []const u8) ParseError!Ast.TypeName {
        const type_name: Ast.TypeName = if (self.current.tag == .identifier)
            .{ .structure = try self.parseQualifiedName(message) }
        else switch (self.current.tag) {
            .keyword_int => .int,
            .keyword_int8 => .int8,
            .keyword_int16 => .int16,
            .keyword_int32 => .int32,
            .keyword_int64 => .int64,
            .keyword_uint => .uint,
            .keyword_uint8 => .uint8,
            .keyword_uint16 => .uint16,
            .keyword_uint32 => .uint32,
            .keyword_uint64 => .uint64,
            .keyword_float => .float,
            .keyword_float32 => .float32,
            .keyword_float64 => .float64,
            .keyword_bool => .bool,
            .keyword_str => .str,
            else => return self.fail(message),
        };
        if (type_name != .structure) try self.advance();
        var result = type_name;
        while (self.current.tag == .left_bracket) {
            try self.advance();
            if (self.current.tag == .right_bracket) {
                try self.advance();
                const element = try self.newTypeName(result);
                result = .{ .list = element };
                continue;
            }
            if (self.current.tag != .integer) return self.fail("expected array length or ']'");
            const length = self.current.lexeme;
            try self.advance();
            try self.expect(.right_bracket, "expected ']' after array length");
            const element = try self.newTypeName(result);
            result = .{ .fixed_array = .{ .element = element, .length = length } };
        }
        return result;
    }

    fn parseIdentifierStatement(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        const target = try self.parseExpression(false);
        if (assignmentOperator(self.current.tag)) |operator| {
            try self.advance();
            var value: ?*Ast.Expression = null;
            if (operator != .increment and operator != .decrement) {
                value = try self.parseExpression(false);
            }
            try self.expectStatementTerminator();
            return .{ .assignment = .{
                .position = position,
                .target = target,
                .operator = operator,
                .value = value,
            } };
        }
        if (target.value == .call or target.value == .method_call or target.value == .cascade) {
            try self.expectStatementTerminator();
            return .{ .expression_statement = target };
        }
        return self.fail("expected assignment or function call");
    }

    fn parseIf(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '('");
        const condition = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')'");
        const body = try self.parseBlock();
        var else_body: ?[]const Ast.Statement = null;
        if (self.current.tag == .keyword_else) {
            try self.advance();
            else_body = try self.parseBlock();
        }
        return .{ .if_statement = .{
            .position = position,
            .condition = condition,
            .body = body,
            .else_body = else_body,
        } };
    }

    fn parseWhile(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '('");
        const condition = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')'");
        const body = try self.parseBlock();
        return .{ .while_statement = .{ .position = position, .condition = condition, .body = body } };
    }

    fn parseFor(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '('");
        const mutable = self.current.tag == .keyword_var;
        if (mutable) try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected iteration variable name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        try self.expect(.keyword_in, "expected 'in' after iteration variable");
        const iterable = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')' after for source");
        return .{ .for_statement = .{
            .position = position,
            .name = name,
            .name_position = name_position,
            .mutable = mutable,
            .iterable = iterable,
            .body = try self.parseBlock(),
        } };
    }

    fn parseLoopControl(self: *Parser, comptime tag: std.meta.Tag(Ast.Statement)) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expectStatementTerminator();
        return @unionInit(Ast.Statement, @tagName(tag), position);
    }

    fn parseReturn(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        var value: ?*Ast.Expression = null;
        if (self.current.tag != .semicolon and self.current.tag != .right_brace and
            self.current.tag != .end and self.current.position.line == position.line)
        {
            value = try self.parseExpression(false);
        }
        try self.expectStatementTerminator();
        return .{ .return_statement = .{ .position = position, .value = value } };
    }

    fn parseExpression(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return self.parseCascade(try self.parseLogicalOr(allow_line_breaks));
    }

    fn parseCascade(self: *Parser, object: *Ast.Expression) ParseError!*Ast.Expression {
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

        return self.newExpression(.{
            .position = object.position,
            .value = .{ .cascade = .{
                .object = object,
                .operations = try operations.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn parseLogicalOr(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseLogicalAnd(allow_line_breaks);
        while (self.current.tag == .pipe_pipe and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseLogicalAnd(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseLogicalAnd(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseEquality(allow_line_breaks);
        while (self.current.tag == .amp_amp and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseEquality(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseEquality(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
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

    fn parseComparison(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseAdditive(allow_line_breaks);
        while (isComparisonOperator(self.current.tag) and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseAdditive(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseAdditive(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
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

    fn parseMultiplicative(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseUnary(allow_line_breaks);
        while ((self.current.tag == .star or self.current.tag == .slash) and
            self.canContinueExpression(allow_line_breaks))
        {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseUnary(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseUnary(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
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

    fn parseConversion(self: *Parser) ParseError!*Ast.Expression {
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

    fn parsePrimary(self: *Parser) ParseError!*Ast.Expression {
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
            .string => {
                try self.advance();
                return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .{ .string = token.lexeme } }));
            },
            .left_bracket => return self.parsePostfix(try self.parseSequenceLiteral()),
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

    fn parseSequenceLiteral(self: *Parser) ParseError!*Ast.Expression {
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

    fn parseIdentifierExpression(self: *Parser) ParseError!*Ast.Expression {
        const token = self.current;
        try self.advance();
        return self.parseIdentifierExpressionAfterToken(token);
    }

    fn parseIdentifierExpressionAfterToken(self: *Parser, token: Token) ParseError!*Ast.Expression {
        var expression = if (token.tag == .keyword_self)
            try self.newExpression(.{ .position = token.position, .value = .self })
        else if (self.current.tag == .left_parenthesis)
            try self.parseCallAfterName(token.lexeme, token.position)
        else if (self.current.tag == .left_brace)
            try self.parseStructureInitializer(token.lexeme, token.position)
        else
            try self.newExpression(.{ .position = token.position, .value = .{ .identifier = token.lexeme } });

        expression = try self.parsePostfix(expression);
        if (self.current.tag == .left_brace) {
            if (try self.expressionPath(expression)) |path| {
                return self.parseStructureInitializer(path, token.position);
            }
        }
        return expression;
    }

    fn parsePostfix(self: *Parser, initial: *Ast.Expression) ParseError!*Ast.Expression {
        var expression = initial;
        while (self.current.tag == .dot or self.current.tag == .left_bracket) {
            if (self.current.tag == .left_bracket) {
                const bracket_position = self.current.position;
                try self.advance();
                const from_end = self.current.tag == .caret;
                if (from_end) try self.advance();
                const index = try self.parseExpression(true);
                try self.expect(.right_bracket, "expected ']' after collection index");
                expression = try self.newExpression(.{
                    .position = expression.position,
                    .value = .{ .index_access = .{
                        .object = expression,
                        .index = index,
                        .from_end = from_end,
                        .bracket_position = bracket_position,
                    } },
                });
                continue;
            }
            try self.advance();
            if (self.current.tag != .identifier) return self.fail("expected field name after '.'");
            const name = self.current.lexeme;
            const position = self.current.position;
            try self.advance();
            if (self.current.tag == .left_parenthesis) {
                expression = try self.parseMethodCall(expression, name, position);
            } else {
                expression = try self.newExpression(.{
                    .position = expression.position,
                    .value = .{ .member_access = .{
                        .object = expression,
                        .name = name,
                        .name_position = position,
                    } },
                });
            }
        }
        return expression;
    }

    fn expressionPath(self: *Parser, expression: *const Ast.Expression) !?[]const u8 {
        return switch (expression.value) {
            .identifier => |name| name,
            .member_access => |member| if (try self.expressionPath(member.object)) |prefix|
                try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name })
            else
                null,
            else => null,
        };
    }

    fn parseStructureInitializer(
        self: *Parser,
        name: []const u8,
        position: Source.Position,
    ) ParseError!*Ast.Expression {
        try self.expect(.left_brace, "expected '{'");
        var fields: std.ArrayList(Ast.Expression.FieldInitializer) = .empty;
        while (self.current.tag != .right_brace) {
            if (self.current.tag != .identifier) return self.fail("expected field name");
            const field_name = self.current.lexeme;
            const field_position = self.current.position;
            try self.advance();
            try self.expect(.colon, "expected ':' after field name");
            try fields.append(self.allocator, .{
                .name = field_name,
                .position = field_position,
                .value = try self.parseExpression(true),
            });
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        try self.expect(.right_brace, "expected '}'");
        return self.newExpression(.{
            .position = position,
            .value = .{ .structure_initializer = .{
                .name = name,
                .name_position = position,
                .fields = try fields.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn parseCallAfterName(
        self: *Parser,
        name: []const u8,
        position: Source.Position,
    ) ParseError!*Ast.Expression {
        try self.expect(.left_parenthesis, "expected '('");
        var arguments: std.ArrayList(*Ast.Expression) = .empty;
        while (self.current.tag != .right_parenthesis) {
            try arguments.append(self.allocator, try self.parseExpression(true));
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        try self.expect(.right_parenthesis, "expected ')'");
        return self.newExpression(.{
            .position = position,
            .value = .{ .call = .{
                .name = name,
                .name_position = position,
                .arguments = try arguments.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn parseMethodCall(
        self: *Parser,
        object: *Ast.Expression,
        name: []const u8,
        position: Source.Position,
    ) ParseError!*Ast.Expression {
        try self.expect(.left_parenthesis, "expected '('");
        var arguments: std.ArrayList(*Ast.Expression) = .empty;
        while (self.current.tag != .right_parenthesis) {
            try arguments.append(self.allocator, try self.parseExpression(true));
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        try self.expect(.right_parenthesis, "expected ')'");
        return self.newExpression(.{
            .position = object.position,
            .value = .{ .method_call = .{
                .object = object,
                .name = name,
                .name_position = position,
                .arguments = try arguments.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn binaryExpression(
        self: *Parser,
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
            .star => .multiply,
            .slash => .divide,
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

    fn newExpression(self: *Parser, value: Ast.Expression) !*Ast.Expression {
        const result = try self.allocator.create(Ast.Expression);
        result.* = value;
        return result;
    }

    fn newTypeName(self: *Parser, type_name: Ast.TypeName) !*Ast.TypeName {
        const result = try self.allocator.create(Ast.TypeName);
        result.* = type_name;
        return result;
    }

    fn expect(self: *Parser, tag: TokenTag, message: []const u8) !void {
        if (self.current.tag != tag) return self.fail(message);
        try self.advance();
    }

    fn expectIdentifier(self: *Parser, expected: []const u8, message: []const u8) !void {
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, expected)) {
            return self.fail(message);
        }
        try self.advance();
    }

    fn expectStatementTerminator(self: *Parser) ParseError!void {
        if (self.current.tag == .semicolon and self.current.position.line == self.previous.position.line) {
            try self.advance();
            return;
        }
        if (self.current.tag == .right_brace or self.current.tag == .end) return;
        if (self.current.position.line > self.previous.position.line) return;
        return self.fail("expected ';' or line break");
    }

    fn canContinueExpression(self: *const Parser, allow_line_breaks: bool) bool {
        return allow_line_breaks or self.current.position.line == self.previous.position.line;
    }

    fn advance(self: *Parser) !void {
        const next = self.lexer.next() catch |err| {
            self.diagnostic = self.lexer.diagnostic;
            return err;
        };
        if (self.started) {
            self.previous = self.current;
        } else {
            self.started = true;
        }
        self.current = next;
    }

    fn fail(self: *Parser, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = self.current.position, .message = message };
        return error.InvalidSource;
    }

    fn failAt(self: *Parser, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn isComparisonOperator(tag: TokenTag) bool {
    return switch (tag) {
        .less, .less_equal, .greater, .greater_equal => true,
        else => false,
    };
}

fn assignmentOperator(tag: TokenTag) ?Ast.AssignmentOperator {
    return switch (tag) {
        .equal => .assign,
        .plus_equal => .add,
        .minus_equal => .subtract,
        .star_equal => .multiply,
        .slash_equal => .divide,
        .plus_plus => .increment,
        .minus_minus => .decrement,
        else => null,
    };
}

test "multiplication binds tighter than addition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { print(1 + 2 * 3); }");
    const program = try parser.parse();

    const addition = program.functions[0].statements[0].print.argument.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.add, addition.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.multiply, addition.right.value.binary.operator);
}

test "parse explicit conversions before arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let value = 1 as uint8 + 2 as int; }",
    );
    const program = try parser.parse();

    const addition = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.add, addition.operator);
    try std.testing.expectEqual(Ast.TypeName.uint8, addition.left.value.conversion.target_type);
    try std.testing.expectEqual(Ast.TypeName.int, addition.right.value.conversion.target_type);
}

test "parse struct initialization and member assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Position { x:int; y:int }
        \\func main() void { var position = Position { y:20, x:10 }; position.x = 12 }
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expectEqualStrings("Position", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].fields.len);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.initializer.?.value == .structure_initializer);
    try std.testing.expect(program.functions[0].statements[1].assignment.target.value == .member_access);
}

test "parse defaults and compound assignments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Counter { value:int = 2 }
        \\func main() void { var counter:Counter; counter.value += 3; counter.value-- }
    );
    const program = try parser.parse();

    try std.testing.expect(program.structures[0].fields[0].initializer != null);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.initializer == null);
    try std.testing.expectEqual(Ast.AssignmentOperator.add, program.functions[0].statements[1].assignment.operator);
    try std.testing.expectEqual(Ast.AssignmentOperator.decrement, program.functions[0].statements[2].assignment.operator);
}

test "parse inferred and annotated declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let count = 5; var hit:bool = true; if (hit) { print(count); } }",
    );
    const program = try parser.parse();

    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[0].variable_declaration.mutability);
    try std.testing.expectEqual(Ast.TypeName.bool, program.functions[0].statements[1].variable_declaration.annotation.?);
    try std.testing.expectEqualStrings(
        "count",
        program.functions[0].statements[2].if_statement.body[0].print.argument.value.identifier,
    );
}

test "logical operators follow comparison precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let result = !false || 1 < 2 && 3 == 3; }",
    );
    const program = try parser.parse();

    const logical_or = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.logical_or, logical_or.operator);
    try std.testing.expectEqual(Ast.UnaryOperator.logical_not, logical_or.left.value.unary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.logical_and, logical_or.right.value.binary.operator);
    try std.testing.expectEqual(
        Ast.BinaryOperator.less,
        logical_or.right.value.binary.left.value.binary.operator,
    );
    try std.testing.expectEqual(
        Ast.BinaryOperator.equal,
        logical_or.right.value.binary.right.value.binary.operator,
    );
}

test "parse else block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { if (true) { print(1); } else { print(2); } }",
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[0].if_statement.else_body.?.len);
}

test "parse while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { var count = 2; while (count > 0) { count = count - 1; } }",
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.BinaryOperator.greater, program.functions[0].statements[1].while_statement.condition.value.binary.operator);
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[1].while_statement.body.len);
}

test "newlines terminate simple statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let count = 1
        \\    var enabled = true
        \\    print(count)
        \\    count = 2
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 4), program.functions[0].statements.len);
}

test "semicolons separate statements on one line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { let a = 1; let b = 2; print(a + b) }");
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 3), program.functions[0].statements.len);
}

test "comments preserve automatic line termination" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let value = 1 // comment
        \\    print(value)
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements.len);
}

test "semicolon cannot stand alone on next line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    print(1)
        \\    ;
        \\}
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected statement", parser.diagnostic.?.message);
}

test "reject statements on one line without semicolon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { let a = 1 let b = 2 }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected ';' or line break", parser.diagnostic.?.message);
}

test "reject missing explicit type after colon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { var health: = 20 }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected type name after ':'", parser.diagnostic.?.message);
}

test "multiline expressions continue after operators and inside parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let total =
        \\        1 +
        \\        2
        \\    let active = (
        \\        total > 0
        \\        && true
        \\    )
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements.len);
}

test "operator cannot begin continuation outside parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let total = 1
        \\        + 2
        \\}
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected statement", parser.diagnostic.?.message);
}

test "parse method and field cascade operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Point { x:int }
        \\func main() void {
        \\    var point = Point { x:0 }
        \\        ..x = 10
        \\        ..move(1, 2)
        \\}
    );
    const program = try parser.parse();
    const cascade = program.functions[0].statements[0].variable_declaration.initializer.?.value.cascade;
    try std.testing.expectEqual(@as(usize, 2), cascade.operations.len);
    try std.testing.expect(cascade.operations[0] == .field_assignment);
    try std.testing.expectEqualStrings("10", cascade.operations[0].field_assignment.value.value.integer);
    try std.testing.expect(cascade.operations[1] == .method_call);
    try std.testing.expectEqualStrings("move", cascade.operations[1].method_call.name);
}

test "parse functions parameters calls and returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    print(add(2, 3))
        \\}
        \\func add(left:int, right:int) int {
        \\    return left + right
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expectEqual(@as(usize, 2), program.functions[1].parameters.len);
    try std.testing.expectEqualStrings("add", program.functions[0].statements[0].print.argument.value.call.name);
    try std.testing.expect(program.functions[1].statements[0].return_statement.value != null);
}

test "void return type is optional but typed returns remain explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func implicit() {}
        \\func explicit() void {}
        \\func answer() int { return 42 }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.ReturnType.void, program.functions[0].return_type);
    try std.testing.expectEqual(Ast.ReturnType.void, program.functions[1].return_type);
    try std.testing.expectEqual(Ast.ReturnType.int, program.functions[2].return_type);
}

test "parse fixed arrays and lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main(values:int[], fixed:int[3]) void {}");
    const program = try parser.parse();
    try std.testing.expect(program.functions[0].parameters[0].type == .list);
    try std.testing.expect(program.functions[0].parameters[0].type.list.* == .int);
    try std.testing.expect(program.functions[0].parameters[1].type == .fixed_array);
    try std.testing.expect(program.functions[0].parameters[1].type.fixed_array.element.* == .int);
}
