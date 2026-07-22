const std = @import("std");
const Ast = @import("../Ast.zig");
const LexerModule = @import("../Lexer.zig");
const Source = @import("../Source.zig");

const Allocator = std.mem.Allocator;
const Token = LexerModule.Token;
const TokenTag = LexerModule.TokenTag;
const ParseError = Source.Error || Allocator.Error;
const Expressions = @import("Expressions.zig");

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
            } else if (self.current.tag == .keyword_public) {
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
                } else return self.fail("expected 'enum', 'protocol', 'struct', 'class', 'func', 'native func', 'native resource', or 'use' after 'public'");
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

    pub fn parseExtension(self: *Parser) ParseError!Ast.Extension {
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
            if (self.current.tag == .keyword_protected) return self.fail("an extension method cannot use 'protected'");
            if (self.current.tag == .keyword_private) return self.fail("an extension method cannot use 'private'");
            if (self.current.tag == .keyword_override) return self.fail("an extension method cannot use 'override'");
            const is_public = self.current.tag == .keyword_public;
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

    pub fn parseProtocol(self: *Parser, is_public: bool) ParseError!Ast.Protocol {
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

    pub fn parseEnum(self: *Parser, is_public: bool) ParseError!Ast.Enum {
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

    pub fn rejectImport(self: *Parser) ParseError!Ast.Program {
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

    pub fn parseUse(self: *Parser, is_public: bool) ParseError!Ast.Use {
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

    pub fn parseOptionalAlias(self: *Parser) ParseError!?ParsedAlias {
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

    pub fn parseQualifiedName(self: *Parser, message: []const u8) ParseError![]const u8 {
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

    pub fn parseStructure(self: *Parser, is_public: bool) ParseError!Ast.Structure {
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
            const has_visibility = self.current.tag == .keyword_private or
                self.current.tag == .keyword_protected or
                self.current.tag == .keyword_public;
            if (has_visibility) {
                if (!is_class and self.current.tag == .keyword_protected) {
                    return self.fail("a struct member cannot use 'protected' because structs do not support inheritance");
                }
                visibility = switch (self.current.tag) {
                    .keyword_private => .private_access,
                    .keyword_protected => .subclass,
                    .keyword_public => .public_access,
                    else => unreachable,
                };
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
                const constructor_position = self.current.position;
                try self.advance();
                const parameters = try self.parseParameters();
                var super_arguments: ?[]const *Ast.Expression = null;
                var super_position: ?Source.Position = null;
                if (self.current.tag == .colon) {
                    if (!is_class) return self.fail("a struct constructor cannot call 'super'");
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

    pub fn parseFunction(self: *Parser, is_public: bool) ParseError!Ast.Function {
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

    pub fn parseNativeFunction(self: *Parser, is_public: bool) ParseError!Ast.Function {
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, "native")) {
            return self.fail("expected 'native'");
        }
        try self.advance();
        return self.parseNativeFunctionAfterNative(is_public);
    }

    pub fn parseNativeFunctionAfterNative(self: *Parser, is_public: bool) ParseError!Ast.Function {
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

    pub fn parseNativeResource(self: *Parser, is_public: bool) ParseError!Ast.Structure {
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

    pub fn nativeResourceDropFunction(self: *Parser, resource: Ast.Structure) Allocator.Error!Ast.Function {
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

    pub fn parseReturnType(self: *Parser) ParseError!Ast.ReturnType {
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
        const type_name = if (reference_mode != null and self.current.tag == .keyword_self) reference: {
            provenance = "self";
            try self.advance();
            if (self.current.tag != .colon) return self.fail("expected ':' after 'self' return provenance");
            try self.advance();
            break :reference try self.parseTypeNameAfter("expected function return type after provenance");
        } else if (reference_mode != null and self.current.tag == .identifier) reference: {
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

    pub fn parseParameters(self: *Parser) ParseError![]const Ast.Parameter {
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

    pub fn parseBlock(self: *Parser) ParseError![]const Ast.Statement {
        try self.expect(.left_brace, "expected '{'");
        var statements: std.ArrayList(Ast.Statement) = .empty;
        while (self.current.tag != .right_brace and self.current.tag != .end) {
            try statements.append(self.allocator, try self.parseStatement());
        }
        try self.expect(.right_brace, "expected '}'");
        return statements.toOwnedSlice(self.allocator);
    }

    pub fn parseStatement(self: *Parser) ParseError!Ast.Statement {
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

    pub fn parseMatchStatement(self: *Parser) ParseError!Ast.Statement {
        const expression = try self.parseMatchExpression();
        for (expression.value.match_expression.branches) |branch| {
            if (branch.body != .statements) return self.failAt(expression.position, "an imperative match requires a block in every branch");
        }
        return .{ .expression_statement = expression };
    }

    pub fn parseTryStatement(self: *Parser) ParseError!Ast.Statement {
        const expression = try self.parseExpression(false);
        try self.expectStatementTerminator();
        return .{ .expression_statement = expression };
    }

    pub fn parsePrint(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '('");
        const argument = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')'");
        try self.expectStatementTerminator();
        return .{ .print = .{ .position = position, .argument = argument } };
    }

    pub fn parseAssert(self: *Parser) ParseError!Ast.Statement {
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

    pub fn parsePanic(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expect(.left_parenthesis, "expected '(' after 'panic'");
        const message = try self.parseExpression(true);
        try self.expect(.right_parenthesis, "expected ')' after panic message");
        try self.expectStatementTerminator();
        return .{ .panic_statement = .{ .position = position, .message = message } };
    }

    pub fn parseVariableDeclaration(self: *Parser, mutability: Ast.Mutability) ParseError!Ast.Statement {
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

    pub fn parseTypeName(self: *Parser) ParseError!Ast.TypeName {
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

    pub fn parseTypeNameAfter(self: *Parser, message: []const u8) ParseError!Ast.TypeName {
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

    pub fn parseFunctionType(self: *Parser, deferred: bool) ParseError!Ast.TypeName {
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

    pub fn isTypeStart(self: *const Parser) bool {
        return switch (self.current.tag) {
            .left_parenthesis, .keyword_func, .keyword_deferred, .keyword_int, .keyword_int8, .keyword_int16, .keyword_int32, .keyword_int64, .keyword_uint, .keyword_uint8, .keyword_uint16, .keyword_uint32, .keyword_uint64, .keyword_float, .keyword_float32, .keyword_float64, .keyword_bool, .keyword_str, .identifier => true,
            else => false,
        };
    }

    pub fn parseIdentifierStatement(self: *Parser) ParseError!Ast.Statement {
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

    pub fn parseIf(self: *Parser) ParseError!Ast.Statement {
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

    pub fn parseIfAlternative(self: *Parser) ParseError!Ast.Statement.If.Alternative {
        return .{
            .condition = try self.parseCondition(),
            .body = try self.parseBlock(),
        };
    }

    pub fn parseWhile(self: *Parser) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        const condition = try self.parseCondition();
        const body = try self.parseBlock();
        return .{ .while_statement = .{ .position = position, .condition = condition, .body = body } };
    }

    pub fn parseCondition(self: *Parser) ParseError!Ast.Statement.Condition {
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

    pub fn parenthesizedConditionStartsBinding(self: *const Parser) Source.Error!bool {
        var lexer = self.lexer;
        const first = try lexer.next();
        if (first.tag == .keyword_let or first.tag == .keyword_var) return true;
        if (first.tag != .identifier) return false;
        return (try lexer.next()).tag == .equal;
    }

    pub fn parseFor(self: *Parser) ParseError!Ast.Statement {
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

    pub fn parseForSource(self: *Parser, allow_line_breaks: bool) ParseError!Ast.Statement.For.IterationSource {
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

    pub fn parseLoopControl(self: *Parser, comptime tag: std.meta.Tag(Ast.Statement)) ParseError!Ast.Statement {
        const position = self.current.position;
        try self.advance();
        try self.expectStatementTerminator();
        return @unionInit(Ast.Statement, @tagName(tag), position);
    }

    pub fn parseReturn(self: *Parser) ParseError!Ast.Statement {
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

    const InvocationArguments = Expressions.InvocationArguments;

    pub fn parseExpression(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseExpression(self, allow_line_breaks);
    }

    pub fn parseCascade(self: *Parser, object: *Ast.Expression) ParseError!*Ast.Expression {
        return Expressions.parseCascade(self, object);
    }

    pub fn parseLogicalOr(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseLogicalOr(self, allow_line_breaks);
    }

    pub fn parseLogicalAnd(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseLogicalAnd(self, allow_line_breaks);
    }

    pub fn parseEquality(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseEquality(self, allow_line_breaks);
    }

    pub fn parseComparison(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseComparison(self, allow_line_breaks);
    }

    pub fn parseBitXor(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseBitXor(self, allow_line_breaks);
    }

    pub fn parseBitAnd(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseBitAnd(self, allow_line_breaks);
    }

    pub fn parseShift(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseShift(self, allow_line_breaks);
    }

    pub fn parseAdditive(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseAdditive(self, allow_line_breaks);
    }

    pub fn parseMultiplicative(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseMultiplicative(self, allow_line_breaks);
    }

    pub fn parseUnary(self: *Parser, allow_line_breaks: bool) ParseError!*Ast.Expression {
        return Expressions.parseUnary(self, allow_line_breaks);
    }

    pub fn parseConversion(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parseConversion(self);
    }

    pub fn parsePrimary(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parsePrimary(self);
    }

    pub fn parseMatchExpression(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parseMatchExpression(self);
    }

    pub fn parseSuperMethodCall(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parseSuperMethodCall(self);
    }

    pub fn parseLambda(self: *Parser, deferred: bool) ParseError!*Ast.Expression {
        return Expressions.parseLambda(self, deferred);
    }

    pub fn parseSequenceLiteral(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parseSequenceLiteral(self);
    }

    pub fn parseIdentifierExpression(self: *Parser) ParseError!*Ast.Expression {
        return Expressions.parseIdentifierExpression(self);
    }

    pub fn parseIdentifierExpressionAfterToken(self: *Parser, token: Token) ParseError!*Ast.Expression {
        return Expressions.parseIdentifierExpressionAfterToken(self, token);
    }

    pub fn parsePostfix(self: *Parser, initial: *Ast.Expression) ParseError!*Ast.Expression {
        return Expressions.parsePostfix(self, initial);
    }

    pub fn parseStaticMember(self: *Parser, owner: Ast.TypeName, owner_position: Source.Position) ParseError!*Ast.Expression {
        return Expressions.parseStaticMember(self, owner, owner_position);
    }

    pub fn parseCallAfterName(
        self: *Parser,
        name: []const u8,
        position: Source.Position,
        type_arguments: []const Ast.TypeName,
    ) ParseError!*Ast.Expression {
        return Expressions.parseCallAfterName(self, name, position, type_arguments);
    }

    pub fn parseInvocationArguments(self: *Parser) ParseError!InvocationArguments {
        return Expressions.parseInvocationArguments(self);
    }

    pub fn currentStartsNamedField(self: *const Parser) ParseError!bool {
        return Expressions.currentStartsNamedField(self);
    }

    pub fn looksLikeLegacyStructureInitializer(self: *const Parser) ParseError!bool {
        return Expressions.looksLikeLegacyStructureInitializer(self);
    }

    pub fn parseCallArguments(self: *Parser) ParseError![]const *Ast.Expression {
        return Expressions.parseCallArguments(self);
    }

    pub fn parseMethodCall(
        self: *Parser,
        object: *Ast.Expression,
        name: []const u8,
        position: Source.Position,
        type_arguments: []const Ast.TypeName,
    ) ParseError!*Ast.Expression {
        return Expressions.parseMethodCall(self, object, name, position, type_arguments);
    }

    pub fn parseTypeParameters(self: *Parser, declaration_kind: []const u8) ParseError![]const Ast.TypeParameter {
        return Expressions.parseTypeParameters(self, declaration_kind);
    }

    pub fn parseTypeArguments(self: *Parser, owner_name: ?[]const u8) ParseError![]const Ast.TypeName {
        return Expressions.parseTypeArguments(self, owner_name);
    }

    pub fn expectTypeArgumentClose(self: *Parser) ParseError!void {
        return Expressions.expectTypeArgumentClose(self);
    }

    pub fn genericInvocationFollows(self: *const Parser) bool {
        return Expressions.genericInvocationFollows(self);
    }

    pub fn genericStaticMemberFollows(self: *const Parser) bool {
        return Expressions.genericStaticMemberFollows(self);
    }

    pub fn malformedGenericSuffixFollows(self: *const Parser, suffix: TokenTag) bool {
        return Expressions.malformedGenericSuffixFollows(self, suffix);
    }

    pub fn expressionPath(self: *Parser, expression: *const Ast.Expression) ParseError!?[]const u8 {
        return Expressions.expressionPath(self, expression);
    }

    pub fn binaryExpression(
        self: *Parser,
        left: *Ast.Expression,
        right: *Ast.Expression,
        operator_token: Token,
    ) ParseError!*Ast.Expression {
        return Expressions.binaryExpression(self, left, right, operator_token);
    }
    pub fn newExpression(self: *Parser, value: Ast.Expression) !*Ast.Expression {
        const result = try self.allocator.create(Ast.Expression);
        result.* = value;
        return result;
    }

    pub fn newTypeName(self: *Parser, type_name: Ast.TypeName) !*Ast.TypeName {
        const result = try self.allocator.create(Ast.TypeName);
        result.* = type_name;
        return result;
    }

    pub fn expect(self: *Parser, tag: TokenTag, message: []const u8) !void {
        if (self.current.tag != tag) return self.fail(message);
        try self.advance();
    }

    pub fn peekTag(self: *const Parser) Source.Error!TokenTag {
        var lexer = self.lexer;
        return (try lexer.next()).tag;
    }

    pub fn expectIdentifier(self: *Parser, expected: []const u8, message: []const u8) !void {
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.lexeme, expected)) {
            return self.fail(message);
        }
        try self.advance();
    }

    pub fn expectStatementTerminator(self: *Parser) ParseError!void {
        if (self.current.tag == .semicolon and self.current.position.line == self.previous.position.line) {
            try self.advance();
            return;
        }
        if (self.current.tag == .right_brace or self.current.tag == .end) return;
        if (self.current.position.line > self.previous.position.line) return;
        return self.fail("expected ';' or line break");
    }

    pub fn canContinueExpression(self: *const Parser, allow_line_breaks: bool) bool {
        return allow_line_breaks or self.current.position.line == self.previous.position.line;
    }

    pub fn advance(self: *Parser) !void {
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

    pub fn fail(self: *Parser, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = self.current.position, .message = message };
        return error.InvalidSource;
    }

    pub fn failAt(self: *Parser, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

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
