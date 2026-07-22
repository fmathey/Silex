const std = @import("std");
const Ast = @import("../Ast.zig");
const Parser = @import("Implementation.zig").Parser;
test "control flow parentheses do not change the compiler AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let enabled = true
        \\    let values = [1]
        \\    if (enabled) {}
        \\    if enabled {}
        \\    while (enabled) { break }
        \\    while enabled { break }
        \\    for (let value in values) {}
        \\    for let value in values {}
        \\    for (value in values) {}
        \\    for value in values {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;

    try std.testing.expectEqualStrings(
        statements[2].if_statement.condition.expression.value.identifier,
        statements[3].if_statement.condition.expression.value.identifier,
    );
    try std.testing.expectEqualStrings(
        statements[4].while_statement.condition.expression.value.identifier,
        statements[5].while_statement.condition.expression.value.identifier,
    );
    try std.testing.expectEqual(statements[6].for_statement.binding, statements[7].for_statement.binding);
    try std.testing.expectEqualStrings(statements[6].for_statement.name, statements[7].for_statement.name);
    try std.testing.expectEqualStrings(
        statements[6].for_statement.source.collection.value.identifier,
        statements[7].for_statement.source.collection.value.identifier,
    );
    try std.testing.expectEqual(statements[8].for_statement.binding, statements[9].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, statements[8].for_statement.binding);
    try std.testing.expectEqualStrings(statements[8].for_statement.name, statements[9].for_statement.name);
}

test "implicit conditional bindings match explicit let bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func find() int? { return 1 }
        \\func main() {
        \\    if let first = find() {}
        \\    if second = find() {}
        \\    if (third = find()) {}
        \\    if false {} elif fourth = find() {} else if (fifth = find()) {}
        \\    while sixth = find() { break }
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[1].statements;

    try std.testing.expectEqual(Ast.Mutability.immutable, statements[0].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[1].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[2].if_statement.condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[3].if_statement.alternatives[0].condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[3].if_statement.alternatives[1].condition.binding.mutability);
    try std.testing.expectEqual(Ast.Mutability.immutable, statements[4].while_statement.condition.binding.mutability);
}

test "parse control flow expressions and continuations without wrapper parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let enabled = true
        \\    let count = 2
        \\    if enabled &&
        \\        count > 0 {}
        \\    if (enabled) && count > 0 {}
        \\    if (
        \\        enabled
        \\        && count > 0
        \\    ) {}
        \\    if func() bool { return true }() {}
        \\    while enabled &&
        \\        count > 0 { break }
        \\    for let index in 0...
        \\        count {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;

    try std.testing.expect(statements[2].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[3].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[4].if_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[5].if_statement.condition.expression.value == .value_call);
    try std.testing.expect(statements[6].while_statement.condition.expression.value == .binary);
    try std.testing.expect(statements[7].for_statement.source == .integer_range);
}

test "reject operators that only begin an unparenthesized control header line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conditional = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if true
        \\        && false {}
        \\}
    );
    try std.testing.expectError(error.InvalidSource, conditional.parse());
    try std.testing.expectEqualStrings("expected '{'", conditional.diagnostic.?.message);

    var iteration = Parser.init(arena.allocator(),
        \\func main() void {
        \\    for let index in 0
        \\        ...3 {}
        \\}
    );
    try std.testing.expectError(error.InvalidSource, iteration.parse());
    try std.testing.expectEqualStrings("expected '{'", iteration.diagnostic.?.message);
}

test "reject incomplete control flow headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conditional = Parser.init(arena.allocator(), "func main() void { if {} }");
    try std.testing.expectError(error.InvalidSource, conditional.parse());
    try std.testing.expectEqualStrings("expected expression", conditional.diagnostic.?.message);

    var iteration = Parser.init(arena.allocator(), "func main() void { for in [1] {} }");
    try std.testing.expectError(error.InvalidSource, iteration.parse());
    try std.testing.expectEqualStrings("expected iteration variable name", iteration.diagnostic.?.message);
}

test "diagnose malformed optional control flow headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "func main() void { if (true {} }", .message = "expected ')'" },
        .{ .source = "func main() void { if true) {} }", .message = "expected '{'" },
        .{ .source = "func main() void { if true false {} }", .message = "expected '{'" },
        .{ .source = "func main() void { if true && {} }", .message = "expected expression" },
        .{ .source = "func main() void { for let in [1] {} }", .message = "expected iteration variable name" },
        .{ .source = "func main() void { for let value [1] {} }", .message = "expected 'in' after iteration variable" },
        .{ .source = "func main() void { for let value in {} }", .message = "expected expression" },
        .{ .source = "func main() void { for (let value in [1] {} }", .message = "expected ')' after for source" },
    };

    for (cases) |case| {
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse explicit and implicit for bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let values = [1]
        \\    for (let value in values) {}
        \\    for (var value in values) {}
        \\    for value in values {}
        \\    for (value in values) {}
        \\}
    );
    const program = try parser.parse();

    try std.testing.expectEqual(Ast.IterationBinding.immutable, program.functions[0].statements[1].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.mutable, program.functions[0].statements[2].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[3].for_statement.binding);
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[4].for_statement.binding);
}

test "parse compact and named integer ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let start = 0
        \\    let end = 4
        \\    for (let i in start + 1...end - 1) {}
        \\    for (let j in start...compute_end()) {}
        \\    for (var i in range(end, start)) {}
        \\}
    );
    const program = try parser.parse();

    const compact = program.functions[0].statements[2].for_statement.source.integer_range;
    try std.testing.expect(compact.start.value == .binary);
    try std.testing.expect(compact.end.value == .binary);
    const called = program.functions[0].statements[3].for_statement.source.integer_range;
    try std.testing.expect(called.end.value == .call);
    const named = program.functions[0].statements[4].for_statement.source.integer_range;
    try std.testing.expect(named.start.value == .identifier);
    try std.testing.expect(named.end.value == .identifier);
}

test "preserve cascade as for collection source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    var values = [1]
        \\    for (let value in values..reverse()) {}
        \\}
    );
    const program = try parser.parse();

    try std.testing.expect(program.functions[0].statements[1].for_statement.source.collection.value == .cascade);
}

test "parse for binding without let or var" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let values = [1]; for (value in values) {} }",
    );

    const program = try parser.parse();
    try std.testing.expectEqual(Ast.IterationBinding.read, program.functions[0].statements[1].for_statement.binding);
}

test "reserve range intrinsic name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func range(start:int, end:int) int { return start + end } func main() void {}");

    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected function name", parser.diagnostic.?.message);
}

test "multiplication binds tighter than addition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { print(1 + 2 * 3); }");
    const program = try parser.parse();

    const addition = program.functions[0].statements[0].print.argument.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.add, addition.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.multiply, addition.right.value.binary.operator);
}

test "bitwise operators follow shift precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let value:uint8 = 1 + 1 << 2 & 7 ^ 3; }",
    );
    const program = try parser.parse();

    const bit_xor = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.bit_xor, bit_xor.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.bit_and, bit_xor.left.value.binary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.shift_left, bit_xor.left.value.binary.left.value.binary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.add, bit_xor.left.value.binary.left.value.binary.left.value.binary.operator);
}

test "parse explicit conversions before arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let value = 1 as uint8 + 2 as int; }",
    );
    const program = try parser.parse();

    const addition = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.add, addition.operator);
    try std.testing.expectEqual(Ast.TypeName.uint8, addition.left.value.conversion.target_type);
    try std.testing.expectEqual(Ast.TypeName.int, addition.right.value.conversion.target_type);
}

test "parse named invocation and member assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Position { var x:int; var y:int }
        \\func main() void { var position = Position(y:20, x:10); position.x = 12 }
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expectEqualStrings("Position", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[0].fields.len);
    try std.testing.expectEqual(Ast.Mutability.mutable, program.structures[0].fields[0].mutability);
    const invocation = program.functions[0].statements[0].variable_declaration.initializer.?.value.call;
    try std.testing.expectEqual(@as(usize, 0), invocation.arguments.len);
    try std.testing.expectEqual(@as(usize, 2), invocation.named_fields.?.len);
    try std.testing.expect(program.functions[0].statements[1].assignment.target.value == .member_access);
}

test "require and preserve structure field mutability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct State { let id:int; var count:int }");
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.Mutability.immutable, program.structures[0].fields[0].mutability);
    try std.testing.expectEqual(Ast.Mutability.mutable, program.structures[0].fields[1].mutability);

    var invalid = Parser.init(arena.allocator(), "struct State { count:int }");
    try std.testing.expectError(error.InvalidSource, invalid.parse());
    try std.testing.expectEqualStrings("expected 'let' or 'var' before field name", invalid.diagnostic.?.message);
}

test "reject invalid invocation argument forms" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(1, x:2) }",
            .message = "cannot mix positional arguments and named fields",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(x:) }",
            .message = "expected value after ':'",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position(x:1 }",
            .message = "expected ')' after invocation",
        },
        .{
            .source = "struct Position { var x:int } func main() { let value = Position { x:1 } }",
            .message = "structure initializers use 'Type(...)', not 'Type { ... }'",
        },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse defaults and compound assignments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Counter { var value:int = 2 }
        \\func main() void { var counter:Counter; counter.value += 3; counter.value-- }
    );
    const program = try parser.parse();

    try std.testing.expect(program.structures[0].fields[0].initializer != null);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.initializer == null);
    try std.testing.expectEqual(Ast.AssignmentOperator.add, program.functions[0].statements[1].assignment.operator);
    try std.testing.expectEqual(Ast.AssignmentOperator.decrement, program.functions[0].statements[2].assignment.operator);
}

test "parse inferred and annotated declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let count = 5; var hit:bool = true; if (hit) { print(count); } }",
    );
    const program = try parser.parse();

    try std.testing.expectEqual(Ast.Mutability.immutable, program.functions[0].statements[0].variable_declaration.mutability);
    try std.testing.expectEqual(Ast.TypeName.bool, program.functions[0].statements[1].variable_declaration.annotation.?);
    try std.testing.expectEqualStrings(
        "count",
        program.functions[0].statements[2].if_statement.body[0].print.argument.value.identifier,
    );
}

test "parse class declarations with the structure member grammar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\public class Player {
        \\    private var id:int = 0
        \\    public var health:int = 100
        \\    protected var velocity:int = 0
        \\    public func damage(amount:int) { self.health -= amount }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.structures.len);
    try std.testing.expect(program.structures[0].is_public);
    try std.testing.expect(program.structures[0].is_class);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].fields[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].fields[2].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].methods[0].member_visibility.?);
    try std.testing.expectEqualStrings("Player", program.structures[0].name);
    try std.testing.expectEqual(@as(usize, 3), program.structures[0].fields.len);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].methods.len);
}

test "parse visible overloaded class constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Session {
        \\    var token:str
        \\    public init() { self.token = "" }
        \\    protected init(token:str) { self.token = token }
        \\    private init(token:str, attempts:int) { self.token = token }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 3), program.structures[0].constructors.len);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].constructors[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].constructors[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].constructors[2].visibility);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].constructors[1].parameters.len);
}

test "parse class and struct drop blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Texture {
        \\    var handle:int = 1
        \\    drop { print(self.handle) }
        \\}
        \\struct File {
        \\    let handle:int
        \\    drop { print(self.handle) }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].drop != null);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].drop.?.statements.len);
    try std.testing.expect(program.structures[1].drop != null);
    try std.testing.expectEqual(@as(usize, 1), program.structures[1].drop.?.statements.len);
}

test "reject invalid drop declarations and explicit calls" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{ .source = "class Value { drop {} drop {} } func main() {}", .message = "a class can declare only one 'drop' block" },
        .{ .source = "struct Value { drop {} drop {} } func main() {}", .message = "a struct can declare only one 'drop' block" },
        .{ .source = "class Value { public drop {} } func main() {}", .message = "'drop' does not accept a visibility modifier" },
        .{ .source = "class Value { protected drop {} } func main() {}", .message = "'drop' does not accept a visibility modifier" },
        .{ .source = "class Value { private drop {} } func main() {}", .message = "'drop' does not accept a visibility modifier" },
        .{ .source = "class Value { override drop {} } func main() {}", .message = "'override' cannot apply to 'drop'" },
        .{ .source = "class Value { drop() {} } func main() {}", .message = "'drop' must be followed by a block" },
        .{ .source = "class Value {} func main() { var value = Value(); value.drop() }", .message = "expected field name after '.'" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse class base and constructor super call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Entity { protected init(id:int) {} }
        \\class Player : Entity {
        \\    public init(id:int, name:str) : super(id) {}
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqualStrings("Entity", program.structures[1].base.?.name);
    try std.testing.expectEqual(@as(usize, 1), program.structures[1].constructors[0].super_arguments.?.len);
}

test "parse class base and protocol conformance list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Player : Entity, Actor {} func main() {}");
    const program = try parser.parse();
    try std.testing.expectEqualStrings("Entity", program.structures[0].base.?.name);
    try std.testing.expectEqual(@as(usize, 1), program.structures[0].conformances.len);
    try std.testing.expectEqualStrings("Actor", program.structures[0].conformances[0].name);
}

test "parse protocols structure conformances and generic constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\public protocol Describable {
        \\    func describe() str
        \\    func write(value:&str)
        \\}
        \\struct User : Describable {}
        \\func label<T : Describable>(value:T) str { return value.describe() }
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.protocols.len);
    try std.testing.expect(program.protocols[0].is_public);
    try std.testing.expectEqual(@as(usize, 2), program.protocols[0].requirements.len);
    try std.testing.expectEqualStrings("describe", program.protocols[0].requirements[0].name);
    try std.testing.expectEqual(Ast.ReturnType.str, program.protocols[0].requirements[0].return_type);
    try std.testing.expectEqual(Ast.ParameterMode.mutable_reference, program.protocols[0].requirements[1].parameters[0].mode);
    try std.testing.expectEqualStrings("Describable", program.structures[0].conformances[0].name);
    try std.testing.expectEqualStrings("Describable", program.functions[0].type_parameters[0].constraint.?.name);
}

test "reject unsupported protocol declaration forms" {
    const cases = [_]struct { source: []const u8, message: []const u8 }{
        .{ .source = "protocol Value<T> {} func main() {}", .message = "generic protocols are not supported" },
        .{ .source = "protocol Child : Parent {} func main() {}", .message = "protocol inheritance is not supported" },
        .{ .source = "protocol Value { let count:int } func main() {}", .message = "a protocol can declare only method requirements" },
        .{ .source = "protocol Value { func read<T>() T } func main() {}", .message = "generic protocol methods are not supported" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse visible overloaded struct constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Value {
        \\    let number:int
        \\    init() { self.number = 0 }
        \\    public init(number:int) { self.number = number }
        \\    private init(number:int, doubled:bool) { self.number = number }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 3), program.structures[0].constructors.len);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].constructors[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].constructors[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].constructors[2].visibility);
}

test "reject super call on struct constructor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct Value { init() : super() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a struct constructor cannot call 'super'", parser.diagnostic.?.message);
}

test "parse struct visibility and reject protected members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Position {
        \\    private var x:int
        \\    public var y:int
        \\    var z:int
        \\    private static var count:int
        \\    public func read() int { return self.y }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].fields[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].fields[2].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[3].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].methods[0].member_visibility.?);

    var protected_member = Parser.init(arena.allocator(), "struct Position { protected var x:int } func main() {}");
    try std.testing.expectError(error.InvalidSource, protected_member.parse());
    try std.testing.expectEqualStrings(
        "a struct member cannot use 'protected' because structs do not support inheritance",
        protected_member.diagnostic.?.message,
    );
}

test "logical operators follow comparison precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { let result = !false || 1 < 2 && 3 == 3; }",
    );
    const program = try parser.parse();

    const logical_or = program.functions[0].statements[0].variable_declaration.initializer.?.value.binary;
    try std.testing.expectEqual(Ast.BinaryOperator.logical_or, logical_or.operator);
    try std.testing.expectEqual(Ast.UnaryOperator.logical_not, logical_or.left.value.unary.operator);
    try std.testing.expectEqual(Ast.BinaryOperator.logical_and, logical_or.right.value.binary.operator);
    try std.testing.expectEqual(
        Ast.BinaryOperator.less,
        logical_or.right.value.binary.left.value.binary.operator,
    );
    try std.testing.expectEqual(
        Ast.BinaryOperator.equal,
        logical_or.right.value.binary.right.value.binary.operator,
    );
}

test "parse else block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { if (true) { print(1); } else { print(2); } }",
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 0), program.functions[0].statements[0].if_statement.alternatives.len);
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[0].if_statement.else_body.?.len);
}

test "normalize elif and else if into the same AST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if false {} elif true { print(1) } elif (false) {} else {}
        \\    if false {} else if true { print(1) } else if (false) {} else {}
        \\    if false {} elif true {} else if false {} elif true {}
        \\}
    );
    const program = try parser.parse();
    const statements = program.functions[0].statements;
    const canonical = statements[0].if_statement;
    const compatible = statements[1].if_statement;

    try std.testing.expectEqual(@as(usize, 2), canonical.alternatives.len);
    try std.testing.expectEqual(canonical.alternatives.len, compatible.alternatives.len);
    for (canonical.alternatives, compatible.alternatives) |left, right| {
        try std.testing.expectEqual(left.condition.expression.value.boolean, right.condition.expression.value.boolean);
        try std.testing.expectEqual(left.body.len, right.body.len);
    }
    try std.testing.expect(canonical.else_body != null);
    try std.testing.expect(compatible.else_body != null);
    try std.testing.expectEqual(@as(usize, 3), statements[2].if_statement.alternatives.len);
}

test "allow trivia inside an alternative chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    if false {}
        \\    // before else
        \\    else
        \\    // before if
        \\    if true {}
        \\    // before elif
        \\    elif false {}
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements[0].if_statement.alternatives.len);
}

test "preserve explicit else block with nested if" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { if false {} else { if true {} } }",
    );
    const program = try parser.parse();
    const outer = program.functions[0].statements[0].if_statement;
    try std.testing.expectEqual(@as(usize, 0), outer.alternatives.len);
    try std.testing.expect(outer.else_body.?[0] == .if_statement);
}

test "diagnose malformed alternative chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cases = [_]struct {
        source: []const u8,
        message: []const u8,
    }{
        .{ .source = "func main() void { elif true {} }", .message = "'elif' must directly continue an if chain" },
        .{ .source = "func main() void { else {} }", .message = "'else' must directly continue an if chain with '{' or 'if'" },
        .{ .source = "func main() void { if false {} else elif true {} }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { if false {} else while true {} }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { if false {} else {} elif true {} }", .message = "conditional branch cannot follow final 'else'" },
        .{ .source = "func main() void { if false {} else {} else {} }", .message = "conditional branch cannot follow final 'else'" },
        .{ .source = "func main() void { if false {} elif {} }", .message = "expected expression" },
        .{ .source = "func main() void { if false {} elif true }", .message = "expected '{'" },
        .{ .source = "func main() void { if false {} else }", .message = "expected '{' or 'if' after 'else'" },
        .{ .source = "func main() void { let elif = 1 }", .message = "'elif' is reserved; rename this identifier" },
    };

    for (cases) |case| {
        var parser = Parser.init(arena.allocator(), case.source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
        try std.testing.expectEqualStrings(case.message, parser.diagnostic.?.message);
    }
}

test "parse while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(
        arena.allocator(),
        "func main() void { var count = 2; while (count > 0) { count = count - 1; } }",
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.BinaryOperator.greater, program.functions[0].statements[1].while_statement.condition.expression.value.binary.operator);
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[1].while_statement.body.len);
}

test "newlines terminate simple statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let count = 1
        \\    var enabled = true
        \\    print(count)
        \\    count = 2
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 4), program.functions[0].statements.len);
}

test "semicolons separate statements on one line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { let a = 1; let b = 2; print(a + b) }");
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 3), program.functions[0].statements.len);
}

test "comments preserve automatic line termination" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let value = 1 // comment
        \\    print(value)
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements.len);
}

test "semicolon cannot stand alone on next line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    print(1)
        \\    ;
        \\}
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected statement", parser.diagnostic.?.message);
}

test "reject statements on one line without semicolon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { let a = 1 let b = 2 }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected ';' or line break", parser.diagnostic.?.message);
}

test "reject missing explicit type after colon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main() void { var health: = 20 }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected type name after ':'", parser.diagnostic.?.message);
}

test "multiline expressions continue after operators and inside parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let total =
        \\        1 +
        \\        2
        \\    let active = (
        \\        total > 0
        \\        && true
        \\    )
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements.len);
}

test "operator cannot begin continuation outside parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    let total = 1
        \\        + 2
        \\}
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("expected statement", parser.diagnostic.?.message);
}
