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
pub fn generateNativeArgument(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    index: usize,
) GenerateError!void {
    const argument = call.arguments[index];
    if (argument.type == .str) {
        try output.appendSlice(allocator, "silexNativeString");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeString");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (self.nativeArgumentViewType(argument.type) != null) {
        try output.appendSlice(allocator, "silexNativeView");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeView");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (self.isNativeByteViewType(argument.type)) {
        try output.appendSlice(allocator, "silexNativeBytes");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeBytes");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (self.isNativeCallbackType(argument.type)) {
        try self.generateNativeCallbackTrampoline(allocator, output, argument.type.function, index);
    } else if (call.native_parameter_structures[index]) |structure| {
        if (structure.is_native_resource) {
            if (call.is_native_resource_drop) {
                try output.appendSlice(allocator, "([&]() { auto&& silexNativeDropResource = ");
                try self.generateExpression(allocator, output, argument);
                try output.appendSlice(allocator, "; silexNativeDropResource.silexCancelDeferred(); return silexNativeDropResource.silexReleaseNativeHandle(); }())");
                return;
            }
            try output.append(allocator, '(');
            try self.generateExpression(allocator, output, argument);
            try output.append(allocator, ')');
            try output.appendSlice(allocator, if (call.native_parameter_modes[index] == .value) ".silexReleaseNativeHandle()" else ".silexBorrowNativeHandle()");
            return;
        }
        try output.appendSlice(allocator, "&silexNativeInput");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
    } else {
        try self.generateExpression(allocator, output, argument);
    }
}

pub fn generateNativeCallbackTrampoline(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
    index: usize,
) GenerateError!void {
    try output.appendSlice(allocator, "+[](void* silexNativeContext");
    for (callback.parameters, 0..) |parameter, parameter_index| {
        try output.appendSlice(allocator, ", ");
        try self.appendCppType(allocator, output, parameter);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexNativeArgument{d}", .{parameter_index}));
    }
    try output.appendSlice(allocator, ") -> ");
    try self.appendCppType(allocator, output, callback.return_type.*);
    if (callback.deferred) {
        try output.appendSlice(allocator, " {auto* silexNativeCallback = static_cast<");
        try self.appendCppDeferredCallbackStateType(allocator, output, callback);
        try output.appendSlice(allocator, "*>(silexNativeContext);silexNativeCallback->enqueue(");
        for (callback.parameters, 0..) |_, parameter_index| {
            if (parameter_index != 0) try output.appendSlice(allocator, ", ");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexNativeArgument{d}", .{parameter_index}));
        }
        try output.appendSlice(allocator, ");}, silexNativeDeferred");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.get()", .{index}));
        return;
    }
    try output.appendSlice(allocator, " {auto& silexNativeCallback = *static_cast<SilexFunction<");
    try self.appendCppType(allocator, output, callback.return_type.*);
    try output.append(allocator, '(');
    for (callback.parameters, 0..) |parameter, parameter_index| {
        if (parameter_index != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")>*>(silexNativeContext);");
    if (callback.return_type.* != .void) try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, "silexNativeCallback(");
    for (callback.parameters, 0..) |_, parameter_index| {
        if (parameter_index != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexNativeArgument{d}", .{parameter_index}));
    }
    try output.appendSlice(allocator, ");}, &silexNativeCallback");
    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
}

pub fn appendCppDeferredCallbackStateType(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
) GenerateError!void {
    try output.appendSlice(allocator, "SilexDeferredCallbackStateFor<void(");
    for (callback.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")>");
}

pub fn nativeResultBranchHasOwned(
    self: anytype,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) bool {
    const value = self.nativeBranchValueType(branch_type);
    if (value == .str or self.isNativeByteBufferReturnType(value)) return true;
    return structure != null and (structure.?.is_native_resource or self.nativeTransportHasString(structure.?));
}

pub fn generateNativeResultOwnedAction(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
    action: NativeResultOwnedAction,
) GenerateError!void {
    const value = self.nativeBranchValueType(branch_type);
    if (value == .str or self.isNativeByteBufferReturnType(value)) {
        try self.generateNativeResultPointerAction(allocator, output, branch_name, null, self.isNativeByteBufferReturnType(value), action);
    } else if (structure) |transport| {
        if (transport.is_native_resource) {
            switch (action) {
                .raw_free => {
                    try output.appendSlice(allocator, "if (silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value != nullptr) ");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, "(silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value);");
                },
                .guard => {
                    try output.appendSlice(allocator, "std::unique_ptr<::");
                    try output.appendSlice(allocator, try NativeInterface.transportName(allocator, transport.native_module_name.?, transport.source_name));
                    try output.appendSlice(allocator, ", decltype(&");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, ")> silexNativeGuard_");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "{silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value, &");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, "};");
                },
                .reset => {
                    try output.appendSlice(allocator, "silexNativeGuard_");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, ".reset();");
                },
            }
            return;
        }
        for (transport.fields) |field| {
            if (field.type != .str) continue;
            try self.generateNativeResultPointerAction(allocator, output, branch_name, field.generated_name, false, action);
        }
    }
}

pub fn generateNativeResultPointerAction(
    _: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    field_name: ?[]const u8,
    byte_buffer: bool,
    action: NativeResultOwnedAction,
) GenerateError!void {
    switch (action) {
        .raw_free => try output.appendSlice(allocator, "silexNativeRelease("),
        .guard => try output.appendSlice(allocator, if (byte_buffer) "std::unique_ptr<std::uint8_t, decltype(&silexNativeRelease)> silexNativeGuard_" else "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_"),
        .reset => try output.appendSlice(allocator, "silexNativeGuard_"),
    }
    if (action == .guard or action == .reset) {
        try output.appendSlice(allocator, branch_name);
        if (field_name) |field| {
            try output.append(allocator, '_');
            try output.appendSlice(allocator, field);
        }
    }
    if (action == .reset) {
        try output.appendSlice(allocator, ".reset();");
        return;
    }
    if (action == .guard) try output.append(allocator, '{');
    try output.appendSlice(allocator, "silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
        try output.appendSlice(allocator, "Bytes");
    } else {
        try output.appendSlice(allocator, "Bytes");
    }
    try output.appendSlice(allocator, if (action == .guard) ", &silexNativeRelease};" else ");");
}

pub fn generateNativeResultOwnedCondition(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) GenerateError!void {
    const value = self.nativeBranchValueType(branch_type);
    if (value == .str or self.isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Bytes != nullptr");
        return;
    }
    var count: usize = 0;
    if (structure.?.is_native_resource) {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value != nullptr");
        return;
    }
    for (structure.?.fields) |field| {
        if (field.type != .str) continue;
        if (count != 0) try output.appendSlice(allocator, " || ");
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, "Bytes != nullptr");
        count += 1;
    }
}

pub fn generateNativeResultByteBufferValidation(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length < 0) {");
    try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a negative length", .{branch_name}));
    try output.appendSlice(allocator, "}if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length > 0) {");
    try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null pointer with a positive length", .{branch_name}));
    try output.appendSlice(allocator, "}");
}

pub fn generateNativeResultByteBufferConstruction(
    _: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "SilexList<std::uint8_t> silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ";if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes != nullptr) {silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ".insert(silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ".end(), silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes, silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes + static_cast<std::size_t>(silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length));}");
}

pub fn generateNativeResultFatal(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    message: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "silexNativeCleanup();nativeFunctionRuntimeError(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, message);
    try output.appendSlice(allocator, ");");
}

pub fn generateNativeResultStringValidation(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    const label = if (field_name) |field|
        try std.fmt.allocPrint(allocator, "{s}.{s}", .{ branch_name, field })
    else
        branch_name;
    try output.appendSlice(allocator, "if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length < 0) {");
    try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a negative length", .{label}));
    try output.appendSlice(allocator, "}if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length > 0) {");
    try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null pointer with a positive length", .{label}));
    try output.appendSlice(allocator, "}");
}

pub fn generateNativeResultStringConstruction(
    _: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "std::string silexNativeString_");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.append(allocator, '_');
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, " = silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length)};");
}

pub fn generateNativeResultUtf8Validation(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "if (!nativeStringIsValidUtf8(silexNativeString_");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.append(allocator, '_');
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, ")) {nativeFunctionRuntimeError(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", ");
    const label = if (field_name) |field|
        try std.fmt.allocPrint(allocator, "Result {s}.{s} returned invalid UTF-8", .{ branch_name, field })
    else
        try std.fmt.allocPrint(allocator, "Result {s} returned invalid UTF-8", .{branch_name});
    try self.appendCppByteStringLiteral(allocator, output, label);
    try output.appendSlice(allocator, ");}");
}

pub fn generateNativeResultBranchValue(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) GenerateError!void {
    const value = self.nativeBranchValueType(branch_type);
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "std::optional<");
        try self.appendCppType(allocator, output, value);
        try output.appendSlice(allocator, ">{");
    }
    if (value == .str) {
        try output.appendSlice(allocator, "std::move(silexNativeString_");
        try output.appendSlice(allocator, branch_name);
        try output.append(allocator, ')');
    } else if (self.isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "std::move(silexNativeBytes_");
        try output.appendSlice(allocator, branch_name);
        try output.append(allocator, ')');
    } else if (structure) |transport| {
        if (transport.is_native_resource) {
            try output.appendSlice(allocator, transport.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeAdopted_");
            try output.appendSlice(allocator, branch_name);
            try output.append(allocator, ')');
            if (branch_type == .optional) try output.append(allocator, '}');
            return;
        }
        try output.appendSlice(allocator, transport.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (transport.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, branch_name);
                try output.append(allocator, '_');
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, branch_name);
                try output.appendSlice(allocator, "Value.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.append(allocator, ')');
    } else {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value");
    }
    if (branch_type == .optional) try output.append(allocator, '}');
}

pub fn generateNativeResultBranchReturn(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    result: Semantic.NativeResultTransport,
    branch_name: []const u8,
    branch_index: usize,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
    module_name: []const u8,
    function_name: []const u8,
) GenerateError!void {
    const has_owned = self.nativeResultBranchHasOwned(branch_type, structure);
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "if (!silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Present) {");
        if (has_owned) {
            try output.appendSlice(allocator, "if (");
            try self.generateNativeResultOwnedCondition(allocator, output, branch_name, branch_type, structure);
            try output.appendSlice(allocator, ") {");
            try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned an owned buffer while reporting absence", .{branch_name}));
            try output.appendSlice(allocator, "}");
        }
        try output.appendSlice(allocator, "silexNativeCleanup();return ");
        try output.appendSlice(allocator, result.enum_generated_name);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}, std::optional<", .{branch_index}));
        try self.appendCppType(allocator, output, self.nativeBranchValueType(branch_type));
        try output.appendSlice(allocator, ">{}};}");
    }

    const value = self.nativeBranchValueType(branch_type);
    if (structure != null and structure.?.is_native_resource) {
        try output.appendSlice(allocator, "if (silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value == nullptr) {");
        try self.generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null native resource", .{branch_name}));
        try output.appendSlice(allocator, "}");
    }
    if (value == .str) {
        try self.generateNativeResultStringValidation(allocator, output, module_name, function_name, branch_name, null);
        try self.generateNativeResultStringConstruction(allocator, output, branch_name, null);
    } else if (self.isNativeByteBufferReturnType(value)) {
        try self.generateNativeResultByteBufferValidation(allocator, output, module_name, function_name, branch_name);
        try self.generateNativeResultByteBufferConstruction(allocator, output, branch_name);
    } else if (structure) |transport| {
        for (transport.fields) |field| if (field.type == .str) {
            try self.generateNativeResultStringValidation(allocator, output, module_name, function_name, branch_name, field.generated_name);
            try self.generateNativeResultStringConstruction(allocator, output, branch_name, field.generated_name);
        };
    }
    if (structure != null and structure.?.is_native_resource) {
        try output.appendSlice(allocator, "auto* silexNativeAdopted_");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, " = silexNativeGuard_");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, ".release();");
    }
    try output.appendSlice(allocator, "silexNativeCleanup();");
    if (value == .str) {
        try self.generateNativeResultUtf8Validation(allocator, output, module_name, function_name, branch_name, null);
    } else if (structure) |transport| {
        for (transport.fields) |field| if (field.type == .str) {
            try self.generateNativeResultUtf8Validation(allocator, output, module_name, function_name, branch_name, field.generated_name);
        };
    }
    try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, result.enum_generated_name);
    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}", .{branch_index}));
    if (value != .void) {
        try output.appendSlice(allocator, ", ");
        try self.generateNativeResultBranchValue(allocator, output, branch_name, branch_type, structure);
    }
    try output.appendSlice(allocator, "};");
}

pub fn generateNativeResultFunctionCall(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    result: Semantic.NativeResultTransport,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const transport_name = try NativeInterface.resultTransportName(allocator, module_name, function_name);
    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{transport_name});
    try output.appendSlice(allocator, "callNativeFunction(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() {");
    try self.generateNativeArgumentPreludes(allocator, output, call);
    try output.appendSlice(allocator, transport_name);
    try output.appendSlice(allocator, " silexNativeOutput{};silexNativeOutput.tag = static_cast<");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, ">(2);try {");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    try output.appendSlice(allocator, "&silexNativeOutput);} catch (...) {");
    try self.generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .raw_free);
    try self.generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .raw_free);
    try output.appendSlice(allocator, "throw;}");
    try self.generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .guard);
    try self.generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .guard);
    try output.appendSlice(allocator, "auto silexNativeCleanup = [&]() {");
    try self.generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .reset);
    try self.generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .reset);
    try output.appendSlice(allocator, "};");

    try output.appendSlice(allocator, "if (silexNativeOutput.tag == ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_success) {");
    if (self.nativeResultBranchHasOwned(result.failure_type, result.failure_structure)) {
        try output.appendSlice(allocator, "if (");
        try self.generateNativeResultOwnedCondition(allocator, output, "failure", result.failure_type, result.failure_structure);
        try output.appendSlice(allocator, ") {");
        try self.generateNativeResultFatal(allocator, output, module_name, function_name, "returned an owned buffer in the inactive failure branch");
        try output.appendSlice(allocator, "}");
    }
    try self.generateNativeResultBranchReturn(allocator, output, result, "success", 0, result.success_type, result.success_structure, module_name, function_name);
    try output.appendSlice(allocator, "}if (silexNativeOutput.tag == ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_failure) {");
    if (self.nativeResultBranchHasOwned(result.success_type, result.success_structure)) {
        try output.appendSlice(allocator, "if (");
        try self.generateNativeResultOwnedCondition(allocator, output, "success", result.success_type, result.success_structure);
        try output.appendSlice(allocator, ") {");
        try self.generateNativeResultFatal(allocator, output, module_name, function_name, "returned an owned buffer in the inactive success branch");
        try output.appendSlice(allocator, "}");
    }
    try self.generateNativeResultBranchReturn(allocator, output, result, "failure", 1, result.failure_type, result.failure_structure, module_name, function_name);
    try output.appendSlice(allocator, "}");
    try self.generateNativeResultFatal(allocator, output, module_name, function_name, "returned an unknown Result tag");
    try output.appendSlice(allocator, "})");
}

pub fn generateNativeFunctionCall(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    return_type: Semantic.Type,
) GenerateError!void {
    if (self.nativeReturnedView(return_type)) |_| {
        const module_name = call.native_module_name.?;
        const function_name = call.native_function_name.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try self.generateNativeArgumentPreludes(allocator, output, call);
        try self.appendCppType(allocator, output, return_type);
        try output.appendSlice(allocator, "::value_type");
        if (!return_type.reference.mutable) try output.appendSlice(allocator, " const");
        try output.appendSlice(allocator, "* silexNativeValues = nullptr;std::int64_t silexNativeCount = 0;");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try self.generateNativeArgument(allocator, output, call, index);
        }
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeValues, &silexNativeCount);if (silexNativeCount < 0) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a negative view count\");if (silexNativeCount > 0 && silexNativeValues == nullptr) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null view with a positive count\");if (static_cast<std::uint64_t>(silexNativeCount) > std::numeric_limits<std::size_t>::max()) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a view count that is not representable\");return ");
        try self.appendCppType(allocator, output, return_type);
        try output.appendSlice(allocator, "(silexNativeValues, static_cast<std::size_t>(silexNativeCount));})");
        return;
    }
    if (return_type == .reference) {
        const parameter_index = call.borrowed_return_parameter.?;
        const module_name = call.native_module_name.?;
        const function_name = call.native_function_name.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try self.generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "auto& silexBorrowRoot = ");
        try self.generateExpression(allocator, output, call.arguments[parameter_index]);
        try output.appendSlice(allocator, ";auto* silexNativeBorrow = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try self.generateNativeArgument(allocator, output, call, index);
        }
        try output.appendSlice(allocator, ");if (silexNativeBorrow == nullptr) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null borrowed resource\");if (silexNativeBorrow != silexBorrowRoot.silexBorrowNativeHandle()) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a resource outside its declared provenance\");return &silexBorrowRoot;})");
        return;
    }
    if (call.native_result) |result| {
        return self.generateNativeResultFunctionCall(allocator, output, call, result);
    }
    if (self.isNativeByteBufferReturnType(return_type)) {
        return self.generateNativeByteBufferFunctionCall(allocator, output, call);
    }
    if (return_type == .optional) {
        return self.generateNativeOptionalFunctionCall(allocator, output, call, return_type.optional.*);
    }
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const returns_string = return_type == .str;
    const returned_structure = call.native_return_structure;
    if (returned_structure != null and returned_structure.?.is_native_resource) {
        const resource = returned_structure.?;
        const deferred_index = self.nativeDeferredCallbackIndex(call.arguments);
        try output.appendSlice(allocator, "callNativeFunction(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try self.generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "auto* silexNativeHandle = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try self.generateNativeArgument(allocator, output, call, index);
        }
        try output.appendSlice(allocator, ");if (silexNativeHandle == nullptr) {");
        if (deferred_index) |index| {
            try output.appendSlice(allocator, "silexNativeDeferred");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}->cancel();silexNativeDeferred{d}.reset();", .{ index, index }));
        }
        try output.appendSlice(allocator, "nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null native resource\");}return ");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeHandle");
        if (deferred_index) |index| {
            try output.appendSlice(allocator, ", std::move(silexNativeDeferred");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d})", .{index}));
        }
        try output.appendSlice(allocator, ");})");
        return;
    }
    try output.appendSlice(allocator, if (returns_string) "callNativeStringFunction(" else "callNativeFunction(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, if (returns_string) ", [&](char** output_bytes, std::int64_t* output_length) {" else ", [&]() {");
    try self.generateNativeArgumentPreludes(allocator, output, call);
    if (returned_structure) |structure| {
        try output.appendSlice(allocator, try NativeInterface.transportName(
            allocator,
            module_name,
            structure.source_name,
        ));
        try output.appendSlice(allocator, " silexNativeOutput{};");
        if (self.nativeTransportHasString(structure)) try output.appendSlice(allocator, "try {");
    }
    if (!returns_string and returned_structure == null) try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.generateNativeArgument(allocator, output, call, index);
    }
    if (returns_string) {
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "output_bytes, output_length");
    } else if (returned_structure != null) {
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeOutput");
    }
    try output.appendSlice(allocator, ");");
    if (returned_structure) |structure| {
        if (self.nativeTransportHasString(structure)) {
            try output.appendSlice(allocator, "} catch (...) {");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes);");
            }
            try output.appendSlice(allocator, "throw;}");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, &silexNativeRelease};");
            }
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length < 0) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a negative length\");}");
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length > 0) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
                try output.appendSlice(allocator, "std::string silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " = silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length)};");
                try output.appendSlice(allocator, "if (!nativeStringIsValidUtf8(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ")) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}");
            }
            try self.generateNativeStringGuardCleanup(allocator, output, structure);
        }
        try output.appendSlice(allocator, " return ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (structure.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, ");");
    }
    try output.appendSlice(allocator, " })");
}

pub fn generateNativeByteBufferFunctionCall(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    try output.appendSlice(allocator, "callNativeFunction(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() -> SilexList<std::uint8_t> {");
    try self.generateNativeArgumentPreludes(allocator, output, call);
    try output.appendSlice(allocator, "std::uint8_t* silexNativeOutputBytes = nullptr;std::int64_t silexNativeOutputLength = 0;try {");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    try output.appendSlice(allocator, "&silexNativeOutputBytes, &silexNativeOutputLength);} catch (...) {silexNativeRelease(silexNativeOutputBytes);throw;}");
    try output.appendSlice(allocator, "std::unique_ptr<std::uint8_t, decltype(&silexNativeRelease)> silexNativeGuard{silexNativeOutputBytes, &silexNativeRelease};");
    try output.appendSlice(allocator, "if (silexNativeOutputLength < 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", \"returned a negative length\");}");
    try output.appendSlice(allocator, "if (silexNativeOutputBytes == nullptr && silexNativeOutputLength > 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
    try output.appendSlice(allocator, "SilexList<std::uint8_t> silexNativeBytes;if (silexNativeOutputBytes != nullptr) {silexNativeBytes.insert(silexNativeBytes.end(), silexNativeOutputBytes, silexNativeOutputBytes + static_cast<std::size_t>(silexNativeOutputLength));}silexNativeGuard.reset();return silexNativeBytes;})");
}

pub fn generateNativeOptionalFunctionCall(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    returned_type: Semantic.Type,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const returns_string = returned_type == .str;
    const returned_structure = call.native_return_structure;

    if (returned_structure != null and returned_structure.?.is_native_resource) {
        const resource = returned_structure.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() -> std::optional<");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "> {");
        try self.generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "::");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, resource.source_name));
        try output.appendSlice(allocator, "* silexNativeHandle = nullptr;const bool silexNativePresent = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try self.generateNativeArgument(allocator, output, call, index);
        }
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeHandle);if (!silexNativePresent) {if (silexNativeHandle != nullptr) {");
        try output.appendSlice(allocator, resource.native_drop_symbol.?);
        try output.appendSlice(allocator, "(silexNativeHandle);nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a native resource while reporting absence\");}return std::nullopt;}if (silexNativeHandle == nullptr) nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null native resource\");return ");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeHandle);})");
        return;
    }

    try output.appendSlice(allocator, "callNativeFunction(");
    try self.appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try self.appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() -> std::optional<");
    try self.appendCppType(allocator, output, returned_type);
    try output.appendSlice(allocator, "> {");

    try self.generateNativeArgumentPreludes(allocator, output, call);

    if (returns_string) {
        try output.appendSlice(allocator, "char* silexNativeOutputBytes = nullptr;std::int64_t silexNativeOutputLength = 0;");
    } else if (returned_structure) |structure| {
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.appendSlice(allocator, " silexNativeOutput{};");
    } else {
        try self.appendCppType(allocator, output, returned_type);
        try output.appendSlice(allocator, " silexNativeOutput{};");
    }

    const has_owned_buffers = returns_string or
        (returned_structure != null and self.nativeTransportHasString(returned_structure.?));
    if (has_owned_buffers) try output.appendSlice(allocator, "bool silexNativePresent = false;try {");
    if (!has_owned_buffers) try output.appendSlice(allocator, "const bool silexNativePresent = ");
    if (has_owned_buffers) try output.appendSlice(allocator, "silexNativePresent = ");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    if (returns_string) {
        try output.appendSlice(allocator, "&silexNativeOutputBytes, &silexNativeOutputLength");
    } else {
        try output.appendSlice(allocator, "&silexNativeOutput");
    }
    try output.appendSlice(allocator, ");");

    if (has_owned_buffers) {
        try output.appendSlice(allocator, "} catch (...) {");
        if (returns_string) {
            try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutputBytes);");
        } else for (returned_structure.?.fields) |field| {
            if (field.type != .str) continue;
            try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutput.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, "Bytes);");
        }
        try output.appendSlice(allocator, "throw;}");
    }

    if (returns_string) {
        try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard{silexNativeOutputBytes, &silexNativeRelease};");
        try output.appendSlice(allocator, "if (!silexNativePresent) {if (silexNativeOutputBytes != nullptr) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned an owned buffer while reporting absence\");}return std::nullopt;}");
        try output.appendSlice(allocator, "if (silexNativeOutputLength < 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a negative length\");}");
        try output.appendSlice(allocator, "if (silexNativeOutputBytes == nullptr && silexNativeOutputLength > 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
        try output.appendSlice(allocator, "std::string silexNativeString = silexNativeOutputBytes == nullptr ? std::string{} : std::string{silexNativeOutputBytes, static_cast<std::size_t>(silexNativeOutputLength)};silexNativeGuard.reset();if (!nativeStringIsValidUtf8(silexNativeString)) {nativeFunctionRuntimeError(");
        try self.appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try self.appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}return silexNativeString;");
    } else if (returned_structure) |structure| {
        if (self.nativeTransportHasString(structure)) {
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, &silexNativeRelease};");
            }
            try output.appendSlice(allocator, "if (!silexNativePresent) {");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes != nullptr) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned an owned buffer while reporting absence\");}");
            }
            try output.appendSlice(allocator, "return std::nullopt;}");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length < 0) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a negative length\");}");
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length > 0) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
                try output.appendSlice(allocator, "std::string silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " = silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length)};if (!nativeStringIsValidUtf8(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ")) {");
                try self.generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try self.appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try self.appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}");
            }
            try self.generateNativeStringGuardCleanup(allocator, output, structure);
        } else {
            try output.appendSlice(allocator, "if (!silexNativePresent) return std::nullopt;");
        }
        try output.appendSlice(allocator, "return ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (structure.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, ");");
    } else {
        try output.appendSlice(allocator, "if (!silexNativePresent) return std::nullopt;return silexNativeOutput;");
    }
    try output.appendSlice(allocator, " })");
}
