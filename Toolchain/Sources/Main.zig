const std = @import("std");
const build_options = @import("build_options");
const Compiler = @import("Compiler.zig");
const Formatter = @import("Formatter.zig");
const Lint = @import("Lint.zig");
const Lsp = @import("Lsp.zig");
const ModuleInit = @import("ModuleInit.zig");
const PackageGraph = @import("PackageGraph.zig");
const TargetModule = @import("Target.zig");
const NativeDependency = @import("NativeDependency.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main(init: std.process.Init) u8 {
    return runCli(init) catch |err| {
        if (err != error.Reported) std.debug.print("silex: error: {t}\n", .{err});
        return 1;
    };
}

fn runCli(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len == 1 or (args.len == 2 and isHelp(args[1]))) {
        try Io.File.stdout().writeStreamingAll(init.io, usage);
        return 0;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
        try Io.File.stdout().writeStreamingAll(init.io, "Silex " ++ build_options.silex_version ++ "\n");
        return 0;
    }

    if (std.mem.eql(u8, args[1], "compile")) return compileCommand(allocator, init.io, init.environ_map, args[2..]);
    if (std.mem.eql(u8, args[1], "format")) return formatCommand(allocator, init.io, args[2..]);
    if (std.mem.eql(u8, args[1], "lint")) return lintCommand(allocator, init.io, args[2..]);
    if (std.mem.eql(u8, args[1], "run")) return runCommand(allocator, init.io, init.environ_map, args[2..]);
    if (std.mem.eql(u8, args[1], "update")) return updateCommand(allocator, init.io, init.environ_map, args[2..]);
    if (std.mem.eql(u8, args[1], "module")) return moduleCommand(allocator, init.io, args[2..]);
    if (std.mem.eql(u8, args[1], "clean")) return cleanCommand(allocator, init.io, args[2..]);
    if (std.mem.eql(u8, args[1], "lsp")) return Lsp.run(allocator, init.io, init.environ_map);

    std.debug.print("silex: unknown command '{s}'\n\n{s}", .{ args[1], usage });
    return 1;
}

fn lintCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: lint expects a source or project manifest\n", .{});
        return 1;
    }
    if (args.len != 1) {
        std.debug.print("silex: lint accepts exactly one input\n", .{});
        return 1;
    }
    return Lint.run(allocator, io, args[0]);
}

fn formatCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: format expects a source or project manifest\n", .{});
        return 1;
    }
    if (args.len > 2 or (args.len == 2 and !std.mem.eql(u8, args[1], "--check"))) {
        std.debug.print("silex: format accepts only the '--check' option after its input\n", .{});
        return 1;
    }
    const result = try Formatter.formatPath(allocator, io, args[0], args.len == 2);
    for (result.changed_paths) |path| {
        try Io.File.stdout().writeStreamingAll(io, path);
        try Io.File.stdout().writeStreamingAll(io, "\n");
    }
    return if (args.len == 2 and result.had_differences) 1 else 0;
}

fn moduleCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: module expects the 'init' command\n", .{});
        return 1;
    }
    if (!std.mem.eql(u8, args[0], "init")) {
        std.debug.print("silex: unknown module command '{s}'\n", .{args[0]});
        return 1;
    }
    return ModuleInit.run(allocator, io, args[1..]);
}

fn compileCommand(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: missing source or project manifest\n\n{s}", .{usage});
        return 1;
    }

    const input_path = args[0];
    var output_path: ?[]const u8 = null;
    var emit_cpp = false;
    var target = TargetModule.Target.native();
    var native_dependencies: std.ArrayList(NativeDependency.Dependency) = .empty;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--emit-cpp")) {
            emit_cpp = true;
        } else if (std.mem.eql(u8, args[index], "-o")) {
            index += 1;
            if (index == args.len) {
                std.debug.print("silex: expected an executable path after '-o'\n", .{});
                return 1;
            }
            output_path = args[index];
        } else if (std.mem.eql(u8, args[index], "--target")) {
            index += 1;
            if (index == args.len) {
                std.debug.print("silex: expected a target after '--target'\n", .{});
                return 1;
            }
            target = TargetModule.Target.parse(allocator, io, args[index]) catch |err| {
                std.debug.print("silex: target '{s}' is unavailable: {t}\n", .{ args[index], err });
                return 1;
            };
        } else if (std.mem.eql(u8, args[index], "--native")) {
            index += 1;
            if (index == args.len) {
                std.debug.print("silex: expected a dependency manifest after '--native'\n", .{});
                return 1;
            }
            const dependency = NativeDependency.load(allocator, io, args[index]) catch |err| {
                std.debug.print("silex: unable to load native dependency '{s}': {t}\n", .{ args[index], err });
                return 1;
            };
            try native_dependencies.append(allocator, dependency);
        } else {
            std.debug.print("silex: unknown option '{s}'\n", .{args[index]});
            return 1;
        }
    }

    const compilation = try compileWithProgress(
        allocator,
        io,
        environ_map,
        input_path,
        target,
        native_dependencies.items,
    );
    const output = output_path orelse try Compiler.defaultOutputPath(
        allocator,
        compilation.artifact_root,
        compilation.program_name,
    );
    try Compiler.copyArtifact(io, compilation.executable_path, output);

    if (emit_cpp) {
        const generated_dir = try std.fs.path.join(allocator, &.{ compilation.artifact_root, ".silex", "generated" });
        try Io.Dir.cwd().createDirPath(io, generated_dir);
        const generated_name = try std.fmt.allocPrint(allocator, "{s}.cpp", .{compilation.program_name});
        const generated_path = try std.fs.path.join(allocator, &.{ generated_dir, generated_name });
        try Compiler.copyArtifact(io, compilation.cpp_path, generated_path);
        std.debug.print("Generated C++: {s}\n", .{generated_path});
    }

    for (compilation.compiled_packages) |package| std.debug.print("Compiled native package {s}\n", .{package});
    for (compilation.reused_packages) |package| std.debug.print("Reused native package {s}\n", .{package});
    if (compilation.cache_hit) {
        std.debug.print("Up to date {s} -> {s}\n", .{ input_path, output });
    } else {
        std.debug.print("Linked application {s} -> {s}\n", .{ input_path, output });
    }
    return 0;
}

fn runCommand(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: run expects a source or project manifest\n\n{s}", .{usage});
        return 1;
    }

    var native_dependencies: std.ArrayList(NativeDependency.Dependency) = .empty;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (!std.mem.eql(u8, args[index], "--native")) {
            std.debug.print("silex: unknown option '{s}'\n", .{args[index]});
            return 1;
        }
        index += 1;
        if (index == args.len) {
            std.debug.print("silex: expected a dependency manifest after '--native'\n", .{});
            return 1;
        }
        const dependency = NativeDependency.load(allocator, io, args[index]) catch |err| {
            std.debug.print("silex: unable to load native dependency '{s}': {t}\n", .{ args[index], err });
            return 1;
        };
        try native_dependencies.append(allocator, dependency);
    }

    const compilation = try compileWithProgress(
        allocator,
        io,
        environ_map,
        args[0],
        TargetModule.Target.native(),
        native_dependencies.items,
    );
    const term = try Compiler.runProcess(io, &.{compilation.executable_path});
    if (runTerminationMessage(term)) |message| std.debug.print("{s}", .{message});
    return Compiler.exitCode(term);
}

fn compileWithProgress(
    allocator: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    input_path: []const u8,
    target: TargetModule.Target,
    native_dependencies: []const NativeDependency.Dependency,
) !Compiler.Compilation {
    const progress_name = try std.fmt.allocPrint(allocator, "Building {s}", .{input_path});
    const progress = std.Progress.start(io, .{ .root_name = progress_name });
    defer progress.end();
    return Compiler.compile(
        allocator,
        io,
        environ_map,
        input_path,
        target,
        native_dependencies,
        progress,
    );
}

fn updateCommand(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map, args: []const []const u8) !u8 {
    if (args.len > 1) {
        std.debug.print("silex: update accepts at most one package name\n\n{s}", .{usage});
        return 1;
    }
    const mode: PackageGraph.Mode = if (args.len == 0) .update_all else .{ .update_one = args[0] };
    _ = try PackageGraph.resolve(allocator, io, environ_map, ".", mode);
    std.debug.print("Updated Silex.lock\n", .{});
    return 0;
}

fn runTerminationMessage(term: std.process.Child.Term) ?[]const u8 {
    return switch (term) {
        .signal => |signal| if (signal == .SEGV)
            "silex: program crashed: invalid memory access\n"
        else
            null,
        else => null,
    };
}

fn cleanCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len != 0) {
        std.debug.print("silex: clean does not accept an input; it cleans the current directory\n\n{s}", .{usage});
        return 1;
    }

    const artifact_root = "";
    const cache_path = try std.fs.path.join(allocator, &.{ artifact_root, ".silex" });
    if (try Compiler.cleanArtifacts(allocator, io, artifact_root)) {
        std.debug.print("Cleaned {s}\n", .{cache_path});
    } else {
        std.debug.print("No cache to clean: {s}\n", .{cache_path});
    }
    return 0;
}

fn isHelp(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h");
}

test "run explains invalid memory access without reporting an intentional interrupt" {
    try std.testing.expectEqualStrings(
        "silex: program crashed: invalid memory access\n",
        runTerminationMessage(.{ .signal = .SEGV }).?,
    );
    try std.testing.expect(runTerminationMessage(.{ .signal = .INT }) == null);
    try std.testing.expect(runTerminationMessage(.{ .exited = 0 }) == null);
}

const usage =
    \\Usage:
    \\  silex compile <source.sx|project.json> [-o <executable>] [--emit-cpp]
    \\      [--target <arch-os-abi>] [--native <dependency.json>]
    \\  silex run <source.sx|project.json> [--native <dependency.json>]
    \\  silex format <source.sx|project.json> [--check]
    \\  silex lint <source.sx|project.json>
    \\  silex module init <directory> [--native]
    \\  silex update [package]
    \\  silex clean
    \\  silex lsp
    \\  silex --help
    \\  silex --version
    \\
;
