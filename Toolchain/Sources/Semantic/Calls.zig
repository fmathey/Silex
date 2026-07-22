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
pub fn methodCallExpression(
    self: anytype,
    call: Ast.Expression.MethodCall,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const object = try self.expression(call.object, scope);
    if (object.type == .structure) {
        const structure_index = self.findStructureIndexByGeneratedName(object.type.structure.generated_name).?;
        if (self.findFieldInHierarchy(structure_index, call.name)) |field_candidate| {
            const declaring_structure = &self.structures.items[field_candidate.structure_index];
            const field = field_candidate.symbol;
            if (field.type == .function) {
                try self.requireFieldAccess(field_candidate.structure_index, declaring_structure, field, call.name_position);
                if (call.object.value == .self and self.current_method_index != null) {
                    self.current_method_direct_mutable_codegen = true;
                }
                const callee = try self.newExpression(.{
                    .type = field.type,
                    .position = call.name_position,
                    .value = .{ .member_access = .{ .object = object, .generated_name = field.generated_name } },
                });
                return self.checkedValueCall(callee, call.arguments, call.name_position, scope, object);
            }
        }
    }
    var receiver = receiverFor(
        call.object,
        scope,
        self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0,
    );
    const shared_identity_receiver = switch (receiver) {
        .immutable => |value| value.read_iteration or value.collection_shell,
        else => false,
    };
    if ((object.type == .structure and object.type.structure.is_class and
        (receiver == .temporary or shared_identity_receiver)) or
        (object.type == .protocol and switch (receiver) {
            .immutable => |value| value.read_iteration,
            else => false,
        }))
    {
        receiver = .mutable;
    }
    if (self.immutableFieldInPlace(object)) |field_candidate| receiver = .{ .immutable_field = field_candidate.symbol.source_name };
    return self.methodCallExpressionWithObject(call, object, scope, receiver, false);
}

pub fn methodCallExpressionWithObject(
    self: anytype,
    call: Ast.Expression.MethodCall,
    object: *Expression,
    scope: *const Scope,
    receiver: Receiver,
    allow_temporary_collection_mutation: bool,
) AnalyzeError!*Expression {
    const receiver_type = if (object.type == .reference and object.type.reference.target.* == .view)
        object.type.reference.target.*
    else
        object.type;
    switch (receiver_type) {
        .list, .fixed_array, .view, .str => return self.collectionMethodCallExpression(
            call,
            object,
            scope,
            receiver,
            allow_temporary_collection_mutation,
        ),
        .protocol => return self.protocolMethodCallExpression(call, object, scope, receiver),
        .structure => {},
        else => return self.fail(call.name_position, "method call requires a struct, class, or collection value"),
    }
    const generated_structure_name = object.type.structure.generated_name;
    const structure_index = self.findStructureIndexByGeneratedName(generated_structure_name).?;
    const structure = &self.structures.items[structure_index];
    const extension_visibility_file = call.extension_visibility_file orelse call.name_position.file;
    var candidates: std.ArrayList(MethodCandidate) = .empty;
    var inaccessible: ?MethodCandidate = null;
    var static_match = false;
    var declaring_index: ?usize = structure_index;
    while (declaring_index) |index| {
        const declaring_structure = self.structures.items[index];
        for (declaring_structure.methods, 0..) |method_symbol, method_index| {
            if (std.mem.eql(u8, method_symbol.source_name, call.name)) {
                if (method_symbol.extension_visible_files) |visible_files| {
                    if (index != structure_index or !fileSetContains(visible_files, extension_visibility_file)) continue;
                }
                if (method_symbol.is_static) {
                    if (index == structure_index) static_match = true;
                    continue;
                }
                const candidate = MethodCandidate{ .symbol = method_symbol, .structure_index = index, .index = method_index };
                if (method_symbol.extension_visible_files != null or self.memberVisibleFromCurrentContext(index, method_symbol.visibility)) {
                    if (!methodCandidatesContainSlot(candidates.items, method_symbol.generated_name)) try candidates.append(self.allocator, candidate);
                } else {
                    inaccessible = candidate;
                }
            }
        }
        declaring_index = declaring_structure.base_index;
    }
    if (candidates.items.len == 0) {
        if (static_match) {
            const message = try std.fmt.allocPrint(self.allocator, "static method '{s}' must be called through type '{s}'", .{ call.name, structure.source_name });
            return self.fail(call.name_position, message);
        }
        if (inaccessible) |candidate| {
            const declaring_structure = &self.structures.items[candidate.structure_index];
            return self.failMemberAccess("method", declaring_structure, candidate.symbol.source_name, candidate.symbol.visibility, call.name_position);
        }
        const message = try std.fmt.allocPrint(self.allocator, "{s} '{s}' has no method '{s}'", .{ if (structure.is_class) "class" else "struct", structure.source_name, call.name });
        return self.fail(call.name_position, message);
    }
    const resolved = try self.resolveMethodOverload(call.name, call.name_position, call.arguments, scope, candidates.items);
    const method_symbol = resolved.symbol;
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    const receiver_depth = expressionScopeDepth(call.object, scope);
    for (call.arguments, method_symbol.parameter_types, method_symbol.parameter_modes, method_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and receiver_depth < value.lifetime_depth) {
            return self.fail(argument.position, "capturing callback cannot be stored in a receiver that outlives one of its captures");
        }
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    const method_id = MethodId{ .structure_index = resolved.structure_index, .method_index = resolved.index };
    if (receiver == .self and self.current_method_index != null) {
        try self.current_method_dependencies.append(self.allocator, method_id);
    }
    var returned_borrow: ?Borrow = null;
    if (method_symbol.return_type == .reference) {
        const root = if (method_symbol.return_borrow_parameter) |parameter_index|
            if (arguments.items[parameter_index].borrow) |borrow| borrow.root else arguments.items[parameter_index].owner_state
        else if (object.borrow) |borrow|
            borrow.root
        else
            object.owner_state;
        const mutable = method_symbol.return_type.reference.mutable;
        returned_borrow = .{ .root = root, .mutable = mutable };
        if (root) |state| {
            if (mutable) state.mutable_borrow = true else state.immutable_borrows += 1;
        }
    }
    return self.newExpression(.{
        .type = method_symbol.return_type,
        .position = call.name_position,
        .borrow = returned_borrow,
        .owns_borrow = returned_borrow != null,
        .value = .{ .method_call = .{
            .object = object,
            .source_name = method_symbol.source_name,
            .generated_name = method_symbol.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .method_id = method_id,
            .receiver = receiver,
            .position = call.name_position,
        } },
    });
}

pub fn protocolMethodCallExpression(
    self: anytype,
    call: Ast.Expression.MethodCall,
    object: *Expression,
    scope: *const Scope,
    receiver: Receiver,
) AnalyzeError!*Expression {
    if (receiver == .self and self.current_method_index != null) self.current_method_direct_mutation = true;
    const protocol = self.protocols.items[object.type.protocol.index];
    var matching: std.ArrayList(usize) = .empty;
    for (protocol.requirements, 0..) |requirement, index| {
        if (std.mem.eql(u8, requirement.source_name, call.name)) try matching.append(self.allocator, index);
    }
    if (matching.items.len == 0) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "protocol '{s}' has no method '{s}'",
            .{ protocol.source_name, call.name },
        );
        return self.fail(call.name_position, message);
    }

    var best: ?usize = null;
    var best_scores: ?[]const u8 = null;
    var ambiguous = false;
    for (matching.items) |index| {
        const requirement = protocol.requirements[index];
        const scores = try self.overloadScores(
            call.arguments,
            scope,
            requirement.parameter_types,
            requirement.parameter_modes,
        ) orelse continue;
        if (best == null or overloadBetter(scores, best_scores.?)) {
            best = index;
            best_scores = scores;
            ambiguous = false;
        } else if (!overloadBetter(best_scores.?, scores)) {
            ambiguous = true;
        }
    }
    if (best == null) {
        const message = try std.fmt.allocPrint(self.allocator, "no compatible signature for protocol method '{s}'", .{call.name});
        return self.fail(call.name_position, message);
    }
    if (ambiguous) {
        const message = try std.fmt.allocPrint(self.allocator, "ambiguous call to protocol method '{s}'", .{call.name});
        return self.fail(call.name_position, message);
    }
    const requirement = protocol.requirements[best.?];
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (call.arguments, requirement.parameter_types, requirement.parameter_modes, 0..) |argument, expected_type, mode, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "argument {d} of protocol method '{s}' expects '{s}', found '{s}'",
                .{ index + 1, call.name, typeName(expected_type), typeName(value.type) },
            );
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    var returned_borrow: ?Borrow = null;
    if (requirement.return_type == .reference) {
        const root = if (object.borrow) |borrow| borrow.root else object.owner_state;
        const mutable = requirement.return_type.reference.mutable;
        returned_borrow = .{ .root = root, .mutable = mutable };
        if (root) |state| {
            if (mutable) state.mutable_borrow = true else state.immutable_borrows += 1;
        }
    }
    return self.newExpression(.{
        .type = requirement.return_type,
        .position = call.name_position,
        .borrow = returned_borrow,
        .owns_borrow = returned_borrow != null,
        .value = .{ .protocol_method_call = .{
            .object = object,
            .source_name = requirement.source_name,
            .generated_name = requirement.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .receiver = receiver,
            .position = call.name_position,
        } },
    });
}

pub fn staticFieldAccessExpression(
    self: anytype,
    access: Ast.Expression.StaticFieldAccess,
) AnalyzeError!*Expression {
    const owner_type = try typeFromAnnotation(self, access.owner, access.owner_position);
    if (owner_type == .enumeration) {
        const enum_symbol = self.findEnumByGeneratedName(owner_type.enumeration.generated_name).?;
        if (findEnumVariant(enum_symbol, access.name) != null) {
            return self.fail(access.name_position, "an enum variant must be constructed with parentheses");
        }
        const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' has no variant '{s}'", .{ enum_symbol.source_name, access.name });
        return self.fail(access.name_position, message);
    }
    if (owner_type != .structure) return self.fail(access.owner_position, "a static field must be selected through a struct or class type");
    const structure_index = self.findStructureIndexByGeneratedName(owner_type.structure.generated_name).?;
    const structure = &self.structures.items[structure_index];
    if (self.findStaticField(structure_index, access.name)) |field| {
        if (!self.memberVisibleFromCurrentContext(structure_index, field.visibility)) {
            return self.failMemberAccess("static field", structure, field.source_name, field.visibility, access.name_position);
        }
        return self.newExpression(.{
            .type = field.type,
            .position = access.name_position,
            .value = .{ .static_field_access = .{
                .owner_generated_name = structure.generated_name,
                .generated_name = field.generated_name,
            } },
        });
    }
    if (self.findFieldInHierarchy(structure_index, access.name) != null) {
        const message = try std.fmt.allocPrint(self.allocator, "instance field '{s}' requires a value of type '{s}'", .{ access.name, structure.source_name });
        return self.fail(access.name_position, message);
    }
    const message = try std.fmt.allocPrint(self.allocator, "type '{s}' has no static field '{s}'", .{ structure.source_name, access.name });
    return self.fail(access.name_position, message);
}

pub fn staticMethodCallExpression(
    self: anytype,
    call: Ast.Expression.StaticMethodCall,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (call.named_fields != null) return self.fail(call.name_position, "static methods do not accept named arguments");
    const owner_type = try typeFromAnnotation(self, call.owner, call.owner_position);
    if (owner_type == .enumeration) return self.enumInitializerExpression(owner_type.enumeration, call, scope);
    if (owner_type != .structure) return self.fail(call.owner_position, "a static method must be selected through a struct or class type");
    const structure_index = self.findStructureIndexByGeneratedName(owner_type.structure.generated_name).?;
    const structure = &self.structures.items[structure_index];
    var candidates: std.ArrayList(MethodCandidate) = .empty;
    var inaccessible: ?MethodCandidate = null;
    var instance_match = false;
    for (structure.methods, 0..) |method_symbol, method_index| {
        if (!std.mem.eql(u8, method_symbol.source_name, call.name)) continue;
        if (method_symbol.extension_visible_files) |visible_files| {
            if (!fileSetContains(visible_files, call.name_position.file)) continue;
        }
        if (!method_symbol.is_static) {
            instance_match = true;
            continue;
        }
        const candidate = MethodCandidate{ .symbol = method_symbol, .structure_index = structure_index, .index = method_index };
        if (method_symbol.extension_visible_files != null or self.memberVisibleFromCurrentContext(structure_index, method_symbol.visibility)) {
            try candidates.append(self.allocator, candidate);
        } else {
            inaccessible = candidate;
        }
    }
    if (candidates.items.len == 0) {
        if (inaccessible) |candidate| {
            return self.failMemberAccess("static method", structure, candidate.symbol.source_name, candidate.symbol.visibility, call.name_position);
        }
        if (instance_match) {
            const message = try std.fmt.allocPrint(self.allocator, "instance method '{s}' requires a value of type '{s}'", .{ call.name, structure.source_name });
            return self.fail(call.name_position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "type '{s}' has no static method '{s}'", .{ structure.source_name, call.name });
        return self.fail(call.name_position, message);
    }
    const resolved = try self.resolveMethodOverload(call.name, call.name_position, call.arguments, scope, candidates.items);
    const method_symbol = resolved.symbol;
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (call.arguments, method_symbol.parameter_types, method_symbol.parameter_modes, method_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of static method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and value.lifetime_depth != 0) {
            return self.fail(argument.position, "capturing callback cannot be passed to a parameter whose value escapes the call");
        }
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    return self.newExpression(.{
        .type = method_symbol.return_type,
        .position = call.name_position,
        .value = .{ .static_method_call = .{
            .owner_generated_name = structure.generated_name,
            .generated_name = method_symbol.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn enumInitializerExpression(
    self: anytype,
    enum_type: EnumType,
    call: Ast.Expression.StaticMethodCall,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const enum_symbol = self.findEnumByGeneratedName(enum_type.generated_name).?;
    const variant_index = findEnumVariant(enum_symbol, call.name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' has no variant '{s}'", .{ enum_symbol.source_name, call.name });
        return self.fail(call.name_position, message);
    };
    const variant = enum_symbol.variants[variant_index];
    if (call.arguments.len != variant.associated_types.len) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "variant '{s}.{s}' expects {d} associated values, found {d}",
            .{ enum_symbol.source_name, variant.source_name, variant.associated_types.len, call.arguments.len },
        );
        return self.fail(call.name_position, message);
    }
    var arguments: std.ArrayList(*Expression) = .empty;
    var lifetime_depth: usize = 0;
    for (call.arguments, variant.associated_types, 0..) |argument, expected_type, index| {
        var value = try self.expressionForExpected(argument, scope, expected_type);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "associated value {d} of variant '{s}.{s}' expects '{s}', found '{s}'",
                .{ index + 1, enum_symbol.source_name, variant.source_name, typeName(expected_type), typeName(value.type) },
            );
            return self.fail(argument.position, message);
        }
        try self.rejectUniqueOwnerArgument(value, argument.position);
        try arguments.append(self.allocator, value);
        lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
        self.releaseTransientBorrow(value);
    }
    return self.newExpression(.{
        .type = .{ .enumeration = enum_type },
        .position = call.name_position,
        .lifetime_depth = lifetime_depth,
        .value = .{ .enum_initializer = .{
            .enum_generated_name = enum_type.generated_name,
            .variant_index = variant_index,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn matchExpression(
    self: anytype,
    ast_match: Ast.Expression.Match,
    parent_scope: *const Scope,
) AnalyzeError!*Expression {
    var mode: TransferMode = if (ast_match.subject.value == .move_expression)
        .move
    else if (ast_match.subject.value == .borrow_expression)
        .borrow
    else
        .copy;
    const subject = switch (mode) {
        .copy => try self.expression(ast_match.subject, parent_scope),
        .move => move_subject: {
            const move_value = ast_match.subject.value.move_expression;
            if (move_value.operand.value == .identifier) {
                if (findSymbol(parent_scope, move_value.operand.value.identifier)) |symbol| {
                    if (try self.isNonCopyableType(symbol.type)) break :move_subject try self.moveExpression(move_value, parent_scope);
                }
            }
            break :move_subject try self.expression(move_value.operand, parent_scope);
        },
        .borrow => try self.readBorrowValue(ast_match.subject.value.borrow_expression, parent_scope, null),
    };
    if (subject.type != .enumeration) {
        const message = try std.fmt.allocPrint(self.allocator, "match requires an enum value, found '{s}'", .{typeName(subject.type)});
        return self.fail(ast_match.subject.position, message);
    }
    if (try self.isNonCopyableType(subject.type) and mode == .copy) {
        if (self.isNonCopyableTemporary(subject)) {
            mode = .move;
        } else {
            return self.fail(ast_match.subject.position, "a named noncopyable enum must be matched with 'match move' or 'match @value'");
        }
    }
    const enum_symbol = self.findEnumByGeneratedName(subject.type.enumeration.generated_name).?;
    const temporary_name = try std.fmt.allocPrint(self.allocator, "silexMatch{d}", .{self.next_symbol_id});
    self.next_symbol_id += 1;
    const seen = try self.allocator.alloc(bool, enum_symbol.variants.len);
    @memset(seen, false);
    var branches: std.ArrayList(Expression.Match.Branch) = .empty;
    var result_type: ?Type = null;
    var expression_form: ?bool = null;
    var lifetime_depth = subject.lifetime_depth;
    var has_else = false;
    const tracked = try self.snapshotOwnerStates(parent_scope);
    const branch_entry = try self.captureOwnerStates(tracked);
    var owner_outcomes: std.ArrayList([]const OwnerStateSnapshot) = .empty;

    for (ast_match.branches, 0..) |ast_branch, branch_index| {
        restoreOwnerStates(branch_entry);
        var associated_types: []const Type = &.{};
        const variant_index: ?usize = if (ast_branch.variant) |variant_name| variant: {
            const index = findEnumVariant(enum_symbol, variant_name) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' has no variant '{s}'", .{ enum_symbol.source_name, variant_name });
                return self.fail(ast_branch.variant_position, message);
            };
            if (seen[index]) {
                const message = try std.fmt.allocPrint(self.allocator, "variant '{s}' is matched more than once", .{variant_name});
                return self.fail(ast_branch.variant_position, message);
            }
            seen[index] = true;
            associated_types = enum_symbol.variants[index].associated_types;
            break :variant index;
        } else else_branch: {
            if (has_else) return self.fail(ast_branch.variant_position, "a match can contain only one else branch");
            if (branch_index + 1 != ast_match.branches.len) return self.fail(ast_branch.variant_position, "else must be the last match branch");
            has_else = true;
            var covers_variant = false;
            for (seen) |was_seen| covers_variant = covers_variant or !was_seen;
            if (!covers_variant) return self.fail(ast_branch.variant_position, "else match branch does not cover any remaining variant");
            if (ast_branch.bindings.len != 0) return self.fail(ast_branch.variant_position, "an else match branch cannot bind associated values");
            break :else_branch null;
        };
        if (variant_index != null and ast_branch.bindings.len != associated_types.len) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "variant '{s}.{s}' exposes {d} associated values, but the pattern binds {d}",
                .{ enum_symbol.source_name, ast_branch.variant.?, associated_types.len, ast_branch.bindings.len },
            );
            return self.fail(ast_branch.variant_position, message);
        }

        var branch_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
        var bindings: std.ArrayList(Expression.Match.Binding) = .empty;
        for (ast_branch.bindings, associated_types) |ast_binding, binding_type| {
            try self.requireAvailableVariableName(&branch_scope, ast_binding.name, ast_binding.position);
            if (mode == .borrow and ast_binding.mutability == .mutable) {
                return self.fail(ast_binding.position, "a match binding extracted with '@' is read-only and cannot use 'var'");
            }
            if (ast_binding.mutability == .immutable and mode == .copy) try self.requireIndependentLetType(binding_type, ast_binding.position);
            const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            const state = try self.newBindingState(binding_type);
            state.borrowed_parameter = mode == .borrow;
            try branch_scope.symbols.append(self.allocator, .{
                .source_name = ast_binding.name,
                .generated_name = generated_name,
                .type = binding_type,
                .mutability = if (mode == .borrow) .immutable else ast_binding.mutability,
                .state = state,
                .scope_depth = branch_scope.depth,
                .control_binding = true,
            });
            try bindings.append(self.allocator, .{
                .source_name = ast_binding.name,
                .position = ast_binding.position,
                .generated_name = generated_name,
                .type = binding_type,
                .mutability = if (mode == .borrow) .immutable else ast_binding.mutability,
                .capture_box = &state.capture_box,
            });
        }

        const body: Expression.Match.Body = switch (ast_branch.body) {
            .expression => |ast_expression| expression_body: {
                if (expression_form == false) return self.fail(ast_expression.position, "match cannot mix expression branches and block branches");
                expression_form = true;
                const value = try self.expression(ast_expression, &branch_scope);
                if (result_type) |expected| {
                    if (!typeEqual(expected, value.type)) {
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "match branches must have the same type; expected '{s}', found '{s}'",
                            .{ typeName(expected), typeName(value.type) },
                        );
                        return self.fail(ast_expression.position, message);
                    }
                } else {
                    result_type = value.type;
                }
                lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
                try owner_outcomes.append(self.allocator, try self.captureOwnerStates(tracked));
                break :expression_body .{ .expression = value };
            },
            .statements => |ast_statements| block_body: {
                if (expression_form == true) return self.fail(ast_branch.variant_position, "match cannot mix expression branches and block branches");
                expression_form = false;
                const statements_value = try self.statements(ast_statements, &branch_scope);
                if (astStatementsFallThrough(ast_statements)) {
                    try owner_outcomes.append(self.allocator, try self.captureOwnerStates(tracked));
                }
                break :block_body .{ .statements = statements_value };
            },
        };
        self.releaseScopeBorrows(&branch_scope);
        try branches.append(self.allocator, .{
            .variant_index = variant_index,
            .bindings = try bindings.toOwnedSlice(self.allocator),
            .body = body,
        });
    }

    for (seen, enum_symbol.variants) |was_seen, variant| {
        if (has_else) break;
        if (!was_seen) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "match on enum '{s}' is not exhaustive; missing variant '{s}'",
                .{ enum_symbol.source_name, variant.source_name },
            );
            return self.fail(ast_match.subject.position, message);
        }
    }
    try self.mergeOwnerStates(tracked, owner_outcomes.items);
    self.releaseTransientBorrow(subject);
    return self.newExpression(.{
        .type = if (expression_form orelse false) result_type.? else .void,
        .position = ast_match.subject.position,
        .lifetime_depth = lifetime_depth,
        .value = .{ .match_expression = .{
            .subject = subject,
            .temporary_name = temporary_name,
            .mode = mode,
            .branches = try branches.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn superMethodCallExpression(
    self: anytype,
    call: Ast.Expression.SuperMethodCall,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (call.named_fields != null) return self.fail(call.name_position, "'super' method calls do not accept named arguments");
    if (self.current_extension) return self.fail(call.position, "'super' is not available in an extension method");
    if (self.current_method_static) return self.fail(call.position, "'super' is not available inside a static method");
    const structure_index = self.current_structure_index orelse return self.fail(call.position, "'super' is only available inside a class method");
    if (self.current_method_index == null or self.current_constructor) return self.fail(call.position, "'super.method(...)' is only available inside a class method");
    const structure = self.structures.items[structure_index];
    if (!structure.is_class) return self.fail(call.position, "'super' is only available inside a class method");
    const direct_base_index = structure.base_index orelse return self.fail(call.position, "'super' requires a base class");

    var candidates: std.ArrayList(MethodCandidate) = .empty;
    var inaccessible: ?MethodCandidate = null;
    var declaring_index: ?usize = direct_base_index;
    while (declaring_index) |index| {
        const declaring_structure = self.structures.items[index];
        for (declaring_structure.methods, 0..) |method_symbol, method_index| {
            if (method_symbol.extension_visible_files != null) continue;
            if (method_symbol.is_static) continue;
            if (!std.mem.eql(u8, method_symbol.source_name, call.name)) continue;
            const candidate = MethodCandidate{ .symbol = method_symbol, .structure_index = index, .index = method_index };
            if (self.memberVisibleFrom(structure_index, index, method_symbol.visibility)) {
                if (!methodCandidatesContainSlot(candidates.items, method_symbol.generated_name)) try candidates.append(self.allocator, candidate);
            } else {
                inaccessible = candidate;
            }
        }
        declaring_index = declaring_structure.base_index;
    }
    if (candidates.items.len == 0) {
        if (inaccessible) |candidate| {
            return self.failMemberAccess("method", &self.structures.items[candidate.structure_index], candidate.symbol.source_name, candidate.symbol.visibility, call.name_position);
        }
        const message = try std.fmt.allocPrint(self.allocator, "base class has no method '{s}'", .{call.name});
        return self.fail(call.name_position, message);
    }

    const resolved = try self.resolveMethodOverload(call.name, call.name_position, call.arguments, scope, candidates.items);
    const method_symbol = resolved.symbol;
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (call.arguments, method_symbol.parameter_types, method_symbol.parameter_modes, method_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and value.lifetime_depth > 1) {
            return self.fail(argument.position, "capturing callback cannot be stored in a receiver that outlives one of its captures");
        }
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    const method_id = MethodId{ .structure_index = resolved.structure_index, .method_index = resolved.index };
    try self.current_method_dependencies.append(self.allocator, method_id);
    return self.newExpression(.{
        .type = method_symbol.return_type,
        .position = call.name_position,
        .value = .{ .super_method_call = .{
            .base_generated_name = self.structures.items[direct_base_index].generated_name,
            .generated_name = method_symbol.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn cascadeExpression(
    self: anytype,
    cascade: Ast.Expression.Cascade,
    scope: *const Scope,
    expected_type: ?Type,
) AnalyzeError!*Expression {
    const object = try self.expressionForExpected(cascade.object, scope, expected_type);
    if (object.type == .void) return self.fail(cascade.object.position, "cascade receiver cannot have type 'void'");

    const target = try self.newExpression(.{
        .type = object.type,
        .position = cascade.object.position,
        .value = .cascade_target,
    });
    var ordinary_receiver = receiverFor(
        cascade.object,
        scope,
        self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0,
    );
    if (self.immutableFieldInPlace(object)) |field_candidate| ordinary_receiver = .{ .immutable_field = field_candidate.symbol.source_name };
    const owns_temporary = isCascadeOwnedTemporary(cascade.object);
    const receiver: Receiver = if (ordinary_receiver == .temporary and owns_temporary)
        .cascade_temporary
    else
        ordinary_receiver;

    var operations: std.ArrayList(Expression.Cascade.Operation) = .empty;
    var cascade_lifetime = object.lifetime_depth;
    for (cascade.operations) |operation| switch (operation) {
        .method_call => |cascade_method| {
            const call = Ast.Expression.MethodCall{
                .object = cascade.object,
                .name = cascade_method.name,
                .name_position = cascade_method.name_position,
                .extension_visibility_file = cascade_method.extension_visibility_file,
                .arguments = cascade_method.arguments,
            };
            const resolved = try self.methodCallExpressionWithObject(call, target, scope, receiver, owns_temporary);
            try operations.append(self.allocator, .{ .method_call = resolved });
        },
        .field_assignment => |field_assignment| {
            if (self.immutableFieldInPlace(object)) |field_candidate| {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutate through let field '{s}'", .{field_candidate.symbol.source_name});
                return self.fail(field_assignment.name_position, message);
            }
            try self.requireMutableCascadeReceiver(
                cascade.object,
                scope,
                field_assignment.name_position,
                owns_temporary,
            );
            const structure_type = switch (object.type) {
                .structure => |structure| structure,
                else => return self.fail(field_assignment.name_position, "cascade field assignment requires a struct or class value"),
            };
            const structure = self.findStructureByGeneratedName(structure_type.generated_name).?;
            const structure_index = self.findStructureIndexByGeneratedName(structure_type.generated_name).?;
            const field_candidate = self.findFieldInHierarchy(structure_index, field_assignment.name) orelse {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "{s} '{s}' has no field '{s}'",
                    .{ if (structure.is_class) "class" else "struct", structure.source_name, field_assignment.name },
                );
                return self.fail(field_assignment.name_position, message);
            };
            const declaring_structure = &self.structures.items[field_candidate.structure_index];
            const field = field_candidate.symbol;
            try self.requireFieldAccess(field_candidate.structure_index, declaring_structure, field, field_assignment.name_position);
            if (field.mutability == .immutable) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutate let field '{s}'", .{field.source_name});
                return self.fail(field_assignment.name_position, message);
            }
            var value = try self.expressionForExpected(field_assignment.value, scope, field.type);
            value = try self.coerce(value, field.type);
            if (!typeEqual(value.type, field.type)) {
                const message = try typeMismatchMessage(self.allocator, field.type, value.type);
                return self.fail(field_assignment.value.position, message);
            }
            if (expressionScopeDepth(cascade.object, scope) < value.lifetime_depth) {
                return self.fail(field_assignment.value.position, "capturing function value cannot be stored in a longer-lived destination");
            }
            updateDestinationLifetime(cascade.object, scope, value.lifetime_depth);
            cascade_lifetime = @max(cascade_lifetime, value.lifetime_depth);
            try operations.append(self.allocator, .{ .field_assignment = .{
                .generated_name = field.generated_name,
                .value = value,
            } });
        },
    };

    return self.newExpression(.{
        .type = object.type,
        .position = cascade.object.position,
        .lifetime_depth = cascade_lifetime,
        .value = .{ .cascade = .{
            .object = object,
            .operations = try operations.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn requireMutableCascadeReceiver(
    self: anytype,
    ast_object: *const Ast.Expression,
    scope: *const Scope,
    position: Source.Position,
    allow_temporary_mutation: bool,
) AnalyzeError!void {
    const root = assignmentRoot(ast_object) orelse {
        if (allow_temporary_mutation) return;
        return self.fail(position, "cascade mutations require a mutable value or a newly owned temporary");
    };
    switch (root) {
        .static => {},
        .self => {
            if (self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0) {
                return self.fail(position, "cannot mutate 'self' while one of its collections is iterated");
            }
            self.current_method_direct_mutation = true;
        },
        .variable => |name| {
            const symbol = findSymbol(scope, name) orelse return self.fail(position, "unknown cascade receiver");
            if (symbol.mutability == .immutable) {
                const message = if (symbol.control_binding)
                    try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{name})
                else
                    try std.fmt.allocPrint(self.allocator, "cannot assign through cascade on immutable value '{s}'", .{name});
                return self.fail(position, message);
            }
            if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{name});
                return self.fail(position, message);
            }
        },
    }
}

pub fn collectionMethodCallExpression(
    self: anytype,
    call: Ast.Expression.MethodCall,
    object: *Expression,
    scope: *const Scope,
    receiver: Receiver,
    allow_temporary_mutation: bool,
) AnalyzeError!*Expression {
    const operation: Expression.CollectionMethod.Operation = if (std.mem.eql(u8, call.name, "count"))
        .count
    else if (std.mem.eql(u8, call.name, "is_empty"))
        .is_empty
    else if (std.mem.eql(u8, call.name, "append"))
        .append
    else if (std.mem.eql(u8, call.name, "prepend"))
        .prepend
    else if (std.mem.eql(u8, call.name, "insert"))
        .insert
    else if (std.mem.eql(u8, call.name, "take"))
        .take
    else if (std.mem.eql(u8, call.name, "take_first"))
        .take_first
    else if (std.mem.eql(u8, call.name, "take_last"))
        .take_last
    else if (std.mem.eql(u8, call.name, "replace"))
        .replace
    else if (std.mem.eql(u8, call.name, "swap"))
        .swap
    else if (std.mem.eql(u8, call.name, "reverse"))
        .reverse
    else if (std.mem.eql(u8, call.name, "clear"))
        .clear
    else {
        const message = try std.fmt.allocPrint(self.allocator, "type '{s}' has no method '{s}'", .{ typeName(object.type), call.name });
        return self.fail(call.name_position, message);
    };
    const collection_type = if (object.type == .reference and object.type.reference.target.* == .view)
        object.type.reference.target.*
    else
        object.type;
    const element_type: ?Type = switch (collection_type) {
        .list => |element| element.*,
        .fixed_array => |array| array.element.*,
        .view => |element| element.*,
        .str => null,
        else => unreachable,
    };
    const allows = switch (operation) {
        .count => collection_type == .str or element_type != null,
        .is_empty => element_type != null,
        .swap => element_type != null,
        .replace, .reverse => element_type != null and collection_type != .view,
        .append, .append_range, .prepend, .insert, .take, .take_first, .take_last, .clear => collection_type == .list,
    };
    if (!allows) {
        const message = try std.fmt.allocPrint(self.allocator, "method '{s}' is not available on '{s}'", .{ call.name, typeName(object.type) });
        return self.fail(call.name_position, message);
    }
    const expected_arguments: usize = switch (operation) {
        .count, .is_empty, .take_first, .take_last, .reverse, .clear => 0,
        .append, .append_range, .prepend, .take => 1,
        .insert, .replace, .swap => 2,
    };
    if (call.arguments.len != expected_arguments) {
        const message = try std.fmt.allocPrint(self.allocator, "method '{s}' expects {d} arguments, found {d}", .{ call.name, expected_arguments, call.arguments.len });
        return self.fail(call.name_position, message);
    }
    switch (operation) {
        .count, .is_empty => {},
        else => if (!allow_temporary_mutation or assignmentRoot(call.object) != null)
            try self.requireMutableCollectionReceiver(call.object, object, scope, receiver, call.name_position, call.name),
    }

    var resolved_operation = operation;
    var arguments: std.ArrayList(*Expression) = .empty;
    for (call.arguments, 0..) |argument, index| {
        const expects_element = switch (operation) {
            .append, .prepend => true,
            .insert, .replace => index == 1,
            else => false,
        };
        const expected_type: Type = if (expects_element) element_type.? else .int;
        const expression_expected_type: Type = if (operation == .append and argument.value == .sequence_literal)
            try self.appendLiteralExpectedType(argument.value.sequence_literal, element_type.?)
        else
            expected_type;
        var value = try self.expressionForExpected(argument, scope, expression_expected_type);
        if (operation == .append and !typeEqual(value.type, element_type.?)) {
            if (value.type == .reference and typeEqual(value.type.reference.target.*, element_type.?)) {
                value = try self.newExpression(.{
                    .type = element_type.?,
                    .position = argument.position,
                    .value = .{ .unary = .{ .operator = .dereference, .operand = value } },
                });
            } else {
                var range_type = value.type;
                if (range_type == .reference) range_type = range_type.reference.target.*;
                if (sequenceElementType(range_type)) |range_element| {
                    if (typeEqual(range_element, element_type.?)) {
                        if (try self.isNonCopyableType(element_type.?)) {
                            return self.fail(argument.position, "appending a range would copy noncopyable elements; append them individually with 'move'");
                        }
                        if (value.type == .reference) {
                            value = try self.newExpression(.{
                                .type = range_type,
                                .position = argument.position,
                                .value = .{ .unary = .{ .operator = .dereference, .operand = value } },
                            });
                        }
                        resolved_operation = .append_range;
                        if (value.borrowed_parameter) {
                            if (assignmentRoot(call.object)) |root| switch (root) {
                                .self, .static => return self.fail(argument.position, "a read-reference parameter cannot be stored beyond its call"),
                                .variable => {},
                            };
                        }
                        if (expressionScopeDepth(call.object, scope) < value.lifetime_depth) {
                            return self.fail(argument.position, "capturing function value cannot be stored in a longer-lived collection");
                        }
                        updateDestinationLifetime(call.object, scope, value.lifetime_depth);
                        try arguments.append(self.allocator, value);
                        continue;
                    }
                }
            }
        }
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        try self.rejectUniqueOwnerArgument(value, argument.position);
        const stores_value = switch (operation) {
            .append, .prepend => true,
            .insert, .replace => index == 1,
            else => false,
        };
        if (stores_value and value.borrowed_parameter) {
            if (assignmentRoot(call.object)) |root| switch (root) {
                .self, .static => return self.fail(argument.position, "a read-reference parameter cannot be stored beyond its call"),
                .variable => {},
            };
        }
        if (stores_value and expressionScopeDepth(call.object, scope) < value.lifetime_depth) {
            return self.fail(argument.position, "capturing function value cannot be stored in a longer-lived collection");
        }
        if (stores_value) updateDestinationLifetime(call.object, scope, value.lifetime_depth);
        try arguments.append(self.allocator, value);
    }
    const result_type: Type = switch (operation) {
        .count => .int,
        .is_empty => .bool,
        .append, .append_range, .prepend, .insert, .swap, .reverse, .clear => .void,
        .take, .take_first, .take_last, .replace => element_type.?,
    };
    if (object.type == .str and operation == .count) {
        return self.newExpression(.{ .type = .int, .position = call.name_position, .value = .{ .string_length = object } });
    }
    return self.newExpression(.{
        .type = result_type,
        .position = call.name_position,
        .lifetime_depth = switch (operation) {
            .take, .take_first, .take_last, .replace => object.lifetime_depth,
            else => 0,
        },
        .value = .{ .collection_method = .{
            .object = object,
            .operation = resolved_operation,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .position = call.name_position,
        } },
    });
}

pub fn requireMutableCollectionReceiver(
    self: anytype,
    ast_object: *const Ast.Expression,
    object: *const Expression,
    scope: *const Scope,
    receiver: Receiver,
    position: Source.Position,
    method_name: []const u8,
) AnalyzeError!void {
    if (receiver == .immutable_field) {
        const message = try std.fmt.allocPrint(self.allocator, "cannot mutate through let field '{s}'", .{receiver.immutable_field});
        return self.fail(position, message);
    }
    if (self.immutableFieldInPlace(object)) |field_candidate| {
        const message = try std.fmt.allocPrint(self.allocator, "cannot mutate through let field '{s}'", .{field_candidate.symbol.source_name});
        return self.fail(position, message);
    }
    const root = assignmentRoot(ast_object) orelse return self.fail(position, "cannot call mutating collection method on a temporary value");
    switch (root) {
        .static => return,
        .self => {
            if (self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0) {
                return self.fail(position, "cannot mutate 'self' while one of its collections is iterated");
            }
            self.current_method_direct_mutation = true;
            return;
        },
        .variable => |name| {
            const symbol = findSymbol(scope, name) orelse return self.fail(position, "unknown collection receiver");
            if (symbol.mutability == .immutable) {
                const message = if (symbol.control_binding)
                    try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{name})
                else
                    try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on immutable value '{s}'", .{ method_name, name });
                return self.fail(position, message);
            }
            if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{name});
                return self.fail(position, message);
            }
        },
    }
}
