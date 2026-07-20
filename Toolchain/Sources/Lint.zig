const std = @import("std");
const Ast = @import("Ast.zig");
const ParserModule = @import("Parser.zig");
const ProjectModule = @import("Project.zig");
const Semantic = @import("Semantic.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Severity = enum { warning };

pub const Diagnostic = struct {
    position: Source.Position,
    severity: Severity = .warning,
    source: []const u8 = "silex lint",
    code: []const u8,
    message: []const u8,
};

const LocatedDiagnostic = struct {
    path: []const u8,
    diagnostic: Diagnostic,
    parse_error: bool = false,
};

pub fn run(allocator: Allocator, io: Io, input_path: []const u8) !u8 {
    const project = try ProjectModule.load(allocator, io, input_path);
    var located: std.ArrayList(LocatedDiagnostic) = .empty;
    for (project.modules) |module| for (module.sources) |path| {
        const source = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
            std.debug.print("silex: unable to read source '{s}': {t}\n", .{ path, err });
            return error.Reported;
        };
        var parser = ParserModule.Parser.init(allocator, source);
        const program = parser.parse() catch |err| switch (err) {
            error.InvalidSource => {
                try located.append(allocator, .{
                    .path = path,
                    .diagnostic = .{
                        .position = parser.diagnostic.?.position,
                        .source = "silex",
                        .code = "",
                        .message = parser.diagnostic.?.message,
                    },
                    .parse_error = true,
                });
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        const diagnostics = try analyze(allocator, program);
        for (diagnostics) |diagnostic| try located.append(allocator, .{
            .path = path,
            .diagnostic = diagnostic,
        });
    };

    insertionSortLocated(located.items);
    for (located.items) |item| {
        if (item.parse_error) {
            std.debug.print("{s}:{d}:{d}: error: {s}\n", .{
                item.path,
                item.diagnostic.position.line,
                item.diagnostic.position.column,
                item.diagnostic.message,
            });
        } else {
            std.debug.print("{s}:{d}:{d}: warning[{s}]: {s}\n", .{
                item.path,
                item.diagnostic.position.line,
                item.diagnostic.position.column,
                item.diagnostic.code,
                item.diagnostic.message,
            });
        }
    }
    return if (located.items.len == 0) 0 else 1;
}

pub fn analyze(allocator: Allocator, program: Ast.Program) ![]const Diagnostic {
    var analyzer = Analyzer{ .allocator = allocator };
    try analyzer.program(program);
    insertionSortDiagnostics(analyzer.diagnostics.items);
    return analyzer.diagnostics.toOwnedSlice(allocator);
}

const Analyzer = struct {
    allocator: Allocator,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    fn program(self: *Analyzer, value: Ast.Program) Allocator.Error!void {
        for (value.uses) |use_value| {
            if (use_value.target == .type) {
                try self.typeName(use_value.alias.?, use_value.alias_position.?);
            }
        }
        for (value.enums) |enum_value| {
            try self.typeName(enum_value.name, enum_value.name_position);
            try self.typeParameters(enum_value.type_parameters);
            for (enum_value.variants) |variant| if (variant.raw_value) |raw_value| try self.expression(raw_value);
        }
        for (value.protocols) |protocol| {
            try self.typeName(protocol.name, protocol.name_position);
            for (protocol.requirements) |requirement| try self.function(requirement, .method);
        }
        for (value.structures) |structure_value| try self.structure(structure_value);
        for (value.extensions) |extension| {
            for (extension.methods) |method| try self.function(method, .method);
        }
        for (value.functions) |function_value| try self.function(function_value, .function);
    }

    fn structure(self: *Analyzer, value: Ast.Structure) Allocator.Error!void {
        try self.typeName(value.name, value.name_position);
        try self.typeParameters(value.type_parameters);
        for (value.fields) |field| {
            try self.valueName(field.name, field.position, "field");
            if (field.initializer) |initializer| try self.expression(initializer);
        }
        for (value.constructors) |constructor| {
            try self.parameters(constructor.parameters);
            if (constructor.super_arguments) |arguments| try self.expressions(arguments);
            try self.statements(constructor.statements);
        }
        if (value.drop) |drop_value| try self.statements(drop_value.statements);
        for (value.methods) |method| try self.function(method, .method);
    }

    const FunctionKind = enum { function, method };

    fn function(self: *Analyzer, value: Ast.Function, kind: FunctionKind) Allocator.Error!void {
        try self.valueName(value.name, value.name_position, @tagName(kind));
        try self.typeParameters(value.type_parameters);
        try self.parameters(value.parameters);
        try self.statements(value.statements);
    }

    fn typeParameters(self: *Analyzer, values: []const Ast.TypeParameter) Allocator.Error!void {
        for (values) |parameter| try self.typeName(parameter.name, parameter.position);
    }

    fn parameters(self: *Analyzer, values: []const Ast.Parameter) Allocator.Error!void {
        for (values) |parameter| try self.valueName(parameter.name, parameter.position, "parameter");
    }

    fn statements(self: *Analyzer, values: []const Ast.Statement) Allocator.Error!void {
        var reachable = true;
        var reported_unreachable = false;
        for (values) |statement_value| {
            if (!reachable and !reported_unreachable) {
                try self.add(statementPosition(statement_value), "control-flow/unreachable", "statement is unreachable");
                reported_unreachable = true;
            }
            try self.statement(statement_value);
            if (reachable and !Semantic.astStatementFallsThrough(statement_value)) reachable = false;
        }
    }

    fn statement(self: *Analyzer, value: Ast.Statement) Allocator.Error!void {
        switch (value) {
            .print => |print_value| try self.expression(print_value.argument),
            .assertion => |assertion| {
                try self.expression(assertion.condition);
                try self.expression(assertion.message);
            },
            .panic_statement => |panic_value| try self.expression(panic_value.message),
            .variable_declaration => |declaration| {
                try self.valueName(declaration.name, declaration.name_position, "variable");
                if (declaration.initializer) |initializer| try self.expression(initializer);
            },
            .assignment => |assignment| {
                try self.expression(assignment.target);
                if (assignment.value) |assigned| try self.expression(assigned);
            },
            .if_statement => |if_value| {
                try self.condition(if_value.condition);
                try self.statements(if_value.body);
                for (if_value.alternatives) |alternative| {
                    try self.condition(alternative.condition);
                    try self.statements(alternative.body);
                }
                if (if_value.else_body) |else_body| try self.statements(else_body);
            },
            .while_statement => |while_value| {
                try self.condition(while_value.condition);
                try self.statements(while_value.body);
            },
            .for_statement => |for_value| {
                try self.valueName(for_value.name, for_value.name_position, "binding");
                switch (for_value.source) {
                    .collection => |collection| try self.expression(collection),
                    .integer_range => |range| {
                        try self.expression(range.start);
                        try self.expression(range.end);
                    },
                }
                try self.statements(for_value.body);
            },
            .return_statement => |return_value| if (return_value.value) |returned| try self.expression(returned),
            .expression_statement => |expression_value| try self.expression(expression_value),
            .break_statement, .continue_statement => {},
        }
    }

    fn condition(self: *Analyzer, value: Ast.Statement.Condition) Allocator.Error!void {
        switch (value) {
            .expression => |expression_value| try self.expression(expression_value),
            .binding => |binding| {
                try self.valueName(binding.name, binding.name_position, "binding");
                try self.expression(binding.source);
            },
        }
    }

    fn expression(self: *Analyzer, value: *const Ast.Expression) Allocator.Error!void {
        switch (value.value) {
            .sequence_literal => |items| try self.expressions(items),
            .call => |call| {
                try self.expressions(call.arguments);
                if (call.named_fields) |fields| try self.fieldInitializers(fields);
            },
            .value_call => |call| {
                try self.expression(call.callee);
                try self.expressions(call.arguments);
            },
            .lambda => |lambda| {
                try self.parameters(lambda.parameters);
                try self.statements(lambda.statements);
            },
            .method_call => |call| {
                try self.expression(call.object);
                try self.expressions(call.arguments);
                if (call.named_fields) |fields| try self.fieldInitializers(fields);
            },
            .static_method_call => |call| {
                try self.expressions(call.arguments);
                if (call.named_fields) |fields| try self.fieldInitializers(fields);
            },
            .super_method_call => |call| {
                try self.expressions(call.arguments);
                if (call.named_fields) |fields| try self.fieldInitializers(fields);
            },
            .cascade => |cascade| {
                try self.expression(cascade.object);
                for (cascade.operations) |operation| switch (operation) {
                    .method_call => |call| try self.expressions(call.arguments),
                    .field_assignment => |assignment| try self.expression(assignment.value),
                };
            },
            .class_initializer => |initializer| try self.expressions(initializer.arguments),
            .structure_initializer => |initializer| try self.fieldInitializers(initializer.fields),
            .member_access => |member| try self.expression(member.object),
            .safe_member_access => |member| {
                try self.expression(member.object);
                if (member.arguments) |arguments| try self.expressions(arguments);
                if (member.named_fields) |fields| try self.fieldInitializers(fields);
            },
            .index_access => |access| {
                try self.expression(access.object);
                try self.expression(access.index);
            },
            .slice_access => |access| {
                try self.expression(access.object);
                try self.expression(access.start);
                try self.expression(access.end);
            },
            .try_expression => |wrapped| try self.expression(wrapped.operand),
            .move_expression => |wrapped| try self.expression(wrapped.operand),
            .borrow_expression => |wrapped| try self.expression(wrapped.operand),
            .unary => |unary| try self.expression(unary.operand),
            .conversion => |conversion| try self.expression(conversion.operand),
            .binary => |binary| {
                try self.expression(binary.left);
                try self.expression(binary.right);
            },
            .match_expression => |match_value| {
                try self.expression(match_value.subject);
                for (match_value.branches) |branch| {
                    for (branch.bindings) |binding| try self.valueName(binding.name, binding.position, "binding");
                    switch (branch.body) {
                        .expression => |branch_expression| try self.expression(branch_expression),
                        .statements => |branch_statements| try self.statements(branch_statements),
                    }
                }
            },
            .integer, .floating, .boolean, .null, .string, .identifier, .self, .static_field_access => {},
        }
    }

    fn expressions(self: *Analyzer, values: []const *Ast.Expression) Allocator.Error!void {
        for (values) |value| try self.expression(value);
    }

    fn fieldInitializers(self: *Analyzer, values: []const Ast.Expression.FieldInitializer) Allocator.Error!void {
        for (values) |value| try self.expression(value.value);
    }

    fn typeName(self: *Analyzer, name: []const u8, position: Source.Position) Allocator.Error!void {
        if (isPascalCase(name)) return;
        try self.add(
            position,
            "naming/type",
            try std.fmt.allocPrint(self.allocator, "type name '{s}' should use PascalCase", .{name}),
        );
    }

    fn valueName(self: *Analyzer, name: []const u8, position: Source.Position, kind: []const u8) Allocator.Error!void {
        if (isSnakeCase(name)) return;
        try self.add(
            position,
            "naming/value",
            try std.fmt.allocPrint(self.allocator, "{s} name '{s}' should use snake_case", .{ kind, name }),
        );
    }

    fn add(self: *Analyzer, position: Source.Position, code: []const u8, message: []const u8) Allocator.Error!void {
        try self.diagnostics.append(self.allocator, .{ .position = position, .code = code, .message = message });
    }
};

fn statementPosition(value: Ast.Statement) Source.Position {
    return switch (value) {
        .print => |item| item.position,
        .assertion => |item| item.position,
        .panic_statement => |item| item.position,
        .variable_declaration => |item| item.position,
        .assignment => |item| item.position,
        .if_statement => |item| item.position,
        .while_statement => |item| item.position,
        .for_statement => |item| item.position,
        .break_statement => |position| position,
        .continue_statement => |position| position,
        .return_statement => |item| item.position,
        .expression_statement => |item| item.position,
    };
}

fn isPascalCase(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isUpper(name[0])) return false;
    for (name[1..]) |character| if (!std.ascii.isAlphanumeric(character)) return false;
    return true;
}

fn isSnakeCase(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isLower(name[0])) return false;
    var previous_underscore = false;
    for (name[1..]) |character| {
        if (character == '_') {
            if (previous_underscore) return false;
            previous_underscore = true;
        } else {
            if (!std.ascii.isLower(character) and !std.ascii.isDigit(character)) return false;
            previous_underscore = false;
        }
    }
    return !previous_underscore;
}

fn insertionSortDiagnostics(values: []Diagnostic) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var insertion = index;
        while (insertion > 0 and diagnosticLessThan(value, values[insertion - 1])) : (insertion -= 1) {
            values[insertion] = values[insertion - 1];
        }
        values[insertion] = value;
    }
}

fn diagnosticLessThan(left: Diagnostic, right: Diagnostic) bool {
    if (left.position.line != right.position.line) return left.position.line < right.position.line;
    if (left.position.column != right.position.column) return left.position.column < right.position.column;
    return std.mem.order(u8, left.code, right.code) == .lt;
}

fn insertionSortLocated(values: []LocatedDiagnostic) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var insertion = index;
        while (insertion > 0 and locatedLessThan(value, values[insertion - 1])) : (insertion -= 1) {
            values[insertion] = values[insertion - 1];
        }
        values[insertion] = value;
    }
}

fn locatedLessThan(left: LocatedDiagnostic, right: LocatedDiagnostic) bool {
    const path_order = std.mem.order(u8, left.path, right.path);
    if (path_order != .eq) return path_order == .lt;
    if (left.diagnostic.position.line != right.diagnostic.position.line) {
        return left.diagnostic.position.line < right.diagnostic.position.line;
    }
    if (left.diagnostic.position.column != right.diagnostic.position.column) {
        return left.diagnostic.position.column < right.diagnostic.position.column;
    }
    return std.mem.order(u8, left.diagnostic.code, right.diagnostic.code) == .lt;
}

test "naming forms accept acronyms and digits but reject noncanonical separators" {
    try std.testing.expect(isPascalCase("HTTP2Client"));
    try std.testing.expect(isPascalCase("X1"));
    try std.testing.expect(!isPascalCase("httpClient"));
    try std.testing.expect(!isPascalCase("HTTP_Client"));
    try std.testing.expect(isSnakeCase("http2_client"));
    try std.testing.expect(isSnakeCase("x1"));
    try std.testing.expect(!isSnakeCase("HTTPClient"));
    try std.testing.expect(!isSnakeCase("http__client"));
    try std.testing.expect(!isSnakeCase("http_client_"));
}

test "lint covers declarations exclusions nested bindings and unreachable suites" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\use int as bad_alias
        \\use Some.Module as moduleAlias
        \\enum bad_enum<T_good> { MixedVariant }
        \\protocol bad_protocol { func BadRequirement(BadParameter:int) }
        \\struct bad_struct<good_type> {
        \\    var BadField:int
        \\    func BadMethod(BadParameter:int) {
        \\        let BadVariable = 1
        \\        if BadBinding = maybe() { return }
        \\        for BadItem in [1] { continue; print(1); print(2) }
        \\        match value { MixedVariant(BadMatch) => { panic("x"); print(1) } }
        \\    }
        \\}
        \\func BadFunction<bad_type>(BadParameter:int) {
        \\    return
        \\    print(1)
        \\    print(2)
        \\}
    ;
    var parser = ParserModule.Parser.init(allocator, source);
    const program = try parser.parse();
    const diagnostics = try analyze(allocator, program);
    try std.testing.expectEqual(@as(usize, 21), diagnostics.len);
    try std.testing.expectEqualStrings("naming/type", diagnostics[0].code);
    try std.testing.expectEqualStrings("type name 'bad_alias' should use PascalCase", diagnostics[0].message);
    try std.testing.expectEqual(Severity.warning, diagnostics[0].severity);
    try std.testing.expectEqualStrings("silex lint", diagnostics[0].source);
    var unreachable_count: usize = 0;
    for (diagnostics) |diagnostic| if (std.mem.eql(u8, diagnostic.code, "control-flow/unreachable")) {
        unreachable_count += 1;
    };
    try std.testing.expectEqual(@as(usize, 3), unreachable_count);
}

test "terminal if and match statements make only the following suite unreachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\enum State { ready; stopped }
        \\func clean() {
        \\    if true { return } else { panic("stop") }
        \\    print(1)
        \\    print(2)
        \\}
        \\func matched(value:State) {
        \\    match value { ready => { return }; stopped => { panic("stop") } }
        \\    print(3)
        \\}
    ;
    var parser = ParserModule.Parser.init(allocator, source);
    const program = try parser.parse();
    const diagnostics = try analyze(allocator, program);
    var unreachable_count: usize = 0;
    for (diagnostics) |diagnostic| if (std.mem.eql(u8, diagnostic.code, "control-flow/unreachable")) {
        unreachable_count += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), unreachable_count);
}

test "break and continue terminate their block without treating loops as terminal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\func flow() {
        \\    while true { break; print(1) }
        \\    while true { continue; print(2) }
        \\    print(3)
        \\}
    ;
    var parser = ParserModule.Parser.init(allocator, source);
    const program = try parser.parse();
    const diagnostics = try analyze(allocator, program);
    try std.testing.expectEqual(@as(usize, 2), diagnostics.len);
    for (diagnostics) |diagnostic| {
        try std.testing.expectEqualStrings("control-flow/unreachable", diagnostic.code);
    }
}
