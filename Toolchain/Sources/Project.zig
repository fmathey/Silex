const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Module = struct {
    name: []const u8,
    sources: []const []const u8,
    package_index: usize = 0,
    native_runtime_name: ?[]const u8 = null,
    module_manifest_path: ?[]const u8 = null,
    native_module_directory: ?[]const u8 = null,
    origin: ModuleOrigin = .application,
};

pub const ModuleOrigin = enum { application, local, package, distributed };

pub const Project = struct {
    program_name: []const u8,
    target_module: usize,
    modules: []const Module,
    single_file: bool,
};

const Manifest = struct {
    target: []const u8,
    modules: []const ManifestModule,
};

const ManifestModule = struct {
    name: []const u8,
    sources: []const []const u8,
};

pub fn load(allocator: Allocator, io: Io, input_path: []const u8) !Project {
    if (std.mem.endsWith(u8, input_path, ".sx")) {
        const filename = std.fs.path.basename(input_path);
        return .{
            .program_name = filename[0 .. filename.len - 3],
            .target_module = 0,
            .modules = try allocator.dupe(Module, &.{.{
                .name = filename[0 .. filename.len - 3],
                .sources = try allocator.dupe([]const u8, &.{input_path}),
            }}),
            .single_file = true,
        };
    }

    if (!std.mem.endsWith(u8, input_path, ".json")) {
        std.debug.print("silex: input must be a .sx source or .json project manifest\n", .{});
        return error.Reported;
    }
    const contents = Io.Dir.cwd().readFileAlloc(io, input_path, allocator, .limited(1024 * 1024)) catch |err| {
        std.debug.print("silex: unable to read project manifest '{s}': {t}\n", .{ input_path, err });
        return error.Reported;
    };
    const manifest = std.json.parseFromSliceLeaky(Manifest, allocator, contents, .{
        .ignore_unknown_fields = false,
    }) catch |err| {
        std.debug.print("silex: invalid project manifest '{s}': {t}\n", .{ input_path, err });
        return error.Reported;
    };
    if (!validModuleName(manifest.target) or manifest.modules.len == 0) {
        std.debug.print("silex: project manifest requires a valid target module and at least one module\n", .{});
        return error.Reported;
    }

    const manifest_dir = inputDirectory(input_path);
    var modules: std.ArrayList(Module) = .empty;
    var target_module: ?usize = null;
    for (manifest.modules) |module| {
        if (!validModuleName(module.name) or module.sources.len == 0) {
            std.debug.print("silex: module '{s}' requires a valid name and at least one source\n", .{module.name});
            return error.Reported;
        }
        if (isReservedModule(module.name)) {
            std.debug.print("silex: module '{s}' is reserved for the distributed library\n", .{module.name});
            return error.Reported;
        }
        if (findModule(modules.items, module.name)) |existing_index| {
            if (modules.items[existing_index].sources.len != 0) {
                std.debug.print("silex: module '{s}' has multiple providers\n", .{module.name});
                return error.Reported;
            }
        }
        var sources: std.ArrayList([]const u8) = .empty;
        var unit_names: std.ArrayList([]const u8) = .empty;
        for (module.sources) |relative_source| {
            if (!std.mem.endsWith(u8, relative_source, ".sx")) {
                std.debug.print("silex: module source '{s}' must use the .sx extension\n", .{relative_source});
                return error.Reported;
            }
            const basename = std.fs.path.basename(relative_source);
            const unit_name = basename[0 .. basename.len - ".sx".len];
            for (unit_names.items) |existing_name| {
                if (std.mem.eql(u8, existing_name, unit_name)) {
                    std.debug.print("silex: module '{s}' has multiple source units named '{s}'\n", .{
                        module.name,
                        unit_name,
                    });
                    return error.Reported;
                }
            }
            try unit_names.append(allocator, unit_name);
            const source_path = try std.fs.path.join(allocator, &.{ manifest_dir, relative_source });
            for (modules.items) |existing| for (existing.sources) |existing_source| {
                if (std.mem.eql(u8, existing_source, source_path)) {
                    std.debug.print("silex: source '{s}' belongs to more than one module\n", .{source_path});
                    return error.Reported;
                }
            };
            for (sources.items) |existing_source| {
                if (std.mem.eql(u8, existing_source, source_path)) {
                    std.debug.print("silex: source '{s}' is listed more than once\n", .{source_path});
                    return error.Reported;
                }
            }
            try sources.append(allocator, source_path);
        }
        try appendModuleParents(allocator, &modules, module.name);
        const module_sources = try sources.toOwnedSlice(allocator);
        const module_index = if (findModule(modules.items, module.name)) |existing_index| block: {
            modules.items[existing_index].sources = module_sources;
            break :block existing_index;
        } else block: {
            const index = modules.items.len;
            try modules.append(allocator, .{ .name = module.name, .sources = module_sources });
            break :block index;
        };
        if (std.mem.eql(u8, module.name, manifest.target)) target_module = module_index;
    }
    if (target_module == null) {
        std.debug.print("silex: target module '{s}' has no provider\n", .{manifest.target});
        return error.Reported;
    }
    const program_name = std.fs.path.extension(manifest.target);
    return .{
        .program_name = if (program_name.len > 0) program_name[1..] else manifest.target,
        .target_module = target_module.?,
        .modules = try modules.toOwnedSlice(allocator),
        .single_file = false,
    };
}

fn appendModuleParents(allocator: Allocator, modules: *std.ArrayList(Module), name: []const u8) !void {
    var offset: usize = 0;
    while (std.mem.indexOfScalarPos(u8, name, offset, '.')) |separator| {
        const parent = name[0..separator];
        if (findModule(modules.items, parent) == null) {
            try modules.append(allocator, .{ .name = parent, .sources = &.{} });
        }
        offset = separator + 1;
    }
}

fn findModule(modules: []const Module, name: []const u8) ?usize {
    for (modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, name)) return index;
    }
    return null;
}

fn inputDirectory(input_path: []const u8) []const u8 {
    const directory = std.fs.path.dirname(input_path) orelse return "";
    return if (std.mem.eql(u8, directory, ".")) "" else directory;
}

fn validModuleName(name: []const u8) bool {
    if (name.len == 0) return false;
    var segment_start = true;
    for (name) |character| {
        if (character == '.') {
            if (segment_start) return false;
            segment_start = true;
        } else if (segment_start) {
            if (!std.ascii.isAlphabetic(character) and character != '_') return false;
            segment_start = false;
        } else if (!std.ascii.isAlphanumeric(character) and character != '_') return false;
    }
    return !segment_start;
}

fn isReservedModule(name: []const u8) bool {
    return isReservedRoot(name, "STD") or isReservedRoot(name, "Silex");
}

fn isReservedRoot(name: []const u8, root: []const u8) bool {
    return std.mem.eql(u8, name, root) or
        (std.mem.startsWith(u8, name, root) and name.len > root.len and name[root.len] == '.');
}

test "validate logical module names" {
    try std.testing.expect(validModuleName("NK.Window"));
    try std.testing.expect(!validModuleName("NK..Window"));
    try std.testing.expect(!validModuleName("2D.Window"));
}

test "manifest source paths follow the input directory" {
    try std.testing.expectEqualStrings("Sandbox", inputDirectory("Sandbox/Main.sx"));
    try std.testing.expectEqualStrings("Sandbox", inputDirectory("Sandbox/silex.json"));
    try std.testing.expectEqualStrings("", inputDirectory("Main.sx"));
    try std.testing.expectEqualStrings("", inputDirectory("./Main.sx"));
}

test "module parents are inferred from dotted manifest names" {
    var modules: std.ArrayList(Module) = .empty;
    defer modules.deinit(std.testing.allocator);

    try appendModuleParents(std.testing.allocator, &modules, "NK.Rendering.Window");

    try std.testing.expectEqual(@as(usize, 2), modules.items.len);
    try std.testing.expectEqualStrings("NK", modules.items[0].name);
    try std.testing.expectEqualStrings("NK.Rendering", modules.items[1].name);
    try std.testing.expectEqual(@as(usize, 0), modules.items[0].sources.len);
}
