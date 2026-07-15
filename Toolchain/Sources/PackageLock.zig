const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnvironMap = std.process.Environ.Map;

pub const Origin = struct {
    path: ?[]const u8 = null,
    git: ?[]const u8 = null,
};

pub const Dependency = struct {
    name: []const u8,
    version: []const u8,
};

pub const Package = struct {
    name: []const u8,
    version: []const u8,
    origin: Origin,
    requested_revision: ?[]const u8 = null,
    revision: ?[]const u8 = null,
    dependencies: []const Dependency,
};

pub const File = struct {
    format: u32,
    packages: []const Package,

    pub fn find(self: File, name: []const u8) ?Package {
        for (self.packages) |package| {
            if (std.mem.eql(u8, package.name, name)) return package;
        }
        return null;
    }
};

pub const Checkout = struct {
    root: []const u8,
    revision: []const u8,
};

pub fn loadOptional(allocator: Allocator, io: Io, project_root: []const u8) !?File {
    const path = try std.fs.path.join(allocator, &.{ project_root, "Silex.lock" });
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    if (stat.kind != .file) return error.InvalidLockfile;
    const contents = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
    const lock = std.json.parseFromSliceLeaky(File, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
    }) catch return error.InvalidLockfile;
    if (lock.format != 1) return error.InvalidLockfile;
    for (lock.packages) |package| {
        if ((package.origin.path == null) == (package.origin.git == null)) return error.InvalidLockfile;
        if ((package.origin.git == null) != (package.revision == null)) return error.InvalidLockfile;
    }
    return lock;
}

pub fn writeAtomic(allocator: Allocator, io: Io, project_root: []const u8, lock: File) !void {
    const contents = try std.json.Stringify.valueAlloc(allocator, lock, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    const with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{contents});
    const path = try std.fs.path.join(allocator, &.{ project_root, "Silex.lock" });
    const temporary_path = try std.fs.path.join(allocator, &.{ project_root, "Silex.lock.tmp" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = temporary_path, .data = with_newline });
    errdefer Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
    try Io.Dir.cwd().rename(temporary_path, .cwd(), path, io);
}

pub fn canonicalGitOrigin(
    allocator: Allocator,
    io: Io,
    declaring_root: []const u8,
    origin: []const u8,
) ![]const u8 {
    if (origin.len == 0) return error.InvalidGitOrigin;
    if (std.mem.containsAtLeast(u8, origin, 1, "://") or isScpOrigin(origin)) {
        return allocator.dupe(u8, std.mem.trimEnd(u8, origin, "/"));
    }
    const candidate = if (std.fs.path.isAbsolute(origin))
        origin
    else
        try std.fs.path.join(allocator, &.{ declaring_root, origin });
    return Io.Dir.cwd().realPathFileAlloc(io, candidate, allocator) catch error.GitOriginUnavailable;
}

pub fn displayOrigin(allocator: Allocator, origin: []const u8) ![]const u8 {
    const scheme = std.mem.indexOf(u8, origin, "://") orelse return origin;
    const authority_start = scheme + 3;
    const authority_end = std.mem.indexOfScalarPos(u8, origin, authority_start, '/') orelse origin.len;
    const credentials_end = std.mem.lastIndexOfScalar(u8, origin[authority_start..authority_end], '@');
    const query = std.mem.findAnyPos(u8, origin, authority_end, "?#") orelse origin.len;
    if (credentials_end) |relative_at| {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{
            origin[0..authority_start],
            origin[authority_start + relative_at + 1 .. query],
        });
    }
    return origin[0..query];
}

pub fn materialize(
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    origin: []const u8,
    requested_revision: ?[]const u8,
) !Checkout {
    const packages_root = try cacheRoot(allocator, environ_map);
    try Io.Dir.cwd().createDirPath(io, packages_root);

    if (requested_revision) |revision| {
        const destination = try checkoutPath(allocator, packages_root, origin, revision);
        if (try checkoutComplete(allocator, io, destination)) return .{ .root = destination, .revision = revision };
    }

    var random_bytes: [8]u8 = undefined;
    io.random(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);
    const temporary_name = try std.fmt.allocPrint(allocator, ".resolve-{s}", .{&random_hex});
    const temporary_path = try std.fs.path.join(allocator, &.{ packages_root, temporary_name });
    errdefer Io.Dir.cwd().deleteTree(io, temporary_path) catch {};

    const clone = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-c", "core.hooksPath=.silex-disabled-hooks", "clone", "--quiet", "--no-checkout", origin, temporary_path },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch return error.GitUnavailable;
    if (!termSucceeded(clone.term)) {
        return if (isNetworkOrigin(origin)) error.NetworkFailure else error.GitOriginUnavailable;
    }

    const revision = requested_revision orelse "origin/HEAD";
    const checkout = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", temporary_path, "-c", "core.hooksPath=.silex-disabled-hooks", "checkout", "--quiet", "--detach", revision },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch return error.GitUnavailable;
    if (!termSucceeded(checkout.term)) return error.RevisionNotFound;

    const head = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", temporary_path, "rev-parse", "HEAD" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch return error.GitUnavailable;
    if (!termSucceeded(head.term)) return error.CheckoutIncomplete;
    const exact_revision = try allocator.dupe(u8, std.mem.trim(u8, head.stdout, " \t\r\n"));
    if (exact_revision.len != 40 or !isHex(exact_revision)) return error.CheckoutIncomplete;

    const destination = try checkoutPath(allocator, packages_root, origin, exact_revision);
    if (try checkoutComplete(allocator, io, destination)) {
        Io.Dir.cwd().deleteTree(io, temporary_path) catch {};
        return .{ .root = destination, .revision = exact_revision };
    }
    Io.Dir.cwd().renamePreserve(temporary_path, .cwd(), destination, io) catch |err| switch (err) {
        error.PathAlreadyExists => {
            if (!try checkoutComplete(allocator, io, destination)) return error.CheckoutIncomplete;
        },
        error.PermissionDenied => try installCheckout(allocator, io, origin, exact_revision, destination),
        else => |other| return other,
    };
    const marker = try std.fs.path.join(allocator, &.{ destination, ".silex-checkout" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = marker, .data = exact_revision });
    Io.Dir.cwd().deleteTree(io, temporary_path) catch {};
    return .{ .root = destination, .revision = exact_revision };
}

fn installCheckout(
    allocator: Allocator,
    io: Io,
    origin: []const u8,
    revision: []const u8,
    destination: []const u8,
) !void {
    if (try directoryExists(io, destination)) {
        Io.Dir.cwd().deleteTree(io, destination) catch return error.CheckoutIncomplete;
    }
    const clone = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-c", "core.hooksPath=.silex-disabled-hooks", "clone", "--quiet", "--no-checkout", origin, destination },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch return error.GitUnavailable;
    if (!termSucceeded(clone.term)) {
        return if (isNetworkOrigin(origin)) error.NetworkFailure else error.GitOriginUnavailable;
    }
    const checkout = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", destination, "-c", "core.hooksPath=.silex-disabled-hooks", "checkout", "--quiet", "--detach", revision },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch return error.GitUnavailable;
    if (!termSucceeded(checkout.term)) return error.RevisionNotFound;
}

fn cacheRoot(allocator: Allocator, environ_map: *const EnvironMap) ![]const u8 {
    if (builtin.os.tag == .windows) {
        const local = environ_map.get("LOCALAPPDATA") orelse environ_map.get("USERPROFILE") orelse
            return error.UserCacheUnavailable;
        return std.fs.path.join(allocator, &.{ local, "Silex", "packages" });
    }
    const home = environ_map.get("HOME") orelse return error.UserCacheUnavailable;
    return std.fs.path.join(allocator, &.{ home, ".silex", "packages" });
}

fn checkoutPath(allocator: Allocator, packages_root: []const u8, origin: []const u8, revision: []const u8) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(origin);
    hasher.update(&.{0});
    hasher.update(revision);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    const key = std.fmt.bytesToHex(digest, .lower);
    return std.fs.path.join(allocator, &.{ packages_root, &key });
}

fn directoryExists(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

fn checkoutComplete(allocator: Allocator, io: Io, path: []const u8) !bool {
    if (!try directoryExists(io, path)) return false;
    const marker = try std.fs.path.join(allocator, &.{ path, ".silex-checkout" });
    const stat = Io.Dir.cwd().statFile(io, marker, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    return stat.kind == .file;
}

fn termSucceeded(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn isNetworkOrigin(origin: []const u8) bool {
    return std.mem.startsWith(u8, origin, "http://") or
        std.mem.startsWith(u8, origin, "https://") or
        std.mem.startsWith(u8, origin, "ssh://") or
        std.mem.startsWith(u8, origin, "git://") or
        isScpOrigin(origin);
}

fn isScpOrigin(origin: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, origin, ':') orelse return false;
    return std.mem.indexOfScalar(u8, origin[0..colon], '@') != null;
}

fn isHex(text: []const u8) bool {
    for (text) |byte| if (!std.ascii.isHex(byte)) return false;
    return true;
}

test "credentials and query parameters are removed from displayed Git origins" {
    const displayed = try displayOrigin(std.testing.allocator, "https://user:secret@example.com/Package.git?token=secret");
    defer std.testing.allocator.free(displayed);
    try std.testing.expectEqualStrings("https://example.com/Package.git", displayed);
}
