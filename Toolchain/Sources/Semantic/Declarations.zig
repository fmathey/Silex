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
pub fn collectEnumNames(self: anytype, ast_enums: []const Ast.Enum) AnalyzeError!void {
    for (ast_enums, 0..) |ast_enum, enum_index| {
        if (self.findEnum(ast_enum.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "type '{s}' is already declared", .{ast_enum.name});
            return self.fail(ast_enum.name_position, message);
        }
        try self.enums.append(self.allocator, .{
            .source_name = ast_enum.name,
            .generated_name = try std.fmt.allocPrint(self.allocator, "SilexEnum{d}", .{enum_index}),
            .raw_type = if (ast_enum.raw_type) |raw_type| switch (raw_type) {
                .int => .int,
                .str => .str,
            } else null,
            .variants = &.{},
            .position = ast_enum.name_position,
        });
    }
}

pub fn collectEnumVariants(self: anytype, ast_enums: []const Ast.Enum) AnalyzeError!void {
    for (ast_enums, 0..) |ast_enum, enum_index| {
        var variants: std.ArrayList(EnumVariantSymbol) = .empty;
        for (ast_enum.variants) |ast_variant| {
            for (variants.items) |existing| {
                if (std.mem.eql(u8, existing.source_name, ast_variant.name)) {
                    const message = try std.fmt.allocPrint(self.allocator, "variant '{s}' is already declared in enum '{s}'", .{ ast_variant.name, ast_enum.name });
                    return self.fail(ast_variant.position, message);
                }
            }
            var associated_types: std.ArrayList(Type) = .empty;
            for (ast_variant.associated_types) |annotation| {
                const associated_type = try typeFromAnnotation(self, annotation, ast_variant.position);
                if (associated_type == .void or associated_type == .reference) {
                    return self.fail(ast_variant.position, "an enum associated value cannot have this type");
                }
                try self.rejectUniqueOwnerComposition(associated_type, false, ast_variant.position);
                try associated_types.append(self.allocator, associated_type);
            }
            const raw_value = if (ast_variant.raw_value) |ast_raw_value|
                try self.enumRawValue(ast_raw_value, self.enums.items[enum_index].raw_type.?, ast_variant.position)
            else
                null;
            if (raw_value) |value| {
                for (variants.items) |existing| if (existing.raw_value) |existing_value| {
                    if (rawEnumValuesEqual(value, existing_value)) {
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "raw enum value is already used by variant '{s}'",
                            .{existing.source_name},
                        );
                        return self.fail(ast_variant.position, message);
                    }
                };
            }
            try variants.append(self.allocator, .{
                .source_name = ast_variant.name,
                .associated_types = try associated_types.toOwnedSlice(self.allocator),
                .raw_value = raw_value,
                .position = ast_variant.position,
            });
        }
        self.enums.items[enum_index].variants = try variants.toOwnedSlice(self.allocator);
    }
}

pub fn validateNoncopyableStaticFields(self: anytype) AnalyzeError!void {
    for (self.structures.items) |structure| {
        for (structure.static_fields) |field| {
            if (try self.isNonCopyableType(field.type)) {
                return self.fail(field.position, "a static field cannot own a noncopyable value");
            }
        }
    }
}

pub fn enumRawValue(
    self: anytype,
    ast_value: *const Ast.Expression,
    raw_type: Type,
    position: Source.Position,
) AnalyzeError!*Expression {
    const valid_shape = if (raw_type == .str)
        ast_value.value == .string
    else
        ast_value.value == .integer or
            (ast_value.value == .unary and ast_value.value.unary.operator == .numeric_negate and ast_value.value.unary.operand.value == .integer);
    if (!valid_shape) {
        const message = try std.fmt.allocPrint(self.allocator, "raw enum value must be a '{s}' literal", .{typeName(raw_type)});
        return self.fail(position, message);
    }
    var empty_scope = Scope{ .parent = null, .depth = 0 };
    var value = try self.expressionForExpected(ast_value, &empty_scope, raw_type);
    value = try self.coerce(value, raw_type);
    try self.validateExpression(value);
    return value;
}

pub fn collectStructures(self: anytype, ast_structures: []const Ast.Structure) AnalyzeError!void {
    for (ast_structures, 0..) |ast_structure, structure_index| {
        var protocol_conformances: std.ArrayList(ProtocolConformanceSymbol) = .empty;
        if (ast_structure.base) |base| {
            if (self.findProtocolIndex(base.name)) |protocol_index| {
                try protocol_conformances.append(self.allocator, .{
                    .protocol_index = protocol_index,
                    .position = base.position,
                    .extension_visible_files = null,
                    .extension_module_name = null,
                });
            } else {
                if (!ast_structure.is_class) return self.fail(base.position, "only a class can declare a base class");
                const base_index = self.findStructureIndex(base.name) orelse {
                    const message = try std.fmt.allocPrint(self.allocator, "unknown base class or protocol '{s}'", .{base.name});
                    return self.fail(base.position, message);
                };
                if (!self.structures.items[base_index].is_class) {
                    const message = try std.fmt.allocPrint(self.allocator, "base type '{s}' is not a class", .{base.name});
                    return self.fail(base.position, message);
                }
                self.structures.items[structure_index].base_index = base_index;
            }
        }
        for (ast_structure.conformances) |conformance| {
            const protocol_index = self.findProtocolIndex(conformance.name) orelse {
                const message = if (self.findStructure(conformance.name) != null)
                    try std.fmt.allocPrint(self.allocator, "type '{s}' is not a protocol", .{conformance.name})
                else
                    try std.fmt.allocPrint(self.allocator, "unknown protocol '{s}'", .{conformance.name});
                return self.fail(conformance.position, message);
            };
            for (protocol_conformances.items) |existing| {
                if (existing.protocol_index != protocol_index) continue;
                const message = if (conformance.extension_visible_files != null and existing.extension_visible_files != null)
                    try std.fmt.allocPrint(
                        self.allocator,
                        "extension conformance of type '{s}' to protocol '{s}' from module '{s}' conflicts with module '{s}'",
                        .{ ast_structure.name, conformance.name, conformance.extension_module_name.?, existing.extension_module_name.? },
                    )
                else if (conformance.extension_visible_files != null or existing.extension_visible_files != null)
                    try std.fmt.allocPrint(
                        self.allocator,
                        "extension conformance of type '{s}' to protocol '{s}' from module '{s}' conflicts with the conformance declared by the type",
                        .{
                            ast_structure.name,
                            conformance.name,
                            if (conformance.extension_module_name) |name| name else existing.extension_module_name.?,
                        },
                    )
                else
                    try std.fmt.allocPrint(self.allocator, "protocol '{s}' is already declared in the conformance list", .{conformance.name});
                return self.fail(conformance.position, message);
            }
            try protocol_conformances.append(self.allocator, .{
                .protocol_index = protocol_index,
                .position = conformance.position,
                .extension_visible_files = conformance.extension_visible_files,
                .extension_module_name = conformance.extension_module_name,
            });
        }
        self.structures.items[structure_index].protocol_conformances = try protocol_conformances.toOwnedSlice(self.allocator);
    }
    try self.validateInheritanceCycles();

    for (ast_structures, 0..) |ast_structure, structure_index| {
        var fields: std.ArrayList(StructureFieldSymbol) = .empty;
        var static_fields: std.ArrayList(StructureFieldSymbol) = .empty;
        for (ast_structure.fields, 0..) |field, field_index| {
            const existing_fields = if (field.is_static) static_fields.items else fields.items;
            for (existing_fields) |existing| {
                if (std.mem.eql(u8, existing.source_name, field.name)) {
                    const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is already declared in {s} '{s}'", .{ field.name, if (ast_structure.is_class) "class" else "struct", ast_structure.name });
                    return self.fail(field.position, message);
                }
            }
            var field_type = try typeFromAnnotation(self, field.type, field.position);
            if (field_type == .function) {
                field_type.function.owner = .{
                    .source_name = ast_structure.name,
                    .generated_name = self.structures.items[structure_index].generated_name,
                    .is_class = ast_structure.is_class,
                };
            }
            if (field_type == .reference) return self.fail(field.position, if (ast_structure.is_class)
                "a class field cannot have a reference type"
            else
                "a struct field cannot have a reference type");
            try self.rejectUniqueOwnerComposition(field_type, false, field.position);
            if (field.is_static and try self.isNonCopyableType(field_type)) {
                return self.fail(field.position, "a static field cannot own a noncopyable value");
            }
            if (field_type == .structure and !field_type.structure.is_class) {
                const dependency_index = self.findStructureIndex(field_type.structure.source_name).?;
                if (dependency_index >= structure_index) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "struct field type '{s}' must be declared before '{s}'",
                        .{ field_type.structure.source_name, ast_structure.name },
                    );
                    return self.fail(field.position, message);
                }
            }
            const field_symbol = StructureFieldSymbol{
                .source_name = field.name,
                .generated_name = if (field.is_static)
                    try std.fmt.allocPrint(self.allocator, "staticField{d}_{d}", .{ structure_index, field_index })
                else if (ast_structure.is_class)
                    try std.fmt.allocPrint(self.allocator, "field{d}_{d}", .{ structure_index, field_index })
                else
                    try std.fmt.allocPrint(self.allocator, "field{d}", .{field_index}),
                .type = field_type,
                .position = field.position,
                .ast_initializer = field.initializer,
                .visibility = field.visibility,
                .mutability = field.mutability,
            };
            if (field.is_static)
                try static_fields.append(self.allocator, field_symbol)
            else
                try fields.append(self.allocator, field_symbol);
        }
        self.structures.items[structure_index].fields = try fields.toOwnedSlice(self.allocator);
        self.structures.items[structure_index].static_fields = try static_fields.toOwnedSlice(self.allocator);
        for (self.structures.items[structure_index].fields) |field| {
            if (field.mutability == .immutable) try self.requireIndependentLetType(field.type, field.position);
        }
        for (self.structures.items[structure_index].static_fields) |field| {
            if (field.mutability == .immutable) try self.requireIndependentLetType(field.type, field.position);
        }

        var constructors: std.ArrayList(ConstructorSymbol) = .empty;
        for (ast_structure.constructors) |ast_constructor| {
            var parameter_types: std.ArrayList(Type) = .empty;
            var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
            var parameter_stored_values: std.ArrayList(bool) = .empty;
            for (ast_constructor.parameters) |parameter| {
                const parameter_type = try typeFromAnnotation(self, parameter.type, parameter.position);
                try self.validateParameterMode(parameter_type, parameter.mode, parameter.position, false);
                try parameter_types.append(self.allocator, parameter_type);
                try parameter_modes.append(self.allocator, parameter.mode);
                var stored = parameterStored(ast_constructor.statements, parameter.name);
                if (ast_constructor.super_arguments) |arguments| {
                    for (arguments) |argument| stored = stored or astExpressionUsesIdentifier(argument, parameter.name);
                }
                try parameter_stored_values.append(self.allocator, stored);
            }
            for (constructors.items) |existing| {
                if (sameCallableShape(existing.parameter_types, parameter_types.items)) return self.fail(
                    ast_constructor.position,
                    if (ast_structure.is_class)
                        "constructor 'init' with this callable shape is already declared in this class"
                    else
                        "constructor 'init' with this callable shape is already declared in this struct",
                );
            }
            try constructors.append(self.allocator, .{
                .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
                .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
                .parameter_stored = try parameter_stored_values.toOwnedSlice(self.allocator),
                .position = ast_constructor.position,
                .visibility = ast_constructor.visibility,
            });
        }
        self.structures.items[structure_index].constructors = try constructors.toOwnedSlice(self.allocator);

        var methods: std.ArrayList(MethodSymbol) = .empty;
        for (ast_structure.methods, 0..) |ast_method, method_index| {
            var parameter_types: std.ArrayList(Type) = .empty;
            var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
            var parameter_stored_values: std.ArrayList(bool) = .empty;
            for (ast_method.parameters) |parameter| {
                const parameter_type = try typeFromAnnotation(self, parameter.type, parameter.position);
                try self.validateParameterMode(parameter_type, parameter.mode, parameter.position, false);
                try parameter_types.append(self.allocator, parameter_type);
                try parameter_modes.append(self.allocator, parameter.mode);
                try parameter_stored_values.append(self.allocator, parameterStored(ast_method.statements, parameter.name));
            }
            for (methods.items) |existing| {
                if (existing.is_static == ast_method.is_static and
                    std.mem.eql(u8, existing.source_name, ast_method.name) and
                    sameCallableShape(existing.parameter_types, parameter_types.items))
                duplicate: {
                    const existing_extension = existing.extension_visible_files;
                    const current_extension = ast_method.extension_visible_files;
                    if (existing_extension != null and current_extension != null and
                        !fileSetsOverlap(existing_extension.?, current_extension.?)) break :duplicate;
                    const message = if (existing_extension != null and current_extension != null)
                        try std.fmt.allocPrint(
                            self.allocator,
                            "extension method '{s}' from module '{s}' conflicts with module '{s}' on type '{s}'",
                            .{ ast_method.name, ast_method.extension_module_name.?, existing.extension_module_name.?, ast_structure.name },
                        )
                    else if (existing_extension != null or current_extension != null)
                        try std.fmt.allocPrint(self.allocator, "extension method '{s}' conflicts with an existing callable shape on type '{s}'", .{ ast_method.name, ast_structure.name })
                    else
                        try std.fmt.allocPrint(self.allocator, "method '{s}' with this callable shape is already declared in {s} '{s}'", .{ ast_method.name, if (ast_structure.is_class) "class" else "struct", ast_structure.name });
                    return self.fail(ast_method.name_position, message);
                }
            }
            const return_type = try typeFromReturn(self, ast_method.return_type, ast_method.position);
            var return_borrow_parameter: ?usize = null;
            if (return_type == .reference) {
                if (ast_method.return_type.reference.provenance) |provenance| {
                    if (!std.mem.eql(u8, provenance, "self")) {
                        for (ast_method.parameters, parameter_modes.items, 0..) |parameter, mode, parameter_index| {
                            const compatible_mode = if (return_type.reference.mutable) mode == .mutable_reference else mode != .value;
                            if (!compatible_mode) continue;
                            if (std.mem.eql(u8, provenance, parameter.name)) return_borrow_parameter = parameter_index;
                        }
                        if (return_borrow_parameter == null) {
                            return self.fail(ast_method.position, "borrowed method return provenance must name 'self' or a compatible borrowed parameter");
                        }
                    }
                } else {
                    var compatible_count: usize = 0;
                    for (parameter_modes.items, 0..) |mode, parameter_index| {
                        const compatible_mode = if (return_type.reference.mutable) mode == .mutable_reference else mode != .value;
                        if (!compatible_mode) continue;
                        compatible_count += 1;
                        return_borrow_parameter = parameter_index;
                    }
                    if (compatible_count > 1) {
                        return self.fail(ast_method.position, "borrowed method return provenance is ambiguous; qualify it with 'self' or a borrowed parameter name");
                    }
                }
            }
            try self.rejectUniqueOwnerComposition(return_type, true, ast_method.position);
            try methods.append(self.allocator, .{
                .source_name = ast_method.name,
                .generated_name = if (ast_structure.is_class)
                    try std.fmt.allocPrint(self.allocator, "method{d}_{d}", .{ structure_index, method_index })
                else
                    try std.fmt.allocPrint(self.allocator, "method{d}", .{method_index}),
                .return_type = return_type,
                .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
                .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
                .parameter_stored = try parameter_stored_values.toOwnedSlice(self.allocator),
                .position = ast_method.name_position,
                .visibility = ast_method.member_visibility.?,
                .is_override = ast_method.is_override,
                .is_static = ast_method.is_static,
                .extension_visible_files = ast_method.extension_visible_files,
                .extension_module_name = ast_method.extension_module_name,
                .return_borrow_parameter = return_borrow_parameter,
            });
        }
        self.structures.items[structure_index].methods = try methods.toOwnedSlice(self.allocator);
    }
    try self.validateInheritedMembers();
    try self.validateProtocolConformances();
}

pub fn collectStructureNames(self: anytype, ast_structures: []const Ast.Structure) AnalyzeError!void {
    for (ast_structures, 0..) |ast_structure, structure_index| {
        if (self.findStructure(ast_structure.name) != null or self.findEnum(ast_structure.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "type '{s}' is already declared", .{ast_structure.name});
            return self.fail(ast_structure.name_position, message);
        }
        const native_module_name = if (ast_structure.is_native_resource)
            ast_structure.module_name orelse moduleName(ast_structure.name)
        else
            null;
        if (ast_structure.is_native_resource) {
            const module_name = native_module_name orelse return self.fail(
                ast_structure.position,
                "native resources are only available in a named module with @Module.json native configuration",
            );
            if (!self.isNativeModule(module_name)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "native resources require module '{s}' or one of its parents to declare @Module.json native configuration",
                    .{module_name},
                );
                return self.fail(ast_structure.position, message);
            }
        }
        const drop_qualified_name = if (ast_structure.is_native_resource)
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ native_module_name.?, ast_structure.native_drop_name.? })
        else
            null;
        try self.structures.append(self.allocator, .{
            .source_name = ast_structure.name,
            .generated_name = if (ast_structure.is_class)
                try std.fmt.allocPrint(self.allocator, "SilexClass{d}", .{structure_index})
            else
                try std.fmt.allocPrint(self.allocator, "SilexStruct{d}", .{structure_index}),
            .is_class = ast_structure.is_class,
            .is_owner = !ast_structure.is_class and (ast_structure.drop != null or ast_structure.is_native_resource),
            .is_native_resource = ast_structure.is_native_resource,
            .native_module_name = native_module_name,
            .native_drop_name = ast_structure.native_drop_name,
            .native_drop_symbol = if (drop_qualified_name) |name| try nativeSymbol(self.allocator, name) else null,
            .is_generic = ast_structure.type_parameters.len != 0 or
                std.mem.indexOfScalar(u8, ast_structure.name, '<') != null,
            .module_files = ast_structure.module_files,
            .base_index = null,
            .protocol_conformances = &.{},
            .fields = &.{},
            .static_fields = &.{},
            .constructors = &.{},
            .methods = &.{},
            .position = ast_structure.name_position,
        });
    }
}

pub fn collectProtocols(self: anytype, ast_protocols: []const Ast.Protocol) AnalyzeError!void {
    for (ast_protocols, 0..) |ast_protocol, protocol_index| {
        if (self.findProtocol(ast_protocol.name) != null or self.findStructure(ast_protocol.name) != null or self.findEnum(ast_protocol.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "protocol '{s}' is already declared", .{ast_protocol.name});
            return self.fail(ast_protocol.name_position, message);
        }
        try self.protocols.append(self.allocator, .{
            .source_name = ast_protocol.name,
            .generated_name = try std.fmt.allocPrint(self.allocator, "SilexProtocol{d}", .{protocol_index}),
            .requirements = &.{},
            .position = ast_protocol.name_position,
        });
    }
    for (ast_protocols, 0..) |ast_protocol, protocol_index| {
        var requirements: std.ArrayList(ProtocolRequirement) = .empty;
        for (ast_protocol.requirements, 0..) |requirement, requirement_index| {
            var parameter_types: std.ArrayList(Type) = .empty;
            var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
            for (requirement.parameters) |parameter| {
                const parameter_type = try typeFromAnnotation(self, parameter.type, parameter.position);
                try self.validateParameterMode(parameter_type, parameter.mode, parameter.position, false);
                try parameter_types.append(self.allocator, parameter_type);
                try parameter_modes.append(self.allocator, parameter.mode);
            }
            for (requirements.items) |existing| {
                if (std.mem.eql(u8, existing.source_name, requirement.name) and
                    sameCallableShape(existing.parameter_types, parameter_types.items))
                {
                    const message = try std.fmt.allocPrint(self.allocator, "protocol method '{s}' with this callable shape is already declared", .{requirement.name});
                    return self.fail(requirement.name_position, message);
                }
            }
            const return_type = try typeFromReturn(self, requirement.return_type, requirement.position);
            try self.rejectUniqueOwnerComposition(return_type, true, requirement.position);
            try requirements.append(self.allocator, .{
                .source_name = requirement.name,
                .generated_name = try std.fmt.allocPrint(self.allocator, "method{d}_{d}", .{ protocol_index, requirement_index }),
                .return_type = return_type,
                .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
                .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
                .position = requirement.name_position,
            });
        }
        self.protocols.items[protocol_index].requirements = try requirements.toOwnedSlice(self.allocator);
    }
}

pub fn validateProtocolConformances(self: anytype) AnalyzeError!void {
    for (self.structures.items, 0..) |structure, structure_index| {
        for (structure.protocol_conformances) |conformance| {
            const protocol = self.protocols.items[conformance.protocol_index];
            for (protocol.requirements) |requirement| {
                if (self.findProtocolRequirementMethod(structure_index, requirement, conformance, true) != null) continue;
                const message = if (self.findProtocolRequirementMethod(structure_index, requirement, conformance, false) != null)
                    try std.fmt.allocPrint(
                        self.allocator,
                        "method '{s}' must be public to satisfy protocol '{s}' for type '{s}'",
                        .{ requirement.source_name, protocol.source_name, structure.source_name },
                    )
                else
                    try std.fmt.allocPrint(
                        self.allocator,
                        "type '{s}' does not satisfy method '{s}' required by protocol '{s}'",
                        .{ structure.source_name, requirement.source_name, protocol.source_name },
                    );
                return self.fail(conformance.position, message);
            }
        }
    }
}

pub fn findProtocolRequirementMethod(
    self: anytype,
    start_index: usize,
    requirement: ProtocolRequirement,
    conformance: ProtocolConformanceSymbol,
    require_public: bool,
) ?MethodCandidate {
    var structure_index: ?usize = start_index;
    while (structure_index) |index| {
        const structure = self.structures.items[index];
        for (structure.methods, 0..) |method_symbol, method_index| {
            if (method_symbol.extension_visible_files) |visible_files| {
                if (conformance.extension_visible_files == null or index != start_index or
                    !fileSetContains(visible_files, conformance.position.file)) continue;
            }
            if (method_symbol.is_static or (require_public and method_symbol.visibility != .public_access)) continue;
            if (!std.mem.eql(u8, method_symbol.source_name, requirement.source_name)) continue;
            if (!sameSignature(
                method_symbol.parameter_types,
                method_symbol.parameter_modes,
                requirement.parameter_types,
                requirement.parameter_modes,
            )) continue;
            if (typeEqual(method_symbol.return_type, requirement.return_type)) return .{
                .symbol = method_symbol,
                .structure_index = index,
                .index = method_index,
            };
        }
        structure_index = structure.base_index;
    }
    return null;
}

pub fn protocolConformance(
    self: anytype,
    structure_index: usize,
    protocol_index: usize,
    source_file: ?usize,
) ?ProtocolConformanceSymbol {
    var cursor: ?usize = structure_index;
    while (cursor) |index| {
        for (self.structures.items[index].protocol_conformances) |conformance| {
            if (conformance.protocol_index != protocol_index) continue;
            if (conformance.extension_visible_files) |visible_files| {
                if (index != structure_index or source_file == null or
                    !fileSetContains(visible_files, source_file.?)) continue;
            }
            return conformance;
        }
        cursor = self.structures.items[index].base_index;
    }
    return null;
}

pub fn structureConformsToProtocol(
    self: anytype,
    structure_index: usize,
    protocol_index: usize,
    source_file: ?usize,
) bool {
    return self.protocolConformance(structure_index, protocol_index, source_file) != null;
}

pub fn protocolConformances(self: anytype, structure_index: usize) AnalyzeError![]const ProtocolConformance {
    var conformances: std.ArrayList(ProtocolConformance) = .empty;
    for (self.protocols.items, 0..) |protocol, protocol_index| {
        const conformance = conformance: {
            for (self.structures.items[structure_index].protocol_conformances) |value| {
                if (value.protocol_index == protocol_index) break :conformance value;
            }
            var cursor = self.structures.items[structure_index].base_index;
            while (cursor) |index| {
                for (self.structures.items[index].protocol_conformances) |value| {
                    if (value.protocol_index == protocol_index and value.extension_visible_files == null) {
                        break :conformance value;
                    }
                }
                cursor = self.structures.items[index].base_index;
            }
            continue;
        };
        var method_names: std.ArrayList([]const u8) = .empty;
        for (protocol.requirements) |requirement| {
            const candidate = self.findProtocolRequirementMethod(structure_index, requirement, conformance, true) orelse unreachable;
            try method_names.append(self.allocator, candidate.symbol.generated_name);
        }
        try conformances.append(self.allocator, .{
            .protocol_index = protocol_index,
            .protocol_generated_name = protocol.generated_name,
            .witness_name = try std.fmt.allocPrint(self.allocator, "SilexWitness{d}_{d}", .{ protocol_index, structure_index }),
            .method_generated_names = try method_names.toOwnedSlice(self.allocator),
        });
    }
    return conformances.toOwnedSlice(self.allocator);
}

pub fn validateInheritanceCycles(self: anytype) AnalyzeError!void {
    for (self.structures.items, 0..) |structure, start_index| {
        if (!structure.is_class) continue;
        var cursor = structure.base_index;
        while (cursor) |index| {
            if (index == start_index) {
                const message = try std.fmt.allocPrint(self.allocator, "inheritance cycle involving class '{s}'", .{structure.source_name});
                return self.fail(structure.position, message);
            }
            cursor = self.structures.items[index].base_index;
        }
    }
}

pub fn validateInheritedMembers(self: anytype) AnalyzeError!void {
    const validated = try self.allocator.alloc(bool, self.structures.items.len);
    @memset(validated, false);
    for (self.structures.items, 0..) |structure, structure_index| {
        if (structure.is_class) try self.validateInheritedStructure(structure_index, validated);
    }
}

pub fn validateInheritedStructure(self: anytype, structure_index: usize, validated: []bool) AnalyzeError!void {
    if (validated[structure_index]) return;
    const direct_base_index = self.structures.items[structure_index].base_index orelse {
        validated[structure_index] = true;
        return;
    };
    try self.validateInheritedStructure(direct_base_index, validated);

    var base_index: ?usize = direct_base_index;
    while (base_index) |index| {
        const base = self.structures.items[index];
        for (self.structures.items[structure_index].fields) |field| {
            for (base.fields) |base_field| {
                if (std.mem.eql(u8, field.source_name, base_field.source_name)) {
                    const message = try std.fmt.allocPrint(self.allocator, "field '{s}' in class '{s}' collides with an inherited field", .{ field.source_name, self.structures.items[structure_index].source_name });
                    return self.fail(field.position, message);
                }
            }
        }
        base_index = base.base_index;
    }

    for (self.structures.items[structure_index].methods, 0..) |method_symbol, method_index| {
        if (method_symbol.extension_visible_files != null) continue;
        if (method_symbol.is_static) continue;
        var inherited: ?MethodCandidate = null;
        var private_match = false;
        base_index = direct_base_index;
        while (base_index) |index| {
            const base = self.structures.items[index];
            for (base.methods, 0..) |base_method, base_method_index| {
                if (base_method.extension_visible_files != null) continue;
                if (base_method.is_static) continue;
                if (!std.mem.eql(u8, method_symbol.source_name, base_method.source_name) or !sameSignature(
                    method_symbol.parameter_types,
                    method_symbol.parameter_modes,
                    base_method.parameter_types,
                    base_method.parameter_modes,
                )) continue;
                if (base_method.visibility == .private_access) {
                    private_match = true;
                } else if (inherited == null) {
                    inherited = .{ .symbol = base_method, .structure_index = index, .index = base_method_index };
                }
            }
            if (inherited != null) break;
            base_index = base.base_index;
        }

        if (inherited) |candidate| {
            if (!method_symbol.is_override) {
                const message = try std.fmt.allocPrint(self.allocator, "method '{s}' matches an inherited signature; declare it with 'override'", .{method_symbol.source_name});
                return self.fail(method_symbol.position, message);
            }
            if (!typeEqual(method_symbol.return_type, candidate.symbol.return_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "override method '{s}' must return '{s}'", .{ method_symbol.source_name, typeName(candidate.symbol.return_type) });
                return self.fail(method_symbol.position, message);
            }
            if (visibilityRank(method_symbol.visibility) < visibilityRank(candidate.symbol.visibility)) {
                const message = try std.fmt.allocPrint(self.allocator, "override method '{s}' cannot reduce inherited visibility", .{method_symbol.source_name});
                return self.fail(method_symbol.position, message);
            }
            self.structures.items[structure_index].methods[method_index].generated_name = candidate.symbol.generated_name;
        } else if (method_symbol.is_override) {
            const message = if (private_match)
                try std.fmt.allocPrint(self.allocator, "private method '{s}' cannot be overridden", .{method_symbol.source_name})
            else
                try std.fmt.allocPrint(self.allocator, "override method '{s}' has no compatible inherited method", .{method_symbol.source_name});
            return self.fail(method_symbol.position, message);
        }
    }
    validated[structure_index] = true;
}

pub fn collectFunctions(self: anytype, ast_functions: []const Ast.Function) AnalyzeError!void {
    var main_count: usize = 0;
    for (ast_functions, 0..) |ast_function, index| {
        const is_main = std.mem.eql(u8, ast_function.name, "main");
        if (is_main) main_count += 1;
        const native_module_name = if (ast_function.is_native)
            ast_function.module_name orelse moduleName(ast_function.name)
        else
            null;
        const native_function_name = if (ast_function.is_native) lastNameSegment(ast_function.name) else null;
        if (ast_function.is_native) {
            const module_name = native_module_name orelse return self.fail(
                ast_function.position,
                "native functions are only available in a named module with @Module.json native configuration",
            );
            if (!self.isNativeModule(module_name)) {
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "native functions require module '{s}' or one of its parents to declare @Module.json native configuration",
                    .{module_name},
                );
                return self.fail(ast_function.position, message);
            }
        }
        var parameter_types: std.ArrayList(Type) = .empty;
        var parameter_modes: std.ArrayList(Ast.ParameterMode) = .empty;
        var parameter_stored_values: std.ArrayList(bool) = .empty;
        for (ast_function.parameters) |parameter| {
            const parameter_type = try typeFromAnnotation(self, parameter.type, parameter.position);
            try self.validateParameterMode(parameter_type, parameter.mode, parameter.position, ast_function.is_native);
            try parameter_types.append(self.allocator, parameter_type);
            try parameter_modes.append(self.allocator, parameter.mode);
            try parameter_stored_values.append(self.allocator, parameterStored(ast_function.statements, parameter.name));
        }
        for (self.functions.items) |existing| {
            if (std.mem.eql(u8, existing.source_name, ast_function.name) and
                sameCallableShape(existing.parameter_types, parameter_types.items))
            {
                const message = try std.fmt.allocPrint(self.allocator, "function '{s}' with this callable shape is already declared", .{ast_function.name});
                return self.fail(ast_function.name_position, message);
            }
        }
        if (ast_function.is_native and self.findFunction(ast_function.name) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "native function '{s}' is already declared", .{ast_function.name});
            return self.fail(ast_function.name_position, message);
        }
        const return_type = try typeFromReturn(self, ast_function.return_type, ast_function.position);
        if (return_type == .view) return self.fail(ast_function.position, "a view type must be borrowed as '@T[..]' or '&T[..]'");
        var deferred_callback_index: ?usize = null;
        for (parameter_types.items, 0..) |parameter_type, parameter_index| {
            if (parameter_type != .function or !parameter_type.function.deferred) continue;
            if (deferred_callback_index != null) {
                return self.fail(ast_function.position, "a native deferred registration requires exactly one 'deferred func' parameter");
            }
            deferred_callback_index = parameter_index;
        }
        if (deferred_callback_index != null) {
            if (!ast_function.is_native) {
                return self.fail(ast_function.position, "a 'deferred func' parameter is only valid in a native registration function");
            }
            if (!self.isNativeResourceType(return_type)) {
                return self.fail(ast_function.position, "a native deferred registration must return one native resource directly");
            }
        }
        var return_borrow_parameter: ?usize = null;
        if (return_type == .reference) {
            const reference = ast_function.return_type.reference;
            var compatible_count: usize = 0;
            for (ast_function.parameters, parameter_types.items, parameter_modes.items, 0..) |parameter, parameter_type, mode, parameter_index| {
                const compatible_mode = if (reference.mutable) mode == .mutable_reference else mode != .value;
                _ = parameter_type;
                if (!compatible_mode) continue;
                if (reference.provenance) |provenance| {
                    if (std.mem.eql(u8, provenance, parameter.name)) return_borrow_parameter = parameter_index;
                } else {
                    compatible_count += 1;
                    return_borrow_parameter = parameter_index;
                }
            }
            if (reference.provenance != null and return_borrow_parameter == null) {
                return self.fail(ast_function.position, "borrowed return provenance must name a compatible borrowed parameter");
            }
            if (reference.provenance == null and compatible_count != 1) {
                return self.fail(ast_function.position, "borrowed return provenance is ambiguous; qualify it with the parameter name");
            }
        }
        try self.rejectUniqueOwnerComposition(return_type, true, ast_function.position);
        if (ast_function.is_native) {
            if (!try self.isNativeReturnType(return_type)) {
                const return_name = try allocatedTypeName(self.allocator, return_type);
                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "native functions cannot return '{s}'",
                    .{return_name},
                );
                return self.fail(ast_function.position, message);
            }
            for (ast_function.parameters, parameter_types.items, parameter_modes.items) |parameter, parameter_type, mode| {
                if (!try self.isNativeParameterType(parameter_type) or
                    (mode != .value and !self.isNativeResourceType(parameter_type) and parameter_type != .view))
                {
                    const parameter_name = try allocatedTypeName(self.allocator, parameter_type);
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "native parameter '{s}' cannot use '{s}'",
                        .{ parameter.name, parameter_name },
                    );
                    return self.fail(parameter.position, message);
                }
            }
            if (return_type == .reference) {
                const parameter_index = return_borrow_parameter.?;
                const root_type = parameter_types.items[parameter_index];
                const returned_target = return_type.reference.target.*;
                if (!self.isNativeResourceType(root_type) or
                    (returned_target != .view and !typeEqual(root_type, returned_target)))
                {
                    return self.fail(ast_function.position, "a native borrowed return must alias its native resource parameter directly");
                }
            }
        }
        try self.functions.append(self.allocator, .{
            .source_name = ast_function.name,
            .generated_name = if (is_main)
                "main"
            else if (ast_function.is_native)
                try nativeSymbol(self.allocator, ast_function.name)
            else
                try std.fmt.allocPrint(self.allocator, "silexFunction{d}", .{index}),
            .return_type = return_type,
            .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
            .parameter_modes = try parameter_modes.toOwnedSlice(self.allocator),
            .parameter_stored = try parameter_stored_values.toOwnedSlice(self.allocator),
            .position = ast_function.name_position,
            .is_main = is_main,
            .is_native = ast_function.is_native,
            .is_native_resource_drop = ast_function.is_native_resource_drop,
            .native_module_name = native_module_name,
            .native_function_name = native_function_name,
            .return_borrow_parameter = return_borrow_parameter,
            .deferred_callback_index = deferred_callback_index,
        });
    }
    if (!self.require_main) return;
    if (main_count == 0) return self.fail(.{ .line = 1, .column = 1 }, "missing 'main' function");
    if (main_count > 1) return self.fail(.{ .line = 1, .column = 1 }, "'main' cannot be overloaded");
    const main = self.findFunction("main").?;
    if (main.parameter_types.len != 0) return self.fail(main.position, "'main' must have no parameters");
    if (typeEqual(main.return_type, .void)) return;
    const main_result = self.resultShape(main.return_type) orelse
        return self.fail(main.position, "'main' must return 'void' or 'Result<void, str>'");
    if (!typeEqual(main_result.success_type, .void) or !typeEqual(main_result.error_type, .str)) {
        return self.fail(main.position, "'main' must return 'void' or 'Result<void, str>'");
    }
}

pub fn validateStructureDefaults(self: anytype) AnalyzeError!void {
    self.current_structure_index = null;
    self.current_method_index = null;
    self.current_extension = false;
    var empty_scope = Scope{ .parent = null, .depth = 0 };
    for (self.structures.items) |*structure| {
        for (structure.fields) |*field| {
            const ast_initializer = field.ast_initializer orelse continue;
            try self.validateDefaultShape(ast_initializer, field.type);
            var value = try self.expressionForExpected(ast_initializer, &empty_scope, field.type);
            value = try self.coerce(value, field.type);
            if (!typeEqual(field.type, value.type)) {
                const message = try typeMismatchMessage(self.allocator, field.type, value.type);
                return self.fail(ast_initializer.position, message);
            }
            field.default_value = value;
        }
        for (structure.static_fields) |*field| {
            const ast_initializer = field.ast_initializer orelse continue;
            try self.validateDefaultShape(ast_initializer, field.type);
            var value = try self.expressionForExpected(ast_initializer, &empty_scope, field.type);
            value = try self.coerce(value, field.type);
            if (!typeEqual(field.type, value.type)) {
                const message = try typeMismatchMessage(self.allocator, field.type, value.type);
                return self.fail(ast_initializer.position, message);
            }
            field.default_value = value;
        }
    }
}

pub fn validateDefaultShape(
    self: anytype,
    ast: *const Ast.Expression,
    expected_type: Type,
) AnalyzeError!void {
    const valid = switch (expected_type) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => ast.value == .integer,
        .float, .float64 => ast.value == .integer or ast.value == .floating,
        .bool => ast.value == .boolean,
        .str => ast.value == .string,
        .list => ast.value == .sequence_literal and ast.value.sequence_literal.len == 0,
        .fixed_array, .view, .protocol => false,
        .reference => false,
        .function => false,
        .enumeration => |enum_type| enum_default: {
            if (ast.value != .static_method_call) break :enum_default false;
            const call = ast.value.static_method_call;
            if (call.owner != .structure or !std.mem.eql(u8, call.owner.structure, enum_type.source_name)) break :enum_default false;
            const enum_symbol = self.findEnumByGeneratedName(enum_type.generated_name) orelse break :enum_default false;
            const variant_index = findEnumVariant(enum_symbol, call.name) orelse break :enum_default false;
            const variant = enum_symbol.variants[variant_index];
            if (call.arguments.len != variant.associated_types.len) break :enum_default false;
            for (call.arguments, variant.associated_types) |argument, associated_type| {
                try self.validateDefaultShape(argument, associated_type);
            }
            break :enum_default true;
        },
        .optional => ast.value == .null,
        .null => false,
        .structure => |structure_type| structure_default: {
            if (ast.value != .structure_initializer) break :structure_default false;
            const initializer = ast.value.structure_initializer;
            if (!std.mem.eql(u8, initializer.name, structure_type.source_name)) break :structure_default false;
            const structure = self.findStructure(initializer.name).?;
            for (initializer.fields) |initialized_field| {
                var matched: ?*const StructureFieldSymbol = null;
                for (structure.fields) |*field| {
                    if (std.mem.eql(u8, field.source_name, initialized_field.name)) matched = field;
                }
                if (matched) |field| try self.validateDefaultShape(initialized_field.value, field.type);
            }
            break :structure_default true;
        },
        .void => false,
    };
    if (!valid) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "default field value must be a literal or named initializer of type '{s}'",
            .{typeName(expected_type)},
        );
        return self.fail(ast.position, message);
    }
}
