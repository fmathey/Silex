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
pub fn inferMethodMutability(self: anytype) void {
    for (self.structures.items) |*structure| {
        for (structure.methods) |*method_symbol| {
            method_symbol.is_mutating = method_symbol.direct_mutation;
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (self.structures.items) |*structure| {
            for (structure.methods) |*method_symbol| {
                if (method_symbol.is_mutating) continue;
                for (method_symbol.dependencies) |dependency| {
                    if (self.methodSymbol(dependency).is_mutating) {
                        method_symbol.is_mutating = true;
                        changed = true;
                        break;
                    }
                }
            }
        }
        for (self.structures.items) |*structure| {
            if (!structure.is_class) continue;
            for (structure.methods) |*method_symbol| {
                if (method_symbol.is_mutating) continue;
                for (self.structures.items) |candidate_structure| {
                    if (!candidate_structure.is_class) continue;
                    for (candidate_structure.methods) |candidate| {
                        if (candidate.is_mutating and std.mem.eql(u8, candidate.generated_name, method_symbol.generated_name)) {
                            method_symbol.is_mutating = true;
                            changed = true;
                            break;
                        }
                    }
                    if (method_symbol.is_mutating) break;
                }
            }
        }
    }

    for (self.structures.items) |*structure| {
        for (structure.methods) |*method_symbol| {
            method_symbol.requires_mutable_codegen = method_symbol.direct_mutable_codegen;
        }
    }
    changed = true;
    while (changed) {
        changed = false;
        for (self.structures.items) |*structure| {
            for (structure.methods) |*method_symbol| {
                if (method_symbol.requires_mutable_codegen) continue;
                for (method_symbol.dependencies) |dependency| {
                    if (self.methodSymbol(dependency).requires_mutable_codegen) {
                        method_symbol.requires_mutable_codegen = true;
                        changed = true;
                        break;
                    }
                }
            }
        }
        for (self.structures.items) |*structure| {
            if (!structure.is_class) continue;
            for (structure.methods) |*method_symbol| {
                if (method_symbol.requires_mutable_codegen) continue;
                for (self.structures.items) |candidate_structure| {
                    if (!candidate_structure.is_class) continue;
                    for (candidate_structure.methods) |candidate| {
                        if (candidate.requires_mutable_codegen and
                            std.mem.eql(u8, candidate.generated_name, method_symbol.generated_name))
                        {
                            method_symbol.requires_mutable_codegen = true;
                            changed = true;
                            break;
                        }
                    }
                    if (method_symbol.requires_mutable_codegen) break;
                }
            }
        }
    }
}

pub fn methodSymbol(self: anytype, id: MethodId) *const MethodSymbol {
    return &self.structures.items[id.structure_index].methods[id.method_index];
}

pub fn validateMethodCalls(self: anytype, program: Program) AnalyzeError!void {
    for (program.structures) |structure| {
        for (structure.constructors) |constructor_value| try self.validateStatements(constructor_value.statements);
        if (structure.drop) |drop| try self.validateStatements(drop.statements);
        for (structure.methods) |method_value| try self.validateStatements(method_value.statements);
    }
    for (program.functions) |function_value| try self.validateStatements(function_value.statements);
}

pub fn validateStatements(self: anytype, statements_value: []const Statement) AnalyzeError!void {
    for (statements_value) |statement_value| {
        switch (statement_value) {
            .print => |expression_value| try self.validateExpression(expression_value),
            .assertion => |assertion_value| {
                try self.validateExpression(assertion_value.condition);
                try self.validateExpression(assertion_value.message);
            },
            .panic_statement => |panic_value| try self.validateExpression(panic_value.message),
            .variable_declaration => |declaration| try self.validateExpression(declaration.initializer),
            .assignment => |assignment_value| {
                try self.validateExpression(assignment_value.target);
                if (assignment_value.value) |value| try self.validateExpression(value);
            },
            .if_statement => |if_value| {
                try self.validateCondition(if_value.condition);
                try self.validateStatements(if_value.body);
                for (if_value.alternatives) |alternative| {
                    try self.validateCondition(alternative.condition);
                    try self.validateStatements(alternative.body);
                }
                if (if_value.else_body) |else_body| try self.validateStatements(else_body);
            },
            .while_statement => |while_value| {
                try self.validateCondition(while_value.condition);
                try self.validateStatements(while_value.body);
            },
            .for_statement => |for_value| {
                switch (for_value.source) {
                    .collection => |collection| try self.validateExpression(collection),
                    .integer_range => |range| {
                        try self.validateExpression(range.start);
                        try self.validateExpression(range.end);
                    },
                }
                try self.validateStatements(for_value.body);
            },
            .break_statement, .continue_statement => {},
            .return_statement => |value| if (value) |expression_value| try self.validateExpression(expression_value),
            .expression_statement => |expression_value| try self.validateExpression(expression_value),
        }
    }
}

pub fn validateCondition(self: anytype, condition_value: Statement.Condition) AnalyzeError!void {
    switch (condition_value) {
        .expression => |value| try self.validateExpression(value),
        .binding => |binding| try self.validateExpression(binding.source),
    }
}

pub fn validateExpression(self: anytype, expression_value: *const Expression) AnalyzeError!void {
    switch (expression_value.value) {
        .integer => |value| if (!integerLiteralFits(value, expression_value.type)) {
            const message = try std.fmt.allocPrint(self.allocator, "integer literal is outside the range of '{s}'", .{typeName(expression_value.type)});
            return self.fail(expression_value.position, message);
        },
        .floating => |lexeme| if (expression_value.type == .float) {
            const value = std.fmt.parseFloat(f32, lexeme) catch return self.fail(expression_value.position, "float literal is outside the range of 'float'");
            if (!std.math.isFinite(value)) return self.fail(expression_value.position, "float literal is outside the range of 'float'");
        },
        .boolean, .string, .null, .variable, .static_field_access, .self, .owner_self, .cascade_target, .optional_unwrap => {},
        .optional_wrap => |value| try self.validateExpression(value),
        .safe_access => |access| {
            try self.validateExpression(access.receiver);
            try self.validateExpression(access.end);
        },
        .string_length => |argument| try self.validateExpression(argument),
        .sequence_literal => |values| for (values) |value| try self.validateExpression(value),
        .collection_method => |collection_method| {
            try self.validateExpression(collection_method.object);
            for (collection_method.arguments) |argument| try self.validateExpression(argument);
        },
        .call => |call| for (call.arguments) |argument| try self.validateExpression(argument),
        .value_call => |call| {
            try self.validateExpression(call.callee);
            if (call.owner) |owner| try self.validateExpression(owner);
            for (call.arguments) |argument| try self.validateExpression(argument);
        },
        .lambda => |lambda| try self.validateStatements(lambda.statements),
        .method_call => |call| {
            try self.validateExpression(call.object);
            for (call.arguments) |argument| try self.validateExpression(argument);
            const called_method = self.methodSymbol(call.method_id);
            const mutable_return = called_method.return_type == .reference and called_method.return_type.reference.mutable;
            if (!called_method.is_mutating and !mutable_return) return;
            const kept_mutable_return = expression_value.type == .reference and expression_value.type.reference.mutable;
            switch (call.receiver) {
                .self, .mutable, .cascade_temporary => {},
                .borrowed_self => if (called_method.is_mutating or kept_mutable_return)
                    return self.fail(call.position, "cannot mutate 'self' while one of its collections is iterated"),
                .immutable => |receiver| {
                    const message = if (receiver.control_binding)
                        try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{receiver.name})
                    else
                        try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on immutable value '{s}'", .{ call.source_name, receiver.name });
                    return self.fail(call.position, message);
                },
                .immutable_field => |name| {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' through let field '{s}'", .{ call.source_name, name });
                    return self.fail(call.position, message);
                },
                .borrowed => |name| if (called_method.is_mutating or kept_mutable_return) {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{name});
                    return self.fail(call.position, message);
                },
                .temporary => {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on a temporary value", .{call.source_name});
                    return self.fail(call.position, message);
                },
            }
        },
        .protocol_method_call => |call| {
            try self.validateExpression(call.object);
            for (call.arguments) |argument| try self.validateExpression(argument);
            switch (call.receiver) {
                .self, .mutable, .cascade_temporary => {},
                .borrowed_self => return self.fail(call.position, "cannot mutate 'self' while one of its collections is iterated"),
                .immutable => |receiver| {
                    const message = if (receiver.control_binding)
                        try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{receiver.name})
                    else
                        try std.fmt.allocPrint(self.allocator, "cannot call protocol method '{s}' on immutable value '{s}'; use 'var'", .{ call.source_name, receiver.name });
                    return self.fail(call.position, message);
                },
                .immutable_field => |name| {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot call protocol method '{s}' through let field '{s}'", .{ call.source_name, name });
                    return self.fail(call.position, message);
                },
                .borrowed => |name| {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{name});
                    return self.fail(call.position, message);
                },
                .temporary => {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot call protocol method '{s}' on a temporary value", .{call.source_name});
                    return self.fail(call.position, message);
                },
            }
        },
        .static_method_call => |call| {
            for (call.arguments) |argument| try self.validateExpression(argument);
        },
        .super_method_call => |call| {
            for (call.arguments) |argument| try self.validateExpression(argument);
        },
        .cascade => |cascade| {
            try self.validateExpression(cascade.object);
            for (cascade.operations) |operation| switch (operation) {
                .method_call => |cascade_method| try self.validateExpression(cascade_method),
                .field_assignment => |field_assignment| try self.validateExpression(field_assignment.value),
            };
        },
        .class_initializer => |initializer| for (initializer.arguments) |argument| try self.validateExpression(argument),
        .structure_initializer => |initializer| for (initializer.fields) |field| try self.validateExpression(field),
        .enum_initializer => |initializer| for (initializer.arguments) |argument| try self.validateExpression(argument),
        .enum_raw_value => |value| try self.validateExpression(value),
        .match_expression => |match_value| {
            try self.validateExpression(match_value.subject);
            for (match_value.branches) |branch| switch (branch.body) {
                .expression => |value| try self.validateExpression(value),
                .statements => |values| try self.validateStatements(values),
            };
        },
        .member_access => |member| try self.validateExpression(member.object),
        .bound_function => |member| try self.validateExpression(member.object),
        .function_reference => {},
        .adapt_function => |value| try self.validateExpression(value),
        .index_access => |access| {
            try self.validateExpression(access.object);
            try self.validateExpression(access.index);
        },
        .slice_access => |access| {
            try self.validateExpression(access.object);
            try self.validateExpression(access.start);
            try self.validateExpression(access.end);
        },
        .move_expression => |move_value| try self.validateExpression(move_value.operand),
        .borrow_expression => |borrow_value| try self.validateExpression(borrow_value.operand),
        .try_expression => |try_value| try self.validateExpression(try_value.operand),
        .unary => |unary| {
            if (unary.operator == .numeric_negate and unary.operand.value == .integer and isInteger(expression_value.type)) {
                const bits = integerBits(expression_value.type);
                const magnitude = unary.operand.value.integer;
                if (isUnsignedInteger(expression_value.type) or magnitude > (@as(u64, 1) << @intCast(bits - 1))) {
                    const message = try std.fmt.allocPrint(self.allocator, "integer literal is outside the range of '{s}'", .{typeName(expression_value.type)});
                    return self.fail(expression_value.position, message);
                }
            } else try self.validateExpression(unary.operand);
        },
        .binary => |binary| {
            try self.validateExpression(binary.left);
            try self.validateExpression(binary.right);
        },
        .conversion => |conversion| try self.validateExpression(conversion.operand),
        .protocol_conversion => |conversion| try self.validateExpression(conversion.operand),
    }
}

pub fn unaryExpression(
    self: anytype,
    unary: Ast.Expression.Unary,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (unary.operator == .borrow) {
        return self.fail(unary.operator_position, "'&' is only valid in parameter declarations; calls use plain arguments");
    }
    const operand = try self.expression(unary.operand, scope);
    const result_type: Type = switch (unary.operator) {
        .logical_not => logical: {
            if (!typeEqual(operand.type, .bool)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "logical operator '!' requires a 'bool' operand, found '{s}'",
                    .{typeName(operand.type)},
                );
                return self.fail(unary.operator_position, message);
            }
            break :logical .bool;
        },
        .numeric_negate => numeric: {
            if (!isNumeric(operand.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "numeric operator '-' requires an 'int' or 'float' operand, found '{s}'",
                    .{typeName(operand.type)},
                );
                return self.fail(unary.operator_position, message);
            }
            break :numeric operand.type;
        },
        .borrow => unreachable,
        .dereference => unreachable,
    };
    return self.newExpression(.{
        .type = result_type,
        .position = unary.operator_position,
        .value = .{ .unary = .{ .operator = unary.operator, .operand = operand } },
    });
}

pub fn moveExpression(
    self: anytype,
    move_value: Ast.Expression.Move,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (move_value.operand.value != .identifier) {
        return self.fail(move_value.operator_position, "'move' requires a complete local binding or parameter");
    }
    const name = move_value.operand.value.identifier;
    const symbol = findSymbol(scope, name) orelse {
        const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
        return self.fail(move_value.operand.position, message);
    };
    if (!try self.isNonCopyableType(symbol.type) and !symbol.control_binding) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "'move' requires a noncopyable value, found '{s}'",
            .{typeName(symbol.type)},
        );
        return self.fail(move_value.operator_position, message);
    }
    if (symbol.state.borrowed_parameter) {
        return self.fail(move_value.operator_position, "a read-reference parameter cannot be consumed with 'move'");
    }
    const operand = try self.variableExpression(move_value.operand.position, name, scope);
    if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow or symbol.state.transient_mutable_borrows != 0) {
        const message = try std.fmt.allocPrint(self.allocator, "cannot move borrowed noncopyable value '{s}'", .{name});
        return self.fail(move_value.operator_position, message);
    }
    if (try self.isNonCopyableType(symbol.type)) {
        symbol.state.owner_available = false;
        symbol.state.consumed_at = move_value.operator_position;
    }
    const resource_dependencies = symbol.state.resource_dependencies;
    symbol.state.resource_dependencies = &.{};
    const deferred_resource_paths = symbol.state.deferred_resource_paths;
    symbol.state.deferred_resource_paths = &.{};
    return self.newExpression(.{
        .type = symbol.type,
        .position = move_value.operator_position,
        .lifetime_depth = symbol.state.lifetime_depth,
        .owner_state = symbol.state,
        .resource_dependencies = resource_dependencies,
        .transfers_resource_dependencies = true,
        .deferred_resource_paths = deferred_resource_paths,
        .value = .{ .move_expression = .{ .operand = operand } },
    });
}

pub const ResultShape = struct {
    enum_symbol: *const EnumSymbol,
    success_type: Type,
    error_type: Type,
    failure_variant_index: usize,
};

pub fn resultShape(self: anytype, value: Type) ?ResultShape {
    if (value != .enumeration or !std.mem.startsWith(u8, value.enumeration.source_name, "Result<")) return null;
    const enum_symbol = self.findEnumByGeneratedName(value.enumeration.generated_name) orelse return null;
    if (enum_symbol.variants.len != 2 or
        !std.mem.eql(u8, enum_symbol.variants[0].source_name, "success") or
        !std.mem.eql(u8, enum_symbol.variants[1].source_name, "failure") or
        enum_symbol.variants[0].associated_types.len > 1 or
        enum_symbol.variants[1].associated_types.len != 1)
    {
        return null;
    }
    return .{
        .enum_symbol = enum_symbol,
        .success_type = if (enum_symbol.variants[0].associated_types.len == 0)
            .void
        else
            enum_symbol.variants[0].associated_types[0],
        .error_type = enum_symbol.variants[1].associated_types[0],
        .failure_variant_index = 1,
    };
}

pub fn tryExpression(
    self: anytype,
    try_value: Ast.Expression.Try,
    scope: *const Scope,
) AnalyzeError!*Expression {
    if (self.current_constructor) return self.fail(try_value.operator_position, "'try' is not available in a constructor");
    if (self.current_drop) return self.fail(try_value.operator_position, "'try' is not available in a drop block");

    const return_shape = self.resultShape(self.current_return_type) orelse {
        return self.fail(try_value.operator_position, "'try' requires the current function or lambda to return a Result");
    };
    const operand = try self.expression(try_value.operand, scope);
    const operand_shape = self.resultShape(operand.type) orelse {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "'try' requires a Result operand, found '{s}'",
            .{typeName(operand.type)},
        );
        return self.fail(try_value.operator_position, message);
    };
    if (try self.isNonCopyableType(operand.type) and !self.isNonCopyableTemporary(operand)) {
        return self.fail(try_value.operator_position, "a named noncopyable Result must be consumed with 'try move result'");
    }
    if (!typeEqual(operand_shape.error_type, return_shape.error_type)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "'try' cannot propagate error type '{s}' through Result error type '{s}'",
            .{ typeName(operand_shape.error_type), typeName(return_shape.error_type) },
        );
        return self.fail(try_value.operator_position, message);
    }
    const temporary_name = try std.fmt.allocPrint(self.allocator, "silexTry{d}", .{self.next_symbol_id});
    self.next_symbol_id += 1;
    self.releaseTransientBorrow(operand);
    return self.newExpression(.{
        .type = operand_shape.success_type,
        .position = try_value.operator_position,
        .lifetime_depth = operand.lifetime_depth,
        .value = .{ .try_expression = .{
            .operand = operand,
            .temporary_name = temporary_name,
            .error_type = operand_shape.error_type,
            .return_enum_generated_name = return_shape.enum_symbol.generated_name,
            .failure_variant_index = return_shape.failure_variant_index,
        } },
    });
}

pub fn argumentForMode(
    self: anytype,
    argument: *const Ast.Expression,
    scope: *const Scope,
    expected_type: Type,
    mode: Ast.ParameterMode,
) AnalyzeError!*Expression {
    if (argument.value == .borrow_expression) {
        return self.fail(argument.position, "reference arguments are selected by the parameter signature; pass the value without '@'");
    }
    if (argument.value == .unary and argument.value.unary.operator == .borrow) {
        return self.fail(argument.position, "reference arguments are selected by the parameter signature; pass the place without '&'");
    }
    if (argument.value == .identifier) {
        if (findSymbol(scope, argument.value.identifier)) |symbol| {
            if (symbol.state.borrowed_parameter and symbol.type == .view and
                mode == .borrow and typeEqual(symbol.type, expected_type))
            {
                return self.variableExpression(argument.position, argument.value.identifier, scope);
            }
        }
    }
    if (argument.value == .identifier and findSymbol(scope, argument.value.identifier) != null and
        findSymbol(scope, argument.value.identifier).?.type == .reference)
    {
        const existing_reference = try self.expressionForExpected(argument, scope, null);
        const reference = existing_reference.type.reference;
        if (mode == .value or !typeEqual(reference.target.*, expected_type)) return existing_reference;
        if (mode == .mutable_reference and !reference.mutable) {
            return self.fail(argument.position, "a shared alias cannot be passed to a mutable reference parameter");
        }
        if (reference.target.* == .view) {
            return self.newExpression(.{
                .type = reference.target.*,
                .position = argument.position,
                .borrow = existing_reference.borrow,
                .borrowed_parameter = existing_reference.borrowed_parameter,
                .value = existing_reference.value,
            });
        }
        return self.newExpression(.{
            .type = reference.target.*,
            .position = argument.position,
            .borrow = existing_reference.borrow,
            .value = .{ .unary = .{ .operator = .dereference, .operand = existing_reference } },
        });
    }
    return switch (mode) {
        .value => self.expressionForExpected(argument, scope, expected_type),
        .mutable_reference => self.mutableReferenceArgument(argument, scope, expected_type),
        .borrow => self.readBorrowArgument(argument, scope, expected_type),
    };
}

pub fn nativeResourceDropArgument(
    self: anytype,
    argument: *const Ast.Expression,
    scope: *const Scope,
    expected_type: Type,
) AnalyzeError!*Expression {
    if (argument.value != .identifier) {
        const value = try self.expressionForExpected(argument, scope, expected_type);
        if (!self.isNonCopyableTemporary(value)) {
            return self.fail(argument.position, "a native resource destructor requires a complete owner or temporary");
        }
        return value;
    }
    const symbol = findSymbol(scope, argument.value.identifier) orelse return self.expressionForExpected(argument, scope, expected_type);
    if (symbol.state.borrowed_parameter) return self.fail(argument.position, "a read-reference parameter cannot be destroyed");
    const operand = try self.variableExpression(argument.position, argument.value.identifier, scope);
    if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow or symbol.state.transient_mutable_borrows != 0) {
        return self.fail(argument.position, "cannot destroy a borrowed native resource");
    }
    if (symbol.state.resource_dependents != 0) {
        return self.fail(argument.position, "cannot destroy a native resource while acquired resources still depend on it");
    }
    for (symbol.state.resource_dependencies) |dependency| dependency.resource_dependents -= 1;
    symbol.state.resource_dependencies = &.{};
    symbol.state.owner_available = false;
    symbol.state.consumed_at = argument.position;
    return self.newExpression(.{
        .type = symbol.type,
        .position = argument.position,
        .value = .{ .move_expression = .{ .operand = operand } },
    });
}

pub fn readBorrowArgument(
    self: anytype,
    argument: *const Ast.Expression,
    scope: *const Scope,
    expected_type: Type,
) AnalyzeError!*Expression {
    return self.readBorrowValue(.{
        .operator_position = argument.position,
        .operand = @constCast(argument),
    }, scope, expected_type);
}

pub fn readBorrowValue(
    self: anytype,
    borrow_value: Ast.Expression.Borrow,
    scope: *const Scope,
    expected_type: ?Type,
) AnalyzeError!*Expression {
    var root: ?*BindingState = null;
    if (assignmentRoot(borrow_value.operand)) |assignment_root| switch (assignment_root) {
        .static => {},
        .self => root = &self.current_self_state,
        .variable => |name| {
            const symbol = findSymbol(scope, name) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
                return self.fail(borrow_value.operator_position, message);
            };
            root = symbol.state;
        },
    };
    if (root) |state| {
        if (state.mutable_borrow or state.transient_mutable_borrows != 0) {
            return self.fail(borrow_value.operator_position, "cannot read-borrow a value while it is mutably borrowed");
        }
    }
    var operand = if (borrow_value.operand.value == .slice_access)
        try self.sliceAccessExpression(borrow_value.operand.value.slice_access, scope, true)
    else
        try self.expressionForExpected(borrow_value.operand, scope, expected_type);
    if (expected_type) |expected| {
        operand = try self.coerce(operand, expected);
        if (!typeEqual(operand.type, expected)) return operand;
    }
    const borrow = Borrow{ .root = root, .mutable = false };
    if (root) |state| state.immutable_borrows += 1;
    const result_type = if (operand.type == .view) reference_type: {
        const target = try self.allocator.create(Type);
        target.* = operand.type;
        break :reference_type Type{ .reference = .{ .target = target, .mutable = false } };
    } else operand.type;
    return self.newExpression(.{
        .type = result_type,
        .position = borrow_value.operator_position,
        .borrow = borrow,
        .owns_borrow = true,
        .borrowed_parameter = operand.borrowed_parameter,
        .value = .{ .borrow_expression = .{ .operand = operand } },
    });
}

pub fn mutableReferenceArgument(
    self: anytype,
    argument: *const Ast.Expression,
    scope: *const Scope,
    expected_type: Type,
) AnalyzeError!*Expression {
    const root = assignmentRoot(argument) orelse {
        return self.fail(argument.position, "a mutable reference parameter requires a variable, field, or collection element");
    };
    var root_state: ?*BindingState = null;
    switch (root) {
        .static => {},
        .self => {
            if (self.current_method_index == null and !self.current_constructor and !self.current_drop) return self.fail(argument.position, "'self' is only available inside a method, constructor, or drop block");
            root_state = &self.current_self_state;
            self.current_method_direct_mutation = true;
        },
        .variable => |name| {
            const symbol = findSymbol(scope, name) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
                return self.fail(argument.position, message);
            };
            if (symbol.mutability != .mutable) {
                const message = if (symbol.control_binding)
                    try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{name})
                else
                    try std.fmt.allocPrint(self.allocator, "cannot pass immutable variable '{s}' to a mutable reference parameter", .{name});
                return self.fail(argument.position, message);
            }
            root_state = symbol.state;
        },
    }
    if (root_state) |state| {
        if (state.immutable_borrows != 0) {
            return self.fail(argument.position, "cannot pass a value to a mutable reference parameter while it is read-borrowed");
        }
    }
    const operand = if (argument.value == .identifier and findSymbol(scope, argument.value.identifier) != null and
        findSymbol(scope, argument.value.identifier).?.unwrap_optional)
    narrowed_operand: {
        const symbol = findSymbol(scope, argument.value.identifier).?;
        try self.recordSymbolCapture(symbol, argument.position);
        symbol.state.narrowed_valid = false;
        break :narrowed_operand try self.newExpression(.{
            .type = symbol.original_type.?,
            .position = argument.position,
            .value = .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
        });
    } else try self.expression(argument, scope);
    if (operand.value == .enum_raw_value) return self.fail(argument.position, "enum property 'raw_value' cannot be passed to a mutable reference parameter");
    if (self.immutableFieldInPlace(operand)) |field_candidate| {
        const message = try std.fmt.allocPrint(self.allocator, "cannot pass let field '{s}' to a mutable reference parameter", .{field_candidate.symbol.source_name});
        return self.fail(argument.position, message);
    }
    if (!typeEqual(operand.type, expected_type)) return operand;
    const borrow = Borrow{ .root = root_state, .mutable = true, .transient = true };
    if (root_state) |state| state.transient_mutable_borrows += 1;
    return self.newExpression(.{
        .type = operand.type,
        .position = argument.position,
        .borrow = borrow,
        .owns_borrow = true,
        .value = .{ .unary = .{ .operator = .borrow, .operand = operand } },
    });
}

pub fn borrowExpression(
    self: anytype,
    unary: Ast.Expression.Unary,
    scope: *const Scope,
    mutable: bool,
) AnalyzeError!*Expression {
    const symbol = try self.placeRootSymbol(unary.operand, scope, unary.operator_position);
    const state = if (symbol) |value| value.state else &self.current_self_state;
    if (mutable) {
        if (symbol != null and symbol.?.mutability != .mutable) {
            const message = if (symbol.?.control_binding)
                try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{symbol.?.source_name})
            else
                try std.fmt.allocPrint(self.allocator, "cannot mutably borrow immutable variable '{s}'", .{symbol.?.source_name});
            return self.fail(unary.operator_position, message);
        }
        if (state.mutable_borrow or state.immutable_borrows != 0) {
            return self.fail(unary.operator_position, "cannot mutably borrow a value because it is already borrowed");
        }
    } else if (state.mutable_borrow) {
        return self.fail(unary.operator_position, "cannot immutably borrow a value while it is mutably borrowed");
    }
    const operand = if (unary.operand.value == .slice_access)
        try self.sliceAccessExpression(unary.operand.value.slice_access, scope, true)
    else
        try self.expression(unary.operand, scope);
    if (operand.value == .slice_access) operand.value.slice_access.mutable = mutable;
    if (mutable) if (self.immutableFieldInPlace(operand)) |field_candidate| {
        const message = try std.fmt.allocPrint(self.allocator, "cannot mutably borrow let field '{s}'", .{field_candidate.symbol.source_name});
        return self.fail(unary.operator_position, message);
    };
    const target = try self.allocator.create(Type);
    target.* = operand.type;
    const borrow = Borrow{ .root = state, .mutable = mutable };
    if (mutable) state.mutable_borrow = true else state.immutable_borrows += 1;
    return self.newExpression(.{
        .type = .{ .reference = .{ .target = target, .mutable = mutable } },
        .position = unary.operator_position,
        .borrow = borrow,
        .owns_borrow = true,
        .value = .{ .unary = .{ .operator = unary.operator, .operand = operand } },
    });
}

pub fn appendLiteralExpectedType(
    self: anytype,
    values: []const *Ast.Expression,
    element_type: Type,
) !Type {
    const element_is_collection = element_type == .list or element_type == .fixed_array;
    const is_range = !element_is_collection or (values.len > 0 and values[0].value == .sequence_literal);
    if (!is_range) return element_type;
    const element = try self.allocator.create(Type);
    element.* = element_type;
    return .{ .list = element };
}

pub fn requireBinaryOperands(
    self: anytype,
    position: Source.Position,
    operator_name: []const u8,
    required_type: Type,
    left_type: Type,
    right_type: Type,
    result_type: Type,
) AnalyzeError!Type {
    if (typeEqual(left_type, required_type) and typeEqual(right_type, required_type)) return result_type;
    const message = try std.fmt.allocPrint(
        self.allocator,
        "{s} requires '{s}' operands, found '{s}' and '{s}'",
        .{ operator_name, typeName(required_type), typeName(left_type), typeName(right_type) },
    );
    return self.fail(position, message);
}

pub fn requireNumericOperands(
    self: anytype,
    position: Source.Position,
    operator_name: []const u8,
    left_type: Type,
    right_type: Type,
) AnalyzeError!void {
    if (isNumeric(left_type) and isNumeric(right_type)) return;
    const message = try std.fmt.allocPrint(
        self.allocator,
        "{s} requires numeric operands, found '{s}' and '{s}'",
        .{ operator_name, try allocatedTypeName(self.allocator, left_type), try allocatedTypeName(self.allocator, right_type) },
    );
    return self.fail(position, message);
}

pub fn coerce(self: anytype, expression_value: *Expression, target_type: Type) AnalyzeError!*Expression {
    if (typeEqual(expression_value.type, target_type)) {
        if (expression_value.value == .integer and !integerLiteralFits(expression_value.value.integer, target_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "integer literal is outside the range of '{s}'", .{typeName(target_type)});
            return self.fail(expression_value.position, message);
        }
        if (expression_value.value == .floating and target_type == .float) {
            const value = std.fmt.parseFloat(f32, expression_value.value.floating) catch {
                return self.fail(expression_value.position, "float literal is outside the range of 'float'");
            };
            if (!std.math.isFinite(value)) return self.fail(expression_value.position, "float literal is outside the range of 'float'");
        }
        return expression_value;
    }
    if (expression_value.type == .reference and target_type == .reference and
        expression_value.type.reference.mutable and !target_type.reference.mutable and
        typeEqual(expression_value.type.reference.target.*, target_type.reference.target.*) and
        expression_value.owns_borrow)
    {
        const mutable_borrow = expression_value.borrow orelse return expression_value;
        if (!mutable_borrow.mutable) return expression_value;
        releaseBorrow(mutable_borrow);
        const shared_borrow = Borrow{ .root = mutable_borrow.root, .mutable = false };
        if (shared_borrow.root) |root| root.immutable_borrows += 1;
        expression_value.type = target_type;
        expression_value.borrow = shared_borrow;
        return expression_value;
    }
    if (target_type == .protocol and expression_value.type == .structure) {
        if (try self.isNonCopyableType(expression_value.type)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "noncopyable value '{s}' cannot be converted to dynamic protocol value '{s}'",
                .{ expression_value.type.structure.source_name, target_type.protocol.source_name },
            );
            return self.fail(expression_value.position, message);
        }
        const structure_index = self.findStructureIndexByGeneratedName(expression_value.type.structure.generated_name).?;
        if (self.structureConformsToProtocol(structure_index, target_type.protocol.index, expression_value.position.file)) {
            return self.newExpression(.{
                .type = target_type,
                .position = expression_value.position,
                .lifetime_depth = expression_value.lifetime_depth,
                .value = .{ .protocol_conversion = .{
                    .operand = expression_value,
                    .witness_name = try std.fmt.allocPrint(
                        self.allocator,
                        "SilexWitness{d}_{d}",
                        .{ target_type.protocol.index, structure_index },
                    ),
                } },
            });
        }
    }
    if (self.classUpcastDistance(expression_value.type, target_type) != null) {
        return self.newExpression(.{
            .type = target_type,
            .position = expression_value.position,
            .lifetime_depth = expression_value.lifetime_depth,
            .value = .{ .conversion = .{ .operand = expression_value, .target_type = target_type } },
        });
    }
    if (target_type == .optional) {
        if (expression_value.type == .null) {
            expression_value.type = target_type;
            return expression_value;
        }
        if (expression_value.type == .optional and self.implicitConversionScore(
            expression_value.type.optional.*,
            target_type.optional.*,
            expression_value.position.file,
        ) != null) {
            return self.newExpression(.{
                .type = target_type,
                .position = expression_value.position,
                .lifetime_depth = expression_value.lifetime_depth,
                .value = .{ .optional_wrap = expression_value },
            });
        }
        const contained_value = try self.coerce(expression_value, target_type.optional.*);
        if (typeEqual(contained_value.type, target_type.optional.*)) {
            return self.newExpression(.{
                .type = target_type,
                .position = contained_value.position,
                .lifetime_depth = contained_value.lifetime_depth,
                .value = .{ .optional_wrap = contained_value },
            });
        }
    }
    if (expression_value.value == .integer and isInteger(target_type)) {
        const value = expression_value.value.integer;
        if (!integerLiteralFits(value, target_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "integer literal is outside the range of '{s}'", .{typeName(target_type)});
            return self.fail(expression_value.position, message);
        }
        expression_value.type = target_type;
        return expression_value;
    }
    if (expression_value.value == .floating and target_type == .float64) {
        expression_value.type = .float64;
        return expression_value;
    }
    if (expression_value.value == .unary and expression_value.value.unary.operator == .numeric_negate and
        expression_value.value.unary.operand.value == .integer and isInteger(target_type) and !isUnsignedInteger(target_type))
    {
        const magnitude = expression_value.value.unary.operand.value.integer;
        const limit = @as(u64, 1) << @intCast(integerBits(target_type) - 1);
        if (magnitude > limit) {
            const message = try std.fmt.allocPrint(self.allocator, "integer literal is outside the range of '{s}'", .{typeName(target_type)});
            return self.fail(expression_value.position, message);
        }
        expression_value.type = target_type;
        return expression_value;
    }
    if (canWiden(expression_value.type, target_type)) {
        return self.newExpression(.{
            .type = target_type,
            .position = expression_value.position,
            .value = .{ .conversion = .{ .operand = expression_value, .target_type = target_type } },
        });
    }
    return expression_value;
}
