const std = @import("std");
const build_options = @import("build_options");
const Ast = @import("Ast.zig");
const LexerModule = @import("Lexer.zig");
const ParserModule = @import("Parser.zig");
const Source = @import("Source.zig");
const StandardLibrary = @import("StandardLibrary.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const protocol_version = "2.0";
const max_message_size = 16 * 1024 * 1024;
const completion_trigger_characters = [_][]const u8{"."};

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

const SignatureInformation = struct {
    label: []const u8,
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
    collection: ?CollectionKind = null,
    kind: u8,
    detail: []const u8,
};

const DeclaredVariable = struct {
    name: []const u8,
    type_name: []const u8,
    collection: ?CollectionKind = null,
    offset: usize,
};

const CollectionKind = enum {
    list,
    fixed_array,
};

const ReceiverType = union(enum) {
    structure: []const u8,
    list,
    fixed_array,
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

const StandardFunctionLookup = struct {
    name: []const u8,
    result: ?[]const u8 = null,
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
                        .triggerCharacters = &completion_trigger_characters,
                    },
                    .signatureHelpProvider = .{
                        .triggerCharacters = &.{ "(", "," },
                    },
                },
                .serverInfo = .{
                    .name = "Silex",
                    .version = build_options.silex_version,
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
                        if (try importedModulePath(self.allocator, source, context.qualifier)) |module_path| {
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
                const project_root = try documentProjectRoot(self.allocator, uri);
                break :completion try completionItemsForProject(
                    self.allocator,
                    self.io,
                    source,
                    project_root,
                    position,
                );
            } else &[_]CompletionItem{};
            if (request.id) |id| try self.reply(id, .{
                .isIncomplete = false,
                .items = items,
            });
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/signatureHelp")) {
            const signatures = if (request.params) |params| signatures: {
                const uri = textDocumentUri(params) orelse break :signatures &[_]SignatureInformation{};
                const source = self.documentText(uri) orelse break :signatures &[_]SignatureInformation{};
                const position = completionPosition(params) orelse break :signatures &[_]SignatureInformation{};
                break :signatures try signatureHelpItems(self.allocator, source, position);
            } else &[_]SignatureInformation{};
            if (request.id) |id| try self.reply(id, .{
                .signatures = signatures,
                .activeSignature = @as(usize, 0),
                .activeParameter = @as(usize, 0),
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

fn signatureHelpItems(
    allocator: Allocator,
    source: []const u8,
    position: Position,
) ![]const SignatureInformation {
    const cursor = byteOffsetAtPosition(source, position) orelse return allocator.alloc(SignatureInformation, 0);
    const name = signatureNameAt(source, cursor) orelse return allocator.alloc(SignatureInformation, 0);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var parser = ParserModule.Parser.init(arena.allocator(), source);
    const program = parser.parse() catch return allocator.alloc(SignatureInformation, 0);
    var result: std.ArrayList(SignatureInformation) = .empty;
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) try appendSignatureHelp(allocator, &result, function);
    }
    for (program.structures) |structure| for (structure.methods) |method| {
        if (std.mem.eql(u8, method.name, name)) try appendSignatureHelp(allocator, &result, method);
    };
    return result.toOwnedSlice(allocator);
}

fn signatureNameAt(source: []const u8, cursor: usize) ?[]const u8 {
    var index = @min(cursor, source.len);
    while (index > 0 and source[index - 1] != '(') index -= 1;
    if (index == 0) return null;
    index -= 1;
    while (index > 0 and std.ascii.isWhitespace(source[index - 1])) index -= 1;
    const end = index;
    while (index > 0 and isIdentifierContinue(source[index - 1])) index -= 1;
    return if (index == end) null else source[index..end];
}

fn appendSignatureHelp(
    allocator: Allocator,
    signatures: *std.ArrayList(SignatureInformation),
    function: Ast.Function,
) !void {
    var label: std.ArrayList(u8) = .empty;
    try label.appendSlice(allocator, function.name);
    try label.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try label.appendSlice(allocator, ", ");
        if (parameter.is_mutable_reference) try label.append(allocator, '&');
        try appendAstTypeName(allocator, &label, parameter.type);
    }
    try label.append(allocator, ')');
    const value = label.items;
    for (signatures.items) |existing| if (std.mem.eql(u8, existing.label, value)) return;
    try signatures.append(allocator, .{ .label = try label.toOwnedSlice(allocator) });
}

fn appendAstTypeName(allocator: Allocator, output: *std.ArrayList(u8), type_name: Ast.TypeName) !void {
    switch (type_name) {
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
        .list => |element| {
            try appendAstTypeName(allocator, output, element.*);
            try output.appendSlice(allocator, "[]");
        },
        .fixed_array => |array| {
            try appendAstTypeName(allocator, output, array.element.*);
            try output.append(allocator, '[');
            try output.appendSlice(allocator, array.length);
            try output.append(allocator, ']');
        },
        .reference => |reference| {
            try output.append(allocator, if (reference.mutable) '&' else '@');
            try appendAstTypeName(allocator, output, reference.target.*);
        },
        .function => |function| {
            try output.appendSlice(allocator, "func(");
            for (function.parameters, function.parameter_is_mutable_references, 0..) |parameter, is_mutable_reference, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (is_mutable_reference) try output.append(allocator, '&');
                try appendAstTypeName(allocator, output, parameter);
            }
            try output.append(allocator, ')');
            if (function.return_type) |return_type| {
                try output.append(allocator, ' ');
                try appendAstTypeName(allocator, output, return_type.*);
            }
        },
        .optional => |contained| {
            try appendAstTypeName(allocator, output, contained.*);
            try output.append(allocator, '?');
        },
    }
}

fn completionItems(
    allocator: Allocator,
    io: Io,
    source: []const u8,
    position: ?Position,
) ![]const CompletionItem {
    return completionItemsForProject(allocator, io, source, null, position);
}

fn completionItemsForProject(
    allocator: Allocator,
    io: Io,
    source: []const u8,
    project_root: ?[]const u8,
    position: ?Position,
) ![]const CompletionItem {
    if (position) |cursor| {
        if (try memberCompletionItems(allocator, io, source, project_root, cursor)) |items| return items;
        if (isIncompleteCascadePrefix(source, cursor)) return try allocator.alloc(CompletionItem, 0);
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

fn isIncompleteCascadePrefix(source: []const u8, position: Position) bool {
    const cursor_offset = byteOffsetAtPosition(source, position) orelse return false;
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..cursor_offset], '\n')) |newline|
        newline + 1
    else
        0;
    return std.mem.eql(u8, std.mem.trim(u8, source[line_start..cursor_offset], " \t\r"), ".");
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

const VisibleModule = struct {
    qualifier: []const u8,
    module_path: []const u8,
};

fn importedModulePath(allocator: Allocator, source: []const u8, qualifier: []const u8) !?[]const u8 {
    var modules: std.ArrayList(VisibleModule) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |source_line| {
        const line = std.mem.trim(u8, source_line, " \t\r");
        const kind: enum { import_value, use_value } = if (directiveBody(line, "import") != null)
            .import_value
        else if (directiveBody(line, "use") != null)
            .use_value
        else
            continue;

        const declaration = directiveBody(line, if (kind == .import_value) "import" else "use").?;
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const path = declaration[0..module_end];
        if (path.len == 0) continue;

        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const visible_qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else if (kind == .use_value)
            lastPathSegment(path)
        else
            path;
        const module_path = try expandVisibleModulePath(allocator, modules.items, path) orelse path;
        try modules.append(allocator, .{ .qualifier = visible_qualifier, .module_path = module_path });
    }
    return expandVisibleModulePath(allocator, modules.items, qualifier);
}

fn directiveBody(line: []const u8, keyword: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, keyword) or line.len == keyword.len or
        !std.ascii.isWhitespace(line[keyword.len])) return null;
    return std.mem.trimStart(u8, line[keyword.len..], " \t");
}

fn expandVisibleModulePath(
    allocator: Allocator,
    modules: []const VisibleModule,
    path: []const u8,
) !?[]const u8 {
    var matched: ?VisibleModule = null;
    for (modules) |module| {
        if (!std.mem.eql(u8, path, module.qualifier) and !pathHasModuleQualifier(path, module.qualifier)) continue;
        if (matched == null or module.qualifier.len > matched.?.qualifier.len) matched = module;
    }
    const module = matched orelse return null;
    if (std.mem.eql(u8, path, module.qualifier)) return module.module_path;
    const expanded: []const u8 = try std.fmt.allocPrint(allocator, "{s}.{s}", .{
        module.module_path,
        path[module.qualifier.len + 1 ..],
    });
    return expanded;
}

fn pathHasModuleQualifier(path: []const u8, qualifier: []const u8) bool {
    return path.len > qualifier.len and std.mem.startsWith(u8, path, qualifier) and
        path[qualifier.len] == '.';
}

fn lastPathSegment(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[separator + 1 ..];
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
    const module_root = try moduleCompletionRoot(allocator, io, project_root, module_path) orelse
        return try allocator.alloc(CompletionItem, 0);
    const module_directory = try moduleDirectoryPath(allocator, module_root, module_path);

    var directory = Io.Dir.cwd().openDir(io, module_directory, .{ .iterate = true }) catch
        return try allocator.alloc(CompletionItem, 0);
    defer directory.close(io);

    var items: std.ArrayList(CompletionItem) = .empty;
    var source_names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) {
            try source_names.append(allocator, try allocator.dupe(u8, entry.name));
        } else if (entry.kind == .directory and entry.name.len > 0 and entry.name[0] != '.' and
            std.mem.startsWith(u8, entry.name, context.prefix))
        {
            try appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                entry.name,
                9,
                "Silex submodule",
            );
        }
    }

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

fn moduleCompletionRoot(
    allocator: Allocator,
    io: Io,
    project_root: []const u8,
    module_path: []const u8,
) !?[]const u8 {
    const library_root = StandardLibrary.root(allocator, io) catch {
        return if (StandardLibrary.isReservedModule(module_path)) null else project_root;
    };
    if (StandardLibrary.isReservedModule(module_path)) return library_root;

    const local_directory = try moduleDirectoryPath(allocator, project_root, module_path);
    if (try lspDirectoryExists(io, local_directory)) return project_root;
    const distributed_directory = try moduleDirectoryPath(allocator, library_root, module_path);
    if (try lspDirectoryExists(io, distributed_directory)) return library_root;
    return project_root;
}

fn lspDirectoryExists(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
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
    try collectModules(allocator, io, project_root, "", prefix, "Silex local module", &items);
    if (StandardLibrary.root(allocator, io) catch null) |standard_library_root| {
        try collectModules(allocator, io, standard_library_root, "", prefix, "Silex standard module", &items);
    }
    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return try items.toOwnedSlice(allocator);
}

fn collectModules(
    allocator: Allocator,
    io: Io,
    directory_path: []const u8,
    module_name: []const u8,
    prefix: []const u8,
    detail: []const u8,
    items: *std.ArrayList(CompletionItem),
) !void {
    var directory = Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch return;
    defer directory.close(io);

    var child_directories: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind == .directory and entry.name.len > 0 and entry.name[0] != '.') {
            try child_directories.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    if (module_name.len > 0 and std.mem.startsWith(u8, module_name, prefix)) {
        try items.append(allocator, .{
            .label = module_name,
            .kind = 9,
            .detail = detail,
        });
    }

    for (child_directories.items) |child_name| {
        const child_path = try std.fs.path.join(allocator, &.{ directory_path, child_name });
        const child_module = if (module_name.len == 0)
            child_name
        else
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, child_name });
        try collectModules(allocator, io, child_path, child_module, prefix, detail, items);
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

fn documentProjectRoot(allocator: Allocator, uri: []const u8) !?[]const u8 {
    const source_path = try filePathFromUri(allocator, uri) orelse return null;
    return std.fs.path.dirname(source_path);
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
    io: Io,
    source: []const u8,
    project_root: ?[]const u8,
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
    try collectSemanticInfo(allocator, io, source, project_root, tokens.items, &info);

    var receiver_type = receiverType(info, receiver_path[0], cursor_offset) orelse
        return try allocator.alloc(CompletionItem, 0);
    for (receiver_path[1..]) |field_name| {
        const structure_name = switch (receiver_type) {
            .structure => |name| name,
            .list, .fixed_array => return try allocator.alloc(CompletionItem, 0),
        };
        receiver_type = fieldType(info.members.items, structure_name, field_name) orelse
            return try allocator.alloc(CompletionItem, 0);
    }

    switch (receiver_type) {
        .list => return try collectionCompletionItems(allocator, true),
        .fixed_array => return try collectionCompletionItems(allocator, false),
        .structure => {},
    }

    var items: std.ArrayList(CompletionItem) = .empty;
    const structure_name = receiver_type.structure;
    for (info.members.items) |member| {
        if (!std.mem.eql(u8, member.structure, structure_name)) continue;
        if (containsCompletion(items.items, member.name)) continue;
        try items.append(allocator, .{
            .label = member.name,
            .kind = member.kind,
            .detail = member.detail,
        });
    }
    return try items.toOwnedSlice(allocator);
}

fn collectionCompletionItems(allocator: Allocator, dynamic: bool) ![]const CompletionItem {
    const common = [_][]const u8{ "count", "is_empty", "replace", "swap", "reverse" };
    const list_only = [_][]const u8{ "append", "prepend", "insert", "take", "take_first", "take_last", "clear" };
    const count = common.len + if (dynamic) list_only.len else 0;
    const items = try allocator.alloc(CompletionItem, count);
    var index: usize = 0;
    for (common) |name| {
        items[index] = .{ .label = name, .kind = 2, .detail = "Silex collection method" };
        index += 1;
    }
    if (dynamic) for (list_only) |name| {
        items[index] = .{ .label = name, .kind = 2, .detail = "Silex list method" };
        index += 1;
    };
    return items;
}

fn collectSemanticInfo(
    allocator: Allocator,
    io: Io,
    source: []const u8,
    project_root: ?[]const u8,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    try collectImportedStructures(allocator, io, source, project_root, tokens, info);
    var index: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if ((tokens[index].tag == .keyword_struct or tokens[index].tag == .keyword_class) and index + 2 < tokens.len and
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
                        .collection = collectionKind(tokens, member_index + 2),
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
                    .collection = collectionKind(tokens, index + 3),
                    .offset = tokenOffset(source, tokens[index + 1]),
                });
            } else if (tokens[index + 2].tag == .equal) {
                if (structureInitializerType(info, tokens, index + 3)) |type_name| {
                    try info.variables.append(allocator, .{
                        .name = tokens[index + 1].lexeme,
                        .type_name = type_name,
                        .offset = tokenOffset(source, tokens[index + 1]),
                    });
                } else if (index + 6 < tokens.len and tokens[index + 3].tag == .identifier and
                    tokens[index + 4].tag == .dot and tokens[index + 5].tag == .identifier and
                    tokens[index + 6].tag == .left_parenthesis)
                {
                    const qualifier = tokens[index + 3].lexeme;
                    const module_path = try importedModulePath(allocator, source, qualifier) orelse continue;
                    const type_name = standardFunctionReturnStructure(
                        allocator,
                        io,
                        module_path,
                        tokens[index + 5].lexeme,
                    ) catch null orelse continue;
                    try info.variables.append(allocator, .{
                        .name = tokens[index + 1].lexeme,
                        .type_name = type_name,
                        .offset = tokenOffset(source, tokens[index + 1]),
                    });
                }
            }
        }

        if (tokens[index].tag == .keyword_func) {
            try collectParameters(allocator, source, tokens, index, &info.variables);
        }
    }
}

fn structureInitializerType(info: *const SemanticInfo, tokens: []const LexerModule.Token, start: usize) ?[]const u8 {
    if (start >= tokens.len or tokens[start].tag != .identifier) return null;
    var type_name = tokens[start].lexeme;
    var index = start + 1;
    while (index + 1 < tokens.len and tokens[index].tag == .dot and tokens[index + 1].tag == .identifier) {
        type_name = tokens[index + 1].lexeme;
        index += 2;
    }
    if (index >= tokens.len or tokens[index].tag != .left_parenthesis) return null;
    if (index + 2 < tokens.len and tokens[index + 1].tag == .identifier and tokens[index + 2].tag == .colon) {
        return type_name;
    }
    if (index + 1 >= tokens.len or tokens[index + 1].tag != .right_parenthesis) return null;
    for (info.structures.items) |structure| {
        if (std.mem.eql(u8, structure.name, type_name)) return type_name;
    }
    for (info.members.items) |member| {
        if (std.mem.eql(u8, member.structure, type_name)) return type_name;
    }
    return null;
}

fn structureInitializerPath(
    allocator: Allocator,
    tokens: []const LexerModule.Token,
    start: usize,
) !?[]const u8 {
    if (start >= tokens.len or tokens[start].tag != .identifier) return null;
    var path: std.ArrayList(u8) = .empty;
    defer path.deinit(allocator);
    try path.appendSlice(allocator, tokens[start].lexeme);
    var index = start + 1;
    while (index + 1 < tokens.len and tokens[index].tag == .dot and tokens[index + 1].tag == .identifier) {
        try path.append(allocator, '.');
        try path.appendSlice(allocator, tokens[index + 1].lexeme);
        index += 2;
    }
    if (index >= tokens.len or tokens[index].tag != .left_parenthesis) return null;
    const result: []const u8 = try path.toOwnedSlice(allocator);
    return result;
}

fn collectImportedStructures(
    allocator: Allocator,
    io: Io,
    source: []const u8,
    project_root: ?[]const u8,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |source_line| {
        const line = std.mem.trim(u8, source_line, " \t\r");
        const kind: enum { import_value, use_value } = if (directiveBody(line, "import") != null)
            .import_value
        else if (directiveBody(line, "use") != null)
            .use_value
        else
            continue;
        const declaration = directiveBody(line, if (kind == .import_value) "import" else "use").?;
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const path = declaration[0..module_end];
        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else if (kind == .use_value)
            lastPathSegment(path)
        else
            path;
        const module_path = try importedModulePath(allocator, source, qualifier) orelse continue;
        const module_directory = try longestModuleSourceDirectory(
            allocator,
            io,
            module_path,
            project_root,
        ) orelse continue;
        try visitModuleSources(
            allocator,
            io,
            module_directory,
            collectPublicStructureMembers,
            info,
        );
    }

    for (tokens, 0..) |token, index| {
        if (token.tag != .identifier) continue;
        const path = try structureInitializerPath(allocator, tokens, index) orelse continue;
        defer allocator.free(path);
        const module_path = try importedModulePath(allocator, source, path) orelse continue;
        const module_directory = try longestModuleSourceDirectory(
            allocator,
            io,
            module_path,
            project_root,
        ) orelse continue;
        try visitModuleSources(
            allocator,
            io,
            module_directory,
            collectPublicStructureMembers,
            info,
        );
    }
}

fn longestModuleSourceDirectory(
    allocator: Allocator,
    io: Io,
    module_path: []const u8,
    project_root: ?[]const u8,
) !?[]const u8 {
    var candidate = module_path;
    while (true) {
        if (try moduleSourceDirectory(allocator, io, candidate, project_root)) |directory| return directory;
        const separator = std.mem.lastIndexOfScalar(u8, candidate, '.') orelse return null;
        candidate = candidate[0..separator];
    }
}

fn moduleSourceDirectory(
    allocator: Allocator,
    io: Io,
    module_path: []const u8,
    project_root: ?[]const u8,
) !?[]const u8 {
    if (!StandardLibrary.isReservedModule(module_path)) {
        if (project_root) |root| {
            const local_directory = try moduleDirectoryPath(allocator, root, module_path);
            if (try lspDirectoryExists(io, local_directory)) return local_directory;
        }
    }

    const library_root = StandardLibrary.root(allocator, io) catch return null;
    const distributed_directory = try moduleDirectoryPath(allocator, library_root, module_path);
    return if (try lspDirectoryExists(io, distributed_directory)) distributed_directory else null;
}

fn standardFunctionReturnStructure(
    allocator: Allocator,
    io: Io,
    module_path: []const u8,
    function_name: []const u8,
) !?[]const u8 {
    if (!StandardLibrary.isStandardPath(module_path)) return null;
    var lookup: StandardFunctionLookup = .{ .name = function_name };
    try visitStandardModuleSources(
        allocator,
        io,
        module_path,
        collectStandardFunctionReturn,
        &lookup,
    );
    return lookup.result;
}

fn collectPublicStructureMembers(
    allocator: Allocator,
    program: Ast.Program,
    info: *SemanticInfo,
) !void {
    for (program.structures) |structure| {
        if (!structure.is_public) continue;
        for (structure.fields) |field| try info.members.append(allocator, .{
            .structure = structure.name,
            .name = field.name,
            .type_name = astTypeName(field.type),
            .collection = astCollectionKind(field.type),
            .kind = 5,
            .detail = "Silex module field",
        });
        for (structure.methods) |method| try info.members.append(allocator, .{
            .structure = structure.name,
            .name = method.name,
            .type_name = null,
            .kind = 2,
            .detail = "Silex module method",
        });
    }
}

fn astTypeName(type_name: Ast.TypeName) []const u8 {
    return switch (type_name) {
        .int => "int",
        .int8 => "int8",
        .int16 => "int16",
        .int32 => "int32",
        .int64 => "int64",
        .uint => "uint",
        .uint8 => "uint8",
        .uint16 => "uint16",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .float => "float",
        .float32 => "float32",
        .float64 => "float64",
        .bool => "bool",
        .str => "str",
        .structure => |name| name,
        .list => |element| astTypeName(element.*),
        .fixed_array => |array| astTypeName(array.element.*),
        .reference => |reference| astTypeName(reference.target.*),
        .function => "func",
        .optional => |contained| astTypeName(contained.*),
    };
}

fn astCollectionKind(type_name: Ast.TypeName) ?CollectionKind {
    return switch (type_name) {
        .list => .list,
        .fixed_array => .fixed_array,
        .reference => |reference| astCollectionKind(reference.target.*),
        else => null,
    };
}

fn collectStandardFunctionReturn(
    _: Allocator,
    program: Ast.Program,
    lookup: *StandardFunctionLookup,
) !void {
    if (lookup.result != null) return;
    for (program.functions) |function| {
        if (!function.is_public or !std.mem.eql(u8, function.name, lookup.name)) continue;
        if (function.return_type == .structure) lookup.result = function.return_type.structure;
        return;
    }
}

fn visitStandardModuleSources(
    allocator: Allocator,
    io: Io,
    module_path: []const u8,
    comptime visit: anytype,
    context: anytype,
) !void {
    const standard_library_root = StandardLibrary.root(allocator, io) catch return;
    const module_directory = try moduleDirectoryPath(allocator, standard_library_root, module_path);
    try visitModuleSources(allocator, io, module_directory, visit, context);
}

fn visitModuleSources(
    allocator: Allocator,
    io: Io,
    module_directory: []const u8,
    comptime visit: anytype,
    context: anytype,
) !void {
    var directory = Io.Dir.cwd().openDir(io, module_directory, .{ .iterate = true }) catch return;
    defer directory.close(io);

    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
        const module_source_path = try std.fs.path.join(allocator, &.{ module_directory, entry.name });
        const module_source = Io.Dir.cwd().readFileAlloc(
            io,
            module_source_path,
            allocator,
            .limited(max_message_size),
        ) catch continue;
        var parser = ParserModule.Parser.init(allocator, module_source);
        const program = parser.parse() catch continue;
        try visit(allocator, program, context);
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
                .collection = collectionKind(tokens, index + 2),
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
    if (prefix_start == 0) return null;

    if (source[prefix_start - 1] != '.') return null;
    const is_cascade = prefix_start >= 2 and source[prefix_start - 2] == '.' and
        (prefix_start < 3 or source[prefix_start - 3] != '.');
    var path_end = if (is_cascade)
        cascadeReceiverEnd(source, prefix_start - 2) orelse return null
    else
        prefix_start - 1;
    var is_cascade_receiver = is_cascade;
    if (!is_cascade) {
        if (terminalCascadeReceiverEnd(source, prefix_start - 1)) |receiver_end| {
            path_end = receiver_end;
            is_cascade_receiver = true;
        }
    }
    var path_start = path_end;
    while (path_start > 0 and
        (isIdentifierContinue(source[path_start - 1]) or source[path_start - 1] == '.'))
    {
        path_start -= 1;
    }
    const path_source = source[path_start..path_end];
    if (path_source.len == 0) {
        if (!is_cascade_receiver) return null;
        const declaration_name = cascadeDeclarationName(source, path_end) orelse return null;
        const path = try allocator.alloc([]const u8, 1);
        path[0] = declaration_name;
        return path;
    }

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

fn terminalCascadeReceiverEnd(source: []const u8, member_operator_start: usize) ?usize {
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..member_operator_start], '\n')) |newline|
        newline + 1
    else
        0;
    const statement_start = if (std.mem.lastIndexOfScalar(u8, source[line_start..member_operator_start], ';')) |semicolon|
        line_start + semicolon + 1
    else
        line_start;
    const statement = source[statement_start..member_operator_start];
    const operator_offset = lastCascadeOperator(statement) orelse return null;
    return cascadeReceiverEnd(source, statement_start + operator_offset);
}

fn firstCascadeOperator(source: []const u8) ?usize {
    var index: usize = 0;
    while (index + 1 < source.len) : (index += 1) {
        if (source[index] != '.' or source[index + 1] != '.') continue;
        const preceded_by_dot = index > 0 and source[index - 1] == '.';
        const followed_by_dot = index + 2 < source.len and source[index + 2] == '.';
        if (!preceded_by_dot and !followed_by_dot) return index;
    }
    return null;
}

fn lastCascadeOperator(source: []const u8) ?usize {
    var result: ?usize = null;
    var search_start: usize = 0;
    while (firstCascadeOperator(source[search_start..])) |offset| {
        result = search_start + offset;
        search_start += offset + 2;
    }
    return result;
}

fn cascadeDeclarationName(source: []const u8, anchor_end: usize) ?[]const u8 {
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..anchor_end], '\n')) |newline|
        newline + 1
    else
        0;
    const line = std.mem.trim(u8, source[line_start..anchor_end], " \t\r");
    const keyword_length: usize = if (std.mem.startsWith(u8, line, "var "))
        "var ".len
    else if (std.mem.startsWith(u8, line, "let "))
        "let ".len
    else
        return null;
    var name_end = keyword_length;
    while (name_end < line.len and isIdentifierContinue(line[name_end])) name_end += 1;
    if (name_end == keyword_length) return null;
    return line[keyword_length..name_end];
}

fn cascadeReceiverEnd(source: []const u8, operator_start: usize) ?usize {
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..operator_start], '\n')) |newline|
        newline + 1
    else
        0;
    const statement_start = if (std.mem.lastIndexOfScalar(u8, source[line_start..operator_start], ';')) |semicolon|
        line_start + semicolon + 1
    else
        line_start;
    const compact_receiver = std.mem.trim(u8, source[statement_start..operator_start], " \t\r");
    if (compact_receiver.len != 0) {
        if (firstCascadeOperator(source[statement_start..operator_start])) |first_operator| {
            return statement_start + first_operator;
        }
        return statement_start + std.mem.trimEnd(u8, source[statement_start..operator_start], " \t\r").len;
    }

    var search_end = line_start;
    while (search_end > 0) {
        const line_end = search_end - 1;
        const previous_start = if (std.mem.lastIndexOfScalar(u8, source[0..line_end], '\n')) |newline|
            newline + 1
        else
            0;
        const line = source[previous_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len != 0 and !std.mem.startsWith(u8, trimmed, "..")) {
            if (firstCascadeOperator(line)) |first_operator| {
                return previous_start + first_operator;
            }
            return previous_start + std.mem.trimEnd(u8, line, " \t\r").len;
        }
        search_end = previous_start;
    }
    return null;
}

fn receiverType(info: SemanticInfo, receiver: []const u8, cursor_offset: usize) ?ReceiverType {
    if (std.mem.eql(u8, receiver, "self")) {
        for (info.structures.items) |structure| {
            if (structure.start <= cursor_offset and cursor_offset <= structure.end) {
                return .{ .structure = structure.name };
            }
        }
        return null;
    }

    var result: ?ReceiverType = null;
    var result_offset: usize = 0;
    for (info.variables.items) |variable| {
        if (variable.offset <= cursor_offset and variable.offset >= result_offset and
            std.mem.eql(u8, variable.name, receiver))
        {
            result = if (variable.collection) |collection| switch (collection) {
                .list => .list,
                .fixed_array => .fixed_array,
            } else .{ .structure = variable.type_name };
            result_offset = variable.offset;
        }
    }
    return result;
}

fn fieldType(members: []const DeclaredMember, structure: []const u8, field: []const u8) ?ReceiverType {
    for (members) |member| {
        if (std.mem.eql(u8, member.structure, structure) and std.mem.eql(u8, member.name, field)) {
            if (member.collection) |collection| return switch (collection) {
                .list => .list,
                .fixed_array => .fixed_array,
            };
            return if (member.type_name) |type_name| .{ .structure = type_name } else null;
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

fn collectionKind(tokens: []const LexerModule.Token, type_index: usize) ?CollectionKind {
    var index = type_index + 1;
    var result: ?CollectionKind = null;
    while (index < tokens.len and tokens[index].tag == .left_bracket) {
        if (index + 1 < tokens.len and tokens[index + 1].tag == .right_bracket) {
            result = .list;
            index += 2;
            continue;
        }
        if (index + 2 < tokens.len and tokens[index + 1].tag == .integer and
            tokens[index + 2].tag == .right_bracket)
        {
            result = .fixed_array;
            index += 3;
            continue;
        }
        break;
    }
    return result;
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
    .{ .label = "class", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "assert", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "panic", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "let", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "var", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "if", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "elif", .kind = 14, .detail = "Silex keyword" },
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
    const items = try completionItems(std.testing.allocator, std.testing.io, "func main() void { let total = 1 }", null);
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "func"));
    try std.testing.expect(containsCompletion(items, "class"));
    try std.testing.expect(containsCompletion(items, "elif"));
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\import Math
        \\var pos:Math.V
    ;
    const context = qualifiedCompletionContext(source, .{ .line = 1, .character = 14 }).?;
    try std.testing.expectEqualStrings("Math", context.qualifier);
    try std.testing.expectEqualStrings("V", context.prefix);
    try std.testing.expect(context.type_only);
    try std.testing.expectEqualStrings("Math", (try importedModulePath(allocator, source, context.qualifier)).?);

    const aliased_source = "import Math as Algebra\nvar pos:Algebra.V";
    const aliased = qualifiedCompletionContext(aliased_source, .{ .line = 1, .character = 17 }).?;
    try std.testing.expectEqualStrings("Algebra", aliased.qualifier);
    try std.testing.expectEqualStrings("Math", (try importedModulePath(allocator, aliased_source, aliased.qualifier)).?);

    const parent_source =
        \\import STD as Standard
        \\use Standard.Random as Random
        \\var pos:Random.G
    ;
    const parent = qualifiedCompletionContext(parent_source, .{ .line = 2, .character = 16 }).?;
    try std.testing.expectEqualStrings("Random", parent.qualifier);
    try std.testing.expectEqualStrings(
        "STD.Random",
        (try importedModulePath(allocator, parent_source, parent.qualifier)).?,
    );
}

test "file URIs are decoded for local module discovery" {
    const path = (try filePathFromUri(std.testing.allocator, "file:///tmp/Silex%20Project/Main.sx")).?;
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/tmp/Silex Project/Main.sx", path);
}

test "standard library modules and exports complete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const uri = "file:///Users/nekmata/Projects/Silex/Sandbox/Main.sx";
    const roots = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD");
    try std.testing.expect(containsCompletion(roots, "STD"));
    const modules = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD.R");
    try std.testing.expect(containsCompletion(modules, "STD.Random"));
    const time_modules = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD.T");
    try std.testing.expect(containsCompletion(time_modules, "STD.Time"));

    const submodules = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD",
        .{ .qualifier = "STD", .prefix = "R", .type_only = false },
    );
    try std.testing.expect(containsCompletion(submodules, "STD.Random"));

    const exports = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD.Random",
        .{ .qualifier = "STD.Random", .prefix = "", .type_only = false },
    );
    try std.testing.expect(containsCompletion(exports, "STD.Random.Generator"));
    try std.testing.expect(containsCompletion(exports, "STD.Random.create"));
    try std.testing.expect(containsCompletion(exports, "STD.Random.system"));

    const time_exports = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD.Time",
        .{ .qualifier = "STD.Time", .prefix = "", .type_only = false },
    );
    try std.testing.expect(containsCompletion(time_exports, "STD.Time.Clock"));
    try std.testing.expect(containsCompletion(time_exports, "STD.Time.Stopwatch"));
}

test "member completion infers an imported standard-library factory result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\import STD
        \\use STD.Random as Random
        \\func main() void {
        \\    var rand = Random.system()
        \\    print(rand.get_)
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 4, .character = 19 },
    );
    try std.testing.expect(containsCompletion(items, "get_int"));
    try std.testing.expect(containsCompletion(items, "get_float"));
    try std.testing.expect(containsCompletion(items, "get_bool"));
    try std.testing.expect(!containsCompletion(items, "next"));
}

test "member completion infers qualified standard-library structure initializers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const aliased_source =
        \\import STD.Random as Random
        \\func main() void {
        \\    var generator = Random.Generator(state:1)
        \\    generator.
        \\}
    ;
    const aliased_items = try completionItems(
        allocator,
        std.testing.io,
        aliased_source,
        .{ .line = 3, .character = 14 },
    );
    try std.testing.expect(containsCompletion(aliased_items, "get_int"));
    try std.testing.expect(containsCompletion(aliased_items, "get_float"));

    const canonical_source =
        \\import STD.Random
        \\func main() void {
        \\    var generator = STD.Random.Generator(state:1)
        \\    generator.
        \\}
    ;
    const canonical_items = try completionItems(
        allocator,
        std.testing.io,
        canonical_source,
        .{ .line = 3, .character = 14 },
    );
    try std.testing.expect(containsCompletion(canonical_items, "get_int"));
    try std.testing.expect(containsCompletion(canonical_items, "get_float"));
}

test "member completion loads local module structure fields and methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\import Math
        \\func main() void {
        \\    var vec = Math.Vec2()
        \\    vec.
        \\}
    ;
    const items = try completionItemsForProject(
        arena.allocator(),
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 3, .character = 8 },
    );
    try std.testing.expect(containsCompletion(items, "x"));
    try std.testing.expect(containsCompletion(items, "y"));
    try std.testing.expect(containsCompletion(items, "length_squared"));
}

test "member completion exposes STD Time clock methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\import STD.Time as Time
        \\func main() void {
        \\    var clock = Time.Clock()
        \\    clock.
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 3, .character = 10 },
    );
    try std.testing.expect(containsCompletion(items, "tick"));
    try std.testing.expect(containsCompletion(items, "pause"));
    try std.testing.expect(containsCompletion(items, "get_total_seconds"));
    try std.testing.expect(!containsCompletion(items, "start"));
    try std.testing.expect(!containsCompletion(items, "get_elapsed_seconds"));
}

test "member completion exposes STD Time stopwatch methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\import STD
        \\func main() void {
        \\    var stopwatch = STD.Time.Stopwatch()
        \\    stopwatch.
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 3, .character = 14 },
    );
    try std.testing.expect(containsCompletion(items, "start"));
    try std.testing.expect(containsCompletion(items, "stop"));
    try std.testing.expect(containsCompletion(items, "reset"));
    try std.testing.expect(containsCompletion(items, "restart"));
    try std.testing.expect(containsCompletion(items, "get_elapsed_seconds"));
    try std.testing.expect(!containsCompletion(items, "tick"));
    try std.testing.expect(!containsCompletion(items, "set_time_scale"));
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
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 15 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("speed", items[0].label);
    try std.testing.expectEqual(@as(u8, 5), items[0].kind);
}

test "member completion recognizes class declarations" {
    const source =
        \\class Player {
        \\    health:int = 100
        \\}
        \\func main() {
        \\    var player = Player()
        \\    print(player.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 17 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("health", items[0].label);
}

test "self completion resolves fields and methods of the enclosing structure" {
    const source =
        \\struct Counter {
        \\    value:int
        \\
        \\    func current() int {
        \\        return self.
        \\    }
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 4, .character = 20 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "value"));
    try std.testing.expect(containsCompletion(items, "current"));
}

test "signature help lists overloaded functions once each" {
    const source =
        \\func measure() int { return 1 }
        \\func measure(value:int) int { return value }
        \\func measure(value:float) float { return value }
        \\func main() { print(measure(1)) }
    ;
    const signatures = try signatureHelpItems(std.testing.allocator, source, .{ .line = 3, .character = 28 });
    defer std.testing.allocator.free(signatures);
    defer for (signatures) |signature| std.testing.allocator.free(signature.label);
    try std.testing.expectEqual(@as(usize, 3), signatures.len);
    try std.testing.expectEqualStrings("measure()", signatures[0].label);
    try std.testing.expectEqualStrings("measure(int)", signatures[1].label);
    try std.testing.expectEqualStrings("measure(float)", signatures[2].label);
}

test "cascade completion resolves a receiver on the preceding line" {
    const source =
        \\struct Move {
        \\    speed:float = 100
        \\}
        \\func main() void {
        \\    var move:Move
        \\    move
        \\        ..
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 10 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("speed", items[0].label);
}

test "compact cascade completion keeps the first receiver" {
    const source =
        \\struct Move {
        \\    speed:float = 100
        \\    func reset() void {}
        \\}
        \\func main() void {
        \\    var move:Move
        \\    move..reset()..
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 19 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "speed"));
    try std.testing.expect(containsCompletion(items, "reset"));
    try std.testing.expect(!containsCompletion(items, "return"));
}

test "terminal member dot after a compact cascade keeps the first receiver" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\import STD
        \\func main() void {
        \\    var stopwatch = STD.Time.Stopwatch()
        \\    stopwatch..reset()..start().
        \\}
    ;
    const items = try completionItems(allocator, std.testing.io, source, .{ .line = 3, .character = 32 });
    try std.testing.expect(containsCompletion(items, "is_running"));
    try std.testing.expect(containsCompletion(items, "reset"));
    try std.testing.expect(!containsCompletion(items, "return"));
}

test "completion trigger includes members and cascades" {
    try std.testing.expectEqual(@as(usize, 1), completion_trigger_characters.len);
    try std.testing.expectEqualStrings(".", completion_trigger_characters[0]);
}

test "first dot of an indented cascade does not offer global completions" {
    const source =
        \\func main() void {
        \\    var values:int[]
        \\    values
        \\        .
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 3, .character = 9 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 0), items.len);
}

test "cascade completion resolves an inferred structure initializer" {
    const source =
        \\struct Move {
        \\    speed:float = 100
        \\    func stop() void {}
        \\}
        \\func main() void {
        \\    var move = Move(speed:10)
        \\        ..
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 10 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "speed"));
    try std.testing.expect(containsCompletion(items, "stop"));
    try std.testing.expect(!containsCompletion(items, "return"));
}

test "collection completion distinguishes lists and fixed arrays" {
    const list_source =
        \\func main() void {
        \\    var values:int[]
        \\    values
        \\        ..
        \\}
    ;
    const list_items = try completionItems(std.testing.allocator, std.testing.io, list_source, .{ .line = 3, .character = 10 });
    defer std.testing.allocator.free(list_items);
    try std.testing.expect(containsCompletion(list_items, "append"));
    try std.testing.expect(containsCompletion(list_items, "reverse"));

    const fixed_source =
        \\func main() void {
        \\    var values:int[3]
        \\    values..
        \\}
    ;
    const fixed_items = try completionItems(std.testing.allocator, std.testing.io, fixed_source, .{ .line = 2, .character = 12 });
    defer std.testing.allocator.free(fixed_items);
    try std.testing.expect(containsCompletion(fixed_items, "reverse"));
    try std.testing.expect(!containsCompletion(fixed_items, "append"));
}

test "syntax diagnostics use zero-based LSP positions" {
    const diagnostic = syntaxDiagnostic(std.testing.allocator, "func main() void {\n    let value =\n}").?;
    try std.testing.expectEqual(@as(usize, 2), diagnostic.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), diagnostic.range.start.character);
}

test "syntax diagnostics accept implicit control bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\func next() int? { return null }
        \\func main() {
        \\    if value = next() {}
        \\    while (value = next()) {}
        \\    for value in [1] {}
        \\    for (value in [1]) {}
        \\}
    ;
    try std.testing.expect(syntaxDiagnostic(arena.allocator(), source) == null);
}
