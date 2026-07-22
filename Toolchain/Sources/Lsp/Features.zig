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

pub const RenameSpan = struct { start: usize, end: usize };

pub fn renamedSource(
    self: anytype,
    allocator: Allocator,
    source: []const u8,
    file: usize,
    index: SymbolIndex.Index,
    rename_group: usize,
    new_name: []const u8,
) ![]const u8 {
    var spans: std.ArrayList(RenameSpan) = .empty;
    for (index.occurrences) |occurrence| {
        if (index.symbol(occurrence.symbol).rename_group != rename_group or occurrence.position.file != file) continue;
        const start = self.sourceByteOffset(source, occurrence.position);
        try spans.append(allocator, .{ .start = start, .end = @min(source.len, start + occurrence.length) });
    }
    std.mem.sort(RenameSpan, spans.items, {}, struct {
        fn lessThan(_: void, left: RenameSpan, right: RenameSpan) bool {
            return left.start < right.start;
        }
    }.lessThan);
    var output: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    for (spans.items) |span| {
        if (span.start < offset) continue;
        try output.appendSlice(allocator, source[offset..span.start]);
        try output.appendSlice(allocator, new_name);
        offset = span.end;
    }
    try output.appendSlice(allocator, source[offset..]);
    return output.toOwnedSlice(allocator);
}

pub fn renameGroupHasKind(_: anytype, index: SymbolIndex.Index, rename_group: usize, kind: SymbolIndex.Kind) bool {
    for (index.symbols) |symbol| {
        if (symbol.rename_group == rename_group and symbol.kind == kind) return true;
    }
    return false;
}

pub fn syntaxDiagnostic(self: anytype, allocator: Allocator, source: []const u8) ?Diagnostic {
    return self.syntaxDiagnosticWithEncoding(allocator, source, .utf16);
}

pub fn syntaxDiagnosticWithEncoding(
    self: anytype,
    allocator: Allocator,
    source: []const u8,
    encoding: PositionEncoding,
) ?Diagnostic {
    var parser = ParserModule.Parser.init(allocator, source);
    _ = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return self.diagnosticFromSource(source, parser.diagnostic.?, encoding),
        else => return null,
    };
    return null;
}

pub fn diagnosticsWithEncoding(
    self: anytype,
    allocator: Allocator,
    source: []const u8,
    encoding: PositionEncoding,
) ![]const Diagnostic {
    var parser = ParserModule.Parser.init(allocator, source);
    const program = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return allocator.dupe(Diagnostic, &.{
            self.diagnosticFromSource(source, parser.diagnostic.?, encoding),
        }),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const lint_diagnostics = try Lint.analyze(allocator, program);
    const diagnostics = try allocator.alloc(Diagnostic, lint_diagnostics.len);
    for (lint_diagnostics, diagnostics) |lint_diagnostic, *diagnostic| {
        const byte_offset = self.sourceDiagnosticByteOffset(source, lint_diagnostic.position);
        const position = self.encodedPositionAtByteOffset(source, byte_offset, encoding) orelse Position{
            .line = lint_diagnostic.position.line -| 1,
            .character = lint_diagnostic.position.column -| 1,
        };
        diagnostic.* = .{
            .range = .{
                .start = position,
                .end = .{ .line = position.line, .character = position.character + 1 },
            },
            .severity = 2,
            .source = lint_diagnostic.source,
            .code = lint_diagnostic.code,
            .message = lint_diagnostic.message,
        };
    }
    return diagnostics;
}

pub fn diagnosticFromSource(
    self: anytype,
    source: []const u8,
    diagnostic: Source.Diagnostic,
    encoding: PositionEncoding,
) Diagnostic {
    const byte_offset = self.sourceDiagnosticByteOffset(source, diagnostic.position);
    const position = self.encodedPositionAtByteOffset(source, byte_offset, encoding) orelse Position{
        .line = diagnostic.position.line -| 1,
        .character = diagnostic.position.column -| 1,
    };
    return .{
        .range = .{
            .start = position,
            .end = .{ .line = position.line, .character = position.character + 1 },
        },
        .message = diagnostic.message,
    };
}

pub fn sourceDiagnosticByteOffset(_: anytype, source: []const u8, position: Source.Position) usize {
    var offset: usize = 0;
    var line: usize = 1;
    while (line < position.line and offset < source.len) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return source.len;
        offset = newline + 1;
    }
    return @min(source.len, offset + position.column -| 1);
}

pub const SignatureCallee = struct { name: []const u8, start: usize };

pub const NamedArgumentContext = struct {
    supplied: []const []const u8,
    current_has_colon: bool,
    current_is_value: bool,
};

pub fn enclosingParenthesisAt(_: anytype, allocator: Allocator, source: []const u8, cursor: usize) !?usize {
    var openings: std.ArrayList(usize) = .empty;
    var lexer = LexerModule.Lexer.init(source);
    while (true) {
        const token = lexer.next() catch return null;
        if (token.tag == .end or token.start >= @min(cursor, source.len)) break;
        switch (token.tag) {
            .left_parenthesis => try openings.append(allocator, token.start),
            .right_parenthesis => {
                if (openings.items.len != 0) _ = openings.pop();
            },
            else => {},
        }
    }
    return if (openings.items.len == 0) null else openings.items[openings.items.len - 1];
}

pub fn namedArgumentContext(
    _: anytype,
    allocator: Allocator,
    source: []const u8,
    arguments_start: usize,
    cursor: usize,
) !?NamedArgumentContext {
    if (arguments_start > cursor or cursor > source.len) return null;
    var supplied: std.ArrayList([]const u8) = .empty;
    var lexer = LexerModule.Lexer.init(source[arguments_start..cursor]);
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var current_name: ?[]const u8 = null;
    var current_has_colon = false;
    var current_is_value = false;
    while (true) {
        const token = lexer.next() catch return null;
        if (token.tag == .end) break;
        const top_level = parentheses == 0 and brackets == 0 and braces == 0;
        if (top_level) switch (token.tag) {
            .identifier => {
                if (current_name == null and !current_has_colon and !current_is_value)
                    current_name = token.lexeme
                else if (!current_has_colon)
                    current_is_value = true;
            },
            .colon => {
                if (current_name) |name| {
                    try supplied.append(allocator, name);
                    current_has_colon = true;
                    current_is_value = false;
                } else {
                    current_is_value = true;
                }
            },
            .comma => {
                current_name = null;
                current_has_colon = false;
                current_is_value = false;
            },
            .left_parenthesis => {
                current_is_value = true;
                parentheses += 1;
                continue;
            },
            .left_bracket => {
                current_is_value = true;
                brackets += 1;
                continue;
            },
            .left_brace => {
                current_is_value = true;
                braces += 1;
                continue;
            },
            else => if (!current_has_colon) {
                current_is_value = true;
            },
        };
        switch (token.tag) {
            .left_parenthesis => parentheses += 1,
            .right_parenthesis => parentheses -|= 1,
            .left_bracket => brackets += 1,
            .right_bracket => brackets -|= 1,
            .left_brace => braces += 1,
            .right_brace => braces -|= 1,
            else => {},
        }
    }
    return .{
        .supplied = try supplied.toOwnedSlice(allocator),
        .current_has_colon = current_has_colon,
        .current_is_value = current_is_value,
    };
}

pub fn initializerTypeSymbol(
    self: anytype,
    allocator: Allocator,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    callee: SignatureCallee,
) !?SymbolIndex.Symbol {
    const position = self.sourcePositionAtByteOffset(source, file, callee.start);
    if (snapshot.index.occurrenceAt(file, position.line, position.column)) |occurrence| {
        const symbol = snapshot.index.symbol(occurrence.symbol);
        if (symbol.kind == .type and std.mem.eql(u8, symbol.name, callee.name) and
            self.symbolVisibleFromFile(snapshot, file, symbol))
        {
            return symbol;
        }
    }

    const qualifier = self.calleeQualifierAt(source, callee.start);
    const module_path = if (qualifier) |value|
        try self.usedModulePath(allocator, source, value) orelse value
    else
        null;
    var matched: ?SymbolIndex.Symbol = null;
    for (snapshot.index.symbols) |symbol| {
        if (symbol.kind != .type or !std.mem.eql(u8, symbol.name, callee.name) or
            !self.symbolVisibleFromFile(snapshot, file, symbol))
        {
            continue;
        }
        if (module_path) |module| {
            if (!std.mem.eql(u8, symbol.module_name, module) and
                !self.principalModuleMatches(symbol.module_name, module, callee.name))
            {
                continue;
            }
        }
        if (matched != null and !std.mem.eql(u8, matched.?.key, symbol.key)) return null;
        matched = symbol;
    }
    return matched;
}

pub fn calleeQualifierAt(self: anytype, source: []const u8, callee_start: usize) ?[]const u8 {
    var end = @min(callee_start, source.len);
    while (end > 0 and std.ascii.isWhitespace(source[end - 1])) end -= 1;
    if (end == 0 or source[end - 1] != '.') return null;
    const qualifier_end = end - 1;
    var start = qualifier_end;
    while (start > 0 and (self.isIdentifierContinue(source[start - 1]) or source[start - 1] == '.')) start -= 1;
    return if (start == qualifier_end) null else source[start..qualifier_end];
}

pub fn principalModuleMatches(_: anytype, module_name: []const u8, qualifier: []const u8, type_name: []const u8) bool {
    return module_name.len == qualifier.len + 1 + type_name.len and
        std.mem.startsWith(u8, module_name, qualifier) and module_name[qualifier.len] == '.' and
        std.mem.eql(u8, module_name[qualifier.len + 1 ..], type_name);
}

pub fn containsName(_: anytype, names: []const []const u8, expected: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, expected)) return true;
    return false;
}

pub fn completionInsideOwnerCallable(
    self: anytype,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    cursor: usize,
    owner: []const u8,
) bool {
    const callable = self.callableNameAt(source, cursor) orelse return false;
    for (snapshot.index.symbols) |symbol| {
        if (symbol.kind == .method and symbol.definition.file == file and
            std.mem.eql(u8, symbol.owner, owner) and std.mem.eql(u8, symbol.name, callable))
        {
            return true;
        }
    }
    return false;
}

pub fn signatureCalleeAt(self: anytype, source: []const u8, cursor: usize) ?SignatureCallee {
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
    while (index > 0 and self.isIdentifierContinue(source[index - 1])) index -= 1;
    return if (index == end) null else .{ .name = source[index..end], .start = index };
}

pub fn symbolVisibleFromFile(_: anytype, snapshot: *const Frontend.Snapshot, file: usize, symbol: SymbolIndex.Symbol) bool {
    if (symbol.definition.file == file) return true;
    if (file >= snapshot.files.len or symbol.definition.file >= snapshot.files.len) return false;
    const source_module = snapshot.files[file].module_index;
    const symbol_module = snapshot.files[symbol.definition.file].module_index;
    if (source_module == symbol_module) return true;
    const exported = if (symbol.visibility) |visibility| visibility == .public_access else symbol.is_public;
    if (!exported) return false;
    for (snapshot.files[file].activated_files) |activated| {
        if (activated == symbol.definition.file) return true;
    }
    return false;
}

pub fn useCompletionPrefix(self: anytype, source: []const u8, position: Position) ?[]const u8 {
    const cursor_offset = self.byteOffsetAtPosition(source, position) orelse return null;
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
        if (!self.isIdentifierContinue(character) and character != '.') return null;
    }
    return prefix;
}

pub const VisibleModule = struct {
    qualifier: []const u8,
    module_path: []const u8,
};

pub fn usedModulePath(self: anytype, allocator: Allocator, source: []const u8, qualifier: []const u8) !?[]const u8 {
    var modules: std.ArrayList(VisibleModule) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |source_line| {
        const line = std.mem.trim(u8, source_line, " \t\r");
        const declaration = self.directiveBody(line, "use") orelse continue;
        const module_end = std.mem.indexOfAny(u8, declaration, " \t\r") orelse declaration.len;
        const path = declaration[0..module_end];
        if (path.len == 0) continue;
        if (self.looksLikeTypeAliasTarget(path)) continue;

        const remainder = std.mem.trimStart(u8, declaration[module_end..], " \t");
        const visible_qualifier = if (std.mem.startsWith(u8, remainder, "as "))
            std.mem.trim(u8, remainder["as ".len..], " \t\r")
        else
            self.lastPathSegment(path);
        const module_path = try self.expandVisibleModulePath(allocator, modules.items, path) orelse path;
        try modules.append(allocator, .{ .qualifier = visible_qualifier, .module_path = module_path });
    }
    return self.expandVisibleModulePath(allocator, modules.items, qualifier);
}

pub fn directiveBody(_: anytype, line: []const u8, keyword: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, keyword) or line.len == keyword.len or
        !std.ascii.isWhitespace(line[keyword.len])) return null;
    return std.mem.trimStart(u8, line[keyword.len..], " \t");
}

pub fn looksLikeTypeAliasTarget(_: anytype, path: []const u8) bool {
    if (std.mem.indexOfAny(u8, path, "<[]?()") != null) return true;
    const builtins = [_][]const u8{
        "int",   "int8",    "int16",   "int32",  "int64",
        "uint",  "uint8",   "uint16",  "uint32", "uint64",
        "float", "float32", "float64", "bool",   "str",
    };
    for (builtins) |builtin_name| if (std.mem.eql(u8, path, builtin_name)) return true;
    return false;
}

pub fn expandVisibleModulePath(
    self: anytype,
    allocator: Allocator,
    modules: []const VisibleModule,
    path: []const u8,
) !?[]const u8 {
    var matched: ?VisibleModule = null;
    for (modules) |module| {
        if (!std.mem.eql(u8, path, module.qualifier) and !self.pathHasModuleQualifier(path, module.qualifier)) continue;
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

pub fn pathHasModuleQualifier(_: anytype, path: []const u8, qualifier: []const u8) bool {
    return path.len > qualifier.len and std.mem.startsWith(u8, path, qualifier) and
        path[qualifier.len] == '.';
}

pub fn qualifiedCompletionPrefix(self: anytype, source: []const u8, cursor: usize) ?QualifiedCompletionContext {
    var prefix_start = @min(cursor, source.len);
    while (prefix_start > 0 and self.isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return null;
    const qualifier_end = prefix_start - 1;
    var qualifier_start = qualifier_end;
    while (qualifier_start > 0) {
        const character = source[qualifier_start - 1];
        if (!self.isIdentifierContinue(character) and character != '.') break;
        qualifier_start -= 1;
    }
    const qualifier = source[qualifier_start..qualifier_end];
    if (!ModuleDiscovery.isModuleName(qualifier)) return null;
    return .{
        .qualifier = qualifier,
        .prefix = source[prefix_start..@min(cursor, source.len)],
        .type_only = false,
    };
}
