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
pub fn classUpcastDistance(self: anytype, source: Type, target: Type) ?u8 {
    if (source != .structure or target != .structure or !source.structure.is_class or !target.structure.is_class) return null;
    const source_index = self.findStructureIndexByGeneratedName(source.structure.generated_name) orelse return null;
    const target_index = self.findStructureIndexByGeneratedName(target.structure.generated_name) orelse return null;
    var distance: u8 = 0;
    var cursor: ?usize = source_index;
    while (cursor) |index| {
        if (index == target_index) return distance;
        distance +|= 1;
        cursor = self.structures.items[index].base_index;
    }
    return null;
}

pub fn implicitConversionScore(self: anytype, source: Type, target: Type, source_file: usize) ?u8 {
    if (typeEqual(source, target)) return 0;
    if (target == .protocol and source == .structure) {
        const structure_index = self.findStructureIndexByGeneratedName(source.structure.generated_name) orelse return null;
        if (self.structureConformsToProtocol(structure_index, target.protocol.index, source_file)) return 1;
    }
    if (target == .optional) {
        if (source == .null) return 3;
        if (source == .optional) return self.implicitConversionScore(source.optional.*, target.optional.*, source_file);
        const score = self.implicitConversionScore(source, target.optional.*, source_file) orelse return null;
        return score +| 3;
    }
    if (self.classUpcastDistance(source, target)) |distance| return distance;
    return overloadScore(source, target);
}

pub fn optionalType(self: anytype, contained_type: Type) Allocator.Error!Type {
    const contained = try self.allocator.create(Type);
    contained.* = contained_type;
    return .{ .optional = contained };
}

pub fn newExpression(self: anytype, value: Expression) !*Expression {
    const result = try self.allocator.create(Expression);
    result.* = value;
    return result;
}

pub fn projectDeferredResourcePaths(
    self: anytype,
    paths: []const DeferredResourcePath,
    field_name: []const u8,
) Allocator.Error![]const DeferredResourcePath {
    var projected: std.ArrayList(DeferredResourcePath) = .empty;
    for (paths) |path| {
        if (path.len == 0 or !std.mem.eql(u8, path[0], field_name)) continue;
        try projected.append(self.allocator, path[1..]);
    }
    return projected.toOwnedSlice(self.allocator);
}

pub fn appendDeferredStoragePath(
    self: anytype,
    path: DeferredResourcePath,
    field_name: []const u8,
) Allocator.Error!DeferredResourcePath {
    const appended = try self.allocator.alloc([]const u8, path.len + 1);
    @memcpy(appended[0..path.len], path);
    appended[path.len] = field_name;
    return appended;
}

pub fn replacedDeferredResourcePaths(
    self: anytype,
    existing: []const DeferredResourcePath,
    destination: DeferredResourcePath,
    replacement: []const DeferredResourcePath,
) Allocator.Error![]const DeferredResourcePath {
    var paths: std.ArrayList(DeferredResourcePath) = .empty;
    for (existing) |path| {
        if (!deferredResourcePathStartsWith(path, destination)) try paths.append(self.allocator, path);
    }
    for (replacement) |path| {
        const prefixed = try self.allocator.alloc([]const u8, destination.len + path.len);
        @memcpy(prefixed[0..destination.len], destination);
        @memcpy(prefixed[destination.len..], path);
        try paths.append(self.allocator, prefixed);
    }
    return paths.toOwnedSlice(self.allocator);
}

pub fn recordLambdaCapture(
    self: anytype,
    lambda: *LambdaContext,
    generated_name: []const u8,
    by_value: bool,
) !void {
    for (lambda.captures.items) |capture| {
        if (std.mem.eql(u8, capture.generated_name, generated_name)) return;
    }
    try lambda.captures.append(self.allocator, .{ .generated_name = generated_name, .by_value = by_value });
}

pub fn recordSymbolCapture(self: anytype, symbol: *const Symbol, position: Source.Position) !void {
    var lambda_context = self.current_lambda;
    while (lambda_context) |lambda| : (lambda_context = lambda.parent) {
        if (symbol.scope_depth < lambda.local_depth) {
            if (symbol.state.borrowed_parameter) {
                return self.fail(position, "a read-reference parameter cannot be captured by a lambda");
            }
            if (try self.isNonCopyableType(symbol.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "noncopyable value '{s}' cannot be captured by a lambda",
                    .{typeName(symbol.type)},
                );
                return self.fail(position, message);
            }
            const by_value = try self.typeContainsClass(symbol.type);
            if (by_value) symbol.state.capture_box = true;
            try self.recordLambdaCapture(lambda, symbol.generated_name, by_value);
            lambda.lifetime_depth = @max(lambda.lifetime_depth, symbol.scope_depth);
        }
    }
}

pub fn typeContainsClass(self: anytype, type_value: Type) Allocator.Error!bool {
    var visiting = std.StringHashMap(void).init(self.allocator);
    defer visiting.deinit();
    return self.typeContainsClassInner(type_value, &visiting);
}

pub fn typeContainsClassInner(
    self: anytype,
    type_value: Type,
    visiting: *std.StringHashMap(void),
) Allocator.Error!bool {
    return switch (type_value) {
        .protocol => true,
        .optional => |contained| self.typeContainsClassInner(contained.*, visiting),
        .list => |element| self.typeContainsClassInner(element.*, visiting),
        .fixed_array => |array| self.typeContainsClassInner(array.element.*, visiting),
        .enumeration => |enum_type| contains: {
            if (visiting.contains(enum_type.generated_name)) break :contains false;
            try visiting.put(enum_type.generated_name, {});
            defer _ = visiting.remove(enum_type.generated_name);
            const enum_symbol = self.findEnumByGeneratedName(enum_type.generated_name) orelse break :contains false;
            for (enum_symbol.variants) |variant| for (variant.associated_types) |associated_type| {
                if (try self.typeContainsClassInner(associated_type, visiting)) break :contains true;
            };
            break :contains false;
        },
        .structure => |structure_type| contains: {
            if (structure_type.is_class) break :contains true;
            if (visiting.contains(structure_type.generated_name)) break :contains false;
            try visiting.put(structure_type.generated_name, {});
            defer _ = visiting.remove(structure_type.generated_name);
            const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :contains false;
            for (structure.fields) |field| {
                if (try self.typeContainsClassInner(field.type, visiting)) break :contains true;
            }
            break :contains false;
        },
        else => false,
    };
}

pub fn newBindingState(self: anytype, type_value: Type) !*BindingState {
    const state = try self.allocator.create(BindingState);
    state.* = .{};
    if (type_value == .reference) {
        state.reference = .{ .root = null, .mutable = type_value.reference.mutable };
    }
    return state;
}

pub fn copyBorrow(self: anytype, borrow: Borrow) !Borrow {
    _ = self;
    if (borrow.mutable) return error.InvalidSource;
    if (borrow.root) |root| root.immutable_borrows += 1;
    return borrow;
}

pub fn releaseTransientBorrow(_: anytype, expression_value: *Expression) void {
    if (expression_value.owns_borrow) {
        releaseBorrow(expression_value.borrow.?);
        expression_value.owns_borrow = false;
    }
}

pub fn retainTransientBorrow(self: anytype, borrows: *std.ArrayList(Borrow), expression_value: *Expression) !void {
    if (!expression_value.owns_borrow) return;
    try borrows.append(self.allocator, expression_value.borrow.?);
    expression_value.owns_borrow = false;
}

pub fn releaseScopeBorrows(_: anytype, scope: *Scope) void {
    for (scope.borrows.items) |borrow| releaseBorrow(borrow);
}

pub fn placeRootSymbol(
    self: anytype,
    ast_expression: *const Ast.Expression,
    scope: *const Scope,
    position: Source.Position,
) AnalyzeError!?*const Symbol {
    const name = switch (ast_expression.value) {
        .identifier => |value| value,
        .self => return null,
        .member_access => |member| return self.placeRootSymbol(member.object, scope, position),
        .index_access => |access| return self.placeRootSymbol(access.object, scope, position),
        .slice_access => |access| return self.placeRootSymbol(access.object, scope, position),
        else => return self.fail(position, "a reference must borrow a variable, field, or collection element"),
    };
    const symbol = findSymbol(scope, name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
        return self.fail(position, message);
    };
    return symbol;
}

pub fn isNativeReturnType(self: anytype, value: Type) Allocator.Error!bool {
    if (self.resultShape(value)) |shape| {
        return try self.isNativeResultBranchType(shape.success_type) and
            try self.isNativeResultBranchType(shape.error_type);
    }
    if (isNativeByteBufferReturnType(value)) return true;
    return self.isNativeLegacyReturnType(value);
}

pub fn isNativeResultBranchType(self: anytype, value: Type) Allocator.Error!bool {
    if (isNativeByteBufferReturnType(value)) return true;
    return self.isNativeLegacyReturnType(value);
}

pub fn isNativeLegacyReturnType(self: anytype, value: Type) Allocator.Error!bool {
    if (value == .reference) {
        const target = value.reference.target.*;
        return self.isNativeResourceType(target) or isNativeScalarViewType(target);
    }
    if (value == .optional) return self.isNativeLegacyReturnType(value.optional.*);
    if (isNativeScalarReturnType(value)) return true;
    const structure_type = switch (value) {
        .structure => |type_value| type_value,
        else => return false,
    };
    if (self.isNativeResourceType(value)) return true;
    if (structure_type.is_class or structure_type.is_owner) return false;
    const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse return false;
    if (structure.is_generic or try self.isNonCopyableType(value)) return false;
    for (structure.fields) |field| if (!isNativeStructureFieldType(field.type)) return false;
    return true;
}

pub fn nativeResultTransport(self: anytype, value: Type) Allocator.Error!?NativeResultTransport {
    const shape = self.resultShape(value) orelse return null;
    return .{
        .enum_generated_name = shape.enum_symbol.generated_name,
        .success_type = shape.success_type,
        .failure_type = shape.error_type,
        .success_structure = try self.nativeStructureTransport(shape.success_type),
        .failure_structure = try self.nativeStructureTransport(shape.error_type),
    };
}

pub fn nativeStructureTransport(self: anytype, value: Type) Allocator.Error!?NativeStructureTransport {
    const optional_returned = if (value == .optional) value.optional.* else value;
    const returned = if (optional_returned == .reference) optional_returned.reference.target.* else optional_returned;
    const structure_type = switch (returned) {
        .structure => |type_value| type_value,
        else => return null,
    };
    const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse return null;
    var fields: std.ArrayList(NativeTransportField) = .empty;
    for (structure.fields) |field| try fields.append(self.allocator, .{
        .source_name = field.source_name,
        .generated_name = field.generated_name,
        .type = field.type,
    });
    return .{
        .source_name = structure.source_name,
        .generated_name = structure.generated_name,
        .fields = try fields.toOwnedSlice(self.allocator),
        .is_native_resource = structure.is_native_resource,
        .native_module_name = structure.native_module_name,
        .native_drop_name = structure.native_drop_name,
        .native_drop_symbol = structure.native_drop_symbol,
    };
}

pub fn nativeParameterStructures(
    self: anytype,
    parameter_types: []const Type,
) Allocator.Error![]const ?NativeStructureTransport {
    var structures: std.ArrayList(?NativeStructureTransport) = .empty;
    for (parameter_types) |parameter_type| {
        try structures.append(self.allocator, try self.nativeStructureTransport(parameter_type));
    }
    return structures.toOwnedSlice(self.allocator);
}

pub fn isNativeParameterType(self: anytype, value: Type) Allocator.Error!bool {
    if (isNativeCallbackType(value)) return true;
    if (isNativeScalarViewType(value)) return true;
    if (isNativeByteViewType(value)) return true;
    if (isNativeScalarParameterType(value)) return true;
    const structure_type = switch (value) {
        .structure => |type_value| type_value,
        else => return false,
    };
    if (self.isNativeResourceType(value)) return true;
    if (structure_type.is_class or structure_type.is_owner) return false;
    const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse return false;
    if (structure.is_generic or try self.isNonCopyableType(value)) return false;
    for (structure.fields) |field| if (!isNativeStructureFieldType(field.type)) return false;
    return true;
}

pub fn isNativeResourceType(self: anytype, value: Type) bool {
    const structure_type = switch (value) {
        .structure => |type_value| type_value,
        else => return false,
    };
    const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse return false;
    return structure.is_native_resource;
}

pub fn fail(self: anytype, position: Source.Position, message: []const u8) Source.Error {
    self.diagnostic = .{ .position = position, .message = message };
    return error.InvalidSource;
}
