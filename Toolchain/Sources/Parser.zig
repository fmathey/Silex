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
        var uses: std.ArrayList(Ast.Use) = .empty;
        var enums: std.ArrayList(Ast.Enum) = .empty;
        var protocols: std.ArrayList(Ast.Protocol) = .empty;
        var extensions: std.ArrayList(Ast.Extension) = .empty;
        var structures: std.ArrayList(Ast.Structure) = .empty;
        var functions: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .end) {
            if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "import")) {
                return self.rejectImport();
            } else if (self.current.tag == .keyword_use) {
                try uses.append(self.allocator, try self.parseUse(false));
            } else if (self.current.tag == .keyword_pub) {
                try self.advance();
                if (self.current.tag == .keyword_use) {
                    try uses.append(self.allocator, try self.parseUse(true));
                } else if (self.current.tag == .keyword_enum) {
                    try enums.append(self.allocator, try self.parseEnum(true));
                } else if (self.current.tag == .keyword_protocol) {
                    try protocols.append(self.allocator, try self.parseProtocol(true));
                } else if (self.current.tag == .keyword_struct or self.current.tag == .keyword_class) {
                    try structures.append(self.allocator, try self.parseStructure(true));
                } else if (self.current.tag == .keyword_func) {
                    try functions.append(self.allocator, try self.parseFunction(true));
                } else if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "native")) {
                    try self.advance();
                    if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "resource")) {
                        const resource = try self.parseNativeResource(true);
                        try structures.append(self.allocator, resource);
                        try functions.append(self.allocator, try self.nativeResourceDropFunction(resource));
                    } else {
                        try functions.append(self.allocator, try self.parseNativeFunctionAfterNative(true));
                    }
                } else return self.fail("expected 'enum', 'protocol', 'struct', 'class', 'func', 'native func', 'native resource', or 'use' after 'pub'");
            } else if (self.current.tag == .keyword_enum) {
                try enums.append(self.allocator, try self.parseEnum(false));
            } else if (self.current.tag == .keyword_protocol) {
                try protocols.append(self.allocator, try self.parseProtocol(false));
            } else if (self.current.tag == .keyword_extend) {
                try extensions.append(self.allocator, try self.parseExtension());
            } else if (self.current.tag == .keyword_struct or self.current.tag == .keyword_class) {
                try structures.append(self.allocator, try self.parseStructure(false));
            } else if (self.current.tag == .keyword_func) {
                try functions.append(self.allocator, try self.parseFunction(false));
            } else if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "native")) {
                try self.advance();
                if (self.current.tag == .identifier and std.mem.eql(u8, self.current.lexeme, "resource")) {
                    const resource = try self.parseNativeResource(false);
                    try structures.append(self.allocator, resource);
                    try functions.append(self.allocator, try self.nativeResourceDropFunction(resource));
                } else {
                    try functions.append(self.allocator, try self.parseNativeFunctionAfterNative(false));
                }
            } else if (self.current.tag == .keyword_elif) {
                return self.fail("'elif' must directly continue an if chain");
            } else {
                return self.fail("expected use, enum, protocol, extend, struct, class, func, native func, or native resource declaration");
            }
        }
        return .{
            .uses = try uses.toOwnedSlice(self.allocator),
            .enums = try enums.toOwnedSlice(self.allocator),
            .protocols = try protocols.toOwnedSlice(self.allocator),
            .extensions = try extensions.toOwnedSlice(self.allocator),
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
    }

    fn parseExtension(self: *Parser) ParseError!Ast.Extension {
        const position = self.current.position;
        try self.expect(.keyword_extend, "expected 'extend'");
        const target_position = self.current.position;
        const target = try self.parseQualifiedName("expected struct or class name after 'extend'");
        if (self.current.tag == .less) return self.fail("generic extensions are not supported");
        var conformances: std.ArrayList(Ast.ProtocolReference) = .empty;
        if (self.current.tag == .colon) {
            try self.advance();
            while (true) {
                const conformance_position = self.current.position;
                const conformance = try self.parseQualifiedName("expected protocol name after ':'");
                try conformances.append(self.allocator, .{
                    .name = conformance,
                    .position = conformance_position,
                });
                if (self.current.tag != .comma) break;
                try self.advance();
            }
        }
        try self.expect(.left_brace, "expected '{' after extended type");
        var methods: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            if (self.current.tag == .keyword_sub) return self.fail("an extension method cannot use 'sub'");
            if (self.current.tag == .keyword_override) return self.fail("an extension method cannot use 'override'");
            const is_public = self.current.tag == .keyword_pub;
            if (is_public) try self.advance();
            const is_static = self.current.tag == .keyword_static;
            if (is_static) try self.advance();
            if (self.current.tag == .keyword_init) return self.fail("an extension cannot declare a constructor");
            if (self.current.tag == .keyword_drop) return self.fail("an extension cannot declare 'drop'");
            if (self.current.tag == .keyword_let or self.current.tag == .keyword_var) {
                return self.fail("an extension cannot declare a field");
            }
            if (self.current.tag != .keyword_func) {
                return self.fail("an extension can declare only methods");
            }
            var method = try self.parseFunction(is_public);
            if (is_static and method.type_parameters.len != 0) {
                return self.fail("generic static extension methods are not supported");
            }
            method.member_visibility = if (is_public) .public_access else null;
            method.is_static = is_static;
            try methods.append(self.allocator, method);
        }
        try self.expect(.right_brace, "expected '}' after extension methods");
        return .{
            .position = position,
            .target = target,
            .target_position = target_position,
            .conformances = try conformances.toOwnedSlice(self.allocator),
            .methods = try methods.toOwnedSlice(self.allocator),
        };
    }

    fn parseProtocol(self: *Parser, is_public: bool) ParseError!Ast.Protocol {
        const position = self.current.position;
        try self.expect(.keyword_protocol, "expected 'protocol'");
        if (self.current.tag != .identifier) return self.fail("expected protocol name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        if (std.mem.eql(u8, name, "Result")) return self.fail("type name 'Result' is reserved");
        try self.advance();
        if (self.current.tag == .less) return self.fail("generic protocols are not supported");
        if (self.current.tag == .colon) return self.fail("protocol inheritance is not supported");
        try self.expect(.left_brace, "expected '{' after protocol name");
        var requirements: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            if (self.current.tag != .keyword_func) {
                return self.fail("a protocol can declare only method requirements");
            }
            const method_position = self.current.position;
            try self.advance();
            if (self.current.tag != .identifier) return self.fail("expected protocol method name");
            const method_name = self.current.lexeme;
            const method_name_position = self.current.position;
            try self.advance();
            if (self.current.tag == .less) return self.fail("generic protocol methods are not supported");
            const parameters = try self.parseParameters();
            const return_type: Ast.ReturnType = if (self.current.tag == .semicolon or
                self.current.tag == .right_brace or
                self.current.position.line > self.previous.position.line) .void else try self.parseReturnType();
            try self.expectStatementTerminator();
            try requirements.append(self.allocator, .{
                .member_visibility = .public_access,
                .position = method_position,
                .name = method_name,
                .name_position = method_name_position,
                .return_type = return_type,
                .parameters = parameters,
                .statements = &.{},
            });
        }
        try self.expect(.right_brace, "expected '}' after protocol requirements");
        return .{
            .is_public = is_public,
            .position = position,
            .name = name,
            .name_position = name_position,
            .requirements = try requirements.toOwnedSlice(self.allocator),
        };
    }

    fn parseEnum(self: *Parser, is_public: bool) ParseError!Ast.Enum {
        const position = self.current.position;
        try self.expect(.keyword_enum, "expected 'enum'");
        if (self.current.tag != .identifier) return self.fail("expected enum name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        if (std.mem.eql(u8, name, "Result")) return self.fail("type name 'Result' is reserved");
        try self.advance();
        const type_parameters = if (self.current.tag == .less)
            try self.parseTypeParameters("enum")
        else
            &.{};
        const raw_type: ?Ast.RawEnumType = if (self.current.tag == .colon) raw_type: {
            if (type_parameters.len != 0) return self.fail("a raw enum cannot be generic");
            try self.advance();
            const result: Ast.RawEnumType = switch (self.current.tag) {
                .keyword_int => .int,
                .keyword_str => .str,
                else => return self.fail("an enum raw type must be 'int' or 'str'"),
            };
            try self.advance();
            break :raw_type result;
        } else null;
        try self.expect(.left_brace, "expected '{' after enum name");
        var variants: std.ArrayList(Ast.EnumVariant) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            if (self.current.tag != .identifier) return self.fail("expected enum variant name");
            const variant_name = self.current.lexeme;
            const variant_position = self.current.position;
            try self.advance();
            var associated_types: std.ArrayList(Ast.TypeName) = .empty;
            if (self.current.tag == .left_parenthesis) {
                if (raw_type != null) return self.fail("a raw enum variant cannot declare associated values");
                try self.advance();
                if (self.current.tag == .right_parenthesis) {
                    return self.fail("an empty enum variant does not use parentheses");
                }
                while (true) {
                    try associated_types.append(self.allocator, try self.parseTypeNameAfter("expected associated value type"));
                    if (self.current.tag != .comma) break;
                    try self.advance();
                    if (self.current.tag == .right_parenthesis) return self.fail("expected associated value type after ','");
                }
                try self.expect(.right_parenthesis, "expected ')' after associated value types");
            }
            var raw_value: ?*Ast.Expression = null;
            if (self.current.tag == .equal) {
                if (raw_type == null) return self.fail("an enum without a raw type cannot assign variant values");
                try self.advance();
                raw_value = try self.parseExpression(false);
            } else if (raw_type != null) {
                return self.fail("a raw enum variant requires a value");
            }
            try variants.append(self.allocator, .{
                .name = variant_name,
                .position = variant_position,
                .associated_types = try associated_types.toOwnedSlice(self.allocator),
                .raw_value = raw_value,
            });
            try self.expectStatementTerminator();
        }
        try self.expect(.right_brace, "expected '}' after enum variants");
        if (variants.items.len == 0) return self.failAt(name_position, "an enum requires at least one variant");
        return .{
            .is_public = is_public,
            .position = position,
            .name = name,
            .name_position = name_position,
            .type_parameters = type_parameters,
            .raw_type = raw_type,
            .variants = try variants.toOwnedSlice(self.allocator),
        };
    }

    fn rejectImport(self: *Parser) ParseError!Ast.Program {
        const position = self.current.position;
        try self.advance();
        const path = try self.parseQualifiedName("expected module name after 'import'");
        const alias = try self.parseOptionalAlias();
        try self.expectStatementTerminator();
        const replacement = if (alias) |name|
            try std.fmt.allocPrint(self.allocator, "'import' was removed; use 'use {s} as {s}'", .{ path, name.name })
        else
            try std.fmt.allocPrint(self.allocator, "'import' was removed; use 'use {s}'", .{path});
        return self.failAt(position, replacement);
    }

    fn parseUse(self: *Parser, is_public: bool) ParseError!Ast.Use {
        const position = self.current.position;
        try self.advance();
        const parsed_type = try self.parseTypeNameAfter("expected declaration or type after 'use'");
        const target: Ast.Use.Target = if (parsed_type == .structure)
            .{ .declaration = parsed_type.structure }
        else
            .{ .type = parsed_type };
        const alias = try self.parseOptionalAlias();
        if (target == .type and alias == null) return self.failAt(position, "a type expression after 'use' requires an alias with 'as'");
        try self.expectStatementTerminator();
        return .{
            .target = target,
            .alias = if (alias) |value| value.name else null,
            .alias_position = if (alias) |value| value.position else null,
            .is_public = is_public,
            .position = position,
        };
    }

    const ParsedAlias = struct {
        name: []const u8,
        position: Source.Position,
    };

    fn parseOptionalAlias(self: *Parser) ParseError!?ParsedAlias {
        if (self.current.tag != .keyword_as) return null;
        try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected alias after 'as'");
        const alias = self.current.lexeme;
        const position = self.current.position;
        if (std.mem.eql(u8, alias, "Result")) return self.fail("name 'Result' is reserved");
        if (std.mem.eql(u8, alias, "map_error")) return self.fail("name 'map_error' is reserved");
        try self.advance();
        return .{ .name = alias, .position = position };
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
        if (std.mem.eql(u8, name, "Result")) return self.fail("type name 'Result' is reserved");
        try self.advance();
        const type_parameters = if (self.current.tag == .less) parameters: {
            if (is_class) return self.fail("generic classes are not supported");
            break :parameters try self.parseTypeParameters("structure");
        } else &.{};
        var base: ?Ast.BaseClass = null;
        var conformances: std.ArrayList(Ast.ProtocolReference) = .empty;
        if (self.current.tag == .colon) {
            try self.advance();
            var first = true;
            while (true) {
                const relation_position = self.current.position;
                const relation_name = try self.parseQualifiedName("expected base class or protocol name after ':'");
                if (is_class and first) {
                    base = .{ .name = relation_name, .position = relation_position };
                } else {
                    try conformances.append(self.allocator, .{ .name = relation_name, .position = relation_position });
                }
                first = false;
                if (self.current.tag != .comma) break;
                try self.advance();
            }
        }
        try self.expect(.left_brace, "expected '{'");
        var fields: std.ArrayList(Ast.StructureField) = .empty;
        var constructors: std.ArrayList(Ast.Constructor) = .empty;
        var drop: ?Ast.Drop = null;
        var methods: std.ArrayList(Ast.Function) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            const is_override = self.current.tag == .keyword_override;
            if (is_override) {
                if (!is_class) return self.fail("only class methods can use 'override'");
                try self.advance();
            }
            var visibility: Ast.MemberVisibility = if (is_class) .private_access else .public_access;
            const has_visibility = self.current.tag == .keyword_pub or self.current.tag == .keyword_sub;
            if (has_visibility) {
                if (!is_class) return self.fail("struct members are already public and do not accept visibility modifiers");
                visibility = if (self.current.tag == .keyword_pub) .public_access else .subclass;
                try self.advance();
            }
            if (self.current.tag == .keyword_override) return self.fail("'override' must precede the method visibility");
            const is_static = self.current.tag == .keyword_static;
            if (is_static) {
                const static_position = self.current.position;
                try self.advance();
                if (is_override) return self.failAt(static_position, if (self.current.tag == .keyword_func)
                    "a static method cannot use 'override'"
                else
                    "a static field cannot use 'override'");
                if (self.current.tag != .keyword_func and self.current.tag != .keyword_let and self.current.tag != .keyword_var) {
                    return self.fail("expected 'func', 'let', or 'var' after 'static'");
                }
            }
            if (self.current.tag == .keyword_func) {
                var method = try self.parseFunction(false);
                if (method.type_parameters.len != 0) return self.fail("generic methods are not supported");
                method.member_visibility = visibility;
                method.is_override = is_override;
                method.is_static = is_static;
                try methods.append(self.allocator, method);
                continue;
            }
            if (self.current.tag == .keyword_drop) {
                if (is_override) return self.fail("'override' cannot apply to 'drop'");
                if (has_visibility) return self.fail("'drop' does not accept a visibility modifier");
                if (drop != null) return self.fail(if (is_class)
                    "a class can declare only one 'drop' block"
                else
                    "a struct can declare only one 'drop' block");
                const drop_position = self.current.position;
                try self.advance();
                if (self.current.tag != .left_brace) return self.fail("'drop' must be followed by a block");
                drop = .{
                    .position = drop_position,
                    .statements = try self.parseBlock(),
                };
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
            if (self.current.tag != .keyword_let and self.current.tag != .keyword_var) {
                if (self.current.tag == .identifier) return self.fail("expected 'let' or 'var' before field name");
                return self.fail("expected field declaration starting with 'let' or 'var'");
            }
            const field_mutability: Ast.Mutability = if (self.current.tag == .keyword_let) .immutable else .mutable;
            try self.advance();
            if (self.current.tag != .identifier) return self.fail("expected field name after 'let' or 'var'");
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
                .mutability = field_mutability,
                .is_static = is_static,
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
            .type_parameters = type_parameters,
            .base = base,
            .conformances = try conformances.toOwnedSlice(self.allocator),
            .fields = try fields.toOwnedSlice(self.allocator),
            .constructors = try constructors.toOwnedSlice(self.allocator),
            .drop = drop,
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
        const type_parameters = if (self.current.tag == .less) try self.parseTypeParameters("function") else &.{};
        if (type_parameters.len != 0 and std.mem.eql(u8, name, "main")) {
            return self.fail("'main' cannot be generic");
        }
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
            .type_parameters = type_parameters,
            .return_type = return_type,
            .parameters = parameters,
            .statements = try self.parseBlock(),
        };
    }

    fn parseNativeFunction(self: *Parser, is_public: bool) ParseError!Ast.Function {
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, "native")) {
            return self.fail("expected 'native'");
        }
        try self.advance();
        return self.parseNativeFunctionAfterNative(is_public);
    }

    fn parseNativeFunctionAfterNative(self: *Parser, is_public: bool) ParseError!Ast.Function {
        const position = self.previous.position;
        try self.expect(.keyword_func, "expected 'func' after 'native'");
        if (self.current.tag != .identifier) return self.fail("expected function name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        try self.advance();
        if (self.current.tag == .less) return self.fail("native functions cannot be generic");
        const parameters = try self.parseParameters();
        const return_type = try self.parseReturnType();
        try self.expectStatementTerminator();
        return .{
            .is_public = is_public,
            .is_native = true,
            .position = position,
            .name = name,
            .name_position = name_position,
            .return_type = return_type,
            .parameters = parameters,
            .statements = &.{},
        };
    }

    fn parseNativeResource(self: *Parser, is_public: bool) ParseError!Ast.Structure {
        const position = self.previous.position;
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, "resource")) {
            return self.fail("expected 'resource' after 'native'");
        }
        try self.advance();
        if (self.current.tag != .identifier) return self.fail("expected native resource name");
        const name = self.current.lexeme;
        const name_position = self.current.position;
        if (std.mem.eql(u8, name, "Result")) return self.fail("type name 'Result' is reserved");
        try self.advance();
        if (self.current.tag == .less) return self.fail("native resources cannot be generic");
        if (self.current.tag == .colon) return self.fail("native resources cannot inherit or conform to protocols");
        try self.expect(.left_brace, "expected '{' after native resource name");
        try self.expect(.keyword_drop, "a native resource must declare exactly one 'drop' member");
        if (self.current.tag != .identifier) return self.fail("expected native destructor name after 'drop'");
        const drop_name = self.current.lexeme;
        try self.advance();
        try self.expectStatementTerminator();
        if (self.current.tag != .right_brace) return self.fail("a native resource can declare only one 'drop' member");
        try self.advance();
        return .{
            .is_public = is_public,
            .is_native_resource = true,
            .native_drop_name = drop_name,
            .position = position,
            .name = name,
            .name_position = name_position,
            .fields = &.{},
            .methods = &.{},
        };
    }

    fn nativeResourceDropFunction(self: *Parser, resource: Ast.Structure) Allocator.Error!Ast.Function {
        return .{
            .is_public = resource.is_public,
            .is_native = true,
            .is_native_resource_drop = true,
            .position = resource.position,
            .name = resource.native_drop_name.?,
            .name_position = resource.name_position,
            .return_type = .void,
            .parameters = try self.allocator.dupe(Ast.Parameter, &.{.{
                .name = "resource",
                .position = resource.name_position,
                .type = .{ .structure = resource.name },
            }}),
            .statements = &.{},
        };
    }

    fn parseReturnType(self: *Parser) ParseError!Ast.ReturnType {
        if (self.current.tag == .keyword_void) {
            try self.advance();
            if (self.current.tag == .question) return self.fail("type 'void' cannot be optional");
            return .void;
        }
        const reference_mode: ?bool = if (self.current.tag == .at)
            false
        else if (self.current.tag == .amp)
            true
        else
            null;
        if (reference_mode) |_| try self.advance();
        var provenance: ?[]const u8 = null;
        const type_name = if (reference_mode != null and self.current.tag == .identifier) reference: {
            const first = try self.parseQualifiedName("expected function return type");
            if (self.current.tag == .colon) {
                provenance = first;
                try self.advance();
                break :reference try self.parseTypeNameAfter("expected function return type after provenance");
            }
            break :reference Ast.TypeName{ .structure = first };
        } else try self.parseTypeNameAfter("expected function return type");
        if (reference_mode) |mutable| {
            const target = try self.newTypeName(type_name);
            return .{ .reference = .{ .target = target, .mutable = mutable, .provenance = provenance } };
        }
        return switch (type_name) {
            .void => unreachable,
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
            .generic_structure => |generic| .{ .generic_structure = generic },
            .type_parameter => |name| .{ .type_parameter = name },
            .list => |element| .{ .list = element },
            .fixed_array => |array| .{ .fixed_array = array },
            .view => |element| .{ .view = element },
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
            const is_read_reference = self.current.tag == .at;
            if (is_read_reference) try self.advance();
            const is_mutable_reference = self.current.tag == .amp;
            if (is_mutable_reference) try self.advance();
            if (is_read_reference and is_mutable_reference) return self.fail("a parameter cannot combine '@' and '&'");
            try parameters.append(self.allocator, .{
                .name = name,
                .position = position,
                .type = try self.parseTypeName(),
                .mode = if (is_read_reference) .borrow else if (is_mutable_reference) .mutable_reference else .value,
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
            .keyword_try => self.parseTryStatement(),
            .keyword_match => self.parseMatchStatement(),
            .identifier, .keyword_self, .keyword_super => self.parseIdentifierStatement(),
            else => self.fail("expected statement"),
        };
    }

    fn parseMatchStatement(self: *Parser) ParseError!Ast.Statement {
        const expression = try self.parseMatchExpression();
        for (expression.value.match_expression.branches) |branch| {
            if (branch.body != .statements) return self.failAt(expression.position, "an imperative match requires a block in every branch");
        }
        return .{ .expression_statement = expression };
    }

    fn parseTryStatement(self: *Parser) ParseError!Ast.Statement {
        const expression = try self.parseExpression(false);
        try self.expectStatementTerminator();
        return .{ .expression_statement = expression };
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
        const reference_mode: ?bool = if (self.current.tag == .at)
            false
        else if (self.current.tag == .amp)
            true
        else
            null;
        if (reference_mode) |mutable| {
            try self.advance();
            const target = try self.newTypeName(try self.parseTypeNameAfter("expected type name after reference mode"));
            return .{ .reference = .{ .target = target, .mutable = mutable } };
        }
        return self.parseTypeNameAfter("expected type name after ':'");
    }

    fn parseTypeNameAfter(self: *Parser, message: []const u8) ParseError!Ast.TypeName {
        const type_name: Ast.TypeName = if (self.current.tag == .left_parenthesis) grouped: {
            try self.advance();
            const grouped_type = try self.parseTypeNameAfter(message);
            try self.expect(.right_parenthesis, "expected ')' after grouped type");
            break :grouped grouped_type;
        } else if (self.current.tag == .keyword_func)
            try self.parseFunctionType(false)
        else if (self.current.tag == .keyword_deferred) deferred: {
            try self.advance();
            if (self.current.tag != .keyword_func) return self.fail("expected 'func' after 'deferred'");
            break :deferred try self.parseFunctionType(true);
        } else if (self.current.tag == .identifier) named: {
            const name = try self.parseQualifiedName(message);
            if (self.current.tag == .less) {
                break :named .{ .generic_structure = .{
                    .name = name,
                    .arguments = try self.parseTypeArguments(name),
                } };
            }
            break :named .{ .structure = name };
        } else switch (self.current.tag) {
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
        if (type_name != .structure and type_name != .generic_structure and type_name != .function) try self.advance();
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
            if (self.current.tag == .dot_dot) {
                try self.advance();
                try self.expect(.right_bracket, "expected ']' after view marker '..'");
                const element = try self.newTypeName(result);
                result = .{ .view = element };
                continue;
            }
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

    fn parseFunctionType(self: *Parser, deferred: bool) ParseError!Ast.TypeName {
        try self.expect(.keyword_func, "expected 'func'");
        try self.expect(.left_parenthesis, "expected '(' after 'func'");
        var parameters: std.ArrayList(Ast.TypeName) = .empty;
        var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
        while (self.current.tag != .right_parenthesis) {
            const is_read_reference = self.current.tag == .at;
            if (is_read_reference) try self.advance();
            const is_mutable_reference = self.current.tag == .amp;
            if (is_mutable_reference) try self.advance();
            if (is_read_reference and is_mutable_reference) return self.fail("a function parameter type cannot combine '@' and '&'");
            try parameters.append(self.allocator, try self.parseTypeNameAfter("expected function parameter type"));
            try parameter_modes.append(self.allocator, if (is_read_reference) .borrow else if (is_mutable_reference) .mutable_reference else .value);
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
            .deferred = deferred,
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
            .return_type = return_type,
        } };
    }

    fn isTypeStart(self: *const Parser) bool {
        return switch (self.current.tag) {
            .left_parenthesis, .keyword_func, .keyword_deferred, .keyword_int, .keyword_int8, .keyword_int16, .keyword_int32, .keyword_int64, .keyword_uint, .keyword_uint8, .keyword_uint16, .keyword_uint32, .keyword_uint64, .keyword_float, .keyword_float32, .keyword_float64, .keyword_bool, .keyword_str, .identifier => true,
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
        var binding: Ast.IterationBinding = .read;
        if (self.current.tag == .keyword_let or self.current.tag == .keyword_var) {
            binding = if (self.current.tag == .keyword_let) .immutable else .mutable;
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
            .binding = binding,
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

    fn parseMatchExpression(self: *Parser) ParseError!*Ast.Expression {
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

    fn parseLambda(self: *Parser, deferred: bool) ParseError!*Ast.Expression {
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

    fn parseStaticMember(self: *Parser, owner: Ast.TypeName, owner_position: Source.Position) ParseError!*Ast.Expression {
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

    fn parseCallAfterName(
        self: *Parser,
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

    fn parseTypeParameters(self: *Parser, declaration_kind: []const u8) ParseError![]const Ast.TypeParameter {
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

    fn parseTypeArguments(self: *Parser, owner_name: ?[]const u8) ParseError![]const Ast.TypeName {
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

    fn expectTypeArgumentClose(self: *Parser) ParseError!void {
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

    fn genericInvocationFollows(self: *const Parser) bool {
        var probe = self.*;
        _ = probe.parseTypeArguments(null) catch return self.malformedGenericSuffixFollows(.left_parenthesis);
        return probe.current.tag == .left_parenthesis;
    }

    fn genericStaticMemberFollows(self: *const Parser) bool {
        var probe = self.*;
        _ = probe.parseTypeArguments(null) catch return self.malformedGenericSuffixFollows(.dot);
        if (probe.current.tag != .dot) return false;
        probe.advance() catch return false;
        return probe.current.tag == .identifier;
    }

    fn malformedGenericSuffixFollows(self: *const Parser, suffix: TokenTag) bool {
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

    fn expressionPath(self: *Parser, expression: *const Ast.Expression) ParseError!?[]const u8 {
        return switch (expression.value) {
            .identifier => |name| name,
            .member_access => |member| if (try self.expressionPath(member.object)) |prefix|
                try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name })
            else
                null,
            else => null,
        };
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
    try std.testing.expectEqual(statements[6].for_statement.binding, statements[7].for_statement.binding);
    try std.testing.expectEqualStrings(statements[6].for_statement.name, statements[7].for_statement.name);
    try std.testing.expectEqualStrings(
        statements[6].for_statement.source.collection.value.identifier,
        statements[7].for_statement.source.collection.value.identifier,
    );
    try std.testing.expectEqual(statements[8].for_statement.binding, statements[9].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, statements[8].for_statement.binding);
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

    try std.testing.expectEqual(Ast.IterationBinding.immutable, program.functions[0].statements[1].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.mutable, program.functions[0].statements[2].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[3].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[4].for_statement.binding);
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
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[1].for_statement.binding);
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
        \\struct Position { var x:int; var y:int }
        \\func main() void { var position = Position(y:20, x:10); position.x = 12 }
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expectEqualStrings("Position", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].fields.len);
    try std.testing.expectEqual(Ast.Mutability.mutable, program.structures[0].fields[0].mutability);
    const invocation = program.functions[0].statements[0].variable_declaration.initializer.?.value.call;
    try std.testing.expectEqual(@as(usize, 0), invocation.arguments.len);
    try std.testing.expectEqual(@as(usize, 2), invocation.named_fields.?.len);
    try std.testing.expect(program.functions[0].statements[1].assignment.target.value == .member_access);
}

test "require and preserve structure field mutability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct State { let id:int; var count:int }");
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.Mutability.immutable, program.structures[0].fields[0].mutability);
    try std.testing.expectEqual(Ast.Mutability.mutable, program.structures[0].fields[1].mutability);

    var invalid = Parser.init(arena.allocator(), "struct State { count:int }");
    try std.testing.expectError(error.InvalidSource, invalid.parse());
    try std.testing.expectEqualStrings("expected 'let' or 'var' before field name", invalid.diagnostic.?.message);
}

test "reject invalid invocation argument forms" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(1, x:2) }",
            .message = "cannot mix positional arguments and named fields",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(x:) }",
            .message = "expected value after ':'",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(x:1 }",
            .message = "expected ')' after invocation",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position { x:1 } }",
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
        \\struct Counter { var value:int = 2 }
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
        \\    pub var health:int = 100
        \\    sub var velocity:int = 0
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
        \\    var token:str
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

test "parse class and struct drop blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Texture {
        \\    var handle:int = 1
        \\    drop { print(self.handle) }
        \\}
        \\struct File {
        \\    let handle:int
        \\    drop { print(self.handle) }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].drop != null);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].drop.?.statements.len);
    try std.testing.expect(program.structures[1].drop != null);
    try std.testing.expectEqual(@as(usize, 1), program.structures[1].drop.?.statements.len);
}

test "reject invalid drop declarations and explicit calls" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{ .source = "class Value { drop {} drop {} } func main() {}", .message = "a class can declare only one 'drop' block" },
        .{ .source = "struct Value { drop {} drop {} } func main() {}", .message = "a struct can declare only one 'drop' block" },
        .{ .source = "class Value { pub drop {} } func main() {}", .message = "'drop' does not accept a visibility modifier" },
        .{ .source = "class Value { sub drop {} } func main() {}", .message = "'drop' does not accept a visibility modifier" },
        .{ .source = "class Value { override drop {} } func main() {}", .message = "'override' cannot apply to 'drop'" },
        .{ .source = "class Value { drop() {} } func main() {}", .message = "'drop' must be followed by a block" },
        .{ .source = "class Value {} func main() { var value = Value(); value.drop() }", .message = "expected field name after '.'" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
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

test "parse class base and protocol conformance list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Player : Entity, Actor {} func main() {}");
    const program = try parser.parse();
    try std.testing.expectEqualStrings("Entity", program.structures[0].base.?.name);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].conformances.len);
    try std.testing.expectEqualStrings("Actor", program.structures[0].conformances[0].name);
}

test "parse protocols structure conformances and generic constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\pub protocol Describable {
        \\    func describe() str
        \\    func write(value:&str)
        \\}
        \\struct User : Describable {}
        \\func label<T : Describable>(value:T) str { return value.describe() }
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.protocols.len);
    try std.testing.expect(program.protocols[0].is_public);
    try std.testing.expectEqual(@as(usize, 2), program.protocols[0].requirements.len);
    try std.testing.expectEqualStrings("describe", program.protocols[0].requirements[0].name);
    try std.testing.expectEqual(Ast.ReturnType.str, program.protocols[0].requirements[0].return_type);
    try std.testing.expectEqual(Ast.ParameterMode.mutable_reference, program.protocols[0].requirements[1].parameters[0].mode);
    try std.testing.expectEqualStrings("Describable", program.structures[0].conformances[0].name);
    try std.testing.expectEqualStrings("Describable", program.functions[0].type_parameters[0].constraint.?.name);
}

test "reject unsupported protocol declaration forms" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{ .source = "protocol Value<T> {} func main() {}", .message = "generic protocols are not supported" },
        .{ .source = "protocol Child : Parent {} func main() {}", .message = "protocol inheritance is not supported" },
        .{ .source = "protocol Value { let count:int } func main() {}", .message = "a protocol can declare only method requirements" },
        .{ .source = "protocol Value { func read<T>() T } func main() {}", .message = "generic protocol methods are not supported" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
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
    var parser = Parser.init(arena.allocator(), "struct Position { pub var x:int } func main() {}");
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
        \\struct Point { var x:int }
        \\func main() void {
        \\    var point = Point(x:0)..x = 10..shift(1, 2)
        \\}
    );
    const program = try parser.parse();
    const cascade = program.functions[0].statements[0].variable_declaration.initializer.?.value.cascade;
    try std.testing.expectEqual(@as(usize, 2), cascade.operations.len);
    try std.testing.expect(cascade.operations[0] == .field_assignment);
    try std.testing.expectEqualStrings("10", cascade.operations[0].field_assignment.value.value.integer);
    try std.testing.expect(cascade.operations[1] == .method_call);
    try std.testing.expectEqualStrings("shift", cascade.operations[1].method_call.name);
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

test "parse public and private native functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\pub native func pow(value:int) int
        \\native func native_seed() int
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expect(program.functions[0].is_native);
    try std.testing.expect(program.functions[0].is_public);
    try std.testing.expectEqualStrings("pow", program.functions[0].name);
    try std.testing.expect(program.functions[1].is_native);
    try std.testing.expect(!program.functions[1].is_public);
    try std.testing.expectEqualStrings("native_seed", program.functions[1].name);
}

test "parse public and private opaque native resources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\pub native resource Buffer {
        \\    drop destroy_buffer
        \\}
        \\native resource Image { drop release_image }
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.structures.len);
    try std.testing.expect(program.structures[0].is_native_resource);
    try std.testing.expect(program.structures[0].is_public);
    try std.testing.expectEqualStrings("destroy_buffer", program.structures[0].native_drop_name.?);
    try std.testing.expect(program.structures[1].is_native_resource);
    try std.testing.expect(!program.structures[1].is_public);
    try std.testing.expectEqual(@as(usize, 3), program.functions.len);
    try std.testing.expect(program.functions[0].is_native_resource_drop);
    try std.testing.expectEqualStrings("destroy_buffer", program.functions[0].name);
    try std.testing.expectEqualStrings("Buffer", program.functions[0].parameters[0].type.structure);
}

test "reject malformed opaque native resources" {
    const cases = [_][]const u8{
        "native resource Buffer {} func main() {}",
        "native resource Buffer<T> { drop destroy } func main() {}",
        "native resource Buffer : Other { drop destroy } func main() {}",
        "native resource Buffer { drop destroy drop again } func main() {}",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
    }
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

test "parse static methods and generic static calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Box<T> {
        \\    var value:T
        \\    static func filled(value:T) Box<T> { return Box<T>(value:value) }
        \\}
        \\func main() { let box = Box<int>.filled(42) }
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].methods[0].is_static);
    const call = program.functions[0].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(call.value == .static_method_call);
    try std.testing.expect(call.value.static_method_call.owner == .generic_structure);
    try std.testing.expectEqualStrings("filled", call.value.static_method_call.name);
}

test "reject override on static method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Factory { override pub static func create() {} }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a static method cannot use 'override'", parser.diagnostic.?.message);
}

test "parse static fields and generic static field access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Cache<T> {
        \\    static var hits:int
        \\    let value:T
        \\}
        \\func main() { Cache<int>.hits = 1 }
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].fields[0].is_static);
    try std.testing.expect(!program.structures[0].fields[1].is_static);
    const target = program.functions[0].statements[0].assignment.target;
    try std.testing.expect(target.value == .static_field_access);
    try std.testing.expect(target.value.static_field_access.owner == .generic_structure);
    try std.testing.expectEqualStrings("hits", target.value.static_field_access.name);
}

test "override must precede method visibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Child { pub override func update() {} }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("'override' must precede the method visibility", parser.diagnostic.?.message);
}

test "parse generic structure declarations types and invocations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Pair<T> {
        \\    var first:T
        \\    var second:T
        \\}
        \\struct Entry<Key, Value> {
        \\    var key:Key
        \\    var value:Value
        \\}
        \\func main() {
        \\    let pair:Pair<int> = Pair<int>(first:1, second:2)
        \\    let nested = Entry<int, Pair<str>>(key:1, value:Pair<str>(first:"a", second:"b"))
        \\    print(pair.first < pair.second)
        \\}
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.structures[0].type_parameters[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[1].type_parameters.len);
    const annotation = program.functions[0].statements[0].variable_declaration.annotation.?.generic_structure;
    try std.testing.expectEqualStrings("Pair", annotation.name);
    try std.testing.expectEqual(Ast.TypeName.int, annotation.arguments[0]);
    const initializer = program.functions[0].statements[1].variable_declaration.initializer.?.value.call;
    try std.testing.expectEqual(@as(usize, 2), initializer.type_arguments.len);
    try std.testing.expect(initializer.type_arguments[1] == .generic_structure);
    try std.testing.expect(program.functions[0].statements[2].print.argument.value == .binary);
}

test "reject duplicate generic structure parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct Pair<T, T> { var value:T }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("type parameter is already declared", parser.diagnostic.?.message);
}

test "parse generic function declaration and invocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func identity<T>(value:T) T {
        \\    return value
        \\}
        \\func main() {
        \\    print(identity<int>(42))
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.functions[0].type_parameters[0].name);
    try std.testing.expect(program.functions[0].parameters[0].type == .structure);
    const call = program.functions[1].statements[0].print.argument.value.call;
    try std.testing.expectEqual(@as(usize, 1), call.type_arguments.len);
    try std.testing.expectEqual(Ast.TypeName.int, call.type_arguments[0]);
}

test "reject generic main function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main<T>() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("'main' cannot be generic", parser.diagnostic.?.message);
}

test "keep generic methods limited to instance extensions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var direct = Parser.init(arena.allocator(), "struct Box { func keep<T>(value:T) T { return value } } func main() {}");
    try std.testing.expectError(error.InvalidSource, direct.parse());
    try std.testing.expectEqualStrings("generic methods are not supported", direct.diagnostic.?.message);

    var protocol = Parser.init(arena.allocator(), "protocol Box { func keep<T>(value:T) T } func main() {}");
    try std.testing.expectError(error.InvalidSource, protocol.parse());
    try std.testing.expectEqualStrings("generic protocol methods are not supported", protocol.diagnostic.?.message);
}

test "parse transparent type aliases with use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\use Vec3<int> as Vec3i
        \\use int[] as Integers
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expect(program.uses[0].target == .type);
    try std.testing.expect(program.uses[0].target.type == .generic_structure);
    try std.testing.expectEqualStrings("Vec3i", program.uses[0].alias.?);
    try std.testing.expect(program.uses[1].target.type == .list);
}

test "parse enums and expression and imperative matches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Verdict { idle; value(int, str); failed(str) }
        \\func main() {
        \\    let result = Verdict.value(7, "ok")
        \\    let text = match result { idle => "idle"; value(number, text) => text; failed(error) => error }
        \\    match result { idle => {}; value(var number, let text) => { print(text) }; failed(error) => {} }
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.enums.len);
    try std.testing.expectEqualStrings("Verdict", program.enums[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.enums[0].variants[1].associated_types.len);
    const expression_match = program.functions[0].statements[1].variable_declaration.initializer.?.value.match_expression;
    try std.testing.expectEqual(@as(usize, 3), expression_match.branches.len);
    try std.testing.expect(expression_match.branches[1].body == .expression);
    const imperative_match = program.functions[0].statements[2].expression_statement.value.match_expression;
    try std.testing.expect(imperative_match.branches[1].body == .statements);
    try std.testing.expectEqual(Ast.Mutability.mutable, imperative_match.branches[1].bindings[0].mutability);
}

test "parse generic enum declarations and specialized variant constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Outcome<T, E> { success(T); failure(E) }
        \\func main() {
        \\    let value:Outcome<int, str> = Outcome<int, str>.success(42)
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.enums[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.enums[0].type_parameters[0].name);
    try std.testing.expectEqualStrings("E", program.enums[0].type_parameters[1].name);
    try std.testing.expectEqualStrings("T", program.enums[0].variants[0].associated_types[0].structure);
    const annotation = program.functions[0].statements[0].variable_declaration.annotation.?.generic_structure;
    try std.testing.expectEqualStrings("Outcome", annotation.name);
    try std.testing.expectEqual(@as(usize, 2), annotation.arguments.len);
    const owner = program.functions[0].statements[0].variable_declaration.initializer.?.value.static_method_call.owner.generic_structure;
    try std.testing.expectEqualStrings("Outcome", owner.name);
    try std.testing.expectEqual(@as(usize, 2), owner.arguments.len);
}

test "parse intrinsic Result with a void success type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum SaveError { denied }
        \\func save() Result<void, SaveError> {
        \\    return Result<void, SaveError>.success()
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const return_type = program.functions[0].return_type.generic_structure;
    try std.testing.expectEqualStrings("Result", return_type.name);
    try std.testing.expectEqual(Ast.TypeName.void, return_type.arguments[0]);
    const owner = program.functions[0].statements[0].return_statement.value.?.value.static_method_call.owner.generic_structure;
    try std.testing.expectEqual(Ast.TypeName.void, owner.arguments[0]);
}

test "parse try with prefix precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func read() Result<int, Failure> { return Result<int, Failure>.success(1) }
        \\func load() Result<int, Failure> {
        \\    let value = try read() + 1
        \\    let member = try loader.read()
        \\    return Result<int, Failure>.success(value)
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const initializer = program.functions[1].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(initializer.value == .binary);
    try std.testing.expect(initializer.value.binary.left.value == .try_expression);
    try std.testing.expect(initializer.value.binary.left.value.try_expression.operand.value == .call);
    const member = program.functions[1].statements[1].variable_declaration.initializer.?;
    try std.testing.expect(member.value == .try_expression);
    try std.testing.expect(member.value.try_expression.operand.value == .method_call);
}

test "parse move with prefix precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let next = move current
        \\}
    );
    const program = try parser.parse();
    const initializer = program.functions[0].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(initializer.value == .move_expression);
    try std.testing.expect(initializer.value.move_expression.operand.value == .identifier);
}

test "parse deferred function type and literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    var callback:deferred func(int) = deferred func(value:int) {}
        \\}
    );
    const program = try parser.parse();
    const declaration = program.functions[0].statements[0].variable_declaration;
    try std.testing.expect(declaration.annotation.?.function.deferred);
    try std.testing.expect(declaration.initializer.?.value.lambda.deferred);
}

test "reserve Result and reject void as its error type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var error_type = Parser.init(arena.allocator(), "func main() { let value:Result<int, void> }");
    try std.testing.expectError(error.InvalidSource, error_type.parse());
    try std.testing.expectEqualStrings("Result error type cannot be 'void'", error_type.diagnostic.?.message);

    var both_void = Parser.init(arena.allocator(), "func main() { let value:Result<void, void> }");
    try std.testing.expectError(error.InvalidSource, both_void.parse());
    try std.testing.expectEqualStrings("Result error type cannot be 'void'", both_void.diagnostic.?.message);

    var enum_name = Parser.init(arena.allocator(), "enum Result<T, E> { success(T); failure(E) } func main() {}");
    try std.testing.expectError(error.InvalidSource, enum_name.parse());
    try std.testing.expectEqualStrings("type name 'Result' is reserved", enum_name.diagnostic.?.message);

    var type_parameter = Parser.init(arena.allocator(), "struct Box<Result> { var value:Result } func main() {}");
    try std.testing.expectError(error.InvalidSource, type_parameter.parse());
    try std.testing.expectEqualStrings("type name 'Result' is reserved", type_parameter.diagnostic.?.message);

    var module_alias = Parser.init(arena.allocator(), "use Library as Result\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, module_alias.parse());
    try std.testing.expectEqualStrings("name 'Result' is reserved", module_alias.diagnostic.?.message);
}

test "removed import reports its use replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var aliased = Parser.init(arena.allocator(), "import STD as Standard\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, aliased.parse());
    try std.testing.expectEqualStrings(
        "'import' was removed; use 'use STD as Standard'",
        aliased.diagnostic.?.message,
    );

    var direct = Parser.init(arena.allocator(), "import STD\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, direct.parse());
    try std.testing.expectEqualStrings("'import' was removed; use 'use STD'", direct.diagnostic.?.message);
}

test "parse terminal else match branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum State { idle; ready; failed(str) }
        \\func main() {
        \\    let state = State.idle()
        \\    let text = match state { idle => "idle"; else => "other" }
        \\    match state { failed(message) => { print(message) }; else => {} }
        \\}
    );
    const program = try parser.parse();
    const expression_match = program.functions[0].statements[1].variable_declaration.initializer.?.value.match_expression;
    try std.testing.expect(expression_match.branches[0].variant != null);
    try std.testing.expect(expression_match.branches[1].variant == null);
    const imperative_match = program.functions[0].statements[2].expression_statement.value.match_expression;
    try std.testing.expect(imperative_match.branches[1].variant == null);
}

test "reject misplaced and binding else match branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var misplaced = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { else => {}; ready => {} } }
    );
    try std.testing.expectError(error.InvalidSource, misplaced.parse());
    try std.testing.expectEqualStrings("else must be the last match branch", misplaced.diagnostic.?.message);

    var binding = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; else(value) => {} } }
    );
    try std.testing.expectError(error.InvalidSource, binding.parse());
    try std.testing.expectEqualStrings("an else match branch cannot bind associated values", binding.diagnostic.?.message);
}

test "reject mixed enum match branch forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 0; ready => {} } }
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("match branches cannot mix expressions and blocks", parser.diagnostic.?.message);
}

test "parse int and string raw enums" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Direction:int { north = 1; unknown = -1 }
        \\enum DirectionName:str { north = "north"; south = "south" }
        \\func main() { print(Direction.north().raw_value) }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.RawEnumType.int, program.enums[0].raw_type.?);
    try std.testing.expect(program.enums[0].variants[0].raw_value.?.value == .integer);
    try std.testing.expect(program.enums[0].variants[1].raw_value.?.value == .unary);
    try std.testing.expectEqual(Ast.RawEnumType.str, program.enums[1].raw_type.?);
    try std.testing.expect(program.enums[1].variants[0].raw_value.?.value == .string);
}

test "reject invalid raw enum declaration shapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var invalid_type = Parser.init(arena.allocator(), "enum State:bool { ready = true }");
    try std.testing.expectError(error.InvalidSource, invalid_type.parse());
    try std.testing.expectEqualStrings("an enum raw type must be 'int' or 'str'", invalid_type.diagnostic.?.message);

    var missing_value = Parser.init(arena.allocator(), "enum State:int { ready }");
    try std.testing.expectError(error.InvalidSource, missing_value.parse());
    try std.testing.expectEqualStrings("a raw enum variant requires a value", missing_value.diagnostic.?.message);

    var associated_value = Parser.init(arena.allocator(), "enum State:int { ready(str) = 1 }");
    try std.testing.expectError(error.InvalidSource, associated_value.parse());
    try std.testing.expectEqualStrings("a raw enum variant cannot declare associated values", associated_value.diagnostic.?.message);

    var missing_type = Parser.init(arena.allocator(), "enum State { ready = 1 }");
    try std.testing.expectError(error.InvalidSource, missing_type.parse());
    try std.testing.expectEqualStrings("an enum without a raw type cannot assign variant values", missing_type.diagnostic.?.message);

    var generic_raw = Parser.init(arena.allocator(), "enum State<T>:int { ready = 1 }");
    try std.testing.expectError(error.InvalidSource, generic_raw.parse());
    try std.testing.expectEqualStrings("a raw enum cannot be generic", generic_raw.diagnostic.?.message);
}

test "require a name for a type alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "use int[]\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a type expression after 'use' requires an alias with 'as'", parser.diagnostic.?.message);
}

test "parse type extensions and reject stateful members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\extend STD.Randomizer {
        \\    pub func get_uint() uint { return self.get_int() as uint }
        \\    static func seeded() Randomizer { return Randomizer.create() }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.extensions.len);
    try std.testing.expectEqualStrings("STD.Randomizer", program.extensions[0].target);
    try std.testing.expectEqual(@as(usize, 2), program.extensions[0].methods.len);
    try std.testing.expect(program.extensions[0].methods[0].is_public);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.extensions[0].methods[0].member_visibility.?);
    try std.testing.expect(program.extensions[0].methods[1].is_static);
    try std.testing.expect(program.extensions[0].methods[1].member_visibility == null);

    var generic_method = Parser.init(arena.allocator(),
        \\extend Randomizer {
        \\    pub func choose<T>(values:@T[..]) @values:T { return @values[0] }
        \\    func select<Key, Value:Comparable>(key:Key, fallback:Value?) Value? { return fallback }
        \\}
        \\func main() {}
    );
    const generic_program = try generic_method.parse();
    try std.testing.expectEqual(@as(usize, 1), generic_program.extensions[0].methods[0].type_parameters.len);
    try std.testing.expectEqual(@as(usize, 2), generic_program.extensions[0].methods[1].type_parameters.len);
    try std.testing.expectEqualStrings("Comparable", generic_program.extensions[0].methods[1].type_parameters[1].constraint.?.name);

    var generic_static = Parser.init(arena.allocator(), "extend Randomizer { static func create<T>() Randomizer {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, generic_static.parse());
    try std.testing.expectEqualStrings("generic static extension methods are not supported", generic_static.diagnostic.?.message);

    var field = Parser.init(arena.allocator(), "extend Randomizer { var state:int } func main() {}");
    try std.testing.expectError(error.InvalidSource, field.parse());
    try std.testing.expectEqualStrings("an extension cannot declare a field", field.diagnostic.?.message);

    var subclass = Parser.init(arena.allocator(), "extend Randomizer { sub func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, subclass.parse());
    try std.testing.expectEqualStrings("an extension method cannot use 'sub'", subclass.diagnostic.?.message);

    var constructor = Parser.init(arena.allocator(), "extend Randomizer { init() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, constructor.parse());
    try std.testing.expectEqualStrings("an extension cannot declare a constructor", constructor.diagnostic.?.message);

    var destructor = Parser.init(arena.allocator(), "extend Randomizer { drop {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, destructor.parse());
    try std.testing.expectEqualStrings("an extension cannot declare 'drop'", destructor.diagnostic.?.message);

    var override_method = Parser.init(arena.allocator(), "extend Randomizer { override func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, override_method.parse());
    try std.testing.expectEqualStrings("an extension method cannot use 'override'", override_method.diagnostic.?.message);

    var generic = Parser.init(arena.allocator(), "extend Randomizer<int> { func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, generic.parse());
    try std.testing.expectEqualStrings("generic extensions are not supported", generic.diagnostic.?.message);
}

test "parse protocol conformances on a type extension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\extend Sprite : Drawable, UI.Renderable {
        \\    pub func draw() {}
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.extensions.len);
    try std.testing.expectEqual(@as(usize, 2), program.extensions[0].conformances.len);
    try std.testing.expectEqualStrings("Drawable", program.extensions[0].conformances[0].name);
    try std.testing.expectEqualStrings("UI.Renderable", program.extensions[0].conformances[1].name);

    var missing = Parser.init(arena.allocator(), "extend Sprite : { } func main() {}");
    try std.testing.expectError(error.InvalidSource, missing.parse());
    try std.testing.expectEqualStrings("expected protocol name after ':'", missing.diagnostic.?.message);
}

test "parse read reference parameters with ordinary arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Data { let value:int }
        \\func inspect(value:@Data) int { return value.value }
        \\func main() { let data = Data(value:1); inspect(data) }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.functions[0].parameters[0].mode);
    const call = program.functions[1].statements[1].expression_statement.value.call;
    try std.testing.expect(call.arguments[0].value == .identifier);

    var released_identifier = Parser.init(arena.allocator(), "func borrow(value:int) int { return value } func main() {}");
    _ = try released_identifier.parse();

    var old_keyword = Parser.init(arena.allocator(), "func inspect(borrow value:Data) {} func main() {}");
    try std.testing.expectError(error.InvalidSource, old_keyword.parse());

    var old_postfix = Parser.init(arena.allocator(), "func inspect(value:Data@) {} func main() {}");
    try std.testing.expectError(error.InvalidSource, old_postfix.parse());
}
