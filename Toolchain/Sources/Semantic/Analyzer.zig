const Types = @import("Types.zig");
const Support = @import("Support.zig");
const Declarations = @import("Declarations.zig");
const Callables = @import("Callables.zig");
const Statements = @import("Statements.zig");
const Expressions = @import("Expressions.zig");
const Calls = @import("Calls.zig");
const Resolution = @import("Resolution.zig");
const Validation = @import("Validation.zig");
const Ownership = @import("Ownership.zig");
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

pub const Analyzer = struct {
    allocator: Allocator,
    native_module_names: []const []const u8 = &.{},
    require_main: bool = true,
    next_symbol_id: usize = 0,
    functions: std.ArrayList(FunctionSymbol) = .empty,
    enums: std.ArrayList(EnumSymbol) = .empty,
    protocols: std.ArrayList(ProtocolSymbol) = .empty,
    structures: std.ArrayList(StructureSymbol) = .empty,
    current_return_type: Type = .void,
    current_return_borrow_root: ?*BindingState = null,
    current_structure_index: ?usize = null,
    current_method_index: ?usize = null,
    current_constructor: bool = false,
    current_drop: bool = false,
    current_method_static: bool = false,
    current_extension: bool = false,
    current_method_direct_mutation: bool = false,
    current_method_direct_mutable_codegen: bool = false,
    current_method_dependencies: std.ArrayList(MethodId) = .empty,
    current_self_state: BindingState = .{},
    loop_depth: usize = 0,
    current_loop_flow: ?*LoopFlow = null,
    function_scope_depth: usize = 0,
    current_lambda: ?*LambdaContext = null,
    inferring_deferred_return_summaries: bool = false,
    deferred_return_summary_changed: bool = false,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator) Analyzer {
        return .{ .allocator = allocator };
    }

    pub fn analyze(self: *Analyzer, program: Ast.Program) !Program {
        try self.collectEnumNames(program.enums);
        try self.collectStructureNames(program.structures);
        try self.collectProtocols(program.protocols);
        try self.collectStructures(program.structures);
        try self.collectEnumVariants(program.enums);
        try self.validateNoncopyableStaticFields();
        try self.collectFunctions(program.functions);
        try self.validateStructureDefaults();
        var enums: std.ArrayList(Enum) = .empty;
        for (self.enums.items) |symbol| {
            var variants: std.ArrayList(EnumVariant) = .empty;
            for (symbol.variants) |variant| try variants.append(self.allocator, .{
                .associated_types = variant.associated_types,
                .raw_value = variant.raw_value,
            });
            try enums.append(self.allocator, .{
                .generated_name = symbol.generated_name,
                .raw_type = symbol.raw_type,
                .is_copyable = !try self.isNonCopyableType(.{ .enumeration = .{
                    .source_name = symbol.source_name,
                    .generated_name = symbol.generated_name,
                } }),
                .variants = try variants.toOwnedSlice(self.allocator),
            });
        }
        var protocols: std.ArrayList(Protocol) = .empty;
        for (self.protocols.items) |symbol| {
            var requirements: std.ArrayList(ProtocolMethod) = .empty;
            for (symbol.requirements) |requirement| try requirements.append(self.allocator, .{
                .generated_name = requirement.generated_name,
                .return_type = requirement.return_type,
                .parameter_types = requirement.parameter_types,
                .parameter_modes = requirement.parameter_modes,
            });
            try protocols.append(self.allocator, .{
                .generated_name = symbol.generated_name,
                .requirements = try requirements.toOwnedSlice(self.allocator),
            });
        }
        var structures: std.ArrayList(Structure) = .empty;
        for (program.structures, self.structures.items, 0..) |ast_structure, symbol, structure_index| {
            var fields: std.ArrayList(StructureField) = .empty;
            for (symbol.fields) |field| try fields.append(self.allocator, .{
                .source_name = field.source_name,
                .generated_name = field.generated_name,
                .type = field.type,
                .visibility = field.visibility,
                .mutability = field.mutability,
                .initializer = if (symbol.constructors.len == 0)
                    field.default_value
                else if (field.default_value) |default_value|
                    default_value
                else if (field.mutability == .mutable)
                    try self.intrinsicDefaultExpression(field.type, field.position)
                else
                    null,
            });
            var static_fields: std.ArrayList(StructureField) = .empty;
            for (symbol.static_fields) |field| {
                const intrinsic = try self.intrinsicDefaultExpression(field.type, field.position);
                const reset_value = intrinsic orelse field.default_value orelse {
                    const field_type_name = try allocatedTypeName(self.allocator, field.type);
                    const message = try std.fmt.allocPrint(self.allocator, "static field '{s}' of type '{s}' has no intrinsic value", .{ field.source_name, field_type_name });
                    return self.fail(field.position, message);
                };
                try static_fields.append(self.allocator, .{
                    .source_name = field.source_name,
                    .generated_name = field.generated_name,
                    .type = field.type,
                    .visibility = field.visibility,
                    .mutability = field.mutability,
                    .initializer = field.default_value orelse intrinsic.?,
                    .reset_value = reset_value,
                });
            }
            var constructors: std.ArrayList(Constructor) = .empty;
            for (ast_structure.constructors, symbol.constructors) |ast_constructor, constructor_symbol| {
                try constructors.append(self.allocator, try self.constructor(ast_constructor, constructor_symbol, structure_index));
            }
            const drop = if (ast_structure.drop) |ast_drop|
                try self.dropBlock(ast_drop, structure_index)
            else if (ast_structure.is_native_resource)
                Drop{ .statements = &.{} }
            else
                null;
            var methods: std.ArrayList(Method) = .empty;
            for (ast_structure.methods, symbol.methods, 0..) |ast_method, method_symbol, method_index| {
                try methods.append(self.allocator, try self.method(ast_method, method_symbol, structure_index, method_index));
            }
            const implicit_base = if (symbol.constructors.len == 0)
                try self.implicitBaseInitialization(structure_index)
            else
                ImplicitBaseInitialization{ .available = false, .initializer = null };
            try structures.append(self.allocator, .{
                .source_name = symbol.source_name,
                .generated_name = symbol.generated_name,
                .is_class = symbol.is_class,
                .is_owner = symbol.is_owner,
                .is_native_resource = symbol.is_native_resource,
                .native_module_name = symbol.native_module_name,
                .native_drop_name = symbol.native_drop_name,
                .native_drop_symbol = symbol.native_drop_symbol,
                .is_noncopyable = !symbol.is_class and try self.isNonCopyableType(.{ .structure = self.structureType(structure_index) }),
                .equality_comparable = self.isEqualityComparable(.{ .structure = self.structureType(structure_index) }),
                .protocol_conformances = try self.protocolConformances(structure_index),
                .base = if (symbol.base_index) |base_index| self.structureType(base_index) else null,
                .implicit_constructor_available = symbol.constructors.len == 0 and implicit_base.available,
                .implicit_base_initializer = implicit_base.initializer,
                .fields = try fields.toOwnedSlice(self.allocator),
                .static_fields = try static_fields.toOwnedSlice(self.allocator),
                .constructors = try constructors.toOwnedSlice(self.allocator),
                .drop = drop,
                .methods = try methods.toOwnedSlice(self.allocator),
            });
        }
        const function_symbol_start = self.next_symbol_id;
        var has_deferred_registration = false;
        for (self.functions.items) |symbol| {
            if (symbol.deferred_callback_index != null) has_deferred_registration = true;
        }
        if (has_deferred_registration) {
            self.inferring_deferred_return_summaries = true;
            var summary_pass: usize = 0;
            while (summary_pass <= program.functions.len) : (summary_pass += 1) {
                self.next_symbol_id = function_symbol_start;
                self.deferred_return_summary_changed = false;
                for (program.functions, self.functions.items) |ast_function, symbol| {
                    _ = try self.function(ast_function, symbol);
                }
                if (!self.deferred_return_summary_changed) break;
            }
            self.inferring_deferred_return_summaries = false;
        }
        self.next_symbol_id = function_symbol_start;

        var functions: std.ArrayList(Function) = .empty;
        for (program.functions, self.functions.items) |ast_function, symbol| {
            try functions.append(self.allocator, try self.function(ast_function, symbol));
        }
        self.inferMethodMutability();
        for (structures.items, self.structures.items) |*structure, symbol| {
            for (structure.methods, symbol.methods) |*method_value, method_symbol| {
                method_value.is_mutating = method_symbol.is_mutating;
                method_value.requires_mutable_codegen = method_symbol.requires_mutable_codegen;
            }
        }
        const result = Program{
            .enums = try enums.toOwnedSlice(self.allocator),
            .protocols = try protocols.toOwnedSlice(self.allocator),
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
        try self.validateMethodCalls(result);
        return result;
    }

    pub const collectEnumNames = Declarations.collectEnumNames;
    pub const collectEnumVariants = Declarations.collectEnumVariants;
    pub const validateNoncopyableStaticFields = Declarations.validateNoncopyableStaticFields;
    pub const enumRawValue = Declarations.enumRawValue;
    pub const collectStructures = Declarations.collectStructures;
    pub const collectStructureNames = Declarations.collectStructureNames;
    pub const collectProtocols = Declarations.collectProtocols;
    pub const validateProtocolConformances = Declarations.validateProtocolConformances;
    pub const findProtocolRequirementMethod = Declarations.findProtocolRequirementMethod;
    pub const protocolConformance = Declarations.protocolConformance;
    pub const structureConformsToProtocol = Declarations.structureConformsToProtocol;
    pub const protocolConformances = Declarations.protocolConformances;
    pub const validateInheritanceCycles = Declarations.validateInheritanceCycles;
    pub const validateInheritedMembers = Declarations.validateInheritedMembers;
    pub const validateInheritedStructure = Declarations.validateInheritedStructure;
    pub const collectFunctions = Declarations.collectFunctions;
    pub const validateStructureDefaults = Declarations.validateStructureDefaults;
    pub const validateDefaultShape = Declarations.validateDefaultShape;
    pub const function = Callables.function;
    pub const method = Callables.method;
    pub const constructor = Callables.constructor;
    pub const dropBlock = Callables.dropBlock;
    pub const constructorBaseInitialization = Callables.constructorBaseInitialization;
    pub const validateConstructorInitialization = Callables.validateConstructorInitialization;
    pub const validateConstructorStatements = Callables.validateConstructorStatements;
    pub const validateConstructorStatement = Callables.validateConstructorStatement;
    pub const validateConstructorCondition = Callables.validateConstructorCondition;
    pub const validateConstructorExpression = Callables.validateConstructorExpression;
    pub const requireConstructorFieldsInitialized = Callables.requireConstructorFieldsInitialized;
    pub const statements = Statements.statements;
    pub const statement = Statements.statement;
    pub const analyzeAssertion = Statements.analyzeAssertion;
    pub const analyzePanic = Statements.analyzePanic;
    pub const variableDeclaration = Statements.variableDeclaration;
    pub const requireAvailableVariableName = Statements.requireAvailableVariableName;
    pub const assignment = Statements.assignment;
    pub const uniqueOwnerAssignment = Statements.uniqueOwnerAssignment;
    pub const checkedAssignment = Statements.checkedAssignment;
    pub const snapshotOwnerStates = Statements.snapshotOwnerStates;
    pub const captureOwnerStates = Statements.captureOwnerStates;
    pub const restoreOwnerStates = Support.restoreOwnerStates;
    pub const mergeOwnerStates = Statements.mergeOwnerStates;
    pub const requireSameOwnerStates = Statements.requireSameOwnerStates;
    pub const ifStatement = Statements.ifStatement;
    pub const whileStatement = Statements.whileStatement;
    pub const analyzeCondition = Statements.analyzeCondition;
    pub const applyPresenceReduction = Statements.applyPresenceReduction;
    pub const forStatement = Statements.forStatement;
    pub const returnStatement = Statements.returnStatement;
    pub const expression = Expressions.expression;
    pub const expressionForBorrow = Expressions.expressionForBorrow;
    pub const expressionForExpected = Expressions.expressionForExpected;
    pub const functionReferenceExpression = Expressions.functionReferenceExpression;
    pub const identifierExpression = Expressions.identifierExpression;
    pub const integerExpression = Expressions.integerExpression;
    pub const floatExpression = Expressions.floatExpression;
    pub const stringExpression = Expressions.stringExpression;
    pub const sequenceLiteralExpression = Expressions.sequenceLiteralExpression;
    pub const decodeStringLiteral = Expressions.decodeStringLiteral;
    pub const defaultExpression = Expressions.defaultExpression;
    pub const intrinsicDefaultExpression = Expressions.intrinsicDefaultExpression;
    pub const hasIntrinsicDefault = Expressions.hasIntrinsicDefault;
    pub const variableExpression = Expressions.variableExpression;
    pub const selfExpression = Expressions.selfExpression;
    pub const binaryExpression = Expressions.binaryExpression;
    pub const conversionExpression = Expressions.conversionExpression;
    pub const callExpression = Expressions.callExpression;
    pub const dispatchCallbacksExpression = Expressions.dispatchCallbacksExpression;
    pub const valueCallExpression = Expressions.valueCallExpression;
    pub const functionCallResourceDependencies = Expressions.functionCallResourceDependencies;
    pub const checkedValueCall = Expressions.checkedValueCall;
    pub const lambdaExpression = Expressions.lambdaExpression;
    pub const methodCallExpression = Calls.methodCallExpression;
    pub const methodCallExpressionWithObject = Calls.methodCallExpressionWithObject;
    pub const protocolMethodCallExpression = Calls.protocolMethodCallExpression;
    pub const staticFieldAccessExpression = Calls.staticFieldAccessExpression;
    pub const staticMethodCallExpression = Calls.staticMethodCallExpression;
    pub const enumInitializerExpression = Calls.enumInitializerExpression;
    pub const matchExpression = Calls.matchExpression;
    pub const superMethodCallExpression = Calls.superMethodCallExpression;
    pub const cascadeExpression = Calls.cascadeExpression;
    pub const requireMutableCascadeReceiver = Calls.requireMutableCascadeReceiver;
    pub const collectionMethodCallExpression = Calls.collectionMethodCallExpression;
    pub const requireMutableCollectionReceiver = Calls.requireMutableCollectionReceiver;
    pub const resolveFunctionOverload = Resolution.resolveFunctionOverload;
    pub const resolveMethodOverload = Resolution.resolveMethodOverload;
    pub const resolveConstructorOverload = Resolution.resolveConstructorOverload;
    pub const overloadScores = Resolution.overloadScores;
    pub const noCompatibleFunctionOverload = Resolution.noCompatibleFunctionOverload;
    pub const ambiguousFunctionOverload = Resolution.ambiguousFunctionOverload;
    pub const noCompatibleMethodOverload = Resolution.noCompatibleMethodOverload;
    pub const ambiguousMethodOverload = Resolution.ambiguousMethodOverload;
    pub const findFunction = Resolution.findFunction;
    pub const isNativeModule = Resolution.isNativeModule;
    pub const findStructure = Resolution.findStructure;
    pub const findProtocol = Resolution.findProtocol;
    pub const findProtocolIndex = Resolution.findProtocolIndex;
    pub const findEnum = Resolution.findEnum;
    pub const findEnumByGeneratedName = Resolution.findEnumByGeneratedName;
    pub const findEnumVariant = Support.findEnumVariant;
    pub const findStructureIndex = Resolution.findStructureIndex;
    pub const findStructureIndexByGeneratedName = Resolution.findStructureIndexByGeneratedName;
    pub const structureType = Resolution.structureType;
    pub const findFieldInHierarchy = Resolution.findFieldInHierarchy;
    pub const findStaticField = Resolution.findStaticField;
    pub const findStaticFieldByGeneratedName = Resolution.findStaticFieldByGeneratedName;
    pub const findFieldByGeneratedName = Resolution.findFieldByGeneratedName;
    pub const immutableFieldInPlace = Resolution.immutableFieldInPlace;
    pub const implicitBaseInitialization = Resolution.implicitBaseInitialization;
    pub const memberVisibleFromCurrentContext = Resolution.memberVisibleFromCurrentContext;
    pub const memberVisibleFrom = Resolution.memberVisibleFrom;
    pub const isDescendantOf = Resolution.isDescendantOf;
    pub const requireFieldAccess = Resolution.requireFieldAccess;
    pub const uniqueOwnerStorageVisible = Resolution.uniqueOwnerStorageVisible;
    pub const failMemberAccess = Resolution.failMemberAccess;
    pub const structureInitializerExpression = Resolution.structureInitializerExpression;
    pub const classInitializerExpression = Resolution.classInitializerExpression;
    pub const memberAccessExpression = Resolution.memberAccessExpression;
    pub const memberAccessExpressionRaw = Resolution.memberAccessExpressionRaw;
    pub const memberAccessExpressionWithObject = Resolution.memberAccessExpressionWithObject;
    pub const safeMemberAccessExpression = Resolution.safeMemberAccessExpression;
    pub const indexAccessExpression = Resolution.indexAccessExpression;
    pub const sliceAccessExpression = Resolution.sliceAccessExpression;
    pub const findStructureByGeneratedName = Resolution.findStructureByGeneratedName;
    pub const validateParameterMode = Resolution.validateParameterMode;
    pub const rejectUniqueOwnerArgument = Resolution.rejectUniqueOwnerArgument;
    pub const rejectUniqueOwnerComposition = Resolution.rejectUniqueOwnerComposition;
    pub const uniqueOwnerCause = Resolution.uniqueOwnerCause;
    pub const isNonCopyableType = Resolution.isNonCopyableType;
    pub const isNonCopyableTemporary = Resolution.isNonCopyableTemporary;
    pub const uniqueOwnerCauseInner = Resolution.uniqueOwnerCauseInner;
    pub const isEqualityComparable = Resolution.isEqualityComparable;
    pub const requireIndependentLetType = Resolution.requireIndependentLetType;
    pub const nonIndependentType = Resolution.nonIndependentType;
    pub const inferMethodMutability = Validation.inferMethodMutability;
    pub const methodSymbol = Validation.methodSymbol;
    pub const validateMethodCalls = Validation.validateMethodCalls;
    pub const validateStatements = Validation.validateStatements;
    pub const validateCondition = Validation.validateCondition;
    pub const validateExpression = Validation.validateExpression;
    pub const unaryExpression = Validation.unaryExpression;
    pub const moveExpression = Validation.moveExpression;
    pub const resultShape = Validation.resultShape;
    pub const tryExpression = Validation.tryExpression;
    pub const argumentForMode = Validation.argumentForMode;
    pub const nativeResourceDropArgument = Validation.nativeResourceDropArgument;
    pub const readBorrowArgument = Validation.readBorrowArgument;
    pub const readBorrowValue = Validation.readBorrowValue;
    pub const mutableReferenceArgument = Validation.mutableReferenceArgument;
    pub const borrowExpression = Validation.borrowExpression;
    pub const appendLiteralExpectedType = Validation.appendLiteralExpectedType;
    pub const requireBinaryOperands = Validation.requireBinaryOperands;
    pub const requireNumericOperands = Validation.requireNumericOperands;
    pub const coerce = Validation.coerce;
    pub const classUpcastDistance = Ownership.classUpcastDistance;
    pub const implicitConversionScore = Ownership.implicitConversionScore;
    pub const optionalType = Ownership.optionalType;
    pub const newExpression = Ownership.newExpression;
    pub const projectDeferredResourcePaths = Ownership.projectDeferredResourcePaths;
    pub const appendDeferredStoragePath = Ownership.appendDeferredStoragePath;
    pub const replacedDeferredResourcePaths = Ownership.replacedDeferredResourcePaths;
    pub const recordLambdaCapture = Ownership.recordLambdaCapture;
    pub const recordSymbolCapture = Ownership.recordSymbolCapture;
    pub const typeContainsClass = Ownership.typeContainsClass;
    pub const typeContainsClassInner = Ownership.typeContainsClassInner;
    pub const newBindingState = Ownership.newBindingState;
    pub const copyBorrow = Ownership.copyBorrow;
    pub const releaseTransientBorrow = Ownership.releaseTransientBorrow;
    pub const retainTransientBorrow = Ownership.retainTransientBorrow;
    pub const releaseScopeBorrows = Ownership.releaseScopeBorrows;
    pub const placeRootSymbol = Ownership.placeRootSymbol;
    pub const isNativeReturnType = Ownership.isNativeReturnType;
    pub const isNativeResultBranchType = Ownership.isNativeResultBranchType;
    pub const isNativeLegacyReturnType = Ownership.isNativeLegacyReturnType;
    pub const nativeResultTransport = Ownership.nativeResultTransport;
    pub const nativeStructureTransport = Ownership.nativeStructureTransport;
    pub const nativeParameterStructures = Ownership.nativeParameterStructures;
    pub const isNativeParameterType = Ownership.isNativeParameterType;
    pub const isNativeResourceType = Ownership.isNativeResourceType;
    pub const fail = Ownership.fail;
};
