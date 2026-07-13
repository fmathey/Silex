const std = @import("std");
const Source = @import("Source.zig");

pub const TokenTag = enum {
    keyword_void,
    keyword_let,
    keyword_var,
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_for,
    keyword_in,
    keyword_break,
    keyword_continue,
    keyword_return,
    keyword_struct,
    keyword_func,
    keyword_self,
    keyword_true,
    keyword_false,
    keyword_int,
    keyword_int8,
    keyword_int16,
    keyword_int32,
    keyword_int64,
    keyword_uint,
    keyword_uint8,
    keyword_uint16,
    keyword_uint32,
    keyword_uint64,
    keyword_float,
    keyword_float32,
    keyword_float64,
    keyword_bool,
    keyword_str,
    keyword_print,
    keyword_import,
    keyword_use,
    keyword_pub,
    keyword_as,
    identifier,
    integer,
    floating,
    string,
    plus,
    plus_plus,
    plus_equal,
    minus,
    minus_minus,
    minus_equal,
    star,
    star_equal,
    slash,
    slash_equal,
    bang,
    equal,
    equal_equal,
    bang_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    amp_amp,
    amp,
    at,
    caret,
    pipe_pipe,
    colon,
    comma,
    dot,
    left_parenthesis,
    right_parenthesis,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    semicolon,
    end,
};

pub const Token = struct {
    tag: TokenTag,
    lexeme: []const u8,
    position: Source.Position,
};

pub const Lexer = struct {
    source: []const u8,
    index: usize = 0,
    line: usize = 1,
    column: usize = 1,
    file: usize = 0,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    pub fn initFile(source: []const u8, file: usize) Lexer {
        return .{ .source = source, .file = file };
    }

    pub fn next(self: *Lexer) Source.Error!Token {
        self.skipIgnored();

        if (self.index == self.source.len) {
            return self.token(.end, self.index, self.currentPosition());
        }

        const start = self.index;
        const position = self.currentPosition();
        const character = self.source[self.index];

        if (isIdentifierStart(character)) {
            self.advance();
            while (self.index < self.source.len and isIdentifierContinue(self.source[self.index])) {
                self.advance();
            }

            const lexeme = self.source[start..self.index];
            return .{ .tag = keywordTag(lexeme) orelse .identifier, .lexeme = lexeme, .position = position };
        }

        if (std.ascii.isDigit(character)) return self.numericToken(start, position);

        if (character == '"') return self.stringToken(position);

        if (character == '=') return self.optionalDoubleToken(start, position, '=', .equal, .equal_equal);
        if (character == '!') return self.optionalDoubleToken(start, position, '=', .bang, .bang_equal);
        if (character == '<') return self.optionalDoubleToken(start, position, '=', .less, .less_equal);
        if (character == '>') return self.optionalDoubleToken(start, position, '=', .greater, .greater_equal);
        if (character == '&') return self.optionalDoubleToken(start, position, '&', .amp, .amp_amp);
        if (character == '|') return self.requiredDoubleToken(start, position, '|', .pipe_pipe, "expected '||'");
        if (character == '+') return self.arithmeticToken(start, position, '+', .plus, .plus_plus, .plus_equal);
        if (character == '-') return self.arithmeticToken(start, position, '-', .minus, .minus_minus, .minus_equal);
        if (character == '*') return self.arithmeticToken(start, position, 0, .star, .star, .star_equal);
        if (character == '/') return self.arithmeticToken(start, position, 0, .slash, .slash, .slash_equal);

        self.advance();
        return switch (character) {
            ':' => self.token(.colon, start, position),
            '@' => self.token(.at, start, position),
            '^' => self.token(.caret, start, position),
            ',' => self.token(.comma, start, position),
            '.' => self.token(.dot, start, position),
            '(' => self.token(.left_parenthesis, start, position),
            ')' => self.token(.right_parenthesis, start, position),
            '{' => self.token(.left_brace, start, position),
            '}' => self.token(.right_brace, start, position),
            '[' => self.token(.left_bracket, start, position),
            ']' => self.token(.right_bracket, start, position),
            ';' => self.token(.semicolon, start, position),
            else => self.fail(position, "invalid character"),
        };
    }

    fn stringToken(self: *Lexer, position: Source.Position) Source.Error!Token {
        self.advance();
        const contents_start = self.index;
        while (self.index < self.source.len) {
            switch (self.source[self.index]) {
                '"' => {
                    const lexeme = self.source[contents_start..self.index];
                    if (!std.unicode.utf8ValidateSlice(lexeme)) {
                        return self.fail(position, "string literal is not valid UTF-8");
                    }
                    self.advance();
                    return .{ .tag = .string, .lexeme = lexeme, .position = position };
                },
                '\n', '\r' => return self.fail(position, "unterminated string literal"),
                '\\' => {
                    self.advance();
                    if (self.index == self.source.len) {
                        return self.fail(position, "unterminated string literal");
                    }
                    try self.stringEscape(position);
                },
                else => self.advance(),
            }
        }
        return self.fail(position, "unterminated string literal");
    }

    fn stringEscape(self: *Lexer, position: Source.Position) Source.Error!void {
        switch (self.source[self.index]) {
            '"', '\\', 'n', 'r', 't', '0' => self.advance(),
            'u' => {
                self.advance();
                if (self.index == self.source.len or self.source[self.index] != '{') {
                    return self.fail(position, "expected '{' after '\\u' in string escape");
                }
                self.advance();
                var scalar: u21 = 0;
                var digits: usize = 0;
                while (self.index < self.source.len and self.source[self.index] != '}') {
                    const digit = digitValue(self.source[self.index]) orelse {
                        return self.fail(position, "invalid Unicode escape in string literal");
                    };
                    if (digits == 6 or digit >= 16) {
                        return self.fail(position, "invalid Unicode escape in string literal");
                    }
                    scalar = scalar * 16 + digit;
                    digits += 1;
                    self.advance();
                }
                if (digits == 0 or self.index == self.source.len) {
                    return self.fail(position, "invalid Unicode escape in string literal");
                }
                if (!isUnicodeScalar(scalar)) return self.fail(position, "invalid Unicode scalar in string literal");
                self.advance();
            },
            else => return self.fail(position, "invalid escape sequence in string literal"),
        }
    }

    fn numericToken(self: *Lexer, start: usize, position: Source.Position) Source.Error!Token {
        if (self.source[start] == '0' and self.index + 1 < self.source.len) {
            const prefix = self.source[self.index + 1];
            const base: ?u8 = switch (prefix) {
                'b', 'B' => 2,
                'o', 'O' => 8,
                'x', 'X' => 16,
                else => null,
            };
            if (base) |value| {
                self.advance();
                self.advance();
                try self.scanDigits(value, position, "expected digit after numeric base prefix");
                if (self.index < self.source.len and isIdentifierContinue(self.source[self.index])) {
                    return self.fail(position, "invalid digit in numeric literal");
                }
                return self.token(.integer, start, position);
            }
        }

        try self.scanDigits(10, position, "expected digit in numeric literal");
        var floating = false;
        if (self.index + 1 < self.source.len and self.source[self.index] == '.' and
            std.ascii.isDigit(self.source[self.index + 1]))
        {
            floating = true;
            self.advance();
            try self.scanDigits(10, position, "expected digit after decimal point");
        }
        if (self.index < self.source.len and (self.source[self.index] == 'e' or self.source[self.index] == 'E')) {
            floating = true;
            self.advance();
            if (self.index < self.source.len and (self.source[self.index] == '+' or self.source[self.index] == '-')) {
                self.advance();
            }
            try self.scanDigits(10, position, "expected exponent digit");
        }
        if (self.index < self.source.len and isIdentifierContinue(self.source[self.index])) {
            return self.fail(position, "invalid digit in decimal literal");
        }
        return self.token(if (floating) .floating else .integer, start, position);
    }

    fn scanDigits(
        self: *Lexer,
        base: u8,
        position: Source.Position,
        empty_message: []const u8,
    ) Source.Error!void {
        var found_digit = false;
        while (self.index < self.source.len) {
            const character = self.source[self.index];
            if (digitValue(character)) |value| {
                if (value >= base) {
                    if (std.ascii.isDigit(character)) return self.fail(position, "invalid digit in numeric literal");
                    break;
                }
                found_digit = true;
                self.advance();
                continue;
            }
            if (character == '_') {
                if (!found_digit or self.index + 1 == self.source.len) {
                    return self.fail(position, "numeric separator must appear between digits");
                }
                const following_digit = digitValue(self.source[self.index + 1]) orelse {
                    return self.fail(position, "numeric separator must appear between digits");
                };
                if (following_digit >= base) return self.fail(position, "invalid digit in numeric literal");
                self.advance();
                continue;
            }
            break;
        }
        if (!found_digit) return self.fail(position, empty_message);
    }

    fn optionalDoubleToken(
        self: *Lexer,
        start: usize,
        position: Source.Position,
        second: u8,
        single_tag: TokenTag,
        double_tag: TokenTag,
    ) Token {
        self.advance();
        if (self.index < self.source.len and self.source[self.index] == second) {
            self.advance();
            return self.token(double_tag, start, position);
        }
        return self.token(single_tag, start, position);
    }

    fn requiredDoubleToken(
        self: *Lexer,
        start: usize,
        position: Source.Position,
        second: u8,
        tag: TokenTag,
        message: []const u8,
    ) Source.Error!Token {
        self.advance();
        if (self.index == self.source.len or self.source[self.index] != second) {
            return self.fail(position, message);
        }
        self.advance();
        return self.token(tag, start, position);
    }

    fn arithmeticToken(
        self: *Lexer,
        start: usize,
        position: Source.Position,
        repeated: u8,
        single_tag: TokenTag,
        repeated_tag: TokenTag,
        assignment_tag: TokenTag,
    ) Token {
        self.advance();
        if (self.index < self.source.len) {
            if (repeated != 0 and self.source[self.index] == repeated) {
                self.advance();
                return self.token(repeated_tag, start, position);
            }
            if (self.source[self.index] == '=') {
                self.advance();
                return self.token(assignment_tag, start, position);
            }
        }
        return self.token(single_tag, start, position);
    }

    fn skipIgnored(self: *Lexer) void {
        while (self.index < self.source.len) {
            switch (self.source[self.index]) {
                ' ', '\t', '\r' => self.advance(),
                '\n' => self.newline(),
                '/' => {
                    if (self.index + 1 >= self.source.len or self.source[self.index + 1] != '/') return;
                    while (self.index < self.source.len and self.source[self.index] != '\n') self.advance();
                },
                else => return,
            }
        }
    }

    fn advance(self: *Lexer) void {
        self.index += 1;
        self.column += 1;
    }

    fn newline(self: *Lexer) void {
        self.index += 1;
        self.line += 1;
        self.column = 1;
    }

    fn currentPosition(self: *const Lexer) Source.Position {
        return .{ .line = self.line, .column = self.column, .file = self.file };
    }

    fn token(self: *const Lexer, tag: TokenTag, start: usize, position: Source.Position) Token {
        return .{ .tag = tag, .lexeme = self.source[start..self.index], .position = position };
    }

    fn fail(self: *Lexer, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn keywordTag(lexeme: []const u8) ?TokenTag {
    const keywords = .{
        .{ "void", TokenTag.keyword_void },
        .{ "let", TokenTag.keyword_let },
        .{ "var", TokenTag.keyword_var },
        .{ "if", TokenTag.keyword_if },
        .{ "else", TokenTag.keyword_else },
        .{ "while", TokenTag.keyword_while },
        .{ "for", TokenTag.keyword_for },
        .{ "in", TokenTag.keyword_in },
        .{ "break", TokenTag.keyword_break },
        .{ "continue", TokenTag.keyword_continue },
        .{ "return", TokenTag.keyword_return },
        .{ "struct", TokenTag.keyword_struct },
        .{ "func", TokenTag.keyword_func },
        .{ "self", TokenTag.keyword_self },
        .{ "true", TokenTag.keyword_true },
        .{ "false", TokenTag.keyword_false },
        .{ "int", TokenTag.keyword_int },
        .{ "int8", TokenTag.keyword_int8 },
        .{ "int16", TokenTag.keyword_int16 },
        .{ "int32", TokenTag.keyword_int32 },
        .{ "int64", TokenTag.keyword_int64 },
        .{ "uint", TokenTag.keyword_uint },
        .{ "uint8", TokenTag.keyword_uint8 },
        .{ "uint16", TokenTag.keyword_uint16 },
        .{ "uint32", TokenTag.keyword_uint32 },
        .{ "uint64", TokenTag.keyword_uint64 },
        .{ "float", TokenTag.keyword_float },
        .{ "float32", TokenTag.keyword_float32 },
        .{ "float64", TokenTag.keyword_float64 },
        .{ "bool", TokenTag.keyword_bool },
        .{ "str", TokenTag.keyword_str },
        .{ "print", TokenTag.keyword_print },
        .{ "import", TokenTag.keyword_import },
        .{ "use", TokenTag.keyword_use },
        .{ "pub", TokenTag.keyword_pub },
        .{ "as", TokenTag.keyword_as },
    };
    inline for (keywords) |keyword| {
        if (std.mem.eql(u8, lexeme, keyword[0])) return keyword[1];
    }
    return null;
}

fn isIdentifierStart(character: u8) bool {
    return std.ascii.isAlphabetic(character) or character == '_';
}

fn isIdentifierContinue(character: u8) bool {
    return isIdentifierStart(character) or std.ascii.isDigit(character);
}

fn digitValue(character: u8) ?u8 {
    if (std.ascii.isDigit(character)) return character - '0';
    if (character >= 'a' and character <= 'f') return character - 'a' + 10;
    if (character >= 'A' and character <= 'F') return character - 'A' + 10;
    return null;
}

fn isUnicodeScalar(value: u21) bool {
    return value <= 0x10FFFF and (value < 0xD800 or value > 0xDFFF);
}

test "recognize declaration keywords" {
    var lexer = Lexer.init("let value:bool = true;");
    try std.testing.expectEqual(TokenTag.keyword_let, (try lexer.next()).tag);
    try std.testing.expectEqual(TokenTag.identifier, (try lexer.next()).tag);
    try std.testing.expectEqual(TokenTag.colon, (try lexer.next()).tag);
    try std.testing.expectEqual(TokenTag.keyword_bool, (try lexer.next()).tag);
    try std.testing.expectEqual(TokenTag.equal, (try lexer.next()).tag);
    try std.testing.expectEqual(TokenTag.keyword_true, (try lexer.next()).tag);
}

test "skip line comments" {
    var lexer = Lexer.init("// comment\n42");
    const token = try lexer.next();
    try std.testing.expectEqual(TokenTag.integer, token.tag);
    try std.testing.expectEqual(@as(usize, 2), token.position.line);
}

test "recognize comparison and logical operators" {
    var lexer = Lexer.init("!= == < <= > >= ! && ||");
    const expected = [_]TokenTag{
        .bang_equal,
        .equal_equal,
        .less,
        .less_equal,
        .greater,
        .greater_equal,
        .bang,
        .amp_amp,
        .pipe_pipe,
    };
    for (expected) |tag| try std.testing.expectEqual(tag, (try lexer.next()).tag);
}

test "recognize compound and update operators" {
    var lexer = Lexer.init("++ -- += -= *= /=");
    const expected = [_]TokenTag{
        .plus_plus,
        .minus_minus,
        .plus_equal,
        .minus_equal,
        .star_equal,
        .slash_equal,
    };
    for (expected) |tag| try std.testing.expectEqual(tag, (try lexer.next()).tag);
}

test "recognize numeric bases separators and exponents" {
    var lexer = Lexer.init("0b1010_0101 0o7_55 0xCA_FE 1_000_000 1.25e-3");
    const expected = [_]TokenTag{ .integer, .integer, .integer, .integer, .floating };
    for (expected) |tag| try std.testing.expectEqual(tag, (try lexer.next()).tag);
}

test "reject invalid numeric separator" {
    var lexer = Lexer.init("1__0");
    try std.testing.expectError(error.InvalidSource, lexer.next());
    try std.testing.expectEqualStrings("numeric separator must appear between digits", lexer.diagnostic.?.message);
}

test "recognize string escapes" {
    var lexer = Lexer.init("\"line\\n\\u{00E9}\"");
    const token = try lexer.next();
    try std.testing.expectEqual(TokenTag.string, token.tag);
    try std.testing.expectEqualStrings("line\\n\\u{00E9}", token.lexeme);
}

test "reject invalid string escape" {
    var lexer = Lexer.init("\"\\q\"");
    try std.testing.expectError(error.InvalidSource, lexer.next());
    try std.testing.expectEqualStrings("invalid escape sequence in string literal", lexer.diagnostic.?.message);
}
