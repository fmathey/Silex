const std = @import("std");
const Ast = @import("../Ast.zig");
const Parser = @import("Implementation.zig").Parser;
test "parse method and field cascade operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Point { var x:int }
        \\func main() void {
        \\    var point = Point(x:0)..x = 10..shift(1, 2)
        \\}
    );
    const program = try parser.parse();
    const cascade = program.functions[0].statements[0].variable_declaration.initializer.?.value.cascade;
    try std.testing.expectEqual(@as(usize, 2), cascade.operations.len);
    try std.testing.expect(cascade.operations[0] == .field_assignment);
    try std.testing.expectEqualStrings("10", cascade.operations[0].field_assignment.value.value.integer);
    try std.testing.expect(cascade.operations[1] == .method_call);
    try std.testing.expectEqualStrings("shift", cascade.operations[1].method_call.name);
}

test "parse terminal member access after a cascade" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let running = stopwatch..reset()..start().is_running()
        \\}
    );
    const program = try parser.parse();
    const call = program.functions[0].statements[0].variable_declaration.initializer.?.value.method_call;
    try std.testing.expectEqualStrings("is_running", call.name);
    try std.testing.expect(call.object.value == .cascade);
    try std.testing.expectEqual(@as(usize, 2), call.object.value.cascade.operations.len);
}

test "parse functions parameters calls and returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() void {
        \\    print(add(2, 3))
        \\}
        \\func add(left:int, right:int) int {
        \\    return left + right
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expectEqual(@as(usize, 2), program.functions[1].parameters.len);
    try std.testing.expectEqualStrings("add", program.functions[0].statements[0].print.argument.value.call.name);
    try std.testing.expect(program.functions[1].statements[0].return_statement.value != null);
}

test "void return type is optional but typed returns remain explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func implicit() {}
        \\func explicit() void {}
        \\func answer() int { return 42 }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.ReturnType.void, program.functions[0].return_type);
    try std.testing.expectEqual(Ast.ReturnType.void, program.functions[1].return_type);
    try std.testing.expectEqual(Ast.ReturnType.int, program.functions[2].return_type);
}

test "parse public and private native functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\public native func pow(value:int) int
        \\native func native_seed() int
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expect(program.functions[0].is_native);
    try std.testing.expect(program.functions[0].is_public);
    try std.testing.expectEqualStrings("pow", program.functions[0].name);
    try std.testing.expect(program.functions[1].is_native);
    try std.testing.expect(!program.functions[1].is_public);
    try std.testing.expectEqualStrings("native_seed", program.functions[1].name);
}

test "parse public and private opaque native resources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\public native resource Buffer {
        \\    drop destroy_buffer
        \\}
        \\native resource Image { drop release_image }
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.structures.len);
    try std.testing.expect(program.structures[0].is_native_resource);
    try std.testing.expect(program.structures[0].is_public);
    try std.testing.expectEqualStrings("destroy_buffer", program.structures[0].native_drop_name.?);
    try std.testing.expect(program.structures[1].is_native_resource);
    try std.testing.expect(!program.structures[1].is_public);
    try std.testing.expectEqual(@as(usize, 3), program.functions.len);
    try std.testing.expect(program.functions[0].is_native_resource_drop);
    try std.testing.expectEqualStrings("destroy_buffer", program.functions[0].name);
    try std.testing.expectEqualStrings("Buffer", program.functions[0].parameters[0].type.structure);
}

test "reject malformed opaque native resources" {
    const cases = [_][]const u8{
        "native resource Buffer {} func main() {}",
        "native resource Buffer<T> { drop destroy } func main() {}",
        "native resource Buffer : Other { drop destroy } func main() {}",
        "native resource Buffer { drop destroy drop again } func main() {}",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var parser = Parser.init(arena.allocator(), source);
        try std.testing.expectError(error.InvalidSource, parser.parse());
    }
}

test "parse fixed arrays and lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main(values:int[], fixed:int[3]) void {}");
    const program = try parser.parse();
    try std.testing.expect(program.functions[0].parameters[0].type == .list);
    try std.testing.expect(program.functions[0].parameters[0].type.list.* == .int);
    try std.testing.expect(program.functions[0].parameters[1].type == .fixed_array);
    try std.testing.expect(program.functions[0].parameters[1].type.fixed_array.element.* == .int);
}

test "parse optional type composition and conditional bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main(entries:int?[], cache:int[]?, callback:(func(int))?) {
        \\    if let value = entries[0] {}
        \\    if (let value = entries[0]) {}
        \\    while var value = entries[0] { break }
        \\    let missing = null
        \\    cache?.count()
        \\}
    );
    const program = try parser.parse();
    const parameters = program.functions[0].parameters;
    try std.testing.expect(parameters[0].type == .list);
    try std.testing.expect(parameters[0].type.list.* == .optional);
    try std.testing.expect(parameters[1].type == .optional);
    try std.testing.expect(parameters[1].type.optional.* == .list);
    try std.testing.expect(parameters[2].type == .optional);
    try std.testing.expect(parameters[2].type.optional.* == .function);
    const statements = program.functions[0].statements;
    try std.testing.expect(statements[0].if_statement.condition == .binding);
    try std.testing.expect(statements[1].if_statement.condition == .binding);
    try std.testing.expectEqualStrings(
        statements[0].if_statement.condition.binding.name,
        statements[1].if_statement.condition.binding.name,
    );
    try std.testing.expect(statements[2].while_statement.condition == .binding);
    try std.testing.expect(statements[3].variable_declaration.initializer.?.value == .null);
    try std.testing.expect(statements[4].expression_statement.value == .safe_member_access);
}

test "parse negative collection indexes and slices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let values = [10, 20, 30]
        \\    let last = values[-1]
        \\    let middle = values[1:-1]
        \\}
    );
    const program = try parser.parse();

    const index = program.functions[0].statements[1].variable_declaration.initializer.?.value.index_access;
    try std.testing.expectEqual(Ast.UnaryOperator.numeric_negate, index.index.value.unary.operator);
    const slice = program.functions[0].statements[2].variable_declaration.initializer.?.value.slice_access;
    try std.testing.expectEqualStrings("1", slice.start.value.integer);
    try std.testing.expectEqual(Ast.UnaryOperator.numeric_negate, slice.end.value.unary.operator);
}

test "parse override methods and direct super calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\class Base { protected func update(value:int) int { return value } }
        \\class Child : Base {
        \\    override public func update(value:int) int { return super.update(value) }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const method = program.structures[1].methods[0];
    try std.testing.expect(method.is_override);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, method.member_visibility.?);
    const call = method.statements[0].return_statement.value.?.value.super_method_call;
    try std.testing.expectEqualStrings("update", call.name);
    try std.testing.expectEqual(@as(usize, 1), call.arguments.len);
}

test "parse static methods and generic static calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Box<T> {
        \\    var value:T
        \\    static func filled(value:T) Box<T> { return Box<T>(value:value) }
        \\}
        \\func main() { let box = Box<int>.filled(42) }
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].methods[0].is_static);
    const call = program.functions[0].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(call.value == .static_method_call);
    try std.testing.expect(call.value.static_method_call.owner == .generic_structure);
    try std.testing.expectEqualStrings("filled", call.value.static_method_call.name);
}

test "reject override on static method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Factory { override public static func create() {} }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a static method cannot use 'override'", parser.diagnostic.?.message);
}

test "parse static fields and generic static field access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Cache<T> {
        \\    static var hits:int
        \\    let value:T
        \\}
        \\func main() { Cache<int>.hits = 1 }
    );
    const program = try parser.parse();
    try std.testing.expect(program.structures[0].fields[0].is_static);
    try std.testing.expect(!program.structures[0].fields[1].is_static);
    const target = program.functions[0].statements[0].assignment.target;
    try std.testing.expect(target.value == .static_field_access);
    try std.testing.expect(target.value.static_field_access.owner == .generic_structure);
    try std.testing.expectEqualStrings("hits", target.value.static_field_access.name);
}

test "override must precede method visibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "class Child { public override func update() {} }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("'override' must precede the method visibility", parser.diagnostic.?.message);
}

test "parse generic structure declarations types and invocations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Pair<T> {
        \\    var first:T
        \\    var second:T
        \\}
        \\struct Entry<Key, Value> {
        \\    var key:Key
        \\    var value:Value
        \\}
        \\func main() {
        \\    let pair:Pair<int> = Pair<int>(first:1, second:2)
        \\    let nested = Entry<int, Pair<str>>(key:1, value:Pair<str>(first:"a", second:"b"))
        \\    print(pair.first < pair.second)
        \\}
    );
    const program = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), program.structures[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.structures[0].type_parameters[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.structures[1].type_parameters.len);
    const annotation = program.functions[0].statements[0].variable_declaration.annotation.?.generic_structure;
    try std.testing.expectEqualStrings("Pair", annotation.name);
    try std.testing.expectEqual(Ast.TypeName.int, annotation.arguments[0]);
    const initializer = program.functions[0].statements[1].variable_declaration.initializer.?.value.call;
    try std.testing.expectEqual(@as(usize, 2), initializer.type_arguments.len);
    try std.testing.expect(initializer.type_arguments[1] == .generic_structure);
    try std.testing.expect(program.functions[0].statements[2].print.argument.value == .binary);
}

test "parse self-qualified borrowed method returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Store<T> {
        \\    var value:T
        \\    func inspect(other:@T) @self:T { return @self.value }
        \\    func edit(other:@T) &self:T { return &self.value }
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqualStrings("self", program.structures[0].methods[0].return_type.reference.provenance.?);
    try std.testing.expectEqualStrings("self", program.structures[0].methods[1].return_type.reference.provenance.?);
}

test "reject duplicate generic structure parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "struct Pair<T, T> { var value:T }");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("type parameter is already declared", parser.diagnostic.?.message);
}

test "parse generic function declaration and invocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func identity<T>(value:T) T {
        \\    return value
        \\}
        \\func main() {
        \\    print(identity<int>(42))
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.functions[0].type_parameters[0].name);
    try std.testing.expect(program.functions[0].parameters[0].type == .structure);
    const call = program.functions[1].statements[0].print.argument.value.call;
    try std.testing.expectEqual(@as(usize, 1), call.type_arguments.len);
    try std.testing.expectEqual(Ast.TypeName.int, call.type_arguments[0]);
}

test "reject generic main function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "func main<T>() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("'main' cannot be generic", parser.diagnostic.?.message);
}

test "keep generic methods limited to instance extensions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var direct = Parser.init(arena.allocator(), "struct Box { func keep<T>(value:T) T { return value } } func main() {}");
    try std.testing.expectError(error.InvalidSource, direct.parse());
    try std.testing.expectEqualStrings("generic methods are not supported", direct.diagnostic.?.message);

    var protocol = Parser.init(arena.allocator(), "protocol Box { func keep<T>(value:T) T } func main() {}");
    try std.testing.expectError(error.InvalidSource, protocol.parse());
    try std.testing.expectEqualStrings("generic protocol methods are not supported", protocol.diagnostic.?.message);
}

test "parse transparent type aliases with use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\use Vec3<int> as Vec3i
        \\use int[] as Integers
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expect(program.uses[0].target == .type);
    try std.testing.expect(program.uses[0].target.type == .generic_structure);
    try std.testing.expectEqualStrings("Vec3i", program.uses[0].alias.?);
    try std.testing.expect(program.uses[1].target.type == .list);
}

test "parse enums and expression and imperative matches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Verdict { idle; value(int, str); failed(str) }
        \\func main() {
        \\    let result = Verdict.value(7, "ok")
        \\    let text = match result { idle => "idle"; value(number, text) => text; failed(error) => error }
        \\    match result { idle => {}; value(var number, let text) => { print(text) }; failed(error) => {} }
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.enums.len);
    try std.testing.expectEqualStrings("Verdict", program.enums[0].name);
    try std.testing.expectEqual(@as(usize, 2), program.enums[0].variants[1].associated_types.len);
    const expression_match = program.functions[0].statements[1].variable_declaration.initializer.?.value.match_expression;
    try std.testing.expectEqual(@as(usize, 3), expression_match.branches.len);
    try std.testing.expect(expression_match.branches[1].body == .expression);
    const imperative_match = program.functions[0].statements[2].expression_statement.value.match_expression;
    try std.testing.expect(imperative_match.branches[1].body == .statements);
    try std.testing.expectEqual(Ast.Mutability.mutable, imperative_match.branches[1].bindings[0].mutability);
}

test "parse generic enum declarations and specialized variant constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Outcome<T, E> { success(T); failure(E) }
        \\func main() {
        \\    let value:Outcome<int, str> = Outcome<int, str>.success(42)
        \\}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), program.enums[0].type_parameters.len);
    try std.testing.expectEqualStrings("T", program.enums[0].type_parameters[0].name);
    try std.testing.expectEqualStrings("E", program.enums[0].type_parameters[1].name);
    try std.testing.expectEqualStrings("T", program.enums[0].variants[0].associated_types[0].structure);
    const annotation = program.functions[0].statements[0].variable_declaration.annotation.?.generic_structure;
    try std.testing.expectEqualStrings("Outcome", annotation.name);
    try std.testing.expectEqual(@as(usize, 2), annotation.arguments.len);
    const owner = program.functions[0].statements[0].variable_declaration.initializer.?.value.static_method_call.owner.generic_structure;
    try std.testing.expectEqualStrings("Outcome", owner.name);
    try std.testing.expectEqual(@as(usize, 2), owner.arguments.len);
}

test "parse intrinsic Result with a void success type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum SaveError { denied }
        \\func save() Result<void, SaveError> {
        \\    return Result<void, SaveError>.success()
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const return_type = program.functions[0].return_type.generic_structure;
    try std.testing.expectEqualStrings("Result", return_type.name);
    try std.testing.expectEqual(Ast.TypeName.void, return_type.arguments[0]);
    const owner = program.functions[0].statements[0].return_statement.value.?.value.static_method_call.owner.generic_structure;
    try std.testing.expectEqual(Ast.TypeName.void, owner.arguments[0]);
}

test "parse try with prefix precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func read() Result<int, Failure> { return Result<int, Failure>.success(1) }
        \\func load() Result<int, Failure> {
        \\    let value = try read() + 1
        \\    let member = try loader.read()
        \\    return Result<int, Failure>.success(value)
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    const initializer = program.functions[1].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(initializer.value == .binary);
    try std.testing.expect(initializer.value.binary.left.value == .try_expression);
    try std.testing.expect(initializer.value.binary.left.value.try_expression.operand.value == .call);
    const member = program.functions[1].statements[1].variable_declaration.initializer.?;
    try std.testing.expect(member.value == .try_expression);
    try std.testing.expect(member.value.try_expression.operand.value == .method_call);
}

test "parse move with prefix precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    let next = move current
        \\}
    );
    const program = try parser.parse();
    const initializer = program.functions[0].statements[0].variable_declaration.initializer.?;
    try std.testing.expect(initializer.value == .move_expression);
    try std.testing.expect(initializer.value.move_expression.operand.value == .identifier);
}

test "parse deferred function type and literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\func main() {
        \\    var callback:deferred func(int) = deferred func(value:int) {}
        \\}
    );
    const program = try parser.parse();
    const declaration = program.functions[0].statements[0].variable_declaration;
    try std.testing.expect(declaration.annotation.?.function.deferred);
    try std.testing.expect(declaration.initializer.?.value.lambda.deferred);
}

test "reserve Result and reject void as its error type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var error_type = Parser.init(arena.allocator(), "func main() { let value:Result<int, void> }");
    try std.testing.expectError(error.InvalidSource, error_type.parse());
    try std.testing.expectEqualStrings("Result error type cannot be 'void'", error_type.diagnostic.?.message);

    var both_void = Parser.init(arena.allocator(), "func main() { let value:Result<void, void> }");
    try std.testing.expectError(error.InvalidSource, both_void.parse());
    try std.testing.expectEqualStrings("Result error type cannot be 'void'", both_void.diagnostic.?.message);

    var enum_name = Parser.init(arena.allocator(), "enum Result<T, E> { success(T); failure(E) } func main() {}");
    try std.testing.expectError(error.InvalidSource, enum_name.parse());
    try std.testing.expectEqualStrings("type name 'Result' is reserved", enum_name.diagnostic.?.message);

    var type_parameter = Parser.init(arena.allocator(), "struct Box<Result> { var value:Result } func main() {}");
    try std.testing.expectError(error.InvalidSource, type_parameter.parse());
    try std.testing.expectEqualStrings("type name 'Result' is reserved", type_parameter.diagnostic.?.message);

    var module_alias = Parser.init(arena.allocator(), "use Library as Result\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, module_alias.parse());
    try std.testing.expectEqualStrings("name 'Result' is reserved", module_alias.diagnostic.?.message);
}

test "removed import reports its use replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var aliased = Parser.init(arena.allocator(), "import STD as Standard\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, aliased.parse());
    try std.testing.expectEqualStrings(
        "'import' was removed; use 'use STD as Standard'",
        aliased.diagnostic.?.message,
    );

    var direct = Parser.init(arena.allocator(), "import STD\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, direct.parse());
    try std.testing.expectEqualStrings("'import' was removed; use 'use STD'", direct.diagnostic.?.message);
}

test "parse terminal else match branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum State { idle; ready; failed(str) }
        \\func main() {
        \\    let state = State.idle()
        \\    let text = match state { idle => "idle"; else => "other" }
        \\    match state { failed(message) => { print(message) }; else => {} }
        \\}
    );
    const program = try parser.parse();
    const expression_match = program.functions[0].statements[1].variable_declaration.initializer.?.value.match_expression;
    try std.testing.expect(expression_match.branches[0].variant != null);
    try std.testing.expect(expression_match.branches[1].variant == null);
    const imperative_match = program.functions[0].statements[2].expression_statement.value.match_expression;
    try std.testing.expect(imperative_match.branches[1].variant == null);
}

test "reject misplaced and binding else match branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var misplaced = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { else => {}; ready => {} } }
    );
    try std.testing.expectError(error.InvalidSource, misplaced.parse());
    try std.testing.expectEqualStrings("else must be the last match branch", misplaced.diagnostic.?.message);

    var binding = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; else(value) => {} } }
    );
    try std.testing.expectError(error.InvalidSource, binding.parse());
    try std.testing.expectEqualStrings("an else match branch cannot bind associated values", binding.diagnostic.?.message);
}

test "reject mixed enum match branch forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 0; ready => {} } }
    );
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("match branches cannot mix expressions and blocks", parser.diagnostic.?.message);
}

test "parse int and string raw enums" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\enum Direction:int { north = 1; unknown = -1 }
        \\enum DirectionName:str { north = "north"; south = "south" }
        \\func main() { print(Direction.north().raw_value) }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.RawEnumType.int, program.enums[0].raw_type.?);
    try std.testing.expect(program.enums[0].variants[0].raw_value.?.value == .integer);
    try std.testing.expect(program.enums[0].variants[1].raw_value.?.value == .unary);
    try std.testing.expectEqual(Ast.RawEnumType.str, program.enums[1].raw_type.?);
    try std.testing.expect(program.enums[1].variants[0].raw_value.?.value == .string);
}

test "reject invalid raw enum declaration shapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var invalid_type = Parser.init(arena.allocator(), "enum State:bool { ready = true }");
    try std.testing.expectError(error.InvalidSource, invalid_type.parse());
    try std.testing.expectEqualStrings("an enum raw type must be 'int' or 'str'", invalid_type.diagnostic.?.message);

    var missing_value = Parser.init(arena.allocator(), "enum State:int { ready }");
    try std.testing.expectError(error.InvalidSource, missing_value.parse());
    try std.testing.expectEqualStrings("a raw enum variant requires a value", missing_value.diagnostic.?.message);

    var associated_value = Parser.init(arena.allocator(), "enum State:int { ready(str) = 1 }");
    try std.testing.expectError(error.InvalidSource, associated_value.parse());
    try std.testing.expectEqualStrings("a raw enum variant cannot declare associated values", associated_value.diagnostic.?.message);

    var missing_type = Parser.init(arena.allocator(), "enum State { ready = 1 }");
    try std.testing.expectError(error.InvalidSource, missing_type.parse());
    try std.testing.expectEqualStrings("an enum without a raw type cannot assign variant values", missing_type.diagnostic.?.message);

    var generic_raw = Parser.init(arena.allocator(), "enum State<T>:int { ready = 1 }");
    try std.testing.expectError(error.InvalidSource, generic_raw.parse());
    try std.testing.expectEqualStrings("a raw enum cannot be generic", generic_raw.diagnostic.?.message);
}

test "require a name for a type alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "use int[]\nfunc main() {}");
    try std.testing.expectError(error.InvalidSource, parser.parse());
    try std.testing.expectEqualStrings("a type expression after 'use' requires an alias with 'as'", parser.diagnostic.?.message);
}

test "parse type extensions and reject stateful members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\extend STD.Randomizer {
        \\    public func get_uint() uint { return self.get_int() as uint }
        \\    static func seeded() Randomizer { return Randomizer.create() }
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.extensions.len);
    try std.testing.expectEqualStrings("STD.Randomizer", program.extensions[0].target);
    try std.testing.expectEqual(@as(usize, 2), program.extensions[0].methods.len);
    try std.testing.expect(program.extensions[0].methods[0].is_public);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.extensions[0].methods[0].member_visibility.?);
    try std.testing.expect(program.extensions[0].methods[1].is_static);
    try std.testing.expect(program.extensions[0].methods[1].member_visibility == null);

    var generic_method = Parser.init(arena.allocator(),
        \\extend Randomizer {
        \\    public func choose<T>(values:@T[..]) @values:T { return @values[0] }
        \\    func select<Key, Value:Comparable>(key:Key, fallback:Value?) Value? { return fallback }
        \\}
        \\func main() {}
    );
    const generic_program = try generic_method.parse();
    try std.testing.expectEqual(@as(usize, 1), generic_program.extensions[0].methods[0].type_parameters.len);
    try std.testing.expectEqual(@as(usize, 2), generic_program.extensions[0].methods[1].type_parameters.len);
    try std.testing.expectEqualStrings("Comparable", generic_program.extensions[0].methods[1].type_parameters[1].constraint.?.name);

    var generic_static = Parser.init(arena.allocator(), "extend Randomizer { static func create<T>() Randomizer {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, generic_static.parse());
    try std.testing.expectEqualStrings("generic static extension methods are not supported", generic_static.diagnostic.?.message);

    var field = Parser.init(arena.allocator(), "extend Randomizer { var state:int } func main() {}");
    try std.testing.expectError(error.InvalidSource, field.parse());
    try std.testing.expectEqualStrings("an extension cannot declare a field", field.diagnostic.?.message);

    var subclass = Parser.init(arena.allocator(), "extend Randomizer { protected func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, subclass.parse());
    try std.testing.expectEqualStrings("an extension method cannot use 'protected'", subclass.diagnostic.?.message);

    var private_method = Parser.init(arena.allocator(), "extend Randomizer { private func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, private_method.parse());
    try std.testing.expectEqualStrings("an extension method cannot use 'private'", private_method.diagnostic.?.message);

    var constructor = Parser.init(arena.allocator(), "extend Randomizer { init() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, constructor.parse());
    try std.testing.expectEqualStrings("an extension cannot declare a constructor", constructor.diagnostic.?.message);

    var destructor = Parser.init(arena.allocator(), "extend Randomizer { drop {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, destructor.parse());
    try std.testing.expectEqualStrings("an extension cannot declare 'drop'", destructor.diagnostic.?.message);

    var override_method = Parser.init(arena.allocator(), "extend Randomizer { override func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, override_method.parse());
    try std.testing.expectEqualStrings("an extension method cannot use 'override'", override_method.diagnostic.?.message);

    var generic = Parser.init(arena.allocator(), "extend Randomizer<int> { func next() {} } func main() {}");
    try std.testing.expectError(error.InvalidSource, generic.parse());
    try std.testing.expectEqualStrings("generic extensions are not supported", generic.diagnostic.?.message);
}

test "parse protocol conformances on a type extension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\extend Sprite : Drawable, UI.Renderable {
        \\    public func draw() {}
        \\}
        \\func main() {}
    );
    const program = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), program.extensions.len);
    try std.testing.expectEqual(@as(usize, 2), program.extensions[0].conformances.len);
    try std.testing.expectEqualStrings("Drawable", program.extensions[0].conformances[0].name);
    try std.testing.expectEqualStrings("UI.Renderable", program.extensions[0].conformances[1].name);

    var missing = Parser.init(arena.allocator(), "extend Sprite : { } func main() {}");
    try std.testing.expectError(error.InvalidSource, missing.parse());
    try std.testing.expectEqualStrings("expected protocol name after ':'", missing.diagnostic.?.message);
}

test "parse read reference parameters with ordinary arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(),
        \\struct Data { let value:int }
        \\func inspect(value:@Data) int { return value.value }
        \\func main() { let data = Data(value:1); inspect(data) }
    );
    const program = try parser.parse();
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.functions[0].parameters[0].mode);
    const call = program.functions[1].statements[1].expression_statement.value.call;
    try std.testing.expect(call.arguments[0].value == .identifier);

    var released_identifier = Parser.init(arena.allocator(), "func borrow(value:int) int { return value } func main() {}");
    _ = try released_identifier.parse();

    var old_keyword = Parser.init(arena.allocator(), "func inspect(borrow value:Data) {} func main() {}");
    try std.testing.expectError(error.InvalidSource, old_keyword.parse());

    var old_postfix = Parser.init(arena.allocator(), "func inspect(value:Data@) {} func main() {}");
    try std.testing.expectError(error.InvalidSource, old_postfix.parse());
}
