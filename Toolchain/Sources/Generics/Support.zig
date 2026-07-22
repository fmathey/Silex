pub const Types = @import("Types.zig");
pub const std = Types.std;
pub const Ast = Types.Ast;
pub const Parser = Types.Parser;
pub const Source = Types.Source;
pub const Allocator = Types.Allocator;
pub const SpecializeError = Types.SpecializeError;
pub const Binding = Types.Binding;
pub const State = Types.State;
pub const StructureSpecialization = Types.StructureSpecialization;
pub const EnumSpecialization = Types.EnumSpecialization;
pub const result_type_parameters = Types.result_type_parameters;
pub const result_success_types = Types.result_success_types;
pub const result_failure_types = Types.result_failure_types;
pub const result_variants = Types.result_variants;
pub const intrinsic_result = Types.intrinsic_result;
pub const intrinsic_function_source = Types.intrinsic_function_source;
pub const FunctionSpecialization = Types.FunctionSpecialization;
pub const MethodSpecialization = Types.MethodSpecialization;

pub fn functionIsVisible(function: Ast.Function, visible_declarations: ?[]const Source.Position) bool {
    const positions = visible_declarations orelse return true;
    for (positions) |position| {
        if (positionsEqual(position, function.name_position)) return true;
    }
    return false;
}

pub fn fileSetContains(files: []const usize, target: usize) bool {
    for (files) |file| if (file == target) return true;
    return false;
}

pub fn positionsEqual(left: Source.Position, right: Source.Position) bool {
    return left.file == right.file and left.line == right.line and left.column == right.column;
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
        .list => |element| .{ .list = element },
        .view => |element| .{ .view = element },
        .fixed_array => |array| .{ .fixed_array = array },
        .reference => |reference| .{ .reference = reference },
        .function => |function| .{ .function = function },
        .optional => |contained| .{ .optional = contained },
        .generic_structure, .type_parameter => unreachable,
    };
}

pub fn appendTypeName(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    value: Ast.TypeName,
) Allocator.Error!void {
    switch (value) {
        .void => try output.appendSlice(allocator, "void"),
        .int => try output.appendSlice(allocator, "int"),
        .int8 => try output.appendSlice(allocator, "int8"),
        .int16 => try output.appendSlice(allocator, "int16"),
        .int32 => try output.appendSlice(allocator, "int32"),
        .int64 => try output.appendSlice(allocator, "int64"),
        .uint => try output.appendSlice(allocator, "uint"),
        .uint8 => try output.appendSlice(allocator, "uint8"),
        .uint16 => try output.appendSlice(allocator, "uint16"),
        .uint32 => try output.appendSlice(allocator, "uint32"),
        .uint64 => try output.appendSlice(allocator, "uint64"),
        .float => try output.appendSlice(allocator, "float"),
        .float32 => try output.appendSlice(allocator, "float32"),
        .float64 => try output.appendSlice(allocator, "float64"),
        .bool => try output.appendSlice(allocator, "bool"),
        .str => try output.appendSlice(allocator, "str"),
        .structure => |name| try output.appendSlice(allocator, name),
        .generic_structure => |generic| {
            try output.appendSlice(allocator, generic.name);
            try output.append(allocator, '<');
            for (generic.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendTypeName(allocator, output, argument);
            }
            try output.append(allocator, '>');
        },
        .type_parameter => |name| try output.appendSlice(allocator, name),
        .list => |element| {
            try appendTypeName(allocator, output, element.*);
            try output.appendSlice(allocator, "[]");
        },
        .fixed_array => |array| {
            try appendTypeName(allocator, output, array.element.*);
            try output.append(allocator, '[');
            try output.appendSlice(allocator, array.length);
            try output.append(allocator, ']');
        },
        .view => |element| {
            try appendTypeName(allocator, output, element.*);
            try output.appendSlice(allocator, "[..]");
        },
        .reference => |reference| {
            try output.append(allocator, if (reference.mutable) '&' else '@');
            try appendTypeName(allocator, output, reference.target.*);
        },
        .function => |function| {
            try output.appendSlice(allocator, "func(");
            for (function.parameters, function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (mode == .borrow) try output.append(allocator, '@');
                if (mode == .mutable_reference) try output.append(allocator, '&');
                try appendTypeName(allocator, output, parameter);
            }
            try output.append(allocator, ')');
            if (function.return_type) |return_type| {
                try output.append(allocator, ' ');
                try appendTypeName(allocator, output, return_type.*);
            }
        },
        .optional => |contained| {
            try appendTypeName(allocator, output, contained.*);
            try output.append(allocator, '?');
        },
    }
}
