const Types = @import("Types.zig");
const std = Types.std;
const build_options = Types.build_options;
const Ast = Types.Ast;
const Formatter = Types.Formatter;
const Frontend = Types.Frontend;
const LexerModule = Types.LexerModule;
const Lint = Types.Lint;
const ModuleDiscovery = Types.ModuleDiscovery;
const ModuleManifest = Types.ModuleManifest;
const ParserModule = Types.ParserModule;
const ProjectModule = Types.ProjectModule;
const Semantic = Types.Semantic;
const Source = Types.Source;
const StandardLibrary = Types.StandardLibrary;
const SourceGraph = Types.SourceGraph;
const SymbolIndex = Types.SymbolIndex;
const Allocator = Types.Allocator;
const Io = Types.Io;
const protocol_version = Types.protocol_version;
const max_message_size = Types.max_message_size;
const completion_trigger_characters = Types.completion_trigger_characters;
const semantic_token_types = Types.semantic_token_types;
const module_analysis_directory = Types.module_analysis_directory;
const Document = Types.Document;
const ProjectState = Types.ProjectState;
const VersionStamp = Types.VersionStamp;
const ProjectAffinity = Types.ProjectAffinity;
const ModuleAnalysisProject = Types.ModuleAnalysisProject;
const CompletionItem = Types.CompletionItem;
const SignatureInformation = Types.SignatureInformation;
const SignatureParameter = Types.SignatureParameter;
const SignatureHelpResult = Types.SignatureHelpResult;
const SemanticTokenKind = Types.SemanticTokenKind;
const SemanticTokenSpan = Types.SemanticTokenSpan;
const SemanticTokens = Types.SemanticTokens;
const Location = Types.Location;
const RenameEdit = Types.RenameEdit;
const TextDocumentEdit = Types.TextDocumentEdit;
const MarkupContent = Types.MarkupContent;
const Hover = Types.Hover;
const PreparedRename = Types.PreparedRename;
const WorkspaceEdit = Types.WorkspaceEdit;
const RequestContext = Types.RequestContext;
const RenameError = Types.RenameError;
const QualifiedCompletionContext = Types.QualifiedCompletionContext;
const ModuleExportScope = Types.ModuleExportScope;
const Position = Types.Position;
const Range = Types.Range;
const PositionEncoding = Types.PositionEncoding;
const TextEdit = Types.TextEdit;
const FormattingOutcome = Types.FormattingOutcome;
const Diagnostic = Types.Diagnostic;
const Request = Types.Request;

pub fn readMessage(_: anytype, allocator: Allocator, reader: *Io.Reader) !?[]const u8 {
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

pub fn documentFromOpen(self: anytype, params: std.json.Value) ?Document {
    const text_document = self.objectMember(params, "textDocument") orelse return null;
    return .{
        .uri = self.stringMember(text_document, "uri") orelse return null,
        .text = self.stringMember(text_document, "text") orelse return null,
        .version = self.integerMember(text_document, "version") orelse 0,
    };
}

pub fn documentFromChange(self: anytype, params: std.json.Value) ?Document {
    const uri = self.textDocumentUri(params) orelse return null;
    const changes = self.objectMember(params, "contentChanges") orelse return null;
    if (changes != .array or changes.array.items.len == 0) return null;
    return .{
        .uri = uri,
        .text = self.stringMember(changes.array.items[changes.array.items.len - 1], "text") orelse return null,
        .version = self.integerMember(self.objectMember(params, "textDocument") orelse return null, "version") orelse 0,
    };
}

pub fn textDocumentUri(self: anytype, params: std.json.Value) ?[]const u8 {
    const text_document = self.objectMember(params, "textDocument") orelse return null;
    return self.stringMember(text_document, "uri");
}

pub fn completionPosition(self: anytype, params: std.json.Value) ?Position {
    const position = self.objectMember(params, "position") orelse return null;
    return .{
        .line = self.unsignedMember(position, "line") orelse return null,
        .character = self.unsignedMember(position, "character") orelse return null,
    };
}

pub fn negotiatedPositionEncoding(self: anytype, params: ?std.json.Value) PositionEncoding {
    const capabilities = self.objectMember(params orelse return .utf16, "capabilities") orelse return .utf16;
    const general = self.objectMember(capabilities, "general") orelse return .utf16;
    const encodings = self.objectMember(general, "positionEncodings") orelse return .utf16;
    if (encodings != .array) return .utf16;
    for (encodings.array.items) |encoding| {
        if (encoding != .string) continue;
        if (std.mem.eql(u8, encoding.string, "utf-8")) return .utf8;
        if (std.mem.eql(u8, encoding.string, "utf-16")) return .utf16;
        if (std.mem.eql(u8, encoding.string, "utf-32")) return .utf32;
    }
    return .utf16;
}

pub fn formattingOutcome(
    self: anytype,
    allocator: Allocator,
    source: []const u8,
    encoding: PositionEncoding,
) Formatter.FormatError!FormattingOutcome {
    const result = try Formatter.formatSource(allocator, source);
    if (result.diagnostic) |diagnostic| return .{ .diagnostic = diagnostic };
    if (std.mem.eql(u8, source, result.text)) {
        return .{ .edits = try allocator.alloc(TextEdit, 0) };
    }
    const edits = try allocator.alloc(TextEdit, 1);
    edits[0] = .{
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = self.documentEndPosition(source, encoding),
        },
        .newText = result.text,
    };
    return .{ .edits = edits };
}

pub fn objectMember(_: anytype, value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

pub fn stringMember(self: anytype, value: std.json.Value, name: []const u8) ?[]const u8 {
    const member = self.objectMember(value, name) orelse return null;
    return switch (member) {
        .string => |string| string,
        else => null,
    };
}

pub fn booleanMember(self: anytype, value: std.json.Value, name: []const u8) ?bool {
    const member = self.objectMember(value, name) orelse return null;
    return switch (member) {
        .bool => |result| result,
        else => null,
    };
}

pub fn unsignedMember(self: anytype, value: std.json.Value, name: []const u8) ?usize {
    const member = self.objectMember(value, name) orelse return null;
    if (member != .integer or member.integer < 0) return null;
    return std.math.cast(usize, member.integer);
}

pub fn integerMember(self: anytype, value: std.json.Value, name: []const u8) ?i64 {
    const member = self.objectMember(value, name) orelse return null;
    if (member != .integer) return null;
    return member.integer;
}

pub fn sourcePositionAtByteOffset(_: anytype, source: []const u8, file: usize, requested: usize) Source.Position {
    var line: usize = 1;
    var line_start: usize = 0;
    var offset: usize = 0;
    while (offset < @min(requested, source.len)) : (offset += 1) {
        if (source[offset] == '\n') {
            line += 1;
            line_start = offset + 1;
        }
    }
    return .{ .line = line, .column = requested - line_start + 1, .file = file };
}

pub fn sourceByteOffset(_: anytype, source: []const u8, position: Source.Position) usize {
    var offset: usize = 0;
    var line: usize = 1;
    while (line < position.line and offset < source.len) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return source.len;
        offset = newline + 1;
    }
    return @min(source.len, offset + position.column -| 1);
}

pub fn semanticTokenData(
    self: anytype,
    allocator: Allocator,
    index: SymbolIndex.Index,
    file: usize,
    source: []const u8,
    encoding: PositionEncoding,
) ![]const u32 {
    var spans: std.ArrayList(SemanticTokenSpan) = .empty;
    for (index.occurrences) |occurrence| {
        if (occurrence.position.file != file) continue;
        const symbol = index.symbol(occurrence.symbol);
        const start_offset = self.sourceByteOffset(source, occurrence.position);
        const end_offset = start_offset + occurrence.length;
        if (end_offset > source.len or
            !std.mem.eql(u8, source[start_offset..end_offset], symbol.name))
        {
            continue;
        }
        const start = self.encodedPositionAtByteOffset(source, start_offset, encoding) orelse continue;
        const end = self.encodedPositionAtByteOffset(source, end_offset, encoding) orelse continue;
        if (start.line != end.line or end.character <= start.character) continue;
        const kind = self.semanticTokenKind(symbol, source, end_offset) orelse continue;
        try spans.append(allocator, .{
            .position = start,
            .length = end.character - start.character,
            .kind = kind,
        });
    }
    std.mem.sort(SemanticTokenSpan, spans.items, {}, struct {
        fn lessThan(_: void, left: SemanticTokenSpan, right: SemanticTokenSpan) bool {
            if (left.position.line != right.position.line) return left.position.line < right.position.line;
            return left.position.character < right.position.character;
        }
    }.lessThan);

    var data: std.ArrayList(u32) = .empty;
    var previous_line: usize = 0;
    var previous_start: usize = 0;
    for (spans.items) |span| {
        const delta_line = span.position.line - previous_line;
        const delta_start = if (delta_line == 0)
            span.position.character - previous_start
        else
            span.position.character;
        try data.appendSlice(allocator, &.{
            @intCast(delta_line),
            @intCast(delta_start),
            @intCast(span.length),
            @intFromEnum(span.kind),
            0,
        });
        previous_line = span.position.line;
        previous_start = span.position.character;
    }
    return data.toOwnedSlice(allocator);
}

pub fn semanticTokenKind(
    self: anytype,
    symbol: SymbolIndex.Symbol,
    source: []const u8,
    end_offset: usize,
) ?SemanticTokenKind {
    const kind = if (symbol.kind == .alias) symbol.alias_target_kind orelse return null else symbol.kind;
    if (self.followedByInvocation(source, end_offset)) return switch (kind) {
        .method, .requirement => if (symbol.is_static) .function else .method,
        else => .function,
    };
    return switch (kind) {
        .module => .namespace,
        .type, .enumeration, .protocol, .type_parameter => .type,
        .variant => .enum_member,
        .constructor, .function => .function,
        .requirement => .method,
        .method => if (symbol.is_static) .function else .method,
        .field => .property,
        .parameter => .parameter,
        .variable, .binding => .variable,
        .alias => unreachable,
    };
}

pub fn followedByInvocation(_: anytype, source: []const u8, end_offset: usize) bool {
    var offset = end_offset;
    while (offset < source.len and std.ascii.isWhitespace(source[offset])) offset += 1;
    return offset < source.len and source[offset] == '(';
}

pub fn pathWithin(_: anytype, path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    return path.len > root.len and std.mem.startsWith(u8, path, root) and path[root.len] == std.fs.path.sep;
}

pub fn uriFromPath(_: anytype, allocator: Allocator, path: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, "file://");
    const hex = "0123456789ABCDEF";
    for (path) |character| {
        if (std.ascii.isAlphanumeric(character) or character == '/' or character == '-' or
            character == '_' or character == '.' or character == '~')
        {
            try result.append(allocator, character);
        } else {
            try result.append(allocator, '%');
            try result.append(allocator, hex[character >> 4]);
            try result.append(allocator, hex[character & 0x0f]);
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn manifestDeclares(self: anytype, allocator: Allocator, io: Io, manifest_path: []const u8, document_path: []const u8) !bool {
    const contents = Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024)) catch return false;
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, contents, .{}) catch return false;
    const target = self.stringMember(parsed, "target") orelse return false;
    _ = target;
    const modules = self.objectMember(parsed, "modules") orelse return false;
    if (modules != .array) return false;
    const root = std.fs.path.dirname(manifest_path) orelse ".";
    for (modules.array.items) |module| {
        const sources = self.objectMember(module, "sources") orelse continue;
        if (sources != .array) continue;
        for (sources.array.items) |source| {
            if (source != .string) continue;
            const joined = try std.fs.path.join(allocator, &.{ root, source.string });
            const canonical = SourceGraph.canonicalPath(allocator, io, joined) catch continue;
            if (std.mem.eql(u8, canonical, document_path)) return true;
        }
    }
    return false;
}

pub fn moduleAnalysisInput(_: anytype, path: []const u8) bool {
    if (!std.mem.endsWith(u8, std.fs.path.basename(path), ".sx")) return false;
    const directory = std.fs.path.dirname(path) orelse return false;
    return std.mem.eql(u8, std.fs.path.basename(directory), module_analysis_directory);
}

pub fn singleSourceRootForDocument(self: anytype, input_path: []const u8, document_path: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, input_path, ".sx") or self.moduleAnalysisInput(input_path)) return null;
    if (std.mem.eql(u8, input_path, document_path)) return null;
    const root = std.fs.path.dirname(input_path) orelse return null;
    return if (self.pathWithin(document_path, root)) root else null;
}

pub fn sourceDefinesMain(_: anytype, allocator: Allocator, source: []const u8) bool {
    var parser = ParserModule.Parser.init(allocator, source);
    const program = parser.parse() catch return false;
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, "main")) return true;
    }
    return false;
}

pub fn moduleNameFromSource(
    self: anytype,
    allocator: Allocator,
    root: []const u8,
    source_path: []const u8,
) !?[]const u8 {
    if (!std.mem.endsWith(u8, source_path, ".sx")) return null;
    const directory = std.fs.path.dirname(source_path) orelse return null;
    const parent = try self.moduleNameFromDirectories(allocator, root, directory) orelse return null;
    const filename = std.fs.path.basename(source_path);
    const stem = filename[0 .. filename.len - ".sx".len];
    if (!ModuleDiscovery.isModuleName(stem)) return null;
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, stem });
}

pub fn moduleNameFromDirectories(
    _: anytype,
    allocator: Allocator,
    root: []const u8,
    module_directory: []const u8,
) !?[]const u8 {
    const relative = try std.fs.path.relative(allocator, ".", null, root, module_directory);
    if (relative.len == 0 or std.mem.startsWith(u8, relative, "..")) return null;
    for (relative) |*character| {
        if (character.* == '/' or character.* == '\\') character.* = '.';
    }
    if (!ModuleDiscovery.isModuleName(relative)) return null;
    return relative;
}

pub fn validIdentifier(_: anytype, name: []const u8) bool {
    if (name.len == 0) return false;
    var lexer = LexerModule.Lexer.init(name);
    const token = lexer.next() catch return false;
    if (token.tag != .identifier or token.start != 0 or token.end != name.len) return false;
    const end = lexer.next() catch return false;
    return end.tag == .end;
}

pub fn canonicalRename(_: anytype, kind: SymbolIndex.Kind, name: []const u8) bool {
    return switch (kind) {
        .type, .enumeration, .protocol, .type_parameter => std.ascii.isUpper(name[0]),
        .variant, .alias, .module => true,
        else => std.ascii.isLower(name[0]) or name[0] == '_',
    };
}

pub fn renameErrorMessage(_: anytype, err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidPosition => "rename requires a resolved Silex symbol in the current snapshot",
        error.NotRenamable => "this Silex symbol cannot be renamed",
        error.InvalidName => "the new name must be a different non-keyword Silex identifier",
        error.NonCanonicalName => "the new name does not use the canonical casing for this symbol",
        error.Collision => "the new name collides with another visible declaration",
        error.ExternalSource => "the complete rename group is not editable in this workspace",
        error.ValidationFailed => "the renamed project does not preserve a valid semantic symbol group",
        else => "rename validation failed",
    };
}

pub fn snapshotFile(_: anytype, snapshot: *const Frontend.Snapshot, path: []const u8) ?usize {
    for (snapshot.source_paths, 0..) |candidate, index| if (std.mem.eql(u8, candidate, path)) return index;
    return null;
}

pub fn projectContainsPath(self: anytype, project: *const ProjectState, path: []const u8) bool {
    if (project.current) |snapshot| if (self.snapshotFile(&snapshot, path) != null) return true;
    if (project.failure) |failure| for (failure.source_paths) |candidate| {
        if (std.mem.eql(u8, candidate, path)) return true;
    };
    if (project.last_success) |snapshot| if (self.snapshotFile(&snapshot, path) != null) return true;
    return false;
}

pub fn positionAfter(_: anytype, left: Source.Position, right: Source.Position) bool {
    if (left.line != right.line) return left.line > right.line;
    return left.column > right.column;
}

pub fn completionItemForSymbol(_: anytype, symbol: SymbolIndex.Symbol) CompletionItem {
    const kind: u8 = switch (symbol.kind) {
        .module => 9,
        .alias, .type, .type_parameter => 7,
        .enumeration => 13,
        .variant => 20,
        .protocol => 8,
        .field => 5,
        .constructor => 4,
        .function, .method, .requirement => 3,
        .parameter, .variable, .binding => 6,
    };
    return .{ .label = symbol.name, .kind = kind, .detail = symbol.detail };
}

pub fn detailTypeName(_: anytype, detail: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, detail, ':') orelse return null;
    var value = std.mem.trim(u8, detail[separator + 1 ..], " @&");
    const generic = std.mem.indexOfScalar(u8, value, '<') orelse value.len;
    const collection = std.mem.indexOfScalar(u8, value, '[') orelse value.len;
    const optional = std.mem.indexOfScalar(u8, value, '?') orelse value.len;
    value = value[0..@min(generic, @min(collection, optional))];
    return if (value.len == 0) null else value;
}

pub fn blankLineAt(_: anytype, allocator: Allocator, source: []const u8, cursor: usize) ![]const u8 {
    const bounded_cursor = @min(cursor, source.len);
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..bounded_cursor], '\n')) |newline|
        newline + 1
    else
        0;
    const line_end = std.mem.indexOfScalarPos(u8, source, bounded_cursor, '\n') orelse source.len;
    const repaired = try allocator.dupe(u8, source);
    for (repaired[line_start..line_end]) |*character| {
        if (character.* != '\r' and character.* != '\t') character.* = ' ';
    }
    return repaired;
}

pub fn fallbackCompletionReceiver(
    self: anytype,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    start: usize,
    end: usize,
) ?SymbolIndex.Symbol {
    const callable = self.callableNameAt(source, start) orelse return null;
    const receiver_name = source[start..end];
    var matched: ?SymbolIndex.Symbol = null;
    for (snapshot.index.symbols) |symbol| {
        if ((symbol.kind != .parameter and symbol.kind != .variable and symbol.kind != .binding) or
            symbol.definition.file != file or !std.mem.eql(u8, symbol.name, receiver_name))
        {
            continue;
        }
        const snapshot_source = snapshot.source_contents[file];
        const definition_offset = self.sourceByteOffset(snapshot_source, symbol.definition);
        const symbol_callable = self.callableNameAt(snapshot_source, definition_offset) orelse continue;
        if (!std.mem.eql(u8, symbol_callable, callable)) continue;
        if (matched != null) return null;
        matched = symbol;
    }
    return matched;
}

pub fn callableNameAt(_: anytype, source: []const u8, byte_offset: usize) ?[]const u8 {
    var lexer = LexerModule.Lexer.init(source);
    var depth: usize = 0;
    var active_name: ?[]const u8 = null;
    var active_depth: usize = 0;
    var pending_name: ?[]const u8 = null;
    var expects_name = false;
    while (true) {
        const token = lexer.next() catch return null;
        if (token.tag == .end or token.start >= byte_offset) break;
        switch (token.tag) {
            .keyword_func => {
                expects_name = true;
                pending_name = null;
            },
            .identifier => if (expects_name) {
                pending_name = token.lexeme;
                expects_name = false;
            },
            .left_brace => {
                depth += 1;
                if (pending_name) |name| {
                    active_name = name;
                    active_depth = depth;
                    pending_name = null;
                }
                expects_name = false;
            },
            .right_brace => {
                if (active_name != null and active_depth == depth) active_name = null;
                depth -|= 1;
                expects_name = false;
            },
            .left_parenthesis => expects_name = false,
            else => {},
        }
    }
    return active_name orelse pending_name;
}

pub fn signatureParameters(self: anytype, allocator: Allocator, label: []const u8) ![]const SignatureParameter {
    const opening = std.mem.indexOfScalar(u8, label, '(') orelse return allocator.alloc(SignatureParameter, 0);
    var result: std.ArrayList(SignatureParameter) = .empty;
    var start = opening + 1;
    var index = start;
    var depth: usize = 0;
    while (index < label.len) : (index += 1) {
        switch (label[index]) {
            '<', '[', '(' => depth += 1,
            '>', ']' => depth -|= 1,
            ')' => {
                if (depth == 0) {
                    try self.appendSignatureParameter(allocator, &result, label, start, index);
                    break;
                }
                depth -= 1;
            },
            ',' => if (depth == 0) {
                try self.appendSignatureParameter(allocator, &result, label, start, index);
                start = index + 1;
            },
            else => {},
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn appendSignatureParameter(
    _: anytype,
    allocator: Allocator,
    result: *std.ArrayList(SignatureParameter),
    label: []const u8,
    raw_start: usize,
    raw_end: usize,
) !void {
    var start = raw_start;
    var end = raw_end;
    while (start < end and std.ascii.isWhitespace(label[start])) start += 1;
    while (end > start and std.ascii.isWhitespace(label[end - 1])) end -= 1;
    if (start != end) try result.append(allocator, .{ .label = .{ start, end } });
}

pub fn activeParameterAt(_: anytype, source: []const u8, cursor: usize) usize {
    var opening: ?usize = null;
    var index = @min(cursor, source.len);
    var depth: usize = 0;
    while (index > 0) {
        index -= 1;
        switch (source[index]) {
            ')' => depth += 1,
            '(' => {
                if (depth == 0) {
                    opening = index;
                    break;
                }
                depth -= 1;
            },
            else => {},
        }
    }
    var parameter: usize = 0;
    var nested: usize = 0;
    index = (opening orelse return 0) + 1;
    while (index < @min(cursor, source.len)) : (index += 1) switch (source[index]) {
        '(', '[', '{', '<' => nested += 1,
        ')', ']', '}', '>' => nested -|= 1,
        ',' => if (nested == 0) {
            parameter += 1;
        },
        else => {},
    };
    return parameter;
}
