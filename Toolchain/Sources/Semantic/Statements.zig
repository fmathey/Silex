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
pub fn statements(
    self: anytype,
    ast_statements: []const Ast.Statement,
    scope: *Scope,
) AnalyzeError![]const Statement {
    var result: std.ArrayList(Statement) = .empty;
    for (ast_statements) |ast_statement| {
        try result.append(self.allocator, try self.statement(ast_statement, scope));
        if (!astStatementFallsThrough(ast_statement)) break;
    }
    return result.toOwnedSlice(self.allocator);
}

pub fn statement(self: anytype, ast: Ast.Statement, scope: *Scope) AnalyzeError!Statement {
    return switch (ast) {
        .print => |print| print_statement: {
            const argument = try self.expression(print.argument, scope);
            if (!isPrintable(argument.type)) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot print a value of type '{s}'", .{typeName(argument.type)});
                return self.fail(print.position, message);
            }
            break :print_statement .{ .print = argument };
        },
        .assertion => |assertion_value| self.analyzeAssertion(assertion_value, scope),
        .panic_statement => |panic_value| self.analyzePanic(panic_value, scope),
        .variable_declaration => |declaration| self.variableDeclaration(declaration, scope),
        .assignment => |ast_assignment| self.assignment(ast_assignment, scope),
        .if_statement => |if_statement| self.ifStatement(if_statement, scope),
        .while_statement => |while_statement| self.whileStatement(while_statement, scope),
        .for_statement => |for_statement| self.forStatement(for_statement, scope),
        .break_statement => |position| loop_control: {
            if (self.loop_depth == 0) return self.fail(position, "'break' is only available inside a loop");
            const flow = self.current_loop_flow.?;
            try flow.break_states.append(self.allocator, try self.captureOwnerStates(flow.tracked));
            break :loop_control .break_statement;
        },
        .continue_statement => |position| loop_control: {
            if (self.loop_depth == 0) return self.fail(position, "'continue' is only available inside a loop");
            const flow = self.current_loop_flow.?;
            try flow.continue_states.append(self.allocator, try self.captureOwnerStates(flow.tracked));
            break :loop_control .continue_statement;
        },
        .return_statement => |return_statement| self.returnStatement(return_statement, scope),
        .expression_statement => |expression_statement| .{ .expression_statement = try self.expression(expression_statement, scope) },
    };
}

pub fn analyzeAssertion(self: anytype, ast: Ast.Statement.Assert, scope: *const Scope) AnalyzeError!Statement {
    const condition = try self.expression(ast.condition, scope);
    if (!typeEqual(condition.type, .bool)) {
        const message = try typeMismatchMessage(self.allocator, .bool, condition.type);
        return self.fail(ast.condition.position, message);
    }
    const message = try self.expression(ast.message, scope);
    if (!typeEqual(message.type, .str)) {
        const diagnostic = try typeMismatchMessage(self.allocator, .str, message.type);
        return self.fail(ast.message.position, diagnostic);
    }
    return .{ .assertion = .{ .position = ast.position, .condition = condition, .message = message } };
}

pub fn analyzePanic(self: anytype, ast: Ast.Statement.Panic, scope: *const Scope) AnalyzeError!Statement {
    const message = try self.expression(ast.message, scope);
    if (!typeEqual(message.type, .str)) {
        const diagnostic = try typeMismatchMessage(self.allocator, .str, message.type);
        return self.fail(ast.message.position, diagnostic);
    }
    return .{ .panic_statement = .{ .position = ast.position, .message = message } };
}

pub fn variableDeclaration(
    self: anytype,
    declaration: Ast.Statement.VariableDeclaration,
    scope: *Scope,
) AnalyzeError!Statement {
    try self.requireAvailableVariableName(scope, declaration.name, declaration.name_position);

    const declared_annotation_type = if (declaration.annotation) |annotation|
        try typeFromAnnotation(self, annotation, declaration.name_position)
    else
        null;
    if (declared_annotation_type != null and declared_annotation_type.? == .view) {
        return self.fail(declaration.name_position, "a view type must be borrowed as '@T[..]' or '&T[..]'");
    }
    if (declaration.initializer == null and declared_annotation_type != null and isUniqueOwnerType(declared_annotation_type.?)) {
        const structure = self.findStructureByGeneratedName(declared_annotation_type.?.structure.generated_name).?;
        if (!self.uniqueOwnerStorageVisible(structure, declaration.name_position.file)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "initializer of unique resource struct '{s}' is private to its module",
                .{structure.source_name},
            );
            return self.fail(declaration.name_position, message);
        }
    }
    var initializer = if (declaration.initializer) |ast_initializer|
        try self.expressionForExpected(ast_initializer, scope, declared_annotation_type)
    else
        try self.defaultExpression(declared_annotation_type.?, declaration.name_position);
    if (typeEqual(initializer.type, .void)) {
        const position = if (declaration.initializer) |value| value.position else declaration.name_position;
        return self.fail(position, "variable initializer cannot have type 'void'");
    }
    const declared_type = declared_annotation_type orelse inferred: {
        if (declaration.mutability == .immutable and initializer.type == .reference and
            initializer.type.reference.mutable and initializer.owns_borrow)
        {
            break :inferred Type{ .reference = .{
                .target = initializer.type.reference.target,
                .mutable = false,
            } };
        }
        break :inferred initializer.type;
    };
    initializer = try self.coerce(initializer, declared_type);
    if (!typeEqual(declared_type, initializer.type)) {
        const message = try typeMismatchMessage(self.allocator, declared_type, initializer.type);
        return self.fail(if (declaration.initializer) |value| value.position else declaration.name_position, message);
    }
    try self.rejectUniqueOwnerComposition(declared_type, true, declaration.name_position);
    if (try self.isNonCopyableType(declared_type) and !self.isNonCopyableTemporary(initializer)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "cannot copy noncopyable value '{s}'; initialize it directly from a temporary value or use 'move'",
            .{typeName(declared_type)},
        );
        return self.fail(if (declaration.initializer) |value| value.position else declaration.name_position, message);
    }

    if (declaration.mutability == .immutable and declared_type != .list and declared_type != .fixed_array and declared_type != .reference) {
        try self.requireIndependentLetType(declared_type, declaration.name_position);
    }
    if (declared_type == .reference and declared_type.reference.mutable and declaration.mutability != .mutable) {
        return self.fail(declaration.name_position, "a mutable reference must be declared with 'var'");
    }
    const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
    self.next_symbol_id += 1;
    const state = try self.newBindingState(declared_type);
    if (try self.isNonCopyableType(declared_type)) {
        state.resource_dependencies = initializer.resource_dependencies;
        state.deferred_resource_paths = initializer.deferred_resource_paths;
        if (!initializer.transfers_resource_dependencies) {
            for (state.resource_dependencies) |dependency| dependency.resource_dependents += 1;
        }
    }
    if (scope.depth < initializer.lifetime_depth) {
        return self.fail(declaration.name_position, "capturing function value cannot outlive one of its captures");
    }
    state.lifetime_depth = initializer.lifetime_depth;
    if (declared_type == .reference) {
        const borrow = initializer.borrow orelse return self.fail(declaration.name_position, "a reference initializer must borrow a place");
        if (initializer.owns_borrow) {
            try scope.borrows.append(self.allocator, borrow);
            initializer.owns_borrow = false;
            state.reference = borrow;
        } else {
            if (borrow.mutable) return self.fail(declaration.name_position, "cannot copy a mutable reference");
            const copy = try self.copyBorrow(borrow);
            try scope.borrows.append(self.allocator, copy);
            state.reference = copy;
        }
    }
    try scope.symbols.append(self.allocator, .{
        .source_name = declaration.name,
        .generated_name = generated_name,
        .type = declared_type,
        .mutability = declaration.mutability,
        .state = state,
        .scope_depth = scope.depth,
        .immutable_collection_shell = declaration.mutability == .immutable and
            (declared_type == .list or declared_type == .fixed_array),
    });

    return .{ .variable_declaration = .{
        .source_name = declaration.name,
        .position = declaration.name_position,
        .generated_name = generated_name,
        .type = declared_type,
        .is_noncopyable = try self.isNonCopyableType(declared_type),
        .mutability = declaration.mutability,
        .initializer = initializer,
        .capture_box = &state.capture_box,
    } };
}

pub fn requireAvailableVariableName(
    self: anytype,
    scope: *const Scope,
    name: []const u8,
    position: Source.Position,
) AnalyzeError!void {
    if (findInCurrentScope(scope, name) != null) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "variable '{s}' is already declared in this scope",
            .{name},
        );
        return self.fail(position, message);
    }
    const parent = scope.parent orelse return;
    if (findSymbol(parent, name) == null) return;
    const message = try std.fmt.allocPrint(
        self.allocator,
        "variable '{s}' is already declared in an enclosing scope",
        .{name},
    );
    return self.fail(position, message);
}

pub fn assignment(
    self: anytype,
    ast: Ast.Statement.Assignment,
    scope: *const Scope,
) AnalyzeError!Statement {
    if (ast.target.value == .unary and ast.target.value.unary.operator == .dereference) {
        const target = try self.expression(ast.target, scope);
        const operand = target.value.unary.operand;
        const reference = operand.type.reference;
        if (!reference.mutable) return self.fail(ast.position, "cannot assign through an immutable reference");
        var value: ?*Expression = null;
        if (ast.value) |ast_value| value = try self.expressionForExpected(ast_value, scope, target.type);
        return self.checkedAssignment(ast, target, value, scope);
    }

    const root = assignmentRoot(ast.target) orelse return self.fail(ast.position, "invalid assignment target");
    var prepared_target: ?*Expression = null;
    switch (root) {
        .static => {},
        .self => {
            if (self.current_method_index == null and !self.current_constructor and !self.current_drop) return self.fail(ast.position, "'self' is only available inside a method, constructor, or drop block");
            if (ast.target.value == .self) return self.fail(ast.position, "cannot assign to 'self'");
            if (self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0) {
                return self.fail(ast.position, "cannot mutate 'self' while one of its collections is iterated");
            }
            self.current_method_direct_mutation = true;
        },
        .variable => |root_name| {
            const symbol = findSymbol(scope, root_name) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{root_name});
                return self.fail(ast.position, message);
            };
            if (symbol.mutability == .immutable) {
                if ((symbol.read_iteration or symbol.immutable_collection_shell) and ast.target.value != .identifier) {
                    prepared_target = if (ast.target.value == .member_access)
                        try self.memberAccessExpressionRaw(ast.target.value.member_access, scope, false)
                    else
                        try self.expression(ast.target, scope);
                    if (!mutationReachesClassIdentity(prepared_target.?)) {
                        const message = if (symbol.control_binding)
                            try std.fmt.allocPrint(
                                self.allocator,
                                "cannot assign to immutable control binding '{s}'; use 'var' in the header",
                                .{root_name},
                            )
                        else
                            try std.fmt.allocPrint(
                                self.allocator,
                                "cannot assign to immutable variable '{s}'",
                                .{root_name},
                            );
                        return self.fail(ast.position, message);
                    }
                } else {
                    const message = if (symbol.control_binding)
                        try std.fmt.allocPrint(
                            self.allocator,
                            "cannot assign to immutable control binding '{s}'; use 'var' in the header",
                            .{root_name},
                        )
                    else
                        try std.fmt.allocPrint(
                            self.allocator,
                            "cannot assign to immutable variable '{s}'",
                            .{root_name},
                        );
                    return self.fail(ast.position, message);
                }
            }
            if (prepared_target == null and (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow)) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{root_name});
                return self.fail(ast.position, message);
            }
        },
    }

    if (ast.target.value == .identifier) {
        const symbol = findSymbol(scope, ast.target.value.identifier).?;
        if (try self.isNonCopyableType(symbol.type)) return self.uniqueOwnerAssignment(ast, symbol, scope);
    }

    const target = prepared_target orelse if (ast.target.value == .identifier and findSymbol(scope, ast.target.value.identifier) != null and
        findSymbol(scope, ast.target.value.identifier).?.unwrap_optional)
    narrowed_assignment: {
        const symbol = findSymbol(scope, ast.target.value.identifier).?;
        try self.recordSymbolCapture(symbol, ast.target.position);
        symbol.state.narrowed_valid = false;
        break :narrowed_assignment try self.newExpression(.{
            .type = symbol.original_type.?,
            .position = ast.target.position,
            .value = .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
        });
    } else if (ast.target.value == .member_access)
        try self.memberAccessExpressionRaw(ast.target.value.member_access, scope, false)
    else
        try self.expression(ast.target, scope);

    if (target.value == .enum_raw_value) return self.fail(ast.position, "enum property 'raw_value' is read-only");

    if (self.immutableFieldInPlace(target)) |field_candidate| {
        const direct_constructor_initialization = self.current_constructor and
            ast.operator == .assign and
            target.value == .member_access and
            target.value.member_access.object.value == .self and
            self.current_structure_index.? == field_candidate.structure_index and
            field_candidate.symbol.ast_initializer == null;
        if (!direct_constructor_initialization) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot mutate let field '{s}'", .{field_candidate.symbol.source_name});
            return self.fail(ast.position, message);
        }
    }

    var value: ?*Expression = null;
    if (ast.value) |ast_value| value = try self.expressionForExpected(ast_value, scope, target.type);

    if (try self.isNonCopyableType(target.type)) {
        if (ast.operator != .assign) {
            const message = try std.fmt.allocPrint(self.allocator, "operator '{s}' is not available for noncopyable value '{s}'", .{ assignmentOperatorText(ast.operator), typeName(target.type) });
            return self.fail(ast.position, message);
        }
        value = try self.coerce(value.?, target.type);
        if (!typeEqual(target.type, value.?.type)) {
            const message = try typeMismatchMessage(self.allocator, target.type, value.?.type);
            return self.fail(ast.value.?.position, message);
        }
        if (!self.isNonCopyableTemporary(value.?)) {
            const message = try std.fmt.allocPrint(self.allocator, "noncopyable value '{s}' must be assigned from a temporary or with 'move'", .{typeName(target.type)});
            return self.fail(ast.value.?.position, message);
        }
    }

    return self.checkedAssignment(ast, target, value, scope);
}

pub fn uniqueOwnerAssignment(
    self: anytype,
    ast: Ast.Statement.Assignment,
    symbol: *const Symbol,
    scope: *const Scope,
) AnalyzeError!Statement {
    if (ast.operator != .assign) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "operator '{s}' is not available for unique resource '{s}'",
            .{ assignmentOperatorText(ast.operator), typeName(symbol.type) },
        );
        return self.fail(ast.position, message);
    }
    const ast_value = ast.value.?;
    if (ast_value.value == .move_expression and
        ast_value.value.move_expression.operand.value == .identifier and
        std.mem.eql(u8, ast_value.value.move_expression.operand.value.identifier, symbol.source_name))
    {
        const message = try std.fmt.allocPrint(self.allocator, "cannot move unique resource '{s}' into itself", .{symbol.source_name});
        return self.fail(ast_value.value.move_expression.operator_position, message);
    }
    var value = try self.expressionForExpected(ast_value, scope, symbol.type);
    value = try self.coerce(value, symbol.type);
    if (!typeEqual(symbol.type, value.type)) {
        const message = try typeMismatchMessage(self.allocator, symbol.type, value.type);
        return self.fail(ast_value.position, message);
    }
    if (!self.isNonCopyableTemporary(value)) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "noncopyable value '{s}' must be assigned from a temporary or with 'move'",
            .{typeName(symbol.type)},
        );
        return self.fail(ast_value.position, message);
    }
    if (symbol.scope_depth < value.lifetime_depth) {
        return self.fail(ast_value.position, "capturing function value cannot be stored in a longer-lived destination");
    }
    const target = try self.newExpression(.{
        .type = symbol.type,
        .position = ast.target.position,
        .value = .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
    });
    if (symbol.state.resource_dependents != 0) {
        return self.fail(ast.position, "cannot replace a native resource while acquired resources still depend on it");
    }
    for (symbol.state.resource_dependencies) |dependency| dependency.resource_dependents -= 1;
    symbol.state.resource_dependencies = value.resource_dependencies;
    symbol.state.deferred_resource_paths = value.deferred_resource_paths;
    symbol.state.lifetime_depth = value.lifetime_depth;
    if (!value.transfers_resource_dependencies) {
        for (symbol.state.resource_dependencies) |dependency| dependency.resource_dependents += 1;
    }
    symbol.state.owner_available = true;
    symbol.state.consumed_at = null;
    return .{ .assignment = .{
        .position = ast.position,
        .target = target,
        .operator = .assign,
        .value = value,
    } };
}

pub fn checkedAssignment(
    self: anytype,
    ast: Ast.Statement.Assignment,
    target: *Expression,
    initial_value: ?*Expression,
    scope: *const Scope,
) AnalyzeError!Statement {
    var value = initial_value;
    switch (ast.operator) {
        .assign => {
            value = try self.coerce(value.?, target.type);
            if (!typeEqual(target.type, value.?.type)) {
                const message = try typeMismatchMessage(self.allocator, target.type, value.?.type);
                return self.fail(ast.value.?.position, message);
            }
            if (target.type == .function and target.type.function.owner != null and value.?.type.function.owner == null) {
                value = try self.newExpression(.{
                    .type = target.type,
                    .position = value.?.position,
                    .lifetime_depth = value.?.lifetime_depth,
                    .value = .{ .adapt_function = value.? },
                });
            }
            if (value.?.borrowed_parameter) {
                if (assignmentRoot(ast.target)) |root| switch (root) {
                    .self, .static => return self.fail(ast.value.?.position, "a read-reference parameter cannot be stored beyond its call"),
                    .variable => {},
                };
            }
            const destination_depth = assignmentDestinationDepth(ast.target, self, scope);
            if (destination_depth < value.?.lifetime_depth) {
                return self.fail(ast.value.?.position, "capturing function value cannot be stored in a longer-lived destination");
            }
            if (assignmentRoot(ast.target)) |root| switch (root) {
                .variable => |name| {
                    if (findSymbol(scope, name)) |symbol| symbol.state.lifetime_depth = value.?.lifetime_depth;
                },
                .self, .static => {},
            };
            if (target.deferred_storage_state) |state| {
                state.deferred_resource_paths = try self.replacedDeferredResourcePaths(
                    state.deferred_resource_paths,
                    target.deferred_storage_path,
                    value.?.deferred_resource_paths,
                );
            }
        },
        .add, .subtract, .multiply, .divide => {
            value = try self.coerce(value.?, target.type);
            const supports_string_append = ast.operator == .add and typeEqual(target.type, .str);
            if (!typeEqual(target.type, value.?.type)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "operator '{s}' requires a compatible value, found '{s}' and '{s}'",
                    .{ assignmentOperatorText(ast.operator), typeName(target.type), typeName(value.?.type) },
                );
                return self.fail(ast.position, message);
            }
            if (!isNumeric(target.type) and !supports_string_append) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "operator '{s}' requires a numeric target, found '{s}'",
                    .{ assignmentOperatorText(ast.operator), typeName(target.type) },
                );
                return self.fail(ast.position, message);
            }
        },
        .increment, .decrement => if (!isNumeric(target.type)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "operator '{s}' requires a numeric target, found '{s}'",
                .{ assignmentOperatorText(ast.operator), typeName(target.type) },
            );
            return self.fail(ast.position, message);
        },
    }
    return .{ .assignment = .{
        .position = ast.position,
        .target = target,
        .operator = ast.operator,
        .value = value,
    } };
}

pub fn snapshotOwnerStates(self: anytype, scope: *const Scope) Allocator.Error![]const OwnerStateSnapshot {
    var snapshots: std.ArrayList(OwnerStateSnapshot) = .empty;
    var current: ?*const Scope = scope;
    while (current) |visible_scope| : (current = visible_scope.parent) {
        for (visible_scope.symbols.items) |symbol| {
            if (!try self.isNonCopyableType(symbol.type)) continue;
            try snapshots.append(self.allocator, .{
                .name = symbol.source_name,
                .state = symbol.state,
                .available = symbol.state.owner_available,
                .consumed_at = symbol.state.consumed_at,
                .lifetime_depth = symbol.state.lifetime_depth,
                .deferred_resource_paths = symbol.state.deferred_resource_paths,
            });
        }
    }
    return snapshots.toOwnedSlice(self.allocator);
}

pub fn captureOwnerStates(self: anytype, tracked: []const OwnerStateSnapshot) Allocator.Error![]const OwnerStateSnapshot {
    const snapshots = try self.allocator.alloc(OwnerStateSnapshot, tracked.len);
    for (tracked, snapshots) |entry, *snapshot| snapshot.* = .{
        .name = entry.name,
        .state = entry.state,
        .available = entry.state.owner_available,
        .consumed_at = entry.state.consumed_at,
        .lifetime_depth = entry.state.lifetime_depth,
        .deferred_resource_paths = entry.state.deferred_resource_paths,
    };
    return snapshots;
}

pub fn mergeOwnerStates(self: anytype, base: []const OwnerStateSnapshot, outcomes: []const []const OwnerStateSnapshot) Allocator.Error!void {
    if (outcomes.len == 0) {
        restoreOwnerStates(base);
        return;
    }
    for (base, 0..) |entry, index| {
        var available = true;
        var consumed_at: ?Source.Position = null;
        for (outcomes) |outcome| {
            if (outcome[index].available) continue;
            available = false;
            if (consumed_at == null) consumed_at = outcome[index].consumed_at;
        }
        entry.state.owner_available = available;
        entry.state.consumed_at = if (available) null else consumed_at;
        var lifetime_depth: usize = 0;
        for (outcomes) |outcome| lifetime_depth = @max(lifetime_depth, outcome[index].lifetime_depth);
        entry.state.lifetime_depth = lifetime_depth;
        var deferred_resource_paths: std.ArrayList(DeferredResourcePath) = .empty;
        for (outcomes[0][index].deferred_resource_paths) |path| {
            var present_everywhere = true;
            for (outcomes[1..]) |outcome| {
                if (!containsDeferredResourcePath(outcome[index].deferred_resource_paths, path)) {
                    present_everywhere = false;
                    break;
                }
            }
            if (present_everywhere) try deferred_resource_paths.append(self.allocator, path);
        }
        entry.state.deferred_resource_paths = try deferred_resource_paths.toOwnedSlice(self.allocator);
    }
}

pub fn requireSameOwnerStates(
    self: anytype,
    expected: []const OwnerStateSnapshot,
    actual: []const OwnerStateSnapshot,
    loop_position: Source.Position,
) AnalyzeError!void {
    for (expected, actual) |before, after| {
        if (before.available == after.available and
            before.lifetime_depth == after.lifetime_depth and
            deferredResourcePathsEqual(before.deferred_resource_paths, after.deferred_resource_paths)) continue;
        const position = after.consumed_at orelse loop_position;
        const message = if (before.available != after.available)
            try std.fmt.allocPrint(
                self.allocator,
                "unique resource '{s}' must have the same availability on every path returning to the loop header",
                .{before.name},
            )
        else if (before.lifetime_depth != after.lifetime_depth)
            try std.fmt.allocPrint(
                self.allocator,
                "unique resource '{s}' must keep the same capture lifetime on every path returning to the loop header",
                .{before.name},
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "unique resource '{s}' must keep the same deferred callback provenance on every path returning to the loop header",
                .{before.name},
            );
        return self.fail(position, message);
    }
}

pub fn ifStatement(
    self: anytype,
    ast: Ast.Statement.If,
    parent_scope: *const Scope,
) AnalyzeError!Statement {
    var body_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
    const condition = try self.analyzeCondition(ast.condition, parent_scope, &body_scope);
    const tracked = try self.snapshotOwnerStates(parent_scope);
    var remaining = try self.captureOwnerStates(tracked);
    var outcomes: std.ArrayList([]const OwnerStateSnapshot) = .empty;
    if (condition == .expression) try self.applyPresenceReduction(ast.condition.expression, &body_scope, true);
    const body = try self.statements(ast.body, &body_scope);
    self.releaseScopeBorrows(&body_scope);
    if (astStatementsFallThrough(ast.body)) try outcomes.append(self.allocator, try self.captureOwnerStates(tracked));

    var alternatives: std.ArrayList(Statement.If.Alternative) = .empty;
    for (ast.alternatives) |ast_alternative| {
        restoreOwnerStates(remaining);
        var alternative_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
        const alternative_condition = try self.analyzeCondition(ast_alternative.condition, parent_scope, &alternative_scope);
        remaining = try self.captureOwnerStates(tracked);
        if (alternative_condition == .expression) try self.applyPresenceReduction(ast_alternative.condition.expression, &alternative_scope, true);
        const alternative_body = try self.statements(ast_alternative.body, &alternative_scope);
        self.releaseScopeBorrows(&alternative_scope);
        if (astStatementsFallThrough(ast_alternative.body)) try outcomes.append(self.allocator, try self.captureOwnerStates(tracked));
        try alternatives.append(self.allocator, .{
            .condition = alternative_condition,
            .body = alternative_body,
        });
    }

    var else_body: ?[]const Statement = null;
    if (ast.else_body) |ast_else_body| {
        restoreOwnerStates(remaining);
        var else_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
        if (ast.condition == .expression) try self.applyPresenceReduction(ast.condition.expression, &else_scope, false);
        else_body = try self.statements(ast_else_body, &else_scope);
        self.releaseScopeBorrows(&else_scope);
        if (astStatementsFallThrough(ast_else_body)) try outcomes.append(self.allocator, try self.captureOwnerStates(tracked));
    } else {
        try outcomes.append(self.allocator, remaining);
    }
    try self.mergeOwnerStates(tracked, outcomes.items);

    return .{ .if_statement = .{
        .condition = condition,
        .body = body,
        .alternatives = try alternatives.toOwnedSlice(self.allocator),
        .else_body = else_body,
    } };
}

pub fn whileStatement(
    self: anytype,
    ast: Ast.Statement.While,
    parent_scope: *const Scope,
) AnalyzeError!Statement {
    const tracked = try self.snapshotOwnerStates(parent_scope);
    var body_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
    const condition = try self.analyzeCondition(ast.condition, parent_scope, &body_scope);
    const condition_exit = try self.captureOwnerStates(tracked);
    if (condition == .expression) try self.applyPresenceReduction(ast.condition.expression, &body_scope, true);

    var flow = LoopFlow{ .tracked = tracked };
    const previous_flow = self.current_loop_flow;
    self.current_loop_flow = &flow;
    self.loop_depth += 1;
    defer {
        self.loop_depth -= 1;
        self.current_loop_flow = previous_flow;
    }
    const body = try self.statements(ast.body, &body_scope);
    self.releaseScopeBorrows(&body_scope);

    if (astStatementsFallThrough(ast.body)) {
        try self.requireSameOwnerStates(tracked, try self.captureOwnerStates(tracked), ast.position);
    }
    for (flow.continue_states.items) |continue_state| {
        try self.requireSameOwnerStates(tracked, continue_state, ast.position);
    }
    var exits: std.ArrayList([]const OwnerStateSnapshot) = .empty;
    try exits.append(self.allocator, condition_exit);
    try exits.appendSlice(self.allocator, flow.break_states.items);
    try self.mergeOwnerStates(tracked, exits.items);
    return .{ .while_statement = .{
        .condition = condition,
        .body = body,
    } };
}

pub fn analyzeCondition(
    self: anytype,
    ast: Ast.Statement.Condition,
    parent_scope: *const Scope,
    body_scope: *Scope,
) AnalyzeError!Statement.Condition {
    return switch (ast) {
        .expression => |ast_expression| expression_condition: {
            const value = try self.expression(ast_expression, parent_scope);
            if (!typeEqual(value.type, .bool)) {
                const message = try typeMismatchMessage(self.allocator, .bool, value.type);
                return self.fail(ast_expression.position, message);
            }
            break :expression_condition .{ .expression = value };
        },
        .binding => |binding| binding_condition: {
            try self.requireAvailableVariableName(body_scope, binding.name, binding.name_position);
            const mode: TransferMode = if (binding.source.value == .move_expression)
                .move
            else if (binding.source.value == .borrow_expression)
                .borrow
            else
                .copy;
            if (mode == .borrow and binding.mutability == .mutable) {
                return self.fail(binding.name_position, "a binding extracted with '@' is read-only and cannot use 'var'");
            }
            const source = switch (mode) {
                .copy => try self.expression(binding.source, parent_scope),
                .move => try self.moveExpression(binding.source.value.move_expression, parent_scope),
                .borrow => try self.readBorrowValue(binding.source.value.borrow_expression, parent_scope, null),
            };
            if (source.type != .optional) return self.fail(binding.source.position, "conditional binding source must have an optional type");
            const noncopyable = try self.isNonCopyableType(source.type);
            if (noncopyable and mode == .copy and !self.isNonCopyableTemporary(source)) {
                return self.fail(binding.source.position, "a named noncopyable optional must be extracted with 'move' or '@'");
            }
            if (binding.mutability == .immutable and mode == .copy) {
                try self.requireIndependentLetType(source.type.optional.*, binding.name_position);
            }
            const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            const temporary_name = try std.fmt.allocPrint(self.allocator, "silexOptional{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            const state = try self.newBindingState(source.type.optional.*);
            state.borrowed_parameter = mode == .borrow;
            if (mode == .borrow and source.owns_borrow) {
                try body_scope.borrows.append(self.allocator, source.borrow.?);
                source.owns_borrow = false;
            }
            try body_scope.symbols.append(self.allocator, .{
                .source_name = binding.name,
                .generated_name = generated_name,
                .type = source.type.optional.*,
                .mutability = if (mode == .borrow) .immutable else binding.mutability,
                .state = state,
                .scope_depth = body_scope.depth,
                .control_binding = true,
            });
            break :binding_condition .{ .binding = .{
                .source_name = binding.name,
                .position = binding.name_position,
                .source = source,
                .temporary_name = temporary_name,
                .generated_name = generated_name,
                .type = source.type.optional.*,
                .mode = mode,
                .mutability = if (mode == .borrow) .immutable else binding.mutability,
                .capture_box = &state.capture_box,
            } };
        },
    };
}

pub fn applyPresenceReduction(
    self: anytype,
    ast: *const Ast.Expression,
    scope: *Scope,
    branch_is_true: bool,
) AnalyzeError!void {
    if (ast.value != .binary) return;
    const binary = ast.value.binary;
    if (binary.operator != .equal and binary.operator != .not_equal) return;
    const name = if (binary.left.value == .identifier and binary.right.value == .null)
        binary.left.value.identifier
    else if (binary.right.value == .identifier and binary.left.value == .null)
        binary.right.value.identifier
    else
        return;
    const proves_presence = if (binary.operator == .not_equal) branch_is_true else !branch_is_true;
    if (!proves_presence) return;
    const original = findSymbol(scope.parent.?, name) orelse return;
    if (original.type != .optional) return;
    try scope.symbols.append(self.allocator, .{
        .source_name = original.source_name,
        .generated_name = original.generated_name,
        .type = original.type.optional.*,
        .mutability = original.mutability,
        .state = try self.newBindingState(original.type.optional.*),
        .scope_depth = scope.depth,
        .unwrap_optional = true,
        .original_type = original.type,
    });
}

pub fn forStatement(
    self: anytype,
    ast: Ast.Statement.For,
    parent_scope: *const Scope,
) AnalyzeError!Statement {
    var body_scope = Scope{ .parent = parent_scope, .depth = parent_scope.depth + 1 };
    try self.requireAvailableVariableName(&body_scope, ast.name, ast.name_position);
    const mutable = ast.binding == .mutable;
    const symbol_id = self.next_symbol_id;
    var element_type: Type = undefined;
    var iteration_borrow: ?Borrow = null;
    const source: Statement.For.IterationSource = switch (ast.source) {
        .collection => |ast_collection| source: {
            const collection = try self.expression(ast_collection, parent_scope);
            const collection_type = if (collection.type == .reference) collection.type.reference.target.* else collection.type;
            element_type = switch (collection_type) {
                .list => |element| element.*,
                .fixed_array => |array| array.element.*,
                .view => |element| element.*,
                else => return self.fail(ast_collection.position, "for source must be an array or list"),
            };

            const root = assignmentRoot(ast_collection);
            if (root) |resolved_root| {
                if (resolved_root == .static) {
                    if (mutable) if (self.immutableFieldInPlace(collection)) |field_candidate| {
                        const message = try std.fmt.allocPrint(self.allocator, "cannot iterate mutably through let field '{s}'", .{field_candidate.symbol.source_name});
                        return self.fail(ast_collection.position, message);
                    };
                    break :source .{ .collection = collection };
                }
                const state: *BindingState = switch (resolved_root) {
                    .static => unreachable,
                    .self => &self.current_self_state,
                    .variable => |name| (findSymbol(parent_scope, name) orelse return self.fail(ast_collection.position, "unknown iteration source")).state,
                };
                if (mutable) {
                    switch (resolved_root) {
                        .static => unreachable,
                        .self => self.current_method_direct_mutation = true,
                        .variable => |name| {
                            const symbol = findSymbol(parent_scope, name).?;
                            if (symbol.mutability == .immutable) {
                                const message = try std.fmt.allocPrint(self.allocator, "cannot iterate mutably over immutable variable '{s}'", .{name});
                                return self.fail(ast_collection.position, message);
                            }
                        },
                    }
                    if (state.mutable_borrow or state.immutable_borrows != 0) {
                        return self.fail(ast_collection.position, "cannot iterate mutably over an already borrowed collection");
                    }
                    state.mutable_borrow = true;
                } else {
                    if (state.mutable_borrow) return self.fail(ast_collection.position, "cannot iterate over a mutably borrowed collection");
                    state.immutable_borrows += 1;
                }
                iteration_borrow = .{ .root = state, .mutable = mutable };
            } else if (mutable) {
                return self.fail(ast_collection.position, "mutable iteration requires a mutable collection place");
            }

            break :source .{ .collection = collection };
        },
        .integer_range => |ast_range| source: {
            const start = try self.expression(ast_range.start, parent_scope);
            if (!typeEqual(start.type, .int)) {
                const message = try typeMismatchMessage(self.allocator, .int, start.type);
                return self.fail(ast_range.start.position, message);
            }
            const end = try self.expression(ast_range.end, parent_scope);
            if (!typeEqual(end.type, .int)) {
                const message = try typeMismatchMessage(self.allocator, .int, end.type);
                return self.fail(ast_range.end.position, message);
            }
            element_type = .int;
            break :source .{ .integer_range = .{
                .start = start,
                .end = end,
                .generated_start_name = try std.fmt.allocPrint(self.allocator, "silexRangeStart{d}", .{symbol_id}),
                .generated_end_name = try std.fmt.allocPrint(self.allocator, "silexRangeEnd{d}", .{symbol_id}),
                .generated_step_name = try std.fmt.allocPrint(self.allocator, "silexRangeStep{d}", .{symbol_id}),
                .generated_current_name = try std.fmt.allocPrint(self.allocator, "silexRangeCurrent{d}", .{symbol_id}),
            } };
        },
    };
    defer if (iteration_borrow) |borrow| releaseBorrow(borrow);

    const tracked = try self.snapshotOwnerStates(parent_scope);

    const element_noncopyable = try self.isNonCopyableType(element_type);
    if (ast.binding == .immutable and element_noncopyable) {
        return self.fail(ast.name_position, "'for let' would copy a noncopyable element; use the read loop or 'for var'");
    }
    if (ast.binding == .immutable) {
        try self.requireIndependentLetType(element_type, ast.name_position);
    }

    const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{symbol_id});
    self.next_symbol_id += 1;
    const state = try self.newBindingState(element_type);
    state.borrowed_parameter = element_noncopyable and ast.binding == .read;
    try body_scope.symbols.append(self.allocator, .{
        .source_name = ast.name,
        .generated_name = generated_name,
        .type = element_type,
        .mutability = if (mutable) .mutable else .immutable,
        .state = state,
        .scope_depth = body_scope.depth,
        .control_binding = true,
        .read_iteration = ast.binding == .read,
    });

    var flow = LoopFlow{ .tracked = tracked };
    const previous_flow = self.current_loop_flow;
    self.current_loop_flow = &flow;
    self.loop_depth += 1;
    defer {
        self.loop_depth -= 1;
        self.current_loop_flow = previous_flow;
    }
    const body = try self.statements(ast.body, &body_scope);
    self.releaseScopeBorrows(&body_scope);
    if (astStatementsFallThrough(ast.body)) {
        try self.requireSameOwnerStates(tracked, try self.captureOwnerStates(tracked), ast.position);
    }
    for (flow.continue_states.items) |continue_state| {
        try self.requireSameOwnerStates(tracked, continue_state, ast.position);
    }
    var exits: std.ArrayList([]const OwnerStateSnapshot) = .empty;
    try exits.append(self.allocator, tracked);
    try exits.appendSlice(self.allocator, flow.break_states.items);
    try self.mergeOwnerStates(tracked, exits.items);
    return .{ .for_statement = .{
        .source_name = ast.name,
        .position = ast.name_position,
        .generated_name = generated_name,
        .element_type = element_type,
        .element_noncopyable = element_noncopyable,
        .binding = ast.binding,
        .source = source,
        .body = body,
        .capture_box = &state.capture_box,
    } };
}

pub fn returnStatement(
    self: anytype,
    ast: Ast.Statement.Return,
    scope: *const Scope,
) AnalyzeError!Statement {
    if (self.current_drop) return self.fail(ast.position, "'drop' cannot return");
    if (ast.value) |ast_value| {
        if (typeEqual(self.current_return_type, .void)) return self.fail(ast.position, "void function cannot return a value");
        var value = try self.expressionForExpected(ast_value, scope, self.current_return_type);
        value = try self.coerce(value, self.current_return_type);
        if (!typeEqual(value.type, self.current_return_type)) {
            const message = try typeMismatchMessage(self.allocator, self.current_return_type, value.type);
            return self.fail(ast_value.position, message);
        }
        if (self.current_return_type == .reference) {
            const borrow = value.borrow orelse return self.fail(ast.position, "a borrowed return must return an explicit '@' or '&' borrow");
            if (borrow.root != self.current_return_borrow_root) {
                return self.fail(ast.position, "borrowed return does not originate from its declared root");
            }
            if (self.current_return_type.reference.mutable and !borrow.mutable) {
                return self.fail(ast.position, "a shared borrow cannot satisfy a mutable borrowed return");
            }
        }
        if (value.borrowed_parameter and self.current_return_type != .reference) {
            return self.fail(ast.position, "a read-reference parameter cannot be returned from its call");
        }
        if (value.lifetime_depth != 0) {
            return self.fail(ast.position, "capturing function value cannot be returned from its lexical scope");
        }
        if (try self.isNonCopyableType(value.type) and !self.isNonCopyableTemporary(value)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "named noncopyable value '{s}' must be returned with 'move'",
                .{typeName(value.type)},
            );
            return self.fail(ast.position, message);
        }
        return .{ .return_statement = value };
    }
    if (!typeEqual(self.current_return_type, .void)) {
        const message = try std.fmt.allocPrint(self.allocator, "expected return value of type '{s}'", .{typeName(self.current_return_type)});
        return self.fail(ast.position, message);
    }
    return .{ .return_statement = null };
}
