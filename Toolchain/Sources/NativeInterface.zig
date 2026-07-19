const std = @import("std");
const NativeDependency = @import("NativeDependency.zig");
const ProjectModule = @import("Project.zig");
const Semantic = @import("Semantic.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Header = struct {
    module_name: []const u8,
    contents: []const u8,
};

pub const Generated = struct {
    cache_root: []const u8,
    editor_root: []const u8,
};

pub fn write(
    allocator: Allocator,
    io: Io,
    program: Semantic.Program,
    project: ProjectModule.Project,
    runtimes: []const NativeDependency.ModuleRuntime,
    target_cache_dir: []const u8,
    artifact_root: []const u8,
) !?Generated {
    var headers: std.ArrayList(Header) = .empty;

    for (runtimes, 0..) |runtime, index| {
        const runtime_name = runtime.module_name;
        if (runtimeAppearedEarlier(runtimes[0..index], runtime_name)) continue;
        const header = try renderRuntimeHeader(allocator, program, project, runtime_name);
        try headers.append(allocator, .{ .module_name = runtime_name, .contents = header });
    }
    for (program.functions, 0..) |function, index| {
        if (!function.is_native or appearedEarlier(program.functions[0..index], function.native_module_name.?)) continue;
        if (hasHeader(headers.items, function.native_module_name.?)) continue;
        try headers.append(allocator, .{
            .module_name = function.native_module_name.?,
            .contents = try renderHeader(allocator, program, function.native_module_name.?),
        });
    }
    if (headers.items.len == 0) return null;

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("silex-native-interface-v2");
    for (headers.items) |header| {
        hasher.update("\x00module\x00");
        hasher.update(header.module_name);
        hasher.update("\x00header\x00");
        hasher.update(header.contents);
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    const key = std.fmt.bytesToHex(digest, .lower);
    const cache_root = try std.fs.path.join(allocator, &.{ target_cache_dir, "interfaces", &key });
    const editor_root = try std.fs.path.join(allocator, &.{ artifact_root, ".silex", "interfaces" });

    for (headers.items) |header| {
        const path = try headerPath(allocator, cache_root, header.module_name);
        if (std.fs.path.dirname(path)) |directory| try Io.Dir.cwd().createDirPath(io, directory);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = header.contents });
    }
    try synchronizeEditorHeaders(allocator, io, editor_root, headers.items, &key);
    return .{ .cache_root = cache_root, .editor_root = editor_root };
}

fn synchronizeEditorHeaders(
    allocator: Allocator,
    io: Io,
    root: []const u8,
    headers: []const Header,
    generation: []const u8,
) !void {
    try Io.Dir.cwd().createDirPath(io, root);
    var manifest: std.ArrayList(u8) = .empty;
    var current_paths: std.ArrayList([]const u8) = .empty;
    for (headers) |header| {
        const relative_path = try headerPath(allocator, "", header.module_name);
        try current_paths.append(allocator, relative_path);
        try manifest.appendSlice(allocator, relative_path);
        try manifest.append(allocator, '\n');

        const path = try std.fs.path.join(allocator, &.{ root, relative_path });
        if (std.fs.path.dirname(path)) |directory| try Io.Dir.cwd().createDirPath(io, directory);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = header.contents });
    }

    const manifest_path = try std.fs.path.join(allocator, &.{ root, ".headers" });
    const previous_manifest: ?[]const u8 = Io.Dir.cwd().readFileAlloc(
        io,
        manifest_path,
        allocator,
        .limited(1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (previous_manifest) |contents| {
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |relative_path| {
            if (relative_path.len == 0 or containsPath(current_paths.items, relative_path)) continue;
            if (!isSafeEditorHeaderPath(relative_path)) continue;
            const obsolete_path = try std.fs.path.join(allocator, &.{ root, relative_path });
            Io.Dir.cwd().deleteFile(io, obsolete_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
    }

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_path, .data = manifest.items });
    const generation_path = try std.fs.path.join(allocator, &.{ root, ".generation" });
    const generation_contents = try std.fmt.allocPrint(allocator, "{s}\n", .{generation});
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = generation_path, .data = generation_contents });
}

fn containsPath(paths: []const []const u8, candidate: []const u8) bool {
    for (paths) |path| if (std.mem.eql(u8, path, candidate)) return true;
    return false;
}

fn isSafeEditorHeaderPath(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path) or !std.mem.endsWith(u8, path, ".h")) return false;
    var components = std.mem.splitScalar(u8, path, std.fs.path.sep);
    const root = components.next() orelse return false;
    if (!std.mem.eql(u8, root, "SilexNative")) return false;
    var count: usize = 1;
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
        count += 1;
    }
    return count >= 2;
}

fn headerPath(allocator: Allocator, root: []const u8, module_name: []const u8) ![]const u8 {
    const module_path = try modulePath(allocator, module_name);
    const filename = try std.fmt.allocPrint(allocator, "{s}.h", .{module_path});
    return std.fs.path.join(allocator, &.{ root, "SilexNative", filename });
}

fn runtimeAppearedEarlier(runtimes: []const NativeDependency.ModuleRuntime, runtime_name: []const u8) bool {
    for (runtimes) |runtime| {
        if (std.mem.eql(u8, runtime.module_name, runtime_name)) return true;
    }
    return false;
}

fn hasHeader(headers: []const Header, module_name: []const u8) bool {
    for (headers) |header| {
        if (std.mem.eql(u8, header.module_name, module_name)) return true;
    }
    return false;
}

fn renderRuntimeHeader(
    allocator: Allocator,
    program: Semantic.Program,
    project: ProjectModule.Project,
    runtime_name: []const u8,
) ![]const u8 {
    var module_names: std.ArrayList([]const u8) = .empty;
    for (project.modules) |module| {
        const candidate = module.native_runtime_name orelse continue;
        if (!std.mem.eql(u8, candidate, runtime_name)) continue;
        for (module_names.items) |existing| {
            if (std.mem.eql(u8, existing, module.name)) break;
        } else try module_names.append(allocator, module.name);
    }
    return renderHeaderForModules(allocator, program, runtime_name, module_names.items);
}

fn appearedEarlier(functions: []const Semantic.Function, module_name: []const u8) bool {
    for (functions) |function| {
        if (!function.is_native) continue;
        if (std.mem.eql(u8, function.native_module_name.?, module_name)) return true;
    }
    return false;
}

fn renderHeader(
    allocator: Allocator,
    program: Semantic.Program,
    module_name: []const u8,
) ![]const u8 {
    return renderHeaderForModules(allocator, program, module_name, &.{module_name});
}

fn renderHeaderForModules(
    allocator: Allocator,
    program: Semantic.Program,
    header_name: []const u8,
    module_names: []const []const u8,
) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator, "#ifndef SILEX_NATIVE_");
    try appendGuardName(allocator, &output, header_name);
    try output.appendSlice(allocator, "_H\n#define SILEX_NATIVE_");
    try appendGuardName(allocator, &output, header_name);
    try output.appendSlice(
        allocator,
        "_H\n\n#include <stdbool.h>\n#include <stdint.h>\n\n#ifdef __cplusplus\n" ++
            "extern \"C\" {\n#endif\n\n",
    );

    var emitted_transports: std.ArrayList([]const u8) = .empty;
    for (program.functions) |function| {
        if (!function.is_native or !containsModule(module_names, function.native_module_name.?)) continue;
        const module_name = function.native_module_name.?;
        if (nativeResultShape(program, function.return_type)) |result| {
            if (structureForType(program, nativeBranchValueType(result.success_type))) |structure| {
                try appendTransportIfNew(allocator, &output, &emitted_transports, module_name, structure, false);
            }
            if (structureForType(program, nativeBranchValueType(result.failure_type))) |structure| {
                try appendTransportIfNew(allocator, &output, &emitted_transports, module_name, structure, false);
            }
            try appendResultTransportIfNew(allocator, &output, &emitted_transports, program, function, result);
        }
        if (returnedStructure(program, function)) |structure| {
            try appendTransportIfNew(allocator, &output, &emitted_transports, module_name, structure, false);
        }
        for (function.parameters) |parameter| {
            if (structureForType(program, parameter.type)) |structure| {
                try appendTransportIfNew(allocator, &output, &emitted_transports, module_name, structure, true);
            }
        }
    }

    for (program.functions) |function| {
        if (!function.is_native or !containsModule(module_names, function.native_module_name.?)) continue;
        try appendFunctionSignature(allocator, &output, program, function);
        try output.appendSlice(allocator, ";\n");
    }

    try output.appendSlice(
        allocator,
        "\n#ifdef __cplusplus\n}\n#endif\n\n#endif\n",
    );
    return output.toOwnedSlice(allocator);
}

fn containsModule(module_names: []const []const u8, module_name: []const u8) bool {
    for (module_names) |candidate| {
        if (std.mem.eql(u8, candidate, module_name)) return true;
    }
    return false;
}

fn appendGuardName(allocator: Allocator, output: *std.ArrayList(u8), module_name: []const u8) !void {
    for (module_name) |character| {
        const upper = if (character >= 'a' and character <= 'z') character - ('a' - 'A') else character;
        try output.append(allocator, if ((upper >= 'A' and upper <= 'Z') or (upper >= '0' and upper <= '9')) upper else '_');
    }
}

fn appendFunctionSignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
    function: Semantic.Function,
) !void {
    const result = nativeResultShape(program, function.return_type);
    const structure = returnedStructure(program, function);
    const returned = nativeReturnValueType(function.return_type);
    const returns_bytes = isNativeByteBufferReturnType(returned);
    const optional = function.return_type == .optional;
    if (result != null) {
        try output.appendSlice(allocator, "void");
    } else if (optional) {
        try output.appendSlice(allocator, "bool");
    } else if (returned == .str or returns_bytes or structure != null) {
        try output.appendSlice(allocator, "void");
    } else {
        try appendType(allocator, output, returned);
    }
    try output.append(allocator, ' ');
    try output.appendSlice(allocator, function.generated_name);
    try output.append(allocator, '(');
    var parameter_count: usize = 0;
    for (function.parameters) |parameter| {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        if (parameter.type == .str) {
            try output.appendSlice(allocator, "const char* ");
            try output.appendSlice(allocator, parameter.generated_name);
            try output.appendSlice(allocator, "Bytes, int64_t ");
            try output.appendSlice(allocator, parameter.generated_name);
            try output.appendSlice(allocator, "Length");
            parameter_count += 2;
            continue;
        }
        if (isNativeByteViewType(parameter.type)) {
            try output.appendSlice(allocator, "const uint8_t* ");
            try output.appendSlice(allocator, parameter.generated_name);
            try output.appendSlice(allocator, "Bytes, int64_t ");
            try output.appendSlice(allocator, parameter.generated_name);
            try output.appendSlice(allocator, "Length");
            parameter_count += 2;
            continue;
        }
        if (isNativeCallbackType(parameter.type)) {
            try appendCallbackParameter(allocator, output, parameter.type.function, parameter.generated_name);
            parameter_count += 2;
            continue;
        }
        if (structureForType(program, parameter.type)) |parameter_structure| {
            try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, try inputTransportName(
                allocator,
                function.native_module_name.?,
                parameter_structure.source_name,
                structureHasString(parameter_structure),
            ));
            try output.appendSlice(allocator, "* ");
            try output.appendSlice(allocator, parameter.generated_name);
            parameter_count += 1;
            continue;
        }
        try appendType(allocator, output, parameter.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, parameter.generated_name);
        parameter_count += 1;
    }
    if (result != null) {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try resultTransportName(
            allocator,
            function.native_module_name.?,
            function.native_function_name.?,
        ));
        try output.appendSlice(allocator, "* output");
    } else if (returned == .str) {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "char** output_bytes, int64_t* output_length");
    } else if (returns_bytes) {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "uint8_t** output_bytes, int64_t* output_length");
    } else if (structure) |returned_structure| {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try transportName(allocator, function.native_module_name.?, returned_structure.source_name));
        try output.appendSlice(allocator, "* output");
    } else if (optional) {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try appendType(allocator, output, returned);
        try output.appendSlice(allocator, "* output");
    }
    if (parameter_count == 0 and result == null and returned != .str and !returns_bytes and structure == null and !optional) try output.appendSlice(allocator, "void");
    try output.append(allocator, ')');
}

const NativeResultShape = struct {
    success_type: Semantic.Type,
    failure_type: Semantic.Type,
};

fn nativeResultShape(program: Semantic.Program, value: Semantic.Type) ?NativeResultShape {
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

fn nativeBranchValueType(value: Semantic.Type) Semantic.Type {
    return if (value == .optional) value.optional.* else value;
}

fn isNativeByteViewType(value: Semantic.Type) bool {
    return switch (value) {
        .list => |element| element.* == .uint8,
        .fixed_array => |array| array.element.* == .uint8,
        else => false,
    };
}

fn isNativeByteBufferReturnType(value: Semantic.Type) bool {
    return value == .list and value.list.* == .uint8;
}

fn isNativeCallbackType(value: Semantic.Type) bool {
    const function = switch (value) {
        .function => |function_value| function_value,
        else => return false,
    };
    if (function.owner != null) return false;
    if (function.return_type.* != .void and !isNativeCallbackScalarType(function.return_type.*)) return false;
    for (function.parameters, function.parameter_modes) |parameter, mode| {
        if (mode != .value or !isNativeCallbackScalarType(parameter)) return false;
    }
    return true;
}

fn isNativeCallbackScalarType(value: Semantic.Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool => true,
        else => false,
    };
}

fn appendCallbackParameter(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
    name: []const u8,
) !void {
    try appendType(allocator, output, callback.return_type.*);
    try output.appendSlice(allocator, " (*");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, ")(void*");
    for (callback.parameters) |parameter| {
        try output.appendSlice(allocator, ", ");
        try appendType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, "), void* ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, "_context");
}

fn appendResultTransportIfNew(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    program: Semantic.Program,
    function: Semantic.Function,
    result: NativeResultShape,
) !void {
    const name = try resultTransportName(allocator, function.native_module_name.?, function.native_function_name.?);
    for (emitted.items) |emitted_name| if (std.mem.eql(u8, emitted_name, name)) return;
    try emitted.append(allocator, name);

    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});
    try output.appendSlice(allocator, "typedef enum ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_success = 0,\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_failure = 1\n} ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, ";\n\ntypedef struct ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " tag;\n");
    try appendResultBranchFields(allocator, output, program, function.native_module_name.?, "success", result.success_type);
    try appendResultBranchFields(allocator, output, program, function.native_module_name.?, "failure", result.failure_type);
    try output.appendSlice(allocator, "} ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, ";\n\n");
}

fn appendResultBranchFields(
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
        try output.appendSlice(allocator, "_present;\n");
    }
    const value = nativeBranchValueType(branch_type);
    if (value == .void) return;
    if (isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "    uint8_t* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_bytes;\n    int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_length;\n");
    } else if (value == .str) {
        try output.appendSlice(allocator, "    char* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_bytes;\n    int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_length;\n");
    } else if (structureForType(program, value)) |structure| {
        try output.appendSlice(allocator, "    ");
        try output.appendSlice(allocator, try transportName(allocator, module_name, structure.source_name));
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_value;\n");
    } else {
        try output.appendSlice(allocator, "    ");
        try appendType(allocator, output, value);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "_value;\n");
    }
}

fn appendTransportIfNew(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    const transport_name = if (input)
        try inputTransportName(allocator, module_name, structure.source_name, structureHasString(structure))
    else
        try transportName(allocator, module_name, structure.source_name);
    for (emitted.items) |emitted_name| {
        if (std.mem.eql(u8, emitted_name, transport_name)) return;
    }
    try emitted.append(allocator, transport_name);
    try appendTransportDefinition(allocator, output, module_name, structure, input);
    try output.append(allocator, '\n');
}

fn appendTransportDefinition(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    const name = if (input)
        try inputTransportName(allocator, module_name, structure.source_name, structureHasString(structure))
    else
        try transportName(allocator, module_name, structure.source_name);
    try output.appendSlice(allocator, "#define SILEX_NATIVE_TRANSPORT_");
    try appendGuardName(allocator, output, name);
    try output.appendSlice(allocator, " 1\n");
    try output.appendSlice(allocator, "typedef struct ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, " {\n");
    if (structure.fields.len == 0) {
        try output.appendSlice(allocator, "    uint8_t _silex_unused;\n");
    } else for (structure.fields) |field| {
        try output.appendSlice(allocator, "    ");
        if (field.type == .str) {
            try output.appendSlice(allocator, if (input) "const char* " else "char* ");
            try output.appendSlice(allocator, field.source_name);
            try output.appendSlice(allocator, "_bytes;\n    int64_t ");
            try output.appendSlice(allocator, field.source_name);
            try output.appendSlice(allocator, "_length;\n");
            continue;
        }
        try appendType(allocator, output, field.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, field.source_name);
        try output.appendSlice(allocator, ";\n");
    }
    try output.appendSlice(allocator, "} ");
    try output.appendSlice(allocator, name);
    try output.append(allocator, ';');
}

fn returnedStructure(program: Semantic.Program, function: Semantic.Function) ?Semantic.Structure {
    return structureForType(program, nativeReturnValueType(function.return_type));
}

fn structureForType(program: Semantic.Program, value: Semantic.Type) ?Semantic.Structure {
    const structure_type = switch (value) {
        .structure => |structure| structure,
        else => return null,
    };
    for (program.structures) |structure| {
        if (std.mem.eql(u8, structure.generated_name, structure_type.generated_name)) return structure;
    }
    return null;
}

fn nativeReturnValueType(return_type: Semantic.Type) Semantic.Type {
    return if (return_type == .optional) return_type.optional.* else return_type;
}

pub fn transportName(allocator: Allocator, module_name: []const u8, structure_name: []const u8) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator, "SilexNative_");
    for (module_name) |character| try output.append(allocator, if (character == '.') '_' else character);
    try output.append(allocator, '_');
    const name = if (std.mem.lastIndexOfScalar(u8, structure_name, '.')) |separator|
        structure_name[separator + 1 ..]
    else
        structure_name;
    try output.appendSlice(allocator, name);
    return output.toOwnedSlice(allocator);
}

pub fn inputTransportName(
    allocator: Allocator,
    module_name: []const u8,
    structure_name: []const u8,
    has_string_fields: bool,
) ![]const u8 {
    const base = try transportName(allocator, module_name, structure_name);
    if (!has_string_fields) return base;
    return std.fmt.allocPrint(allocator, "{s}Input", .{base});
}

pub fn resultTransportName(
    allocator: Allocator,
    module_name: []const u8,
    function_name: []const u8,
) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator, "SilexNative_");
    for (module_name) |character| try output.append(allocator, if (character == '.') '_' else character);
    try output.append(allocator, '_');
    try output.appendSlice(allocator, function_name);
    try output.appendSlice(allocator, "Result");
    return output.toOwnedSlice(allocator);
}

fn structureHasString(structure: Semantic.Structure) bool {
    for (structure.fields) |field| if (field.type == .str) return true;
    return false;
}

fn appendType(allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) !void {
    const name = switch (type_name) {
        .void => "void",
        .int => "int64_t",
        .int8 => "int8_t",
        .int16 => "int16_t",
        .int32 => "int32_t",
        .uint8 => "uint8_t",
        .uint16 => "uint16_t",
        .uint32 => "uint32_t",
        .uint64 => "uint64_t",
        .float => "float",
        .float64 => "double",
        .bool => "bool",
        .str => unreachable,
        else => unreachable,
    };
    try output.appendSlice(allocator, name);
}

fn modulePath(allocator: Allocator, module_name: []const u8) ![]const u8 {
    const path = try allocator.dupe(u8, module_name);
    for (path) |*character| {
        if (character.* == '.') character.* = std.fs.path.sep;
    }
    return path;
}

test "stable editor headers track one generated interface" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const temporary_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const editor_root = try std.fs.path.join(allocator, &.{ temporary_root, "interfaces" });

    try synchronizeEditorHeaders(allocator, std.testing.io, editor_root, &.{
        .{ .module_name = "Math", .contents = "old Math\n" },
        .{ .module_name = "Removed.Module", .contents = "obsolete\n" },
    }, "first-generation");
    try synchronizeEditorHeaders(allocator, std.testing.io, editor_root, &.{
        .{ .module_name = "Math", .contents = "new Math\n" },
    }, "second-generation");

    const math_path = try std.fs.path.join(allocator, &.{ editor_root, "SilexNative", "Math.h" });
    const math = try Io.Dir.cwd().readFileAlloc(std.testing.io, math_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("new Math\n", math);
    const removed_path = try std.fs.path.join(allocator, &.{ editor_root, "SilexNative", "Removed", "Module.h" });
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().access(std.testing.io, removed_path, .{}));
    const generation_path = try std.fs.path.join(allocator, &.{ editor_root, ".generation" });
    const generation = try Io.Dir.cwd().readFileAlloc(std.testing.io, generation_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("second-generation\n", generation);
}

test "selected runtimes receive an empty root header without native declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const target_cache_dir = try std.fs.path.join(allocator, &.{
        ".zig-cache",
        "tmp",
        &temporary.sub_path,
        "target",
    });
    const project: ProjectModule.Project = .{
        .program_name = "Main",
        .target_module = 0,
        .modules = &.{.{
            .name = "Pure",
            .sources = &.{"Pure.sx"},
            .native_runtime_name = "Pure",
        }},
        .single_file = true,
    };
    const runtime: NativeDependency.ModuleRuntime = .{
        .module_name = "Pure",
        .module_directory = "Pure",
        .manifest_path = "Pure/@Module.json",
        .sources = &.{},
        .include_dirs = &.{},
        .defines = &.{},
        .system_libraries = &.{},
        .frameworks = &.{},
    };
    const program: Semantic.Program = .{
        .enums = &.{},
        .protocols = &.{},
        .structures = &.{},
        .functions = &.{},
    };

    const artifact_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", &temporary.sub_path });
    const generated = (try write(
        allocator,
        std.testing.io,
        program,
        project,
        &.{runtime},
        target_cache_dir,
        artifact_root,
    )).?;
    const path = try std.fs.path.join(allocator, &.{ generated.cache_root, "SilexNative", "Pure.h" });
    const header = try Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(4096));
    try std.testing.expect(std.mem.indexOf(u8, header, "#ifndef SILEX_NATIVE_PURE_H") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "extern \"C\"") != null);
    const editor_path = try std.fs.path.join(allocator, &.{ generated.editor_root, "SilexNative", "Pure.h" });
    const editor_header = try Io.Dir.cwd().readFileAlloc(std.testing.io, editor_path, allocator, .limited(4096));
    try std.testing.expectEqualStrings(header, editor_header);
}

test "native headers are C compatible and preserve the string ABI" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "native func native_echo(value:str) str\n" ++
            "native func native_ready() bool\n" ++
            "func main() {}\n",
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "STD.Console.native_echo";
    @constCast(ast.functions)[1].name = "STD.Console.native_ready";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"STD.Console"};
    const program = try analyzer.analyze(ast);
    const header = try renderHeader(allocator, program, "STD.Console");

    try std.testing.expect(std.mem.indexOf(u8, header, "#include <stdbool.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "#include <stdint.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "extern \"C\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "std::") == null);
    try std.testing.expect(std.mem.indexOf(u8, header, "const char* silexValue0Bytes, int64_t silexValue0Length") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "char** output_bytes, int64_t* output_length") != null);
}

test "native headers define scalar structure transports" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeDimensions {
        \\    let columns:int
        \\    let rows:int
        \\    static var cached:int
        \\    func total() int { return self.columns + self.rows }
        \\}
        \\native func native_dimensions() NativeDimensions
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "STD.Console.native_dimensions";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"STD.Console"};
    const program = try analyzer.analyze(ast);
    const header = try renderHeader(allocator, program, "STD.Console");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "typedef struct SilexNative_STD_Console_NativeDimensions {",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t columns;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t rows;") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_STD_Console_native_dimensions(SilexNative_STD_Console_NativeDimensions* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "cached") == null);
}

test "native headers define string structure fields as owned bytes and lengths" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeMessage { let code:int; let title:str; let detail:str }
        \\native func native_message() NativeMessage
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Events.native_message";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Events"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Events");

    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t code;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "char* title_bytes;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t title_length;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "char* detail_bytes;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t detail_length;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "std::string") == null);
}

test "native headers define optional return presence and outputs" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Message { let code:int; let text:str }
        \\native func native_integer() int?
        \\native func native_text(handle:int) str?
        \\native func native_message() Message?
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Events.native_integer";
    @constCast(ast.functions)[1].name = "Events.native_text";
    @constCast(ast.functions)[2].name = "Events.native_message";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Events"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Events");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "bool silexNative_Events_native_integer(int64_t* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "bool silexNative_Events_native_text(int64_t silexValue0, char** output_bytes, int64_t* output_length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "bool silexNative_Events_native_message(SilexNative_Events_Message* output);",
    ) != null);
}

test "native headers reuse scalar structure transports for const parameters" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeBounds { let width:int; let height:int }
        \\native func native_round_trip(first:NativeBounds, second:NativeBounds) NativeBounds
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Geometry.native_round_trip";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Geometry"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Geometry");

    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, header, "typedef struct SilexNative_Geometry_NativeBounds"),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_Geometry_native_round_trip(const SilexNative_Geometry_NativeBounds* silexValue0, const SilexNative_Geometry_NativeBounds* silexValue1, SilexNative_Geometry_NativeBounds* output);",
    ) != null);
}

test "native headers separate borrowed string inputs from owned outputs" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeRequest { let path:str; let mode:int; let note:str }
        \\native func native_round_trip(request:NativeRequest) NativeRequest
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Files.native_round_trip";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Files"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Files");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "typedef struct SilexNative_Files_NativeRequest {\n    char* path_bytes;",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "typedef struct SilexNative_Files_NativeRequestInput {\n    const char* path_bytes;",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "const char* note_bytes;") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_Files_native_round_trip(const SilexNative_Files_NativeRequestInput* silexValue0, SilexNative_Files_NativeRequest* output);",
    ) != null);
}

test "native headers expose tagged Result outputs" {
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeFile { let handle:int; let path:str }
        \\native func native_open(path:str) Result<NativeFile,str>
        \\native func native_save() Result<void,str>
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Files.native_open";
    @constCast(ast.functions)[1].name = "Files.native_save";
    var specializer = Generics.Specializer.init(allocator, ast);
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Files"};
    const header = try renderHeader(allocator, try analyzer.analyze(try specializer.specialize()), "Files");

    try std.testing.expect(std.mem.indexOf(u8, header, "SilexNative_Files_native_openResultTag_success = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "SilexNative_Files_native_openResultTag_failure = 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "SilexNative_Files_NativeFile success_value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "char* failure_bytes;") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_Files_native_open(const char* silexValue0Bytes, int64_t silexValue0Length, SilexNative_Files_native_openResult* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "SilexNative_Files_native_saveResultTag tag;") != null);
}

test "native headers expose uint8 collections as borrowed byte views" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_checksum(bytes:uint8[]) uint64
        \\native func native_write_block(bytes:uint8[512]) bool
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Bytes.native_checksum";
    @constCast(ast.functions)[1].name = "Bytes.native_write_block";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Bytes"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Bytes");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "uint64_t silexNative_Bytes_native_checksum(const uint8_t* silexValue0Bytes, int64_t silexValue0Length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "bool silexNative_Bytes_native_write_block(const uint8_t* silexValue1Bytes, int64_t silexValue1Length);",
    ) != null);
}

test "native headers expose synchronous scalar callbacks" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_visit(limit:int, visitor:func(int) bool) int
        \\native func native_notify(visitor:func()) void
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Visitors.native_visit";
    @constCast(ast.functions)[1].name = "Visitors.native_notify";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Visitors"};
    const header = try renderHeader(allocator, try analyzer.analyze(ast), "Visitors");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "int64_t silexNative_Visitors_native_visit(int64_t silexValue0, bool (*silexValue1)(void*, int64_t), void* silexValue1_context);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_Visitors_native_notify(void (*silexValue0)(void*), void* silexValue0_context);",
    ) != null);
}

test "native headers expose owned uint8 list returns" {
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_compress(bytes:uint8[]) uint8[]
        \\native func native_read(path:str) Result<uint8[],str>
        \\func main() {}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Bytes.native_compress";
    @constCast(ast.functions)[1].name = "Bytes.native_read";
    var specializer = Generics.Specializer.init(allocator, ast);
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Bytes"};
    const header = try renderHeader(allocator, try analyzer.analyze(try specializer.specialize()), "Bytes");

    try std.testing.expect(std.mem.indexOf(
        u8,
        header,
        "void silexNative_Bytes_native_compress(const uint8_t* silexValue0Bytes, int64_t silexValue0Length, uint8_t** output_bytes, int64_t* output_length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "uint8_t* success_bytes;") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "int64_t success_length;") != null);
}
