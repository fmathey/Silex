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
                } else if (self.current.tag == .keyword_struct or self.current.tag == .keyword_class) {
                    try structures.append(self.allocator, try self.parseStructure(true));
                } else if (self.current.tag == .keyword_func) {
                    try functions.append(self.allocator, try self.parseFunction(true));
                } else if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "native")) {
                    return self.fail("native functions cannot be public");
                } else return self.fail("expected 'struct', 'class', 'func', or 'use' after 'pub'");
            } else if (self.current.tag == .keyword_struct or self.current.tag == .keyword_class) {
                try structures.append(self.allocator, try self.parseStructure(false));
            } else if (self.current.tag == .keyword_func) {
                try functions.append(self.allocator, try self.parseFunction(false));
            } else if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "native")) {
                try functions.append(self.allocator, try self.parseNativeFunction());
            } else if (self.current.tag == .keyword_elif) {
                return self.fail("'elif' must directly continue an if chain");
            } else {
                return self.fail("expected import, use, struct, class, func, or native func declaration");
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
        const is_class = self.current.tag == .keyword_class;
        try self.advance();
        if (self.current.tag != .identifier) return self.fail(if (is_class) "expected class name" else "expected struct name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        var base: ?Ast.BaseClass = null;
        if (self.current.tag == .colon) {
            if (!is_class) return self.fail("only a class can declare a base class");
            try self.advance();
            const base_position = self.current.position;
            base = .{
                .name = try self.parseQualifiedName("expected base class name after ':'"),
                .position = base_position,
            };
            if (self.current.tag == .comma or self.current.tag == .colon) {
                return self.fail("a class can declare only one base class");
            }
        }
        try self.expect(.left_brace, "expected '{'");
        var fields: std.ArrayList(Ast.StructureField) = .empty;
        var constructors: std.ArrayList(Ast.Constructor) = .empty;
        var methods: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            const is_override = self.current.tag == .keyword_override;
            if (is_override) {
                if (!is_class) return self.fail("only class methods can use 'override'");
                try self.advance();
            }
            var visibility: Ast.MemberVisibility = if (is_class) .private_access else .public_access;
            if (self.current.tag == .keyword_pub or self.current.tag == .keyword_sub) {
                if (!is_class) return self.fail("struct members are already public and do not accept visibility modifiers");
                visibility = if (self.current.tag == .keyword_pub) .public_access else .subclass;
                try self.advance();
            }
            if (self.current.tag == .keyword_override) return self.fail("'override' must precede the method visibility");
            if (self.current.tag == .keyword_func) {
                var method = try self.parseFunction(false);
                method.member_visibility = visibility;
                method.is_override = is_override;
                try methods.append(self.allocator, method);
                continue;
            }
            if (is_override) return self.fail("'override' must declare a class method");
            if (self.current.tag == .keyword_init) {
                if (!is_class) return self.fail("custom constructors are available only in classes");
                const constructor_position = self.current.position;
                try self.advance();
                const parameters = try self.parseParameters();
                var super_arguments: ?[]const *Ast.Expression = null;
                var super_position: ?Source.Position = null;
                if (self.current.tag == .colon) {
                    try self.advance();
                    if (self.current.tag != .keyword_super) return self.fail("expected 'super' after constructor ':'");
                    super_position = self.current.position;
                    try self.advance();
                    super_arguments = try self.parseCallArguments();
                }
                if (self.current.tag != .left_brace) return self.fail("constructor 'init' cannot declare a return type");
                try constructors.append(self.allocator, .{
                    .visibility = visibility,
                    .position = constructor_position,
                    .parameters = parameters,
                    .super_arguments = super_arguments,
                    .super_position = super_position,
                    .statements = try self.parseBlock(),
                });
                continue;
            }
            if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "native")) {
                return self.fail("native functions must be declared at module level");
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
                .visibility = visibility,
            });
            try self.expectStatementTerminator();
        }
        try self.expect(.right_brace, "expected '}'");
        return .{
            .is_public = is_public,
            .is_class = is_class,
            .position = position,
            .name = name,
            .name_position = name_position,
            .base = base,
            .fields = try fields.toOwnedSlice(self.allocator),
            .constructors = try constructors.toOwnedSlice(self.allocator),
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

    fn parseNativeFunction(self: *Parser) ParseError!Ast.Function {
        const position = self.current.position;
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, "native")) {
            return self.fail("expected 'native'");
        }
        try self.advance();
        try self.expect(.keyword_func, "expected 'func' after 'native'");
        if (self.current.tag != .identifier) return self.fail("expected function name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        const parameters = try self.parseParameters();
        const return_type = try self.parseReturnType();
        try self.expectStatementTerminator();
        return .{
            .is_native = true,
            .position = position,
            .name = name,
            .name_position = name_position,
            .return_type = return_type,
            .parameters = parameters,
            .statements = &.{},
        };
    }

    fn parseReturnType(self: *Parser) ParseError!Ast.ReturnType {
        if (self.current.tag == .keyword_void) {
            try self.advance();
            if (self.current.tag == .question) return self.fail("type 'void' cannot be optional");
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
            .function => |function| .{ .function = function },
            .optional => |contained| .{ .optional = contained },
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
            .keyword_assert => self.parseAssert(),
            .keyword_panic => self.parsePanic(),
            .keyword_let => self.parseVariableDeclaration(.immutable),
            .keyword_var => self.parseVariableDeclaration(.mutable),
            .keyword_if => self.parseIf(),
            .keyword_elif => self.fail("'elif' must directly continue an if chain"),
            .keyword_else => self.fail("'else' must directly continue an if chain with '{' or 'if'"),
            .keyword_while => self.parseWhile(),
            .keyword_for => self.parseFor(),
            .keyword_break => self.parseLoopControl(.break_statement),
            .keyword_continue => self.parseLoopControl(.continue_statement),
            .keyword_return => self.parseReturn(),
            .identifier, .keyword_self, .keyword_super => self.parseIdentifierStatement(),
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

    fn parseAssert(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '(' after 'assert'");
        const condition = try self.parseExpression(true);
        try self.expect(.comma, "expected ',' after assertion condition");
        const message = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')' after assertion message");
        try self.expectStatementTerminator();
        return .{ .assertion = .{ .position = position, .condition = condition, .message = message } };
    }

    fn parsePanic(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '(' after 'panic'");
        const message = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')' after panic message");
        try self.expectStatementTerminator();
        return .{ .panic_statement = .{ .position = position, .message = message } };
    }

    fn parseVariableDeclaration(self: *Parser, mutability: Ast.Mutability) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();

        if (self.current.tag == .keyword_elif) return self.fail("'elif' is reserved; rename this identifier");
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
        const type_name: Ast.TypeName = if (self.current.tag == .left_parenthesis) grouped: {
            try self.advance();
            const grouped_type = try self.parseTypeNameAfter(message);
            try self.expect(.right_parenthesis, "expected ')' after grouped type");
            break :grouped grouped_type;
        } else if (self.current.tag == .keyword_func)
            try self.parseFunctionType()
        else if (self.current.tag == .identifier)
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
        if (type_name != .structure and type_name != .function) try self.advance();
        var result = type_name;
        while (self.current.tag == .left_bracket or self.current.tag == .question) {
            if (self.current.tag == .question) {
                if (result == .optional) return self.fail("an optional type cannot be optional again");
                try self.advance();
                const contained = try self.newTypeName(result);
                result = .{ .optional = contained };
                continue;
            }
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

    fn parseFunctionType(self: *Parser) ParseError!Ast.TypeName {
        try self.expect(.keyword_func, "expected 'func'");
        try self.expect(.left_parenthesis, "expected '(' after 'func'");
        var parameters: std.ArrayList(Ast.TypeName) = .empty;
        var parameter_is_mutable_references: std.ArrayList(bool) = .empty;
        while (self.current.tag != .right_parenthesis) {
            const is_mutable_reference = self.current.tag == .amp;
            if (is_mutable_reference) try self.advance();
            try parameters.append(self.allocator, try self.parseTypeNameAfter("expected function parameter type"));
            try parameter_is_mutable_references.append(self.allocator, is_mutable_reference);
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        try self.expect(.right_parenthesis, "expected ')' after function parameter types");
        var return_type: ?*Ast.TypeName = null;
        const return_on_same_line = self.current.position.line == self.previous.position.line;
        if (return_on_same_line and self.current.tag == .keyword_void) {
            try self.advance();
        } else if (return_on_same_line and self.isTypeStart()) {
            return_type = try self.newTypeName(try self.parseTypeNameAfter("expected function return type"));
        }
        return .{ .function = .{
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .parameter_is_mutable_references = try parameter_is_mutable_references.toOwnedSlice(self.allocator),
            .return_type = return_type,
        } };
    }

    fn isTypeStart(self: *const Parser) bool {
        return switch (self.current.tag) {
            .left_parenthesis, .keyword_func, .keyword_int, .keyword_int8, .keyword_int16, .keyword_int32, .keyword_int64, .keyword_uint, .keyword_uint8, .keyword_uint16, .keyword_uint32, .keyword_uint64, .keyword_float, .keyword_float32, .keyword_float64, .keyword_bool, .keyword_str, .identifier => true,
            else => false,
        };
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
        if (target.value == .call or target.value == .value_call or target.value == .method_call or target.value == .super_method_call or target.value == .safe_member_access or target.value == .cascade) {
            try self.expectStatementTerminator();
            return .{ .expression_statement = target };
        }
        return self.fail("expected assignment or function call");
    }

    fn parseIf(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        const condition = try self.parseCondition();
        const body = try self.parseBlock();
        var alternatives: std.ArrayList(Ast.Statement.If.Alternative) = .empty;
        var else_body: ?[]const Ast.Statement = null;
        while (true) {
            if (self.current.tag == .keyword_elif) {
                try self.advance();
                try alternatives.append(self.allocator, try self.parseIfAlternative());
                continue;
            }
            if (self.current.tag != .keyword_else) break;

            try self.advance();
            if (self.current.tag == .keyword_if) {
                try self.advance();
                try alternatives.append(self.allocator, try self.parseIfAlternative());
                continue;
            }
            if (self.current.tag != .left_brace) return self.fail("expected '{' or 'if' after 'else'");
            else_body = try self.parseBlock();
            if (self.current.tag == .keyword_elif or self.current.tag == .keyword_else) {
                return self.fail("conditional branch cannot follow final 'else'");
            }
            break;
        }
        return .{ .if_statement = .{
            .position = position,
            .condition = condition,
            .body = body,
            .alternatives = try alternatives.toOwnedSlice(self.allocator),
            .else_body = else_body,
        } };
    }

    fn parseIfAlternative(self: *Parser) ParseError!Ast.Statement.If.Alternative {
        return .{
            .condition = try self.parseCondition(),
            .body = try self.parseBlock(),
        };
    }

    fn parseWhile(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        const condition = try self.parseCondition();
        const body = try self.parseBlock();
        return .{ .while_statement = .{ .position = position, .condition = condition, .body = body } };
    }

    fn parseCondition(self: *Parser) ParseError!Ast.Statement.Condition {
        const parenthesized_binding = if (self.current.tag == .left_parenthesis)
            try self.parenthesizedConditionStartsBinding()
        else
            false;
        const unparenthesized_binding = self.current.tag == .keyword_let or
            self.current.tag == .keyword_var or
            (self.current.tag == .identifier and (try self.peekTag()) == .equal);
        if (!parenthesized_binding and !unparenthesized_binding) {
            return .{ .expression = try self.parseExpression(false) };
        }

        if (parenthesized_binding) try self.advance();
        const position = self.current.position;
        var mutability: Ast.Mutability = .immutable;
        const explicit_mutability = self.current.tag == .keyword_let or self.current.tag == .keyword_var;
        if (explicit_mutability) {
            mutability = if (self.current.tag == .keyword_let) .immutable else .mutable;
            try self.advance();
        }
        if (self.current.tag != .identifier) return self.fail(if (explicit_mutability)
            "expected binding name after 'let' or 'var'"
        else
            "expected conditional binding name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        try self.expect(.equal, "expected '=' after conditional binding name");
        const source = try self.parseExpression(parenthesized_binding);
        if (parenthesized_binding) try self.expect(.right_parenthesis, "expected ')' after conditional binding");
        return .{ .binding = .{
            .position = position,
            .name = name,
            .name_position = name_position,
            .mutability = mutability,
            .source = source,
        } };
    }

    fn parenthesizedConditionStartsBinding(self: *const Parser) Source.Error!bool {
        var lexer = self.lexer;
        const first = try lexer.next();
        if (first.tag == .keyword_let or first.tag == .keyword_var) return true;
        if (first.tag != .identifier) return false;
        return (try lexer.next()).tag == .equal;
    }

    fn parseFor(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        const parenthesized = self.current.tag == .left_parenthesis;
        if (parenthesized) try self.advance();
        var mutability: Ast.Mutability = .immutable;
        if (self.current.tag == .keyword_let or self.current.tag == .keyword_var) {
            mutability = if (self.current.tag == .keyword_let) .immutable else .mutable;
            try self.advance();
        }
        if (self.current.tag != .identifier) return self.fail("expected iteration variable name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        try self.expect(.keyword_in, "expected 'in' after iteration variable");
        const source = try self.parseForSource(parenthesized);
        if (parenthesized) try self.expect(.right_parenthesis, "expected ')' after for source");
        return .{ .for_statement = .{
            .position = position,
            .name = name,
            .name_position = name_position,
            .mutability = mutability,
            .source = source,
            .body = try self.parseBlock(),
        } };
    }

    fn parseForSource(self: *Parser, allow_line_breaks: bool) ParseError!Ast.Statement.For.IterationSource {
        if (self.current.tag == .keyword_range) {
            try self.advance();
            try self.expect(.left_parenthesis, "expected '(' after 'range'");
            const start = try self.parseExpression(true);
            try self.expect(.comma, "expected ',' between range bounds");
            const end = try self.parseExpression(true);
            try self.expect(.right_parenthesis, "expected ')' after range bounds");
            return .{ .integer_range = .{ .start = start, .end = end } };
        }

        const first = try self.parseExpression(allow_line_breaks);
        if (self.current.tag == .dot_dot_dot and self.canContinueExpression(allow_line_breaks)) {
            try self.advance();
            const end = try self.parseExpression(allow_line_breaks);
            return .{ .integer_range = .{ .start = first, .end = end } };
        }
        return .{ .collection = first };
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

        const cascade = try self.newExpression(.{
            .position = object.position,
            .value = .{ .cascade = .{
                .object = object,
                .operations = try operations.toOwnedSlice(self.allocator),
            } },
        });
        return if (self.current.tag == .dot) self.parsePostfix(cascade) else cascade;
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
        var expression = try self.parseBitXor(allow_line_breaks);
        while (isComparisonOperator(self.current.tag) and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseBitXor(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseBitXor(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseBitAnd(allow_line_breaks);
        while (self.current.tag == .caret and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseBitAnd(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseBitAnd(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        var expression = try self.parseShift(allow_line_breaks);
        while (self.current.tag == .amp and self.canContinueExpression(allow_line_breaks)) {
            const operator_token = self.current;
            try self.advance();
            const right = try self.parseShift(allow_line_breaks);
            expression = try self.binaryExpression(expression, right, operator_token);
        }
        return expression;
    }

    fn parseShift(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
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
            .keyword_null => {
                try self.advance();
                return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .null }));
            },
            .string => {
                try self.advance();
                return self.parsePostfix(try self.newExpression(.{ .position = token.position, .value = .{ .string = token.lexeme } }));
            },
            .left_bracket => return self.parsePostfix(try self.parseSequenceLiteral()),
            .keyword_func => return self.parsePostfix(try self.parseLambda()),
            .keyword_super => return self.parseSuperMethodCall(),
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

    fn parseSuperMethodCall(self: *Parser) ParseError!*Ast.Expression {
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

    fn parseLambda(self: *Parser) ParseError!*Ast.Expression {
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
                .parameters = parameters,
                .return_type = return_type,
                .statements = try self.parseBlock(),
            } },
        });
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
        else
            try self.newExpression(.{ .position = token.position, .value = .{ .identifier = token.lexeme } });

        expression = try self.parsePostfix(expression);
        if (self.current.tag == .left_brace and try self.looksLikeLegacyStructureInitializer()) {
            return self.fail("structure initializers use 'Type(...)', not 'Type { ... }'");
        }
        return expression;
    }

    fn parsePostfix(self: *Parser, initial: *Ast.Expression) ParseError!*Ast.Expression {
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
                } else expression = try self.parseMethodCall(expression, name, position);
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

    fn parseCallAfterName(
        self: *Parser,
        name: []const u8,
        position: Source.Position,
    ) ParseError!*Ast.Expression {
        const arguments = try self.parseInvocationArguments();
        return self.newExpression(.{
            .position = position,
            .value = .{ .call = .{
                .name = name,
                .name_position = position,
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

    const InvocationArguments = union(enum) {
        positional: []const *Ast.Expression,
        named: []const Ast.Expression.FieldInitializer,
    };

    fn parseInvocationArguments(self: *Parser) ParseError!InvocationArguments {
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

    fn currentStartsNamedField(self: *const Parser) ParseError!bool {
        if (self.current.tag != .identifier) return false;
        var lexer = self.lexer;
        return (try lexer.next()).tag == .colon;
    }

    fn looksLikeLegacyStructureInitializer(self: *const Parser) ParseError!bool {
        if (self.current.tag != .left_brace) return false;
        var lexer = self.lexer;
        if ((try lexer.next()).tag != .identifier) return false;
        return (try lexer.next()).tag == .colon;
    }

    fn parseCallArguments(self: *Parser) ParseError![]const *Ast.Expression {
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

    fn parseMethodCall(
        self: *Parser,
        object: *Ast.Expression,
        name: []const u8,
        position: Source.Position,
    ) ParseError!*Ast.Expression {
        const arguments = try self.parseInvocationArguments();
        return self.newExpression(.{
            .position = object.position,
            .value = .{ .method_call = .{
                .object = object,
                .name = name,
                .name_position = position,
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

    fn peekTag(self: *const Parser) Source.Error!TokenTag {
        var lexer = self.lexer;
        return (try lexer.next()).tag;
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

test "control flow parentheses do not change the compiler AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let enabled = true
        \\    let values = [1]
        \\    if (enabled) {}
        \\    if enabled {}
        \\    while (enabled) { break }
        \\    while enabled { break }
        \\    for (let value in values) {}
        \\    for let value in values {}
        \\    for (value in values) {}
        \\    for value in values {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;

    try std.testing.expectEqualStrings(
        statements[2].if_statement.condition.expression.value.identifier,
        statements[3].if_statement.condition.expression.value.identifier,
    );
    try std.testing.expectEqualStrings(
        statements[4].while_statement.condition.expression.value.identifier,
        statements[5].while_statement.condition.expression.value.identifier,
    );
    try std.testing.expectEqual(statements[6].for_statement.mutability, statements[7].for_statement.mutability);
    try std.testing.expectEqualStrings(statements[6].for_statement.name, statements[7].for_statement.name);
    try std.testing.expectEqualStrings(
        statements[6].for_statement.source.collection.value.identifier,
        statements[7].for_statement.source.collection.value.identifier,
    );
    try std.testing.expectEqual(statements[8].for_statement.mutability, statements[9].for_statement.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[8].for_statement.mutability);
    try std.testing.expectEqualStrings(statements[8].for_statement.name, statements[9].for_statement.name);
}

test "implicit conditional bindings match explicit let bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func find() int? { return 1 }
        \\func main() {
        \\    if let first = find() {}
        \\    if second = find() {}
        \\    if (third = find()) {}
        \\    if false {} elif fourth = find() {} else if (fifth = find()) {}
        \\    while sixth = find() { break }
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[1].statements;

    try std.testing.expectEqual(Ast.Mutability.immutable, statements[0].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[1].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[2].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[3].if_statement.alternatives[0].condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[3].if_statement.alternatives[1].condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[4].while_statement.condition.binding.mutability);
}

test "parse control flow expressions and continuations without wrapper parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let enabled = true
        \\    let count = 2
        \\    if enabled &&
        \\        count > 0 {}
        \\    if (enabled) && count > 0 {}
        \\    if (
        \\        enabled
        \\        && count > 0
        \\    ) {}
        \\    if func() bool { return true }() {}
        \\    while enabled &&
        \\        count > 0 { break }
        \\    for let index in 0...
        \\        count {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;

    try std.testing.expect(statements[2].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[3].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[4].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[5].if_statement.condition.expression.value == .value_call);
    try std.testing.expect(statements[6].while_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[7].for_statement.source == .integer_range);
}

test "reject operators that only begin an unparenthesized control header line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conditional = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if true
        \\        && false {}
        \\}
    );
    try std.testing.expectError(error.InvalidSource, conditional.parse());
    try std.testing.expectEqualStrings("expected '{'", conditional.diagnostic.?.message);

    var iteration = Parser.init(arena.allocator(),
        \\func main() void {
        \\    for let index in 0
        \\        ...3 {}
        \\}
    );
    try std.testing.expectError(error.InvalidSource, iteration.parse());
    try std.testing.expectEqualStrings("expected '{'", iteration.diagnostic.?.message);
}

test "reject incomplete control flow headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conditional = Parser.init(arena.allocator(), "func main() void { if {} }");
    try std.testing.expectError(error.InvalidSource, conditional.parse());
    try std.testing.expectEqualStrings("expected expression", conditional.diagnostic.?.message);

    var iteration = Parser.init(arena.allocator(), "func main() void { for in [1] {} }");
    try std.testing.expectError(error.InvalidSource, iteration.parse());
    try std.testing.expectEqualStrings("expected iteration variable name", iteration.diagnostic.?.message);
}

test "diagnose malformed optional control flow headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "func main() void { if (true {} }", .message = "expected ')'" },
        .{ .source = "func main() void { if true) {} }", .message = "expected '{'" },
        .{ .source = "func main() void { if true false {} }", .message = "expected '{'" },
        .{ .source = "func main() void { if true && {} }", .message = "expected expression" },
        .{ .source = "func main() void { for let in [1] {} }", .message = "expected iteration variable name" },
        .{ .source = "func main() void { for let value [1] {} }", .message = "expected 'in' after iteration variable" },
        .{ .source = "func main() void { for let value in {} }", .message = "expected expression" },
        .{ .source = "func main() void { for (let value in [1] {} }", .message = "expected ')' after for source" },
    };

    for (cases) |case| {
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse explicit and implicit for bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let values = [1]
        \\    for (let value in values) {}
        \\    for (var value in values) {}
        \\    for value in values {}
        \\    for (value in values) {}
        \\}
    );
    const program = try parser.parse();

    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[1].for_statement.mutability);
    try std.testing.expectEqual(Ast.Mutability.mutable, program.functions[0].statements[2].for_statement.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[3].for_statement.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[4].for_statement.mutability);
}

test "parse compact and named integer ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let start = 0
        \\    let end = 4
        \\    for (let i in start + 1...end - 1) {}
        \\    for (let j in start...compute_end()) {}
        \\    for (var i in range(end, start)) {}
        \\}
    );
    const program = try parser.parse();

    const compact = program.functions[0].statements[2].for_statement.source.integer_range;
    try std.testing.expect(compact.start.value == .binary);
    try std.testing.expect(compact.end.value == .binary);
    const called = program.functions[0].statements[3].for_statement.source.integer_range;
    try std.testing.expect(called.end.value == .call);
    const named = program.functions[0].statements[4].for_statement.source.integer_range;
    try std.testing.expect(named.start.value == .identifier);
    try std.testing.expect(named.end.value == .identifier);
}

test "preserve cascade as for collection source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    var values = [1]
        \\    for (let value in values..reverse()) {}
        \\}
    );
    const program = try parser.parse();

    try std.testing.expect(program.functions[0].statements[1].for_statement.source.collection.value == .cascade);
}

test "parse for binding without let or var" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let values = [1]; for (value in values) {} }",
    );

    const program = try parser.parse();
    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[1].for_statement.mutability);
}

test "reserve range intrinsic name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func range(start:int, end:int) int { return start + end } func main() void {}");

    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected function name", parser.diagnostic.?.message);
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

test "bitwise operators follow shift precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let value:uint8 = 1 + 1 << 2 & 7 ^ 3; }",
    );
    const program = try parser.parse();

    const bit_xor = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.bit_xor, bit_xor.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.bit_and, bit_xor.left.value.binary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.shift_left, bit_xor.left.value.binary.left.value.binary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.add, bit_xor.left.value.binary.left.value.binary.left.value.binary.operator);
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

test "parse named invocation and member assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Position { x:int; y:int }
        \\func main() void { var position = Position(y:20, x:10); position.x = 12 }
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expectEqualStrings("Position", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].fields.len);
    const invocation = program.functions[0].statements[0].variable_declaration.initializer.?.value.call;
    try std.testing.expectEqual(@as(usize, 0), invocation.arguments.len);
    try std.testing.expectEqual(@as(usize, 2), invocation.named_fields.?.len);
    try std.testing.expect(program.functions[0].statements[1].assignment.target.value == .member_access);
}

test "reject invalid invocation argument forms" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{
            .source = "struct Position { x:int } func main() { let value = Position(1, x:2) }",
            .message = "cannot mix positional arguments and named fields",
        },
        .{
            .source = "struct Position { x:int } func main() { let value = Position(x:) }",
            .message = "expected value after ':'",
        },
        .{
            .source = "struct Position { x:int } func main() { let value = Position(x:1 }",
            .message = "expected ')' after invocation",
        },
        .{
            .source = "struct Position { x:int } func main() { let value = Position { x:1 } }",
            .message = "structure initializers use 'Type(...)', not 'Type { ... }'",
        },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
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

test "parse class declarations with the structure member grammar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\pub class Player {
        \\    pub health:int = 100
        \\    sub velocity:int = 0
        \\    pub func damage(amount:int) { self.health -= amount }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expect(program.structures[0].is_public);
    try std.testing.expect(program.structures[0].is_class);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].fields[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].methods[0].member_visibility.?);
    try std.testing.expectEqualStrings("Player", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].fields.len);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].methods.len);
}

test "parse visible overloaded class constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Session {
        \\    token:str
        \\    pub init() { self.token = "" }
        \\    sub init(token:str) { self.token = token }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].constructors.len);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].constructors[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].constructors[1].visibility);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].constructors[1].parameters.len);
}

test "parse class base and constructor super call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Entity { sub init(id:int) {} }
        \\class Player : Entity {
        \\    pub init(id:int, name:str) : super(id) {}
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqualStrings("Entity", program.structures[1].base.?.name);
    try std.testing.expectEqual(@as(usize, 1), program.structures[1].constructors[0].super_arguments.?.len);
}

test "reject a second base class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Player : Entity, Actor {} func main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a class can declare only one base class", parser.diagnostic.?.message);
}

test "reject constructors on structs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct Value { init() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("custom constructors are available only in classes", parser.diagnostic.?.message);
}

test "reject class visibility modifiers on struct members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct Position { pub x:int } func main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings(
        "struct members are already public and do not accept visibility modifiers",
        parser.diagnostic.?.message,
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
    try std.testing.expectEqual(@as(usize, 0), program.functions[0].statements[0].if_statement.alternatives.len);
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[0].if_statement.else_body.?.len);
}

test "normalize elif and else if into the same AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if false {} elif true { print(1) } elif (false) {} else {}
        \\    if false {} else if true { print(1) } else if (false) {} else {}
        \\    if false {} elif true {} else if false {} elif true {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;
    const canonical = statements[0].if_statement;
    const compatible = statements[1].if_statement;

    try std.testing.expectEqual(@as(usize, 2), canonical.alternatives.len);
    try std.testing.expectEqual(canonical.alternatives.len, compatible.alternatives.len);
    for (canonical.alternatives, compatible.alternatives) |left, right| {
        try std.testing.expectEqual(left.condition.expression.value.boolean, right.condition.expression.value.boolean);
        try std.testing.expectEqual(left.body.len, right.body.len);
    }
    try std.testing.expect(canonical.else_body != null);
    try std.testing.expect(compatible.else_body != null);
    try std.testing.expectEqual(@as(usize, 3), statements[2].if_statement.alternatives.len);
}

test "allow trivia inside an alternative chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if false {}
        \\    // before else
        \\    else
        \\    // before if
        \\    if true {}
        \\    // before elif
        \\    elif false {}
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements[0].if_statement.alternatives.len);
}

test "preserve explicit else block with nested if" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { if false {} else { if true {} } }",
    );
    const program = try parser.parse();
    const outer = program.functions[0].statements[0].if_statement;
    try std.testing.expectEqual(@as(usize, 0), outer.alternatives.len);
    try std.testing.expect(outer.else_body.?[0] == .if_statement);
}

test "diagnose malformed alternative chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "func main() void { elif true {} }", .message = "'elif' must directly continue an if chain" },
        .{ .source = "func main() void { else {} }", .message = "'else' must directly continue an if chain with '{' or 'if'" },
        .{ .source = "func main() void { if false {} else elif true {} }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { if false {} else while true {} }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { if false {} else {} elif true {} }", .message = "conditional branch cannot follow final 'else'" },
        .{ .source = "func main() void { if false {} else {} else {} }", .message = "conditional branch cannot follow final 'else'" },
        .{ .source = "func main() void { if false {} elif {} }", .message = "expected expression" },
        .{ .source = "func main() void { if false {} elif true }", .message = "expected '{'" },
        .{ .source = "func main() void { if false {} else }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { let elif = 1 }", .message = "'elif' is reserved; rename this identifier" },
    };

    for (cases) |case| {
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { var count = 2; while (count > 0) { count = count - 1; } }",
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.BinaryOperator.greater, program.functions[0].statements[1].while_statement.condition.expression.value.binary.operator);
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
        \\    var point = Point(x:0)..x = 10..move(1, 2)
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

test "parse terminal member access after a cascade" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let running = stopwatch..reset()..start().is_running()
        \\}
    );
    const program = try parser.parse();
    const call = program.functions[0].statements[0].variable_declaration.initializer.?.value.method_call;
    try std.testing.expectEqualStrings("is_running", call.name);
    try std.testing.expect(call.object.value == .cascade);
    try std.testing.expectEqual(@as(usize, 2), call.object.value.cascade.operations.len);
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

test "parse optional type composition and conditional bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main(entries:int?[], cache:int[]?, callback:(func(int))?) {
        \\    if let value = entries[0] {}
        \\    if (let value = entries[0]) {}
        \\    while var value = entries[0] { break }
        \\    let missing = null
        \\    cache?.count()
        \\}
    );
    const program = try parser.parse();
    const parameters = program.functions[0].parameters;
    try std.testing.expect(parameters[0].type == .list);
    try std.testing.expect(parameters[0].type.list.* == .optional);
    try std.testing.expect(parameters[1].type == .optional);
    try std.testing.expect(parameters[1].type.optional.* == .list);
    try std.testing.expect(parameters[2].type == .optional);
    try std.testing.expect(parameters[2].type.optional.* == .function);
    const statements = program.functions[0].statements;
    try std.testing.expect(statements[0].if_statement.condition == .binding);
    try std.testing.expect(statements[1].if_statement.condition == .binding);
    try std.testing.expectEqualStrings(
        statements[0].if_statement.condition.binding.name,
        statements[1].if_statement.condition.binding.name,
    );
    try std.testing.expect(statements[2].while_statement.condition == .binding);
    try std.testing.expect(statements[3].variable_declaration.initializer.?.value == .null);
    try std.testing.expect(statements[4].expression_statement.value == .safe_member_access);
}

test "parse negative collection indexes and slices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let values = [10, 20, 30]
        \\    let last = values[-1]
        \\    let middle = values[1:-1]
        \\}
    );
    const program = try parser.parse();

    const index = program.functions[0].statements[1].variable_declaration.initializer.?.value.index_access;
    try std.testing.expectEqual(Ast.UnaryOperator.numeric_negate, index.index.value.unary.operator);
    const slice = program.functions[0].statements[2].variable_declaration.initializer.?.value.slice_access;
    try std.testing.expectEqualStrings("1", slice.start.value.integer);
    try std.testing.expectEqual(Ast.UnaryOperator.numeric_negate, slice.end.value.unary.operator);
}

test "parse override methods and direct super calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Base { sub func update(value:int) int { return value } }
        \\class Child : Base {
        \\    override pub func update(value:int) int { return super.update(value) }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const method = program.structures[1].methods[0];
    try std.testing.expect(method.is_override);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, method.member_visibility.?);
    const call = method.statements[0].return_statement.value.?.value.super_method_call;
    try std.testing.expectEqualStrings("update", call.name);
    try std.testing.expectEqual(@as(usize, 1), call.arguments.len);
}

test "override must precede method visibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Child { pub override func update() {} }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("'override' must precede the method visibility", parser.diagnostic.?.message);
}
