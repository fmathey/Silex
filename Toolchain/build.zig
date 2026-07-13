const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "developer_zig", b.graph.zig_exe);

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
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run the Silex toolchain");
    run_step.dependOn(&run_command.step);

    const tests = b.addTest(.{
        .root_module = module,
    });
    const test_command = b.addRunArtifact(tests);

    const invalid_command = b.addRunArtifact(executable);
    invalid_command.addArgs(&.{ "compile", "Tests/InvalidArithmetic.sx" });
    invalid_command.expectExitCode(1);
    invalid_command.expectStdErrEqual(
        "Tests/InvalidArithmetic.sx:2:19: error: arithmetic operator requires numeric operands, found 'str' and 'int'\n",
    );

    const immutable_assignment_command = b.addRunArtifact(executable);
    immutable_assignment_command.addArgs(&.{ "compile", "Tests/InvalidImmutableAssignment.sx" });
    immutable_assignment_command.expectExitCode(1);
    immutable_assignment_command.expectStdErrEqual(
        "Tests/InvalidImmutableAssignment.sx:3:5: error: cannot assign to immutable variable 'count'\n",
    );

    const invalid_condition_command = b.addRunArtifact(executable);
    invalid_condition_command.addArgs(&.{ "compile", "Tests/InvalidCondition.sx" });
    invalid_condition_command.expectExitCode(1);
    invalid_condition_command.expectStdErrEqual(
        "Tests/InvalidCondition.sx:2:9: error: expected 'bool', found 'int'\n",
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

    const invalid_arguments_command = b.addRunArtifact(executable);
    invalid_arguments_command.addArgs(&.{ "compile", "Tests/InvalidArguments.sx" });
    invalid_arguments_command.expectExitCode(1);
    invalid_arguments_command.expectStdErrEqual(
        "Tests/InvalidArguments.sx:2:18: error: argument 2 of 'add' expects 'int', found 'bool'\n",
    );

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
        "Tests/InvalidCompoundAssignment.sx:3:5: error: operator '+=' requires a numeric target and compatible value, found 'str' and 'str'\n",
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
    backend_discovered_target_failure_command.expectStdErrMatch("silex: backend details: .silex/cache/x86_64-linux-musl/");

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

    const test_step = b.step("test", "Run the toolchain tests");
    test_step.dependOn(&test_command.step);
    test_step.dependOn(&invalid_command.step);
    test_step.dependOn(&immutable_assignment_command.step);
    test_step.dependOn(&invalid_condition_command.step);
    test_step.dependOn(&invalid_logical_command.step);
    test_step.dependOn(&invalid_while_command.step);
    test_step.dependOn(&missing_separator_command.step);
    test_step.dependOn(&missing_type_command.step);
    test_step.dependOn(&missing_return_command.step);
    test_step.dependOn(&invalid_arguments_command.step);
    test_step.dependOn(&unknown_struct_field_command.step);
    test_step.dependOn(&immutable_struct_field_command.step);
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
    test_step.dependOn(&invalid_target_command.step);
    test_step.dependOn(&unavailable_cpp_target_command.step);
    test_step.dependOn(&backend_discovered_target_failure_command.step);
    test_step.dependOn(&unsupported_native_target_command.step);

    const smoke_command = b.addRunArtifact(executable);
    smoke_command.addArgs(&.{ "run", "Smokes/Main.sx" });
    smoke_command.expectStdOutEqual("Hello from Silex smoke test\n50\nlogic works\ntrue\nfalse\n2\n1\n");

    const boolean_condition_command = b.addRunArtifact(executable);
    boolean_condition_command.addArgs(&.{ "run", "Smokes/BooleanCondition.sx" });
    boolean_condition_command.expectStdOutEqual("true branch\n");

    const compact_command = b.addRunArtifact(executable);
    compact_command.addArgs(&.{ "run", "Smokes/Compact.sx" });
    compact_command.expectStdOutEqual("50\n");

    const structures_command = b.addRunArtifact(executable);
    structures_command.addArgs(&.{ "run", "Smokes/Structures.sx" });
    structures_command.expectStdOutEqual("Ada\n32\n0\n");

    const defaults_command = b.addRunArtifact(executable);
    defaults_command.addArgs(&.{ "run", "Smokes/Defaults.sx" });
    defaults_command.expectStdOutEqual("Ada\nfalse\n1\n7\n0\n\nBob\ntrue\n4\n5\n");

    const floats_command = b.addRunArtifact(executable);
    floats_command.addArgs(&.{ "run", "Smokes/Floats.sx" });
    floats_command.expectStdOutEqual("3\n-2.5\n2.5\n2.5\n2\n1.5\ntrue\n2\n");

    const numeric_types_command = b.addRunArtifact(executable);
    numeric_types_command.addArgs(&.{ "run", "Smokes/NumericTypes.sx" });
    numeric_types_command.expectStdOutEqual("-128\n32767\n2147483647\n-9223372036854775808\n255\n65535\n4294967295\n18446744073709551615\n42\n1.5\n2.25\n0\n12\n");

    const integer_overflow_command = b.addRunArtifact(executable);
    integer_overflow_command.addArgs(&.{ "run", "Smokes/IntegerOverflow.sx" });
    integer_overflow_command.expectExitCode(1);
    integer_overflow_command.expectStdErrEqual("silex: runtime error: integer overflow in addition\n");

    const native_source_command = b.addRunArtifact(executable);
    native_source_command.addArgs(&.{
        "run",
        "Smokes/Native/Main.sx",
        "--native",
        "Smokes/Native/dependency.json",
    });
    native_source_command.expectStdOutEqual("Native wrapper initialized\nSilex with native source\n");

    const smoke_step = b.step("smoke", "Compile and run the smoke program");
    smoke_step.dependOn(&smoke_command.step);
    smoke_step.dependOn(&boolean_condition_command.step);
    smoke_step.dependOn(&compact_command.step);
    smoke_step.dependOn(&structures_command.step);
    smoke_step.dependOn(&defaults_command.step);
    smoke_step.dependOn(&floats_command.step);
    smoke_step.dependOn(&numeric_types_command.step);
    smoke_step.dependOn(&integer_overflow_command.step);
    smoke_step.dependOn(&native_source_command.step);

    const cross_smoke_command = b.addRunArtifact(executable);
    cross_smoke_command.addArgs(&.{
        "compile",
        "Smokes/Main.sx",
        "--target",
        "x86_64-linux-musl",
        "-o",
        ".silex/cross-smoke/Main-x86_64-linux",
    });

    const cross_smoke_step = b.step("cross-smoke", "Cross-compile the smoke program for x86_64 Linux");
    cross_smoke_step.dependOn(&cross_smoke_command.step);

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

    const cross_native_smoke_step = b.step(
        "cross-native-smoke",
        "Cross-compile the native source smoke program for x86_64 Linux",
    );
    cross_native_smoke_step.dependOn(&cross_native_smoke_command.step);

    const distribution_options = b.addOptions();
    distribution_options.addOption([]const u8, "developer_zig", "");
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
    const distribution_name = b.fmt("silex-0.6.1-{s}-{s}", .{
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

    const distribution_step = b.step("dist", "Build a self-contained distribution for this host");
    distribution_step.dependOn(&install_silex.step);
    distribution_step.dependOn(&install_zig.step);
    distribution_step.dependOn(&install_zig_lib.step);

    const distribution_check_files = b.addWriteFiles();
    _ = distribution_check_files.addCopyFile(b.path("Smokes/Main.sx"), "Main.sx");
    const installed_silex = b.getInstallPath(.prefix, b.fmt("{s}/bin/{s}", .{ distribution_root, silex_name }));
    const verify_distribution = b.addSystemCommand(&.{ installed_silex, "run", "Main.sx" });
    verify_distribution.setCwd(distribution_check_files.getDirectory());
    verify_distribution.setEnvironmentVariable("PATH", "");
    verify_distribution.expectStdOutEqual("Hello from Silex smoke test\n50\nlogic works\ntrue\nfalse\n2\n1\n");
    verify_distribution.step.dependOn(distribution_step);

    const distribution_check_step = b.step("dist-check", "Build and verify the self-contained host distribution");
    distribution_check_step.dependOn(&verify_distribution.step);
}
