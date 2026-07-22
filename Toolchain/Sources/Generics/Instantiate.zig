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
pub fn findTemplate(self: anytype, name: []const u8) ?*const Ast.Structure {
    for (self.program.structures) |*structure| {
        if (structure.type_parameters.len != 0 and std.mem.eql(u8, structure.name, name)) return structure;
    }
    return null;
}

pub fn findEnumTemplate(self: anytype, name: []const u8) ?*const Ast.Enum {
    if (std.mem.eql(u8, name, "Result")) return &intrinsic_result;
    for (self.program.enums) |*enum_value| {
        if (enum_value.type_parameters.len != 0 and std.mem.eql(u8, enum_value.name, name)) return enum_value;
    }
    return null;
}

pub fn findConcreteEnum(self: anytype, name: []const u8) ?*const Ast.Enum {
    for (self.program.enums) |*enum_value| {
        if (enum_value.type_parameters.len == 0 and std.mem.eql(u8, enum_value.name, name)) return enum_value;
    }
    return null;
}

pub fn findConcreteStructure(self: anytype, name: []const u8) ?*const Ast.Structure {
    for (self.program.structures) |*structure| {
        if (structure.type_parameters.len == 0 and std.mem.eql(u8, structure.name, name)) return structure;
    }
    return null;
}

pub fn instantiateFunctions(
    self: anytype,
    template_name: []const u8,
    arguments: []const Ast.TypeName,
    visible_declarations: ?[]const Source.Position,
    position: Source.Position,
) SpecializeError![]const u8 {
    if (std.mem.eql(u8, template_name, "map_error")) {
        if (arguments.len == 3 and arguments[0] == .void) {
            return self.fail(position, "map_error for Result<void,E> expects 2 type arguments: E and F");
        }
        if (arguments.len >= 2 and arguments[arguments.len - 1] == .void) {
            return self.fail(position, "map_error target error type cannot be 'void'");
        }
    }
    const name = try self.genericTypeName(template_name, arguments);
    var generic_count: usize = 0;
    var matching_count: usize = 0;
    var expected_arity: ?usize = null;
    var arities_match = true;

    for (self.function_templates) |*function| {
        if (function.type_parameters.len == 0 or
            !std.mem.eql(u8, function.name, template_name) or
            !functionIsVisible(function.*, visible_declarations)) continue;
        generic_count += 1;
        if (expected_arity) |expected| {
            if (expected != function.type_parameters.len) arities_match = false;
        } else expected_arity = function.type_parameters.len;
        if (function.type_parameters.len != arguments.len) continue;
        matching_count += 1;
        try self.instantiateFunction(function.*, arguments, name, position);
    }

    if (generic_count == 0) {
        const message = if (self.hasVisibleConcreteFunction(template_name, visible_declarations))
            try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept type arguments", .{template_name})
        else
            try std.fmt.allocPrint(self.allocator, "unknown generic function '{s}'", .{template_name});
        return self.fail(position, message);
    }
    if (matching_count == 0) {
        const message = if (arities_match)
            try std.fmt.allocPrint(
                self.allocator,
                "generic function '{s}' expects {d} type argument{s}, found {d}",
                .{ template_name, expected_arity.?, if (expected_arity.? == 1) "" else "s", arguments.len },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "generic function '{s}' has no overload accepting {d} type arguments",
                .{ template_name, arguments.len },
            );
        return self.fail(position, message);
    }
    return name;
}

pub fn instantiateFunction(
    self: anytype,
    template: Ast.Function,
    arguments: []const Ast.TypeName,
    name: []const u8,
    position: Source.Position,
) SpecializeError!void {
    try self.validateTypeArgumentConstraints(template.type_parameters, arguments, position);
    for (self.function_specializations.items) |specialization| {
        if (!positionsEqual(specialization.template_position, template.name_position)) continue;
        if (std.mem.eql(u8, specialization.name, name)) return;
        if (specialization.state == .visiting) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "generic function '{s}' recursively expands with different type arguments",
                .{template.name},
            );
            return self.fail(position, message);
        }
    }

    const specialization_index = self.function_specializations.items.len;
    try self.function_specializations.append(self.allocator, .{
        .template_position = template.name_position,
        .name = name,
        .state = .visiting,
    });
    const bindings = try self.allocator.alloc(Binding, arguments.len);
    for (template.type_parameters, arguments, 0..) |parameter, argument, index| {
        bindings[index] = .{ .name = parameter.name, .value = argument };
    }

    var constraint_protocols: std.ArrayList([]const u8) = .empty;
    for (template.type_parameters) |parameter| {
        if (parameter.constraint) |constraint| try constraint_protocols.append(self.allocator, constraint.name);
    }
    const previous_constraints = self.active_constraint_protocols;
    const previous_visibility_file = self.active_extension_visibility_file;
    self.active_constraint_protocols = try constraint_protocols.toOwnedSlice(self.allocator);
    self.active_extension_visibility_file = position.file;
    defer {
        self.active_constraint_protocols = previous_constraints;
        self.active_extension_visibility_file = previous_visibility_file;
    }

    var concrete = try self.rewriteFunction(template, bindings);
    concrete.name = name;
    concrete.type_parameters = &.{};
    try self.functions.append(self.allocator, concrete);
    self.function_specializations.items[specialization_index].state = .done;
}

pub fn instantiateMethods(
    self: anytype,
    template_name: []const u8,
    arguments: []const Ast.TypeName,
    visibility_file: usize,
    position: Source.Position,
) SpecializeError![]const u8 {
    const name = try self.genericTypeName(template_name, arguments);
    var generic_count: usize = 0;
    var matching_arity: usize = 0;
    var expected_arity: ?usize = null;
    var arities_match = true;
    var instantiated = false;
    var constrained_candidate: ?*const Ast.Function = null;
    for (self.program.extensions) |extension| {
        for (extension.methods) |*method| {
            if (method.type_parameters.len == 0 or
                !std.mem.eql(u8, method.name, template_name)) continue;
            if (method.extension_visible_files) |visible_files| {
                if (!fileSetContains(visible_files, visibility_file)) continue;
            }
            generic_count += 1;
            if (expected_arity) |expected| {
                if (expected != method.type_parameters.len) arities_match = false;
            } else expected_arity = method.type_parameters.len;
            if (method.type_parameters.len != arguments.len) continue;
            matching_arity += 1;
            constrained_candidate = method;
            if (!self.typeArgumentsSatisfyConstraints(method.type_parameters, arguments, visibility_file)) continue;
            try self.instantiateMethod(extension.target, method.*, arguments, name, position);
            instantiated = true;
        }
    }
    if (generic_count != 0 and matching_arity == 0) {
        if (arities_match) {
            const count = expected_arity.?;
            const message = try std.fmt.allocPrint(
                self.allocator,
                "generic extension method '{s}' expects {d} type argument{s}, found {d}",
                .{ template_name, count, if (count == 1) "" else "s", arguments.len },
            );
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "no generic extension method '{s}' accepts {d} type arguments", .{ template_name, arguments.len });
        return self.fail(position, message);
    }
    if (!instantiated and constrained_candidate != null) {
        try self.validateTypeArgumentConstraints(constrained_candidate.?.type_parameters, arguments, position);
    }
    return name;
}

pub fn genericExtensionMethodRequiresArguments(self: anytype, name: []const u8, visibility_file: usize) bool {
    var generic_visible = false;
    for (self.program.structures) |structure| {
        for (structure.methods) |method| {
            if (method.type_parameters.len == 0 and std.mem.eql(u8, method.name, name)) return false;
        }
    }
    for (self.program.extensions) |extension| {
        for (extension.methods) |method| {
            if (!std.mem.eql(u8, method.name, name)) continue;
            if (method.extension_visible_files) |visible_files| {
                if (!fileSetContains(visible_files, visibility_file)) continue;
            }
            if (method.type_parameters.len == 0) return false;
            generic_visible = true;
        }
    }
    return generic_visible;
}

pub fn instantiateMethod(
    self: anytype,
    target_name: []const u8,
    template: Ast.Function,
    arguments: []const Ast.TypeName,
    name: []const u8,
    position: Source.Position,
) SpecializeError!void {
    for (self.method_specializations.items) |specialization| {
        if (!positionsEqual(specialization.template_position, template.name_position)) continue;
        if (std.mem.eql(u8, specialization.name, name)) return;
        if (specialization.state == .visiting) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "generic extension method '{s}' recursively expands with different type arguments",
                .{template.name},
            );
            return self.fail(position, message);
        }
    }

    const specialization_index = self.method_specializations.items.len;
    try self.method_specializations.append(self.allocator, .{
        .target_name = target_name,
        .template_position = template.name_position,
        .name = name,
        .state = .visiting,
    });
    const bindings = try self.allocator.alloc(Binding, arguments.len);
    for (template.type_parameters, arguments, 0..) |parameter, argument, index| {
        bindings[index] = .{ .name = parameter.name, .value = argument };
    }

    var constraint_protocols: std.ArrayList([]const u8) = .empty;
    for (template.type_parameters) |parameter| {
        if (parameter.constraint) |constraint| try constraint_protocols.append(self.allocator, constraint.name);
    }
    const previous_constraints = self.active_constraint_protocols;
    const previous_visibility_file = self.active_extension_visibility_file;
    self.active_constraint_protocols = try constraint_protocols.toOwnedSlice(self.allocator);
    self.active_extension_visibility_file = position.file;
    defer {
        self.active_constraint_protocols = previous_constraints;
        self.active_extension_visibility_file = previous_visibility_file;
    }

    var concrete = try self.rewriteFunction(template, bindings);
    concrete.name = name;
    concrete.type_parameters = &.{};
    self.method_specializations.items[specialization_index].method = concrete;
    self.method_specializations.items[specialization_index].state = .done;
}
