const std = @import("std");
const build_options = @import("build_options");
const Ast = @import("Ast.zig");
const Formatter = @import("Formatter.zig");
const Frontend = @import("Frontend.zig");
const LexerModule = @import("Lexer.zig");
const Lint = @import("Lint.zig");
const ModuleDiscovery = @import("ModuleDiscovery.zig");
const ModuleManifest = @import("ModuleManifest.zig");
const ParserModule = @import("Parser.zig");
const ProjectModule = @import("Project.zig");
const Semantic = @import("Semantic.zig");
const Source = @import("Source.zig");
const StandardLibrary = @import("StandardLibrary.zig");
const SourceGraph = @import("SourceGraph.zig");
const SymbolIndex = @import("SymbolIndex.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const protocol_version = "2.0";
const max_message_size = 16 * 1024 * 1024;
const completion_trigger_characters = [_][]const u8{"."};
const module_analysis_directory = ".silex-lsp";

const Document = struct {
    uri: []const u8,
    path: []const u8 = "",
    text: []const u8,
    version: i64 = 0,
};

const ProjectState = struct {
    input_path: []const u8,
    current: ?Frontend.Snapshot = null,
    last_success: ?Frontend.Snapshot = null,
    failure: ?Frontend.Failure = null,
    published_uris: []const []const u8 = &.{},
    last_versions: []const VersionStamp = &.{},
};

const VersionStamp = struct { path: []const u8, version: i64 };
const ProjectAffinity = struct { path: []const u8, input_path: []const u8 };
const ModuleAnalysisProject = struct {
    root: []const u8,
    project: ProjectModule.Project,
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
    parameters: []const SignatureParameter = &.{},
};

const SignatureParameter = struct {
    label: [2]usize,
};

const SignatureHelpResult = struct {
    signatures: []const SignatureInformation,
    activeSignature: usize = 0,
    activeParameter: usize = 0,
};

const Location = struct {
    uri: []const u8,
    range: Range,
};

const RenameEdit = struct {
    range: Range,
    newText: []const u8,
};

const TextDocumentEdit = struct {
    textDocument: struct {
        uri: []const u8,
        version: ?i64,
    },
    edits: []const RenameEdit,
};

const MarkupContent = struct {
    kind: []const u8 = "markdown",
    value: []const u8,
};

const Hover = struct {
    contents: MarkupContent,
    range: Range,
};

const PreparedRename = struct {
    range: Range,
    placeholder: []const u8,
};

const WorkspaceEdit = struct {
    documentChanges: []const TextDocumentEdit,
};

const RequestContext = struct {
    document: *const Document,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    occurrence: SymbolIndex.Occurrence,
};

const RenameError = error{
    InvalidPosition,
    NotRenamable,
    InvalidName,
    NonCanonicalName,
    Collision,
    ExternalSource,
    ValidationFailed,
};

const QualifiedCompletionContext = struct {
    qualifier: []const u8,
    prefix: []const u8,
    type_only: bool,
};

const ModuleExportScope = enum {
    public_api,
    use_path,
    qualified_expression,
};

const Position = struct {
    line: usize,
    character: usize,
};

const Range = struct {
    start: Position,
    end: Position,
};

const PositionEncoding = enum {
    utf8,
    utf16,
    utf32,

    fn protocolName(self: PositionEncoding) []const u8 {
        return switch (self) {
            .utf8 => "utf-8",
            .utf16 => "utf-16",
            .utf32 => "utf-32",
        };
    }
};

const TextEdit = struct {
    range: Range,
    newText: []const u8,
};

const FormattingOutcome = union(enum) {
    edits: []const TextEdit,
    diagnostic: Source.Diagnostic,
};

const Diagnostic = struct {
    range: Range,
    severity: u8 = 1,
    source: []const u8 = "silex",
    code: ?[]const u8 = null,
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
    environ_map: *const std.process.Environ.Map,
    documents: std.ArrayList(Document) = .empty,
    projects: std.ArrayList(ProjectState) = .empty,
    workspace_roots: std.ArrayList([]const u8) = .empty,
    configured_project: ?[]const u8 = null,
    project_affinities: std.ArrayList(ProjectAffinity) = .empty,
    position_encoding: PositionEncoding = .utf16,

    fn init(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map) Server {
        return .{ .allocator = allocator, .io = io, .environ_map = environ_map };
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
            self.position_encoding = negotiatedPositionEncoding(request.params);
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
                    try self.setDocument(document.uri, document.text, document.version);
                    try self.analyzeAndPublish(document.uri);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didChange")) {
            if (request.params) |params| {
                if (documentFromChange(params)) |document| {
                    try self.setDocument(document.uri, document.text, document.version);
                    try self.analyzeAndPublish(document.uri);
                }
            }
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/didClose")) {
            if (request.params) |params| {
                if (textDocumentUri(params)) |uri| {
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
                try self.replyRequestFailed(id, renameErrorMessage(err));
                return;
            };
            try self.reply(id, prepared);
            return;
        }

        if (std.mem.eql(u8, request.method, "textDocument/rename")) {
            const id = request.id orelse return;
            const params = request.params orelse return self.replyInvalidParams(id, "missing rename parameters");
            const edit = self.rename(params) catch |err| {
                try self.replyRequestFailed(id, renameErrorMessage(err));
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

        if (std.mem.eql(u8, request.method, "textDocument/formatting")) {
            const id = request.id orelse return;
            const params = request.params orelse {
                try self.replyInvalidParams(id, "missing formatting parameters");
                return;
            };
            const uri = textDocumentUri(params) orelse {
                try self.replyInvalidParams(id, "missing text document URI");
                return;
            };
            const source = self.documentText(uri) orelse {
                try self.replyInvalidParams(id, "document is not open");
                return;
            };
            switch (try formattingOutcome(self.allocator, source, self.position_encoding)) {
                .edits => |edits| try self.reply(id, edits),
                .diagnostic => |diagnostic| try self.replyFormattingError(id, diagnostic),
            }
        }
    }

    fn reply(self: *Server, id: std.json.Value, result: anytype) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .result = result,
        });
    }

    fn replyInvalidParams(self: *Server, id: std.json.Value, message: []const u8) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .@"error" = .{
                .code = @as(i32, -32602),
                .message = message,
            },
        });
    }

    fn replyRequestFailed(self: *Server, id: std.json.Value, message: []const u8) !void {
        try self.send(.{
            .jsonrpc = protocol_version,
            .id = id,
            .@"error" = .{ .code = @as(i32, -32803), .message = message },
        });
    }

    fn replyFormattingError(self: *Server, id: std.json.Value, diagnostic: Source.Diagnostic) !void {
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

    fn setDocument(self: *Server, uri: []const u8, text: []const u8, version: i64) !void {
        const decoded_path = try filePathFromUri(self.allocator, uri) orelse return;
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

    fn findDocument(self: *const Server, uri: []const u8) ?*const Document {
        for (self.documents.items) |*document| if (std.mem.eql(u8, document.uri, uri)) return document;
        return null;
    }

    fn configureWorkspace(self: *Server, params: std.json.Value) !void {
        if (objectMember(params, "workspaceFolders")) |folders| {
            if (folders == .array) for (folders.array.items) |folder| {
                const uri = stringMember(folder, "uri") orelse continue;
                const decoded = try filePathFromUri(self.allocator, uri) orelse continue;
                try self.workspace_roots.append(
                    self.allocator,
                    try SourceGraph.canonicalPath(self.allocator, self.io, decoded),
                );
            };
        }
        if (self.workspace_roots.items.len == 0) if (stringMember(params, "rootUri")) |uri| {
            const decoded = try filePathFromUri(self.allocator, uri) orelse return;
            try self.workspace_roots.append(
                self.allocator,
                try SourceGraph.canonicalPath(self.allocator, self.io, decoded),
            );
        };
        const options = objectMember(params, "initializationOptions") orelse return;
        const configured = stringMember(options, "silex.project") orelse configured: {
            const silex = objectMember(options, "silex") orelse break :configured null;
            break :configured stringMember(silex, "project");
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

    fn analyzeAndPublish(self: *Server, uri: []const u8) !void {
        const document = self.findDocument(uri) orelse return;
        const input = try self.inputForDocument(document.path) orelse {
            try self.clearDiagnostics(uri);
            return;
        };
        try self.analyzeInputAndPublish(input);
    }

    fn analyzeInputAndPublish(self: *Server, input_path: []const u8) !void {
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
                    if (snapshotFile(&snapshot, document.path) != null) try versions.append(self.allocator, .{
                        .path = document.path,
                        .version = document.version,
                    });
                }
                state.last_versions = try versions.toOwnedSlice(self.allocator);
                state.failure = null;
                for (snapshot.source_paths, snapshot.source_contents) |path, source| {
                    const uri = try uriFromPath(self.allocator, path);
                    try published.append(self.allocator, uri);
                    try self.sendNotification("textDocument/publishDiagnostics", .{
                        .uri = uri,
                        .diagnostics = try diagnosticsWithEncoding(self.allocator, source, self.position_encoding),
                    });
                }
            },
            .failure => |failure| {
                state.current = null;
                state.failure = failure;
                const diagnostic_file = failure.diagnostic.position.file;
                for (failure.source_paths, 0..) |path, file| {
                    const uri = try uriFromPath(self.allocator, path);
                    try published.append(self.allocator, uri);
                    const source = if (file < failure.source_contents.len) failure.source_contents[file] else "";
                    const diagnostics = if (file == diagnostic_file)
                        try self.allocator.dupe(Diagnostic, &.{diagnosticFromSource(
                            source,
                            failure.diagnostic,
                            self.position_encoding,
                        )})
                    else
                        try diagnosticsWithEncoding(self.allocator, source, self.position_encoding);
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

    fn analyzeInput(
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

    fn clearDiagnostics(self: *Server, uri: []const u8) !void {
        try self.sendNotification("textDocument/publishDiagnostics", .{
            .uri = uri,
            .diagnostics = &[_]Diagnostic{},
        });
    }

    fn inputForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
        if (self.configured_project) |configured| {
            if (std.mem.eql(u8, configured, document_path) or
                try manifestDeclares(self.allocator, self.io, configured, document_path) or
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
                    if (try manifestDeclares(self.allocator, self.io, path, document_path)) {
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

    fn moduleAnalysisInputForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
        const module_directory = std.fs.path.dirname(document_path) orelse return null;
        const root = try self.moduleAnalysisRootForDocument(document_path) orelse return null;
        _ = try moduleNameFromSource(self.allocator, root, document_path) orelse return null;
        return try std.fs.path.join(self.allocator, &.{
            module_directory,
            module_analysis_directory,
            std.fs.path.basename(document_path),
        });
    }

    fn moduleAnalysisProject(self: *Server, input_path: []const u8) !?ModuleAnalysisProject {
        if (!moduleAnalysisInput(input_path)) return null;
        const analysis_directory = std.fs.path.dirname(input_path) orelse return null;
        const module_directory = std.fs.path.dirname(analysis_directory) orelse return null;
        const source_path = try std.fs.path.join(self.allocator, &.{
            module_directory,
            std.fs.path.basename(input_path),
        });
        const root = try self.moduleAnalysisRootForDocument(source_path) orelse return null;
        const module_name = try moduleNameFromSource(self.allocator, root, source_path) orelse return null;
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

    fn moduleAnalysisRootForDocument(self: *Server, document_path: []const u8) !?[]const u8 {
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
            if (singleSourceRootForDocument(input_path, document_path)) |root| return root;
        }
        var selected: ?[]const u8 = null;
        for (self.projects.items) |project| {
            const root = singleSourceRootForDocument(project.input_path, document_path) orelse continue;
            if (selected == null or root.len > selected.?.len) selected = root;
        }
        if (selected) |root| return root;
        return self.discoverSingleSourceRoot(document_path);
    }

    fn discoverSingleSourceRoot(self: *Server, document_path: []const u8) !?[]const u8 {
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
                    if (sourceDefinesMain(self.allocator, source)) return directory;
                }
            }
            if (std.mem.eql(u8, directory, workspace)) break;
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory) or !pathWithin(parent, workspace)) break;
            directory = parent;
        }
        return null;
    }

    fn openDocumentSource(self: *const Server, path: []const u8) ?[]const u8 {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.path, path)) return document.text;
        }
        return null;
    }

    fn moduleManifestDirectory(self: *Server, start: []const u8) !?[]const u8 {
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

    fn projectInputContains(self: *const Server, input_path: []const u8, document_path: []const u8) bool {
        for (self.projects.items) |project| {
            if (!std.mem.eql(u8, project.input_path, input_path)) continue;
            return projectContainsPath(&project, document_path);
        }
        return false;
    }

    fn preferredProjectInput(self: *const Server, document_path: []const u8) ?[]const u8 {
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

    fn rememberProjectInput(self: *Server, document_path: []const u8, input_path: []const u8) !void {
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

    fn loadedProjectForDocument(self: *Server, document_path: []const u8) ?*ProjectState {
        var selected: ?*ProjectState = null;
        var selected_score: usize = 0;
        for (self.projects.items) |*project| {
            if (!projectContainsPath(project, document_path)) continue;
            var score: usize = if (project.current != null) 2 else 1;
            for (self.documents.items) |document| {
                if (std.mem.eql(u8, document.path, document_path)) continue;
                if (projectContainsPath(project, document.path)) score += 4;
            }
            if (selected == null or score > selected_score) {
                selected = project;
                selected_score = score;
            }
        }
        return selected;
    }

    fn workspaceForPath(self: *const Server, path: []const u8) ?[]const u8 {
        var matched: ?[]const u8 = null;
        for (self.workspace_roots.items) |root| if (pathWithin(path, root)) {
            if (matched == null or root.len > matched.?.len) matched = root;
        };
        return matched;
    }

    fn projectForDocument(self: *Server, document: *const Document) ?*ProjectState {
        return self.loadedProjectForDocument(document.path);
    }

    fn projectByInput(self: *Server, input_path: []const u8) ?*ProjectState {
        for (self.projects.items) |*project| if (std.mem.eql(u8, project.input_path, input_path)) return project;
        return null;
    }

    fn projectHasOpenDocument(self: *const Server, project: *const ProjectState) bool {
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

    fn fallbackAllowed(self: *const Server, project: *const ProjectState, changing_path: []const u8) bool {
        for (self.documents.items) |document| {
            if (std.mem.eql(u8, document.path, changing_path)) continue;
            var matched = false;
            for (project.last_versions) |stamp| {
                if (!std.mem.eql(u8, stamp.path, document.path)) continue;
                if (stamp.version != document.version) return false;
                matched = true;
                break;
            }
            if (!matched and project.last_success != null and snapshotFile(&project.last_success.?, document.path) != null) return false;
        }
        return true;
    }

    fn requestContext(self: *Server, params: std.json.Value) ?RequestContext {
        const uri = textDocumentUri(params) orelse return null;
        const document = self.findDocument(uri) orelse return null;
        const project = self.projectForDocument(document) orelse return null;
        const snapshot = if (project.current) |*value| value else return null;
        var file: ?usize = null;
        for (snapshot.source_paths, 0..) |path, index| if (std.mem.eql(u8, path, document.path)) {
            file = index;
            break;
        };
        const file_index = file orelse return null;
        const requested = completionPosition(params) orelse return null;
        const offset = byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse return null;
        const source_position = sourcePositionAtByteOffset(document.text, file_index, offset);
        const occurrence = snapshot.index.occurrenceAt(
            file_index,
            source_position.line,
            source_position.column,
        ) orelse return null;
        return .{ .document = document, .snapshot = snapshot, .file = file_index, .occurrence = occurrence };
    }

    fn definition(self: *Server, params: std.json.Value) !?Location {
        const context = self.requestContext(params) orelse return null;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        if (self.projectForDocument(context.document)) |project| {
            try self.rememberProjectInput(context.snapshot.source_paths[symbol.definition.file], project.input_path);
        }
        return try self.location(context.snapshot, symbol.definition, symbol.name.len);
    }

    fn references(self: *Server, params: std.json.Value) ![]const Location {
        const context = self.requestContext(params) orelse return self.allocator.alloc(Location, 0);
        const include_declaration = if (objectMember(params, "context")) |value|
            booleanMember(value, "includeDeclaration") orelse false
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

    fn hover(self: *Server, params: std.json.Value) !?Hover {
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

    fn prepareRename(self: *Server, params: std.json.Value) RenameError!PreparedRename {
        const context = self.requestContext(params) orelse return error.InvalidPosition;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        try self.requireRenamable(context.snapshot, symbol.id);
        return .{
            .range = self.rangeFor(context.snapshot, context.occurrence.position, context.occurrence.length) catch return error.InvalidPosition,
            .placeholder = symbol.name,
        };
    }

    fn rename(self: *Server, params: std.json.Value) (RenameError || Allocator.Error)!WorkspaceEdit {
        const context = self.requestContext(params) orelse return error.InvalidPosition;
        const new_name = stringMember(params, "newName") orelse return error.InvalidName;
        const symbol = context.snapshot.index.symbol(context.occurrence.symbol);
        try self.requireRenamable(context.snapshot, symbol.id);
        if (!validIdentifier(new_name) or std.mem.eql(u8, new_name, symbol.name)) return error.InvalidName;
        if (!canonicalRename(symbol.kind, new_name)) return error.NonCanonicalName;
        for (context.snapshot.index.symbols) |existing| {
            if (existing.rename_group != symbol.rename_group and std.mem.eql(u8, existing.name, new_name)) return error.Collision;
        }

        const project = self.projectForDocument(context.document) orelse return error.ValidationFailed;
        var validation_overlays: std.ArrayList(Frontend.Overlay) = .empty;
        for (context.snapshot.source_paths, context.snapshot.source_contents, 0..) |path, source, file| {
            try validation_overlays.append(self.allocator, .{
                .path = path,
                .text = try renamedSource(
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
                !renameGroupHasKind(context.snapshot.index, symbol.rename_group, candidate.kind))
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
            const uri = try uriFromPath(self.allocator, path);
            try changes.append(self.allocator, .{
                .textDocument = .{ .uri = uri, .version = self.openVersion(path) },
                .edits = try edits.toOwnedSlice(self.allocator),
            });
        }
        return .{ .documentChanges = try changes.toOwnedSlice(self.allocator) };
    }

    fn requireRenamable(self: *const Server, snapshot: *const Frontend.Snapshot, symbol_id: usize) RenameError!void {
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

    fn location(self: *Server, snapshot: *const Frontend.Snapshot, position: Source.Position, length: usize) !Location {
        return .{
            .uri = try uriFromPath(self.allocator, snapshot.source_paths[position.file]),
            .range = try self.rangeFor(snapshot, position, length),
        };
    }

    fn rangeFor(self: *const Server, snapshot: *const Frontend.Snapshot, position: Source.Position, length: usize) !Range {
        const source = snapshot.source_contents[position.file];
        const start_offset = sourceByteOffset(source, position);
        return .{
            .start = encodedPositionAtByteOffset(source, start_offset, self.position_encoding) orelse return error.InvalidPosition,
            .end = encodedPositionAtByteOffset(source, @min(source.len, start_offset + length), self.position_encoding) orelse return error.InvalidPosition,
        };
    }

    fn completion(self: *Server, params: std.json.Value) ![]const CompletionItem {
        const uri = textDocumentUri(params) orelse return self.allocator.alloc(CompletionItem, 0);
        const document = self.findDocument(uri) orelse return self.allocator.alloc(CompletionItem, 0);
        const requested = completionPosition(params) orelse return self.allocator.alloc(CompletionItem, 0);
        const normalized = normalizePosition(document.text, requested, self.position_encoding) orelse
            return self.allocator.alloc(CompletionItem, 0);
        if (useCompletionPrefix(document.text, normalized)) |prefix| {
            return useCompletionItems(self.allocator, self.io, uri, document.text, prefix);
        }
        const cursor = byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse
            return self.allocator.alloc(CompletionItem, 0);
        var namespace_items: []const CompletionItem = &.{};
        var namespace_qualified = false;
        if (qualifiedCompletionPrefix(document.text, cursor)) |context| {
            const module_path = try usedModulePath(self.allocator, document.text, context.qualifier) orelse context.qualifier;
            namespace_qualified = try completionNamespaceExists(self.allocator, self.io, uri, module_path);
            const exports = try moduleExportCompletionItems(
                self.allocator,
                self.io,
                uri,
                module_path,
                context,
                .qualified_expression,
            );
            namespace_items = try unqualifiedModuleCompletionItems(self.allocator, exports);
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
        const file = snapshotFile(snapshot, document.path) orelse return if (namespace_qualified)
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
                if (!symbolVisibleFromFile(snapshot, file, symbol)) continue;
                if (containsCompletion(members.items, symbol.name)) continue;
                try members.append(self.allocator, completionItemForSymbol(symbol));
            }
            return members.toOwnedSlice(self.allocator);
        }
        if (namespace_qualified) return namespace_items;

        var items: std.ArrayList(CompletionItem) = .empty;
        try items.appendSlice(self.allocator, &language_completions);
        const cursor_position = sourcePositionAtByteOffset(document.text, file, cursor);
        for (snapshot.index.symbols) |symbol| {
            if (symbol.owner.len != 0) continue;
            const local = switch (symbol.kind) {
                .parameter, .variable, .binding, .type_parameter => true,
                else => false,
            };
            if (local and (symbol.definition.file != file or positionAfter(symbol.definition, cursor_position))) continue;
            if (!local and !symbolVisibleFromFile(snapshot, file, symbol)) continue;
            if (!containsCompletion(items.items, symbol.name)) try items.append(self.allocator, completionItemForSymbol(symbol));
        }
        return items.toOwnedSlice(self.allocator);
    }

    fn initializerFieldCompletionItems(
        self: *Server,
        snapshot: *const Frontend.Snapshot,
        file: usize,
        source: []const u8,
        cursor: usize,
    ) !?[]const CompletionItem {
        const opening = try enclosingParenthesisAt(self.allocator, source, cursor) orelse return null;
        const callee = signatureCalleeAt(source, opening + 1) orelse return null;
        const argument_context = try namedArgumentContext(self.allocator, source, opening + 1, cursor) orelse return null;
        if (argument_context.current_has_colon or argument_context.current_is_value) return null;

        const owner = try initializerTypeSymbol(self.allocator, snapshot, file, source, callee) orelse return null;
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
        const owner_context = completionInsideOwnerCallable(snapshot, file, source, cursor, owner.key);
        for (snapshot.index.symbols) |symbol| {
            if (symbol.kind != .field or symbol.is_static or !std.mem.eql(u8, symbol.owner, owner.key)) continue;
            if (symbol.visibility != null and symbol.visibility.? != .public_access and !owner_context) continue;
            if (containsName(argument_context.supplied, symbol.name)) continue;
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

    fn completionRecoverySnapshot(
        self: *Server,
        input_path: []const u8,
        document: *const Document,
        cursor: usize,
    ) !?Frontend.Snapshot {
        const repaired = try blankLineAt(self.allocator, document.text, cursor);
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

    fn completionOwner(
        self: *Server,
        snapshot: *const Frontend.Snapshot,
        file: usize,
        source: []const u8,
        cursor: usize,
    ) !?CompletionOwner {
        _ = self;
        var dot = @min(cursor, source.len);
        while (dot > 0 and (std.ascii.isWhitespace(source[dot - 1]) or isIdentifierContinue(source[dot - 1]))) dot -= 1;
        if (dot == 0 or source[dot - 1] != '.') return null;
        var end = dot - 1;
        while (end > 0 and std.ascii.isWhitespace(source[end - 1])) end -= 1;
        var start = end;
        while (start > 0 and isIdentifierContinue(source[start - 1])) start -= 1;
        if (start == end) return null;
        const position = sourcePositionAtByteOffset(source, file, start);
        const receiver = if (snapshot.index.occurrenceAt(file, position.line, position.column)) |occurrence|
            snapshot.index.symbol(occurrence.symbol)
        else
            fallbackCompletionReceiver(snapshot, file, source, start, end) orelse return null;
        if (receiver.kind == .type or receiver.kind == .enumeration) return .{ .key = receiver.key, .static = true };
        const type_name = detailTypeName(receiver.detail) orelse return null;
        for (snapshot.index.symbols) |symbol| {
            if ((symbol.kind == .type or symbol.kind == .enumeration) and std.mem.eql(u8, symbol.name, type_name)) {
                return .{ .key = symbol.key, .static = false };
            }
        }
        return null;
    }

    fn signatureHelp(self: *Server, params: std.json.Value) !SignatureHelpResult {
        const uri = textDocumentUri(params) orelse return .{ .signatures = &.{} };
        const document = self.findDocument(uri) orelse return .{ .signatures = &.{} };
        const requested = completionPosition(params) orelse return .{ .signatures = &.{} };
        const cursor = byteOffsetAtEncodedPosition(document.text, requested, self.position_encoding) orelse
            return .{ .signatures = &.{} };
        const callee = signatureCalleeAt(document.text, cursor) orelse return .{ .signatures = &.{} };
        const project = self.projectForDocument(document) orelse return .{ .signatures = &.{} };
        const snapshot = if (project.current) |*current|
            current
        else if (project.last_success) |*previous| fallback: {
            if (!self.fallbackAllowed(project, document.path)) return .{ .signatures = &.{} };
            break :fallback previous;
        } else return .{ .signatures = &.{} };
        const file = snapshotFile(snapshot, document.path) orelse return .{ .signatures = &.{} };
        const member_owner = try self.completionOwner(snapshot, file, document.text, callee.start);
        var constructor_owner: ?[]const u8 = null;
        if (member_owner == null) for (snapshot.index.symbols) |candidate| {
            if ((candidate.kind == .type or candidate.kind == .enumeration) and
                std.mem.eql(u8, candidate.name, callee.name) and symbolVisibleFromFile(snapshot, file, candidate))
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
                    !symbolVisibleFromFile(snapshot, file, symbol))
                {
                    continue;
                }
            }
            try signatures.append(self.allocator, .{
                .label = symbol.detail,
                .parameters = try signatureParameters(self.allocator, symbol.detail),
            });
        }
        return .{
            .signatures = try signatures.toOwnedSlice(self.allocator),
            .activeParameter = activeParameterAt(document.text, cursor),
        };
    }

    fn openVersion(self: *const Server, path: []const u8) ?i64 {
        for (self.documents.items) |document| if (std.mem.eql(u8, document.path, path)) return document.version;
        return null;
    }

    fn publishDiagnostics(self: *Server, uri: []const u8, source: []const u8) !void {
        try self.sendNotification("textDocument/publishDiagnostics", .{
            .uri = uri,
            .diagnostics = try diagnosticsWithEncoding(self.allocator, source, self.position_encoding),
        });
    }
};

pub fn run(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map) !u8 {
    var server = Server.init(allocator, io, environ_map);
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
        .version = integerMember(text_document, "version") orelse 0,
    };
}

fn documentFromChange(params: std.json.Value) ?Document {
    const uri = textDocumentUri(params) orelse return null;
    const changes = objectMember(params, "contentChanges") orelse return null;
    if (changes != .array or changes.array.items.len == 0) return null;
    return .{
        .uri = uri,
        .text = stringMember(changes.array.items[changes.array.items.len - 1], "text") orelse return null,
        .version = integerMember(objectMember(params, "textDocument") orelse return null, "version") orelse 0,
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

fn negotiatedPositionEncoding(params: ?std.json.Value) PositionEncoding {
    const capabilities = objectMember(params orelse return .utf16, "capabilities") orelse return .utf16;
    const general = objectMember(capabilities, "general") orelse return .utf16;
    const encodings = objectMember(general, "positionEncodings") orelse return .utf16;
    if (encodings != .array) return .utf16;
    for (encodings.array.items) |encoding| {
        if (encoding != .string) continue;
        if (std.mem.eql(u8, encoding.string, "utf-8")) return .utf8;
        if (std.mem.eql(u8, encoding.string, "utf-16")) return .utf16;
        if (std.mem.eql(u8, encoding.string, "utf-32")) return .utf32;
    }
    return .utf16;
}

fn formattingOutcome(
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
            .end = documentEndPosition(source, encoding),
        },
        .newText = result.text,
    };
    return .{ .edits = edits };
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

fn booleanMember(value: std.json.Value, name: []const u8) ?bool {
    const member = objectMember(value, name) orelse return null;
    return switch (member) {
        .bool => |result| result,
        else => null,
    };
}

fn unsignedMember(value: std.json.Value, name: []const u8) ?usize {
    const member = objectMember(value, name) orelse return null;
    if (member != .integer or member.integer < 0) return null;
    return std.math.cast(usize, member.integer);
}

fn integerMember(value: std.json.Value, name: []const u8) ?i64 {
    const member = objectMember(value, name) orelse return null;
    if (member != .integer) return null;
    return member.integer;
}

fn sourcePositionAtByteOffset(source: []const u8, file: usize, requested: usize) Source.Position {
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

fn sourceByteOffset(source: []const u8, position: Source.Position) usize {
    var offset: usize = 0;
    var line: usize = 1;
    while (line < position.line and offset < source.len) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return source.len;
        offset = newline + 1;
    }
    return @min(source.len, offset + position.column -| 1);
}

fn pathWithin(path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    return path.len > root.len and std.mem.startsWith(u8, path, root) and path[root.len] == std.fs.path.sep;
}

fn uriFromPath(allocator: Allocator, path: []const u8) ![]const u8 {
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

fn manifestDeclares(allocator: Allocator, io: Io, manifest_path: []const u8, document_path: []const u8) !bool {
    const contents = Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024)) catch return false;
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, contents, .{}) catch return false;
    const target = stringMember(parsed, "target") orelse return false;
    _ = target;
    const modules = objectMember(parsed, "modules") orelse return false;
    if (modules != .array) return false;
    const root = std.fs.path.dirname(manifest_path) orelse ".";
    for (modules.array.items) |module| {
        const sources = objectMember(module, "sources") orelse continue;
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

fn moduleAnalysisInput(path: []const u8) bool {
    if (!std.mem.endsWith(u8, std.fs.path.basename(path), ".sx")) return false;
    const directory = std.fs.path.dirname(path) orelse return false;
    return std.mem.eql(u8, std.fs.path.basename(directory), module_analysis_directory);
}

fn singleSourceRootForDocument(input_path: []const u8, document_path: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, input_path, ".sx") or moduleAnalysisInput(input_path)) return null;
    if (std.mem.eql(u8, input_path, document_path)) return null;
    const root = std.fs.path.dirname(input_path) orelse return null;
    return if (pathWithin(document_path, root)) root else null;
}

fn sourceDefinesMain(allocator: Allocator, source: []const u8) bool {
    var parser = ParserModule.Parser.init(allocator, source);
    const program = parser.parse() catch return false;
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, "main")) return true;
    }
    return false;
}

fn moduleNameFromSource(
    allocator: Allocator,
    root: []const u8,
    source_path: []const u8,
) !?[]const u8 {
    if (!std.mem.endsWith(u8, source_path, ".sx")) return null;
    const directory = std.fs.path.dirname(source_path) orelse return null;
    const parent = try moduleNameFromDirectories(allocator, root, directory) orelse return null;
    const filename = std.fs.path.basename(source_path);
    const stem = filename[0 .. filename.len - ".sx".len];
    if (!ModuleDiscovery.isModuleName(stem)) return null;
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, stem });
}

fn moduleNameFromDirectories(
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

fn validIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    var lexer = LexerModule.Lexer.init(name);
    const token = lexer.next() catch return false;
    if (token.tag != .identifier or token.start != 0 or token.end != name.len) return false;
    const end = lexer.next() catch return false;
    return end.tag == .end;
}

fn canonicalRename(kind: SymbolIndex.Kind, name: []const u8) bool {
    return switch (kind) {
        .type, .enumeration, .protocol, .type_parameter => std.ascii.isUpper(name[0]),
        .variant, .alias, .module => true,
        else => std.ascii.isLower(name[0]) or name[0] == '_',
    };
}

fn renameErrorMessage(err: anyerror) []const u8 {
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

fn snapshotFile(snapshot: *const Frontend.Snapshot, path: []const u8) ?usize {
    for (snapshot.source_paths, 0..) |candidate, index| if (std.mem.eql(u8, candidate, path)) return index;
    return null;
}

fn projectContainsPath(project: *const ProjectState, path: []const u8) bool {
    if (project.current) |snapshot| if (snapshotFile(&snapshot, path) != null) return true;
    if (project.failure) |failure| for (failure.source_paths) |candidate| {
        if (std.mem.eql(u8, candidate, path)) return true;
    };
    if (project.last_success) |snapshot| if (snapshotFile(&snapshot, path) != null) return true;
    return false;
}

fn positionAfter(left: Source.Position, right: Source.Position) bool {
    if (left.line != right.line) return left.line > right.line;
    return left.column > right.column;
}

fn completionItemForSymbol(symbol: SymbolIndex.Symbol) CompletionItem {
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

fn detailTypeName(detail: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, detail, ':') orelse return null;
    var value = std.mem.trim(u8, detail[separator + 1 ..], " @&");
    const generic = std.mem.indexOfScalar(u8, value, '<') orelse value.len;
    const collection = std.mem.indexOfScalar(u8, value, '[') orelse value.len;
    const optional = std.mem.indexOfScalar(u8, value, '?') orelse value.len;
    value = value[0..@min(generic, @min(collection, optional))];
    return if (value.len == 0) null else value;
}

fn blankLineAt(allocator: Allocator, source: []const u8, cursor: usize) ![]const u8 {
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

fn fallbackCompletionReceiver(
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    start: usize,
    end: usize,
) ?SymbolIndex.Symbol {
    const callable = callableNameAt(source, start) orelse return null;
    const receiver_name = source[start..end];
    var matched: ?SymbolIndex.Symbol = null;
    for (snapshot.index.symbols) |symbol| {
        if ((symbol.kind != .parameter and symbol.kind != .variable and symbol.kind != .binding) or
            symbol.definition.file != file or !std.mem.eql(u8, symbol.name, receiver_name))
        {
            continue;
        }
        const snapshot_source = snapshot.source_contents[file];
        const definition_offset = sourceByteOffset(snapshot_source, symbol.definition);
        const symbol_callable = callableNameAt(snapshot_source, definition_offset) orelse continue;
        if (!std.mem.eql(u8, symbol_callable, callable)) continue;
        if (matched != null) return null;
        matched = symbol;
    }
    return matched;
}

fn callableNameAt(source: []const u8, byte_offset: usize) ?[]const u8 {
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

fn signatureParameters(allocator: Allocator, label: []const u8) ![]const SignatureParameter {
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
                    try appendSignatureParameter(allocator, &result, label, start, index);
                    break;
                }
                depth -= 1;
            },
            ',' => if (depth == 0) {
                try appendSignatureParameter(allocator, &result, label, start, index);
                start = index + 1;
            },
            else => {},
        }
    }
    return result.toOwnedSlice(allocator);
}

fn appendSignatureParameter(
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

fn activeParameterAt(source: []const u8, cursor: usize) usize {
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

const RenameSpan = struct { start: usize, end: usize };

fn renamedSource(
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
        const start = sourceByteOffset(source, occurrence.position);
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

fn renameGroupHasKind(index: SymbolIndex.Index, rename_group: usize, kind: SymbolIndex.Kind) bool {
    for (index.symbols) |symbol| {
        if (symbol.rename_group == rename_group and symbol.kind == kind) return true;
    }
    return false;
}

fn syntaxDiagnostic(allocator: Allocator, source: []const u8) ?Diagnostic {
    return syntaxDiagnosticWithEncoding(allocator, source, .utf16);
}

fn syntaxDiagnosticWithEncoding(
    allocator: Allocator,
    source: []const u8,
    encoding: PositionEncoding,
) ?Diagnostic {
    var parser = ParserModule.Parser.init(allocator, source);
    _ = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return diagnosticFromSource(source, parser.diagnostic.?, encoding),
        else => return null,
    };
    return null;
}

fn diagnosticsWithEncoding(
    allocator: Allocator,
    source: []const u8,
    encoding: PositionEncoding,
) ![]const Diagnostic {
    var parser = ParserModule.Parser.init(allocator, source);
    const program = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return allocator.dupe(Diagnostic, &.{
            diagnosticFromSource(source, parser.diagnostic.?, encoding),
        }),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const lint_diagnostics = try Lint.analyze(allocator, program);
    const diagnostics = try allocator.alloc(Diagnostic, lint_diagnostics.len);
    for (lint_diagnostics, diagnostics) |lint_diagnostic, *diagnostic| {
        const byte_offset = sourceDiagnosticByteOffset(source, lint_diagnostic.position);
        const position = encodedPositionAtByteOffset(source, byte_offset, encoding) orelse Position{
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

fn diagnosticFromSource(
    source: []const u8,
    diagnostic: Source.Diagnostic,
    encoding: PositionEncoding,
) Diagnostic {
    const byte_offset = sourceDiagnosticByteOffset(source, diagnostic.position);
    const position = encodedPositionAtByteOffset(source, byte_offset, encoding) orelse Position{
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

fn sourceDiagnosticByteOffset(source: []const u8, position: Source.Position) usize {
    var offset: usize = 0;
    var line: usize = 1;
    while (line < position.line and offset < source.len) : (line += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse return source.len;
        offset = newline + 1;
    }
    return @min(source.len, offset + position.column -| 1);
}

const SignatureCallee = struct { name: []const u8, start: usize };

const NamedArgumentContext = struct {
    supplied: []const []const u8,
    current_has_colon: bool,
    current_is_value: bool,
};

fn enclosingParenthesisAt(allocator: Allocator, source: []const u8, cursor: usize) !?usize {
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

fn namedArgumentContext(
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

fn initializerTypeSymbol(
    allocator: Allocator,
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    callee: SignatureCallee,
) !?SymbolIndex.Symbol {
    const position = sourcePositionAtByteOffset(source, file, callee.start);
    if (snapshot.index.occurrenceAt(file, position.line, position.column)) |occurrence| {
        const symbol = snapshot.index.symbol(occurrence.symbol);
        if (symbol.kind == .type and std.mem.eql(u8, symbol.name, callee.name) and
            symbolVisibleFromFile(snapshot, file, symbol))
        {
            return symbol;
        }
    }

    const qualifier = calleeQualifierAt(source, callee.start);
    const module_path = if (qualifier) |value|
        try usedModulePath(allocator, source, value) orelse value
    else
        null;
    var matched: ?SymbolIndex.Symbol = null;
    for (snapshot.index.symbols) |symbol| {
        if (symbol.kind != .type or !std.mem.eql(u8, symbol.name, callee.name) or
            !symbolVisibleFromFile(snapshot, file, symbol))
        {
            continue;
        }
        if (module_path) |module| {
            if (!std.mem.eql(u8, symbol.module_name, module) and
                !principalModuleMatches(symbol.module_name, module, callee.name))
            {
                continue;
            }
        }
        if (matched != null and !std.mem.eql(u8, matched.?.key, symbol.key)) return null;
        matched = symbol;
    }
    return matched;
}

fn calleeQualifierAt(source: []const u8, callee_start: usize) ?[]const u8 {
    var end = @min(callee_start, source.len);
    while (end > 0 and std.ascii.isWhitespace(source[end - 1])) end -= 1;
    if (end == 0 or source[end - 1] != '.') return null;
    const qualifier_end = end - 1;
    var start = qualifier_end;
    while (start > 0 and (isIdentifierContinue(source[start - 1]) or source[start - 1] == '.')) start -= 1;
    return if (start == qualifier_end) null else source[start..qualifier_end];
}

fn principalModuleMatches(module_name: []const u8, qualifier: []const u8, type_name: []const u8) bool {
    return module_name.len == qualifier.len + 1 + type_name.len and
        std.mem.startsWith(u8, module_name, qualifier) and module_name[qualifier.len] == '.' and
        std.mem.eql(u8, module_name[qualifier.len + 1 ..], type_name);
}

fn containsName(names: []const []const u8, expected: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, expected)) return true;
    return false;
}

fn completionInsideOwnerCallable(
    snapshot: *const Frontend.Snapshot,
    file: usize,
    source: []const u8,
    cursor: usize,
    owner: []const u8,
) bool {
    const callable = callableNameAt(source, cursor) orelse return false;
    for (snapshot.index.symbols) |symbol| {
        if (symbol.kind == .method and symbol.definition.file == file and
            std.mem.eql(u8, symbol.owner, owner) and std.mem.eql(u8, symbol.name, callable))
        {
            return true;
        }
    }
    return false;
}

fn signatureCalleeAt(source: []const u8, cursor: usize) ?SignatureCallee {
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
    return if (index == end) null else .{ .name = source[index..end], .start = index };
}

fn symbolVisibleFromFile(snapshot: *const Frontend.Snapshot, file: usize, symbol: SymbolIndex.Symbol) bool {
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

fn qualifiedCompletionPrefix(source: []const u8, cursor: usize) ?QualifiedCompletionContext {
    var prefix_start = @min(cursor, source.len);
    while (prefix_start > 0 and isIdentifierContinue(source[prefix_start - 1])) prefix_start -= 1;
    if (prefix_start == 0 or source[prefix_start - 1] != '.') return null;
    const qualifier_end = prefix_start - 1;
    var qualifier_start = qualifier_end;
    while (qualifier_start > 0) {
        const character = source[qualifier_start - 1];
        if (!isIdentifierContinue(character) and character != '.') break;
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

fn lastPathSegment(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[separator + 1 ..];
}

fn firstPathSegment(path: []const u8) []const u8 {
    const separator = std.mem.indexOfScalar(u8, path, '.') orelse return path;
    return path[0..separator];
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
    var items: std.ArrayList(CompletionItem) = .empty;
    const module_directory = try moduleDirectoryPath(allocator, module_root, module_path);
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
                    break :block firstPathSegment(stem);
                } else continue;
                if (!std.mem.startsWith(u8, child_name, context.prefix)) continue;
                if (scope == .qualified_expression) {
                    const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_path, child_name });
                    if (!try namespaceHasPublicApiOrChildren(allocator, io, module_root, child_path)) continue;
                }
                try appendModuleExportCompletion(
                    allocator,
                    &items,
                    context.qualifier,
                    child_name,
                    9,
                    "Silex child namespace",
                );
            }
        }
        try appendCompactChildCompletions(
            allocator,
            io,
            module_root,
            module_path,
            context,
            scope,
            &items,
        );
    }

    const module_sources = try namespaceSourcePaths(allocator, io, module_root, module_path);
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
            if (std.mem.eql(u8, structure.name, lastPathSegment(module_path))) continue;
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
            if (std.mem.eql(u8, enumeration.name, lastPathSegment(module_path))) continue;
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
            if (std.mem.eql(u8, protocol.name, lastPathSegment(module_path))) continue;
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
                if (std.mem.eql(u8, function.name, lastPathSegment(module_path))) continue;
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

    if (try lspNamespaceExists(allocator, io, project_root, module_path)) return project_root;
    if (try lspNamespaceExists(allocator, io, library_root, module_path)) return library_root;
    return project_root;
}

fn completionNamespaceExists(
    allocator: Allocator,
    io: Io,
    uri: []const u8,
    module_path: []const u8,
) !bool {
    const source_path = try filePathFromUri(allocator, uri) orelse return false;
    const project_root = std.fs.path.dirname(source_path) orelse return false;
    const root = try moduleCompletionRoot(allocator, io, project_root, module_path) orelse return false;
    return lspNamespaceExists(allocator, io, root, module_path);
}

fn lspNamespaceExists(allocator: Allocator, io: Io, root: []const u8, module_path: []const u8) !bool {
    const directory = try moduleDirectoryPath(allocator, root, module_path);
    if (try lspDirectoryExists(io, directory)) return true;
    if ((try namespaceSourcePaths(allocator, io, root, module_path)).len != 0) return true;
    return lspCompactDescendantExists(allocator, io, root, module_path);
}

fn lspCompactDescendantExists(allocator: Allocator, io: Io, root: []const u8, module_path: []const u8) !bool {
    var stem_start: usize = 0;
    while (true) {
        const prefix = if (stem_start == 0) "" else module_path[0 .. stem_start - 1];
        const stem = module_path[stem_start..];
        const physical_parent = if (prefix.len == 0) root else try moduleDirectoryPath(allocator, root, prefix);
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

fn appendCompactChildCompletions(
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
        const physical_parent = if (prefix.len == 0) root else try moduleDirectoryPath(allocator, root, prefix);
        var directory = Io.Dir.cwd().openDir(io, physical_parent, .{ .iterate = true }) catch null;
        if (directory) |*opened| {
            defer opened.close(io);
            var iterator = opened.iterateAssumeFirstIteration();
            while (iterator.next(io) catch null) |entry| {
                if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
                const source_stem = entry.name[0 .. entry.name.len - ".sx".len];
                if (source_stem.len <= stem.len or !std.mem.startsWith(u8, source_stem, stem) or source_stem[stem.len] != '.') continue;
                const child_name = firstPathSegment(source_stem[stem.len + 1 ..]);
                if (!std.mem.startsWith(u8, child_name, context.prefix)) continue;
                if (scope == .qualified_expression) {
                    const child_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_path, child_name });
                    if (!try namespaceHasPublicApiOrChildren(allocator, io, root, child_path)) continue;
                }
                try appendModuleExportCompletion(
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

fn namespaceHasPublicApiOrChildren(
    allocator: Allocator,
    io: Io,
    root: []const u8,
    module_path: []const u8,
) !bool {
    const directory = try moduleDirectoryPath(allocator, root, module_path);
    if (try lspDirectoryExists(io, directory)) return true;
    if (try lspCompactDescendantExists(allocator, io, root, module_path)) return true;
    const sources = try namespaceSourcePaths(allocator, io, root, module_path);
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

fn namespaceSourcePaths(
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
            try std.fs.path.join(allocator, &.{ try moduleDirectoryPath(allocator, root, prefix), filename });
        const stat = Io.Dir.cwd().statFile(io, source_path, .{}) catch null;
        if (stat != null and stat.?.kind == .file) try sources.append(allocator, source_path);
        const separator = std.mem.indexOfScalarPos(u8, module_path, stem_start, '.') orelse break;
        stem_start = separator + 1;
    }
    return sources.toOwnedSlice(allocator);
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

fn unqualifiedModuleCompletionItems(
    allocator: Allocator,
    qualified: []const CompletionItem,
) ![]const CompletionItem {
    var items: std.ArrayList(CompletionItem) = .empty;
    for (qualified) |candidate| {
        const name = candidate.insertText orelse lastPathSegment(candidate.label);
        if (containsCompletion(items.items, name)) continue;
        var item = candidate;
        item.label = name;
        item.insertText = name;
        item.filterText = name;
        try items.append(allocator, item);
    }
    return items.toOwnedSlice(allocator);
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

    if (module_name.len > 0 and std.mem.startsWith(u8, module_name, prefix)) {
        if (!containsCompletion(items.items, module_name)) try items.append(allocator, .{
            .label = module_name,
            .kind = 9,
            .detail = detail,
        });
    }

    for (source_stems.items) |stem| {
        const source_module = if (module_name.len == 0)
            stem
        else
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, stem });
        if (std.mem.startsWith(u8, source_module, prefix) and !containsCompletion(items.items, source_module)) {
            try items.append(allocator, .{
                .label = source_module,
                .kind = 9,
                .detail = detail,
            });
        }
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

fn byteOffsetAtPosition(source: []const u8, position: Position) ?usize {
    return byteOffsetAtEncodedPosition(source, position, .utf16);
}

fn normalizePosition(
    source: []const u8,
    position: ?Position,
    encoding: PositionEncoding,
) ?Position {
    const requested = position orelse return null;
    const offset = byteOffsetAtEncodedPosition(source, requested, encoding) orelse return null;
    return encodedPositionAtByteOffset(source, offset, .utf16);
}

fn byteOffsetAtEncodedPosition(
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
        const sequence_length = utf8SequenceLength(source[offset]);
        units += switch (encoding) {
            .utf8 => sequence_length,
            .utf16 => if (sequence_length == 4) 2 else 1,
            .utf32 => 1,
        };
        offset += @min(sequence_length, source.len - offset);
    }
    return if (units == position.character) offset else null;
}

fn encodedPositionAtByteOffset(
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
        const sequence_length = utf8SequenceLength(source[offset]);
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

fn documentEndPosition(source: []const u8, encoding: PositionEncoding) Position {
    return encodedPositionAtByteOffset(source, source.len, encoding).?;
}

fn utf8SequenceLength(first_byte: u8) usize {
    if (first_byte & 0x80 == 0) return 1;
    if (first_byte & 0xe0 == 0xc0) return 2;
    if (first_byte & 0xf0 == 0xe0) return 3;
    if (first_byte & 0xf8 == 0xf0) return 4;
    return 1;
}

fn isIdentifierContinue(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

fn containsCompletion(items: []const CompletionItem, label: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.label, label)) return true;
    return false;
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

test "lint diagnostics preserve shared identity order and positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\struct bad_type {}
        \\func BadFunction() { return; print(1) }
    ;
    var parser = ParserModule.Parser.init(allocator, source);
    const program = try parser.parse();
    const shared = try Lint.analyze(allocator, program);
    const diagnostics = try diagnosticsWithEncoding(allocator, source, .utf16);
    try std.testing.expectEqual(shared.len, diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), diagnostics.len);
    for (shared, diagnostics) |lint_diagnostic, diagnostic| {
        try std.testing.expectEqualStrings(lint_diagnostic.code, diagnostic.code.?);
        try std.testing.expectEqualStrings(lint_diagnostic.message, diagnostic.message);
        try std.testing.expectEqualStrings("silex lint", diagnostic.source);
        try std.testing.expectEqual(@as(u8, 2), diagnostic.severity);
        try std.testing.expectEqual(lint_diagnostic.position.line - 1, diagnostic.range.start.line);
    }
    try std.testing.expectEqual(Position{ .line = 0, .character = 7 }, diagnostics[0].range.start);
    try std.testing.expectEqual(Position{ .line = 1, .character = 5 }, diagnostics[1].range.start);
    try std.testing.expectEqual(Position{ .line = 1, .character = 29 }, diagnostics[2].range.start);
}

test "invalid source publishes only its syntax error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const diagnostics = try diagnosticsWithEncoding(
        arena.allocator(),
        "func BadFunction() { let BadValue =\n}",
        .utf16,
    );
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqual(@as(u8, 1), diagnostics[0].severity);
    try std.testing.expectEqualStrings("silex", diagnostics[0].source);
    try std.testing.expect(diagnostics[0].code == null);
}

test "lint positions use the negotiated Unicode encoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source = "func good() { print(\"😀\"); let BadValue = 1 }";
    const utf8 = try diagnosticsWithEncoding(arena.allocator(), source, .utf8);
    const utf16 = try diagnosticsWithEncoding(arena.allocator(), source, .utf16);
    try std.testing.expectEqual(@as(usize, 1), utf8.len);
    try std.testing.expectEqual(@as(usize, 1), utf16.len);
    try std.testing.expectEqual(utf16[0].range.start.character + 2, utf8[0].range.start.character);
}

test "position encoding negotiation defaults to UTF-16 and accepts client encodings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(PositionEncoding.utf16, negotiatedPositionEncoding(null));
    const parsed = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        "{\"capabilities\":{\"general\":{\"positionEncodings\":[\"unknown\",\"utf-8\",\"utf-16\"]}}}",
        .{},
    );
    try std.testing.expectEqual(PositionEncoding.utf8, negotiatedPositionEncoding(parsed));
}

test "formatting returns one full document edit identical to the shared formatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "func main(){print(1)}";
    const shared = try Formatter.formatSource(allocator, source);
    const outcome = try formattingOutcome(allocator, source, .utf16);
    switch (outcome) {
        .diagnostic => return error.TestUnexpectedResult,
        .edits => |edits| {
            try std.testing.expectEqual(@as(usize, 1), edits.len);
            try std.testing.expectEqualStrings(shared.text, edits[0].newText);
            try std.testing.expectEqual(Position{ .line = 0, .character = 0 }, edits[0].range.start);
            try std.testing.expectEqual(Position{ .line = 0, .character = source.len }, edits[0].range.end);
        },
    }
}

test "formatting returns no edit for a canonical document" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try formattingOutcome(arena.allocator(), "func main() {}\n", .utf16);
    switch (outcome) {
        .diagnostic => return error.TestUnexpectedResult,
        .edits => |edits| try std.testing.expectEqual(@as(usize, 0), edits.len),
    }
}

test "formatting uses the open document text without mutating its saved counterpart" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    const uri = "file:///tmp/FormattingMemory.sx";
    const saved_text = "func main() {}\n";
    const open_text = "func main(){print(1)}";
    try server.setDocument(uri, open_text, 1);

    const outcome = try formattingOutcome(allocator, server.documentText(uri).?, .utf16);
    try std.testing.expectEqualStrings(saved_text, "func main() {}\n");
    try std.testing.expectEqualStrings(open_text, server.documentText(uri).?);
    switch (outcome) {
        .diagnostic => return error.TestUnexpectedResult,
        .edits => |edits| try std.testing.expectEqualStrings("func main() {\n    print(1)\n}\n", edits[0].newText),
    }
}

test "formatting covers CRLF documents without a final newline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try formattingOutcome(arena.allocator(), "func main() {\r\n}", .utf16);
    switch (outcome) {
        .diagnostic => return error.TestUnexpectedResult,
        .edits => |edits| {
            try std.testing.expectEqual(@as(usize, 1), edits.len);
            try std.testing.expectEqual(Position{ .line = 1, .character = 1 }, edits[0].range.end);
            try std.testing.expectEqualStrings("func main() {}\n", edits[0].newText);
        },
    }
}

test "formatting rejects invalid source without edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try formattingOutcome(arena.allocator(), "func main( {", .utf16);
    switch (outcome) {
        .edits => return error.TestUnexpectedResult,
        .diagnostic => |diagnostic| {
            try std.testing.expect(diagnostic.message.len != 0);
            try std.testing.expect(diagnostic.position.line >= 1);
            try std.testing.expect(diagnostic.position.column >= 1);
        },
    }
}

test "LSP positions follow the negotiated UTF encoding" {
    const source = "// 😀";
    try std.testing.expectEqual(Position{ .line = 0, .character = 7 }, documentEndPosition(source, .utf8));
    try std.testing.expectEqual(Position{ .line = 0, .character = 5 }, documentEndPosition(source, .utf16));
    try std.testing.expectEqual(Position{ .line = 0, .character = 4 }, documentEndPosition(source, .utf32));
    try std.testing.expectEqual(
        Position{ .line = 0, .character = 5 },
        normalizePosition(source, .{ .line = 0, .character = 7 }, .utf8).?,
    );
}

test "project snapshot keeps overload definitions and calls as distinct semantic identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    const outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        "Tests/Modules/Overloads/project.json",
        .editor,
        &.{},
    );
    const snapshot = switch (outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };

    var overloads: [2]usize = undefined;
    var overload_count: usize = 0;
    for (snapshot.index.symbols) |symbol| {
        if (symbol.kind == .function and std.mem.eql(u8, symbol.name, "measure")) {
            try std.testing.expect(overload_count < overloads.len);
            overloads[overload_count] = symbol.id;
            overload_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), overload_count);
    for (overloads) |symbol_id| {
        var definitions: usize = 0;
        var calls: usize = 0;
        for (snapshot.index.occurrences) |occurrence| {
            if (occurrence.symbol != symbol_id) continue;
            if (occurrence.definition) definitions += 1 else calls += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), definitions);
        try std.testing.expectEqual(@as(usize, 1), calls);
    }
}

test "semantic project requests share the selected overload identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);

    const project_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Modules/Overloads/project.json");
    const main_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Modules/Overloads/Main.sx");
    const library_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Modules/Overloads/Library.sx");
    const workspace_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Modules/Overloads");
    const main_uri = try uriFromPath(allocator, main_path);
    const library_uri = try uriFromPath(allocator, library_path);
    const main_source = try Io.Dir.cwd().readFileAlloc(std.testing.io, main_path, allocator, .limited(1024 * 1024));
    try server.workspace_roots.append(allocator, workspace_path);
    try server.setDocument(main_uri, main_source, 4);

    const outcome = try Frontend.analyze(allocator, std.testing.io, &environ_map, project_path, .editor, &.{});
    const snapshot = switch (outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try server.projects.append(allocator, .{
        .input_path = project_path,
        .current = snapshot,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = main_path, .version = 4 }}),
    });

    const call_offset = std.mem.indexOf(u8, main_source, "measure(2)") orelse return error.TestUnexpectedResult;
    const call_position = encodedPositionAtByteOffset(main_source, call_offset, .utf16).?;
    const request = try testRequestParams(allocator, main_uri, call_position, "");

    const definition_location = (try server.definition(request)).?;
    try std.testing.expectEqualStrings(library_uri, definition_location.uri);
    try std.testing.expectEqual(@as(usize, 8), definition_location.range.start.line);

    const reference_request = try testRequestParams(allocator, main_uri, call_position, ",\"context\":{\"includeDeclaration\":false}");
    const locations = try server.references(reference_request);
    try std.testing.expectEqual(@as(usize, 1), locations.len);
    try std.testing.expectEqualStrings(main_uri, locations[0].uri);

    const hover_value = (try server.hover(request)).?;
    try std.testing.expect(std.mem.indexOf(u8, hover_value.contents.value, "func measure(value:int):int") != null);
    try std.testing.expect(std.mem.indexOf(u8, hover_value.contents.value, library_path) != null);

    const member_offset = (std.mem.indexOf(u8, main_source, "holder.value.count") orelse return error.TestUnexpectedResult) + "holder.value.".len;
    const member_position = encodedPositionAtByteOffset(main_source, member_offset, .utf16).?;
    const completion_request = try testRequestParams(allocator, main_uri, member_position, "");
    const completions = try server.completion(completion_request);
    try std.testing.expect(containsCompletion(completions, "count"));

    const argument_offset = call_offset + "measure(2".len;
    const argument_position = encodedPositionAtByteOffset(main_source, argument_offset, .utf16).?;
    const signature_request = try testRequestParams(allocator, main_uri, argument_position, "");
    const signatures = try server.signatureHelp(signature_request);
    try std.testing.expectEqual(@as(usize, 2), signatures.signatures.len);
    try std.testing.expectEqual(@as(usize, 0), signatures.activeParameter);

    const rename_request = try testRequestParams(allocator, main_uri, call_position, ",\"newName\":\"weigh\"");
    const edit = try server.rename(rename_request);
    try std.testing.expectEqual(@as(usize, 2), edit.documentChanges.len);
    var saw_open = false;
    var saw_closed = false;
    for (edit.documentChanges) |change| {
        try std.testing.expectEqual(@as(usize, 1), change.edits.len);
        if (std.mem.eql(u8, change.textDocument.uri, main_uri)) {
            try std.testing.expectEqual(@as(?i64, 4), change.textDocument.version);
            saw_open = true;
        }
        if (std.mem.eql(u8, change.textDocument.uri, library_uri)) {
            try std.testing.expect(change.textDocument.version == null);
            saw_closed = true;
        }
    }
    try std.testing.expect(saw_open and saw_closed);
}

test "editor overlays change project diagnostics without changing disk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    const main_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Modules/Overloads/Main.sx");
    const disk_source = try Io.Dir.cwd().readFileAlloc(std.testing.io, main_path, allocator, .limited(1024 * 1024));
    const overlay_source =
        \\use Library
        \\use Library.measure
        \\
        \\struct Holder {
        \\    var value:Library.Value
        \\}
        \\
        \\func main() {
        \\    let holder = Holder(value:Library.Value(count:3))
        \\    print(measure())
        \\    print(Library.measure("bad"))
        \\    print(holder.value.count)
        \\}
    ;
    const outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        "Tests/Modules/Overloads/project.json",
        .editor,
        &.{.{ .path = main_path, .text = overlay_source }},
    );
    const failure = switch (outcome) {
        .success => return error.TestUnexpectedResult,
        .failure => |value| value,
    };
    try std.testing.expectEqualStrings(main_path, failure.source_paths[failure.diagnostic.position.file]);
    try std.testing.expect(std.mem.indexOf(u8, failure.diagnostic.message, "compatible") != null);
    const disk_after = try Io.Dir.cwd().readFileAlloc(std.testing.io, main_path, allocator, .limited(1024 * 1024));
    try std.testing.expectEqualStrings(disk_source, disk_after);
}

test "rename groups close overrides and protocol conformances without merging homonyms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);

    const inheritance_outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        "Smokes/Inheritance.sx",
        .editor,
        &.{},
    );
    const inheritance = switch (inheritance_outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    var override_group: ?usize = null;
    var override_count: usize = 0;
    var homonym_count: usize = 0;
    for (inheritance.index.symbols) |symbol| {
        if (symbol.kind != .method or !std.mem.eql(u8, symbol.name, "describe")) continue;
        if (override_group == null) override_group = symbol.rename_group;
        if (symbol.rename_group == override_group.?) override_count += 1 else homonym_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), override_count);
    try std.testing.expectEqual(@as(usize, 1), homonym_count);

    const protocol_outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        "Smokes/Protocols.sx",
        .editor,
        &.{},
    );
    const protocols = switch (protocol_outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    var contract_group: ?usize = null;
    var contract_count: usize = 0;
    for (protocols.index.symbols) |symbol| {
        if ((symbol.kind != .method and symbol.kind != .requirement) or
            !std.mem.eql(u8, symbol.name, "describe"))
        {
            continue;
        }
        if (contract_group == null) contract_group = symbol.rename_group;
        try std.testing.expectEqual(contract_group.?, symbol.rename_group);
        contract_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), contract_count);
}

test "fresh LSP restart analyzes named module sources without requiring main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);

    const cases = [_][]const u8{
        "../Library/STD/IO.sx",
        "../Library/STD/Console/Session.sx",
        "../Library/STD/Time/Clock.sx",
    };
    for (cases) |relative_path| {
        const source_path = try SourceGraph.canonicalPath(allocator, std.testing.io, relative_path);
        const source = try Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, allocator, .limited(1024 * 1024));
        const input_path = (try server.inputForDocument(source_path)).?;
        try std.testing.expect(moduleAnalysisInput(input_path));
        const outcome = try server.analyzeInput(input_path, &.{.{ .path = source_path, .text = source }});
        const snapshot = switch (outcome) {
            .success => |value| value,
            .failure => return error.TestUnexpectedResult,
        };
        try std.testing.expect(snapshotFile(&snapshot, source_path) != null);
    }

    const loose_path = try SourceGraph.canonicalPath(allocator, std.testing.io, "Tests/Lint/Clean.sx");
    try std.testing.expectEqualStrings(loose_path, (try server.inputForDocument(loose_path)).?);
    const loose_outcome = try server.analyzeInput(loose_path, &.{});
    switch (loose_outcome) {
        .success => return error.TestUnexpectedResult,
        .failure => |failure| try std.testing.expectEqualStrings("missing 'main' function", failure.diagnostic.message),
    }
}

test "fresh LSP restart analyzes local module sources from the nearest single-source root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "Workspace/Sandbox/Math");
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Workspace/Sandbox/Main.sx",
        .data = "func main() {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Workspace/Sandbox/Math/Vec3.sx",
        .data = "struct Vec3 {\n    var x:float\n}\n",
    });

    const temporary_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const workspace = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ temporary_root, "Workspace" }),
    );
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ temporary_root, "Workspace/Sandbox/Main.sx" }),
    );
    const source_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ temporary_root, "Workspace/Sandbox/Math/Vec3.sx" }),
    );
    try server.workspace_roots.append(allocator, workspace);

    try std.testing.expectEqualStrings(main_path, (try server.inputForDocument(main_path)).?);
    const input_path = (try server.inputForDocument(source_path)).?;
    try std.testing.expect(moduleAnalysisInput(input_path));
    const outcome = try server.analyzeInput(input_path, &.{});
    const snapshot = switch (outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try std.testing.expect(snapshotFile(&snapshot, source_path) != null);
    try std.testing.expectEqualStrings("Math.Vec3", snapshot.project.modules[snapshot.project.target_module].name);
}

test "application module manifest keeps the local module root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDirPath(std.testing.io, "Sandbox/Math");
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Sandbox/@Module.json",
        .data = "{\"dependencies\":{}}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Sandbox/Math/Vec3.sx",
        .data = "struct Vec3 {}\n",
    });

    const temporary_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const workspace = try SourceGraph.canonicalPath(allocator, std.testing.io, temporary_root);
    const source_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ temporary_root, "Sandbox/Math/Vec3.sx" }),
    );
    try server.workspace_roots.append(allocator, workspace);

    const input_path = (try server.inputForDocument(source_path)).?;
    try std.testing.expect(moduleAnalysisInput(input_path));
    const context = (try server.moduleAnalysisProject(input_path)).?;
    try std.testing.expectEqualStrings("Math.Vec3", context.project.modules[context.project.target_module].name);
}

test "qualified completion lists local namespace children while the source is incomplete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Math", .default_dir);
    try temporary.dir.createDir(std.testing.io, "Hidden", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Math/Vec3.sx",
        .data = "public struct Vec3 {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Hidden/Secret.sx",
        .data = "struct Secret {}\n",
    });
    const source = "use Math\nuse Hidden\n\nfunc main() {\n    var v = Math.\n    var secret = Hidden.\n}\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try uriFromPath(allocator, main_path);
    try server.workspace_roots.append(allocator, try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root));
    try server.setDocument(uri, source, 1);

    const cursor = (std.mem.indexOf(u8, source, "Math.") orelse return error.TestUnexpectedResult) + "Math.".len;
    const position = encodedPositionAtByteOffset(source, cursor, .utf16).?;
    const request = try testRequestParams(allocator, uri, position, "");
    const completions = try server.completion(request);
    try std.testing.expect(containsCompletion(completions, "Vec3"));
    try std.testing.expect(!containsCompletion(completions, "Secret"));
    try std.testing.expect(!containsCompletion(completions, "func"));
    for (completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "Vec3")) continue;
        try std.testing.expectEqualStrings("Vec3", completion.insertText.?);
        try std.testing.expectEqualStrings("Vec3", completion.filterText.?);
        break;
    } else return error.TestUnexpectedResult;

    const hidden_cursor = (std.mem.indexOf(u8, source, "Hidden.") orelse return error.TestUnexpectedResult) + "Hidden.".len;
    const hidden_position = encodedPositionAtByteOffset(source, hidden_cursor, .utf16).?;
    const hidden_request = try testRequestParams(allocator, uri, hidden_position, "");
    const hidden_completions = try server.completion(hidden_request);
    try std.testing.expectEqual(@as(usize, 0), hidden_completions.len);
}

test "member completion resolves a variable on a line added after the last snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Math", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Math/Vec3.sx",
        .data = "public struct Vec3 {\n    var x:float\n    var y:float\n    var z:float\n\n    public func sum() float {\n        return self.x + self.y + self.z\n    }\n}\n",
    });
    const valid_source = "use Math\n\nfunc main() {\n    var v = Math.Vec3()\n}\n";
    const incomplete_source = "use Math\n\nfunc main() {\n    var v = Math.Vec3()\n\n    print(v.)\n}\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = valid_source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try uriFromPath(allocator, main_path);
    const snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        main_path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try server.workspace_roots.append(allocator, try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root));
    try server.setDocument(uri, incomplete_source, 2);
    try server.projects.append(allocator, .{
        .input_path = main_path,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = main_path, .version = 1 }}),
    });

    const cursor = (std.mem.indexOf(u8, incomplete_source, "v.") orelse return error.TestUnexpectedResult) + "v.".len;
    const position = encodedPositionAtByteOffset(incomplete_source, cursor, .utf16).?;
    const request = try testRequestParams(allocator, uri, position, "");
    const completions = try server.completion(request);
    try std.testing.expect(containsCompletion(completions, "x"));
    try std.testing.expect(containsCompletion(completions, "y"));
    try std.testing.expect(containsCompletion(completions, "z"));
    try std.testing.expect(containsCompletion(completions, "sum"));
    try std.testing.expect(!containsCompletion(completions, "func"));

    const failed_outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        main_path,
        .editor,
        &.{.{ .path = main_path, .text = incomplete_source }},
    );
    server.projects.items[0].last_success = null;
    server.projects.items[0].last_versions = &.{};
    server.projects.items[0].failure = switch (failed_outcome) {
        .success => return error.TestUnexpectedResult,
        .failure => |failure| failure,
    };
    const cold_completions = try server.completion(request);
    try std.testing.expect(containsCompletion(cold_completions, "x"));
    try std.testing.expect(containsCompletion(cold_completions, "y"));
    try std.testing.expect(containsCompletion(cold_completions, "z"));
    try std.testing.expect(containsCompletion(cold_completions, "sum"));
    try std.testing.expect(!containsCompletion(cold_completions, "func"));
}

test "initializer completion proposes remaining public fields from the resolved type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Math", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Math/Vec3.sx",
        .data =
        \\public struct Vec3 {
        \\    var x:float
        \\    var y:float
        \\    var z:float
        \\}
        \\public struct Test {
        \\    var foo:str
        \\}
        ,
    });
    const valid_source =
        \\use Math
        \\
        \\func main() {
        \\    var vector = Math.Vec3(x:1, y:2, z:3)
        \\    var test = Math.Vec3.Test(foo:"ok")
        \\    print(vector.x)
        \\    print(test.foo)
        \\}
    ;
    const incomplete_source =
        \\use Math
        \\
        \\func main() {
        \\    var vector = Math.Vec3(
        \\        x:1,
        \\        y
        \\    )
        \\    var test = Math.Vec3.Test(f
        \\    print(vector.x)
        \\    print(test.foo)
        \\}
    ;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = valid_source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try uriFromPath(allocator, main_path);
    const snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        main_path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try server.workspace_roots.append(allocator, try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root));
    try server.setDocument(uri, incomplete_source, 2);
    try server.projects.append(allocator, .{
        .input_path = main_path,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = main_path, .version = 1 }}),
    });

    const vector_marker = "        y\n    )";
    const vector_cursor = (std.mem.indexOf(u8, incomplete_source, vector_marker) orelse return error.TestUnexpectedResult) + "        y".len;
    const vector_position = encodedPositionAtByteOffset(incomplete_source, vector_cursor, .utf16).?;
    const vector_request = try testRequestParams(allocator, uri, vector_position, "");
    const vector_completions = try server.completion(vector_request);
    try std.testing.expect(!containsCompletion(vector_completions, "x"));
    try std.testing.expect(containsCompletion(vector_completions, "y"));
    try std.testing.expect(containsCompletion(vector_completions, "z"));
    try std.testing.expect(!containsCompletion(vector_completions, "func"));
    for (vector_completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "y")) continue;
        try std.testing.expectEqualStrings("y:", completion.insertText.?);
        try std.testing.expectEqualStrings("y", completion.filterText.?);
        break;
    } else return error.TestUnexpectedResult;

    const test_cursor = (std.mem.indexOf(u8, incomplete_source, "Test(f") orelse return error.TestUnexpectedResult) + "Test(f".len;
    const test_position = encodedPositionAtByteOffset(incomplete_source, test_cursor, .utf16).?;
    const test_request = try testRequestParams(allocator, uri, test_position, "");
    const test_completions = try server.completion(test_request);
    try std.testing.expectEqual(@as(usize, 1), test_completions.len);
    try std.testing.expectEqualStrings("foo", test_completions[0].label);
    try std.testing.expectEqualStrings("foo:", test_completions[0].insertText.?);
}

test "struct constructor completion closes fields and exposes overload signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    const source =
        \\public struct Point {
        \\    private let x:int
        \\    private let y:int
        \\    init(value:int) { self.x = value; self.y = value }
        \\    public init(x:int, y:int) { self.x = x; self.y = y }
        \\}
        \\func main() { let point = Point(1, 2); assert(point == point, "point") }
    ;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try uriFromPath(allocator, main_path);
    const snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        main_path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try server.workspace_roots.append(allocator, try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root));
    try server.setDocument(uri, source, 1);
    try server.projects.append(allocator, .{
        .input_path = main_path,
        .current = snapshot,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = main_path, .version = 1 }}),
    });

    const completion_cursor = (std.mem.indexOf(u8, source, "Point(1") orelse return error.TestUnexpectedResult) + "Point(".len;
    const completion_position = encodedPositionAtByteOffset(source, completion_cursor, .utf16).?;
    const completion_request = try testRequestParams(allocator, uri, completion_position, "");
    const completions = try server.completion(completion_request);
    for (completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "x") and !std.mem.eql(u8, completion.label, "y")) continue;
        try std.testing.expect(completion.insertText == null or !std.mem.endsWith(u8, completion.insertText.?, ":"));
    }

    const signature_cursor = completion_cursor + 1;
    const signature_position = encodedPositionAtByteOffset(source, signature_cursor, .utf16).?;
    const signature_request = try testRequestParams(allocator, uri, signature_position, "");
    const signatures = try server.signatureHelp(signature_request);
    try std.testing.expectEqual(@as(usize, 2), signatures.signatures.len);
    try std.testing.expectEqualStrings("init Point(value:int)", signatures.signatures[0].label);
    try std.testing.expectEqualStrings("init Point(x:int, y:int)", signatures.signatures[1].label);
}

test "module completion separates file declarations from child namespaces and expands dotted stems" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Library", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = "func main() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library.sx",
        .data = "public struct Extra {}\npublic func root_value() int { return 1 }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Child.sx",
        .data = "public func child_value() int { return 2 }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Compact.Session.sx",
        .data = "public func compact_value() int { return 3 }\n",
    });

    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try uriFromPath(allocator, main_path);
    const root_items = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library",
        .{ .qualifier = "Library", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(root_items, "Library.Child"));
    try std.testing.expect(containsCompletion(root_items, "Library.Compact"));
    try std.testing.expect(containsCompletion(root_items, "Library.Extra"));
    try std.testing.expect(containsCompletion(root_items, "Library.root_value"));
    try std.testing.expect(!containsCompletion(root_items, "Library.child_value"));

    const compact_items = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library.Compact",
        .{ .qualifier = "Library.Compact", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(compact_items, "Library.Compact.Session"));

    const session_items = try moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library.Compact.Session",
        .{ .qualifier = "Library.Compact.Session", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(containsCompletion(session_items, "Library.Compact.Session.compact_value"));
}

test "opening a loaded distributed source keeps its application project input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);
    var server = Server.init(allocator, std.testing.io, &environ_map);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    const main_source = "use STD.Console\n\nfunc main() {}\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = main_source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const workspace_path = try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root);
    const input_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const main_uri = try uriFromPath(allocator, input_path);
    try server.workspace_roots.append(allocator, workspace_path);
    try server.setDocument(main_uri, main_source, 1);

    const initial_outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        input_path,
        .editor,
        &.{.{ .path = input_path, .text = main_source }},
    );
    const snapshot = switch (initial_outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try server.projects.append(allocator, .{
        .input_path = input_path,
        .current = snapshot,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = input_path, .version = 1 }}),
    });

    var console_file: ?usize = null;
    for (snapshot.source_paths, 0..) |path, file| {
        if (std.mem.endsWith(u8, path, "/STD/Console.sx")) {
            console_file = file;
            break;
        }
    }
    const file = console_file orelse return error.TestUnexpectedResult;
    const console_path = snapshot.source_paths[file];
    const console_source = snapshot.source_contents[file];
    try std.testing.expect(std.mem.indexOf(u8, console_source, "native func native_move_cursor") != null);
    try std.testing.expectEqualStrings(input_path, (try server.inputForDocument(console_path)).?);

    const reopened_outcome = try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        (try server.inputForDocument(console_path)).?,
        .editor,
        &.{.{ .path = console_path, .text = console_source }},
    );
    switch (reopened_outcome) {
        .success => {},
        .failure => return error.TestUnexpectedResult,
    }
}

fn testRequestParams(
    allocator: Allocator,
    uri: []const u8,
    position: Position,
    suffix: []const u8,
) !std.json.Value {
    const source = try std.fmt.allocPrint(
        allocator,
        "{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}}{s}}}",
        .{ uri, position.line, position.character, suffix },
    );
    return std.json.parseFromSliceLeaky(std.json.Value, allocator, source, .{});
}
