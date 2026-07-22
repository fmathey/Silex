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
pub fn expression(self: anytype, ast: *const Ast.Expression, scope: *const Scope) AnalyzeError!*Expression {
    return self.expressionForBorrow(ast, scope);
}

pub fn expressionForBorrow(
    self: anytype,
    ast: *const Ast.Expression,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (ast.value == .unary and ast.value.unary.operator == .borrow and ast.value.unary.operand.value == .slice_access) {
        return self.borrowExpression(ast.value.unary, scope, true);
    }
    if (ast.value == .unary and ast.value.unary.operator == .borrow) {
        return self.fail(ast.value.unary.operator_position, "'&' is only valid in parameter declarations; calls use plain arguments");
    }
    if (ast.value == .borrow_expression and ast.value.borrow_expression.operand.value == .slice_access) {
        return self.readBorrowValue(ast.value.borrow_expression, scope, null);
    }
    if (ast.value == .borrow_expression) {
        return self.fail(ast.value.borrow_expression.operator_position, "'@' is only valid for read bindings; calls use plain arguments");
    }
    return switch (ast.value) {
        .integer => |lexeme| self.integerExpression(ast.position, lexeme),
        .floating => |lexeme| self.floatExpression(ast.position, lexeme),
        .boolean => |value| self.newExpression(.{
            .type = .bool,
            .position = ast.position,
            .value = .{ .boolean = value },
        }),
        .null => self.newExpression(.{ .type = .null, .position = ast.position, .value = .null }),
        .string => |value| self.stringExpression(ast.position, value),
        .sequence_literal => |values| self.sequenceLiteralExpression(values, ast.position, scope, null),
        .identifier => |name| self.identifierExpression(ast.position, name, scope),
        .self => self.selfExpression(ast.position),
        .call => |call| self.callExpression(call, scope),
        .value_call => |call| self.valueCallExpression(call, scope),
        .lambda => |lambda| self.lambdaExpression(lambda, scope, null),
        .method_call => |call| self.methodCallExpression(call, scope),
        .static_method_call => |call| self.staticMethodCallExpression(call, scope),
        .static_field_access => |access| self.staticFieldAccessExpression(access),
        .super_method_call => |call| self.superMethodCallExpression(call, scope),
        .cascade => |cascade| self.cascadeExpression(cascade, scope, null),
        .class_initializer => |initializer| self.classInitializerExpression(initializer, scope),
        .structure_initializer => |initializer| self.structureInitializerExpression(initializer, scope),
        .member_access => |member| self.memberAccessExpression(member, scope),
        .safe_member_access => |member| self.safeMemberAccessExpression(member, scope),
        .index_access => |access| self.indexAccessExpression(access, scope),
        .slice_access => |access| self.sliceAccessExpression(access, scope, false),
        .try_expression => |try_value| self.tryExpression(try_value, scope),
        .move_expression => |move_value| self.moveExpression(move_value, scope),
        .borrow_expression => unreachable,
        .unary => |unary| self.unaryExpression(unary, scope),
        .conversion => |conversion| self.conversionExpression(conversion, scope),
        .binary => |binary| self.binaryExpression(binary, scope),
        .match_expression => |match_value| self.matchExpression(match_value, scope),
    };
}

pub fn expressionForExpected(
    self: anytype,
    ast: *const Ast.Expression,
    scope: *const Scope,
    expected_type: ?Type,
) AnalyzeError!*Expression {
    if (expected_type != null and expected_type.? == .reference) {
        const reference = expected_type.?.reference;
        if (ast.value == .borrow_expression and !reference.mutable) {
            const value = try self.readBorrowValue(ast.value.borrow_expression, scope, reference.target.*);
            value.type = expected_type.?;
            return value;
        }
        if (ast.value == .unary and ast.value.unary.operator == .borrow) {
            return self.borrowExpression(ast.value.unary, scope, reference.mutable);
        }
    }
    if (ast.value == .null) {
        const optional_type = expected_type orelse return self.fail(ast.position, "'null' requires an expected optional type");
        if (optional_type != .optional) return self.fail(ast.position, "'null' requires an expected optional type");
        return self.newExpression(.{ .type = optional_type, .position = ast.position, .value = .null });
    }
    if (expected_type != null and expected_type.? == .optional and
        (ast.value == .sequence_literal or ast.value == .cascade or ast.value == .lambda))
    {
        const contained = expected_type.?.optional.*;
        const value = if (ast.value == .sequence_literal)
            try self.sequenceLiteralExpression(ast.value.sequence_literal, ast.position, scope, contained)
        else if (ast.value == .cascade)
            try self.cascadeExpression(ast.value.cascade, scope, contained)
        else
            try self.lambdaExpression(ast.value.lambda, scope, contained);
        return self.coerce(value, expected_type.?);
    }
    if (ast.value == .sequence_literal) return self.sequenceLiteralExpression(ast.value.sequence_literal, ast.position, scope, expected_type);
    if (ast.value == .cascade) return self.cascadeExpression(ast.value.cascade, scope, expected_type);
    if (ast.value == .lambda) return self.lambdaExpression(ast.value.lambda, scope, expected_type);
    if (expected_type != null and expected_type.? == .function and ast.value == .identifier and
        findSymbol(scope, ast.value.identifier) == null)
    {
        return self.functionReferenceExpression(ast.position, ast.value.identifier, expected_type.?);
    }
    return self.expressionForBorrow(ast, scope);
}

pub fn functionReferenceExpression(
    self: anytype,
    position: Source.Position,
    name: []const u8,
    expected_type: Type,
) AnalyzeError!*Expression {
    var match: ?FunctionSymbol = null;
    for (self.functions.items) |function_symbol| {
        if (!std.mem.eql(u8, function_symbol.source_name, name) or function_symbol.is_main or function_symbol.is_native) continue;
        if (function_symbol.parameter_types.len != expected_type.function.parameters.len or
            function_symbol.parameter_modes.len != expected_type.function.parameter_modes.len or
            !typeEqual(function_symbol.return_type, expected_type.function.return_type.*)) continue;
        var compatible = true;
        for (function_symbol.parameter_types, expected_type.function.parameters) |actual, expected| {
            if (!typeEqual(actual, expected)) compatible = false;
        }
        for (function_symbol.parameter_modes, expected_type.function.parameter_modes) |actual, expected| {
            if (actual != expected) compatible = false;
        }
        if (!compatible) continue;
        if (match != null) {
            const message = try std.fmt.allocPrint(self.allocator, "function reference '{s}' is ambiguous for the expected signature", .{name});
            return self.fail(position, message);
        }
        match = function_symbol;
    }
    const function_symbol = match orelse {
        const message = try std.fmt.allocPrint(self.allocator, "no function '{s}' matches the expected function type", .{name});
        return self.fail(position, message);
    };
    return self.newExpression(.{
        .type = expected_type,
        .position = position,
        .value = .{ .function_reference = function_symbol.generated_name },
    });
}

pub fn identifierExpression(
    self: anytype,
    position: Source.Position,
    name: []const u8,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (findSymbol(scope, name) != null) return self.variableExpression(position, name, scope);
    var match: ?FunctionSymbol = null;
    for (self.functions.items) |function_symbol| {
        if (!std.mem.eql(u8, function_symbol.source_name, name) or function_symbol.is_main or function_symbol.is_native) continue;
        if (match != null) {
            const message = try std.fmt.allocPrint(self.allocator, "function reference '{s}' requires an expected type to select an overload", .{name});
            return self.fail(position, message);
        }
        match = function_symbol;
    }
    if (match) |function_symbol| {
        const return_type = try self.allocator.create(Type);
        return_type.* = function_symbol.return_type;
        const function_type: Type = .{ .function = .{
            .parameters = function_symbol.parameter_types,
            .parameter_modes = function_symbol.parameter_modes,
            .return_type = return_type,
        } };
        return self.newExpression(.{
            .type = function_type,
            .position = position,
            .value = .{ .function_reference = function_symbol.generated_name },
        });
    }
    return self.variableExpression(position, name, scope);
}

pub fn integerExpression(self: anytype, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
    const normalized = try normalizeNumericLiteral(self.allocator, lexeme);
    const base: u8 = if (normalized.len > 2 and normalized[0] == '0') switch (normalized[1]) {
        'b', 'B' => 2,
        'o', 'O' => 8,
        'x', 'X' => 16,
        else => 10,
    } else 10;
    const digits = if (base == 10) normalized else normalized[2..];
    const value = std.fmt.parseInt(u64, digits, base) catch {
        return self.fail(position, "integer literal is outside the range of 'int'");
    };
    return self.newExpression(.{
        .type = .int,
        .position = position,
        .value = .{ .integer = value },
    });
}

pub fn floatExpression(self: anytype, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
    const normalized = try normalizeNumericLiteral(self.allocator, lexeme);
    const value = std.fmt.parseFloat(f64, normalized) catch {
        return self.fail(position, "float literal is outside the range of 'float'");
    };
    if (!std.math.isFinite(value)) return self.fail(position, "float literal is outside the range of 'float'");
    return self.newExpression(.{
        .type = .float,
        .position = position,
        .value = .{ .floating = normalized },
    });
}

pub fn stringExpression(self: anytype, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
    return self.newExpression(.{
        .type = .str,
        .position = position,
        .value = .{ .string = try self.decodeStringLiteral(position, lexeme) },
    });
}

pub fn sequenceLiteralExpression(
    self: anytype,
    ast_values: []const *Ast.Expression,
    position: Source.Position,
    scope: *const Scope,
    expected_type: ?Type,
) AnalyzeError!*Expression {
    var element_type: Type = undefined;
    var result_type: Type = undefined;
    switch (expected_type orelse .void) {
        .list => |element| {
            element_type = element.*;
            result_type = expected_type.?;
        },
        .fixed_array => |array| {
            if (ast_values.len != array.length) {
                const message = try std.fmt.allocPrint(self.allocator, "array literal expects {d} values, found {d}", .{ array.length, ast_values.len });
                return self.fail(position, message);
            }
            element_type = array.element.*;
            result_type = expected_type.?;
        },
        .void => {
            if (ast_values.len == 0) return self.fail(position, "empty sequence literal requires a collection type");
            const first = try self.expression(ast_values[0], scope);
            if (first.type == .null) return self.fail(ast_values[0].position, "'null' in a sequence literal requires an expected collection element type");
            element_type = first.type;
            const element = try self.allocator.create(Type);
            element.* = element_type;
            result_type = .{ .list = element };
        },
        else => return self.fail(position, "sequence literal requires an array or list type"),
    }
    try self.rejectUniqueOwnerComposition(result_type, false, position);

    var values: std.ArrayList(*Expression) = .empty;
    var lifetime_depth: usize = 0;
    for (ast_values, 0..) |ast_value, index| {
        var value = if (expected_type == null and index == 0)
            try self.expression(ast_value, scope)
        else
            try self.expressionForExpected(ast_value, scope, element_type);
        value = try self.coerce(value, element_type);
        if (!typeEqual(value.type, element_type)) {
            const message = try typeMismatchMessage(self.allocator, element_type, value.type);
            return self.fail(ast_value.position, message);
        }
        try self.rejectUniqueOwnerArgument(value, ast_value.position);
        try values.append(self.allocator, value);
        lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
    }
    return self.newExpression(.{
        .type = result_type,
        .position = position,
        .lifetime_depth = lifetime_depth,
        .value = .{ .sequence_literal = try values.toOwnedSlice(self.allocator) },
    });
}

pub fn decodeStringLiteral(self: anytype, position: Source.Position, lexeme: []const u8) AnalyzeError![]const u8 {
    var value: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < lexeme.len) {
        const character = lexeme[index];
        if (character != '\\') {
            try value.append(self.allocator, character);
            index += 1;
            continue;
        }
        index += 1;
        if (index == lexeme.len) return self.fail(position, "unterminated string literal");
        switch (lexeme[index]) {
            '"' => try value.append(self.allocator, '"'),
            '\\' => try value.append(self.allocator, '\\'),
            'n' => try value.append(self.allocator, '\n'),
            'r' => try value.append(self.allocator, '\r'),
            't' => try value.append(self.allocator, '\t'),
            '0' => try value.append(self.allocator, 0),
            'u' => {
                index += 2;
                var scalar: u21 = 0;
                while (lexeme[index] != '}') : (index += 1) {
                    scalar = scalar * 16 + (hexDigit(lexeme[index]) orelse unreachable);
                }
                try appendUnicodeScalar(self.allocator, &value, scalar);
            },
            else => unreachable,
        }
        index += 1;
    }
    return value.toOwnedSlice(self.allocator);
}

pub fn defaultExpression(self: anytype, type_value: Type, position: Source.Position) AnalyzeError!*Expression {
    return switch (type_value) {
        .void => self.fail(position, "type 'void' has no default value"),
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .integer = 0 } }),
        .float, .float64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .floating = "0.0" } }),
        .bool => self.newExpression(.{ .type = .bool, .position = position, .value = .{ .boolean = false } }),
        .str => self.newExpression(.{ .type = .str, .position = position, .value = .{ .string = "" } }),
        .list, .fixed_array => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .sequence_literal = &.{} } }),
        .reference, .view => self.fail(position, "a borrowed view or reference requires an initializer"),
        .function => self.fail(position, "a function value requires an initializer"),
        .protocol => |protocol_type| default_protocol: {
            const message = try std.fmt.allocPrint(self.allocator, "protocol value '{s}' requires an initializer", .{protocol_type.source_name});
            break :default_protocol self.fail(position, message);
        },
        .enumeration => |enum_type| default_enum: {
            const message = try std.fmt.allocPrint(self.allocator, "enum '{s}' requires an initializer", .{enum_type.source_name});
            break :default_enum self.fail(position, message);
        },
        .optional => self.newExpression(.{ .type = type_value, .position = position, .value = .null }),
        .null => unreachable,
        .structure => |structure_type| structure_default: {
            if (structure_type.is_class) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "class '{s}' requires an initializer",
                    .{structure_type.source_name},
                );
                return self.fail(position, message);
            }
            const structure = self.findStructureByGeneratedName(structure_type.generated_name).?;
            var fields: std.ArrayList(*Expression) = .empty;
            for (structure.fields) |field| {
                try fields.append(
                    self.allocator,
                    field.default_value orelse try self.defaultExpression(field.type, position),
                );
            }
            break :structure_default self.newExpression(.{
                .type = type_value,
                .position = position,
                .value = .{ .structure_initializer = .{
                    .generated_name = structure.generated_name,
                    .fields = try fields.toOwnedSlice(self.allocator),
                } },
            });
        },
    };
}

pub fn intrinsicDefaultExpression(
    self: anytype,
    type_value: Type,
    position: Source.Position,
) AnalyzeError!?*Expression {
    if (!self.hasIntrinsicDefault(type_value)) return null;
    return try self.defaultExpression(type_value, position);
}

pub fn hasIntrinsicDefault(self: anytype, type_value: Type) bool {
    return switch (type_value) {
        .void, .reference, .view, .function, .protocol, .enumeration, .null => false,
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool, .str, .list, .fixed_array, .optional => true,
        .structure => |structure_type| intrinsic: {
            if (structure_type.is_class) break :intrinsic false;
            const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :intrinsic false;
            for (structure.fields) |field| {
                if (field.default_value == null and !self.hasIntrinsicDefault(field.type)) break :intrinsic false;
            }
            break :intrinsic true;
        },
    };
}

pub fn variableExpression(
    self: anytype,
    position: Source.Position,
    name: []const u8,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const symbol = findSymbol(scope, name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
        return self.fail(position, message);
    };
    if (try self.isNonCopyableType(symbol.type) and !symbol.state.owner_available) {
        const consumed_at = symbol.state.consumed_at.?;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "noncopyable value '{s}' was consumed by 'move' at {d}:{d}",
            .{ name, consumed_at.line, consumed_at.column },
        );
        return self.fail(position, message);
    }
    try self.recordSymbolCapture(symbol, position);
    if (symbol.state.mutable_borrow) {
        const message = try std.fmt.allocPrint(self.allocator, "cannot access variable '{s}' while it is mutably borrowed", .{name});
        return self.fail(position, message);
    }
    const narrowed = symbol.unwrap_optional and symbol.state.narrowed_valid;
    return self.newExpression(.{
        .type = if (narrowed) symbol.type else symbol.original_type orelse symbol.type,
        .position = position,
        .borrow = symbol.state.reference,
        .lifetime_depth = symbol.state.lifetime_depth,
        .borrowed_parameter = symbol.state.borrowed_parameter,
        .owner_state = symbol.state,
        .resource_dependencies = symbol.state.resource_dependencies,
        .deferred_resource_paths = symbol.state.deferred_resource_paths,
        .deferred_storage_state = symbol.state,
        .value = if (narrowed)
            .{ .optional_unwrap = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } }
        else
            .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
    });
}

pub fn selfExpression(self: anytype, position: Source.Position) AnalyzeError!*Expression {
    if (self.current_method_static) return self.fail(position, "'self' is not available inside a static method");
    const structure_index = self.current_structure_index orelse return self.fail(position, "'self' is only available inside a method or constructor");
    if (self.current_self_state.mutable_borrow) return self.fail(position, "cannot access 'self' while one of its collections is mutably iterated");
    const structure = self.structures.items[structure_index];
    if (self.current_lambda != null and try self.isNonCopyableType(.{ .structure = self.structureType(structure_index) })) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "noncopyable value '{s}' cannot be captured by a lambda",
            .{structure.source_name},
        );
        return self.fail(position, message);
    }
    if (self.current_lambda) |_| {
        var owner_context = self.current_lambda;
        while (owner_context) |lambda| : (owner_context = lambda.parent) {
            if (!lambda.owner_self) continue;
            var child_context = self.current_lambda;
            while (child_context.? != lambda) : (child_context = child_context.?.parent) {
                try self.recordLambdaCapture(child_context.?, "silexOwner", false);
            }
            return self.newExpression(.{
                .type = .{ .structure = self.structureType(structure_index) },
                .position = position,
                .value = .owner_self,
            });
        }
        var lambda_context = self.current_lambda;
        while (lambda_context) |lambda| : (lambda_context = lambda.parent) {
            lambda.captures_self = true;
            lambda.lifetime_depth = @max(lambda.lifetime_depth, self.function_scope_depth);
        }
    }
    return self.newExpression(.{
        .type = .{ .structure = self.structureType(structure_index) },
        .position = position,
        .lifetime_depth = if (self.current_lambda != null) self.function_scope_depth else 0,
        .value = .self,
    });
}

pub fn binaryExpression(
    self: anytype,
    binary: Ast.Expression.Binary,
    scope: *const Scope,
) AnalyzeError!*Expression {
    var left = try self.expression(binary.left, scope);
    var right = try self.expression(binary.right, scope);
    const is_shift = binary.operator == .shift_left or binary.operator == .shift_right;
    if (!is_shift and isContextualIntegerLiteral(left) and isInteger(right.type)) left = try self.coerce(left, right.type);
    if (!is_shift and isContextualIntegerLiteral(right) and isInteger(left.type)) right = try self.coerce(right, left.type);
    const result_type: Type = switch (binary.operator) {
        .add, .subtract, .multiply, .divide => arithmetic: {
            if (binary.operator == .add and typeEqual(left.type, .str) and typeEqual(right.type, .str)) {
                break :arithmetic .str;
            }
            try self.requireNumericOperands(binary.operator_position, "arithmetic operator", left.type, right.type);
            const common_type = commonNumericType(left.type, right.type) orelse {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "arithmetic operator requires compatible numeric operands, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            };
            left = try self.coerce(left, common_type);
            right = try self.coerce(right, common_type);
            break :arithmetic common_type;
        },
        .remainder => remainder: {
            if (!isInteger(left.type) or !isInteger(right.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "remainder operator requires compatible integer operands, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            }
            const common_type = commonNumericType(left.type, right.type) orelse {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "remainder operator requires compatible integer operands, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            };
            left = try self.coerce(left, common_type);
            right = try self.coerce(right, common_type);
            break :remainder common_type;
        },
        .bit_and, .bit_xor => bitwise: {
            const common_type = commonUnsignedIntegerType(left.type, right.type) orelse {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "bitwise operator requires compatible unsigned integer operands, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            };
            left = try self.coerce(left, common_type);
            right = try self.coerce(right, common_type);
            break :bitwise common_type;
        },
        .shift_left, .shift_right => shift: {
            if (!isUnsignedInteger(left.type) or !isInteger(right.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "shift operator requires an unsigned integer value and an integer count, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            }
            break :shift left.type;
        },
        .less, .less_equal, .greater, .greater_equal => comparison: {
            try self.requireNumericOperands(binary.operator_position, "comparison operator", left.type, right.type);
            const common_type = commonNumericType(left.type, right.type) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "comparison operator requires compatible numeric operands, found '{s}' and '{s}'", .{ typeName(left.type), typeName(right.type) });
                return self.fail(binary.operator_position, message);
            };
            left = try self.coerce(left, common_type);
            right = try self.coerce(right, common_type);
            break :comparison .bool;
        },
        .logical_and, .logical_or => try self.requireBinaryOperands(
            binary.operator_position,
            "logical operator",
            .bool,
            left.type,
            right.type,
            .bool,
        ),
        .equal, .not_equal => equality: {
            if (left.type == .null and right.type == .null) {
                return self.fail(binary.operator_position, "'null' cannot be compared without an expected optional type");
            }
            if (left.type == .null or right.type == .null) {
                if (left.type == .null and right.type == .optional) left = try self.coerce(left, right.type);
                if (right.type == .null and left.type == .optional) right = try self.coerce(right, left.type);
                if (left.type != .optional or right.type != .optional) {
                    return self.fail(binary.operator_position, "'null' can only be compared with an optional value");
                }
                break :equality .bool;
            }
            if (left.type == .optional or right.type == .optional) {
                if (left.type == .optional and right.type != .optional) right = try self.coerce(right, left.type);
                if (right.type == .optional and left.type != .optional) left = try self.coerce(left, right.type);
                if (left.type != .optional or right.type != .optional) {
                    return self.fail(binary.operator_position, "equality operator requires compatible optional operands");
                }
                if (!self.isEqualityComparable(left.type) or !self.isEqualityComparable(right.type)) {
                    return self.fail(binary.operator_position, "optional function values are only comparable to 'null'");
                }
                if (!typeEqual(left.type, right.type)) {
                    const left_contained = left.type.optional.*;
                    const right_contained = right.type.optional.*;
                    const common = if (self.classUpcastDistance(left_contained, right_contained) != null)
                        right_contained
                    else if (self.classUpcastDistance(right_contained, left_contained) != null)
                        left_contained
                    else
                        commonNumericType(left_contained, right_contained) orelse {
                            return self.fail(binary.operator_position, "equality operator requires compatible optional operands");
                        };
                    const common_optional = try self.optionalType(common);
                    left = try self.coerce(left, common_optional);
                    right = try self.coerce(right, common_optional);
                }
                break :equality .bool;
            }
            if (try self.isNonCopyableType(left.type) or try self.isNonCopyableType(right.type)) {
                const owner_type = if (try self.isNonCopyableType(left.type)) left.type else right.type;
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "type '{s}' does not support equality",
                    .{typeName(owner_type)},
                );
                return self.fail(binary.operator_position, message);
            }
            if (!self.isEqualityComparable(left.type) or !self.isEqualityComparable(right.type)) {
                return self.fail(binary.operator_position, "function values and values containing them are not comparable");
            }
            if (isNumeric(left.type) and isNumeric(right.type)) {
                const common_type = commonNumericType(left.type, right.type) orelse {
                    const message = try std.fmt.allocPrint(self.allocator, "equality operator requires compatible numeric operands, found '{s}' and '{s}'", .{ typeName(left.type), typeName(right.type) });
                    return self.fail(binary.operator_position, message);
                };
                left = try self.coerce(left, common_type);
                right = try self.coerce(right, common_type);
            } else if (self.classUpcastDistance(left.type, right.type) != null) {
                left = try self.coerce(left, right.type);
            } else if (self.classUpcastDistance(right.type, left.type) != null) {
                right = try self.coerce(right, left.type);
            } else if (!typeEqual(left.type, right.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "equality operator requires operands of the same type, found '{s}' and '{s}'",
                    .{ typeName(left.type), typeName(right.type) },
                );
                return self.fail(binary.operator_position, message);
            }
            break :equality .bool;
        },
    };
    return self.newExpression(.{
        .type = result_type,
        .position = binary.operator_position,
        .value = .{ .binary = .{ .operator = binary.operator, .left = left, .right = right } },
    });
}

pub fn conversionExpression(
    self: anytype,
    conversion: Ast.Expression.Conversion,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const operand = try self.expression(conversion.operand, scope);
    const target_type = try typeFromAnnotation(self, conversion.target_type, conversion.as_position);
    if (!isNumeric(operand.type) or !isNumeric(target_type)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "explicit conversion requires numeric source and target types, found '{s}' and '{s}'",
            .{ typeName(operand.type), typeName(target_type) },
        );
        return self.fail(conversion.as_position, message);
    }
    return self.newExpression(.{
        .type = target_type,
        .position = conversion.as_position,
        .value = .{ .conversion = .{ .operand = operand, .target_type = target_type } },
    });
}

pub fn callExpression(self: anytype, call: Ast.Expression.Call, scope: *const Scope) AnalyzeError!*Expression {
    if (std.mem.eql(u8, call.name, "dispatch_callbacks")) return self.dispatchCallbacksExpression(call, scope);
    if (findSymbol(scope, call.name)) |symbol| {
        if (symbol.type != .function) {
            const message = try std.fmt.allocPrint(self.allocator, "value '{s}' is not callable", .{call.name});
            return self.fail(call.name_position, message);
        }
        const callee = try self.variableExpression(call.name_position, call.name, scope);
        return self.checkedValueCall(callee, call.arguments, call.name_position, scope, null);
    }
    if (std.mem.eql(u8, call.name, "main")) return self.fail(call.name_position, "'main' cannot be called");
    var candidates: std.ArrayList(FunctionSymbol) = .empty;
    for (self.functions.items) |function_symbol| {
        if (std.mem.eql(u8, function_symbol.source_name, call.name) and !function_symbol.is_main and
            (call.visible_declarations == null or containsPosition(call.visible_declarations.?, function_symbol.position)))
        {
            try candidates.append(self.allocator, function_symbol);
        }
    }
    if (candidates.items.len == 0) {
        const message = try std.fmt.allocPrint(self.allocator, "unknown function '{s}'", .{call.name});
        return self.fail(call.name_position, message);
    }
    const function_symbol = try self.resolveFunctionOverload(call.name, call.name_position, call.arguments, scope, candidates.items);
    var arguments: std.ArrayList(*Expression) = .empty;
    var lifetime_depth: usize = 0;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (call.arguments, function_symbol.parameter_types, function_symbol.parameter_modes, function_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
        var value = if (function_symbol.is_native_resource_drop)
            try self.nativeResourceDropArgument(argument, scope, expected_type)
        else
            try self.argumentForMode(argument, scope, expected_type, mode);
        value = try self.coerce(value, expected_type);
        if (!typeEqual(value.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} of '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
            return self.fail(argument.position, message);
        }
        if (function_symbol.is_native and
            !function_symbol.is_native_resource_drop and
            mode == .value and
            value.deferred_resource_paths.len != 0)
        {
            return self.fail(argument.position, "a deferred subscription can only be transferred to its declared native destructor");
        }
        if (mode == .value and !function_symbol.is_native_resource_drop) try self.rejectUniqueOwnerArgument(value, argument.position);
        if (is_stored and value.lifetime_depth != 0) {
            return self.fail(argument.position, "capturing callback cannot be passed to a parameter whose value escapes the call");
        }
        try arguments.append(self.allocator, value);
        if (expected_type == .function and expected_type.function.deferred) {
            lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
        }
        try self.retainTransientBorrow(&transient_borrows, value);
    }
    const resource_dependencies = if (try self.isNonCopyableType(function_symbol.return_type))
        try self.functionCallResourceDependencies(function_symbol, arguments.items)
    else
        &.{};
    var returned_borrow: ?Borrow = null;
    if (function_symbol.return_borrow_parameter) |parameter_index| {
        const root = if (arguments.items[parameter_index].borrow) |borrow| borrow.root else arguments.items[parameter_index].owner_state;
        const mutable = function_symbol.return_type.reference.mutable;
        returned_borrow = .{ .root = root, .mutable = mutable };
        if (root) |state| {
            if (mutable) state.mutable_borrow = true else state.immutable_borrows += 1;
        }
    }
    return self.newExpression(.{
        .type = function_symbol.return_type,
        .position = call.name_position,
        .lifetime_depth = lifetime_depth,
        .borrow = returned_borrow,
        .owns_borrow = returned_borrow != null,
        .resource_dependencies = resource_dependencies,
        .deferred_resource_paths = if (function_symbol.deferred_callback_index != null)
            &.{&.{}}
        else
            function_symbol.return_deferred_resource_paths,
        .value = .{ .call = .{
            .generated_name = function_symbol.generated_name,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .is_native = function_symbol.is_native,
            .native_module_name = function_symbol.native_module_name,
            .native_function_name = function_symbol.native_function_name,
            .native_return_structure = if (function_symbol.is_native)
                try self.nativeStructureTransport(function_symbol.return_type)
            else
                null,
            .native_result = if (function_symbol.is_native)
                try self.nativeResultTransport(function_symbol.return_type)
            else
                null,
            .native_parameter_structures = if (function_symbol.is_native)
                try self.nativeParameterStructures(function_symbol.parameter_types)
            else
                &.{},
            .native_parameter_modes = if (function_symbol.is_native) function_symbol.parameter_modes else &.{},
            .borrowed_return_parameter = function_symbol.return_borrow_parameter,
            .is_native_resource_drop = function_symbol.is_native_resource_drop,
        } },
    });
}

pub fn dispatchCallbacksExpression(
    self: anytype,
    call: Ast.Expression.Call,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (call.type_arguments.len != 0 or call.named_fields != null or call.arguments.len != 1) {
        return self.fail(call.name_position, "dispatch_callbacks expects exactly one subscription resource place");
    }
    const subscription = try self.expression(call.arguments[0], scope);
    if (!isPlaceValue(subscription)) {
        return self.fail(call.arguments[0].position, "dispatch_callbacks requires a readable subscription resource place");
    }
    if (!self.isNativeResourceType(subscription.type) or
        (!hasDirectDeferredResource(subscription) and !self.inferring_deferred_return_summaries))
    {
        return self.fail(call.arguments[0].position, "dispatch_callbacks requires a native resource returned by a deferred registration");
    }
    return self.newExpression(.{
        .type = .int,
        .position = call.name_position,
        .value = .{ .call = .{
            .generated_name = "silexDispatchCallbacks",
            .arguments = try self.allocator.dupe(*Expression, &.{subscription}),
            .is_native = false,
            .native_module_name = null,
            .native_function_name = null,
        } },
    });
}

pub fn valueCallExpression(
    self: anytype,
    call: Ast.Expression.ValueCall,
    scope: *const Scope,
) AnalyzeError!*Expression {
    const callee = try self.expression(call.callee, scope);
    return self.checkedValueCall(callee, call.arguments, call.parenthesis_position, scope, null);
}

pub fn functionCallResourceDependencies(
    self: anytype,
    function_symbol: FunctionSymbol,
    arguments: []const *Expression,
) Allocator.Error![]const *BindingState {
    var dependencies: std.ArrayList(*BindingState) = .empty;
    for (arguments, function_symbol.parameter_modes, 0..) |argument, mode, index| {
        const depends = if (function_symbol.is_native)
            mode != .value
        else
            containsIndex(function_symbol.return_dependency_parameters, index);
        if (!depends) continue;
        const root = if (argument.borrow) |borrow| borrow.root else argument.owner_state;
        const dependency = root orelse continue;
        var found = false;
        for (dependencies.items) |existing| {
            if (existing == dependency) found = true;
        }
        if (!found) try dependencies.append(self.allocator, dependency);
    }
    return dependencies.toOwnedSlice(self.allocator);
}

pub fn checkedValueCall(
    self: anytype,
    callee: *Expression,
    ast_arguments: []const *Ast.Expression,
    position: Source.Position,
    scope: *const Scope,
    owner: ?*Expression,
) AnalyzeError!*Expression {
    const function_type = switch (callee.type) {
        .function => |value| value,
        else => return self.fail(position, "expression is not callable"),
    };
    if (function_type.deferred) return self.fail(position, "a 'deferred func' cannot be called directly in Silex");
    if (ast_arguments.len != function_type.parameters.len) {
        const message = try std.fmt.allocPrint(self.allocator, "function value expects {d} arguments, found {d}", .{ function_type.parameters.len, ast_arguments.len });
        return self.fail(position, message);
    }
    var arguments: std.ArrayList(*Expression) = .empty;
    var transient_borrows: std.ArrayList(Borrow) = .empty;
    defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
    for (ast_arguments, function_type.parameters, function_type.parameter_modes, 0..) |ast_argument, expected_type, mode, index| {
        var argument = try self.argumentForMode(ast_argument, scope, expected_type, mode);
        argument = try self.coerce(argument, expected_type);
        if (!typeEqual(argument.type, expected_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "argument {d} expects '{s}', found '{s}'", .{ index + 1, typeName(expected_type), typeName(argument.type) });
            return self.fail(ast_argument.position, message);
        }
        if (mode == .value) try self.rejectUniqueOwnerArgument(argument, ast_argument.position);
        try arguments.append(self.allocator, argument);
        try self.retainTransientBorrow(&transient_borrows, argument);
    }
    return self.newExpression(.{
        .type = function_type.return_type.*,
        .position = position,
        .lifetime_depth = callee.lifetime_depth,
        .value = .{ .value_call = .{
            .callee = callee,
            .arguments = try arguments.toOwnedSlice(self.allocator),
            .owner = owner,
        } },
    });
}

pub fn lambdaExpression(
    self: anytype,
    lambda: Ast.Expression.Lambda,
    parent_scope: *const Scope,
    expected_type: ?Type,
) AnalyzeError!*Expression {
    var parameter_types: std.ArrayList(Type) = .empty;
    var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
    var parameters: std.ArrayList(Parameter) = .empty;
    var scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
    for (lambda.parameters) |parameter| {
        if (findInCurrentScope(&scope, parameter.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
            return self.fail(parameter.position, message);
        }
        const parameter_type = try typeFromAnnotation(self, parameter.type, parameter.position);
        try self.validateParameterMode(parameter_type, parameter.mode, parameter.position, false);
        if (lambda.deferred and (parameter.mode != .value or !isNativeCallbackScalarType(parameter_type))) {
            return self.fail(parameter.position, "a 'deferred func' parameter must be a scalar bool or numeric value");
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        try parameter_types.append(self.allocator, parameter_type);
        try parameter_modes.append(self.allocator, parameter.mode);
        const state = try self.newBindingState(parameter_type);
        state.borrowed_parameter = parameter.mode == .borrow;
        try scope.symbols.append(self.allocator, .{
            .source_name = parameter.name,
            .generated_name = generated_name,
            .type = parameter_type,
            .mutability = if (parameter.mode == .borrow) .immutable else .mutable,
            .state = state,
            .scope_depth = scope.depth,
        });
        try parameters.append(self.allocator, .{
            .source_name = parameter.name,
            .position = parameter.position,
            .generated_name = generated_name,
            .type = parameter_type,
            .mode = parameter.mode,
            .capture_box = &state.capture_box,
        });
    }
    const return_type = try typeFromReturn(self, lambda.return_type, lambda.position);
    if (lambda.deferred and return_type != .void) return self.fail(lambda.position, "a 'deferred func' must return 'void'");
    try self.rejectUniqueOwnerComposition(return_type, true, lambda.position);
    const return_pointer = try self.allocator.create(Type);
    return_pointer.* = return_type;
    var lambda_type: Type = .{ .function = .{
        .deferred = lambda.deferred,
        .parameters = try parameter_types.toOwnedSlice(self.allocator),
        .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
        .return_type = return_pointer,
    } };
    if (expected_type) |expected| {
        if (expected != .function or !typeEqual(lambda_type, expected)) {
            const message = try typeMismatchMessage(self.allocator, expected, lambda_type);
            return self.fail(lambda.position, message);
        }
        lambda_type = expected;
    }

    var context = LambdaContext{
        .local_depth = scope.depth,
        .owner_self = lambda_type.function.owner != null,
        .parent = self.current_lambda,
    };
    const previous_lambda = self.current_lambda;
    const previous_return_type = self.current_return_type;
    const previous_loop_depth = self.loop_depth;
    const previous_loop_flow = self.current_loop_flow;
    self.current_lambda = &context;
    self.current_return_type = return_type;
    self.loop_depth = 0;
    self.current_loop_flow = null;
    defer {
        self.current_lambda = previous_lambda;
        self.current_return_type = previous_return_type;
        self.loop_depth = previous_loop_depth;
        self.current_loop_flow = previous_loop_flow;
    }
    const body = try self.statements(lambda.statements, &scope);
    self.releaseScopeBorrows(&scope);
    if (!typeEqual(return_type, .void) and !blockAlwaysReturns(body)) {
        return self.fail(lambda.position, "lambda must return a value on every path");
    }
    return self.newExpression(.{
        .type = lambda_type,
        .position = lambda.position,
        .lifetime_depth = context.lifetime_depth,
        .value = .{ .lambda = .{
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .return_type = return_type,
            .statements = body,
            .captures = try context.captures.toOwnedSlice(self.allocator),
            .captures_self = context.captures_self,
            .self_is_class = if (self.current_structure_index) |structure_index|
                self.structures.items[structure_index].is_class
            else
                false,
        } },
    });
}
