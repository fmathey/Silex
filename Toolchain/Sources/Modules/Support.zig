pub const Types = @import("Types.zig");
pub const std = Types.std;
pub const Ast = Types.Ast;
pub const ProjectModule = Types.ProjectModule;
pub const Source = Types.Source;
pub const Allocator = Types.Allocator;
pub const File = Types.File;
pub const Kind = Types.Kind;
pub const VisitState = Types.VisitState;
pub const Declaration = Types.Declaration;
pub const Export = Types.Export;
pub const ModuleBinding = Types.ModuleBinding;
pub const QualifiedTarget = Types.QualifiedTarget;
pub const Dependency = Types.Dependency;
pub const UseBinding = Types.UseBinding;
pub const FileInfo = Types.FileInfo;

pub fn pathHasQualifier(path: []const u8, qualifier: []const u8) bool {
    return path.len > qualifier.len and std.mem.startsWith(u8, path, qualifier) and path[qualifier.len] == '.';
}

pub fn sourceFileIndex(program: Ast.Program) ?usize {
    if (program.uses.len != 0) return program.uses[0].position.file;
    if (program.enums.len != 0) return program.enums[0].position.file;
    if (program.protocols.len != 0) return program.protocols[0].position.file;
    if (program.extensions.len != 0) return program.extensions[0].position.file;
    if (program.structures.len != 0) return program.structures[0].position.file;
    if (program.functions.len != 0) return program.functions[0].position.file;
    return null;
}

pub fn appendFunctions(allocator: Allocator, left: []const Ast.Function, right: []const Ast.Function) ![]const Ast.Function {
    const result = try allocator.alloc(Ast.Function, left.len + right.len);
    @memcpy(result[0..left.len], left);
    @memcpy(result[left.len..], right);
    return result;
}

pub fn appendProtocolReferences(
    allocator: Allocator,
    left: []const Ast.ProtocolReference,
    right: []const Ast.ProtocolReference,
) ![]const Ast.ProtocolReference {
    const result = try allocator.alloc(Ast.ProtocolReference, left.len + right.len);
    @memcpy(result[0..left.len], left);
    @memcpy(result[left.len..], right);
    return result;
}

pub fn lastSegment(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[index + 1 ..];
}

pub fn parentModuleName(path: []const u8) ?[]const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[0..index];
}

pub fn sameModuleParent(left: []const u8, right: []const u8) bool {
    const left_parent = parentModuleName(left) orelse return false;
    const right_parent = parentModuleName(right) orelse return false;
    return std.mem.eql(u8, left_parent, right_parent);
}

pub fn moduleUseAt(file: *const FileInfo, position: Source.Position) bool {
    return moduleBindingAt(file, position) != null;
}

pub fn moduleBindingAt(file: *const FileInfo, position: Source.Position) ?ModuleBinding {
    for (file.module_bindings) |binding| {
        if (binding.position.file == position.file and binding.position.line == position.line and
            binding.position.column == position.column) return binding;
    }
    return null;
}

pub fn loadOnlyUseAt(file: File, position: Source.Position) bool {
    for (file.load_only_uses) |candidate| {
        if (candidate.file == position.file and candidate.line == position.line and
            candidate.column == position.column) return true;
    }
    return false;
}

pub fn declarationPositions(allocator: Allocator, declarations: []const *const Declaration) ![]const Source.Position {
    var positions: std.ArrayList(Source.Position) = .empty;
    for (declarations) |declaration| try positions.append(allocator, declaration.position);
    return positions.toOwnedSlice(allocator);
}

pub fn typeNameToReturnType(value: Ast.TypeName) Ast.ReturnType {
    return switch (value) {
        .void => .void,
        .int => .int,
        .int8 => .int8,
        .int16 => .int16,
        .int32 => .int32,
        .int64 => .int64,
        .uint => .uint,
        .uint8 => .uint8,
        .uint16 => .uint16,
        .uint32 => .uint32,
        .uint64 => .uint64,
        .float => .float,
        .float32 => .float32,
        .float64 => .float64,
        .bool => .bool,
        .str => .str,
        .structure => |name| .{ .structure = name },
        .generic_structure => |generic| .{ .generic_structure = generic },
        .type_parameter => |name| .{ .type_parameter = name },
        .list => |contained| .{ .list = contained },
        .view => |contained| .{ .view = contained },
        .fixed_array => |array| .{ .fixed_array = array },
        .reference => |reference| .{ .reference = reference },
        .function => |function| .{ .function = function },
        .optional => |contained| .{ .optional = contained },
    };
}
