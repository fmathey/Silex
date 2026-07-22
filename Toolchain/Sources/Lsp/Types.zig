pub const std = @import("std");
pub const build_options = @import("build_options");
pub const Ast = @import("../Ast.zig");
pub const Formatter = @import("../Formatter.zig");
pub const Frontend = @import("../Frontend.zig");
pub const LexerModule = @import("../Lexer.zig");
pub const Lint = @import("../Lint.zig");
pub const ModuleDiscovery = @import("../ModuleDiscovery.zig");
pub const ModuleManifest = @import("../ModuleManifest.zig");
pub const ParserModule = @import("../Parser.zig");
pub const ProjectModule = @import("../Project.zig");
pub const Semantic = @import("../Semantic.zig");
pub const Source = @import("../Source.zig");
pub const StandardLibrary = @import("../StandardLibrary.zig");
pub const SourceGraph = @import("../SourceGraph.zig");
pub const SymbolIndex = @import("../SymbolIndex.zig");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;

pub const protocol_version = "2.0";
pub const max_message_size = 16 * 1024 * 1024;
pub const completion_trigger_characters = [_][]const u8{"."};
pub const semantic_token_types = [_][]const u8{
    "namespace",
    "type",
    "enumMember",
    "function",
    "method",
    "property",
    "parameter",
    "variable",
};
pub const module_analysis_directory = ".silex-lsp";

pub const Document = struct {
    uri: []const u8,
    path: []const u8 = "",
    text: []const u8,
    version: i64 = 0,
};

pub const ProjectState = struct {
    input_path: []const u8,
    current: ?Frontend.Snapshot = null,
    last_success: ?Frontend.Snapshot = null,
    failure: ?Frontend.Failure = null,
    published_uris: []const []const u8 = &.{},
    last_versions: []const VersionStamp = &.{},
};

pub const VersionStamp = struct { path: []const u8, version: i64 };
pub const ProjectAffinity = struct { path: []const u8, input_path: []const u8 };
pub const ModuleAnalysisProject = struct {
    root: []const u8,
    project: ProjectModule.Project,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: u8,
    detail: []const u8,
    insertText: ?[]const u8 = null,
    filterText: ?[]const u8 = null,
    insertTextFormat: ?u8 = null,
};

pub const SignatureInformation = struct {
    label: []const u8,
    parameters: []const SignatureParameter = &.{},
};

pub const SignatureParameter = struct {
    label: [2]usize,
};

pub const SignatureHelpResult = struct {
    signatures: []const SignatureInformation,
    activeSignature: usize = 0,
    activeParameter: usize = 0,
};

pub const SemanticTokenKind = enum(u32) {
    namespace,
    type,
    enum_member,
    function,
    method,
    property,
    parameter,
    variable,
};

pub const SemanticTokenSpan = struct {
    position: Position,
    length: usize,
    kind: SemanticTokenKind,
};

pub const SemanticTokens = struct {
    data: []const u32,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const RenameEdit = struct {
    range: Range,
    newText: []const u8,
};

pub const TextDocumentEdit = struct {
    textDocument: struct {
        uri: []const u8,
        version: ?i64,
    },
    edits: []const RenameEdit,
};

pub const MarkupContent = struct {
    kind: []const u8 = "markdown",
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: Range,
};

pub const PreparedRename = struct {
    range: Range,
    placeholder: []const u8,
};

pub const WorkspaceEdit = struct {
    documentChanges: []const TextDocumentEdit,
};

pub const RequestContext = struct {
    document: *const Document,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    occurrence: SymbolIndex.Occurrence,
};

pub const RenameError = error{
    InvalidPosition,
    NotRenamable,
    InvalidName,
    NonCanonicalName,
    Collision,
    ExternalSource,
    ValidationFailed,
};

pub const QualifiedCompletionContext = struct {
    qualifier: []const u8,
    prefix: []const u8,
    type_only: bool,
};

pub const ModuleExportScope = enum {
    public_api,
    use_path,
    qualified_expression,
};

pub const Position = struct {
    line: usize,
    character: usize,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const PositionEncoding = enum {
    utf8,
    utf16,
    utf32,

    pub fn protocolName(self: PositionEncoding) []const u8 {
        return switch (self) {
            .utf8 => "utf-8",
            .utf16 => "utf-16",
            .utf32 => "utf-32",
        };
    }
};

pub const TextEdit = struct {
    range: Range,
    newText: []const u8,
};

pub const FormattingOutcome = union(enum) {
    edits: []const TextEdit,
    diagnostic: Source.Diagnostic,
};

pub const Diagnostic = struct {
    range: Range,
    severity: u8 = 1,
    source: []const u8 = "silex",
    code: ?[]const u8 = null,
    message: []const u8,
};

pub const Request = struct {
    jsonrpc: []const u8,
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,
};
