const std = @import("std");
const Compiler = @import("Compiler.zig");
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
        try Io.File.stdout().writeStreamingAll(init.io, "Silex 0.6.1\n");
        return 0;
    }

    if (std.mem.eql(u8, args[1], "compile")) return compileCommand(allocator, init.io, args[2..]);
    if (std.mem.eql(u8, args[1], "run")) return runCommand(allocator, init.io, args[2..]);

    std.debug.print("silex: unknown command '{s}'\n\n{s}", .{ args[1], usage });
    return 1;
}

fn compileCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: missing source file\n\n{s}", .{usage});
        return 1;
    }

    const source_path = args[0];
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

    const compilation = try Compiler.compile(allocator, io, source_path, target, native_dependencies.items);
    const output = output_path orelse try Compiler.defaultOutputPath(
        allocator,
        compilation.project_path,
        compilation.program_name,
    );
    try Compiler.copyArtifact(io, compilation.executable_path, output);

    if (emit_cpp) {
        const generated_dir = try std.fs.path.join(allocator, &.{ compilation.project_path, ".silex", "generated" });
        try Io.Dir.cwd().createDirPath(io, generated_dir);
        const generated_name = try std.fmt.allocPrint(allocator, "{s}.cpp", .{compilation.program_name});
        const generated_path = try std.fs.path.join(allocator, &.{ generated_dir, generated_name });
        try Compiler.copyArtifact(io, compilation.cpp_path, generated_path);
        std.debug.print("Generated C++: {s}\n", .{generated_path});
    }

    const status = if (compilation.cache_hit) "Up to date" else "Compiled";
    std.debug.print("{s} {s} -> {s}\n", .{ status, source_path, output });
    return 0;
}

fn runCommand(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("silex: run expects a source file\n\n{s}", .{usage});
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

    const compilation = try Compiler.compile(
        allocator,
        io,
        args[0],
        TargetModule.Target.native(),
        native_dependencies.items,
    );
    const term = try Compiler.runProcess(io, &.{compilation.executable_path});
    return Compiler.exitCode(term);
}

fn isHelp(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h");
}

const usage =
    \\Usage:
    \\  silex compile <source.sx> [-o <executable>] [--emit-cpp]
    \\      [--target <arch-os-abi>] [--native <dependency.json>]
    \\  silex run <source.sx> [--native <dependency.json>]
    \\  silex --help
    \\  silex --version
    \\
;
