const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const CppGenerator = @import("CppGenerator.zig");
const ParserModule = @import("Parser.zig");
const Semantic = @import("Semantic.zig");
const TargetModule = @import("Target.zig");
const NativeDependency = @import("NativeDependency.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const NativeConfiguration = enum {
    unoptimized,
    optimized,

    fn optimizationFlag(self: NativeConfiguration) ?[]const u8 {
        return switch (self) {
            .unoptimized => null,
            .optimized => "-O2",
        };
    }
};

const default_native_configuration: NativeConfiguration = .optimized;

pub const Compilation = struct {
    executable_path: []const u8,
    cpp_path: []const u8,
    project_path: []const u8,
    program_name: []const u8,
    cache_hit: bool,
    target: TargetModule.Target,
};

pub fn compile(
    allocator: Allocator,
    io: Io,
    source_path: []const u8,
    target: TargetModule.Target,
    native_dependencies: []const NativeDependency.Dependency,
) !Compilation {
    if (!std.mem.endsWith(u8, source_path, ".sx")) {
        std.debug.print("silex: source file must use the .sx extension\n", .{});
        return error.Reported;
    }

    const source = Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        std.debug.print("silex: unable to read '{s}': {t}\n", .{ source_path, err });
        return error.Reported;
    };

    var parser = ParserModule.Parser.init(allocator, source);
    const ast = parser.parse() catch |err| switch (err) {
        error.InvalidSource => return report(source_path, parser.diagnostic.?),
        else => |other| return other,
    };

    var analyzer = Semantic.Analyzer.init(allocator);
    const program = analyzer.analyze(ast) catch |err| switch (err) {
        error.InvalidSource => return report(source_path, analyzer.diagnostic.?),
        else => |other| return other,
    };

    const cpp = try CppGenerator.generate(allocator, program);
    const project_path = "";
    const source_name = std.fs.path.basename(source_path);
    const program_name = source_name[0 .. source_name.len - 3];
    const target_name = try target.cacheName(allocator);
    if (target.cppBackendUnavailableReason()) |reason| {
        std.debug.print("silex: target '{s}' is unavailable: {s}\n", .{ target_name, reason });
        return error.Reported;
    }
    for (native_dependencies) |dependency| {
        if (!try dependency.supports(allocator, target)) {
            std.debug.print("silex: native dependency '{s}' does not support target '{s}'\n", .{
                dependency.name,
                target_name,
            });
            return error.Reported;
        }
    }
    const cache_key = try cacheKey(
        allocator,
        io,
        cpp,
        target,
        native_dependencies,
        default_native_configuration,
    );
    const cache_dir = try std.fs.path.join(allocator, &.{ project_path, ".silex", "cache", target_name, &cache_key });
    try Io.Dir.cwd().createDirPath(io, cache_dir);

    const cpp_path = try std.fs.path.join(allocator, &.{ cache_dir, "Generated.cpp" });
    const executable_path = try std.fs.path.join(allocator, &.{ cache_dir, program_name });
    const temporary_name = try std.fmt.allocPrint(allocator, "{s}.tmp", .{program_name});
    const temporary_executable_path = try std.fs.path.join(allocator, &.{ cache_dir, temporary_name });
    const cache_hit = try fileExists(io, executable_path);

    if (!cache_hit) {
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = cpp_path, .data = cpp });
        const zig_path = resolveZig(allocator, io) catch {
            std.debug.print(
                "silex: bundled Zig toolchain was not found; reinstall Silex or rebuild it for development\n",
                .{},
            );
            return error.Reported;
        };
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(allocator, &.{ zig_path, "c++" });
        if (target.zig_triple) |triple| try arguments.appendSlice(allocator, &.{ "-target", triple });
        if (default_native_configuration.optimizationFlag()) |flag| try arguments.append(allocator, flag);
        try arguments.appendSlice(allocator, &.{ "-std=c++23", "-Wno-nullability-completeness", cpp_path });
        for (native_dependencies) |dependency| try arguments.appendSlice(allocator, dependency.sources);
        try arguments.appendSlice(allocator, &.{ "-o", temporary_executable_path });

        const result = try std.process.run(allocator, io, .{
            .argv = arguments.items,
            .stdout_limit = .limited(16 * 1024 * 1024),
            .stderr_limit = .limited(16 * 1024 * 1024),
        });
        if (exitCode(result.term) != 0) {
            Io.Dir.cwd().deleteFile(io, temporary_executable_path) catch {};
            const backend_log_path = try std.fs.path.join(allocator, &.{ cache_dir, "Backend.log" });
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = backend_log_path, .data = result.stderr });
            std.debug.print(
                "silex: native compilation failed for target '{s}'; target support, SDKs, or native sources may be unavailable or incomplete\n",
                .{target_name},
            );
            std.debug.print("silex: backend details: {s}\n", .{backend_log_path});
            return error.Reported;
        }
        if (result.stdout.len > 0) try Io.File.stdout().writeStreamingAll(io, result.stdout);
        if (result.stderr.len > 0) try Io.File.stderr().writeStreamingAll(io, result.stderr);
        try Io.Dir.cwd().rename(temporary_executable_path, .cwd(), executable_path, io);
    }

    return .{
        .executable_path = executable_path,
        .cpp_path = cpp_path,
        .project_path = project_path,
        .program_name = program_name,
        .cache_hit = cache_hit,
        .target = target,
    };
}

pub fn runProcess(io: Io, arguments: []const []const u8) !std.process.Child.Term {
    var child = try std.process.spawn(io, .{
        .argv = arguments,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    defer child.kill(io);
    return child.wait(io);
}

pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

pub fn defaultOutputPath(
    allocator: Allocator,
    project_path: []const u8,
    program_name: []const u8,
) ![]const u8 {
    return std.fs.path.join(allocator, &.{ project_path, ".silex", "bin", program_name });
}

pub fn copyArtifact(io: Io, source_path: []const u8, destination_path: []const u8) !void {
    if (std.fs.path.dirname(destination_path)) |directory| {
        if (directory.len > 0) try Io.Dir.cwd().createDirPath(io, directory);
    }
    try Io.Dir.copyFile(.cwd(), source_path, .cwd(), destination_path, io, .{ .make_path = true });
}

fn report(source_path: []const u8, diagnostic: @import("Source.zig").Diagnostic) error{Reported} {
    std.debug.print("{s}:{d}:{d}: error: {s}\n", .{
        source_path,
        diagnostic.position.line,
        diagnostic.position.column,
        diagnostic.message,
    });
    return error.Reported;
}

fn cacheKey(
    allocator: Allocator,
    io: Io,
    cpp: []const u8,
    target: TargetModule.Target,
    native_dependencies: []const NativeDependency.Dependency,
    native_configuration: NativeConfiguration,
) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("silex-cache-v11\x00");
    hasher.update(@tagName(native_configuration));
    hasher.update("\x00");
    hasher.update(@tagName(target.cpu_arch));
    hasher.update("\x00");
    hasher.update(@tagName(target.os_tag));
    hasher.update("\x00");
    hasher.update(@tagName(target.abi));
    if (target.zig_triple) |triple| {
        hasher.update("\x00");
        hasher.update(triple);
    }
    hasher.update("\x00");
    hasher.update(cpp);
    for (native_dependencies) |dependency| {
        hasher.update("\x00");
        hasher.update(dependency.name);
        for (dependency.sources) |source_path| {
            const source = try Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(16 * 1024 * 1024));
            hasher.update("\x00");
            hasher.update(source_path);
            hasher.update("\x00");
            hasher.update(source);
        }
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn resolveZig(allocator: Allocator, io: Io) ![]const u8 {
    const executable_dir = try std.process.executableDirPathAlloc(io, allocator);
    const zig_name = if (builtin.os.tag == .windows) "zig.exe" else "zig";
    const bundled_path = try std.fs.path.resolve(allocator, &.{
        executable_dir,
        "..",
        "toolchain",
        "zig",
        zig_name,
    });
    if (try fileExists(io, bundled_path)) return bundled_path;

    if (build_options.developer_zig.len > 0 and try fileExists(io, build_options.developer_zig)) {
        return build_options.developer_zig;
    }
    return error.ZigToolchainNotFound;
}

fn fileExists(io: Io, path: []const u8) !bool {
    Io.Dir.cwd().access(io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    return true;
}

test "cache key follows generated content" {
    const target = TargetModule.Target.native();
    const first = try cacheKey(std.testing.allocator, std.testing.io, "first", target, &.{}, .optimized);
    const repeated = try cacheKey(std.testing.allocator, std.testing.io, "first", target, &.{}, .optimized);
    const changed = try cacheKey(std.testing.allocator, std.testing.io, "second", target, &.{}, .optimized);
    try std.testing.expectEqualSlices(u8, &first, &repeated);
    try std.testing.expect(!std.mem.eql(u8, &first, &changed));
}

test "cache key separates native configurations" {
    const target = TargetModule.Target.native();
    const optimized = try cacheKey(std.testing.allocator, std.testing.io, "program", target, &.{}, .optimized);
    const unoptimized = try cacheKey(std.testing.allocator, std.testing.io, "program", target, &.{}, .unoptimized);
    try std.testing.expect(!std.mem.eql(u8, &optimized, &unoptimized));
}

test "default native configuration enables optimization" {
    try std.testing.expectEqualStrings("-O2", default_native_configuration.optimizationFlag().?);
}

test "default output belongs to current project" {
    const output = try defaultOutputPath(std.testing.allocator, "", "Main");
    defer std.testing.allocator.free(output);
    const expected = try std.fmt.allocPrint(std.testing.allocator, ".silex{c}bin{c}Main", .{
        std.fs.path.sep,
        std.fs.path.sep,
    });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, output);
}
