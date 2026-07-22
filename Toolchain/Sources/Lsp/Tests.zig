const Types = @import("Types.zig");
const ServerModule = @import("Server.zig");
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
const Server = ServerModule.Server;
const helpers = ServerModule.Helpers{};
const RenameSpan = @import("Features.zig").RenameSpan;
const SignatureCallee = @import("Features.zig").SignatureCallee;
const NamedArgumentContext = @import("Features.zig").NamedArgumentContext;
const VisibleModule = @import("Features.zig").VisibleModule;
const language_completions = @import("Completion.zig").language_completions;
test "syntax diagnostics use zero-based LSP positions" {
    const diagnostic = helpers.syntaxDiagnostic(std.testing.allocator, "func main() void {\n    let value =\n}").?;
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
    try std.testing.expect(helpers.syntaxDiagnostic(arena.allocator(), source) == null);
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
    const diagnostics = try helpers.diagnosticsWithEncoding(allocator, source, .utf16);
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
    const diagnostics = try helpers.diagnosticsWithEncoding(
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
    const utf8 = try helpers.diagnosticsWithEncoding(arena.allocator(), source, .utf8);
    const utf16 = try helpers.diagnosticsWithEncoding(arena.allocator(), source, .utf16);
    try std.testing.expectEqual(@as(usize, 1), utf8.len);
    try std.testing.expectEqual(@as(usize, 1), utf16.len);
    try std.testing.expectEqual(utf16[0].range.start.character + 2, utf8[0].range.start.character);
}

test "position encoding negotiation defaults to UTF-16 and accepts client encodings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(PositionEncoding.utf16, helpers.negotiatedPositionEncoding(null));
    const parsed = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        "{\"capabilities\":{\"general\":{\"positionEncodings\":[\"unknown\",\"utf-8\",\"utf-16\"]}}}",
        .{},
    );
    try std.testing.expectEqual(PositionEncoding.utf8, helpers.negotiatedPositionEncoding(parsed));
}

test "semantic tokens distinguish namespaces types calls methods and properties" {
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
        \\    public var x:int
        \\    public var y:int
        \\    public var z:int
        \\    public init(x:int, y:int, z:int) {
        \\        self.x = x
        \\        self.y = y
        \\        self.z = z
        \\    }
        \\    public static func pow(value:Vec3) Vec3 { return value }
        \\    public func magnitude() int { return self.x }
        \\}
        ,
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Text.sx",
        .data =
        \\public enum Normalization { nfc }
        \\public func normalize(text:str, form:Normalization) str { return text }
        ,
    });
    const source =
        \\use Math
        \\use Math.Vec3 as Vec3
        \\use Text
        \\use Text as Words
        \\struct Configuration { var strict:bool }
        \\func accepts(configuration:Configuration) bool { return configuration.strict }
        \\func main() {
        \\    let expected = Configuration(strict:true)
        \\    let vector = Math.Vec3(1, 2, 3)
        \\    let powered = Math.Vec3.pow(vector)
        \\    let aliased_powered = Vec3.pow(vector)
        \\    let magnitude = vector.magnitude()
        \\    let normalized = Text.normalize("é", Text.Normalization.nfc())
        \\    let aliased_normalized = Words.normalize("é", Text.Normalization.nfc())
        \\    print(powered.x)
        \\}
    ;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = source });
    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try helpers.uriFromPath(allocator, main_path);
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
    try server.workspace_roots.append(
        allocator,
        try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root),
    );
    try server.setDocument(uri, source, 1);
    try server.projects.append(allocator, .{
        .input_path = main_path,
        .current = snapshot,
        .last_success = snapshot,
        .last_versions = try allocator.dupe(VersionStamp, &.{.{ .path = main_path, .version = 1 }}),
    });
    const params = try testRequestParams(allocator, uri, .{ .line = 0, .character = 0 }, "");
    const tokens = try server.semanticTokens(params);

    const annotation = std.mem.indexOf(u8, source, "configuration:Configuration") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, annotation, "configuration".len, .parameter);
    try helpers.expectSemanticTokenAt(
        source,
        tokens.data,
        annotation + "configuration:".len,
        "Configuration".len,
        .type,
    );

    const constructor = std.mem.indexOf(u8, source, "Configuration(strict:true)") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, constructor, "Configuration".len, .function);

    const type_alias_definition = std.mem.indexOf(u8, source, "as Vec3") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(
        source,
        tokens.data,
        type_alias_definition + "as ".len,
        "Vec3".len,
        .type,
    );
    const namespace_alias_definition = std.mem.indexOf(u8, source, "as Words") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(
        source,
        tokens.data,
        namespace_alias_definition + "as ".len,
        "Words".len,
        .namespace,
    );

    const static_call = std.mem.indexOf(u8, source, "Math.Vec3.pow(vector)") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, static_call, "Math".len, .namespace);
    try helpers.expectSemanticTokenAt(source, tokens.data, static_call + "Math.".len, "Vec3".len, .type);
    try helpers.expectSemanticTokenAt(source, tokens.data, static_call + "Math.Vec3.".len, "pow".len, .function);
    const aliased_static_call = std.mem.indexOf(u8, source, "Vec3.pow(vector)") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, aliased_static_call, "Vec3".len, .type);
    try helpers.expectSemanticTokenAt(source, tokens.data, aliased_static_call + "Vec3.".len, "pow".len, .function);

    const method_call = std.mem.indexOf(u8, source, "vector.magnitude()") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, method_call, "vector".len, .variable);
    try helpers.expectSemanticTokenAt(source, tokens.data, method_call + "vector.".len, "magnitude".len, .method);

    const text_call = std.mem.indexOf(u8, source, "Text.normalize") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, text_call, "Text".len, .namespace);
    try helpers.expectSemanticTokenAt(source, tokens.data, text_call + "Text.".len, "normalize".len, .function);
    const aliased_text_call = std.mem.indexOf(u8, source, "Words.normalize") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, aliased_text_call, "Words".len, .namespace);
    try helpers.expectSemanticTokenAt(source, tokens.data, aliased_text_call + "Words.".len, "normalize".len, .function);

    const variant_call = std.mem.indexOf(u8, source, "Text.Normalization.nfc()") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, variant_call, "Text".len, .namespace);
    try helpers.expectSemanticTokenAt(
        source,
        tokens.data,
        variant_call + "Text.".len,
        "Normalization".len,
        .type,
    );
    try helpers.expectSemanticTokenAt(
        source,
        tokens.data,
        variant_call + "Text.Normalization.".len,
        "nfc".len,
        .function,
    );

    const field_access = std.mem.indexOf(u8, source, "powered.x") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens.data, field_access, "powered".len, .variable);
    try helpers.expectSemanticTokenAt(source, tokens.data, field_access + "powered.".len, "x".len, .property);
}

test "semantic tokens classify principal type and namespace aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);

    const path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        "Smokes/AlgorithmsChooseEmpty.sx",
    );
    const source = try Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        allocator,
        .limited(max_message_size),
    );
    const snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    const file = helpers.snapshotFile(&snapshot, path) orelse return error.TestUnexpectedResult;
    const tokens = try helpers.semanticTokenData(allocator, snapshot.index, file, source, .utf16);

    const namespace_definition = std.mem.indexOf(u8, source, "as Algorithms") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(
        source,
        tokens,
        namespace_definition + "as ".len,
        "Algorithms".len,
        .namespace,
    );
    const type_definition = std.mem.indexOf(u8, source, "as Randomizer") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(
        source,
        tokens,
        type_definition + "as ".len,
        "Randomizer".len,
        .type,
    );

    const type_reference = std.mem.indexOf(u8, source, "Randomizer.create") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens, type_reference, "Randomizer".len, .type);
    const namespace_reference = std.mem.indexOf(u8, source, "Algorithms.choose") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(source, tokens, namespace_reference, "Algorithms".len, .namespace);
}

test "semantic tokens resolve distributed namespaces and intermediate enum types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var environ_map = std.process.Environ.Map.init(allocator);

    const system_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        "Smokes/SystemErrors.sx",
    );
    const system_source = try Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        system_path,
        allocator,
        .limited(max_message_size),
    );
    const system_snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        system_path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    const system_file = helpers.snapshotFile(&system_snapshot, system_path) orelse
        return error.TestUnexpectedResult;
    const system_tokens = try helpers.semanticTokenData(
        allocator,
        system_snapshot.index,
        system_file,
        system_source,
        .utf16,
    );
    const error_kind_call = std.mem.indexOf(u8, system_source, "System.ErrorKind.not_found()") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(system_source, system_tokens, error_kind_call, "System".len, .namespace);
    try helpers.expectSemanticTokenAt(
        system_source,
        system_tokens,
        error_kind_call + "System.".len,
        "ErrorKind".len,
        .type,
    );
    try helpers.expectSemanticTokenAt(
        system_source,
        system_tokens,
        error_kind_call + "System.ErrorKind.".len,
        "not_found".len,
        .function,
    );

    const text_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        "Smokes/UnicodeText.sx",
    );
    const text_source = try Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        text_path,
        allocator,
        .limited(max_message_size),
    );
    const text_snapshot = switch (try Frontend.analyze(
        allocator,
        std.testing.io,
        &environ_map,
        text_path,
        .editor,
        &.{},
    )) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    const text_file = helpers.snapshotFile(&text_snapshot, text_path) orelse
        return error.TestUnexpectedResult;
    const text_tokens = try helpers.semanticTokenData(
        allocator,
        text_snapshot.index,
        text_file,
        text_source,
        .utf16,
    );
    const normalize_call = std.mem.indexOf(u8, text_source, "Text.normalize") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(text_source, text_tokens, normalize_call, "Text".len, .namespace);
    try helpers.expectSemanticTokenAt(
        text_source,
        text_tokens,
        normalize_call + "Text.".len,
        "normalize".len,
        .function,
    );
    const normalization_call = std.mem.indexOf(u8, text_source, "Text.Normalization.nfc()") orelse
        return error.TestUnexpectedResult;
    try helpers.expectSemanticTokenAt(text_source, text_tokens, normalization_call, "Text".len, .namespace);
    try helpers.expectSemanticTokenAt(
        text_source,
        text_tokens,
        normalization_call + "Text.".len,
        "Normalization".len,
        .type,
    );
    try helpers.expectSemanticTokenAt(
        text_source,
        text_tokens,
        normalization_call + "Text.Normalization.".len,
        "nfc".len,
        .function,
    );
}

test "formatting returns one full document edit identical to the shared formatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "func main(){print(1)}";
    const shared = try Formatter.formatSource(allocator, source);
    const outcome = try helpers.formattingOutcome(allocator, source, .utf16);
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
    const outcome = try helpers.formattingOutcome(arena.allocator(), "func main() {}\n", .utf16);
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

    const outcome = try helpers.formattingOutcome(allocator, server.documentText(uri).?, .utf16);
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
    const outcome = try helpers.formattingOutcome(arena.allocator(), "func main() {\r\n}", .utf16);
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
    const outcome = try helpers.formattingOutcome(arena.allocator(), "func main( {", .utf16);
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
    try std.testing.expectEqual(Position{ .line = 0, .character = 7 }, helpers.documentEndPosition(source, .utf8));
    try std.testing.expectEqual(Position{ .line = 0, .character = 5 }, helpers.documentEndPosition(source, .utf16));
    try std.testing.expectEqual(Position{ .line = 0, .character = 4 }, helpers.documentEndPosition(source, .utf32));
    try std.testing.expectEqual(
        Position{ .line = 0, .character = 5 },
        helpers.normalizePosition(source, .{ .line = 0, .character = 7 }, .utf8).?,
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
    const main_uri = try helpers.uriFromPath(allocator, main_path);
    const library_uri = try helpers.uriFromPath(allocator, library_path);
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
    const call_position = helpers.encodedPositionAtByteOffset(main_source, call_offset, .utf16).?;
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
    const member_position = helpers.encodedPositionAtByteOffset(main_source, member_offset, .utf16).?;
    const completion_request = try testRequestParams(allocator, main_uri, member_position, "");
    const completions = try server.completion(completion_request);
    try std.testing.expect(helpers.containsCompletion(completions, "count"));

    const argument_offset = call_offset + "measure(2".len;
    const argument_position = helpers.encodedPositionAtByteOffset(main_source, argument_offset, .utf16).?;
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
        try std.testing.expect(helpers.moduleAnalysisInput(input_path));
        const outcome = try server.analyzeInput(input_path, &.{.{ .path = source_path, .text = source }});
        const snapshot = switch (outcome) {
            .success => |value| value,
            .failure => return error.TestUnexpectedResult,
        };
        try std.testing.expect(helpers.snapshotFile(&snapshot, source_path) != null);
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
    try std.testing.expect(helpers.moduleAnalysisInput(input_path));
    const outcome = try server.analyzeInput(input_path, &.{});
    const snapshot = switch (outcome) {
        .success => |value| value,
        .failure => return error.TestUnexpectedResult,
    };
    try std.testing.expect(helpers.snapshotFile(&snapshot, source_path) != null);
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
    try std.testing.expect(helpers.moduleAnalysisInput(input_path));
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
    const uri = try helpers.uriFromPath(allocator, main_path);
    try server.workspace_roots.append(allocator, try SourceGraph.canonicalPath(allocator, std.testing.io, relative_root));
    try server.setDocument(uri, source, 1);

    const cursor = (std.mem.indexOf(u8, source, "Math.") orelse return error.TestUnexpectedResult) + "Math.".len;
    const position = helpers.encodedPositionAtByteOffset(source, cursor, .utf16).?;
    const request = try testRequestParams(allocator, uri, position, "");
    const completions = try server.completion(request);
    try std.testing.expect(helpers.containsCompletion(completions, "Vec3"));
    try std.testing.expect(!helpers.containsCompletion(completions, "Secret"));
    try std.testing.expect(!helpers.containsCompletion(completions, "func"));
    for (completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "Vec3")) continue;
        try std.testing.expectEqualStrings("Vec3", completion.insertText.?);
        try std.testing.expectEqualStrings("Vec3", completion.filterText.?);
        break;
    } else return error.TestUnexpectedResult;

    const hidden_cursor = (std.mem.indexOf(u8, source, "Hidden.") orelse return error.TestUnexpectedResult) + "Hidden.".len;
    const hidden_position = helpers.encodedPositionAtByteOffset(source, hidden_cursor, .utf16).?;
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
    const uri = try helpers.uriFromPath(allocator, main_path);
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
    const position = helpers.encodedPositionAtByteOffset(incomplete_source, cursor, .utf16).?;
    const request = try testRequestParams(allocator, uri, position, "");
    const completions = try server.completion(request);
    try std.testing.expect(helpers.containsCompletion(completions, "x"));
    try std.testing.expect(helpers.containsCompletion(completions, "y"));
    try std.testing.expect(helpers.containsCompletion(completions, "z"));
    try std.testing.expect(helpers.containsCompletion(completions, "sum"));
    try std.testing.expect(!helpers.containsCompletion(completions, "func"));

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
    try std.testing.expect(helpers.containsCompletion(cold_completions, "x"));
    try std.testing.expect(helpers.containsCompletion(cold_completions, "y"));
    try std.testing.expect(helpers.containsCompletion(cold_completions, "z"));
    try std.testing.expect(helpers.containsCompletion(cold_completions, "sum"));
    try std.testing.expect(!helpers.containsCompletion(cold_completions, "func"));
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
    const uri = try helpers.uriFromPath(allocator, main_path);
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
    const vector_position = helpers.encodedPositionAtByteOffset(incomplete_source, vector_cursor, .utf16).?;
    const vector_request = try testRequestParams(allocator, uri, vector_position, "");
    const vector_completions = try server.completion(vector_request);
    try std.testing.expect(!helpers.containsCompletion(vector_completions, "x"));
    try std.testing.expect(helpers.containsCompletion(vector_completions, "y"));
    try std.testing.expect(helpers.containsCompletion(vector_completions, "z"));
    try std.testing.expect(!helpers.containsCompletion(vector_completions, "func"));
    for (vector_completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "y")) continue;
        try std.testing.expectEqualStrings("y:", completion.insertText.?);
        try std.testing.expectEqualStrings("y", completion.filterText.?);
        break;
    } else return error.TestUnexpectedResult;

    const test_cursor = (std.mem.indexOf(u8, incomplete_source, "Test(f") orelse return error.TestUnexpectedResult) + "Test(f".len;
    const test_position = helpers.encodedPositionAtByteOffset(incomplete_source, test_cursor, .utf16).?;
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
    const uri = try helpers.uriFromPath(allocator, main_path);
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
    const completion_position = helpers.encodedPositionAtByteOffset(source, completion_cursor, .utf16).?;
    const completion_request = try testRequestParams(allocator, uri, completion_position, "");
    const completions = try server.completion(completion_request);
    for (completions) |completion| {
        if (!std.mem.eql(u8, completion.label, "x") and !std.mem.eql(u8, completion.label, "y")) continue;
        try std.testing.expect(completion.insertText == null or !std.mem.endsWith(u8, completion.insertText.?, ":"));
    }

    const signature_cursor = completion_cursor + 1;
    const signature_position = helpers.encodedPositionAtByteOffset(source, signature_cursor, .utf16).?;
    const signature_request = try testRequestParams(allocator, uri, signature_position, "");
    const signatures = try server.signatureHelp(signature_request);
    try std.testing.expectEqual(@as(usize, 2), signatures.signatures.len);
    try std.testing.expectEqualStrings("init Point(value:int)", signatures.signatures[0].label);
    try std.testing.expectEqualStrings("init Point(x:int, y:int)", signatures.signatures[1].label);
}

test "use completion proposes one module segment and inserts only that segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();

    try temporary.dir.createDir(std.testing.io, "Library", .default_dir);
    try temporary.dir.createDir(std.testing.io, "Library/Vectors", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Main.sx", .data = "func main() {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Math.sx",
        .data = "public func square(value:int) int { return value * value }\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Vectors/Vec3.sx",
        .data = "public struct Vec3 {}\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "Library/Console.Session.sx",
        .data = "public struct Session {}\n",
    });

    const relative_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const main_path = try SourceGraph.canonicalPath(
        allocator,
        std.testing.io,
        try std.fs.path.join(allocator, &.{ relative_root, "Main.sx" }),
    );
    const uri = try helpers.uriFromPath(allocator, main_path);

    const root_items = try helpers.useCompletionItems(allocator, std.testing.io, uri, "use Lib", "Lib");
    try std.testing.expect(helpers.containsCompletion(root_items, "Library"));
    try std.testing.expect(!helpers.containsCompletion(root_items, "Library.Math"));
    for (root_items) |item| {
        if (!std.mem.eql(u8, item.label, "Library")) continue;
        try std.testing.expectEqualStrings("Library", item.insertText.?);
        try std.testing.expectEqualStrings("Library", item.filterText.?);
    }

    const library_items = try helpers.useCompletionItems(allocator, std.testing.io, uri, "use Library.", "Library.");
    try std.testing.expect(helpers.containsCompletion(library_items, "Math"));
    try std.testing.expect(helpers.containsCompletion(library_items, "Vectors"));
    try std.testing.expect(helpers.containsCompletion(library_items, "Console"));
    try std.testing.expect(!helpers.containsCompletion(library_items, "Library.Math"));
    try std.testing.expect(!helpers.containsCompletion(library_items, "Console.Session"));
    for (library_items) |item| {
        if (!std.mem.eql(u8, item.label, "Math")) continue;
        try std.testing.expectEqualStrings("Math", item.insertText.?);
        try std.testing.expectEqualStrings("Math", item.filterText.?);
    }

    const filtered_items = try helpers.useCompletionItems(allocator, std.testing.io, uri, "use Library.M", "Library.M");
    try std.testing.expectEqual(@as(usize, 1), filtered_items.len);
    try std.testing.expectEqualStrings("Math", filtered_items[0].label);
    try std.testing.expectEqualStrings("Math", filtered_items[0].insertText.?);

    const compact_items = try helpers.useCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "use Library.Console.",
        "Library.Console.",
    );
    try std.testing.expect(helpers.containsCompletion(compact_items, "Session"));
    try std.testing.expect(!helpers.containsCompletion(compact_items, "Library.Console.Session"));
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
    const uri = try helpers.uriFromPath(allocator, main_path);
    const root_items = try helpers.moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library",
        .{ .qualifier = "Library", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(helpers.containsCompletion(root_items, "Library.Child"));
    try std.testing.expect(helpers.containsCompletion(root_items, "Library.Compact"));
    try std.testing.expect(helpers.containsCompletion(root_items, "Library.Extra"));
    try std.testing.expect(helpers.containsCompletion(root_items, "Library.root_value"));
    try std.testing.expect(!helpers.containsCompletion(root_items, "Library.child_value"));

    const compact_items = try helpers.moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library.Compact",
        .{ .qualifier = "Library.Compact", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(helpers.containsCompletion(compact_items, "Library.Compact.Session"));

    const session_items = try helpers.moduleExportCompletionItems(
        allocator,
        std.testing.io,
        uri,
        "Library.Compact.Session",
        .{ .qualifier = "Library.Compact.Session", .prefix = "", .type_only = false },
        .use_path,
    );
    try std.testing.expect(helpers.containsCompletion(session_items, "Library.Compact.Session.compact_value"));
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
    const main_uri = try helpers.uriFromPath(allocator, input_path);
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
