const std = @import("std");
const NativeDependency = @import("NativeDependency.zig");
const TargetModule = @import("Target.zig");

const Allocator = std.mem.Allocator;

pub fn compileArguments(
    allocator: Allocator,
    zig_path: []const u8,
    target: TargetModule.Target,
    compiler_flags: []const []const u8,
    runtime: NativeDependency.ModuleRuntime,
    source: NativeDependency.SourceFile,
    output_path: ?[]const u8,
) ![]const []const u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    const driver = switch (source.kind) {
        .c, .objective_c => "cc",
        .cpp, .objective_cpp => "c++",
    };
    try arguments.appendSlice(allocator, &.{ zig_path, driver });
    if (target.zig_triple) |triple| try arguments.appendSlice(allocator, &.{ "-target", triple });
    try arguments.appendSlice(allocator, compiler_flags);
    if (source.kind == .cpp or source.kind == .objective_cpp) {
        try arguments.appendSlice(allocator, &.{ "-std=c++23", "-Wno-nullability-completeness" });
    }
    for (runtime.include_dirs) |include_dir| {
        try arguments.append(allocator, try std.fmt.allocPrint(allocator, "-I{s}", .{include_dir}));
    }
    for (runtime.defines) |define| {
        try arguments.append(allocator, try std.fmt.allocPrint(allocator, "-D{s}={s}", .{ define.name, define.value }));
    }
    try arguments.appendSlice(allocator, &.{ "-c", source.path });
    if (output_path) |output| try arguments.appendSlice(allocator, &.{ "-o", output });
    return arguments.toOwnedSlice(allocator);
}

test "native command preserves the C++ compilation contract" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Probe",
        .module_directory = ".",
        .manifest_path = "@Module.json",
        .origin = .project,
        .sources = &.{},
        .include_dirs = &.{"Includes"},
        .defines = &.{.{ .name = "MODE", .value = "editor" }},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const arguments = try compileArguments(
        arena.allocator(),
        "/distribution/toolchain/zig/zig",
        TargetModule.Target.native(),
        &.{"-O2"},
        runtime,
        .{ .kind = .cpp, .path = "Source.cpp" },
        "Source.o",
    );
    const expected: []const []const u8 = &.{
        "/distribution/toolchain/zig/zig",
        "c++",
        "-O2",
        "-std=c++23",
        "-Wno-nullability-completeness",
        "-IIncludes",
        "-DMODE=editor",
        "-c",
        "Source.cpp",
        "-o",
        "Source.o",
    };
    try std.testing.expectEqual(expected.len, arguments.len);
    for (expected, arguments) |expected_argument, argument| {
        try std.testing.expectEqualStrings(expected_argument, argument);
    }
}
