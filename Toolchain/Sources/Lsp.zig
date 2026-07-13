const std = @import("std");
const LexerModule = @import("Lexer.zig");
const ParserModule = @import("Parser.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const protocol_version = "2.0";
const max_message_size = 16 * 1024 * 1024;

const Document = struct {
    uri: []const u8,
    text: []const u8,
};

const CompletionItem = struct {
    label: []const u8,
    kind: u8,
    detail: []const u8,
    insertText: ?[]const u8 = null,
    filterText: ?[]const u8 = null,
};

const QualifiedCompletionContext = struct {
    qualifier: []const u8,
    prefix: []const u8,
    type_only: bool,
};

const DeclaredMember = struct {
    structure: []const u8,
    name: []const u8,
    type_name: ?[]const u8,
    kind: u8,
    detail: []const u8,
};

const DeclaredVariable = struct {
    name: []const u8,
    type_name: []const u8,
    offset: usize,
};

const StructureRange = struct {
    name: []const u8,
    start: usize,
    end: usize,
};

const SemanticInfo = struct {
    members: std.ArrayList(DeclaredMember) = .empty,
    variables: std.ArrayList(DeclaredVariable) = .empty,
    structures: std.ArrayList(StructureRange) = .empty,

    fn deinit(self: *SemanticInfo, allocator: Allocator) void {
        self.members.deinit(allocator);
        self.variables.deinit(allocator);
        self.structures.deinit(allocator);
    }
};

const Position = struct {
    line: usize,
    character: usize,
};

const Range = struct {
    start: Position,
    end: Position,
};

const Diagnostic = struct {
    range: Range,
    severity: u8 = 1,
    source: []const u8 = "silex",
    message: []const u8,
};

const Request = struct {
    jsonrpc: []const u8,
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,
};

const Server = struct {
    allocator: Allocator,
    io: Io,
    documents: std.ArrayList(Document) = .empty,

    fn init(allocator: Allocator, io: Io) Server {
        return .{ .allocator = allocator, .io = io };
    }

    fn run(self: *Server) !void {
        var input_buffer: [32 * 1024]u8 = undefined;
        var reader = Io.File.stdin().readerStreaming(self.io, &input_buffer);
        while (try readMessage(self.allocator, &reader.interface)) |body| {
            const request = std.json.parseFromSliceLeaky(Request, self.allocator, body, .{
                .ignore_unknown_fields = true,
            }) catch continue;
            if (!std.mem.eql(u8, request.jsonrpc, protocol_version)) continue;
            try self.handle(request);
        }
    }

    fn handle(self: *Server, request: Request) !void {
        if (std.mem.eql(u8, request.method, "initialize")) {
            if (request.id) |id| try self.reply(id, .{
                .capabilities = .{
                    .textDocumentSync = 1,
                    .completionProvider = .{
                        .triggerCharacters = &.{"."},
                    },
                },
                .serverInfo = .{
                    .name = "Silex",
                    .version = "0.9.0",
                },
            });
            return;
        }

        if (std.mem.eql(u8, request.method, "shutdown")) {
            if (request.id) |id| try self.reply(id, @as(?std.json.Value, null));
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didOpen")) {
            if (request.params) |params| {
                if (documentFromOpen(params)) |document| {
                    try self.setDocument(document.uri, document.text);
                    try self.publishDiagnostics(document.uri, document.text);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didChange")) {
            if (request.params) |params| {
                if (documentFromChange(params)) |document| {
                    try self.setDocument(document.uri, document.text);
                    try self.publishDiagnostics(document.uri, document.text);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didClose")) {
            if (request.params) |params| {
                if (textDocumentUri(params)) |uri| {
                    self.removeDocument(uri);
                    try self.sendNotification("textDocument/publishDiagnostics", .{
                        .uri = uri,
                        .diagnostics = &[_]Diagnostic{},
                    });
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/completion")) {
            const items = if (request.params) |params| completion: {
                const uri = textDocumentUri(params) orelse break :completion &[_]CompletionItem{};
                const source = self.documentText(uri) orelse break :completion &[_]CompletionItem{};
                const position = completionPosition(params);
                if (position) |cursor| {
                    if (importCompletionPrefix(source, cursor)) |prefix| {
                        break :completion try localModuleCompletionItems(
                            self.allocator,
                            self.io,
                            uri,
                            prefix,
                        );
                    }
                    if (qualifiedCompletionContext(source, cursor)) |context| {
                        if (importedModulePath(source, context.qualifier)) |module_path| {
                            break :completion try moduleExportCompletionItems(
                                self.allocator,
                                self.io,
                                uri,
                                module_path,
                                context,
                            );
                        }
                    }
                }
                break :completion try completionItems(self.allocator, source, position);
            } else &[_]CompletionItem{};
            if (request.id) |id| try self.reply(id, .{
                .isIncomplete = false,
                .items = items,
            });
        }
    }

    fn reply(self: *Server, id: std.json.Value, result: anytype) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .result = result,
        });
    }

    fn sendNotification(self: *Server, method: []const u8, params: anytype) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .method = method,
            .params = params,
        });
    }

    fn send(self: *Server, message: anytype) !void {
        const body = try std.json.Stringify.valueAlloc(self.allocator, message, .{
            .emit_null_optional_fields = false,
        });
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
        try Io.File.stdout().writeStreamingAll(self.io, header);
        try Io.File.stdout().writeStreamingAll(self.io, body);
    }

    fn setDocument(self: *Server, uri: []const u8, text: []const u8) !void {
        for (self.documents.items) |*document| {
            if (std.mem.eql(u8, document.uri, uri)) {
                document.text = try self.allocator.dupe(u8, text);
                return;
            }
        }
        try self.documents.append(self.allocator, .{
            .uri = try self.allocator.dupe(u8, uri),
            .text = try self.allocator.dupe(u8, text),
        });
    }

    fn removeDocument(self: *Server, uri: []const u8) void {
        for (self.documents.items, 0..) |document, index| {
            if (std.mem.eql(u8, document.uri, uri)) {
                _ = self.documents.orderedRemove(index);
                return;
            }
        }
    }

    fn documentText(self: *const Server, uri: []const u8) ?[]const u8 {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.uri, uri)) return document.text;
        }
        return null;
    }

    fn publishDiagnostics(self: *Server, uri: []const u8, source: []const u8) !void {
        const diagnostic = syntaxDiagnostic(self.allocator, source);
        if (diagnostic) |value| {
            try self.sendNotification("textDocument/publishDiagnostics", .{
                .uri = uri,
                .diagnostics = &.{value},
            });
        } else {
            try self.sendNotification("textDocument/publishDiagnostics", .{
                .uri = uri,
                .diagnostics = &[_]Diagnostic{},
            });
        }
    }
};

pub fn run(allocator: Allocator, io: Io) !u8 {
    var server = Server.init(allocator, io);
    try server.run();
    return 0;
}

fn readMessage(allocator: Allocator, reader: *Io.Reader) !?[]const u8 {
    var content_length: ?usize = null;
    while (true) {
        const line = try reader.takeDelimiter('\n') orelse return null;
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        if (trimmed.len == 0) break;
        const separator = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const name = std.mem.trim(u8, trimmed[0..separator], " \t");
        const value = std.mem.trim(u8, trimmed[separator + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            content_length = std.fmt.parseInt(usize, value, 10) catch return error.InvalidRequest;
        }
    }
    const length = content_length orelse return error.InvalidRequest;
    if (length > max_message_size) return error.MessageTooLarge;
    return try reader.readAlloc(allocator, length);
}

fn documentFromOpen(params: std.json.Value) ?Document {
    const text_document = objectMember(params, "textDocument") orelse return null;
    return .{
        .uri = stringMember(text_document, "uri") orelse return null,
        .text = stringMember(text_document, "text") orelse return null,
    };
}

fn documentFromChange(params: std.json.Value) ?Document {
    const uri = textDocumentUri(params) orelse return null;
    const changes = objectMember(params, "contentChanges") orelse return null;
    if (changes != .array or changes.array.items.len == 0) return null;
    return .{
        .uri = uri,
        .text = stringMember(changes.array.items[changes.array.items.len - 1], "text") orelse return null,
    };
}

fn textDocumentUri(params: std.json.Value) ?[]const u8 {
    const text_document = objectMember(params, "textDocument") orelse return null;
    return stringMember(text_document, "uri");
}

fn completionPosition(params: std.json.Value) ?Position {
    const position = objectMember(params, "position") orelse return null;
    return .{
        .line = unsignedMember(position, "line") orelse return null,
        .character = unsignedMember(position, "character") orelse return null,
    };
}

fn objectMember(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn stringMember(value: std.json.Value, name: []const u8) ?[]const u8 {
    const member = objectMember(value, name) orelse return null;
    return switch (member) {
        .string => |string| string,
        else => null,
    };
}

fn unsignedMember(value: std.json.Value, name: []const u8) ?usize {
    const member = objectMember(value, name) orelse return null;
    if (member != .integer or member.integer < 0) return null;
    return std.math.cast(usize, member.integer);
}

fn syntaxDiagnostic(allocator: Allocator, source: []const u8) ?Diagnostic {
    var parser = ParserModule.Parser.init(allocator, source);
    _ = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return diagnosticFromSource(parser.diagnostic.?),
        else => return null,
    };
    return null;
}

fn diagnosticFromSource(diagnostic: Source.Diagnostic) Diagnostic {
    const line = diagnostic.position.line -| 1;
    const character = diagnostic.position.column -| 1;
    return .{
        .range = .{
            .start = .{ .line = line, .character = character },
            .end = .{ .line = line, .character = character + 1 },
        },
        .message = diagnostic.message,
    };
}

fn completionItems(
    allocator: Allocator,
    source: []const u8,
    position: ?Position,
) ![]const CompletionItem {
    if (position) |cursor| {
        if (try memberCompletionItems(allocator, source, cursor)) |items| return items;
    }

    var items: std.ArrayList(CompletionItem) = .empty;
    for (language_completions) |item| try items.append(allocator, item);

    var lexer = LexerModule.Lexer.init(source);
    while (true) {
        const token = lexer.next() catch break;
        if (token.tag == .end) break;
        if (token.tag == .identifier and !containsCompletion(items.items, token.lexeme)) {
            try items.append(allocator, .{
                .label = token.lexeme,
                .kind = 6,
                .detail = "Identifier in this document",
            });
        }
    }
    return items.toOwnedSlice(allocator);
}

fn importCompletionPrefix(source: []const u8, position: Position) ?[]const u8 {
    const cursor_offset = byteOffsetAtPosition(source, position) orelse return null;
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..cursor_offset], '\n')) |newline|
        newline + 1
    else
        0;
    const line = std.mem.trimStart(u8, source[line_start..cursor_offset], " \t");
    if (!std.mem.startsWith(u8, line, "import") or line.len == "import".len) return null;
    if (!std.ascii.isWhitespace(line["import".len])) return null;

    const prefix = std.mem.trimStart(u8, line["import".len..], " \t");
    for (prefix) |character| {
        if (std.ascii.isWhitespace(character)) return null;
        if (!isIdentifierContinue(character) and character != '.') return null;
    }
    return prefix;
}

fn qualifiedCompletionContext(source: []const u8, position: Position) ?QualifiedCompletionContext {
    const cursor_offset = byteOffsetAtPosition(source, position) orelse return null;
    var prefix_start = cursor_offset;
    while (prefix_start > 0 and isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return null;

    var qualifier_start = prefix_start - 1;
    while (qualifier_start > 0 and
        (isIdentifierContinue(source[qualifier_start - 1]) or source[qualifier_start - 1] == '.'))
    {
        qualifier_start -= 1;
    }
    const qualifier = source[qualifier_start .. prefix_start - 1];
    if (qualifier.len == 0) return null;

    var previous = qualifier_start;
    while (previous > 0 and std.ascii.isWhitespace(source[previous - 1])) previous -= 1;
    return .{
        .qualifier = qualifier,
        .prefix = source[prefix_start..cursor_offset],
        .type_only = previous > 0 and source[previous - 1] == ':',
    };
}

fn importedModulePath(source: []const u8, qualifier: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |source_line| {
        const line = std.mem.trim(u8, source_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "import") or line.len == "import".len or
            !std.ascii.isWhitespace(line["import".len]))
        {
            continue;
        }

        const declaration = std.mem.trimStart(u8, line["import".len..], " \t");
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const module_path = declaration[0..module_end];
        if (module_path.len == 0) continue;

        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const visible_qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else
            module_path;
        if (std.mem.eql(u8, visible_qualifier, qualifier)) return module_path;
    }
    return null;
}

fn moduleExportCompletionItems(
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    module_path: []const u8,
    context: QualifiedCompletionContext,
) ![]const CompletionItem {
    const source_path = try filePathFromUri(allocator, uri) orelse
        return try allocator.alloc(CompletionItem, 0);
    const project_root = std.fs.path.dirname(source_path) orelse
        return try allocator.alloc(CompletionItem, 0);
    const module_directory = try moduleDirectoryPath(allocator, project_root, module_path);

    var directory = Io.Dir.cwd().openDir(io, module_directory, .{ .iterate = true }) catch
        return try allocator.alloc(CompletionItem, 0);
    defer directory.close(io);

    var source_names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) {
            try source_names.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    var items: std.ArrayList(CompletionItem) = .empty;
    for (source_names.items) |source_name| {
        const module_source_path = try std.fs.path.join(allocator, &.{ module_directory, source_name });
        const module_source = Io.Dir.cwd().readFileAlloc(
            io,
            module_source_path,
            allocator,
            .limited(max_message_size),
        ) catch continue;
        var parser = ParserModule.Parser.init(allocator, module_source);
        const program = parser.parse() catch continue;

        for (program.structures) |structure| {
            if (!structure.is_public or !std.mem.startsWith(u8, structure.name, context.prefix)) continue;
            try appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                structure.name,
                22,
                "Silex public structure",
            );
        }
        if (!context.type_only) {
            for (program.functions) |function| {
                if (!function.is_public or !std.mem.startsWith(u8, function.name, context.prefix)) continue;
                try appendModuleExportCompletion(
                    allocator,
                    &items,
                    context.qualifier,
                    function.name,
                    3,
                    "Silex public function",
                );
            }
        }
    }

    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return try items.toOwnedSlice(allocator);
}

fn appendModuleExportCompletion(
    allocator: Allocator,
    items: *std.ArrayList(CompletionItem),
    qualifier: []const u8,
    name: []const u8,
    kind: u8,
    detail: []const u8,
) !void {
    const label = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ qualifier, name });
    if (containsCompletion(items.items, label)) return;
    try items.append(allocator, .{
        .label = label,
        .kind = kind,
        .detail = detail,
        .insertText = name,
        .filterText = name,
    });
}

fn moduleDirectoryPath(allocator: Allocator, root: []const u8, module_path: []const u8) ![]const u8 {
    const relative_path = try allocator.dupe(u8, module_path);
    for (relative_path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return std.fs.path.join(allocator, &.{ root, relative_path });
}

fn localModuleCompletionItems(
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    prefix: []const u8,
) ![]const CompletionItem {
    const source_path = try filePathFromUri(allocator, uri) orelse
        return try allocator.alloc(CompletionItem, 0);
    const project_root = std.fs.path.dirname(source_path) orelse
        return try allocator.alloc(CompletionItem, 0);

    var items: std.ArrayList(CompletionItem) = .empty;
    try collectLocalModules(allocator, io, project_root, "", prefix, &items);
    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return try items.toOwnedSlice(allocator);
}

fn collectLocalModules(
    allocator: Allocator,
    io: Io,
    directory_path: []const u8,
    module_name: []const u8,
    prefix: []const u8,
    items: *std.ArrayList(CompletionItem),
) !void {
    var directory = Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch return;
    defer directory.close(io);

    var has_direct_source = false;
    var child_directories: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) {
            has_direct_source = true;
        } else if (entry.kind == .directory and entry.name.len > 0 and entry.name[0] != '.') {
            try child_directories.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    if (module_name.len > 0 and has_direct_source and std.mem.startsWith(u8, module_name, prefix)) {
        try items.append(allocator, .{
            .label = module_name,
            .kind = 9,
            .detail = "Silex local module",
        });
    }

    for (child_directories.items) |child_name| {
        const child_path = try std.fs.path.join(allocator, &.{ directory_path, child_name });
        const child_module = if (module_name.len == 0)
            child_name
        else
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, child_name });
        try collectLocalModules(allocator, io, child_path, child_module, prefix, items);
    }
}

fn filePathFromUri(allocator: Allocator, uri: []const u8) !?[]const u8 {
    const scheme = "file://";
    if (!std.mem.startsWith(u8, uri, scheme)) return null;
    const encoded = uri[scheme.len..];
    var path: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] == '%' and index + 2 < encoded.len) {
            const high = hexDigit(encoded[index + 1]) orelse return null;
            const low = hexDigit(encoded[index + 2]) orelse return null;
            try path.append(allocator, high * 16 + low);
            index += 3;
        } else {
            try path.append(allocator, encoded[index]);
            index += 1;
        }
    }
    return try path.toOwnedSlice(allocator);
}

fn hexDigit(character: u8) ?u8 {
    return switch (character) {
        '0'...'9' => character - '0',
        'a'...'f' => character - 'a' + 10,
        'A'...'F' => character - 'A' + 10,
        else => null,
    };
}

fn memberCompletionItems(
    allocator: Allocator,
    source: []const u8,
    position: Position,
) !?[]const CompletionItem {
    const cursor_offset = byteOffsetAtPosition(source, position) orelse return null;
    const receiver_path = try memberReceiverPath(allocator, source, cursor_offset) orelse return null;
    defer allocator.free(receiver_path);

    var tokens: std.ArrayList(LexerModule.Token) = .empty;
    defer tokens.deinit(allocator);
    var lexer = LexerModule.Lexer.init(source);
    while (true) {
        const token = lexer.next() catch break;
        if (token.tag == .end) break;
        try tokens.append(allocator, token);
    }

    var info: SemanticInfo = .{};
    defer info.deinit(allocator);
    try collectSemanticInfo(allocator, source, tokens.items, &info);

    var structure_name = receiverType(info, receiver_path[0], cursor_offset) orelse
        return try allocator.alloc(CompletionItem, 0);
    for (receiver_path[1..]) |field_name| {
        structure_name = fieldType(info.members.items, structure_name, field_name) orelse
            return try allocator.alloc(CompletionItem, 0);
    }

    var items: std.ArrayList(CompletionItem) = .empty;
    for (info.members.items) |member| {
        if (!std.mem.eql(u8, member.structure, structure_name)) continue;
        try items.append(allocator, .{
            .label = member.name,
            .kind = member.kind,
            .detail = member.detail,
        });
    }
    return try items.toOwnedSlice(allocator);
}

fn collectSemanticInfo(
    allocator: Allocator,
    source: []const u8,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    var index: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if (tokens[index].tag == .keyword_struct and index + 2 < tokens.len and
            tokens[index + 1].tag == .identifier and tokens[index + 2].tag == .left_brace)
        {
            const structure_name = tokens[index + 1].lexeme;
            var depth: usize = 0;
            var parentheses: usize = 0;
            var member_index = index + 2;
            while (member_index < tokens.len) : (member_index += 1) {
                const token = tokens[member_index];
                switch (token.tag) {
                    .left_brace => depth += 1,
                    .right_brace => {
                        if (depth == 0) break;
                        depth -= 1;
                        if (depth == 0) {
                            try info.structures.append(allocator, .{
                                .name = structure_name,
                                .start = tokenOffset(source, tokens[index]),
                                .end = tokenOffset(source, token) + token.lexeme.len,
                            });
                            break;
                        }
                    },
                    .left_parenthesis => if (depth == 1) {
                        parentheses += 1;
                    },
                    .right_parenthesis => if (depth == 1 and parentheses > 0) {
                        parentheses -= 1;
                    },
                    else => {},
                }

                if (depth != 1 or parentheses != 0) continue;
                if (token.tag == .keyword_func and member_index + 1 < tokens.len and
                    tokens[member_index + 1].tag == .identifier)
                {
                    try info.members.append(allocator, .{
                        .structure = structure_name,
                        .name = tokens[member_index + 1].lexeme,
                        .type_name = null,
                        .kind = 2,
                        .detail = "Silex method",
                    });
                } else if (token.tag == .identifier and member_index + 2 < tokens.len and
                    tokens[member_index + 1].tag == .colon and isTypeToken(tokens[member_index + 2].tag))
                {
                    try info.members.append(allocator, .{
                        .structure = structure_name,
                        .name = token.lexeme,
                        .type_name = tokens[member_index + 2].lexeme,
                        .kind = 5,
                        .detail = "Silex field",
                    });
                }
            }
        }

        if ((tokens[index].tag == .keyword_let or tokens[index].tag == .keyword_var) and
            index + 3 < tokens.len and tokens[index + 1].tag == .identifier)
        {
            if (tokens[index + 2].tag == .colon and isTypeToken(tokens[index + 3].tag)) {
                try info.variables.append(allocator, .{
                    .name = tokens[index + 1].lexeme,
                    .type_name = tokens[index + 3].lexeme,
                    .offset = tokenOffset(source, tokens[index + 1]),
                });
            } else if (tokens[index + 2].tag == .equal and tokens[index + 3].tag == .identifier and
                index + 4 < tokens.len and tokens[index + 4].tag == .left_brace)
            {
                try info.variables.append(allocator, .{
                    .name = tokens[index + 1].lexeme,
                    .type_name = tokens[index + 3].lexeme,
                    .offset = tokenOffset(source, tokens[index + 1]),
                });
            }
        }

        if (tokens[index].tag == .keyword_func) {
            try collectParameters(allocator, source, tokens, index, &info.variables);
        }
    }
}

fn collectParameters(
    allocator: Allocator,
    source: []const u8,
    tokens: []const LexerModule.Token,
    function_index: usize,
    variables: *std.ArrayList(DeclaredVariable),
) !void {
    var index = function_index + 1;
    while (index < tokens.len and tokens[index].tag != .left_parenthesis) : (index += 1) {}
    if (index == tokens.len) return;
    index += 1;
    while (index + 2 < tokens.len and tokens[index].tag != .right_parenthesis) : (index += 1) {
        if (tokens[index].tag == .identifier and tokens[index + 1].tag == .colon and
            isTypeToken(tokens[index + 2].tag))
        {
            try variables.append(allocator, .{
                .name = tokens[index].lexeme,
                .type_name = tokens[index + 2].lexeme,
                .offset = tokenOffset(source, tokens[index]),
            });
        }
    }
}

fn memberReceiverPath(
    allocator: Allocator,
    source: []const u8,
    cursor_offset: usize,
) !?[][]const u8 {
    var prefix_start = cursor_offset;
    while (prefix_start > 0 and isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return null;

    var path_start = prefix_start - 1;
    while (path_start > 0 and
        (isIdentifierContinue(source[path_start - 1]) or source[path_start - 1] == '.'))
    {
        path_start -= 1;
    }
    const path_source = source[path_start .. prefix_start - 1];
    if (path_source.len == 0) return null;

    var path: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, path_source, '.');
    while (iterator.next()) |segment| {
        if (segment.len == 0) {
            path.deinit(allocator);
            return null;
        }
        try path.append(allocator, segment);
    }
    return try path.toOwnedSlice(allocator);
}

fn receiverType(info: SemanticInfo, receiver: []const u8, cursor_offset: usize) ?[]const u8 {
    if (std.mem.eql(u8, receiver, "self")) {
        for (info.structures.items) |structure| {
            if (structure.start <= cursor_offset and cursor_offset <= structure.end) return structure.name;
        }
        return null;
    }

    var result: ?[]const u8 = null;
    var result_offset: usize = 0;
    for (info.variables.items) |variable| {
        if (variable.offset <= cursor_offset and variable.offset >= result_offset and
            std.mem.eql(u8, variable.name, receiver))
        {
            result = variable.type_name;
            result_offset = variable.offset;
        }
    }
    return result;
}

fn fieldType(members: []const DeclaredMember, structure: []const u8, field: []const u8) ?[]const u8 {
    for (members) |member| {
        if (std.mem.eql(u8, member.structure, structure) and std.mem.eql(u8, member.name, field)) {
            return member.type_name;
        }
    }
    return null;
}

fn byteOffsetAtPosition(source: []const u8, position: Position) ?usize {
    var offset: usize = 0;
    var line: usize = 0;
    while (line < position.line) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return null;
        offset = newline + 1;
    }

    var utf16_units: usize = 0;
    while (offset < source.len and source[offset] != '\n' and utf16_units < position.character) {
        const sequence_length = utf8SequenceLength(source[offset]);
        utf16_units += if (sequence_length == 4) 2 else 1;
        offset += @min(sequence_length, source.len - offset);
    }
    return if (utf16_units == position.character) offset else null;
}

fn utf8SequenceLength(first_byte: u8) usize {
    if (first_byte & 0x80 == 0) return 1;
    if (first_byte & 0xe0 == 0xc0) return 2;
    if (first_byte & 0xf0 == 0xe0) return 3;
    if (first_byte & 0xf8 == 0xf0) return 4;
    return 1;
}

fn tokenOffset(source: []const u8, token: LexerModule.Token) usize {
    return @intFromPtr(token.lexeme.ptr) - @intFromPtr(source.ptr);
}

fn isIdentifierContinue(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

fn isTypeToken(tag: LexerModule.TokenTag) bool {
    return switch (tag) {
        .identifier,
        .keyword_int,
        .keyword_int8,
        .keyword_int16,
        .keyword_int32,
        .keyword_int64,
        .keyword_uint,
        .keyword_uint8,
        .keyword_uint16,
        .keyword_uint32,
        .keyword_uint64,
        .keyword_float,
        .keyword_float32,
        .keyword_float64,
        .keyword_bool,
        .keyword_str,
        => true,
        else => false,
    };
}

fn containsCompletion(items: []const CompletionItem, label: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.label, label)) return true;
    return false;
}

const language_completions = [_]CompletionItem{
    .{ .label = "func", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "struct", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "let", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "var", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "if", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "else", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "while", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "return", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "import", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "use", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "pub", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "as", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "self", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "true", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "false", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "print", .kind = 3, .detail = "Silex builtin" },
    .{ .label = "void", .kind = 7, .detail = "Silex type" },
    .{ .label = "bool", .kind = 7, .detail = "Silex type" },
    .{ .label = "int", .kind = 7, .detail = "Silex type" },
    .{ .label = "int8", .kind = 7, .detail = "Silex type" },
    .{ .label = "int16", .kind = 7, .detail = "Silex type" },
    .{ .label = "int32", .kind = 7, .detail = "Silex type" },
    .{ .label = "int64", .kind = 7, .detail = "Silex type" },
    .{ .label = "uint", .kind = 7, .detail = "Silex type" },
    .{ .label = "uint8", .kind = 7, .detail = "Silex type" },
    .{ .label = "uint16", .kind = 7, .detail = "Silex type" },
    .{ .label = "uint32", .kind = 7, .detail = "Silex type" },
    .{ .label = "uint64", .kind = 7, .detail = "Silex type" },
    .{ .label = "float", .kind = 7, .detail = "Silex type" },
    .{ .label = "float32", .kind = 7, .detail = "Silex type" },
    .{ .label = "float64", .kind = 7, .detail = "Silex type" },
    .{ .label = "str", .kind = 7, .detail = "Silex type" },
};

test "completion items include language terms and document identifiers" {
    const items = try completionItems(std.testing.allocator, "func main() void { let total = 1 }", null);
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "func"));
    try std.testing.expect(containsCompletion(items, "total"));
}

test "import completion recognizes only the module path context" {
    try std.testing.expectEqualStrings(
        "M",
        importCompletionPrefix("import M", .{ .line = 0, .character = 8 }).?,
    );
    try std.testing.expectEqualStrings(
        "",
        importCompletionPrefix("    import ", .{ .line = 0, .character = 11 }).?,
    );
    try std.testing.expect(importCompletionPrefix(
        "import Math as M",
        .{ .line = 0, .character = 16 },
    ) == null);
}

test "qualified completion resolves an imported module and its typed prefix" {
    const source =
        \\import Math
        \\var pos:Math.V
    ;
    const context = qualifiedCompletionContext(source, .{ .line = 1, .character = 14 }).?;
    try std.testing.expectEqualStrings("Math", context.qualifier);
    try std.testing.expectEqualStrings("V", context.prefix);
    try std.testing.expect(context.type_only);
    try std.testing.expectEqualStrings("Math", importedModulePath(source, context.qualifier).?);

    const aliased_source = "import Math as Algebra\nvar pos:Algebra.V";
    const aliased = qualifiedCompletionContext(aliased_source, .{ .line = 1, .character = 17 }).?;
    try std.testing.expectEqualStrings("Algebra", aliased.qualifier);
    try std.testing.expectEqualStrings("Math", importedModulePath(aliased_source, aliased.qualifier).?);
}

test "file URIs are decoded for local module discovery" {
    const path = (try filePathFromUri(std.testing.allocator, "file:///tmp/Silex%20Project/Main.sx")).?;
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/tmp/Silex Project/Main.sx", path);
}

test "member completion only includes members of the receiver structure" {
    const source =
        \\struct Move {
        \\    speed:float = 100
        \\}
        \\func main() void {
        \\    var move:Move
        \\    print(move.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, source, .{ .line = 5, .character = 15 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("speed", items[0].label);
    try std.testing.expectEqual(@as(u8, 5), items[0].kind);
}

test "syntax diagnostics use zero-based LSP positions" {
    const diagnostic = syntaxDiagnostic(std.testing.allocator, "func main() void {\n    let value =\n}").?;
    try std.testing.expectEqual(@as(usize, 2), diagnostic.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), diagnostic.range.start.character);
}
