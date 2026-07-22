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
pub fn generateNativeTransportIfNew(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    const transport_name = if (input)
        try NativeInterface.inputTransportName(
            allocator,
            module_name,
            structure.source_name,
            self.structureHasString(structure),
        )
    else
        try NativeInterface.transportName(allocator, module_name, structure.source_name);
    for (emitted.items) |name| {
        if (std.mem.eql(u8, name, transport_name)) return;
    }
    try emitted.append(allocator, transport_name);
    try self.generateNativeTransportDefinition(allocator, output, module_name, structure, input);
    try output.append(allocator, '\n');
}

pub fn generateNativeTransportDefinition(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    if (structure.is_native_resource) {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.append(allocator, ';');
        return;
    }
    try output.appendSlice(allocator, "struct ");
    if (input) {
        try output.appendSlice(allocator, try NativeInterface.inputTransportName(
            allocator,
            module_name,
            structure.source_name,
            self.structureHasString(structure),
        ));
    } else {
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
    }
    try output.appendSlice(allocator, " {\n");
    if (structure.fields.len == 0) {
        try output.appendSlice(allocator, "    std::uint8_t silexUnused;\n");
    } else for (structure.fields) |field| {
        try output.appendSlice(allocator, "    ");
        if (field.type == .str) {
            try output.appendSlice(allocator, if (input) "const char* " else "char* ");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, if (input) "Bytes;\n    std::int64_t " else "Bytes = nullptr;\n    std::int64_t ");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, if (input) "Length;\n" else "Length = 0;\n");
            continue;
        }
        try self.appendCppType(allocator, output, field.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    try output.appendSlice(allocator, "};");
}

pub fn nativeResultShape(_: anytype, program: Semantic.Program, value: Semantic.Type) ?NativeResultShape {
    const enum_type = switch (value) {
        .enumeration => |enumeration| enumeration,
        else => return null,
    };
    if (!std.mem.startsWith(u8, enum_type.source_name, "Result<")) return null;
    for (program.enums) |enumeration| {
        if (!std.mem.eql(u8, enumeration.generated_name, enum_type.generated_name)) continue;
        if (enumeration.variants.len != 2 or enumeration.variants[1].associated_types.len != 1 or
            enumeration.variants[0].associated_types.len > 1)
        {
            return null;
        }
        return .{
            .success_type = if (enumeration.variants[0].associated_types.len == 0)
                .void
            else
                enumeration.variants[0].associated_types[0],
            .failure_type = enumeration.variants[1].associated_types[0],
        };
    }
    return null;
}

pub fn nativeBranchValueType(_: anytype, value: Semantic.Type) Semantic.Type {
    return if (value == .optional) value.optional.* else value;
}

pub fn isNativeByteViewType(_: anytype, value: Semantic.Type) bool {
    return switch (value) {
        .list => |element| element.* == .uint8,
        .fixed_array => |array| array.element.* == .uint8,
        else => false,
    };
}

pub fn isNativeByteBufferReturnType(_: anytype, value: Semantic.Type) bool {
    return value == .list and value.list.* == .uint8;
}

pub fn isNativeCallbackType(self: anytype, value: Semantic.Type) bool {
    const function = switch (value) {
        .function => |function_value| function_value,
        else => return false,
    };
    if (function.owner != null) return false;
    if (function.return_type.* != .void and !self.isNativeCallbackScalarType(function.return_type.*)) return false;
    for (function.parameters, function.parameter_modes) |parameter, mode| {
        if (mode != .value or !self.isNativeCallbackScalarType(parameter)) return false;
    }
    return true;
}

pub fn nativeDeferredCallbackIndex(_: anytype, arguments: []const *Semantic.Expression) ?usize {
    for (arguments, 0..) |argument, index| {
        if (argument.type == .function and argument.type.function.deferred) return index;
    }
    return null;
}

pub fn isNativeCallbackScalarType(_: anytype, value: Semantic.Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool => true,
        else => false,
    };
}

pub fn appendCppNativeCallbackParameter(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
    name: ?[]const u8,
) GenerateError!void {
    try self.appendCppType(allocator, output, callback.return_type.*);
    try output.appendSlice(allocator, " (*");
    if (name) |parameter_name| try output.appendSlice(allocator, parameter_name);
    try output.appendSlice(allocator, ")(void*");
    for (callback.parameters) |parameter| {
        try output.appendSlice(allocator, ", ");
        try self.appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")");
    if (name) |parameter_name| {
        try output.appendSlice(allocator, ", void* ");
        try output.appendSlice(allocator, parameter_name);
        try output.appendSlice(allocator, "_context");
    } else {
        try output.appendSlice(allocator, ", void*");
    }
}

pub fn generateNativeResultTransportIfNew(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    program: Semantic.Program,
    function: Semantic.Function,
    result: NativeResultShape,
) !void {
    const name = try NativeInterface.resultTransportName(
        allocator,
        function.native_module_name.?,
        function.native_function_name.?,
    );
    for (emitted.items) |emitted_name| if (std.mem.eql(u8, emitted_name, name)) return;
    try emitted.append(allocator, name);

    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});
    try output.appendSlice(allocator, "enum ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_success = 0,\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_failure = 1\n};\n\nstruct ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " tag{};\n");
    try self.generateNativeResultBranchFields(allocator, output, program, function.native_module_name.?, "success", result.success_type);
    try self.generateNativeResultBranchFields(allocator, output, program, function.native_module_name.?, "failure", result.failure_type);
    try output.appendSlice(allocator, "};\n\n");
}

pub fn generateNativeResultBranchFields(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
    module_name: []const u8,
    prefix: []const u8,
    branch_type: Semantic.Type,
) !void {
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "    bool ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Present{};\n");
    }
    const value = self.nativeBranchValueType(branch_type);
    if (value == .void) return;
    if (self.isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "    std::uint8_t* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Bytes = nullptr;\n    std::int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Length = 0;\n");
    } else if (value == .str) {
        try output.appendSlice(allocator, "    char* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Bytes = nullptr;\n    std::int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Length = 0;\n");
    } else if (self.nativeStructureForType(program, value)) |structure| {
        try output.appendSlice(allocator, "    ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.appendSlice(allocator, if (structure.is_native_resource) "* " else " ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, if (structure.is_native_resource) "Value = nullptr;\n" else "Value{};\n");
    } else {
        try output.appendSlice(allocator, "    ");
        try self.appendCppType(allocator, output, value);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Value{};\n");
    }
}

pub fn nativeReturnStructure(self: anytype, program: Semantic.Program, function: Semantic.Function) ?Semantic.Structure {
    const returned = self.nativeReturnValueType(function.return_type);
    return self.nativeStructureForType(program, if (returned == .reference) returned.reference.target.* else returned);
}

pub fn nativeStructureForType(_: anytype, program: Semantic.Program, value: Semantic.Type) ?Semantic.Structure {
    const structure_type = switch (value) {
        .structure => |structure| structure,
        else => return null,
    };
    for (program.structures) |structure| {
        if (std.mem.eql(u8, structure.generated_name, structure_type.generated_name)) return structure;
    }
    return null;
}

pub fn structureIsNativeReturn(self: anytype, program: Semantic.Program, structure: Semantic.Structure) bool {
    for (program.functions) |function| {
        if (!function.is_native) continue;
        if (self.nativeResultShape(program, function.return_type)) |result| {
            const branches = [_]Semantic.Type{ result.success_type, result.failure_type };
            for (branches) |branch| {
                const value = self.nativeBranchValueType(branch);
                if (value == .structure and std.mem.eql(u8, value.structure.generated_name, structure.generated_name)) return true;
            }
        }
        const returned = self.nativeReturnValueType(function.return_type);
        if (returned != .structure) continue;
        if (std.mem.eql(u8, returned.structure.generated_name, structure.generated_name)) return true;
    }
    return false;
}

pub fn nativeReturnValueType(_: anytype, return_type: Semantic.Type) Semantic.Type {
    return if (return_type == .optional) return_type.optional.* else return_type;
}

pub fn nativeReturnedView(_: anytype, value: Semantic.Type) ?*const Semantic.Type {
    if (value != .reference or value.reference.target.* != .view) return null;
    return value.reference.target.*.view;
}

pub fn nativeArgumentViewType(_: anytype, value: Semantic.Type) ?*const Semantic.Type {
    const target = if (value == .reference) value.reference.target.* else value;
    return if (target == .view) target.view else null;
}

pub fn structureHasString(_: anytype, structure: Semantic.Structure) bool {
    for (structure.fields) |field| if (field.type == .str) return true;
    return false;
}

pub fn containsNativeFunction(_: anytype, functions: []const Semantic.Function) bool {
    for (functions) |function| if (function.is_native) return true;
    return false;
}

pub fn nativeTransportHasString(_: anytype, structure: Semantic.NativeStructureTransport) bool {
    for (structure.fields) |field| if (field.type == .str) return true;
    return false;
}

pub fn generateNativeStringGuardCleanup(
    _: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.NativeStructureTransport,
) GenerateError!void {
    for (structure.fields) |field| {
        if (field.type != .str) continue;
        try output.appendSlice(allocator, "silexNativeGuard_");
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, ".reset();");
    }
}

pub fn generateNativeArgumentPreludes(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
) GenerateError!void {
    for (call.arguments, call.native_parameter_structures, 0..) |argument, parameter_structure, index| {
        if (argument.type == .str) {
            try output.appendSlice(allocator, "auto&& silexNativeString");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (self.nativeArgumentViewType(argument.type) != null) {
            try output.appendSlice(allocator, "const auto& silexNativeView");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (self.isNativeByteViewType(argument.type)) {
            try output.appendSlice(allocator, "const auto& silexNativeBytes");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (self.isNativeCallbackType(argument.type)) {
            try output.appendSlice(allocator, if (argument.type.function.deferred) "auto silexNativeDeferred" else "auto silexNativeCallback");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            if (argument.type.function.deferred) {
                try output.appendSlice(allocator, " = std::make_shared<");
                try self.appendCppDeferredCallbackStateType(allocator, output, argument.type.function);
                try output.appendSlice(allocator, ">(");
            } else try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, output, argument);
            try output.appendSlice(allocator, if (argument.type.function.deferred) ");" else ";");
            continue;
        }
        const structure = parameter_structure orelse continue;
        if (structure.is_native_resource) continue;
        try output.appendSlice(allocator, "const auto& silexNativeStructure");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, " = ");
        try self.generateExpression(allocator, output, argument);
        try output.append(allocator, ';');
        try output.appendSlice(allocator, try NativeInterface.inputTransportName(
            allocator,
            call.native_module_name.?,
            structure.source_name,
            self.nativeTransportHasString(structure),
        ));
        try output.appendSlice(allocator, " silexNativeInput");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, "{");
        for (structure.fields, 0..) |field, field_index| {
            if (field_index != 0) try output.appendSlice(allocator, ", ");
            if (field.type == .str) {
                try output.appendSlice(allocator, "silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ".size())");
            } else {
                try output.appendSlice(allocator, "silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, "};");
    }
}
