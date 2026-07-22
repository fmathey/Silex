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
pub fn resolveFunctionOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    arguments: []const *Ast.Expression,
    scope: *const Scope,
    candidates: []const FunctionSymbol,
) AnalyzeError!FunctionSymbol {
    var best: ?FunctionSymbol = null;
    var best_scores: ?[]const u8 = null;
    var ambiguous: std.ArrayList(FunctionSymbol) = .empty;
    for (candidates) |candidate| {
        const scores = try self.overloadScores(arguments, scope, candidate.parameter_types, candidate.parameter_modes);
        if (scores == null) continue;
        if (best == null) {
            best = candidate;
            best_scores = scores.?;
            continue;
        }
        if (overloadBetter(scores.?, best_scores.?)) {
            best = candidate;
            best_scores = scores.?;
            ambiguous.clearRetainingCapacity();
        } else if (!overloadBetter(best_scores.?, scores.?)) {
            if (ambiguous.items.len == 0) try ambiguous.append(self.allocator, best.?);
            try ambiguous.append(self.allocator, candidate);
        }
    }
    if (best == null) return self.noCompatibleFunctionOverload(name, position, candidates);
    if (ambiguous.items.len != 0) return self.ambiguousFunctionOverload(name, position, ambiguous.items);
    return best.?;
}

pub fn resolveMethodOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    arguments: []const *Ast.Expression,
    scope: *const Scope,
    candidates: []const MethodCandidate,
) AnalyzeError!MethodCandidate {
    var best: ?MethodCandidate = null;
    var best_scores: ?[]const u8 = null;
    var ambiguous: std.ArrayList(MethodCandidate) = .empty;
    for (candidates) |candidate| {
        const scores = try self.overloadScores(arguments, scope, candidate.symbol.parameter_types, candidate.symbol.parameter_modes);
        if (scores == null) continue;
        if (best == null) {
            best = candidate;
            best_scores = scores.?;
            continue;
        }
        if (overloadBetter(scores.?, best_scores.?)) {
            best = candidate;
            best_scores = scores.?;
            ambiguous.clearRetainingCapacity();
        } else if (!overloadBetter(best_scores.?, scores.?)) {
            if (ambiguous.items.len == 0) try ambiguous.append(self.allocator, best.?);
            try ambiguous.append(self.allocator, candidate);
        }
    }
    if (best == null) return self.noCompatibleMethodOverload(name, position, candidates);
    if (ambiguous.items.len != 0) return self.ambiguousMethodOverload(name, position, ambiguous.items);
    return best.?;
}

pub fn resolveConstructorOverload(
    self: anytype,
    class_name: []const u8,
    position: Source.Position,
    arguments: []const *Ast.Expression,
    scope: *const Scope,
    candidates: []const ConstructorCandidate,
) AnalyzeError!ConstructorCandidate {
    var best: ?ConstructorCandidate = null;
    var best_scores: ?[]const u8 = null;
    var ambiguous: std.ArrayList(ConstructorCandidate) = .empty;
    for (candidates) |candidate| {
        const scores = try self.overloadScores(arguments, scope, candidate.symbol.parameter_types, candidate.symbol.parameter_modes);
        if (scores == null) continue;
        if (best == null) {
            best = candidate;
            best_scores = scores.?;
            continue;
        }
        if (overloadBetter(scores.?, best_scores.?)) {
            best = candidate;
            best_scores = scores.?;
            ambiguous.clearRetainingCapacity();
        } else if (!overloadBetter(best_scores.?, scores.?)) {
            if (ambiguous.items.len == 0) try ambiguous.append(self.allocator, best.?);
            try ambiguous.append(self.allocator, candidate);
        }
    }
    if (best == null) {
        const signatures = try constructorSignatures(self.allocator, class_name, candidates);
        const message = try std.fmt.allocPrint(self.allocator, "no compatible constructor for '{s}'; visible constructors: {s}", .{ class_name, signatures });
        return self.fail(position, message);
    }
    if (ambiguous.items.len != 0) {
        const signatures = try constructorSignatures(self.allocator, class_name, ambiguous.items);
        const message = try std.fmt.allocPrint(self.allocator, "ambiguous constructor call for '{s}'; matching constructors: {s}", .{ class_name, signatures });
        return self.fail(position, message);
    }
    return best.?;
}

pub fn overloadScores(
    self: anytype,
    arguments: []const *Ast.Expression,
    scope: *const Scope,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
) AnalyzeError!?[]const u8 {
    if (arguments.len != parameter_types.len) return null;
    const owner_states = try self.snapshotOwnerStates(scope);
    defer restoreOwnerStates(owner_states);
    var scores: std.ArrayList(u8) = .empty;
    for (arguments, parameter_types, parameter_modes) |argument, parameter_type, parameter_mode| {
        if (argument.value == .borrow_expression) {
            return self.fail(argument.position, "reference arguments are selected by the parameter signature; pass the value without '@'");
        }
        if (argument.value == .unary and argument.value.unary.operator == .borrow) {
            return self.fail(argument.position, "reference arguments are selected by the parameter signature; pass the place without '&'");
        }
        const argument_value = if (argument.value == .null)
            try self.newExpression(.{ .type = .null, .position = argument.position, .value = .null })
        else if (parameter_mode == .mutable_reference and argument.value == .identifier and
            findSymbol(scope, argument.value.identifier) != null and
            findSymbol(scope, argument.value.identifier).?.unwrap_optional)
            try self.newExpression(.{
                .type = findSymbol(scope, argument.value.identifier).?.original_type.?,
                .position = argument.position,
                .value = .{ .variable = .{
                    .generated_name = findSymbol(scope, argument.value.identifier).?.generated_name,
                    .capture_box = &findSymbol(scope, argument.value.identifier).?.state.capture_box,
                } },
            })
        else
            try self.expressionForExpected(argument, scope, null);
        const effective_argument_type = if (argument_value.type == .reference and parameter_mode != .value)
            argument_value.type.reference.target.*
        else
            argument_value.type;
        if (argument_value.type == .reference and parameter_mode == .mutable_reference and !argument_value.type.reference.mutable) return null;
        const score = self.implicitConversionScore(effective_argument_type, parameter_type, argument_value.position.file) orelse literalOverloadScore(argument_value, parameter_type) orelse return null;
        try scores.append(self.allocator, score);
    }
    return @as(?[]const u8, try scores.toOwnedSlice(self.allocator));
}

pub fn noCompatibleFunctionOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    candidates: []const FunctionSymbol,
) AnalyzeError {
    const signatures = try functionSignatures(self.allocator, candidates);
    const message = try std.fmt.allocPrint(self.allocator, "no compatible signature for function '{s}'; visible signatures: {s}", .{ name, signatures });
    return self.fail(position, message);
}

pub fn ambiguousFunctionOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    candidates: []const FunctionSymbol,
) AnalyzeError {
    const signatures = try functionSignatures(self.allocator, candidates);
    const message = try std.fmt.allocPrint(self.allocator, "ambiguous call to function '{s}'; matching signatures: {s}", .{ name, signatures });
    return self.fail(position, message);
}

pub fn noCompatibleMethodOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    candidates: []const MethodCandidate,
) AnalyzeError {
    const signatures = try methodSignatures(self.allocator, candidates);
    const message = try std.fmt.allocPrint(self.allocator, "no compatible signature for method '{s}'; visible signatures: {s}", .{ name, signatures });
    return self.fail(position, message);
}

pub fn ambiguousMethodOverload(
    self: anytype,
    name: []const u8,
    position: Source.Position,
    candidates: []const MethodCandidate,
) AnalyzeError {
    const signatures = try methodSignatures(self.allocator, candidates);
    const message = try std.fmt.allocPrint(self.allocator, "ambiguous call to method '{s}'; matching signatures: {s}", .{ name, signatures });
    return self.fail(position, message);
}

pub fn findFunction(self: anytype, name: []const u8) ?FunctionSymbol {
    for (self.functions.items) |function_symbol| {
        if (std.mem.eql(u8, function_symbol.source_name, name)) return function_symbol;
    }
    return null;
}

pub fn isNativeModule(self: anytype, module_name: []const u8) bool {
    for (self.native_module_names) |candidate| {
        if (std.mem.eql(u8, candidate, module_name)) return true;
    }
    return false;
}

pub fn findStructure(self: anytype, name: []const u8) ?*const StructureSymbol {
    for (self.structures.items) |*structure| {
        if (std.mem.eql(u8, structure.source_name, name)) return structure;
    }
    return null;
}

pub fn findProtocol(self: anytype, name: []const u8) ?*const ProtocolSymbol {
    for (self.protocols.items) |*protocol| {
        if (std.mem.eql(u8, protocol.source_name, name)) return protocol;
    }
    return null;
}

pub fn findProtocolIndex(self: anytype, name: []const u8) ?usize {
    for (self.protocols.items, 0..) |protocol, index| {
        if (std.mem.eql(u8, protocol.source_name, name)) return index;
    }
    return null;
}

pub fn findEnum(self: anytype, name: []const u8) ?*const EnumSymbol {
    for (self.enums.items) |*enum_symbol| {
        if (std.mem.eql(u8, enum_symbol.source_name, name)) return enum_symbol;
    }
    return null;
}

pub fn findEnumByGeneratedName(self: anytype, name: []const u8) ?*const EnumSymbol {
    for (self.enums.items) |*enum_symbol| {
        if (std.mem.eql(u8, enum_symbol.generated_name, name)) return enum_symbol;
    }
    return null;
}

pub fn findStructureIndex(self: anytype, name: []const u8) ?usize {
    for (self.structures.items, 0..) |structure, index| {
        if (std.mem.eql(u8, structure.source_name, name)) return index;
    }
    return null;
}

pub fn findStructureIndexByGeneratedName(self: anytype, name: []const u8) ?usize {
    for (self.structures.items, 0..) |structure, index| {
        if (std.mem.eql(u8, structure.generated_name, name)) return index;
    }
    return null;
}

pub fn structureType(self: anytype, structure_index: usize) StructureType {
    const structure = self.structures.items[structure_index];
    return .{
        .source_name = structure.source_name,
        .generated_name = structure.generated_name,
        .is_class = structure.is_class,
        .is_owner = structure.is_owner,
    };
}

pub fn findFieldInHierarchy(self: anytype, structure_index: usize, name: []const u8) ?FieldCandidate {
    var declaring_index: ?usize = structure_index;
    while (declaring_index) |index| {
        const structure = self.structures.items[index];
        for (structure.fields) |field| {
            if (std.mem.eql(u8, field.source_name, name)) return .{
                .symbol = field,
                .structure_index = index,
            };
        }
        declaring_index = structure.base_index;
    }
    return null;
}

pub fn findStaticField(self: anytype, structure_index: usize, name: []const u8) ?StructureFieldSymbol {
    for (self.structures.items[structure_index].static_fields) |field| {
        if (std.mem.eql(u8, field.source_name, name)) return field;
    }
    return null;
}

pub fn findStaticFieldByGeneratedName(self: anytype, structure_index: usize, name: []const u8) ?StructureFieldSymbol {
    for (self.structures.items[structure_index].static_fields) |field| {
        if (std.mem.eql(u8, field.generated_name, name)) return field;
    }
    return null;
}

pub fn findFieldByGeneratedName(self: anytype, structure_index: usize, name: []const u8) ?FieldCandidate {
    var declaring_index: ?usize = structure_index;
    while (declaring_index) |index| {
        const structure = self.structures.items[index];
        for (structure.fields) |field| {
            if (std.mem.eql(u8, field.generated_name, name)) return .{
                .symbol = field,
                .structure_index = index,
            };
        }
        declaring_index = structure.base_index;
    }
    return null;
}

pub fn immutableFieldInPlace(self: anytype, expression_value: *const Expression) ?FieldCandidate {
    return switch (expression_value.value) {
        .static_field_access => |access| field: {
            const structure_index = self.findStructureIndexByGeneratedName(access.owner_generated_name) orelse break :field null;
            const field = self.findStaticFieldByGeneratedName(structure_index, access.generated_name) orelse break :field null;
            break :field if (field.mutability == .immutable) .{ .symbol = field, .structure_index = structure_index } else null;
        },
        .member_access, .bound_function => |member| field: {
            if (self.immutableFieldInPlace(member.object)) |candidate| break :field candidate;
            if (member.object.type != .structure) break :field null;
            const structure_index = self.findStructureIndexByGeneratedName(member.object.type.structure.generated_name) orelse break :field null;
            const candidate = self.findFieldByGeneratedName(structure_index, member.generated_name) orelse break :field null;
            break :field if (candidate.symbol.mutability == .immutable) candidate else null;
        },
        .index_access => |access| self.immutableFieldInPlace(access.object),
        .slice_access => |access| self.immutableFieldInPlace(access.object),
        .unary => |unary| self.immutableFieldInPlace(unary.operand),
        else => null,
    };
}

pub fn implicitBaseInitialization(self: anytype, structure_index: usize) AnalyzeError!ImplicitBaseInitialization {
    const structure = self.structures.items[structure_index];
    const base_index = structure.base_index orelse return .{ .available = true, .initializer = null };
    const base = self.structures.items[base_index];

    if (base.constructors.len != 0) {
        for (base.constructors) |constructor_symbol| {
            if (constructor_symbol.parameter_types.len == 0 and
                self.memberVisibleFrom(structure_index, base_index, constructor_symbol.visibility))
            {
                return .{
                    .available = true,
                    .initializer = .{ .generated_name = base.generated_name, .arguments = &.{} },
                };
            }
        }
        return .{ .available = false, .initializer = null };
    }

    const base_chain = try self.implicitBaseInitialization(base_index);
    if (!base_chain.available) return .{ .available = false, .initializer = null };

    var arguments: std.ArrayList(*Expression) = .empty;
    for (base.fields) |field| {
        const value = if (field.default_value) |default_value|
            default_value
        else
            try self.intrinsicDefaultExpression(field.type, field.position) orelse
                return .{ .available = false, .initializer = null };
        try arguments.append(self.allocator, value);
    }
    return .{
        .available = true,
        .initializer = .{
            .generated_name = base.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        },
    };
}

pub fn memberVisibleFromCurrentContext(
    self: anytype,
    structure_index: usize,
    visibility: Ast.MemberVisibility,
) bool {
    if (self.current_extension) return visibility == .public_access;
    const current_index = self.current_structure_index orelse return visibility == .public_access;
    return self.memberVisibleFrom(current_index, structure_index, visibility);
}

pub fn memberVisibleFrom(
    self: anytype,
    current_index: usize,
    declaring_index: usize,
    visibility: Ast.MemberVisibility,
) bool {
    return switch (visibility) {
        .public_access => true,
        .private_access => current_index == declaring_index,
        .subclass => current_index == declaring_index or self.isDescendantOf(current_index, declaring_index),
    };
}

pub fn isDescendantOf(self: anytype, candidate_index: usize, ancestor_index: usize) bool {
    var base_index = self.structures.items[candidate_index].base_index;
    while (base_index) |index| {
        if (index == ancestor_index) return true;
        base_index = self.structures.items[index].base_index;
    }
    return false;
}

pub fn requireFieldAccess(
    self: anytype,
    structure_index: usize,
    structure: *const StructureSymbol,
    field: StructureFieldSymbol,
    position: Source.Position,
) AnalyzeError!void {
    if (structure.is_owner and !self.uniqueOwnerStorageVisible(structure, position.file)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "field '{s}' of unique resource struct '{s}' is private to its module",
            .{ field.source_name, structure.source_name },
        );
        return self.fail(position, message);
    }
    if (self.memberVisibleFromCurrentContext(structure_index, field.visibility)) return;
    return self.failMemberAccess("field", structure, field.source_name, field.visibility, position);
}

pub fn uniqueOwnerStorageVisible(self: anytype, structure: *const StructureSymbol, source_file: usize) bool {
    if (self.current_extension) return false;
    if (structure.module_files.len == 0) return source_file == structure.position.file;
    return fileSetContains(structure.module_files, source_file);
}

pub fn failMemberAccess(
    self: anytype,
    member_kind: []const u8,
    structure: *const StructureSymbol,
    member_name: []const u8,
    visibility: Ast.MemberVisibility,
    position: Source.Position,
) AnalyzeError {
    const message = switch (visibility) {
        .private_access => try std.fmt.allocPrint(
            self.allocator,
            "{s} '{s}' is private in {s} '{s}'",
            .{ member_kind, member_name, if (structure.is_class) "class" else "struct", structure.source_name },
        ),
        .subclass => try std.fmt.allocPrint(
            self.allocator,
            "{s} '{s}' is accessible only from class '{s}' and its descendants",
            .{ member_kind, member_name, structure.source_name },
        ),
        .public_access => unreachable,
    };
    return self.fail(position, message);
}

pub fn structureInitializerExpression(
    self: anytype,
    initializer: Ast.Expression.StructureInitializer,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const structure = self.findStructure(initializer.name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown struct '{s}'", .{initializer.name});
        return self.fail(initializer.name_position, message);
    };
    const structure_index = self.findStructureIndexByGeneratedName(structure.generated_name).?;
    if (structure.is_native_resource) {
        const message = try std.fmt.allocPrint(self.allocator, "native resource '{s}' cannot be constructed in Silex", .{structure.source_name});
        return self.fail(initializer.name_position, message);
    }
    if (structure.is_owner and !self.uniqueOwnerStorageVisible(structure, initializer.name_position.file)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "initializer of unique resource struct '{s}' is private to its module",
            .{structure.source_name},
        );
        return self.fail(initializer.name_position, message);
    }
    if (!structure.is_class) {
        var has_private_field = false;
        for (structure.fields) |field| {
            if (field.visibility == .private_access) {
                has_private_field = true;
                break;
            }
        }
        if (has_private_field and !self.memberVisibleFromCurrentContext(structure_index, .private_access)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "initializer of struct '{s}' is private because it declares private fields",
                .{structure.source_name},
            );
            return self.fail(initializer.name_position, message);
        }
    }
    if (structure.constructors.len != 0) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "{s} '{s}' declares custom constructors and cannot use a named field initializer",
            .{ if (structure.is_class) "class" else "struct", structure.source_name },
        );
        return self.fail(initializer.name_position, message);
    }
    if (structure.is_class) {
        const implicit = try self.implicitBaseInitialization(structure_index);
        if (!implicit.available) {
            const base = self.structures.items[structure.base_index.?];
            const message = try std.fmt.allocPrint(
                self.allocator,
                "class '{s}' cannot use its named initializer because base class '{s}' has no accessible 'super()' construction",
                .{ structure.source_name, base.source_name },
            );
            return self.fail(initializer.name_position, message);
        }
    }
    for (initializer.fields, 0..) |field, field_index| {
        var known: ?StructureFieldSymbol = null;
        for (structure.fields) |expected_field| {
            if (std.mem.eql(u8, field.name, expected_field.source_name)) known = expected_field;
        }
        if (known == null) {
            const message = try std.fmt.allocPrint(self.allocator, "unknown field '{s}' in {s} '{s}'", .{ field.name, if (structure.is_class) "class" else "struct", initializer.name });
            return self.fail(field.position, message);
        }
        try self.requireFieldAccess(structure_index, structure, known.?, field.position);
        for (initializer.fields[0..field_index]) |previous| {
            if (std.mem.eql(u8, previous.name, field.name)) {
                const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is initialized more than once", .{field.name});
                return self.fail(field.position, message);
            }
        }
    }

    var values: std.ArrayList(*Expression) = .empty;
    var deferred_resource_paths: std.ArrayList(DeferredResourcePath) = .empty;
    var lifetime_depth: usize = 0;
    for (structure.fields) |expected_field| {
        var matching: ?Ast.Expression.FieldInitializer = null;
        for (initializer.fields) |field| {
            if (std.mem.eql(u8, field.name, expected_field.source_name)) {
                matching = field;
            }
        }
        var value = if (matching) |field|
            try self.expressionForExpected(field.value, scope, expected_field.type)
        else if (expected_field.default_value) |default_value|
            default_value
        else if (structure.is_class)
            try self.intrinsicDefaultExpression(expected_field.type, initializer.name_position) orelse {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "class '{s}' requires field '{s}'",
                    .{ structure.source_name, expected_field.source_name },
                );
                return self.fail(initializer.name_position, message);
            }
        else
            try self.defaultExpression(expected_field.type, initializer.name_position);
        value = try self.coerce(value, expected_field.type);
        if (!typeEqual(value.type, expected_field.type)) {
            const message = try typeMismatchMessage(self.allocator, expected_field.type, value.type);
            const position = if (matching) |field| field.value.position else initializer.name_position;
            return self.fail(position, message);
        }
        if (expected_field.type == .function and expected_field.type.function.owner != null and
            value.type.function.owner == null)
        {
            value = try self.newExpression(.{
                .type = expected_field.type,
                .position = value.position,
                .lifetime_depth = value.lifetime_depth,
                .value = .{ .adapt_function = value },
            });
        }
        if (matching) |field| try self.rejectUniqueOwnerArgument(value, field.value.position);
        try values.append(self.allocator, value);
        for (value.deferred_resource_paths) |path| {
            const prefixed = try self.allocator.alloc([]const u8, path.len + 1);
            prefixed[0] = expected_field.generated_name;
            @memcpy(prefixed[1..], path);
            try deferred_resource_paths.append(self.allocator, prefixed);
        }
        lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
    }
    return self.newExpression(.{
        .type = .{ .structure = self.structureType(structure_index) },
        .position = initializer.name_position,
        .lifetime_depth = lifetime_depth,
        .deferred_resource_paths = try deferred_resource_paths.toOwnedSlice(self.allocator),
        .value = .{ .structure_initializer = .{
            .generated_name = structure.generated_name,
            .fields = try values.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn classInitializerExpression(
    self: anytype,
    initializer: Ast.Expression.ClassInitializer,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const structure = self.findStructure(initializer.name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown type '{s}'", .{initializer.name});
        return self.fail(initializer.name_position, message);
    };
    if (structure.constructors.len == 0) {
        if (initializer.arguments.len != 0) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "{s} '{s}' requires named fields such as 'field:value'",
                .{ if (structure.is_class) "class" else "struct", structure.source_name },
            );
            return self.fail(initializer.name_position, message);
        }
        return self.structureInitializerExpression(.{
            .name = initializer.name,
            .name_position = initializer.name_position,
            .fields = &.{},
        }, scope);
    }

    const structure_index = self.findStructureIndexByGeneratedName(structure.generated_name).?;
    var candidates: std.ArrayList(ConstructorCandidate) = .empty;
    var inaccessible: ?ConstructorSymbol = null;
    for (structure.constructors, 0..) |constructor_symbol, index| {
        if (self.memberVisibleFromCurrentContext(structure_index, constructor_symbol.visibility)) {
            try candidates.append(self.allocator, .{ .symbol = constructor_symbol, .index = index });
        } else {
            inaccessible = constructor_symbol;
        }
    }
    if (candidates.items.len == 0) {
        const constructor_symbol = inaccessible.?;
        const message = switch (constructor_symbol.visibility) {
            .private_access => try std.fmt.allocPrint(
                self.allocator,
                "constructor of {s} '{s}' is private",
                .{ if (structure.is_class) "class" else "struct", structure.source_name },
            ),
            .subclass => try std.fmt.allocPrint(self.allocator, "constructor of class '{s}' is accessible only from that class and its descendants", .{structure.source_name}),
            .public_access => unreachable,
        };
        return self.fail(initializer.name_position, message);
    }
    const resolved = try self.resolveConstructorOverload(structure.source_name, initializer.name_position, initializer.arguments, scope, candidates.items);
    const constructor_symbol = resolved.symbol;
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    var lifetime_depth: usize = 0;
    for (initializer.arguments, constructor_symbol.parameter_types, constructor_symbol.parameter_modes, constructor_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of constructor '{s}' expects '{s}', found '{s}'", .{ index + 1, structure.source_name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and value.lifetime_depth != 0) {
            return self.fail(argument.position, "capturing callback cannot be passed to a constructor parameter whose value escapes the call");
        }
        try arguments.append(self.allocator, value);
        try self.retainTransientBorrow(&transient_borrows, value);
        lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
    }
    return self.newExpression(.{
        .type = .{ .structure = self.structureType(structure_index) },
        .position = initializer.name_position,
        .lifetime_depth = lifetime_depth,
        .value = .{ .class_initializer = .{
            .generated_name = structure.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } },
    });
}

pub fn memberAccessExpression(
    self: anytype,
    member: Ast.Expression.MemberAccess,
    scope: *const Scope,
) AnalyzeError!*Expression {
    return self.memberAccessExpressionRaw(member, scope, true);
}

pub fn memberAccessExpressionRaw(
    self: anytype,
    member: Ast.Expression.MemberAccess,
    scope: *const Scope,
    bind_function: bool,
) AnalyzeError!*Expression {
    const object = try self.expression(member.object, scope);
    return self.memberAccessExpressionWithObject(member, object, scope, bind_function);
}

pub fn memberAccessExpressionWithObject(
    self: anytype,
    member: Ast.Expression.MemberAccess,
    object: *Expression,
    scope: *const Scope,
    bind_function: bool,
) AnalyzeError!*Expression {
    if (object.type == .enumeration) {
        const enum_symbol = self.findEnumByGeneratedName(object.type.enumeration.generated_name).?;
        if (!std.mem.eql(u8, member.name, "raw_value")) {
            const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' has no property '{s}'", .{ enum_symbol.source_name, member.name });
            return self.fail(member.name_position, message);
        }
        const raw_type = enum_symbol.raw_type orelse {
            const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' has no raw value", .{enum_symbol.source_name});
            return self.fail(member.name_position, message);
        };
        return self.newExpression(.{
            .type = raw_type,
            .position = member.name_position,
            .lifetime_depth = object.lifetime_depth,
            .value = .{ .enum_raw_value = object },
        });
    }
    const object_target_type = if (object.type == .reference) object.type.reference.target.* else object.type;
    const generated_structure_name = switch (object_target_type) {
        .structure => |structure_type| structure_type.generated_name,
        else => return self.fail(member.name_position, "member access requires a struct or class value"),
    };
    const structure = self.findStructureByGeneratedName(generated_structure_name).?;
    const structure_index = self.findStructureIndexByGeneratedName(generated_structure_name).?;
    if (self.findFieldInHierarchy(structure_index, member.name)) |field_candidate| {
        const declaring_structure = &self.structures.items[field_candidate.structure_index];
        const field = field_candidate.symbol;
        try self.requireFieldAccess(field_candidate.structure_index, declaring_structure, field, member.name_position);
        if (bind_function and field.type == .function and field.type.function.owner != null) {
            var bound_type = field.type;
            bound_type.function.owner = null;
            return self.newExpression(.{
                .type = bound_type,
                .position = member.name_position,
                .lifetime_depth = expressionScopeDepth(member.object, scope),
                .value = .{ .bound_function = .{
                    .object = object,
                    .generated_name = field.generated_name,
                } },
            });
        }
        return self.newExpression(.{
            .type = field.type,
            .position = member.name_position,
            .lifetime_depth = object.lifetime_depth,
            .borrowed_parameter = object.borrowed_parameter,
            .deferred_resource_paths = try self.projectDeferredResourcePaths(object.deferred_resource_paths, field.generated_name),
            .deferred_storage_state = object.deferred_storage_state,
            .deferred_storage_path = try self.appendDeferredStoragePath(object.deferred_storage_path, field.generated_name),
            .value = .{ .member_access = .{
                .object = object,
                .generated_name = field.generated_name,
            } },
        });
    }
    if (self.findStaticField(structure_index, member.name) != null) {
        const message = try std.fmt.allocPrint(self.allocator, "static field '{s}' must be accessed through type '{s}'", .{ member.name, structure.source_name });
        return self.fail(member.name_position, message);
    }
    const message = try std.fmt.allocPrint(self.allocator, "{s} '{s}' has no field '{s}'", .{ if (structure.is_class) "class" else "struct", structure.source_name, member.name });
    return self.fail(member.name_position, message);
}

pub fn safeMemberAccessExpression(
    self: anytype,
    member: Ast.Expression.SafeMemberAccess,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (member.named_fields != null) return self.fail(member.name_position, "safe method calls do not accept named fields");
    const receiver = try self.expression(member.object, scope);
    if (receiver.type != .optional) return self.fail(member.name_position, "safe access requires an optional receiver");
    const unwrapped = try self.newExpression(.{
        .type = receiver.type.optional.*,
        .position = member.object.position,
        .lifetime_depth = receiver.lifetime_depth,
        .value = .{ .optional_unwrap = .{ .generated_name = "silexOptionalValue", .capture_box = &never_capture_box } },
    });
    const end = if (member.arguments) |arguments| method: {
        var method_receiver = receiverFor(member.object, scope, false);
        if (self.immutableFieldInPlace(receiver)) |field_candidate| method_receiver = .{ .immutable_field = field_candidate.symbol.source_name };
        break :method try self.methodCallExpressionWithObject(.{
            .object = member.object,
            .name = member.name,
            .name_position = member.name_position,
            .arguments = arguments,
        }, unwrapped, scope, method_receiver, false);
    } else try self.memberAccessExpressionWithObject(.{
        .object = member.object,
        .name = member.name,
        .name_position = member.name_position,
    }, unwrapped, scope, true);
    const result_type = if (end.type == .void or end.type == .optional)
        end.type
    else
        try self.optionalType(end.type);
    return self.newExpression(.{
        .type = result_type,
        .position = member.name_position,
        .lifetime_depth = receiver.lifetime_depth,
        .value = .{ .safe_access = .{ .receiver = receiver, .end = end } },
    });
}

pub fn indexAccessExpression(
    self: anytype,
    access: Ast.Expression.IndexAccess,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const object = try self.expression(access.object, scope);
    const indexed_type = if (object.type == .reference) object.type.reference.target.* else object.type;
    const element_type: Type = switch (indexed_type) {
        .list => |element| element.*,
        .fixed_array => |array| array.element.*,
        .view => |element| element.*,
        else => return self.fail(access.bracket_position, "indexed access requires an array or list value"),
    };
    var index = try self.expressionForExpected(access.index, scope, .int);
    index = try self.coerce(index, .int);
    if (!typeEqual(index.type, .int)) {
        const message = try std.fmt.allocPrint(self.allocator, "collection index expects 'int', found '{s}'", .{typeName(index.type)});
        return self.fail(access.index.position, message);
    }
    return self.newExpression(.{
        .type = element_type,
        .position = access.bracket_position,
        .lifetime_depth = object.lifetime_depth,
        .borrowed_parameter = object.borrowed_parameter,
        .value = .{ .index_access = .{
            .object = object,
            .index = index,
        } },
    });
}

pub fn sliceAccessExpression(
    self: anytype,
    access: Ast.Expression.SliceAccess,
    scope: *const Scope,
    borrowed: bool,
) AnalyzeError!*Expression {
    const object = try self.expression(access.object, scope);
    const sliced_type = if (object.type == .reference) object.type.reference.target.* else object.type;
    const element_type: Type = switch (sliced_type) {
        .list => |element| element.*,
        .fixed_array => |array| array.element.*,
        .view => |element| element.*,
        else => return self.fail(access.bracket_position, "collection slice requires an array or list value"),
    };
    var start = try self.expressionForExpected(access.start, scope, .int);
    start = try self.coerce(start, .int);
    if (!typeEqual(start.type, .int)) {
        const message = try std.fmt.allocPrint(self.allocator, "collection slice start expects 'int', found '{s}'", .{typeName(start.type)});
        return self.fail(access.start.position, message);
    }
    var end = try self.expressionForExpected(access.end, scope, .int);
    end = try self.coerce(end, .int);
    if (!typeEqual(end.type, .int)) {
        const message = try std.fmt.allocPrint(self.allocator, "collection slice end expects 'int', found '{s}'", .{typeName(end.type)});
        return self.fail(access.end.position, message);
    }
    const element = try self.allocator.create(Type);
    element.* = element_type;
    return self.newExpression(.{
        .type = if (borrowed) .{ .view = element } else .{ .list = element },
        .position = access.bracket_position,
        .value = .{ .slice_access = .{
            .object = object,
            .start = start,
            .end = end,
            .borrowed = borrowed,
        } },
    });
}

pub fn findStructureByGeneratedName(self: anytype, name: []const u8) ?*const StructureSymbol {
    for (self.structures.items) |*structure| {
        if (std.mem.eql(u8, structure.generated_name, name)) return structure;
    }
    return null;
}

pub fn validateParameterMode(
    self: anytype,
    type_value: Type,
    mode: Ast.ParameterMode,
    position: Source.Position,
    is_native: bool,
) AnalyzeError!void {
    try self.rejectUniqueOwnerComposition(type_value, true, position);
    if (type_value == .function and type_value.function.deferred and !is_native) {
        return self.fail(position, "a 'deferred func' parameter is only valid in a native registration function");
    }
    if (mode == .value) {
        if (type_value == .view) return self.fail(position, "a view type must be borrowed as '@T[..]' or '&T[..]'");
        return;
    }
    if (is_native and mode == .borrow and !self.isNativeResourceType(type_value) and type_value != .view) return self.fail(position, "a native function cannot declare an '@T' parameter");
    if (type_value == .structure and type_value.structure.is_class) {
        if (mode == .mutable_reference) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "class '{s}' already has reference semantics; '&{s}' is invalid",
                .{ type_value.structure.source_name, type_value.structure.source_name },
            );
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(
            self.allocator,
            "class '{s}' already has shared identity; parameter mode '@' is invalid",
            .{type_value.structure.source_name},
        );
        return self.fail(position, message);
    }
    if (type_value == .protocol and mode == .borrow) {
        return self.fail(position, "a dynamic protocol value cannot use parameter mode '@'");
    }
}

pub fn rejectUniqueOwnerArgument(
    self: anytype,
    value: *const Expression,
    position: Source.Position,
) AnalyzeError!void {
    if (!try self.isNonCopyableType(value.type) or self.isNonCopyableTemporary(value)) return;
    const message = try std.fmt.allocPrint(
        self.allocator,
        "noncopyable value '{s}' must be passed with 'move'",
        .{typeName(value.type)},
    );
    return self.fail(position, message);
}

pub fn rejectUniqueOwnerComposition(
    self: anytype,
    type_value: Type,
    allow_direct_owner: bool,
    position: Source.Position,
) AnalyzeError!void {
    if (!containsDeferredCallback(type_value)) return;
    if (allow_direct_owner and type_value == .function and type_value.function.deferred) return;
    return self.fail(position, "a 'deferred func' cannot be stored in another type");
}

pub fn uniqueOwnerCause(self: anytype, type_value: Type) Allocator.Error!?StructureType {
    var visiting = std.StringHashMap(void).init(self.allocator);
    defer visiting.deinit();
    return self.uniqueOwnerCauseInner(type_value, &visiting);
}

pub fn isNonCopyableType(self: anytype, type_value: Type) Allocator.Error!bool {
    if (type_value == .function and type_value.function.deferred) return true;
    return (try self.uniqueOwnerCause(type_value)) != null;
}

pub fn isNonCopyableTemporary(self: anytype, expression_value: *const Expression) bool {
    return switch (expression_value.value) {
        .move_expression,
        .lambda,
        .structure_initializer,
        .enum_initializer,
        .sequence_literal,
        .call,
        .value_call,
        .method_call,
        .static_method_call,
        .class_initializer,
        .match_expression,
        .try_expression,
        .collection_method,
        => true,
        .optional_wrap => |value| self.isNonCopyableTemporary(value),
        else => false,
    };
}

pub fn uniqueOwnerCauseInner(
    self: anytype,
    type_value: Type,
    visiting: *std.StringHashMap(void),
) Allocator.Error!?StructureType {
    return switch (type_value) {
        .optional => |contained| self.uniqueOwnerCauseInner(contained.*, visiting),
        .list => |element| self.uniqueOwnerCauseInner(element.*, visiting),
        .fixed_array => |array| self.uniqueOwnerCauseInner(array.element.*, visiting),
        .enumeration => |enum_type| enumeration: {
            if (visiting.contains(enum_type.generated_name)) break :enumeration null;
            try visiting.put(enum_type.generated_name, {});
            defer _ = visiting.remove(enum_type.generated_name);
            const enum_symbol = self.findEnumByGeneratedName(enum_type.generated_name) orelse break :enumeration null;
            for (enum_symbol.variants) |variant| for (variant.associated_types) |associated_type| {
                if (try self.uniqueOwnerCauseInner(associated_type, visiting)) |owner| break :enumeration owner;
            };
            break :enumeration null;
        },
        .structure => |structure_type| structure: {
            if (structure_type.is_owner) break :structure structure_type;
            if (structure_type.is_class or visiting.contains(structure_type.generated_name)) break :structure null;
            try visiting.put(structure_type.generated_name, {});
            defer _ = visiting.remove(structure_type.generated_name);
            const structure_symbol = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :structure null;
            for (structure_symbol.fields) |field| {
                if (try self.uniqueOwnerCauseInner(field.type, visiting)) |owner| break :structure owner;
            }
            break :structure null;
        },
        else => null,
    };
}

pub fn isEqualityComparable(self: anytype, type_value: Type) bool {
    return switch (type_value) {
        .function, .reference, .protocol, .enumeration, .void, .null => false,
        .optional => |contained| self.isEqualityComparable(contained.*),
        .list => |element| self.isEqualityComparable(element.*),
        .fixed_array => |array| self.isEqualityComparable(array.element.*),
        .structure => |structure_type| comparable: {
            if (structure_type.is_owner) break :comparable false;
            const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :comparable false;
            if (structure.is_class) break :comparable true;
            for (structure.fields) |field| if (!self.isEqualityComparable(field.type)) break :comparable false;
            break :comparable true;
        },
        else => true,
    };
}

pub fn requireIndependentLetType(
    self: anytype,
    type_value: Type,
    position: Source.Position,
) AnalyzeError!void {
    var field_path: std.ArrayList([]const u8) = .empty;
    defer field_path.deinit(self.allocator);
    var visiting = std.StringHashMap(void).init(self.allocator);
    defer visiting.deinit();
    const cause = try self.nonIndependentType(type_value, &field_path, &visiting) orelse return;
    const declared_name = try allocatedTypeName(self.allocator, type_value);
    const cause_name = try allocatedTypeName(self.allocator, cause);
    const message = if (field_path.items.len == 0)
        try std.fmt.allocPrint(
            self.allocator,
            "type '{s}' is not an independent value and cannot be bound with 'let'; use 'var'",
            .{declared_name},
        )
    else
        try std.fmt.allocPrint(
            self.allocator,
            "type '{s}' is not an independent value because field '{s}' reaches '{s}'; use 'var'",
            .{ declared_name, try std.mem.join(self.allocator, ".", field_path.items), cause_name },
        );
    return self.fail(position, message);
}

pub fn nonIndependentType(
    self: anytype,
    type_value: Type,
    field_path: *std.ArrayList([]const u8),
    visiting: *std.StringHashMap(void),
) Allocator.Error!?Type {
    return switch (type_value) {
        .function, .reference, .protocol => type_value,
        .optional => |contained| self.nonIndependentType(contained.*, field_path, visiting),
        .list => |element| self.nonIndependentType(element.*, field_path, visiting),
        .fixed_array => |array| self.nonIndependentType(array.element.*, field_path, visiting),
        .enumeration => |enum_type| enumeration: {
            if (visiting.contains(enum_type.generated_name)) break :enumeration null;
            try visiting.put(enum_type.generated_name, {});
            defer _ = visiting.remove(enum_type.generated_name);
            const enum_symbol = self.findEnumByGeneratedName(enum_type.generated_name) orelse break :enumeration type_value;
            for (enum_symbol.variants) |variant| {
                for (variant.associated_types, 0..) |associated_type, index| {
                    try field_path.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}[{d}]", .{ variant.source_name, index + 1 }));
                    if (try self.nonIndependentType(associated_type, field_path, visiting)) |cause| break :enumeration cause;
                    _ = field_path.pop();
                }
            }
            break :enumeration null;
        },
        .structure => |structure_type| structure: {
            if (structure_type.is_class) break :structure type_value;
            if (visiting.contains(structure_type.generated_name)) break :structure null;
            try visiting.put(structure_type.generated_name, {});
            defer _ = visiting.remove(structure_type.generated_name);

            const structure_symbol = self.findStructureByGeneratedName(structure_type.generated_name) orelse
                break :structure type_value;
            for (structure_symbol.fields) |field| {
                try field_path.append(self.allocator, field.source_name);
                if (try self.nonIndependentType(field.type, field_path, visiting)) |cause| {
                    break :structure cause;
                }
                _ = field_path.pop();
            }
            break :structure null;
        },
        .void, .null => type_value,
        else => null,
    };
}
