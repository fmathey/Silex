const std = @import("std");
const ModuleManifest = @import("ModuleManifest.zig");
const PackageLock = @import("PackageLock.zig");
const PackageVersion = @import("PackageVersion.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnvironMap = std.process.Environ.Map;

pub const Mode = union(enum) {
    normal,
    update_all,
    update_one: []const u8,
};

pub const Origin = union(enum) {
    root,
    path: []const u8,
    git: []const u8,
};

pub const Dependency = struct {
    name: []const u8,
    package_index: usize,
};

pub const Package = struct {
    name: ?[]const u8,
    version: ?[]const u8,
    root: []const u8,
    manifest_path: ?[]const u8,
    dependencies: []const Dependency,
    first_chain: []const u8,
    origin: Origin,
    requested_revision: ?[]const u8 = null,
    revision: ?[]const u8 = null,
};

pub const Graph = struct {
    packages: []const Package,
    explicit: bool,

    pub fn directDependency(self: Graph, package_index: usize, name: []const u8) ?usize {
        for (self.packages[package_index].dependencies) |dependency| {
            if (std.mem.eql(u8, dependency.name, name)) return dependency.package_index;
        }
        return null;
    }

    pub fn packageLabel(self: Graph, package_index: usize) []const u8 {
        return self.packages[package_index].name orelse "application";
    }

    pub fn findPackage(self: Graph, name: []const u8) ?usize {
        for (self.packages, 0..) |package, index| {
            if (package.name) |package_name| {
                if (std.mem.eql(u8, package_name, name)) return index;
            }
        }
        return null;
    }
};

const PathOrigin = struct {
    path: []const u8,
};

const GitOrigin = struct {
    git: []const u8,
    version: []const u8,
    rev: ?[]const u8 = null,
};

const DependencyOrigin = union(enum) {
    path: PathOrigin,
    git: GitOrigin,
};

const ResolvedPackage = struct {
    root: []const u8,
    manifest_path: []const u8,
    manifest: ModuleManifest.Manifest,
    origin: Origin,
    requested_revision: ?[]const u8 = null,
    revision: ?[]const u8 = null,
};

const VisitState = enum { visiting, done };

const Builder = struct {
    package: Package,
    dependencies: std.ArrayList(Dependency) = .empty,
    state: VisitState,
};

const Resolver = struct {
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    mode: Mode,
    lock: ?PackageLock.File = null,
    saw_dependency: bool = false,
    update_target_found: bool = false,
    packages: std.ArrayList(Builder) = .empty,

    fn resolveRoot(self: *Resolver, project_root: []const u8) !Graph {
        const canonical_root = Io.Dir.cwd().realPathFileAlloc(self.io, project_root, self.allocator) catch |err| {
            std.debug.print("silex: unable to resolve project root '{s}': {t}\n", .{ project_root, err });
            return error.Reported;
        };
        self.lock = PackageLock.loadOptional(self.allocator, self.io, canonical_root) catch |err| {
            std.debug.print("silex: invalid lockfile at '{s}/Silex.lock': {t}\n", .{ canonical_root, err });
            return error.Reported;
        };
        const manifest_path = try std.fs.path.join(self.allocator, &.{ canonical_root, "Module.json" });
        const root_manifest = loadOptionalManifest(self.allocator, self.io, manifest_path) catch |err| {
            std.debug.print("silex: invalid module manifest at '{s}': {t}\n", .{ manifest_path, err });
            return error.Reported;
        };
        const explicit = if (root_manifest) |manifest|
            manifest.name != null or manifest.version != null or manifest.dependencies != null
        else
            false;
        if (root_manifest) |manifest| try validateOptionalIdentity(manifest, manifest_path);

        try self.packages.append(self.allocator, .{
            .package = .{
                .name = if (root_manifest) |manifest| manifest.name else null,
                .version = if (root_manifest) |manifest| manifest.version else null,
                .root = canonical_root,
                .manifest_path = if (root_manifest != null) manifest_path else null,
                .dependencies = &.{},
                .first_chain = "application",
                .origin = .root,
            },
            .state = .visiting,
        });
        if (root_manifest) |manifest| {
            try self.resolveDependencies(0, manifest, &.{"application"});
        }
        self.packages.items[0].state = .done;

        switch (self.mode) {
            .update_one => |name| if (!self.update_target_found) {
                std.debug.print("silex: Git package '{s}' is not present in the dependency graph\n", .{name});
                return error.Reported;
            },
            else => {},
        }

        const packages = try self.allocator.alloc(Package, self.packages.items.len);
        for (self.packages.items, 0..) |*builder, index| {
            builder.package.dependencies = try builder.dependencies.toOwnedSlice(self.allocator);
            packages[index] = builder.package;
        }
        const graph: Graph = .{ .packages = packages, .explicit = explicit };
        if (self.saw_dependency) {
            const generated_lock = try makeLock(self.allocator, graph);
            if (self.lock == null or !locksEqual(self.lock.?, generated_lock)) {
                PackageLock.writeAtomic(self.allocator, self.io, canonical_root, generated_lock) catch |err| {
                    std.debug.print("silex: unable to write lockfile at '{s}/Silex.lock': {t}\n", .{ canonical_root, err });
                    return error.Reported;
                };
            }
        }
        return graph;
    }

    fn resolveDependencies(
        self: *Resolver,
        package_index: usize,
        manifest: ModuleManifest.Manifest,
        chain: []const []const u8,
    ) anyerror!void {
        const dependencies_value = manifest.dependencies orelse return;
        const dependencies = switch (dependencies_value) {
            .object => |object| object,
            else => {
                std.debug.print("silex: package {s} has a dependencies field that is not an object\n", .{
                    try formatChain(self.allocator, chain),
                });
                return error.Reported;
            },
        };
        var iterator = dependencies.iterator();
        while (iterator.next()) |entry| {
            self.saw_dependency = true;
            const dependency_name = entry.key_ptr.*;
            if (!validRootModuleName(dependency_name)) {
                std.debug.print("silex: package {s} declares invalid dependency name '{s}'\n", .{
                    try formatChain(self.allocator, chain),
                    dependency_name,
                });
                return error.Reported;
            }
            const requested_chain = try appendChain(self.allocator, chain, dependency_name);
            const origin = parseDependencyOrigin(self.allocator, entry.value_ptr.*) catch {
                std.debug.print("silex: dependency {s} must contain exactly one 'path' or 'git' origin\n", .{
                    try formatChain(self.allocator, requested_chain),
                });
                return error.Reported;
            };
            const resolved = switch (origin) {
                .path => |path_origin| try self.resolvePathDependency(
                    package_index,
                    dependency_name,
                    path_origin,
                    requested_chain,
                ),
                .git => |git_origin| try self.resolveGitDependency(
                    package_index,
                    dependency_name,
                    git_origin,
                    requested_chain,
                ),
            };
            const child_index = try self.resolvePackage(resolved, requested_chain);
            try self.packages.items[package_index].dependencies.append(self.allocator, .{
                .name = dependency_name,
                .package_index = child_index,
            });
        }
    }

    fn resolvePathDependency(
        self: *Resolver,
        package_index: usize,
        dependency_name: []const u8,
        origin: PathOrigin,
        chain: []const []const u8,
    ) !ResolvedPackage {
        if (origin.path.len == 0 or std.fs.path.isAbsolute(origin.path)) {
            std.debug.print("silex: dependency {s} path must be non-empty and relative\n", .{
                try formatChain(self.allocator, chain),
            });
            return error.Reported;
        }
        const package_root = self.packages.items[package_index].package.root;
        const joined = try std.fs.path.join(self.allocator, &.{ package_root, origin.path });
        const canonical_root = Io.Dir.cwd().realPathFileAlloc(self.io, joined, self.allocator) catch |err| {
            std.debug.print("silex: package path for {s} is unavailable at '{s}': {t}\n", .{
                try formatChain(self.allocator, chain),
                joined,
                err,
            });
            return error.Reported;
        };
        if (!try isDirectory(self.io, canonical_root)) {
            std.debug.print("silex: package path for {s} is not a directory: '{s}'\n", .{
                try formatChain(self.allocator, chain),
                canonical_root,
            });
            return error.Reported;
        }
        const manifest_path = try std.fs.path.join(self.allocator, &.{ canonical_root, "Module.json" });
        const manifest = ModuleManifest.load(self.allocator, self.io, manifest_path) catch |err| {
            std.debug.print("silex: invalid package manifest for {s} at '{s}': {t}\n", .{
                try formatChain(self.allocator, chain),
                manifest_path,
                err,
            });
            return error.Reported;
        };
        try validateReferencedIdentity(manifest, dependency_name, manifest_path, chain, self.allocator);
        return .{
            .root = canonical_root,
            .manifest_path = manifest_path,
            .manifest = manifest,
            .origin = .{ .path = canonical_root },
        };
    }

    fn resolveGitDependency(
        self: *Resolver,
        package_index: usize,
        dependency_name: []const u8,
        origin: GitOrigin,
        chain: []const []const u8,
    ) !ResolvedPackage {
        const constraint = PackageVersion.Constraint.parse(origin.version) catch {
            std.debug.print("silex: dependency {s} has unsupported version constraint '{s}'\n", .{
                try formatChain(self.allocator, chain),
                origin.version,
            });
            return error.Reported;
        };
        const declaring_root = self.packages.items[package_index].package.root;
        const canonical_origin = PackageLock.canonicalGitOrigin(self.allocator, self.io, declaring_root, origin.git) catch |err| {
            std.debug.print("silex: Git origin for {s} is unavailable: {t}\n", .{
                try formatChain(self.allocator, chain),
                err,
            });
            return error.Reported;
        };
        const refresh = switch (self.mode) {
            .normal => false,
            .update_all => origin.rev == null,
            .update_one => |name| block: {
                if (std.mem.eql(u8, name, dependency_name)) {
                    self.update_target_found = true;
                    break :block origin.rev == null;
                }
                break :block false;
            },
        };
        const locked = if (!refresh and self.lock != null) self.lock.?.find(dependency_name) else null;
        const locked_revision = if (locked) |package|
            if (package.origin.git != null and
                std.mem.eql(u8, package.origin.git.?, canonical_origin) and
                optionalEqual(package.requested_revision, origin.rev) and
                constraint.matches(package.version))
                package.revision
            else
                null
        else
            null;
        const checkout = PackageLock.materialize(
            self.allocator,
            self.io,
            self.environ_map,
            canonical_origin,
            locked_revision orelse origin.rev,
        ) catch |err| {
            const display_origin = try PackageLock.displayOrigin(self.allocator, canonical_origin);
            switch (err) {
                error.NetworkFailure => std.debug.print("silex: network error while resolving {s} from '{s}'\n", .{
                    try formatChain(self.allocator, chain), display_origin,
                }),
                error.RevisionNotFound => std.debug.print("silex: Git revision for {s} was not found in '{s}'\n", .{
                    try formatChain(self.allocator, chain), display_origin,
                }),
                error.CheckoutIncomplete => std.debug.print("silex: Git checkout for {s} from '{s}' is incomplete\n", .{
                    try formatChain(self.allocator, chain), display_origin,
                }),
                else => std.debug.print("silex: Git origin for {s} is unavailable at '{s}': {t}\n", .{
                    try formatChain(self.allocator, chain), display_origin, err,
                }),
            }
            return error.Reported;
        };
        const manifest_path = try std.fs.path.join(self.allocator, &.{ checkout.root, "Module.json" });
        const manifest = ModuleManifest.load(self.allocator, self.io, manifest_path) catch {
            std.debug.print("silex: Git checkout for {s} is incomplete: missing valid Module.json\n", .{
                try formatChain(self.allocator, chain),
            });
            return error.Reported;
        };
        try validateReferencedIdentity(manifest, dependency_name, manifest_path, chain, self.allocator);
        if (!constraint.matches(manifest.version.?)) {
            std.debug.print("silex: package {s} version '{s}' does not satisfy '{s}'\n", .{
                try formatChain(self.allocator, chain), manifest.version.?, origin.version,
            });
            return error.Reported;
        }
        return .{
            .root = checkout.root,
            .manifest_path = manifest_path,
            .manifest = manifest,
            .origin = .{ .git = canonical_origin },
            .requested_revision = origin.rev,
            .revision = checkout.revision,
        };
    }

    fn resolvePackage(
        self: *Resolver,
        resolved: ResolvedPackage,
        chain: []const []const u8,
    ) anyerror!usize {
        const canonical_root = resolved.root;
        const manifest_path = resolved.manifest_path;
        const manifest = resolved.manifest;
        const name = manifest.name.?;
        const version = manifest.version.?;
        if (self.findPackage(name)) |existing_index| {
            const existing = self.packages.items[existing_index];
            if (!std.mem.eql(u8, existing.package.root, canonical_root) or
                !std.mem.eql(u8, existing.package.version.?, version))
            {
                std.debug.print(
                    "silex: package '{s}' has multiple providers: {s} at '{s}' version '{s}', and {s} at '{s}' version '{s}'\n",
                    .{
                        name,
                        existing.package.first_chain,
                        existing.package.root,
                        existing.package.version.?,
                        try formatChain(self.allocator, chain),
                        canonical_root,
                        version,
                    },
                );
                return error.Reported;
            }
            if (existing.state == .visiting) {
                std.debug.print("silex: package dependency cycle: {s}\n", .{try formatChain(self.allocator, chain)});
                return error.Reported;
            }
            return existing_index;
        }

        const index = self.packages.items.len;
        try self.packages.append(self.allocator, .{
            .package = .{
                .name = name,
                .version = version,
                .root = canonical_root,
                .manifest_path = manifest_path,
                .dependencies = &.{},
                .first_chain = try formatChain(self.allocator, chain),
                .origin = resolved.origin,
                .requested_revision = resolved.requested_revision,
                .revision = resolved.revision,
            },
            .state = .visiting,
        });
        try self.resolveDependencies(index, manifest, chain);
        self.packages.items[index].state = .done;
        return index;
    }

    fn findPackage(self: *Resolver, name: []const u8) ?usize {
        for (self.packages.items, 0..) |builder, index| {
            if (builder.package.name) |existing_name| {
                if (std.mem.eql(u8, existing_name, name)) return index;
            }
        }
        return null;
    }
};

pub fn resolve(
    allocator: Allocator,
    io: Io,
    environ_map: *const EnvironMap,
    project_root: []const u8,
    mode: Mode,
) !Graph {
    var resolver: Resolver = .{
        .allocator = allocator,
        .io = io,
        .environ_map = environ_map,
        .mode = mode,
    };
    return resolver.resolveRoot(project_root);
}

fn parseDependencyOrigin(allocator: Allocator, value: std.json.Value) !DependencyOrigin {
    const path = std.json.parseFromValueLeaky(PathOrigin, allocator, value, .{
        .ignore_unknown_fields = false,
    }) catch null;
    if (path) |origin| return .{ .path = origin };
    const git = std.json.parseFromValueLeaky(GitOrigin, allocator, value, .{
        .ignore_unknown_fields = false,
    }) catch null;
    if (git) |origin| return .{ .git = origin };
    return error.InvalidDependencyOrigin;
}

fn makeLock(allocator: Allocator, graph: Graph) !PackageLock.File {
    const packages = try allocator.alloc(PackageLock.Package, graph.packages.len - 1);
    for (graph.packages[1..], packages) |package, *locked| {
        const dependencies = try allocator.alloc(PackageLock.Dependency, package.dependencies.len);
        for (package.dependencies, dependencies) |dependency, *locked_dependency| {
            const child = graph.packages[dependency.package_index];
            locked_dependency.* = .{ .name = dependency.name, .version = child.version.? };
        }
        const origin: PackageLock.Origin = switch (package.origin) {
            .root => unreachable,
            .path => |path| .{ .path = path },
            .git => |git| .{ .git = git },
        };
        locked.* = .{
            .name = package.name.?,
            .version = package.version.?,
            .origin = origin,
            .requested_revision = package.requested_revision,
            .revision = package.revision,
            .dependencies = dependencies,
        };
    }
    return .{ .format = 1, .packages = packages };
}

fn locksEqual(left: PackageLock.File, right: PackageLock.File) bool {
    if (left.format != right.format or left.packages.len != right.packages.len) return false;
    for (left.packages, right.packages) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or
            !std.mem.eql(u8, a.version, b.version) or
            !optionalEqual(a.origin.path, b.origin.path) or
            !optionalEqual(a.origin.git, b.origin.git) or
            !optionalEqual(a.requested_revision, b.requested_revision) or
            !optionalEqual(a.revision, b.revision) or
            a.dependencies.len != b.dependencies.len)
        {
            return false;
        }
        for (a.dependencies, b.dependencies) |a_dependency, b_dependency| {
            if (!std.mem.eql(u8, a_dependency.name, b_dependency.name) or
                !std.mem.eql(u8, a_dependency.version, b_dependency.version))
            {
                return false;
            }
        }
    }
    return true;
}

fn optionalEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn loadOptionalManifest(allocator: Allocator, io: Io, path: []const u8) !?ModuleManifest.Manifest {
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    if (stat.kind != .file) return error.InvalidModuleManifest;
    const manifest = try ModuleManifest.load(allocator, io, path);
    return manifest;
}

fn isDirectory(io: Io, path: []const u8) !bool {
    var directory = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    directory.close(io);
    return true;
}

fn validateOptionalIdentity(manifest: ModuleManifest.Manifest, path: []const u8) !void {
    if (manifest.name) |name| {
        if (!validRootModuleName(name)) {
            std.debug.print("silex: package name '{s}' in '{s}' is invalid\n", .{ name, path });
            return error.Reported;
        }
    }
    if (manifest.version) |version| {
        _ = std.SemanticVersion.parse(version) catch {
            std.debug.print("silex: package version '{s}' in '{s}' is not Semantic Versioning\n", .{ version, path });
            return error.Reported;
        };
    }
}

fn validateReferencedIdentity(
    manifest: ModuleManifest.Manifest,
    expected_name: []const u8,
    manifest_path: []const u8,
    chain: []const []const u8,
    allocator: Allocator,
) !void {
    const name = manifest.name orelse {
        std.debug.print("silex: package {s} at '{s}' is missing required name\n", .{
            try formatChain(allocator, chain),
            manifest_path,
        });
        return error.Reported;
    };
    if (!validRootModuleName(name) or !std.mem.eql(u8, name, expected_name)) {
        std.debug.print("silex: dependency '{s}' in {s} points to package named '{s}' at '{s}'\n", .{
            expected_name,
            try formatChain(allocator, chain),
            name,
            manifest_path,
        });
        return error.Reported;
    }
    const version = manifest.version orelse {
        std.debug.print("silex: package {s} at '{s}' is missing required version\n", .{
            try formatChain(allocator, chain),
            manifest_path,
        });
        return error.Reported;
    };
    _ = std.SemanticVersion.parse(version) catch {
        std.debug.print("silex: package {s} has invalid Semantic Version '{s}' at '{s}'\n", .{
            try formatChain(allocator, chain),
            version,
            manifest_path,
        });
        return error.Reported;
    };
}

fn validRootModuleName(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name[1..]) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '_') return false;
    }
    return true;
}

fn appendChain(allocator: Allocator, chain: []const []const u8, name: []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, chain.len + 1);
    @memcpy(result[0..chain.len], chain);
    result[chain.len] = name;
    return result;
}

fn formatChain(allocator: Allocator, chain: []const []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    for (chain, 0..) |name, index| {
        if (index > 0) try result.appendSlice(allocator, " -> ");
        try result.appendSlice(allocator, name);
    }
    return result.toOwnedSlice(allocator);
}

test "root module names and Semantic Versions are validated" {
    try std.testing.expect(validRootModuleName("Foundation"));
    try std.testing.expect(!validRootModuleName("Foundation.Core"));
    try std.testing.expect(!validRootModuleName("3D"));
    _ = try std.SemanticVersion.parse("1.2.3-alpha.1+build");
    try std.testing.expectError(error.InvalidVersion, std.SemanticVersion.parse("1.2"));
}
