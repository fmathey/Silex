const std = @import("std");
const Semantic = @import("Semantic.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn write(
    allocator: Allocator,
    io: Io,
    program: Semantic.Program,
    target_cache_dir: []const u8,
) !?[]const u8 {
    var has_native_function = false;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("silex-native-interface-v1");

    for (program.functions, 0..) |function, index| {
        if (!function.is_native or appearedEarlier(program.functions[0..index], function.native_module_name.?)) continue;
        has_native_function = true;
        const header = try renderHeader(allocator, program, function.native_module_name.?);
        hasher.update("\x00module\x00");
        hasher.update(function.native_module_name.?);
        hasher.update("\x00header\x00");
        hasher.update(header);
    }
    if (!has_native_function) return null;

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    const key = std.fmt.bytesToHex(digest, .lower);
    const root = try std.fs.path.join(allocator, &.{ target_cache_dir, "interfaces", &key });

    for (program.functions, 0..) |function, index| {
        if (!function.is_native or appearedEarlier(program.functions[0..index], function.native_module_name.?)) continue;
        const header = try renderHeader(allocator, program, function.native_module_name.?);
        const module_path = try modulePath(allocator, function.native_module_name.?);
        const filename = try std.fmt.allocPrint(allocator, "{s}.h", .{module_path});
        const path = try std.fs.path.join(allocator, &.{ root, "SilexNative", filename });
        if (std.fs.path.dirname(path)) |directory| try Io.Dir.cwd().createDirPath(io, directory);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = header });
    }
    return root;
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
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator, "#ifndef SILEX_NATIVE_");
    try appendGuardName(allocator, &output, module_name);
    try output.appendSlice(allocator, "_H\n#define SILEX_NATIVE_");
    try appendGuardName(allocator, &output, module_name);
    try output.appendSlice(
        allocator,
        "_H\n\n#include <stdbool.h>\n#include <stdint.h>\n\n#ifdef __cplusplus\n" ++
            "extern \"C\" {\n#endif\n\n",
    );

    for (program.functions, 0..) |function, index| {
        if (!function.is_native or !std.mem.eql(u8, function.native_module_name.?, module_name)) continue;
        const structure = returnedStructure(program, function) orelse continue;
        if (returnedStructureAppearedEarlier(program, program.functions[0..index], function, structure)) continue;
        try appendTransportDefinition(allocator, &output, module_name, structure);
        try output.append(allocator, '\n');
    }

    for (program.functions) |function| {
        if (!function.is_native or !std.mem.eql(u8, function.native_module_name.?, module_name)) continue;
        try appendFunctionSignature(allocator, &output, program, function);
        try output.appendSlice(allocator, ";\n");
    }

    try output.appendSlice(
        allocator,
        "\n#ifdef __cplusplus\n}\n#endif\n\n#endif\n",
    );
    return output.toOwnedSlice(allocator);
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
    const structure = returnedStructure(program, function);
    if (function.return_type == .str or structure != null) {
        try output.appendSlice(allocator, "void");
    } else {
        try appendType(allocator, output, function.return_type);
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
        try appendType(allocator, output, parameter.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, parameter.generated_name);
        parameter_count += 1;
    }
    if (function.return_type == .str) {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "char** output_bytes, int64_t* output_length");
    } else if (structure) |returned| {
        if (parameter_count != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try transportName(allocator, function.native_module_name.?, returned.source_name));
        try output.appendSlice(allocator, "* output");
    }
    if (parameter_count == 0 and function.return_type != .str and structure == null) try output.appendSlice(allocator, "void");
    try output.append(allocator, ')');
}

fn appendTransportDefinition(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    structure: Semantic.Structure,
) !void {
    const name = try transportName(allocator, module_name, structure.source_name);
    try output.appendSlice(allocator, "typedef struct ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, " {\n");
    if (structure.fields.len == 0) {
        try output.appendSlice(allocator, "    uint8_t _silex_unused;\n");
    } else for (structure.fields) |field| {
        try output.appendSlice(allocator, "    ");
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
    const structure_type = switch (function.return_type) {
        .structure => |value| value,
        else => return null,
    };
    for (program.structures) |structure| {
        if (std.mem.eql(u8, structure.generated_name, structure_type.generated_name)) return structure;
    }
    return null;
}

fn returnedStructureAppearedEarlier(
    program: Semantic.Program,
    functions: []const Semantic.Function,
    function: Semantic.Function,
    structure: Semantic.Structure,
) bool {
    for (functions) |previous| {
        if (!previous.is_native or !std.mem.eql(u8, previous.native_module_name.?, function.native_module_name.?)) continue;
        const previous_structure = returnedStructure(program, previous) orelse continue;
        if (std.mem.eql(u8, previous_structure.source_name, structure.source_name)) return true;
    }
    return false;
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
