const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("../Ast.zig");
const NativeInterface = @import("../NativeInterface.zig");
const Semantic = @import("../Semantic.zig");
const Source = @import("../Source.zig");
const Types = @import("Types.zig");

const Allocator = std.mem.Allocator;
const GenerateError = Allocator.Error;
const NativeResultShape = Types.NativeResultShape;
const NativeResultOwnedAction = Types.NativeResultOwnedAction;
pub fn generateSourcePaths(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    source_paths: []const []const u8,
) !void {
    try output.appendSlice(allocator, "constexpr const char* k_silexSourcePaths[] = {\n");
    if (source_paths.len == 0) {
        try output.appendSlice(allocator, "    \"<unknown>\",\n");
    } else for (source_paths) |source_path| {
        try output.appendSlice(allocator, "    ");
        try self.appendCppStringLiteral(allocator, output, source_path);
        try output.appendSlice(allocator, ",\n");
    }
    try output.appendSlice(allocator, "};\nconstexpr std::size_t k_silexSourcePathCount = ");
    try output.appendSlice(allocator, if (source_paths.len == 0) "1" else try std.fmt.allocPrint(allocator, "{d}", .{source_paths.len}));
    try output.appendSlice(allocator, ";\n");
}

pub fn appendCppStringLiteral(_: anytype, allocator: Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append(allocator, '"');
    for (value) |character| switch (character) {
        '\\' => try output.appendSlice(allocator, "\\\\"),
        '"' => try output.appendSlice(allocator, "\\\""),
        '\n' => try output.appendSlice(allocator, "\\n"),
        '\r' => try output.appendSlice(allocator, "\\r"),
        '\t' => try output.appendSlice(allocator, "\\t"),
        else => try output.append(allocator, character),
    };
    try output.append(allocator, '"');
}

pub fn appendCppByteStringLiteral(_: anytype, allocator: Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append(allocator, '"');
    for (value) |character| switch (character) {
        '\\' => try output.appendSlice(allocator, "\\\\"),
        '"' => try output.appendSlice(allocator, "\\\""),
        else => if (character >= 0x20 and character <= 0x7E) {
            try output.append(allocator, character);
        } else {
            const octal = [_]u8{
                '\\',
                '0' + (character >> 6),
                '0' + ((character >> 3) & 7),
                '0' + (character & 7),
            };
            try output.appendSlice(allocator, &octal);
        },
    };
    try output.append(allocator, '"');
}

pub fn generateRuntimeArguments(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    position: Source.Position,
    type_name: Semantic.Type,
) !void {
    try output.appendSlice(allocator, try std.fmt.allocPrint(
        allocator,
        ", SilexSourceLocation{{{d}, {d}, {d}}}, ",
        .{ position.file, position.line, position.column },
    ));
    try self.appendCppStringLiteral(allocator, output, self.silexTypeName(type_name));
}

pub fn appendCppSourceLocation(_: anytype, allocator: Allocator, output: *std.ArrayList(u8), position: Source.Position) !void {
    try output.appendSlice(allocator, try std.fmt.allocPrint(
        allocator,
        "SilexSourceLocation{{{d}, {d}, {d}}}",
        .{ position.file, position.line, position.column },
    ));
}

pub fn indent(_: anytype, allocator: Allocator, output: *std.ArrayList(u8), level: usize) !void {
    var index: usize = 0;
    while (index < level) : (index += 1) try output.appendSlice(allocator, "    ");
}

pub fn cppType(_: anytype, type_name: Semantic.Type) []const u8 {
    return switch (type_name) {
        .void => "void",
        .int => "std::int64_t",
        .int8 => "std::int8_t",
        .int16 => "std::int16_t",
        .int32 => "std::int32_t",
        .uint8 => "std::uint8_t",
        .uint16 => "std::uint16_t",
        .uint32 => "std::uint32_t",
        .uint64 => "std::uint64_t",
        .float => "float",
        .float64 => "double",
        .bool => "bool",
        .str => "std::string",
        .function => unreachable,
        .list, .fixed_array, .view => unreachable,
        .structure => |structure_type| if (structure_type.is_class) unreachable else structure_type.generated_name,
        .protocol => |protocol_type| protocol_type.generated_name,
        .enumeration => |enum_type| enum_type.generated_name,
        .reference => unreachable,
        .optional, .null => unreachable,
    };
}

pub fn appendCppType(self: anytype, allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) Allocator.Error!void {
    switch (type_name) {
        .reference => |reference| {
            if (reference.target.* == .view) {
                try output.appendSlice(allocator, "SilexView<");
                if (!reference.mutable) try output.appendSlice(allocator, "const ");
                try self.appendCppType(allocator, output, reference.target.*.view.*);
                try output.append(allocator, '>');
                return;
            }
            if (!reference.mutable) try output.appendSlice(allocator, "const ");
            try self.appendCppType(allocator, output, reference.target.*);
            try output.append(allocator, '*');
        },
        .list => |element| {
            try output.appendSlice(allocator, "SilexList<");
            try self.appendCppType(allocator, output, element.*);
            try output.append(allocator, '>');
        },
        .fixed_array => |array| {
            try output.appendSlice(allocator, "std::array<");
            try self.appendCppType(allocator, output, array.element.*);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", {d}>", .{array.length}));
        },
        .view => |element| {
            try output.appendSlice(allocator, "SilexView<");
            try self.appendCppType(allocator, output, element.*);
            try output.append(allocator, '>');
        },
        .function => |function| {
            try output.appendSlice(allocator, "SilexFunction<");
            try self.appendCppType(allocator, output, function.return_type.*);
            try output.append(allocator, '(');
            var index: usize = 0;
            if (function.owner) |owner| {
                try output.appendSlice(allocator, owner.generated_name);
                try output.append(allocator, '&');
                index += 1;
            }
            for (function.parameters, function.parameter_modes) |parameter, mode| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter, mode);
                index += 1;
            }
            try output.appendSlice(allocator, ")>");
        },
        .optional => |contained| {
            try output.appendSlice(allocator, "std::optional<");
            try self.appendCppType(allocator, output, contained.*);
            try output.append(allocator, '>');
        },
        .structure => |structure_type| {
            if (structure_type.is_class) {
                try output.appendSlice(allocator, "SilexRef<");
                try output.appendSlice(allocator, structure_type.generated_name);
                try output.append(allocator, '>');
            } else {
                try output.appendSlice(allocator, structure_type.generated_name);
            }
        },
        .protocol => |protocol_type| try output.appendSlice(allocator, protocol_type.generated_name),
        .enumeration => |enum_type| try output.appendSlice(allocator, enum_type.generated_name),
        .null => unreachable,
        else => try output.appendSlice(allocator, self.cppType(type_name)),
    }
}

pub fn appendCppParameterType(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    type_name: Semantic.Type,
    mode: Ast.ParameterMode,
) Allocator.Error!void {
    if (type_name == .view) {
        if (mode == .borrow) try output.appendSlice(allocator, "const ");
        try output.appendSlice(allocator, "SilexView<");
        if (mode == .borrow) try output.appendSlice(allocator, "const ");
        try self.appendCppType(allocator, output, type_name.view.*);
        try output.append(allocator, '>');
        if (mode != .value) try output.append(allocator, '&');
        return;
    }
    if (mode == .borrow) try output.appendSlice(allocator, "const ");
    try self.appendCppType(allocator, output, type_name);
    if (mode != .value) try output.append(allocator, '&');
}

pub fn isClassType(_: anytype, type_name: Semantic.Type) bool {
    return type_name == .structure and type_name.structure.is_class;
}

pub fn silexTypeName(_: anytype, type_name: Semantic.Type) []const u8 {
    return switch (type_name) {
        .void => "void",
        .int => "int",
        .int8 => "int8",
        .int16 => "int16",
        .int32 => "int32",
        .uint8 => "uint8",
        .uint16 => "uint16",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .float => "float",
        .float64 => "float64",
        .bool => "bool",
        .str => "str",
        .list => "list",
        .fixed_array => "array",
        .view => "view",
        .structure => |structure_type| structure_type.source_name,
        .protocol => |protocol_type| protocol_type.source_name,
        .enumeration => |enum_type| enum_type.source_name,
        .reference => |reference| if (reference.mutable) "reference&" else "reference@",
        .function => "func",
        .optional => "optional",
        .null => "null",
    };
}

pub fn isInteger(_: anytype, type_name: Semantic.Type) bool {
    return switch (type_name) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

pub fn isUnsignedInteger(_: anytype, type_name: Semantic.Type) bool {
    return switch (type_name) {
        .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

pub fn isArithmetic(_: anytype, operator: Ast.BinaryOperator) bool {
    return switch (operator) {
        .add, .subtract, .multiply, .divide, .remainder => true,
        else => false,
    };
}

pub fn isShift(_: anytype, operator: Ast.BinaryOperator) bool {
    return switch (operator) {
        .shift_left, .shift_right => true,
        else => false,
    };
}

pub fn checkedBinaryFunction(_: anytype, operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .add => "checkedAdd",
        .subtract => "checkedSubtract",
        .multiply => "checkedMultiply",
        .divide => "checkedDivide",
        .remainder => "checkedRemainder",
        else => unreachable,
    };
}

pub fn checkedShiftFunction(_: anytype, operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .shift_left => "checkedShiftLeft",
        .shift_right => "checkedShiftRight",
        else => unreachable,
    };
}

pub fn checkedAssignmentFunction(_: anytype, operator: Ast.AssignmentOperator) []const u8 {
    return switch (operator) {
        .add, .increment => "checkedAdd",
        .subtract, .decrement => "checkedSubtract",
        .multiply => "checkedMultiply",
        .divide => "checkedDivide",
        .assign => unreachable,
    };
}

pub fn generateIntegerOne(self: anytype, allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) !void {
    try output.appendSlice(allocator, self.cppType(type_name));
    try output.appendSlice(allocator, "{1}");
}

pub fn integerMinimumMagnitude(_: anytype, type_name: Semantic.Type) u64 {
    return switch (type_name) {
        .int8 => 1 << 7,
        .int16 => 1 << 15,
        .int32 => 1 << 31,
        .int => 1 << 63,
        else => 0,
    };
}

pub fn operatorText(_: anytype, operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .logical_or => " || ",
        .logical_and => " && ",
        .equal => " == ",
        .not_equal => " != ",
        .less => " < ",
        .less_equal => " <= ",
        .greater => " > ",
        .greater_equal => " >= ",
        .add => " + ",
        .subtract => " - ",
        .shift_left => " << ",
        .shift_right => " >> ",
        .bit_and => " & ",
        .bit_xor => " ^ ",
        .multiply => " * ",
        .divide => " / ",
        .remainder => " % ",
    };
}

pub fn assignmentOperatorText(_: anytype, operator: Ast.AssignmentOperator) []const u8 {
    return switch (operator) {
        .assign => " = ",
        .add => " += ",
        .subtract => " -= ",
        .multiply => " *= ",
        .divide => " /= ",
        .increment, .decrement => unreachable,
    };
}
