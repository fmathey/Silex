const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Module = struct {
    name: []const u8,
    sources: []const []const u8,
};

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
    for (manifest.modules, 0..) |module, module_index| {
        if (!validModuleName(module.name) or module.sources.len == 0) {
            std.debug.print("silex: module '{s}' requires a valid name and at least one source\n", .{module.name});
            return error.Reported;
        }
        for (modules.items) |existing| {
            if (std.mem.eql(u8, existing.name, module.name)) {
                std.debug.print("silex: module '{s}' has multiple providers\n", .{module.name});
                return error.Reported;
            }
        }
        var sources: std.ArrayList([]const u8) = .empty;
        for (module.sources) |relative_source| {
            if (!std.mem.endsWith(u8, relative_source, ".sx")) {
                std.debug.print("silex: module source '{s}' must use the .sx extension\n", .{relative_source});
                return error.Reported;
            }
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
        if (std.mem.eql(u8, module.name, manifest.target)) target_module = module_index;
        try modules.append(allocator, .{ .name = module.name, .sources = try sources.toOwnedSlice(allocator) });
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
