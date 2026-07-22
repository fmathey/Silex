const Types = @import("Types.zig");
const AnalyzerModule = @import("Analyzer.zig");
const Support = @import("Support.zig");
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

pub fn expectSemanticError(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(expected_message, analyzer.diagnostic.?.message);
}

pub fn expectResolvedSemanticError(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expectEqualStrings(expected_message, analyzer.diagnostic.?.message);
}

pub fn expectResolvedSemanticErrorContains(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expect(std.mem.indexOf(u8, analyzer.diagnostic.?.message, expected_message) != null);
}

pub fn expectSemanticSuccess(source: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    _ = analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())) catch |failure| {
        if (analyzer.diagnostic) |diagnostic| std.debug.print("unexpected semantic error: {s}\n", .{diagnostic.message});
        return failure;
    };
}

pub fn analyzeDeferredNativeTest(allocator: Allocator, source: []const u8) !Program {
    const Parser = @import("../Parser.zig").Parser;
    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    return analyzer.analyze(try resolveDeferredNativeTestProgram(allocator, try parser.parse()));
}

pub fn resolveDeferredNativeTestProgram(allocator: Allocator, program: Ast.Program) !Ast.Program {
    const Modules = @import("../Modules.zig");
    const project = @import("../Project.zig").Project{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = false,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = program }});
    return resolver.resolve();
}

pub fn expectDeferredNativeError(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveDeferredNativeTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expectEqualStrings(expected_message, analyzer.diagnostic.?.message);
}

pub fn expectDeferredNativeSuccess(source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try analyzeDeferredNativeTest(arena.allocator(), source);
}

pub fn expectNativeStructureReturnRejected(source: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
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
    try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "native functions cannot return 'Payload"));
}

pub fn expectNativeStructureParameterRejected(source: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Native.native_accept";
    var specializer = Generics.Specializer.init(allocator, program);
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Native"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try specializer.specialize()));
    try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "native parameter 'value' cannot use 'Payload"));
}

pub fn expectNativeByteViewParameterRejected(source: []const u8) !void {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
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
    try std.testing.expect(std.mem.startsWith(u8, analyzer.diagnostic.?.message, "native parameter 'bytes' cannot use '"));
}

pub fn resolveSingleTestProgram(allocator: Allocator, program: Ast.Program) !Ast.Program {
    const Modules = @import("../Modules.zig");
    const project = @import("../Project.zig").Project{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = true,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = program }});
    return resolver.resolve();
}
