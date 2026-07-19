const std = @import("std");
const build_options = @import("build_options");
const Ast = @import("Ast.zig");
const LexerModule = @import("Lexer.zig");
const ModuleDiscovery = @import("ModuleDiscovery.zig");
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
    insertTextFormat: ?u8 = null,
};

const SignatureInformation = struct {
    label: []const u8,
};

const QualifiedCompletionContext = struct {
    qualifier: []const u8,
    prefix: []const u8,
    type_only: bool,
};

const ModuleExportScope = enum {
    public_api,
    use_path,
};

const DeclaredMember = struct {
    structure: []const u8,
    name: []const u8,
    type_name: ?[]const u8,
    collection: ?CollectionKind = null,
    kind: u8,
    detail: []const u8,
    visibility: Ast.MemberVisibility = .public_access,
    is_static: bool = false,
};

const DeclaredVariable = struct {
    name: []const u8,
    type_name: []const u8,
    collection: ?CollectionKind = null,
    offset: usize,
};

const DeclaredTypeAlias = struct {
    name: []const u8,
    target_name: []const u8,
    collection: ?CollectionKind = null,
};

const DeclaredTypeConstraint = struct {
    name: []const u8,
    target_name: []const u8,
    start: usize,
    end: usize,
};

const DeclaredEnum = struct {
    name: []const u8,
    has_raw_value: bool,
};

const DeclaredEnumVariant = struct {
    enumeration: []const u8,
    name: []const u8,
    has_associated_values: bool,
};

const CollectionKind = enum {
    list,
    fixed_array,
};

const ReceiverType = union(enum) {
    structure: []const u8,
    enumeration: []const u8,
    list,
    fixed_array,
};

const NamedType = struct {
    name: []const u8,
    collection: ?CollectionKind = null,
};

const StructureRange = struct {
    name: []const u8,
    base: ?[]const u8 = null,
    is_class: bool,
    start: ?usize = null,
    end: ?usize = null,
};

const ExtensionRange = struct {
    target: []const u8,
    start: usize,
    end: usize,
};

const SemanticInfo = struct {
    members: std.ArrayList(DeclaredMember) = .empty,
    variables: std.ArrayList(DeclaredVariable) = .empty,
    structures: std.ArrayList(StructureRange) = .empty,
    extensions: std.ArrayList(ExtensionRange) = .empty,
    aliases: std.ArrayList(DeclaredTypeAlias) = .empty,
    constraints: std.ArrayList(DeclaredTypeConstraint) = .empty,
    protocols: std.ArrayList([]const u8) = .empty,
    enums: std.ArrayList(DeclaredEnum) = .empty,
    enum_variants: std.ArrayList(DeclaredEnumVariant) = .empty,

    fn deinit(self: *SemanticInfo, allocator: Allocator) void {
        self.members.deinit(allocator);
        self.variables.deinit(allocator);
        self.structures.deinit(allocator);
        self.extensions.deinit(allocator);
        self.aliases.deinit(allocator);
        self.constraints.deinit(allocator);
        self.protocols.deinit(allocator);
        self.enums.deinit(allocator);
        self.enum_variants.deinit(allocator);
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
                    if (useCompletionPrefix(source, cursor)) |prefix| {
                        break :completion try useCompletionItems(
                            self.allocator,
                            self.io,
                            uri,
                            source,
                            prefix,
                        );
                    }
                    if (qualifiedCompletionContext(source, cursor)) |context| {
                        if (try usedModulePath(self.allocator, source, context.qualifier)) |module_path| {
                            const project_root = try documentProjectRoot(self.allocator, uri);
                            if (try memberCompletionItems(self.allocator, self.io, source, project_root, cursor)) |member_items| {
                                if (member_items.len != 0) break :completion member_items;
                                self.allocator.free(member_items);
                            }
                            break :completion try moduleExportCompletionItems(
                                self.allocator,
                                self.io,
                                uri,
                                module_path,
                                context,
                                .public_api,
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
    for (program.extensions) |extension| for (extension.methods) |method| {
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
    if (index > 0 and source[index - 1] == '>') {
        var depth: usize = 0;
        while (index > 0) {
            index -= 1;
            if (source[index] == '>') {
                depth += 1;
            } else if (source[index] == '<') {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        if (depth != 0) return null;
        while (index > 0 and std.ascii.isWhitespace(source[index - 1])) index -= 1;
    }
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
    if (function.type_parameters.len != 0) {
        try label.append(allocator, '<');
        for (function.type_parameters, 0..) |parameter, index| {
            if (index != 0) try label.appendSlice(allocator, ", ");
            try label.appendSlice(allocator, parameter.name);
            if (parameter.constraint) |constraint| {
                try label.appendSlice(allocator, " : ");
                try label.appendSlice(allocator, constraint.name);
            }
        }
        try label.append(allocator, '>');
    }
    try label.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try label.appendSlice(allocator, ", ");
        if (parameter.mode == .borrow) try label.append(allocator, '@');
        if (parameter.mode == .mutable_reference) try label.append(allocator, '&');
        try appendAstTypeName(allocator, &label, parameter.type);
    }
    try label.append(allocator, ')');
    const value = label.items;
    for (signatures.items) |existing| if (std.mem.eql(u8, existing.label, value)) return;
    try signatures.append(allocator, .{ .label = try label.toOwnedSlice(allocator) });
}

fn appendAstTypeName(allocator: Allocator, output: *std.ArrayList(u8), type_name: Ast.TypeName) !void {
    switch (type_name) {
        .void => try output.appendSlice(allocator, "void"),
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
        .generic_structure => |generic| {
            try output.appendSlice(allocator, generic.name);
            try output.append(allocator, '<');
            for (generic.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendAstTypeName(allocator, output, argument);
            }
            try output.append(allocator, '>');
        },
        .type_parameter => |name| try output.appendSlice(allocator, name),
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
            for (function.parameters, function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (mode == .borrow) try output.append(allocator, '@');
                if (mode == .mutable_reference) try output.append(allocator, '&');
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

fn useCompletionPrefix(source: []const u8, position: Position) ?[]const u8 {
    const cursor_offset = byteOffsetAtPosition(source, position) orelse return null;
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..cursor_offset], '\n')) |newline|
        newline + 1
    else
        0;
    const line = std.mem.trimStart(u8, source[line_start..cursor_offset], " \t");
    if (!std.mem.startsWith(u8, line, "use") or line.len == "use".len) return null;
    if (!std.ascii.isWhitespace(line["use".len])) return null;

    const prefix = std.mem.trimStart(u8, line["use".len..], " \t");
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

fn usedModulePath(allocator: Allocator, source: []const u8, qualifier: []const u8) !?[]const u8 {
    var modules: std.ArrayList(VisibleModule) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |source_line| {
        const line = std.mem.trim(u8, source_line, " \t\r");
        const declaration = directiveBody(line, "use") orelse continue;
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const path = declaration[0..module_end];
        if (path.len == 0) continue;
        if (looksLikeTypeAliasTarget(path)) continue;

        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const visible_qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else
            lastPathSegment(path);
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

fn looksLikeTypeAliasTarget(path: []const u8) bool {
    if (std.mem.indexOfAny(u8, path, "<[]?()") != null) return true;
    const builtins = [_][]const u8{
        "int",   "int8",    "int16",   "int32",  "int64",
        "uint",  "uint8",   "uint16",  "uint32", "uint64",
        "float", "float32", "float64", "bool",   "str",
    };
    for (builtins) |builtin_name| if (std.mem.eql(u8, path, builtin_name)) return true;
    return false;
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
    scope: ModuleExportScope,
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
        } else if (entry.kind == .directory and ModuleDiscovery.isDirectoryName(entry.name) and
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
        const unit_name = source_name[0 .. source_name.len - ".sx".len];
        if (scope == .use_path and std.mem.startsWith(u8, unit_name, context.prefix)) try appendModuleExportCompletion(
            allocator,
            &items,
            context.qualifier,
            unit_name,
            9,
            "Silex source unit",
        );
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
        for (program.enums) |enumeration| {
            if (!enumeration.is_public or !std.mem.startsWith(u8, enumeration.name, context.prefix)) continue;
            try appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                enumeration.name,
                13,
                "Silex public enum",
            );
        }
        for (program.protocols) |protocol| {
            if (!protocol.is_public or !std.mem.startsWith(u8, protocol.name, context.prefix)) continue;
            try appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                protocol.name,
                8,
                "Silex public protocol",
            );
        }
        for (program.uses) |use_value| {
            if (!use_value.is_public or use_value.target != .type) continue;
            const alias = use_value.alias.?;
            if (!std.mem.startsWith(u8, alias, context.prefix)) continue;
            try appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                alias,
                7,
                "Silex public type alias",
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

fn useCompletionItems(
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    source: []const u8,
    prefix: []const u8,
) ![]const CompletionItem {
    var items: std.ArrayList(CompletionItem) = .empty;
    const modules = try localModuleCompletionItems(allocator, io, uri, prefix);
    try items.appendSlice(allocator, modules);

    if (std.mem.lastIndexOfScalar(u8, prefix, '.')) |separator| {
        const qualifier = prefix[0..separator];
        const module_path = try usedModulePath(allocator, source, qualifier) orelse qualifier;
        const exports = try moduleExportCompletionItems(
            allocator,
            io,
            uri,
            module_path,
            .{
                .qualifier = qualifier,
                .prefix = prefix[separator + 1 ..],
                .type_only = false,
            },
            .use_path,
        );
        for (exports) |candidate| {
            var duplicate = false;
            for (items.items) |existing| {
                if (std.mem.eql(u8, existing.label, candidate.label)) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) try items.append(allocator, candidate);
        }
    }

    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return items.toOwnedSlice(allocator);
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
        if (entry.kind == .directory and ModuleDiscovery.isDirectoryName(entry.name)) {
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
    const receiver_path = try memberReceiverPath(allocator, source, cursor_offset);
    defer if (receiver_path) |path| allocator.free(path);

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

    if (receiver_path == null) {
        const enum_name = enumConstructorBeforeMember(info, tokens.items, source, cursor_offset) orelse return null;
        return try enumCompletionItems(allocator, info, enum_name, false, false);
    }
    const path = receiver_path.?;

    var static_selection = false;
    var receiver_type = receiverType(info, path[0], cursor_offset) orelse type_receiver: {
        const resolved = resolveNamedType(info, path[path.len - 1], null).name;
        for (info.structures.items) |structure| {
            if (!std.mem.eql(u8, structure.name, resolved)) continue;
            static_selection = true;
            break :type_receiver ReceiverType{ .structure = resolved };
        }
        for (info.enums.items) |enumeration| {
            if (!std.mem.eql(u8, enumeration.name, resolved)) continue;
            static_selection = true;
            break :type_receiver ReceiverType{ .enumeration = resolved };
        }
        return try allocator.alloc(CompletionItem, 0);
    };
    const enclosing_structure = enclosingStructureName(info, cursor_offset);
    for (path[1..]) |field_name| {
        if (static_selection) break;
        const structure_name = switch (receiver_type) {
            .structure => |name| name,
            .enumeration, .list, .fixed_array => return try allocator.alloc(CompletionItem, 0),
        };
        receiver_type = fieldType(info, structure_name, field_name, enclosing_structure) orelse
            return try allocator.alloc(CompletionItem, 0);
    }

    switch (receiver_type) {
        .list => return try collectionCompletionItems(allocator, true),
        .fixed_array => return try collectionCompletionItems(allocator, false),
        .enumeration => |name| return try enumCompletionItems(
            allocator,
            info,
            name,
            static_selection,
            static_selection and resultVoidStaticSelection(source, cursor_offset),
        ),
        .structure => {},
    }

    var items: std.ArrayList(CompletionItem) = .empty;
    var current_structure: ?[]const u8 = receiver_type.structure;
    var hierarchy_depth: usize = 0;
    while (current_structure) |structure_name| : (hierarchy_depth += 1) {
        if (hierarchy_depth > info.structures.items.len) break;
        for (info.members.items) |member| {
            if (!std.mem.eql(u8, member.structure, structure_name)) continue;
            if (member.is_static != static_selection) continue;
            if (!memberVisibleForCompletion(info, structure_name, member.visibility, enclosing_structure)) continue;
            if (containsCompletion(items.items, member.name)) continue;
            try items.append(allocator, .{
                .label = member.name,
                .kind = member.kind,
                .detail = member.detail,
            });
        }
        current_structure = if (static_selection) null else structureBase(info, structure_name);
    }
    return try items.toOwnedSlice(allocator);
}

fn enumCompletionItems(
    allocator: Allocator,
    info: SemanticInfo,
    enum_name: []const u8,
    static_selection: bool,
    result_void_success: bool,
) ![]const CompletionItem {
    var items: std.ArrayList(CompletionItem) = .empty;
    if (static_selection) {
        for (info.enum_variants.items) |variant| {
            if (!std.mem.eql(u8, variant.enumeration, enum_name) or
                containsCompletion(items.items, variant.name)) continue;
            const has_associated_values = variant.has_associated_values and
                !(result_void_success and std.mem.eql(u8, variant.name, "success"));
            const insertion = if (has_associated_values)
                try std.fmt.allocPrint(allocator, "{s}($0)", .{variant.name})
            else
                try std.fmt.allocPrint(allocator, "{s}()", .{variant.name});
            try items.append(allocator, .{
                .label = variant.name,
                .kind = 20,
                .detail = "Silex enum variant",
                .insertText = insertion,
                .filterText = variant.name,
                .insertTextFormat = if (has_associated_values) 2 else null,
            });
        }
        return try items.toOwnedSlice(allocator);
    }

    for (info.enums.items) |enumeration| {
        if (!std.mem.eql(u8, enumeration.name, enum_name) or !enumeration.has_raw_value) continue;
        try items.append(allocator, .{
            .label = "raw_value",
            .kind = 10,
            .detail = "Silex raw enum value",
        });
        break;
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
    try info.enums.append(allocator, .{ .name = "Result", .has_raw_value = false });
    try info.enum_variants.append(allocator, .{
        .enumeration = "Result",
        .name = "success",
        .has_associated_values = true,
    });
    try info.enum_variants.append(allocator, .{
        .enumeration = "Result",
        .name = "failure",
        .has_associated_values = true,
    });
    try collectUsedStructures(allocator, io, source, project_root, tokens, info);
    try collectLocalTypeAliases(allocator, tokens, info);
    try collectLocalEnums(allocator, tokens, info);
    try collectLocalProtocolsAndConstraints(allocator, source, tokens, info);
    try collectLocalExtensions(allocator, source, tokens, info);
    var index: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if ((tokens[index].tag == .keyword_struct or tokens[index].tag == .keyword_class) and
            index + 2 < tokens.len and tokens[index + 1].tag == .identifier)
        {
            const structure_name = tokens[index + 1].lexeme;
            const is_class = tokens[index].tag == .keyword_class;
            var base_name: ?[]const u8 = null;
            var body_index = index + 2;
            if (tokens[body_index].tag == .less) {
                body_index = genericArgumentsEnd(tokens, body_index) orelse continue;
            }
            if (tokens[body_index].tag == .colon) {
                body_index += 1;
                while (body_index < tokens.len and tokens[body_index].tag != .left_brace) : (body_index += 1) {
                    if (base_name == null and tokens[body_index].tag == .identifier and
                        !protocolNameExists(info.*, tokens[body_index].lexeme))
                    {
                        base_name = tokens[body_index].lexeme;
                    }
                }
            }
            if (body_index >= tokens.len or tokens[body_index].tag != .left_brace) continue;
            const is_owner = !is_class and structureDeclaresDrop(tokens, body_index);
            var depth: usize = 0;
            var parentheses: usize = 0;
            var member_index = body_index;
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
                                .base = base_name,
                                .is_class = is_class,
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
                var declaration_index = member_index;
                var visibility: Ast.MemberVisibility = if (is_class) .private_access else .public_access;
                var has_field_mutability = false;
                var is_static = false;
                if (tokens[declaration_index].tag == .keyword_override) {
                    declaration_index += 1;
                    member_index += 1;
                }
                if (declaration_index < tokens.len and
                    (tokens[declaration_index].tag == .keyword_pub or tokens[declaration_index].tag == .keyword_sub))
                {
                    visibility = if (tokens[declaration_index].tag == .keyword_pub) .public_access else .subclass;
                    declaration_index += 1;
                    member_index += 1;
                }
                if (declaration_index < tokens.len and tokens[declaration_index].tag == .keyword_static) {
                    is_static = true;
                    declaration_index += 1;
                    member_index += 1;
                }
                if (declaration_index < tokens.len and
                    (tokens[declaration_index].tag == .keyword_let or tokens[declaration_index].tag == .keyword_var))
                {
                    has_field_mutability = true;
                    declaration_index += 1;
                    member_index += 1;
                }
                if (declaration_index >= tokens.len) continue;
                const declaration = tokens[declaration_index];
                if (declaration.tag == .keyword_func and declaration_index + 1 < tokens.len and
                    tokens[declaration_index + 1].tag == .identifier)
                {
                    try info.members.append(allocator, .{
                        .structure = structure_name,
                        .name = tokens[declaration_index + 1].lexeme,
                        .type_name = if (is_static) methodReturnType(tokens, declaration_index) else null,
                        .kind = 2,
                        .detail = "Silex method",
                        .visibility = visibility,
                        .is_static = is_static,
                    });
                } else if (has_field_mutability and declaration.tag == .identifier and declaration_index + 2 < tokens.len and
                    tokens[declaration_index + 1].tag == .colon and isTypeToken(tokens[declaration_index + 2].tag))
                {
                    try info.members.append(allocator, .{
                        .structure = structure_name,
                        .name = declaration.lexeme,
                        .type_name = tokens[declaration_index + 2].lexeme,
                        .collection = collectionKind(tokens, declaration_index + 2),
                        .kind = 5,
                        .detail = "Silex field",
                        .visibility = if (is_owner) .private_access else visibility,
                        .is_static = is_static,
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
                } else if (enumVariantInitializerType(info.*, tokens, index + 3)) |type_name| {
                    try info.variables.append(allocator, .{
                        .name = tokens[index + 1].lexeme,
                        .type_name = type_name,
                        .offset = tokenOffset(source, tokens[index + 1]),
                    });
                } else if (staticCallResultType(info.*, tokens, index + 3)) |type_name| {
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
                    const module_path = try usedModulePath(allocator, source, qualifier) orelse continue;
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

        if (tokens[index].tag == .keyword_for) {
            try collectIterationBinding(allocator, source, tokens, index, &info.variables);
        }
    }
}

fn structureDeclaresDrop(tokens: []const LexerModule.Token, body_index: usize) bool {
    var depth: usize = 0;
    for (tokens[body_index..]) |token| switch (token.tag) {
        .left_brace => depth += 1,
        .right_brace => {
            if (depth == 0) return false;
            depth -= 1;
            if (depth == 0) return false;
        },
        .keyword_drop => if (depth == 1) return true,
        else => {},
    };
    return false;
}

fn collectIterationBinding(
    allocator: Allocator,
    source: []const u8,
    tokens: []const LexerModule.Token,
    for_index: usize,
    variables: *std.ArrayList(DeclaredVariable),
) !void {
    var binding_index = for_index + 1;
    if (binding_index < tokens.len and tokens[binding_index].tag == .left_parenthesis) binding_index += 1;
    if (binding_index < tokens.len and
        (tokens[binding_index].tag == .keyword_let or tokens[binding_index].tag == .keyword_var))
    {
        binding_index += 1;
    }
    if (binding_index + 2 >= tokens.len or tokens[binding_index].tag != .identifier or
        tokens[binding_index + 1].tag != .keyword_in or tokens[binding_index + 2].tag != .identifier)
    {
        return;
    }

    const source_name = tokens[binding_index + 2].lexeme;
    var source_variable: ?DeclaredVariable = null;
    for (variables.items) |variable| {
        if (variable.collection != null and std.mem.eql(u8, variable.name, source_name)) {
            source_variable = variable;
        }
    }
    const collection = source_variable orelse return;
    try variables.append(allocator, .{
        .name = tokens[binding_index].lexeme,
        .type_name = collection.type_name,
        .offset = tokenOffset(source, tokens[binding_index]),
    });
}

fn collectLocalExtensions(
    allocator: Allocator,
    source: []const u8,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    for (tokens, 0..) |token, index| {
        if (token.tag != .keyword_extend or index + 2 >= tokens.len) continue;
        var target_index = index + 1;
        var target_name: ?[]const u8 = null;
        while (target_index < tokens.len and tokens[target_index].tag != .colon and
            tokens[target_index].tag != .left_brace) : (target_index += 1)
        {
            if (tokens[target_index].tag == .identifier) target_name = tokens[target_index].lexeme;
        }
        if (target_name == null) continue;
        var body_index = target_index;
        while (body_index < tokens.len and tokens[body_index].tag != .left_brace) : (body_index += 1) {}
        if (body_index >= tokens.len) continue;

        var depth: usize = 0;
        var range_end = source.len;
        var member_index = body_index;
        while (member_index < tokens.len) : (member_index += 1) {
            switch (tokens[member_index].tag) {
                .left_brace => depth += 1,
                .right_brace => {
                    if (depth == 0) break;
                    depth -= 1;
                    if (depth == 0) {
                        range_end = tokenOffset(source, tokens[member_index]) + tokens[member_index].lexeme.len;
                        break;
                    }
                },
                else => {},
            }
            if (depth != 1) continue;

            var declaration_index = member_index;
            if (tokens[declaration_index].tag == .keyword_pub) declaration_index += 1;
            var is_static = false;
            if (declaration_index < tokens.len and tokens[declaration_index].tag == .keyword_static) {
                is_static = true;
                declaration_index += 1;
            }
            if (declaration_index + 1 >= tokens.len or tokens[declaration_index].tag != .keyword_func or
                tokens[declaration_index + 1].tag != .identifier) continue;
            try info.members.append(allocator, .{
                .structure = target_name.?,
                .name = tokens[declaration_index + 1].lexeme,
                .type_name = if (is_static) methodReturnType(tokens, declaration_index) else null,
                .kind = 2,
                .detail = "Silex extension method",
                .visibility = .public_access,
                .is_static = is_static,
            });
            member_index = declaration_index + 1;
        }
        try info.extensions.append(allocator, .{
            .target = target_name.?,
            .start = tokenOffset(source, token),
            .end = range_end,
        });
    }
}

fn collectLocalProtocolsAndConstraints(
    allocator: Allocator,
    source: []const u8,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    var index: usize = 0;
    while (index + 2 < tokens.len) : (index += 1) {
        if (tokens[index].tag == .keyword_protocol and tokens[index + 1].tag == .identifier and
            tokens[index + 2].tag == .left_brace)
        {
            const protocol_name = tokens[index + 1].lexeme;
            try info.protocols.append(allocator, protocol_name);
            var depth: usize = 1;
            var member_index = index + 3;
            while (member_index + 1 < tokens.len and depth != 0) : (member_index += 1) {
                switch (tokens[member_index].tag) {
                    .left_brace => depth += 1,
                    .right_brace => depth -= 1,
                    else => {},
                }
                if (depth == 1 and tokens[member_index].tag == .keyword_func and
                    tokens[member_index + 1].tag == .identifier)
                {
                    try info.members.append(allocator, .{
                        .structure = protocol_name,
                        .name = tokens[member_index + 1].lexeme,
                        .type_name = null,
                        .kind = 2,
                        .detail = "Silex protocol requirement",
                    });
                }
            }
        }

        const declaration = tokens[index].tag == .keyword_func or tokens[index].tag == .keyword_struct or
            tokens[index].tag == .keyword_enum;
        if (!declaration or tokens[index + 1].tag != .identifier or tokens[index + 2].tag != .less) continue;
        const end = genericArgumentsEnd(tokens, index + 2) orelse continue;
        var body_index = end;
        while (body_index < tokens.len and tokens[body_index].tag != .left_brace and tokens[body_index].tag != .end) : (body_index += 1) {}
        if (body_index >= tokens.len or tokens[body_index].tag != .left_brace) continue;
        var body_depth: usize = 1;
        var body_end = body_index + 1;
        while (body_end < tokens.len and body_depth != 0) : (body_end += 1) {
            switch (tokens[body_end].tag) {
                .left_brace => body_depth += 1,
                .right_brace => body_depth -= 1,
                else => {},
            }
        }
        if (body_depth != 0 or body_end == 0) continue;
        const range_start = tokenOffset(source, tokens[index]);
        const closing = tokens[body_end - 1];
        const range_end = tokenOffset(source, closing) + closing.lexeme.len;
        var parameter_index = index + 3;
        while (parameter_index + 2 < end) : (parameter_index += 1) {
            if (tokens[parameter_index].tag != .identifier or tokens[parameter_index + 1].tag != .colon or
                tokens[parameter_index + 2].tag != .identifier) continue;
            var target_name = tokens[parameter_index + 2].lexeme;
            var target_index = parameter_index + 3;
            while (target_index + 1 < end and tokens[target_index].tag == .dot and
                tokens[target_index + 1].tag == .identifier)
            {
                target_name = tokens[target_index + 1].lexeme;
                target_index += 2;
            }
            try info.constraints.append(allocator, .{
                .name = tokens[parameter_index].lexeme,
                .target_name = target_name,
                .start = range_start,
                .end = range_end,
            });
        }
    }
}

fn protocolNameExists(info: SemanticInfo, name: []const u8) bool {
    for (info.protocols.items) |protocol_name| {
        if (std.mem.eql(u8, protocol_name, name)) return true;
    }
    return false;
}

fn collectLocalEnums(
    allocator: Allocator,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    var index: usize = 0;
    while (index + 2 < tokens.len) : (index += 1) {
        if (tokens[index].tag != .keyword_enum or tokens[index + 1].tag != .identifier) continue;
        const enum_name = tokens[index + 1].lexeme;
        var body_index = index + 2;
        if (tokens[body_index].tag == .less) {
            body_index = genericArgumentsEnd(tokens, body_index) orelse continue;
        }
        var has_raw_value = false;
        if (tokens[body_index].tag == .colon) {
            body_index += 1;
            if (body_index >= tokens.len) continue;
            has_raw_value = tokens[body_index].tag == .keyword_int or tokens[body_index].tag == .keyword_str;
            body_index += 1;
        }
        if (body_index >= tokens.len or tokens[body_index].tag != .left_brace) continue;
        try info.enums.append(allocator, .{ .name = enum_name, .has_raw_value = has_raw_value });

        var depth: usize = 1;
        var parentheses: usize = 0;
        var variant_index = body_index + 1;
        while (variant_index < tokens.len and depth != 0) : (variant_index += 1) {
            const token = tokens[variant_index];
            if (token.tag == .left_brace) {
                depth += 1;
                continue;
            }
            if (token.tag == .right_brace) {
                depth -= 1;
                continue;
            }
            if (depth == 1 and token.tag == .left_parenthesis) {
                parentheses += 1;
                continue;
            }
            if (depth == 1 and token.tag == .right_parenthesis) {
                parentheses -|= 1;
                continue;
            }
            if (depth != 1 or parentheses != 0 or token.tag != .identifier) continue;
            try info.enum_variants.append(allocator, .{
                .enumeration = enum_name,
                .name = token.lexeme,
                .has_associated_values = variant_index + 1 < tokens.len and
                    tokens[variant_index + 1].tag == .left_parenthesis,
            });
        }
        index = if (variant_index == 0) index else variant_index - 1;
    }
}

fn methodReturnType(tokens: []const LexerModule.Token, function_index: usize) ?[]const u8 {
    if (function_index + 2 >= tokens.len or tokens[function_index].tag != .keyword_func) return null;
    var index = function_index + 2;
    if (tokens[index].tag != .left_parenthesis) return null;
    var depth: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if (tokens[index].tag == .left_parenthesis) depth += 1 else if (tokens[index].tag == .right_parenthesis) {
            depth -|= 1;
            if (depth == 0) {
                index += 1;
                break;
            }
        }
    }
    if (index >= tokens.len or tokens[index].tag == .left_brace) return null;
    var result: ?[]const u8 = null;
    while (index < tokens.len and tokens[index].tag != .left_brace) : (index += 1) {
        if (tokens[index].tag == .identifier) result = tokens[index].lexeme;
        if (tokens[index].tag == .less or tokens[index].tag == .left_bracket or tokens[index].tag == .question) break;
    }
    return result;
}

fn staticCallResultType(info: SemanticInfo, tokens: []const LexerModule.Token, start: usize) ?[]const u8 {
    if (start >= tokens.len or tokens[start].tag != .identifier) return null;
    var owner_name = tokens[start].lexeme;
    var index = start + 1;
    while (index < tokens.len) {
        if (tokens[index].tag == .less) {
            index = genericArgumentsEnd(tokens, index) orelse return null;
            continue;
        }
        if (index + 2 < tokens.len and tokens[index].tag == .dot and
            tokens[index + 1].tag == .identifier)
        {
            if (tokens[index + 2].tag == .left_parenthesis) {
                const resolved_owner = resolveNamedType(info, owner_name, null).name;
                for (info.members.items) |member| {
                    if (member.is_static and member.type_name != null and
                        std.mem.eql(u8, member.structure, resolved_owner) and
                        std.mem.eql(u8, member.name, tokens[index + 1].lexeme)) return member.type_name;
                }
                return null;
            }
            owner_name = tokens[index + 1].lexeme;
            index += 2;
            continue;
        }
        return null;
    }
    return null;
}

fn structureInitializerType(info: *const SemanticInfo, tokens: []const LexerModule.Token, start: usize) ?[]const u8 {
    if (start >= tokens.len or tokens[start].tag != .identifier) return null;
    var type_name = tokens[start].lexeme;
    var index = start + 1;
    while (index + 1 < tokens.len and tokens[index].tag == .dot and tokens[index + 1].tag == .identifier) {
        type_name = tokens[index + 1].lexeme;
        index += 2;
    }
    if (index < tokens.len and tokens[index].tag == .less) {
        index = genericArgumentsEnd(tokens, index) orelse return null;
    }
    if (index >= tokens.len or tokens[index].tag != .left_parenthesis) return null;
    type_name = resolveNamedType(info.*, type_name, null).name;
    const named_initializer = index + 2 < tokens.len and tokens[index + 1].tag == .identifier and
        tokens[index + 2].tag == .colon;
    const empty_initializer = index + 1 < tokens.len and tokens[index + 1].tag == .right_parenthesis;
    for (info.structures.items) |structure| {
        if (std.mem.eql(u8, structure.name, type_name) and
            (structure.is_class or named_initializer or empty_initializer)) return type_name;
    }
    if (!named_initializer and !empty_initializer) return null;
    for (info.members.items) |member| {
        if (std.mem.eql(u8, member.structure, type_name)) return type_name;
    }
    return null;
}

fn enumVariantInitializerType(info: SemanticInfo, tokens: []const LexerModule.Token, start: usize) ?[]const u8 {
    if (start >= tokens.len or tokens[start].tag != .identifier) return null;
    var current_name = tokens[start].lexeme;
    var enum_candidate: ?[]const u8 = null;
    var index = start + 1;
    while (true) {
        if (index < tokens.len and tokens[index].tag == .less) {
            index = genericArgumentsEnd(tokens, index) orelse return null;
        }
        if (index + 1 >= tokens.len or tokens[index].tag != .dot or tokens[index + 1].tag != .identifier) break;
        enum_candidate = current_name;
        current_name = tokens[index + 1].lexeme;
        index += 2;
    }
    if (enum_candidate == null or index >= tokens.len or tokens[index].tag != .left_parenthesis) return null;
    const enum_name = resolveNamedType(info, enum_candidate.?, null).name;
    var enum_exists = false;
    for (info.enums.items) |enumeration| {
        if (std.mem.eql(u8, enumeration.name, enum_name)) {
            enum_exists = true;
            break;
        }
    }
    if (!enum_exists) return null;
    for (info.enum_variants.items) |variant| {
        if (std.mem.eql(u8, variant.enumeration, enum_name) and
            std.mem.eql(u8, variant.name, current_name)) return enum_name;
    }
    return null;
}

fn enumConstructorBeforeMember(
    info: SemanticInfo,
    tokens: []const LexerModule.Token,
    source: []const u8,
    cursor_offset: usize,
) ?[]const u8 {
    var prefix_start = cursor_offset;
    while (prefix_start > 0 and isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return null;
    const member_operator = prefix_start - 1;

    var dot_index: ?usize = null;
    for (tokens, 0..) |token, index| {
        if (token.tag == .dot and tokenOffset(source, token) == member_operator) {
            dot_index = index;
            break;
        }
    }
    var index = dot_index orelse return null;
    if (index == 0 or tokens[index - 1].tag != .right_parenthesis) return null;

    index -= 1;
    var depth: usize = 0;
    var call_start: ?usize = null;
    while (true) {
        if (tokens[index].tag == .right_parenthesis) {
            depth += 1;
        } else if (tokens[index].tag == .left_parenthesis) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) {
                call_start = index;
                break;
            }
        }
        if (index == 0) break;
        index -= 1;
    }
    const left_parenthesis = call_start orelse return null;
    if (left_parenthesis == 0 or tokens[left_parenthesis - 1].tag != .identifier) return null;
    var callee_start = left_parenthesis - 1;
    while (callee_start >= 2 and tokens[callee_start - 1].tag == .dot and
        tokens[callee_start - 2].tag == .identifier)
    {
        callee_start -= 2;
    }
    return enumVariantInitializerType(info, tokens, callee_start);
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
    if (index < tokens.len and tokens[index].tag == .less) {
        index = genericArgumentsEnd(tokens, index) orelse return null;
    }
    if (index >= tokens.len or tokens[index].tag != .left_parenthesis) return null;
    const result: []const u8 = try path.toOwnedSlice(allocator);
    return result;
}

fn genericArgumentsEnd(tokens: []const LexerModule.Token, start: usize) ?usize {
    if (start >= tokens.len or tokens[start].tag != .less) return null;
    var depth: usize = 0;
    var index = start;
    while (index < tokens.len) : (index += 1) {
        switch (tokens[index].tag) {
            .less => depth += 1,
            .greater => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) return index + 1;
            },
            .shift_right => {
                if (depth == 0) return null;
                if (depth <= 2) return index + 1;
                depth -= 2;
            },
            else => {},
        }
    }
    return null;
}

fn collectLocalTypeAliases(
    allocator: Allocator,
    tokens: []const LexerModule.Token,
    info: *SemanticInfo,
) !void {
    for (tokens, 0..) |token, use_index| {
        if (token.tag != .keyword_use or use_index + 2 >= tokens.len) continue;
        const line = token.position.line;
        var as_index = use_index + 1;
        while (as_index < tokens.len and tokens[as_index].position.line == line and
            tokens[as_index].tag != .keyword_as) : (as_index += 1)
        {}
        if (as_index + 1 >= tokens.len or tokens[as_index].tag != .keyword_as or
            tokens[as_index + 1].tag != .identifier) continue;

        var target_index = use_index + 1;
        while (target_index < as_index and tokens[target_index].tag == .amp) target_index += 1;
        if (target_index >= as_index or !isTypeToken(tokens[target_index].tag) and
            tokens[target_index].tag != .keyword_func) continue;

        var target_name = tokens[target_index].lexeme;
        var path_index = target_index + 1;
        while (path_index + 1 < as_index and tokens[path_index].tag == .dot and
            tokens[path_index + 1].tag == .identifier)
        {
            target_name = tokens[path_index + 1].lexeme;
            path_index += 2;
        }
        try info.aliases.append(allocator, .{
            .name = tokens[as_index + 1].lexeme,
            .target_name = target_name,
            .collection = aliasCollectionKind(tokens[target_index..as_index]),
        });
    }
}

fn aliasCollectionKind(tokens: []const LexerModule.Token) ?CollectionKind {
    var generic_depth: usize = 0;
    for (tokens, 0..) |token, index| {
        switch (token.tag) {
            .less => generic_depth += 1,
            .greater => generic_depth -|= 1,
            .shift_right => generic_depth -|= 2,
            .left_bracket => if (generic_depth == 0) {
                if (index + 1 < tokens.len and tokens[index + 1].tag == .right_bracket) return .list;
                if (index + 2 < tokens.len and tokens[index + 1].tag == .integer and
                    tokens[index + 2].tag == .right_bracket) return .fixed_array;
            },
            else => {},
        }
    }
    return null;
}

fn resolveNamedType(info: SemanticInfo, name: []const u8, collection: ?CollectionKind) NamedType {
    var result: NamedType = .{ .name = name, .collection = collection };
    var depth: usize = 0;
    while (depth <= info.aliases.items.len) : (depth += 1) {
        var alias_index = info.aliases.items.len;
        while (alias_index > 0) {
            alias_index -= 1;
            const alias = info.aliases.items[alias_index];
            if (!std.mem.eql(u8, alias.name, result.name)) continue;
            result.name = alias.target_name;
            if (result.collection == null) result.collection = alias.collection;
            break;
        } else return result;
    }
    return result;
}

fn collectUsedStructures(
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
        const declaration = directiveBody(line, "use") orelse continue;
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const path = declaration[0..module_end];
        if (looksLikeTypeAliasTarget(path)) continue;
        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else
            lastPathSegment(path);
        const module_path = try usedModulePath(allocator, source, qualifier) orelse continue;
        const module_directory = try longestModuleSourceDirectory(
            allocator,
            io,
            module_path,
            project_root,
        ) orelse continue;
        try visitSelectedModuleSources(
            allocator,
            io,
            module_path,
            module_directory,
            collectPublicStructureMembers,
            info,
        );
    }

    for (tokens, 0..) |token, index| {
        if (token.tag != .identifier) continue;
        const path = try structureInitializerPath(allocator, tokens, index) orelse continue;
        defer allocator.free(path);
        const module_path = try usedModulePath(allocator, source, path) orelse continue;
        const module_directory = try longestModuleSourceDirectory(
            allocator,
            io,
            module_path,
            project_root,
        ) orelse continue;
        try visitSelectedModuleSources(
            allocator,
            io,
            module_path,
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
    for (program.extensions) |extension| {
        const target_is_struct = if (extensionTargetIsClass(program, info.*, extension.target)) |is_class|
            !is_class
        else
            false;
        for (extension.methods) |method| {
            if (!method.is_public and !target_is_struct) continue;
            try info.members.append(allocator, .{
                .structure = lastPathSegment(extension.target),
                .name = method.name,
                .type_name = if (method.is_static) switch (method.return_type) {
                    .structure => |name| lastPathSegment(name),
                    .generic_structure => |generic| lastPathSegment(generic.name),
                    else => null,
                } else null,
                .kind = 2,
                .detail = "Silex module extension method",
                .visibility = .public_access,
                .is_static = method.is_static,
            });
        }
    }
    for (program.protocols) |protocol| {
        if (!protocol.is_public) continue;
        try info.protocols.append(allocator, protocol.name);
        for (protocol.requirements) |requirement| {
            try info.members.append(allocator, .{
                .structure = protocol.name,
                .name = requirement.name,
                .type_name = null,
                .kind = 2,
                .detail = "Silex module protocol requirement",
            });
        }
    }
    for (program.enums) |enumeration| {
        if (!enumeration.is_public) continue;
        try info.enums.append(allocator, .{
            .name = enumeration.name,
            .has_raw_value = enumeration.raw_type != null,
        });
        for (enumeration.variants) |variant| {
            try info.enum_variants.append(allocator, .{
                .enumeration = enumeration.name,
                .name = variant.name,
                .has_associated_values = variant.associated_types.len != 0,
            });
        }
    }
    for (program.structures) |structure| {
        if (!structure.is_public) continue;
        try info.structures.append(allocator, .{
            .name = structure.name,
            .base = if (structure.base) |base| lastPathSegment(base.name) else null,
            .is_class = structure.is_class,
        });
        for (structure.fields) |field| {
            if (!structure.is_class and structure.drop != null) continue;
            if (structure.is_class and field.visibility != .public_access) continue;
            try info.members.append(allocator, .{
                .structure = structure.name,
                .name = field.name,
                .type_name = astTypeName(field.type),
                .collection = astCollectionKind(field.type),
                .kind = 5,
                .detail = "Silex module field",
                .visibility = field.visibility,
                .is_static = field.is_static,
            });
        }
        for (structure.methods) |method| {
            const visibility = method.member_visibility orelse .public_access;
            if (structure.is_class and visibility != .public_access) continue;
            try info.members.append(allocator, .{
                .structure = structure.name,
                .name = method.name,
                .type_name = if (method.is_static) switch (method.return_type) {
                    .structure => |name| lastPathSegment(name),
                    .generic_structure => |generic| lastPathSegment(generic.name),
                    else => null,
                } else null,
                .kind = 2,
                .detail = "Silex module method",
                .visibility = visibility,
                .is_static = method.is_static,
            });
        }
    }
    for (program.uses) |use_value| {
        if (!use_value.is_public) continue;
        const alias = use_value.alias orelse continue;
        const target = switch (use_value.target) {
            .declaration => |declaration| NamedType{ .name = lastPathSegment(declaration) },
            .type => |type_name| NamedType{
                .name = lastPathSegment(astTypeName(type_name)),
                .collection = astCollectionKind(type_name),
            },
        };
        try info.aliases.append(allocator, .{
            .name = alias,
            .target_name = target.name,
            .collection = target.collection,
        });
    }
}

fn extensionTargetIsClass(program: Ast.Program, info: SemanticInfo, target: []const u8) ?bool {
    const target_name = lastPathSegment(target);
    for (program.structures) |structure| {
        if (std.mem.eql(u8, structure.name, target_name)) return structure.is_class;
    }
    var index = info.structures.items.len;
    while (index > 0) {
        index -= 1;
        const structure = info.structures.items[index];
        if (std.mem.eql(u8, structure.name, target_name)) return structure.is_class;
    }
    return null;
}

fn astTypeName(type_name: Ast.TypeName) []const u8 {
    return switch (type_name) {
        .void => "void",
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
        .generic_structure => |generic| generic.name,
        .type_parameter => |name| name,
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

fn visitSelectedModuleSources(
    allocator: Allocator,
    io: Io,
    selected_path: []const u8,
    module_directory: []const u8,
    comptime visit: anytype,
    context: anytype,
) !void {
    const unit_name = lastPathSegment(selected_path);
    const unit_filename = try std.fmt.allocPrint(allocator, "{s}.sx", .{unit_name});
    const unit_path = try std.fs.path.join(allocator, &.{ module_directory, unit_filename });
    const stat = Io.Dir.cwd().statFile(io, unit_path, .{}) catch {
        return visitModuleSources(allocator, io, module_directory, visit, context);
    };
    if (stat.kind != .file) return visitModuleSources(allocator, io, module_directory, visit, context);

    var pending: std.ArrayList([]const u8) = .empty;
    var visited: std.ArrayList([]const u8) = .empty;
    try pending.append(allocator, unit_name);
    while (pending.pop()) |current| {
        var already_visited = false;
        for (visited.items) |existing| if (std.mem.eql(u8, existing, current)) {
            already_visited = true;
            break;
        };
        if (already_visited) continue;
        try visited.append(allocator, current);

        const filename = try std.fmt.allocPrint(allocator, "{s}.sx", .{current});
        const source_path = try std.fs.path.join(allocator, &.{ module_directory, filename });
        const source = Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(max_message_size)) catch continue;
        var parser = ParserModule.Parser.init(allocator, source);
        const program = parser.parse() catch continue;
        try visit(allocator, program, context);
        for (program.uses) |use_value| {
            if (use_value.target != .declaration) continue;
            const sibling = use_value.target.declaration;
            if (std.mem.indexOfScalar(u8, sibling, '.') != null) continue;
            const sibling_filename = try std.fmt.allocPrint(allocator, "{s}.sx", .{sibling});
            const sibling_path = try std.fs.path.join(allocator, &.{ module_directory, sibling_filename });
            const sibling_stat = Io.Dir.cwd().statFile(io, sibling_path, .{}) catch continue;
            if (sibling_stat.kind == .file) try pending.append(allocator, sibling);
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
    if (path_end > 0 and source[path_end - 1] == '>') {
        var depth: usize = 1;
        var generic_start = path_end - 1;
        while (generic_start > 0 and depth != 0) {
            generic_start -= 1;
            if (source[generic_start] == '>') depth += 1 else if (source[generic_start] == '<') depth -= 1;
        }
        if (depth != 0) return null;
        path_end = generic_start;
        path_start = path_end;
    }
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

fn resultVoidStaticSelection(source: []const u8, cursor_offset: usize) bool {
    var prefix_start = @min(cursor_offset, source.len);
    while (prefix_start > 0 and isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return false;

    var type_end = prefix_start - 1;
    while (type_end > 0 and std.ascii.isWhitespace(source[type_end - 1])) type_end -= 1;
    if (type_end == 0 or source[type_end - 1] != '>') return false;

    var depth: usize = 0;
    var generic_start: ?usize = null;
    var index = type_end;
    while (index > 0) {
        index -= 1;
        if (source[index] == '>') {
            depth += 1;
        } else if (source[index] == '<') {
            if (depth == 0) return false;
            depth -= 1;
            if (depth == 0) {
                generic_start = index;
                break;
            }
        }
    }
    const argument_start = generic_start orelse return false;

    var name_end = argument_start;
    while (name_end > 0 and std.ascii.isWhitespace(source[name_end - 1])) name_end -= 1;
    var name_start = name_end;
    while (name_start > 0 and isIdentifierContinue(source[name_start - 1])) name_start -= 1;
    if (!std.mem.eql(u8, source[name_start..name_end], "Result")) return false;

    const arguments = std.mem.trim(u8, source[argument_start + 1 .. type_end - 1], " \t\r\n");
    if (!std.mem.startsWith(u8, arguments, "void")) return false;
    const remainder = std.mem.trimStart(u8, arguments["void".len..], " \t\r\n");
    return remainder.len != 0 and remainder[0] == ',';
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
            if (structure.start != null and structure.end != null and
                structure.start.? <= cursor_offset and cursor_offset <= structure.end.?)
            {
                return .{ .structure = structure.name };
            }
        }
        for (info.extensions.items) |extension| {
            if (extension.start <= cursor_offset and cursor_offset <= extension.end) {
                return .{ .structure = extension.target };
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
            const constrained_name = constrainedTypeAt(info, variable.type_name, cursor_offset) orelse variable.type_name;
            const resolved = resolveNamedType(info, constrained_name, variable.collection);
            result = if (resolved.collection) |collection| switch (collection) {
                .list => .list,
                .fixed_array => .fixed_array,
            } else receiverTypeForNamed(info, resolved.name);
            result_offset = variable.offset;
        }
    }
    return result;
}

fn constrainedTypeAt(info: SemanticInfo, name: []const u8, cursor_offset: usize) ?[]const u8 {
    var result: ?[]const u8 = null;
    var result_start: usize = 0;
    for (info.constraints.items) |constraint| {
        if (constraint.start <= cursor_offset and cursor_offset <= constraint.end and
            constraint.start >= result_start and std.mem.eql(u8, constraint.name, name))
        {
            result = constraint.target_name;
            result_start = constraint.start;
        }
    }
    return result;
}

fn enclosingStructureName(info: SemanticInfo, cursor_offset: usize) ?[]const u8 {
    for (info.structures.items) |structure| {
        if (structure.start != null and structure.end != null and
            structure.start.? <= cursor_offset and cursor_offset <= structure.end.?) return structure.name;
    }
    return null;
}

fn fieldType(
    info: SemanticInfo,
    structure: []const u8,
    field: []const u8,
    enclosing_structure: ?[]const u8,
) ?ReceiverType {
    var current_structure: ?[]const u8 = structure;
    var hierarchy_depth: usize = 0;
    while (current_structure) |structure_name| : (hierarchy_depth += 1) {
        if (hierarchy_depth > info.structures.items.len) return null;
        for (info.members.items) |member| {
            if (member.is_static) continue;
            if (std.mem.eql(u8, member.structure, structure_name) and std.mem.eql(u8, member.name, field)) {
                if (!memberVisibleForCompletion(info, structure_name, member.visibility, enclosing_structure)) return null;
                const type_name = member.type_name orelse return null;
                const resolved = resolveNamedType(info, type_name, member.collection);
                if (resolved.collection) |collection| return switch (collection) {
                    .list => .list,
                    .fixed_array => .fixed_array,
                };
                return receiverTypeForNamed(info, resolved.name);
            }
        }
        current_structure = structureBase(info, structure_name);
    }
    return null;
}

fn receiverTypeForNamed(info: SemanticInfo, name: []const u8) ReceiverType {
    for (info.enums.items) |enumeration| {
        if (std.mem.eql(u8, enumeration.name, name)) return .{ .enumeration = name };
    }
    return .{ .structure = name };
}

fn structureBase(info: SemanticInfo, structure_name: []const u8) ?[]const u8 {
    for (info.structures.items) |structure| {
        if (std.mem.eql(u8, structure.name, structure_name)) return structure.base;
    }
    return null;
}

fn structureDescendsFrom(info: SemanticInfo, candidate: []const u8, ancestor: []const u8) bool {
    var current = structureBase(info, candidate);
    var hierarchy_depth: usize = 0;
    while (current) |structure_name| : (hierarchy_depth += 1) {
        if (hierarchy_depth > info.structures.items.len) return false;
        if (std.mem.eql(u8, structure_name, ancestor)) return true;
        current = structureBase(info, structure_name);
    }
    return false;
}

fn memberVisibleForCompletion(
    info: SemanticInfo,
    declaring_structure: []const u8,
    visibility: Ast.MemberVisibility,
    enclosing_structure: ?[]const u8,
) bool {
    return switch (visibility) {
        .public_access => true,
        .private_access => enclosing_structure != null and
            std.mem.eql(u8, enclosing_structure.?, declaring_structure),
        .subclass => enclosing_structure != null and
            (std.mem.eql(u8, enclosing_structure.?, declaring_structure) or
                structureDescendsFrom(info, enclosing_structure.?, declaring_structure)),
    };
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

fn findCompletion(items: []const CompletionItem, label: []const u8) ?CompletionItem {
    for (items) |item| if (std.mem.eql(u8, item.label, label)) return item;
    return null;
}

const language_completions = [_]CompletionItem{
    .{ .label = "func", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "struct", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "class", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "protocol", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "extend", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "enum", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "init", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "drop", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "super", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "override", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "static", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "assert", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "panic", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "let", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "var", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "if", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "elif", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "else", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "while", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "match", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "return", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "try", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "move", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "use", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "pub", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "sub", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "as", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "self", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "true", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "false", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "print", .kind = 3, .detail = "Silex builtin" },
    .{ .label = "map_error", .kind = 3, .detail = "Silex intrinsic function" },
    .{ .label = "Result", .kind = 7, .detail = "Silex intrinsic type" },
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
    try std.testing.expect(containsCompletion(items, "protocol"));
    try std.testing.expect(containsCompletion(items, "extend"));
    try std.testing.expect(containsCompletion(items, "enum"));
    try std.testing.expect(containsCompletion(items, "init"));
    try std.testing.expect(containsCompletion(items, "drop"));
    try std.testing.expect(containsCompletion(items, "override"));
    try std.testing.expect(containsCompletion(items, "static"));
    try std.testing.expect(containsCompletion(items, "super"));
    try std.testing.expect(containsCompletion(items, "sub"));
    try std.testing.expect(containsCompletion(items, "elif"));
    try std.testing.expect(containsCompletion(items, "match"));
    try std.testing.expect(containsCompletion(items, "try"));
    try std.testing.expect(containsCompletion(items, "move"));
    try std.testing.expect(!containsCompletion(items, "borrow"));
    try std.testing.expect(containsCompletion(items, "total"));
    try std.testing.expect(!containsCompletion(items, "import"));
}

test "constrained generic completion exposes protocol requirements" {
    const source =
        \\protocol Drawable { func draw() }
        \\func render<T : Drawable>(value:T) {
        \\    value.
        \\}
    ;
    const items = try completionItems(
        std.testing.allocator,
        std.testing.io,
        source,
        .{ .line = 2, .character = 10 },
    );
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "draw"));
}

test "protocol value completion exposes only protocol requirements" {
    const source =
        \\protocol Drawable { func draw() }
        \\class Player : Drawable { pub var score:int; pub func draw() {}; pub func jump() {} }
        \\func main() {
        \\    var drawable:Drawable = Player()
        \\    drawable.
        \\}
    ;
    const items = try completionItems(
        std.testing.allocator,
        std.testing.io,
        source,
        .{ .line = 4, .character = 13 },
    );
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expect(containsCompletion(items, "draw"));
    try std.testing.expect(!containsCompletion(items, "jump"));
    try std.testing.expect(!containsCompletion(items, "score"));
}

test "member completion infers neutral iteration elements" {
    const source =
        \\protocol Drawable { func draw() }
        \\class Player : Drawable { pub func draw() {}; pub func jump() {} }
        \\func main() {
        \\    let drawables:Drawable[] = [Player()]
        \\    for drawable in drawables {
        \\        drawable.
        \\    }
        \\}
    ;
    const items = try completionItems(
        std.testing.allocator,
        std.testing.io,
        source,
        .{ .line = 5, .character = 17 },
    );
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expect(containsCompletion(items, "draw"));
    try std.testing.expect(!containsCompletion(items, "jump"));
}

test "local extension completion augments a used STD type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use STD.Randomizer as Randomizer
        \\extend Randomizer {
        \\    pub func get_uint() uint { return self.get_int() as uint }
        \\    static func seeded() Randomizer { return Randomizer.create(42) }
        \\}
        \\func main() {
        \\    var randomizer = Randomizer.create(42)
        \\    randomizer.
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 7, .character = 15 },
    );
    try std.testing.expect(containsCompletion(items, "get_int"));
    try std.testing.expect(containsCompletion(items, "get_uint"));
    try std.testing.expect(!containsCompletion(items, "seeded"));
}

test "direct module use activates public extension completion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\use Math
        \\use Extras
        \\func main() {
        \\    var vector = Math.Vec2()
        \\    vector.
        \\}
    ;
    const items = try completionItemsForProject(
        allocator,
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 4, .character = 11 },
    );
    try std.testing.expect(containsCompletion(items, "length_squared"));
    try std.testing.expect(containsCompletion(items, "scaled"));
    try std.testing.expect(!containsCompletion(items, "origin"));

    const class_source =
        \\use Math
        \\use Extras
        \\func main() {
        \\    var canvas = Math.Canvas()
        \\    canvas.
        \\}
    ;
    const class_items = try completionItemsForProject(
        allocator,
        std.testing.io,
        class_source,
        "Tests/LspModules",
        .{ .line = 4, .character = 11 },
    );
    try std.testing.expect(!containsCompletion(class_items, "hidden"));
}

test "use completion recognizes only the dependency path context" {
    try std.testing.expectEqualStrings(
        "M",
        useCompletionPrefix("use M", .{ .line = 0, .character = 5 }).?,
    );
    try std.testing.expectEqualStrings(
        "",
        useCompletionPrefix("    use ", .{ .line = 0, .character = 8 }).?,
    );
    try std.testing.expect(useCompletionPrefix(
        "use Math as M",
        .{ .line = 0, .character = 16 },
    ) == null);
}

test "qualified completion resolves a used module and its typed prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\use Math
        \\var pos:Math.V
    ;
    const context = qualifiedCompletionContext(source, .{ .line = 1, .character = 14 }).?;
    try std.testing.expectEqualStrings("Math", context.qualifier);
    try std.testing.expectEqualStrings("V", context.prefix);
    try std.testing.expect(context.type_only);
    try std.testing.expectEqualStrings("Math", (try usedModulePath(allocator, source, context.qualifier)).?);

    const aliased_source = "use Math as Algebra\nvar pos:Algebra.V";
    const aliased = qualifiedCompletionContext(aliased_source, .{ .line = 1, .character = 17 }).?;
    try std.testing.expectEqualStrings("Algebra", aliased.qualifier);
    try std.testing.expectEqualStrings("Math", (try usedModulePath(allocator, aliased_source, aliased.qualifier)).?);

    const parent_source =
        \\use STD as Standard
        \\use Standard.Time as Time
        \\var pos:Time.S
    ;
    const parent = qualifiedCompletionContext(parent_source, .{ .line = 2, .character = 14 }).?;
    try std.testing.expectEqualStrings("Time", parent.qualifier);
    try std.testing.expectEqualStrings(
        "STD.Time",
        (try usedModulePath(allocator, parent_source, parent.qualifier)).?,
    );
}

test "module completion exposes public native functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Math", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Main.sx",
        .data = "use Math\nfunc main() {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Math/Runtime.sx",
        .data = "pub native func pow(value:int) int\nnative func native_seed() int\n",
    });

    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const absolute_root = try std.fs.path.resolve(allocator, &.{relative_root});
    const main_path = try std.fs.path.join(allocator, &.{ absolute_root, "Main.sx" });
    const uri = try std.fmt.allocPrint(allocator, "file://{s}", .{main_path});
    const items = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Math",
        .{ .qualifier = "Math", .prefix = "", .type_only = false },
        .public_api,
    );

    try std.testing.expect(containsCompletion(items, "Math.pow"));
    try std.testing.expect(!containsCompletion(items, "Math.native_seed"));
}

test "file URIs are decoded for local module discovery" {
    const path = (try filePathFromUri(std.testing.allocator, "file:///tmp/Silex%20Project/Main.sx")).?;
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/tmp/Silex Project/Main.sx", path);
}

test "module completion excludes infrastructure directories but keeps underscore directories" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "@Native/Nested");
    try temporary.dir.createDirPath(std.testing.io, "_Private/Nested");
    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    var items: std.ArrayList(CompletionItem) = .empty;
    try collectModules(allocator, std.testing.io, root, "", "", "Silex module", &items);

    try std.testing.expect(!containsCompletion(items.items, "@Native"));
    try std.testing.expect(!containsCompletion(items.items, "@Native.Nested"));
    try std.testing.expect(containsCompletion(items.items, "_Private"));
    try std.testing.expect(containsCompletion(items.items, "_Private.Nested"));
}

test "standard library modules and exports complete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const uri = "file:///Users/nekmata/Projects/Silex/Sandbox/Main.sx";
    const roots = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD");
    try std.testing.expect(containsCompletion(roots, "STD"));
    const time_modules = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD.T");
    try std.testing.expect(containsCompletion(time_modules, "STD.Time"));
    const infrastructure = try localModuleCompletionItems(allocator, std.testing.io, uri, "STD.@");
    try std.testing.expect(!containsCompletion(infrastructure, "STD.@Native"));

    const exports = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD",
        .{ .qualifier = "STD", .prefix = "R", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(exports, "STD.Randomizer"));
    try std.testing.expect(!containsCompletion(exports, "STD.Random"));

    const time_exports = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD.Time",
        .{ .qualifier = "STD.Time", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(time_exports, "STD.Time.Clock"));
    try std.testing.expect(containsCompletion(time_exports, "STD.Time.Internal"));
    try std.testing.expect(containsCompletion(time_exports, "STD.Time.Stopwatch"));

    const console_api = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD.Console",
        .{ .qualifier = "Console", .prefix = "", .type_only = false },
        .public_api,
    );
    try std.testing.expect(!containsCompletion(console_api, "Console.Console"));
    const session = findCompletion(console_api, "Console.Session").?;
    try std.testing.expectEqualStrings("Silex public structure", session.detail);

    const console_uses = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "STD.Console",
        .{ .qualifier = "STD.Console", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(console_uses, "STD.Console.Console"));
    const session_unit = findCompletion(console_uses, "STD.Console.Session").?;
    try std.testing.expectEqualStrings("Silex source unit", session_unit.detail);

    const static_source =
        \\use STD
        \\func main() {
        \\    STD.Randomizer.
        \\}
    ;
    const static_methods = try completionItems(
        allocator,
        std.testing.io,
        static_source,
        .{ .line = 2, .character = 19 },
    );
    try std.testing.expect(containsCompletion(static_methods, "create"));
    try std.testing.expect(!containsCompletion(static_methods, "system"));
    try std.testing.expect(!containsCompletion(static_methods, "get_int"));
}

test "use completion includes modules source units and public types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const uri = "file:///Users/nekmata/Projects/Silex/Repository/Toolchain/Tests/LspModules/Main.sx";

    const modules = try useCompletionItems(allocator, std.testing.io, uri, "use Geo", "Geo");
    try std.testing.expect(containsCompletion(modules, "Geometry"));

    const declarations = try useCompletionItems(allocator, std.testing.io, uri, "use Geometry.D", "Geometry.D");
    try std.testing.expect(containsCompletion(declarations, "Geometry.Direction"));
    try std.testing.expect(containsCompletion(declarations, "Geometry.DirectionName"));

    const aliases = try useCompletionItems(allocator, std.testing.io, uri, "use Geometry.V", "Geometry.V");
    try std.testing.expect(containsCompletion(aliases, "Geometry.Vec3"));
    try std.testing.expect(containsCompletion(aliases, "Geometry.Vec3i"));
}

test "member completion infers a used standard-library factory result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use STD.Randomizer as Randomizer
        \\func main() void {
        \\    var rand = Randomizer.create()
        \\    print(rand.get_)
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 3, .character = 19 },
    );
    try std.testing.expect(containsCompletion(items, "get_int"));
    try std.testing.expect(containsCompletion(items, "get_float"));
    try std.testing.expect(containsCompletion(items, "get_bool"));
    try std.testing.expect(!containsCompletion(items, "next"));
}

test "member completion infers qualified standard-library factory results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const aliased_source =
        \\use STD as Standard
        \\func main() void {
        \\    var randomizer = Standard.Randomizer.create(1)
        \\    randomizer.
        \\}
    ;
    const aliased_items = try completionItems(
        allocator,
        std.testing.io,
        aliased_source,
        .{ .line = 3, .character = 15 },
    );
    try std.testing.expect(containsCompletion(aliased_items, "get_int"));
    try std.testing.expect(containsCompletion(aliased_items, "get_float"));

    const canonical_source =
        \\use STD
        \\func main() void {
        \\    var randomizer = STD.Randomizer.create(1)
        \\    randomizer.
        \\}
    ;
    const canonical_items = try completionItems(
        allocator,
        std.testing.io,
        canonical_source,
        .{ .line = 3, .character = 15 },
    );
    try std.testing.expect(containsCompletion(canonical_items, "get_int"));
    try std.testing.expect(containsCompletion(canonical_items, "get_float"));
}

test "member completion loads local module structure fields and methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use Math
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

test "member completion keeps unique resource storage private outside its module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use Math
        \\func main() {
        \\    let resource = Math.Resource.open(7)
        \\    resource.
        \\}
    ;
    const items = try completionItemsForProject(
        arena.allocator(),
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 3, .character = 13 },
    );
    try std.testing.expect(containsCompletion(items, "get_handle"));
    try std.testing.expect(!containsCompletion(items, "handle"));
}

test "member completion gives owner extensions external storage rights" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\struct Resource {
        \\    let handle:int
        \\    func get_handle() int { return self.handle }
        \\    drop {}
        \\}
        \\extend Resource {
        \\    func inspect() {
        \\        self.
        \\    }
        \\}
    ;
    const items = try completionItems(
        arena.allocator(),
        std.testing.io,
        source,
        .{ .line = 7, .character = 13 },
    );
    try std.testing.expect(containsCompletion(items, "get_handle"));
    try std.testing.expect(!containsCompletion(items, "handle"));
}

test "member completion exposes STD Time clock methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use STD.Time as Time
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
        \\use STD
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
        \\    var speed:float = 100
        \\}
        \\func main() void {
        \\    var motion:Move
        \\    print(motion.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 17 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("speed", items[0].label);
    try std.testing.expectEqual(@as(u8, 5), items[0].kind);
}

test "member completion infers an explicit generic structure initializer" {
    const source =
        \\struct Vec3<T> {
        \\    var x:T
        \\    var y:T
        \\    var z:T
        \\    func reset() {}
        \\}
        \\func main() {
        \\    var value = Vec3<int>()
        \\    print(value.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 8, .character = 16 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "x"));
    try std.testing.expect(containsCompletion(items, "y"));
    try std.testing.expect(containsCompletion(items, "z"));
    try std.testing.expect(containsCompletion(items, "reset"));
}

test "member completion resolves a local generic type alias initializer" {
    const source =
        \\struct Vec3<T> {
        \\    var x:T
        \\    var y:T
        \\    var z:T
        \\    func reset() {}
        \\}
        \\use Vec3<int> as Vec3i
        \\func main() {
        \\    var value = Vec3i()
        \\    print(value.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 9, .character = 16 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "x"));
    try std.testing.expect(containsCompletion(items, "y"));
    try std.testing.expect(containsCompletion(items, "z"));
    try std.testing.expect(containsCompletion(items, "reset"));
}

test "member completion resolves generic and aliased type annotations" {
    const source =
        \\struct Vec3<T> {
        \\    var x:T
        \\    func reset() {}
        \\}
        \\use Vec3<int> as Vec3i
        \\func main() {
        \\    var direct:Vec3<int>
        \\    var aliased:Vec3i
        \\    print(direct.)
        \\    print(aliased.)
        \\}
    ;
    const direct_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 8, .character = 17 });
    defer std.testing.allocator.free(direct_items);
    try std.testing.expect(containsCompletion(direct_items, "x"));
    try std.testing.expect(containsCompletion(direct_items, "reset"));

    const aliased_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 9, .character = 18 });
    defer std.testing.allocator.free(aliased_items);
    try std.testing.expect(containsCompletion(aliased_items, "x"));
    try std.testing.expect(containsCompletion(aliased_items, "reset"));
}

test "member completion resolves an aliased generic structure field" {
    const source =
        \\struct Vec3<T> {
        \\    var x:T
        \\    func reset() {}
        \\}
        \\use Vec3<int> as Vec3i
        \\struct Transform {
        \\    var position:Vec3i
        \\}
        \\func main() {
        \\    var transform = Transform()
        \\    print(transform.position.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 11, .character = 29 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "x"));
    try std.testing.expect(containsCompletion(items, "reset"));
}

test "member completion resolves a public generic type alias from a module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use Geometry
        \\func main() {
        \\    var value = Geometry.Vec3i()
        \\    print(value.)
        \\}
    ;
    const items = try completionItemsForProject(
        arena.allocator(),
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 3, .character = 16 },
    );
    try std.testing.expect(containsCompletion(items, "x"));
    try std.testing.expect(containsCompletion(items, "y"));
    try std.testing.expect(containsCompletion(items, "z"));
    try std.testing.expect(containsCompletion(items, "reset"));
}

test "member completion preserves collection aliases" {
    const source =
        \\use int[] as Integers
        \\func main() {
        \\    var values:Integers
        \\    values.
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 3, .character = 11 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "append"));
    try std.testing.expect(containsCompletion(items, "reverse"));
}

test "member completion recognizes class declarations" {
    const source =
        \\class Player {
        \\    var secret:int = 1
        \\    sub var energy:int = 50
        \\    pub var health:int = 100
        \\    func reset() {}
        \\}
        \\func main() {
        \\    var player = Player()
        \\    print(player.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 8, .character = 17 });
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("health", items[0].label);
}

test "member completion separates static and instance methods" {
    const source =
        \\struct Factory {
        \\    static func create() Factory { return Factory() }
        \\    func reset() {}
        \\}
        \\func main() {
        \\    var factory = Factory()
        \\    Factory.
        \\    factory.
        \\}
    ;
    const type_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 12 });
    defer std.testing.allocator.free(type_items);
    try std.testing.expect(containsCompletion(type_items, "create"));
    try std.testing.expect(!containsCompletion(type_items, "reset"));

    const value_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 7, .character = 12 });
    defer std.testing.allocator.free(value_items);
    try std.testing.expect(!containsCompletion(value_items, "create"));
    try std.testing.expect(containsCompletion(value_items, "reset"));
}

test "member completion separates static and instance fields" {
    const source =
        \\struct State {
        \\    static var shared:int
        \\    var local:int
        \\}
        \\func main() {
        \\    State.
        \\    var state = State()
        \\    state.
        \\}
    ;
    const type_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 10 });
    defer std.testing.allocator.free(type_items);
    try std.testing.expect(containsCompletion(type_items, "shared"));
    try std.testing.expect(!containsCompletion(type_items, "local"));

    const value_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 7, .character = 10 });
    defer std.testing.allocator.free(value_items);
    try std.testing.expect(containsCompletion(value_items, "local"));
    try std.testing.expect(!containsCompletion(value_items, "shared"));
}

test "member completion recognizes generic and aliased static field receivers" {
    const source =
        \\struct Cache<T> {
        \\    static var hits:int
        \\    var value:T
        \\}
        \\use Cache<int> as IntCache
        \\func main() {
        \\    Cache<int>.
        \\    IntCache.
        \\}
    ;
    const generic_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 15 });
    defer std.testing.allocator.free(generic_items);
    try std.testing.expect(containsCompletion(generic_items, "hits"));
    try std.testing.expect(!containsCompletion(generic_items, "value"));

    const alias_items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 7, .character = 13 });
    defer std.testing.allocator.free(alias_items);
    try std.testing.expect(containsCompletion(alias_items, "hits"));
    try std.testing.expect(!containsCompletion(alias_items, "value"));
}

test "member completion recognizes generic and used static type receivers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const generic_source =
        \\struct Box<T> {
        \\    var value:T
        \\    static func filled(value:T) Box<T> { return Box<T>(value:value) }
        \\    func clear() {}
        \\}
        \\func main() { Box<int>. }
    ;
    const generic_items = try completionItems(allocator, std.testing.io, generic_source, .{ .line = 5, .character = 23 });
    try std.testing.expect(containsCompletion(generic_items, "filled"));
    try std.testing.expect(!containsCompletion(generic_items, "clear"));

    const imported_source =
        \\use Math
        \\func main() { Math.Vec2. }
    ;
    const imported_items = try completionItemsForProject(
        allocator,
        std.testing.io,
        imported_source,
        "Tests/LspModules",
        .{ .line = 1, .character = 24 },
    );
    try std.testing.expect(containsCompletion(imported_items, "zero"));
    try std.testing.expect(containsCompletion(imported_items, "creations"));
    try std.testing.expect(!containsCompletion(imported_items, "x"));
    try std.testing.expect(!containsCompletion(imported_items, "length_squared"));
}

test "enum completion inserts local variant constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\enum Direction {
        \\    north
        \\    connected(str)
        \\}
        \\func main() {
        \\    Direction.nor
        \\}
    ;
    const items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 5, .character = 17 });
    const north = findCompletion(items, "north").?;
    try std.testing.expectEqual(@as(u8, 20), north.kind);
    try std.testing.expectEqualStrings("north()", north.insertText.?);
    try std.testing.expect(north.insertTextFormat == null);
    const connected = findCompletion(items, "connected").?;
    try std.testing.expectEqualStrings("connected($0)", connected.insertText.?);
    try std.testing.expectEqual(@as(?u8, 2), connected.insertTextFormat);
    try std.testing.expectEqual(@as(usize, 2), items.len);
}

test "enum completion recognizes generic declarations and specializations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\enum Outcome<T, E> {
        \\    success(T)
        \\    failure(E)
        \\}
        \\func main() {
        \\    Outcome<int, str>.
        \\}
    ;
    const items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 5, .character = 22 });
    try std.testing.expect(containsCompletion(items, "success"));
    try std.testing.expect(containsCompletion(items, "failure"));
    try std.testing.expect(syntaxDiagnostic(arena.allocator(),
        \\enum Outcome<T, E> { success(T); failure(E) }
        \\func main() { let value = Outcome<int, str>.success(42) }
    ) == null);
}

test "Result completion distinguishes value and void success" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\enum SaveError { denied }
        \\func main() {
        \\    Result<int, SaveError>.
        \\    Result<void, SaveError>.
        \\}
    ;
    const value_items = try completionItems(allocator, std.testing.io, source, .{ .line = 2, .character = 27 });
    try std.testing.expectEqualStrings("success($0)", findCompletion(value_items, "success").?.insertText.?);
    try std.testing.expectEqualStrings("failure($0)", findCompletion(value_items, "failure").?.insertText.?);

    const void_items = try completionItems(allocator, std.testing.io, source, .{ .line = 3, .character = 28 });
    try std.testing.expectEqualStrings("success()", findCompletion(void_items, "success").?.insertText.?);
    try std.testing.expectEqualStrings("failure($0)", findCompletion(void_items, "failure").?.insertText.?);

    const global_items = try completionItems(allocator, std.testing.io, "func main() {}", null);
    try std.testing.expect(containsCompletion(global_items, "Result"));
    try std.testing.expect(containsCompletion(global_items, "map_error"));
    try std.testing.expect(syntaxDiagnostic(allocator,
        \\enum SaveError { denied }
        \\func save() Result<void, SaveError> { return Result<void, SaveError>.success() }
        \\func main() {}
    ) == null);
    try std.testing.expect(syntaxDiagnostic(allocator,
        \\enum SaveError { denied }
        \\func save() Result<void, SaveError> { return Result<void, SaveError>.success() }
        \\func save_all() Result<void, SaveError> { try save(); return Result<void, SaveError>.success() }
        \\func main() {}
    ) == null);
    try std.testing.expect(syntaxDiagnostic(allocator,
        \\func run_application() Result<void,str> { return Result<void,str>.failure("failed") }
        \\func main() Result<void,str> { try run_application(); return Result<void,str>.success() }
    ) == null);
}

test "enum instance completion exposes only declared raw values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\enum Direction { north; south }
        \\enum DirectionName:str { north = "north"; south = "south" }
        \\func main() {
        \\    let direction = Direction.north()
        \\    direction.
        \\    let name = DirectionName.north()
        \\    name.
        \\    DirectionName.north().
        \\}
    ;
    const direction_items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 4, .character = 14 });
    try std.testing.expect(!containsCompletion(direction_items, "raw_value"));
    const name_items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 6, .character = 9 });
    const raw_value = findCompletion(name_items, "raw_value").?;
    try std.testing.expectEqual(@as(u8, 10), raw_value.kind);
    const direct_items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 7, .character = 26 });
    try std.testing.expect(containsCompletion(direct_items, "raw_value"));
}

test "enum completion resolves public used types and module exports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\use Geometry
        \\use Geometry.Direction as Heading
        \\func main() {
        \\    Geometry.Direction.
        \\    Heading.
        \\}
    ;
    const items = try completionItemsForProject(
        allocator,
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 3, .character = 23 },
    );
    try std.testing.expect(containsCompletion(items, "north"));
    try std.testing.expect(containsCompletion(items, "south"));
    const alias_items = try completionItemsForProject(
        allocator,
        std.testing.io,
        source,
        "Tests/LspModules",
        .{ .line = 4, .character = 12 },
    );
    try std.testing.expect(containsCompletion(alias_items, "north"));
    try std.testing.expect(containsCompletion(alias_items, "south"));

    const exports = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        "file:///Users/nekmata/Projects/Silex/Repository/Toolchain/Tests/LspModules/Main.sx",
        "Geometry",
        .{ .qualifier = "Geometry", .prefix = "Direction", .type_only = true },
        .public_api,
    );
    try std.testing.expect(containsCompletion(exports, "Geometry.Direction"));
    try std.testing.expect(containsCompletion(exports, "Geometry.DirectionName"));
}

test "cascade completion after a static factory stays instance-only" {
    const source =
        \\class Client {
        \\    pub static func create() Client { return Client() }
        \\    pub func connect() {}
        \\}
        \\func main() {
        \\    var client = Client.create()..
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 34 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(!containsCompletion(items, "create"));
    try std.testing.expect(containsCompletion(items, "connect"));
}

test "member completion infers positional class construction and inherited methods" {
    const source =
        \\class Animal {
        \\    sub var name:str
        \\    sub init(name:str) { self.name = name }
        \\    pub func get_name() str { return self.name }
        \\}
        \\class Dog : Animal {
        \\    pub init(name:str) : super(name) {}
        \\    pub func show() {}
        \\}
        \\func main() {
        \\    var animal = Dog("Kiki")
        \\    print(animal.)
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 11, .character = 17 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "show"));
    try std.testing.expect(containsCompletion(items, "get_name"));
    try std.testing.expect(!containsCompletion(items, "name"));
}

test "self completion includes private sub and public class members" {
    const source =
        \\class Player {
        \\    var secret:int = 1
        \\    sub var energy:int = 50
        \\    pub var health:int = 100
        \\    func reset() {
        \\        print(self.)
        \\    }
        \\}
        \\func main() {}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 5, .character = 19 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "secret"));
    try std.testing.expect(containsCompletion(items, "energy"));
    try std.testing.expect(containsCompletion(items, "health"));
    try std.testing.expect(containsCompletion(items, "reset"));
}

test "self completion resolves fields and methods of the enclosing structure" {
    const source =
        \\struct Counter {
        \\    var value:int
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

test "self completion resolves the target of a local extension" {
    const source =
        \\protocol Named { func get_name() str }
        \\struct Animal {
        \\    var name:str
        \\    func show() {}
        \\}
        \\extend Animal : Named {
        \\    func get_name() str {
        \\        return self.
        \\    }
        \\    func set_name(name:str) { self.name = name }
        \\}
        \\func main() {}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 7, .character = 20 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "name"));
    try std.testing.expect(containsCompletion(items, "show"));
    try std.testing.expect(containsCompletion(items, "get_name"));
    try std.testing.expect(containsCompletion(items, "set_name"));
}

test "self completion resolves a used extension target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\use STD.Randomizer as Randomizer
        \\extend Randomizer {
        \\    func get_uint() uint {
        \\        return self.
        \\    }
        \\}
        \\func main() {}
    ;
    const items = try completionItems(arena.allocator(), std.testing.io, source, .{ .line = 3, .character = 20 });
    try std.testing.expect(containsCompletion(items, "get_int"));
    try std.testing.expect(containsCompletion(items, "get_float"));
    try std.testing.expect(containsCompletion(items, "get_bool"));
    try std.testing.expect(containsCompletion(items, "get_uint"));
}

test "self completion in an extension excludes private and sub class members" {
    const source =
        \\class Vault {
        \\    var secret:int
        \\    sub var inherited:int
        \\    pub var visible:int
        \\}
        \\extend Vault {
        \\    func inspect() {
        \\        print(self.)
        \\    }
        \\}
        \\func main() {}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 7, .character = 19 });
    defer std.testing.allocator.free(items);
    try std.testing.expect(containsCompletion(items, "visible"));
    try std.testing.expect(containsCompletion(items, "inspect"));
    try std.testing.expect(!containsCompletion(items, "secret"));
    try std.testing.expect(!containsCompletion(items, "inherited"));
}

test "signature help lists overloaded functions once each" {
    const source =
        \\func measure() int { return 1 }
        \\func measure(value:@int) int { return value }
        \\func measure(value:float) float { return value }
        \\func main() { print(measure(1)) }
    ;
    const signatures = try signatureHelpItems(std.testing.allocator, source, .{ .line = 3, .character = 29 });
    defer std.testing.allocator.free(signatures);
    defer for (signatures) |signature| std.testing.allocator.free(signature.label);
    try std.testing.expectEqual(@as(usize, 3), signatures.len);
    try std.testing.expectEqualStrings("measure()", signatures[0].label);
    try std.testing.expectEqualStrings("measure(@int)", signatures[1].label);
    try std.testing.expectEqualStrings("measure(float)", signatures[2].label);
}

test "signature help recognizes explicit generic arguments" {
    const source =
        \\func identity<T>(value:T) T { return value }
        \\func main() { print(identity<int>(42)) }
    ;
    const signatures = try signatureHelpItems(std.testing.allocator, source, .{ .line = 1, .character = 39 });
    defer std.testing.allocator.free(signatures);
    defer for (signatures) |signature| std.testing.allocator.free(signature.label);
    try std.testing.expectEqual(@as(usize, 1), signatures.len);
    try std.testing.expectEqualStrings("identity<T>(T)", signatures[0].label);
}

test "cascade completion resolves a receiver on the preceding line" {
    const source =
        \\struct Move {
        \\    var speed:float = 100
        \\}
        \\func main() void {
        \\    var motion:Move
        \\    motion
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
        \\    var speed:float = 100
        \\    func reset() void {}
        \\}
        \\func main() void {
        \\    var motion:Move
        \\    motion..reset()..
        \\}
    ;
    const items = try completionItems(std.testing.allocator, std.testing.io, source, .{ .line = 6, .character = 21 });
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
        \\use STD
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
        \\    var speed:float = 100
        \\    func stop() void {}
        \\}
        \\func main() void {
        \\    var motion = Move(speed:10)
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
