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
test "validate protocol conformances and inherited public requirements" {
    try expectSemanticSuccess(
        \\protocol Describable { func describe() str }
        \\protocol Drawable { func draw() }
        \\struct User : Describable { func describe() str { return "user" } }
        \\class Entity { public func describe() str { return "entity" } }
        \\class Player : Entity, Describable, Drawable { public func draw() {} }
        \\class Child : Player {}
        \\func main() {}
    );
}

test "reject missing private static and incompatible protocol requirements" {
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Player : Drawable { func draw() {} }
        \\func main() {}
    , "method 'draw' must be public to satisfy protocol 'Drawable' for type 'Player'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Icon : Drawable { static func draw() {} }
        \\func main() {}
    , "type 'Icon' does not satisfy method 'draw' required by protocol 'Drawable'");
    try expectResolvedSemanticError(
        \\protocol Describable { func describe() str }
        \\struct User : Describable { func describe() int { return 1 } }
        \\func main() {}
    , "type 'User' does not satisfy method 'describe' required by protocol 'Describable'");
}

test "analyze dynamic protocol values and reject values outside their contract" {
    try expectSemanticSuccess(
        \\protocol Drawable { func draw() str }
        \\struct Icon : Drawable { var name:str; func draw() str { return self.name } }
        \\class Player : Drawable { public func draw() str { return "player" } }
        \\func render(value:Drawable) str { return value.draw() }
        \\func make() Drawable { return Icon(name:"icon") }
        \\func main() {
        \\    var drawable:Drawable = Icon(name:"first")
        \\    drawable = Player()
        \\    var values:Drawable[] = [Icon(name:"list"), Player()]
        \\    assert(render(values[0]) == "list", "protocol parameter")
        \\    var result = make()
        \\    assert(result.draw() == "icon", "protocol return")
        \\}
    );
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Rock {}
        \\func main() { var drawable:Drawable = Rock() }
    , "expected 'Drawable', found 'Rock'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Icon : Drawable { func draw() {} }
        \\func main() { var drawable:Drawable = Icon(); drawable.save() }
    , "protocol 'Drawable' has no method 'save'");
}

test "analyze local type extensions with mutation and static methods" {
    try expectSemanticSuccess(
        \\struct Counter { var value:int }
        \\extend Counter {
        \\    func increment() int { self.value += 1; return self.value }
        \\    public static func zero() Counter { return Counter(value:0) }
        \\}
        \\func main() {
        \\    var counter = Counter.zero()
        \\    assert(counter.increment() == 1, "extension mutation")
        \\}
    );
}

test "extensions use only public members and do not participate in inheritance" {
    try expectResolvedSemanticError(
        \\class Vault { var secret:int; public init() { self.secret = 1 } }
        \\extend Vault { public func reveal() int { return self.secret } }
        \\func main() {}
    , "field 'secret' is private in class 'Vault'");
    try expectResolvedSemanticError(
        \\class Entity { protected func hidden() {} }
        \\extend Entity { public func expose() { self.hidden() } }
        \\func main() {}
    , "method 'hidden' is accessible only from class 'Entity' and its descendants");
    try expectResolvedSemanticError(
        \\class Entity {}
        \\extend Entity { public func ping() {} }
        \\class Player : Entity {}
        \\func main() { var player = Player(); player.ping() }
    , "class 'Player' has no method 'ping'");
    try expectResolvedSemanticError(
        \\struct Value { func read() int { return 1 } }
        \\extend Value { public func read() int { return 2 } }
        \\func main() {}
    , "extension method 'read' conflicts with an existing callable shape on type 'Value'");
}

test "extension conformances support dynamic values and multiple protocols" {
    try expectSemanticSuccess(
        \\protocol Drawable { func draw() int }
        \\protocol Named { func name() str }
        \\struct Sprite { var value:int }
        \\struct Existing { func draw() int { return 7 } }
        \\class Button {}
        \\extend Sprite : Drawable, Named {
        \\    func draw() int { return self.value }
        \\    func name() str { return "sprite" }
        \\}
        \\extend Existing : Drawable {}
        \\extend Button : Drawable { public func draw() int { return 9 } }
        \\func main() {
        \\    var sprite = Sprite(value:42)
        \\    var drawable:Drawable = sprite
        \\    var named:Named = sprite
        \\    assert(drawable.draw() == 42, "dynamic extension conformance")
        \\    assert(named.name() == "sprite", "second extension conformance")
        \\    var existing:Drawable = Existing()
        \\    assert(existing.draw() == 7, "existing method conformance")
        \\    var button:Drawable = Button()
        \\    assert(button.draw() == 9, "public class extension conformance")
        \\}
    );
}

test "extension conformances use target visibility defaults and apply to the exact type" {
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Sprite {}
        \\extend Sprite : Drawable { func draw() {} }
        \\func main() {}
    , "method 'draw' must be public to satisfy protocol 'Drawable' for type 'Sprite'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Sprite {}
        \\extend Sprite : Drawable {}
        \\func main() {}
    , "type 'Sprite' does not satisfy method 'draw' required by protocol 'Drawable'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Entity {}
        \\extend Entity : Drawable { public func draw() {} }
        \\class Player : Entity {}
        \\func main() { var drawable:Drawable = Player() }
    , "expected 'Drawable', found 'Player'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Sprite : Drawable { func draw() {} }
        \\extend Sprite : Drawable {}
        \\func main() {}
    , "extension conformance of type 'Sprite' to protocol 'Drawable' from module 'Test' conflicts with the conformance declared by the type");
}

test "native ABI accepts optional transferable returns" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Message { let code:int; let text:str }
        \\native func native_integer() int?
        \\native func native_text() str?
        \\native func native_message() Message?
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_integer";
    @constCast(program.functions)[1].name = "Native.native_text";
    @constCast(program.functions)[2].name = "Native.native_message";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(program);
}

test "public native functions use ordinary API names" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "public native func pow(value:int) int\nfunc main() {}\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.pow";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    const analyzed = try analyzer.analyze(program);
    try std.testing.expect(analyzed.functions[0].is_native);
    try std.testing.expectEqualStrings("pow", analyzed.functions[0].native_function_name.?);
    try std.testing.expectEqualStrings("silexNative_Math_pow", analyzed.functions[0].generated_name);
}

test "private native functions use ordinary names" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func pow(value:int) int\nfunc main() {}\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.pow";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    const analyzed = try analyzer.analyze(program);
    try std.testing.expect(analyzed.functions[0].is_native);
    try std.testing.expectEqualStrings("pow", analyzed.functions[0].native_function_name.?);
    try std.testing.expectEqualStrings("silexNative_Math_pow", analyzed.functions[0].generated_name);
}

test "native ABI rejects optional non-transferable returns" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_lookup() int[]?\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.native_lookup";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings("native functions cannot return 'int[]?'", analyzer.diagnostic.?.message);
}

test "native ABI accepts string returns" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_read_text() str\nfunc main() {}\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Console.native_read_text";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Console"};
    _ = try analyzer.analyze(program);
}

test "native ABI accepts scalar and string structure returns" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeScalars {
        \\    let integer:int
        \\    let signed8:int8
        \\    let signed16:int16
        \\    let signed32:int32
        \\    let unsigned8:uint8
        \\    let unsigned16:uint16
        \\    let unsigned32:uint32
        \\    let unsigned64:uint64
        \\    let decimal32:float
        \\    let decimal64:float64
        \\    let ready:bool
        \\    let label:str
        \\}
        \\native func native_read() NativeScalars
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_read";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(program);
}

test "native ABI accepts transferable Result returns" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeFile { let handle:int }
        \\native func native_open(path:str) Result<NativeFile,str>
        \\native func native_save() Result<void,str>
        \\native func native_optional() Result<int?,str>
        \\func main() {}
    );
    const program = try parser.parse();
    for (@constCast(program.functions)[0..3]) |*function| {
        function.name = try std.fmt.allocPrint(allocator, "Native.{s}", .{function.name});
    }
    var specializer = Generics.Specializer.init(allocator, program);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(try specializer.specialize());
}

test "native ABI accepts owned uint8 list returns" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_compress(bytes:uint8[]) uint8[]
        \\native func native_read(path:str) Result<uint8[],str>
        \\func main() {}
    );
    const program = try parser.parse();
    for (@constCast(program.functions)[0..2]) |*function| {
        function.name = try std.fmt.allocPrint(allocator, "Native.{s}", .{function.name});
    }
    var specializer = Generics.Specializer.init(allocator, program);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(try specializer.specialize());
}

test "native ABI rejects non transferable Result returns and Result parameters" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    const result_return_cases = [_][]const u8{
        "class Value {} native func native_read() Result<Value,str>; func main() {}",
        "native func native_read() Result<int[],str>; func main() {}",
        "native func native_read() Result<uint8[4],str>; func main() {}",
        "native func native_read() Result<uint8[]?,str>; func main() {}",
        "native func native_read() Result<int,func()>; func main() {}",
        "native func native_read() Result<Result<int,str>,str>; func main() {}",
    };
    for (result_return_cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var parser = Parser.init(allocator, source);
        const program = try parser.parse();
        @constCast(program.functions)[0].name = "Native.native_read";
        var specializer = Generics.Specializer.init(allocator, program);
        var analyzer = Analyzer.init(allocator);
        analyzer.native_module_names = &.{"Native"};
        try std.testing.expectError(error.InvalidSource, analyzer.analyze(try specializer.specialize()));
        try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "native functions cannot return 'Result<"));
    }

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_accept(value:Result<int,str>) bool; func main() {}");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_accept";
    var specializer = Generics.Specializer.init(allocator, program);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try specializer.specialize()));
    try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "native parameter 'value' cannot use 'Result<"));
}

test "native ABI rejects non scalar structure returns" {
    const cases = [_][]const u8{
        "struct Inner { let value:int } struct Payload { let value:Inner } native func native_read() Payload; func main() {}",
        "enum State { ready } struct Payload { let value:State } native func native_read() Payload; func main() {}",
        "class Payload {} native func native_read() Payload; func main() {}",
        "protocol Value {} struct Payload { var value:Value } native func native_read() Payload; func main() {}",
        "struct Payload { var value:int[] } native func native_read() Payload; func main() {}",
        "struct Payload { var value:int? } native func native_read() Payload; func main() {}",
        "struct Payload { var value:Result<int,str> } native func native_read() Payload; func main() {}",
        "struct Payload { var value:func() } native func native_read() Payload; func main() {}",
        "struct Payload { drop {} } native func native_read() Payload; func main() {}",
        "struct Payload<T> { let value:T } native func native_read() Payload<int>; func main() {}",
    };
    for (cases) |source| try expectNativeStructureReturnRejected(source);
}

test "native ABI accepts scalar and string structure parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeScalars {
        \\    let integer:int
        \\    let signed8:int8
        \\    let signed16:int16
        \\    let signed32:int32
        \\    let unsigned8:uint8
        \\    let unsigned16:uint16
        \\    let unsigned32:uint32
        \\    let unsigned64:uint64
        \\    let decimal32:float
        \\    let decimal64:float64
        \\    let ready:bool
        \\    let first:str
        \\    let second:str
        \\}
        \\struct NativeBounds { let width:int; let height:int }
        \\native func native_accept(values:NativeScalars, first:NativeBounds, second:NativeBounds) bool
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_accept";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(program);
}

test "native ABI accepts borrowed uint8 collection parameters" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_checksum(bytes:uint8[]) uint64
        \\native func native_write_block(bytes:uint8[512]) Result<void,str>
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_checksum";
    @constCast(program.functions)[1].name = "Native.native_write_block";
    var specializer = Generics.Specializer.init(allocator, program);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    _ = try analyzer.analyze(try specializer.specialize());
}

test "native ABI rejects unsupported collection parameters" {
    const cases = [_][]const u8{
        "native func native_read(bytes:int[]) int; func main() {}",
        "native func native_read(bytes:str[]) int; func main() {}",
        "native func native_read(bytes:uint8[][]) int; func main() {}",
        "native func native_read(bytes:int[4]) int; func main() {}",
        "native func native_read(bytes:uint8[4][]) int; func main() {}",
        "native func native_read(bytes:&uint8[]) int; func main() {}",
    };
    for (cases) |source| try expectNativeByteViewParameterRejected(source);
}

test "native ABI rejects non scalar structure parameters" {
    const cases = [_][]const u8{
        "struct Inner { let value:int } struct Payload { let value:Inner } native func native_accept(value:Payload) bool; func main() {}",
        "enum State { ready } struct Payload { let value:State } native func native_accept(value:Payload) bool; func main() {}",
        "class Payload {} native func native_accept(value:Payload) bool; func main() {}",
        "protocol Value {} struct Payload { var value:Value } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload { var value:int[] } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload { var value:int? } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload { var value:Result<int,str> } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload { var value:func() } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload { drop {} } native func native_accept(value:Payload) bool; func main() {}",
        "struct Payload<T> { let value:T } native func native_accept(value:Payload<int>) bool; func main() {}",
    };
    for (cases) |source| try expectNativeStructureParameterRejected(source);
}

test "native ABI rejects optional parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_lookup(value:int?) int\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.native_lookup";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings("native parameter 'value' cannot use 'int?'", analyzer.diagnostic.?.message);
}

test "infer variables and resolve nested scope" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; if (true) { print(count); } }");
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(Type.int, program.functions[0].statements[0].variable_declaration.type);
    try std.testing.expectEqual(
        Type.int,
        program.functions[0].statements[1].if_statement.body[0].print.type,
    );
}

test "let accepts recursively independent values" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int; var y:int }
        \\struct Snapshot { var positions:Position[]; var selected:Position? }
        \\func main() {
        \\    let origin = Position()
        \\    let snapshot = Snapshot(positions:[origin], selected:origin)
        \\    print(snapshot.positions[0].x)
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));

    try std.testing.expectEqual(@as(usize, 3), program.functions[0].statements.len);
}

test "let rejects function values directly and through fields" {
    try expectSemanticError(
        "func main() { let callback = func() {}; }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectResolvedSemanticError(
        \\struct Handler { var callback:func() }
        \\func main() { let handler = Handler(callback:func() {}); }
    ,
        "type 'Handler' is not an independent value because field 'callback' reaches 'func'; use 'var'",
    );
    try expectResolvedSemanticError(
        \\struct Handler { var callbacks:func()[] }
        \\struct Screen { var handler:Handler? }
        \\func main() { let screen = Screen(handler:null); }
    ,
        "type 'Screen' is not an independent value because field 'handler.callbacks' reaches 'func'; use 'var'",
    );
}

test "classes have shared-reference types and are never independent let values" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { public var health:int = 100 }
        \\func main() { var player = Player(); var alias = player; alias.health -= 1 }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expect(program.structures[0].is_class);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.type.structure.is_class);

    try expectResolvedSemanticError(
        "class Player {} func main() { let player = Player() }",
        "type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectResolvedSemanticError(
        "class Player {} func replace(player:&Player) {} func main() {}",
        "class 'Player' already has reference semantics; '&Player' is invalid",
    );
    try expectResolvedSemanticError(
        "class Player {} class Enemy {} func main() { var player = Player(); var enemy = Enemy(); let equal = player == enemy }",
        "equality operator requires operands of the same type, found 'Player' and 'Enemy'",
    );
    try expectResolvedSemanticError(
        "class Player {} func main() { if var player = Player() {} }",
        "conditional binding source must have an optional type",
    );
    try expectResolvedSemanticError(
        "class Player {} func invalid() func() { var player = Player(); return func() { print(player == player) } } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "class members are private by default and public exposes them" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Vault {
        \\    var value:int = 40
        \\    protected var offset:int = 2
        \\    func total() int { return self.value + self.offset }
        \\    public func read() int { return self.total() }
        \\    public func copy_from(other:Vault) { self.value = other.value }
        \\}
        \\func main() { var first = Vault(); var second = Vault(); second.copy_from(first); print(second.read()) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].fields[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].methods[1].visibility);

    try expectResolvedSemanticError(
        "class Vault { var value:int = 1 } func main() { var vault = Vault(); print(vault.value) }",
        "field 'value' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { func reset() {} } func main() { var vault = Vault(); vault.reset() }",
        "method 'reset' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { protected var value:int = 1 } func main() { var vault = Vault(); print(vault.value) }",
        "field 'value' is accessible only from class 'Vault' and its descendants",
    );
    try expectResolvedSemanticError(
        "class Vault { var value:int } func main() { var vault = Vault(value:1) }",
        "field 'value' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { var callback:(func())? = null } func main() { var vault = Vault(); print(vault.callback == null) }",
        "field 'callback' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { func reset() {} } func main() { var vault:Vault? = Vault(); vault?.reset() }",
        "method 'reset' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { var value:int = 1 } func main() { var vault = Vault()..value = 2 }",
        "field 'value' is private in class 'Vault'",
    );
}

test "struct private members protect copyable storage and close aggregate initialization" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Queue {
        \\    private var values:int[]
        \\    private var head:int
        \\    private static var creations:int
        \\    public var label:str
        \\    public static func create(label:str) Queue {
        \\        Queue.creations += 1
        \\        return Queue(values:[], head:0, label:label)
        \\    }
        \\    public func count() int { return self.values.count() - self.head }
        \\    private func hidden_count() int { return self.count() }
        \\}
        \\func main() {
        \\    var first = Queue.create("ready")
        \\    first.label = "updated"
        \\    let second = first
        \\    assert(first == second, "private fields keep structural equality")
        \\    print(first.count())
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].fields[2].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].static_fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].methods[2].visibility);

    try expectResolvedSemanticError(
        "struct Vault { private var value:int; public static func create() Vault { return Vault(value:1) } } func main() { let vault = Vault.create(); print(vault.value) }",
        "field 'value' is private in struct 'Vault'",
    );
    try expectResolvedSemanticError(
        "struct Vault { private var value:int; private func read() int { return self.value } public static func create() Vault { return Vault(value:1) } } func main() { let vault = Vault.create(); print(vault.read()) }",
        "method 'read' is private in struct 'Vault'",
    );
    try expectResolvedSemanticError(
        "struct Vault { private var value:int = 1; public var label:str } func main() { let vault = Vault(label:\"x\") }",
        "initializer of struct 'Vault' is private because it declares private fields",
    );
    try expectResolvedSemanticError(
        "struct Vault { private var value:int } func make() Vault { return Vault(value:1) } func main() {}",
        "initializer of struct 'Vault' is private because it declares private fields",
    );
    try expectResolvedSemanticError(
        "struct Vault { private var value:int; public static func create() Vault { return Vault(value:1) } } extend Vault { public func reveal() int { return self.value } } func main() {}",
        "field 'value' is private in struct 'Vault'",
    );
    try expectResolvedSemanticError(
        "struct Vault { private static var value:int; public static func create() int { return Vault.value } } func main() { print(Vault.value) }",
        "static field 'value' is private in struct 'Vault'",
    );
}

test "class constructors overload and establish private state" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { public var health:int = 100 }
        \\class Match {
        \\    var owner:Player
        \\    var count:int = 1
        \\    public init(owner:Player) { self.owner = owner }
        \\    public init(owner:Player, count:int) { self.owner = owner; self.count = count }
        \\    public func get_owner() Player { return self.owner }
        \\    public func get_count() int { return self.count }
        \\}
        \\func main() { var first = Match(Player()); var second = Match(Player(), 2); print(second.get_count()) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(@as(usize, 2), program.structures[1].constructors.len);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.initializer.value == .class_initializer);

    try expectResolvedSemanticError(
        "class Session { var token:str; public init(token:str) { self.token = token } } func main() { var session = Session() }",
        "no compatible constructor for 'Session'; visible constructors: Session(str)",
    );
    try expectResolvedSemanticError(
        "class Session { public var token:str; public init(token:str) { self.token = token } } func main() { var session = Session(token:\"abc\") }",
        "class 'Session' declares custom constructors and cannot use a named field initializer",
    );
    try expectResolvedSemanticError(
        "class Session { var token:str; init(token:str) { self.token = token } } func main() { var session = Session(\"abc\") }",
        "constructor of class 'Session' is private",
    );
}

test "class constructors require complete initialization on every path" {
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; public init(owner:Player, assign:bool) { if assign { self.owner = owner } } } func main() {}",
        "constructor of class 'Match' leaves field 'owner' without a value",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; public init(owner:Player) { print(self.owner == owner); self.owner = owner } } func main() {}",
        "field 'owner' is read before it is initialized",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; public init(owner:Player) { self.inspect(); self.owner = owner } func inspect() {} } func main() {}",
        "an instance method cannot be called before every class field is initialized",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; public init(owner:Player) { var alias = self; self.owner = owner } } func main() {}",
        "'self' cannot escape before every class field is initialized",
    );
}

test "class drop can read private state but cannot return" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Texture {
        \\    var handle:int = 1
        \\    drop { print(self.handle) }
        \\}
        \\func main() { var texture = Texture() }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expect(program.structures[0].drop != null);

    try expectResolvedSemanticError(
        "class Texture { drop { return } } func main() {}",
        "'drop' cannot return",
    );
}

test "unique resource structures initialize local owners directly" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    func value() int { return self.handle }
        \\    drop { print(self.handle) }
        \\}
        \\func main() {
        \\    let first = Resource.open(1)
        \\    var second = Resource.open(2)
        \\    print(first.value())
        \\    print(second.value())
        \\}
    );
}

test "noncopyable values compose through fields enums optionals collections classes and generics" {
    const declaration =
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
    ;

    try expectSemanticSuccess(declaration ++
        \\struct Holder { var resource:Resource }
        \\class Owner { public var resource:Resource }
        \\enum Slot { full(Holder); empty }
        \\func consume(value:Resource) {}
        \\func consume_holder(value:Holder) {}
        \\func inspect(value:@Resource) {}
        \\func main() {
        \\    let holder = Holder(resource:Resource.open(1))
        \\    inspect(holder.resource)
        \\    var optional:Resource? = Resource.open(3)
        \\    if value = @optional { inspect(value) }
        \\    if var value = move optional { consume(move value) }
        \\    var slot = Slot.full(Holder(resource:Resource.open(4)))
        \\    match @slot { full(value) => { inspect(value.resource) }; empty => {} }
        \\    match move slot { full(var value) => { consume_holder(move value) }; empty => {} }
        \\    var values:Resource[] = []
        \\    values.append(Resource.open(5))
        \\    let resource = Resource.open(6)
        \\    values.append(move resource)
        \\    for value in values { inspect(value) }
        \\    for var value in values { inspect(value) }
        \\    consume(values.take_first())
        \\    consume(values.replace(0, Resource.open(7)))
        \\    consume(values.take_last())
        \\    var owner = Owner(resource:Resource.open(8))
        \\    inspect(owner.resource)
        \\}
    );
    try expectSemanticSuccess(
        \\protocol Readable { func value() int }
        \\struct Resource : Readable {
        \\    let handle:int
        \\    func value() int { return self.handle }
        \\    drop {}
        \\}
        \\func inspect(value:@Resource) int { return value.value() }
        \\func main() { let resource = Resource(handle:1); print(inspect(resource)) }
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Resource.open(1); let second = first }",
        "cannot copy noncopyable value 'Resource'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func duplicate() Resource { let resource = Resource.open(1); return resource } func main() {}",
        "named noncopyable value 'Resource' must be returned with 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "struct Registry { static var current:Resource } func main() {}",
        "a static field cannot own a noncopyable value",
    );
    try expectSemanticSuccess(declaration ++ "func mutate(resource:&Resource) {} func main() {}");
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let callback = func() { print(resource.handle) } }",
        "noncopyable value 'Resource' cannot be captured by a lambda",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Resource.open(1); let second = Resource.open(2); print(first == second) }",
        "type 'Resource' does not support equality",
    );
    try expectResolvedSemanticError(
        declaration ++ "struct Holder { var resource:Resource } func main() { let first = Holder(resource:Resource.open(1)); let second = Holder(resource:Resource.open(2)); print(first == second) }",
        "type 'Holder' does not support equality",
    );
}
