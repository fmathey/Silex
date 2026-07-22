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
test "analyze enum construction and exhaustive match" {
    try expectSemanticSuccess(
        \\enum Verdict { idle; value(int); failed(str) }
        \\func text(result:Verdict) str {
        \\    return match result { idle => "idle"; value(number) => "value"; failed(message) => message }
        \\}
        \\func main() { let result = Verdict.value(7); print(text(result)) }
    );
}

test "analyze expression and imperative matches with else" {
    try expectSemanticSuccess(
        \\enum State { idle; ready; failed(str) }
        \\func main() {
        \\    let state = State.ready()
        \\    let text = match state { idle => "idle"; else => "other" }
        \\    match state { failed(message) => { print(message) }; else => { print(text) } }
        \\    let any = match state { else => true }
        \\    print(any)
        \\}
    );
}

test "reject incomplete duplicate and ill-typed enum matches" {
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {} } }
    , "match on enum 'State' is not exhaustive; missing variant 'ready'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; idle => {}; ready => {} } }
    , "variant 'idle' is matched more than once");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 1; ready => "ready" } }
    , "match branches must have the same type; expected 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 1; else => "ready" } }
    , "match branches must have the same type; expected 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; ready => {}; else => {} } }
    , "else match branch does not cover any remaining variant");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; unknown => {}; ready => {} } }
    , "enum 'State' has no variant 'unknown'");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.integer(); }
    , "variant 'Value.integer' expects 1 associated values, found 0");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.integer("wrong"); }
    , "associated value 1 of variant 'Value.integer' expects 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.empty; }
    , "an enum variant must be constructed with parentheses");
    try expectResolvedSemanticError(
        \\class Owner {}
        \\enum Value { empty; owner(Owner) }
        \\func main() { let value = Value.empty(); }
    , "type 'Value' is not an independent value because field 'owner[1]' reaches 'Owner'; use 'var'");
}

test "analyze raw enum values and intrinsic property" {
    try expectSemanticSuccess(
        \\enum Direction:int { north = 1; south = 2; unknown = -1 }
        \\enum Name:str { north = "north"; south = "south" }
        \\func main() {
        \\    let direction = Direction.north()
        \\    let code:int = direction.raw_value
        \\    let name:str = Name.south().raw_value
        \\    print(code)
        \\    print(name)
        \\}
    );
}

test "reject invalid raw enum values and property mutation" {
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1; south = 1 }
        \\func main() {}
    , "raw enum value is already used by variant 'north'");
    try expectResolvedSemanticError(
        \\enum Name:str { first = "same"; second = "s\u{61}me" }
        \\func main() {}
    , "raw enum value is already used by variant 'first'");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = "north" }
        \\func main() {}
    , "raw enum value must be a 'int' literal");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 + 1 }
        \\func main() {}
    , "raw enum value must be a 'int' literal");
    try expectResolvedSemanticError(
        \\enum State { ready }
        \\func main() { let state = State.ready(); print(state.raw_value) }
    , "enum 'State' has no raw value");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 }
        \\func main() { var direction = Direction.north(); direction.raw_value = 2 }
    , "enum property 'raw_value' is read-only");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 }
        \\func replace(value:&int) { value = 2 }
        \\func main() { var direction = Direction.north(); replace(direction.raw_value) }
    , "enum property 'raw_value' cannot be passed to a mutable reference parameter");
}

test "field mutability controls direct and nested mutation" {
    try expectSemanticSuccess(
        \\struct Counter { var value:int; func bump() { self.value += 1 } }
        \\struct State { let id:int; var counter:Counter }
        \\func main() { var state = State(id:1, counter:Counter(value:0)); state.counter.bump() }
    );
    try expectResolvedSemanticError(
        "struct State { let id:int } func main() { var state = State(id:1); state.id = 2 }",
        "cannot mutate let field 'id'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int } struct State { let counter:Counter } func main() { var state = State(counter:Counter(value:0)); state.counter.value = 1 }",
        "cannot mutate let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } struct State { let counter:Counter } func main() { var state = State(counter:Counter(value:0)); state.counter.bump() }",
        "cannot call mutating method 'bump' through let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct State { let values:int[] } func main() { var state = State(values:[]); state.values.append(1) }",
        "cannot mutate through let field 'values'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } struct State { let counter:Counter? } func main() { var state = State(counter:Counter(value:0)); state.counter?.bump() }",
        "cannot call mutating method 'bump' through let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct State { let values:int[]? } func main() { var state = State(values:[]); state.values?.append(1) }",
        "cannot mutate through let field 'values'",
    );
}

test "static methods use type receivers and separate overload sets" {
    try expectSemanticSuccess(
        \\struct Position {
        \\    var x:int
        \\    static func origin() Position { return Position(x:0) }
        \\    static func from(value:int) Position { return Position(x:value) }
        \\    func from() int { return self.x }
        \\}
        \\func main() { let origin = Position.origin(); let value = Position.from(3); assert(origin.x + value.from() == 3, "static methods") }
    );
    try expectResolvedSemanticError(
        "struct Factory { static func create() Factory { return Factory() } } func main() { var factory = Factory(); factory.create() }",
        "static method 'create' must be called through type 'Factory'",
    );
    try expectResolvedSemanticError(
        "struct Factory { func create() Factory { return Factory() } } func main() { let factory = Factory.create() }",
        "instance method 'create' requires a value of type 'Factory'",
    );
}

test "static methods have no self or super and are not inherited" {
    try expectResolvedSemanticError(
        "struct Factory { static func create() Factory { return self } } func main() {}",
        "'self' is not available inside a static method",
    );
    try expectResolvedSemanticError(
        "class Base { public static func create() Base { return Base() } } class Child : Base {} func main() { let child = Child.create() }",
        "type 'Child' has no static method 'create'",
    );
    try expectResolvedSemanticError(
        "class Base { public func value() int { return 1 } } class Child : Base { public static func value() int { return super.value() } } func main() {}",
        "'super' is not available inside a static method",
    );
}

test "let class fields initialize exactly once in their declaring constructor" {
    try expectSemanticSuccess(
        \\class User {
        \\    let id:int
        \\    public var name:str
        \\    public init(id:int, name:str) { self.id = id; self.name = name }
        \\}
        \\func main() { var user = User(1, "Ada"); user.name = "Grace" }
    );
    try expectSemanticError(
        "class User { let id:int; public init(id:int) { self.id = id; self.id = id } } func main() {}",
        "field 'id' is initialized more than once",
    );
    try expectSemanticError(
        "class User { let id:int; public init(assign:bool) { if assign { self.id = 1 } } } func main() {}",
        "constructor of class 'User' leaves field 'id' without a value",
    );
    try expectSemanticError(
        "class User { let id:int; public init(assign:bool) { if assign { self.id = 1 } self.id = 2 } } func main() {}",
        "field 'id' may be initialized more than once",
    );
    try expectSemanticError(
        "class User { let id:int = 1; public init() { self.id = 2 } } func main() {}",
        "cannot mutate let field 'id'",
    );
    try expectSemanticError(
        "class Base { protected let id:int; protected init(id:int) { self.id = id } } class Child : Base { public init() : super(1) { self.id = 2 } } func main() {}",
        "cannot mutate let field 'id'",
    );
}

test "let fields require recursively independent types" {
    try expectSemanticError(
        "class Player {} struct Team { let player:Player } func main() {}",
        "type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectSemanticError(
        "struct Handler { let callback:func() } func main() {}",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
}
