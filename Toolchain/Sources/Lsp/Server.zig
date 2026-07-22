const Types = @import("Types.zig");
const Protocol = @import("Protocol.zig");
const Features = @import("Features.zig");
const Completion = @import("Completion.zig");
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

pub const Helpers = struct {
    pub const readMessage = Protocol.readMessage;
    pub const documentFromOpen = Protocol.documentFromOpen;
    pub const documentFromChange = Protocol.documentFromChange;
    pub const textDocumentUri = Protocol.textDocumentUri;
    pub const completionPosition = Protocol.completionPosition;
    pub const negotiatedPositionEncoding = Protocol.negotiatedPositionEncoding;
    pub const formattingOutcome = Protocol.formattingOutcome;
    pub const objectMember = Protocol.objectMember;
    pub const stringMember = Protocol.stringMember;
    pub const booleanMember = Protocol.booleanMember;
    pub const unsignedMember = Protocol.unsignedMember;
    pub const integerMember = Protocol.integerMember;
    pub const sourcePositionAtByteOffset = Protocol.sourcePositionAtByteOffset;
    pub const sourceByteOffset = Protocol.sourceByteOffset;
    pub const semanticTokenData = Protocol.semanticTokenData;
    pub const semanticTokenKind = Protocol.semanticTokenKind;
    pub const followedByInvocation = Protocol.followedByInvocation;
    pub const pathWithin = Protocol.pathWithin;
    pub const uriFromPath = Protocol.uriFromPath;
    pub const manifestDeclares = Protocol.manifestDeclares;
    pub const moduleAnalysisInput = Protocol.moduleAnalysisInput;
    pub const singleSourceRootForDocument = Protocol.singleSourceRootForDocument;
    pub const sourceDefinesMain = Protocol.sourceDefinesMain;
    pub const moduleNameFromSource = Protocol.moduleNameFromSource;
    pub const moduleNameFromDirectories = Protocol.moduleNameFromDirectories;
    pub const validIdentifier = Protocol.validIdentifier;
    pub const canonicalRename = Protocol.canonicalRename;
    pub const renameErrorMessage = Protocol.renameErrorMessage;
    pub const snapshotFile = Protocol.snapshotFile;
    pub const projectContainsPath = Protocol.projectContainsPath;
    pub const positionAfter = Protocol.positionAfter;
    pub const completionItemForSymbol = Protocol.completionItemForSymbol;
    pub const detailTypeName = Protocol.detailTypeName;
    pub const blankLineAt = Protocol.blankLineAt;
    pub const fallbackCompletionReceiver = Protocol.fallbackCompletionReceiver;
    pub const callableNameAt = Protocol.callableNameAt;
    pub const signatureParameters = Protocol.signatureParameters;
    pub const appendSignatureParameter = Protocol.appendSignatureParameter;
    pub const activeParameterAt = Protocol.activeParameterAt;
    pub const renamedSource = Features.renamedSource;
    pub const renameGroupHasKind = Features.renameGroupHasKind;
    pub const syntaxDiagnostic = Features.syntaxDiagnostic;
    pub const syntaxDiagnosticWithEncoding = Features.syntaxDiagnosticWithEncoding;
    pub const diagnosticsWithEncoding = Features.diagnosticsWithEncoding;
    pub const diagnosticFromSource = Features.diagnosticFromSource;
    pub const sourceDiagnosticByteOffset = Features.sourceDiagnosticByteOffset;
    pub const enclosingParenthesisAt = Features.enclosingParenthesisAt;
    pub const namedArgumentContext = Features.namedArgumentContext;
    pub const initializerTypeSymbol = Features.initializerTypeSymbol;
    pub const calleeQualifierAt = Features.calleeQualifierAt;
    pub const principalModuleMatches = Features.principalModuleMatches;
    pub const containsName = Features.containsName;
    pub const completionInsideOwnerCallable = Features.completionInsideOwnerCallable;
    pub const signatureCalleeAt = Features.signatureCalleeAt;
    pub const symbolVisibleFromFile = Features.symbolVisibleFromFile;
    pub const useCompletionPrefix = Features.useCompletionPrefix;
    pub const usedModulePath = Features.usedModulePath;
    pub const directiveBody = Features.directiveBody;
    pub const looksLikeTypeAliasTarget = Features.looksLikeTypeAliasTarget;
    pub const expandVisibleModulePath = Features.expandVisibleModulePath;
    pub const pathHasModuleQualifier = Features.pathHasModuleQualifier;
    pub const qualifiedCompletionPrefix = Features.qualifiedCompletionPrefix;
    pub const lastPathSegment = Completion.lastPathSegment;
    pub const firstPathSegment = Completion.firstPathSegment;
    pub const moduleExportCompletionItems = Completion.moduleExportCompletionItems;
    pub const moduleCompletionRoot = Completion.moduleCompletionRoot;
    pub const completionNamespaceExists = Completion.completionNamespaceExists;
    pub const lspNamespaceExists = Completion.lspNamespaceExists;
    pub const lspCompactDescendantExists = Completion.lspCompactDescendantExists;
    pub const appendCompactChildCompletions = Completion.appendCompactChildCompletions;
    pub const namespaceHasPublicApiOrChildren = Completion.namespaceHasPublicApiOrChildren;
    pub const namespaceSourcePaths = Completion.namespaceSourcePaths;
    pub const lspDirectoryExists = Completion.lspDirectoryExists;
    pub const appendModuleExportCompletion = Completion.appendModuleExportCompletion;
    pub const unqualifiedModuleCompletionItems = Completion.unqualifiedModuleCompletionItems;
    pub const moduleDirectoryPath = Completion.moduleDirectoryPath;
    pub const localModuleCompletionItems = Completion.localModuleCompletionItems;
    pub const useCompletionItems = Completion.useCompletionItems;
    pub const collectRootModules = Completion.collectRootModules;
    pub const filePathFromUri = Completion.filePathFromUri;
    pub const documentProjectRoot = Completion.documentProjectRoot;
    pub const hexDigit = Completion.hexDigit;
    pub const byteOffsetAtPosition = Completion.byteOffsetAtPosition;
    pub const normalizePosition = Completion.normalizePosition;
    pub const byteOffsetAtEncodedPosition = Completion.byteOffsetAtEncodedPosition;
    pub const encodedPositionAtByteOffset = Completion.encodedPositionAtByteOffset;
    pub const documentEndPosition = Completion.documentEndPosition;
    pub const utf8SequenceLength = Completion.utf8SequenceLength;
    pub const isIdentifierContinue = Completion.isIdentifierContinue;
    pub const containsCompletion = Completion.containsCompletion;
    pub const expectSemanticTokenAt = Completion.expectSemanticTokenAt;
};
pub const Server = struct {
    allocator: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    documents: std.ArrayList(Document) = .empty,
    projects: std.ArrayList(ProjectState) = .empty,
    workspace_roots: std.ArrayList([]const u8) = .empty,
    configured_project: ?[]const u8 = null,
    project_affinities: std.ArrayList(ProjectAffinity) = .empty,
    position_encoding: PositionEncoding = .utf16,

    pub fn init(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map) Server {
        return .{ .allocator = allocator, .io = io, .environ_map = environ_map };
    }

    pub fn run(self: *Server) !void {
        var input_buffer: [32 * 1024]u8 = undefined;
        var reader = Io.File.stdin().readerStreaming(self.io, &input_buffer);
        while (try self.readMessage(self.allocator, &reader.interface)) |body| {
            const request = std.json.parseFromSliceLeaky(Request, self.allocator, body, .{
                .ignore_unknown_fields = true,
            }) catch continue;
            if (!std.mem.eql(u8, request.jsonrpc, protocol_version)) continue;
            try self.handle(request);
        }
    }

    pub fn handle(self: *Server, request: Request) !void {
        if (std.mem.eql(u8, request.method, "initialize")) {
            self.position_encoding = self.negotiatedPositionEncoding(request.params);
            if (request.params) |params| try self.configureWorkspace(params);
            if (request.id) |id| try self.reply(id, .{
                .capabilities = .{
                    .positionEncoding = self.position_encoding.protocolName(),
                    .textDocumentSync = 1,
                    .documentFormattingProvider = true,
                    .completionProvider = .{
                        .triggerCharacters = &completion_trigger_characters,
                    },
                    .signatureHelpProvider = .{
                        .triggerCharacters = &.{ "(", "," },
                    },
                    .definitionProvider = true,
                    .referencesProvider = true,
                    .renameProvider = .{ .prepareProvider = true },
                    .hoverProvider = true,
                    .semanticTokensProvider = .{
                        .legend = .{
                            .tokenTypes = &semantic_token_types,
                            .tokenModifiers = &[_][]const u8{},
                        },
                        .full = true,
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
                if (self.documentFromOpen(params)) |document| {
                    try self.setDocument(document.uri, document.text, document.version);
                    try self.analyzeAndPublish(document.uri);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didChange")) {
            if (request.params) |params| {
                if (self.documentFromChange(params)) |document| {
                    try self.setDocument(document.uri, document.text, document.version);
                    try self.analyzeAndPublish(document.uri);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didClose")) {
            if (request.params) |params| {
                if (self.textDocumentUri(params)) |uri| {
                    const input = if (self.findDocument(uri)) |document| try self.inputForDocument(document.path) else null;
                    self.removeDocument(uri);
                    if (input) |input_path| {
                        if (self.projectByInput(input_path)) |project| {
                            if (!self.projectHasOpenDocument(project)) {
                                for (project.published_uris) |published| try self.clearDiagnostics(published);
                                project.published_uris = &.{};
                                project.current = null;
                                project.failure = null;
                            } else try self.analyzeInputAndPublish(input_path);
                        } else try self.clearDiagnostics(uri);
                    } else try self.clearDiagnostics(uri);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "workspace/didChangeWatchedFiles")) {
            for (self.projects.items) |project| try self.analyzeInputAndPublish(project.input_path);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/definition")) {
            const result = if (request.params) |params| try self.definition(params) else null;
            if (request.id) |id| try self.reply(id, result);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/references")) {
            const locations = if (request.params) |params| try self.references(params) else &[_]Location{};
            if (request.id) |id| try self.reply(id, locations);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/hover")) {
            const result = if (request.params) |params| try self.hover(params) else null;
            if (request.id) |id| try self.reply(id, result);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/prepareRename")) {
            const id = request.id orelse return;
            const params = request.params orelse return self.replyInvalidParams(id, "missing rename parameters");
            const prepared = self.prepareRename(params) catch |err| {
                try self.replyRequestFailed(id, self.renameErrorMessage(err));
                return;
            };
            try self.reply(id, prepared);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/rename")) {
            const id = request.id orelse return;
            const params = request.params orelse return self.replyInvalidParams(id, "missing rename parameters");
            const edit = self.rename(params) catch |err| {
                try self.replyRequestFailed(id, self.renameErrorMessage(err));
                return;
            };
            try self.reply(id, edit);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/completion")) {
            const items = if (request.params) |params| try self.completion(params) else &[_]CompletionItem{};
            if (request.id) |id| try self.reply(id, .{
                .isIncomplete = false,
                .items = items,
            });
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/signatureHelp")) {
            const result = if (request.params) |params| try self.signatureHelp(params) else SignatureHelpResult{ .signatures = &.{} };
            if (request.id) |id| try self.reply(id, result);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/semanticTokens/full")) {
            const result = if (request.params) |params| try self.semanticTokens(params) else SemanticTokens{ .data = &.{} };
            if (request.id) |id| try self.reply(id, result);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/formatting")) {
            const id = request.id orelse return;
            const params = request.params orelse {
                try self.replyInvalidParams(id, "missing formatting parameters");
                return;
            };
            const uri = self.textDocumentUri(params) orelse {
                try self.replyInvalidParams(id, "missing text document URI");
                return;
            };
            const source = self.documentText(uri) orelse {
                try self.replyInvalidParams(id, "document is not open");
                return;
            };
            switch (try self.formattingOutcome(self.allocator, source, self.position_encoding)) {
                .edits => |edits| try self.reply(id, edits),
                .diagnostic => |diagnostic| try self.replyFormattingError(id, diagnostic),
            }
        }
    }

    pub fn reply(self: *Server, id: std.json.Value, result: anytype) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .result = result,
        });
    }

    pub fn replyInvalidParams(self: *Server, id: std.json.Value, message: []const u8) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .@"error" = .{
                .code = @as(i32, -32602),
                .message = message,
            },
        });
    }

    pub fn replyRequestFailed(self: *Server, id: std.json.Value, message: []const u8) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .@"error" = .{ .code = @as(i32, -32803), .message = message },
        });
    }

    pub fn replyFormattingError(self: *Server, id: std.json.Value, diagnostic: Source.Diagnostic) !void {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "{d}:{d}: error: {s}",
            .{ diagnostic.position.line, diagnostic.position.column, diagnostic.message },
        );
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .@"error" = .{
                .code = @as(i32, -32803),
                .message = message,
                .data = .{
                    .line = diagnostic.position.line,
                    .column = diagnostic.position.column,
                    .diagnostic = diagnostic.message,
                },
            },
        });
    }

    pub fn sendNotification(self: *Server, method: []const u8, params: anytype) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .method = method,
            .params = params,
        });
    }

    pub fn send(self: *Server, message: anytype) !void {
        const body = try std.json.Stringify.valueAlloc(self.allocator, message, .{
            .emit_null_optional_fields = false,
        });
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
        try Io.File.stdout().writeStreamingAll(self.io, header);
        try Io.File.stdout().writeStreamingAll(self.io, body);
    }

    pub fn setDocument(self: *Server, uri: []const u8, text: []const u8, version: i64) !void {
        const decoded_path = try self.filePathFromUri(self.allocator, uri) orelse return;
        const path = try SourceGraph.canonicalPath(self.allocator, self.io, decoded_path);
        for (self.documents.items) |*document| {
            if (std.mem.eql(u8, document.uri, uri)) {
                document.text = try self.allocator.dupe(u8, text);
                document.path = path;
                document.version = version;
                return;
            }
        }
        try self.documents.append(self.allocator, .{
            .uri = try self.allocator.dupe(u8, uri),
            .path = path,
            .text = try self.allocator.dupe(u8, text),
            .version = version,
        });
    }

    pub fn removeDocument(self: *Server, uri: []const u8) void {
        for (self.documents.items, 0..) |document, index| {
            if (std.mem.eql(u8, document.uri, uri)) {
                _ = self.documents.orderedRemove(index);
                return;
            }
        }
    }

    pub fn documentText(self: *const Server, uri: []const u8) ?[]const u8 {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.uri, uri)) return document.text;
        }
        return null;
    }

    pub fn findDocument(self: *const Server, uri: []const u8) ?*const Document {
        for (self.documents.items) |*document| if (std.mem.eql(u8, document.uri, uri)) return document;
        return null;
    }

    pub fn configureWorkspace(self: *Server, params: std.json.Value) !void {
        if (self.objectMember(params, "workspaceFolders")) |folders| {
            if (folders == .array) for (folders.array.items) |folder| {
                const uri = self.stringMember(folder, "uri") orelse continue;
                const decoded = try self.filePathFromUri(self.allocator, uri) orelse continue;
                try self.workspace_roots.append(
                    self.allocator,
                    try SourceGraph.canonicalPath(self.allocator, self.io, decoded),
                );
            };
        }
        if (self.workspace_roots.items.len == 0) if (self.stringMember(params, "rootUri")) |uri| {
            const decoded = try self.filePathFromUri(self.allocator, uri) orelse return;
            try self.workspace_roots.append(
                self.allocator,
                try SourceGraph.canonicalPath(self.allocator, self.io, decoded),
            );
        };
        const options = self.objectMember(params, "initializationOptions") orelse return;
        const configured = self.stringMember(options, "silex.project") orelse configured: {
            const silex = self.objectMember(options, "silex") orelse break :configured null;
            break :configured self.stringMember(silex, "project");
        };
        if (configured) |path| {
            const candidate = if (std.fs.path.isAbsolute(path))
                path
            else if (self.workspace_roots.items.len != 0)
                try std.fs.path.join(self.allocator, &.{ self.workspace_roots.items[0], path })
            else
                path;
            self.configured_project = try SourceGraph.canonicalPath(self.allocator, self.io, candidate);
        }
    }

    pub fn analyzeAndPublish(self: *Server, uri: []const u8) !void {
        const document = self.findDocument(uri) orelse return;
        const input = try self.inputForDocument(document.path) orelse {
            try self.clearDiagnostics(uri);
            return;
        };
        try self.analyzeInputAndPublish(input);
    }

    pub fn analyzeInputAndPublish(self: *Server, input_path: []const u8) !void {
        var overlays: std.ArrayList(Frontend.Overlay) = .empty;
        for (self.documents.items) |document| try overlays.append(self.allocator, .{
            .path = document.path,
            .text = document.text,
        });

        var state_index: ?usize = null;
        for (self.projects.items, 0..) |project, index| if (std.mem.eql(u8, project.input_path, input_path)) {
            state_index = index;
            break;
        };
        if (state_index == null) {
            state_index = self.projects.items.len;
            try self.projects.append(self.allocator, .{ .input_path = try self.allocator.dupe(u8, input_path) });
        }
        const state = &self.projects.items[state_index.?];
        const previous = state.published_uris;
        const outcome = self.analyzeInput(input_path, overlays.items) catch |err| {
            if (err == error.Reported) {
                state.current = null;
                state.failure = null;
                for (previous) |uri| try self.clearDiagnostics(uri);
                state.published_uris = &.{};
                return;
            }
            return err;
        };

        var published: std.ArrayList([]const u8) = .empty;
        switch (outcome) {
            .success => |snapshot| {
                state.current = snapshot;
                state.last_success = snapshot;
                var versions: std.ArrayList(VersionStamp) = .empty;
                for (self.documents.items) |document| {
                    if (self.snapshotFile(&snapshot, document.path) != null) try versions.append(self.allocator, .{
                        .path = document.path,
                        .version = document.version,
                    });
                }
                state.last_versions = try versions.toOwnedSlice(self.allocator);
                state.failure = null;
                for (snapshot.source_paths, snapshot.source_contents) |path, source| {
                    const uri = try self.uriFromPath(self.allocator, path);
                    try published.append(self.allocator, uri);
                    try self.sendNotification("textDocument/publishDiagnostics", .{
                        .uri = uri,
                        .diagnostics = try self.diagnosticsWithEncoding(self.allocator, source, self.position_encoding),
                    });
                }
            },
            .failure => |failure| {
                state.current = null;
                state.failure = failure;
                const diagnostic_file = failure.diagnostic.position.file;
                for (failure.source_paths, 0..) |path, file| {
                    const uri = try self.uriFromPath(self.allocator, path);
                    try published.append(self.allocator, uri);
                    const source = if (file < failure.source_contents.len) failure.source_contents[file] else "";
                    const diagnostics = if (file == diagnostic_file)
                        try self.allocator.dupe(Diagnostic, &.{self.diagnosticFromSource(
                            source,
                            failure.diagnostic,
                            self.position_encoding,
                        )})
                    else
                        try self.diagnosticsWithEncoding(self.allocator, source, self.position_encoding);
                    try self.sendNotification("textDocument/publishDiagnostics", .{ .uri = uri, .diagnostics = diagnostics });
                }
            },
        }
        for (previous) |uri| {
            var retained = false;
            for (published.items) |current| if (std.mem.eql(u8, current, uri)) {
                retained = true;
                break;
            };
            if (!retained) try self.clearDiagnostics(uri);
        }
        state.published_uris = try published.toOwnedSlice(self.allocator);
    }

    pub fn analyzeInput(
        self: *Server,
        input_path: []const u8,
        overlays: []const Frontend.Overlay,
    ) !Frontend.Outcome {
        const context = try self.moduleAnalysisProject(input_path) orelse return Frontend.analyze(
            self.allocator,
            self.io,
            self.environ_map,
            input_path,
            .editor,
            overlays,
        );
        return Frontend.analyzeProject(
            self.allocator,
            self.io,
            self.environ_map,
            context.project,
            context.root,
            .editor,
            overlays,
            false,
        );
    }

    pub fn clearDiagnostics(self: *Server, uri: []const u8) !void {
        try self.sendNotification("textDocument/publishDiagnostics", .{
            .uri = uri,
            .diagnostics = &[_]Diagnostic{},
        });
    }

    pub fn inputForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
        if (self.configured_project) |configured| {
            if (std.mem.eql(u8, configured, document_path) or
                try self.manifestDeclares(self.allocator, self.io, configured, document_path) or
                self.projectInputContains(configured, document_path))
            {
                return configured;
            }
        }
        if (self.preferredProjectInput(document_path)) |input_path| return input_path;
        if (self.loadedProjectForDocument(document_path)) |project| return project.input_path;
        const workspace = self.workspaceForPath(document_path);
        var directory = std.fs.path.dirname(document_path) orelse return document_path;
        while (true) {
            var candidates: std.ArrayList([]const u8) = .empty;
            var opened = Io.Dir.cwd().openDir(self.io, directory, .{ .iterate = true }) catch null;
            if (opened) |*folder| {
                defer folder.close(self.io);
                var names: std.ArrayList([]const u8) = .empty;
                var iterator = folder.iterateAssumeFirstIteration();
                while (try iterator.next(self.io)) |entry| {
                    if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                        try names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
                    }
                }
                std.mem.sort([]const u8, names.items, {}, struct {
                    fn lessThan(_: void, left: []const u8, right: []const u8) bool {
                        return std.mem.lessThan(u8, left, right);
                    }
                }.lessThan);
                for (names.items) |name| {
                    const path = try std.fs.path.join(self.allocator, &.{ directory, name });
                    if (try self.manifestDeclares(self.allocator, self.io, path, document_path)) {
                        try candidates.append(self.allocator, try SourceGraph.canonicalPath(self.allocator, self.io, path));
                    }
                }
            }
            if (candidates.items.len == 1) return candidates.items[0];
            if (candidates.items.len > 1) {
                try self.sendNotification("window/showMessage", .{
                    .type = @as(u8, 2),
                    .message = "Several Silex manifests contain this document; configure initializationOptions.silex.project.",
                });
                return null;
            }
            if (workspace) |root| if (std.mem.eql(u8, directory, root)) break;
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory)) break;
            directory = parent;
        }
        if (try self.moduleAnalysisInputForDocument(document_path)) |input_path| return input_path;
        return document_path;
    }

    pub fn moduleAnalysisInputForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
        const module_directory = std.fs.path.dirname(document_path) orelse return null;
        const root = try self.moduleAnalysisRootForDocument(document_path) orelse return null;
        _ = try self.moduleNameFromSource(self.allocator, root, document_path) orelse return null;
        return try std.fs.path.join(self.allocator, &.{
            module_directory,
            module_analysis_directory,
            std.fs.path.basename(document_path),
        });
    }

    pub fn moduleAnalysisProject(self: *Server, input_path: []const u8) !?ModuleAnalysisProject {
        if (!self.moduleAnalysisInput(input_path)) return null;
        const analysis_directory = std.fs.path.dirname(input_path) orelse return null;
        const module_directory = std.fs.path.dirname(analysis_directory) orelse return null;
        const source_path = try std.fs.path.join(self.allocator, &.{
            module_directory,
            std.fs.path.basename(input_path),
        });
        const root = try self.moduleAnalysisRootForDocument(source_path) orelse return null;
        const module_name = try self.moduleNameFromSource(self.allocator, root, source_path) orelse return null;
        const modules = try self.allocator.dupe(ProjectModule.Module, &.{.{
            .name = module_name,
            .sources = try self.allocator.dupe([]const u8, &.{source_path}),
        }});
        return .{
            .root = root,
            .project = .{
                .program_name = module_name,
                .target_module = 0,
                .modules = modules,
                .single_file = false,
            },
        };
    }

    pub fn moduleAnalysisRootForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
        const module_directory = std.fs.path.dirname(document_path) orelse return null;
        if (try self.moduleManifestDirectory(module_directory)) |manifest_directory| {
            const manifest_path = try std.fs.path.join(self.allocator, &.{ manifest_directory, ModuleManifest.filename });
            const manifest = ModuleManifest.load(self.allocator, self.io, manifest_path) catch {
                return std.fs.path.dirname(manifest_directory);
            };
            if (manifest.name != null or
                StandardLibrary.isReservedModule(std.fs.path.basename(manifest_directory)))
            {
                return std.fs.path.dirname(manifest_directory);
            }
            return manifest_directory;
        }
        if (self.configured_project) |input_path| {
            if (self.singleSourceRootForDocument(input_path, document_path)) |root| return root;
        }
        var selected: ?[]const u8 = null;
        for (self.projects.items) |project| {
            const root = self.singleSourceRootForDocument(project.input_path, document_path) orelse continue;
            if (selected == null or root.len > selected.?.len) selected = root;
        }
        if (selected) |root| return root;
        return self.discoverSingleSourceRoot(document_path);
    }

    pub fn discoverSingleSourceRoot(self: *Server, document_path: []const u8) !?[]const u8 {
        const workspace = self.workspaceForPath(document_path) orelse return null;
        var directory = std.fs.path.dirname(document_path) orelse return null;
        while (true) {
            var opened = Io.Dir.cwd().openDir(self.io, directory, .{ .iterate = true }) catch null;
            if (opened) |*folder| {
                defer folder.close(self.io);
                var iterator = folder.iterateAssumeFirstIteration();
                while (try iterator.next(self.io)) |entry| {
                    if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
                    const candidate = try std.fs.path.join(self.allocator, &.{ directory, entry.name });
                    if (std.mem.eql(u8, candidate, document_path)) continue;
                    const source = self.openDocumentSource(candidate) orelse
                        Io.Dir.cwd().readFileAlloc(
                            self.io,
                            candidate,
                            self.allocator,
                            .limited(1024 * 1024),
                        ) catch continue;
                    if (self.sourceDefinesMain(self.allocator, source)) return directory;
                }
            }
            if (std.mem.eql(u8, directory, workspace)) break;
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory) or !self.pathWithin(parent, workspace)) break;
            directory = parent;
        }
        return null;
    }

    pub fn openDocumentSource(self: *const Server, path: []const u8) ?[]const u8 {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.path, path)) return document.text;
        }
        return null;
    }

    pub fn moduleManifestDirectory(self: *Server, start: []const u8) !?[]const u8 {
        var directory = start;
        while (true) {
            const manifest_path = try std.fs.path.join(self.allocator, &.{ directory, "@Module.json" });
            if (Io.Dir.cwd().statFile(self.io, manifest_path, .{})) |stat| {
                if (stat.kind == .file) return directory;
            } else |_| {}
            const parent = std.fs.path.dirname(directory) orelse return null;
            if (std.mem.eql(u8, parent, directory)) return null;
            directory = parent;
        }
    }

    pub fn projectInputContains(self: *const Server, input_path: []const u8, document_path: []const u8) bool {
        for (self.projects.items) |project| {
            if (!std.mem.eql(u8, project.input_path, input_path)) continue;
            return self.projectContainsPath(&project, document_path);
        }
        return false;
    }

    pub fn preferredProjectInput(self: *const Server, document_path: []const u8) ?[]const u8 {
        var index = self.project_affinities.items.len;
        while (index > 0) {
            index -= 1;
            const affinity = self.project_affinities.items[index];
            if (std.mem.eql(u8, affinity.path, document_path) and
                self.projectInputContains(affinity.input_path, document_path))
            {
                return affinity.input_path;
            }
        }
        return null;
    }

    pub fn rememberProjectInput(self: *Server, document_path: []const u8, input_path: []const u8) !void {
        for (self.project_affinities.items) |*affinity| {
            if (!std.mem.eql(u8, affinity.path, document_path)) continue;
            affinity.input_path = input_path;
            return;
        }
        try self.project_affinities.append(self.allocator, .{
            .path = try self.allocator.dupe(u8, document_path),
            .input_path = try self.allocator.dupe(u8, input_path),
        });
    }

    pub fn loadedProjectForDocument(self: *Server, document_path: []const u8) ?*ProjectState {
        var selected: ?*ProjectState = null;
        var selected_score: usize = 0;
        for (self.projects.items) |*project| {
            if (!self.projectContainsPath(project, document_path)) continue;
            var score: usize = if (project.current != null) 2 else 1;
            for (self.documents.items) |document| {
                if (std.mem.eql(u8, document.path, document_path)) continue;
                if (self.projectContainsPath(project, document.path)) score += 4;
            }
            if (selected == null or score > selected_score) {
                selected = project;
                selected_score = score;
            }
        }
        return selected;
    }

    pub fn workspaceForPath(self: *const Server, path: []const u8) ?[]const u8 {
        var matched: ?[]const u8 = null;
        for (self.workspace_roots.items) |root| if (self.pathWithin(path, root)) {
            if (matched == null or root.len > matched.?.len) matched = root;
        };
        return matched;
    }

    pub fn projectForDocument(self: *Server, document: *const Document) ?*ProjectState {
        return self.loadedProjectForDocument(document.path);
    }

    pub fn projectByInput(self: *Server, input_path: []const u8) ?*ProjectState {
        for (self.projects.items) |*project| if (std.mem.eql(u8, project.input_path, input_path)) return project;
        return null;
    }

    pub fn projectHasOpenDocument(self: *const Server, project: *const ProjectState) bool {
        for (self.documents.items) |document| {
            if (project.current) |snapshot| for (snapshot.source_paths) |path| {
                if (std.mem.eql(u8, path, document.path)) return true;
            };
            if (project.failure) |failure| for (failure.source_paths) |path| {
                if (std.mem.eql(u8, path, document.path)) return true;
            };
        }
        return false;
    }

    pub fn fallbackAllowed(self: *const Server, project: *const ProjectState, changing_path: []const u8) bool {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.path, changing_path)) continue;
            var matched = false;
            for (project.last_versions) |stamp| {
                if (!std.mem.eql(u8, stamp.path, document.path)) continue;
                if (stamp.version != document.version) return false;
                matched = true;
                break;
            }
            if (!matched and project.last_success != null and self.snapshotFile(&project.last_success.?, document.path) != null) return false;
        }
        return true;
    }

    pub fn requestContext(self: *Server, params: std.json.Value) ?RequestContext {
        const uri = self.textDocumentUri(params) orelse return null;
        const document = self.findDocument(uri) orelse return null;
        const project = self.projectForDocument(document) orelse return null;
        const snapshot = if (project.current) |*value| value else return null;
        var file: ?usize = null;
        for (snapshot.source_paths, 0..) |path, index| if (std.mem.eql(u8, path, document.path)) {
            file = index;
            break;
        };
        const file_index = file orelse return null;
        const requested = self.completionPosition(params) orelse return null;
        const offset = self.byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse return null;
        const source_position = self.sourcePositionAtByteOffset(document.text, file_index, offset);
        const occurrence = snapshot.index.occurrenceAt(
            file_index,
            source_position.line,
            source_position.column,
        ) orelse return null;
        return .{ .document = document, .snapshot = snapshot, .file = file_index, .occurrence = occurrence };
    }

    pub fn definition(self: *Server, params: std.json.Value) !?Location {
        const context = self.requestContext(params) orelse return null;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        if (self.projectForDocument(context.document)) |project| {
            try self.rememberProjectInput(context.snapshot.source_paths[symbol.definition.file], project.input_path);
        }
        return try self.location(context.snapshot, symbol.definition, symbol.name.len);
    }

    pub fn references(self: *Server, params: std.json.Value) ![]const Location {
        const context = self.requestContext(params) orelse return self.allocator.alloc(Location, 0);
        const include_declaration = if (self.objectMember(params, "context")) |value|
            self.booleanMember(value, "includeDeclaration") orelse false
        else
            false;
        var locations: std.ArrayList(Location) = .empty;
        for (context.snapshot.index.occurrences) |occurrence| {
            if (occurrence.symbol != context.occurrence.symbol or (occurrence.definition and !include_declaration)) continue;
            if (self.projectForDocument(context.document)) |project| {
                try self.rememberProjectInput(context.snapshot.source_paths[occurrence.position.file], project.input_path);
            }
            try locations.append(self.allocator, try self.location(
                context.snapshot,
                occurrence.position,
                occurrence.length,
            ));
        }
        std.mem.sort(Location, locations.items, {}, struct {
            fn lessThan(_: void, left: Location, right: Location) bool {
                const order = std.mem.order(u8, left.uri, right.uri);
                if (order != .eq) return order == .lt;
                if (left.range.start.line != right.range.start.line) return left.range.start.line < right.range.start.line;
                return left.range.start.character < right.range.start.character;
            }
        }.lessThan);
        return locations.toOwnedSlice(self.allocator);
    }

    pub fn hover(self: *Server, params: std.json.Value) !?Hover {
        const context = self.requestContext(params) orelse return null;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        const origin = switch (symbol.origin) {
            .application => "application",
            .local => "local module",
            .package => "package",
            .distributed => "distributed library",
        };
        const path = context.snapshot.source_paths[symbol.definition.file];
        return .{
            .contents = .{ .value = try std.fmt.allocPrint(
                self.allocator,
                "```silex\n{s}\n```\n\nmodule: `{s}`  \nsource: `{s}` ({s})",
                .{ symbol.detail, symbol.module_name, path, origin },
            ) },
            .range = try self.rangeFor(context.snapshot, context.occurrence.position, context.occurrence.length),
        };
    }

    pub fn prepareRename(self: *Server, params: std.json.Value) RenameError!PreparedRename {
        const context = self.requestContext(params) orelse return error.InvalidPosition;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        try self.requireRenamable(context.snapshot, symbol.id);
        return .{
            .range = self.rangeFor(context.snapshot, context.occurrence.position, context.occurrence.length) catch return error.InvalidPosition,
            .placeholder = symbol.name,
        };
    }

    pub fn rename(self: *Server, params: std.json.Value) (RenameError || Allocator.Error)!WorkspaceEdit {
        const context = self.requestContext(params) orelse return error.InvalidPosition;
        const new_name = self.stringMember(params, "newName") orelse return error.InvalidName;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        try self.requireRenamable(context.snapshot, symbol.id);
        if (!self.validIdentifier(new_name) or std.mem.eql(u8, new_name, symbol.name)) return error.InvalidName;
        if (!self.canonicalRename(symbol.kind, new_name)) return error.NonCanonicalName;
        for (context.snapshot.index.symbols) |existing| {
            if (existing.rename_group != symbol.rename_group and std.mem.eql(u8, existing.name, new_name)) return error.Collision;
        }

        const project = self.projectForDocument(context.document) orelse return error.ValidationFailed;
        var validation_overlays: std.ArrayList(Frontend.Overlay) = .empty;
        for (context.snapshot.source_paths, context.snapshot.source_contents, 0..) |path, source, file| {
            try validation_overlays.append(self.allocator, .{
                .path = path,
                .text = try self.renamedSource(
                    self.allocator,
                    source,
                    file,
                    context.snapshot.index,
                    symbol.rename_group,
                    new_name,
                ),
            });
        }
        const validation = Frontend.analyze(
            self.allocator,
            self.io,
            self.environ_map,
            project.input_path,
            .editor,
            validation_overlays.items,
        ) catch return error.ValidationFailed;
        const validated = switch (validation) {
            .success => |snapshot| snapshot,
            .failure => return error.ValidationFailed,
        };
        var validated_occurrences: usize = 0;
        for (validated.index.symbols) |candidate| {
            if (!std.mem.eql(u8, candidate.name, new_name) or
                !self.renameGroupHasKind(context.snapshot.index, symbol.rename_group, candidate.kind))
            {
                continue;
            }
            for (validated.index.occurrences) |occurrence| if (occurrence.symbol == candidate.id) {
                validated_occurrences += 1;
            };
        }
        var original_occurrences: usize = 0;
        for (context.snapshot.index.occurrences) |occurrence| {
            if (context.snapshot.index.symbol(occurrence.symbol).rename_group == symbol.rename_group) original_occurrences += 1;
        }
        if (validated_occurrences != original_occurrences) return error.ValidationFailed;

        var changes: std.ArrayList(TextDocumentEdit) = .empty;
        for (context.snapshot.source_paths, 0..) |path, file| {
            var edits: std.ArrayList(RenameEdit) = .empty;
            for (context.snapshot.index.occurrences) |occurrence| {
                if (context.snapshot.index.symbol(occurrence.symbol).rename_group != symbol.rename_group or
                    occurrence.position.file != file)
                {
                    continue;
                }
                try edits.append(self.allocator, .{
                    .range = try self.rangeFor(context.snapshot, occurrence.position, occurrence.length),
                    .newText = new_name,
                });
            }
            if (edits.items.len == 0) continue;
            std.mem.sort(RenameEdit, edits.items, {}, struct {
                fn lessThan(_: void, left: RenameEdit, right: RenameEdit) bool {
                    if (left.range.start.line != right.range.start.line) return left.range.start.line > right.range.start.line;
                    return left.range.start.character > right.range.start.character;
                }
            }.lessThan);
            const uri = try self.uriFromPath(self.allocator, path);
            try changes.append(self.allocator, .{
                .textDocument = .{ .uri = uri, .version = self.openVersion(path) },
                .edits = try edits.toOwnedSlice(self.allocator),
            });
        }
        return .{ .documentChanges = try changes.toOwnedSlice(self.allocator) };
    }

    pub fn requireRenamable(self: *const Server, snapshot: *const Frontend.Snapshot, symbol_id: usize) RenameError!void {
        const symbol = snapshot.index.symbol(symbol_id);
        if (symbol.kind == .constructor or symbol.kind == .module) return error.NotRenamable;
        for (snapshot.index.occurrences) |occurrence| {
            if (snapshot.index.symbol(occurrence.symbol).rename_group != symbol.rename_group) continue;
            const path = snapshot.source_paths[occurrence.position.file];
            const workspace = self.workspaceForPath(path) orelse return error.ExternalSource;
            _ = workspace;
            const module_index = snapshot.files[occurrence.position.file].module_index;
            const origin = snapshot.project.modules[module_index].origin;
            if (origin != .application and origin != .local) return error.ExternalSource;
        }
    }

    pub fn location(self: *Server, snapshot: *const Frontend.Snapshot, position: Source.Position, length: usize) !Location {
        return .{
            .uri = try self.uriFromPath(self.allocator, snapshot.source_paths[position.file]),
            .range = try self.rangeFor(snapshot, position, length),
        };
    }

    pub fn rangeFor(self: *const Server, snapshot: *const Frontend.Snapshot, position: Source.Position, length: usize) !Range {
        const source = snapshot.source_contents[position.file];
        const start_offset = self.sourceByteOffset(source, position);
        return .{
            .start = self.encodedPositionAtByteOffset(source, start_offset, self.position_encoding) orelse return error.InvalidPosition,
            .end = self.encodedPositionAtByteOffset(source, @min(source.len, start_offset + length), self.position_encoding) orelse return error.InvalidPosition,
        };
    }

    pub fn completion(self: *Server, params: std.json.Value) ![]const CompletionItem {
        const uri = self.textDocumentUri(params) orelse return self.allocator.alloc(CompletionItem, 0);
        const document = self.findDocument(uri) orelse return self.allocator.alloc(CompletionItem, 0);
        const requested = self.completionPosition(params) orelse return self.allocator.alloc(CompletionItem, 0);
        const normalized = self.normalizePosition(document.text, requested, self.position_encoding) orelse
            return self.allocator.alloc(CompletionItem, 0);
        if (self.useCompletionPrefix(document.text, normalized)) |prefix| {
            return self.useCompletionItems(self.allocator, self.io, uri, document.text, prefix);
        }
        const cursor = self.byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse
            return self.allocator.alloc(CompletionItem, 0);
        var namespace_items: []const CompletionItem = &.{};
        var namespace_qualified = false;
        if (self.qualifiedCompletionPrefix(document.text, cursor)) |context| {
            const module_path = try self.usedModulePath(self.allocator, document.text, context.qualifier) orelse context.qualifier;
            namespace_qualified = try self.completionNamespaceExists(self.allocator, self.io, uri, module_path);
            const exports = try self.moduleExportCompletionItems(
                self.allocator,
                self.io,
                uri,
                module_path,
                context,
                .qualified_expression,
            );
            namespace_items = try self.unqualifiedModuleCompletionItems(self.allocator, exports);
        }

        const project = self.projectForDocument(document) orelse return if (namespace_qualified)
            namespace_items
        else
            self.allocator.dupe(CompletionItem, &language_completions);
        var recovered_snapshot: ?Frontend.Snapshot = null;
        const snapshot = if (project.current) |*current|
            current
        else if (project.last_success) |*previous| fallback: {
            if (!self.fallbackAllowed(project, document.path)) return if (namespace_qualified)
                namespace_items
            else
                self.allocator.dupe(CompletionItem, &language_completions);
            break :fallback previous;
        } else recovery: {
            recovered_snapshot = try self.completionRecoverySnapshot(project.input_path, document, cursor);
            if (recovered_snapshot) |*recovered| break :recovery recovered;
            return if (namespace_qualified)
                namespace_items
            else
                self.allocator.dupe(CompletionItem, &language_completions);
        };
        const file = self.snapshotFile(snapshot, document.path) orelse return if (namespace_qualified)
            namespace_items
        else
            self.allocator.dupe(CompletionItem, &language_completions);

        if (try self.initializerFieldCompletionItems(snapshot, file, document.text, cursor)) |fields| {
            return fields;
        }

        if (try self.completionOwner(snapshot, file, document.text, cursor)) |owner| {
            var members: std.ArrayList(CompletionItem) = .empty;
            try members.appendSlice(self.allocator, namespace_items);
            for (snapshot.index.symbols) |symbol| {
                if (!std.mem.eql(u8, symbol.owner, owner.key) or symbol.is_static != owner.static) continue;
                if (!self.symbolVisibleFromFile(snapshot, file, symbol)) continue;
                if (self.containsCompletion(members.items, symbol.name)) continue;
                try members.append(self.allocator, self.completionItemForSymbol(symbol));
            }
            return members.toOwnedSlice(self.allocator);
        }
        if (namespace_qualified) return namespace_items;

        var items: std.ArrayList(CompletionItem) = .empty;
        try items.appendSlice(self.allocator, &language_completions);
        const cursor_position = self.sourcePositionAtByteOffset(document.text, file, cursor);
        for (snapshot.index.symbols) |symbol| {
            if (symbol.owner.len != 0) continue;
            const local = switch (symbol.kind) {
                .parameter, .variable, .binding, .type_parameter => true,
                else => false,
            };
            if (local and (symbol.definition.file != file or self.positionAfter(symbol.definition, cursor_position))) continue;
            if (!local and !self.symbolVisibleFromFile(snapshot, file, symbol)) continue;
            if (!self.containsCompletion(items.items, symbol.name)) try items.append(self.allocator, self.completionItemForSymbol(symbol));
        }
        return items.toOwnedSlice(self.allocator);
    }

    pub fn initializerFieldCompletionItems(
        self: *Server,
        snapshot: *const Frontend.Snapshot,
        file: usize,
        source: []const u8,
        cursor: usize,
    ) !?[]const CompletionItem {
        const opening = try self.enclosingParenthesisAt(self.allocator, source, cursor) orelse return null;
        const callee = self.signatureCalleeAt(source, opening + 1) orelse return null;
        const argument_context = try self.namedArgumentContext(self.allocator, source, opening + 1, cursor) orelse return null;
        if (argument_context.current_has_colon or argument_context.current_is_value) return null;

        const owner = try self.initializerTypeSymbol(self.allocator, snapshot, file, source, callee) orelse return null;
        var structure: ?Semantic.Structure = null;
        for (snapshot.program.structures) |candidate| {
            if (std.mem.eql(u8, candidate.generated_name, owner.key)) {
                structure = candidate;
                break;
            }
        }
        const value = structure orelse return null;
        if (value.is_native_resource or value.constructors.len != 0 or
            (value.is_class and !value.implicit_constructor_available))
        {
            return null;
        }
        if (value.is_owner and snapshot.files[file].module_index != snapshot.files[owner.definition.file].module_index) {
            return try self.allocator.alloc(CompletionItem, 0);
        }

        var items: std.ArrayList(CompletionItem) = .empty;
        const owner_context = self.completionInsideOwnerCallable(snapshot, file, source, cursor, owner.key);
        for (snapshot.index.symbols) |symbol| {
            if (symbol.kind != .field or symbol.is_static or !std.mem.eql(u8, symbol.owner, owner.key)) continue;
            if (symbol.visibility != null and symbol.visibility.? != .public_access and !owner_context) continue;
            if (self.containsName(argument_context.supplied, symbol.name)) continue;
            try items.append(self.allocator, .{
                .label = symbol.name,
                .kind = 5,
                .detail = symbol.detail,
                .insertText = try std.fmt.allocPrint(self.allocator, "{s}:", .{symbol.name}),
                .filterText = symbol.name,
            });
        }
        return try items.toOwnedSlice(self.allocator);
    }

    pub fn completionRecoverySnapshot(
        self: *Server,
        input_path: []const u8,
        document: *const Document,
        cursor: usize,
    ) !?Frontend.Snapshot {
        const repaired = try self.blankLineAt(self.allocator, document.text, cursor);
        var overlays: std.ArrayList(Frontend.Overlay) = .empty;
        for (self.documents.items) |open_document| try overlays.append(self.allocator, .{
            .path = open_document.path,
            .text = if (std.mem.eql(u8, open_document.path, document.path)) repaired else open_document.text,
        });
        return switch (try self.analyzeInput(input_path, overlays.items)) {
            .success => |snapshot| snapshot,
            .failure => null,
        };
    }

    const CompletionOwner = struct { key: []const u8, static: bool };

    pub fn completionOwner(
        self: *Server,
        snapshot: *const Frontend.Snapshot,
        file: usize,
        source: []const u8,
        cursor: usize,
    ) !?CompletionOwner {
        var dot = @min(cursor, source.len);
        while (dot > 0 and (std.ascii.isWhitespace(source[dot - 1]) or self.isIdentifierContinue(source[dot - 1]))) dot -= 1;
        if (dot == 0 or source[dot - 1] != '.') return null;
        var end = dot - 1;
        while (end > 0 and std.ascii.isWhitespace(source[end - 1])) end -= 1;
        var start = end;
        while (start > 0 and self.isIdentifierContinue(source[start - 1])) start -= 1;
        if (start == end) return null;
        const position = self.sourcePositionAtByteOffset(source, file, start);
        const receiver = if (snapshot.index.occurrenceAt(file, position.line, position.column)) |occurrence|
            snapshot.index.symbol(occurrence.symbol)
        else
            self.fallbackCompletionReceiver(snapshot, file, source, start, end) orelse return null;
        if (receiver.kind == .type or receiver.kind == .enumeration) return .{ .key = receiver.key, .static = true };
        const type_name = self.detailTypeName(receiver.detail) orelse return null;
        for (snapshot.index.symbols) |symbol| {
            if ((symbol.kind == .type or symbol.kind == .enumeration) and std.mem.eql(u8, symbol.name, type_name)) {
                return .{ .key = symbol.key, .static = false };
            }
        }
        return null;
    }

    pub fn signatureHelp(self: *Server, params: std.json.Value) !SignatureHelpResult {
        const uri = self.textDocumentUri(params) orelse return .{ .signatures = &.{} };
        const document = self.findDocument(uri) orelse return .{ .signatures = &.{} };
        const requested = self.completionPosition(params) orelse return .{ .signatures = &.{} };
        const cursor = self.byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse
            return .{ .signatures = &.{} };
        const callee = self.signatureCalleeAt(document.text, cursor) orelse return .{ .signatures = &.{} };
        const project = self.projectForDocument(document) orelse return .{ .signatures = &.{} };
        const snapshot = if (project.current) |*current|
            current
        else if (project.last_success) |*previous| fallback: {
            if (!self.fallbackAllowed(project, document.path)) return .{ .signatures = &.{} };
            break :fallback previous;
        } else return .{ .signatures = &.{} };
        const file = self.snapshotFile(snapshot, document.path) orelse return .{ .signatures = &.{} };
        const member_owner = try self.completionOwner(snapshot, file, document.text, callee.start);
        var constructor_owner: ?[]const u8 = null;
        if (member_owner == null) for (snapshot.index.symbols) |candidate| {
            if ((candidate.kind == .type or candidate.kind == .enumeration) and
                std.mem.eql(u8, candidate.name, callee.name) and self.symbolVisibleFromFile(snapshot, file, candidate))
            {
                if (constructor_owner != null) {
                    constructor_owner = null;
                    break;
                }
                constructor_owner = candidate.key;
            }
        };
        var signatures: std.ArrayList(SignatureInformation) = .empty;
        for (snapshot.index.symbols) |symbol| {
            if (symbol.kind != .function and symbol.kind != .method and symbol.kind != .requirement and symbol.kind != .constructor) continue;
            if (member_owner) |owner| {
                if (!std.mem.eql(u8, symbol.name, callee.name) or
                    !std.mem.eql(u8, symbol.owner, owner.key) or symbol.is_static != owner.static)
                {
                    continue;
                }
            } else if (constructor_owner) |owner| {
                if (symbol.kind != .constructor or !std.mem.eql(u8, symbol.owner, owner)) continue;
            } else {
                if (!std.mem.eql(u8, symbol.name, callee.name) or symbol.owner.len != 0 or
                    !self.symbolVisibleFromFile(snapshot, file, symbol))
                {
                    continue;
                }
            }
            try signatures.append(self.allocator, .{
                .label = symbol.detail,
                .parameters = try self.signatureParameters(self.allocator, symbol.detail),
            });
        }
        return .{
            .signatures = try signatures.toOwnedSlice(self.allocator),
            .activeParameter = self.activeParameterAt(document.text, cursor),
        };
    }

    pub fn semanticTokens(self: *Server, params: std.json.Value) !SemanticTokens {
        const uri = self.textDocumentUri(params) orelse return .{ .data = &.{} };
        const document = self.findDocument(uri) orelse return .{ .data = &.{} };
        const project = self.projectForDocument(document) orelse return .{ .data = &.{} };
        const snapshot = if (project.current) |*value| value else return .{ .data = &.{} };
        const file = self.snapshotFile(snapshot, document.path) orelse return .{ .data = &.{} };
        return .{ .data = try self.semanticTokenData(
            self.allocator,
            snapshot.index,
            file,
            document.text,
            self.position_encoding,
        ) };
    }

    pub fn openVersion(self: *const Server, path: []const u8) ?i64 {
        for (self.documents.items) |document| if (std.mem.eql(u8, document.path, path)) return document.version;
        return null;
    }

    pub fn publishDiagnostics(self: *Server, uri: []const u8, source: []const u8) !void {
        try self.sendNotification("textDocument/publishDiagnostics", .{
            .uri = uri,
            .diagnostics = try self.diagnosticsWithEncoding(self.allocator, source, self.position_encoding),
        });
    }
    pub const readMessage = Protocol.readMessage;
    pub const documentFromOpen = Protocol.documentFromOpen;
    pub const documentFromChange = Protocol.documentFromChange;
    pub const textDocumentUri = Protocol.textDocumentUri;
    pub const completionPosition = Protocol.completionPosition;
    pub const negotiatedPositionEncoding = Protocol.negotiatedPositionEncoding;
    pub const formattingOutcome = Protocol.formattingOutcome;
    pub const objectMember = Protocol.objectMember;
    pub const stringMember = Protocol.stringMember;
    pub const booleanMember = Protocol.booleanMember;
    pub const unsignedMember = Protocol.unsignedMember;
    pub const integerMember = Protocol.integerMember;
    pub const sourcePositionAtByteOffset = Protocol.sourcePositionAtByteOffset;
    pub const sourceByteOffset = Protocol.sourceByteOffset;
    pub const semanticTokenData = Protocol.semanticTokenData;
    pub const semanticTokenKind = Protocol.semanticTokenKind;
    pub const followedByInvocation = Protocol.followedByInvocation;
    pub const pathWithin = Protocol.pathWithin;
    pub const uriFromPath = Protocol.uriFromPath;
    pub const manifestDeclares = Protocol.manifestDeclares;
    pub const moduleAnalysisInput = Protocol.moduleAnalysisInput;
    pub const singleSourceRootForDocument = Protocol.singleSourceRootForDocument;
    pub const sourceDefinesMain = Protocol.sourceDefinesMain;
    pub const moduleNameFromSource = Protocol.moduleNameFromSource;
    pub const moduleNameFromDirectories = Protocol.moduleNameFromDirectories;
    pub const validIdentifier = Protocol.validIdentifier;
    pub const canonicalRename = Protocol.canonicalRename;
    pub const renameErrorMessage = Protocol.renameErrorMessage;
    pub const snapshotFile = Protocol.snapshotFile;
    pub const projectContainsPath = Protocol.projectContainsPath;
    pub const positionAfter = Protocol.positionAfter;
    pub const completionItemForSymbol = Protocol.completionItemForSymbol;
    pub const detailTypeName = Protocol.detailTypeName;
    pub const blankLineAt = Protocol.blankLineAt;
    pub const fallbackCompletionReceiver = Protocol.fallbackCompletionReceiver;
    pub const callableNameAt = Protocol.callableNameAt;
    pub const signatureParameters = Protocol.signatureParameters;
    pub const appendSignatureParameter = Protocol.appendSignatureParameter;
    pub const activeParameterAt = Protocol.activeParameterAt;
    pub const renamedSource = Features.renamedSource;
    pub const renameGroupHasKind = Features.renameGroupHasKind;
    pub const syntaxDiagnostic = Features.syntaxDiagnostic;
    pub const syntaxDiagnosticWithEncoding = Features.syntaxDiagnosticWithEncoding;
    pub const diagnosticsWithEncoding = Features.diagnosticsWithEncoding;
    pub const diagnosticFromSource = Features.diagnosticFromSource;
    pub const sourceDiagnosticByteOffset = Features.sourceDiagnosticByteOffset;
    pub const enclosingParenthesisAt = Features.enclosingParenthesisAt;
    pub const namedArgumentContext = Features.namedArgumentContext;
    pub const initializerTypeSymbol = Features.initializerTypeSymbol;
    pub const calleeQualifierAt = Features.calleeQualifierAt;
    pub const principalModuleMatches = Features.principalModuleMatches;
    pub const containsName = Features.containsName;
    pub const completionInsideOwnerCallable = Features.completionInsideOwnerCallable;
    pub const signatureCalleeAt = Features.signatureCalleeAt;
    pub const symbolVisibleFromFile = Features.symbolVisibleFromFile;
    pub const useCompletionPrefix = Features.useCompletionPrefix;
    pub const usedModulePath = Features.usedModulePath;
    pub const directiveBody = Features.directiveBody;
    pub const looksLikeTypeAliasTarget = Features.looksLikeTypeAliasTarget;
    pub const expandVisibleModulePath = Features.expandVisibleModulePath;
    pub const pathHasModuleQualifier = Features.pathHasModuleQualifier;
    pub const qualifiedCompletionPrefix = Features.qualifiedCompletionPrefix;
    pub const lastPathSegment = Completion.lastPathSegment;
    pub const firstPathSegment = Completion.firstPathSegment;
    pub const moduleExportCompletionItems = Completion.moduleExportCompletionItems;
    pub const moduleCompletionRoot = Completion.moduleCompletionRoot;
    pub const completionNamespaceExists = Completion.completionNamespaceExists;
    pub const lspNamespaceExists = Completion.lspNamespaceExists;
    pub const lspCompactDescendantExists = Completion.lspCompactDescendantExists;
    pub const appendCompactChildCompletions = Completion.appendCompactChildCompletions;
    pub const namespaceHasPublicApiOrChildren = Completion.namespaceHasPublicApiOrChildren;
    pub const namespaceSourcePaths = Completion.namespaceSourcePaths;
    pub const lspDirectoryExists = Completion.lspDirectoryExists;
    pub const appendModuleExportCompletion = Completion.appendModuleExportCompletion;
    pub const unqualifiedModuleCompletionItems = Completion.unqualifiedModuleCompletionItems;
    pub const moduleDirectoryPath = Completion.moduleDirectoryPath;
    pub const localModuleCompletionItems = Completion.localModuleCompletionItems;
    pub const useCompletionItems = Completion.useCompletionItems;
    pub const collectRootModules = Completion.collectRootModules;
    pub const filePathFromUri = Completion.filePathFromUri;
    pub const documentProjectRoot = Completion.documentProjectRoot;
    pub const hexDigit = Completion.hexDigit;
    pub const byteOffsetAtPosition = Completion.byteOffsetAtPosition;
    pub const normalizePosition = Completion.normalizePosition;
    pub const byteOffsetAtEncodedPosition = Completion.byteOffsetAtEncodedPosition;
    pub const encodedPositionAtByteOffset = Completion.encodedPositionAtByteOffset;
    pub const documentEndPosition = Completion.documentEndPosition;
    pub const utf8SequenceLength = Completion.utf8SequenceLength;
    pub const isIdentifierContinue = Completion.isIdentifierContinue;
    pub const containsCompletion = Completion.containsCompletion;
    pub const expectSemanticTokenAt = Completion.expectSemanticTokenAt;
    const RenameSpan = Features.RenameSpan;
    const SignatureCallee = Features.SignatureCallee;
    const NamedArgumentContext = Features.NamedArgumentContext;
    const VisibleModule = Features.VisibleModule;
    const language_completions = Completion.language_completions;
};

pub fn run(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map) !u8 {
    var server = Server.init(allocator, io, environ_map);
    try server.run();
    return 0;
}
