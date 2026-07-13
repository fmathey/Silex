const std = @import("std");
const Ast = @import("Ast.zig");
const Modules = @import("Modules.zig");
const ParserModule = @import("Parser.zig");
const ProjectModule = @import("Project.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const ModuleBuilder = struct {
    name: []const u8,
    sources: std.ArrayList([]const u8) = .empty,
};

pub const Loaded = struct {
    project: ProjectModule.Project,
    source_paths: []const []const u8,
    source_contents: []const []const u8,
    files: []const Modules.File,
};

pub const Loader = struct {
    allocator: Allocator,
    io: Io,
    source_paths: std.ArrayList([]const u8) = .empty,
    source_contents: std.ArrayList([]const u8) = .empty,
    files: std.ArrayList(Modules.File) = .empty,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, io: Io) Loader {
        return .{ .allocator = allocator, .io = io };
    }

    pub fn load(self: *Loader, input_path: []const u8) !Loaded {
        var project = try ProjectModule.load(self.allocator, self.io, input_path);
        if (!project.single_file) {
            for (project.modules, 0..) |module, module_index| for (module.sources) |source_path| {
                try self.appendFile(source_path, module_index);
            };
            return self.finish(project);
        }

        var modules: std.ArrayList(ModuleBuilder) = .empty;
        var target_sources: std.ArrayList([]const u8) = .empty;
        try target_sources.append(self.allocator, input_path);
        try modules.append(self.allocator, .{
            .name = project.modules[0].name,
            .sources = target_sources,
        });
        try self.appendFile(input_path, 0);

        const project_root = std.fs.path.dirname(input_path) orelse ".";
        var file_index: usize = 0;
        while (file_index < self.files.items.len) : (file_index += 1) {
            const file = self.files.items[file_index];
            for (file.program.imports) |import_value| {
                try self.loadLocalModule(&modules, project_root, import_value.path, import_value.position);
            }
            for (file.program.uses) |use_value| {
                if (useUsesImportAlias(file.program.imports, use_value.path)) continue;
                const module_name = moduleNameFromUse(use_value.path) orelse continue;
                try self.loadLocalModule(&modules, project_root, module_name, use_value.position);
            }
        }

        var project_modules: std.ArrayList(ProjectModule.Module) = .empty;
        for (modules.items) |*module| try project_modules.append(self.allocator, .{
            .name = module.name,
            .sources = try module.sources.toOwnedSlice(self.allocator),
        });
        project.modules = try project_modules.toOwnedSlice(self.allocator);
        project.single_file = self.files.items.len == 1;
        return self.finish(project);
    }

    fn loadLocalModule(
        self: *Loader,
        modules: *std.ArrayList(ModuleBuilder),
        project_root: []const u8,
        module_name: []const u8,
        position: Source.Position,
    ) !void {
        if (findModule(modules.items, module_name) != null) return;

        const directory_path = try localModulePath(self.allocator, project_root, module_name);
        var directory = Io.Dir.cwd().openDir(self.io, directory_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "local module '{s}' was not found at '{s}'",
                    .{ module_name, directory_path },
                );
                return self.fail(position, message);
            },
            else => |other| return other,
        };
        defer directory.close(self.io);

        var source_names: std.ArrayList([]const u8) = .empty;
        var iterator = directory.iterateAssumeFirstIteration();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sx")) continue;
            try source_names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }
        std.mem.sort([]const u8, source_names.items, {}, struct {
            fn lessThan(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.lessThan);

        if (source_names.items.len == 0) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "local module '{s}' has no direct .sx source in '{s}'",
                .{ module_name, directory_path },
            );
            return self.fail(position, message);
        }

        const module_index = modules.items.len;
        try modules.append(self.allocator, .{ .name = module_name });
        for (source_names.items) |source_name| {
            const source_path = try std.fs.path.join(self.allocator, &.{ directory_path, source_name });
            try modules.items[module_index].sources.append(self.allocator, source_path);
            try self.appendFile(source_path, module_index);
        }
    }

    fn appendFile(self: *Loader, source_path: []const u8, module_index: usize) !void {
        const source = Io.Dir.cwd().readFileAlloc(self.io, source_path, self.allocator, .limited(16 * 1024 * 1024)) catch |err| {
            std.debug.print("silex: unable to read '{s}': {t}\n", .{ source_path, err });
            return error.Reported;
        };
        const file_index = self.source_paths.items.len;
        try self.source_paths.append(self.allocator, source_path);
        try self.source_contents.append(self.allocator, source);
        var parser = ParserModule.Parser.initFile(self.allocator, source, file_index);
        const program = parser.parse() catch |err| switch (err) {
            error.InvalidSource => {
                self.diagnostic = parser.diagnostic.?;
                return error.InvalidSource;
            },
            else => |other| return other,
        };
        try self.files.append(self.allocator, .{ .module_index = module_index, .program = program });
    }

    fn finish(self: *Loader, project: ProjectModule.Project) !Loaded {
        return .{
            .project = project,
            .source_paths = try self.source_paths.toOwnedSlice(self.allocator),
            .source_contents = try self.source_contents.toOwnedSlice(self.allocator),
            .files = try self.files.toOwnedSlice(self.allocator),
        };
    }

    fn fail(self: *Loader, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn findModule(modules: []const ModuleBuilder, name: []const u8) ?usize {
    for (modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, name)) return index;
    }
    return null;
}

fn moduleNameFromUse(path: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[0..separator];
}

fn useUsesImportAlias(imports: []const Ast.Import, path: []const u8) bool {
    for (imports) |import_value| {
        const qualifier = import_value.alias orelse import_value.path;
        const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse continue;
        if (separator == qualifier.len and std.mem.startsWith(u8, path, qualifier)) return true;
    }
    return false;
}

fn localModulePath(allocator: Allocator, root: []const u8, module_name: []const u8) ![]const u8 {
    const relative_path = try allocator.dupe(u8, module_name);
    for (relative_path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return std.fs.path.join(allocator, &.{ root, relative_path });
}

test "local module paths follow their logical segments" {
    const path = try localModulePath(std.testing.allocator, "Sandbox", "Math.Geometry");
    defer std.testing.allocator.free(path);
    const expected = try std.fs.path.join(std.testing.allocator, &.{ "Sandbox", "Math", "Geometry" });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, path);
}

test "use paths select a declaration from their parent module" {
    try std.testing.expectEqualStrings("Math.Geometry", moduleNameFromUse("Math.Geometry.Ray").?);
    try std.testing.expect(moduleNameFromUse("Vec3") == null);
}
