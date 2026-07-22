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
test "borrowed returns preserve provenance through functions methods and local aliases" {
    try expectSemanticSuccess(
        \\struct State { var value:int }
        \\struct Owner {
        \\    var state:State
        \\    func inspect() @State { return @self.state }
        \\    func inspect_other(owner:@Owner) @State { return @owner.state }
        \\    func edit() &State { return &self.state }
        \\}
        \\func inspect(owner:@Owner) @State { return @owner.state }
        \\func wrapped(owner:@Owner) @State { return inspect(owner) }
        \\func choose(first:@Owner, second:@Owner) @first:State { return @first.state }
        \\func main() {
        \\    var owner = Owner(state:State(value:1))
        \\    let first = inspect(owner)
        \\    let second:@State = wrapped(owner)
        \\    let other = owner.inspect_other(owner)
        \\    print(first.value + second.value + other.value)
        \\}
    );
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\struct Owner {
        \\    func choose(first:@State, second:@State) @State { return first }
        \\}
        \\func main() {}
    , "borrowed method return provenance is ambiguous; qualify it with 'self' or a borrowed parameter name");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\func choose(first:@State, second:@State) @State { return @first }
        \\func main() {}
    , "borrowed return provenance is ambiguous; qualify it with the parameter name");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\func inspect(owner:@State) @missing:State { return @owner }
        \\func main() {}
    , "borrowed return provenance must name a compatible borrowed parameter");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\func inspect(owner:@State) @State { return owner }
        \\func main() {}
    , "expected 'reference@', found 'State'");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\func edit(owner:@State) &State { return &owner }
        \\func main() {}
    , "borrowed return provenance is ambiguous; qualify it with the parameter name");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\func edit(owner:&State) &State { return &owner }
        \\func main() { var state = State(value:1); var first = edit(state); var second = first }
    , "cannot copy a mutable reference");
    try expectResolvedSemanticError(
        \\struct State { var value:int }
        \\struct Holder { let view:@State }
        \\func main() {}
    , "a struct field cannot have a reference type");
}

test "mutable borrowed returns infer shared let and mutable var aliases" {
    const source =
        \\struct State { var value:int }
        \\struct Owner {
        \\    var state:State
        \\    func access() &State { return &self.state }
        \\}
    ;
    try expectSemanticSuccess(source ++
        \\func observe(owner:&Owner) {
        \\    let first = owner.access()
        \\    let second = owner.access()
        \\    let explicit:@State = owner.access()
        \\    print(first.value + second.value + explicit.value)
        \\}
        \\func edit(owner:&Owner) {
        \\    var value = owner.access()
        \\    value.value = 2
        \\}
        \\func main() {
        \\    var owner = Owner(state:State(value:1))
        \\    observe(owner)
        \\    edit(owner)
        \\}
    );
    try expectResolvedSemanticError(source ++
        \\func main() {
        \\    var owner = Owner(state:State(value:1))
        \\    let value = owner.access()
        \\    value.value = 2
        \\}
    , "cannot assign to immutable variable 'value'");
    try expectResolvedSemanticError(source ++
        \\func main() {
        \\    var owner = Owner(state:State(value:1))
        \\    let value:&State = owner.access()
        \\}
    , "a mutable reference must be declared with 'var'");
    try expectResolvedSemanticError(source ++
        \\func main() {
        \\    var owner = Owner(state:State(value:1))
        \\    var mutable = owner.access()
        \\    let shared:@State = mutable
        \\}
    , "expected 'reference@', found 'reference&'");
}

test "noncopyable containers require explicit whole-value transfer" {
    const declaration =
        \\struct Resource { let handle:int; drop {} }
        \\struct Holder { var resource:Resource }
        \\enum Slot { full(Holder); empty }
        \\func consume(value:Resource) {}
    ;

    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Holder(resource:Resource(handle:1)); let second = first }",
        "cannot copy noncopyable value 'Holder'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let slot = Slot.full(Holder(resource:Resource(handle:1))); match slot { full(value) => {}; empty => {} } }",
        "a named noncopyable enum must be matched with 'match move' or 'match @value'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let pending:Resource? = Resource(handle:1); if value = pending {} }",
        "a named noncopyable optional must be extracted with 'move' or '@'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let holder = Holder(resource:Resource(handle:1)); consume(move holder.resource) }",
        "'move' requires a complete local binding or parameter",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; let copy = values[0] }",
        "cannot copy noncopyable value 'Resource'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; let copy = values[0:1] }",
        "cannot copy noncopyable value 'list'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; for let value in values {} }",
        "'for let' would copy a noncopyable element; use the read loop or 'for var'",
    );
    try expectResolvedSemanticError(
        "protocol Stored {} struct Resource { let handle:int; drop {} } struct Holder : Stored { var resource:Resource } func erase(value:Stored) {} func main() { let holder = Holder(resource:Resource(handle:1)); erase(move holder) }",
        "noncopyable value 'Holder' cannot be converted to dynamic protocol value 'Stored'",
    );
}

test "mutable contiguous views can swap noncopyable elements" {
    try expectSemanticSuccess(
        \\struct Resource { let handle:int; drop {} }
        \\func exchange(values:&Resource[..]) { values.swap(0, 1) }
        \\func main() {
        \\    var values:Resource[] = [Resource(handle:1), Resource(handle:2)]
        \\    var view = &values[0:2]
        \\    exchange(view)
        \\}
    );
    try expectResolvedSemanticError(
        "func exchange(values:@int[..]) { values.swap(0, 1) } func main() {}",
        "cannot call mutating method 'swap' on immutable value 'values'",
    );
}

test "unique resources transfer explicitly through locals parameters assignments and returns" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\func consume(resource:Resource) {}
        \\func forward(resource:Resource) Resource { return move resource }
        \\func main() {
        \\    let first = Resource.open(1)
        \\    let second = move first
        \\    consume(move second)
        \\    consume(Resource.open(2))
        \\    let third = forward(Resource.open(3))
        \\    var reusable = move third
        \\    reusable = Resource.open(4)
        \\    consume(move reusable)
        \\    reusable = Resource.open(5)
        \\    consume(move reusable)
        \\}
    );
}

test "unique resource availability follows branches matches and loop exits" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\enum Choice { first; second }
        \\func consume(resource:Resource) {}
        \\func branch(flag:bool) {
        \\    let resource = Resource.open(1)
        \\    if flag { consume(move resource); return }
        \\    consume(move resource)
        \\}
        \\func main() {
        \\    var resource = Resource.open(2)
        \\    if true { consume(move resource); resource = Resource.open(3) }
        \\    else { consume(move resource); resource = Resource.open(4) }
        \\    match Choice.first() {
        \\        first => { consume(move resource); resource = Resource.open(5) }
        \\        second => { consume(move resource); resource = Resource.open(6) }
        \\    }
        \\    var count = 0
        \\    while count < 1 {
        \\        consume(move resource)
        \\        resource = Resource.open(7)
        \\        count += 1
        \\    }
        \\    for index in 0...1 {
        \\        consume(move resource)
        \\        resource = Resource.open(index)
        \\    }
        \\    consume(move resource)
        \\}
    );
}

test "unique resource moves reject invalid sources and consumed uses" {
    const declaration =
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\func consume(resource:Resource) {}
    ;

    try expectResolvedSemanticError(
        declaration ++ "func main() { let value = 1; let invalid = move value }",
        "'move' requires a noncopyable value, found 'int'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let invalid = move resource.handle }",
        "'move' requires a complete local binding or parameter",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); consume(resource) }",
        "noncopyable value 'Resource' must be passed with 'move'",
    );
    try expectResolvedSemanticErrorContains(
        declaration ++ "func main() { let resource = Resource.open(1); consume(move resource); print(resource.handle) }",
        "noncopyable value 'resource' was consumed by 'move' at",
    );
    try expectResolvedSemanticErrorContains(
        declaration ++ "func main() { let resource = Resource.open(1); consume(move resource); consume(move resource) }",
        "noncopyable value 'resource' was consumed by 'move' at",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let other = move resource; resource = move other }",
        "cannot assign to immutable variable 'resource'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { var resource = Resource.open(1); resource = move resource }",
        "cannot move unique resource 'resource' into itself",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { var resource = Resource.open(1); while true { consume(move resource) } }",
        "unique resource 'resource' must have the same availability on every path returning to the loop header",
    );
}

test "unique resource drop has the ordinary drop restrictions" {
    try expectResolvedSemanticError(
        "struct Resource { drop { return } } func main() {}",
        "'drop' cannot return",
    );
}

test "class inheritance constructs one base and converts references upward" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Entity {
        \\    var id:int
        \\    protected var position:int
        \\    protected init(id:int, position:int) { self.id = id; self.position = position }
        \\    public func advance(delta:int) { self.position += delta }
        \\}
        \\class Player : Entity {
        \\    var name:str
        \\    public init(id:int, name:str, position:int) : super(id, position) { self.name = name }
        \\    public func copy_position(other:Entity) { self.position = other.position }
        \\}
        \\func update(entity:Entity) { entity.advance(1) }
        \\func main() {
        \\    var player = Player(1, "Ada", 2)
        \\    var entity:Entity = player
        \\    var optional:Entity? = player
        \\    var entities:Entity[] = [player]
        \\    update(player)
        \\    assert(entity == player, "upcast keeps identity")
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqualStrings(program.structures[0].generated_name, program.structures[1].base.?.generated_name);
    try std.testing.expect(program.structures[1].constructors[0].base_initializer != null);
    try std.testing.expect(program.functions[1].statements[1].variable_declaration.initializer.value == .conversion);

    try expectResolvedSemanticError(
        "class Base { var value:int; protected init() {} } class Child : Base { var value:int; public init() : super() {} } func main() {}",
        "field 'value' in class 'Child' collides with an inherited field",
    );
    try expectResolvedSemanticError(
        "class Base { func hidden() {} } class Child : Base { public init() {} public func reveal() { self.hidden() } } func main() {}",
        "method 'hidden' is private in class 'Base'",
    );
    try expectResolvedSemanticError(
        "class Base { var hidden:int } class Child : Base { public init() {} public func reveal() int { return self.hidden } } func main() {}",
        "field 'hidden' is private in class 'Base'",
    );
    try expectResolvedSemanticError(
        "class Base { init() {} } class Child : Base { public init() : super() {} } func main() {}",
        "constructor of base class 'Base' is private",
    );
    try expectResolvedSemanticError(
        "class First : Second {} class Second : First {} func main() {}",
        "inheritance cycle involving class 'First'",
    );
    try expectResolvedSemanticError(
        "class Base { public func act() {} } class Child : Base { public func act() {} } func main() {}",
        "method 'act' matches an inherited signature; declare it with 'override'",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base {} func main() { var children:Child[] = []; var bases:Base[] = children }",
        "expected 'Base[]', found 'Child[]'",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base {} func main() { var base = Base(); var child:Child = base }",
        "expected 'Child', found 'Base'",
    );
    try expectResolvedSemanticError(
        "struct Value {} class Child : Value {} func main() {}",
        "base type 'Value' is not a class",
    );
    try expectResolvedSemanticError(
        "class Dependency {} class Base { var dependency:Dependency } class Child : Base { public init() {} } func main() {}",
        "base class 'Base' cannot be constructed with 'super()'",
    );
    try expectResolvedSemanticError(
        "class Root { public init() : super() {} } func main() {}",
        "constructor 'super' call requires a base class",
    );
}

test "class overrides share a dynamic slot and super selects the base implementation" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Child : Base {
        \\    override public func value(input:int) int { return super.value(input) + 1 }
        \\}
        \\class Base { public func value(input:int) int { return input } }
        \\func main() {}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqualStrings(program.structures[1].methods[0].generated_name, program.structures[0].methods[0].generated_name);
    try std.testing.expect(program.structures[0].methods[0].is_override);
    const returned = program.structures[0].methods[0].statements[0].return_statement.?;
    try std.testing.expect(returned.value.binary.left.value == .super_method_call);

    try expectResolvedSemanticError(
        "class Base { public func act() {} } class Child : Base { override public func other() {} } func main() {}",
        "override method 'other' has no compatible inherited method",
    );
    try expectResolvedSemanticError(
        "class Base { public func value() int { return 1 } } class Child : Base { override public func value() str { return \"x\" } } func main() {}",
        "override method 'value' must return 'int'",
    );
    try expectResolvedSemanticError(
        "class Base { public func act() {} } class Child : Base { override protected func act() {} } func main() {}",
        "override method 'act' cannot reduce inherited visibility",
    );
    try expectResolvedSemanticError(
        "class Base { func hidden() {} } class Child : Base { override public func hidden() {} } func main() {}",
        "private method 'hidden' cannot be overridden",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base { public func act() { super.missing() } } func main() {}",
        "base class has no method 'missing'",
    );
    try expectResolvedSemanticError(
        "class Base { public func classify(value:int) {} } class Child : Base { public func classify(value:str) {} } func main() { var value:Base = Child(); value.classify(\"child\") }",
        "no compatible signature for method 'classify'; visible signatures: classify(int)",
    );
}

test "let rejects non-independent conditional and iteration bindings" {
    try expectSemanticError(
        "func main() { var callback:(func())? = func() {}; if let selected = callback {} }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectSemanticError(
        "func main() { var callbacks:func()[] = [func() {}]; for (let callback in callbacks) {} }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
}

test "let accepts non-independent elements only through a local collection shell" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { public var value:int; public func show() {} }
        \\func main() {
        \\    let players:Player[] = [Player()]
        \\    players[0].show()
        \\    players[0].value = 1
        \\    for player in players { player.show() }
        \\    let fixed:Player[1] = [Player()]
        \\    for (player in fixed) { player.show() }
        \\    let callbacks:func()[] = [func() {}]
        \\    for callback in callbacks { callback() }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    _ = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
}

test "read iteration and let collection shells reject storage mutation" {
    try expectResolvedSemanticError(
        "class Player {} func main() { let players:Player[] = [Player()]; players[0] = Player() }",
        "cannot assign to immutable variable 'players'",
    );
    try expectResolvedSemanticError(
        "class Player {} func main() { let players:Player[] = [Player()]; for player in players { player = Player() } }",
        "cannot assign to immutable control binding 'player'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } func main() { let counters:Counter[] = [Counter(value:0)]; for counter in counters { counter.bump() } }",
        "cannot mutate immutable control binding 'counter'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "class Player {} struct Team { var player:Player } func main() { let teams:Team[] = [Team(player:Player())]; teams[0].player = Player() }",
        "cannot assign to immutable variable 'teams'",
    );
}

test "reject assignment to immutable variable" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; count = 6; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "cannot assign to immutable variable 'count'",
        analyzer.diagnostic.?.message,
    );
}

test "reject duplicate variable in same scope" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; let count = 6; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "variable 'count' is already declared in this scope",
        analyzer.diagnostic.?.message,
    );
}

test "block variables do not escape their scope" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { if (true) { let inside = 5; } print(inside); }",
    );
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("unknown variable 'inside'", analyzer.diagnostic.?.message);
}

test "reject lexical shadowing from enclosing scopes" {
    try expectSemanticError(
        "func read(value:int) int { if (true) { let value = 1; } return value; } func main() void {}",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let value = 1; if (true) { let value = value + 1; } }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { var count = 1; while (true) { var count = 2; } }",
        "variable 'count' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; for (let value in values) { if (true) { let value = 2; } } }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; let value = 0; for (let value in values) {} }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; for (let value in values) { for (let value in values) {} } }",
        "variable 'value' is already declared in an enclosing scope",
    );
}

test "separate scopes may reuse a local name" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    let values = [1]
        \\    if (true) { let value = 1 } else { let value = 2 }
        \\    for (let value in values) {}
        \\    for (let value in values) {}
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(usize, 4), program.functions[0].statements.len);
}

test "local variable may share a structure field name" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Counter {
        \\    var value:int
        \\    func combined() int {
        \\        let value = 1
        \\        return self.value + value
        \\    }
        \\}
        \\func main() void {}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(usize, 2), program.structures[0].methods[0].statements.len);
}

test "analyze compact and named integer ranges" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    for (let i in 0...3) {}
        \\    for (var i in range(3, 0)) { i += 100 }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const compact = program.functions[0].statements[0].for_statement;
    try std.testing.expectEqual(Ast.IterationBinding.immutable, compact.binding);
    try std.testing.expectEqual(Type.int, compact.source.integer_range.start.type);
    const named = program.functions[0].statements[1].for_statement;
    try std.testing.expectEqual(Ast.IterationBinding.mutable, named.binding);
    try std.testing.expectEqual(Type.int, named.source.integer_range.end.type);
}

test "analyze negative collection indexes and slices" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() {
        \\    let values:int[3] = [10, 20, 30]
        \\    let last = values[-1]
        \\    let middle = values[1:-1]
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const last = program.functions[0].statements[1].variable_declaration.initializer;
    try std.testing.expectEqual(Type.int, last.type);
    try std.testing.expect(last.value == .index_access);
    const middle = program.functions[0].statements[2].variable_declaration.initializer;
    try std.testing.expect(middle.type == .list);
    try std.testing.expectEqual(Type.int, middle.type.list.*);
    try std.testing.expect(middle.value == .slice_access);
}

test "reject non-int range bounds" {
    try expectSemanticError(
        "func main() void { for (let i in 0.0...3) {} }",
        "expected 'int', found 'float'",
    );
    try expectSemanticError(
        "func main() void { for (let i in range(0, true)) {} }",
        "expected 'int', found 'bool'",
    );
}

test "reject incompatible type annotation" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count:bool = 5; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "resolve explicit numeric conversion" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let source:int = 12; let target:uint8 = source as uint8; }");
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const initializer = program.functions[0].statements[1].variable_declaration.initializer;
    try std.testing.expectEqual(Type.uint8, initializer.type);
    try std.testing.expectEqual(Type.uint8, initializer.value.conversion.target_type);
}

test "resolve numeric bases separators and exponents" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let binary = 0b1010_0101; let hexadecimal = 0xCA_FE; let exponent = 1.25e+2; }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(u64, 165), program.functions[0].statements[0].variable_declaration.initializer.value.integer);
    try std.testing.expectEqual(@as(u64, 51966), program.functions[0].statements[1].variable_declaration.initializer.value.integer);
    try std.testing.expectEqualStrings("1.25e+2", program.functions[0].statements[2].variable_declaration.initializer.value.floating);
}

test "resolve string escapes concatenation and length" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { var value = \"A\\u{00E9}\\0\"; value += \"!\"; let count = value.count(); }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const value = program.functions[0].statements[0].variable_declaration.initializer;
    try std.testing.expectEqual(Type.str, value.type);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0xC3, 0xA9, 0 }, value.value.string);
    try std.testing.expectEqual(Type.str, program.functions[0].statements[1].assignment.value.?.type);
    try std.testing.expectEqual(Type.int, program.functions[0].statements[2].variable_declaration.initializer.type);
}
