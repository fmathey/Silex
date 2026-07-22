pub const std = @import("std");
pub const Ast = @import("../Ast.zig");
pub const Parser = @import("../Parser.zig").Parser;
pub const Source = @import("../Source.zig");

pub const Allocator = std.mem.Allocator;
pub const SpecializeError = Source.Error || Allocator.Error;

pub const Binding = struct {
    name: []const u8,
    value: Ast.TypeName,
};

pub const State = enum { visiting, done };

pub const StructureSpecialization = struct {
    template_name: []const u8,
    name: []const u8,
    state: State,
};

pub const EnumSpecialization = struct {
    template_name: []const u8,
    name: []const u8,
    state: State,
};

pub const result_type_parameters = [_]Ast.TypeParameter{
    .{ .name = "T", .position = .{ .line = 1, .column = 1 } },
    .{ .name = "E", .position = .{ .line = 1, .column = 1 } },
};
pub const result_success_types = [_]Ast.TypeName{.{ .type_parameter = "T" }};
pub const result_failure_types = [_]Ast.TypeName{.{ .type_parameter = "E" }};
pub const result_variants = [_]Ast.EnumVariant{
    .{ .name = "success", .position = .{ .line = 1, .column = 1 }, .associated_types = &result_success_types },
    .{ .name = "failure", .position = .{ .line = 1, .column = 1 }, .associated_types = &result_failure_types },
};
pub const intrinsic_result = Ast.Enum{
    .is_public = true,
    .position = .{ .line = 1, .column = 1 },
    .name = "Result",
    .name_position = .{ .line = 1, .column = 1 },
    .type_parameters = &result_type_parameters,
    .variants = &result_variants,
};

pub const intrinsic_function_source =
    \\func map_error<T, E, F>(result:Result<T,E>, transform:func(E) F) Result<T,F> {
    \\    match move result {
    \\        success(var value) => { return Result<T,F>.success(move value) }
    \\        failure(var error) => {
    \\            return Result<T,F>.failure(transform(move error))
    \\        }
    \\    }
    \\    panic("invalid intrinsic Result variant")
    \\}
    \\func map_error<E, F>(result:Result<void,E>, transform:func(E) F) Result<void,F> {
    \\    match move result {
    \\        success => { return Result<void,F>.success() }
    \\        failure(var error) => {
    \\            return Result<void,F>.failure(transform(move error))
    \\        }
    \\    }
    \\    panic("invalid intrinsic Result variant")
    \\}
;

pub const FunctionSpecialization = struct {
    template_position: Source.Position,
    name: []const u8,
    state: State,
};

pub const MethodSpecialization = struct {
    target_name: []const u8,
    template_position: Source.Position,
    name: []const u8,
    state: State,
    method: ?Ast.Function = null,
};
