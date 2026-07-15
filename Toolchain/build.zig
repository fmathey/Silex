const std = @import("std");
const silex_version = "0.13.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "silex_version", silex_version);
    build_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);
    build_options.addOption([]const u8, "developer_standard_library_root", b.getInstallPath(.prefix, "lib/silex"));

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
    b.installArtifact(executable);
    const install_library = b.addInstallDirectory(.{
        .source_dir = b.path("../Library"),
        .install_dir = .prefix,
        .install_subdir = "lib/silex",
    });
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

    const lsp_test_module = b.createModule(.{
        .root_source_file = b.path("Sources/Lsp.zig"),
        .target = target,
        .optimize = optimize,
    });
    lsp_test_module.addOptions("build_options", build_options);
    const lsp_tests = b.addTest(.{
        .root_module = lsp_test_module,
    });
    const lsp_test_command = b.addRunArtifact(lsp_tests);

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
        "Tests/InvalidMutableReferenceArgument.sx:7:13: error: cannot pass immutable variable 'count' with '&'\n",
    );

    const missing_mutable_reference_argument_command = b.addRunArtifact(executable);
    missing_mutable_reference_argument_command.addArgs(&.{ "compile", "Tests/MissingMutableReferenceArgument.sx" });
    missing_mutable_reference_argument_command.expectExitCode(1);
    missing_mutable_reference_argument_command.expectStdErrEqual(
        "Tests/MissingMutableReferenceArgument.sx:7:5: error: no compatible signature for function 'replace'; visible signatures: replace(&int)\n",
    );

    const invalid_local_reference_command = b.addRunArtifact(executable);
    invalid_local_reference_command.addArgs(&.{ "compile", "Tests/InvalidLocalReference.sx" });
    invalid_local_reference_command.expectExitCode(1);
    invalid_local_reference_command.expectStdErrEqual(
        "Tests/InvalidLocalReference.sx:3:21: error: '&' is only valid for an argument of a parameter declared with '&'\n",
    );

    const invalid_native_function_command = b.addRunArtifact(executable);
    invalid_native_function_command.addArgs(&.{ "compile", "Tests/InvalidNativeFunction.sx" });
    invalid_native_function_command.expectExitCode(1);
    invalid_native_function_command.expectStdErrEqual(
        "Tests/InvalidNativeFunction.sx:1:1: error: native functions are only available in a named module with Module.json native configuration\n",
    );

    const invalid_public_native_function_command = b.addRunArtifact(executable);
    invalid_public_native_function_command.addArgs(&.{ "compile", "Tests/InvalidPublicNativeFunction.sx" });
    invalid_public_native_function_command.expectExitCode(1);
    invalid_public_native_function_command.expectStdErrEqual(
        "Tests/InvalidPublicNativeFunction.sx:1:5: error: native functions cannot be public\n",
    );

    const invalid_native_type_command = b.addRunArtifact(native_module_test_executable);
    invalid_native_type_command.addArgs(&.{ "compile", "Tests/DistributedModules/NativeInvalidType/Main.sx" });
    invalid_native_type_command.expectExitCode(1);
    invalid_native_type_command.expectStdErrMatch("native parameter 'values' cannot use 'list'\n");

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

    const invalid_reference_type_command = b.addRunArtifact(executable);
    invalid_reference_type_command.addArgs(&.{ "compile", "Tests/InvalidReferenceType.sx" });
    invalid_reference_type_command.expectExitCode(1);
    invalid_reference_type_command.expectStdErrEqual(
        "Tests/InvalidReferenceType.sx:1:20: error: expected ')'\n",
    );

    const invalid_condition_command = b.addRunArtifact(executable);
    invalid_condition_command.addArgs(&.{ "compile", "Tests/InvalidCondition.sx" });
    invalid_condition_command.expectExitCode(1);
    invalid_condition_command.expectStdErrEqual(
        "Tests/InvalidCondition.sx:2:9: error: expected 'bool', found 'int'\n",
    );

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
    removed_random_next_command.addArgs(&.{ "compile", "Tests/RemovedRandomNext.sx" });
    removed_random_next_command.expectExitCode(1);
    removed_random_next_command.expectStdErrEqual(
        "Tests/RemovedRandomNext.sx:5:18: error: struct 'STD.Random.Generator' has no method 'next'\n",
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
        "Tests/DuplicateOverloadAlias.sx:5:6: error: function 'measure' with this signature is already declared\n",
    );

    const duplicate_overload_return_command = b.addRunArtifact(executable);
    duplicate_overload_return_command.addArgs(&.{ "compile", "Tests/DuplicateOverloadReturn.sx" });
    duplicate_overload_return_command.expectExitCode(1);
    duplicate_overload_return_command.expectStdErrEqual(
        "Tests/DuplicateOverloadReturn.sx:5:6: error: function 'measure' with this signature is already declared\n",
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
        "Tests/UnknownStructField.sx:7:37: error: unknown field 'depth' in struct 'Position'\n",
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
        "Tests/DuplicateStructField.sx:7:37: error: field 'x' is initialized more than once\n",
    );

    const invalid_struct_field_type_command = b.addRunArtifact(executable);
    invalid_struct_field_type_command.addArgs(&.{ "compile", "Tests/InvalidStructFieldType.sx" });
    invalid_struct_field_type_command.expectExitCode(1);
    invalid_struct_field_type_command.expectStdErrEqual(
        "Tests/InvalidStructFieldType.sx:7:33: error: expected 'int', found 'str'\n",
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
        "Tests/InvalidFieldDefault.sx:2:18: error: default field value must be a literal or struct initializer of type 'int'\n",
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
        "Tests/InvalidStringLength.sx:2:13: error: method call requires a struct or collection value\n",
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
        "Tests/InvalidForSource.sx:2:19: error: for source must be an array or list\n",
    );

    const invalid_immutable_iteration_alias_command = b.addRunArtifact(executable);
    invalid_immutable_iteration_alias_command.addArgs(&.{ "compile", "Tests/InvalidImmutableIterationAlias.sx" });
    invalid_immutable_iteration_alias_command.expectExitCode(1);
    invalid_immutable_iteration_alias_command.expectStdErrEqual(
        "Tests/InvalidImmutableIterationAlias.sx:4:9: error: cannot assign to immutable variable 'value'\n",
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
        "Tests/InvalidStructureEquality.sx:10:28: error: equality operator requires operands of the same type, found 'Position' and 'Velocity'\n",
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
        "silex: backend details: .silex{c}build{c}v24{c}x86_64-linux-musl{c}",
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
        "Tests/Modules/Missing/Main.sx:1:1: error: module 'Missing' was not found\n",
    );

    const module_alias_collision_command = b.addRunArtifact(executable);
    module_alias_collision_command.addArgs(&.{ "compile", "Tests/Modules/AliasCollision/project.json" });
    module_alias_collision_command.expectExitCode(1);
    module_alias_collision_command.expectStdErrEqual(
        "Tests/Modules/AliasCollision/Main.sx:3:1: error: name 'Shared' collides with an import alias\n",
    );

    const multiple_module_providers_command = b.addRunArtifact(executable);
    multiple_module_providers_command.addArgs(&.{ "compile", "Tests/Modules/MultipleProviders/project.json" });
    multiple_module_providers_command.expectExitCode(1);
    multiple_module_providers_command.expectStdErrEqual(
        "silex: module 'Lib' has multiple providers\n",
    );

    const unknown_module_path_command = b.addRunArtifact(executable);
    unknown_module_path_command.addArgs(&.{ "compile", "Tests/Modules/UnknownPath/project.json" });
    unknown_module_path_command.expectExitCode(1);
    unknown_module_path_command.expectStdErrEqual(
        "Tests/Modules/UnknownPath/Main.sx:4:9: error: module 'Lib' has no public declaration 'Missing'\n",
    );

    const unknown_qualified_descendant_command = b.addRunArtifact(executable);
    unknown_qualified_descendant_command.addArgs(&.{ "compile", "Tests/UnknownQualifiedDescendant.sx" });
    unknown_qualified_descendant_command.expectExitCode(1);
    unknown_qualified_descendant_command.expectStdErrEqual(
        "Tests/UnknownQualifiedDescendant.sx:4:17: error: unknown struct 'STD.Unknown.Value'\n",
    );

    const public_module_use_command = b.addRunArtifact(executable);
    public_module_use_command.addArgs(&.{ "compile", "Tests/Modules/PublicModuleUse/project.json" });
    public_module_use_command.expectExitCode(1);
    public_module_use_command.expectStdErrEqual(
        "Tests/Modules/PublicModuleUse/Main.sx:1:5: error: module 'Lib.Child' cannot be re-exported with 'pub use'\n",
    );

    const missing_local_import_command = b.addRunArtifact(executable);
    missing_local_import_command.addArgs(&.{ "compile", "Tests/LocalImports/Missing/Main.sx" });
    missing_local_import_command.expectExitCode(1);
    missing_local_import_command.expectStdErrEqual(
        "Tests/LocalImports/Missing/Main.sx:1:1: error: local module 'Math.Vec3' was not found at 'Tests/LocalImports/Missing/Math/Vec3'\n",
    );

    const parent_only_import_command = b.addRunArtifact(executable);
    parent_only_import_command.addArgs(&.{ "run", "Tests/LocalImports/ParentOnly/Main.sx" });
    parent_only_import_command.expectStdOutEqual(hostText(b, "parent only\n"));

    const package_diamond_command = b.addRunArtifact(executable);
    package_diamond_command.addArgs(&.{ "run", "Tests/Packages/Diamond/App/Main.sx" });
    package_diamond_command.expectStdOutEqual(hostText(b, "23\n"));

    const transitive_package_visibility_command = b.addRunArtifact(executable);
    transitive_package_visibility_command.addArgs(&.{ "compile", "Tests/Packages/Visibility/App/Main.sx" });
    transitive_package_visibility_command.expectExitCode(1);
    transitive_package_visibility_command.expectStdErrEqual(
        "Tests/Packages/Visibility/App/Main.sx:1:1: error: package 'application' cannot import transitive package 'Utility' without declaring it directly\n",
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

    const test_step = b.step("test", "Run the toolchain tests");
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&test_command.step);
    test_step.dependOn(&lsp_test_command.step);
    test_step.dependOn(&invalid_command.step);
    test_step.dependOn(&missing_module_subcommand_command.step);
    test_step.dependOn(&missing_module_init_path_command.step);
    test_step.dependOn(&invalid_module_init_option_command.step);
    test_step.dependOn(&immutable_assignment_command.step);
    test_step.dependOn(&invalid_mutable_reference_argument_command.step);
    test_step.dependOn(&missing_mutable_reference_argument_command.step);
    test_step.dependOn(&invalid_local_reference_command.step);
    test_step.dependOn(&invalid_native_function_command.step);
    test_step.dependOn(&invalid_public_native_function_command.step);
    test_step.dependOn(&invalid_native_type_command.step);
    test_step.dependOn(&missing_native_symbol_command.step);
    test_step.dependOn(&native_exception_command.step);
    test_step.dependOn(&duplicate_native_source_command.step);
    test_step.dependOn(&inherited_native_runtime_command.step);
    test_step.dependOn(&invalid_reference_type_command.step);
    test_step.dependOn(&invalid_condition_command.step);
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
    test_step.dependOn(&invalid_immutable_iteration_alias_command.step);
    test_step.dependOn(&invalid_mutable_iteration_source_command.step);
    test_step.dependOn(&invalid_iteration_mutation_command.step);
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
    test_step.dependOn(&module_alias_collision_command.step);
    test_step.dependOn(&multiple_module_providers_command.step);
    test_step.dependOn(&unknown_module_path_command.step);
    test_step.dependOn(&unknown_qualified_descendant_command.step);
    test_step.dependOn(&public_module_use_command.step);
    test_step.dependOn(&missing_local_import_command.step);
    test_step.dependOn(&parent_only_import_command.step);
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

    const smoke_command = b.addRunArtifact(executable);
    smoke_command.addArgs(&.{ "run", "Smokes/Main.sx" });
    smoke_command.expectStdOutEqual(hostText(b, "Hello from Silex smoke test\n50\nlogic works\ntrue\nfalse\n2\n1\n"));

    const references_command = b.addRunArtifact(executable);
    references_command.step.dependOn(&smoke_command.step);
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
    structures_command.expectStdOutEqual(hostText(b, "Ada\n35\n0\n10\n"));

    const defaults_command = b.addRunArtifact(executable);
    defaults_command.step.dependOn(&structures_command.step);
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
    collections_command.expectStdOutEqual(hostText(b, "1\n3\n20\n20\n1\nfalse\n1\n99\n3\n1\n3\n6\n2\n5\ntrue\n15\n15\n10\n30\n20\n40\n50\n40\n40\n500\n2\n3\n40\n600\n40\n700\n40\n800\n0\ntrue\n7\n17\n17\n7\n70\n7\n80\n2\n7\n9\n8\n17\n2\n17\n14\n11\n99\n11\n77\n2\n1\n"));

    const collection_take_last_empty_command = b.addRunArtifact(executable);
    collection_take_last_empty_command.step.dependOn(&collections_command.step);
    collection_take_last_empty_command.addArgs(&.{ "run", "Smokes/CollectionErrors/TakeLastEmpty.sx" });
    collection_take_last_empty_command.expectExitCode(1);
    collection_take_last_empty_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:12: runtime error: collection index ^1 is out of bounds for count 0\n", .{
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

    const collection_reverse_index_zero_command = b.addRunArtifact(executable);
    collection_reverse_index_zero_command.step.dependOn(&collection_index_out_of_bounds_command.step);
    collection_reverse_index_zero_command.addArgs(&.{ "run", "Smokes/CollectionErrors/ReverseIndexZero.sx" });
    collection_reverse_index_zero_command.expectExitCode(1);
    collection_reverse_index_zero_command.expectStdErrEqual(hostText(
        b,
        b.fmt("{s}:3:17: runtime error: collection index ^0 is out of bounds for count 3\n", .{
            b.pathFromRoot("Smokes/CollectionErrors/ReverseIndexZero.sx"),
        }),
    ));

    const iteration_command = b.addRunArtifact(executable);
    iteration_command.step.dependOn(&collection_reverse_index_zero_command.step);
    iteration_command.addArgs(&.{ "run", "Smokes/Iteration.sx" });
    iteration_command.expectStdOutEqual(hostText(b, "6\n2\n6\n2\n6\n3\n2\n1\n3\n8\n10\n"));

    const structure_equality_command = b.addRunArtifact(executable);
    structure_equality_command.step.dependOn(&iteration_command.step);
    structure_equality_command.addArgs(&.{ "run", "Smokes/StructureEquality.sx" });
    structure_equality_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\ntrue\n"));

    const integer_semantics_output = "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n";
    const integer_semantics_command = b.addRunArtifact(executable);
    integer_semantics_command.step.dependOn(&structure_equality_command.step);
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
    modules_command.step.dependOn(previous_integer_error_step);
    modules_command.addArgs(&.{ "run", "Smokes/Modules/silex.json" });
    modules_command.expectStdOutEqual(hostText(b, "true\ntrue\ntrue\n1\n2\nmodules\n"));

    const local_imports_command = b.addRunArtifact(executable);
    local_imports_command.step.dependOn(&modules_command.step);
    local_imports_command.addArgs(&.{ "run", "Smokes/LocalImports/Main.sx" });
    local_imports_command.expectStdOutEqual(hostText(b, "2\n3\n9\n3\n7\n"));

    const standard_library_output = "1065361344\n1152851127339773951\n508277857751731680\n6637030065269067181\n7345633470618427510\n8792660973527785782\n1082269761\n1152992998833853505\n1954144627577988649\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n1301891922867780472\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n";
    const standard_library_command = b.addRunArtifact(executable);
    standard_library_command.step.dependOn(&local_imports_command.step);
    standard_library_command.addArgs(&.{ "run", "Smokes/StandardLibrary/Main.sx" });
    standard_library_command.expectStdOutEqual(hostText(
        b,
        standard_library_output,
    ));

    const qualified_parent_alias_command = b.addRunArtifact(executable);
    qualified_parent_alias_command.step.dependOn(&standard_library_command.step);
    qualified_parent_alias_command.addArgs(&.{ "run", "Smokes/QualifiedImports/ParentAlias.sx" });
    qualified_parent_alias_command.expectStdOutEqual(hostText(b, "true\n"));

    const random_generator_source = b.getInstallPath(.prefix, "lib/silex/STD/Random/Generator.sx");
    const random_error_cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "Smokes/RandomErrors/IntOrder.sx", .message = "30:13: runtime error: get_int(minimum, maximum) requires minimum < maximum" },
        .{ .source = "Smokes/RandomErrors/IntWidth.sx", .message = "35:17: runtime error: get_int(minimum, maximum) requires an interval width that fits in int" },
        .{ .source = "Smokes/RandomErrors/FloatOrder.sx", .message = "59:13: runtime error: get_float(minimum, maximum) requires minimum < maximum" },
        .{ .source = "Smokes/RandomErrors/FloatFinite.sx", .message = "56:13: runtime error: get_float(minimum, maximum) requires finite bounds" },
        .{ .source = "Smokes/RandomErrors/FloatResolution.sx", .message = "66:13: runtime error: get_float(minimum, maximum) requires a representable value below maximum" },
    };
    var previous_random_error_step: *std.Build.Step = &qualified_parent_alias_command.step;
    for (random_error_cases) |case| {
        const command = b.addRunArtifact(executable);
        command.step.dependOn(previous_random_error_step);
        command.addArgs(&.{ "run", case.source });
        command.expectExitCode(1);
        command.expectStdErrEqual(hostText(
            b,
            b.fmt("{s}:{s}\n", .{ random_generator_source, case.message }),
        ));
        previous_random_error_step = &command.step;
    }

    const standard_library_manifest_command = b.addRunArtifact(executable);
    standard_library_manifest_command.step.dependOn(previous_random_error_step);
    standard_library_manifest_command.addArgs(&.{ "run", "Smokes/StandardLibrary/silex.json" });
    standard_library_manifest_command.expectStdOutEqual(hostText(
        b,
        standard_library_output,
    ));

    const distributed_native_runtime_command = b.addRunArtifact(executable);
    distributed_native_runtime_command.step.dependOn(&standard_library_manifest_command.step);
    distributed_native_runtime_command.addArgs(&.{ "run", "Smokes/DistributedNative/Main.sx" });
    distributed_native_runtime_command.expectStdOutEqual(hostText(b, "Distributed native runtime linked\ntrue\n10\n"));

    const local_native_runtime_command = b.addRunArtifact(executable);
    local_native_runtime_command.step.dependOn(&distributed_native_runtime_command.step);
    local_native_runtime_command.addArgs(&.{ "run", "Smokes/LocalNative/Main.sx" });
    local_native_runtime_command.expectStdOutEqual(hostText(b, "42\n"));

    const local_native_manifest_command = b.addRunArtifact(executable);
    local_native_manifest_command.step.dependOn(&local_native_runtime_command.step);
    local_native_manifest_command.addArgs(&.{ "run", "Smokes/LocalNative/project.json" });
    local_native_manifest_command.expectStdOutEqual(hostText(b, "42\n"));

    const portable_distributed_native_target_command = b.addRunArtifact(executable);
    portable_distributed_native_target_command.step.dependOn(&local_native_manifest_command.step);
    portable_distributed_native_target_command.addArgs(&.{
        "compile",
        "Smokes/DistributedNative/Main.sx",
        "--target",
        "riscv64-linux-musl",
        "-o",
        ".silex/portable-native-target/DistributedNative-riscv64-linux",
    });

    const distributed_module_collision_command = b.addRunArtifact(executable);
    distributed_module_collision_command.step.dependOn(&portable_distributed_native_target_command.step);
    distributed_module_collision_command.addArgs(&.{ "compile", "Tests/DistributedModules/Collision/Main.sx" });
    distributed_module_collision_command.expectExitCode(1);
    distributed_module_collision_command.expectStdErrEqual(
        "Tests/DistributedModules/Collision/Main.sx:1:1: error: module 'NativeRuntime' has multiple providers\n",
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
        "Created native module manifest: .zig-cache/module-init-smoke/Answer/Module.json\n" ++
            "Created native source: .zig-cache/module-init-smoke/Answer/Module.cpp\n",
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

    const smoke_step = b.step("smoke", "Compile and run the smoke program");
    smoke_step.dependOn(b.getInstallStep());
    smoke_step.dependOn(&native_package_smoke_command.step);

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

    const cross_distributed_native_smoke_command = b.addRunArtifact(executable);
    cross_distributed_native_smoke_command.step.dependOn(&cross_native_smoke_command.step);
    cross_distributed_native_smoke_command.addArgs(&.{
        "compile",
        "Smokes/DistributedNative/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/DistributedNative-x86_64-linux",
    });

    const cross_local_native_smoke_command = b.addRunArtifact(executable);
    cross_local_native_smoke_command.step.dependOn(&cross_distributed_native_smoke_command.step);
    cross_local_native_smoke_command.addArgs(&.{
        "compile",
        "Smokes/LocalNative/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-native-smoke/LocalNative-x86_64-linux",
    });

    const cross_native_smoke_step = b.step(
        "cross-native-smoke",
        "Cross-compile the native source smoke program for x86_64 Linux",
    );
    cross_native_smoke_step.dependOn(&cross_local_native_smoke_command.step);

    const distribution_options = b.addOptions();
    distribution_options.addOption([]const u8, "silex_version", silex_version);
    distribution_options.addOption([]const u8, "developer_zig", "");
    distribution_options.addOption([]const u8, "developer_standard_library_root", "");
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
    verify_distribution.expectStdOutEqual(hostText(b, standard_library_output));
    verify_distribution.step.dependOn(distribution_step);

    const distribution_check_step = b.step("dist-check", "Build and verify the self-contained host distribution");
    distribution_check_step.dependOn(&verify_distribution.step);
}

fn hostText(b: *std.Build, text: []const u8) []const u8 {
    if (b.graph.host.result.os.tag != .windows) return text;
    return std.mem.replaceOwned(u8, b.allocator, text, "\n", "\r\n") catch @panic("OOM");
}
