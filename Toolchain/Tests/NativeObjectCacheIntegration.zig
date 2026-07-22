const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.InvalidArguments;
    const silex = try Io.Dir.cwd().realPathFileAlloc(init.io, args[1], allocator);
    const root = args[2];
    const home = args[3];

    Io.Dir.cwd().deleteTree(init.io, root) catch {};
    Io.Dir.cwd().deleteTree(init.io, home) catch {};
    try Io.Dir.cwd().createDirPath(init.io, root);
    try Io.Dir.cwd().createDirPath(init.io, home);
    const canonical_root = try Io.Dir.cwd().realPathFileAlloc(init.io, root, allocator);
    const canonical_home = try Io.Dir.cwd().realPathFileAlloc(init.io, home, allocator);
    const vendor = try std.fs.path.join(allocator, &.{ canonical_root, "Vendor" });
    const first_app = try std.fs.path.join(allocator, &.{ canonical_root, "FirstApp" });
    const second_app = try std.fs.path.join(allocator, &.{ canonical_root, "SecondApp" });
    try createVendor(allocator, init.io, vendor, 40);
    try createApp(allocator, init.io, first_app, 2);
    try createApp(allocator, init.io, second_app, 2);

    var environment = try init.environ_map.clone(allocator);
    const silex_home = try std.fs.path.join(allocator, &.{ canonical_home, ".silex" });
    try environment.put("SILEX_HOME", silex_home);

    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        first_app,
        &.{ "compile", "Main.sx" },
        "Compiled native package Vendor",
    );
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        second_app,
        &.{ "compile", "Main.sx" },
        "Reused native package Vendor",
    );

    try writeFile(
        allocator,
        init.io,
        vendor,
        "Value.sx",
        "native func native_value() int\n\n" ++
            "public func value() int {\n" ++
            "    return native_value()\n" ++
            "}\n\n",
    );
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        first_app,
        &.{ "compile", "Main.sx" },
        "Reused native package Vendor",
    );

    try writeFile(
        allocator,
        init.io,
        vendor,
        "Value.sx",
        "native func native_value() int\n" ++
            "native func native_unused(value:int) int\n\n" ++
            "public func value() int {\n" ++
            "    return native_value()\n" ++
            "}\n\n",
    );
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        first_app,
        &.{ "compile", "Main.sx" },
        "Compiled native package Vendor",
    );

    try createApp(allocator, init.io, second_app, 3);
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        second_app,
        &.{ "compile", "Main.sx" },
        "Reused native package Vendor",
    );

    try writeHeader(allocator, init.io, vendor, 41);
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        first_app,
        &.{ "compile", "Main.sx" },
        "Compiled native package Vendor",
    );
    try expectCompile(
        allocator,
        init.io,
        &environment,
        silex,
        first_app,
        &.{ "compile", "Main.sx", "--target", "x86_64-linux-musl" },
        "Compiled native package Vendor",
    );

    try writeHeader(allocator, init.io, vendor, 42);
    var first = try spawnCompile(init.io, &environment, silex, first_app);
    var second = try spawnCompile(init.io, &environment, silex, second_app);
    try expectSuccess(try first.wait(init.io));
    try expectSuccess(try second.wait(init.io));

    const objects_root = try userObjectsRoot(allocator, canonical_home);
    try verifyPublishedEntries(allocator, init.io, objects_root);

    const clean = try std.process.run(allocator, init.io, .{
        .argv = &.{ silex, "clean" },
        .cwd = .{ .path = first_app },
        .environ_map = &environment,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    try expectSuccess(clean.term);
    const local_artifacts = try std.fs.path.join(allocator, &.{ first_app, ".silex" });
    if (Io.Dir.cwd().statFile(init.io, local_artifacts, .{})) |_| {
        return error.LocalCleanFailed;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |other| return other,
    }
    try verifyPublishedEntries(allocator, init.io, objects_root);
}

fn createVendor(allocator: Allocator, io: Io, root: []const u8, value: u8) !void {
    try writeFile(
        allocator,
        io,
        root,
        "@Module.json",
        "{\n" ++
            "  \"name\": \"Vendor\",\n" ++
            "  \"version\": \"1.0.0\",\n" ++
            "  \"native\": {\n" ++
            "    \"provides\": [\"VendorNative\"],\n" ++
            "    \"sources\": { \"c\": [\"Source.c\"] },\n" ++
            "    \"include_dirs\": [\"include\"]\n" ++
            "  }\n" ++
            "}\n",
    );
    try writeFile(
        allocator,
        io,
        root,
        "Value.sx",
        "native func native_value() int\n\n" ++
            "public func value() int {\n" ++
            "    return native_value()\n" ++
            "}\n",
    );
    try writeFile(
        allocator,
        io,
        root,
        "Source.c",
        "#include <Header.h>\n" ++
            "#include <SilexNative/Vendor.h>\n" ++
            "#include <stdint.h>\n\n" ++
            "int64_t silexNative_Vendor_Value_native_value(void) {\n" ++
            "    return VENDOR_VALUE;\n" ++
            "}\n",
    );
    try writeHeader(allocator, io, root, value);
}

fn writeHeader(allocator: Allocator, io: Io, root: []const u8, value: u8) !void {
    const contents = try std.fmt.allocPrint(allocator, "#pragma once\n#define VENDOR_VALUE {d}\n", .{value});
    try writeFile(allocator, io, root, "include/Header.h", contents);
}

fn createApp(allocator: Allocator, io: Io, root: []const u8, increment: u8) !void {
    try writeFile(
        allocator,
        io,
        root,
        "@Module.json",
        "{\n" ++
            "  \"dependencies\": {\n" ++
            "    \"Vendor\": { \"path\": \"../Vendor\" }\n" ++
            "  }\n" ++
            "}\n",
    );
    const source = try std.fmt.allocPrint(
        allocator,
        "use Vendor.Value as Vendor\n\nfunc main() {{\n    print(Vendor.value() + {d})\n}}\n",
        .{increment},
    );
    try writeFile(allocator, io, root, "Main.sx", source);
}

fn writeFile(
    allocator: Allocator,
    io: Io,
    root: []const u8,
    relative: []const u8,
    contents: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &.{ root, relative });
    if (std.fs.path.dirname(path)) |directory| try Io.Dir.cwd().createDirPath(io, directory);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = contents });
}

fn expectCompile(
    allocator: Allocator,
    io: Io,
    environment: *const std.process.Environ.Map,
    silex: []const u8,
    cwd: []const u8,
    arguments: []const []const u8,
    expected_operation: []const u8,
) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(allocator, silex);
    try argv.appendSlice(allocator, arguments);
    const result = try std.process.run(allocator, io, .{
        .argv = argv.items,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(16 * 1024 * 1024),
    });
    if (!succeeded(result.term) or std.mem.indexOf(u8, result.stderr, expected_operation) == null or
        std.mem.indexOf(u8, result.stderr, "Linked application") == null)
    {
        std.debug.print("Unexpected cache operation in {s}\nstdout: {s}\nstderr: {s}\n", .{
            cwd,
            result.stdout,
            result.stderr,
        });
        return error.UnexpectedCacheOperation;
    }
}

fn spawnCompile(
    io: Io,
    environment: *const std.process.Environ.Map,
    silex: []const u8,
    cwd: []const u8,
) !std.process.Child {
    return std.process.spawn(io, .{
        .argv = &.{ silex, "compile", "Main.sx" },
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

fn verifyPublishedEntries(allocator: Allocator, io: Io, objects_root: []const u8) !void {
    var format_directory = try Io.Dir.cwd().openDir(io, objects_root, .{ .iterate = true });
    defer format_directory.close(io);
    var target_iterator = format_directory.iterateAssumeFirstIteration();
    var entry_count: usize = 0;
    while (try target_iterator.next(io)) |target| {
        if (target.kind != .directory) return error.InvalidObjectCacheEntry;
        const target_path = try std.fs.path.join(allocator, &.{ objects_root, target.name });
        var target_directory = try Io.Dir.cwd().openDir(io, target_path, .{ .iterate = true });
        defer target_directory.close(io);
        var entry_iterator = target_directory.iterateAssumeFirstIteration();
        while (try entry_iterator.next(io)) |entry| {
            if (entry.kind != .directory or std.mem.startsWith(u8, entry.name, ".")) {
                return error.IncompleteObjectCachePublication;
            }
            const entry_path = try std.fs.path.join(allocator, &.{ target_path, entry.name });
            const marker_path = try std.fs.path.join(allocator, &.{ entry_path, ".complete" });
            const marker = try Io.Dir.cwd().readFileAlloc(io, marker_path, allocator, .limited(64));
            const object_count = try std.fmt.parseUnsigned(usize, std.mem.trim(u8, marker, " \t\r\n"), 10);
            for (0..object_count) |object_index| {
                const object_name = try std.fmt.allocPrint(allocator, "object-{d}.o", .{object_index});
                const object_path = try std.fs.path.join(allocator, &.{ entry_path, object_name });
                const stat = try Io.Dir.cwd().statFile(io, object_path, .{});
                if (stat.kind != .file) return error.IncompleteObjectCachePublication;
            }
            entry_count += 1;
        }
    }
    if (entry_count < 4) return error.MissingObjectCacheEntries;
}

fn userObjectsRoot(allocator: Allocator, home: []const u8) ![]const u8 {
    if (@import("builtin").os.tag == .windows) {
        return std.fs.path.join(allocator, &.{ home, "Silex", "cache", "objects", "v1" });
    }
    return std.fs.path.join(allocator, &.{ home, ".silex", "cache", "objects", "v1" });
}

fn expectSuccess(term: std.process.Child.Term) !void {
    if (!succeeded(term)) return error.ConcurrentCompileFailed;
}

fn succeeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}
