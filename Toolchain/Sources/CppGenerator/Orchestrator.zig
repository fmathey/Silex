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
pub fn generateWithSources(
    self: anytype,
    allocator: Allocator,
    program: Semantic.Program,
    source_paths: []const []const u8,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator,
        \\#include <algorithm>
        \\#include <atomic>
        \\#include <cstddef>
        \\#include <cstdint>
        \\#include <cstdlib>
        \\#include <exception>
        \\#include <functional>
        \\#include <array>
        \\#include <bit>
        \\#include <climits>
        \\#include <cmath>
        \\#include <concepts>
        \\#include <iostream>
        \\#include <iterator>
        \\#include <limits>
        \\#include <memory>
        \\#include <mutex>
        \\#include <optional>
        \\#include <stdexcept>
        \\#include <string>
        \\#include <tuple>
        \\#include <type_traits>
        \\#include <unordered_map>
        \\#include <utility>
        \\#include <vector>
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\#include <condition_variable>
        \\#endif
        \\
    );
    var emitted_native_transports: std.ArrayList([]const u8) = .empty;
    for (program.functions) |function| {
        if (!function.is_native) continue;
        if (self.nativeResultShape(program, function.return_type)) |result| {
            if (self.nativeStructureForType(program, self.nativeBranchValueType(result.success_type))) |structure| {
                try self.generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, function.native_module_name.?, structure, false);
            }
            if (self.nativeStructureForType(program, self.nativeBranchValueType(result.failure_type))) |structure| {
                try self.generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, function.native_module_name.?, structure, false);
            }
            try self.generateNativeResultTransportIfNew(
                allocator,
                &output,
                &emitted_native_transports,
                program,
                function,
                result,
            );
        }
        if (self.nativeReturnStructure(program, function)) |structure| {
            try self.generateNativeTransportIfNew(
                allocator,
                &output,
                &emitted_native_transports,
                function.native_module_name.?,
                structure,
                false,
            );
        }
        for (function.parameters) |parameter| {
            if (self.nativeStructureForType(program, parameter.type)) |structure| {
                try self.generateNativeTransportIfNew(
                    allocator,
                    &output,
                    &emitted_native_transports,
                    function.native_module_name.?,
                    structure,
                    true,
                );
            }
        }
    }
    for (program.structures) |structure| {
        if (!structure.is_native_resource) continue;
        try self.generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, structure.native_module_name.?, structure, false);
    }
    for (program.functions) |function| {
        if (!function.is_native) continue;
        try self.generateNativeFunctionSignature(allocator, &output, program, function, true);
        try output.appendSlice(allocator, ";\n");
    }
    if (self.containsNativeFunction(program.functions)) try output.appendSlice(allocator, "\nstruct SilexNativeReturnTag {};\n\n");
    try output.appendSlice(allocator,
        \\
        \\namespace SilexGenerated {
        \\
        \\// -----------------------------------------------------------------------------
        \\
    );
    try self.generateSourcePaths(allocator, &output, source_paths);
    try self.appendRuntime(allocator, &output);
    try output.append(allocator, '\n');
    for (program.protocols) |protocol| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    for (program.enums) |enum_value| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, enum_value.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    for (program.structures) |structure| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    if (program.protocols.len > 0 or program.enums.len > 0 or program.structures.len > 0) try output.append(allocator, '\n');
    try self.generateProtocolTypes(allocator, &output, program);
    for (program.enums) |enum_value| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, enum_value.generated_name);
        try output.appendSlice(allocator, " : SilexEnumStorage {\n    using SilexEnumStorage::SilexEnumStorage;\n");
        if (!enum_value.is_copyable) {
            try output.appendSlice(allocator, "    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "(const ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "& operator=(const ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "(");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "& operator=(");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n");
        }
        if (enum_value.raw_type) |raw_type| {
            try output.appendSlice(allocator, "    ");
            try self.appendCppType(allocator, &output, raw_type);
            try output.appendSlice(allocator, " rawValue() const {\n        switch (variant) {\n");
            for (enum_value.variants, 0..) |variant, variant_index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "            case {d}: return ", .{variant_index}));
                try self.generateExpression(allocator, &output, variant.raw_value.?);
                try output.appendSlice(allocator, ";\n");
            }
            try output.appendSlice(allocator, "        }\n        std::abort();\n    }\n");
        }
        try output.appendSlice(allocator, "};\n\n");
    }
    const structure_order = try self.structureDefinitionOrder(allocator, program.structures);
    for (structure_order) |structure_index| {
        const structure = program.structures[structure_index];
        const is_native_return = self.structureIsNativeReturn(program, structure);
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        if (structure.is_class) {
            try output.appendSlice(allocator, " : ");
            if (structure.base) |base| {
                try output.appendSlice(allocator, "public ");
                try output.appendSlice(allocator, base.generated_name);
            } else {
                try output.appendSlice(allocator, "SilexObject");
            }
        }
        try output.appendSlice(allocator, " {\n");
        for (structure.static_fields) |field| {
            try output.appendSlice(allocator, "    inline static ");
            try self.appendCppType(allocator, &output, field.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, &output, field.initializer.?);
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.static_fields.len != 0 and structure.fields.len != 0) try output.append(allocator, '\n');
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "    ");
            try self.appendCppType(allocator, &output, field.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, field.generated_name);
            if (structure.constructors.len != 0) {
                if (field.initializer) |initializer| {
                    try output.appendSlice(allocator, " = ");
                    try self.generateExpression(allocator, &output, initializer);
                } else {
                    try output.appendSlice(allocator, "{}");
                }
            }
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.is_native_resource) {
            try output.appendSlice(allocator, "    std::shared_ptr<SilexNativeResourceState> silexNativeState;\n");
        }
        if (is_native_return and !structure.is_native_resource) {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag");
            for (structure.fields, 0..) |field, index| {
                try output.appendSlice(allocator, ", ");
                try self.appendCppType(allocator, &output, field.type);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexNativeField{d}", .{index}));
            }
            try output.appendSlice(allocator, ")");
            if (structure.fields.len == 0) {
                try output.appendSlice(allocator, " {}\n");
            } else {
                try output.appendSlice(allocator, " : ");
                for (structure.fields, 0..) |field, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, field.generated_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "(silexNativeField{d})", .{index}));
                }
                try output.appendSlice(allocator, " {}\n");
            }
        }
        if (structure.is_native_resource) {
            try output.appendSlice(allocator, "\n    explicit ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag, ::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "* handle) : silexNativeState(silexAdoptNativeResource(handle, +[](void* value) { ");
            try output.appendSlice(allocator, structure.native_drop_symbol.?);
            try output.appendSlice(allocator, "(static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(value)); })) {}\n\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag, ::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "* handle, std::shared_ptr<SilexDeferredCallbackState> deferred) : silexNativeState(silexAdoptNativeResource(handle, +[](void* value) { ");
            try output.appendSlice(allocator, structure.native_drop_symbol.?);
            try output.appendSlice(allocator, "(static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(value)); }, std::move(deferred))) {}\n    auto* silexBorrowNativeHandle() const { return static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(silexNativeState->handle); }\n    auto silexReleaseNativeHandle() { if (silexNativeState.use_count() != 1) throw std::runtime_error(\"native resource still has later acquisitions\"); silexOwnsResource = false; auto state = std::move(silexNativeState); auto* handle = static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(state->release()); return SilexNativeTransfer<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, ">{handle, std::move(state)}; }\n    void silexCancelDeferred() { silexNativeState->cancelDeferred(); }\n");
        }
        if (structure.is_owner) try output.appendSlice(allocator, "    bool silexOwnsResource = true;\n");
        if ((structure.is_class and structure.constructors.len == 0 and structure.implicit_constructor_available) or
            (structure.is_noncopyable and !structure.is_native_resource and structure.constructors.len == 0) or
            (is_native_return and !structure.is_class and structure.constructors.len == 0))
        {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.append(allocator, '(');
            for (structure.fields, 0..) |field, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try self.appendCppType(allocator, &output, field.type);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexField{d}", .{index}));
            }
            try output.append(allocator, ')');
            if (structure.fields.len == 0 and structure.implicit_base_initializer == null) {
                try output.appendSlice(allocator, " = default;\n");
            } else {
                try output.appendSlice(allocator, " : ");
                var initializer_count: usize = 0;
                if (structure.implicit_base_initializer) |base_initializer| {
                    try self.generateBaseInitializer(allocator, &output, base_initializer);
                    initializer_count += 1;
                }
                for (structure.fields, 0..) |field, index| {
                    if (initializer_count != 0 or index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, field.generated_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "(std::move(silexField{d}))", .{index}));
                    initializer_count += 1;
                }
                try output.appendSlice(allocator, " {}\n");
            }
        }
        for (structure.constructors) |constructor| {
            try output.appendSlice(allocator, "\n    ");
            try self.generateConstructorSignature(allocator, &output, structure.generated_name, constructor, false);
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.is_noncopyable and structure.drop == null and !structure.is_class) {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(const ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "& operator=(const ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "& operator=(");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n");
        }
        if (structure.drop != null) {
            if (structure.is_class) {
                try output.appendSlice(allocator, "\n    void silexDrop() override;\n");
            } else {
                try output.appendSlice(allocator, "\n    ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "(const ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "&) = delete;\n    ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "& operator=(const ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "&) = delete;\n    ");
                if (structure.is_owner) {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept;\n    ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept;\n    void silexDropResource();\n    ~");
                } else {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&&) = delete;\n    ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&&) = delete;\n    ~");
                }
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "();\n");
            }
        }
        if (structure.fields.len > 0 and (structure.constructors.len > 0 or structure.methods.len > 0)) try output.append(allocator, '\n');
        for (structure.methods) |method| {
            try output.appendSlice(allocator, "    ");
            if (method.is_static) {
                try output.appendSlice(allocator, "static ");
            } else if (structure.is_class and !method.is_extension and method.visibility != .private_access) try output.appendSlice(allocator, "virtual ");
            try self.generateMethodSignature(allocator, &output, method, null, false);
            if (method.is_override) try output.appendSlice(allocator, " override");
            try output.appendSlice(allocator, ";\n");
        }
        try output.appendSlice(allocator, "\n    void silexTrace(const SilexTraceVisitor& visit) const");
        if (structure.is_class) try output.appendSlice(allocator, " override");
        try output.appendSlice(allocator, " {\n");
        if (structure.base) |base| {
            try output.appendSlice(allocator, "        ");
            try output.appendSlice(allocator, base.generated_name);
            try output.appendSlice(allocator, "::silexTrace(visit);\n");
        }
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "        silexTraceValue(");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ", visit);\n");
        }
        try output.appendSlice(allocator, "    }\n    void silexClear()");
        if (structure.is_class) try output.appendSlice(allocator, " override");
        try output.appendSlice(allocator, " {\n");
        if (structure.base) |base| {
            try output.appendSlice(allocator, "        ");
            try output.appendSlice(allocator, base.generated_name);
            try output.appendSlice(allocator, "::silexClear();\n");
        }
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "        silexClearValue(");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator, "    }\n");
        try output.appendSlice(allocator, "};\n\n");
    }
    try self.generateProtocolMethodDefinitions(allocator, &output, program);
    try self.generateProtocolWitnesses(allocator, &output, program);
    try output.appendSlice(allocator, "void silexResetStaticFields() {\n");
    for (program.structures) |structure| {
        for (structure.static_fields) |field| {
            try output.appendSlice(allocator, "    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " = ");
            try self.generateExpression(allocator, &output, field.reset_value.?);
            try output.appendSlice(allocator, ";\n");
        }
    }
    try output.appendSlice(allocator, "}\n\n");
    if (program.structures.len > 0) {
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
            try self.generateStructureEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
            try self.generateStructureOperatorEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
        }
        try output.append(allocator, '\n');
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
            try self.generateStructureEqualitySignature(allocator, &output, structure, true);
            try output.appendSlice(allocator, " {\n    return ");
            if (structure.fields.len == 0) {
                try output.appendSlice(allocator, "true");
            } else {
                for (structure.fields, 0..) |field, index| {
                    if (index != 0) try output.appendSlice(allocator, " && ");
                    try self.generateStructureFieldEquality(allocator, &output, field);
                }
            }
            try output.appendSlice(allocator, ";\n}\n\n");
        }
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
            try self.generateStructureOperatorEqualitySignature(allocator, &output, structure, true);
            try output.appendSlice(allocator, " {\n    return ");
            try self.generateStructureEqualityName(allocator, &output, structure.generated_name);
            try output.appendSlice(allocator, "(left, right);\n}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_main or function.is_native) continue;
        try self.generateFunctionSignature(allocator, &output, function, false);
        try output.appendSlice(allocator, ";\n");
    }
    if (program.functions.len > 1) try output.append(allocator, '\n');
    for (program.structures) |structure| {
        for (structure.constructors) |constructor| {
            try self.generateConstructorSignature(allocator, &output, structure.generated_name, constructor, true);
            if (constructor.base_initializer) |base_initializer| {
                try output.appendSlice(allocator, " : ");
                try self.generateBaseInitializer(allocator, &output, base_initializer);
            }
            try output.appendSlice(allocator, " {\n");
            try self.generateCapturedParameterBindings(allocator, &output, constructor.parameters, 1);
            try self.generateStatements(allocator, &output, constructor.statements, 1, false);
            try output.appendSlice(allocator, "}\n\n");
        }
        if (structure.drop) |drop| {
            if (structure.is_class) {
                try output.appendSlice(allocator, "void ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "::silexDrop() {\n");
                try self.generateStatements(allocator, &output, drop.statements, 1, false);
                try output.appendSlice(allocator, "    ");
                if (structure.base) |base| {
                    try output.appendSlice(allocator, base.generated_name);
                } else {
                    try output.appendSlice(allocator, "SilexObject");
                }
                try output.appendSlice(allocator, "::silexDrop();\n}\n\n");
            } else {
                if (structure.is_owner) {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept : ");
                    for (structure.fields, 0..) |field, field_index| {
                        if (field_index != 0) try output.appendSlice(allocator, ", ");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, "(std::move(other.");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, "))");
                    }
                    if (structure.fields.len != 0) try output.appendSlice(allocator, ", ");
                    if (structure.is_native_resource) try output.appendSlice(allocator, "silexNativeState(std::move(other.silexNativeState)), ");
                    try output.appendSlice(allocator, "silexOwnsResource(std::exchange(other.silexOwnsResource, false)) {}\n\n");

                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept {\n    if (this == &other) return *this;\n    if (silexOwnsResource) {\n        silexDropResource();\n        silexOwnsResource = false;\n    }\n");
                    for (structure.fields) |field| {
                        try output.appendSlice(allocator, "    ");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, " = std::move(other.");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, ");\n");
                    }
                    if (structure.is_native_resource) try output.appendSlice(allocator, "    silexNativeState = std::move(other.silexNativeState);\n");
                    try output.appendSlice(allocator, "    silexOwnsResource = std::exchange(other.silexOwnsResource, false);\n    return *this;\n}\n\nvoid ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::silexDropResource() {\n");
                    if (structure.is_native_resource) {
                        try output.appendSlice(allocator, "    silexNativeState.reset();\n");
                    } else try self.generateStatements(allocator, &output, drop.statements, 1, false);
                    try output.appendSlice(allocator, "}\n\n");

                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::~");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "() {\n    if (silexOwnsResource) silexDropResource();\n}\n\n");
                } else {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::~");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "() {\n");
                    try self.generateStatements(allocator, &output, drop.statements, 1, false);
                    try output.appendSlice(allocator, "}\n\n");
                }
            }
        }
        for (structure.methods) |method| {
            try self.generateMethodSignature(allocator, &output, method, structure.generated_name, true);
            try output.appendSlice(allocator, " {\n");
            try self.generateCapturedParameterBindings(allocator, &output, method.parameters, 1);
            try self.generateStatements(allocator, &output, method.statements, 1, false);
            if (method.return_type != .void) try output.appendSlice(allocator, "    std::abort();\n");
            try output.appendSlice(allocator, "}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_native) continue;
        try self.generateFunctionSignature(allocator, &output, function, true);
        try output.appendSlice(allocator, " {\n");
        try self.generateCapturedParameterBindings(allocator, &output, function.parameters, 1);
        try self.generateStatements(allocator, &output, function.statements, 1, function.is_main);
        if (function.is_main and function.return_type == .void) try output.appendSlice(allocator, "    return 0;\n");
        if (function.return_type != .void) try output.appendSlice(allocator, "    std::abort();\n");
        try output.appendSlice(allocator, "}\n\n");
    }
    const main_function = for (program.functions) |function| {
        if (function.is_main) break function;
    } else unreachable;
    const main_returns_result = main_function.return_type != .void;
    try output.appendSlice(allocator,
        \\// -----------------------------------------------------------------------------
        \\
        \\} // namespace SilexGenerated
        \\
        \\namespace {
        \\int silexRuntimeArgumentCountValue = 0;
        \\char** silexRuntimeArgumentValues = nullptr;
        \\}
        \\
        \\extern "C" std::int64_t silexRuntimeArgumentCount() {
        \\    return silexRuntimeArgumentCountValue;
        \\}
        \\
        \\extern "C" const char* silexRuntimeArgumentValue(
        \\    std::int64_t index,
        \\    std::int64_t* length
        \\) {
        \\    if (index < 0 || index >= silexRuntimeArgumentCountValue) {
        \\        *length = 0;
        \\        return nullptr;
        \\    }
        \\    const char* value = silexRuntimeArgumentValues[index];
        \\    std::int64_t count = 0;
        \\    while (value[count] != '\0') ++count;
        \\    *length = count;
        \\    return value;
        \\}
        \\
        \\int main(int argumentCount, char** argumentValues) {
        \\    silexRuntimeArgumentCountValue = argumentCount;
        \\    silexRuntimeArgumentValues = argumentValues;
    );
    try output.appendSlice(allocator, if (main_returns_result)
        "    const auto result = SilexGenerated::silexMain();\n"
    else
        "    const int result = SilexGenerated::silexMain();\n");
    try output.appendSlice(allocator,
        \\    SilexGenerated::silexResetStaticFields();
        \\    if (SilexGenerated::silexLiveObjects != 0) {
        \\        std::cerr << "silex: runtime error: unreachable class graph was not collected\n";
        \\        return 1;
        \\    }
    );
    if (main_returns_result) {
        try output.appendSlice(allocator,
            \\    if (result.variant == 1) {
            \\        std::cerr << "error: " << result.get<std::string>(0) << '\n';
            \\        return 1;
            \\    }
            \\    return 0;
        );
    } else {
        try output.appendSlice(allocator, "    return result;\n");
    }
    try output.appendSlice(allocator, "}\n");
    return output.toOwnedSlice(allocator);
}
