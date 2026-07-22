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

pub fn lastPathSegment(_: anytype, path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[separator + 1 ..];
}

pub fn firstPathSegment(_: anytype, path: []const u8) []const u8 {
    const separator = std.mem.indexOfScalar(u8, path, '.') orelse return path;
    return path[0..separator];
}

pub fn moduleExportCompletionItems(
    self: anytype,
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    module_path: []const u8,
    context: QualifiedCompletionContext,
    scope: ModuleExportScope,
) ![]const CompletionItem {
    const source_path = try self.filePathFromUri(allocator, uri) orelse
        return try allocator.alloc(CompletionItem, 0);
    const project_root = std.fs.path.dirname(source_path) orelse
        return try allocator.alloc(CompletionItem, 0);
    const module_root = try self.moduleCompletionRoot(allocator, io, project_root, module_path) orelse
        return try allocator.alloc(CompletionItem, 0);
    var items: std.ArrayList(CompletionItem) = .empty;
    const module_directory = try self.moduleDirectoryPath(allocator, module_root, module_path);
    if (scope == .use_path or scope == .qualified_expression) {
        var directory = Io.Dir.cwd().openDir(io, module_directory, .{ .iterate = true }) catch null;
        if (directory) |*opened| {
            defer opened.close(io);
            var iterator = opened.iterateAssumeFirstIteration();
            while (iterator.next(io) catch null) |entry| {
                const child_name = if (entry.kind == .directory and ModuleDiscovery.isDirectoryName(entry.name))
                    entry.name
                else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) block: {
                    const stem = entry.name[0 .. entry.name.len - ".sx".len];
                    if (!ModuleDiscovery.isModuleName(stem)) continue;
                    break :block self.firstPathSegment(stem);
                } else continue;
                if (!std.mem.startsWith(u8, child_name, context.prefix)) continue;
                if (scope == .qualified_expression) {
                    const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_path, child_name });
                    if (!try self.namespaceHasPublicApiOrChildren(allocator, io, module_root, child_path)) continue;
                }
                try self.appendModuleExportCompletion(
                    allocator,
                    &items,
                    context.qualifier,
                    child_name,
                    9,
                    "Silex child namespace",
                );
            }
        }
        try self.appendCompactChildCompletions(
            allocator,
            io,
            module_root,
            module_path,
            context,
            scope,
            &items,
        );
    }

    const module_sources = try self.namespaceSourcePaths(allocator, io, module_root, module_path);
    for (module_sources) |module_source_path| {
        const module_source = Io.Dir.cwd().readFileAlloc(
            io,
            module_source_path,
            allocator,
            .limited(max_message_size),
        ) catch continue;
        var parser = ParserModule.Parser.init(allocator, module_source);
        const program = parser.parse() catch continue;

        for (program.structures) |structure| {
            if (std.mem.eql(u8, structure.name, self.lastPathSegment(module_path))) continue;
            if (!structure.is_public or !std.mem.startsWith(u8, structure.name, context.prefix)) continue;
            try self.appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                structure.name,
                22,
                "Silex public structure",
            );
        }
        for (program.enums) |enumeration| {
            if (std.mem.eql(u8, enumeration.name, self.lastPathSegment(module_path))) continue;
            if (!enumeration.is_public or !std.mem.startsWith(u8, enumeration.name, context.prefix)) continue;
            try self.appendModuleExportCompletion(
                allocator,
                &items,
                context.qualifier,
                enumeration.name,
                13,
                "Silex public enum",
            );
        }
        for (program.protocols) |protocol| {
            if (std.mem.eql(u8, protocol.name, self.lastPathSegment(module_path))) continue;
            if (!protocol.is_public or !std.mem.startsWith(u8, protocol.name, context.prefix)) continue;
            try self.appendModuleExportCompletion(
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
            try self.appendModuleExportCompletion(
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
                if (std.mem.eql(u8, function.name, self.lastPathSegment(module_path))) continue;
                if (!function.is_public or !std.mem.startsWith(u8, function.name, context.prefix)) continue;
                try self.appendModuleExportCompletion(
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

pub fn moduleCompletionRoot(
    self: anytype,
    allocator: Allocator,
    io: Io,
    project_root: []const u8,
    module_path: []const u8,
) !?[]const u8 {
    const library_root = StandardLibrary.root(allocator, io) catch {
        return if (StandardLibrary.isReservedModule(module_path)) null else project_root;
    };
    if (StandardLibrary.isReservedModule(module_path)) return library_root;

    if (try self.lspNamespaceExists(allocator, io, project_root, module_path)) return project_root;
    if (try self.lspNamespaceExists(allocator, io, library_root, module_path)) return library_root;
    return project_root;
}

pub fn completionNamespaceExists(
    self: anytype,
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    module_path: []const u8,
) !bool {
    const source_path = try self.filePathFromUri(allocator, uri) orelse return false;
    const project_root = std.fs.path.dirname(source_path) orelse return false;
    const root = try self.moduleCompletionRoot(allocator, io, project_root, module_path) orelse return false;
    return self.lspNamespaceExists(allocator, io, root, module_path);
}

pub fn lspNamespaceExists(self: anytype, allocator: Allocator, io: Io, root: []const u8, module_path: []const u8) !bool {
    const directory = try self.moduleDirectoryPath(allocator, root, module_path);
    if (try self.lspDirectoryExists(io, directory)) return true;
    if ((try self.namespaceSourcePaths(allocator, io, root, module_path)).len != 0) return true;
    return self.lspCompactDescendantExists(allocator, io, root, module_path);
}

pub fn lspCompactDescendantExists(self: anytype, allocator: Allocator, io: Io, root: []const u8, module_path: []const u8) !bool {
    var stem_start: usize = 0;
    while (true) {
        const prefix = if (stem_start == 0) "" else module_path[0 .. stem_start - 1];
        const stem = module_path[stem_start..];
        const physical_parent = if (prefix.len == 0) root else try self.moduleDirectoryPath(allocator, root, prefix);
        var directory = Io.Dir.cwd().openDir(io, physical_parent, .{ .iterate = true }) catch null;
        if (directory) |*opened| {
            defer opened.close(io);
            var iterator = opened.iterateAssumeFirstIteration();
            while (iterator.next(io) catch null) |entry| {
                if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
                const source_stem = entry.name[0 .. entry.name.len - ".sx".len];
                if (source_stem.len > stem.len and std.mem.startsWith(u8, source_stem, stem) and source_stem[stem.len] == '.') {
                    return true;
                }
            }
        }
        const separator = std.mem.indexOfScalarPos(u8, module_path, stem_start, '.') orelse break;
        stem_start = separator + 1;
    }
    return false;
}

pub fn appendCompactChildCompletions(
    self: anytype,
    allocator: Allocator,
    io: Io,
    root: []const u8,
    module_path: []const u8,
    context: QualifiedCompletionContext,
    scope: ModuleExportScope,
    items: *std.ArrayList(CompletionItem),
) !void {
    var stem_start: usize = 0;
    while (true) {
        const prefix = if (stem_start == 0) "" else module_path[0 .. stem_start - 1];
        const stem = module_path[stem_start..];
        const physical_parent = if (prefix.len == 0) root else try self.moduleDirectoryPath(allocator, root, prefix);
        var directory = Io.Dir.cwd().openDir(io, physical_parent, .{ .iterate = true }) catch null;
        if (directory) |*opened| {
            defer opened.close(io);
            var iterator = opened.iterateAssumeFirstIteration();
            while (iterator.next(io) catch null) |entry| {
                if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
                const source_stem = entry.name[0 .. entry.name.len - ".sx".len];
                if (source_stem.len <= stem.len or !std.mem.startsWith(u8, source_stem, stem) or source_stem[stem.len] != '.') continue;
                const child_name = self.firstPathSegment(source_stem[stem.len + 1 ..]);
                if (!std.mem.startsWith(u8, child_name, context.prefix)) continue;
                if (scope == .qualified_expression) {
                    const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_path, child_name });
                    if (!try self.namespaceHasPublicApiOrChildren(allocator, io, root, child_path)) continue;
                }
                try self.appendModuleExportCompletion(
                    allocator,
                    items,
                    context.qualifier,
                    child_name,
                    9,
                    "Silex child namespace",
                );
            }
        }
        const separator = std.mem.indexOfScalarPos(u8, module_path, stem_start, '.') orelse break;
        stem_start = separator + 1;
    }
}

pub fn namespaceHasPublicApiOrChildren(
    self: anytype,
    allocator: Allocator,
    io: Io,
    root: []const u8,
    module_path: []const u8,
) !bool {
    const directory = try self.moduleDirectoryPath(allocator, root, module_path);
    if (try self.lspDirectoryExists(io, directory)) return true;
    if (try self.lspCompactDescendantExists(allocator, io, root, module_path)) return true;
    const sources = try self.namespaceSourcePaths(allocator, io, root, module_path);
    for (sources) |source_path| {
        const source = Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(max_message_size)) catch continue;
        var parser = ParserModule.Parser.init(allocator, source);
        const program = parser.parse() catch continue;
        for (program.structures) |structure| if (structure.is_public) return true;
        for (program.enums) |enumeration| if (enumeration.is_public) return true;
        for (program.protocols) |protocol| if (protocol.is_public) return true;
        for (program.functions) |function| if (function.is_public) return true;
        for (program.uses) |use_value| if (use_value.is_public) return true;
    }
    return false;
}

pub fn namespaceSourcePaths(
    self: anytype,
    allocator: Allocator,
    io: Io,
    root: []const u8,
    module_path: []const u8,
) ![]const []const u8 {
    var sources: std.ArrayList([]const u8) = .empty;
    var stem_start: usize = 0;
    while (true) {
        const prefix = if (stem_start == 0) "" else module_path[0 .. stem_start - 1];
        const stem = module_path[stem_start..];
        const filename = try std.fmt.allocPrint(allocator, "{s}.sx", .{stem});
        const source_path = if (prefix.len == 0)
            try std.fs.path.join(allocator, &.{ root, filename })
        else
            try std.fs.path.join(allocator, &.{ try self.moduleDirectoryPath(allocator, root, prefix), filename });
        const stat = Io.Dir.cwd().statFile(io, source_path, .{}) catch null;
        if (stat != null and stat.?.kind == .file) try sources.append(allocator, source_path);
        const separator = std.mem.indexOfScalarPos(u8, module_path, stem_start, '.') orelse break;
        stem_start = separator + 1;
    }
    return sources.toOwnedSlice(allocator);
}

pub fn lspDirectoryExists(_: anytype, io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

pub fn appendModuleExportCompletion(
    self: anytype,
    allocator: Allocator,
    items: *std.ArrayList(CompletionItem),
    qualifier: []const u8,
    name: []const u8,
    kind: u8,
    detail: []const u8,
) !void {
    const label = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ qualifier, name });
    if (self.containsCompletion(items.items, label)) return;
    const insertion = try allocator.dupe(u8, name);
    try items.append(allocator, .{
        .label = label,
        .kind = kind,
        .detail = detail,
        .insertText = insertion,
        .filterText = insertion,
    });
}

pub fn unqualifiedModuleCompletionItems(
    self: anytype,
    allocator: Allocator,
    qualified: []const CompletionItem,
) ![]const CompletionItem {
    var items: std.ArrayList(CompletionItem) = .empty;
    for (qualified) |candidate| {
        const name = candidate.insertText orelse self.lastPathSegment(candidate.label);
        if (self.containsCompletion(items.items, name)) continue;
        var item = candidate;
        item.label = name;
        item.insertText = name;
        item.filterText = name;
        try items.append(allocator, item);
    }
    return items.toOwnedSlice(allocator);
}

pub fn moduleDirectoryPath(_: anytype, allocator: Allocator, root: []const u8, module_path: []const u8) ![]const u8 {
    const relative_path = try allocator.dupe(u8, module_path);
    for (relative_path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return std.fs.path.join(allocator, &.{ root, relative_path });
}

pub fn localModuleCompletionItems(
    self: anytype,
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    prefix: []const u8,
) ![]const CompletionItem {
    const source_path = try self.filePathFromUri(allocator, uri) orelse
        return try allocator.alloc(CompletionItem, 0);
    const project_root = std.fs.path.dirname(source_path) orelse
        return try allocator.alloc(CompletionItem, 0);

    var items: std.ArrayList(CompletionItem) = .empty;
    try self.collectRootModules(allocator, io, project_root, prefix, "Silex local module", &items);
    if (StandardLibrary.root(allocator, io) catch null) |standard_library_root| {
        try self.collectRootModules(allocator, io, standard_library_root, prefix, "Silex standard module", &items);
    }
    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return try items.toOwnedSlice(allocator);
}

pub fn useCompletionItems(
    self: anytype,
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    source: []const u8,
    prefix: []const u8,
) ![]const CompletionItem {
    var items: std.ArrayList(CompletionItem) = .empty;
    if (std.mem.lastIndexOfScalar(u8, prefix, '.')) |separator| {
        const qualifier = prefix[0..separator];
        const module_path = try self.usedModulePath(allocator, source, qualifier) orelse qualifier;
        const exports = try self.moduleExportCompletionItems(
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
        const children = try self.unqualifiedModuleCompletionItems(allocator, exports);
        try items.appendSlice(allocator, children);
    } else {
        const modules = try self.localModuleCompletionItems(allocator, io, uri, prefix);
        try items.appendSlice(allocator, modules);
    }

    std.mem.sort(CompletionItem, items.items, {}, struct {
        fn lessThan(_: void, left: CompletionItem, right: CompletionItem) bool {
            return std.mem.lessThan(u8, left.label, right.label);
        }
    }.lessThan);
    return items.toOwnedSlice(allocator);
}

pub fn collectRootModules(
    self: anytype,
    allocator: Allocator,
    io: Io,
    directory_path: []const u8,
    prefix: []const u8,
    detail: []const u8,
    items: *std.ArrayList(CompletionItem),
) !void {
    var directory = Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch return;
    defer directory.close(io);

    var child_directories: std.ArrayList([]const u8) = .empty;
    var source_stems: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterateAssumeFirstIteration();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind == .directory and ModuleDiscovery.isDirectoryName(entry.name)) {
            try child_directories.append(allocator, try allocator.dupe(u8, entry.name));
        } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".sx")) {
            const stem = entry.name[0 .. entry.name.len - ".sx".len];
            if (ModuleDiscovery.isModuleName(stem)) try source_stems.append(allocator, try allocator.dupe(u8, stem));
        }
    }

    for (child_directories.items) |child_name| {
        if (std.mem.startsWith(u8, child_name, prefix) and !self.containsCompletion(items.items, child_name)) {
            try items.append(allocator, .{
                .label = child_name,
                .kind = 9,
                .detail = detail,
                .insertText = child_name,
                .filterText = child_name,
            });
        }
    }

    for (source_stems.items) |stem| {
        const child_name = self.firstPathSegment(stem);
        if (std.mem.startsWith(u8, child_name, prefix) and !self.containsCompletion(items.items, child_name)) {
            try items.append(allocator, .{
                .label = child_name,
                .kind = 9,
                .detail = detail,
                .insertText = child_name,
                .filterText = child_name,
            });
        }
    }
}

pub fn filePathFromUri(self: anytype, allocator: Allocator, uri: []const u8) !?[]const u8 {
    const scheme = "file://";
    if (!std.mem.startsWith(u8, uri, scheme)) return null;
    const encoded = uri[scheme.len..];
    var path: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] == '%' and index + 2 < encoded.len) {
            const high = self.hexDigit(encoded[index + 1]) orelse return null;
            const low = self.hexDigit(encoded[index + 2]) orelse return null;
            try path.append(allocator, high * 16 + low);
            index += 3;
        } else {
            try path.append(allocator, encoded[index]);
            index += 1;
        }
    }
    return try path.toOwnedSlice(allocator);
}

pub fn documentProjectRoot(self: anytype, allocator: Allocator, uri: []const u8) !?[]const u8 {
    const source_path = try self.filePathFromUri(allocator, uri) orelse return null;
    return std.fs.path.dirname(source_path);
}

pub fn hexDigit(_: anytype, character: u8) ?u8 {
    return switch (character) {
        '0'...'9' => character - '0',
        'a'...'f' => character - 'a' + 10,
        'A'...'F' => character - 'A' + 10,
        else => null,
    };
}

pub fn byteOffsetAtPosition(self: anytype, source: []const u8, position: Position) ?usize {
    return self.byteOffsetAtEncodedPosition(source, position, .utf16);
}

pub fn normalizePosition(
    self: anytype,
    source: []const u8,
    position: ?Position,
    encoding: PositionEncoding,
) ?Position {
    const requested = position orelse return null;
    const offset = self.byteOffsetAtEncodedPosition(source, requested, encoding) orelse return null;
    return self.encodedPositionAtByteOffset(source, offset, .utf16);
}

pub fn byteOffsetAtEncodedPosition(
    self: anytype,
    source: []const u8,
    position: Position,
    encoding: PositionEncoding,
) ?usize {
    var offset: usize = 0;
    var line: usize = 0;
    while (line < position.line) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return null;
        offset = newline + 1;
    }

    var units: usize = 0;
    while (offset < source.len and source[offset] != '\n' and units < position.character) {
        const sequence_length = self.utf8SequenceLength(source[offset]);
        units += switch (encoding) {
            .utf8 => sequence_length,
            .utf16 => if (sequence_length == 4) 2 else 1,
            .utf32 => 1,
        };
        offset += @min(sequence_length, source.len - offset);
    }
    return if (units == position.character) offset else null;
}

pub fn encodedPositionAtByteOffset(
    self: anytype,
    source: []const u8,
    requested_offset: usize,
    encoding: PositionEncoding,
) ?Position {
    if (requested_offset > source.len) return null;
    var position: Position = .{ .line = 0, .character = 0 };
    var offset: usize = 0;
    while (offset < requested_offset) {
        if (source[offset] == '\n') {
            position.line += 1;
            position.character = 0;
            offset += 1;
            continue;
        }
        const sequence_length = self.utf8SequenceLength(source[offset]);
        if (offset + sequence_length > requested_offset) return null;
        position.character += switch (encoding) {
            .utf8 => sequence_length,
            .utf16 => if (sequence_length == 4) 2 else 1,
            .utf32 => 1,
        };
        offset += sequence_length;
    }
    return position;
}

pub fn documentEndPosition(self: anytype, source: []const u8, encoding: PositionEncoding) Position {
    return self.encodedPositionAtByteOffset(source, source.len, encoding).?;
}

pub fn utf8SequenceLength(_: anytype, first_byte: u8) usize {
    if (first_byte & 0x80 == 0) return 1;
    if (first_byte & 0xe0 == 0xc0) return 2;
    if (first_byte & 0xf0 == 0xe0) return 3;
    if (first_byte & 0xf8 == 0xf0) return 4;
    return 1;
}

pub fn isIdentifierContinue(_: anytype, character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

pub fn containsCompletion(_: anytype, items: []const CompletionItem, label: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.label, label)) return true;
    return false;
}

pub fn expectSemanticTokenAt(
    self: anytype,
    source: []const u8,
    data: []const u32,
    byte_offset: usize,
    byte_length: usize,
    expected: SemanticTokenKind,
) !void {
    const requested = self.encodedPositionAtByteOffset(source, byte_offset, .utf16) orelse
        return error.TestUnexpectedResult;
    const requested_end = self.encodedPositionAtByteOffset(source, byte_offset + byte_length, .utf16) orelse
        return error.TestUnexpectedResult;
    var line: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index + 4 < data.len) : (index += 5) {
        const delta_line: usize = data[index];
        line += delta_line;
        start = if (delta_line == 0) start + data[index + 1] else data[index + 1];
        if (line != requested.line or start != requested.character) continue;
        try std.testing.expectEqual(requested_end.character - requested.character, data[index + 2]);
        try std.testing.expectEqual(@intFromEnum(expected), data[index + 3]);
        return;
    }
    return error.TestUnexpectedResult;
}

pub const language_completions = [_]CompletionItem{
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
    .{ .label = "deferred", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "use", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "private", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "protected", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "public", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "as", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "self", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "true", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "false", .kind = 14, .detail = "Silex keyword" },
    .{ .label = "print", .kind = 3, .detail = "Silex builtin" },
    .{ .label = "map_error", .kind = 3, .detail = "Silex intrinsic function" },
    .{ .label = "dispatch_callbacks", .kind = 3, .detail = "Silex intrinsic function" },
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
