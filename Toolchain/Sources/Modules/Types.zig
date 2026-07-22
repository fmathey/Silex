pub const std = @import("std");
pub const Ast = @import("../Ast.zig");
pub const ProjectModule = @import("../Project.zig");
pub const Source = @import("../Source.zig");

pub const Allocator = std.mem.Allocator;

pub const File = struct {
    module_index: usize,
    unit_name: []const u8 = "",
    program: Ast.Program,
    dependency_modules: []const usize = &.{},
    activated_files: []const usize = &.{},
    load_only_uses: []const Source.Position = &.{},
};

pub const Kind = enum { structure, protocol, function, type_alias };
pub const VisitState = enum { fresh, visiting, done };

pub const Declaration = struct {
    module_index: usize,
    source_name: []const u8,
    canonical_name: []const u8,
    kind: Kind,
    is_public: bool,
    position: Source.Position,
    aliased_type: ?Ast.TypeName = null,
};

pub const Export = struct {
    module_index: usize,
    public_name: []const u8,
    declaration: *const Declaration,
    position: Source.Position,
};

pub const ModuleBinding = struct {
    module_index: usize,
    qualifier: []const u8,
    position: Source.Position,
};

pub const QualifiedTarget = struct {
    module_index: usize,
    public_name: []const u8,
};

pub const Dependency = struct {
    module_index: usize,
    position: Source.Position,
};

pub const UseBinding = struct {
    local_name: []const u8,
    declaration: *const Declaration,
    position: Source.Position,
};

pub const FileInfo = struct {
    file_index: usize,
    module_index: usize,
    program: Ast.Program,
    module_bindings: []const ModuleBinding,
    dependencies: std.ArrayList(Dependency) = .empty,
    uses: std.ArrayList(UseBinding) = .empty,
};
