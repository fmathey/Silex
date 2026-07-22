const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const LockedOrigin = struct {
    path: ?[]const u8 = null,
    git: ?[]const u8 = null,
};

const LockedDependency = struct {
    name: []const u8,
    version: []const u8,
};

const LockedPackage = struct {
    name: []const u8,
    version: []const u8,
    origin: LockedOrigin,
    requested_revision: ?[]const u8 = null,
    revision: ?[]const u8 = null,
    dependencies: []const LockedDependency,
};

const LockFile = struct {
    format: u32,
    packages: []const LockedPackage,
};

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

    const utility_repo = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories", "Utility" });
    const foundation_repo = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories", "Foundation" });
    const incomplete_repo = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories", "Incomplete" });
    const mismatch_repo = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories", "Mismatch" });
    try createUtility(allocator, init.io, utility_repo);
    try createFoundation(allocator, init.io, foundation_repo, try fileUrl(allocator, utility_repo), "1.2.0", 2, "initial");
    try createIncomplete(allocator, init.io, incomplete_repo);
    try createMismatch(allocator, init.io, mismatch_repo);
    const initial_revision = try gitRevision(allocator, init.io, foundation_repo);

    const app = try createApp(allocator, init.io, canonical_root, "App", "Foundation", try fileUrl(allocator, foundation_repo), "^1.2", null);
    const second_app = try createApp(allocator, init.io, canonical_root, "SecondApp", "Foundation", try fileUrl(allocator, foundation_repo), "^1.2", null);
    const rev_app = try createApp(allocator, init.io, canonical_root, "RevApp", "Foundation", try fileUrl(allocator, foundation_repo), "^1.2", initial_revision);
    const invalid_rev_app = try createApp(allocator, init.io, canonical_root, "InvalidRevApp", "Foundation", try fileUrl(allocator, foundation_repo), "^1.2", "0000000000000000000000000000000000000000");
    const incomplete_app = try createApp(allocator, init.io, canonical_root, "IncompleteApp", "Incomplete", try fileUrl(allocator, incomplete_repo), "^1.0", null);
    const mismatch_app = try createApp(allocator, init.io, canonical_root, "MismatchApp", "Expected", try fileUrl(allocator, mismatch_repo), "^1.0", null);

    var environment = try init.environ_map.clone(allocator);
    try environment.put("HOME", canonical_home);
    try environment.put("LOCALAPPDATA", canonical_home);

    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "run", "Main.sx" }, 0, "42\n", null);
    const initial_lock = try readLock(allocator, init.io, app);
    try expectPackage(initial_lock, "Foundation", "1.2.0", initial_revision);
    try expectPackage(initial_lock, "Utility", "1.0.0", null);
    try expectDependency(initial_lock, "Foundation", "Utility", "1.0.0");

    try createFoundation(allocator, init.io, foundation_repo, try fileUrl(allocator, utility_repo), "1.3.0", 4, "compatible update");
    const packages_cache = try std.fs.path.join(allocator, &.{ canonical_home, ".silex", "packages" });
    try Io.Dir.cwd().deleteTree(init.io, packages_cache);
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "run", "Main.sx" }, 0, "42\n", null);
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "update", "Foundation" }, 0, "", "Updated Silex.lock\n");
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "run", "Main.sx" }, 0, "44\n", null);
    const updated_lock = try readLock(allocator, init.io, app);
    const updated_foundation = findPackage(updated_lock, "Foundation") orelse return error.MissingPackage;
    try std.testing.expectEqualStrings("1.3.0", updated_foundation.version);
    try std.testing.expect(!std.mem.eql(u8, initial_revision, updated_foundation.revision.?));

    try expectSilex(allocator, init.io, &environment, silex, app, &.{"update"}, 0, "", "Updated Silex.lock\n");
    const checkouts_before_second_app = try countCheckouts(allocator, init.io, packages_cache);
    try expectSilex(allocator, init.io, &environment, silex, second_app, &.{ "run", "Main.sx" }, 0, "44\n", null);
    try std.testing.expectEqual(checkouts_before_second_app, try countCheckouts(allocator, init.io, packages_cache));
    const second_lock = try readLock(allocator, init.io, second_app);
    try std.testing.expectEqualStrings(
        updated_foundation.revision.?,
        (findPackage(second_lock, "Foundation") orelse return error.MissingPackage).revision.?,
    );

    try expectSilex(allocator, init.io, &environment, silex, rev_app, &.{ "run", "Main.sx" }, 0, "42\n", null);
    try expectSilex(allocator, init.io, &environment, silex, rev_app, &.{ "update", "Foundation" }, 0, "", "Updated Silex.lock\n");
    const rev_lock = try readLock(allocator, init.io, rev_app);
    try expectPackage(rev_lock, "Foundation", "1.2.0", initial_revision);

    try expectSilex(allocator, init.io, &environment, silex, invalid_rev_app, &.{ "compile", "Main.sx" }, 1, "", "Git revision for application -> Foundation was not found");
    try expectSilex(allocator, init.io, &environment, silex, incomplete_app, &.{ "compile", "Main.sx" }, 1, "", "Git checkout for application -> Incomplete is incomplete");
    try expectSilex(allocator, init.io, &environment, silex, mismatch_app, &.{ "compile", "Main.sx" }, 1, "", "points to package named 'Actual'");

    const lock_path = try std.fs.path.join(allocator, &.{ app, "Silex.lock" });
    const before_failure = try Io.Dir.cwd().readFileAlloc(init.io, lock_path, allocator, .limited(4 * 1024 * 1024));
    try createFoundation(allocator, init.io, foundation_repo, try fileUrl(allocator, utility_repo), "2.0.0", 99, "incompatible update");
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "update", "Foundation" }, 1, "", "version '2.0.0' does not satisfy '^1.2'");
    const after_failure = try Io.Dir.cwd().readFileAlloc(init.io, lock_path, allocator, .limited(4 * 1024 * 1024));
    try std.testing.expectEqualStrings(before_failure, after_failure);
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "run", "Main.sx" }, 0, "44\n", null);

    const repositories = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories" });
    const offline_repositories = try std.fs.path.join(allocator, &.{ canonical_root, "Repositories.offline" });
    try Io.Dir.cwd().rename(repositories, .cwd(), offline_repositories, init.io);
    try expectSilex(allocator, init.io, &environment, silex, app, &.{ "run", "Main.sx" }, 0, "44\n", null);
}

fn createUtility(allocator: Allocator, io: Io, repository: []const u8) !void {
    try initializeRepository(allocator, io, repository);
    try writeFile(allocator, io, repository, "@Module.json", "{\n  \"name\": \"Utility\",\n  \"version\": \"1.0.0\"\n}\n");
    try writeFile(allocator, io, repository, "Base.sx", "public func base() int { return 40 }\n");
    try commitRepository(allocator, io, repository, "initial");
}

fn createFoundation(
    allocator: Allocator,
    io: Io,
    repository: []const u8,
    utility_url: []const u8,
    version: []const u8,
    increment: u8,
    message: []const u8,
) !void {
    if (!try directoryExists(io, repository)) try initializeRepository(allocator, io, repository);
    const quoted_url = try std.json.Stringify.valueAlloc(allocator, utility_url, .{});
    const manifest = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"name\": \"Foundation\",\n  \"version\": \"{s}\",\n  \"dependencies\": {{\n    \"Utility\": {{ \"git\": {s}, \"version\": \"^1.0\" }}\n  }}\n}}\n",
        .{ version, quoted_url },
    );
    const source = try std.fmt.allocPrint(
        allocator,
        "use Utility.Base as Utility\n\npublic func answer() int {{ return Utility.base() + {d} }}\n",
        .{increment},
    );
    try writeFile(allocator, io, repository, "@Module.json", manifest);
    try writeFile(allocator, io, repository, "API.sx", source);
    try commitRepository(allocator, io, repository, message);
}

fn createIncomplete(allocator: Allocator, io: Io, repository: []const u8) !void {
    try initializeRepository(allocator, io, repository);
    try writeFile(allocator, io, repository, "README.txt", "intentionally incomplete\n");
    try commitRepository(allocator, io, repository, "incomplete");
}

fn createMismatch(allocator: Allocator, io: Io, repository: []const u8) !void {
    try initializeRepository(allocator, io, repository);
    try writeFile(allocator, io, repository, "@Module.json", "{\n  \"name\": \"Actual\",\n  \"version\": \"1.0.0\"\n}\n");
    try commitRepository(allocator, io, repository, "mismatch");
}

fn createApp(
    allocator: Allocator,
    io: Io,
    root: []const u8,
    directory_name: []const u8,
    dependency_name: []const u8,
    git_url: []const u8,
    version: []const u8,
    revision: ?[]const u8,
) ![]const u8 {
    const directory = try std.fs.path.join(allocator, &.{ root, directory_name });
    try Io.Dir.cwd().createDirPath(io, directory);
    const quoted_url = try std.json.Stringify.valueAlloc(allocator, git_url, .{});
    const revision_field = if (revision) |rev|
        try std.fmt.allocPrint(allocator, ", \"rev\": \"{s}\"", .{rev})
    else
        "";
    const manifest = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"dependencies\": {{\n    \"{s}\": {{ \"git\": {s}, \"version\": \"{s}\"{s} }}\n  }}\n}}\n",
        .{ dependency_name, quoted_url, version, revision_field },
    );
    try writeFile(allocator, io, directory, "@Module.json", manifest);
    const source = if (std.mem.eql(u8, dependency_name, "Foundation"))
        "use Foundation.API as Foundation\n\nfunc main() void { print(Foundation.answer()) }\n"
    else
        "func main() void {}\n";
    try writeFile(allocator, io, directory, "Main.sx", source);
    return directory;
}

fn initializeRepository(allocator: Allocator, io: Io, repository: []const u8) !void {
    try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(repository).?);
    try expectGit(allocator, io, &.{ "git", "init", "--quiet", "--initial-branch=main", repository });
}

fn commitRepository(allocator: Allocator, io: Io, repository: []const u8, message: []const u8) !void {
    try expectGit(allocator, io, &.{ "git", "-C", repository, "add", "." });
    try expectGit(allocator, io, &.{
        "git",                              "-C",                    repository,
        "-c",                               "user.name=Silex Tests", "-c",
        "user.email=silex@example.invalid", "commit",                "--quiet",
        "--message",                        message,
    });
}

fn gitRevision(allocator: Allocator, io: Io, repository: []const u8) ![]const u8 {
    const result = try run(allocator, io, null, null, &.{ "git", "-C", repository, "rev-parse", "HEAD" });
    if (!succeeded(result.term)) return error.GitFailed;
    return allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"));
}

fn expectGit(allocator: Allocator, io: Io, arguments: []const []const u8) !void {
    const result = try run(allocator, io, null, null, arguments);
    if (!succeeded(result.term)) {
        std.debug.print("Git command failed: {s}\n", .{result.stderr});
        return error.GitFailed;
    }
}

fn expectSilex(
    allocator: Allocator,
    io: Io,
    environment: *const std.process.Environ.Map,
    executable: []const u8,
    cwd: []const u8,
    arguments: []const []const u8,
    expected_exit: u8,
    expected_stdout: []const u8,
    expected_stderr: ?[]const u8,
) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(allocator, executable);
    try argv.appendSlice(allocator, arguments);
    const result = try run(allocator, io, environment, cwd, argv.items);
    const exit_code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    if (exit_code != expected_exit or !std.mem.eql(u8, result.stdout, expected_stdout) or
        if (expected_stderr) |needle| std.mem.indexOf(u8, result.stderr, needle) == null else false)
    {
        std.debug.print(
            "Unexpected Silex result in {s}\nexit: {d}\nstdout: {s}\nstderr: {s}\n",
            .{ cwd, exit_code, result.stdout, result.stderr },
        );
        return error.UnexpectedSilexResult;
    }
}

fn run(
    allocator: Allocator,
    io: Io,
    environment: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    arguments: []const []const u8,
) !std.process.RunResult {
    return std.process.run(allocator, io, .{
        .argv = arguments,
        .cwd = if (cwd) |path| .{ .path = path } else .inherit,
        .environ_map = environment,
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(16 * 1024 * 1024),
    });
}

fn readLock(allocator: Allocator, io: Io, app: []const u8) !LockFile {
    const path = try std.fs.path.join(allocator, &.{ app, "Silex.lock" });
    const contents = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
    return std.json.parseFromSliceLeaky(LockFile, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
    });
}

fn findPackage(lock: LockFile, name: []const u8) ?LockedPackage {
    for (lock.packages) |package| if (std.mem.eql(u8, package.name, name)) return package;
    return null;
}

fn expectPackage(lock: LockFile, name: []const u8, version: []const u8, revision: ?[]const u8) !void {
    const package = findPackage(lock, name) orelse return error.MissingPackage;
    try std.testing.expectEqualStrings(version, package.version);
    if (revision) |expected| try std.testing.expectEqualStrings(expected, package.revision.?);
}

fn expectDependency(lock: LockFile, owner: []const u8, name: []const u8, version: []const u8) !void {
    const package = findPackage(lock, owner) orelse return error.MissingPackage;
    for (package.dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.name, name)) {
            try std.testing.expectEqualStrings(version, dependency.version);
            return;
        }
    }
    return error.MissingDependency;
}

fn writeFile(allocator: Allocator, io: Io, directory: []const u8, name: []const u8, contents: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ directory, name });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = contents });
}

fn fileUrl(allocator: Allocator, path: []const u8) ![]const u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    return if (std.mem.startsWith(u8, normalized, "/"))
        std.fmt.allocPrint(allocator, "file://{s}", .{normalized})
    else
        std.fmt.allocPrint(allocator, "file:///{s}", .{normalized});
}

fn directoryExists(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

fn countCheckouts(allocator: Allocator, io: Io, path: []const u8) !usize {
    var directory = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer directory.close(io);
    var count: usize = 0;
    var iterator = directory.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const marker = try std.fs.path.join(allocator, &.{ entry.name, ".silex-checkout" });
        const stat = directory.statFile(io, marker, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |other| return other,
        };
        if (stat.kind == .file) count += 1;
    }
    return count;
}

fn succeeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}
