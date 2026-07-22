const std = @import("std");
const Semantic = @import("../Semantic.zig");
const Orchestrator = @import("Orchestrator.zig");
const Runtime = @import("Runtime.zig");
const Protocols = @import("Protocols.zig");
const NativeTransports = @import("NativeTransports.zig");
const NativeCalls = @import("NativeCalls.zig");
const CodeGeneration = @import("CodeGeneration.zig");
const Support = @import("Support.zig");

const Allocator = std.mem.Allocator;

pub const Generator = struct {
    pub const generateWithSources = Orchestrator.generateWithSources;
    pub const appendRuntime = Runtime.appendRuntime;
    pub const generateProtocolTypes = Protocols.generateProtocolTypes;
    pub const generateProtocolMethodDefinitions = Protocols.generateProtocolMethodDefinitions;
    pub const generateProtocolWitnesses = Protocols.generateProtocolWitnesses;
    pub const generateMethodSignature = Protocols.generateMethodSignature;
    pub const generateBaseInitializer = Protocols.generateBaseInitializer;
    pub const structureDefinitionOrder = Protocols.structureDefinitionOrder;
    pub const generateConstructorSignature = Protocols.generateConstructorSignature;
    pub const generateFunctionSignature = Protocols.generateFunctionSignature;
    pub const generateCapturedParameterBindings = Protocols.generateCapturedParameterBindings;
    pub const generateNativeFunctionSignature = Protocols.generateNativeFunctionSignature;
    pub const generateNativeTransportIfNew = NativeTransports.generateNativeTransportIfNew;
    pub const generateNativeTransportDefinition = NativeTransports.generateNativeTransportDefinition;
    pub const nativeResultShape = NativeTransports.nativeResultShape;
    pub const nativeBranchValueType = NativeTransports.nativeBranchValueType;
    pub const isNativeByteViewType = NativeTransports.isNativeByteViewType;
    pub const isNativeByteBufferReturnType = NativeTransports.isNativeByteBufferReturnType;
    pub const isNativeCallbackType = NativeTransports.isNativeCallbackType;
    pub const nativeDeferredCallbackIndex = NativeTransports.nativeDeferredCallbackIndex;
    pub const isNativeCallbackScalarType = NativeTransports.isNativeCallbackScalarType;
    pub const appendCppNativeCallbackParameter = NativeTransports.appendCppNativeCallbackParameter;
    pub const generateNativeResultTransportIfNew = NativeTransports.generateNativeResultTransportIfNew;
    pub const generateNativeResultBranchFields = NativeTransports.generateNativeResultBranchFields;
    pub const nativeReturnStructure = NativeTransports.nativeReturnStructure;
    pub const nativeStructureForType = NativeTransports.nativeStructureForType;
    pub const structureIsNativeReturn = NativeTransports.structureIsNativeReturn;
    pub const nativeReturnValueType = NativeTransports.nativeReturnValueType;
    pub const nativeReturnedView = NativeTransports.nativeReturnedView;
    pub const nativeArgumentViewType = NativeTransports.nativeArgumentViewType;
    pub const structureHasString = NativeTransports.structureHasString;
    pub const containsNativeFunction = NativeTransports.containsNativeFunction;
    pub const nativeTransportHasString = NativeTransports.nativeTransportHasString;
    pub const generateNativeStringGuardCleanup = NativeTransports.generateNativeStringGuardCleanup;
    pub const generateNativeArgumentPreludes = NativeTransports.generateNativeArgumentPreludes;
    pub const generateNativeArgument = NativeCalls.generateNativeArgument;
    pub const generateNativeCallbackTrampoline = NativeCalls.generateNativeCallbackTrampoline;
    pub const appendCppDeferredCallbackStateType = NativeCalls.appendCppDeferredCallbackStateType;
    pub const nativeResultBranchHasOwned = NativeCalls.nativeResultBranchHasOwned;
    pub const generateNativeResultOwnedAction = NativeCalls.generateNativeResultOwnedAction;
    pub const generateNativeResultPointerAction = NativeCalls.generateNativeResultPointerAction;
    pub const generateNativeResultOwnedCondition = NativeCalls.generateNativeResultOwnedCondition;
    pub const generateNativeResultByteBufferValidation = NativeCalls.generateNativeResultByteBufferValidation;
    pub const generateNativeResultByteBufferConstruction = NativeCalls.generateNativeResultByteBufferConstruction;
    pub const generateNativeResultFatal = NativeCalls.generateNativeResultFatal;
    pub const generateNativeResultStringValidation = NativeCalls.generateNativeResultStringValidation;
    pub const generateNativeResultStringConstruction = NativeCalls.generateNativeResultStringConstruction;
    pub const generateNativeResultUtf8Validation = NativeCalls.generateNativeResultUtf8Validation;
    pub const generateNativeResultBranchValue = NativeCalls.generateNativeResultBranchValue;
    pub const generateNativeResultBranchReturn = NativeCalls.generateNativeResultBranchReturn;
    pub const generateNativeResultFunctionCall = NativeCalls.generateNativeResultFunctionCall;
    pub const generateNativeFunctionCall = NativeCalls.generateNativeFunctionCall;
    pub const generateNativeByteBufferFunctionCall = NativeCalls.generateNativeByteBufferFunctionCall;
    pub const generateNativeOptionalFunctionCall = NativeCalls.generateNativeOptionalFunctionCall;
    pub const generateStructureEqualitySignature = CodeGeneration.generateStructureEqualitySignature;
    pub const generateStructureEqualityName = CodeGeneration.generateStructureEqualityName;
    pub const generateStructureOperatorEqualitySignature = CodeGeneration.generateStructureOperatorEqualitySignature;
    pub const generateStructureFieldEquality = CodeGeneration.generateStructureFieldEquality;
    pub const generateStatements = CodeGeneration.generateStatements;
    pub const generateTryPreludes = CodeGeneration.generateTryPreludes;
    pub const generateStatement = CodeGeneration.generateStatement;
    pub const generateMatchBindings = CodeGeneration.generateMatchBindings;
    pub const generateImperativeMatch = CodeGeneration.generateImperativeMatch;
    pub const generateIntegerRangeStatement = CodeGeneration.generateIntegerRangeStatement;
    pub const generateCondition = CodeGeneration.generateCondition;
    pub const generateConditionalBindingDeclaration = CodeGeneration.generateConditionalBindingDeclaration;
    pub const generateExpression = CodeGeneration.generateExpression;
    pub const generateSourcePaths = Support.generateSourcePaths;
    pub const appendCppStringLiteral = Support.appendCppStringLiteral;
    pub const appendCppByteStringLiteral = Support.appendCppByteStringLiteral;
    pub const generateRuntimeArguments = Support.generateRuntimeArguments;
    pub const appendCppSourceLocation = Support.appendCppSourceLocation;
    pub const indent = Support.indent;
    pub const cppType = Support.cppType;
    pub const appendCppType = Support.appendCppType;
    pub const appendCppParameterType = Support.appendCppParameterType;
    pub const isClassType = Support.isClassType;
    pub const silexTypeName = Support.silexTypeName;
    pub const isInteger = Support.isInteger;
    pub const isUnsignedInteger = Support.isUnsignedInteger;
    pub const isArithmetic = Support.isArithmetic;
    pub const isShift = Support.isShift;
    pub const checkedBinaryFunction = Support.checkedBinaryFunction;
    pub const checkedShiftFunction = Support.checkedShiftFunction;
    pub const checkedAssignmentFunction = Support.checkedAssignmentFunction;
    pub const generateIntegerOne = Support.generateIntegerOne;
    pub const integerMinimumMagnitude = Support.integerMinimumMagnitude;
    pub const operatorText = Support.operatorText;
    pub const assignmentOperatorText = Support.assignmentOperatorText;
};

pub fn generate(allocator: Allocator, program: Semantic.Program) ![]u8 {
    return generateWithSources(allocator, program, &.{"<memory>"});
}

pub fn generateWithSources(
    allocator: Allocator,
    program: Semantic.Program,
    source_paths: []const []const u8,
) ![]u8 {
    var generator = Generator{};
    return generator.generateWithSources(allocator, program, source_paths);
}
