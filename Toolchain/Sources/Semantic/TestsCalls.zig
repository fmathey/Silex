const Types = @import("Types.zig");
const AnalyzerModule = @import("Analyzer.zig");
const Support = @import("Support.zig");
const TestSupport = @import("TestSupport.zig");
const expectSemanticError = TestSupport.expectSemanticError;
const expectResolvedSemanticError = TestSupport.expectResolvedSemanticError;
const expectResolvedSemanticErrorContains = TestSupport.expectResolvedSemanticErrorContains;
const expectSemanticSuccess = TestSupport.expectSemanticSuccess;
const analyzeDeferredNativeTest = TestSupport.analyzeDeferredNativeTest;
const resolveDeferredNativeTestProgram = TestSupport.resolveDeferredNativeTestProgram;
const expectDeferredNativeError = TestSupport.expectDeferredNativeError;
const expectDeferredNativeSuccess = TestSupport.expectDeferredNativeSuccess;
const expectNativeStructureReturnRejected = TestSupport.expectNativeStructureReturnRejected;
const expectNativeStructureParameterRejected = TestSupport.expectNativeStructureParameterRejected;
const expectNativeByteViewParameterRejected = TestSupport.expectNativeByteViewParameterRejected;
const resolveSingleTestProgram = TestSupport.resolveSingleTestProgram;
const std = Types.std;
const Ast = Types.Ast;
const Source = Types.Source;
const Allocator = Types.Allocator;
const AnalyzeError = Types.AnalyzeError;
const never_capture_box = Types.never_capture_box;
const DeferredResourcePath = Types.DeferredResourcePath;
const TransferMode = Types.TransferMode;
const Type = Types.Type;
const FunctionType = Types.FunctionType;
const StructureType = Types.StructureType;
const ProtocolType = Types.ProtocolType;
const EnumType = Types.EnumType;
const ReferenceType = Types.ReferenceType;
const FixedArrayType = Types.FixedArrayType;
const BindingState = Types.BindingState;
const Borrow = Types.Borrow;
const Expression = Types.Expression;
const Statement = Types.Statement;
const Program = Types.Program;
const Protocol = Types.Protocol;
const ProtocolMethod = Types.ProtocolMethod;
const ProtocolConformance = Types.ProtocolConformance;
const Enum = Types.Enum;
const EnumVariant = Types.EnumVariant;
const Structure = Types.Structure;
const BaseInitializer = Types.BaseInitializer;
const StructureField = Types.StructureField;
const NativeStructureTransport = Types.NativeStructureTransport;
const NativeTransportField = Types.NativeTransportField;
const NativeResultTransport = Types.NativeResultTransport;
const Constructor = Types.Constructor;
const Drop = Types.Drop;
const Parameter = Types.Parameter;
const Function = Types.Function;
const Method = Types.Method;
const MethodId = Types.MethodId;
const Receiver = Types.Receiver;
const Symbol = Types.Symbol;
const Scope = Types.Scope;
const OwnerStateSnapshot = Types.OwnerStateSnapshot;
const LoopFlow = Types.LoopFlow;
const LambdaContext = Types.LambdaContext;
const releaseBorrow = Types.releaseBorrow;
const FunctionSymbol = Types.FunctionSymbol;
const StructureSymbol = Types.StructureSymbol;
const ProtocolConformanceSymbol = Types.ProtocolConformanceSymbol;
const ProtocolSymbol = Types.ProtocolSymbol;
const ProtocolRequirement = Types.ProtocolRequirement;
const EnumSymbol = Types.EnumSymbol;
const EnumVariantSymbol = Types.EnumVariantSymbol;
const ConstructorSymbol = Types.ConstructorSymbol;
const ConstructorCandidate = Types.ConstructorCandidate;
const ImplicitBaseInitialization = Types.ImplicitBaseInitialization;
const MethodSymbol = Types.MethodSymbol;
const MethodCandidate = Types.MethodCandidate;
const methodCandidatesContainSlot = Types.methodCandidatesContainSlot;
const fileSetContains = Types.fileSetContains;
const fileSetsOverlap = Types.fileSetsOverlap;
const visibilityRank = Types.visibilityRank;
const FieldCandidate = Types.FieldCandidate;
const StructureFieldSymbol = Types.StructureFieldSymbol;
const FieldInitialization = Types.FieldInitialization;
const Analyzer = AnalyzerModule.Analyzer;
const allFieldsInitialized = Support.allFieldsInitialized;
const containsIndex = Support.containsIndex;
const hasDirectDeferredResource = Support.hasDirectDeferredResource;
const deferredResourcePathStartsWith = Support.deferredResourcePathStartsWith;
const containsDeferredResourcePath = Support.containsDeferredResourcePath;
const deferredResourcePathsEqual = Support.deferredResourcePathsEqual;
const DeferredReturnSummary = Support.DeferredReturnSummary;
const mergeReturnedDeferredResourcePaths = Support.mergeReturnedDeferredResourcePaths;
const collectReturnedDeferredResourcePaths = Support.collectReturnedDeferredResourcePaths;
const collectReturnedResourceDependencies = Support.collectReturnedResourceDependencies;
const generatedFieldIndex = Support.generatedFieldIndex;
const directSelfFieldIndex = Support.directSelfFieldIndex;
const mutationReachesClassIdentity = Support.mutationReachesClassIdentity;
const findInCurrentScope = Support.findInCurrentScope;
const findSymbol = Support.findSymbol;
const typeFromAnnotation = Support.typeFromAnnotation;
const typeFromReturn = Support.typeFromReturn;
const typeFromFunction = Support.typeFromFunction;
const typeFromReference = Support.typeFromReference;
const parseFixedArrayLength = Support.parseFixedArrayLength;
const blockAlwaysReturns = Support.blockAlwaysReturns;
const astStatementsFallThrough = Support.astStatementsFallThrough;
const astStatementFallsThrough = Support.astStatementFallsThrough;
const parameterStored = Support.parameterStored;
const astCollectionCallStoresIdentifier = Support.astCollectionCallStoresIdentifier;
const astExpressionUsesIdentifier = Support.astExpressionUsesIdentifier;
const typeMismatchMessage = Support.typeMismatchMessage;
const referenceMutability = Support.referenceMutability;
const normalizeNumericLiteral = Support.normalizeNumericLiteral;
const hexDigit = Support.hexDigit;
const appendUnicodeScalar = Support.appendUnicodeScalar;
const isUniqueOwnerType = Support.isUniqueOwnerType;
const containsDeferredCallback = Support.containsDeferredCallback;
const typeEqual = Support.typeEqual;
const rawEnumValuesEqual = Support.rawEnumValuesEqual;
const rawEnumInteger = Support.rawEnumInteger;
const sameSignature = Support.sameSignature;
const sameCallableShape = Support.sameCallableShape;
const containsPosition = Support.containsPosition;
const overloadScore = Support.overloadScore;
const literalOverloadScore = Support.literalOverloadScore;
const overloadBetter = Support.overloadBetter;
const appendSignature = Support.appendSignature;
const functionSignatures = Support.functionSignatures;
const methodSignatures = Support.methodSignatures;
const constructorSignatures = Support.constructorSignatures;
const isNativeScalarReturnType = Support.isNativeScalarReturnType;
const isNativeStructureFieldType = Support.isNativeStructureFieldType;
const isNativeScalarParameterType = Support.isNativeScalarParameterType;
const isNativeScalarViewType = Support.isNativeScalarViewType;
const isNativeCallbackScalarType = Support.isNativeCallbackScalarType;
const isNativeCallbackType = Support.isNativeCallbackType;
const isNativeByteViewType = Support.isNativeByteViewType;
const isNativeByteBufferReturnType = Support.isNativeByteBufferReturnType;
const moduleName = Support.moduleName;
const lastNameSegment = Support.lastNameSegment;
const nativeSymbol = Support.nativeSymbol;
const typeName = Support.typeName;
const allocatedTypeName = Support.allocatedTypeName;
const allocatedSignatureTypeName = Support.allocatedSignatureTypeName;
const sequenceElementType = Support.sequenceElementType;
const isPlaceValue = Support.isPlaceValue;
const isStructure = Support.isStructure;
const isNumeric = Support.isNumeric;
const isInteger = Support.isInteger;
const isUnsignedInteger = Support.isUnsignedInteger;
const commonUnsignedIntegerType = Support.commonUnsignedIntegerType;
const integerBits = Support.integerBits;
const integerLiteralFits = Support.integerLiteralFits;
const isContextualIntegerLiteral = Support.isContextualIntegerLiteral;
const canWiden = Support.canWiden;
const commonNumericType = Support.commonNumericType;
const isPrintable = Support.isPrintable;
const AssignmentRoot = Support.AssignmentRoot;
const isCascadeOwnedTemporary = Support.isCascadeOwnedTemporary;
const assignmentRoot = Support.assignmentRoot;
const expressionScopeDepth = Support.expressionScopeDepth;
const assignmentDestinationDepth = Support.assignmentDestinationDepth;
const updateDestinationLifetime = Support.updateDestinationLifetime;
const receiverFor = Support.receiverFor;
const assignmentOperatorText = Support.assignmentOperatorText;
test "reject explicit conversion from bool" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let value = true as int; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "explicit conversion requires numeric source and target types, found 'bool' and 'int'",
        analyzer.diagnostic.?.message,
    );
}

test "reject arithmetic between str and int" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { print(\"Hello\" + 2); }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqual(@as(usize, 34), analyzer.diagnostic.?.position.column);
}

test "comparison and logical expressions produce bool" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let result = !(1 >= 2) && \"Silex\" == \"Silex\"; }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[0].variable_declaration.type);
}

test "reject logical operator with int operand" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = 1 && true; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "logical operator requires 'bool' operands, found 'int' and 'bool'",
        analyzer.diagnostic.?.message,
    );
}

test "reject comparison with str operand" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = \"one\" < 2; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "comparison operator requires numeric operands, found 'str' and 'int'",
        analyzer.diagnostic.?.message,
    );
}

test "reject equality between different types" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = 1 == true; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "equality operator requires operands of the same type, found 'int' and 'bool'",
        analyzer.diagnostic.?.message,
    );
}

test "resolve structural equality recursively" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int; var y:int }
        \\struct Player { var name:str; var position:Position }
        \\func main() void {
        \\    let first = Player(name:"Ada", position:Position(x:10, y:20))
        \\    let copy = Player(name:"Ada", position:Position(x:10, y:20))
        \\    let equal = first == copy
        \\    let different = first != Player(name:"Ada", position:Position(x:11, y:20))
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));

    try std.testing.expectEqual(Type.bool, program.functions[0].statements[2].variable_declaration.type);
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[3].variable_declaration.type);
}

test "if alternatives and else use separate scopes" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { if false { let value = 1 } elif true { let value = 2 } else if false { let value = 3 } else { let value = 4 } }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    const if_statement = program.functions[0].statements[0].if_statement;
    try std.testing.expectEqual(@as(usize, 2), if_statement.alternatives.len);
    try std.testing.expectEqual(@as(usize, 1), if_statement.else_body.?.len);
}

test "alternative conditions require bool" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { if false {} elif 1 {} }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "while requires bool condition and creates a scope" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { var count = 2; while (count > 0) { let inside = count; count = count - 1; } }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[1].while_statement.condition.expression.type);
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements[1].while_statement.body.len);
}

test "reject while condition that is not bool" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { while (1) { print(1); } }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "implicit conditional bindings keep let semantics" {
    try expectSemanticError(
        "func main() { var source:int? = 1; if value = source { value = 2 } }",
        "cannot assign to immutable control binding 'value'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } func main() { var source:Counter? = Counter(value:0); if counter = source { counter.bump() } }",
        "cannot mutate immutable control binding 'counter'; use 'var' in the header",
    );
}

test "resolve forward and recursive function calls" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void { print(factorial(5)) }
        \\func factorial(value:int) int {
        \\    if (value <= 1) { return 1 } else { return value * factorial(value - 1) }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expectEqual(Type.int, program.functions[1].return_type);
}

test "reject mutation of a let captured by a lambda" {
    try expectSemanticError(
        "func main() { let count = 1; var callback = func() { count += 1; }; callback(); }",
        "cannot assign to immutable variable 'count'",
    );
}

test "reject returning a capturing lambda" {
    try expectSemanticError(
        "func invalid() func() { var count = 1; return func() { count += 1; }; } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "reject storing a callback beyond a captured block" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Foo {
        \\    var callback:func()
        \\    func set_callback(callback:func()) { self.callback = callback }
        \\}
        \\func main() {
        \\    var foo = Foo(callback:func() {})
        \\    if (true) {
        \\        var count = 1
        \\        foo.set_callback(func() { count += 1 })
        \\    }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expectEqualStrings(
        "capturing callback cannot be stored in a receiver that outlives one of its captures",
        analyzer.diagnostic.?.message,
    );
}

test "reject incompatible lambda signature" {
    try expectSemanticError(
        "func main() { var callback:func(int) int = func(value:str) int { return 1; }; }",
        "expected 'func', found 'func'",
    );
}

test "reject missing default function value" {
    try expectSemanticError(
        "func main() { var callback:func(); }",
        "a function value requires an initializer",
    );
}

test "reject equality of function values" {
    try expectSemanticError(
        "func main() { var callback = func() {}; let same = callback == callback; }",
        "function values and values containing them are not comparable",
    );
}

test "reject extracting an owner callback beyond its owner" {
    try expectSemanticError(
        \\struct Foo { var callback:func() }
        \\func invalid(foo:Foo) func() { return foo.callback }
        \\func main() {}
    ,
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "accept scalar function values at the native boundary" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_hook(callback:func(int) bool) void; func main() {}");
    const parsed = try parser.parse();
    const functions = try allocator.dupe(Ast.Function, parsed.functions);
    functions[0].name = "Test.native_hook";
    var program = parsed;
    program.functions = functions;
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    _ = try analyzer.analyze(program);
}

test "reject non scalar function values at the native boundary" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_hook(callback:func(str) bool) void; func main() {}");
    const parsed = try parser.parse();
    const functions = try allocator.dupe(Ast.Function, parsed.functions);
    functions[0].name = "Test.native_hook";
    var program = parsed;
    program.functions = functions;
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings(
        "native parameter 'callback' cannot use 'func'",
        analyzer.diagnostic.?.message,
    );
}

test "reject storing a capturing lambda in a longer-lived collection" {
    try expectSemanticError(
        \\func main() {
        \\    var callbacks:func()[] = []
        \\    if (true) {
        \\        var count = 1
        \\        callbacks.append(func() { count += 1 })
        \\    }
        \\}
    ,
        "capturing function value cannot be stored in a longer-lived collection",
    );
}

test "read references preserve owners and accept ordinary arguments" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Resource {
        \\    var handle:int
        \\    func get_handle() int { return self.handle }
        \\    drop {}
        \\}
        \\func inspect(value:@int) int { return value + 1 }
        \\func describe(resource:@Resource) int { return resource.get_handle() }
        \\func forward(resource:@Resource) int { return describe(resource) }
        \\func pair(left:@Resource, right:@Resource) int { return left.get_handle() + right.get_handle() }
        \\func main() {
        \\    var resource = Resource(handle:4)
        \\    let copied = inspect(4)
        \\    let borrowed = inspect(copied)
        \\    let described = describe(resource)
        \\    let forwarded = forward(resource)
        \\    let paired = pair(resource, resource)
        \\    let temporary = describe(Resource(handle:5))
        \\    let moved = move resource
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.functions[0].parameters[0].mode);
    try std.testing.expect(program.functions[4].statements[2].variable_declaration.initializer.value == .call);

    try expectResolvedSemanticError(
        "func inspect(value:int) {} func inspect(value:@int) {} func main() {}",
        "function 'inspect' with this callable shape is already declared",
    );
    try expectResolvedSemanticError(
        "class Box { init(value:int) {} init(value:@int) {} } func main() {}",
        "constructor 'init' with this callable shape is already declared in this class",
    );
    try expectResolvedSemanticError(
        "struct Box { func inspect(value:int) {} func inspect(value:@int) {} } func main() {}",
        "method 'inspect' with this callable shape is already declared in struct 'Box'",
    );
    try expectResolvedSemanticError(
        "protocol Reader { func inspect(value:int); func inspect(value:@int) } func main() {}",
        "protocol method 'inspect' with this callable shape is already declared",
    );
    try expectResolvedSemanticError(
        "func inspect(value:@int) {} func main() { inspect(@1) }",
        "reference arguments are selected by the parameter signature; pass the value without '@'",
    );
    try expectResolvedSemanticError(
        "func increment(value:&int) {} func main() { var value = 1; increment(&value) }",
        "reference arguments are selected by the parameter signature; pass the place without '&'",
    );
}

test "read references reject mutation conflicts and escape" {
    const resource =
        \\struct Resource {
        \\    var handle:int
        \\    func get_handle() int { return self.handle }
        \\    func increment() { self.handle += 1 }
        \\    drop {}
        \\}
    ;
    try expectResolvedSemanticError(
        resource ++ "func invalid(value:@Resource) { value.increment() } func main() {}",
        "cannot call mutating method 'increment' on immutable value 'value'",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(value:@Resource) Resource { return value } func main() {}",
        "a read-reference parameter cannot be returned from its call",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(value:@Resource) { let callback = func() { print(value.handle) } } func main() {}",
        "a read-reference parameter cannot be captured by a lambda",
    );
    try expectResolvedSemanticError(
        "struct Data { var value:int } struct Holder { var saved:Data; func save(value:@Data) { self.saved = value } } func main() {}",
        "a read-reference parameter cannot be stored beyond its call",
    );
    try expectResolvedSemanticError(
        "struct Holder { var saved:int[]; func save(value:@int) { self.saved.append(value) } } func main() {}",
        "a read-reference parameter cannot be stored beyond its call",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(value:@Resource) { let moved = move value } func main() {}",
        "a read-reference parameter cannot be consumed with 'move'",
    );
    try expectResolvedSemanticError(
        resource ++ "func conflict(first:@Resource, second:Resource) {} func main() { let value = Resource(handle:1); conflict(value, move value) }",
        "cannot move borrowed noncopyable value 'value'",
    );
    try expectResolvedSemanticError(
        "func conflict(first:@int, second:&int) {} func main() { var value = 1; conflict(value, value) }",
        "cannot pass a value to a mutable reference parameter while it is read-borrowed",
    );
    try expectResolvedSemanticError(
        "func conflict(first:&int, second:@int) {} func main() { var value = 1; conflict(value, value) }",
        "cannot read-borrow a value while it is mutably borrowed",
    );
    try expectResolvedSemanticError(
        "class Shared {} func inspect(value:@Shared) {} func main() {}",
        "class 'Shared' already has shared identity; parameter mode '@' is invalid",
    );
    try expectResolvedSemanticError(
        "protocol Shared { func read() } func inspect(value:@Shared) {} func main() {}",
        "a dynamic protocol value cannot use parameter mode '@'",
    );
}

test "native functions reject read reference parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_inspect(value:@int) void; func main() {}");
    const parsed = try parser.parse();
    const functions = try allocator.dupe(Ast.Function, parsed.functions);
    functions[0].name = "Test.native_inspect";
    var program = parsed;
    program.functions = functions;
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings(
        "a native function cannot declare an '@T' parameter",
        analyzer.diagnostic.?.message,
    );
}

test "deferred native registrations transfer callbacks and expose dispatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try analyzeDeferredNativeTest(arena.allocator(),
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func(int)) Watch
        \\func main() {
        \\    var total = 0
        \\    var callback:deferred func(int) = deferred func(value:int) { total += value }
        \\    let watch = start_watch(move callback)
        \\    assert(dispatch_callbacks(watch) == 0, "empty")
        \\}
    );
    try std.testing.expect(program.functions[1].deferred_callback_index != null);
    try std.testing.expectEqual(@as(usize, 0), program.functions[1].deferred_callback_index.?);
    try std.testing.expectEqual(Type.int, program.functions[2].statements[3].assertion.condition.value.binary.left.type);
}

test "deferred callbacks enforce scalar void signatures" {
    const resource =
        \\public native resource Watch { drop stop_watch }
    ;
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func(int) bool) Watch\nfunc main() {}",
        "a 'deferred func' must return 'void'",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func(str)) Watch\nfunc main() {}",
        "a 'deferred func' parameter must be a scalar bool or numeric value",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func(@int)) Watch\nfunc main() {}",
        "a 'deferred func' parameter must be a scalar bool or numeric value",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func(Watch)) Watch\nfunc main() {}",
        "a 'deferred func' parameter must be a scalar bool or numeric value",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func(func())) Watch\nfunc main() {}",
        "a 'deferred func' parameter must be a scalar bool or numeric value",
    );
}

test "deferred callbacks are unique and cannot be called or stored" {
    try expectDeferredNativeError(
        "func main() { var callback:deferred func() = deferred func() {}; callback() }",
        "a 'deferred func' cannot be called directly in Silex",
    );
    try expectDeferredNativeError(
        "func main() { var callback:deferred func() = deferred func() {}; var copy = callback }",
        "cannot copy noncopyable value 'deferred func'; initialize it directly from a temporary value or use 'move'",
    );
    try expectDeferredNativeError(
        "struct Holder { var callback:deferred func() } func main() {}",
        "a 'deferred func' cannot be stored in another type",
    );
    try expectDeferredNativeError(
        "func main() { var callback:(deferred func())? = deferred func() {} }",
        "a 'deferred func' cannot be stored in another type",
    );
}

test "deferred registration requires one callback and one direct resource return" {
    const resource =
        \\public native resource Watch { drop stop_watch }
    ;
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(first:deferred func(), second:deferred func()) Watch\nfunc main() {}",
        "a native deferred registration requires exactly one 'deferred func' parameter",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func()) void\nfunc main() {}",
        "a native deferred registration must return one native resource directly",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func start_watch(callback:deferred func()) Watch?\nfunc main() {}",
        "a native deferred registration must return one native resource directly",
    );
    try expectDeferredNativeError(
        "func consume(callback:deferred func()) {} func main() {}",
        "a 'deferred func' parameter is only valid in a native registration function",
    );
    try expectDeferredNativeError(
        "func make() deferred func() { return deferred func() {} } func main() {}",
        "a Silex function cannot return 'deferred func'",
    );
}

test "deferred registration requires move and propagates capture lifetime" {
    const resource =
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func(int)) Watch
    ;
    try expectDeferredNativeError(
        resource ++ "\nfunc main() { var callback:deferred func(int) = deferred func(value:int) {}; let watch = start_watch(callback) }",
        "noncopyable value 'deferred func' must be passed with 'move'",
    );
    try expectDeferredNativeError(
        resource ++ "\nfunc subscribe() Watch { var total = 0; return start_watch(deferred func(value:int) { total += value }) } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func create_watch() Watch\nfunc leak() Watch { var watch = create_watch(); var total = 0; watch = start_watch(deferred func(value:int) { total += value }); return move watch } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
    try expectDeferredNativeError(
        resource ++ "\nnative func create_watch() Watch\nfunc leak(use_deferred:bool) Watch { var watch = create_watch(); var total = 0; if use_deferred { watch = start_watch(deferred func(value:int) { total += value }) } else { watch = create_watch() } return move watch } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
    try expectDeferredNativeError(
        resource ++ "\nfunc main() { let first = start_watch(deferred func(value:int) {}); let second = start_watch(deferred func(value:int) { dispatch_callbacks(first) }) }",
        "noncopyable value 'Test.Watch' cannot be captured by a lambda",
    );
    try expectDeferredNativeError(
        resource ++ "\nfunc invalid(value:@int) { var callback:deferred func(int) = deferred func(event:int) { print(value + event) } } func main() {}",
        "a read-reference parameter cannot be captured by a lambda",
    );
    try expectDeferredNativeError(
        resource ++ "\nfunc main() { var first:deferred func(int) = deferred func(value:int) {}; var second:deferred func(int) = deferred func(value:int) { var captured = move first } }",
        "noncopyable value 'deferred func' cannot be captured by a lambda",
    );
}

test "deferred subscriptions cannot transfer ownership to ordinary native calls" {
    try expectDeferredNativeError(
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func()) Watch
        \\native func retain_watch(watch:Watch) void
        \\func main() {
        \\    let watch = start_watch(deferred func() {})
        \\    retain_watch(move watch)
        \\}
    ,
        "a deferred subscription can only be transferred to its declared native destructor",
    );
}

test "dispatch callbacks rejects ordinary and destroyed resources" {
    const declarations =
        \\public native resource Watch { drop stop_watch }
        \\public native resource Other { drop stop_other }
        \\native func start_watch(callback:deferred func()) Watch
        \\native func create_watch() Watch
        \\native func create_other() Other
    ;
    try expectDeferredNativeError(
        declarations ++ "\nfunc main() { let ordinary = create_watch(); dispatch_callbacks(ordinary) }",
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );
    try expectDeferredNativeError(
        declarations ++ "\nstruct Watches { var subscription:Watch; var ordinary:Watch } func main() { let watches = Watches(subscription:start_watch(deferred func() {}), ordinary:create_watch()); dispatch_callbacks(watches.ordinary) }",
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );
    try expectDeferredNativeError(
        declarations ++ "\nstruct Watches { var subscription:Watch } func main() { var watches = Watches(subscription:start_watch(deferred func() {})); watches.subscription = create_watch(); dispatch_callbacks(watches.subscription) }",
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );
    try expectDeferredNativeError(
        declarations ++ "\nfunc main() { var watch = create_watch(); if true { watch = start_watch(deferred func() {}) } else { watch = create_watch() } dispatch_callbacks(watch) }",
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );
    try expectDeferredNativeError(
        declarations ++ "\nfunc main() { let other = create_other(); dispatch_callbacks(other) }",
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );

    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, declarations ++ "\nfunc main() { let watch = start_watch(deferred func() {}); stop_watch(watch); dispatch_callbacks(watch) }");
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try resolveDeferredNativeTestProgram(allocator, try parser.parse())));
    try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "noncopyable value 'watch' was consumed by 'move'"));
}

test "deferred resource provenance follows moves and aggregate fields" {
    try expectDeferredNativeSuccess(
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func()) Watch
        \\native func create_watch() Watch
        \\struct Watches { var subscription:Watch; var ordinary:Watch }
        \\func main() {
        \\    let subscription = start_watch(deferred func() {})
        \\    let moved = move subscription
        \\    let watches = Watches(subscription:move moved, ordinary:create_watch())
        \\    dispatch_callbacks(watches.subscription)
        \\    var replaced = Watches(subscription:create_watch(), ordinary:create_watch())
        \\    replaced.subscription = start_watch(deferred func() {})
        \\    dispatch_callbacks(replaced.subscription)
        \\    var branched = create_watch()
        \\    if true { branched = start_watch(deferred func() {}) }
        \\    else { branched = start_watch(deferred func() {}) }
        \\    dispatch_callbacks(branched)
        \\}
    );
    try expectDeferredNativeSuccess(
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func()) Watch
        \\func main() {
        \\    let watch = subscribe()
        \\    dispatch_callbacks(watch)
        \\}
        \\func subscribe() Watch { return start_watch(deferred func() {}) }
    );
    try expectDeferredNativeSuccess(
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func()) Watch
        \\func subscribe() Watch { return start_watch(deferred func() {}) }
        \\func main() {
        \\    let watch = subscribe()
        \\    dispatch_callbacks(watch)
        \\}
    );
    try expectDeferredNativeError(
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func()) Watch
        \\native func create_watch() Watch
        \\func maybe_subscribe(use_deferred:bool) Watch {
        \\    if use_deferred { return start_watch(deferred func() {}) }
        \\    return create_watch()
        \\}
        \\func main() {
        \\    let watch = maybe_subscribe(true)
        \\    dispatch_callbacks(watch)
        \\}
    ,
        "dispatch_callbacks requires a native resource returned by a deferred registration",
    );
}

test "protocol requirements preserve read reference modes" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Reader { func read(value:@int) int }
        \\struct Counter : Reader {
        \\    func read(value:@int) int { return value + 1 }
        \\}
        \\func main() { let counter = Counter(); let result = counter.read(1) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.protocols[0].requirements[0].parameter_modes[0]);

    try expectResolvedSemanticError(
        "protocol Reader { func read(value:@int) int } struct Counter : Reader { func read(value:int) int { return value } } func main() {}",
        "type 'Counter' does not satisfy method 'read' required by protocol 'Reader'",
    );
}
