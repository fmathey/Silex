const std = @import("std");
const Ast = @import("../Ast.zig");
const Parser = @import("../Parser.zig").Parser;
const Specializer = @import("Specializer.zig").Specializer;

test "specialize protocol constrained generic functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User : Named { func name() str { return "Ada" } }
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { print(label<User>(User())) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    var found = false;
    for (program.functions) |function| {
        if (std.mem.startsWith(u8, function.name, "label<")) found = true;
    }
    try std.testing.expect(found);
}

test "specialize generic types in protocol requirements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Reader { func read(buffer:&uint8[..]) Result<int,str> }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 1), program.protocols.len);
    try std.testing.expect(program.protocols[0].requirements[0].return_type == .structure);
    try std.testing.expect(std.mem.startsWith(
        u8,
        program.protocols[0].requirements[0].return_type.structure,
        "Result<int, str>",
    ));
}

test "reject a type argument without declared protocol conformance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User { func name() str { return "Ada" } }
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { print(label<User>(User())) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    try std.testing.expectError(error.InvalidSource, specializer.specialize());
    try std.testing.expectEqualStrings(
        "type argument 'User' does not conform to protocol 'Named' required by 'T'",
        specializer.diagnostic.?.message,
    );
}

test "accept inherited protocol conformance for a type argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\class Entity : Named { public func name() str { return "entity" } }
        \\class Player : Entity {}
        \\func label<T : Named>(value:T) str { return value.name() }
        \\func main() { var player = Player(); print(label<Player>(player)) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    _ = try specializer.specialize();
}

test "specialize a constrained generic enum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct User : Named { func name() str { return "Ada" } }
        \\enum Event<T : Named> { value(T) }
        \\func main() { let event = Event<User>.value(User()) }
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 1), program.enums.len);
}

test "specialize generic extension methods and reuse identical calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Catalog {}
        \\extend Catalog {
        \\    func identity<T>(value:T) T { return value }
        \\    func select<Key, Value>(key:Key, value:Value?) Value? { return value }
        \\    func transform<T>(values:T[], callback:func(T) T) T? {
        \\        let first:T = values[0]
        \\        return callback(first)
        \\    }
        \\    func repeat<T>(value:T, count:int) T {
        \\        if count == 0 { return value }
        \\        return self.repeat<T>(value, count - 1)
        \\    }
        \\}
        \\func main() {
        \\    var catalog = Catalog()
        \\    print(catalog.identity<int>(1))
        \\    print(catalog.identity<int>(2))
        \\    print(catalog.identity<str>("ok"))
        \\    let selected = catalog.select<int, str>(1, "value")
        \\    let transformed = catalog.transform<int>([1], func(value:int) int { return value })
        \\    print(catalog.repeat<int>(3, 1))
        \\}
    );
    var specializer = Specializer.init(allocator, try parser.parse());
    const program = try specializer.specialize();
    try std.testing.expectEqual(@as(usize, 5), program.structures[0].methods.len);
    try std.testing.expectEqualStrings("identity<int>", program.structures[0].methods[0].name);
    try std.testing.expectEqualStrings("identity<str>", program.structures[0].methods[1].name);
    try std.testing.expectEqualStrings("select<int, str>", program.structures[0].methods[2].name);
    try std.testing.expectEqualStrings("transform<int>", program.structures[0].methods[3].name);
    try std.testing.expectEqualStrings("repeat<int>", program.structures[0].methods[4].name);
}

test "diagnose generic extension method arguments and constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var missing_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity(1)) }
    );
    var missing = Specializer.init(allocator, try missing_parser.parse());
    try std.testing.expectError(error.InvalidSource, missing.specialize());
    try std.testing.expectEqualStrings("generic extension method 'identity' requires explicit type arguments", missing.diagnostic.?.message);

    var arity_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity<int, str>(1)) }
    );
    var arity = Specializer.init(allocator, try arity_parser.parse());
    try std.testing.expectError(error.InvalidSource, arity.specialize());
    try std.testing.expectEqualStrings("generic extension method 'identity' expects 1 type argument, found 2", arity.diagnostic.?.message);

    var constraint_parser = Parser.init(allocator,
        \\protocol Named { func name() str }
        \\struct Box {}
        \\struct Value {}
        \\extend Box { func label<T:Named>(value:T) str { return value.name() } }
        \\func main() { var box = Box(); print(box.label<Value>(Value())) }
    );
    var constraint = Specializer.init(allocator, try constraint_parser.parse());
    try std.testing.expectError(error.InvalidSource, constraint.specialize());
    try std.testing.expectEqualStrings(
        "type argument 'Value' does not conform to protocol 'Named' required by 'T'",
        constraint.diagnostic.?.message,
    );

    var concrete_parser = Parser.init(allocator,
        \\struct Box { func identity(value:int) int { return value } }
        \\extend Box { func identity<T>(value:T) T { return value } }
        \\func main() { var box = Box(); print(box.identity(1)) }
    );
    var concrete = Specializer.init(allocator, try concrete_parser.parse());
    const concrete_program = try concrete.specialize();
    try std.testing.expectEqual(@as(usize, 1), concrete_program.structures[0].methods.len);

    var expansion_parser = Parser.init(allocator,
        \\struct Box {}
        \\extend Box {
        \\    func expand<T>(value:T) { self.expand<T[]>([value]) }
        \\}
        \\func main() { var box = Box(); box.expand<int>(1) }
    );
    var expansion = Specializer.init(allocator, try expansion_parser.parse());
    try std.testing.expectError(error.InvalidSource, expansion.specialize());
    try std.testing.expectEqualStrings(
        "generic extension method 'expand' recursively expands with different type arguments",
        expansion.diagnostic.?.message,
    );
}
