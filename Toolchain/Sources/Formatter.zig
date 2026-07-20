const std = @import("std");
const LexerModule = @import("Lexer.zig");
const ParserModule = @import("Parser.zig");
const ProjectModule = @import("Project.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Token = LexerModule.Token;
const TokenTag = LexerModule.TokenTag;

pub const FormatError = error{InvalidSource} || Allocator.Error;

pub const Result = struct {
    text: []const u8,
    diagnostic: ?Source.Diagnostic = null,
};

const Piece = struct {
    token: Token,
    leading: []const u8,
};

/// Formats one complete Silex source unit. The returned slice belongs to
/// `allocator`. A diagnostic message allocated for an invalid source belongs
/// to it as well. Syntax is validated before any formatted text is returned.
pub fn formatSource(allocator: Allocator, source: []const u8) FormatError!Result {
    if (!std.unicode.utf8ValidateSlice(source)) {
        return .{ .text = &.{}, .diagnostic = .{ .position = .{ .line = 1, .column = 1 }, .message = "source is not valid UTF-8" } };
    }

    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();

    var parser = ParserModule.Parser.init(scratch_allocator, source);
    _ = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return invalidResult(allocator, parser.diagnostic orelse parser.lexer.diagnostic.?),
        error.OutOfMemory => return error.OutOfMemory,
    };

    var lexer = LexerModule.Lexer.init(source);
    var pieces: std.ArrayList(Piece) = .empty;
    var previous_end: usize = 0;
    while (true) {
        const token = lexer.next() catch |err| switch (err) {
            error.InvalidSource => return invalidResult(allocator, lexer.diagnostic.?),
        };
        if (token.tag == .end) break;
        try pieces.append(scratch_allocator, .{ .token = token, .leading = source[previous_end..token.start] });
        previous_end = token.end;
    }

    var formatter = Formatter{
        .allocator = allocator,
        .source = source,
        .pieces = pieces.items,
    };
    return .{ .text = try formatter.render() };
}

fn invalidResult(allocator: Allocator, diagnostic: Source.Diagnostic) Allocator.Error!Result {
    return .{ .text = &.{}, .diagnostic = .{
        .position = diagnostic.position,
        .message = try allocator.dupe(u8, diagnostic.message),
    } };
}

pub const CommandResult = struct {
    changed_paths: []const []const u8,
    had_differences: bool,
};

const Unit = struct {
    path: []const u8,
    original: []const u8,
    formatted: []const u8,
};

/// Loads and formats every explicitly declared unit before writing any of
/// them. This preserves the all-or-nothing validation guarantee for projects.
pub fn formatPath(allocator: Allocator, io: Io, input_path: []const u8, check: bool) !CommandResult {
    const project = try ProjectModule.load(allocator, io, input_path);
    var units: std.ArrayList(Unit) = .empty;
    for (project.modules) |module| for (module.sources) |path| {
        const original = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
            std.debug.print("silex: unable to read source '{s}': {t}\n", .{ path, err });
            return error.Reported;
        };
        const result = try formatSource(allocator, original);
        if (result.diagnostic) |diagnostic| {
            std.debug.print("{s}:{d}:{d}: error: {s}\n", .{ path, diagnostic.position.line, diagnostic.position.column, diagnostic.message });
            return error.Reported;
        }
        try units.append(allocator, .{ .path = path, .original = original, .formatted = result.text });
    };

    var changed: std.ArrayList([]const u8) = .empty;
    for (units.items) |unit| {
        if (std.mem.eql(u8, unit.original, unit.formatted)) continue;
        try changed.append(allocator, unit.path);
        if (!check) try replaceAtomically(allocator, io, unit.path, unit.formatted);
    }
    const had_differences = changed.items.len != 0;
    return .{ .changed_paths = try changed.toOwnedSlice(allocator), .had_differences = had_differences };
}

fn replaceAtomically(allocator: Allocator, io: Io, path: []const u8, contents: []const u8) !void {
    const directory_path = std.fs.path.dirname(path) orelse ".";
    const basename = std.fs.path.basename(path);
    const temporary_name = try std.fmt.allocPrint(allocator, ".{s}.silex-format-{x}.tmp", .{ basename, std.hash.Wyhash.hash(0, contents) });
    const temporary_path = try std.fs.path.join(allocator, &.{ directory_path, temporary_name });
    const source = try Io.Dir.cwd().openFile(io, path, .{});
    defer source.close(io);
    const metadata = try source.stat(io);
    var temporary = try Io.Dir.cwd().createFile(io, temporary_path, .{ .permissions = metadata.permissions });
    var temporary_open = true;
    defer if (temporary_open) temporary.close(io);
    errdefer Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
    try temporary.writeStreamingAll(io, contents);
    try temporary.sync(io);
    temporary.close(io);
    temporary_open = false;
    try Io.Dir.cwd().rename(temporary_path, .cwd(), path, io);
}

const Formatter = struct {
    allocator: Allocator,
    source: []const u8,
    pieces: []const Piece,
    output: std.ArrayList(u8) = .empty,
    indent: usize = 0,
    line_start: bool = true,
    line_length: usize = 0,
    brace_depth: usize = 0,
    delimiter_depth: usize = 0,
    prior_tag: ?TokenTag = null,
    previous_generic_open: bool = false,
    continuation_levels: usize = 0,

    fn render(self: *Formatter) ![]const u8 {
        var index: usize = 0;
        var previous: ?TokenTag = null;
        while (index < self.pieces.len) : (index += 1) {
            const piece = self.pieces[index];
            const token = piece.token;
            const next = if (index + 1 < self.pieces.len) self.pieces[index + 1].token.tag else .end;

            try self.emitTrivia(piece.leading, previous != null);
            if (self.delimiter_depth > 0 and containsNewline(piece.leading)) {
                if (isDelimiterClosing(token.tag)) {
                    self.continuation_levels = 0;
                    try self.newline(false);
                } else if (previous == .comma or (previous != null and isOpening(previous.?)) or isOperator(previous orelse .end)) {
                    self.continuation_levels = if (isOperator(previous orelse .end)) 2 else 1;
                    try self.newline(false);
                }
            }

            if (token.tag == .semicolon) {
                try self.newline(false);
                previous = token.tag;
                continue;
            }
            if (token.tag == .left_parenthesis and self.shouldOmitParentheses(index)) {
                if (isControlKeyword(previous)) try self.space();
                continue;
            }
            if (token.tag == .right_parenthesis and self.omittedParenthesisOpen(index) != null) {
                continue;
            }
            if (token.tag == .keyword_void and previous == .right_parenthesis and isReturnBoundary(next)) {
                previous = token.tag;
                continue;
            }
            if (token.tag == .keyword_else and next == .keyword_if and !hasComment(self.pieces[index + 1].leading)) {
                try self.emitWord("elif", previous, next);
                index += 1;
                previous = .keyword_elif;
                continue;
            }

            switch (token.tag) {
                .left_brace => {
                    if (self.needsSpace(previous, token.tag)) try self.space();
                    try self.write("{");
                    self.brace_depth += 1;
                    if (next == .right_brace) {
                        // Empty blocks stay compact.
                    } else {
                        self.indent += 1;
                        try self.newline(false);
                    }
                },
                .right_brace => {
                    if (previous != .left_brace) {
                        if (self.indent > 0) self.indent -= 1;
                        try self.newline(false);
                    }
                    try self.write("}");
                    self.brace_depth -|= 1;
                    if (next == .keyword_else or next == .keyword_elif) {
                        try self.space();
                    } else if (!isClosing(next) and next != .left_parenthesis and next != .left_bracket and next != .comma and next != .semicolon and next != .end) {
                        try self.newline(self.brace_depth == 0);
                    }
                },
                .left_parenthesis, .left_bracket => {
                    if (self.needsSpace(previous, token.tag)) try self.space();
                    try self.write(rawToken(self.source, token));
                    self.delimiter_depth += 1;
                },
                .right_parenthesis, .right_bracket => {
                    try self.write(rawToken(self.source, token));
                    self.delimiter_depth -|= 1;
                    if (self.delimiter_depth == 0) self.continuation_levels = 0;
                },
                .comma => {
                    try self.write(",");
                    if (!isClosing(next)) try self.space();
                },
                .colon => try self.write(":"),
                .dot, .question_dot, .dot_dot, .dot_dot_dot, .question, .plus_plus, .minus_minus => try self.write(rawToken(self.source, token)),
                .less, .greater, .shift_right => if (self.isGenericAngle(index))
                    try self.write(rawToken(self.source, token))
                else
                    try self.emitWord(rawToken(self.source, token), previous, next),
                else => try self.emitWord(rawToken(self.source, token), previous, next),
            }

            if (next != .end and token.position.line < self.pieces[index + 1].token.position.line and
                (self.delimiter_depth == 0 or self.brace_depth > 0) and
                canEndLine(token.tag, next, self.isGenericAngle(index)) and
                !startsWithTrailingComment(self.pieces[index + 1].leading) and
                !(next == .right_parenthesis and self.omittedParenthesisOpen(index + 1) != null))
            {
                self.continuation_levels = 0;
                try self.newline(blankLineCount(self.source[token.end..self.pieces[index + 1].token.start]) > 0);
            }
            self.previous_generic_open = token.tag == .less and self.isGenericAngle(index);
            self.prior_tag = previous;
            previous = token.tag;
        }
        try self.emitTrivia(self.source[if (self.pieces.len == 0) 0 else self.pieces[self.pieces.len - 1].token.end..], self.pieces.len != 0);
        while (self.output.items.len > 0 and (self.output.items[self.output.items.len - 1] == ' ' or self.output.items[self.output.items.len - 1] == '\n')) {
            _ = self.output.pop();
        }
        try self.output.append(self.allocator, '\n');
        const unwrapped = try self.output.toOwnedSlice(self.allocator);
        defer self.allocator.free(unwrapped);
        return wrapLongLines(self.allocator, unwrapped);
    }

    fn emitWord(self: *Formatter, text: []const u8, previous: ?TokenTag, next: TokenTag) !void {
        _ = next;
        if (self.needsSpace(previous, null) and !self.previous_generic_open and !isPrefixUse(previous, self.prior_tag)) try self.space();
        try self.write(text);
    }

    fn needsSpace(self: *const Formatter, previous: ?TokenTag, current: ?TokenTag) bool {
        _ = self;
        const tag = previous orelse return false;
        if (isOpening(tag) or tag == .dot or tag == .question_dot or tag == .dot_dot or tag == .dot_dot_dot or tag == .colon or tag == .at) return false;
        if (current) |value| {
            if (value == .left_parenthesis) return !attachesParenthesis(tag);
            if (value == .left_bracket and (tag == .equal or tag == .keyword_in or tag == .keyword_return)) return true;
            if (isClosing(value) or value == .comma or value == .colon or value == .dot or value == .question_dot or value == .dot_dot or value == .dot_dot_dot or value == .left_bracket or value == .question) return false;
        }
        return true;
    }

    fn emitTrivia(self: *Formatter, trivia: []const u8, has_previous: bool) !void {
        var cursor: usize = 0;
        var saw_comment = false;
        while (std.mem.indexOfPos(u8, trivia, cursor, "//")) |start| {
            const end = std.mem.indexOfScalarPos(u8, trivia, start, '\n') orelse trivia.len;
            const prefix = trivia[cursor..start];
            const trailing = has_previous and !containsNewline(prefix) and !self.line_start;
            if (trailing) {
                try self.space();
            } else if (self.output.items.len != 0) {
                try self.newline(blankLineCount(prefix) > 0);
            }
            const comment_end = if (end > start and trivia[end - 1] == '\r') end - 1 else end;
            try self.write(trivia[start..comment_end]);
            try self.newline(false);
            saw_comment = true;
            cursor = end;
        }
        if (saw_comment and blankLineCount(trivia[cursor..]) > 0) try self.newline(true);
    }

    fn write(self: *Formatter, text: []const u8) !void {
        if (self.line_start) {
            const actual_indent = self.indent + self.continuation_levels;
            try self.output.appendNTimes(self.allocator, ' ', actual_indent * 4);
            self.line_length = actual_indent * 4;
            self.line_start = false;
        }
        try self.output.appendSlice(self.allocator, text);
        self.line_length += text.len;
    }

    fn space(self: *Formatter) !void {
        if (self.line_start or self.output.items.len == 0) return;
        const last = self.output.items[self.output.items.len - 1];
        if (last != ' ' and last != '\n') {
            try self.output.append(self.allocator, ' ');
            self.line_length += 1;
        }
    }

    fn newline(self: *Formatter, blank: bool) !void {
        while (self.output.items.len > 0 and self.output.items[self.output.items.len - 1] == ' ') _ = self.output.pop();
        if (self.output.items.len == 0 or self.output.items[self.output.items.len - 1] != '\n') try self.output.append(self.allocator, '\n');
        if (blank and self.output.items.len >= 1 and (self.output.items.len < 2 or self.output.items[self.output.items.len - 2] != '\n')) try self.output.append(self.allocator, '\n');
        self.line_start = true;
        self.line_length = 0;
    }

    fn matchingClose(self: *const Formatter, open_index: usize) ?usize {
        var depth: usize = 0;
        for (self.pieces[open_index..], open_index..) |piece, index| switch (piece.token.tag) {
            .left_parenthesis => depth += 1,
            .right_parenthesis => {
                depth -= 1;
                if (depth == 0) return index;
            },
            else => {},
        };
        return null;
    }

    fn omittedParenthesisOpen(self: *const Formatter, close_index: usize) ?usize {
        var depth: usize = 0;
        var index = close_index;
        while (index > 0) {
            index -= 1;
            switch (self.pieces[index].token.tag) {
                .right_parenthesis => depth += 1,
                .left_parenthesis => {
                    if (depth == 0) return if (self.shouldOmitParentheses(index)) index else null;
                    depth -= 1;
                },
                else => {},
            }
        }
        return null;
    }

    fn shouldOmitParentheses(self: *const Formatter, open_index: usize) bool {
        const close_index = self.matchingClose(open_index) orelse return false;
        if (triviaContainsComment(self.pieces[open_index + 1 .. close_index + 1])) return false;
        const before = if (open_index == 0) null else self.pieces[open_index - 1].token.tag;
        if (isControlKeyword(before)) return true;
        if (!isRedundantExpressionBoundaryBefore(before)) return false;
        const after = if (close_index + 1 == self.pieces.len) .end else self.pieces[close_index + 1].token.tag;
        return isRedundantExpressionBoundaryAfter(after);
    }

    fn isGenericAngle(self: *const Formatter, index: usize) bool {
        const tag = self.pieces[index].token.tag;
        if (tag == .less) return self.genericClose(index) != null;
        if (tag != .greater and tag != .shift_right) return false;
        var cursor = index;
        while (cursor > 0) {
            cursor -= 1;
            if (self.pieces[cursor].token.tag == .less and self.genericClose(cursor) == index) return true;
        }
        return false;
    }

    fn genericClose(self: *const Formatter, open_index: usize) ?usize {
        if (open_index == 0 or self.pieces[open_index].token.tag != .less) return null;
        const before = self.pieces[open_index - 1].token.tag;
        if (before != .identifier and before != .greater and before != .shift_right) return null;
        var depth: usize = 1;
        var index = open_index + 1;
        while (index < self.pieces.len) : (index += 1) {
            const tag = self.pieces[index].token.tag;
            if (!isTypeListToken(tag)) return null;
            switch (tag) {
                .less => depth += 1,
                .greater => {
                    depth -= 1;
                    if (depth == 0) return if (genericSuffix(self.pieces, index)) index else null;
                },
                .shift_right => {
                    if (depth <= 2) return if (genericSuffix(self.pieces, index)) index else null;
                    depth -= 2;
                },
                else => {},
            }
        }
        return null;
    }
};

fn rawToken(source: []const u8, token: Token) []const u8 {
    return source[token.start..token.end];
}

fn isControlKeyword(tag: ?TokenTag) bool {
    const value = tag orelse return false;
    return value == .keyword_if or value == .keyword_elif or value == .keyword_while or value == .keyword_for;
}

fn isReturnBoundary(tag: TokenTag) bool {
    return tag == .left_brace or tag == .semicolon or tag == .right_brace or tag == .end;
}

fn isRedundantExpressionBoundaryBefore(tag: ?TokenTag) bool {
    const value = tag orelse return true;
    return switch (value) {
        .equal, .comma, .left_parenthesis, .left_bracket, .fat_arrow, .keyword_return, .keyword_try, .keyword_move => true,
        else => false,
    };
}

fn isRedundantExpressionBoundaryAfter(tag: TokenTag) bool {
    return switch (tag) {
        .semicolon, .comma, .right_parenthesis, .right_bracket, .right_brace, .end, .left_brace => true,
        else => false,
    };
}

fn isOpening(tag: TokenTag) bool {
    return tag == .left_parenthesis or tag == .left_bracket;
}

fn attachesParenthesis(tag: TokenTag) bool {
    return switch (tag) {
        .identifier, .greater, .shift_right, .right_parenthesis, .right_bracket, .keyword_func, .keyword_print, .keyword_assert, .keyword_panic, .keyword_range, .keyword_init, .keyword_super => true,
        else => false,
    };
}

fn isClosing(tag: TokenTag) bool {
    return tag == .right_parenthesis or tag == .right_bracket or tag == .right_brace;
}

fn isDelimiterClosing(tag: TokenTag) bool {
    return tag == .right_parenthesis or tag == .right_bracket;
}

fn canEndLine(tag: TokenTag, next: TokenTag, generic_angle: bool) bool {
    if (tag == .comma or tag == .colon or tag == .left_brace or
        (isOperator(tag) and !generic_angle and tag != .plus_plus and tag != .minus_minus)) return false;
    if (next == .right_brace or next == .left_brace or isOperator(next) or next == .dot or next == .question_dot or next == .dot_dot or next == .dot_dot_dot) return false;
    return true;
}

fn isTypeListToken(tag: TokenTag) bool {
    return switch (tag) {
        .identifier, .keyword_void, .keyword_int, .keyword_int8, .keyword_int16, .keyword_int32, .keyword_int64, .keyword_uint, .keyword_uint8, .keyword_uint16, .keyword_uint32, .keyword_uint64, .keyword_float, .keyword_float32, .keyword_float64, .keyword_bool, .keyword_str, .keyword_func, .comma, .colon, .dot, .less, .greater, .shift_right, .left_parenthesis, .right_parenthesis, .left_bracket, .right_bracket, .question, .amp, .at => true,
        else => false,
    };
}

fn genericSuffix(pieces: []const Piece, close_index: usize) bool {
    if (close_index + 1 == pieces.len) return true;
    return switch (pieces[close_index + 1].token.tag) {
        .left_parenthesis, .left_brace, .left_bracket, .right_parenthesis, .right_bracket, .question, .dot, .question_dot, .comma, .colon, .semicolon, .equal, .identifier, .keyword_as, .keyword_in, .right_brace, .greater, .shift_right => true,
        else => pieces[close_index].token.position.line < pieces[close_index + 1].token.position.line,
    };
}

fn isOperator(tag: TokenTag) bool {
    return switch (tag) {
        .plus, .plus_plus, .plus_equal, .minus, .minus_minus, .minus_equal, .star, .star_equal, .slash, .slash_equal, .percent, .bang, .equal, .equal_equal, .fat_arrow, .bang_equal, .less, .less_equal, .shift_left, .greater, .greater_equal, .shift_right, .amp_amp, .amp, .caret, .pipe_pipe => true,
        else => false,
    };
}

fn isPrefixUse(tag: ?TokenTag, prior: ?TokenTag) bool {
    const value = tag orelse return false;
    if (value == .bang or value == .at) return true;
    if (value != .minus and value != .star and value != .amp) return false;
    const before = prior orelse return true;
    return isOpening(before) or isOperator(before) or before == .comma or before == .colon or
        before == .equal or before == .keyword_return or before == .keyword_in;
}

fn hasComment(trivia: []const u8) bool {
    return std.mem.indexOf(u8, trivia, "//") != null;
}

fn startsWithTrailingComment(trivia: []const u8) bool {
    const comment = std.mem.indexOf(u8, trivia, "//") orelse return false;
    const newline = std.mem.indexOfAny(u8, trivia, "\r\n") orelse return true;
    return comment < newline;
}

fn triviaContainsComment(pieces: []const Piece) bool {
    for (pieces) |piece| if (hasComment(piece.leading)) return true;
    return false;
}

fn containsNewline(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, "\r\n") != null;
}

fn blankLineCount(text: []const u8) usize {
    var lines: usize = 0;
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] == '\n') lines += 1;
    }
    return if (lines >= 2) 1 else 0;
}

const ListBreak = struct {
    open: usize,
    close: usize,
};

fn wrapLongLines(allocator: Allocator, source: []const u8) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    var start: usize = 0;
    while (start < source.len) {
        const end = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
        try wrapLine(allocator, &output, source[start..end]);
        start = if (end < source.len) end + 1 else source.len;
    }
    if (output.items.len == 0 or output.items[output.items.len - 1] != '\n') try output.append(allocator, '\n');
    return output.toOwnedSlice(allocator);
}

fn wrapLine(allocator: Allocator, output: *std.ArrayList(u8), line: []const u8) !void {
    if (line.len <= 100 or hasComment(line)) {
        try output.appendSlice(allocator, line);
        try output.append(allocator, '\n');
        return;
    }
    if (findBreakableList(line)) |list| {
        const base_indent = leadingSpaces(line);
        try output.appendSlice(allocator, std.mem.trimEnd(u8, line[0 .. list.open + 1], " "));
        try output.append(allocator, '\n');

        var segment_start = list.open + 1;
        var index = segment_start;
        var round_depth: usize = 0;
        var square_depth: usize = 0;
        var in_string = false;
        var escaped = false;
        while (index <= list.close) : (index += 1) {
            const at_close = index == list.close;
            const character = if (at_close) 0 else line[index];
            if (!at_close) {
                if (in_string) {
                    if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == '"') in_string = false;
                    continue;
                }
                if (character == '"') {
                    in_string = true;
                    continue;
                }
                switch (character) {
                    '(' => round_depth += 1,
                    ')' => round_depth -|= 1,
                    '[' => square_depth += 1,
                    ']' => square_depth -|= 1,
                    else => {},
                }
            }
            if (!at_close and (character != ',' or round_depth != 0 or square_depth != 0)) continue;
            const segment_end = if (at_close) index else index + 1;
            const item = std.mem.trim(u8, line[segment_start..segment_end], " ");
            if (item.len != 0) {
                var indented: std.ArrayList(u8) = .empty;
                defer indented.deinit(allocator);
                try indented.appendNTimes(allocator, ' ', base_indent + 4);
                try indented.appendSlice(allocator, item);
                try wrapLine(allocator, output, indented.items);
            }
            segment_start = index + 1;
        }

        var closing: std.ArrayList(u8) = .empty;
        defer closing.deinit(allocator);
        try closing.appendNTimes(allocator, ' ', base_indent);
        try closing.appendSlice(allocator, std.mem.trimStart(u8, line[list.close..], " "));
        try wrapLine(allocator, output, closing.items);
        return;
    }
    if (binaryBreak(line)) |break_at| {
        try output.appendSlice(allocator, std.mem.trimEnd(u8, line[0..break_at], " "));
        try output.append(allocator, '\n');
        var continuation: std.ArrayList(u8) = .empty;
        defer continuation.deinit(allocator);
        try continuation.appendNTimes(allocator, ' ', leadingSpaces(line) + 4);
        try continuation.appendSlice(allocator, std.mem.trimStart(u8, line[break_at..], " "));
        try wrapLine(allocator, output, continuation.items);
        return;
    }
    try output.appendSlice(allocator, line);
    try output.append(allocator, '\n');
}

fn findBreakableList(line: []const u8) ?ListBreak {
    var open_index: usize = 0;
    while (open_index < line.len) : (open_index += 1) {
        const opener = line[open_index];
        if (opener != '(' and opener != '[') continue;
        const closer: u8 = if (opener == '(') ')' else ']';
        var depth: usize = 1;
        var index = open_index + 1;
        var has_comma = false;
        var in_string = false;
        var escaped = false;
        while (index < line.len) : (index += 1) {
            const character = line[index];
            if (in_string) {
                if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == '"') in_string = false;
                continue;
            }
            if (character == '"') {
                in_string = true;
                continue;
            }
            if (character == opener) depth += 1;
            if (character == closer) {
                depth -= 1;
                if (depth == 0) {
                    if (has_comma) return .{ .open = open_index, .close = index };
                    break;
                }
            }
            if (character == ',' and depth == 1) has_comma = true;
        }
    }
    return null;
}

fn binaryBreak(line: []const u8) ?usize {
    const operators = [_][]const u8{
        " || ", " && ", " == ", " != ", " <= ", " >= ", " << ", " >> ",
        " + ",  " - ",  " * ",  " / ",  " % ",  " & ",  " ^ ",  " = ",
    };
    var best: ?usize = null;
    for (operators) |operator| {
        var start: usize = 0;
        while (std.mem.indexOfPos(u8, line, start, operator)) |position| {
            const after = position + operator.len - 1;
            if (!insideString(line, position) and after <= 100 and (best == null or after > best.?)) best = after;
            start = position + operator.len;
        }
    }
    return best;
}

fn insideString(line: []const u8, position: usize) bool {
    var in_string = false;
    var escaped = false;
    for (line[0..position]) |character| {
        if (!in_string) {
            if (character == '"') in_string = true;
            continue;
        }
        if (escaped) {
            escaped = false;
        } else if (character == '\\') {
            escaped = true;
        } else if (character == '"') {
            in_string = false;
        }
    }
    return in_string;
}

fn leadingSpaces(line: []const u8) usize {
    for (line, 0..) |character, index| if (character != ' ') return index;
    return line.len;
}

test "canonical source is stable and preserves comments and literal spelling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "// head\r\nfunc main() void { let value : int=0xCA_FE; print(\"x\\n\") // tail\r\n}\r\n";
    const first = try formatSource(allocator, source);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expectEqualStrings(
        "// head\nfunc main() {\n    let value:int = 0xCA_FE\n    print(\"x\\n\") // tail\n}\n",
        first.text,
    );
    const second = try formatSource(allocator, first.text);
    try std.testing.expectEqualStrings(first.text, second.text);
}

test "control parentheses and else if use their canonical forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try formatSource(arena.allocator(), "func main() { if (true) {} else if false {} }");
    try std.testing.expectEqualStrings("func main() {\n    if true {} elif false {}\n}\n", result.text);
}

test "a comment between else and if prevents elif rewriting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const first = try formatSource(allocator, "func main() { if false {} else // between\n if true {} }");
    try std.testing.expectEqualStrings(
        "func main() {\n    if false {} else // between\n    if true {}\n}\n",
        first.text,
    );
    const second = try formatSource(allocator, first.text);
    try std.testing.expectEqualStrings(first.text, second.text);
}

test "redundant expression parentheses are removed without changing precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const result = try formatSource(
        allocator,
        "func main() { let sum = (1 + 2); let product = (1 + 2) * 3; print((sum)); return }",
    );
    try std.testing.expectEqualStrings(
        "func main() {\n    let sum = 1 + 2\n    let product = (1 + 2) * 3\n    print(sum)\n    return\n}\n",
        result.text,
    );
}

test "long delimited lists and binary expressions wrap idempotently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        "func main() { assert(first_value == 1 && second_value == 2 && third_value == 3 && fourth_value == 4 && fifth_value == 5, \"values\") }";
    const first = try formatSource(allocator, source);
    try std.testing.expect(first.diagnostic == null);
    var lines = std.mem.splitScalar(u8, first.text, '\n');
    while (lines.next()) |line| try std.testing.expect(line.len <= 100);
    const second = try formatSource(allocator, first.text);
    try std.testing.expectEqualStrings(first.text, second.text);
}

test "an indivisible long string is never split at operator-like text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        "func main() { print(\"This indivisible literal contains + and = spellings but remains one exact string even past one hundred columns.\") }";
    const first = try formatSource(allocator, source);
    try std.testing.expect(std.mem.indexOf(u8, first.text, "contains + and = spellings") != null);
    const second = try formatSource(allocator, first.text);
    try std.testing.expectEqualStrings(first.text, second.text);
}

test "generic use aliases keep canonical angle spacing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try formatSource(arena.allocator(), "use Result < int, str > as IntResult");
    try std.testing.expectEqualStrings("use Result<int, str> as IntResult\n", result.text);
}

test "project validation precedes every write and check preserves files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "First.sx", .data = "func first() void {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Second.sx", .data = "func second() void {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "project.json",
        .data = "{\"target\":\"App\",\"modules\":[{\"name\":\"App\",\"sources\":[\"First.sx\",\"Second.sx\"]}]}\n",
    });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const absolute_root = try std.fs.path.resolve(allocator, &.{relative_root});
    const manifest_path = try std.fs.path.join(allocator, &.{ absolute_root, "project.json" });

    const checked = try formatPath(allocator, std.testing.io, manifest_path, true);
    try std.testing.expect(checked.had_differences);
    try std.testing.expectEqual(@as(usize, 2), checked.changed_paths.len);
    const unchanged = try temporary.dir.readFileAlloc(std.testing.io, "First.sx", allocator, .limited(1024));
    try std.testing.expectEqualStrings("func first() void {}\n", unchanged);

    const written = try formatPath(allocator, std.testing.io, manifest_path, false);
    try std.testing.expect(written.had_differences);
    const canonical = try temporary.dir.readFileAlloc(std.testing.io, "First.sx", allocator, .limited(1024));
    try std.testing.expectEqualStrings("func first() {}\n", canonical);
    const clean_check = try formatPath(allocator, std.testing.io, manifest_path, true);
    try std.testing.expect(!clean_check.had_differences);

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "First.sx", .data = "func first() void {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Second.sx", .data = "func second( {\n" });
    try std.testing.expectError(error.Reported, formatPath(allocator, std.testing.io, manifest_path, false));
    const still_unchanged = try temporary.dir.readFileAlloc(std.testing.io, "First.sx", allocator, .limited(1024));
    try std.testing.expectEqualStrings("func first() void {}\n", still_unchanged);
}
