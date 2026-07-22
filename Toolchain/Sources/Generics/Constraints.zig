const Types = @import("Types.zig");
const Support = @import("Support.zig");
const std = Types.std;
const Ast = Types.Ast;
const Parser = Types.Parser;
const Source = Types.Source;
const Allocator = Types.Allocator;
const SpecializeError = Types.SpecializeError;
const Binding = Types.Binding;
const State = Types.State;
const StructureSpecialization = Types.StructureSpecialization;
const EnumSpecialization = Types.EnumSpecialization;
const result_type_parameters = Types.result_type_parameters;
const result_success_types = Types.result_success_types;
const result_failure_types = Types.result_failure_types;
const result_variants = Types.result_variants;
const intrinsic_result = Types.intrinsic_result;
const intrinsic_function_source = Types.intrinsic_function_source;
const FunctionSpecialization = Types.FunctionSpecialization;
const MethodSpecialization = Types.MethodSpecialization;
const functionIsVisible = Support.functionIsVisible;
const fileSetContains = Support.fileSetContains;
const positionsEqual = Support.positionsEqual;
const typeNameToReturnType = Support.typeNameToReturnType;
const appendTypeName = Support.appendTypeName;
pub fn typeArgumentsSatisfyConstraints(
    self: anytype,
    parameters: []const Ast.TypeParameter,
    arguments: []const Ast.TypeName,
    source_file: usize,
) bool {
    for (parameters, arguments) |parameter, argument| {
        const constraint = parameter.constraint orelse continue;
        if (!self.typeConformsTo(argument, constraint.name, source_file)) return false;
    }
    return true;
}

pub fn validateTypeArgumentConstraints(
    self: anytype,
    parameters: []const Ast.TypeParameter,
    arguments: []const Ast.TypeName,
    position: Source.Position,
) SpecializeError!void {
    for (parameters, arguments) |parameter, argument| {
        const constraint = parameter.constraint orelse continue;
        if (self.typeConformsTo(argument, constraint.name, position.file)) continue;
        var argument_name: std.ArrayList(u8) = .empty;
        try appendTypeName(self.allocator, &argument_name, argument);
        const message = try std.fmt.allocPrint(
            self.allocator,
            "type argument '{s}' does not conform to protocol '{s}' required by '{s}'",
            .{ try argument_name.toOwnedSlice(self.allocator), constraint.name, parameter.name },
        );
        return self.fail(position, message);
    }
}

pub fn typeConformsTo(
    self: anytype,
    value: Ast.TypeName,
    protocol_name: []const u8,
    source_file: usize,
) bool {
    const structure_name = switch (value) {
        .structure => |name| name,
        else => return false,
    };
    return self.structureConformsTo(structure_name, protocol_name, source_file, 0);
}

pub fn structureConformsTo(
    self: anytype,
    structure_name: []const u8,
    protocol_name: []const u8,
    source_file: usize,
    depth: usize,
) bool {
    if (depth > self.program.structures.len + self.structures.items.len) return false;
    const structure = self.findAvailableStructure(structure_name) orelse return false;
    for (structure.conformances) |conformance| {
        if (!std.mem.eql(u8, conformance.name, protocol_name)) continue;
        if (conformance.extension_visible_files) |visible_files| {
            if (depth != 0 or !fileSetContains(visible_files, source_file)) continue;
        }
        return true;
    }
    if (structure.base) |base| {
        // Before module resolution, the parser temporarily stores a
        // first protocol in the base slot because ':' is intentionally
        // ambiguous between a class parent and a protocol.
        if (self.findProtocol(base.name) != null) {
            return std.mem.eql(u8, base.name, protocol_name);
        }
        return self.structureConformsTo(base.name, protocol_name, source_file, depth + 1);
    }
    return false;
}

pub fn findAvailableStructure(self: anytype, name: []const u8) ?*const Ast.Structure {
    for (self.structures.items) |*structure| {
        if (std.mem.eql(u8, structure.name, name)) return structure;
    }
    for (self.program.structures) |*structure| {
        if (std.mem.eql(u8, structure.name, name)) return structure;
    }
    return null;
}

pub fn findProtocol(self: anytype, name: []const u8) ?*const Ast.Protocol {
    for (self.program.protocols) |*protocol| {
        if (std.mem.eql(u8, protocol.name, name)) return protocol;
    }
    return null;
}

pub fn hasVisibleGenericFunction(
    self: anytype,
    name: []const u8,
    visible_declarations: ?[]const Source.Position,
) bool {
    for (self.function_templates) |function| {
        if (function.type_parameters.len != 0 and
            std.mem.eql(u8, function.name, name) and
            functionIsVisible(function, visible_declarations)) return true;
    }
    return false;
}

pub fn hasVisibleConcreteFunction(
    self: anytype,
    name: []const u8,
    visible_declarations: ?[]const Source.Position,
) bool {
    for (self.program.functions) |function| {
        if (function.type_parameters.len == 0 and
            std.mem.eql(u8, function.name, name) and
            functionIsVisible(function, visible_declarations)) return true;
    }
    return false;
}

pub fn activeConstraintRequires(self: anytype, method_name: []const u8) bool {
    for (self.active_constraint_protocols) |protocol_name| {
        const protocol = self.findProtocol(protocol_name) orelse continue;
        for (protocol.requirements) |requirement| {
            if (std.mem.eql(u8, requirement.name, method_name)) return true;
        }
    }
    return false;
}

pub fn genericTypeName(
    self: anytype,
    template_name: []const u8,
    arguments: []const Ast.TypeName,
) Allocator.Error![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(self.allocator, template_name);
    try output.append(self.allocator, '<');
    for (arguments, 0..) |argument, index| {
        if (index != 0) try output.appendSlice(self.allocator, ", ");
        try appendTypeName(self.allocator, &output, argument);
    }
    try output.append(self.allocator, '>');
    return output.toOwnedSlice(self.allocator);
}

pub fn fail(self: anytype, position: Source.Position, message: []const u8) Source.Error {
    self.diagnostic = .{ .position = position, .message = message };
    return error.InvalidSource;
}
