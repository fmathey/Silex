const Types = @import("Types.zig");
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
const restoreOwnerStates = Support.restoreOwnerStates;
const findEnumVariant = Support.findEnumVariant;
pub fn function(self: anytype, ast: Ast.Function, symbol: FunctionSymbol) AnalyzeError!Function {
    self.current_structure_index = null;
    self.current_method_index = null;
    self.current_constructor = false;
    self.current_drop = false;
    self.current_method_static = false;
    self.current_extension = false;
    self.current_self_state = .{};
    self.loop_depth = 0;
    var scope = Scope{ .parent = null, .depth = 1 };
    self.function_scope_depth = scope.depth;
    var parameters: std.ArrayList(Parameter) = .empty;
    for (ast.parameters, symbol.parameter_types, symbol.parameter_modes) |parameter, parameter_type, mode| {
        if (findInCurrentScope(&scope, parameter.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
            return self.fail(parameter.position, message);
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        const state = try self.newBindingState(parameter_type);
        state.borrowed_parameter = mode == .borrow;
        try scope.symbols.append(self.allocator, .{ .source_name = parameter.name, .generated_name = generated_name, .type = parameter_type, .mutability = if (mode == .borrow) .immutable else .mutable, .state = state, .scope_depth = scope.depth });
        try parameters.append(self.allocator, .{
            .source_name = parameter.name,
            .position = parameter.position,
            .generated_name = generated_name,
            .type = parameter_type,
            .mode = mode,
            .capture_box = &state.capture_box,
        });
    }
    self.current_return_type = symbol.return_type;
    self.current_return_borrow_root = if (symbol.return_borrow_parameter) |index| scope.symbols.items[index].state else null;
    defer self.current_return_borrow_root = null;
    const function_statements = try self.statements(ast.statements, &scope);
    if (!ast.is_native and try self.isNonCopyableType(symbol.return_type)) {
        var returned_deferred = DeferredReturnSummary{};
        try collectReturnedDeferredResourcePaths(self.allocator, function_statements, &returned_deferred);
        for (self.functions.items) |*candidate| {
            if (!std.mem.eql(u8, candidate.generated_name, symbol.generated_name)) continue;
            const inferred_paths = try returned_deferred.paths.toOwnedSlice(self.allocator);
            if (!deferredResourcePathsEqual(candidate.return_deferred_resource_paths, inferred_paths)) {
                self.deferred_return_summary_changed = true;
            }
            candidate.return_deferred_resource_paths = inferred_paths;
            break;
        }
    }
    if (!ast.is_native and try self.isNonCopyableType(symbol.return_type)) {
        var returned_dependencies: std.ArrayList(*BindingState) = .empty;
        try collectReturnedResourceDependencies(self.allocator, function_statements, &returned_dependencies);
        var parameter_dependencies: std.ArrayList(usize) = .empty;
        for (returned_dependencies.items) |dependency| {
            var is_parameter = false;
            for (scope.symbols.items[0..ast.parameters.len]) |parameter_symbol| {
                if (dependency == parameter_symbol.state) is_parameter = true;
            }
            if (!is_parameter) {
                return self.fail(ast.name_position, "cannot return a native resource that depends on a local resource");
            }
        }
        for (scope.symbols.items[0..ast.parameters.len], 0..) |parameter_symbol, parameter_index| {
            for (returned_dependencies.items) |dependency| {
                if (dependency != parameter_symbol.state) continue;
                try parameter_dependencies.append(self.allocator, parameter_index);
                break;
            }
        }
        for (self.functions.items) |*candidate| {
            if (!std.mem.eql(u8, candidate.generated_name, symbol.generated_name)) continue;
            candidate.return_dependency_parameters = try parameter_dependencies.toOwnedSlice(self.allocator);
            break;
        }
    }
    self.releaseScopeBorrows(&scope);
    if (!ast.is_native and !typeEqual(symbol.return_type, .void) and !blockAlwaysReturns(function_statements)) {
        const message = try std.fmt.allocPrint(self.allocator, "function '{s}' must return '{s}' on every path", .{ ast.name, typeName(symbol.return_type) });
        return self.fail(ast.name_position, message);
    }
    return .{
        .generated_name = symbol.generated_name,
        .return_type = symbol.return_type,
        .parameters = try parameters.toOwnedSlice(self.allocator),
        .statements = function_statements,
        .is_main = symbol.is_main,
        .is_native = symbol.is_native,
        .is_native_resource_drop = symbol.is_native_resource_drop,
        .native_module_name = symbol.native_module_name,
        .native_function_name = symbol.native_function_name,
        .borrowed_return_parameter = symbol.return_borrow_parameter,
        .deferred_callback_index = symbol.deferred_callback_index,
    };
}

pub fn method(
    self: anytype,
    ast: Ast.Function,
    symbol: MethodSymbol,
    structure_index: usize,
    method_index: usize,
) AnalyzeError!Method {
    self.current_structure_index = structure_index;
    self.current_method_index = method_index;
    self.current_constructor = false;
    self.current_drop = false;
    self.current_method_static = symbol.is_static;
    self.current_extension = symbol.extension_visible_files != null;
    self.current_method_direct_mutation = false;
    self.current_method_direct_mutable_codegen = false;
    self.current_method_dependencies = .empty;
    self.current_self_state = .{};
    self.loop_depth = 0;

    var scope = Scope{ .parent = null, .depth = 1 };
    self.function_scope_depth = scope.depth;
    var parameters: std.ArrayList(Parameter) = .empty;
    for (ast.parameters, symbol.parameter_types, symbol.parameter_modes) |parameter, parameter_type, mode| {
        if (findInCurrentScope(&scope, parameter.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
            return self.fail(parameter.position, message);
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        const state = try self.newBindingState(parameter_type);
        state.borrowed_parameter = mode == .borrow;
        try scope.symbols.append(self.allocator, .{
            .source_name = parameter.name,
            .generated_name = generated_name,
            .type = parameter_type,
            .mutability = if (mode == .borrow) .immutable else .mutable,
            .state = state,
            .scope_depth = scope.depth,
        });
        try parameters.append(self.allocator, .{
            .source_name = parameter.name,
            .position = parameter.position,
            .generated_name = generated_name,
            .type = parameter_type,
            .mode = mode,
            .capture_box = &state.capture_box,
        });
    }

    self.current_return_type = symbol.return_type;
    self.current_return_borrow_root = if (symbol.return_type == .reference)
        if (symbol.return_borrow_parameter) |index| scope.symbols.items[index].state else &self.current_self_state
    else
        null;
    defer self.current_return_borrow_root = null;
    const method_statements = try self.statements(ast.statements, &scope);
    self.releaseScopeBorrows(&scope);
    if (!typeEqual(symbol.return_type, .void) and !blockAlwaysReturns(method_statements)) {
        const message = try std.fmt.allocPrint(self.allocator, "method '{s}' must return '{s}' on every path", .{ ast.name, typeName(symbol.return_type) });
        return self.fail(ast.name_position, message);
    }
    self.structures.items[structure_index].methods[method_index].direct_mutation = self.current_method_direct_mutation;
    self.structures.items[structure_index].methods[method_index].direct_mutable_codegen = self.current_method_direct_mutable_codegen;
    self.structures.items[structure_index].methods[method_index].dependencies = try self.current_method_dependencies.toOwnedSlice(self.allocator);
    return .{
        .generated_name = symbol.generated_name,
        .return_type = symbol.return_type,
        .parameters = try parameters.toOwnedSlice(self.allocator),
        .statements = method_statements,
        .is_mutating = false,
        .requires_mutable_codegen = false,
        .visibility = symbol.visibility,
        .is_override = symbol.is_override,
        .is_static = symbol.is_static,
        .is_extension = symbol.extension_visible_files != null,
    };
}

pub fn constructor(
    self: anytype,
    ast: Ast.Constructor,
    symbol: ConstructorSymbol,
    structure_index: usize,
) AnalyzeError!Constructor {
    self.current_structure_index = structure_index;
    self.current_method_index = null;
    self.current_constructor = true;
    self.current_drop = false;
    self.current_method_static = false;
    self.current_extension = false;
    defer self.current_constructor = false;
    self.current_method_direct_mutation = false;
    self.current_method_dependencies = .empty;
    self.current_self_state = .{};
    self.loop_depth = 0;

    var scope = Scope{ .parent = null, .depth = 1 };
    self.function_scope_depth = scope.depth;
    var parameters: std.ArrayList(Parameter) = .empty;
    for (ast.parameters, symbol.parameter_types, symbol.parameter_modes) |parameter, parameter_type, mode| {
        if (findInCurrentScope(&scope, parameter.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
            return self.fail(parameter.position, message);
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        const state = try self.newBindingState(parameter_type);
        state.borrowed_parameter = mode == .borrow;
        try scope.symbols.append(self.allocator, .{
            .source_name = parameter.name,
            .generated_name = generated_name,
            .type = parameter_type,
            .mutability = if (mode == .borrow) .immutable else .mutable,
            .state = state,
            .scope_depth = scope.depth,
        });
        try parameters.append(self.allocator, .{
            .source_name = parameter.name,
            .position = parameter.position,
            .generated_name = generated_name,
            .type = parameter_type,
            .mode = mode,
            .capture_box = &state.capture_box,
        });
    }

    const base_initializer = try self.constructorBaseInitialization(ast, structure_index, &scope);
    self.current_return_type = .void;
    const constructor_statements = try self.statements(ast.statements, &scope);
    self.releaseScopeBorrows(&scope);
    try self.validateConstructorInitialization(structure_index, constructor_statements, ast.position);
    return .{
        .parameters = try parameters.toOwnedSlice(self.allocator),
        .base_initializer = base_initializer,
        .statements = constructor_statements,
        .visibility = symbol.visibility,
    };
}

pub fn dropBlock(
    self: anytype,
    ast: Ast.Drop,
    structure_index: usize,
) AnalyzeError!Drop {
    self.current_structure_index = structure_index;
    self.current_method_index = null;
    self.current_constructor = false;
    self.current_drop = true;
    self.current_method_static = false;
    self.current_extension = false;
    defer self.current_drop = false;
    self.current_method_direct_mutation = false;
    self.current_method_dependencies = .empty;
    self.current_self_state = .{};
    self.loop_depth = 0;

    var scope = Scope{ .parent = null, .depth = 1 };
    self.function_scope_depth = scope.depth;
    self.current_return_type = .void;
    const drop_statements = try self.statements(ast.statements, &scope);
    self.releaseScopeBorrows(&scope);
    return .{ .statements = drop_statements };
}

pub fn constructorBaseInitialization(
    self: anytype,
    ast: Ast.Constructor,
    structure_index: usize,
    scope: *const Scope,
) AnalyzeError!?BaseInitializer {
    const structure = self.structures.items[structure_index];
    const position = ast.super_position orelse ast.position;
    const base_index = structure.base_index orelse {
        if (ast.super_arguments != null) return self.fail(position, "constructor 'super' call requires a base class");
        return null;
    };
    const base = self.structures.items[base_index];
    const ast_arguments = ast.super_arguments orelse &.{};

    if (base.constructors.len == 0) {
        if (ast_arguments.len != 0) {
            const message = try std.fmt.allocPrint(self.allocator, "base class '{s}' has no custom constructor accepting arguments", .{base.source_name});
            return self.fail(position, message);
        }
        const implicit = try self.implicitBaseInitialization(structure_index);
        if (!implicit.available) {
            const message = try std.fmt.allocPrint(self.allocator, "base class '{s}' cannot be constructed with 'super()'", .{base.source_name});
            return self.fail(position, message);
        }
        return implicit.initializer;
    }

    var candidates: std.ArrayList(ConstructorCandidate) = .empty;
    var inaccessible: ?ConstructorSymbol = null;
    for (base.constructors, 0..) |constructor_symbol, index| {
        if (self.memberVisibleFrom(structure_index, base_index, constructor_symbol.visibility)) {
            try candidates.append(self.allocator, .{ .symbol = constructor_symbol, .index = index });
        } else {
            inaccessible = constructor_symbol;
        }
    }
    if (candidates.items.len == 0) {
        const constructor_symbol = inaccessible.?;
        const message = switch (constructor_symbol.visibility) {
            .private_access => try std.fmt.allocPrint(self.allocator, "constructor of base class '{s}' is private", .{base.source_name}),
            .subclass => unreachable,
            .public_access => unreachable,
        };
        return self.fail(position, message);
    }

    const resolved = try self.resolveConstructorOverload(base.source_name, position, ast_arguments, scope, candidates.items);
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (ast_arguments, resolved.symbol.parameter_types, resolved.symbol.parameter_modes, resolved.symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of base constructor '{s}' expects '{s}', found '{s}'", .{ index + 1, base.source_name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and value.lifetime_depth != 0) {
            return self.fail(argument.position, "capturing callback cannot be passed to a base constructor parameter whose value escapes the call");
        }
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    return .{ .generated_name = base.generated_name, .arguments = try arguments.toOwnedSlice(self.allocator) };
}

pub fn validateConstructorInitialization(
    self: anytype,
    structure_index: usize,
    statements_value: []const Statement,
    position: Source.Position,
) AnalyzeError!void {
    const structure = &self.structures.items[structure_index];
    const initialized = try self.allocator.alloc(FieldInitialization, structure.fields.len);
    for (structure.fields, 0..) |field, index| {
        initialized[index] = if (field.default_value != null or
            (field.mutability == .mutable and self.hasIntrinsicDefault(field.type)))
            .initialized
        else
            .uninitialized;
    }
    const falls_through = try self.validateConstructorStatements(structure, statements_value, initialized);
    if (falls_through) try self.requireConstructorFieldsInitialized(structure, initialized, position);
}

pub fn validateConstructorStatements(
    self: anytype,
    structure: *const StructureSymbol,
    statements_value: []const Statement,
    initialized: []FieldInitialization,
) AnalyzeError!bool {
    for (statements_value) |statement_value| {
        const falls_through = try self.validateConstructorStatement(structure, statement_value, initialized);
        if (!falls_through) return false;
    }
    return true;
}

pub fn validateConstructorStatement(
    self: anytype,
    structure: *const StructureSymbol,
    statement_value: Statement,
    initialized: []FieldInitialization,
) AnalyzeError!bool {
    switch (statement_value) {
        .print => |value| try self.validateConstructorExpression(structure, value, initialized),
        .assertion => |assertion_value| {
            try self.validateConstructorExpression(structure, assertion_value.condition, initialized);
            try self.validateConstructorExpression(structure, assertion_value.message, initialized);
        },
        .panic_statement => |panic_value| {
            try self.validateConstructorExpression(structure, panic_value.message, initialized);
            return false;
        },
        .variable_declaration => |declaration| try self.validateConstructorExpression(structure, declaration.initializer, initialized),
        .assignment => |assignment_value| {
            const assigned_field = if (assignment_value.operator == .assign)
                directSelfFieldIndex(structure, assignment_value.target)
            else
                null;
            if (assigned_field) |field_index| {
                try self.validateConstructorExpression(structure, assignment_value.value.?, initialized);
                const field = structure.fields[field_index];
                if (field.mutability == .immutable) switch (initialized[field_index]) {
                    .uninitialized => {},
                    .initialized => {
                        const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is initialized more than once", .{field.source_name});
                        return self.fail(assignment_value.position, message);
                    },
                    .maybe_initialized => {
                        const message = try std.fmt.allocPrint(self.allocator, "field '{s}' may be initialized more than once", .{field.source_name});
                        return self.fail(assignment_value.position, message);
                    },
                };
                initialized[field_index] = .initialized;
            } else {
                try self.validateConstructorExpression(structure, assignment_value.target, initialized);
                if (assignment_value.value) |value| try self.validateConstructorExpression(structure, value, initialized);
            }
        },
        .if_statement => |if_value| {
            try self.validateConstructorCondition(structure, if_value.condition, initialized);
            var fallthrough_states: std.ArrayList([]FieldInitialization) = .empty;

            const body_state = try self.allocator.dupe(FieldInitialization, initialized);
            if (try self.validateConstructorStatements(structure, if_value.body, body_state)) {
                try fallthrough_states.append(self.allocator, body_state);
            }
            for (if_value.alternatives) |alternative| {
                try self.validateConstructorCondition(structure, alternative.condition, initialized);
                const alternative_state = try self.allocator.dupe(FieldInitialization, initialized);
                if (try self.validateConstructorStatements(structure, alternative.body, alternative_state)) {
                    try fallthrough_states.append(self.allocator, alternative_state);
                }
            }
            if (if_value.else_body) |else_body| {
                const else_state = try self.allocator.dupe(FieldInitialization, initialized);
                if (try self.validateConstructorStatements(structure, else_body, else_state)) {
                    try fallthrough_states.append(self.allocator, else_state);
                }
            } else {
                try fallthrough_states.append(self.allocator, try self.allocator.dupe(FieldInitialization, initialized));
            }
            if (fallthrough_states.items.len == 0) return false;
            for (initialized, 0..) |*field_initialized, field_index| {
                var saw_uninitialized = false;
                var saw_initialized = false;
                for (fallthrough_states.items) |state| switch (state[field_index]) {
                    .uninitialized => saw_uninitialized = true,
                    .initialized => saw_initialized = true,
                    .maybe_initialized => {
                        saw_uninitialized = true;
                        saw_initialized = true;
                    },
                };
                field_initialized.* = if (saw_uninitialized and saw_initialized)
                    .maybe_initialized
                else if (saw_initialized)
                    .initialized
                else
                    .uninitialized;
            }
        },
        .while_statement => |while_value| {
            try self.validateConstructorCondition(structure, while_value.condition, initialized);
            const body_state = try self.allocator.dupe(FieldInitialization, initialized);
            _ = try self.validateConstructorStatements(structure, while_value.body, body_state);
        },
        .for_statement => |for_value| {
            switch (for_value.source) {
                .collection => |collection| try self.validateConstructorExpression(structure, collection, initialized),
                .integer_range => |range| {
                    try self.validateConstructorExpression(structure, range.start, initialized);
                    try self.validateConstructorExpression(structure, range.end, initialized);
                },
            }
            const body_state = try self.allocator.dupe(FieldInitialization, initialized);
            _ = try self.validateConstructorStatements(structure, for_value.body, body_state);
        },
        .break_statement, .continue_statement => return false,
        .return_statement => |value| {
            if (value) |return_value| try self.validateConstructorExpression(structure, return_value, initialized);
            try self.requireConstructorFieldsInitialized(structure, initialized, if (value) |return_value| return_value.position else structure.position);
            return false;
        },
        .expression_statement => |value| try self.validateConstructorExpression(structure, value, initialized),
    }
    return true;
}

pub fn validateConstructorCondition(
    self: anytype,
    structure: *const StructureSymbol,
    condition: Statement.Condition,
    initialized: []const FieldInitialization,
) AnalyzeError!void {
    switch (condition) {
        .expression => |value| try self.validateConstructorExpression(structure, value, initialized),
        .binding => |binding| try self.validateConstructorExpression(structure, binding.source, initialized),
    }
}

pub fn validateConstructorExpression(
    self: anytype,
    structure: *const StructureSymbol,
    expression_value: *const Expression,
    initialized: []const FieldInitialization,
) AnalyzeError!void {
    switch (expression_value.value) {
        .integer, .floating, .boolean, .null, .string, .cascade_target, .variable, .static_field_access, .optional_unwrap, .function_reference => {},
        .self, .owner_self => if (!allFieldsInitialized(initialized)) {
            return self.fail(expression_value.position, try std.fmt.allocPrint(
                self.allocator,
                "'self' cannot escape before every {s} field is initialized",
                .{if (structure.is_class) "class" else "struct"},
            ));
        },
        .string_length => |value| try self.validateConstructorExpression(structure, value, initialized),
        .sequence_literal => |values| for (values) |value| try self.validateConstructorExpression(structure, value, initialized),
        .collection_method => |call| {
            try self.validateConstructorExpression(structure, call.object, initialized);
            for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized);
        },
        .cascade => |cascade_value| {
            try self.validateConstructorExpression(structure, cascade_value.object, initialized);
            for (cascade_value.operations) |operation| switch (operation) {
                .method_call => |call| try self.validateConstructorExpression(structure, call, initialized),
                .field_assignment => |assignment_value| try self.validateConstructorExpression(structure, assignment_value.value, initialized),
            };
        },
        .call => |call| for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized),
        .value_call => |call| {
            try self.validateConstructorExpression(structure, call.callee, initialized);
            if (call.owner) |owner| try self.validateConstructorExpression(structure, owner, initialized);
            for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized);
        },
        .lambda => |lambda| if (lambda.captures_self and !allFieldsInitialized(initialized)) {
            return self.fail(expression_value.position, try std.fmt.allocPrint(
                self.allocator,
                "a constructor lambda cannot capture 'self' before every {s} field is initialized",
                .{if (structure.is_class) "class" else "struct"},
            ));
        },
        .method_call => |call| {
            if (call.object.value == .self) {
                if (!allFieldsInitialized(initialized)) return self.fail(call.position, try std.fmt.allocPrint(
                    self.allocator,
                    "an instance method cannot be called before every {s} field is initialized",
                    .{if (structure.is_class) "class" else "struct"},
                ));
            } else try self.validateConstructorExpression(structure, call.object, initialized);
            for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized);
        },
        .static_method_call => |call| for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized),
        .super_method_call => return self.fail(expression_value.position, "'super.method(...)' is only available inside a class method"),
        .class_initializer => |initializer| for (initializer.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized),
        .structure_initializer => |initializer| for (initializer.fields) |field| try self.validateConstructorExpression(structure, field, initialized),
        .enum_initializer => |initializer| for (initializer.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized),
        .enum_raw_value => |value| try self.validateConstructorExpression(structure, value, initialized),
        .match_expression => |match_value| {
            try self.validateConstructorExpression(structure, match_value.subject, initialized);
            for (match_value.branches) |branch| switch (branch.body) {
                .expression => |value| try self.validateConstructorExpression(structure, value, initialized),
                .statements => |values| _ = try self.validateConstructorStatements(structure, values, try self.allocator.dupe(FieldInitialization, initialized)),
            };
        },
        .member_access, .bound_function => |member| {
            if (member.object.value == .self) {
                const field_index = generatedFieldIndex(structure, member.generated_name) orelse return;
                if (initialized[field_index] != .initialized) {
                    const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is read before it is initialized", .{structure.fields[field_index].source_name});
                    return self.fail(expression_value.position, message);
                }
            } else try self.validateConstructorExpression(structure, member.object, initialized);
        },
        .adapt_function => |value| try self.validateConstructorExpression(structure, value, initialized),
        .optional_wrap => |value| try self.validateConstructorExpression(structure, value, initialized),
        .safe_access => |access| {
            try self.validateConstructorExpression(structure, access.receiver, initialized);
            try self.validateConstructorExpression(structure, access.end, initialized);
        },
        .index_access => |access| {
            try self.validateConstructorExpression(structure, access.object, initialized);
            try self.validateConstructorExpression(structure, access.index, initialized);
        },
        .slice_access => |access| {
            try self.validateConstructorExpression(structure, access.object, initialized);
            try self.validateConstructorExpression(structure, access.start, initialized);
            try self.validateConstructorExpression(structure, access.end, initialized);
        },
        .try_expression => |try_value| try self.validateConstructorExpression(structure, try_value.operand, initialized),
        .move_expression => |move_value| try self.validateConstructorExpression(structure, move_value.operand, initialized),
        .borrow_expression => |borrow_value| try self.validateConstructorExpression(structure, borrow_value.operand, initialized),
        .unary => |unary| try self.validateConstructorExpression(structure, unary.operand, initialized),
        .binary => |binary| {
            try self.validateConstructorExpression(structure, binary.left, initialized);
            try self.validateConstructorExpression(structure, binary.right, initialized);
        },
        .conversion => |conversion| try self.validateConstructorExpression(structure, conversion.operand, initialized),
        .protocol_conversion => |conversion| try self.validateConstructorExpression(structure, conversion.operand, initialized),
        .protocol_method_call => |call| {
            try self.validateConstructorExpression(structure, call.object, initialized);
            for (call.arguments) |argument| try self.validateConstructorExpression(structure, argument, initialized);
        },
    }
}

pub fn requireConstructorFieldsInitialized(
    self: anytype,
    structure: *const StructureSymbol,
    initialized: []const FieldInitialization,
    position: Source.Position,
) AnalyzeError!void {
    for (initialized, 0..) |field_initialized, field_index| {
        if (field_initialized == .initialized) continue;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "constructor of {s} '{s}' leaves field '{s}' without a value",
            .{ if (structure.is_class) "class" else "struct", structure.source_name, structure.fields[field_index].source_name },
        );
        return self.fail(position, message);
    }
}
