const std = @import("std");
const silex_version = "0.30.0";

pub fn build(b: *std.Build) void {
    // A Silex run can itself launch several native compiler processes. Keep the
    // outer build bounded unless the caller selected an explicit `-j` value.
    if (b.graph.max_jobs == null) b.graph.max_jobs = 4;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "silex_version", silex_version);
    build_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);
    build_options.addOption([]const u8, "developer_standard_library_root", b.getInstallPath(.prefix, "lib/silex"));
    build_options.addOption(bool, "repository_compilation_database", false);
    build_options.addOption(bool, "run_source_graph_tests", true);

    const module = b.createModule(.{
        .root_source_file = b.path("Sources/Main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addOptions("build_options", build_options);

    const executable = b.addExecutable(.{
        .name = "silex",
        .root_module = module,
    });

    const native_module_test_options = b.addOptions();
    native_module_test_options.addOption([]const u8, "silex_version", silex_version);
    native_module_test_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);
    native_module_test_options.addOption(
        []const u8,
        "developer_standard_library_root",
        b.pathFromRoot("Tests/DistributedModules/Library"),
    );
    native_module_test_options.addOption(bool, "repository_compilation_database", false);
    native_module_test_options.addOption(bool, "run_source_graph_tests", true);
    const native_module_test_module = b.createModule(.{
        .root_source_file = b.path("Sources/Main.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_module_test_module.addOptions("build_options", native_module_test_options);
    const native_module_test_executable = b.addExecutable(.{
        .name = "silex-native-module-tests",
        .root_module = native_module_test_module,
    });
    const module_init_smoke_setup = b.addExecutable(.{
        .name = "silex-module-init-smoke-setup",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tests/ModuleInitSmokeSetup.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const git_packages_integration = b.addExecutable(.{
        .name = "silex-git-packages-integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tests/GitPackagesIntegration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const native_object_cache_integration = b.addExecutable(.{
        .name = "silex-native-object-cache-integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tests/NativeObjectCacheIntegration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const lint_artifact_check = b.addExecutable(.{
        .name = "silex-lint-artifact-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tests/LintArtifactCheck.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const console_session_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    console_session_test_module.addCSourceFile(.{
        .file = b.path("Tests/ConsoleSessionIntegration.cpp"),
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DSILEX_CONSOLE_STANDALONE_TEST" },
    });
    console_session_test_module.addCSourceFiles(.{
        .files = &.{
            "../Library/STD/@Native/Console.cpp",
            "../Library/STD/@Native/Session.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DSILEX_CONSOLE_STANDALONE_TEST" },
    });
    if (target.result.os.tag == .linux) {
        console_session_test_module.linkSystemLibrary("util", .{});
    }
    const console_session_integration = b.addExecutable(.{
        .name = "silex-console-session-integration",
        .root_module = console_session_test_module,
    });
    const system_error_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    system_error_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/SystemErrorIntegration.cpp",
            "../Library/STD/@Native/System.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" },
    });
    const system_error_integration = b.addExecutable(.{
        .name = "silex-system-error-integration",
        .root_module = system_error_test_module,
    });
    const path_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    path_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/PathIntegration.cpp",
            "../Library/STD/@Native/Path.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DSILEX_PATH_CORE_ONLY" },
    });
    const path_integration = b.addExecutable(.{
        .name = "silex-path-integration",
        .root_module = path_test_module,
    });
    const unicode_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    unicode_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/UnicodeConformance.cpp",
            "../Library/STD/@Native/Text.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" },
    });
    unicode_test_module.addCSourceFile(.{
        .file = b.path("../Library/STD/@Native/Unicode/utf8proc/utf8proc.c"),
        .flags = &.{ "-Wall", "-Wextra", "-Werror" },
    });
    const unicode_conformance = b.addExecutable(.{
        .name = "silex-unicode-conformance",
        .root_module = unicode_test_module,
    });
    const file_native_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    file_native_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/FileNativeIntegration.cpp",
            "../Library/STD/@Native/System.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" },
    });
    const file_native_integration = b.addExecutable(.{
        .name = "silex-file-native-integration",
        .root_module = file_native_test_module,
    });
    const filesystem_native_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    filesystem_native_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/FileSystemNativeIntegration.cpp",
            "../Library/STD/@Native/System.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    filesystem_native_test_module.addCSourceFile(.{
        .file = b.path("../Library/STD/@Native/Unicode/utf8proc/utf8proc.c"),
        .flags = &.{ "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    const filesystem_native_integration = b.addExecutable(.{
        .name = "silex-filesystem-native-integration",
        .root_module = filesystem_native_test_module,
    });
    const environment_native_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    environment_native_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/EnvironmentNativeIntegration.cpp",
            "../Library/STD/@Native/System.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    environment_native_test_module.addCSourceFile(.{
        .file = b.path("../Library/STD/@Native/Unicode/utf8proc/utf8proc.c"),
        .flags = &.{ "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    const environment_native_integration = b.addExecutable(.{
        .name = "silex-environment-native-integration",
        .root_module = environment_native_test_module,
    });
    const process_native_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    process_native_test_module.addCSourceFiles(.{
        .files = &.{
            "Tests/ProcessNativeIntegration.cpp",
            "../Library/STD/@Native/System.cpp",
        },
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    process_native_test_module.addCSourceFile(.{
        .file = b.path("../Library/STD/@Native/Unicode/utf8proc/utf8proc.c"),
        .flags = &.{ "-Wall", "-Wextra", "-Werror", "-DUTF8PROC_STATIC=1" },
    });
    const process_native_integration = b.addExecutable(.{
        .name = "silex-process-native-integration",
        .root_module = process_native_test_module,
    });
    const subprocess_child_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    subprocess_child_module.addCSourceFile(.{
        .file = b.path("Tests/SubprocessChild.cpp"),
        .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" },
    });
    const subprocess_child = b.addExecutable(.{
        .name = "silex-subprocess-child",
        .root_module = subprocess_child_module,
    });
    const tcp_native_test_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true });
    tcp_native_test_module.addCSourceFiles(.{ .files = &.{ "Tests/TCPNativeIntegration.cpp", "../Library/STD/@Native/System.cpp" }, .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" } });
    const tcp_native_integration = b.addExecutable(.{ .name = "silex-tcp-native-integration", .root_module = tcp_native_test_module });
    const udp_native_test_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true });
    udp_native_test_module.addCSourceFiles(.{ .files = &.{ "Tests/UDPNativeIntegration.cpp", "../Library/STD/@Native/System.cpp" }, .flags = &.{ "-std=c++23", "-Wall", "-Wextra", "-Werror" } });
    const udp_native_integration = b.addExecutable(.{ .name = "silex-udp-native-integration", .root_module = udp_native_test_module });
    const clean_library_install = b.addExecutable(.{
        .name = "silex-clean-library-install",
        .root_module = b.createModule(.{
            .root_source_file = b.path("BuildSupport/CleanLibraryInstall.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    b.installArtifact(executable);

    const repository_database_options = b.addOptions();
    repository_database_options.addOption([]const u8, "silex_version", silex_version);
    repository_database_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);
    repository_database_options.addOption(
        []const u8,
        "developer_standard_library_root",
        b.pathFromRoot("../Library"),
    );
    repository_database_options.addOption(bool, "repository_compilation_database", true);
    repository_database_options.addOption(bool, "run_source_graph_tests", true);
    const repository_database_module = b.createModule(.{
        .root_source_file = b.path("Sources/Main.zig"),
        .target = target,
        .optimize = optimize,
    });
    repository_database_module.addOptions("build_options", repository_database_options);
    const repository_database_executable = b.addExecutable(.{
        .name = "silex-repository-compilation-database",
        .root_module = repository_database_module,
    });
    const generate_repository_database = b.addRunArtifact(repository_database_executable);
    generate_repository_database.has_side_effects = true;
    generate_repository_database.setCwd(b.path(".."));
    generate_repository_database.addArgs(&.{
        "compile",
        "Toolchain/Smokes/IsolatedSTD/Main.sx",
    });
    b.getInstallStep().dependOn(&generate_repository_database.step);

    const clean_installed_library = b.addRunArtifact(clean_library_install);
    clean_installed_library.addArg(b.getInstallPath(.prefix, "lib/silex"));
    const install_library = b.addInstallDirectory(.{
        .source_dir = b.path("../Library"),
        .install_dir = .prefix,
        .install_subdir = "lib/silex",
    });
    install_library.step.dependOn(&clean_installed_library.step);
    b.getInstallStep().dependOn(&install_library.step);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run the Silex toolchain");
    run_step.dependOn(&run_command.step);

    const tests = b.addTest(.{
        .root_module = module,
    });
    const test_command = b.addRunArtifact(tests);
    test_command.step.dependOn(b.getInstallStep());

    const semantic_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("Sources/Semantic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const semantic_test_command = b.addRunArtifact(semantic_tests);

    const lint_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("Sources/Lint.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const lint_test_command = b.addRunArtifact(lint_tests);

    const lsp_test_module = b.createModule(.{
        .root_source_file = b.path("Sources/Lsp.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lsp_test_options = b.addOptions();
    lsp_test_options.addOption([]const u8, "silex_version", silex_version);
    lsp_test_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);
    lsp_test_options.addOption([]const u8, "developer_standard_library_root", b.getInstallPath(.prefix, "lib/silex"));
    lsp_test_options.addOption(bool, "repository_compilation_database", false);
    lsp_test_options.addOption(bool, "run_source_graph_tests", false);
    lsp_test_module.addOptions("build_options", lsp_test_options);
    const lsp_tests = b.addTest(.{
        .root_module = lsp_test_module,
    });
    const lsp_test_command = b.addRunArtifact(lsp_tests);
    lsp_test_command.step.dependOn(b.getInstallStep());

    const check_step = b.step("check", "Run the fast internal toolchain checks");
    check_step.dependOn(b.getInstallStep());
    check_step.dependOn(&test_command.step);
    // Lsp imports the shared front-end, so its test binary also contains the
    // SourceGraph tests. Serialize both deterministic temporary namespaces.
    lsp_test_command.step.dependOn(&test_command.step);

    const lsp_protocol_command = b.addRunArtifact(executable);
    lsp_protocol_command.addArg("lsp");
    lsp_protocol_command.setStdIn(.{
        .bytes = "Content-Length: 125\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"capabilities\":{\"general\":{\"positionEncodings\":[\"utf-8\",\"utf-16\"]}}}}" ++
            "Content-Length: 181\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/FormattingMemory.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"func main(){print(1)}\"}}}" ++
            "Content-Length: 173\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/FormattingMemory.sx\"},\"options\":{\"tabSize\":99,\"insertSpaces\":false}}}",
    });
    lsp_protocol_command.expectStdOutEqual(
        "Content-Length: 574\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-8\",\"textDocumentSync\":1,\"documentFormattingProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\"]},\"signatureHelpProvider\":{\"triggerCharacters\":[\"(\",\",\"]},\"definitionProvider\":true,\"referencesProvider\":true,\"renameProvider\":{\"prepareProvider\":true},\"hoverProvider\":true,\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[\"namespace\",\"type\",\"enumMember\",\"function\",\"method\",\"property\",\"parameter\",\"variable\"],\"tokenModifiers\":[]},\"full\":true}},\"serverInfo\":{\"name\":\"Silex\",\"version\":\"0.30.0\"}}}" ++
            "Content-Length: 136\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/FormattingMemory.sx\",\"diagnostics\":[]}}" ++
            "Content-Length: 157\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":21}},\"newText\":\"func main() {\\n    print(1)\\n}\\n\"}]}",
    );

    const lsp_canonical_formatting_command = b.addRunArtifact(executable);
    lsp_canonical_formatting_command.addArg("lsp");
    lsp_canonical_formatting_command.setStdIn(.{
        .bytes = "Content-Length: 169\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/Canonical.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"func main() {}\\n\"}}}" ++
            "Content-Length: 164\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/Canonical.sx\"},\"options\":{\"tabSize\":4,\"insertSpaces\":true}}}",
    });
    lsp_canonical_formatting_command.expectStdOutEqual(
        "Content-Length: 129\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/Canonical.sx\",\"diagnostics\":[]}}" ++
            "Content-Length: 36\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[]}",
    );

    const lsp_crlf_formatting_command = b.addRunArtifact(executable);
    lsp_crlf_formatting_command.addArg("lsp");
    lsp_crlf_formatting_command.setStdIn(.{
        .bytes = "Content-Length: 166\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/CrLf.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"func main() {\\r\\n}\"}}}" ++
            "Content-Length: 159\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/CrLf.sx\"},\"options\":{\"tabSize\":4,\"insertSpaces\":true}}}",
    });
    lsp_crlf_formatting_command.expectStdOutEqual(
        "Content-Length: 124\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/CrLf.sx\",\"diagnostics\":[]}}" ++
            "Content-Length: 140\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":1}},\"newText\":\"func main() {}\\n\"}]}",
    );

    const lsp_invalid_formatting_command = b.addRunArtifact(executable);
    lsp_invalid_formatting_command.addArg("lsp");
    lsp_invalid_formatting_command.setStdIn(.{
        .bytes = "Content-Length: 163\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/Invalid.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"func main( {\"}}}" ++
            "Content-Length: 162\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/Invalid.sx\"},\"options\":{\"tabSize\":4,\"insertSpaces\":true}}}",
    });
    lsp_invalid_formatting_command.expectStdOutEqual(
        "Content-Length: 270\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/Invalid.sx\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":11},\"end\":{\"line\":0,\"character\":12}},\"severity\":1,\"source\":\"silex\",\"message\":\"expected parameter name\"}]}}" ++
            "Content-Length: 166\r\n\r\n" ++
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32803,\"message\":\"1:12: error: expected parameter name\",\"data\":{\"line\":1,\"column\":12,\"diagnostic\":\"expected parameter name\"}}}",
    );

    const lint_open_message =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/UnsavedLint.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"struct bad_type {}\\nfunc BadFunction() { return; print(1) }\\nfunc main() {}\\n\"}}}";
    const lint_change_message =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/UnsavedLint.sx\",\"version\":2},\"contentChanges\":[{\"text\":\"struct GoodType {}\\nfunc good_function() {}\\nfunc main() {}\\n\"}]}}";
    const lint_close_message =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/UnsavedLint.sx\"}}}";
    const lint_protocol_command = b.addRunArtifact(executable);
    lint_protocol_command.addArg("lsp");
    lint_protocol_command.setStdIn(.{ .bytes = b.fmt(
        "Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}",
        .{ lint_open_message.len, lint_open_message, lint_change_message.len, lint_change_message, lint_close_message.len, lint_close_message },
    ) });
    const lint_warning_notification =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/UnsavedLint.sx\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":7},\"end\":{\"line\":0,\"character\":8}},\"severity\":2,\"source\":\"silex lint\",\"code\":\"naming/type\",\"message\":\"type name 'bad_type' should use PascalCase\"},{\"range\":{\"start\":{\"line\":1,\"character\":5},\"end\":{\"line\":1,\"character\":6}},\"severity\":2,\"source\":\"silex lint\",\"code\":\"naming/value\",\"message\":\"function name 'BadFunction' should use snake_case\"},{\"range\":{\"start\":{\"line\":1,\"character\":29},\"end\":{\"line\":1,\"character\":30}},\"severity\":2,\"source\":\"silex lint\",\"code\":\"control-flow/unreachable\",\"message\":\"statement is unreachable\"}]}}";
    const lint_empty_notification =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/UnsavedLint.sx\",\"diagnostics\":[]}}";
    lint_protocol_command.expectStdOutEqual(b.fmt(
        "Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}",
        .{ lint_warning_notification.len, lint_warning_notification, lint_empty_notification.len, lint_empty_notification, lint_empty_notification.len, lint_empty_notification },
    ));

    const unicode_lint_message =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/UnicodeLint.sx\",\"languageId\":\"silex\",\"version\":1,\"text\":\"func main() { print(\\\"😀\\\"); let BadValue = 1 }\"}}}";
    const unicode_lint_protocol_command = b.addRunArtifact(executable);
    unicode_lint_protocol_command.addArg("lsp");
    unicode_lint_protocol_command.setStdIn(.{ .bytes = b.fmt(
        "Content-Length: {d}\r\n\r\n{s}",
        .{ unicode_lint_message.len, unicode_lint_message },
    ) });
    const unicode_lint_notification =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///private/tmp/UnicodeLint.sx\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":31},\"end\":{\"line\":0,\"character\":32}},\"severity\":2,\"source\":\"silex lint\",\"code\":\"naming/value\",\"message\":\"variable name 'BadValue' should use snake_case\"}]}}";
    unicode_lint_protocol_command.expectStdOutEqual(b.fmt(
        "Content-Length: {d}\r\n\r\n{s}",
        .{ unicode_lint_notification.len, unicode_lint_notification },
    ));

    const invalid_command = b.addRunArtifact(executable);
    invalid_command.addArgs(&.{ "compile", "Tests/InvalidArithmetic.sx" });
    invalid_command.expectExitCode(1);
    invalid_command.expectStdErrEqual(
        "Tests/InvalidArithmetic.sx:2:19: error: arithmetic operator requires numeric operands, found 'str' and 'int'\n",
    );

    const missing_module_subcommand_command = b.addRunArtifact(executable);
    missing_module_subcommand_command.addArg("module");
    missing_module_subcommand_command.expectExitCode(1);
    missing_module_subcommand_command.expectStdErrEqual("silex: module expects the 'init' command\n");

    const missing_module_init_path_command = b.addRunArtifact(executable);
    missing_module_init_path_command.addArgs(&.{ "module", "init" });
    missing_module_init_path_command.expectExitCode(1);
    missing_module_init_path_command.expectStdErrEqual("silex: module init expects a directory path\n");

    const invalid_module_init_option_command = b.addRunArtifact(executable);
    invalid_module_init_option_command.addArgs(&.{ "module", "init", "Core", "--force" });
    invalid_module_init_option_command.expectExitCode(1);
    invalid_module_init_option_command.expectStdErrEqual("silex: module init does not accept option '--force'\n");

    const format_check_command = b.addRunArtifact(executable);
    format_check_command.addArgs(&.{ "format", "Tests/Format/Unformatted.sx", "--check" });
    format_check_command.expectExitCode(1);
    format_check_command.expectStdOutEqual("Tests/Format/Unformatted.sx\n");

    const lint_warning_command = b.addRunArtifact(executable);
    lint_warning_command.addArgs(&.{ "lint", "Tests/Lint/Warnings.sx" });
    lint_warning_command.expectExitCode(1);
    lint_warning_command.expectStdErrEqual(
        "Tests/Lint/Warnings.sx:1:8: warning[naming/type]: type name 'bad_type' should use PascalCase\n" ++
            "Tests/Lint/Warnings.sx:2:9: warning[naming/value]: field name 'BadField' should use snake_case\n" ++
            "Tests/Lint/Warnings.sx:5:6: warning[naming/value]: function name 'BadFunction' should use snake_case\n" ++
            "Tests/Lint/Warnings.sx:5:18: warning[naming/value]: parameter name 'BadParam' should use snake_case\n" ++
            "Tests/Lint/Warnings.sx:7:5: warning[control-flow/unreachable]: statement is unreachable\n",
    );

    const lint_clean_command = b.addRunArtifact(executable);
    lint_clean_command.addArgs(&.{ "lint", "Tests/Lint/Clean.sx" });
    lint_clean_command.expectStdOutEqual("");
    lint_clean_command.expectStdErrEqual("");

    const lint_invalid_command = b.addRunArtifact(executable);
    lint_invalid_command.addArgs(&.{ "lint", "Tests/Lint/Invalid.sx" });
    lint_invalid_command.expectExitCode(1);
    lint_invalid_command.expectStdErrEqual("Tests/Lint/Invalid.sx:3:1: error: expected expression\n");

    const lint_project_command = b.addRunArtifact(executable);
    lint_project_command.addArgs(&.{ "lint", "Tests/Lint/Project/silex.json" });
    lint_project_command.expectExitCode(1);
    lint_project_command.expectStdErrEqual(
        "Tests/Lint/Project/A.sx:1:6: warning[naming/value]: function name 'BadA' should use snake_case\n" ++
            "Tests/Lint/Project/B.sx:1:8: warning[naming/type]: type name 'bad_b' should use PascalCase\n",
    );
    const lint_artifact_check_command = b.addRunArtifact(lint_artifact_check);
    lint_artifact_check_command.step.dependOn(&lint_project_command.step);
    lint_artifact_check_command.setCwd(b.path("Tests/Lint/Project"));

    const immutable_assignment_command = b.addRunArtifact(executable);
    immutable_assignment_command.addArgs(&.{ "compile", "Tests/InvalidImmutableAssignment.sx" });
    immutable_assignment_command.expectExitCode(1);
    immutable_assignment_command.expectStdErrEqual(
        "Tests/InvalidImmutableAssignment.sx:3:5: error: cannot assign to immutable variable 'count'\n",
    );

    const invalid_mutable_reference_argument_command = b.addRunArtifact(executable);
    invalid_mutable_reference_argument_command.addArgs(&.{ "compile", "Tests/InvalidMutableReferenceArgument.sx" });
    invalid_mutable_reference_argument_command.expectExitCode(1);
    invalid_mutable_reference_argument_command.expectStdErrEqual(
        "Tests/InvalidMutableReferenceArgument.sx:7:13: error: cannot pass immutable variable 'count' to a mutable reference parameter\n",
    );

    const missing_mutable_reference_argument_command = b.addRunArtifact(executable);
    missing_mutable_reference_argument_command.addArgs(&.{ "compile", "Tests/MissingMutableReferenceArgument.sx" });
    missing_mutable_reference_argument_command.expectExitCode(1);
    missing_mutable_reference_argument_command.expectStdErrEqual(
        "Tests/MissingMutableReferenceArgument.sx:6:13: error: a mutable reference parameter requires a variable, field, or collection element\n",
    );

    const invalid_local_reference_command = b.addRunArtifact(executable);
    invalid_local_reference_command.addArgs(&.{ "compile", "Tests/InvalidLocalReference.sx" });
    invalid_local_reference_command.expectExitCode(1);
    invalid_local_reference_command.expectStdErrEqual(
        "Tests/InvalidLocalReference.sx:3:21: error: '&' is only valid in parameter declarations; calls use plain arguments\n",
    );

    const invalid_native_function_command = b.addRunArtifact(executable);
    invalid_native_function_command.addArgs(&.{ "compile", "Tests/InvalidNativeFunction.sx" });
    invalid_native_function_command.expectExitCode(1);
    invalid_native_function_command.expectStdErrEqual(
        "Tests/InvalidNativeFunction.sx:1:1: error: native functions require module 'InvalidNativeFunction' or one of its parents to declare @Module.json native configuration\n",
    );

    const legacy_module_manifest_command = b.addRunArtifact(executable);
    legacy_module_manifest_command.addArgs(&.{ "compile", "Tests/LegacyManifest/Main.sx" });
    legacy_module_manifest_command.expectExitCode(1);
    legacy_module_manifest_command.expectStdErrMatch("'; rename it to '@Module.json'\n");

    const invalid_native_type_command = b.addRunArtifact(native_module_test_executable);
    invalid_native_type_command.addArgs(&.{ "compile", "Tests/DistributedModules/NativeInvalidType/Main.sx" });
    invalid_native_type_command.expectExitCode(1);
    invalid_native_type_command.expectStdErrMatch("native parameter 'values' cannot use 'int[]'\n");

    const missing_native_symbol_command = b.addRunArtifact(native_module_test_executable);
    missing_native_symbol_command.step.dependOn(&invalid_native_type_command.step);
    missing_native_symbol_command.addArgs(&.{ "compile", "Tests/DistributedModules/NativeMissingSymbol/Main.sx" });
    missing_native_symbol_command.expectExitCode(1);
    missing_native_symbol_command.expectStdErrMatch(
        "silex: native function 'NativeChecks.MissingSymbol.native_missing' requires C symbol 'silexNative_NativeChecks_MissingSymbol_native_missing'\n",
    );

    const native_exception_command = b.addRunArtifact(native_module_test_executable);
    native_exception_command.step.dependOn(&missing_native_symbol_command.step);
    native_exception_command.addArgs(&.{ "run", "Tests/DistributedModules/NativeThrow/Main.sx" });
    native_exception_command.expectExitCode(1);
    native_exception_command.expectStdErrEqual(
        "runtime error: native function 'NativeChecks.Throw.native_fail' failed: planned native failure\n",
    );

    const duplicate_native_source_command = b.addRunArtifact(native_module_test_executable);
    duplicate_native_source_command.step.dependOn(&native_exception_command.step);
    duplicate_native_source_command.addArgs(&.{ "compile", "Tests/DistributedModules/NativeDuplicateSource/Main.sx" });
    duplicate_native_source_command.expectExitCode(1);
    duplicate_native_source_command.expectStdErrEqual(b.fmt(
        "silex: native module 'NativeChecks.Duplicate' repeats source '{s}' in 'native' and 'native'\n",
        .{b.pathFromRoot("Tests/DistributedModules/Library/NativeChecks/Duplicate/Runtime.c")},
    ));

    const inherited_native_runtime_command = b.addRunArtifact(native_module_test_executable);
    inherited_native_runtime_command.step.dependOn(&duplicate_native_source_command.step);
    inherited_native_runtime_command.addArgs(&.{ "run", "Tests/DistributedModules/NativeInherited/Main.sx" });
    inherited_native_runtime_command.expectStdOutEqual(hostText(b, "42\n"));

    const premature_native_resource_root_command = b.addRunArtifact(native_module_test_executable);
    premature_native_resource_root_command.addArgs(&.{ "compile", "Smokes/NativeOpaqueResources/InvalidPrematureRoot.sx" });
    premature_native_resource_root_command.expectExitCode(1);
    premature_native_resource_root_command.expectStdErrMatch(
        "cannot destroy a native resource while acquired resources still depend on it\n",
    );

    const wrapped_premature_native_resource_root_command = b.addRunArtifact(native_module_test_executable);
    wrapped_premature_native_resource_root_command.addArgs(&.{ "compile", "Smokes/NativeOpaqueResources/InvalidWrappedPrematureRoot.sx" });
    wrapped_premature_native_resource_root_command.expectExitCode(1);
    wrapped_premature_native_resource_root_command.expectStdErrMatch(
        "cannot destroy a native resource while acquired resources still depend on it\n",
    );

    const escaping_native_resource_dependency_command = b.addRunArtifact(native_module_test_executable);
    escaping_native_resource_dependency_command.addArgs(&.{ "compile", "Smokes/NativeOpaqueResources/InvalidEscapingDependent.sx" });
    escaping_native_resource_dependency_command.expectExitCode(1);
    escaping_native_resource_dependency_command.expectStdErrMatch(
        "cannot return a native resource that depends on a local resource\n",
    );

    const replaced_native_resource_root_command = b.addRunArtifact(native_module_test_executable);
    replaced_native_resource_root_command.addArgs(&.{ "compile", "Smokes/NativeOpaqueResources/InvalidReplaceRoot.sx" });
    replaced_native_resource_root_command.expectExitCode(1);
    replaced_native_resource_root_command.expectStdErrMatch(
        "cannot replace a native resource while acquired resources still depend on it\n",
    );

    const negative_native_view_command = b.addRunArtifact(native_module_test_executable);
    negative_native_view_command.addArgs(&.{ "run", "Smokes/NativeOpaqueResources/InvalidNegativeView.sx" });
    negative_native_view_command.expectExitCode(1);
    negative_native_view_command.expectStdErrEqual(
        "runtime error: native function 'NativeOpaqueResources.invalid_negative_view' failed: returned a negative view count\n",
    );

    const null_native_view_command = b.addRunArtifact(native_module_test_executable);
    null_native_view_command.addArgs(&.{ "run", "Smokes/NativeOpaqueResources/InvalidNullView.sx" });
    null_native_view_command.expectExitCode(1);
    null_native_view_command.expectStdErrEqual(
        "runtime error: native function 'NativeOpaqueResources.invalid_null_view' failed: returned a null view with a positive count\n",
    );

    const invalid_reference_type_command = b.addRunArtifact(executable);
    invalid_reference_type_command.addArgs(&.{ "compile", "Tests/InvalidReferenceType.sx" });
    invalid_reference_type_command.expectExitCode(1);
    invalid_reference_type_command.expectStdErrEqual(
        "Tests/InvalidReferenceType.sx:1:20: error: expected ')'\n",
    );

    const invalid_unborrowed_view_command = b.addRunArtifact(executable);
    invalid_unborrowed_view_command.addArgs(&.{ "compile", "Tests/InvalidUnborrowedView.sx" });
    invalid_unborrowed_view_command.expectExitCode(1);
    invalid_unborrowed_view_command.expectStdErrEqual(
        "Tests/InvalidUnborrowedView.sx:1:14: error: a view type must be borrowed as '@T[..]' or '&T[..]'\n",
    );

    const invalid_condition_command = b.addRunArtifact(executable);
    invalid_condition_command.addArgs(&.{ "compile", "Tests/InvalidCondition.sx" });
    invalid_condition_command.expectExitCode(1);
    invalid_condition_command.expectStdErrEqual(
        "Tests/InvalidCondition.sx:2:9: error: expected 'bool', found 'int'\n",
    );

    const isolated_elif_command = b.addRunArtifact(executable);
    isolated_elif_command.addArgs(&.{ "compile", "Tests/IsolatedElif.sx" });
    isolated_elif_command.expectExitCode(1);
    isolated_elif_command.expectStdErrEqual(
        "Tests/IsolatedElif.sx:2:5: error: 'elif' must directly continue an if chain\n",
    );

    const invalid_alternative_condition_command = b.addRunArtifact(executable);
    invalid_alternative_condition_command.addArgs(&.{ "compile", "Tests/InvalidAlternativeCondition.sx" });
    invalid_alternative_condition_command.expectExitCode(1);
    invalid_alternative_condition_command.expectStdErrEqual(
        "Tests/InvalidAlternativeCondition.sx:2:22: error: expected 'bool', found 'int'\n",
    );

    const invalid_else_continuation_command = b.addRunArtifact(executable);
    invalid_else_continuation_command.addArgs(&.{ "compile", "Tests/InvalidElseContinuation.sx" });
    invalid_else_continuation_command.expectExitCode(1);
    invalid_else_continuation_command.expectStdErrEqual(
        "Tests/InvalidElseContinuation.sx:2:22: error: expected '{' or 'if' after 'else'\n",
    );

    const reserved_elif_identifier_command = b.addRunArtifact(executable);
    reserved_elif_identifier_command.addArgs(&.{ "compile", "Tests/ReservedElifIdentifier.sx" });
    reserved_elif_identifier_command.expectExitCode(1);
    reserved_elif_identifier_command.expectStdErrEqual(
        "Tests/ReservedElifIdentifier.sx:2:9: error: 'elif' is reserved; rename this identifier\n",
    );

    const invalid_optional_inference_command = b.addRunArtifact(executable);
    invalid_optional_inference_command.addArgs(&.{ "compile", "Tests/InvalidOptionalInference.sx" });
    invalid_optional_inference_command.expectExitCode(1);
    invalid_optional_inference_command.expectStdErrEqual("Tests/InvalidOptionalInference.sx:2:17: error: 'null' requires an expected optional type\n");

    const invalid_optional_condition_command = b.addRunArtifact(executable);
    invalid_optional_condition_command.addArgs(&.{ "compile", "Tests/InvalidOptionalCondition.sx" });
    invalid_optional_condition_command.expectExitCode(1);
    invalid_optional_condition_command.expectStdErrEqual("Tests/InvalidOptionalCondition.sx:3:8: error: expected 'bool', found 'int?'\n");

    const invalid_conditional_binding_source_command = b.addRunArtifact(executable);
    invalid_conditional_binding_source_command.addArgs(&.{ "compile", "Tests/InvalidConditionalBindingSource.sx" });
    invalid_conditional_binding_source_command.expectExitCode(1);
    invalid_conditional_binding_source_command.expectStdErrEqual("Tests/InvalidConditionalBindingSource.sx:2:16: error: conditional binding source must have an optional type\n");

    const invalid_safe_access_command = b.addRunArtifact(executable);
    invalid_safe_access_command.addArgs(&.{ "compile", "Tests/InvalidSafeAccess.sx" });
    invalid_safe_access_command.expectExitCode(1);
    invalid_safe_access_command.expectStdErrEqual("Tests/InvalidSafeAccess.sx:7:18: error: safe access requires an optional receiver\n");

    const invalid_safe_mutation_command = b.addRunArtifact(executable);
    invalid_safe_mutation_command.addArgs(&.{ "compile", "Tests/InvalidSafeMutation.sx" });
    invalid_safe_mutation_command.expectExitCode(1);
    invalid_safe_mutation_command.expectStdErrEqual("Tests/InvalidSafeMutation.sx:11:12: error: cannot call mutating method 'translate' on immutable value 'value'\n");

    const invalid_optional_demotion_command = b.addRunArtifact(executable);
    invalid_optional_demotion_command.addArgs(&.{ "compile", "Tests/InvalidOptionalDemotion.sx" });
    invalid_optional_demotion_command.expectExitCode(1);
    invalid_optional_demotion_command.expectStdErrEqual("Tests/InvalidOptionalDemotion.sx:6:21: error: expected 'int', found 'int?'\n");

    const invalid_null_comparison_command = b.addRunArtifact(executable);
    invalid_null_comparison_command.addArgs(&.{ "compile", "Tests/InvalidNullComparison.sx" });
    invalid_null_comparison_command.expectExitCode(1);
    invalid_null_comparison_command.expectStdErrEqual("Tests/InvalidNullComparison.sx:2:17: error: 'null' cannot be compared without an expected optional type\n");

    const invalid_nested_optional_command = b.addRunArtifact(executable);
    invalid_nested_optional_command.addArgs(&.{ "compile", "Tests/InvalidNestedOptional.sx" });
    invalid_nested_optional_command.expectExitCode(1);
    invalid_nested_optional_command.expectStdErrEqual("Tests/InvalidNestedOptional.sx:2:19: error: an optional type cannot be optional again\n");

    const invalid_void_optional_command = b.addRunArtifact(executable);
    invalid_void_optional_command.addArgs(&.{ "compile", "Tests/InvalidVoidOptional.sx" });
    invalid_void_optional_command.expectExitCode(1);
    invalid_void_optional_command.expectStdErrEqual("Tests/InvalidVoidOptional.sx:1:20: error: type 'void' cannot be optional\n");

    const reserved_null_identifier_command = b.addRunArtifact(executable);
    reserved_null_identifier_command.addArgs(&.{ "compile", "Tests/ReservedNullIdentifier.sx" });
    reserved_null_identifier_command.expectExitCode(1);
    reserved_null_identifier_command.expectStdErrEqual("Tests/ReservedNullIdentifier.sx:2:9: error: expected variable name\n");

    const ambiguous_null_overload_command = b.addRunArtifact(executable);
    ambiguous_null_overload_command.addArgs(&.{ "compile", "Tests/AmbiguousNullOverload.sx" });
    ambiguous_null_overload_command.expectExitCode(1);
    ambiguous_null_overload_command.expectStdErrEqual("Tests/AmbiguousNullOverload.sx:10:11: error: ambiguous call to function 'select'; matching signatures: select(int?), select(str?)\n");

    const invalid_untyped_null_sequence_command = b.addRunArtifact(executable);
    invalid_untyped_null_sequence_command.addArgs(&.{ "compile", "Tests/InvalidUntypedNullSequence.sx" });
    invalid_untyped_null_sequence_command.expectExitCode(1);
    invalid_untyped_null_sequence_command.expectStdErrEqual("Tests/InvalidUntypedNullSequence.sx:2:19: error: 'null' in a sequence literal requires an expected collection element type\n");

    const invalidated_optional_reduction_command = b.addRunArtifact(executable);
    invalidated_optional_reduction_command.addArgs(&.{ "compile", "Tests/InvalidatedOptionalReduction.sx" });
    invalidated_optional_reduction_command.expectExitCode(1);
    invalidated_optional_reduction_command.expectStdErrEqual("Tests/InvalidatedOptionalReduction.sx:5:21: error: arithmetic operator requires numeric operands, found 'int?' and 'int'\n");

    const invalidated_optional_alias_reduction_command = b.addRunArtifact(executable);
    invalidated_optional_alias_reduction_command.addArgs(&.{ "compile", "Tests/InvalidatedOptionalAliasReduction.sx" });
    invalidated_optional_alias_reduction_command.expectExitCode(1);
    invalidated_optional_alias_reduction_command.expectStdErrEqual("Tests/InvalidatedOptionalAliasReduction.sx:9:21: error: arithmetic operator requires numeric operands, found 'int?' and 'int'\n");

    const invalidated_optional_lambda_reduction_command = b.addRunArtifact(executable);
    invalidated_optional_lambda_reduction_command.addArgs(&.{ "compile", "Tests/InvalidatedOptionalLambdaReduction.sx" });
    invalidated_optional_lambda_reduction_command.expectExitCode(1);
    invalidated_optional_lambda_reduction_command.expectStdErrEqual("Tests/InvalidatedOptionalLambdaReduction.sx:7:21: error: arithmetic operator requires numeric operands, found 'int?' and 'int'\n");

    const invalid_let_function_command = b.addRunArtifact(executable);
    invalid_let_function_command.addArgs(&.{ "compile", "Tests/InvalidLetFunction.sx" });
    invalid_let_function_command.expectExitCode(1);
    invalid_let_function_command.expectStdErrEqual("Tests/InvalidLetFunction.sx:2:9: error: type 'func' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_let_function_field_command = b.addRunArtifact(executable);
    invalid_let_function_field_command.addArgs(&.{ "compile", "Tests/InvalidLetFunctionField.sx" });
    invalid_let_function_field_command.expectExitCode(1);
    invalid_let_function_field_command.expectStdErrEqual("Tests/InvalidLetFunctionField.sx:6:9: error: type 'Handler' is not an independent value because field 'callback' reaches 'func'; use 'var'\n");

    const invalid_implicit_conditional_function_command = b.addRunArtifact(executable);
    invalid_implicit_conditional_function_command.addArgs(&.{ "compile", "Tests/InvalidImplicitConditionalFunction.sx" });
    invalid_implicit_conditional_function_command.expectExitCode(1);
    invalid_implicit_conditional_function_command.expectStdErrEqual("Tests/InvalidImplicitConditionalFunction.sx:3:8: error: type 'func' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_let_function_iteration_command = b.addRunArtifact(executable);
    invalid_let_function_iteration_command.addArgs(&.{ "compile", "Tests/InvalidLetFunctionIteration.sx" });
    invalid_let_function_iteration_command.expectExitCode(1);
    invalid_let_function_iteration_command.expectStdErrEqual("Tests/InvalidLetFunctionIteration.sx:3:13: error: type 'func' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_let_class_command = b.addRunArtifact(executable);
    invalid_let_class_command.addArgs(&.{ "compile", "Tests/InvalidLetClass.sx" });
    invalid_let_class_command.expectExitCode(1);
    invalid_let_class_command.expectStdErrEqual("Tests/InvalidLetClass.sx:4:9: error: type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_let_class_container_command = b.addRunArtifact(executable);
    invalid_let_class_container_command.addArgs(&.{ "compile", "Tests/InvalidLetClassContainer.sx" });
    invalid_let_class_container_command.expectExitCode(1);
    invalid_let_class_container_command.expectStdErrEqual("Tests/InvalidLetClassContainer.sx:8:9: error: type 'Team' is not an independent value because field 'players' reaches 'Player'; use 'var'\n");

    const invalid_class_reference_command = b.addRunArtifact(executable);
    invalid_class_reference_command.addArgs(&.{ "compile", "Tests/InvalidClassReference.sx" });
    invalid_class_reference_command.expectExitCode(1);
    invalid_class_reference_command.expectStdErrEqual("Tests/InvalidClassReference.sx:3:14: error: class 'Player' already has reference semantics; '&Player' is invalid\n");

    const invalid_implicit_class_conditional_command = b.addRunArtifact(executable);
    invalid_implicit_class_conditional_command.addArgs(&.{ "compile", "Tests/InvalidImplicitClassConditional.sx" });
    invalid_implicit_class_conditional_command.expectExitCode(1);
    invalid_implicit_class_conditional_command.expectStdErrEqual("Tests/InvalidImplicitClassConditional.sx:8:8: error: type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_let_class_iteration_command = b.addRunArtifact(executable);
    invalid_let_class_iteration_command.addArgs(&.{ "compile", "Tests/InvalidLetClassIteration.sx" });
    invalid_let_class_iteration_command.expectExitCode(1);
    invalid_let_class_iteration_command.expectStdErrEqual("Tests/InvalidLetClassIteration.sx:5:13: error: type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'\n");

    const invalid_class_default_variable_command = b.addRunArtifact(executable);
    invalid_class_default_variable_command.addArgs(&.{ "compile", "Tests/InvalidClassDefaultVariable.sx" });
    invalid_class_default_variable_command.expectExitCode(1);
    invalid_class_default_variable_command.expectStdErrEqual("Tests/InvalidClassDefaultVariable.sx:4:9: error: class 'Player' requires an initializer\n");

    const invalid_missing_class_constructor_command = b.addRunArtifact(executable);
    invalid_missing_class_constructor_command.addArgs(&.{ "compile", "Tests/InvalidMissingClassConstructor.sx" });
    invalid_missing_class_constructor_command.expectExitCode(1);
    invalid_missing_class_constructor_command.expectStdErrEqual("Tests/InvalidMissingClassConstructor.sx:10:19: error: no compatible constructor for 'Session'; visible constructors: Session(str)\n");

    const invalid_named_struct_constructor_command = b.addRunArtifact(executable);
    invalid_named_struct_constructor_command.addArgs(&.{ "compile", "Tests/InvalidNamedStructConstructor.sx" });
    invalid_named_struct_constructor_command.expectExitCode(1);
    invalid_named_struct_constructor_command.expectStdErrEqual("Tests/InvalidNamedStructConstructor.sx:10:17: error: struct 'Value' declares custom constructors and cannot use a named field initializer\n");

    const invalid_private_struct_constructor_command = b.addRunArtifact(executable);
    invalid_private_struct_constructor_command.addArgs(&.{ "compile", "Tests/InvalidPrivateStructConstructor.sx" });
    invalid_private_struct_constructor_command.expectExitCode(1);
    invalid_private_struct_constructor_command.expectStdErrEqual("Tests/InvalidPrivateStructConstructor.sx:10:18: error: constructor of struct 'Secret' is private\n");

    const invalid_missing_struct_constructor_field_command = b.addRunArtifact(executable);
    invalid_missing_struct_constructor_field_command.addArgs(&.{ "compile", "Tests/InvalidMissingStructConstructorField.sx" });
    invalid_missing_struct_constructor_field_command.expectExitCode(1);
    invalid_missing_struct_constructor_field_command.expectStdErrEqual("Tests/InvalidMissingStructConstructorField.sx:4:5: error: constructor of struct 'Value' leaves field 'number' without a value\n");

    const invalid_inheritance_cycle_command = b.addRunArtifact(executable);
    invalid_inheritance_cycle_command.addArgs(&.{ "compile", "Tests/InvalidInheritanceCycle.sx" });
    invalid_inheritance_cycle_command.expectExitCode(1);
    invalid_inheritance_cycle_command.expectStdErrEqual("Tests/InvalidInheritanceCycle.sx:1:7: error: inheritance cycle involving class 'First'\n");

    const unique_resource_initializer_visibility_command = b.addRunArtifact(executable);
    unique_resource_initializer_visibility_command.addArgs(&.{ "compile", "Tests/UniqueResourceVisibility/Initializer/silex.json" });
    unique_resource_initializer_visibility_command.expectExitCode(1);
    unique_resource_initializer_visibility_command.expectStdErrEqual(
        "Tests/UniqueResourceVisibility/Initializer/Main.sx:4:30: error: initializer of unique resource struct 'Resources.Resource' is private to its module\n",
    );

    const unique_resource_field_visibility_command = b.addRunArtifact(executable);
    unique_resource_field_visibility_command.addArgs(&.{ "compile", "Tests/UniqueResourceVisibility/Field/silex.json" });
    unique_resource_field_visibility_command.expectExitCode(1);
    unique_resource_field_visibility_command.expectStdErrEqual(
        "Tests/UniqueResourceVisibility/Field/Main.sx:5:20: error: field 'handle' of unique resource struct 'Resources.Resource' is private to its module\n",
    );

    const unique_resource_extension_visibility_command = b.addRunArtifact(executable);
    unique_resource_extension_visibility_command.addArgs(&.{ "compile", "Tests/UniqueResourceVisibility/Extension/silex.json" });
    unique_resource_extension_visibility_command.expectExitCode(1);
    unique_resource_extension_visibility_command.expectStdErrEqual(
        "Tests/UniqueResourceVisibility/Extension/Main.sx:5:21: error: field 'handle' of unique resource struct 'Resources.Resource' is private to its module\n",
    );

    const extension_visibility_command = b.addRunArtifact(executable);
    extension_visibility_command.addArgs(&.{ "compile", "Tests/ExtensionVisibility/silex.json" });
    extension_visibility_command.expectExitCode(0);

    const generic_extension_private_command = b.addRunArtifact(executable);
    generic_extension_private_command.addArgs(&.{ "compile", "Tests/GenericExtensionPrivate/silex.json" });
    generic_extension_private_command.expectExitCode(1);
    generic_extension_private_command.expectStdErrEqual(
        "Tests/GenericExtensionPrivate/Main.sx:7:15: error: class 'GenericExtensionPrivate.Core.Box' has no method 'keep<int>'\n",
    );

    const extension_conflict_command = b.addRunArtifact(executable);
    extension_conflict_command.addArgs(&.{ "compile", "Tests/ExtensionConflict/silex.json" });
    extension_conflict_command.expectExitCode(1);
    extension_conflict_command.expectStdErrEqual(
        "Tests/ExtensionConflict/Second.sx:5:17: error: extension method 'read<int>' from module 'ExtensionConflict.Second' conflicts with module 'ExtensionConflict.First' on type 'ExtensionConflict.Core.Value'\n",
    );

    const extension_conformance_visibility_command = b.addRunArtifact(executable);
    extension_conformance_visibility_command.addArgs(&.{ "compile", "Tests/ExtensionConformanceVisibility/silex.json" });
    extension_conformance_visibility_command.expectExitCode(0);

    const extension_conformance_conflict_command = b.addRunArtifact(executable);
    extension_conformance_conflict_command.addArgs(&.{ "compile", "Tests/ExtensionConformanceConflict/silex.json" });
    extension_conformance_conflict_command.expectExitCode(1);
    extension_conformance_conflict_command.expectStdErrEqual(
        "Tests/ExtensionConformanceConflict/Second.sx:4:23: error: extension conformance of type 'ExtensionConformanceConflict.Types.Sprite' to protocol 'ExtensionConformanceConflict.Core.Drawable' from module 'ExtensionConformanceConflict.Second' conflicts with module 'ExtensionConformanceConflict.First'\n",
    );

    const invalid_private_super_constructor_command = b.addRunArtifact(executable);
    invalid_private_super_constructor_command.addArgs(&.{ "compile", "Tests/InvalidPrivateSuperConstructor.sx" });
    invalid_private_super_constructor_command.expectExitCode(1);
    invalid_private_super_constructor_command.expectStdErrEqual("Tests/InvalidPrivateSuperConstructor.sx:6:21: error: constructor of base class 'Base' is private\n");

    const invalid_class_collection_covariance_command = b.addRunArtifact(executable);
    invalid_class_collection_covariance_command.addArgs(&.{ "compile", "Tests/InvalidClassCollectionCovariance.sx" });
    invalid_class_collection_covariance_command.expectExitCode(1);
    invalid_class_collection_covariance_command.expectStdErrEqual("Tests/InvalidClassCollectionCovariance.sx:6:29: error: expected 'Entity[]', found 'Player[]'\n");

    const invalid_private_class_field_command = b.addRunArtifact(executable);
    invalid_private_class_field_command.addArgs(&.{ "compile", "Tests/InvalidPrivateClassField.sx" });
    invalid_private_class_field_command.expectExitCode(1);
    invalid_private_class_field_command.expectStdErrEqual("Tests/InvalidPrivateClassField.sx:7:17: error: field 'value' is private in class 'Vault'\n");

    const invalid_private_class_method_command = b.addRunArtifact(executable);
    invalid_private_class_method_command.addArgs(&.{ "compile", "Tests/InvalidPrivateClassMethod.sx" });
    invalid_private_class_method_command.expectExitCode(1);
    invalid_private_class_method_command.expectStdErrEqual("Tests/InvalidPrivateClassMethod.sx:7:11: error: method 'reset' is private in class 'Vault'\n");

    const invalid_sub_class_field_command = b.addRunArtifact(executable);
    invalid_sub_class_field_command.addArgs(&.{ "compile", "Tests/InvalidSubClassField.sx" });
    invalid_sub_class_field_command.expectExitCode(1);
    invalid_sub_class_field_command.expectStdErrEqual("Tests/InvalidSubClassField.sx:7:17: error: field 'value' is accessible only from class 'Vault' and its descendants\n");

    const invalid_private_class_initializer_command = b.addRunArtifact(executable);
    invalid_private_class_initializer_command.addArgs(&.{ "compile", "Tests/InvalidPrivateClassInitializer.sx" });
    invalid_private_class_initializer_command.expectExitCode(1);
    invalid_private_class_initializer_command.expectStdErrEqual("Tests/InvalidPrivateClassInitializer.sx:6:23: error: field 'value' is private in class 'Vault'\n");

    const invalid_struct_member_visibility_command = b.addRunArtifact(executable);
    invalid_struct_member_visibility_command.addArgs(&.{ "compile", "Tests/InvalidStructMemberVisibility.sx" });
    invalid_struct_member_visibility_command.expectExitCode(1);
    invalid_struct_member_visibility_command.expectStdErrEqual("Tests/InvalidStructMemberVisibility.sx:2:5: error: a struct member cannot use 'protected' because structs do not support inheritance\n");

    const struct_private_visibility_command = b.addRunArtifact(executable);
    struct_private_visibility_command.addArgs(&.{ "compile", "Tests/StructPrivateVisibility/Valid/silex.json" });
    struct_private_visibility_command.expectExitCode(0);

    const invalid_private_struct_initializer_command = b.addRunArtifact(executable);
    invalid_private_struct_initializer_command.addArgs(&.{ "compile", "Tests/StructPrivateVisibility/InvalidInitializer/silex.json" });
    invalid_private_struct_initializer_command.expectExitCode(1);
    invalid_private_struct_initializer_command.expectStdErrEqual("Tests/StructPrivateVisibility/InvalidInitializer/Main.sx:4:24: error: initializer of struct 'Queues.Queue' is private because it declares private fields\n");

    const invalid_private_struct_field_command = b.addRunArtifact(executable);
    invalid_private_struct_field_command.addArgs(&.{ "compile", "Tests/StructPrivateVisibility/InvalidField/silex.json" });
    invalid_private_struct_field_command.expectExitCode(1);
    invalid_private_struct_field_command.expectStdErrEqual("Tests/StructPrivateVisibility/InvalidField/Main.sx:5:17: error: field 'values' is private in struct 'Queues.Queue'\n");

    const invalid_private_struct_extension_command = b.addRunArtifact(executable);
    invalid_private_struct_extension_command.addArgs(&.{ "compile", "Tests/StructPrivateVisibility/InvalidExtension/silex.json" });
    invalid_private_struct_extension_command.expectExitCode(1);
    invalid_private_struct_extension_command.expectStdErrEqual("Tests/StructPrivateVisibility/InvalidExtension/Main.sx:5:21: error: field 'values' is private in struct 'Queues.Queue'\n");

    const invalid_assertion_condition_command = b.addRunArtifact(executable);
    invalid_assertion_condition_command.addArgs(&.{ "compile", "Tests/InvalidAssertionCondition.sx" });
    invalid_assertion_condition_command.expectExitCode(1);
    invalid_assertion_condition_command.expectStdErrEqual(
        "Tests/InvalidAssertionCondition.sx:2:12: error: expected 'bool', found 'int'\n",
    );

    const invalid_assertion_message_command = b.addRunArtifact(executable);
    invalid_assertion_message_command.addArgs(&.{ "compile", "Tests/InvalidAssertionMessage.sx" });
    invalid_assertion_message_command.expectExitCode(1);
    invalid_assertion_message_command.expectStdErrEqual(
        "Tests/InvalidAssertionMessage.sx:2:18: error: expected 'str', found 'int'\n",
    );

    const assertion_failure_command = b.addRunArtifact(executable);
    assertion_failure_command.addArgs(&.{ "run", "Tests/AssertionFailure.sx" });
    assertion_failure_command.expectExitCode(1);
    assertion_failure_command.expectStdErrEqual(b.fmt(
        "{s}:2:5: runtime error: assertion failed: planned failure\n",
        .{b.pathFromRoot("Tests/AssertionFailure.sx")},
    ));

    const invalid_panic_message_command = b.addRunArtifact(executable);
    invalid_panic_message_command.addArgs(&.{ "compile", "Tests/InvalidPanicMessage.sx" });
    invalid_panic_message_command.expectExitCode(1);
    invalid_panic_message_command.expectStdErrEqual(
        "Tests/InvalidPanicMessage.sx:2:11: error: expected 'str', found 'int'\n",
    );

    const panic_literal_command = b.addRunArtifact(executable);
    panic_literal_command.addArgs(&.{ "run", "Tests/PanicLiteral.sx" });
    panic_literal_command.expectExitCode(1);
    panic_literal_command.expectStdErrEqual(b.fmt(
        "{s}:2:5: runtime error: literal panic\n",
        .{b.pathFromRoot("Tests/PanicLiteral.sx")},
    ));

    const panic_computed_command = b.addRunArtifact(executable);
    panic_computed_command.addArgs(&.{ "run", "Tests/PanicComputed.sx" });
    panic_computed_command.expectExitCode(1);
    panic_computed_command.expectStdErrEqual(b.fmt(
        "{s}:3:5: runtime error: computed panic\n",
        .{b.pathFromRoot("Tests/PanicComputed.sx")},
    ));

    const removed_random_next_command = b.addRunArtifact(executable);
    removed_random_next_command.step.dependOn(b.getInstallStep());
    removed_random_next_command.addArgs(&.{ "compile", "Tests/RemovedRandomNext.sx" });
    removed_random_next_command.expectExitCode(1);
    removed_random_next_command.expectStdErrEqual(
        "Tests/RemovedRandomNext.sx:5:18: error: class 'STD.Randomizer' has no method 'next'\n",
    );

    const removed_random_module_command = b.addRunArtifact(executable);
    removed_random_module_command.step.dependOn(b.getInstallStep());
    removed_random_module_command.addArgs(&.{ "compile", "Tests/RemovedRandomModule.sx" });
    removed_random_module_command.expectExitCode(1);
    removed_random_module_command.expectStdErrEqual(
        "Tests/RemovedRandomModule.sx:1:1: error: module 'STD.Random' was not found\n",
    );

    const removed_random_system_command = b.addRunArtifact(executable);
    removed_random_system_command.step.dependOn(b.getInstallStep());
    removed_random_system_command.addArgs(&.{ "compile", "Tests/RemovedRandomSystem.sx" });
    removed_random_system_command.expectExitCode(1);
    removed_random_system_command.expectStdErrEqual(
        "Tests/RemovedRandomSystem.sx:4:33: error: type 'STD.Randomizer' has no static method 'system'\n",
    );

    const invalid_logical_command = b.addRunArtifact(executable);
    invalid_logical_command.addArgs(&.{ "compile", "Tests/InvalidLogical.sx" });
    invalid_logical_command.expectExitCode(1);
    invalid_logical_command.expectStdErrEqual(
        "Tests/InvalidLogical.sx:2:11: error: logical operator requires 'bool' operands, found 'int' and 'bool'\n",
    );

    const invalid_while_command = b.addRunArtifact(executable);
    invalid_while_command.addArgs(&.{ "compile", "Tests/InvalidWhileCondition.sx" });
    invalid_while_command.expectExitCode(1);
    invalid_while_command.expectStdErrEqual(
        "Tests/InvalidWhileCondition.sx:2:12: error: expected 'bool', found 'int'\n",
    );

    const missing_separator_command = b.addRunArtifact(executable);
    missing_separator_command.addArgs(&.{ "compile", "Tests/MissingStatementSeparator.sx" });
    missing_separator_command.expectExitCode(1);
    missing_separator_command.expectStdErrEqual(
        "Tests/MissingStatementSeparator.sx:2:15: error: expected ';' or line break\n",
    );

    const missing_type_command = b.addRunArtifact(executable);
    missing_type_command.addArgs(&.{ "compile", "Tests/MissingTypeAnnotation.sx" });
    missing_type_command.expectExitCode(1);
    missing_type_command.expectStdErrEqual(
        "Tests/MissingTypeAnnotation.sx:2:17: error: expected type name after ':'\n",
    );

    const missing_return_command = b.addRunArtifact(executable);
    missing_return_command.addArgs(&.{ "compile", "Tests/MissingReturn.sx" });
    missing_return_command.expectExitCode(1);
    missing_return_command.expectStdErrEqual(
        "Tests/MissingReturn.sx:1:6: error: function 'value' must return 'int' on every path\n",
    );

    const implicit_void_return_value_command = b.addRunArtifact(executable);
    implicit_void_return_value_command.addArgs(&.{ "compile", "Tests/ImplicitVoidReturnValue.sx" });
    implicit_void_return_value_command.expectExitCode(1);
    implicit_void_return_value_command.expectStdErrEqual(
        "Tests/ImplicitVoidReturnValue.sx:2:5: error: void function cannot return a value\n",
    );

    const invalid_arguments_command = b.addRunArtifact(executable);
    invalid_arguments_command.addArgs(&.{ "compile", "Tests/InvalidArguments.sx" });
    invalid_arguments_command.expectExitCode(1);
    invalid_arguments_command.expectStdErrEqual(
        "Tests/InvalidArguments.sx:2:11: error: no compatible signature for function 'add'; visible signatures: add(int, int)\n",
    );

    const duplicate_overload_alias_command = b.addRunArtifact(executable);
    duplicate_overload_alias_command.addArgs(&.{ "compile", "Tests/DuplicateOverloadAlias.sx" });
    duplicate_overload_alias_command.expectExitCode(1);
    duplicate_overload_alias_command.expectStdErrEqual(
        "Tests/DuplicateOverloadAlias.sx:5:6: error: function 'measure' with this callable shape is already declared\n",
    );

    const duplicate_overload_return_command = b.addRunArtifact(executable);
    duplicate_overload_return_command.addArgs(&.{ "compile", "Tests/DuplicateOverloadReturn.sx" });
    duplicate_overload_return_command.expectExitCode(1);
    duplicate_overload_return_command.expectStdErrEqual(
        "Tests/DuplicateOverloadReturn.sx:5:6: error: function 'measure' with this callable shape is already declared\n",
    );

    const ambiguous_overload_command = b.addRunArtifact(executable);
    ambiguous_overload_command.addArgs(&.{ "compile", "Tests/AmbiguousOverload.sx" });
    ambiguous_overload_command.expectExitCode(1);
    ambiguous_overload_command.expectStdErrEqual(
        "Tests/AmbiguousOverload.sx:10:11: error: ambiguous call to function 'measure'; matching signatures: measure(float), measure(float64)\n",
    );

    const module_overload_command = b.addRunArtifact(executable);
    module_overload_command.addArgs(&.{ "run", "Tests/Modules/Overloads/project.json" });
    module_overload_command.expectStdOutEqual(hostText(b, "1\n2\n3\n"));

    const unknown_struct_field_command = b.addRunArtifact(executable);
    unknown_struct_field_command.addArgs(&.{ "compile", "Tests/UnknownStructField.sx" });
    unknown_struct_field_command.expectExitCode(1);
    unknown_struct_field_command.expectStdErrEqual(
        "Tests/UnknownStructField.sx:7:35: error: unknown field 'depth' in struct 'Position'\n",
    );

    const immutable_struct_field_command = b.addRunArtifact(executable);
    immutable_struct_field_command.addArgs(&.{ "compile", "Tests/ImmutableStructField.sx" });
    immutable_struct_field_command.expectExitCode(1);
    immutable_struct_field_command.expectStdErrEqual(
        "Tests/ImmutableStructField.sx:8:5: error: cannot assign to immutable variable 'position'\n",
    );

    const immutable_cascade_command = b.addRunArtifact(executable);
    immutable_cascade_command.addArgs(&.{ "compile", "Tests/ImmutableCascade.sx" });
    immutable_cascade_command.expectExitCode(1);
    immutable_cascade_command.expectStdErrEqual(
        "Tests/ImmutableCascade.sx:8:11: error: cannot assign through cascade on immutable value 'point'\n",
    );

    const duplicate_struct_field_command = b.addRunArtifact(executable);
    duplicate_struct_field_command.addArgs(&.{ "compile", "Tests/DuplicateStructField.sx" });
    duplicate_struct_field_command.expectExitCode(1);
    duplicate_struct_field_command.expectStdErrEqual(
        "Tests/DuplicateStructField.sx:7:35: error: field 'x' is initialized more than once\n",
    );

    const invalid_struct_field_type_command = b.addRunArtifact(executable);
    invalid_struct_field_type_command.addArgs(&.{ "compile", "Tests/InvalidStructFieldType.sx" });
    invalid_struct_field_type_command.expectExitCode(1);
    invalid_struct_field_type_command.expectStdErrEqual(
        "Tests/InvalidStructFieldType.sx:7:31: error: expected 'int', found 'str'\n",
    );

    const missing_generic_arguments_command = b.addRunArtifact(executable);
    missing_generic_arguments_command.addArgs(&.{ "compile", "Tests/MissingGenericArguments.sx" });
    missing_generic_arguments_command.expectExitCode(1);
    missing_generic_arguments_command.expectStdErrEqual(
        "Tests/MissingGenericArguments.sx:6:15: error: generic struct 'Box' requires 1 type argument\n",
    );

    const unexpected_generic_arguments_command = b.addRunArtifact(executable);
    unexpected_generic_arguments_command.addArgs(&.{ "compile", "Tests/UnexpectedGenericArguments.sx" });
    unexpected_generic_arguments_command.expectExitCode(1);
    unexpected_generic_arguments_command.expectStdErrEqual(
        "Tests/UnexpectedGenericArguments.sx:6:15: error: struct 'Box' does not accept type arguments\n",
    );

    const invalid_generic_arity_command = b.addRunArtifact(executable);
    invalid_generic_arity_command.addArgs(&.{ "compile", "Tests/InvalidGenericArity.sx" });
    invalid_generic_arity_command.expectExitCode(1);
    invalid_generic_arity_command.expectStdErrEqual(
        "Tests/InvalidGenericArity.sx:7:16: error: generic struct 'Pair' expects 2 type arguments, found 1\n",
    );

    const invalid_generic_specialization_command = b.addRunArtifact(executable);
    invalid_generic_specialization_command.addArgs(&.{ "compile", "Tests/InvalidGenericSpecialization.sx" });
    invalid_generic_specialization_command.expectExitCode(1);
    invalid_generic_specialization_command.expectStdErrEqual(
        "Tests/InvalidGenericSpecialization.sx:6:22: error: comparison operator requires numeric operands, found 'str' and 'str'\n",
    );

    const recursive_generic_structure_expansion_command = b.addRunArtifact(executable);
    recursive_generic_structure_expansion_command.addArgs(&.{ "compile", "Tests/RecursiveGenericStructureExpansion.sx" });
    recursive_generic_structure_expansion_command.expectExitCode(1);
    recursive_generic_structure_expansion_command.expectStdErrEqual(
        "Tests/RecursiveGenericStructureExpansion.sx:6:9: error: generic struct 'Expand' recursively expands with different type arguments\n",
    );

    const missing_generic_enum_arguments_command = b.addRunArtifact(executable);
    missing_generic_enum_arguments_command.addArgs(&.{ "compile", "Tests/MissingGenericEnumArguments.sx" });
    missing_generic_enum_arguments_command.expectExitCode(1);
    missing_generic_enum_arguments_command.expectStdErrEqual(
        "Tests/MissingGenericEnumArguments.sx:7:9: error: generic enum 'Outcome' requires 2 type arguments\n",
    );

    const invalid_generic_enum_arity_command = b.addRunArtifact(executable);
    invalid_generic_enum_arity_command.addArgs(&.{ "compile", "Tests/InvalidGenericEnumArity.sx" });
    invalid_generic_enum_arity_command.expectExitCode(1);
    invalid_generic_enum_arity_command.expectStdErrEqual(
        "Tests/InvalidGenericEnumArity.sx:7:17: error: generic enum 'Outcome' expects 2 type arguments, found 1\n",
    );

    const unexpected_generic_enum_arguments_command = b.addRunArtifact(executable);
    unexpected_generic_enum_arguments_command.addArgs(&.{ "compile", "Tests/UnexpectedGenericEnumArguments.sx" });
    unexpected_generic_enum_arguments_command.expectExitCode(1);
    unexpected_generic_enum_arguments_command.expectStdErrEqual(
        "Tests/UnexpectedGenericEnumArguments.sx:6:17: error: enum 'State' does not accept type arguments\n",
    );

    const recursive_generic_enum_expansion_command = b.addRunArtifact(executable);
    recursive_generic_enum_expansion_command.addArgs(&.{ "compile", "Tests/RecursiveGenericEnumExpansion.sx" });
    recursive_generic_enum_expansion_command.expectExitCode(1);
    recursive_generic_enum_expansion_command.expectStdErrEqual(
        "Tests/RecursiveGenericEnumExpansion.sx:2:5: error: generic enum 'Expand' recursively expands with different type arguments\n",
    );

    const invalid_generic_enum_independence_command = b.addRunArtifact(executable);
    invalid_generic_enum_independence_command.addArgs(&.{ "compile", "Tests/InvalidGenericEnumIndependence.sx" });
    invalid_generic_enum_independence_command.expectExitCode(1);
    invalid_generic_enum_independence_command.expectStdErrEqual(
        "Tests/InvalidGenericEnumIndependence.sx:6:9: error: type 'Callback<int>' is not an independent value because field 'ready[1]' reaches 'func'; use 'var'\n",
    );

    const invalid_generic_raw_enum_command = b.addRunArtifact(executable);
    invalid_generic_raw_enum_command.addArgs(&.{ "compile", "Tests/InvalidGenericRawEnum.sx" });
    invalid_generic_raw_enum_command.expectExitCode(1);
    invalid_generic_raw_enum_command.expectStdErrEqual(
        "Tests/InvalidGenericRawEnum.sx:1:13: error: a raw enum cannot be generic\n",
    );

    const invalid_generic_enum_void_argument_command = b.addRunArtifact(executable);
    invalid_generic_enum_void_argument_command.addArgs(&.{ "compile", "Tests/InvalidGenericEnumVoidArgument.sx" });
    invalid_generic_enum_void_argument_command.expectExitCode(1);
    invalid_generic_enum_void_argument_command.expectStdErrEqual(
        "Tests/InvalidGenericEnumVoidArgument.sx:6:23: error: void cannot be used as a type argument\n",
    );

    const missing_result_arguments_command = b.addRunArtifact(executable);
    missing_result_arguments_command.addArgs(&.{ "compile", "Tests/MissingResultArguments.sx" });
    missing_result_arguments_command.expectExitCode(1);
    missing_result_arguments_command.expectStdErrEqual(
        "Tests/MissingResultArguments.sx:2:9: error: generic enum 'Result' requires 2 type arguments\n",
    );

    const invalid_result_type_arity_command = b.addRunArtifact(executable);
    invalid_result_type_arity_command.addArgs(&.{ "compile", "Tests/InvalidResultTypeArity.sx" });
    invalid_result_type_arity_command.expectExitCode(1);
    invalid_result_type_arity_command.expectStdErrEqual(
        "Tests/InvalidResultTypeArity.sx:6:17: error: generic enum 'Result' expects 2 type arguments, found 1\n",
    );

    const invalid_result_success_arity_command = b.addRunArtifact(executable);
    invalid_result_success_arity_command.addArgs(&.{ "compile", "Tests/InvalidResultSuccessArity.sx" });
    invalid_result_success_arity_command.expectExitCode(1);
    invalid_result_success_arity_command.expectStdErrEqual(
        "Tests/InvalidResultSuccessArity.sx:6:38: error: variant 'Result<int, Failure>.success' expects 1 associated values, found 0\n",
    );

    const invalid_void_result_success_argument_command = b.addRunArtifact(executable);
    invalid_void_result_success_argument_command.addArgs(&.{ "compile", "Tests/InvalidVoidResultSuccessArgument.sx" });
    invalid_void_result_success_argument_command.expectExitCode(1);
    invalid_void_result_success_argument_command.expectStdErrEqual(
        "Tests/InvalidVoidResultSuccessArgument.sx:6:39: error: variant 'Result<void, Failure>.success' expects 0 associated values, found 1\n",
    );

    const invalid_result_failure_arity_command = b.addRunArtifact(executable);
    invalid_result_failure_arity_command.addArgs(&.{ "compile", "Tests/InvalidResultFailureArity.sx" });
    invalid_result_failure_arity_command.expectExitCode(1);
    invalid_result_failure_arity_command.expectStdErrEqual(
        "Tests/InvalidResultFailureArity.sx:6:38: error: variant 'Result<int, Failure>.failure' expects 1 associated values, found 0\n",
    );

    const invalid_implicit_result_conversion_command = b.addRunArtifact(executable);
    invalid_implicit_result_conversion_command.addArgs(&.{ "compile", "Tests/InvalidImplicitResultConversion.sx" });
    invalid_implicit_result_conversion_command.expectExitCode(1);
    invalid_implicit_result_conversion_command.expectStdErrEqual(
        "Tests/InvalidImplicitResultConversion.sx:6:12: error: expected 'Result<int, Failure>', found 'int'\n",
    );

    const invalid_implicit_result_error_conversion_command = b.addRunArtifact(executable);
    invalid_implicit_result_error_conversion_command.addArgs(&.{ "compile", "Tests/InvalidImplicitResultErrorConversion.sx" });
    invalid_implicit_result_error_conversion_command.expectExitCode(1);
    invalid_implicit_result_error_conversion_command.expectStdErrEqual(
        "Tests/InvalidImplicitResultErrorConversion.sx:6:12: error: expected 'Result<int, Failure>', found 'Failure'\n",
    );

    const invalid_result_void_error_command = b.addRunArtifact(executable);
    invalid_result_void_error_command.addArgs(&.{ "compile", "Tests/InvalidResultVoidError.sx" });
    invalid_result_void_error_command.expectExitCode(1);
    invalid_result_void_error_command.expectStdErrEqual(
        "Tests/InvalidResultVoidError.sx:2:27: error: Result error type cannot be 'void'\n",
    );

    const reserved_result_enum_command = b.addRunArtifact(executable);
    reserved_result_enum_command.addArgs(&.{ "compile", "Tests/ReservedResultEnum.sx" });
    reserved_result_enum_command.expectExitCode(1);
    reserved_result_enum_command.expectStdErrEqual(
        "Tests/ReservedResultEnum.sx:1:6: error: type name 'Result' is reserved\n",
    );

    const reserved_result_alias_command = b.addRunArtifact(executable);
    reserved_result_alias_command.addArgs(&.{ "compile", "Tests/ReservedResultAlias.sx" });
    reserved_result_alias_command.expectExitCode(1);
    reserved_result_alias_command.expectStdErrEqual(
        "Tests/ReservedResultAlias.sx:5:16: error: name 'Result' is reserved\n",
    );

    const invalid_result_let_independence_command = b.addRunArtifact(executable);
    invalid_result_let_independence_command.addArgs(&.{ "compile", "Tests/InvalidResultLetIndependence.sx" });
    invalid_result_let_independence_command.expectExitCode(1);
    invalid_result_let_independence_command.expectStdErrEqual(
        "Tests/InvalidResultLetIndependence.sx:6:9: error: type 'Result<func(), Failure>' is not an independent value because field 'success[1]' reaches 'func'; use 'var'\n",
    );

    const invalid_result_main_command = b.addRunArtifact(executable);
    invalid_result_main_command.addArgs(&.{ "compile", "Tests/InvalidResultMain.sx" });
    invalid_result_main_command.expectExitCode(1);
    invalid_result_main_command.expectStdErrEqual(
        "Tests/InvalidResultMain.sx:5:6: error: 'main' must return 'void' or 'Result<void, str>'\n",
    );

    const invalid_result_main_success_command = b.addRunArtifact(executable);
    invalid_result_main_success_command.addArgs(&.{ "compile", "Tests/InvalidResultMainSuccess.sx" });
    invalid_result_main_success_command.expectExitCode(1);
    invalid_result_main_success_command.expectStdErrEqual(
        "Tests/InvalidResultMainSuccess.sx:1:6: error: 'main' must return 'void' or 'Result<void, str>'\n",
    );

    const missing_result_main_return_command = b.addRunArtifact(executable);
    missing_result_main_return_command.addArgs(&.{ "compile", "Tests/MissingResultMainReturn.sx" });
    missing_result_main_return_command.expectExitCode(1);
    missing_result_main_return_command.expectStdErrEqual(
        "Tests/MissingResultMainReturn.sx:1:6: error: function 'main' must return 'Result<void, str>' on every path\n",
    );

    const invalid_main_parameter_command = b.addRunArtifact(executable);
    invalid_main_parameter_command.addArgs(&.{ "compile", "Tests/InvalidMainParameter.sx" });
    invalid_main_parameter_command.expectExitCode(1);
    invalid_main_parameter_command.expectStdErrEqual(
        "Tests/InvalidMainParameter.sx:1:6: error: 'main' must have no parameters\n",
    );

    const invalid_result_main_try_error_command = b.addRunArtifact(executable);
    invalid_result_main_try_error_command.addArgs(&.{ "compile", "Tests/InvalidResultMainTryError.sx" });
    invalid_result_main_try_error_command.expectExitCode(1);
    invalid_result_main_try_error_command.expectStdErrEqual(
        "Tests/InvalidResultMainTryError.sx:10:5: error: 'try' cannot propagate error type 'AppError' through Result error type 'str'\n",
    );

    const invalid_try_void_function_command = b.addRunArtifact(executable);
    invalid_try_void_function_command.addArgs(&.{ "compile", "Tests/InvalidTryVoidFunction.sx" });
    invalid_try_void_function_command.expectExitCode(1);
    invalid_try_void_function_command.expectStdErrEqual(
        "Tests/InvalidTryVoidFunction.sx:10:17: error: 'try' requires the current function or lambda to return a Result\n",
    );

    const invalid_try_non_result_return_command = b.addRunArtifact(executable);
    invalid_try_non_result_return_command.addArgs(&.{ "compile", "Tests/InvalidTryNonResultReturn.sx" });
    invalid_try_non_result_return_command.expectExitCode(1);
    invalid_try_non_result_return_command.expectStdErrEqual(
        "Tests/InvalidTryNonResultReturn.sx:10:12: error: 'try' requires the current function or lambda to return a Result\n",
    );

    const invalid_try_operand_command = b.addRunArtifact(executable);
    invalid_try_operand_command.addArgs(&.{ "compile", "Tests/InvalidTryOperand.sx" });
    invalid_try_operand_command.expectExitCode(1);
    invalid_try_operand_command.expectStdErrEqual(
        "Tests/InvalidTryOperand.sx:6:17: error: 'try' requires a Result operand, found 'int'\n",
    );

    const invalid_try_error_type_command = b.addRunArtifact(executable);
    invalid_try_error_type_command.addArgs(&.{ "compile", "Tests/InvalidTryErrorType.sx" });
    invalid_try_error_type_command.expectExitCode(1);
    invalid_try_error_type_command.expectStdErrEqual(
        "Tests/InvalidTryErrorType.sx:14:17: error: 'try' cannot propagate error type 'ReadError' through Result error type 'SaveError'\n",
    );

    const invalid_try_lambda_error_type_command = b.addRunArtifact(executable);
    invalid_try_lambda_error_type_command.addArgs(&.{ "compile", "Tests/InvalidTryLambdaErrorType.sx" });
    invalid_try_lambda_error_type_command.expectExitCode(1);
    invalid_try_lambda_error_type_command.expectStdErrEqual(
        "Tests/InvalidTryLambdaErrorType.sx:15:21: error: 'try' cannot propagate error type 'ReadError' through Result error type 'SaveError'\n",
    );

    const invalid_try_constructor_command = b.addRunArtifact(executable);
    invalid_try_constructor_command.addArgs(&.{ "compile", "Tests/InvalidTryConstructor.sx" });
    invalid_try_constructor_command.expectExitCode(1);
    invalid_try_constructor_command.expectStdErrEqual(
        "Tests/InvalidTryConstructor.sx:13:22: error: 'try' is not available in a constructor\n",
    );

    const invalid_try_drop_command = b.addRunArtifact(executable);
    invalid_try_drop_command.addArgs(&.{ "compile", "Tests/InvalidTryDrop.sx" });
    invalid_try_drop_command.expectExitCode(1);
    invalid_try_drop_command.expectStdErrEqual(
        "Tests/InvalidTryDrop.sx:11:9: error: 'try' is not available in a drop block\n",
    );

    const invalid_try_unique_resource_drop_command = b.addRunArtifact(executable);
    invalid_try_unique_resource_drop_command.addArgs(&.{ "compile", "Tests/InvalidTryUniqueResourceDrop.sx" });
    invalid_try_unique_resource_drop_command.expectExitCode(1);
    invalid_try_unique_resource_drop_command.expectStdErrEqual(
        "Tests/InvalidTryUniqueResourceDrop.sx:11:9: error: 'try' is not available in a drop block\n",
    );

    const invalid_try_named_noncopyable_result_command = b.addRunArtifact(executable);
    invalid_try_named_noncopyable_result_command.addArgs(&.{ "compile", "Tests/InvalidTryNamedNoncopyableResult.sx" });
    invalid_try_named_noncopyable_result_command.expectExitCode(1);
    invalid_try_named_noncopyable_result_command.expectStdErrEqual(
        "Tests/InvalidTryNamedNoncopyableResult.sx:8:17: error: a named noncopyable Result must be consumed with 'try move result'\n",
    );

    const noncopyable_result_command = b.addRunArtifact(executable);
    noncopyable_result_command.addArgs(&.{ "compile", "Tests/NoncopyableResult.sx" });

    const reserved_try_identifier_command = b.addRunArtifact(executable);
    reserved_try_identifier_command.addArgs(&.{ "compile", "Tests/ReservedTryIdentifier.sx" });
    reserved_try_identifier_command.expectExitCode(1);
    reserved_try_identifier_command.expectStdErrEqual(
        "Tests/ReservedTryIdentifier.sx:2:9: error: expected variable name\n",
    );

    const missing_map_error_type_arguments_command = b.addRunArtifact(executable);
    missing_map_error_type_arguments_command.addArgs(&.{ "compile", "Tests/MissingMapErrorTypeArguments.sx" });
    missing_map_error_type_arguments_command.expectExitCode(1);
    missing_map_error_type_arguments_command.expectStdErrEqual(
        "Tests/MissingMapErrorTypeArguments.sx:9:18: error: generic function 'map_error' requires explicit type arguments\n",
    );

    const invalid_map_error_result_type_command = b.addRunArtifact(executable);
    invalid_map_error_result_type_command.addArgs(&.{ "compile", "Tests/InvalidMapErrorResultType.sx" });
    invalid_map_error_result_type_command.expectExitCode(1);
    invalid_map_error_result_type_command.expectStdErrEqual(
        "Tests/InvalidMapErrorResultType.sx:10:18: error: no compatible signature for function 'map_error<int, IOError, AppError>'; visible signatures: map_error<int, IOError, AppError>(Result<int, IOError>, func(IOError) AppError)\n",
    );

    const invalid_map_error_transform_command = b.addRunArtifact(executable);
    invalid_map_error_transform_command.addArgs(&.{ "compile", "Tests/InvalidMapErrorTransform.sx" });
    invalid_map_error_transform_command.expectExitCode(1);
    invalid_map_error_transform_command.expectStdErrEqual(
        "Tests/InvalidMapErrorTransform.sx:9:18: error: no compatible signature for function 'map_error<int, SourceError, TargetError>'; visible signatures: map_error<int, SourceError, TargetError>(Result<int, SourceError>, func(SourceError) TargetError)\n",
    );

    const invalid_map_error_named_noncopyable_command = b.addRunArtifact(executable);
    invalid_map_error_named_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidMapErrorNamedNoncopyable.sx" });
    invalid_map_error_named_noncopyable_command.expectExitCode(1);
    invalid_map_error_named_noncopyable_command.expectStdErrEqual(
        "Tests/InvalidMapErrorNamedNoncopyable.sx:9:9: error: noncopyable value 'Result<Resource, str>' must be passed with 'move'\n",
    );

    const invalid_map_error_void_overload_command = b.addRunArtifact(executable);
    invalid_map_error_void_overload_command.addArgs(&.{ "compile", "Tests/InvalidMapErrorVoidOverload.sx" });
    invalid_map_error_void_overload_command.expectExitCode(1);
    invalid_map_error_void_overload_command.expectStdErrEqual(
        "Tests/InvalidMapErrorVoidOverload.sx:9:28: error: void cannot be used as a type argument\n",
    );

    const invalid_map_error_type_arity_command = b.addRunArtifact(executable);
    invalid_map_error_type_arity_command.addArgs(&.{ "compile", "Tests/InvalidMapErrorTypeArity.sx" });
    invalid_map_error_type_arity_command.expectExitCode(1);
    invalid_map_error_type_arity_command.expectStdErrEqual(
        "Tests/InvalidMapErrorTypeArity.sx:9:18: error: generic function 'map_error' has no overload accepting 1 type arguments\n",
    );

    const reserved_map_error_function_command = b.addRunArtifact(executable);
    reserved_map_error_function_command.addArgs(&.{ "compile", "Tests/ReservedMapErrorFunction.sx" });
    reserved_map_error_function_command.expectExitCode(1);
    reserved_map_error_function_command.expectStdErrEqual(
        "Tests/ReservedMapErrorFunction.sx:1:6: error: name 'map_error' is reserved\n",
    );

    const reserved_map_error_local_command = b.addRunArtifact(executable);
    reserved_map_error_local_command.addArgs(&.{ "compile", "Tests/ReservedMapErrorLocal.sx" });
    reserved_map_error_local_command.expectExitCode(1);
    reserved_map_error_local_command.expectStdErrEqual(
        "Tests/ReservedMapErrorLocal.sx:2:9: error: name 'map_error' is reserved\n",
    );

    const reserved_map_error_module_alias_command = b.addRunArtifact(executable);
    reserved_map_error_module_alias_command.addArgs(&.{ "compile", "Tests/ReservedMapErrorModuleAlias.sx" });
    reserved_map_error_module_alias_command.expectExitCode(1);
    reserved_map_error_module_alias_command.expectStdErrEqual(
        "Tests/ReservedMapErrorModuleAlias.sx:1:16: error: name 'map_error' is reserved\n",
    );

    const missing_generic_function_arguments_command = b.addRunArtifact(executable);
    missing_generic_function_arguments_command.addArgs(&.{ "compile", "Tests/MissingGenericFunctionArguments.sx" });
    missing_generic_function_arguments_command.expectExitCode(1);
    missing_generic_function_arguments_command.expectStdErrEqual(
        "Tests/MissingGenericFunctionArguments.sx:6:11: error: generic function 'identity' requires explicit type arguments\n",
    );

    const unexpected_generic_function_arguments_command = b.addRunArtifact(executable);
    unexpected_generic_function_arguments_command.addArgs(&.{ "compile", "Tests/UnexpectedGenericFunctionArguments.sx" });
    unexpected_generic_function_arguments_command.expectExitCode(1);
    unexpected_generic_function_arguments_command.expectStdErrEqual(
        "Tests/UnexpectedGenericFunctionArguments.sx:6:11: error: function 'identity' does not accept type arguments\n",
    );

    const invalid_generic_function_arity_command = b.addRunArtifact(executable);
    invalid_generic_function_arity_command.addArgs(&.{ "compile", "Tests/InvalidGenericFunctionArity.sx" });
    invalid_generic_function_arity_command.expectExitCode(1);
    invalid_generic_function_arity_command.expectStdErrEqual(
        "Tests/InvalidGenericFunctionArity.sx:7:11: error: generic function 'choose' expects 2 type arguments, found 1\n",
    );

    const invalid_generic_function_specialization_command = b.addRunArtifact(executable);
    invalid_generic_function_specialization_command.addArgs(&.{ "compile", "Tests/InvalidGenericFunctionSpecialization.sx" });
    invalid_generic_function_specialization_command.expectExitCode(1);
    invalid_generic_function_specialization_command.expectStdErrEqual(
        "Tests/InvalidGenericFunctionSpecialization.sx:2:18: error: arithmetic operator requires numeric operands, found 'str' and 'int'\n",
    );

    const recursive_generic_function_expansion_command = b.addRunArtifact(executable);
    recursive_generic_function_expansion_command.addArgs(&.{ "compile", "Tests/RecursiveGenericFunctionExpansion.sx" });
    recursive_generic_function_expansion_command.expectExitCode(1);
    recursive_generic_function_expansion_command.expectStdErrEqual(
        "Tests/RecursiveGenericFunctionExpansion.sx:6:5: error: generic function 'expand' recursively expands with different type arguments\n",
    );

    const missing_type_alias_name_command = b.addRunArtifact(executable);
    missing_type_alias_name_command.addArgs(&.{ "compile", "Tests/MissingTypeAliasName.sx" });
    missing_type_alias_name_command.expectExitCode(1);
    missing_type_alias_name_command.expectStdErrEqual(
        "Tests/MissingTypeAliasName.sx:1:1: error: a type expression after 'use' requires an alias with 'as'\n",
    );

    const unknown_type_alias_target_command = b.addRunArtifact(executable);
    unknown_type_alias_target_command.addArgs(&.{ "compile", "Tests/UnknownTypeAliasTarget.sx" });
    unknown_type_alias_target_command.expectExitCode(1);
    unknown_type_alias_target_command.expectStdErrEqual(
        "Tests/UnknownTypeAliasTarget.sx:1:1: error: unknown type 'Missing'\n",
    );

    const type_alias_collision_command = b.addRunArtifact(executable);
    type_alias_collision_command.addArgs(&.{ "compile", "Tests/TypeAliasCollision.sx" });
    type_alias_collision_command.expectExitCode(1);
    type_alias_collision_command.expectStdErrEqual(
        "Tests/TypeAliasCollision.sx:3:1: error: name 'Values' collides with a module declaration\n",
    );

    const type_alias_as_value_command = b.addRunArtifact(executable);
    type_alias_as_value_command.addArgs(&.{ "compile", "Tests/TypeAliasAsValue.sx" });
    type_alias_as_value_command.expectExitCode(1);
    type_alias_as_value_command.expectStdErrEqual(
        "Tests/TypeAliasAsValue.sx:4:5: error: type alias 'Integers' cannot be used as a function or value\n",
    );

    const type_alias_cycle_command = b.addRunArtifact(executable);
    type_alias_cycle_command.addArgs(&.{ "compile", "Tests/TypeAliasCycle.sx" });
    type_alias_cycle_command.expectExitCode(1);
    type_alias_cycle_command.expectStdErrEqual(
        "Tests/TypeAliasCycle.sx:1:1: error: type alias cycle involving 'Left'\n",
    );

    const invalid_type_alias_arity_command = b.addRunArtifact(executable);
    invalid_type_alias_arity_command.addArgs(&.{ "compile", "Tests/InvalidTypeAliasArity.sx" });
    invalid_type_alias_arity_command.expectExitCode(1);
    invalid_type_alias_arity_command.expectStdErrEqual(
        "Tests/InvalidTypeAliasArity.sx:5:1: error: generic struct 'Box' expects 1 type argument, found 2\n",
    );

    const missing_type_alias_arguments_command = b.addRunArtifact(executable);
    missing_type_alias_arguments_command.addArgs(&.{ "compile", "Tests/MissingTypeAliasArguments.sx" });
    missing_type_alias_arguments_command.expectExitCode(1);
    missing_type_alias_arguments_command.expectStdErrEqual(
        "Tests/MissingTypeAliasArguments.sx:5:1: error: generic struct 'Box' requires 1 type argument\n",
    );

    const legacy_struct_initializer_command = b.addRunArtifact(executable);
    legacy_struct_initializer_command.addArgs(&.{ "compile", "Tests/LegacyStructInitializer.sx" });
    legacy_struct_initializer_command.expectExitCode(1);
    legacy_struct_initializer_command.expectStdErrEqual(
        "Tests/LegacyStructInitializer.sx:4:29: error: structure initializers use 'Type(...)', not 'Type { ... }'\n",
    );

    const positional_struct_initializer_command = b.addRunArtifact(executable);
    positional_struct_initializer_command.addArgs(&.{ "compile", "Tests/PositionalStructInitializer.sx" });
    positional_struct_initializer_command.expectExitCode(1);
    positional_struct_initializer_command.expectStdErrEqual(
        "Tests/PositionalStructInitializer.sx:4:20: error: struct 'Position' requires named fields such as 'field:value'\n",
    );

    const named_function_arguments_command = b.addRunArtifact(executable);
    named_function_arguments_command.addArgs(&.{ "compile", "Tests/NamedFunctionArguments.sx" });
    named_function_arguments_command.expectExitCode(1);
    named_function_arguments_command.expectStdErrEqual(
        "Tests/NamedFunctionArguments.sx:6:17: error: function 'compute' does not accept named arguments; named fields initialize a struct\n",
    );

    const immutable_method_call_command = b.addRunArtifact(executable);
    immutable_method_call_command.addArgs(&.{ "compile", "Tests/ImmutableMethodCall.sx" });
    immutable_method_call_command.expectExitCode(1);
    immutable_method_call_command.expectStdErrEqual(
        "Tests/ImmutableMethodCall.sx:15:13: error: cannot call mutating method 'increment' on immutable value 'counter'\n",
    );

    const untyped_declaration_command = b.addRunArtifact(executable);
    untyped_declaration_command.addArgs(&.{ "compile", "Tests/UntypedDeclaration.sx" });
    untyped_declaration_command.expectExitCode(1);
    untyped_declaration_command.expectStdErrEqual(
        "Tests/UntypedDeclaration.sx:2:9: error: variable declaration requires a type or initializer\n",
    );

    const invalid_field_default_command = b.addRunArtifact(executable);
    invalid_field_default_command.addArgs(&.{ "compile", "Tests/InvalidFieldDefault.sx" });
    invalid_field_default_command.expectExitCode(1);
    invalid_field_default_command.expectStdErrEqual(
        "Tests/InvalidFieldDefault.sx:2:22: error: default field value must be a literal or named initializer of type 'int'\n",
    );

    const invalid_compound_assignment_command = b.addRunArtifact(executable);
    invalid_compound_assignment_command.addArgs(&.{ "compile", "Tests/InvalidCompoundAssignment.sx" });
    invalid_compound_assignment_command.expectExitCode(1);
    invalid_compound_assignment_command.expectStdErrEqual(
        "Tests/InvalidCompoundAssignment.sx:3:5: error: operator '-=' requires a numeric target, found 'str'\n",
    );

    const invalid_float_narrowing_command = b.addRunArtifact(executable);
    invalid_float_narrowing_command.addArgs(&.{ "compile", "Tests/InvalidFloatNarrowing.sx" });
    invalid_float_narrowing_command.expectExitCode(1);
    invalid_float_narrowing_command.expectStdErrEqual(
        "Tests/InvalidFloatNarrowing.sx:2:21: error: expected 'int', found 'float'\n",
    );

    const invalid_numeric_negation_command = b.addRunArtifact(executable);
    invalid_numeric_negation_command.addArgs(&.{ "compile", "Tests/InvalidNumericNegation.sx" });
    invalid_numeric_negation_command.expectExitCode(1);
    invalid_numeric_negation_command.expectStdErrEqual(
        "Tests/InvalidNumericNegation.sx:2:11: error: numeric operator '-' requires an 'int' or 'float' operand, found 'str'\n",
    );

    const invalid_integer_literal_range_command = b.addRunArtifact(executable);
    invalid_integer_literal_range_command.addArgs(&.{ "compile", "Tests/InvalidIntegerLiteralRange.sx" });
    invalid_integer_literal_range_command.expectExitCode(1);
    invalid_integer_literal_range_command.expectStdErrEqual(
        "Tests/InvalidIntegerLiteralRange.sx:2:23: error: integer literal is outside the range of 'uint8'\n",
    );

    const invalid_signed_unsigned_arithmetic_command = b.addRunArtifact(executable);
    invalid_signed_unsigned_arithmetic_command.addArgs(&.{ "compile", "Tests/InvalidSignedUnsignedArithmetic.sx" });
    invalid_signed_unsigned_arithmetic_command.expectExitCode(1);
    invalid_signed_unsigned_arithmetic_command.expectStdErrEqual(
        "Tests/InvalidSignedUnsignedArithmetic.sx:4:18: error: arithmetic operator requires compatible numeric operands, found 'int8' and 'uint8'\n",
    );

    const invalid_remainder_command = b.addRunArtifact(executable);
    invalid_remainder_command.addArgs(&.{ "compile", "Tests/InvalidRemainder.sx" });
    invalid_remainder_command.expectExitCode(1);
    invalid_remainder_command.expectStdErrEqual(
        "Tests/InvalidRemainder.sx:3:17: error: remainder operator requires compatible integer operands, found 'float' and 'int'\n",
    );

    const invalid_bitwise_command = b.addRunArtifact(executable);
    invalid_bitwise_command.addArgs(&.{ "compile", "Tests/InvalidBitwise.sx" });
    invalid_bitwise_command.expectExitCode(1);
    invalid_bitwise_command.expectStdErrEqual(
        "Tests/InvalidBitwise.sx:4:17: error: bitwise operator requires compatible unsigned integer operands, found 'int8' and 'uint8'\n",
    );

    const invalid_shift_command = b.addRunArtifact(executable);
    invalid_shift_command.addArgs(&.{ "compile", "Tests/InvalidShift.sx" });
    invalid_shift_command.expectExitCode(1);
    invalid_shift_command.expectStdErrEqual(
        "Tests/InvalidShift.sx:3:17: error: shift operator requires an unsigned integer value and an integer count, found 'uint8' and 'float'\n",
    );

    const invalid_explicit_conversion_command = b.addRunArtifact(executable);
    invalid_explicit_conversion_command.addArgs(&.{ "compile", "Tests/InvalidExplicitConversion.sx" });
    invalid_explicit_conversion_command.expectExitCode(1);
    invalid_explicit_conversion_command.expectStdErrEqual(
        "Tests/InvalidExplicitConversion.sx:2:22: error: explicit conversion requires numeric source and target types, found 'bool' and 'int'\n",
    );

    const invalid_numeric_prefix_command = b.addRunArtifact(executable);
    invalid_numeric_prefix_command.addArgs(&.{ "compile", "Tests/InvalidNumericPrefix.sx" });
    invalid_numeric_prefix_command.expectExitCode(1);
    invalid_numeric_prefix_command.expectStdErrEqual(
        "Tests/InvalidNumericPrefix.sx:2:17: error: expected digit after numeric base prefix\n",
    );

    const invalid_numeric_separator_command = b.addRunArtifact(executable);
    invalid_numeric_separator_command.addArgs(&.{ "compile", "Tests/InvalidNumericSeparator.sx" });
    invalid_numeric_separator_command.expectExitCode(1);
    invalid_numeric_separator_command.expectStdErrEqual(
        "Tests/InvalidNumericSeparator.sx:2:17: error: numeric separator must appear between digits\n",
    );

    const invalid_numeric_base_digit_command = b.addRunArtifact(executable);
    invalid_numeric_base_digit_command.addArgs(&.{ "compile", "Tests/InvalidNumericBaseDigit.sx" });
    invalid_numeric_base_digit_command.expectExitCode(1);
    invalid_numeric_base_digit_command.expectStdErrEqual(
        "Tests/InvalidNumericBaseDigit.sx:2:17: error: invalid digit in numeric literal\n",
    );

    const invalid_float_literal_range_command = b.addRunArtifact(executable);
    invalid_float_literal_range_command.addArgs(&.{ "compile", "Tests/InvalidFloatLiteralRange.sx" });
    invalid_float_literal_range_command.expectExitCode(1);
    invalid_float_literal_range_command.expectStdErrEqual(
        "Tests/InvalidFloatLiteralRange.sx:2:23: error: float literal is outside the range of 'float'\n",
    );

    const invalid_string_escape_command = b.addRunArtifact(executable);
    invalid_string_escape_command.addArgs(&.{ "compile", "Tests/InvalidStringEscape.sx" });
    invalid_string_escape_command.expectExitCode(1);
    invalid_string_escape_command.expectStdErrEqual(
        "Tests/InvalidStringEscape.sx:2:11: error: invalid escape sequence in string literal\n",
    );

    const invalid_unicode_escape_command = b.addRunArtifact(executable);
    invalid_unicode_escape_command.addArgs(&.{ "compile", "Tests/InvalidUnicodeEscape.sx" });
    invalid_unicode_escape_command.expectExitCode(1);
    invalid_unicode_escape_command.expectStdErrEqual(
        "Tests/InvalidUnicodeEscape.sx:2:11: error: invalid Unicode scalar in string literal\n",
    );

    const invalid_string_length_command = b.addRunArtifact(executable);
    invalid_string_length_command.addArgs(&.{ "compile", "Tests/InvalidStringLength.sx" });
    invalid_string_length_command.expectExitCode(1);
    invalid_string_length_command.expectStdErrEqual(
        "Tests/InvalidStringLength.sx:2:13: error: method call requires a struct, class, or collection value\n",
    );

    const reserved_length_function_command = b.addRunArtifact(executable);
    reserved_length_function_command.addArgs(&.{ "compile", "Tests/ReservedLengthFunction.sx" });

    const invalid_collection_clone_command = b.addRunArtifact(executable);
    invalid_collection_clone_command.addArgs(&.{ "compile", "Tests/InvalidCollectionClone.sx" });
    invalid_collection_clone_command.expectExitCode(1);
    invalid_collection_clone_command.expectStdErrEqual(
        "Tests/InvalidCollectionClone.sx:3:34: error: type 'list' has no method 'clone'\n",
    );

    const invalid_fixed_array_length_command = b.addRunArtifact(executable);
    invalid_fixed_array_length_command.addArgs(&.{ "compile", "Tests/InvalidFixedArrayLength.sx" });
    invalid_fixed_array_length_command.expectExitCode(1);
    invalid_fixed_array_length_command.expectStdErrEqual(
        "Tests/InvalidFixedArrayLength.sx:2:25: error: array literal expects 3 values, found 2\n",
    );

    const invalid_empty_collection_literal_command = b.addRunArtifact(executable);
    invalid_empty_collection_literal_command.addArgs(&.{ "compile", "Tests/InvalidEmptyCollectionLiteral.sx" });
    invalid_empty_collection_literal_command.expectExitCode(1);
    invalid_empty_collection_literal_command.expectStdErrEqual(
        "Tests/InvalidEmptyCollectionLiteral.sx:2:18: error: empty sequence literal requires a collection type\n",
    );

    const invalid_immutable_list_mutation_command = b.addRunArtifact(executable);
    invalid_immutable_list_mutation_command.addArgs(&.{ "compile", "Tests/InvalidImmutableListMutation.sx" });
    invalid_immutable_list_mutation_command.expectExitCode(1);
    invalid_immutable_list_mutation_command.expectStdErrEqual(
        "Tests/InvalidImmutableListMutation.sx:3:12: error: cannot call mutating method 'append' on immutable value 'values'\n",
    );

    const invalid_collection_index_type_command = b.addRunArtifact(executable);
    invalid_collection_index_type_command.addArgs(&.{ "compile", "Tests/InvalidCollectionIndexType.sx" });
    invalid_collection_index_type_command.expectExitCode(1);
    invalid_collection_index_type_command.expectStdErrEqual(
        "Tests/InvalidCollectionIndexType.sx:3:18: error: collection index expects 'int', found 'bool'\n",
    );

    const invalid_fixed_array_append_command = b.addRunArtifact(executable);
    invalid_fixed_array_append_command.addArgs(&.{ "compile", "Tests/InvalidFixedArrayAppend.sx" });
    invalid_fixed_array_append_command.expectExitCode(1);
    invalid_fixed_array_append_command.expectStdErrEqual(
        "Tests/InvalidFixedArrayAppend.sx:3:12: error: method 'append' is not available on 'array'\n",
    );

    const invalid_immutable_element_assignment_command = b.addRunArtifact(executable);
    invalid_immutable_element_assignment_command.addArgs(&.{ "compile", "Tests/InvalidImmutableElementAssignment.sx" });
    invalid_immutable_element_assignment_command.expectExitCode(1);
    invalid_immutable_element_assignment_command.expectStdErrEqual(
        "Tests/InvalidImmutableElementAssignment.sx:3:5: error: cannot assign to immutable variable 'values'\n",
    );

    const break_outside_loop_command = b.addRunArtifact(executable);
    break_outside_loop_command.addArgs(&.{ "compile", "Tests/BreakOutsideLoop.sx" });
    break_outside_loop_command.expectExitCode(1);
    break_outside_loop_command.expectStdErrEqual(
        "Tests/BreakOutsideLoop.sx:2:5: error: 'break' is only available inside a loop\n",
    );

    const continue_outside_loop_command = b.addRunArtifact(executable);
    continue_outside_loop_command.addArgs(&.{ "compile", "Tests/ContinueOutsideLoop.sx" });
    continue_outside_loop_command.expectExitCode(1);
    continue_outside_loop_command.expectStdErrEqual(
        "Tests/ContinueOutsideLoop.sx:2:5: error: 'continue' is only available inside a loop\n",
    );

    const invalid_for_source_command = b.addRunArtifact(executable);
    invalid_for_source_command.addArgs(&.{ "compile", "Tests/InvalidForSource.sx" });
    invalid_for_source_command.expectExitCode(1);
    invalid_for_source_command.expectStdErrEqual(
        "Tests/InvalidForSource.sx:2:23: error: for source must be an array or list\n",
    );

    const missing_for_binding_name_command = b.addRunArtifact(executable);
    missing_for_binding_name_command.addArgs(&.{ "compile", "Tests/MissingForBindingName.sx" });
    missing_for_binding_name_command.expectExitCode(1);
    missing_for_binding_name_command.expectStdErrEqual(
        "Tests/MissingForBindingName.sx:3:10: error: expected iteration variable name\n",
    );

    const invalid_immutable_iteration_alias_command = b.addRunArtifact(executable);
    invalid_immutable_iteration_alias_command.addArgs(&.{ "compile", "Tests/InvalidImmutableIterationAlias.sx" });
    invalid_immutable_iteration_alias_command.expectExitCode(1);
    invalid_immutable_iteration_alias_command.expectStdErrEqual(
        "Tests/InvalidImmutableIterationAlias.sx:4:9: error: cannot assign to immutable control binding 'value'; use 'var' in the header\n",
    );

    const invalid_mutable_iteration_source_command = b.addRunArtifact(executable);
    invalid_mutable_iteration_source_command.addArgs(&.{ "compile", "Tests/InvalidMutableIterationSource.sx" });
    invalid_mutable_iteration_source_command.expectExitCode(1);
    invalid_mutable_iteration_source_command.expectStdErrEqual(
        "Tests/InvalidMutableIterationSource.sx:3:23: error: cannot iterate mutably over immutable variable 'values'\n",
    );

    const invalid_iteration_mutation_command = b.addRunArtifact(executable);
    invalid_iteration_mutation_command.addArgs(&.{ "compile", "Tests/InvalidIterationMutation.sx" });
    invalid_iteration_mutation_command.expectExitCode(1);
    invalid_iteration_mutation_command.expectStdErrEqual(
        "Tests/InvalidIterationMutation.sx:4:16: error: cannot mutate borrowed variable 'values'\n",
    );

    const invalid_algorithms_choose_mutation_command = b.addRunArtifact(executable);
    invalid_algorithms_choose_mutation_command.step.dependOn(b.getInstallStep());
    invalid_algorithms_choose_mutation_command.addArgs(&.{ "compile", "Tests/InvalidAlgorithmsChooseMutation.sx" });
    invalid_algorithms_choose_mutation_command.expectExitCode(1);
    invalid_algorithms_choose_mutation_command.expectStdErrEqual(
        "Tests/InvalidAlgorithmsChooseMutation.sx:9:5: error: cannot mutate borrowed variable 'values'\n",
    );

    const invalid_mutable_iteration_access_command = b.addRunArtifact(executable);
    invalid_mutable_iteration_access_command.addArgs(&.{ "compile", "Tests/InvalidMutableIterationAccess.sx" });
    invalid_mutable_iteration_access_command.expectExitCode(1);
    invalid_mutable_iteration_access_command.expectStdErrEqual(
        "Tests/InvalidMutableIterationAccess.sx:4:15: error: cannot access variable 'values' while it is mutably borrowed\n",
    );

    const invalid_iteration_method_mutation_command = b.addRunArtifact(executable);
    invalid_iteration_method_mutation_command.addArgs(&.{ "compile", "Tests/InvalidIterationMethodMutation.sx" });
    invalid_iteration_method_mutation_command.expectExitCode(1);
    invalid_iteration_method_mutation_command.expectStdErrEqual(
        "Tests/InvalidIterationMethodMutation.sx:10:18: error: cannot mutate 'self' while one of its collections is iterated\n",
    );

    const invalid_iteration_alias_scope_command = b.addRunArtifact(executable);
    invalid_iteration_alias_scope_command.addArgs(&.{ "compile", "Tests/InvalidIterationAliasScope.sx" });
    invalid_iteration_alias_scope_command.expectExitCode(1);
    invalid_iteration_alias_scope_command.expectStdErrEqual(
        "Tests/InvalidIterationAliasScope.sx:6:11: error: unknown variable 'value'\n",
    );

    const invalid_structure_equality_command = b.addRunArtifact(executable);
    invalid_structure_equality_command.addArgs(&.{ "compile", "Tests/InvalidStructureEquality.sx" });
    invalid_structure_equality_command.expectExitCode(1);
    invalid_structure_equality_command.expectStdErrEqual(
        "Tests/InvalidStructureEquality.sx:10:25: error: equality operator requires operands of the same type, found 'Position' and 'Velocity'\n",
    );

    const invalid_target_command = b.addRunArtifact(executable);
    invalid_target_command.addArgs(&.{ "compile", "Smokes/Main.sx", "--target", "definitely-not-a-target" });
    invalid_target_command.expectExitCode(1);
    invalid_target_command.expectStdErrEqual(
        "silex: target 'definitely-not-a-target' is unavailable: UnknownArchitecture\n",
    );

    const unavailable_cpp_target_command = b.addRunArtifact(executable);
    unavailable_cpp_target_command.addArgs(&.{
        "compile",
        "Smokes/Main.sx",
        "--target",
        "x86_64-freestanding-none",
    });
    unavailable_cpp_target_command.expectExitCode(1);
    unavailable_cpp_target_command.expectStdErrEqual(
        "silex: target 'x86_64-freestanding-none' is unavailable: Silex programs require a hosted operating system with a C++ standard library\n",
    );

    const backend_discovered_target_failure_command = b.addRunArtifact(executable);
    backend_discovered_target_failure_command.addArgs(&.{
        "compile",
        "Smokes/Main.sx",
        "--native",
        "Tests/NativeBackend/dependency.json",
        "--target",
        "x86_64-linux-musl",
    });
    backend_discovered_target_failure_command.expectExitCode(1);
    backend_discovered_target_failure_command.expectStdErrMatch(
        "silex: native compilation failed for target 'x86_64-linux-musl'; target support, SDKs, or native sources may be unavailable or incomplete\n",
    );
    backend_discovered_target_failure_command.expectStdErrMatch(b.fmt(
        "silex: backend details: .silex{c}build{c}v46{c}x86_64-linux-musl{c}",
        .{
            std.fs.path.sep,
            std.fs.path.sep,
            std.fs.path.sep,
            std.fs.path.sep,
        },
    ));

    const unsupported_native_target_command = b.addRunArtifact(executable);
    unsupported_native_target_command.addArgs(&.{
        "compile",
        "Smokes/Native/Main.sx",
        "--native",
        "Smokes/Native/dependency.json",
        "--target",
        "riscv64-linux-musl",
    });
    unsupported_native_target_command.expectExitCode(1);
    unsupported_native_target_command.expectStdErrEqual(
        "silex: native dependency 'native-smoke' does not support target 'riscv64-linux-musl'\n",
    );

    const private_module_command = b.addRunArtifact(executable);
    private_module_command.addArgs(&.{ "compile", "Tests/Modules/Private/project.json" });
    private_module_command.expectExitCode(1);
    private_module_command.expectStdErrEqual(
        "Tests/Modules/Private/Main.sx:4:15: error: declaration 'hidden' is private in module 'Lib'\n",
    );

    const module_cycle_command = b.addRunArtifact(executable);
    module_cycle_command.addArgs(&.{ "compile", "Tests/Modules/Cycle/project.json" });
    module_cycle_command.expectExitCode(1);
    module_cycle_command.expectStdErrEqual(
        "Tests/Modules/Cycle/B.sx:1:1: error: module dependency cycle: A -> B -> A\n",
    );

    const missing_module_command = b.addRunArtifact(executable);
    missing_module_command.addArgs(&.{ "compile", "Tests/Modules/Missing/project.json" });
    missing_module_command.expectExitCode(1);
    missing_module_command.expectStdErrEqual(
        "Tests/Modules/Missing/Main.sx:1:1: error: unknown declaration 'Missing'\n",
    );

    const removed_import_command = b.addRunArtifact(executable);
    removed_import_command.addArgs(&.{ "compile", "Tests/RemovedImport.sx" });
    removed_import_command.expectExitCode(1);
    removed_import_command.expectStdErrEqual(
        "Tests/RemovedImport.sx:1:1: error: 'import' was removed; use 'use STD as Standard'\n",
    );

    const module_alias_collision_command = b.addRunArtifact(executable);
    module_alias_collision_command.addArgs(&.{ "compile", "Tests/Modules/AliasCollision/project.json" });
    module_alias_collision_command.expectExitCode(1);
    module_alias_collision_command.expectStdErrEqual(
        "Tests/Modules/AliasCollision/Main.sx:3:1: error: name 'Shared' collides with a module alias\n",
    );

    const multiple_module_providers_command = b.addRunArtifact(executable);
    multiple_module_providers_command.addArgs(&.{ "compile", "Tests/Modules/MultipleProviders/project.json" });
    multiple_module_providers_command.expectExitCode(1);
    multiple_module_providers_command.expectStdErrEqual(
        "silex: namespace 'Lib.Item' has multiple source providers\n",
    );

    const duplicate_source_units_command = b.addRunArtifact(executable);
    duplicate_source_units_command.addArgs(&.{ "compile", "Tests/Modules/DuplicateUnits/project.json" });
    duplicate_source_units_command.expectExitCode(1);
    duplicate_source_units_command.expectStdErrEqual(
        "silex: namespace 'App.Item' has multiple source providers\n",
    );

    const duplicate_namespace_spelling_command = b.addRunArtifact(executable);
    duplicate_namespace_spelling_command.addArgs(&.{ "compile", "Tests/Namespaces/Duplicate/Main.sx" });
    duplicate_namespace_spelling_command.expectExitCode(1);
    duplicate_namespace_spelling_command.expectStdErrMatch(
        "namespace 'Library.Console.Session' has multiple source providers",
    );

    const namespace_declaration_collision_command = b.addRunArtifact(executable);
    namespace_declaration_collision_command.addArgs(&.{ "compile", "Tests/Namespaces/DeclarationCollision/Main.sx" });
    namespace_declaration_collision_command.expectExitCode(1);
    namespace_declaration_collision_command.expectStdErrMatch(
        "namespace 'Library.Child' conflicts with declaration 'Child' in namespace 'Library'",
    );

    const namespace_static_collision_command = b.addRunArtifact(executable);
    namespace_static_collision_command.addArgs(&.{ "compile", "Tests/Namespaces/StaticCollision/Main.sx" });
    namespace_static_collision_command.expectExitCode(1);
    namespace_static_collision_command.expectStdErrMatch(
        "static member 'Child' of principal declaration 'Library' collides with namespace or declaration 'Library.Child'",
    );

    const namespace_enum_collision_command = b.addRunArtifact(executable);
    namespace_enum_collision_command.addArgs(&.{ "compile", "Tests/Namespaces/EnumCollision/Main.sx" });
    namespace_enum_collision_command.expectExitCode(1);
    namespace_enum_collision_command.expectStdErrMatch(
        "static member 'Child' of principal declaration 'Library' collides with namespace or declaration 'Library.Child'",
    );

    const invalid_namespace_stem_command = b.addRunArtifact(executable);
    invalid_namespace_stem_command.addArgs(&.{ "compile", "Tests/Namespaces/InvalidStem/Bad..Name.sx" });
    invalid_namespace_stem_command.expectExitCode(1);
    invalid_namespace_stem_command.expectStdErrMatch(
        "source filename 'Bad..Name.sx' does not form a valid namespace",
    );

    const unknown_module_path_command = b.addRunArtifact(executable);
    unknown_module_path_command.addArgs(&.{ "compile", "Tests/Modules/UnknownPath/project.json" });
    unknown_module_path_command.expectExitCode(1);
    unknown_module_path_command.expectStdErrEqual(
        "Tests/Modules/UnknownPath/Main.sx:4:9: error: module 'Lib' has no public declaration 'Missing'\n",
    );

    const unknown_qualified_descendant_command = b.addRunArtifact(executable);
    unknown_qualified_descendant_command.step.dependOn(b.getInstallStep());
    unknown_qualified_descendant_command.addArgs(&.{ "compile", "Tests/UnknownQualifiedDescendant.sx" });
    unknown_qualified_descendant_command.expectExitCode(1);
    unknown_qualified_descendant_command.expectStdErrEqual(
        "Tests/UnknownQualifiedDescendant.sx:4:29: error: unknown qualified path 'STD.Unknown.Value'\n",
    );

    const public_module_use_command = b.addRunArtifact(executable);
    public_module_use_command.addArgs(&.{ "compile", "Tests/Modules/PublicModuleUse/project.json" });
    public_module_use_command.expectExitCode(1);
    public_module_use_command.expectStdErrEqual(
        "Tests/Modules/PublicModuleUse/Main.sx:1:8: error: module 'Lib.Child' cannot be re-exported with 'public use'\n",
    );

    const local_source_unit_command = b.addRunArtifact(executable);
    local_source_unit_command.addArgs(&.{ "compile", "Tests/LocalModules/SourceUnit/Main.sx" });

    const parent_only_use_command = b.addRunArtifact(executable);
    parent_only_use_command.addArgs(&.{ "run", "Tests/LocalModules/ParentOnly/Main.sx" });
    parent_only_use_command.expectStdOutEqual(hostText(b, "parent only\n"));

    const package_diamond_command = b.addRunArtifact(executable);
    package_diamond_command.addArgs(&.{ "run", "Tests/Packages/Diamond/App/Main.sx" });
    package_diamond_command.expectStdOutEqual(hostText(b, "23\n"));

    const transitive_package_visibility_command = b.addRunArtifact(executable);
    transitive_package_visibility_command.addArgs(&.{ "compile", "Tests/Packages/Visibility/App/Main.sx" });
    transitive_package_visibility_command.expectExitCode(1);
    transitive_package_visibility_command.expectStdErrEqual(
        "Tests/Packages/Visibility/App/Main.sx:1:1: error: package 'application' cannot use transitive package 'Utility' without declaring it directly\n",
    );

    const package_cycle_command = b.addRunArtifact(executable);
    package_cycle_command.addArgs(&.{ "compile", "Tests/Packages/Cycle/App/Main.sx" });
    package_cycle_command.expectExitCode(1);
    package_cycle_command.expectStdErrEqual(
        "silex: package dependency cycle: application -> First -> Second -> First\n",
    );

    const package_name_mismatch_command = b.addRunArtifact(executable);
    package_name_mismatch_command.addArgs(&.{ "compile", "Tests/Packages/NameMismatch/App/Main.sx" });
    package_name_mismatch_command.expectExitCode(1);
    package_name_mismatch_command.expectStdErrMatch("points to package named 'Actual'");

    const package_multiple_providers_command = b.addRunArtifact(executable);
    package_multiple_providers_command.addArgs(&.{ "compile", "Tests/Packages/MultipleProviders/App/Main.sx" });
    package_multiple_providers_command.expectExitCode(1);
    package_multiple_providers_command.expectStdErrMatch("silex: package 'Shared' has multiple providers:");

    const incomplete_package_command = b.addRunArtifact(executable);
    incomplete_package_command.addArgs(&.{ "compile", "Tests/Packages/Incomplete/App/Main.sx" });
    incomplete_package_command.expectExitCode(1);
    incomplete_package_command.expectStdErrMatch("is missing required version");

    const missing_package_path_command = b.addRunArtifact(executable);
    missing_package_path_command.addArgs(&.{ "compile", "Tests/Packages/Missing/App/Main.sx" });
    missing_package_path_command.expectExitCode(1);
    missing_package_path_command.expectStdErrMatch("package path for application -> Missing is unavailable");

    const invalid_package_origin_command = b.addRunArtifact(executable);
    invalid_package_origin_command.addArgs(&.{ "compile", "Tests/Packages/InvalidOrigin/App/Main.sx" });
    invalid_package_origin_command.expectExitCode(1);
    invalid_package_origin_command.expectStdErrEqual(
        "silex: dependency application -> Foundation must contain exactly one 'path' or 'git' origin\n",
    );

    const git_packages_integration_command = b.addRunArtifact(git_packages_integration);
    git_packages_integration_command.has_side_effects = true;
    git_packages_integration_command.step.dependOn(b.getInstallStep());
    git_packages_integration_command.addFileArg(executable.getEmittedBin());
    git_packages_integration_command.addArgs(&.{
        ".zig-cache/git-packages-integration",
        ".zig-cache/git-packages-home",
    });

    const native_object_cache_integration_command = b.addRunArtifact(native_object_cache_integration);
    native_object_cache_integration_command.has_side_effects = true;
    native_object_cache_integration_command.step.dependOn(b.getInstallStep());
    native_object_cache_integration_command.addFileArg(executable.getEmittedBin());
    native_object_cache_integration_command.addArgs(&.{
        ".zig-cache/native-object-cache-integration",
        ".zig-cache/native-object-cache-home",
    });
    native_object_cache_integration_command.addFileArg(b.path("Tests/STDNativeInterface.sx"));
    native_object_cache_integration_command.addFileArg(
        b.path("../Library/STD/@Native/Includes/SilexNative/STD.h"),
    );

    const native_package_diamond_command = b.addRunArtifact(executable);
    native_package_diamond_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    native_package_diamond_command.addArgs(&.{ "run", "Tests/NativePackages/Diamond/App/Main.sx" });
    native_package_diamond_command.expectStdOutEqual(hostText(b, "42\n"));

    const duplicate_native_owner_command = b.addRunArtifact(executable);
    duplicate_native_owner_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    duplicate_native_owner_command.addArgs(&.{ "compile", "Tests/NativePackages/DuplicateOwner/App/Main.sx" });
    duplicate_native_owner_command.expectExitCode(1);
    duplicate_native_owner_command.expectStdErrEqual(
        "silex: native identity 'SDL3' is provided by both application -> Left and application -> Right\n",
    );

    const conflicting_public_defines_command = b.addRunArtifact(executable);
    conflicting_public_defines_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    conflicting_public_defines_command.addArgs(&.{ "compile", "Tests/NativePackages/ConflictingDefines/App/Main.sx" });
    conflicting_public_defines_command.expectExitCode(1);
    conflicting_public_defines_command.expectStdErrEqual(
        "silex: package application -> Consumer requires conflicting public define 'SHARED_MODE': " ++
            "'left' from application -> Consumer -> Left and 'right' from application -> Consumer -> Right\n",
    );

    const private_public_define_conflict_command = b.addRunArtifact(executable);
    private_public_define_conflict_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    private_public_define_conflict_command.addArgs(&.{ "compile", "Tests/NativePackages/PrivateOverride/App/Main.sx" });
    private_public_define_conflict_command.expectExitCode(1);
    private_public_define_conflict_command.expectStdErrEqual(
        "silex: native module 'Consumer' defines 'SHARED_MODE=private' but direct dependency " ++
            "application -> Consumer -> Provider requires 'SHARED_MODE=public'\n",
    );

    const transitive_native_interface_command = b.addRunArtifact(executable);
    transitive_native_interface_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    transitive_native_interface_command.addArgs(&.{ "compile", "Tests/NativePackages/Transitive/App/Main.sx" });
    transitive_native_interface_command.expectExitCode(1);
    transitive_native_interface_command.expectStdErrMatch("silex: native compilation failed for target '");

    const invalid_public_include_path_command = b.addRunArtifact(executable);
    invalid_public_include_path_command.addArgs(&.{ "compile", "Tests/NativePackages/InvalidPublicPath/Module/Main.sx" });
    invalid_public_include_path_command.expectExitCode(1);
    invalid_public_include_path_command.expectStdErrMatch("silex: invalid module manifest for module 'Main'");

    const missing_field_mutability_command = b.addRunArtifact(executable);
    missing_field_mutability_command.addArgs(&.{ "compile", "Tests/MissingFieldMutability.sx" });
    missing_field_mutability_command.expectExitCode(1);
    missing_field_mutability_command.expectStdErrEqual(
        "Tests/MissingFieldMutability.sx:2:5: error: expected 'let' or 'var' before field name\n",
    );

    const invalid_let_field_mutation_command = b.addRunArtifact(executable);
    invalid_let_field_mutation_command.addArgs(&.{ "compile", "Tests/InvalidLetFieldMutation.sx" });
    invalid_let_field_mutation_command.expectExitCode(1);
    invalid_let_field_mutation_command.expectStdErrEqual(
        "Tests/InvalidLetFieldMutation.sx:7:5: error: cannot mutate let field 'x'\n",
    );

    const invalid_nested_let_field_mutation_command = b.addRunArtifact(executable);
    invalid_nested_let_field_mutation_command.addArgs(&.{ "compile", "Tests/InvalidNestedLetFieldMutation.sx" });
    invalid_nested_let_field_mutation_command.expectExitCode(1);
    invalid_nested_let_field_mutation_command.expectStdErrEqual(
        "Tests/InvalidNestedLetFieldMutation.sx:15:19: error: cannot call mutating method 'increment' through let field 'counter'\n",
    );

    const invalid_let_field_double_initialization_command = b.addRunArtifact(executable);
    invalid_let_field_double_initialization_command.addArgs(&.{ "compile", "Tests/InvalidLetFieldDoubleInitialization.sx" });
    invalid_let_field_double_initialization_command.expectExitCode(1);
    invalid_let_field_double_initialization_command.expectStdErrEqual(
        "Tests/InvalidLetFieldDoubleInitialization.sx:6:9: error: field 'id' is initialized more than once\n",
    );

    const invalid_let_field_missing_initialization_command = b.addRunArtifact(executable);
    invalid_let_field_missing_initialization_command.addArgs(&.{ "compile", "Tests/InvalidLetFieldMissingInitialization.sx" });
    invalid_let_field_missing_initialization_command.expectExitCode(1);
    invalid_let_field_missing_initialization_command.expectStdErrEqual(
        "Tests/InvalidLetFieldMissingInitialization.sx:4:12: error: constructor of class 'User' leaves field 'id' without a value\n",
    );

    const invalid_let_field_independence_command = b.addRunArtifact(executable);
    invalid_let_field_independence_command.addArgs(&.{ "compile", "Tests/InvalidLetFieldIndependence.sx" });
    invalid_let_field_independence_command.expectExitCode(1);
    invalid_let_field_independence_command.expectStdErrEqual(
        "Tests/InvalidLetFieldIndependence.sx:4:9: error: type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'\n",
    );

    const invalid_static_self_command = b.addRunArtifact(executable);
    invalid_static_self_command.addArgs(&.{ "compile", "Tests/InvalidStaticSelf.sx" });
    invalid_static_self_command.expectExitCode(1);
    invalid_static_self_command.expectStdErrEqual("Tests/InvalidStaticSelf.sx:3:16: error: 'self' is not available inside a static method\n");

    const invalid_static_super_command = b.addRunArtifact(executable);
    invalid_static_super_command.addArgs(&.{ "compile", "Tests/InvalidStaticSuper.sx" });
    invalid_static_super_command.expectExitCode(1);
    invalid_static_super_command.expectStdErrEqual("Tests/InvalidStaticSuper.sx:9:16: error: 'super' is not available inside a static method\n");

    const invalid_static_override_command = b.addRunArtifact(executable);
    invalid_static_override_command.addArgs(&.{ "compile", "Tests/InvalidStaticOverride.sx" });
    invalid_static_override_command.expectExitCode(1);
    invalid_static_override_command.expectStdErrEqual("Tests/InvalidStaticOverride.sx:2:21: error: a static method cannot use 'override'\n");

    const invalid_static_by_instance_command = b.addRunArtifact(executable);
    invalid_static_by_instance_command.addArgs(&.{ "compile", "Tests/InvalidStaticByInstance.sx" });
    invalid_static_by_instance_command.expectExitCode(1);
    invalid_static_by_instance_command.expectStdErrEqual("Tests/InvalidStaticByInstance.sx:9:13: error: static method 'create' must be called through type 'Factory'\n");

    const invalid_instance_by_type_command = b.addRunArtifact(executable);
    invalid_instance_by_type_command.addArgs(&.{ "compile", "Tests/InvalidInstanceByType.sx" });
    invalid_instance_by_type_command.expectExitCode(1);
    invalid_instance_by_type_command.expectStdErrEqual("Tests/InvalidInstanceByType.sx:8:27: error: instance method 'create' requires a value of type 'Factory'\n");

    const invalid_inherited_static_method_command = b.addRunArtifact(executable);
    invalid_inherited_static_method_command.addArgs(&.{ "compile", "Tests/InvalidInheritedStaticMethod.sx" });
    invalid_inherited_static_method_command.expectExitCode(1);
    invalid_inherited_static_method_command.expectStdErrEqual("Tests/InvalidInheritedStaticMethod.sx:10:23: error: type 'Child' has no static method 'create'\n");

    const invalid_private_static_method_command = b.addRunArtifact(executable);
    invalid_private_static_method_command.addArgs(&.{ "compile", "Tests/InvalidPrivateStaticMethod.sx" });
    invalid_private_static_method_command.expectExitCode(1);
    invalid_private_static_method_command.expectStdErrEqual("Tests/InvalidPrivateStaticMethod.sx:8:27: error: static method 'create' is private in class 'Factory'\n");

    const invalid_static_cascade_command = b.addRunArtifact(executable);
    invalid_static_cascade_command.addArgs(&.{ "compile", "Tests/InvalidStaticCascade.sx" });
    invalid_static_cascade_command.expectExitCode(1);
    invalid_static_cascade_command.expectStdErrEqual("Tests/InvalidStaticCascade.sx:8:35: error: static method 'create' must be called through type 'Client'\n");

    const invalid_static_field_by_instance_command = b.addRunArtifact(executable);
    invalid_static_field_by_instance_command.addArgs(&.{ "compile", "Tests/InvalidStaticFieldByInstance.sx" });
    invalid_static_field_by_instance_command.expectExitCode(1);
    invalid_static_field_by_instance_command.expectStdErrEqual("Tests/InvalidStaticFieldByInstance.sx:7:19: error: static field 'value' must be accessed through type 'Counter'\n");

    const invalid_instance_field_by_type_command = b.addRunArtifact(executable);
    invalid_instance_field_by_type_command.addArgs(&.{ "compile", "Tests/InvalidInstanceFieldByType.sx" });
    invalid_instance_field_by_type_command.expectExitCode(1);
    invalid_instance_field_by_type_command.expectStdErrEqual("Tests/InvalidInstanceFieldByType.sx:6:19: error: instance field 'value' requires a value of type 'Counter'\n");

    const invalid_static_let_mutation_command = b.addRunArtifact(executable);
    invalid_static_let_mutation_command.addArgs(&.{ "compile", "Tests/InvalidStaticLetMutation.sx" });
    invalid_static_let_mutation_command.expectExitCode(1);
    invalid_static_let_mutation_command.expectStdErrEqual("Tests/InvalidStaticLetMutation.sx:6:21: error: cannot mutate through let field 'values'\n");

    const invalid_static_field_without_intrinsic_command = b.addRunArtifact(executable);
    invalid_static_field_without_intrinsic_command.addArgs(&.{ "compile", "Tests/InvalidStaticFieldWithoutIntrinsic.sx" });
    invalid_static_field_without_intrinsic_command.expectExitCode(1);
    invalid_static_field_without_intrinsic_command.expectStdErrEqual("Tests/InvalidStaticFieldWithoutIntrinsic.sx:2:16: error: static field 'callback' of type 'func' has no intrinsic value\n");

    const invalid_static_field_initializer_command = b.addRunArtifact(executable);
    invalid_static_field_initializer_command.addArgs(&.{ "compile", "Tests/InvalidStaticFieldInitializer.sx" });
    invalid_static_field_initializer_command.expectExitCode(1);
    invalid_static_field_initializer_command.expectStdErrEqual("Tests/InvalidStaticFieldInitializer.sx:6:28: error: default field value must be a literal or named initializer of type 'int'\n");

    const invalid_private_static_field_command = b.addRunArtifact(executable);
    invalid_private_static_field_command.addArgs(&.{ "compile", "Tests/InvalidPrivateStaticField.sx" });
    invalid_private_static_field_command.expectExitCode(1);
    invalid_private_static_field_command.expectStdErrEqual("Tests/InvalidPrivateStaticField.sx:6:17: error: static field 'value' is private in class 'State'\n");

    const invalid_inherited_static_field_command = b.addRunArtifact(executable);
    invalid_inherited_static_field_command.addArgs(&.{ "compile", "Tests/InvalidInheritedStaticField.sx" });
    invalid_inherited_static_field_command.expectExitCode(1);
    invalid_inherited_static_field_command.expectStdErrEqual("Tests/InvalidInheritedStaticField.sx:8:17: error: type 'Child' has no static field 'value'\n");

    const iterator_source = b.getInstallPath(.prefix, "lib/silex/STD/Iteration/Iterator.sx");
    const queue_source = b.getInstallPath(.prefix, "lib/silex/STD/Collections/Queue.sx");
    const invalid_queue_noncopyable_command = b.addRunArtifact(executable);
    invalid_queue_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidQueueNonCopyable.sx" });
    invalid_queue_noncopyable_command.expectExitCode(1);
    invalid_queue_noncopyable_command.expectStdErrEqual(b.fmt(
        "{s}:10:28: error: noncopyable value 'optional' must be passed with 'move'\n",
        .{iterator_source},
    ));

    const invalid_queue_storage_command = b.addRunArtifact(executable);
    invalid_queue_storage_command.addArgs(&.{ "compile", "Tests/InvalidQueueStorage.sx" });
    invalid_queue_storage_command.expectExitCode(1);
    invalid_queue_storage_command.expectStdErrEqual(
        "Tests/InvalidQueueStorage.sx:5:11: error: field 'front' is private in struct 'STD.Collections.Queue<int>'\n",
    );

    const invalid_queue_borrow_mutation_command = b.addRunArtifact(executable);
    invalid_queue_borrow_mutation_command.addArgs(&.{ "compile", "Tests/InvalidQueueBorrowMutation.sx" });
    invalid_queue_borrow_mutation_command.expectExitCode(1);
    invalid_queue_borrow_mutation_command.expectStdErrEqual(
        "Tests/InvalidQueueBorrowMutation.sx:11:11: error: cannot mutate borrowed variable 'queue'\n",
    );

    const stack_source = b.getInstallPath(.prefix, "lib/silex/STD/Collections/Stack.sx");
    const invalid_stack_noncopyable_command = b.addRunArtifact(executable);
    invalid_stack_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidStackNonCopyable.sx" });
    invalid_stack_noncopyable_command.expectExitCode(1);
    invalid_stack_noncopyable_command.expectStdErrEqual(b.fmt(
        "{s}:10:28: error: noncopyable value 'optional' must be passed with 'move'\n",
        .{iterator_source},
    ));

    const invalid_stack_storage_command = b.addRunArtifact(executable);
    invalid_stack_storage_command.addArgs(&.{ "compile", "Tests/InvalidStackStorage.sx" });
    invalid_stack_storage_command.expectExitCode(1);
    invalid_stack_storage_command.expectStdErrEqual(
        "Tests/InvalidStackStorage.sx:5:11: error: field 'storage' is private in struct 'STD.Collections.Stack<int>'\n",
    );

    const invalid_stack_borrow_mutation_command = b.addRunArtifact(executable);
    invalid_stack_borrow_mutation_command.addArgs(&.{ "compile", "Tests/InvalidStackBorrowMutation.sx" });
    invalid_stack_borrow_mutation_command.expectExitCode(1);
    invalid_stack_borrow_mutation_command.expectStdErrEqual(
        "Tests/InvalidStackBorrowMutation.sx:11:11: error: cannot mutate borrowed variable 'stack'\n",
    );

    const dictionary_source = b.getInstallPath(.prefix, "lib/silex/STD/Collections/Dictionary.sx");
    const invalid_dictionary_noncopyable_command = b.addRunArtifact(executable);
    invalid_dictionary_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidDictionaryNonCopyable.sx" });
    invalid_dictionary_noncopyable_command.expectExitCode(1);
    invalid_dictionary_noncopyable_command.expectStdErrEqual(b.fmt(
        "{s}:10:28: error: noncopyable value 'optional' must be passed with 'move'\n",
        .{iterator_source},
    ));

    const invalid_dictionary_storage_command = b.addRunArtifact(executable);
    invalid_dictionary_storage_command.addArgs(&.{ "compile", "Tests/InvalidDictionaryStorage.sx" });
    invalid_dictionary_storage_command.expectExitCode(1);
    invalid_dictionary_storage_command.expectStdErrEqual(
        "Tests/InvalidDictionaryStorage.sx:7:18: error: field 'buckets' is private in struct 'STD.Collections.Dictionary<int, int>'\n",
    );

    const invalid_dictionary_borrow_mutation_command = b.addRunArtifact(executable);
    invalid_dictionary_borrow_mutation_command.addArgs(&.{ "compile", "Tests/InvalidDictionaryBorrowMutation.sx" });
    invalid_dictionary_borrow_mutation_command.expectExitCode(1);
    invalid_dictionary_borrow_mutation_command.expectStdErrEqual(
        "Tests/InvalidDictionaryBorrowMutation.sx:13:12: error: cannot mutate borrowed variable 'values'\n",
    );

    const invalid_set_noncopyable_command = b.addRunArtifact(executable);
    invalid_set_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidSetNonCopyable.sx" });
    invalid_set_noncopyable_command.expectExitCode(1);
    invalid_set_noncopyable_command.expectStdErrEqual(b.fmt(
        "{s}:10:28: error: noncopyable value 'optional' must be passed with 'move'\n",
        .{iterator_source},
    ));

    const invalid_set_storage_command = b.addRunArtifact(executable);
    invalid_set_storage_command.addArgs(&.{ "compile", "Tests/InvalidSetStorage.sx" });
    invalid_set_storage_command.expectExitCode(1);
    invalid_set_storage_command.expectStdErrEqual(
        "Tests/InvalidSetStorage.sx:7:18: error: field 'entries' is private in struct 'STD.Collections.Set<int>'\n",
    );

    const invalid_iterator_noncopyable_command = b.addRunArtifact(executable);
    invalid_iterator_noncopyable_command.addArgs(&.{ "compile", "Tests/InvalidIteratorNonCopyable.sx" });
    invalid_iterator_noncopyable_command.expectExitCode(1);
    invalid_iterator_noncopyable_command.expectStdErrEqual(b.fmt(
        "{s}:10:28: error: noncopyable value 'optional' must be passed with 'move'\n",
        .{iterator_source},
    ));

    const invalid_iterator_storage_command = b.addRunArtifact(executable);
    invalid_iterator_storage_command.addArgs(&.{ "compile", "Tests/InvalidIteratorStorage.sx" });
    invalid_iterator_storage_command.expectExitCode(1);
    invalid_iterator_storage_command.expectStdErrEqual(
        "Tests/InvalidIteratorStorage.sx:5:20: error: field 'next_index' is private in struct 'STD.Iteration.Iterator<int>'\n",
    );

    const invalid_iterator_map_callback_command = b.addRunArtifact(executable);
    invalid_iterator_map_callback_command.addArgs(&.{ "compile", "Tests/InvalidIteratorMapCallback.sx" });
    invalid_iterator_map_callback_command.expectExitCode(1);
    invalid_iterator_map_callback_command.expectStdErrEqual(
        "Tests/InvalidIteratorMapCallback.sx:10:18: error: no compatible signature for function 'STD.Algorithms.Iteration.map<int, int>'; visible signatures: map<int, int>(STD.Iteration.Iterator<int>, func(@int) int)\n",
    );

    const test_step = b.step("test", "Run the toolchain tests");
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&test_command.step);
    test_step.dependOn(&semantic_test_command.step);
    test_step.dependOn(&lint_test_command.step);
    test_step.dependOn(&lsp_test_command.step);
    test_step.dependOn(&lsp_protocol_command.step);
    test_step.dependOn(&lsp_canonical_formatting_command.step);
    test_step.dependOn(&lsp_crlf_formatting_command.step);
    test_step.dependOn(&lsp_invalid_formatting_command.step);
    test_step.dependOn(&invalid_queue_noncopyable_command.step);
    test_step.dependOn(&invalid_queue_storage_command.step);
    test_step.dependOn(&invalid_queue_borrow_mutation_command.step);
    test_step.dependOn(&invalid_stack_noncopyable_command.step);
    test_step.dependOn(&invalid_stack_storage_command.step);
    test_step.dependOn(&invalid_stack_borrow_mutation_command.step);
    test_step.dependOn(&invalid_dictionary_noncopyable_command.step);
    test_step.dependOn(&invalid_dictionary_storage_command.step);
    test_step.dependOn(&invalid_dictionary_borrow_mutation_command.step);
    test_step.dependOn(&invalid_set_noncopyable_command.step);
    test_step.dependOn(&invalid_set_storage_command.step);
    test_step.dependOn(&invalid_iterator_noncopyable_command.step);
    test_step.dependOn(&invalid_iterator_storage_command.step);
    test_step.dependOn(&invalid_iterator_map_callback_command.step);
    test_step.dependOn(&lint_protocol_command.step);
    test_step.dependOn(&unicode_lint_protocol_command.step);
    test_step.dependOn(&missing_field_mutability_command.step);
    test_step.dependOn(&invalid_let_field_mutation_command.step);
    test_step.dependOn(&invalid_nested_let_field_mutation_command.step);
    test_step.dependOn(&invalid_let_field_double_initialization_command.step);
    test_step.dependOn(&invalid_let_field_missing_initialization_command.step);
    test_step.dependOn(&invalid_let_field_independence_command.step);
    test_step.dependOn(&invalid_static_self_command.step);
    test_step.dependOn(&invalid_static_super_command.step);
    test_step.dependOn(&invalid_static_override_command.step);
    test_step.dependOn(&invalid_static_by_instance_command.step);
    test_step.dependOn(&invalid_instance_by_type_command.step);
    test_step.dependOn(&invalid_inherited_static_method_command.step);
    test_step.dependOn(&invalid_private_static_method_command.step);
    test_step.dependOn(&invalid_static_cascade_command.step);
    test_step.dependOn(&invalid_static_field_by_instance_command.step);
    test_step.dependOn(&invalid_instance_field_by_type_command.step);
    test_step.dependOn(&invalid_static_let_mutation_command.step);
    test_step.dependOn(&invalid_static_field_without_intrinsic_command.step);
    test_step.dependOn(&invalid_static_field_initializer_command.step);
    test_step.dependOn(&invalid_private_static_field_command.step);
    test_step.dependOn(&invalid_inherited_static_field_command.step);
    test_step.dependOn(&invalid_command.step);
    test_step.dependOn(&missing_module_subcommand_command.step);
    test_step.dependOn(&missing_module_init_path_command.step);
    test_step.dependOn(&invalid_module_init_option_command.step);
    test_step.dependOn(&format_check_command.step);
    test_step.dependOn(&lint_warning_command.step);
    test_step.dependOn(&lint_clean_command.step);
    test_step.dependOn(&lint_invalid_command.step);
    test_step.dependOn(&lint_project_command.step);
    test_step.dependOn(&lint_artifact_check_command.step);
    test_step.dependOn(&immutable_assignment_command.step);
    test_step.dependOn(&invalid_mutable_reference_argument_command.step);
    test_step.dependOn(&missing_mutable_reference_argument_command.step);
    test_step.dependOn(&invalid_local_reference_command.step);
    test_step.dependOn(&invalid_native_function_command.step);
    test_step.dependOn(&legacy_module_manifest_command.step);
    test_step.dependOn(&invalid_native_type_command.step);
    test_step.dependOn(&missing_native_symbol_command.step);
    test_step.dependOn(&native_exception_command.step);
    test_step.dependOn(&duplicate_native_source_command.step);
    test_step.dependOn(&inherited_native_runtime_command.step);
    test_step.dependOn(&premature_native_resource_root_command.step);
    test_step.dependOn(&wrapped_premature_native_resource_root_command.step);
    test_step.dependOn(&escaping_native_resource_dependency_command.step);
    test_step.dependOn(&replaced_native_resource_root_command.step);
    test_step.dependOn(&negative_native_view_command.step);
    test_step.dependOn(&null_native_view_command.step);
    test_step.dependOn(&invalid_reference_type_command.step);
    test_step.dependOn(&invalid_unborrowed_view_command.step);
    test_step.dependOn(&invalid_condition_command.step);
    test_step.dependOn(&isolated_elif_command.step);
    test_step.dependOn(&invalid_alternative_condition_command.step);
    test_step.dependOn(&invalid_else_continuation_command.step);
    test_step.dependOn(&reserved_elif_identifier_command.step);
    test_step.dependOn(&invalid_optional_inference_command.step);
    test_step.dependOn(&invalid_optional_condition_command.step);
    test_step.dependOn(&invalid_conditional_binding_source_command.step);
    test_step.dependOn(&invalid_safe_access_command.step);
    test_step.dependOn(&invalid_safe_mutation_command.step);
    test_step.dependOn(&invalid_optional_demotion_command.step);
    test_step.dependOn(&invalid_null_comparison_command.step);
    test_step.dependOn(&invalid_nested_optional_command.step);
    test_step.dependOn(&invalid_void_optional_command.step);
    test_step.dependOn(&reserved_null_identifier_command.step);
    test_step.dependOn(&ambiguous_null_overload_command.step);
    test_step.dependOn(&invalid_untyped_null_sequence_command.step);
    test_step.dependOn(&invalidated_optional_reduction_command.step);
    test_step.dependOn(&invalidated_optional_alias_reduction_command.step);
    test_step.dependOn(&invalidated_optional_lambda_reduction_command.step);
    test_step.dependOn(&invalid_let_function_command.step);
    test_step.dependOn(&invalid_let_function_field_command.step);
    test_step.dependOn(&invalid_implicit_conditional_function_command.step);
    test_step.dependOn(&invalid_let_function_iteration_command.step);
    test_step.dependOn(&invalid_let_class_command.step);
    test_step.dependOn(&invalid_let_class_container_command.step);
    test_step.dependOn(&invalid_class_reference_command.step);
    test_step.dependOn(&invalid_implicit_class_conditional_command.step);
    test_step.dependOn(&invalid_let_class_iteration_command.step);
    test_step.dependOn(&invalid_class_default_variable_command.step);
    test_step.dependOn(&invalid_missing_class_constructor_command.step);
    test_step.dependOn(&invalid_named_struct_constructor_command.step);
    test_step.dependOn(&invalid_private_struct_constructor_command.step);
    test_step.dependOn(&invalid_missing_struct_constructor_field_command.step);
    test_step.dependOn(&invalid_inheritance_cycle_command.step);
    test_step.dependOn(&unique_resource_initializer_visibility_command.step);
    test_step.dependOn(&unique_resource_field_visibility_command.step);
    test_step.dependOn(&unique_resource_extension_visibility_command.step);
    test_step.dependOn(&extension_visibility_command.step);
    test_step.dependOn(&generic_extension_private_command.step);
    test_step.dependOn(&extension_conflict_command.step);
    test_step.dependOn(&extension_conformance_visibility_command.step);
    test_step.dependOn(&extension_conformance_conflict_command.step);
    test_step.dependOn(&invalid_private_super_constructor_command.step);
    test_step.dependOn(&invalid_class_collection_covariance_command.step);
    test_step.dependOn(&invalid_private_class_field_command.step);
    test_step.dependOn(&invalid_private_class_method_command.step);
    test_step.dependOn(&invalid_sub_class_field_command.step);
    test_step.dependOn(&invalid_private_class_initializer_command.step);
    test_step.dependOn(&invalid_struct_member_visibility_command.step);
    test_step.dependOn(&struct_private_visibility_command.step);
    test_step.dependOn(&invalid_private_struct_initializer_command.step);
    test_step.dependOn(&invalid_private_struct_field_command.step);
    test_step.dependOn(&invalid_private_struct_extension_command.step);
    test_step.dependOn(&invalid_assertion_condition_command.step);
    test_step.dependOn(&invalid_assertion_message_command.step);
    test_step.dependOn(&assertion_failure_command.step);
    test_step.dependOn(&invalid_panic_message_command.step);
    test_step.dependOn(&panic_literal_command.step);
    test_step.dependOn(&panic_computed_command.step);
    test_step.dependOn(&removed_random_next_command.step);
    test_step.dependOn(&invalid_logical_command.step);
    test_step.dependOn(&invalid_while_command.step);
    test_step.dependOn(&missing_separator_command.step);
    test_step.dependOn(&missing_type_command.step);
    test_step.dependOn(&missing_return_command.step);
    test_step.dependOn(&implicit_void_return_value_command.step);
    test_step.dependOn(&invalid_arguments_command.step);
    test_step.dependOn(&duplicate_overload_alias_command.step);
    test_step.dependOn(&duplicate_overload_return_command.step);
    test_step.dependOn(&ambiguous_overload_command.step);
    test_step.dependOn(&module_overload_command.step);
    test_step.dependOn(&unknown_struct_field_command.step);
    test_step.dependOn(&immutable_struct_field_command.step);
    test_step.dependOn(&immutable_cascade_command.step);
    test_step.dependOn(&duplicate_struct_field_command.step);
    test_step.dependOn(&invalid_struct_field_type_command.step);
    test_step.dependOn(&missing_generic_arguments_command.step);
    test_step.dependOn(&unexpected_generic_arguments_command.step);
    test_step.dependOn(&invalid_generic_arity_command.step);
    test_step.dependOn(&invalid_generic_specialization_command.step);
    test_step.dependOn(&recursive_generic_structure_expansion_command.step);
    test_step.dependOn(&missing_generic_enum_arguments_command.step);
    test_step.dependOn(&invalid_generic_enum_arity_command.step);
    test_step.dependOn(&unexpected_generic_enum_arguments_command.step);
    test_step.dependOn(&recursive_generic_enum_expansion_command.step);
    test_step.dependOn(&invalid_generic_enum_independence_command.step);
    test_step.dependOn(&invalid_generic_raw_enum_command.step);
    test_step.dependOn(&invalid_generic_enum_void_argument_command.step);
    test_step.dependOn(&missing_result_arguments_command.step);
    test_step.dependOn(&invalid_result_type_arity_command.step);
    test_step.dependOn(&invalid_result_success_arity_command.step);
    test_step.dependOn(&invalid_void_result_success_argument_command.step);
    test_step.dependOn(&invalid_result_failure_arity_command.step);
    test_step.dependOn(&invalid_implicit_result_conversion_command.step);
    test_step.dependOn(&invalid_implicit_result_error_conversion_command.step);
    test_step.dependOn(&invalid_result_void_error_command.step);
    test_step.dependOn(&reserved_result_enum_command.step);
    test_step.dependOn(&reserved_result_alias_command.step);
    test_step.dependOn(&invalid_result_let_independence_command.step);
    test_step.dependOn(&invalid_result_main_command.step);
    test_step.dependOn(&invalid_result_main_success_command.step);
    test_step.dependOn(&missing_result_main_return_command.step);
    test_step.dependOn(&invalid_main_parameter_command.step);
    test_step.dependOn(&invalid_result_main_try_error_command.step);
    test_step.dependOn(&invalid_try_void_function_command.step);
    test_step.dependOn(&invalid_try_non_result_return_command.step);
    test_step.dependOn(&invalid_try_operand_command.step);
    test_step.dependOn(&invalid_try_error_type_command.step);
    test_step.dependOn(&invalid_try_lambda_error_type_command.step);
    test_step.dependOn(&invalid_try_constructor_command.step);
    test_step.dependOn(&invalid_try_drop_command.step);
    test_step.dependOn(&invalid_try_unique_resource_drop_command.step);
    test_step.dependOn(&invalid_try_named_noncopyable_result_command.step);
    test_step.dependOn(&noncopyable_result_command.step);
    test_step.dependOn(&reserved_try_identifier_command.step);
    test_step.dependOn(&missing_map_error_type_arguments_command.step);
    test_step.dependOn(&invalid_map_error_result_type_command.step);
    test_step.dependOn(&invalid_map_error_transform_command.step);
    test_step.dependOn(&invalid_map_error_named_noncopyable_command.step);
    test_step.dependOn(&invalid_map_error_void_overload_command.step);
    test_step.dependOn(&invalid_map_error_type_arity_command.step);
    test_step.dependOn(&reserved_map_error_function_command.step);
    test_step.dependOn(&reserved_map_error_local_command.step);
    test_step.dependOn(&reserved_map_error_module_alias_command.step);
    test_step.dependOn(&missing_generic_function_arguments_command.step);
    test_step.dependOn(&unexpected_generic_function_arguments_command.step);
    test_step.dependOn(&invalid_generic_function_arity_command.step);
    test_step.dependOn(&invalid_generic_function_specialization_command.step);
    test_step.dependOn(&recursive_generic_function_expansion_command.step);
    test_step.dependOn(&missing_type_alias_name_command.step);
    test_step.dependOn(&unknown_type_alias_target_command.step);
    test_step.dependOn(&type_alias_collision_command.step);
    test_step.dependOn(&type_alias_as_value_command.step);
    test_step.dependOn(&type_alias_cycle_command.step);
    test_step.dependOn(&invalid_type_alias_arity_command.step);
    test_step.dependOn(&missing_type_alias_arguments_command.step);
    test_step.dependOn(&legacy_struct_initializer_command.step);
    test_step.dependOn(&positional_struct_initializer_command.step);
    test_step.dependOn(&named_function_arguments_command.step);
    test_step.dependOn(&immutable_method_call_command.step);
    test_step.dependOn(&untyped_declaration_command.step);
    test_step.dependOn(&invalid_field_default_command.step);
    test_step.dependOn(&invalid_compound_assignment_command.step);
    test_step.dependOn(&invalid_float_narrowing_command.step);
    test_step.dependOn(&invalid_numeric_negation_command.step);
    test_step.dependOn(&invalid_integer_literal_range_command.step);
    test_step.dependOn(&invalid_signed_unsigned_arithmetic_command.step);
    test_step.dependOn(&invalid_remainder_command.step);
    test_step.dependOn(&invalid_bitwise_command.step);
    test_step.dependOn(&invalid_shift_command.step);
    test_step.dependOn(&invalid_explicit_conversion_command.step);
    test_step.dependOn(&invalid_numeric_prefix_command.step);
    test_step.dependOn(&invalid_numeric_separator_command.step);
    test_step.dependOn(&invalid_numeric_base_digit_command.step);
    test_step.dependOn(&invalid_float_literal_range_command.step);
    test_step.dependOn(&invalid_string_escape_command.step);
    test_step.dependOn(&invalid_unicode_escape_command.step);
    test_step.dependOn(&invalid_string_length_command.step);
    test_step.dependOn(&reserved_length_function_command.step);
    test_step.dependOn(&invalid_collection_clone_command.step);
    test_step.dependOn(&invalid_fixed_array_length_command.step);
    test_step.dependOn(&invalid_empty_collection_literal_command.step);
    test_step.dependOn(&invalid_immutable_list_mutation_command.step);
    test_step.dependOn(&invalid_collection_index_type_command.step);
    test_step.dependOn(&invalid_fixed_array_append_command.step);
    test_step.dependOn(&invalid_immutable_element_assignment_command.step);
    test_step.dependOn(&break_outside_loop_command.step);
    test_step.dependOn(&continue_outside_loop_command.step);
    test_step.dependOn(&invalid_for_source_command.step);
    test_step.dependOn(&missing_for_binding_name_command.step);
    test_step.dependOn(&invalid_immutable_iteration_alias_command.step);
    test_step.dependOn(&invalid_mutable_iteration_source_command.step);
    test_step.dependOn(&invalid_iteration_mutation_command.step);
    test_step.dependOn(&invalid_algorithms_choose_mutation_command.step);
    test_step.dependOn(&invalid_mutable_iteration_access_command.step);
    test_step.dependOn(&invalid_iteration_method_mutation_command.step);
    test_step.dependOn(&invalid_iteration_alias_scope_command.step);
    test_step.dependOn(&invalid_structure_equality_command.step);
    test_step.dependOn(&invalid_target_command.step);
    test_step.dependOn(&unavailable_cpp_target_command.step);
    test_step.dependOn(&backend_discovered_target_failure_command.step);
    test_step.dependOn(&unsupported_native_target_command.step);
    test_step.dependOn(&private_module_command.step);
    test_step.dependOn(&module_cycle_command.step);
    test_step.dependOn(&missing_module_command.step);
    test_step.dependOn(&removed_import_command.step);
    test_step.dependOn(&module_alias_collision_command.step);
    test_step.dependOn(&multiple_module_providers_command.step);
    test_step.dependOn(&duplicate_source_units_command.step);
    test_step.dependOn(&duplicate_namespace_spelling_command.step);
    test_step.dependOn(&namespace_declaration_collision_command.step);
    test_step.dependOn(&namespace_static_collision_command.step);
    test_step.dependOn(&namespace_enum_collision_command.step);
    test_step.dependOn(&invalid_namespace_stem_command.step);
    test_step.dependOn(&unknown_module_path_command.step);
    test_step.dependOn(&unknown_qualified_descendant_command.step);
    test_step.dependOn(&public_module_use_command.step);
    test_step.dependOn(&local_source_unit_command.step);
    test_step.dependOn(&parent_only_use_command.step);
    test_step.dependOn(&package_diamond_command.step);
    test_step.dependOn(&transitive_package_visibility_command.step);
    test_step.dependOn(&package_cycle_command.step);
    test_step.dependOn(&package_name_mismatch_command.step);
    test_step.dependOn(&package_multiple_providers_command.step);
    test_step.dependOn(&incomplete_package_command.step);
    test_step.dependOn(&missing_package_path_command.step);
    test_step.dependOn(&invalid_package_origin_command.step);
    test_step.dependOn(&git_packages_integration_command.step);
    test_step.dependOn(&native_object_cache_integration_command.step);
    test_step.dependOn(&native_package_diamond_command.step);
    test_step.dependOn(&duplicate_native_owner_command.step);
    test_step.dependOn(&conflicting_public_defines_command.step);
    test_step.dependOn(&private_public_define_conflict_command.step);
    test_step.dependOn(&transitive_native_interface_command.step);
    test_step.dependOn(&invalid_public_include_path_command.step);
    const system_error_test_command = b.addRunArtifact(system_error_integration);
    test_step.dependOn(&system_error_test_command.step);
    const path_test_command = b.addRunArtifact(path_integration);
    test_step.dependOn(&path_test_command.step);
    const unicode_conformance_command = b.addRunArtifact(unicode_conformance);
    unicode_conformance_command.addFileArg(b.path("Tests/UnicodeData/17.0.0/NormalizationTest.txt"));
    unicode_conformance_command.addFileArg(b.path("../Library/STD/@Native/Unicode/Data/17.0.0/CaseFolding.txt"));
    unicode_conformance_command.addFileArg(b.path("../Library/STD/@Native/Unicode/Data/17.0.0/SpecialCasing.txt"));
    unicode_conformance_command.addFileArg(b.path("Tests/UnicodeData/17.0.0/GraphemeBreakTest.txt"));
    test_step.dependOn(&unicode_conformance_command.step);
    const file_native_test_command = b.addRunArtifact(file_native_integration);
    file_native_test_command.addArg(".zig-cache/file-native-integration.bin");
    test_step.dependOn(&file_native_test_command.step);
    const filesystem_native_test_command = b.addRunArtifact(filesystem_native_integration);
    filesystem_native_test_command.addArg(".zig-cache/filesystem-native-integration");
    test_step.dependOn(&filesystem_native_test_command.step);
    const environment_native_test_command = b.addRunArtifact(environment_native_integration);
    test_step.dependOn(&environment_native_test_command.step);
    const process_native_test_command = b.addRunArtifact(process_native_integration);
    test_step.dependOn(&process_native_test_command.step);
    const tcp_native_test_command = b.addRunArtifact(tcp_native_integration);
    test_step.dependOn(&tcp_native_test_command.step);
    const udp_native_test_command = b.addRunArtifact(udp_native_integration);
    test_step.dependOn(&udp_native_test_command.step);

    // A dependency of `test` is otherwise a sibling of the install step and
    // may start while the distributed library is being replaced.
    const installed_toolchain = b.getInstallStep();
    for (test_step.dependencies.items) |dependency| {
        if (dependency != installed_toolchain) dependency.dependOn(installed_toolchain);
    }

    const smoke_command = b.addRunArtifact(executable);
    smoke_command.step.dependOn(b.getInstallStep());
    smoke_command.addArgs(&.{ "run", "Smokes/Main.sx" });
    smoke_command.expectStdOutEqual(hostText(b, "Hello from Silex smoke test\n50\nlogic works\ntrue\nfalse\n2\n1\n"));

    const control_flow_command = b.addRunArtifact(executable);
    control_flow_command.step.dependOn(&smoke_command.step);
    control_flow_command.addArgs(&.{ "run", "Smokes/ControlFlow.sx" });
    control_flow_command.expectStdOutEqual(hostText(b, "if\nflow\n"));

    const alternative_branches_command = b.addRunArtifact(executable);
    alternative_branches_command.step.dependOn(&control_flow_command.step);
    alternative_branches_command.addArgs(&.{ "run", "Smokes/AlternativeBranches.sx" });
    alternative_branches_command.expectStdOutEqual(hostText(
        b,
        "1\n2\n3\nthird\nelif\nelse if\nnone\none\n2\n4\nnested\ntrivia\n2\n",
    ));

    const optional_values_command = b.addRunArtifact(executable);
    optional_values_command.step.dependOn(&alternative_branches_command.step);
    optional_values_command.addArgs(&.{ "run", "Smokes/OptionalValues.sx" });
    optional_values_command.expectStdOutEqual(hostText(b, "missing\noptionals\n"));

    const enums_command = b.addRunArtifact(executable);
    enums_command.step.dependOn(&optional_values_command.step);
    enums_command.addArgs(&.{ "run", "Smokes/Enums.sx" });
    enums_command.expectStdOutEqual(hostText(b, "waiting\nserver\nwaiting\nserver\nanother connection\nany connection\n2\n2\nsouth\nserver!\n"));

    const independent_let_values_command = b.addRunArtifact(executable);
    independent_let_values_command.step.dependOn(&enums_command.step);
    independent_let_values_command.addArgs(&.{ "run", "Smokes/IndependentLetValues.sx" });
    independent_let_values_command.expectStdOutEqual(hostText(b, "independent let\n"));

    const classes_command = b.addRunArtifact(executable);
    classes_command.step.dependOn(&independent_let_values_command.step);
    classes_command.addArgs(&.{ "run", "Smokes/Classes.sx" });
    classes_command.expectStdOutEqual(hostText(b, "classes\n"));

    const struct_constructors_command = b.addRunArtifact(executable);
    struct_constructors_command.step.dependOn(&classes_command.step);
    struct_constructors_command.addArgs(&.{ "run", "Smokes/StructConstructors.sx" });
    struct_constructors_command.expectStdOutEqual(hostText(b, "owner\nstruct constructors\n"));

    const drop_command = b.addRunArtifact(executable);
    drop_command.step.dependOn(&struct_constructors_command.step);
    drop_command.addArgs(&.{ "run", "Smokes/Drop.sx" });
    drop_command.expectStdOutEqual(hostText(b, "held\nsingle\ncycle\ncycle\nchild\nbase\ndrop\n"));

    const inheritance_command = b.addRunArtifact(executable);
    inheritance_command.step.dependOn(&drop_command.step);
    inheritance_command.addArgs(&.{ "run", "Smokes/Inheritance.sx" });
    inheritance_command.expectStdOutEqual(hostText(b, "inheritance\n"));

    const functions_command = b.addRunArtifact(executable);
    functions_command.step.dependOn(&inheritance_command.step);
    functions_command.addArgs(&.{ "run", "Smokes/Functions.sx" });
    functions_command.expectStdOutEqual(hostText(b, "8\n2\n10\n85\n6\n84\n82\n1\n3\n77\n0\n1\n"));

    const references_command = b.addRunArtifact(executable);
    references_command.step.dependOn(&functions_command.step);
    references_command.addArgs(&.{ "run", "Smokes/References.sx" });
    references_command.expectStdOutEqual(hostText(b, "1\n2\n4\n11\n21\n13\n11\n10\n"));

    const overloads_command = b.addRunArtifact(executable);
    overloads_command.step.dependOn(&references_command.step);
    overloads_command.addArgs(&.{ "run", "Smokes/Overloads.sx" });
    overloads_command.expectStdOutEqual(hostText(b, "7\n8\n2.5\n3\n12\n9\n0\n0\n"));

    const assertions_command = b.addRunArtifact(executable);
    assertions_command.step.dependOn(&overloads_command.step);
    assertions_command.addArgs(&.{ "run", "Smokes/Assertions.sx" });
    assertions_command.expectStdOutEqual(hostText(b, "1\n"));

    const panic_command = b.addRunArtifact(executable);
    panic_command.step.dependOn(&assertions_command.step);
    panic_command.addArgs(&.{ "run", "Smokes/Panic.sx" });
    panic_command.expectExitCode(1);
    panic_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:5: runtime error: smoke panic\n", .{b.pathFromRoot("Smokes/Panic.sx")}),
    ));

    const boolean_condition_command = b.addRunArtifact(executable);
    boolean_condition_command.step.dependOn(&panic_command.step);
    boolean_condition_command.addArgs(&.{ "run", "Smokes/BooleanCondition.sx" });
    boolean_condition_command.expectStdOutEqual(hostText(b, "true branch\n"));

    const compact_command = b.addRunArtifact(executable);
    compact_command.step.dependOn(&boolean_condition_command.step);
    compact_command.addArgs(&.{ "run", "Smokes/Compact.sx" });
    compact_command.expectStdOutEqual(hostText(b, "50\n"));

    const structures_command = b.addRunArtifact(executable);
    structures_command.step.dependOn(&compact_command.step);
    structures_command.addArgs(&.{ "run", "Smokes/Structures.sx" });
    structures_command.expectStdOutEqual(hostText(b, "Ada\n35\n0\n10\n0\n9\n3\n"));

    const generic_structures_command = b.addRunArtifact(executable);
    generic_structures_command.step.dependOn(&structures_command.step);
    generic_structures_command.addArgs(&.{ "run", "Smokes/GenericStructures.sx" });
    generic_structures_command.expectStdOutEqual(hostText(b, "10\n30\nAda\ntrue\n7\nright\ntrue\n0\n3\nGrace\n8\n4\n9\n"));

    const generic_enums_command = b.addRunArtifact(executable);
    generic_enums_command.step.dependOn(&generic_structures_command.step);
    generic_enums_command.addArgs(&.{ "run", "Smokes/GenericEnums/silex.json" });
    generic_enums_command.expectStdOutEqual(hostText(b, "success\ninvalid\ndistinct\n2\ntrue\nconverted\nsuccess\n"));

    const results_command = b.addRunArtifact(executable);
    results_command.step.dependOn(&generic_enums_command.step);
    results_command.addArgs(&.{ "run", "Smokes/Results/silex.json" });
    results_command.expectStdOutEqual(hostText(b, "8081\nbad\nsaved\ndenied\ncallback\n"));

    const try_command = b.addRunArtifact(executable);
    try_command.step.dependOn(&results_command.step);
    try_command.addArgs(&.{ "run", "Smokes/Try/silex.json" });
    try_command.expectStdOutEqual(hostText(b, "42\n42\ndenied\n3\nnested failure\nscope released\ndenied\n43\nouter continues\nlambda failure\nouter continues\nsaved\n"));

    const map_error_command = b.addRunArtifact(executable);
    map_error_command.step.dependOn(&try_command.step);
    map_error_command.addArgs(&.{ "run", "Smokes/MapError/silex.json" });
    map_error_command.expectStdOutEqual(hostText(b, "42\nbad input\ncallback\nbad input\nsaved\ndenied\n"));

    const main_result_success_command = b.addRunArtifact(executable);
    main_result_success_command.step.dependOn(&map_error_command.step);
    main_result_success_command.addArgs(&.{ "run", "Smokes/MainResultSuccess.sx" });
    main_result_success_command.expectExitCode(0);
    main_result_success_command.expectStdOutEqual("");
    main_result_success_command.expectStdErrEqual("");

    const main_result_failure_command = b.addRunArtifact(executable);
    main_result_failure_command.step.dependOn(&main_result_success_command.step);
    main_result_failure_command.addArgs(&.{ "run", "Smokes/MainResultFailure.sx" });
    main_result_failure_command.expectExitCode(1);
    main_result_failure_command.expectStdOutEqual("");
    main_result_failure_command.expectStdErrEqual(hostText(b, "error: could not save\n"));

    const main_result_failure_newline_command = b.addRunArtifact(executable);
    main_result_failure_newline_command.step.dependOn(&main_result_failure_command.step);
    main_result_failure_newline_command.addArgs(&.{ "run", "Smokes/MainResultFailureNewline.sx" });
    main_result_failure_newline_command.expectExitCode(1);
    main_result_failure_newline_command.expectStdOutEqual("");
    main_result_failure_newline_command.expectStdErrEqual(hostText(b, "error: already terminated\n\n"));

    const main_result_try_failure_command = b.addRunArtifact(executable);
    main_result_try_failure_command.step.dependOn(&main_result_failure_newline_command.step);
    main_result_try_failure_command.addArgs(&.{ "run", "Smokes/MainResultTryFailure.sx" });
    main_result_try_failure_command.expectExitCode(1);
    main_result_try_failure_command.expectStdOutEqual("");
    main_result_try_failure_command.expectStdErrEqual(hostText(b, "error: propagated failure\n"));

    const main_result_panic_command = b.addRunArtifact(executable);
    main_result_panic_command.step.dependOn(&main_result_try_failure_command.step);
    main_result_panic_command.addArgs(&.{ "run", "Smokes/MainResultPanic.sx" });
    main_result_panic_command.expectExitCode(1);
    main_result_panic_command.expectStdOutEqual("");
    main_result_panic_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:2:5: runtime error: boundary panic\n", .{b.pathFromRoot("Smokes/MainResultPanic.sx")}),
    ));

    const main_result_assert_command = b.addRunArtifact(executable);
    main_result_assert_command.step.dependOn(&main_result_panic_command.step);
    main_result_assert_command.addArgs(&.{ "run", "Smokes/MainResultAssert.sx" });
    main_result_assert_command.expectExitCode(1);
    main_result_assert_command.expectStdOutEqual("");
    main_result_assert_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:2:5: runtime error: assertion failed: boundary assertion\n", .{b.pathFromRoot("Smokes/MainResultAssert.sx")}),
    ));

    const generic_functions_command = b.addRunArtifact(executable);
    generic_functions_command.step.dependOn(&main_result_assert_command.step);
    generic_functions_command.addArgs(&.{ "run", "Smokes/GenericFunctions.sx" });
    generic_functions_command.expectStdOutEqual(hostText(b, "42\n7\nAda\nGrace\n9\nSilex\n3\n3\n4\n120\nlocal\n11\n5\ngeneric\n"));

    const protocols_command = b.addRunArtifact(executable);
    protocols_command.step.dependOn(&generic_functions_command.step);
    protocols_command.addArgs(&.{ "run", "Smokes/Protocols.sx" });
    protocols_command.expectStdOutEqual(hostText(b, "Ada\nAda\nplayer\ndraw\n"));

    const protocol_values_command = b.addRunArtifact(executable);
    protocol_values_command.step.dependOn(&protocols_command.step);
    protocol_values_command.addArgs(&.{ "run", "Smokes/ProtocolValues.sx" });
    protocol_values_command.expectStdOutEqual("");

    const protocol_modules_command = b.addRunArtifact(executable);
    protocol_modules_command.step.dependOn(&protocol_values_command.step);
    protocol_modules_command.addArgs(&.{ "run", "Smokes/ProtocolModules/silex.json" });
    protocol_modules_command.expectStdOutEqual(hostText(b, "remote\nlocal\n"));

    const extension_modules_command = b.addRunArtifact(executable);
    extension_modules_command.step.dependOn(&protocol_modules_command.step);
    extension_modules_command.addArgs(&.{ "run", "Smokes/ExtensionModules/silex.json" });
    extension_modules_command.expectStdOutEqual("");

    const extension_conformance_modules_command = b.addRunArtifact(executable);
    extension_conformance_modules_command.step.dependOn(&extension_modules_command.step);
    extension_conformance_modules_command.addArgs(&.{ "run", "Smokes/ExtensionConformanceModules/silex.json" });
    extension_conformance_modules_command.expectStdOutEqual("");

    const type_aliases_command = b.addRunArtifact(executable);
    type_aliases_command.step.dependOn(&extension_conformance_modules_command.step);
    type_aliases_command.addArgs(&.{ "run", "Smokes/TypeAliases.sx" });
    type_aliases_command.expectStdOutEqual(hostText(b, "6\n3\nAda\ntrue\n24\n"));

    const defaults_command = b.addRunArtifact(executable);
    defaults_command.step.dependOn(&type_aliases_command.step);
    defaults_command.addArgs(&.{ "run", "Smokes/Defaults.sx" });
    defaults_command.expectStdOutEqual(hostText(b, "Ada\nfalse\n1\n7\n0\n\nBob\ntrue\n4\n5\n"));

    const floats_command = b.addRunArtifact(executable);
    floats_command.step.dependOn(&defaults_command.step);
    floats_command.addArgs(&.{ "run", "Smokes/Floats.sx" });
    floats_command.expectStdOutEqual(hostText(b, "3\n-2.5\n2.5\n2.5\n2\n1.5\ntrue\n2\n"));

    const numeric_types_command = b.addRunArtifact(executable);
    numeric_types_command.step.dependOn(&floats_command.step);
    numeric_types_command.addArgs(&.{ "run", "Smokes/NumericTypes.sx" });
    numeric_types_command.expectStdOutEqual(hostText(b, "-128\n32767\n2147483647\n-9223372036854775808\n255\n65535\n4294967295\n18446744073709551615\n42\n1.5\n2.25\n0\n12\n"));

    const conversions_command = b.addRunArtifact(executable);
    conversions_command.step.dependOn(&numeric_types_command.step);
    conversions_command.addArgs(&.{ "run", "Smokes/Conversions.sx" });
    conversions_command.expectStdOutEqual(hostText(b, "-12\n255\n12\n-128\n1.5\n1.67772e+07\n"));

    const numeric_literals_command = b.addRunArtifact(executable);
    numeric_literals_command.step.dependOn(&conversions_command.step);
    numeric_literals_command.addArgs(&.{ "run", "Smokes/NumericLiterals.sx" });
    numeric_literals_command.expectStdOutEqual(hostText(b, "165\n493\n51966\n1000000\n125\n0.0025\n"));

    const strings_command = b.addRunArtifact(executable);
    strings_command.step.dependOn(&numeric_literals_command.step);
    strings_command.addArgs(&.{ "run", "Smokes/Strings.sx" });
    strings_command.expectStdOutEqual(hostText(b, "Hello, Silex\n\nAé!\n\"\\\n3\n3\ntrue\ntrue\n"));

    const collections_command = b.addRunArtifact(executable);
    collections_command.step.dependOn(&strings_command.step);
    collections_command.addArgs(&.{ "run", "Smokes/Collections.sx" });
    collections_command.expectStdOutEqual(hostText(b, "1\n3\n20\n20\n1\nfalse\n1\n99\n3\n1\n3\n6\n2\n5\ntrue\n15\n15\n10\n30\n20\n40\n50\n40\n40\n500\n2\n3\n40\n600\n40\n700\n40\n800\n0\ntrue\n7\n17\n17\n7\n70\n7\n80\n2\n7\n9\n8\n17\n2\n17\n14\n11\n99\n11\n77\n2\n1\n3\n"));

    const slices_command = b.addRunArtifact(executable);
    slices_command.step.dependOn(&collections_command.step);
    slices_command.addArgs(&.{ "run", "Smokes/Slices.sx" });
    slices_command.expectStdOutEqual(hostText(b, "50\n40\n3\n20\n40\n99\n20\n30\n77\n4\n40\n5\n0\n2\n2\n3\n3\n2\n20\n77\n"));

    const collection_take_last_empty_command = b.addRunArtifact(executable);
    collection_take_last_empty_command.step.dependOn(&slices_command.step);
    collection_take_last_empty_command.addArgs(&.{ "run", "Smokes/CollectionErrors/TakeLastEmpty.sx" });
    collection_take_last_empty_command.expectExitCode(1);
    collection_take_last_empty_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:12: runtime error: collection index -1 is out of bounds for count 0\n", .{
            b.pathFromRoot("Smokes/CollectionErrors/TakeLastEmpty.sx"),
        }),
    ));

    const collection_index_out_of_bounds_command = b.addRunArtifact(executable);
    collection_index_out_of_bounds_command.step.dependOn(&collection_take_last_empty_command.step);
    collection_index_out_of_bounds_command.addArgs(&.{ "run", "Smokes/CollectionErrors/IndexOutOfBounds.sx" });
    collection_index_out_of_bounds_command.expectExitCode(1);
    collection_index_out_of_bounds_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:17: runtime error: collection index 3 is out of bounds for count 3\n", .{
            b.pathFromRoot("Smokes/CollectionErrors/IndexOutOfBounds.sx"),
        }),
    ));

    const collection_negative_index_out_of_bounds_command = b.addRunArtifact(executable);
    collection_negative_index_out_of_bounds_command.step.dependOn(&collection_index_out_of_bounds_command.step);
    collection_negative_index_out_of_bounds_command.addArgs(&.{ "run", "Smokes/CollectionErrors/NegativeIndexOutOfBounds.sx" });
    collection_negative_index_out_of_bounds_command.expectExitCode(1);
    collection_negative_index_out_of_bounds_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:17: runtime error: collection index -4 is out of bounds for count 3\n", .{
            b.pathFromRoot("Smokes/CollectionErrors/NegativeIndexOutOfBounds.sx"),
        }),
    ));

    const iteration_command = b.addRunArtifact(executable);
    iteration_command.step.dependOn(&collection_negative_index_out_of_bounds_command.step);
    iteration_command.addArgs(&.{ "run", "Smokes/Iteration.sx" });
    iteration_command.expectStdOutEqual(hostText(b, "6\n2\n6\n2\n6\n3\n2\n1\n3\n8\n10\n"));

    const shared_collections_command = b.addRunArtifact(executable);
    shared_collections_command.step.dependOn(&iteration_command.step);
    shared_collections_command.addArgs(&.{ "run", "Smokes/SharedCollections.sx" });
    shared_collections_command.expectStdOutEqual("");

    const integer_ranges_command = b.addRunArtifact(executable);
    integer_ranges_command.step.dependOn(&shared_collections_command.step);
    integer_ranges_command.addArgs(&.{ "run", "Smokes/IntegerRanges.sx" });
    integer_ranges_command.expectStdOutEqual(hostText(
        b,
        "0\n1\n2\n3\n2\n1\n0\n1\n2\n3\n2\n1\n1\n2\n2\n3\n4\n0\n1\n2\n3\n12\n100\n101\n102\n",
    ));

    const structure_equality_command = b.addRunArtifact(executable);
    structure_equality_command.step.dependOn(&integer_ranges_command.step);
    structure_equality_command.addArgs(&.{ "run", "Smokes/StructureEquality.sx" });
    structure_equality_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\ntrue\n"));

    const field_mutability_command = b.addRunArtifact(executable);
    field_mutability_command.step.dependOn(&structure_equality_command.step);
    field_mutability_command.addArgs(&.{ "run", "Smokes/FieldMutability.sx" });

    const static_methods_command = b.addRunArtifact(executable);
    static_methods_command.step.dependOn(&field_mutability_command.step);
    static_methods_command.addArgs(&.{ "run", "Smokes/StaticMethods.sx" });

    const static_fields_command = b.addRunArtifact(executable);
    static_fields_command.step.dependOn(&static_methods_command.step);
    static_fields_command.addArgs(&.{ "run", "Smokes/StaticFields.sx" });

    const integer_semantics_output = "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n";
    const integer_semantics_command = b.addRunArtifact(executable);
    integer_semantics_command.step.dependOn(&static_fields_command.step);
    integer_semantics_command.addArgs(&.{ "run", "Smokes/IntegerSemantics.sx" });
    integer_semantics_command.expectStdOutEqual(hostText(b, integer_semantics_output));

    const bitwise_command = b.addRunArtifact(executable);
    bitwise_command.step.dependOn(&integer_semantics_command.step);
    bitwise_command.addArgs(&.{ "run", "Smokes/Bitwise.sx" });
    bitwise_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\ntrue\ntrue\n"));

    const remainder_command = b.addRunArtifact(executable);
    remainder_command.step.dependOn(&bitwise_command.step);
    remainder_command.addArgs(&.{ "run", "Smokes/Remainder.sx" });
    remainder_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n"));

    const emit_integer_semantics = b.addRunArtifact(executable);
    emit_integer_semantics.step.dependOn(&remainder_command.step);
    emit_integer_semantics.addArgs(&.{ "compile", "Smokes/IntegerSemantics.sx", "--emit-cpp" });

    const unoptimized_semantics_path = if (b.graph.host.result.os.tag == .windows)
        ".silex/integer-semantics-o0.exe"
    else
        ".silex/integer-semantics-o0";
    const compile_unoptimized_semantics = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "c++",
        "-O0",
        "-std=c++23",
        ".silex/generated/IntegerSemantics.cpp",
        "-o",
        unoptimized_semantics_path,
    });
    compile_unoptimized_semantics.step.dependOn(&emit_integer_semantics.step);

    const run_unoptimized_semantics = b.addSystemCommand(&.{unoptimized_semantics_path});
    run_unoptimized_semantics.step.dependOn(&compile_unoptimized_semantics.step);
    run_unoptimized_semantics.expectStdOutEqual(hostText(b, integer_semantics_output));

    const integer_overflow_command = b.addRunArtifact(executable);
    integer_overflow_command.step.dependOn(&run_unoptimized_semantics.step);
    integer_overflow_command.addArgs(&.{ "run", "Smokes/IntegerOverflow.sx" });
    integer_overflow_command.expectExitCode(1);
    integer_overflow_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:5: runtime error: uint8 addition overflow: 255 + 1\n", .{
            b.pathFromRoot("Smokes/IntegerOverflow.sx"),
        }),
    ));

    const integer_error_cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "Smokes/IntegerErrors/AddSigned.sx", .message = "3:17: runtime error: int8 addition overflow: 127 + 1" },
        .{ .source = "Smokes/IntegerErrors/AddUnsigned.sx", .message = "3:5: runtime error: uint8 addition overflow: 255 + 1" },
        .{ .source = "Smokes/IntegerErrors/SubtractSigned.sx", .message = "3:5: runtime error: int16 subtraction underflow: -32768 - 1" },
        .{ .source = "Smokes/IntegerErrors/SubtractUnsigned.sx", .message = "3:5: runtime error: uint16 subtraction underflow: 0 - 1" },
        .{ .source = "Smokes/IntegerErrors/MultiplySigned.sx", .message = "3:17: runtime error: int32 multiplication overflow: 2147483647 * 2" },
        .{ .source = "Smokes/IntegerErrors/MultiplyUnsigned.sx", .message = "3:5: runtime error: uint32 multiplication overflow: 4294967295 * 2" },
        .{ .source = "Smokes/IntegerErrors/DivideSigned.sx", .message = "3:5: runtime error: int division overflow: -9223372036854775808 / -1" },
        .{ .source = "Smokes/IntegerErrors/DivideUnsigned.sx", .message = "3:17: runtime error: uint64 division by zero: 1 / 0" },
        .{ .source = "Smokes/IntegerErrors/RemainderSigned.sx", .message = "3:17: runtime error: int division overflow: -9223372036854775808 % -1" },
        .{ .source = "Smokes/IntegerErrors/RemainderUnsigned.sx", .message = "3:17: runtime error: uint64 division by zero: 1 % 0" },
        .{ .source = "Smokes/IntegerErrors/NegateSigned.sx", .message = "3:11: runtime error: int8 negation overflow: -(-128)" },
        .{ .source = "Smokes/IntegerErrors/NegateUnsigned.sx", .message = "3:11: runtime error: uint8 negation underflow: -(1)" },
        .{ .source = "Smokes/IntegerErrors/MethodUnsigned.sx", .message = "5:9: runtime error: uint8 subtraction underflow: 10 - 255" },
        .{ .source = "Smokes/IntegerErrors/ShiftNegative.sx", .message = "3:17: runtime error: uint8 left shift count out of range: -1" },
        .{ .source = "Smokes/IntegerErrors/ShiftTooLarge.sx", .message = "3:17: runtime error: uint8 right shift count out of range: 8" },
    };
    const integer_error_suffix = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    var previous_integer_error_step: *std.Build.Step = &integer_overflow_command.step;
    for (integer_error_cases) |case| {
        const optimized_command = b.addRunArtifact(executable);
        optimized_command.step.dependOn(previous_integer_error_step);
        optimized_command.addArgs(&.{ "run", case.source });
        optimized_command.expectExitCode(1);
        optimized_command.expectStdErrEqual(hostText(
            b,
            b.fmt("{s}:{s}\n", .{ b.pathFromRoot(case.source), case.message }),
        ));

        const emit_command = b.addRunArtifact(executable);
        emit_command.step.dependOn(&optimized_command.step);
        emit_command.addArgs(&.{ "compile", case.source, "--emit-cpp" });

        const program_name = std.fs.path.stem(case.source);
        const generated_path = b.fmt(".silex/generated/{s}.cpp", .{program_name});
        const unoptimized_path = b.fmt(".silex/{s}-o0{s}", .{ program_name, integer_error_suffix });
        const compile_unoptimized = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "c++",
            "-O0",
            "-std=c++23",
            generated_path,
            "-o",
            unoptimized_path,
        });
        compile_unoptimized.step.dependOn(&emit_command.step);

        const unoptimized_command = b.addSystemCommand(&.{unoptimized_path});
        unoptimized_command.step.dependOn(&compile_unoptimized.step);
        unoptimized_command.expectExitCode(1);
        unoptimized_command.expectStdErrEqual(hostText(
            b,
            b.fmt("{s}:{s}\n", .{ b.pathFromRoot(case.source), case.message }),
        ));
        previous_integer_error_step = &unoptimized_command.step;
    }

    const conversion_error_cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "Smokes/ConversionErrors/IntegerRange.sx", .message = "3:17: runtime error: cannot convert 'int' to 'uint8': value 256 is outside the target range" },
        .{ .source = "Smokes/ConversionErrors/FloatRange.sx", .message = "3:17: runtime error: cannot convert 'float' to 'int8': value 128 is not an exactly representable integer" },
        .{ .source = "Smokes/ConversionErrors/Fraction.sx", .message = "3:17: runtime error: cannot convert 'float' to 'int': value 2.5 is not an exactly representable integer" },
        .{ .source = "Smokes/ConversionErrors/Precision.sx", .message = "3:17: runtime error: cannot convert 'int' to 'float': value 16777217 loses precision" },
    };
    for (conversion_error_cases) |case| {
        const command = b.addRunArtifact(executable);
        command.step.dependOn(previous_integer_error_step);
        command.addArgs(&.{ "run", case.source });
        command.expectExitCode(1);
        command.expectStdErrEqual(hostText(
            b,
            b.fmt("{s}:{s}\n", .{ b.pathFromRoot(case.source), case.message }),
        ));
        previous_integer_error_step = &command.step;
    }

    const modules_command = b.addRunArtifact(executable);
    modules_command.step.dependOn(b.getInstallStep());
    modules_command.addArgs(&.{ "run", "Smokes/Modules/silex.json" });
    modules_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\nfalse\n7\n16\n11\n3\ngeneric module\n1\n2\n4\n5\n1\n2\nenum module\n20\nmodules\n"));

    const local_modules_command = b.addRunArtifact(executable);
    local_modules_command.step.dependOn(&modules_command.step);
    local_modules_command.addArgs(&.{ "run", "Smokes/LocalModules/Main.sx" });
    local_modules_command.expectStdOutEqual(hostText(b, "2\n3\n9\n3\n7\n"));

    const source_units_command = b.addRunArtifact(executable);
    source_units_command.step.dependOn(&local_modules_command.step);
    source_units_command.addArgs(&.{ "run", "Smokes/SourceUnits/silex.json" });
    source_units_command.expectStdOutEqual(hostText(b, "42\n"));

    const file_namespaces_command = b.addRunArtifact(executable);
    file_namespaces_command.step.dependOn(&source_units_command.step);
    file_namespaces_command.addArgs(&.{ "run", "Smokes/FileNamespaces/Main.sx" });
    file_namespaces_command.expectStdOutEqual(hostText(b, "42\n"));

    const math_command = b.addRunArtifact(executable);
    math_command.step.dependOn(&file_namespaces_command.step);
    math_command.addArgs(&.{ "run", "Smokes/Math.sx" });
    math_command.expectStdOutEqual(hostText(b, ""));

    const mat3_row_error_command = b.addRunArtifact(executable);
    mat3_row_error_command.step.dependOn(&math_command.step);
    mat3_row_error_command.addArgs(&.{ "run", "Smokes/MathErrors/Mat3Row.sx" });
    mat3_row_error_command.expectExitCode(1);
    mat3_row_error_command.expectStdErrMatch("runtime error: Mat3 row index out of bounds\n");

    const mat4_row_error_command = b.addRunArtifact(executable);
    mat4_row_error_command.step.dependOn(&mat3_row_error_command.step);
    mat4_row_error_command.addArgs(&.{ "run", "Smokes/MathErrors/Mat4Row.sx" });
    mat4_row_error_command.expectExitCode(1);
    mat4_row_error_command.expectStdErrMatch("runtime error: Mat4 row index out of bounds\n");

    const standard_library_output = "1065361344\n1152851127339773951\n508277857751731680\n6637030065269067181\n7345633470618427510\n8792660973527785782\n1082269761\n1152992998833853505\n1954144627577988649\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n1301891922867780472\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n";
    const standard_library_command = b.addRunArtifact(executable);
    standard_library_command.step.dependOn(&mat4_row_error_command.step);
    standard_library_command.addArgs(&.{ "run", "Smokes/StandardLibrary/Main.sx" });
    standard_library_command.expectStdOutEqual(hostText(
        b,
        standard_library_output ++ "true\n",
    ));

    const qualified_parent_alias_command = b.addRunArtifact(executable);
    qualified_parent_alias_command.step.dependOn(&standard_library_command.step);
    qualified_parent_alias_command.addArgs(&.{ "run", "Smokes/QualifiedUses/ParentAlias.sx" });
    qualified_parent_alias_command.expectStdOutEqual(hostText(b, "true\n"));

    const randomizer_source = b.getInstallPath(.prefix, "lib/silex/STD/Randomizer.sx");
    const random_error_cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "Smokes/RandomErrors/IntOrder.sx", .message = "42:13: runtime error: get_int(minimum, maximum) requires minimum < maximum" },
        .{ .source = "Smokes/RandomErrors/IntWidth.sx", .message = "47:17: runtime error: get_int(minimum, maximum) requires an interval width that fits in int" },
        .{ .source = "Smokes/RandomErrors/FloatOrder.sx", .message = "71:13: runtime error: get_float(minimum, maximum) requires minimum < maximum" },
        .{ .source = "Smokes/RandomErrors/FloatFinite.sx", .message = "68:13: runtime error: get_float(minimum, maximum) requires finite bounds" },
        .{ .source = "Smokes/RandomErrors/FloatResolution.sx", .message = "78:13: runtime error: get_float(minimum, maximum) requires a representable value below maximum" },
    };
    var previous_random_error_step: *std.Build.Step = &qualified_parent_alias_command.step;
    for (random_error_cases) |case| {
        const command = b.addRunArtifact(executable);
        command.step.dependOn(previous_random_error_step);
        command.addArgs(&.{ "run", case.source });
        command.expectExitCode(1);
        command.expectStdErrEqual(hostText(
            b,
            b.fmt("{s}:{s}\n", .{ randomizer_source, case.message }),
        ));
        previous_random_error_step = &command.step;
    }

    const standard_library_manifest_command = b.addRunArtifact(executable);
    standard_library_manifest_command.step.dependOn(previous_random_error_step);
    standard_library_manifest_command.addArgs(&.{ "run", "Smokes/StandardLibrary/silex.json" });
    standard_library_manifest_command.expectStdOutEqual(hostText(
        b,
        standard_library_output ++ "true\n",
    ));

    const local_native_runtime_command = b.addRunArtifact(executable);
    local_native_runtime_command.step.dependOn(&standard_library_manifest_command.step);
    local_native_runtime_command.addArgs(&.{ "run", "Smokes/LocalNative/Main.sx" });
    local_native_runtime_command.expectStdOutEqual(hostText(b, "42\n"));

    const local_native_manifest_command = b.addRunArtifact(executable);
    local_native_manifest_command.step.dependOn(&local_native_runtime_command.step);
    local_native_manifest_command.addArgs(&.{ "run", "Smokes/LocalNative/project.json" });
    local_native_manifest_command.expectStdOutEqual(hostText(b, "42\n"));

    const native_interface_command = b.addRunArtifact(executable);
    native_interface_command.step.dependOn(&local_native_manifest_command.step);
    native_interface_command.addArgs(&.{ "run", "Smokes/NativeInterface/Main.sx" });
    native_interface_command.expectStdOutEqual(hostText(b, "42\ntrue\ntrue\ntrue\n"));

    const incompatible_native_interface_command = b.addRunArtifact(executable);
    incompatible_native_interface_command.step.dependOn(&native_interface_command.step);
    incompatible_native_interface_command.addArgs(&.{ "compile", "Tests/NativeInterface/Main.sx" });
    incompatible_native_interface_command.expectExitCode(1);
    incompatible_native_interface_command.expectStdErrMatch(
        "silex: native compilation failed for target '",
    );

    const native_structure_return_command = b.addRunArtifact(executable);
    native_structure_return_command.step.dependOn(&incompatible_native_interface_command.step);
    native_structure_return_command.addArgs(&.{ "run", "Smokes/NativeStructureReturns/Main.sx" });
    native_structure_return_command.expectStdOutEqual(hostText(
        b,
        "1\n2\n-8\n-16\n-32\n8\n16\n32\n64\n1.5\n2.5\ntrue\n",
    ));

    const native_structure_string_command = b.addRunArtifact(executable);
    native_structure_string_command.step.dependOn(&native_structure_return_command.step);
    native_structure_string_command.addArgs(&.{ "run", "Smokes/NativeStructureStrings/Main.sx" });
    native_structure_string_command.expectStdOutEqual(hostText(
        b,
        "événement 🌟 1\névénement 🌟 2\ntrue\ntrue\n",
    ));

    const native_structure_string_negative_length_command = b.addRunArtifact(executable);
    native_structure_string_negative_length_command.step.dependOn(&native_structure_string_command.step);
    native_structure_string_negative_length_command.addArgs(&.{ "run", "Smokes/NativeStructureStrings/NegativeLength.sx" });
    native_structure_string_negative_length_command.expectExitCode(1);
    native_structure_string_negative_length_command.expectStdErrEqual(
        "runtime error: native function 'NativeStructureStrings.native_negative_length' field 'detail' failed: returned a negative length\n",
    );

    const native_structure_string_null_pointer_command = b.addRunArtifact(executable);
    native_structure_string_null_pointer_command.step.dependOn(&native_structure_string_negative_length_command.step);
    native_structure_string_null_pointer_command.addArgs(&.{ "run", "Smokes/NativeStructureStrings/NullPointer.sx" });
    native_structure_string_null_pointer_command.expectExitCode(1);
    native_structure_string_null_pointer_command.expectStdErrEqual(
        "runtime error: native function 'NativeStructureStrings.native_null_with_positive_length' field 'detail' failed: returned a null pointer with a positive length\n",
    );

    const native_structure_string_invalid_utf8_command = b.addRunArtifact(executable);
    native_structure_string_invalid_utf8_command.step.dependOn(&native_structure_string_null_pointer_command.step);
    native_structure_string_invalid_utf8_command.addArgs(&.{ "run", "Smokes/NativeStructureStrings/InvalidUtf8.sx" });
    native_structure_string_invalid_utf8_command.expectExitCode(1);
    native_structure_string_invalid_utf8_command.expectStdErrEqual(
        "runtime error: native function 'NativeStructureStrings.native_invalid_utf8' field 'detail' failed: returned invalid UTF-8\n",
    );

    const native_optional_return_command = b.addRunArtifact(executable);
    native_optional_return_command.step.dependOn(&native_structure_string_invalid_utf8_command.step);
    native_optional_return_command.addArgs(&.{ "run", "Smokes/NativeOptionalReturns/Main.sx" });
    native_optional_return_command.expectStdOutEqual(hostText(b, "événement 1\névénement 3\n"));

    const native_optional_absent_text_buffer_command = b.addRunArtifact(executable);
    native_optional_absent_text_buffer_command.step.dependOn(&native_optional_return_command.step);
    native_optional_absent_text_buffer_command.addArgs(&.{ "run", "Smokes/NativeOptionalReturns/AbsentTextBuffer.sx" });
    native_optional_absent_text_buffer_command.expectExitCode(1);
    native_optional_absent_text_buffer_command.expectStdErrEqual(
        "runtime error: native function 'NativeOptionalReturns.native_absent_text_with_buffer' failed: returned an owned buffer while reporting absence\n",
    );

    const native_optional_absent_event_buffer_command = b.addRunArtifact(executable);
    native_optional_absent_event_buffer_command.step.dependOn(&native_optional_absent_text_buffer_command.step);
    native_optional_absent_event_buffer_command.addArgs(&.{ "run", "Smokes/NativeOptionalReturns/AbsentEventBuffer.sx" });
    native_optional_absent_event_buffer_command.expectExitCode(1);
    native_optional_absent_event_buffer_command.expectStdErrEqual(
        "runtime error: native function 'NativeOptionalReturns.native_absent_event_with_buffer' field 'text' failed: returned an owned buffer while reporting absence\n",
    );

    const native_structure_parameter_command = b.addRunArtifact(executable);
    native_structure_parameter_command.step.dependOn(&native_optional_absent_event_buffer_command.step);
    native_structure_parameter_command.addArgs(&.{ "run", "Smokes/NativeStructureParameters/Main.sx" });
    native_structure_parameter_command.expectStdOutEqual(hostText(b, "true\n"));

    const native_structure_string_parameter_command = b.addRunArtifact(executable);
    native_structure_string_parameter_command.step.dependOn(&native_structure_parameter_command.step);
    native_structure_string_parameter_command.addArgs(&.{ "run", "Smokes/NativeStructureStringParameters/Main.sx" });
    native_structure_string_parameter_command.expectStdOutEqual(hostText(b, "true\nsecond 🌍 #2\n"));

    const native_result_command = b.addRunArtifact(executable);
    native_result_command.step.dependOn(&native_structure_string_parameter_command.step);
    native_result_command.addArgs(&.{ "run", "Smokes/NativeResults/Main.sx" });
    native_result_command.expectStdOutEqual(hostText(
        b,
        "42\nété/🌟\nmissing:été/🌟\nmissing:try\nsaved\ndenied\n17\n-1\n",
    ));

    const native_result_invalid_tag_command = b.addRunArtifact(executable);
    native_result_invalid_tag_command.step.dependOn(&native_result_command.step);
    native_result_invalid_tag_command.addArgs(&.{ "run", "Smokes/NativeResults/InvalidTag.sx" });
    native_result_invalid_tag_command.expectExitCode(1);
    native_result_invalid_tag_command.expectStdErrEqual(
        "runtime error: native function 'NativeResults.native_invalid_tag' failed: returned an unknown Result tag\n",
    );

    const native_result_inactive_owned_command = b.addRunArtifact(executable);
    native_result_inactive_owned_command.step.dependOn(&native_result_invalid_tag_command.step);
    native_result_inactive_owned_command.addArgs(&.{ "run", "Smokes/NativeResults/InactiveOwned.sx" });
    native_result_inactive_owned_command.expectExitCode(1);
    native_result_inactive_owned_command.expectStdErrEqual(
        "runtime error: native function 'NativeResults.native_inactive_owned' failed: returned an owned buffer in the inactive failure branch\n",
    );

    const native_result_invalid_utf8_command = b.addRunArtifact(executable);
    native_result_invalid_utf8_command.step.dependOn(&native_result_inactive_owned_command.step);
    native_result_invalid_utf8_command.addArgs(&.{ "run", "Smokes/NativeResults/InvalidUtf8.sx" });
    native_result_invalid_utf8_command.expectExitCode(1);
    native_result_invalid_utf8_command.expectStdErrEqual(
        "runtime error: native function 'NativeResults.native_invalid_utf8' failed: Result failure returned invalid UTF-8\n",
    );

    const native_byte_view_command = b.addRunArtifact(executable);
    native_byte_view_command.step.dependOn(&native_result_invalid_utf8_command.step);
    native_byte_view_command.addArgs(&.{ "run", "Smokes/NativeByteViews/Main.sx" });
    native_byte_view_command.expectStdOutEqual(hostText(b, "272\n0\n272\ntrue\n130560\ntrue\n"));

    const native_byte_buffer_command = b.addRunArtifact(executable);
    native_byte_buffer_command.step.dependOn(&native_byte_view_command.step);
    native_byte_buffer_command.addArgs(&.{ "run", "Smokes/NativeByteBuffers/Main.sx" });
    native_byte_buffer_command.expectStdOutEqual(hostText(b, "native byte buffers ok\n"));

    const native_byte_buffer_negative_length_command = b.addRunArtifact(executable);
    native_byte_buffer_negative_length_command.step.dependOn(&native_byte_buffer_command.step);
    native_byte_buffer_negative_length_command.addArgs(&.{ "run", "Smokes/NativeByteBuffers/NegativeLength.sx" });
    native_byte_buffer_negative_length_command.expectExitCode(1);
    native_byte_buffer_negative_length_command.expectStdErrEqual(
        "runtime error: native function 'NativeByteBuffers.native_negative_length' failed: returned a negative length\n",
    );

    const native_byte_buffer_null_pointer_command = b.addRunArtifact(executable);
    native_byte_buffer_null_pointer_command.step.dependOn(&native_byte_buffer_negative_length_command.step);
    native_byte_buffer_null_pointer_command.addArgs(&.{ "run", "Smokes/NativeByteBuffers/NullPointer.sx" });
    native_byte_buffer_null_pointer_command.expectExitCode(1);
    native_byte_buffer_null_pointer_command.expectStdErrEqual(
        "runtime error: native function 'NativeByteBuffers.native_null_with_positive_length' failed: returned a null pointer with a positive length\n",
    );

    const native_callback_command = b.addRunArtifact(executable);
    native_callback_command.step.dependOn(&native_byte_buffer_null_pointer_command.step);
    native_callback_command.addArgs(&.{ "run", "Smokes/NativeCallbacks/Main.sx" });
    native_callback_command.expectStdOutEqual(hostText(b, "native callbacks ok\n"));

    const native_deferred_callback_command = b.addRunArtifact(executable);
    native_deferred_callback_command.step.dependOn(&native_callback_command.step);
    native_deferred_callback_command.addArgs(&.{ "run", "Smokes/NativeDeferredCallbacks/Main.sx" });
    native_deferred_callback_command.expectStdOutEqual(hostText(b, "native deferred callbacks ok\n"));

    const null_deferred_callback_command = b.addRunArtifact(executable);
    null_deferred_callback_command.step.dependOn(&native_deferred_callback_command.step);
    null_deferred_callback_command.addArgs(&.{ "run", "Smokes/NativeDeferredCallbacks/NullReturn.sx" });
    null_deferred_callback_command.expectExitCode(1);
    null_deferred_callback_command.expectStdOutEqual(hostText(b, "null deferred cleanup 0 0 0\n"));
    null_deferred_callback_command.expectStdErrEqual("runtime error: native function 'NativeDeferredCallbacks.start_null_watch' failed: returned a null native resource\n");

    const native_string_command = b.addRunArtifact(executable);
    native_string_command.step.dependOn(&null_deferred_callback_command.step);
    native_string_command.addArgs(&.{ "run", "Smokes/NativeStrings/Main.sx" });
    native_string_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\ntrue\ntrue\ntrue\n"));

    const native_string_negative_length_command = b.addRunArtifact(executable);
    native_string_negative_length_command.step.dependOn(&native_string_command.step);
    native_string_negative_length_command.addArgs(&.{ "run", "Smokes/NativeStrings/NegativeLength.sx" });
    native_string_negative_length_command.expectExitCode(1);
    native_string_negative_length_command.expectStdErrEqual(
        "runtime error: native function 'NativeStrings.native_negative_length' failed: returned a negative length\n",
    );

    const native_string_null_pointer_command = b.addRunArtifact(executable);
    native_string_null_pointer_command.step.dependOn(&native_string_negative_length_command.step);
    native_string_null_pointer_command.addArgs(&.{ "run", "Smokes/NativeStrings/NullPointer.sx" });
    native_string_null_pointer_command.expectExitCode(1);
    native_string_null_pointer_command.expectStdErrEqual(
        "runtime error: native function 'NativeStrings.native_null_with_positive_length' failed: returned a null pointer with a positive length\n",
    );

    const native_string_invalid_utf8_command = b.addRunArtifact(executable);
    native_string_invalid_utf8_command.step.dependOn(&native_string_null_pointer_command.step);
    native_string_invalid_utf8_command.addArgs(&.{ "run", "Smokes/NativeStrings/InvalidUtf8.sx" });
    native_string_invalid_utf8_command.expectExitCode(1);
    native_string_invalid_utf8_command.expectStdErrEqual(
        "runtime error: native function 'NativeStrings.native_invalid_utf8' failed: returned invalid UTF-8\n",
    );

    const console_smoke_command = b.addRunArtifact(executable);
    console_smoke_command.step.dependOn(&native_string_invalid_utf8_command.step);
    console_smoke_command.addArgs(&.{ "run", "Smokes/Console/Main.sx" });
    console_smoke_command.expectStdOutEqual(hostText(b, "write: line\n\nfalse\ntrue\n"));
    console_smoke_command.expectStdErrEqual(hostText(b, "error: line\n"));

    const isolated_std_smoke_command = b.addRunArtifact(executable);
    isolated_std_smoke_command.step.dependOn(&console_smoke_command.step);
    isolated_std_smoke_command.addArgs(&.{ "run", "Smokes/IsolatedSTD/Main.sx" });
    isolated_std_smoke_command.expectStdOutEqual(hostText(b, "true\n"));

    const isolated_time_smoke_command = b.addRunArtifact(executable);
    isolated_time_smoke_command.step.dependOn(&isolated_std_smoke_command.step);
    isolated_time_smoke_command.addArgs(&.{ "run", "Smokes/IsolatedTime/Main.sx" });
    isolated_time_smoke_command.expectStdOutEqual(hostText(b, "true\n"));

    const isolated_console_smoke_command = b.addRunArtifact(executable);
    isolated_console_smoke_command.step.dependOn(&isolated_time_smoke_command.step);
    isolated_console_smoke_command.addArgs(&.{ "run", "Smokes/IsolatedConsole/Main.sx" });
    isolated_console_smoke_command.expectStdOutEqual(hostText(b, "false\n"));

    const console_negative_coordinates_command = b.addRunArtifact(executable);
    console_negative_coordinates_command.step.dependOn(&isolated_console_smoke_command.step);
    console_negative_coordinates_command.addArgs(&.{ "run", "Smokes/Console/NegativeCoordinates.sx" });
    console_negative_coordinates_command.expectExitCode(1);
    console_negative_coordinates_command.expectStdErrMatch("runtime error: Console.move_cursor requires non-negative coordinates\n");

    const console_session_compile_command = b.addRunArtifact(executable);
    console_session_compile_command.step.dependOn(&console_negative_coordinates_command.step);
    console_session_compile_command.addArgs(&.{
        "compile",
        "Smokes/ConsoleSession/Main.sx",
        "-o",
        ".silex/console-session-smoke-bin",
    });

    const console_session_command = b.addRunArtifact(console_session_integration);
    console_session_command.step.dependOn(&console_session_compile_command.step);
    console_session_command.addArg(".silex/console-session-smoke-bin");

    const console_session_noninteractive_command = b.addRunArtifact(executable);
    console_session_noninteractive_command.step.dependOn(&console_session_command.step);
    console_session_noninteractive_command.addArgs(&.{
        "run",
        "Smokes/ConsoleSession/NonInteractive.sx",
    });
    console_session_noninteractive_command.expectExitCode(1);
    console_session_noninteractive_command.expectStdErrEqual(
        "runtime error: native function 'STD.Console.Session.native_session_create' failed: " ++
            "Console.Session.create failed: standard input and output must be interactive\n",
    );

    const portable_distributed_native_target_command = b.addRunArtifact(executable);
    portable_distributed_native_target_command.step.dependOn(&console_session_noninteractive_command.step);
    portable_distributed_native_target_command.addArgs(&.{
        "compile",
        "Smokes/IsolatedSTD/Main.sx",
        "--target",
        "riscv64-linux-musl",
        "-o",
        ".silex/portable-native-target/STD-riscv64-linux",
    });

    const distributed_module_collision_command = b.addRunArtifact(executable);
    distributed_module_collision_command.step.dependOn(&portable_distributed_native_target_command.step);
    distributed_module_collision_command.addArgs(&.{ "compile", "Tests/DistributedModules/Collision/Main.sx" });
    distributed_module_collision_command.expectExitCode(1);
    distributed_module_collision_command.expectStdErrEqual(
        "Tests/DistributedModules/Collision/Main.sx:1:1: error: module 'STD' has multiple providers\n",
    );

    const native_source_command = b.addRunArtifact(executable);
    native_source_command.step.dependOn(&distributed_module_collision_command.step);
    native_source_command.addArgs(&.{
        "run",
        "Smokes/Native/Main.sx",
        "--native",
        "Smokes/Native/dependency.json",
    });
    native_source_command.expectStdOutEqual(hostText(b, "Native wrapper initialized\nSilex with native source\n"));

    const module_init_smoke_root = ".zig-cache/module-init-smoke";
    const module_init_smoke_directory = ".zig-cache/module-init-smoke/Answer";
    const clean_module_init_smoke_command = b.addRunArtifact(module_init_smoke_setup);
    clean_module_init_smoke_command.has_side_effects = true;
    clean_module_init_smoke_command.step.dependOn(&native_source_command.step);
    clean_module_init_smoke_command.addArgs(&.{ "clean", module_init_smoke_root });

    const initialize_native_module_command = b.addRunArtifact(executable);
    initialize_native_module_command.has_side_effects = true;
    initialize_native_module_command.step.dependOn(&clean_module_init_smoke_command.step);
    initialize_native_module_command.addArgs(&.{ "module", "init", module_init_smoke_directory, "--native" });
    initialize_native_module_command.expectStdErrEqual(
        "Created native module manifest: .zig-cache/module-init-smoke/Answer/@Module.json\n" ++
            "Created native source: .zig-cache/module-init-smoke/Answer/@Native/Module.cpp\n",
    );

    const populate_module_init_smoke_command = b.addRunArtifact(module_init_smoke_setup);
    populate_module_init_smoke_command.has_side_effects = true;
    populate_module_init_smoke_command.step.dependOn(&initialize_native_module_command.step);
    populate_module_init_smoke_command.addArgs(&.{ "populate", module_init_smoke_root });

    const module_init_smoke_command = b.addRunArtifact(executable);
    module_init_smoke_command.has_side_effects = true;
    module_init_smoke_command.step.dependOn(&populate_module_init_smoke_command.step);
    module_init_smoke_command.addArgs(&.{ "run", ".zig-cache/module-init-smoke/Main.sx" });
    module_init_smoke_command.expectStdOutEqual(hostText(b, "42\n"));

    const local_package_smoke_command = b.addRunArtifact(executable);
    local_package_smoke_command.step.dependOn(&module_init_smoke_command.step);
    local_package_smoke_command.addArgs(&.{ "run", "Smokes/Packages/App/Main.sx" });
    local_package_smoke_command.expectStdOutEqual(hostText(b, "43\n"));

    const package_project_manifest_smoke_command = b.addRunArtifact(executable);
    package_project_manifest_smoke_command.step.dependOn(&local_package_smoke_command.step);
    package_project_manifest_smoke_command.addArgs(&.{ "run", "Smokes/Packages/App/project.json" });
    package_project_manifest_smoke_command.expectStdOutEqual(hostText(b, "43\n"));

    const native_package_smoke_command = b.addRunArtifact(executable);
    native_package_smoke_command.setEnvironmentVariable("SILEX_HOME", ".zig-cache/native-package-test-home/.silex");
    native_package_smoke_command.step.dependOn(&package_project_manifest_smoke_command.step);
    native_package_smoke_command.addArgs(&.{ "run", "Smokes/NativePackages/App/Main.sx" });
    native_package_smoke_command.expectStdOutEqual(hostText(b, "42\n"));

    const unique_resources_smoke_command = b.addRunArtifact(executable);
    unique_resources_smoke_command.step.dependOn(&native_package_smoke_command.step);
    unique_resources_smoke_command.addArgs(&.{ "run", "Smokes/UniqueResources/silex.json" });
    unique_resources_smoke_command.expectStdOutEqual(hostText(
        b,
        "open 1\n" ++
            "1\n" ++
            "close 1\n" ++
            "lexical\n" ++
            "open 10\n" ++
            "10\n" ++
            "open 11\n" ++
            "11\n" ++
            "close 11\n" ++
            "after inner\n" ++
            "close 10\n" ++
            "open 20\n" ++
            "return\n" ++
            "20\n" ++
            "close 20\n" ++
            "open 31\n" ++
            "continue\n" ++
            "31\n" ++
            "close 31\n" ++
            "open 32\n" ++
            "break\n" ++
            "32\n" ++
            "close 32\n" ++
            "open 40\n" ++
            "try body\n" ++
            "40\n" ++
            "close 40\n" ++
            "try success\n" ++
            "open 41\n" ++
            "close 41\n" ++
            "try failure\n" ++
            "open 50\n" ++
            "open 51\n" ++
            "reverse\n" ++
            "101\n" ++
            "close 51\n" ++
            "close 50\n" ++
            "transfers\n" ++
            "open 80\n" ++
            "consume\n" ++
            "80\n" ++
            "close 80\n" ++
            "open 81\n" ++
            "consume\n" ++
            "81\n" ++
            "close 81\n" ++
            "open 82\n" ++
            "open 83\n" ++
            "close 82\n" ++
            "forward\n" ++
            "83\n" ++
            "open 84\n" ++
            "consume\n" ++
            "84\n" ++
            "close 84\n" ++
            "open 85\n" ++
            "consume\n" ++
            "85\n" ++
            "close 85\n" ++
            "open 86\n" ++
            "consume\n" ++
            "86\n" ++
            "close 86\n" ++
            "open 87\n" ++
            "consume\n" ++
            "87\n" ++
            "close 87\n" ++
            "close 83\n" ++
            "borrows\n" ++
            "open 90\n" ++
            "open 91\n" ++
            "90\n" ++
            "91\n" ++
            "180\n" ++
            "open 92\n" ++
            "92\n" ++
            "close 92\n" ++
            "consume\n" ++
            "91\n" ++
            "close 91\n" ++
            "90\n" ++
            "close 90\n" ++
            "composition\n" ++
            "open 100\n" ++
            "100\n" ++
            "100\n" ++
            "open 101\n" ++
            "101\n" ++
            "101\n" ++
            "99\n" ++
            "open 102\n" ++
            "102\n" ++
            "102\n" ++
            "close 102\n" ++
            "open 116\n" ++
            "ignored\n" ++
            "close 116\n" ++
            "open 103\n" ++
            "103\n" ++
            "consume\n" ++
            "103\n" ++
            "close 103\n" ++
            "open 104\n" ++
            "open 105\n" ++
            "104\n" ++
            "105\n" ++
            "104\n" ++
            "105\n" ++
            "consume\n" ++
            "104\n" ++
            "close 104\n" ++
            "open 106\n" ++
            "consume\n" ++
            "105\n" ++
            "close 105\n" ++
            "consume\n" ++
            "106\n" ++
            "close 106\n" ++
            "open 107\n" ++
            "consume\n" ++
            "107\n" ++
            "close 107\n" ++
            "open 115\n" ++
            "consume\n" ++
            "115\n" ++
            "close 115\n" ++
            "open 108\n" ++
            "consume\n" ++
            "108\n" ++
            "close 108\n" ++
            "open 114\n" ++
            "consume\n" ++
            "114\n" ++
            "close 114\n" ++
            "open 109\n" ++
            "109\n" ++
            "109\n" ++
            "open 110\n" ++
            "open 111\n" ++
            "open 112\n" ++
            "open 113\n" ++
            "close 113\n" ++
            "close 112\n" ++
            "close 111\n" ++
            "close 110\n" ++
            "holder drop\n" ++
            "close 109\n" ++
            "close 101\n" ++
            "close 100\n" ++
            "reject\n" ++
            "60\n" ++
            "incomplete\n" ++
            "open 61\n" ++
            "complete\n" ++
            "61\n" ++
            "close 61\n" ++
            "complete success\n" ++
            "open 70\n" ++
            "open 71\n" ++
            "main\n" ++
            "141\n" ++
            "close 71\n" ++
            "close 70\n",
    ));

    const borrowed_returns_smoke_command = b.addRunArtifact(executable);
    borrowed_returns_smoke_command.step.dependOn(b.getInstallStep());
    borrowed_returns_smoke_command.addArgs(&.{ "run", "Smokes/NativeOpaqueResources/BorrowedReturns.sx" });

    const contiguous_views_smoke_command = b.addRunArtifact(executable);
    contiguous_views_smoke_command.step.dependOn(&borrowed_returns_smoke_command.step);
    contiguous_views_smoke_command.addArgs(&.{ "run", "Smokes/ContiguousViews.sx" });

    const native_contiguous_views_smoke_command = b.addRunArtifact(executable);
    native_contiguous_views_smoke_command.step.dependOn(&contiguous_views_smoke_command.step);
    native_contiguous_views_smoke_command.addArgs(&.{ "run", "Smokes/NativeOpaqueResources/ContiguousViews.sx" });

    const algorithms_smoke_command = b.addRunArtifact(executable);
    algorithms_smoke_command.step.dependOn(&native_contiguous_views_smoke_command.step);
    algorithms_smoke_command.addArgs(&.{ "run", "Smokes/Algorithms.sx" });

    const random_algorithms_smoke_command = b.addRunArtifact(executable);
    random_algorithms_smoke_command.step.dependOn(&algorithms_smoke_command.step);
    random_algorithms_smoke_command.addArgs(&.{ "run", "Smokes/RandomAlgorithms.sx" });
    random_algorithms_smoke_command.expectStdOutEqual(hostText(b, ""));

    const random_algorithms_source = b.getInstallPath(.prefix, "lib/silex/STD/Algorithms/Random.sx");
    const algorithms_choose_empty_command = b.addRunArtifact(executable);
    algorithms_choose_empty_command.step.dependOn(&random_algorithms_smoke_command.step);
    algorithms_choose_empty_command.addArgs(&.{ "run", "Smokes/AlgorithmsChooseEmpty.sx" });
    algorithms_choose_empty_command.expectExitCode(1);
    algorithms_choose_empty_command.expectStdOutEqual(hostText(b, ""));
    algorithms_choose_empty_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:5:9: runtime error: Algorithms.choose requires a non-empty collection\n", .{random_algorithms_source}),
    ));

    const algorithms_comparator_panic_command = b.addRunArtifact(executable);
    algorithms_comparator_panic_command.step.dependOn(&algorithms_choose_empty_command.step);
    algorithms_comparator_panic_command.addArgs(&.{ "run", "Smokes/AlgorithmsComparatorPanic.sx" });
    algorithms_comparator_panic_command.expectExitCode(1);
    algorithms_comparator_panic_command.expectStdOutEqual(hostText(b, ""));
    algorithms_comparator_panic_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:23:21: runtime error: comparator panic\n", .{b.pathFromRoot("Smokes/AlgorithmsComparatorPanic.sx")}),
    ));

    const system_error_smoke_command = b.addRunArtifact(executable);
    system_error_smoke_command.step.dependOn(b.getInstallStep());
    system_error_smoke_command.addArgs(&.{ "run", "Smokes/SystemErrors.sx" });
    system_error_smoke_command.expectStdOutEqual(hostText(b, "system errors ok\n"));

    const path_smoke_command = b.addRunArtifact(executable);
    path_smoke_command.step.dependOn(&system_error_smoke_command.step);
    path_smoke_command.addArgs(&.{ "run", "Smokes/Paths.sx" });
    path_smoke_command.expectStdOutEqual(hostText(b, "paths ok\n"));

    const io_smoke_command = b.addRunArtifact(executable);
    io_smoke_command.step.dependOn(&path_smoke_command.step);
    io_smoke_command.addArgs(&.{ "run", "Smokes/IO.sx" });
    io_smoke_command.expectStdOutEqual(hostText(b, "io streams ok\n"));

    const queue_smoke_command = b.addRunArtifact(executable);
    queue_smoke_command.step.dependOn(&io_smoke_command.step);
    queue_smoke_command.addArgs(&.{ "run", "Smokes/Queue.sx" });
    queue_smoke_command.expectStdOutEqual(hostText(b, ""));

    const stack_smoke_command = b.addRunArtifact(executable);
    stack_smoke_command.step.dependOn(&queue_smoke_command.step);
    stack_smoke_command.addArgs(&.{ "run", "Smokes/Stack.sx" });
    stack_smoke_command.expectStdOutEqual(hostText(b, ""));

    const dictionary_smoke_command = b.addRunArtifact(executable);
    dictionary_smoke_command.step.dependOn(&stack_smoke_command.step);
    dictionary_smoke_command.addArgs(&.{ "run", "Smokes/Dictionary.sx" });
    dictionary_smoke_command.expectStdOutEqual(hostText(b, ""));

    const set_smoke_command = b.addRunArtifact(executable);
    set_smoke_command.step.dependOn(&dictionary_smoke_command.step);
    set_smoke_command.addArgs(&.{ "run", "Smokes/Set.sx" });
    set_smoke_command.expectStdOutEqual(hostText(b, ""));

    const iterator_smoke_command = b.addRunArtifact(executable);
    iterator_smoke_command.step.dependOn(&set_smoke_command.step);
    iterator_smoke_command.addArgs(&.{ "run", "Smokes/Iterator.sx" });
    iterator_smoke_command.expectStdOutEqual(hostText(b, ""));

    const iterator_search_smoke_command = b.addRunArtifact(executable);
    iterator_search_smoke_command.step.dependOn(&iterator_smoke_command.step);
    iterator_search_smoke_command.addArgs(&.{ "run", "Smokes/IteratorSearch.sx" });
    iterator_search_smoke_command.expectStdOutEqual(hostText(b, ""));

    const iterator_transform_smoke_command = b.addRunArtifact(executable);
    iterator_transform_smoke_command.step.dependOn(&iterator_search_smoke_command.step);
    iterator_transform_smoke_command.addArgs(&.{ "run", "Smokes/IteratorTransform.sx" });
    iterator_transform_smoke_command.expectStdOutEqual(hostText(b, ""));

    const utf8_smoke_command = b.addRunArtifact(executable);
    utf8_smoke_command.step.dependOn(&iterator_transform_smoke_command.step);
    utf8_smoke_command.addArgs(&.{ "run", "Smokes/UTF8.sx" });
    utf8_smoke_command.expectStdOutEqual(hostText(b, ""));

    const unicode_text_smoke_command = b.addRunArtifact(executable);
    unicode_text_smoke_command.step.dependOn(&utf8_smoke_command.step);
    unicode_text_smoke_command.addArgs(&.{ "run", "Smokes/UnicodeText.sx" });
    unicode_text_smoke_command.expectStdOutEqual(hostText(b, ""));

    const grapheme_smoke_command = b.addRunArtifact(executable);
    grapheme_smoke_command.step.dependOn(&unicode_text_smoke_command.step);
    grapheme_smoke_command.addArgs(&.{ "run", "Smokes/Grapheme.sx" });
    grapheme_smoke_command.expectStdOutEqual(hostText(b, "2/1\n4/1\n2/1\n2/1\n1/1\n3/3\n"));

    const encoding_smoke_command = b.addRunArtifact(executable);
    encoding_smoke_command.step.dependOn(&grapheme_smoke_command.step);
    encoding_smoke_command.addArgs(&.{ "run", "Smokes/Encoding.sx" });
    encoding_smoke_command.expectStdOutEqual(hostText(b, ""));

    const file_smoke_command = b.addRunArtifact(executable);
    file_smoke_command.step.dependOn(&encoding_smoke_command.step);
    file_smoke_command.addArgs(&.{ "run", "Smokes/BinaryFile.sx" });
    file_smoke_command.expectStdOutEqual(hostText(b, ""));

    const filesystem_smoke_command = b.addRunArtifact(executable);
    filesystem_smoke_command.step.dependOn(&file_smoke_command.step);
    filesystem_smoke_command.addArgs(&.{ "run", "Smokes/FileSystem.sx" });
    filesystem_smoke_command.expectStdOutEqual(hostText(b, ""));

    const environment_smoke_command = b.addRunArtifact(executable);
    environment_smoke_command.step.dependOn(&filesystem_smoke_command.step);
    environment_smoke_command.addArgs(&.{ "run", "Smokes/Environment.sx" });
    environment_smoke_command.expectStdOutEqual(hostText(b, ""));

    const process_smoke_compile_command = b.addRunArtifact(executable);
    process_smoke_compile_command.step.dependOn(&environment_smoke_command.step);
    process_smoke_compile_command.addArgs(&.{
        "compile",
        "Smokes/Process.sx",
        "-o",
        ".silex/process-smoke-bin",
    });
    const process_smoke_command = b.addSystemCommand(&.{
        ".silex/process-smoke-bin",
        "space value",
        "",
        "été",
    });
    process_smoke_command.step.dependOn(&process_smoke_compile_command.step);
    process_smoke_command.expectStdOutEqual("");

    const subprocess_smoke_compile_command = b.addRunArtifact(executable);
    subprocess_smoke_compile_command.step.dependOn(&process_smoke_command.step);
    subprocess_smoke_compile_command.addArgs(&.{
        "compile",
        "Smokes/Subprocess.sx",
        "-o",
        ".silex/subprocess-smoke-bin",
    });
    const subprocess_smoke_command = b.addSystemCommand(&.{".silex/subprocess-smoke-bin"});
    subprocess_smoke_command.step.dependOn(&subprocess_smoke_compile_command.step);
    subprocess_smoke_command.addFileArg(subprocess_child.getEmittedBin());
    subprocess_smoke_command.expectStdOutEqual("");

    const json_smoke_command = b.addRunArtifact(executable);
    json_smoke_command.step.dependOn(&subprocess_smoke_command.step);
    json_smoke_command.addArgs(&.{ "run", "Smokes/JSON.sx" });
    json_smoke_command.expectStdOutEqual(hostText(b, ""));

    const network_address_smoke_command = b.addRunArtifact(executable);
    network_address_smoke_command.step.dependOn(&json_smoke_command.step);
    network_address_smoke_command.addArgs(&.{ "run", "Smokes/NetworkAddress.sx" });
    network_address_smoke_command.expectStdOutEqual(hostText(b, ""));

    const network_tcp_smoke_command = b.addRunArtifact(executable);
    network_tcp_smoke_command.step.dependOn(&network_address_smoke_command.step);
    network_tcp_smoke_command.addArgs(&.{ "run", "Smokes/NetworkTCP.sx" });
    network_tcp_smoke_command.expectStdOutEqual(hostText(b, ""));

    const network_udp_smoke_command = b.addRunArtifact(executable);
    network_udp_smoke_command.step.dependOn(&network_tcp_smoke_command.step);
    network_udp_smoke_command.addArgs(&.{ "run", "Smokes/NetworkUDP.sx" });
    network_udp_smoke_command.expectStdOutEqual(hostText(b, ""));

    const queue_negative_create_command = b.addRunArtifact(executable);
    queue_negative_create_command.step.dependOn(&network_udp_smoke_command.step);
    queue_negative_create_command.addArgs(&.{ "run", "Smokes/QueueErrors/NegativeCreate.sx" });
    queue_negative_create_command.expectExitCode(1);
    queue_negative_create_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:14:13: runtime error: Queue.create requires a non-negative minimum capacity\n",
        .{queue_source},
    )));

    const queue_negative_reserve_command = b.addRunArtifact(executable);
    queue_negative_reserve_command.step.dependOn(&queue_negative_create_command.step);
    queue_negative_reserve_command.addArgs(&.{ "run", "Smokes/QueueErrors/NegativeReserve.sx" });
    queue_negative_reserve_command.expectExitCode(1);
    queue_negative_reserve_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:73:13: runtime error: Queue.reserve requires a non-negative minimum capacity\n",
        .{queue_source},
    )));

    const queue_peek_empty_command = b.addRunArtifact(executable);
    queue_peek_empty_command.step.dependOn(&queue_negative_reserve_command.step);
    queue_peek_empty_command.addArgs(&.{ "run", "Smokes/QueueErrors/PeekEmpty.sx" });
    queue_peek_empty_command.expectExitCode(1);
    queue_peek_empty_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:66:13: runtime error: Queue.peek requires a value\n",
        .{queue_source},
    )));

    const stack_negative_create_command = b.addRunArtifact(executable);
    stack_negative_create_command.step.dependOn(&queue_peek_empty_command.step);
    stack_negative_create_command.addArgs(&.{ "run", "Smokes/StackErrors/NegativeCreate.sx" });
    stack_negative_create_command.expectExitCode(1);
    stack_negative_create_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:13:13: runtime error: Stack.create requires a non-negative minimum capacity\n",
        .{stack_source},
    )));

    const stack_negative_reserve_command = b.addRunArtifact(executable);
    stack_negative_reserve_command.step.dependOn(&stack_negative_create_command.step);
    stack_negative_reserve_command.addArgs(&.{ "run", "Smokes/StackErrors/NegativeReserve.sx" });
    stack_negative_reserve_command.expectExitCode(1);
    stack_negative_reserve_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:65:13: runtime error: Stack.reserve requires a non-negative minimum capacity\n",
        .{stack_source},
    )));

    const stack_peek_empty_command = b.addRunArtifact(executable);
    stack_peek_empty_command.step.dependOn(&stack_negative_reserve_command.step);
    stack_peek_empty_command.addArgs(&.{ "run", "Smokes/StackErrors/PeekEmpty.sx" });
    stack_peek_empty_command.expectExitCode(1);
    stack_peek_empty_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:58:13: runtime error: Stack.peek requires a value\n",
        .{stack_source},
    )));

    const dictionary_negative_create_command = b.addRunArtifact(executable);
    dictionary_negative_create_command.step.dependOn(&stack_peek_empty_command.step);
    dictionary_negative_create_command.addArgs(&.{ "run", "Smokes/DictionaryErrors/NegativeCreate.sx" });
    dictionary_negative_create_command.expectExitCode(1);
    dictionary_negative_create_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:44:13: runtime error: Dictionary.create requires a non-negative minimum capacity\n",
        .{dictionary_source},
    )));

    const dictionary_negative_reserve_command = b.addRunArtifact(executable);
    dictionary_negative_reserve_command.step.dependOn(&dictionary_negative_create_command.step);
    dictionary_negative_reserve_command.addArgs(&.{ "run", "Smokes/DictionaryErrors/NegativeReserve.sx" });
    dictionary_negative_reserve_command.expectExitCode(1);
    dictionary_negative_reserve_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:129:13: runtime error: Dictionary.reserve requires a non-negative minimum capacity\n",
        .{dictionary_source},
    )));

    const dictionary_at_absent_command = b.addRunArtifact(executable);
    dictionary_at_absent_command.step.dependOn(&dictionary_negative_reserve_command.step);
    dictionary_at_absent_command.addArgs(&.{ "run", "Smokes/DictionaryErrors/AtAbsent.sx" });
    dictionary_at_absent_command.expectExitCode(1);
    dictionary_at_absent_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:70:13: runtime error: Dictionary.at requires an existing key\n",
        .{dictionary_source},
    )));

    const set_source = b.getInstallPath(.prefix, "lib/silex/STD/Collections/Set.sx");
    const set_negative_create_command = b.addRunArtifact(executable);
    set_negative_create_command.step.dependOn(&dictionary_at_absent_command.step);
    set_negative_create_command.addArgs(&.{ "run", "Smokes/SetErrors/NegativeCreate.sx" });
    set_negative_create_command.expectExitCode(1);
    set_negative_create_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:21:13: runtime error: Set.create requires a non-negative minimum capacity\n",
        .{set_source},
    )));

    const set_negative_reserve_command = b.addRunArtifact(executable);
    set_negative_reserve_command.step.dependOn(&set_negative_create_command.step);
    set_negative_reserve_command.addArgs(&.{ "run", "Smokes/SetErrors/NegativeReserve.sx" });
    set_negative_reserve_command.expectExitCode(1);
    set_negative_reserve_command.expectStdErrEqual(hostText(b, b.fmt(
        "{s}:63:13: runtime error: Set.reserve requires a non-negative minimum capacity\n",
        .{set_source},
    )));

    const smoke_step = b.step("smoke", "Compile and run the smoke program");
    smoke_step.dependOn(b.getInstallStep());
    smoke_step.dependOn(previous_integer_error_step);
    smoke_step.dependOn(&unique_resources_smoke_command.step);
    smoke_step.dependOn(&algorithms_comparator_panic_command.step);
    smoke_step.dependOn(&set_negative_reserve_command.step);

    const release_check_step = b.step("release-check", "Run tests and end-to-end smokes");
    release_check_step.dependOn(test_step);
    release_check_step.dependOn(smoke_step);

    const benchmark_suffix = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    const silex_benchmark_path = b.fmt("zig-out/bin/IntegerLoopsSilex{s}", .{benchmark_suffix});
    const cpp_benchmark_path = b.fmt("zig-out/bin/IntegerLoopsCpp{s}", .{benchmark_suffix});
    const process_baseline_path = b.fmt("zig-out/bin/ProcessBaseline{s}", .{benchmark_suffix});
    const benchmark_runner_path = b.fmt("zig-out/bin/IntegerBenchmarkRunner{s}", .{benchmark_suffix});

    const compile_silex_benchmark = b.addRunArtifact(executable);
    compile_silex_benchmark.step.dependOn(b.getInstallStep());
    compile_silex_benchmark.addArgs(&.{
        "compile",
        "Benchmarks/IntegerLoops.sx",
        "-o",
        silex_benchmark_path,
    });

    const compile_cpp_benchmark = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "c++",
        "-O2",
        "-std=c++23",
        "Benchmarks/IntegerLoops.cpp",
        "-o",
        cpp_benchmark_path,
    });
    compile_cpp_benchmark.step.dependOn(b.getInstallStep());

    const compile_process_baseline = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "c++",
        "-O2",
        "-std=c++23",
        "Benchmarks/ProcessBaseline.cpp",
        "-o",
        process_baseline_path,
    });
    compile_process_baseline.step.dependOn(b.getInstallStep());

    const compile_benchmark_runner = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "c++",
        "-O2",
        "-std=c++23",
        "Benchmarks/Runner.cpp",
        "-o",
        benchmark_runner_path,
    });
    compile_benchmark_runner.step.dependOn(b.getInstallStep());

    const benchmark_output = hostText(b, "-705898\n-4\n");
    const validate_silex_benchmark = b.addSystemCommand(&.{silex_benchmark_path});
    validate_silex_benchmark.step.dependOn(&compile_silex_benchmark.step);
    validate_silex_benchmark.expectStdOutEqual(benchmark_output);

    const validate_cpp_benchmark = b.addSystemCommand(&.{cpp_benchmark_path});
    validate_cpp_benchmark.step.dependOn(&compile_cpp_benchmark.step);
    validate_cpp_benchmark.expectStdOutEqual(benchmark_output);

    const benchmark_runner = b.addSystemCommand(&.{
        benchmark_runner_path,
        silex_benchmark_path,
        cpp_benchmark_path,
        process_baseline_path,
    });
    benchmark_runner.step.dependOn(&compile_benchmark_runner.step);
    benchmark_runner.step.dependOn(&compile_process_baseline.step);
    benchmark_runner.step.dependOn(&validate_silex_benchmark.step);
    benchmark_runner.step.dependOn(&validate_cpp_benchmark.step);

    const benchmark_step = b.step(
        "benchmark-integers",
        "Measure robust Silex integer statistics against equivalent checked C++",
    );
    benchmark_step.dependOn(&benchmark_runner.step);

    const cross_smoke_command = b.addRunArtifact(executable);
    cross_smoke_command.step.dependOn(b.getInstallStep());
    cross_smoke_command.addArgs(&.{
        "compile",
        "Smokes/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-smoke/Main-x86_64-linux",
    });

    const cross_integer_semantics_command = b.addRunArtifact(executable);
    cross_integer_semantics_command.step.dependOn(&cross_smoke_command.step);
    cross_integer_semantics_command.addArgs(&.{
        "compile",
        "Smokes/IntegerSemantics.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-smoke/IntegerSemantics-x86_64-linux",
    });

    const cross_smoke_step = b.step("cross-smoke", "Cross-compile smoke programs for x86_64 Linux");
    cross_smoke_step.dependOn(&cross_integer_semantics_command.step);

    const cross_native_smoke_command = b.addRunArtifact(executable);
    cross_native_smoke_command.step.dependOn(b.getInstallStep());
    cross_native_smoke_command.addArgs(&.{
        "compile",
        "Smokes/Native/Main.sx",
        "--native",
        "Smokes/Native/dependency.json",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/Main-x86_64-linux",
    });

    const cross_local_native_smoke_command = b.addRunArtifact(executable);
    cross_local_native_smoke_command.step.dependOn(&cross_native_smoke_command.step);
    cross_local_native_smoke_command.addArgs(&.{
        "compile",
        "Smokes/LocalNative/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/LocalNative-x86_64-linux",
    });

    const cross_native_structure_string_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_string_linux_smoke_command.step.dependOn(&cross_local_native_smoke_command.step);
    cross_native_structure_string_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureStrings/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeStructureStrings-x86_64-linux",
    });

    const cross_native_structure_string_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_string_windows_smoke_command.step.dependOn(&cross_native_structure_string_linux_smoke_command.step);
    cross_native_structure_string_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureStrings/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeStructureStrings-x86_64-windows.exe",
    });

    const cross_native_optional_return_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_optional_return_linux_smoke_command.step.dependOn(&cross_native_structure_string_windows_smoke_command.step);
    cross_native_optional_return_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeOptionalReturns/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeOptionalReturns-x86_64-linux",
    });

    const cross_native_optional_return_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_optional_return_windows_smoke_command.step.dependOn(&cross_native_optional_return_linux_smoke_command.step);
    cross_native_optional_return_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeOptionalReturns/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeOptionalReturns-x86_64-windows.exe",
    });

    const cross_native_structure_parameter_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_parameter_linux_smoke_command.step.dependOn(&cross_native_optional_return_windows_smoke_command.step);
    cross_native_structure_parameter_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureParameters/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeStructureParameters-x86_64-linux",
    });

    const cross_native_structure_parameter_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_parameter_windows_smoke_command.step.dependOn(&cross_native_structure_parameter_linux_smoke_command.step);
    cross_native_structure_parameter_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureParameters/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeStructureParameters-x86_64-windows.exe",
    });

    const cross_native_structure_string_parameter_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_string_parameter_linux_smoke_command.step.dependOn(&cross_native_structure_parameter_windows_smoke_command.step);
    cross_native_structure_string_parameter_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureStringParameters/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeStructureStringParameters-x86_64-linux",
    });

    const cross_native_structure_string_parameter_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_structure_string_parameter_windows_smoke_command.step.dependOn(&cross_native_structure_string_parameter_linux_smoke_command.step);
    cross_native_structure_string_parameter_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStructureStringParameters/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeStructureStringParameters-x86_64-windows.exe",
    });

    const cross_native_result_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_result_linux_smoke_command.step.dependOn(&cross_native_structure_string_parameter_windows_smoke_command.step);
    cross_native_result_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeResults/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeResults-x86_64-linux",
    });

    const cross_native_result_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_result_windows_smoke_command.step.dependOn(&cross_native_result_linux_smoke_command.step);
    cross_native_result_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeResults/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeResults-x86_64-windows.exe",
    });

    const cross_native_byte_view_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_byte_view_linux_smoke_command.step.dependOn(&cross_native_result_windows_smoke_command.step);
    cross_native_byte_view_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeByteViews/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeByteViews-x86_64-linux",
    });

    const cross_native_byte_view_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_byte_view_windows_smoke_command.step.dependOn(&cross_native_byte_view_linux_smoke_command.step);
    cross_native_byte_view_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeByteViews/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeByteViews-x86_64-windows.exe",
    });

    const cross_native_byte_buffer_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_byte_buffer_linux_smoke_command.step.dependOn(&cross_native_byte_view_windows_smoke_command.step);
    cross_native_byte_buffer_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeByteBuffers/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeByteBuffers-x86_64-linux",
    });

    const cross_native_byte_buffer_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_byte_buffer_windows_smoke_command.step.dependOn(&cross_native_byte_buffer_linux_smoke_command.step);
    cross_native_byte_buffer_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeByteBuffers/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeByteBuffers-x86_64-windows.exe",
    });

    const cross_native_callback_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_callback_linux_smoke_command.step.dependOn(&cross_native_byte_buffer_windows_smoke_command.step);
    cross_native_callback_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeCallbacks/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeCallbacks-x86_64-linux",
    });

    const cross_native_callback_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_callback_windows_smoke_command.step.dependOn(&cross_native_callback_linux_smoke_command.step);
    cross_native_callback_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeCallbacks/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeCallbacks-x86_64-windows.exe",
    });

    const cross_native_string_linux_smoke_command = b.addRunArtifact(executable);
    cross_native_string_linux_smoke_command.step.dependOn(&cross_native_callback_windows_smoke_command.step);
    cross_native_string_linux_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStrings/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/NativeStrings-x86_64-linux",
    });

    const cross_native_string_windows_smoke_command = b.addRunArtifact(executable);
    cross_native_string_windows_smoke_command.step.dependOn(&cross_native_string_linux_smoke_command.step);
    cross_native_string_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/NativeStrings/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/NativeStrings-x86_64-windows.exe",
    });

    const cross_console_windows_smoke_command = b.addRunArtifact(executable);
    cross_console_windows_smoke_command.step.dependOn(&cross_native_string_windows_smoke_command.step);
    cross_console_windows_smoke_command.addArgs(&.{
        "compile",
        "Smokes/Console/Main.sx",
        "--target",
        "x86_64-windows-gnu",
        "-o",
        ".silex/cross-native-smoke/Console-x86_64-windows.exe",
    });

    const cross_isolated_std_linux_smoke_command = b.addRunArtifact(executable);
    cross_isolated_std_linux_smoke_command.step.dependOn(&cross_console_windows_smoke_command.step);
    cross_isolated_std_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedSTD/Main.sx",                         "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/IsolatedSTD-x86_64-linux",
    });

    const cross_isolated_std_windows_smoke_command = b.addRunArtifact(executable);
    cross_isolated_std_windows_smoke_command.step.dependOn(&cross_isolated_std_linux_smoke_command.step);
    cross_isolated_std_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedSTD/Main.sx",                               "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/IsolatedSTD-x86_64-windows.exe",
    });

    const cross_system_error_linux_smoke_command = b.addRunArtifact(executable);
    cross_system_error_linux_smoke_command.step.dependOn(&cross_isolated_std_windows_smoke_command.step);
    cross_system_error_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/SystemErrors.sx",                              "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/SystemErrors-x86_64-linux",
    });

    const cross_system_error_windows_smoke_command = b.addRunArtifact(executable);
    cross_system_error_windows_smoke_command.step.dependOn(&cross_system_error_linux_smoke_command.step);
    cross_system_error_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/SystemErrors.sx",                                    "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/SystemErrors-x86_64-windows.exe",
    });

    const cross_path_linux_smoke_command = b.addRunArtifact(executable);
    cross_path_linux_smoke_command.step.dependOn(&cross_system_error_windows_smoke_command.step);
    cross_path_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/Paths.sx",                              "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/Paths-x86_64-linux",
    });

    const cross_path_windows_smoke_command = b.addRunArtifact(executable);
    cross_path_windows_smoke_command.step.dependOn(&cross_path_linux_smoke_command.step);
    cross_path_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/Paths.sx",                                    "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/Paths-x86_64-windows.exe",
    });

    const cross_io_linux_smoke_command = b.addRunArtifact(executable);
    cross_io_linux_smoke_command.step.dependOn(&cross_path_windows_smoke_command.step);
    cross_io_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/IO.sx",                              "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/IO-x86_64-linux",
    });

    const cross_io_windows_smoke_command = b.addRunArtifact(executable);
    cross_io_windows_smoke_command.step.dependOn(&cross_io_linux_smoke_command.step);
    cross_io_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/IO.sx",                                    "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/IO-x86_64-windows.exe",
    });

    const cross_isolated_time_linux_smoke_command = b.addRunArtifact(executable);
    cross_isolated_time_linux_smoke_command.step.dependOn(&cross_io_windows_smoke_command.step);
    cross_isolated_time_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedTime/Main.sx",                         "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/IsolatedTime-x86_64-linux",
    });

    const cross_isolated_time_windows_smoke_command = b.addRunArtifact(executable);
    cross_isolated_time_windows_smoke_command.step.dependOn(&cross_isolated_time_linux_smoke_command.step);
    cross_isolated_time_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedTime/Main.sx",                               "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/IsolatedTime-x86_64-windows.exe",
    });

    const cross_isolated_console_linux_smoke_command = b.addRunArtifact(executable);
    cross_isolated_console_linux_smoke_command.step.dependOn(&cross_isolated_time_windows_smoke_command.step);
    cross_isolated_console_linux_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedConsole/Main.sx",                         "--target", "x86_64-linux-musl",
        "-o",      ".silex/cross-native-smoke/IsolatedConsole-x86_64-linux",
    });

    const cross_isolated_console_windows_smoke_command = b.addRunArtifact(executable);
    cross_isolated_console_windows_smoke_command.step.dependOn(&cross_isolated_console_linux_smoke_command.step);
    cross_isolated_console_windows_smoke_command.addArgs(&.{
        "compile", "Smokes/IsolatedConsole/Main.sx",                               "--target", "x86_64-windows-gnu",
        "-o",      ".silex/cross-native-smoke/IsolatedConsole-x86_64-windows.exe",
    });

    const cross_native_smoke_step = b.step(
        "cross-native-smoke",
        "Cross-compile the native source smoke program for x86_64 Linux",
    );
    cross_native_smoke_step.dependOn(&cross_isolated_console_windows_smoke_command.step);

    const distribution_options = b.addOptions();
    distribution_options.addOption([]const u8, "silex_version", silex_version);
    distribution_options.addOption([]const u8, "developer_zig", "");
    distribution_options.addOption([]const u8, "developer_standard_library_root", "");
    distribution_options.addOption(bool, "repository_compilation_database", false);
    distribution_options.addOption(bool, "run_source_graph_tests", true);
    const distribution_module = b.createModule(.{
        .root_source_file = b.path("Sources/Main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    distribution_module.addOptions("build_options", distribution_options);

    const distribution_executable = b.addExecutable(.{
        .name = "silex",
        .root_module = distribution_module,
    });
    const host = b.graph.host.result;
    const distribution_name = b.fmt("silex-{s}-{s}-{s}", .{
        silex_version,
        @tagName(host.cpu.arch),
        @tagName(host.os.tag),
    });
    const distribution_root = b.fmt("dist/{s}", .{distribution_name});
    const silex_name = if (host.os.tag == .windows) "silex.exe" else "silex";
    const zig_name = if (host.os.tag == .windows) "zig.exe" else "zig";

    const install_silex = b.addInstallFile(
        distribution_executable.getEmittedBin(),
        b.fmt("{s}/bin/{s}", .{ distribution_root, silex_name }),
    );
    const install_zig = b.addInstallFile(
        .{ .cwd_relative = b.graph.zig_exe },
        b.fmt("{s}/toolchain/zig/{s}", .{ distribution_root, zig_name }),
    );
    const install_zig_lib = b.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = b.graph.zig_lib_directory.path.? },
        .install_dir = .prefix,
        .install_subdir = b.fmt("{s}/toolchain/zig/lib", .{distribution_root}),
    });
    const install_distribution_library = b.addInstallDirectory(.{
        .source_dir = b.path("../Library"),
        .install_dir = .prefix,
        .install_subdir = b.fmt("{s}/lib/silex", .{distribution_root}),
    });
    const clean_distribution_library = b.addRunArtifact(clean_library_install);
    clean_distribution_library.addArg(b.getInstallPath(
        .prefix,
        b.fmt("{s}/lib/silex", .{distribution_root}),
    ));
    install_distribution_library.step.dependOn(&clean_distribution_library.step);

    const distribution_step = b.step("dist", "Build a self-contained distribution for this host");
    distribution_step.dependOn(&install_silex.step);
    distribution_step.dependOn(&install_zig.step);
    distribution_step.dependOn(&install_zig_lib.step);
    distribution_step.dependOn(&install_distribution_library.step);

    const distribution_check_files = b.addWriteFiles();
    _ = distribution_check_files.addCopyFile(b.path("Smokes/StandardLibrary/Main.sx"), "Main.sx");
    const installed_silex = b.getInstallPath(.prefix, b.fmt("{s}/bin/{s}", .{ distribution_root, silex_name }));
    const verify_distribution = b.addSystemCommand(&.{ installed_silex, "run", "Main.sx" });
    verify_distribution.setCwd(distribution_check_files.getDirectory());
    verify_distribution.setEnvironmentVariable("PATH", "");
    verify_distribution.expectStdOutEqual(hostText(b, standard_library_output ++ "true\n"));
    verify_distribution.step.dependOn(distribution_step);

    const distribution_check_step = b.step("dist-check", "Build and verify the self-contained host distribution");
    distribution_check_step.dependOn(&verify_distribution.step);
}

fn hostText(b: *std.Build, text: []const u8) []const u8 {
    if (b.graph.host.result.os.tag != .windows) return text;
    return std.mem.replaceOwned(u8, b.allocator, text, "\n", "\r\n") catch @panic("OOM");
}
