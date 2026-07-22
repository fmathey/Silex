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
pub fn generateProtocolTypes(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.protocols) |protocol| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator,
            \\ {
            \\    struct Witness {
        );
        for (protocol.requirements) |requirement| {
            try output.appendSlice(allocator, "        ");
            try self.appendCppType(allocator, output, requirement.return_type);
            try output.appendSlice(allocator, " (*");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.appendSlice(allocator, ")(void*");
            for (requirement.parameter_types, requirement.parameter_modes) |parameter_type, mode| {
                try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter_type, mode);
            }
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator,
            \\    };
            \\    struct StorageBase {
            \\        virtual std::unique_ptr<StorageBase> clone() const = 0;
            \\        virtual void* data() = 0;
            \\        virtual void trace(const SilexTraceVisitor& visit) const = 0;
            \\        virtual void clear() = 0;
            \\        virtual ~StorageBase() = default;
            \\    };
            \\    template <typename T>
            \\    struct Storage final : StorageBase {
            \\        explicit Storage(T input) : value(std::move(input)) {}
            \\        std::unique_ptr<StorageBase> clone() const override { return std::make_unique<Storage<T>>(value); }
            \\        void* data() override { return &value; }
            \\        void trace(const SilexTraceVisitor& visit) const override { silexTraceValue(value, visit); }
            \\        void clear() override { silexClearValue(value); }
            \\        T value;
            \\    };
        );
        try output.appendSlice(allocator, "    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "() = default;\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "(const ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& other) : storage_(other.storage_ ? other.storage_->clone() : nullptr), witness_(other.witness_) {}\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "(");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& operator=(const ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& other) { if (this != &other) { ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, " copy(other); *this = std::move(copy); } return *this; }\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& operator=(");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "&&) noexcept = default;\n");
        try output.appendSlice(allocator, "    template <typename T>\n    static ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, " make(T value, const Witness* witness) {\n        ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(
            allocator,
            " result;\n        result.storage_ = std::make_unique<Storage<T>>(std::move(value));\n        result.witness_ = witness;\n        return result;\n    }\n",
        );
        for (protocol.requirements) |requirement| {
            try output.appendSlice(allocator, "    ");
            try self.appendCppType(allocator, output, requirement.return_type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, requirement.generated_name);
            try output.append(allocator, '(');
            for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator,
            \\    void silexTrace(const SilexTraceVisitor& visit) const { if (storage_) storage_->trace(visit); }
            \\    void silexClear() { if (storage_) storage_->clear(); storage_.reset(); witness_ = nullptr; }
            \\private:
            \\    std::unique_ptr<StorageBase> storage_;
            \\    const Witness* witness_ = nullptr;
            \\};
            \\
        );
    }
    for (program.structures) |structure| {
        for (structure.protocol_conformances) |conformance| {
            try output.appendSlice(allocator, "extern const ");
            try output.appendSlice(allocator, conformance.protocol_generated_name);
            try output.appendSlice(allocator, "::Witness ");
            try output.appendSlice(allocator, conformance.witness_name);
            try output.appendSlice(allocator, ";\n");
        }
    }
    if (program.protocols.len != 0) try output.append(allocator, '\n');
}

pub fn generateProtocolMethodDefinitions(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.protocols) |protocol| {
        for (protocol.requirements) |requirement| {
            try self.appendCppType(allocator, output, requirement.return_type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, protocol.generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.append(allocator, '(');
            for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return witness_->");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.appendSlice(allocator, "(storage_->data()");
            for (requirement.parameter_types, 0..) |_, index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }\n");
        }
        try output.append(allocator, '\n');
    }
}

pub fn generateProtocolWitnesses(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.structures) |structure| {
        for (structure.protocol_conformances) |conformance| {
            const protocol = program.protocols[conformance.protocol_index];
            for (protocol.requirements, conformance.method_generated_names, 0..) |requirement, method_name, requirement_index| {
                try self.appendCppType(allocator, output, requirement.return_type);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, conformance.witness_name);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "Method{d}(void* raw", .{requirement_index}));
                for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                    try output.appendSlice(allocator, ", ");
                    try self.appendCppParameterType(allocator, output, parameter_type, mode);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " argument{d}", .{index}));
                }
                try output.appendSlice(allocator, ") { auto& value = *static_cast<");
                if (structure.is_class) {
                    try output.appendSlice(allocator, "SilexRef<");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.append(allocator, '>');
                } else try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "*>(raw); return value");
                try output.appendSlice(allocator, if (structure.is_class) "->" else ".");
                try output.appendSlice(allocator, method_name);
                try output.append(allocator, '(');
                for (requirement.parameter_types, 0..) |_, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "argument{d}", .{index}));
                }
                try output.appendSlice(allocator, "); }\n");
            }
            try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, conformance.protocol_generated_name);
            try output.appendSlice(allocator, "::Witness ");
            try output.appendSlice(allocator, conformance.witness_name);
            try output.appendSlice(allocator, "{");
            for (protocol.requirements, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, "&");
                try output.appendSlice(allocator, conformance.witness_name);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "Method{d}", .{index}));
            }
            try output.appendSlice(allocator, "};\n\n");
        }
    }
}

pub fn generateMethodSignature(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    method: Semantic.Method,
    owner_name: ?[]const u8,
    include_names: bool,
) !void {
    try self.appendCppType(allocator, output, method.return_type);
    try output.append(allocator, ' ');
    if (owner_name) |name| {
        try output.appendSlice(allocator, name);
        try output.appendSlice(allocator, "::");
    }
    try output.appendSlice(allocator, method.generated_name);
    try output.append(allocator, '(');
    for (method.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppParameterType(allocator, output, parameter.type, parameter.mode);
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
    const mutable_return = method.return_type == .reference and method.return_type.reference.mutable;
    if (!method.is_static and !method.is_mutating and !method.requires_mutable_codegen and !mutable_return) {
        try output.appendSlice(allocator, " const");
    }
}

pub fn generateBaseInitializer(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    initializer: Semantic.BaseInitializer,
) !void {
    try output.appendSlice(allocator, initializer.generated_name);
    try output.append(allocator, '(');
    for (initializer.arguments, 0..) |argument, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.generateExpression(allocator, output, argument);
    }
    try output.append(allocator, ')');
}

pub fn structureDefinitionOrder(_: anytype, allocator: Allocator, structures: []const Semantic.Structure) ![]const usize {
    const emitted = try allocator.alloc(bool, structures.len);
    @memset(emitted, false);
    var order: std.ArrayList(usize) = .empty;
    while (order.items.len != structures.len) {
        var progressed = false;
        for (structures, 0..) |structure, index| {
            if (emitted[index]) continue;
            if (structure.base) |base| {
                var base_index: ?usize = null;
                for (structures, 0..) |candidate, candidate_index| {
                    if (std.mem.eql(u8, candidate.generated_name, base.generated_name)) base_index = candidate_index;
                }
                if (base_index == null or !emitted[base_index.?]) continue;
            }
            emitted[index] = true;
            try order.append(allocator, index);
            progressed = true;
        }
        if (!progressed) unreachable;
    }
    return order.toOwnedSlice(allocator);
}

pub fn generateConstructorSignature(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    owner_name: []const u8,
    constructor: Semantic.Constructor,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, owner_name);
    if (include_names) {
        try output.appendSlice(allocator, "::");
        try output.appendSlice(allocator, owner_name);
    }
    try output.append(allocator, '(');
    for (constructor.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppParameterType(allocator, output, parameter.type, parameter.mode);
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
}

pub fn generateFunctionSignature(self: anytype, allocator: Allocator, output: *std.ArrayList(u8), function: Semantic.Function, include_names: bool) !void {
    if (function.is_main and function.return_type == .void) {
        try output.appendSlice(allocator, "int");
    } else {
        try self.appendCppType(allocator, output, function.return_type);
    }
    try output.append(allocator, ' ');
    try output.appendSlice(allocator, if (function.is_main) "silexMain" else function.generated_name);
    try output.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppParameterType(allocator, output, parameter.type, parameter.mode);
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
}

pub fn generateCapturedParameterBindings(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    parameters: []const Semantic.Parameter,
    indentation: usize,
) !void {
    for (parameters) |parameter| {
        if (!parameter.capture_box.*) continue;
        try self.indent(allocator, output, indentation);
        try output.appendSlice(allocator, "auto ");
        try output.appendSlice(allocator, parameter.generated_name);
        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
        try self.appendCppType(allocator, output, parameter.type);
        try output.appendSlice(allocator, ">>(");
        try output.appendSlice(allocator, parameter.generated_name);
        try output.appendSlice(allocator, "Input);\n");
    }
}

pub fn generateNativeFunctionSignature(
    self: anytype,
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
    function: Semantic.Function,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "extern \"C\" ");
    const result = self.nativeResultShape(program, function.return_type);
    const structure = self.nativeReturnStructure(program, function);
    const returned = self.nativeReturnValueType(function.return_type);
    const returned_view = self.nativeReturnedView(returned);
    const returns_bytes = self.isNativeByteBufferReturnType(returned);
    const optional = function.return_type == .optional;
    const resource = if (structure) |value| value.is_native_resource else false;
    if (result != null or returned_view != null) {
        try output.appendSlice(allocator, "void");
    } else if (optional) {
        try output.appendSlice(allocator, "bool");
    } else if (resource) {
        if (returned == .reference and !returned.reference.mutable) try output.appendSlice(allocator, "const ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, function.native_module_name.?, structure.?.source_name));
        try output.append(allocator, '*');
    } else if (returned == .str or returns_bytes or structure != null) {
        try output.appendSlice(allocator, "void");
    } else {
        try self.appendCppType(allocator, output, returned);
    }
    try output.append(allocator, ' ');
    try output.appendSlice(allocator, function.generated_name);
    try output.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        if (parameter.type == .str) {
            try output.appendSlice(allocator, "const char*");
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Bytes, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Length");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else if (parameter.type == .view) {
            if (parameter.mode == .borrow) try output.appendSlice(allocator, "const ");
            try self.appendCppType(allocator, output, parameter.type.view.*);
            try output.append(allocator, '*');
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Values, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Count");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else if (self.isNativeByteViewType(parameter.type)) {
            try output.appendSlice(allocator, "const std::uint8_t*");
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Bytes, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Length");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else if (self.isNativeCallbackType(parameter.type)) {
            try self.appendCppNativeCallbackParameter(allocator, output, parameter.type.function, if (include_names) parameter.generated_name else null);
        } else if (self.nativeStructureForType(program, parameter.type)) |parameter_structure| {
            if (!parameter_structure.is_native_resource or parameter.mode == .borrow) try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, try NativeInterface.inputTransportName(
                allocator,
                function.native_module_name.?,
                parameter_structure.source_name,
                self.structureHasString(parameter_structure) and !parameter_structure.is_native_resource,
            ));
            try output.append(allocator, '*');
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
            }
        } else {
            try self.appendCppType(allocator, output, parameter.type);
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
            }
        }
    }
    if (result != null) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.resultTransportName(
            allocator,
            function.native_module_name.?,
            function.native_function_name.?,
        ));
        try output.append(allocator, '*');
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (returned_view) |view| {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        if (!returned.reference.mutable) try output.appendSlice(allocator, "const ");
        try self.appendCppType(allocator, output, view.*);
        try output.appendSlice(allocator, "**");
        if (include_names) try output.appendSlice(allocator, " output_values");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_count");
    } else if (returned == .str) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "char**");
        if (include_names) try output.appendSlice(allocator, " output_bytes");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_length");
    } else if (returns_bytes) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "std::uint8_t**");
        if (include_names) try output.appendSlice(allocator, " output_bytes");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_length");
    } else if (optional and resource) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, function.native_module_name.?, structure.?.source_name));
        try output.appendSlice(allocator, "**");
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (structure != null and !resource) {
        const returned_structure = structure.?;
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.transportName(
            allocator,
            function.native_module_name.?,
            returned_structure.source_name,
        ));
        try output.appendSlice(allocator, if (returned_structure.is_native_resource) "**" else "*");
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (optional) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try self.appendCppType(allocator, output, returned);
        try output.append(allocator, '*');
        if (include_names) try output.appendSlice(allocator, " output");
    }
    try output.append(allocator, ')');
}
