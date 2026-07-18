const std = @import("std");
const Ast = @import("Ast.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const AnalyzeError = Source.Error || Allocator.Error;
const never_capture_box = false;

pub const TransferMode = enum {
    copy,
    move,
    borrow,
};

pub const Type = union(enum) {
    void,
    int,
    int8,
    int16,
    int32,
    uint8,
    uint16,
    uint32,
    uint64,
    float,
    float64,
    bool,
    str,
    structure: StructureType,
    protocol: ProtocolType,
    enumeration: EnumType,
    list: *const Type,
    fixed_array: FixedArrayType,
    reference: ReferenceType,
    function: FunctionType,
    optional: *const Type,
    null,
};

pub const FunctionType = struct {
    parameters: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    return_type: *const Type,
    owner: ?StructureType = null,
};

pub const StructureType = struct {
    source_name: []const u8,
    generated_name: []const u8,
    is_class: bool,
    is_owner: bool = false,
};

pub const ProtocolType = struct {
    source_name: []const u8,
    generated_name: []const u8,
    index: usize,
};

pub const EnumType = struct {
    source_name: []const u8,
    generated_name: []const u8,
};

pub const ReferenceType = struct {
    target: *const Type,
    mutable: bool,
};

pub const FixedArrayType = struct {
    element: *const Type,
    length: usize,
};

const BindingState = struct {
    immutable_borrows: usize = 0,
    mutable_borrow: bool = false,
    transient_mutable_borrows: usize = 0,
    reference: ?Borrow = null,
    lifetime_depth: usize = 0,
    narrowed_valid: bool = true,
    capture_box: bool = false,
    owner_available: bool = true,
    consumed_at: ?Source.Position = null,
    borrowed_parameter: bool = false,
};

const Borrow = struct {
    root: ?*BindingState,
    mutable: bool,
    transient: bool = false,
};

pub const Expression = struct {
    type: Type,
    position: Source.Position,
    lifetime_depth: usize = 0,
    borrow: ?Borrow = null,
    owns_borrow: bool = false,
    borrowed_parameter: bool = false,
    value: union(enum) {
        integer: u64,
        floating: []const u8,
        boolean: bool,
        null,
        string: []const u8,
        string_length: *Expression,
        sequence_literal: []const *Expression,
        collection_method: CollectionMethod,
        cascade_target,
        cascade: Cascade,
        variable: Variable,
        self,
        call: Call,
        value_call: ValueCall,
        lambda: Lambda,
        owner_self,
        method_call: MethodCall,
        protocol_method_call: ProtocolMethodCall,
        static_method_call: StaticMethodCall,
        static_field_access: StaticFieldAccess,
        super_method_call: SuperMethodCall,
        class_initializer: ClassInitializer,
        structure_initializer: StructureInitializer,
        enum_initializer: EnumInitializer,
        enum_raw_value: *Expression,
        match_expression: Match,
        member_access: MemberAccess,
        bound_function: MemberAccess,
        adapt_function: *Expression,
        optional_wrap: *Expression,
        optional_unwrap: Variable,
        safe_access: SafeAccess,
        index_access: IndexAccess,
        slice_access: SliceAccess,
        try_expression: Try,
        move_expression: Move,
        borrow_expression: BorrowExpression,
        unary: Unary,
        binary: Binary,
        conversion: Conversion,
        protocol_conversion: ProtocolConversion,
    },

    pub const Unary = struct {
        operator: Ast.UnaryOperator,
        operand: *Expression,
    };

    pub const Try = struct {
        operand: *Expression,
        temporary_name: []const u8,
        error_type: Type,
        return_enum_generated_name: []const u8,
        failure_variant_index: usize,
    };

    pub const Variable = struct {
        generated_name: []const u8,
        capture_box: *const bool,
    };

    pub const Call = struct {
        generated_name: []const u8,
        arguments: []const *Expression,
        is_native: bool,
        native_module_name: ?[]const u8,
        native_function_name: ?[]const u8,
    };

    pub const ValueCall = struct {
        callee: *Expression,
        arguments: []const *Expression,
        owner: ?*Expression = null,
    };

    pub const Lambda = struct {
        pub const Capture = struct {
            generated_name: []const u8,
            by_value: bool,
        };

        parameters: []const Parameter,
        return_type: Type,
        statements: []const Statement,
        captures: []const Capture,
        captures_self: bool,
        self_is_class: bool,
    };

    pub const MethodCall = struct {
        object: *Expression,
        source_name: []const u8,
        generated_name: []const u8,
        arguments: []const *Expression,
        method_id: MethodId,
        receiver: Receiver,
        position: Source.Position,
    };

    pub const ProtocolMethodCall = struct {
        object: *Expression,
        source_name: []const u8,
        generated_name: []const u8,
        arguments: []const *Expression,
        receiver: Receiver,
        position: Source.Position,
    };

    pub const ProtocolConversion = struct {
        operand: *Expression,
        witness_name: []const u8,
    };

    pub const Move = struct {
        operand: *Expression,
    };

    pub const BorrowExpression = struct {
        operand: *Expression,
    };

    pub const StaticMethodCall = struct {
        owner_generated_name: []const u8,
        generated_name: []const u8,
        arguments: []const *Expression,
    };

    pub const StaticFieldAccess = struct {
        owner_generated_name: []const u8,
        generated_name: []const u8,
    };

    pub const SuperMethodCall = struct {
        base_generated_name: []const u8,
        generated_name: []const u8,
        arguments: []const *Expression,
    };

    pub const CollectionMethod = struct {
        object: *Expression,
        operation: Operation,
        arguments: []const *Expression,
        position: Source.Position,

        pub const Operation = enum {
            count,
            is_empty,
            append,
            append_range,
            prepend,
            insert,
            take,
            take_first,
            take_last,
            replace,
            swap,
            reverse,
            clear,
        };
    };

    pub const Cascade = struct {
        object: *Expression,
        operations: []const Operation,

        pub const Operation = union(enum) {
            method_call: *Expression,
            field_assignment: FieldAssignment,
        };

        pub const FieldAssignment = struct {
            generated_name: []const u8,
            value: *Expression,
        };
    };

    pub const StructureInitializer = struct {
        generated_name: []const u8,
        fields: []const *Expression,
    };

    pub const EnumInitializer = struct {
        enum_generated_name: []const u8,
        variant_index: usize,
        arguments: []const *Expression,
    };

    pub const Match = struct {
        subject: *Expression,
        temporary_name: []const u8,
        mode: TransferMode,
        branches: []const Branch,

        pub const Branch = struct {
            variant_index: ?usize,
            bindings: []const Binding,
            body: Body,
        };

        pub const Binding = struct {
            generated_name: []const u8,
            type: Type,
            mutability: Ast.Mutability,
            capture_box: *const bool,
        };

        pub const Body = union(enum) {
            expression: *Expression,
            statements: []const Statement,
        };
    };

    pub const ClassInitializer = struct {
        generated_name: []const u8,
        arguments: []const *Expression,
    };

    pub const MemberAccess = struct {
        object: *Expression,
        generated_name: []const u8,
    };

    pub const IndexAccess = struct {
        object: *Expression,
        index: *Expression,
    };

    pub const SliceAccess = struct {
        object: *Expression,
        start: *Expression,
        end: *Expression,
    };

    pub const Binary = struct {
        operator: Ast.BinaryOperator,
        left: *Expression,
        right: *Expression,
    };

    pub const Conversion = struct {
        operand: *Expression,
        target_type: Type,
    };

    pub const SafeAccess = struct {
        receiver: *Expression,
        end: *Expression,
    };
};

pub const Statement = union(enum) {
    print: *Expression,
    assertion: Assertion,
    panic_statement: Panic,
    variable_declaration: VariableDeclaration,
    assignment: Assignment,
    if_statement: If,
    while_statement: While,
    for_statement: For,
    break_statement,
    continue_statement,
    return_statement: ?*Expression,
    expression_statement: *Expression,

    pub const Assertion = struct {
        position: Source.Position,
        condition: *Expression,
        message: *Expression,
    };

    pub const Panic = struct {
        position: Source.Position,
        message: *Expression,
    };

    pub const VariableDeclaration = struct {
        generated_name: []const u8,
        type: Type,
        is_noncopyable: bool,
        mutability: Ast.Mutability,
        initializer: *Expression,
        capture_box: *const bool,
    };

    pub const Assignment = struct {
        position: Source.Position,
        target: *Expression,
        operator: Ast.AssignmentOperator,
        value: ?*Expression,
    };

    pub const If = struct {
        condition: Condition,
        body: []const Statement,
        alternatives: []const Alternative,
        else_body: ?[]const Statement,

        pub const Alternative = struct {
            condition: Condition,
            body: []const Statement,
        };
    };

    pub const While = struct {
        condition: Condition,
        body: []const Statement,
    };

    pub const Condition = union(enum) {
        expression: *Expression,
        binding: ConditionalBinding,
    };

    pub const ConditionalBinding = struct {
        source: *Expression,
        temporary_name: []const u8,
        generated_name: []const u8,
        type: Type,
        mode: TransferMode,
        mutability: Ast.Mutability,
        capture_box: *const bool,
    };

    pub const For = struct {
        generated_name: []const u8,
        element_type: Type,
        element_noncopyable: bool,
        binding: Ast.IterationBinding,
        source: IterationSource,
        body: []const Statement,
        capture_box: *const bool,

        pub const IterationSource = union(enum) {
            collection: *Expression,
            integer_range: IntegerRange,
        };

        pub const IntegerRange = struct {
            start: *Expression,
            end: *Expression,
            generated_start_name: []const u8,
            generated_end_name: []const u8,
            generated_step_name: []const u8,
            generated_current_name: []const u8,
        };
    };
};

pub const Program = struct {
    enums: []const Enum,
    protocols: []const Protocol,
    structures: []const Structure,
    functions: []const Function,
};

pub const Protocol = struct {
    generated_name: []const u8,
    requirements: []const ProtocolMethod,
};

pub const ProtocolMethod = struct {
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
};

pub const ProtocolConformance = struct {
    protocol_index: usize,
    protocol_generated_name: []const u8,
    witness_name: []const u8,
    method_generated_names: []const []const u8,
};

pub const Enum = struct {
    generated_name: []const u8,
    raw_type: ?Type,
    is_copyable: bool,
    variants: []const EnumVariant,
};

pub const EnumVariant = struct {
    associated_types: []const Type,
    raw_value: ?*Expression,
};

pub const Structure = struct {
    generated_name: []const u8,
    is_class: bool,
    is_owner: bool = false,
    is_noncopyable: bool,
    equality_comparable: bool,
    protocol_conformances: []const ProtocolConformance,
    base: ?StructureType,
    implicit_constructor_available: bool,
    implicit_base_initializer: ?BaseInitializer,
    fields: []const StructureField,
    static_fields: []const StructureField,
    constructors: []const Constructor,
    drop: ?Drop,
    methods: []Method,
};

pub const BaseInitializer = struct {
    generated_name: []const u8,
    arguments: []const *Expression,
};

pub const StructureField = struct {
    generated_name: []const u8,
    type: Type,
    visibility: Ast.MemberVisibility,
    mutability: Ast.Mutability,
    initializer: ?*Expression,
    reset_value: ?*Expression = null,
};

pub const Constructor = struct {
    parameters: []const Parameter,
    base_initializer: ?BaseInitializer,
    statements: []const Statement,
    visibility: Ast.MemberVisibility,
};

pub const Drop = struct {
    statements: []const Statement,
};

pub const Parameter = struct {
    generated_name: []const u8,
    type: Type,
    mode: Ast.ParameterMode,
    capture_box: *const bool,
};

pub const Function = struct {
    generated_name: []const u8,
    return_type: Type,
    parameters: []const Parameter,
    statements: []const Statement,
    is_main: bool,
    is_native: bool,
    native_module_name: ?[]const u8,
    native_function_name: ?[]const u8,
};

pub const Method = struct {
    generated_name: []const u8,
    return_type: Type,
    parameters: []const Parameter,
    statements: []const Statement,
    is_mutating: bool,
    visibility: Ast.MemberVisibility,
    is_override: bool,
    is_static: bool,
    is_extension: bool,
};

pub const MethodId = struct {
    structure_index: usize,
    method_index: usize,
};

pub const Receiver = union(enum) {
    self,
    borrowed_self,
    mutable,
    immutable: struct {
        name: []const u8,
        control_binding: bool,
        read_iteration: bool,
        collection_shell: bool,
    },
    immutable_field: []const u8,
    borrowed: []const u8,
    temporary,
    cascade_temporary,
};

const Symbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    mutability: Ast.Mutability,
    state: *BindingState,
    scope_depth: usize,
    control_binding: bool = false,
    read_iteration: bool = false,
    immutable_collection_shell: bool = false,
    unwrap_optional: bool = false,
    original_type: ?Type = null,
};

const Scope = struct {
    parent: ?*const Scope,
    depth: usize,
    symbols: std.ArrayList(Symbol) = .empty,
    borrows: std.ArrayList(Borrow) = .empty,
};

const OwnerStateSnapshot = struct {
    name: []const u8,
    state: *BindingState,
    available: bool,
    consumed_at: ?Source.Position,
};

const LoopFlow = struct {
    tracked: []const OwnerStateSnapshot,
    break_states: std.ArrayList([]const OwnerStateSnapshot) = .empty,
    continue_states: std.ArrayList([]const OwnerStateSnapshot) = .empty,
};

const LambdaContext = struct {
    local_depth: usize,
    captures: std.ArrayList(Expression.Lambda.Capture) = .empty,
    captures_self: bool = false,
    owner_self: bool = false,
    lifetime_depth: usize = 0,
    parent: ?*LambdaContext,
};

fn releaseBorrow(borrow: Borrow) void {
    const root = borrow.root orelse return;
    if (borrow.mutable) {
        if (borrow.transient) {
            root.transient_mutable_borrows -= 1;
        } else {
            root.mutable_borrow = false;
        }
    } else {
        root.immutable_borrows -= 1;
    }
}

const FunctionSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    parameter_stored: []const bool,
    position: Source.Position,
    is_main: bool,
    is_native: bool,
    native_module_name: ?[]const u8,
    native_function_name: ?[]const u8,
};

const StructureSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    is_class: bool,
    is_owner: bool,
    module_files: []const usize,
    base_index: ?usize,
    protocol_conformances: []const ProtocolConformanceSymbol,
    fields: []StructureFieldSymbol,
    static_fields: []StructureFieldSymbol,
    constructors: []ConstructorSymbol,
    methods: []MethodSymbol,
    position: Source.Position,
};

const ProtocolConformanceSymbol = struct {
    protocol_index: usize,
    position: Source.Position,
    extension_visible_files: ?[]const usize,
    extension_module_name: ?[]const u8,
};

const ProtocolSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    requirements: []const ProtocolRequirement,
    position: Source.Position,
};

const ProtocolRequirement = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    position: Source.Position,
};

const EnumSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    raw_type: ?Type,
    variants: []const EnumVariantSymbol,
    position: Source.Position,
};

const EnumVariantSymbol = struct {
    source_name: []const u8,
    associated_types: []const Type,
    raw_value: ?*Expression,
    position: Source.Position,
};

const ConstructorSymbol = struct {
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    parameter_stored: []const bool,
    position: Source.Position,
    visibility: Ast.MemberVisibility,
};

const ConstructorCandidate = struct {
    symbol: ConstructorSymbol,
    index: usize,
};

const ImplicitBaseInitialization = struct {
    available: bool,
    initializer: ?BaseInitializer,
};

const MethodSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    parameter_stored: []const bool,
    position: Source.Position,
    visibility: Ast.MemberVisibility,
    is_override: bool,
    is_static: bool,
    extension_visible_files: ?[]const usize,
    extension_module_name: ?[]const u8,
    direct_mutation: bool = false,
    dependencies: []const MethodId = &.{},
    is_mutating: bool = false,
};

const MethodCandidate = struct {
    symbol: MethodSymbol,
    structure_index: usize,
    index: usize,
};

fn methodCandidatesContainSlot(candidates: []const MethodCandidate, generated_name: []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate.symbol.generated_name, generated_name)) return true;
    }
    return false;
}

fn fileSetContains(files: []const usize, target: usize) bool {
    for (files) |file| if (file == target) return true;
    return false;
}

fn fileSetsOverlap(left: []const usize, right: []const usize) bool {
    for (left) |file| if (fileSetContains(right, file)) return true;
    return false;
}

fn visibilityRank(visibility: Ast.MemberVisibility) u2 {
    return switch (visibility) {
        .private_access => 0,
        .subclass => 1,
        .public_access => 2,
    };
}

const FieldCandidate = struct {
    symbol: StructureFieldSymbol,
    structure_index: usize,
};

const StructureFieldSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    position: Source.Position,
    ast_initializer: ?*Ast.Expression,
    visibility: Ast.MemberVisibility,
    mutability: Ast.Mutability,
    default_value: ?*Expression = null,
};

const FieldInitialization = enum {
    uninitialized,
    maybe_initialized,
    initialized,
};

pub const Analyzer = struct {
    allocator: Allocator,
    native_module_names: []const []const u8 = &.{},
    next_symbol_id: usize = 0,
    functions: std.ArrayList(FunctionSymbol) = .empty,
    enums: std.ArrayList(EnumSymbol) = .empty,
    protocols: std.ArrayList(ProtocolSymbol) = .empty,
    structures: std.ArrayList(StructureSymbol) = .empty,
    current_return_type: Type = .void,
    current_structure_index: ?usize = null,
    current_method_index: ?usize = null,
    current_constructor: bool = false,
    current_drop: bool = false,
    current_method_static: bool = false,
    current_extension: bool = false,
    current_method_direct_mutation: bool = false,
    current_method_dependencies: std.ArrayList(MethodId) = .empty,
    current_self_state: BindingState = .{},
    loop_depth: usize = 0,
    current_loop_flow: ?*LoopFlow = null,
    function_scope_depth: usize = 0,
    current_lambda: ?*LambdaContext = null,
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
                .generated_name = symbol.generated_name,
                .is_class = symbol.is_class,
                .is_owner = symbol.is_owner,
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
        var functions: std.ArrayList(Function) = .empty;
        for (program.functions, self.functions.items) |ast_function, symbol| {
            try functions.append(self.allocator, try self.function(ast_function, symbol));
        }
        self.inferMethodMutability();
        for (structures.items, self.structures.items) |*structure, symbol| {
            for (structure.methods, symbol.methods) |*method_value, method_symbol| {
                method_value.is_mutating = method_symbol.is_mutating;
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

    fn collectEnumNames(self: *Analyzer, ast_enums: []const Ast.Enum) AnalyzeError!void {
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

    fn collectEnumVariants(self: *Analyzer, ast_enums: []const Ast.Enum) AnalyzeError!void {
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

    fn validateNoncopyableStaticFields(self: *Analyzer) AnalyzeError!void {
        for (self.structures.items) |structure| {
            for (structure.static_fields) |field| {
                if (try self.isNonCopyableType(field.type)) {
                    return self.fail(field.position, "a static field cannot own a noncopyable value");
                }
            }
        }
    }

    fn enumRawValue(
        self: *Analyzer,
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

    fn collectStructures(self: *Analyzer, ast_structures: []const Ast.Structure) AnalyzeError!void {
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
                    if (sameSignature(
                        existing.parameter_types,
                        existing.parameter_modes,
                        parameter_types.items,
                        parameter_modes.items,
                    )) return self.fail(ast_constructor.position, "constructor 'init' with this signature is already declared in this class");
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
                        std.mem.eql(u8, existing.source_name, ast_method.name) and sameSignature(
                        existing.parameter_types,
                        existing.parameter_modes,
                        parameter_types.items,
                        parameter_modes.items,
                    )) duplicate: {
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
                            try std.fmt.allocPrint(self.allocator, "extension method '{s}' conflicts with an existing method signature on type '{s}'", .{ ast_method.name, ast_structure.name })
                        else
                            try std.fmt.allocPrint(self.allocator, "method '{s}' with this signature is already declared in {s} '{s}'", .{ ast_method.name, if (ast_structure.is_class) "class" else "struct", ast_structure.name });
                        return self.fail(ast_method.name_position, message);
                    }
                }
                const return_type = try typeFromReturn(self, ast_method.return_type, ast_method.position);
                if (return_type == .reference) return self.fail(ast_method.position, "a method cannot return a reference");
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
                });
            }
            self.structures.items[structure_index].methods = try methods.toOwnedSlice(self.allocator);
        }
        try self.validateInheritedMembers();
        try self.validateProtocolConformances();
    }

    fn collectStructureNames(self: *Analyzer, ast_structures: []const Ast.Structure) AnalyzeError!void {
        for (ast_structures, 0..) |ast_structure, structure_index| {
            if (self.findStructure(ast_structure.name) != null or self.findEnum(ast_structure.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "type '{s}' is already declared", .{ast_structure.name});
                return self.fail(ast_structure.name_position, message);
            }
            try self.structures.append(self.allocator, .{
                .source_name = ast_structure.name,
                .generated_name = if (ast_structure.is_class)
                    try std.fmt.allocPrint(self.allocator, "SilexClass{d}", .{structure_index})
                else
                    try std.fmt.allocPrint(self.allocator, "SilexStruct{d}", .{structure_index}),
                .is_class = ast_structure.is_class,
                .is_owner = !ast_structure.is_class and ast_structure.drop != null,
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

    fn collectProtocols(self: *Analyzer, ast_protocols: []const Ast.Protocol) AnalyzeError!void {
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
                    if (std.mem.eql(u8, existing.source_name, requirement.name) and sameSignature(
                        existing.parameter_types,
                        existing.parameter_modes,
                        parameter_types.items,
                        parameter_modes.items,
                    )) {
                        const message = try std.fmt.allocPrint(self.allocator, "protocol method '{s}' with this signature is already declared", .{requirement.name});
                        return self.fail(requirement.name_position, message);
                    }
                }
                const return_type = try typeFromReturn(self, requirement.return_type, requirement.position);
                if (return_type == .reference) return self.fail(requirement.position, "a protocol method cannot return a reference");
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

    fn validateProtocolConformances(self: *Analyzer) AnalyzeError!void {
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

    fn findProtocolRequirementMethod(
        self: *const Analyzer,
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

    fn protocolConformance(
        self: *const Analyzer,
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

    fn structureConformsToProtocol(
        self: *const Analyzer,
        structure_index: usize,
        protocol_index: usize,
        source_file: ?usize,
    ) bool {
        return self.protocolConformance(structure_index, protocol_index, source_file) != null;
    }

    fn protocolConformances(self: *Analyzer, structure_index: usize) AnalyzeError![]const ProtocolConformance {
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

    fn validateInheritanceCycles(self: *Analyzer) AnalyzeError!void {
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

    fn validateInheritedMembers(self: *Analyzer) AnalyzeError!void {
        const validated = try self.allocator.alloc(bool, self.structures.items.len);
        @memset(validated, false);
        for (self.structures.items, 0..) |structure, structure_index| {
            if (structure.is_class) try self.validateInheritedStructure(structure_index, validated);
        }
    }

    fn validateInheritedStructure(self: *Analyzer, structure_index: usize, validated: []bool) AnalyzeError!void {
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

    fn collectFunctions(self: *Analyzer, ast_functions: []const Ast.Function) AnalyzeError!void {
        var main_count: usize = 0;
        for (ast_functions, 0..) |ast_function, index| {
            const is_main = std.mem.eql(u8, ast_function.name, "main");
            if (is_main) main_count += 1;
            const native_module_name = if (ast_function.is_native) moduleName(ast_function.name) else null;
            const native_function_name = if (ast_function.is_native) lastNameSegment(ast_function.name) else null;
            if (ast_function.is_native) {
                const module_name = native_module_name orelse return self.fail(
                    ast_function.position,
                    "native functions are only available in a named module with Module.json native configuration",
                );
                if (!self.isNativeModule(module_name)) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "native functions require module '{s}' or one of its parents to declare Module.json native configuration",
                        .{module_name},
                    );
                    return self.fail(ast_function.position, message);
                }
                if (!std.mem.startsWith(u8, native_function_name.?, "native_")) {
                    return self.fail(ast_function.name_position, "native function names must begin with 'native_'");
                }
                if (ast_function.is_public) return self.fail(ast_function.position, "native functions cannot be public");
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
                if (std.mem.eql(u8, existing.source_name, ast_function.name) and sameSignature(
                    existing.parameter_types,
                    existing.parameter_modes,
                    parameter_types.items,
                    parameter_modes.items,
                )) {
                    const message = try std.fmt.allocPrint(self.allocator, "function '{s}' with this signature is already declared", .{ast_function.name});
                    return self.fail(ast_function.name_position, message);
                }
            }
            if (ast_function.is_native and self.findFunction(ast_function.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "native function '{s}' is already declared", .{ast_function.name});
                return self.fail(ast_function.name_position, message);
            }
            const return_type = try typeFromReturn(self, ast_function.return_type, ast_function.position);
            if (return_type == .reference) return self.fail(ast_function.position, "a function cannot return a reference");
            try self.rejectUniqueOwnerComposition(return_type, true, ast_function.position);
            if (ast_function.is_native) {
                if (!isNativeReturnType(return_type)) {
                    const return_name = try allocatedTypeName(self.allocator, return_type);
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "native functions cannot return '{s}'",
                        .{return_name},
                    );
                    return self.fail(ast_function.position, message);
                }
                for (ast_function.parameters, parameter_types.items, parameter_modes.items) |parameter, parameter_type, mode| {
                    if (!isNativeParameterType(parameter_type) or mode != .value) {
                        const parameter_name = try allocatedTypeName(self.allocator, parameter_type);
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "native parameter '{s}' cannot use '{s}'",
                            .{ parameter.name, parameter_name },
                        );
                        return self.fail(parameter.position, message);
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
                .native_module_name = native_module_name,
                .native_function_name = native_function_name,
            });
        }
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

    fn validateStructureDefaults(self: *Analyzer) AnalyzeError!void {
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

    fn validateDefaultShape(
        self: *Analyzer,
        ast: *const Ast.Expression,
        expected_type: Type,
    ) AnalyzeError!void {
        const valid = switch (expected_type) {
            .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => ast.value == .integer,
            .float, .float64 => ast.value == .integer or ast.value == .floating,
            .bool => ast.value == .boolean,
            .str => ast.value == .string,
            .list => ast.value == .sequence_literal and ast.value.sequence_literal.len == 0,
            .fixed_array, .protocol => false,
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

    fn function(self: *Analyzer, ast: Ast.Function, symbol: FunctionSymbol) AnalyzeError!Function {
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
                .generated_name = generated_name,
                .type = parameter_type,
                .mode = mode,
                .capture_box = &state.capture_box,
            });
        }
        self.current_return_type = symbol.return_type;
        const function_statements = try self.statements(ast.statements, &scope);
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
            .native_module_name = symbol.native_module_name,
            .native_function_name = symbol.native_function_name,
        };
    }

    fn method(
        self: *Analyzer,
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
                .generated_name = generated_name,
                .type = parameter_type,
                .mode = mode,
                .capture_box = &state.capture_box,
            });
        }

        self.current_return_type = symbol.return_type;
        const method_statements = try self.statements(ast.statements, &scope);
        self.releaseScopeBorrows(&scope);
        if (!typeEqual(symbol.return_type, .void) and !blockAlwaysReturns(method_statements)) {
            const message = try std.fmt.allocPrint(self.allocator, "method '{s}' must return '{s}' on every path", .{ ast.name, typeName(symbol.return_type) });
            return self.fail(ast.name_position, message);
        }
        self.structures.items[structure_index].methods[method_index].direct_mutation = self.current_method_direct_mutation;
        self.structures.items[structure_index].methods[method_index].dependencies = try self.current_method_dependencies.toOwnedSlice(self.allocator);
        return .{
            .generated_name = symbol.generated_name,
            .return_type = symbol.return_type,
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .statements = method_statements,
            .is_mutating = false,
            .visibility = symbol.visibility,
            .is_override = symbol.is_override,
            .is_static = symbol.is_static,
            .is_extension = symbol.extension_visible_files != null,
        };
    }

    fn constructor(
        self: *Analyzer,
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

    fn dropBlock(
        self: *Analyzer,
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

    fn constructorBaseInitialization(
        self: *Analyzer,
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

    fn validateConstructorInitialization(
        self: *Analyzer,
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

    fn validateConstructorStatements(
        self: *Analyzer,
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

    fn validateConstructorStatement(
        self: *Analyzer,
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

    fn validateConstructorCondition(
        self: *Analyzer,
        structure: *const StructureSymbol,
        condition: Statement.Condition,
        initialized: []const FieldInitialization,
    ) AnalyzeError!void {
        switch (condition) {
            .expression => |value| try self.validateConstructorExpression(structure, value, initialized),
            .binding => |binding| try self.validateConstructorExpression(structure, binding.source, initialized),
        }
    }

    fn validateConstructorExpression(
        self: *Analyzer,
        structure: *const StructureSymbol,
        expression_value: *const Expression,
        initialized: []const FieldInitialization,
    ) AnalyzeError!void {
        switch (expression_value.value) {
            .integer, .floating, .boolean, .null, .string, .cascade_target, .variable, .static_field_access, .optional_unwrap => {},
            .self, .owner_self => if (!allFieldsInitialized(initialized)) {
                return self.fail(expression_value.position, "'self' cannot escape before every class field is initialized");
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
                return self.fail(expression_value.position, "a constructor lambda cannot capture 'self' before every class field is initialized");
            },
            .method_call => |call| {
                if (call.object.value == .self) {
                    if (!allFieldsInitialized(initialized)) return self.fail(call.position, "an instance method cannot be called before every class field is initialized");
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

    fn requireConstructorFieldsInitialized(
        self: *Analyzer,
        structure: *const StructureSymbol,
        initialized: []const FieldInitialization,
        position: Source.Position,
    ) AnalyzeError!void {
        for (initialized, 0..) |field_initialized, field_index| {
            if (field_initialized == .initialized) continue;
            const message = try std.fmt.allocPrint(
                self.allocator,
                "constructor of class '{s}' leaves field '{s}' without a value",
                .{ structure.source_name, structure.fields[field_index].source_name },
            );
            return self.fail(position, message);
        }
    }

    fn statements(
        self: *Analyzer,
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

    fn statement(self: *Analyzer, ast: Ast.Statement, scope: *Scope) AnalyzeError!Statement {
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

    fn analyzeAssertion(self: *Analyzer, ast: Ast.Statement.Assert, scope: *const Scope) AnalyzeError!Statement {
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

    fn analyzePanic(self: *Analyzer, ast: Ast.Statement.Panic, scope: *const Scope) AnalyzeError!Statement {
        const message = try self.expression(ast.message, scope);
        if (!typeEqual(message.type, .str)) {
            const diagnostic = try typeMismatchMessage(self.allocator, .str, message.type);
            return self.fail(ast.message.position, diagnostic);
        }
        return .{ .panic_statement = .{ .position = ast.position, .message = message } };
    }

    fn variableDeclaration(
        self: *Analyzer,
        declaration: Ast.Statement.VariableDeclaration,
        scope: *Scope,
    ) AnalyzeError!Statement {
        try self.requireAvailableVariableName(scope, declaration.name, declaration.name_position);

        const declared_annotation_type = if (declaration.annotation) |annotation|
            try typeFromAnnotation(self, annotation, declaration.name_position)
        else
            null;
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
        const declared_type = declared_annotation_type orelse initializer.type;
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

        if (declaration.mutability == .immutable and declared_type != .list and declared_type != .fixed_array) {
            try self.requireIndependentLetType(declared_type, declaration.name_position);
        }
        if (declared_type == .reference and declaration.mutability == .mutable) {
            return self.fail(declaration.name_position, "a reference must be declared with 'let'");
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        const state = try self.newBindingState(declared_type);
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
            .generated_name = generated_name,
            .type = declared_type,
            .is_noncopyable = try self.isNonCopyableType(declared_type),
            .mutability = declaration.mutability,
            .initializer = initializer,
            .capture_box = &state.capture_box,
        } };
    }

    fn requireAvailableVariableName(
        self: *Analyzer,
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

    fn assignment(
        self: *Analyzer,
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

    fn uniqueOwnerAssignment(
        self: *Analyzer,
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
        const target = try self.newExpression(.{
            .type = symbol.type,
            .position = ast.target.position,
            .value = .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
        });
        symbol.state.owner_available = true;
        symbol.state.consumed_at = null;
        return .{ .assignment = .{
            .position = ast.position,
            .target = target,
            .operator = .assign,
            .value = value,
        } };
    }

    fn checkedAssignment(
        self: *Analyzer,
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
                        .self, .static => return self.fail(ast.value.?.position, "a 'borrow' parameter cannot be stored beyond its call"),
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

    fn snapshotOwnerStates(self: *Analyzer, scope: *const Scope) Allocator.Error![]const OwnerStateSnapshot {
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
                });
            }
        }
        return snapshots.toOwnedSlice(self.allocator);
    }

    fn captureOwnerStates(self: *Analyzer, tracked: []const OwnerStateSnapshot) Allocator.Error![]const OwnerStateSnapshot {
        const snapshots = try self.allocator.alloc(OwnerStateSnapshot, tracked.len);
        for (tracked, snapshots) |entry, *snapshot| snapshot.* = .{
            .name = entry.name,
            .state = entry.state,
            .available = entry.state.owner_available,
            .consumed_at = entry.state.consumed_at,
        };
        return snapshots;
    }

    fn restoreOwnerStates(snapshot: []const OwnerStateSnapshot) void {
        for (snapshot) |entry| {
            entry.state.owner_available = entry.available;
            entry.state.consumed_at = entry.consumed_at;
        }
    }

    fn mergeOwnerStates(base: []const OwnerStateSnapshot, outcomes: []const []const OwnerStateSnapshot) void {
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
        }
    }

    fn requireSameOwnerStates(
        self: *Analyzer,
        expected: []const OwnerStateSnapshot,
        actual: []const OwnerStateSnapshot,
        loop_position: Source.Position,
    ) AnalyzeError!void {
        for (expected, actual) |before, after| {
            if (before.available == after.available) continue;
            const position = after.consumed_at orelse loop_position;
            const message = try std.fmt.allocPrint(
                self.allocator,
                "unique resource '{s}' must have the same availability on every path returning to the loop header",
                .{before.name},
            );
            return self.fail(position, message);
        }
    }

    fn ifStatement(
        self: *Analyzer,
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
        mergeOwnerStates(tracked, outcomes.items);

        return .{ .if_statement = .{
            .condition = condition,
            .body = body,
            .alternatives = try alternatives.toOwnedSlice(self.allocator),
            .else_body = else_body,
        } };
    }

    fn whileStatement(
        self: *Analyzer,
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
        mergeOwnerStates(tracked, exits.items);
        return .{ .while_statement = .{
            .condition = condition,
            .body = body,
        } };
    }

    fn analyzeCondition(
        self: *Analyzer,
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
                    return self.fail(binding.name_position, "a binding extracted with 'borrow' is read-only and cannot use 'var'");
                }
                const source = switch (mode) {
                    .copy => try self.expression(binding.source, parent_scope),
                    .move => try self.moveExpression(binding.source.value.move_expression, parent_scope),
                    .borrow => try self.readBorrowValue(binding.source.value.borrow_expression, parent_scope, null),
                };
                if (source.type != .optional) return self.fail(binding.source.position, "conditional binding source must have an optional type");
                const noncopyable = try self.isNonCopyableType(source.type);
                if (noncopyable and mode == .copy and !self.isNonCopyableTemporary(source)) {
                    return self.fail(binding.source.position, "a named noncopyable optional must be extracted with 'move' or 'borrow'");
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

    fn applyPresenceReduction(
        self: *Analyzer,
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

    fn forStatement(
        self: *Analyzer,
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
                element_type = switch (collection.type) {
                    .list => |element| element.*,
                    .fixed_array => |array| array.element.*,
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
        mergeOwnerStates(tracked, exits.items);
        return .{ .for_statement = .{
            .generated_name = generated_name,
            .element_type = element_type,
            .element_noncopyable = element_noncopyable,
            .binding = ast.binding,
            .source = source,
            .body = body,
            .capture_box = &state.capture_box,
        } };
    }

    fn returnStatement(
        self: *Analyzer,
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
            if (value.borrowed_parameter) {
                return self.fail(ast.position, "a 'borrow' parameter cannot be returned from its call");
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

    fn expression(self: *Analyzer, ast: *const Ast.Expression, scope: *const Scope) AnalyzeError!*Expression {
        return self.expressionForBorrow(ast, scope);
    }

    fn expressionForBorrow(
        self: *Analyzer,
        ast: *const Ast.Expression,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        if (ast.value == .unary and ast.value.unary.operator == .borrow) {
            return self.fail(ast.value.unary.operator_position, "'&' is only valid for an argument of a parameter declared with '&'");
        }
        if (ast.value == .borrow_expression) {
            return self.fail(ast.value.borrow_expression.operator_position, "'borrow' is only valid for an argument of a parameter declared with 'borrow'");
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
            .identifier => |name| self.variableExpression(ast.position, name, scope),
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
            .slice_access => |access| self.sliceAccessExpression(access, scope),
            .try_expression => |try_value| self.tryExpression(try_value, scope),
            .move_expression => |move_value| self.moveExpression(move_value, scope),
            .borrow_expression => unreachable,
            .unary => |unary| self.unaryExpression(unary, scope),
            .conversion => |conversion| self.conversionExpression(conversion, scope),
            .binary => |binary| self.binaryExpression(binary, scope),
            .match_expression => |match_value| self.matchExpression(match_value, scope),
        };
    }

    fn expressionForExpected(
        self: *Analyzer,
        ast: *const Ast.Expression,
        scope: *const Scope,
        expected_type: ?Type,
    ) AnalyzeError!*Expression {
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
        return self.expressionForBorrow(ast, scope);
    }

    fn integerExpression(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
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

    fn floatExpression(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
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

    fn stringExpression(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
        return self.newExpression(.{
            .type = .str,
            .position = position,
            .value = .{ .string = try self.decodeStringLiteral(position, lexeme) },
        });
    }

    fn sequenceLiteralExpression(
        self: *Analyzer,
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

    fn decodeStringLiteral(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError![]const u8 {
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

    fn defaultExpression(self: *Analyzer, type_value: Type, position: Source.Position) AnalyzeError!*Expression {
        return switch (type_value) {
            .void => self.fail(position, "type 'void' has no default value"),
            .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .integer = 0 } }),
            .float, .float64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .floating = "0.0" } }),
            .bool => self.newExpression(.{ .type = .bool, .position = position, .value = .{ .boolean = false } }),
            .str => self.newExpression(.{ .type = .str, .position = position, .value = .{ .string = "" } }),
            .list, .fixed_array => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .sequence_literal = &.{} } }),
            .reference => self.fail(position, "a reference requires an initializer"),
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

    fn intrinsicDefaultExpression(
        self: *Analyzer,
        type_value: Type,
        position: Source.Position,
    ) AnalyzeError!?*Expression {
        if (!self.hasIntrinsicDefault(type_value)) return null;
        return try self.defaultExpression(type_value, position);
    }

    fn hasIntrinsicDefault(self: *const Analyzer, type_value: Type) bool {
        return switch (type_value) {
            .void, .reference, .function, .protocol, .enumeration, .null => false,
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

    fn variableExpression(
        self: *Analyzer,
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
            .value = if (narrowed)
                .{ .optional_unwrap = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } }
            else
                .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
        });
    }

    fn selfExpression(self: *Analyzer, position: Source.Position) AnalyzeError!*Expression {
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

    fn binaryExpression(
        self: *Analyzer,
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

    fn conversionExpression(
        self: *Analyzer,
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

    fn callExpression(self: *Analyzer, call: Ast.Expression.Call, scope: *const Scope) AnalyzeError!*Expression {
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
        var transient_borrows: std.ArrayList(Borrow) = .empty;
        defer for (transient_borrows.items) |borrow| releaseBorrow(borrow);
        for (call.arguments, function_symbol.parameter_types, function_symbol.parameter_modes, function_symbol.parameter_stored, 0..) |argument, expected_type, mode, is_stored, index| {
            var value = try self.argumentForMode(argument, scope, expected_type, mode);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
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
            .type = function_symbol.return_type,
            .position = call.name_position,
            .value = .{ .call = .{
                .generated_name = function_symbol.generated_name,
                .arguments = try arguments.toOwnedSlice(self.allocator),
                .is_native = function_symbol.is_native,
                .native_module_name = function_symbol.native_module_name,
                .native_function_name = function_symbol.native_function_name,
            } },
        });
    }

    fn valueCallExpression(
        self: *Analyzer,
        call: Ast.Expression.ValueCall,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const callee = try self.expression(call.callee, scope);
        return self.checkedValueCall(callee, call.arguments, call.parenthesis_position, scope, null);
    }

    fn checkedValueCall(
        self: *Analyzer,
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

    fn lambdaExpression(
        self: *Analyzer,
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
                .generated_name = generated_name,
                .type = parameter_type,
                .mode = parameter.mode,
                .capture_box = &state.capture_box,
            });
        }
        const return_type = try typeFromReturn(self, lambda.return_type, lambda.position);
        try self.rejectUniqueOwnerComposition(return_type, true, lambda.position);
        const return_pointer = try self.allocator.create(Type);
        return_pointer.* = return_type;
        var lambda_type: Type = .{ .function = .{
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

    fn methodCallExpression(
        self: *Analyzer,
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
                    if (call.object.value == .self and self.current_method_index != null) self.current_method_direct_mutation = true;
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

    fn methodCallExpressionWithObject(
        self: *Analyzer,
        call: Ast.Expression.MethodCall,
        object: *Expression,
        scope: *const Scope,
        receiver: Receiver,
        allow_temporary_collection_mutation: bool,
    ) AnalyzeError!*Expression {
        switch (object.type) {
            .list, .fixed_array, .str => return self.collectionMethodCallExpression(
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
        return self.newExpression(.{
            .type = method_symbol.return_type,
            .position = call.name_position,
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

    fn protocolMethodCallExpression(
        self: *Analyzer,
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
        return self.newExpression(.{
            .type = requirement.return_type,
            .position = call.name_position,
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

    fn staticFieldAccessExpression(
        self: *Analyzer,
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

    fn staticMethodCallExpression(
        self: *Analyzer,
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

    fn enumInitializerExpression(
        self: *Analyzer,
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

    fn matchExpression(
        self: *Analyzer,
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
                return self.fail(ast_match.subject.position, "a named noncopyable enum must be matched with 'match move' or 'match borrow'");
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
                    return self.fail(ast_binding.position, "a match binding extracted with 'borrow' is read-only and cannot use 'var'");
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
        mergeOwnerStates(tracked, owner_outcomes.items);
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

    fn superMethodCallExpression(
        self: *Analyzer,
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

    fn cascadeExpression(
        self: *Analyzer,
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

    fn requireMutableCascadeReceiver(
        self: *Analyzer,
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

    fn collectionMethodCallExpression(
        self: *Analyzer,
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
        const element_type: ?Type = switch (object.type) {
            .list => |element| element.*,
            .fixed_array => |array| array.element.*,
            .str => null,
            else => unreachable,
        };
        const allows = switch (operation) {
            .count => object.type == .str or element_type != null,
            .is_empty => element_type != null,
            .replace, .swap, .reverse => element_type != null,
            .append, .append_range, .prepend, .insert, .take, .take_first, .take_last, .clear => object.type == .list,
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
                                    .self, .static => return self.fail(argument.position, "a 'borrow' parameter cannot be stored beyond its call"),
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
                    .self, .static => return self.fail(argument.position, "a 'borrow' parameter cannot be stored beyond its call"),
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

    fn requireMutableCollectionReceiver(
        self: *Analyzer,
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

    fn resolveFunctionOverload(
        self: *Analyzer,
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

    fn resolveMethodOverload(
        self: *Analyzer,
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

    fn resolveConstructorOverload(
        self: *Analyzer,
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

    fn overloadScores(
        self: *Analyzer,
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
            const argument_mode: Ast.ParameterMode = if (argument.value == .borrow_expression)
                .borrow
            else if (argument.value == .unary and argument.value.unary.operator == .borrow)
                .mutable_reference
            else
                .value;
            if (argument_mode != parameter_mode) return null;
            const argument_value = if (argument.value == .null)
                try self.newExpression(.{ .type = .null, .position = argument.position, .value = .null })
            else if (argument_mode == .mutable_reference and argument.value.unary.operand.value == .identifier and
                findSymbol(scope, argument.value.unary.operand.value.identifier) != null and
                findSymbol(scope, argument.value.unary.operand.value.identifier).?.unwrap_optional)
                try self.newExpression(.{
                    .type = findSymbol(scope, argument.value.unary.operand.value.identifier).?.original_type.?,
                    .position = argument.position,
                    .value = .{ .variable = .{
                        .generated_name = findSymbol(scope, argument.value.unary.operand.value.identifier).?.generated_name,
                        .capture_box = &findSymbol(scope, argument.value.unary.operand.value.identifier).?.state.capture_box,
                    } },
                })
            else if (argument_mode == .mutable_reference)
                try self.expression(argument.value.unary.operand, scope)
            else if (argument_mode == .borrow)
                try self.expression(argument.value.borrow_expression.operand, scope)
            else
                try self.expressionForExpected(argument, scope, null);
            const score = self.implicitConversionScore(argument_value.type, parameter_type, argument_value.position.file) orelse literalOverloadScore(argument_value, parameter_type) orelse return null;
            try scores.append(self.allocator, score);
        }
        return @as(?[]const u8, try scores.toOwnedSlice(self.allocator));
    }

    fn noCompatibleFunctionOverload(
        self: *Analyzer,
        name: []const u8,
        position: Source.Position,
        candidates: []const FunctionSymbol,
    ) AnalyzeError {
        const signatures = try functionSignatures(self.allocator, candidates);
        const message = try std.fmt.allocPrint(self.allocator, "no compatible signature for function '{s}'; visible signatures: {s}", .{ name, signatures });
        return self.fail(position, message);
    }

    fn ambiguousFunctionOverload(
        self: *Analyzer,
        name: []const u8,
        position: Source.Position,
        candidates: []const FunctionSymbol,
    ) AnalyzeError {
        const signatures = try functionSignatures(self.allocator, candidates);
        const message = try std.fmt.allocPrint(self.allocator, "ambiguous call to function '{s}'; matching signatures: {s}", .{ name, signatures });
        return self.fail(position, message);
    }

    fn noCompatibleMethodOverload(
        self: *Analyzer,
        name: []const u8,
        position: Source.Position,
        candidates: []const MethodCandidate,
    ) AnalyzeError {
        const signatures = try methodSignatures(self.allocator, candidates);
        const message = try std.fmt.allocPrint(self.allocator, "no compatible signature for method '{s}'; visible signatures: {s}", .{ name, signatures });
        return self.fail(position, message);
    }

    fn ambiguousMethodOverload(
        self: *Analyzer,
        name: []const u8,
        position: Source.Position,
        candidates: []const MethodCandidate,
    ) AnalyzeError {
        const signatures = try methodSignatures(self.allocator, candidates);
        const message = try std.fmt.allocPrint(self.allocator, "ambiguous call to method '{s}'; matching signatures: {s}", .{ name, signatures });
        return self.fail(position, message);
    }

    fn findFunction(self: *const Analyzer, name: []const u8) ?FunctionSymbol {
        for (self.functions.items) |function_symbol| {
            if (std.mem.eql(u8, function_symbol.source_name, name)) return function_symbol;
        }
        return null;
    }

    fn isNativeModule(self: *const Analyzer, module_name: []const u8) bool {
        for (self.native_module_names) |candidate| {
            if (std.mem.eql(u8, candidate, module_name)) return true;
        }
        return false;
    }

    fn findStructure(self: *const Analyzer, name: []const u8) ?*const StructureSymbol {
        for (self.structures.items) |*structure| {
            if (std.mem.eql(u8, structure.source_name, name)) return structure;
        }
        return null;
    }

    fn findProtocol(self: *const Analyzer, name: []const u8) ?*const ProtocolSymbol {
        for (self.protocols.items) |*protocol| {
            if (std.mem.eql(u8, protocol.source_name, name)) return protocol;
        }
        return null;
    }

    fn findProtocolIndex(self: *const Analyzer, name: []const u8) ?usize {
        for (self.protocols.items, 0..) |protocol, index| {
            if (std.mem.eql(u8, protocol.source_name, name)) return index;
        }
        return null;
    }

    fn findEnum(self: *const Analyzer, name: []const u8) ?*const EnumSymbol {
        for (self.enums.items) |*enum_symbol| {
            if (std.mem.eql(u8, enum_symbol.source_name, name)) return enum_symbol;
        }
        return null;
    }

    fn findEnumByGeneratedName(self: *const Analyzer, name: []const u8) ?*const EnumSymbol {
        for (self.enums.items) |*enum_symbol| {
            if (std.mem.eql(u8, enum_symbol.generated_name, name)) return enum_symbol;
        }
        return null;
    }

    fn findEnumVariant(enum_symbol: *const EnumSymbol, name: []const u8) ?usize {
        for (enum_symbol.variants, 0..) |variant, index| {
            if (std.mem.eql(u8, variant.source_name, name)) return index;
        }
        return null;
    }

    fn findStructureIndex(self: *const Analyzer, name: []const u8) ?usize {
        for (self.structures.items, 0..) |structure, index| {
            if (std.mem.eql(u8, structure.source_name, name)) return index;
        }
        return null;
    }

    fn findStructureIndexByGeneratedName(self: *const Analyzer, name: []const u8) ?usize {
        for (self.structures.items, 0..) |structure, index| {
            if (std.mem.eql(u8, structure.generated_name, name)) return index;
        }
        return null;
    }

    fn structureType(self: *const Analyzer, structure_index: usize) StructureType {
        const structure = self.structures.items[structure_index];
        return .{
            .source_name = structure.source_name,
            .generated_name = structure.generated_name,
            .is_class = structure.is_class,
            .is_owner = structure.is_owner,
        };
    }

    fn findFieldInHierarchy(self: *const Analyzer, structure_index: usize, name: []const u8) ?FieldCandidate {
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

    fn findStaticField(self: *const Analyzer, structure_index: usize, name: []const u8) ?StructureFieldSymbol {
        for (self.structures.items[structure_index].static_fields) |field| {
            if (std.mem.eql(u8, field.source_name, name)) return field;
        }
        return null;
    }

    fn findStaticFieldByGeneratedName(self: *const Analyzer, structure_index: usize, name: []const u8) ?StructureFieldSymbol {
        for (self.structures.items[structure_index].static_fields) |field| {
            if (std.mem.eql(u8, field.generated_name, name)) return field;
        }
        return null;
    }

    fn findFieldByGeneratedName(self: *const Analyzer, structure_index: usize, name: []const u8) ?FieldCandidate {
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

    fn immutableFieldInPlace(self: *const Analyzer, expression_value: *const Expression) ?FieldCandidate {
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

    fn implicitBaseInitialization(self: *Analyzer, structure_index: usize) AnalyzeError!ImplicitBaseInitialization {
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

    fn memberVisibleFromCurrentContext(
        self: *const Analyzer,
        structure_index: usize,
        visibility: Ast.MemberVisibility,
    ) bool {
        if (self.current_extension) return visibility == .public_access;
        const current_index = self.current_structure_index orelse return visibility == .public_access;
        return self.memberVisibleFrom(current_index, structure_index, visibility);
    }

    fn memberVisibleFrom(
        self: *const Analyzer,
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

    fn isDescendantOf(self: *const Analyzer, candidate_index: usize, ancestor_index: usize) bool {
        var base_index = self.structures.items[candidate_index].base_index;
        while (base_index) |index| {
            if (index == ancestor_index) return true;
            base_index = self.structures.items[index].base_index;
        }
        return false;
    }

    fn requireFieldAccess(
        self: *Analyzer,
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

    fn uniqueOwnerStorageVisible(self: *const Analyzer, structure: *const StructureSymbol, source_file: usize) bool {
        if (self.current_extension) return false;
        if (structure.module_files.len == 0) return source_file == structure.position.file;
        return fileSetContains(structure.module_files, source_file);
    }

    fn failMemberAccess(
        self: *Analyzer,
        member_kind: []const u8,
        structure: *const StructureSymbol,
        member_name: []const u8,
        visibility: Ast.MemberVisibility,
        position: Source.Position,
    ) AnalyzeError {
        const message = switch (visibility) {
            .private_access => try std.fmt.allocPrint(
                self.allocator,
                "{s} '{s}' is private in class '{s}'",
                .{ member_kind, member_name, structure.source_name },
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

    fn structureInitializerExpression(
        self: *Analyzer,
        initializer: Ast.Expression.StructureInitializer,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const structure = self.findStructure(initializer.name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown struct '{s}'", .{initializer.name});
            return self.fail(initializer.name_position, message);
        };
        const structure_index = self.findStructureIndexByGeneratedName(structure.generated_name).?;
        if (structure.is_owner and !self.uniqueOwnerStorageVisible(structure, initializer.name_position.file)) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "initializer of unique resource struct '{s}' is private to its module",
                .{structure.source_name},
            );
            return self.fail(initializer.name_position, message);
        }
        if (structure.is_class and structure.constructors.len != 0) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "class '{s}' declares custom constructors and cannot use a named field initializer",
                .{structure.source_name},
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
            if (matching) |field| try self.rejectUniqueOwnerArgument(value, field.value.position);
            try values.append(self.allocator, value);
            lifetime_depth = @max(lifetime_depth, value.lifetime_depth);
        }
        return self.newExpression(.{
            .type = .{ .structure = self.structureType(structure_index) },
            .position = initializer.name_position,
            .lifetime_depth = lifetime_depth,
            .value = .{ .structure_initializer = .{
                .generated_name = structure.generated_name,
                .fields = try values.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn classInitializerExpression(
        self: *Analyzer,
        initializer: Ast.Expression.ClassInitializer,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const structure = self.findStructure(initializer.name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown class '{s}'", .{initializer.name});
            return self.fail(initializer.name_position, message);
        };
        if (!structure.is_class) unreachable;
        if (structure.constructors.len == 0) {
            if (initializer.arguments.len != 0) {
                const message = try std.fmt.allocPrint(self.allocator, "class '{s}' requires named fields such as 'field:value'", .{structure.source_name});
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
                .private_access => try std.fmt.allocPrint(self.allocator, "constructor of class '{s}' is private", .{structure.source_name}),
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

    fn memberAccessExpression(
        self: *Analyzer,
        member: Ast.Expression.MemberAccess,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        return self.memberAccessExpressionRaw(member, scope, true);
    }

    fn memberAccessExpressionRaw(
        self: *Analyzer,
        member: Ast.Expression.MemberAccess,
        scope: *const Scope,
        bind_function: bool,
    ) AnalyzeError!*Expression {
        const object = try self.expression(member.object, scope);
        return self.memberAccessExpressionWithObject(member, object, scope, bind_function);
    }

    fn memberAccessExpressionWithObject(
        self: *Analyzer,
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
        const generated_structure_name = switch (object.type) {
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

    fn safeMemberAccessExpression(
        self: *Analyzer,
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

    fn indexAccessExpression(
        self: *Analyzer,
        access: Ast.Expression.IndexAccess,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const object = try self.expression(access.object, scope);
        const element_type: Type = switch (object.type) {
            .list => |element| element.*,
            .fixed_array => |array| array.element.*,
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

    fn sliceAccessExpression(
        self: *Analyzer,
        access: Ast.Expression.SliceAccess,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const object = try self.expression(access.object, scope);
        const element_type: Type = switch (object.type) {
            .list => |element| element.*,
            .fixed_array => |array| array.element.*,
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
            .type = .{ .list = element },
            .position = access.bracket_position,
            .value = .{ .slice_access = .{
                .object = object,
                .start = start,
                .end = end,
            } },
        });
    }

    fn findStructureByGeneratedName(self: *const Analyzer, name: []const u8) ?*const StructureSymbol {
        for (self.structures.items) |*structure| {
            if (std.mem.eql(u8, structure.generated_name, name)) return structure;
        }
        return null;
    }

    fn validateParameterMode(
        self: *Analyzer,
        type_value: Type,
        mode: Ast.ParameterMode,
        position: Source.Position,
        is_native: bool,
    ) AnalyzeError!void {
        try self.rejectUniqueOwnerComposition(type_value, true, position);
        if (mode == .value) return;
        if (is_native and mode == .borrow) return self.fail(position, "a native function cannot declare a 'borrow' parameter");
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
                "class '{s}' already has shared identity; parameter mode 'borrow' is invalid",
                .{type_value.structure.source_name},
            );
            return self.fail(position, message);
        }
        if (type_value == .protocol and mode == .borrow) {
            return self.fail(position, "a dynamic protocol value cannot be passed with 'borrow'");
        }
        if (try self.isNonCopyableType(type_value) and mode == .mutable_reference) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "noncopyable value '{s}' cannot be passed with '&'; use 'borrow' for read-only access",
                .{typeName(type_value)},
            );
            return self.fail(position, message);
        }
    }

    fn rejectUniqueOwnerArgument(
        self: *Analyzer,
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

    fn rejectUniqueOwnerComposition(
        self: *Analyzer,
        type_value: Type,
        allow_direct_owner: bool,
        position: Source.Position,
    ) AnalyzeError!void {
        _ = self;
        _ = type_value;
        _ = allow_direct_owner;
        _ = position;
    }

    fn uniqueOwnerCause(self: *const Analyzer, type_value: Type) Allocator.Error!?StructureType {
        var visiting = std.StringHashMap(void).init(self.allocator);
        defer visiting.deinit();
        return self.uniqueOwnerCauseInner(type_value, &visiting);
    }

    fn isNonCopyableType(self: *const Analyzer, type_value: Type) Allocator.Error!bool {
        return (try self.uniqueOwnerCause(type_value)) != null;
    }

    fn isNonCopyableTemporary(self: *const Analyzer, expression_value: *const Expression) bool {
        return switch (expression_value.value) {
            .move_expression,
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

    fn uniqueOwnerCauseInner(
        self: *const Analyzer,
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

    fn isEqualityComparable(self: *const Analyzer, type_value: Type) bool {
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

    fn requireIndependentLetType(
        self: *Analyzer,
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

    fn nonIndependentType(
        self: *const Analyzer,
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

    fn inferMethodMutability(self: *Analyzer) void {
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
    }

    fn methodSymbol(self: *const Analyzer, id: MethodId) *const MethodSymbol {
        return &self.structures.items[id.structure_index].methods[id.method_index];
    }

    fn validateMethodCalls(self: *Analyzer, program: Program) AnalyzeError!void {
        for (program.structures) |structure| {
            for (structure.constructors) |constructor_value| try self.validateStatements(constructor_value.statements);
            if (structure.drop) |drop| try self.validateStatements(drop.statements);
            for (structure.methods) |method_value| try self.validateStatements(method_value.statements);
        }
        for (program.functions) |function_value| try self.validateStatements(function_value.statements);
    }

    fn validateStatements(self: *Analyzer, statements_value: []const Statement) AnalyzeError!void {
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

    fn validateCondition(self: *Analyzer, condition_value: Statement.Condition) AnalyzeError!void {
        switch (condition_value) {
            .expression => |value| try self.validateExpression(value),
            .binding => |binding| try self.validateExpression(binding.source),
        }
    }

    fn validateExpression(self: *Analyzer, expression_value: *const Expression) AnalyzeError!void {
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
                if (!self.methodSymbol(call.method_id).is_mutating) return;
                switch (call.receiver) {
                    .self, .mutable, .cascade_temporary => {},
                    .borrowed_self => return self.fail(call.position, "cannot mutate 'self' while one of its collections is iterated"),
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
                    .borrowed => |name| {
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

    fn unaryExpression(
        self: *Analyzer,
        unary: Ast.Expression.Unary,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        if (unary.operator == .borrow) {
            return self.fail(unary.operator_position, "'&' is only valid for an argument of a parameter declared with '&'");
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

    fn moveExpression(
        self: *Analyzer,
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
            return self.fail(move_value.operator_position, "a 'borrow' parameter cannot be consumed with 'move'");
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
        return self.newExpression(.{
            .type = symbol.type,
            .position = move_value.operator_position,
            .value = .{ .move_expression = .{ .operand = operand } },
        });
    }

    const ResultShape = struct {
        enum_symbol: *const EnumSymbol,
        success_type: Type,
        error_type: Type,
        failure_variant_index: usize,
    };

    fn resultShape(self: *const Analyzer, value: Type) ?ResultShape {
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

    fn tryExpression(
        self: *Analyzer,
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

    fn argumentForMode(
        self: *Analyzer,
        argument: *const Ast.Expression,
        scope: *const Scope,
        expected_type: Type,
        mode: Ast.ParameterMode,
    ) AnalyzeError!*Expression {
        return switch (mode) {
            .value => self.expressionForExpected(argument, scope, expected_type),
            .mutable_reference => self.mutableReferenceArgument(argument, scope, expected_type),
            .borrow => self.readBorrowArgument(argument, scope, expected_type),
        };
    }

    fn readBorrowArgument(
        self: *Analyzer,
        argument: *const Ast.Expression,
        scope: *const Scope,
        expected_type: Type,
    ) AnalyzeError!*Expression {
        if (argument.value != .borrow_expression) {
            return self.fail(argument.position, "a parameter declared with 'borrow' requires an argument written as 'borrow value'");
        }
        return self.readBorrowValue(argument.value.borrow_expression, scope, expected_type);
    }

    fn readBorrowValue(
        self: *Analyzer,
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
        var operand = try self.expressionForExpected(borrow_value.operand, scope, expected_type);
        if (expected_type) |expected| {
            operand = try self.coerce(operand, expected);
            if (!typeEqual(operand.type, expected)) return operand;
        }
        const borrow = Borrow{ .root = root, .mutable = false };
        if (root) |state| state.immutable_borrows += 1;
        return self.newExpression(.{
            .type = operand.type,
            .position = borrow_value.operator_position,
            .borrow = borrow,
            .owns_borrow = true,
            .borrowed_parameter = operand.borrowed_parameter,
            .value = .{ .borrow_expression = .{ .operand = operand } },
        });
    }

    fn mutableReferenceArgument(
        self: *Analyzer,
        argument: *const Ast.Expression,
        scope: *const Scope,
        expected_type: Type,
    ) AnalyzeError!*Expression {
        if (argument.value != .unary or argument.value.unary.operator != .borrow) {
            return self.fail(argument.position, "a parameter declared with '&' requires an argument written as '&place'");
        }
        const unary = argument.value.unary;
        const root = assignmentRoot(unary.operand) orelse {
            return self.fail(unary.operator_position, "'&' requires a variable, field, or collection element");
        };
        var root_state: ?*BindingState = null;
        switch (root) {
            .static => {},
            .self => {
                if (self.current_method_index == null and !self.current_constructor and !self.current_drop) return self.fail(unary.operator_position, "'self' is only available inside a method, constructor, or drop block");
                root_state = &self.current_self_state;
                self.current_method_direct_mutation = true;
            },
            .variable => |name| {
                const symbol = findSymbol(scope, name) orelse {
                    const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
                    return self.fail(unary.operator_position, message);
                };
                if (symbol.mutability != .mutable) {
                    const message = if (symbol.control_binding)
                        try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{name})
                    else
                        try std.fmt.allocPrint(self.allocator, "cannot pass immutable variable '{s}' with '&'", .{name});
                    return self.fail(unary.operator_position, message);
                }
                root_state = symbol.state;
            },
        }
        if (root_state) |state| {
            if (state.immutable_borrows != 0) {
                return self.fail(unary.operator_position, "cannot pass a value with '&' while it is read-borrowed");
            }
        }
        const operand = if (unary.operand.value == .identifier and findSymbol(scope, unary.operand.value.identifier) != null and
            findSymbol(scope, unary.operand.value.identifier).?.unwrap_optional)
        narrowed_operand: {
            const symbol = findSymbol(scope, unary.operand.value.identifier).?;
            try self.recordSymbolCapture(symbol, unary.operand.position);
            symbol.state.narrowed_valid = false;
            break :narrowed_operand try self.newExpression(.{
                .type = symbol.original_type.?,
                .position = unary.operand.position,
                .value = .{ .variable = .{ .generated_name = symbol.generated_name, .capture_box = &symbol.state.capture_box } },
            });
        } else try self.expression(unary.operand, scope);
        if (operand.value == .enum_raw_value) return self.fail(unary.operator_position, "enum property 'raw_value' cannot be passed with '&'");
        if (self.immutableFieldInPlace(operand)) |field_candidate| {
            const message = try std.fmt.allocPrint(self.allocator, "cannot pass let field '{s}' with '&'", .{field_candidate.symbol.source_name});
            return self.fail(unary.operator_position, message);
        }
        if (!typeEqual(operand.type, expected_type)) return operand;
        const borrow = Borrow{ .root = root_state, .mutable = true, .transient = true };
        if (root_state) |state| state.transient_mutable_borrows += 1;
        return self.newExpression(.{
            .type = operand.type,
            .position = unary.operator_position,
            .borrow = borrow,
            .owns_borrow = true,
            .value = .{ .unary = .{ .operator = .borrow, .operand = operand } },
        });
    }

    fn borrowExpression(
        self: *Analyzer,
        unary: Ast.Expression.Unary,
        scope: *const Scope,
        mutable: bool,
    ) AnalyzeError!*Expression {
        const symbol = try self.placeRootSymbol(unary.operand, scope, unary.operator_position);
        if (mutable) {
            if (symbol.mutability != .mutable) {
                const message = if (symbol.control_binding)
                    try std.fmt.allocPrint(self.allocator, "cannot mutate immutable control binding '{s}'; use 'var' in the header", .{symbol.source_name})
                else
                    try std.fmt.allocPrint(self.allocator, "cannot mutably borrow immutable variable '{s}'", .{symbol.source_name});
                return self.fail(unary.operator_position, message);
            }
            if (symbol.state.mutable_borrow or symbol.state.immutable_borrows != 0) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutably borrow '{s}' because it is already borrowed", .{symbol.source_name});
                return self.fail(unary.operator_position, message);
            }
        } else if (symbol.state.mutable_borrow) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot immutably borrow '{s}' while it is mutably borrowed", .{symbol.source_name});
            return self.fail(unary.operator_position, message);
        }
        const operand = try self.expression(unary.operand, scope);
        if (mutable) if (self.immutableFieldInPlace(operand)) |field_candidate| {
            const message = try std.fmt.allocPrint(self.allocator, "cannot mutably borrow let field '{s}'", .{field_candidate.symbol.source_name});
            return self.fail(unary.operator_position, message);
        };
        const target = try self.allocator.create(Type);
        target.* = operand.type;
        const borrow = Borrow{ .root = symbol.state, .mutable = mutable };
        if (mutable) symbol.state.mutable_borrow = true else symbol.state.immutable_borrows += 1;
        return self.newExpression(.{
            .type = .{ .reference = .{ .target = target, .mutable = mutable } },
            .position = unary.operator_position,
            .borrow = borrow,
            .owns_borrow = true,
            .value = .{ .unary = .{ .operator = unary.operator, .operand = operand } },
        });
    }

    fn appendLiteralExpectedType(
        self: *Analyzer,
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

    fn requireBinaryOperands(
        self: *Analyzer,
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

    fn requireNumericOperands(
        self: *Analyzer,
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

    fn coerce(self: *Analyzer, expression_value: *Expression, target_type: Type) AnalyzeError!*Expression {
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

    fn classUpcastDistance(self: *const Analyzer, source: Type, target: Type) ?u8 {
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

    fn implicitConversionScore(self: *const Analyzer, source: Type, target: Type, source_file: usize) ?u8 {
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

    fn optionalType(self: *Analyzer, contained_type: Type) Allocator.Error!Type {
        const contained = try self.allocator.create(Type);
        contained.* = contained_type;
        return .{ .optional = contained };
    }

    fn newExpression(self: *Analyzer, value: Expression) !*Expression {
        const result = try self.allocator.create(Expression);
        result.* = value;
        return result;
    }

    fn recordLambdaCapture(
        self: *Analyzer,
        lambda: *LambdaContext,
        generated_name: []const u8,
        by_value: bool,
    ) !void {
        for (lambda.captures.items) |capture| {
            if (std.mem.eql(u8, capture.generated_name, generated_name)) return;
        }
        try lambda.captures.append(self.allocator, .{ .generated_name = generated_name, .by_value = by_value });
    }

    fn recordSymbolCapture(self: *Analyzer, symbol: *const Symbol, position: Source.Position) !void {
        var lambda_context = self.current_lambda;
        while (lambda_context) |lambda| : (lambda_context = lambda.parent) {
            if (symbol.scope_depth < lambda.local_depth) {
                if (symbol.state.borrowed_parameter) {
                    return self.fail(position, "a 'borrow' parameter cannot be captured by a lambda");
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

    fn typeContainsClass(self: *const Analyzer, type_value: Type) Allocator.Error!bool {
        var visiting = std.StringHashMap(void).init(self.allocator);
        defer visiting.deinit();
        return self.typeContainsClassInner(type_value, &visiting);
    }

    fn typeContainsClassInner(
        self: *const Analyzer,
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

    fn newBindingState(self: *Analyzer, type_value: Type) !*BindingState {
        const state = try self.allocator.create(BindingState);
        state.* = .{};
        if (type_value == .reference) {
            state.reference = .{ .root = null, .mutable = type_value.reference.mutable };
        }
        return state;
    }

    fn copyBorrow(self: *Analyzer, borrow: Borrow) !Borrow {
        _ = self;
        if (borrow.mutable) return error.InvalidSource;
        if (borrow.root) |root| root.immutable_borrows += 1;
        return borrow;
    }

    fn releaseTransientBorrow(_: *Analyzer, expression_value: *Expression) void {
        if (expression_value.owns_borrow) {
            releaseBorrow(expression_value.borrow.?);
            expression_value.owns_borrow = false;
        }
    }

    fn retainTransientBorrow(self: *Analyzer, borrows: *std.ArrayList(Borrow), expression_value: *Expression) !void {
        if (!expression_value.owns_borrow) return;
        try borrows.append(self.allocator, expression_value.borrow.?);
        expression_value.owns_borrow = false;
    }

    fn releaseScopeBorrows(_: *Analyzer, scope: *Scope) void {
        for (scope.borrows.items) |borrow| releaseBorrow(borrow);
    }

    fn placeRootSymbol(
        self: *Analyzer,
        ast_expression: *const Ast.Expression,
        scope: *const Scope,
        position: Source.Position,
    ) AnalyzeError!*const Symbol {
        const name = switch (ast_expression.value) {
            .identifier => |value| value,
            .member_access => |member| return self.placeRootSymbol(member.object, scope, position),
            .index_access => |access| return self.placeRootSymbol(access.object, scope, position),
            else => return self.fail(position, "a reference must borrow a variable, field, or collection element"),
        };
        const symbol = findSymbol(scope, name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
            return self.fail(position, message);
        };
        return symbol;
    }

    fn fail(self: *Analyzer, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn allFieldsInitialized(initialized: []const FieldInitialization) bool {
    for (initialized) |field_initialized| if (field_initialized != .initialized) return false;
    return true;
}

fn generatedFieldIndex(structure: *const StructureSymbol, generated_name: []const u8) ?usize {
    for (structure.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.generated_name, generated_name)) return index;
    }
    return null;
}

fn directSelfFieldIndex(structure: *const StructureSymbol, target: *const Expression) ?usize {
    if (target.value != .member_access) return null;
    const member = target.value.member_access;
    if (member.object.value != .self) return null;
    return generatedFieldIndex(structure, member.generated_name);
}

fn mutationReachesClassIdentity(target: *const Expression) bool {
    return switch (target.value) {
        .member_access => |member| (member.object.type == .structure and member.object.type.structure.is_class) or
            mutationReachesClassIdentity(member.object),
        .index_access => |access| mutationReachesClassIdentity(access.object),
        else => false,
    };
}

fn findInCurrentScope(scope: *const Scope, name: []const u8) ?*const Symbol {
    for (scope.symbols.items) |*symbol| {
        if (std.mem.eql(u8, symbol.source_name, name)) return symbol;
    }
    return null;
}

fn findSymbol(scope: *const Scope, name: []const u8) ?*const Symbol {
    var current: ?*const Scope = scope;
    while (current) |value| : (current = value.parent) {
        if (findInCurrentScope(value, name)) |symbol| return symbol;
    }
    return null;
}

fn typeFromAnnotation(
    self: *Analyzer,
    annotation: Ast.TypeName,
    position: Source.Position,
) AnalyzeError!Type {
    return switch (annotation) {
        .void => .void,
        .int => .int,
        .int8 => .int8,
        .int16 => .int16,
        .int32 => .int32,
        .int64 => .int,
        .uint => .uint64,
        .uint8 => .uint8,
        .uint16 => .uint16,
        .uint32 => .uint32,
        .uint64 => .uint64,
        .float => .float,
        .float32 => .float,
        .float64 => .float64,
        .bool => .bool,
        .str => .str,
        .list => |element_annotation| list_type: {
            const element = try self.allocator.create(Type);
            element.* = try typeFromAnnotation(self, element_annotation.*, position);
            if (element.* == .void or element.* == .reference) return self.fail(position, "a collection element cannot have this type");
            break :list_type .{ .list = element };
        },
        .fixed_array => |array_annotation| fixed_array_type: {
            const element = try self.allocator.create(Type);
            element.* = try typeFromAnnotation(self, array_annotation.element.*, position);
            if (element.* == .void or element.* == .reference) return self.fail(position, "a collection element cannot have this type");
            const length = try parseFixedArrayLength(self, array_annotation.length, position);
            break :fixed_array_type .{ .fixed_array = .{ .element = element, .length = length } };
        },
        .reference => |reference| try typeFromReference(self, reference, position),
        .function => |function| try typeFromFunction(self, function, position),
        .optional => |contained_annotation| optional_type: {
            const contained = try self.allocator.create(Type);
            contained.* = try typeFromAnnotation(self, contained_annotation.*, position);
            if (contained.* == .void or contained.* == .optional or contained.* == .null) {
                return self.fail(position, "an optional type requires a non-optional, non-void contained type");
            }
            break :optional_type .{ .optional = contained };
        },
        .structure => |name| structure_type: {
            if (self.findProtocolIndex(name)) |protocol_index| {
                const protocol = self.protocols.items[protocol_index];
                break :structure_type .{ .protocol = .{
                    .source_name = protocol.source_name,
                    .generated_name = protocol.generated_name,
                    .index = protocol_index,
                } };
            }
            if (self.findStructure(name)) |structure| {
                const structure_index = self.findStructureIndexByGeneratedName(structure.generated_name).?;
                break :structure_type .{ .structure = self.structureType(structure_index) };
            }
            if (self.findEnum(name)) |enum_symbol| {
                break :structure_type .{ .enumeration = .{
                    .source_name = enum_symbol.source_name,
                    .generated_name = enum_symbol.generated_name,
                } };
            }
            const message = try std.fmt.allocPrint(self.allocator, "unknown type '{s}'", .{name});
            return self.fail(position, message);
        },
        .generic_structure => return self.fail(position, "generic structure type was not specialized before semantic analysis"),
        .type_parameter => return self.fail(position, "generic type parameter was not substituted before semantic analysis"),
    };
}

fn typeFromReturn(
    self: *Analyzer,
    return_type: Ast.ReturnType,
    position: Source.Position,
) AnalyzeError!Type {
    return switch (return_type) {
        .void => .void,
        .int => .int,
        .int8 => .int8,
        .int16 => .int16,
        .int32 => .int32,
        .int64 => .int,
        .uint => .uint64,
        .uint8 => .uint8,
        .uint16 => .uint16,
        .uint32 => .uint32,
        .uint64 => .uint64,
        .float => .float,
        .float32 => .float,
        .float64 => .float64,
        .bool => .bool,
        .str => .str,
        .list => |element| typeFromAnnotation(self, .{ .list = element }, position),
        .fixed_array => |array| typeFromAnnotation(self, .{ .fixed_array = array }, position),
        .structure => |name| typeFromAnnotation(self, .{ .structure = name }, position),
        .generic_structure => |generic| typeFromAnnotation(self, .{ .generic_structure = generic }, position),
        .type_parameter => |name| typeFromAnnotation(self, .{ .type_parameter = name }, position),
        .reference => |reference| typeFromReference(self, reference, position),
        .function => |function| typeFromFunction(self, function, position),
        .optional => |contained| typeFromAnnotation(self, .{ .optional = contained }, position),
    };
}

fn typeFromFunction(
    self: *Analyzer,
    function: Ast.TypeName.FunctionType,
    position: Source.Position,
) AnalyzeError!Type {
    var parameters: std.ArrayList(Type) = .empty;
    for (function.parameters, function.parameter_modes) |parameter, mode| {
        const parameter_type = try typeFromAnnotation(self, parameter, position);
        if (parameter_type == .void or parameter_type == .reference) {
            return self.fail(position, "a function value parameter cannot have this type");
        }
        try self.validateParameterMode(parameter_type, mode, position, false);
        try parameters.append(self.allocator, parameter_type);
    }
    const return_type = try self.allocator.create(Type);
    return_type.* = if (function.return_type) |return_annotation|
        try typeFromAnnotation(self, return_annotation.*, position)
    else
        .void;
    if (return_type.* == .reference) return self.fail(position, "a function value cannot return a reference");
    return .{ .function = .{
        .parameters = try parameters.toOwnedSlice(self.allocator),
        .parameter_modes = try self.allocator.dupe(Ast.ParameterMode, function.parameter_modes),
        .return_type = return_type,
    } };
}

fn typeFromReference(
    self: *Analyzer,
    reference: Ast.TypeName.Reference,
    position: Source.Position,
) AnalyzeError!Type {
    const target = try self.allocator.create(Type);
    target.* = try typeFromAnnotation(self, reference.target.*, position);
    if (target.* == .reference) return self.fail(position, "a reference cannot target another reference");
    if (target.* == .structure and target.*.structure.is_class) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "class '{s}' already has reference semantics; '&{s}' is invalid",
            .{ target.*.structure.source_name, target.*.structure.source_name },
        );
        return self.fail(position, message);
    }
    return .{ .reference = .{ .target = target, .mutable = reference.mutable } };
}

fn parseFixedArrayLength(self: *Analyzer, lexeme: []const u8, position: Source.Position) AnalyzeError!usize {
    const normalized = try normalizeNumericLiteral(self.allocator, lexeme);
    const base: u8 = if (normalized.len > 2 and normalized[0] == '0') switch (normalized[1]) {
        'b', 'B' => 2,
        'o', 'O' => 8,
        'x', 'X' => 16,
        else => 10,
    } else 10;
    const digits = if (base == 10) normalized else normalized[2..];
    return std.fmt.parseInt(usize, digits, base) catch self.fail(position, "array length is outside the supported range");
}

fn blockAlwaysReturns(statements: []const Statement) bool {
    for (statements) |statement| {
        switch (statement) {
            .return_statement, .panic_statement => return true,
            .if_statement => |if_statement| {
                if (if_statement.else_body) |else_body| {
                    var all_branches_return = blockAlwaysReturns(if_statement.body);
                    for (if_statement.alternatives) |alternative| {
                        all_branches_return = all_branches_return and blockAlwaysReturns(alternative.body);
                    }
                    if (all_branches_return and blockAlwaysReturns(else_body)) return true;
                }
            },
            .expression_statement => |expression_value| if (expression_value.value == .match_expression) {
                var all_branches_return = true;
                for (expression_value.value.match_expression.branches) |branch| switch (branch.body) {
                    .expression => all_branches_return = false,
                    .statements => |branch_statements| all_branches_return = all_branches_return and blockAlwaysReturns(branch_statements),
                };
                if (all_branches_return) return true;
            },
            else => {},
        }
    }
    return false;
}

fn astStatementsFallThrough(statements: []const Ast.Statement) bool {
    for (statements) |statement_value| {
        if (!astStatementFallsThrough(statement_value)) return false;
    }
    return true;
}

fn astStatementFallsThrough(statement_value: Ast.Statement) bool {
    return switch (statement_value) {
        .panic_statement, .break_statement, .continue_statement, .return_statement => false,
        .if_statement => |if_value| if_falls_through: {
            const else_body = if_value.else_body orelse break :if_falls_through true;
            if (astStatementsFallThrough(if_value.body)) break :if_falls_through true;
            for (if_value.alternatives) |alternative| {
                if (astStatementsFallThrough(alternative.body)) break :if_falls_through true;
            }
            break :if_falls_through astStatementsFallThrough(else_body);
        },
        .expression_statement => |expression_value| match_falls_through: {
            if (expression_value.value != .match_expression) break :match_falls_through true;
            for (expression_value.value.match_expression.branches) |branch| switch (branch.body) {
                .expression => break :match_falls_through true,
                .statements => |branch_statements| if (astStatementsFallThrough(branch_statements)) break :match_falls_through true,
            };
            break :match_falls_through false;
        },
        else => true,
    };
}

fn parameterStored(statements: []const Ast.Statement, name: []const u8) bool {
    for (statements) |statement_value| switch (statement_value) {
        .assignment => |assignment_value| {
            if (assignment_value.value) |value| {
                if (assignmentRoot(assignment_value.target)) |root| switch (root) {
                    .self => if (astExpressionUsesIdentifier(value, name)) return true,
                    .variable, .static => {},
                };
            }
        },
        .return_statement => |return_value| {
            if (return_value.value) |value| if (astExpressionUsesIdentifier(value, name)) return true;
        },
        .if_statement => |if_value| {
            if (parameterStored(if_value.body, name)) return true;
            for (if_value.alternatives) |alternative| {
                if (parameterStored(alternative.body, name)) return true;
            }
            if (if_value.else_body) |else_body| if (parameterStored(else_body, name)) return true;
        },
        .while_statement => |while_value| if (parameterStored(while_value.body, name)) return true,
        .for_statement => |for_value| if (parameterStored(for_value.body, name)) return true,
        .expression_statement => |expression_value| {
            if (astCollectionCallStoresIdentifier(expression_value, name)) return true;
            if (expression_value.value == .match_expression) {
                for (expression_value.value.match_expression.branches) |branch| switch (branch.body) {
                    .expression => {},
                    .statements => |branch_statements| if (parameterStored(branch_statements, name)) return true,
                };
            }
        },
        else => {},
    };
    return false;
}

fn astCollectionCallStoresIdentifier(expression_value: *const Ast.Expression, name: []const u8) bool {
    if (expression_value.value != .method_call) return false;
    const call = expression_value.value.method_call;
    const root = assignmentRoot(call.object) orelse return false;
    if (root != .self) return false;
    const argument_index: usize = if (std.mem.eql(u8, call.name, "append") or std.mem.eql(u8, call.name, "prepend"))
        0
    else if (std.mem.eql(u8, call.name, "insert") or std.mem.eql(u8, call.name, "replace"))
        1
    else
        return false;
    if (argument_index >= call.arguments.len) return false;
    return astExpressionUsesIdentifier(call.arguments[argument_index], name);
}

fn astExpressionUsesIdentifier(expression_value: *const Ast.Expression, name: []const u8) bool {
    return switch (expression_value.value) {
        .identifier => |candidate| std.mem.eql(u8, candidate, name),
        .sequence_literal => |values| uses: {
            for (values) |value| if (astExpressionUsesIdentifier(value, name)) break :uses true;
            break :uses false;
        },
        .value_call => |call| uses: {
            if (astExpressionUsesIdentifier(call.callee, name)) break :uses true;
            for (call.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .call => |call| uses: {
            for (call.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .method_call => |call| uses: {
            if (astExpressionUsesIdentifier(call.object, name)) break :uses true;
            for (call.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .static_method_call => |call| uses: {
            for (call.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .super_method_call => |call| uses: {
            for (call.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .member_access => |member| astExpressionUsesIdentifier(member.object, name),
        .index_access => |access| astExpressionUsesIdentifier(access.object, name) or astExpressionUsesIdentifier(access.index, name),
        .slice_access => |access| astExpressionUsesIdentifier(access.object, name) or astExpressionUsesIdentifier(access.start, name) or astExpressionUsesIdentifier(access.end, name),
        .try_expression => |try_value| astExpressionUsesIdentifier(try_value.operand, name),
        .unary => |unary| astExpressionUsesIdentifier(unary.operand, name),
        .conversion => |conversion| astExpressionUsesIdentifier(conversion.operand, name),
        .binary => |binary| astExpressionUsesIdentifier(binary.left, name) or astExpressionUsesIdentifier(binary.right, name),
        .structure_initializer => |initializer| uses: {
            for (initializer.fields) |field| if (astExpressionUsesIdentifier(field.value, name)) break :uses true;
            break :uses false;
        },
        .class_initializer => |initializer| uses: {
            for (initializer.arguments) |argument| if (astExpressionUsesIdentifier(argument, name)) break :uses true;
            break :uses false;
        },
        .cascade => |cascade| astExpressionUsesIdentifier(cascade.object, name),
        .match_expression => |match_value| uses: {
            if (astExpressionUsesIdentifier(match_value.subject, name)) break :uses true;
            for (match_value.branches) |branch| switch (branch.body) {
                .expression => |value| if (astExpressionUsesIdentifier(value, name)) break :uses true,
                .statements => {},
            };
            break :uses false;
        },
        .lambda => false,
        else => false,
    };
}

fn typeMismatchMessage(allocator: Allocator, expected: Type, found: Type) ![]const u8 {
    const expected_name = try allocatedTypeName(allocator, expected);
    const found_name = try allocatedTypeName(allocator, found);
    return std.fmt.allocPrint(
        allocator,
        "expected '{s}', found '{s}'",
        .{ expected_name, found_name },
    );
}

fn referenceMutability(type_value: ?Type) ?bool {
    const value = type_value orelse return null;
    return switch (value) {
        .reference => |reference| reference.mutable,
        else => null,
    };
}

fn normalizeNumericLiteral(allocator: Allocator, lexeme: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, lexeme, '_') == null) return lexeme;
    var normalized: std.ArrayList(u8) = .empty;
    for (lexeme) |character| if (character != '_') try normalized.append(allocator, character);
    return normalized.toOwnedSlice(allocator);
}

fn hexDigit(character: u8) ?u21 {
    if (std.ascii.isDigit(character)) return character - '0';
    if (character >= 'a' and character <= 'f') return character - 'a' + 10;
    if (character >= 'A' and character <= 'F') return character - 'A' + 10;
    return null;
}

fn appendUnicodeScalar(allocator: Allocator, output: *std.ArrayList(u8), scalar: u21) !void {
    if (scalar <= 0x7F) {
        try output.append(allocator, @intCast(scalar));
    } else if (scalar <= 0x7FF) {
        try output.append(allocator, @intCast(0xC0 | (scalar >> 6)));
        try output.append(allocator, @intCast(0x80 | (scalar & 0x3F)));
    } else if (scalar <= 0xFFFF) {
        try output.append(allocator, @intCast(0xE0 | (scalar >> 12)));
        try output.append(allocator, @intCast(0x80 | ((scalar >> 6) & 0x3F)));
        try output.append(allocator, @intCast(0x80 | (scalar & 0x3F)));
    } else {
        try output.append(allocator, @intCast(0xF0 | (scalar >> 18)));
        try output.append(allocator, @intCast(0x80 | ((scalar >> 12) & 0x3F)));
        try output.append(allocator, @intCast(0x80 | ((scalar >> 6) & 0x3F)));
        try output.append(allocator, @intCast(0x80 | (scalar & 0x3F)));
    }
}

fn isUniqueOwnerType(type_value: Type) bool {
    return type_value == .structure and type_value.structure.is_owner;
}

fn typeEqual(left: Type, right: Type) bool {
    return switch (left) {
        .void => right == .void,
        .int => right == .int,
        .int8 => right == .int8,
        .int16 => right == .int16,
        .int32 => right == .int32,
        .uint8 => right == .uint8,
        .uint16 => right == .uint16,
        .uint32 => right == .uint32,
        .uint64 => right == .uint64,
        .float => right == .float,
        .float64 => right == .float64,
        .bool => right == .bool,
        .str => right == .str,
        .list => |left_element| switch (right) {
            .list => |right_element| typeEqual(left_element.*, right_element.*),
            else => false,
        },
        .fixed_array => |left_array| switch (right) {
            .fixed_array => |right_array| left_array.length == right_array.length and typeEqual(left_array.element.*, right_array.element.*),
            else => false,
        },
        .reference => |left_reference| switch (right) {
            .reference => |right_reference| left_reference.mutable == right_reference.mutable and typeEqual(left_reference.target.*, right_reference.target.*),
            else => false,
        },
        .function => |left_function| switch (right) {
            .function => |right_function| function_type: {
                if (left_function.parameters.len != right_function.parameters.len) break :function_type false;
                if (!typeEqual(left_function.return_type.*, right_function.return_type.*)) break :function_type false;
                for (left_function.parameters, left_function.parameter_modes, right_function.parameters, right_function.parameter_modes) |left_parameter, left_mode, right_parameter, right_mode| {
                    if (left_mode != right_mode or !typeEqual(left_parameter, right_parameter)) break :function_type false;
                }
                break :function_type true;
            },
            else => false,
        },
        .structure => |left_structure| switch (right) {
            .structure => |right_structure| std.mem.eql(u8, left_structure.generated_name, right_structure.generated_name),
            else => false,
        },
        .protocol => |left_protocol| switch (right) {
            .protocol => |right_protocol| left_protocol.index == right_protocol.index,
            else => false,
        },
        .enumeration => |left_enum| switch (right) {
            .enumeration => |right_enum| std.mem.eql(u8, left_enum.generated_name, right_enum.generated_name),
            else => false,
        },
        .optional => |left_contained| switch (right) {
            .optional => |right_contained| typeEqual(left_contained.*, right_contained.*),
            else => false,
        },
        .null => right == .null,
    };
}

fn rawEnumValuesEqual(left: *const Expression, right: *const Expression) bool {
    if (left.value == .string and right.value == .string) {
        return std.mem.eql(u8, left.value.string, right.value.string);
    }
    const left_integer = rawEnumInteger(left) orelse return false;
    const right_integer = rawEnumInteger(right) orelse return false;
    return left_integer.magnitude == right_integer.magnitude and
        (left_integer.magnitude == 0 or left_integer.negative == right_integer.negative);
}

fn rawEnumInteger(value: *const Expression) ?struct { magnitude: u64, negative: bool } {
    if (value.value == .integer) return .{ .magnitude = value.value.integer, .negative = false };
    if (value.value == .unary and value.value.unary.operator == .numeric_negate and value.value.unary.operand.value == .integer) {
        return .{ .magnitude = value.value.unary.operand.value.integer, .negative = true };
    }
    return null;
}

fn sameSignature(
    left_types: []const Type,
    left_modes: []const Ast.ParameterMode,
    right_types: []const Type,
    right_modes: []const Ast.ParameterMode,
) bool {
    if (left_types.len != right_types.len) return false;
    for (left_types, left_modes, right_types, right_modes) |left_type, left_mode, right_type, right_mode| {
        if (left_mode != right_mode or !typeEqual(left_type, right_type)) return false;
    }
    return true;
}

fn containsPosition(positions: []const Source.Position, candidate: Source.Position) bool {
    for (positions) |position| {
        if (position.file == candidate.file and position.line == candidate.line and position.column == candidate.column) return true;
    }
    return false;
}

fn overloadScore(source: Type, target: Type) ?u8 {
    if (typeEqual(source, target)) return 0;
    if (target == .optional) {
        if (source == .null) return 3;
        if (source == .optional) {
            const score = overloadScore(source.optional.*, target.optional.*) orelse return null;
            return score;
        }
        const score = overloadScore(source, target.optional.*) orelse return null;
        return score + 3;
    }
    if (isInteger(source) and isInteger(target) and
        isUnsignedInteger(source) == isUnsignedInteger(target) and integerBits(source) < integerBits(target))
    {
        return 1;
    }
    if (source == .float and target == .float64) return 1;
    if (isInteger(source) and (target == .float or target == .float64)) return 2;
    return null;
}

fn literalOverloadScore(value: *const Expression, target: Type) ?u8 {
    if (target == .optional) {
        const score = literalOverloadScore(value, target.optional.*) orelse return null;
        return score + 3;
    }
    if (value.value == .integer and isInteger(target) and integerLiteralFits(value.value.integer, target)) return 1;
    if (value.value == .floating and target == .float64) return 1;
    return null;
}

fn overloadBetter(left: []const u8, right: []const u8) bool {
    var strictly_better = false;
    for (left, right) |left_score, right_score| {
        if (left_score > right_score) return false;
        if (left_score < right_score) strictly_better = true;
    }
    return strictly_better;
}

fn appendSignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    name: []const u8,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
) !void {
    try output.appendSlice(allocator, name);
    try output.append(allocator, '(');
    for (parameter_types, parameter_modes, 0..) |parameter_type, mode, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        if (mode == .borrow) try output.appendSlice(allocator, "borrow ");
        if (mode == .mutable_reference) try output.append(allocator, '&');
        try output.appendSlice(allocator, try allocatedSignatureTypeName(allocator, parameter_type));
    }
    try output.append(allocator, ')');
}

fn functionSignatures(allocator: Allocator, candidates: []const FunctionSymbol) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    for (candidates, 0..) |candidate, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendSignature(allocator, &output, lastNameSegment(candidate.source_name), candidate.parameter_types, candidate.parameter_modes);
    }
    return output.toOwnedSlice(allocator);
}

fn methodSignatures(allocator: Allocator, candidates: []const MethodCandidate) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    for (candidates, 0..) |candidate, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendSignature(allocator, &output, candidate.symbol.source_name, candidate.symbol.parameter_types, candidate.symbol.parameter_modes);
    }
    return output.toOwnedSlice(allocator);
}

fn constructorSignatures(
    allocator: Allocator,
    class_name: []const u8,
    candidates: []const ConstructorCandidate,
) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    for (candidates, 0..) |candidate, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendSignature(allocator, &output, lastNameSegment(class_name), candidate.symbol.parameter_types, candidate.symbol.parameter_modes);
    }
    return output.toOwnedSlice(allocator);
}

fn isNativeReturnType(value: Type) bool {
    return switch (value) {
        .void, .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool => true,
        .str, .structure, .protocol, .enumeration, .list, .fixed_array, .reference, .function, .optional, .null => false,
    };
}

fn isNativeParameterType(value: Type) bool {
    return value == .str or isNativeReturnType(value);
}

fn moduleName(function_name: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, function_name, '.') orelse return null;
    return function_name[0..separator];
}

fn lastNameSegment(function_name: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, function_name, '.') orelse return function_name;
    return function_name[separator + 1 ..];
}

fn nativeSymbol(allocator: Allocator, function_name: []const u8) Allocator.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, "silexNative_");
    for (function_name) |character| {
        try result.append(allocator, if (character == '.') '_' else character);
    }
    return result.toOwnedSlice(allocator);
}

fn typeName(value: Type) []const u8 {
    return switch (value) {
        .void => "void",
        .int => "int",
        .int8 => "int8",
        .int16 => "int16",
        .int32 => "int32",
        .uint8 => "uint8",
        .uint16 => "uint16",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .float => "float",
        .float64 => "float64",
        .bool => "bool",
        .str => "str",
        .list => "list",
        .fixed_array => "array",
        .reference => |reference| if (reference.mutable) "reference&" else "reference@",
        .function => "func",
        .optional => "optional",
        .null => "null",
        .structure => |structure_type| structure_type.source_name,
        .protocol => |protocol_type| protocol_type.source_name,
        .enumeration => |enum_type| enum_type.source_name,
    };
}

fn allocatedTypeName(allocator: Allocator, value: Type) Allocator.Error![]const u8 {
    return switch (value) {
        .optional => |contained| std.fmt.allocPrint(allocator, "{s}?", .{try allocatedTypeName(allocator, contained.*)}),
        .list => |element| std.fmt.allocPrint(allocator, "{s}[]", .{try allocatedTypeName(allocator, element.*)}),
        .fixed_array => |array| std.fmt.allocPrint(allocator, "{s}[{d}]", .{ try allocatedTypeName(allocator, array.element.*), array.length }),
        else => typeName(value),
    };
}

fn allocatedSignatureTypeName(allocator: Allocator, value: Type) Allocator.Error![]const u8 {
    return switch (value) {
        .function => |function| function_name: {
            var output: std.ArrayList(u8) = .empty;
            try output.appendSlice(allocator, "func(");
            for (function.parameters, function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (mode == .borrow) try output.appendSlice(allocator, "borrow ");
                if (mode == .mutable_reference) try output.append(allocator, '&');
                try output.appendSlice(allocator, try allocatedTypeName(allocator, parameter));
            }
            try output.append(allocator, ')');
            if (function.return_type.* != .void) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, try allocatedTypeName(allocator, function.return_type.*));
            }
            break :function_name try output.toOwnedSlice(allocator);
        },
        else => allocatedTypeName(allocator, value),
    };
}

fn sequenceElementType(value: Type) ?Type {
    return switch (value) {
        .list => |element| element.*,
        .fixed_array => |array| array.element.*,
        else => null,
    };
}

fn isPlaceValue(value: *const Expression) bool {
    return switch (value.value) {
        .variable, .self, .member_access, .index_access => true,
        .unary => |unary| unary.operator == .dereference,
        else => false,
    };
}

fn isStructure(value: Type) bool {
    return switch (value) {
        .structure => true,
        else => false,
    };
}

fn isNumeric(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64 => true,
        else => false,
    };
}

fn isInteger(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

fn isUnsignedInteger(value: Type) bool {
    return switch (value) {
        .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

fn commonUnsignedIntegerType(left: Type, right: Type) ?Type {
    if (!isUnsignedInteger(left) or !isUnsignedInteger(right)) return null;
    return if (integerBits(left) >= integerBits(right)) left else right;
}

fn integerBits(value: Type) u8 {
    return switch (value) {
        .int8, .uint8 => 8,
        .int16, .uint16 => 16,
        .int32, .uint32 => 32,
        .int, .uint64 => 64,
        else => 0,
    };
}

fn integerLiteralFits(value: u64, target: Type) bool {
    if (!isInteger(target)) return false;
    const bits = integerBits(target);
    if (isUnsignedInteger(target)) return bits == 64 or value <= (@as(u64, 1) << @intCast(bits)) - 1;
    return value <= (@as(u64, 1) << @intCast(bits - 1)) - 1;
}

fn isContextualIntegerLiteral(expression_value: *const Expression) bool {
    if (expression_value.value == .integer) return true;
    return expression_value.value == .unary and
        expression_value.value.unary.operator == .numeric_negate and
        expression_value.value.unary.operand.value == .integer;
}

fn canWiden(source: Type, target: Type) bool {
    if (isInteger(source) and isInteger(target)) {
        return isUnsignedInteger(source) == isUnsignedInteger(target) and integerBits(source) < integerBits(target);
    }
    if (isInteger(source) and (target == .float or target == .float64)) return true;
    return source == .float and target == .float64;
}

fn commonNumericType(left: Type, right: Type) ?Type {
    if (typeEqual(left, right)) return left;
    if (left == .float64 or right == .float64) return .float64;
    if (left == .float or right == .float) return .float;
    if (isInteger(left) and isInteger(right) and isUnsignedInteger(left) == isUnsignedInteger(right)) {
        return if (integerBits(left) >= integerBits(right)) left else right;
    }
    return null;
}

fn isPrintable(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool, .str => true,
        else => false,
    };
}

const AssignmentRoot = union(enum) {
    static,
    self,
    variable: []const u8,
};

fn isCascadeOwnedTemporary(expression: *const Ast.Expression) bool {
    return switch (expression.value) {
        .call, .method_call, .static_method_call, .super_method_call, .class_initializer, .structure_initializer, .match_expression, .sequence_literal => true,
        .member_access => |member| isCascadeOwnedTemporary(member.object),
        .index_access => |access| isCascadeOwnedTemporary(access.object),
        .slice_access => true,
        else => false,
    };
}

fn assignmentRoot(expression: *const Ast.Expression) ?AssignmentRoot {
    return switch (expression.value) {
        .static_field_access => .static,
        .self => .self,
        .identifier => |name| .{ .variable = name },
        .member_access => |member| assignmentRoot(member.object),
        .index_access => |access| assignmentRoot(access.object),
        else => null,
    };
}

fn expressionScopeDepth(expression: *const Ast.Expression, scope: *const Scope) usize {
    return switch (assignmentRoot(expression) orelse return scope.depth) {
        .static => 0,
        .self => 1,
        .variable => |name| if (findSymbol(scope, name)) |symbol| symbol.scope_depth else scope.depth,
    };
}

fn assignmentDestinationDepth(
    expression: *const Ast.Expression,
    self: *const Analyzer,
    scope: *const Scope,
) usize {
    return switch (assignmentRoot(expression) orelse return scope.depth) {
        .static => 0,
        .self => self.function_scope_depth,
        .variable => |name| if (findSymbol(scope, name)) |symbol| symbol.scope_depth else scope.depth,
    };
}

fn updateDestinationLifetime(expression: *const Ast.Expression, scope: *const Scope, lifetime_depth: usize) void {
    const root = assignmentRoot(expression) orelse return;
    switch (root) {
        .static => {},
        .variable => |name| if (findSymbol(scope, name)) |symbol| {
            symbol.state.lifetime_depth = @max(symbol.state.lifetime_depth, lifetime_depth);
        },
        .self => {},
    }
}

fn receiverFor(expression: *const Ast.Expression, scope: *const Scope, self_borrowed: bool) Receiver {
    return switch (expression.value) {
        .static_field_access => .mutable,
        .self => if (self_borrowed) .borrowed_self else .self,
        .identifier => |name| receiver: {
            const symbol = findSymbol(scope, name) orelse break :receiver .temporary;
            if (symbol.state.mutable_borrow or symbol.state.immutable_borrows != 0) break :receiver .{ .borrowed = name };
            break :receiver if (symbol.mutability == .mutable)
                .mutable
            else
                .{ .immutable = .{
                    .name = name,
                    .control_binding = symbol.control_binding,
                    .read_iteration = symbol.read_iteration,
                    .collection_shell = symbol.immutable_collection_shell,
                } };
        },
        .member_access => |member| receiverFor(member.object, scope, self_borrowed),
        .index_access => |access| receiverFor(access.object, scope, self_borrowed),
        else => .temporary,
    };
}

fn assignmentOperatorText(operator: Ast.AssignmentOperator) []const u8 {
    return switch (operator) {
        .assign => "=",
        .add => "+=",
        .subtract => "-=",
        .multiply => "*=",
        .divide => "/=",
        .increment => "++",
        .decrement => "--",
    };
}

fn expectSemanticError(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(expected_message, analyzer.diagnostic.?.message);
}

fn expectResolvedSemanticError(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expectEqualStrings(expected_message, analyzer.diagnostic.?.message);
}

fn expectResolvedSemanticErrorContains(source: []const u8, expected_message: []const u8) !void {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expect(std.mem.indexOf(u8, analyzer.diagnostic.?.message, expected_message) != null);
}

fn expectSemanticSuccess(source: []const u8) !void {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, source);
    var analyzer = Analyzer.init(allocator);
    _ = analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())) catch |failure| {
        if (analyzer.diagnostic) |diagnostic| std.debug.print("unexpected semantic error: {s}\n", .{diagnostic.message});
        return failure;
    };
}

test "analyze enum construction and exhaustive match" {
    try expectSemanticSuccess(
        \\enum Verdict { idle; value(int); failed(str) }
        \\func text(result:Verdict) str {
        \\    return match result { idle => "idle"; value(number) => "value"; failed(message) => message }
        \\}
        \\func main() { let result = Verdict.value(7); print(text(result)) }
    );
}

test "analyze expression and imperative matches with else" {
    try expectSemanticSuccess(
        \\enum State { idle; ready; failed(str) }
        \\func main() {
        \\    let state = State.ready()
        \\    let text = match state { idle => "idle"; else => "other" }
        \\    match state { failed(message) => { print(message) }; else => { print(text) } }
        \\    let any = match state { else => true }
        \\    print(any)
        \\}
    );
}

test "reject incomplete duplicate and ill-typed enum matches" {
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {} } }
    , "match on enum 'State' is not exhaustive; missing variant 'ready'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; idle => {}; ready => {} } }
    , "variant 'idle' is matched more than once");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 1; ready => "ready" } }
    , "match branches must have the same type; expected 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); let value = match state { idle => 1; else => "ready" } }
    , "match branches must have the same type; expected 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; ready => {}; else => {} } }
    , "else match branch does not cover any remaining variant");
    try expectResolvedSemanticError(
        \\enum State { idle; ready }
        \\func main() { let state = State.idle(); match state { idle => {}; unknown => {}; ready => {} } }
    , "enum 'State' has no variant 'unknown'");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.integer(); }
    , "variant 'Value.integer' expects 1 associated values, found 0");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.integer("wrong"); }
    , "associated value 1 of variant 'Value.integer' expects 'int', found 'str'");
    try expectResolvedSemanticError(
        \\enum Value { integer(int); empty }
        \\func main() { let value = Value.empty; }
    , "an enum variant must be constructed with parentheses");
    try expectResolvedSemanticError(
        \\class Owner {}
        \\enum Value { empty; owner(Owner) }
        \\func main() { let value = Value.empty(); }
    , "type 'Value' is not an independent value because field 'owner[1]' reaches 'Owner'; use 'var'");
}

test "analyze raw enum values and intrinsic property" {
    try expectSemanticSuccess(
        \\enum Direction:int { north = 1; south = 2; unknown = -1 }
        \\enum Name:str { north = "north"; south = "south" }
        \\func main() {
        \\    let direction = Direction.north()
        \\    let code:int = direction.raw_value
        \\    let name:str = Name.south().raw_value
        \\    print(code)
        \\    print(name)
        \\}
    );
}

test "reject invalid raw enum values and property mutation" {
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1; south = 1 }
        \\func main() {}
    , "raw enum value is already used by variant 'north'");
    try expectResolvedSemanticError(
        \\enum Name:str { first = "same"; second = "s\u{61}me" }
        \\func main() {}
    , "raw enum value is already used by variant 'first'");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = "north" }
        \\func main() {}
    , "raw enum value must be a 'int' literal");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 + 1 }
        \\func main() {}
    , "raw enum value must be a 'int' literal");
    try expectResolvedSemanticError(
        \\enum State { ready }
        \\func main() { let state = State.ready(); print(state.raw_value) }
    , "enum 'State' has no raw value");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 }
        \\func main() { var direction = Direction.north(); direction.raw_value = 2 }
    , "enum property 'raw_value' is read-only");
    try expectResolvedSemanticError(
        \\enum Direction:int { north = 1 }
        \\func replace(value:&int) { value = 2 }
        \\func main() { var direction = Direction.north(); replace(&direction.raw_value) }
    , "enum property 'raw_value' cannot be passed with '&'");
}

test "field mutability controls direct and nested mutation" {
    try expectSemanticSuccess(
        \\struct Counter { var value:int; func bump() { self.value += 1 } }
        \\struct State { let id:int; var counter:Counter }
        \\func main() { var state = State(id:1, counter:Counter(value:0)); state.counter.bump() }
    );
    try expectResolvedSemanticError(
        "struct State { let id:int } func main() { var state = State(id:1); state.id = 2 }",
        "cannot mutate let field 'id'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int } struct State { let counter:Counter } func main() { var state = State(counter:Counter(value:0)); state.counter.value = 1 }",
        "cannot mutate let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } struct State { let counter:Counter } func main() { var state = State(counter:Counter(value:0)); state.counter.bump() }",
        "cannot call mutating method 'bump' through let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct State { let values:int[] } func main() { var state = State(values:[]); state.values.append(1) }",
        "cannot mutate through let field 'values'",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } struct State { let counter:Counter? } func main() { var state = State(counter:Counter(value:0)); state.counter?.bump() }",
        "cannot call mutating method 'bump' through let field 'counter'",
    );
    try expectResolvedSemanticError(
        "struct State { let values:int[]? } func main() { var state = State(values:[]); state.values?.append(1) }",
        "cannot mutate through let field 'values'",
    );
}

test "static methods use type receivers and separate overload sets" {
    try expectSemanticSuccess(
        \\struct Position {
        \\    var x:int
        \\    static func origin() Position { return Position(x:0) }
        \\    static func from(value:int) Position { return Position(x:value) }
        \\    func from() int { return self.x }
        \\}
        \\func main() { let origin = Position.origin(); let value = Position.from(3); assert(origin.x + value.from() == 3, "static methods") }
    );
    try expectResolvedSemanticError(
        "struct Factory { static func create() Factory { return Factory() } } func main() { var factory = Factory(); factory.create() }",
        "static method 'create' must be called through type 'Factory'",
    );
    try expectResolvedSemanticError(
        "struct Factory { func create() Factory { return Factory() } } func main() { let factory = Factory.create() }",
        "instance method 'create' requires a value of type 'Factory'",
    );
}

test "static methods have no self or super and are not inherited" {
    try expectResolvedSemanticError(
        "struct Factory { static func create() Factory { return self } } func main() {}",
        "'self' is not available inside a static method",
    );
    try expectResolvedSemanticError(
        "class Base { pub static func create() Base { return Base() } } class Child : Base {} func main() { let child = Child.create() }",
        "type 'Child' has no static method 'create'",
    );
    try expectResolvedSemanticError(
        "class Base { pub func value() int { return 1 } } class Child : Base { pub static func value() int { return super.value() } } func main() {}",
        "'super' is not available inside a static method",
    );
}

test "let class fields initialize exactly once in their declaring constructor" {
    try expectSemanticSuccess(
        \\class User {
        \\    let id:int
        \\    pub var name:str
        \\    pub init(id:int, name:str) { self.id = id; self.name = name }
        \\}
        \\func main() { var user = User(1, "Ada"); user.name = "Grace" }
    );
    try expectSemanticError(
        "class User { let id:int; pub init(id:int) { self.id = id; self.id = id } } func main() {}",
        "field 'id' is initialized more than once",
    );
    try expectSemanticError(
        "class User { let id:int; pub init(assign:bool) { if assign { self.id = 1 } } } func main() {}",
        "constructor of class 'User' leaves field 'id' without a value",
    );
    try expectSemanticError(
        "class User { let id:int; pub init(assign:bool) { if assign { self.id = 1 } self.id = 2 } } func main() {}",
        "field 'id' may be initialized more than once",
    );
    try expectSemanticError(
        "class User { let id:int = 1; pub init() { self.id = 2 } } func main() {}",
        "cannot mutate let field 'id'",
    );
    try expectSemanticError(
        "class Base { sub let id:int; sub init(id:int) { self.id = id } } class Child : Base { pub init() : super(1) { self.id = 2 } } func main() {}",
        "cannot mutate let field 'id'",
    );
}

test "let fields require recursively independent types" {
    try expectSemanticError(
        "class Player {} struct Team { let player:Player } func main() {}",
        "type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectSemanticError(
        "struct Handler { let callback:func() } func main() {}",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
}

fn resolveSingleTestProgram(allocator: Allocator, program: Ast.Program) !Ast.Program {
    const Modules = @import("Modules.zig");
    const project = @import("Project.zig").Project{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = true,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = program }});
    return resolver.resolve();
}

test "validate protocol conformances and inherited public requirements" {
    try expectSemanticSuccess(
        \\protocol Describable { func describe() str }
        \\protocol Drawable { func draw() }
        \\struct User : Describable { func describe() str { return "user" } }
        \\class Entity { pub func describe() str { return "entity" } }
        \\class Player : Entity, Describable, Drawable { pub func draw() {} }
        \\class Child : Player {}
        \\func main() {}
    );
}

test "reject missing private static and incompatible protocol requirements" {
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Player : Drawable { func draw() {} }
        \\func main() {}
    , "method 'draw' must be public to satisfy protocol 'Drawable' for type 'Player'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Icon : Drawable { static func draw() {} }
        \\func main() {}
    , "type 'Icon' does not satisfy method 'draw' required by protocol 'Drawable'");
    try expectResolvedSemanticError(
        \\protocol Describable { func describe() str }
        \\struct User : Describable { func describe() int { return 1 } }
        \\func main() {}
    , "type 'User' does not satisfy method 'describe' required by protocol 'Describable'");
}

test "analyze dynamic protocol values and reject values outside their contract" {
    try expectSemanticSuccess(
        \\protocol Drawable { func draw() str }
        \\struct Icon : Drawable { var name:str; func draw() str { return self.name } }
        \\class Player : Drawable { pub func draw() str { return "player" } }
        \\func render(value:Drawable) str { return value.draw() }
        \\func make() Drawable { return Icon(name:"icon") }
        \\func main() {
        \\    var drawable:Drawable = Icon(name:"first")
        \\    drawable = Player()
        \\    var values:Drawable[] = [Icon(name:"list"), Player()]
        \\    assert(render(values[0]) == "list", "protocol parameter")
        \\    var result = make()
        \\    assert(result.draw() == "icon", "protocol return")
        \\}
    );
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Rock {}
        \\func main() { var drawable:Drawable = Rock() }
    , "expected 'Drawable', found 'Rock'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Icon : Drawable { func draw() {} }
        \\func main() { var drawable:Drawable = Icon(); drawable.save() }
    , "protocol 'Drawable' has no method 'save'");
}

test "analyze local type extensions with mutation and static methods" {
    try expectSemanticSuccess(
        \\struct Counter { var value:int }
        \\extend Counter {
        \\    func increment() int { self.value += 1; return self.value }
        \\    pub static func zero() Counter { return Counter(value:0) }
        \\}
        \\func main() {
        \\    var counter = Counter.zero()
        \\    assert(counter.increment() == 1, "extension mutation")
        \\}
    );
}

test "extensions use only public members and do not participate in inheritance" {
    try expectResolvedSemanticError(
        \\class Vault { var secret:int; pub init() { self.secret = 1 } }
        \\extend Vault { pub func reveal() int { return self.secret } }
        \\func main() {}
    , "field 'secret' is private in class 'Vault'");
    try expectResolvedSemanticError(
        \\class Entity { sub func hidden() {} }
        \\extend Entity { pub func expose() { self.hidden() } }
        \\func main() {}
    , "method 'hidden' is accessible only from class 'Entity' and its descendants");
    try expectResolvedSemanticError(
        \\class Entity {}
        \\extend Entity { pub func ping() {} }
        \\class Player : Entity {}
        \\func main() { var player = Player(); player.ping() }
    , "class 'Player' has no method 'ping'");
    try expectResolvedSemanticError(
        \\struct Value { func read() int { return 1 } }
        \\extend Value { pub func read() int { return 2 } }
        \\func main() {}
    , "extension method 'read' conflicts with an existing method signature on type 'Value'");
}

test "extension conformances support dynamic values and multiple protocols" {
    try expectSemanticSuccess(
        \\protocol Drawable { func draw() int }
        \\protocol Named { func name() str }
        \\struct Sprite { var value:int }
        \\struct Existing { func draw() int { return 7 } }
        \\class Button {}
        \\extend Sprite : Drawable, Named {
        \\    func draw() int { return self.value }
        \\    func name() str { return "sprite" }
        \\}
        \\extend Existing : Drawable {}
        \\extend Button : Drawable { pub func draw() int { return 9 } }
        \\func main() {
        \\    var sprite = Sprite(value:42)
        \\    var drawable:Drawable = sprite
        \\    var named:Named = sprite
        \\    assert(drawable.draw() == 42, "dynamic extension conformance")
        \\    assert(named.name() == "sprite", "second extension conformance")
        \\    var existing:Drawable = Existing()
        \\    assert(existing.draw() == 7, "existing method conformance")
        \\    var button:Drawable = Button()
        \\    assert(button.draw() == 9, "public class extension conformance")
        \\}
    );
}

test "extension conformances use target visibility defaults and apply to the exact type" {
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Sprite {}
        \\extend Sprite : Drawable { func draw() {} }
        \\func main() {}
    , "method 'draw' must be public to satisfy protocol 'Drawable' for type 'Sprite'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Sprite {}
        \\extend Sprite : Drawable {}
        \\func main() {}
    , "type 'Sprite' does not satisfy method 'draw' required by protocol 'Drawable'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\class Entity {}
        \\extend Entity : Drawable { pub func draw() {} }
        \\class Player : Entity {}
        \\func main() { var drawable:Drawable = Player() }
    , "expected 'Drawable', found 'Player'");
    try expectResolvedSemanticError(
        \\protocol Drawable { func draw() }
        \\struct Sprite : Drawable { func draw() {} }
        \\extend Sprite : Drawable {}
        \\func main() {}
    , "extension conformance of type 'Sprite' to protocol 'Drawable' from module 'Test' conflicts with the conformance declared by the type");
}

test "native ABI rejects optional returns" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_lookup() int?\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.native_lookup";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings("native functions cannot return 'int?'", analyzer.diagnostic.?.message);
}

test "native ABI rejects optional parameters" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_lookup(value:int?) int\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Math.native_lookup";
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Math"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings("native parameter 'value' cannot use 'int?'", analyzer.diagnostic.?.message);
}

test "infer variables and resolve nested scope" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; if (true) { print(count); } }");
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(Type.int, program.functions[0].statements[0].variable_declaration.type);
    try std.testing.expectEqual(
        Type.int,
        program.functions[0].statements[1].if_statement.body[0].print.type,
    );
}

test "let accepts recursively independent values" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int; var y:int }
        \\struct Snapshot { var positions:Position[]; var selected:Position? }
        \\func main() {
        \\    let origin = Position()
        \\    let snapshot = Snapshot(positions:[origin], selected:origin)
        \\    print(snapshot.positions[0].x)
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));

    try std.testing.expectEqual(@as(usize, 3), program.functions[0].statements.len);
}

test "let rejects function values directly and through fields" {
    try expectSemanticError(
        "func main() { let callback = func() {}; }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectResolvedSemanticError(
        \\struct Handler { var callback:func() }
        \\func main() { let handler = Handler(callback:func() {}); }
    ,
        "type 'Handler' is not an independent value because field 'callback' reaches 'func'; use 'var'",
    );
    try expectResolvedSemanticError(
        \\struct Handler { var callbacks:func()[] }
        \\struct Screen { var handler:Handler? }
        \\func main() { let screen = Screen(handler:null); }
    ,
        "type 'Screen' is not an independent value because field 'handler.callbacks' reaches 'func'; use 'var'",
    );
}

test "classes have shared-reference types and are never independent let values" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { pub var health:int = 100 }
        \\func main() { var player = Player(); var alias = player; alias.health -= 1 }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expect(program.structures[0].is_class);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.type.structure.is_class);

    try expectResolvedSemanticError(
        "class Player {} func main() { let player = Player() }",
        "type 'Player' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectResolvedSemanticError(
        "class Player {} func replace(player:&Player) {} func main() {}",
        "class 'Player' already has reference semantics; '&Player' is invalid",
    );
    try expectResolvedSemanticError(
        "class Player {} class Enemy {} func main() { var player = Player(); var enemy = Enemy(); let equal = player == enemy }",
        "equality operator requires operands of the same type, found 'Player' and 'Enemy'",
    );
    try expectResolvedSemanticError(
        "class Player {} func main() { if var player = Player() {} }",
        "conditional binding source must have an optional type",
    );
    try expectResolvedSemanticError(
        "class Player {} func invalid() func() { var player = Player(); return func() { print(player == player) } } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "class members are private by default and pub exposes them" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Vault {
        \\    var value:int = 40
        \\    sub var offset:int = 2
        \\    func total() int { return self.value + self.offset }
        \\    pub func read() int { return self.total() }
        \\    pub func copy_from(other:Vault) { self.value = other.value }
        \\}
        \\func main() { var first = Vault(); var second = Vault(); second.copy_from(first); print(second.read()) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.MemberVisibility.private_access, program.structures[0].fields[0].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.subclass, program.structures[0].fields[1].visibility);
    try std.testing.expectEqual(Ast.MemberVisibility.public_access, program.structures[0].methods[1].visibility);

    try expectResolvedSemanticError(
        "class Vault { var value:int = 1 } func main() { var vault = Vault(); print(vault.value) }",
        "field 'value' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { func reset() {} } func main() { var vault = Vault(); vault.reset() }",
        "method 'reset' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { sub var value:int = 1 } func main() { var vault = Vault(); print(vault.value) }",
        "field 'value' is accessible only from class 'Vault' and its descendants",
    );
    try expectResolvedSemanticError(
        "class Vault { var value:int } func main() { var vault = Vault(value:1) }",
        "field 'value' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { var callback:(func())? = null } func main() { var vault = Vault(); print(vault.callback == null) }",
        "field 'callback' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { func reset() {} } func main() { var vault:Vault? = Vault(); vault?.reset() }",
        "method 'reset' is private in class 'Vault'",
    );
    try expectResolvedSemanticError(
        "class Vault { var value:int = 1 } func main() { var vault = Vault()..value = 2 }",
        "field 'value' is private in class 'Vault'",
    );
}

test "class constructors overload and establish private state" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { pub var health:int = 100 }
        \\class Match {
        \\    var owner:Player
        \\    var count:int = 1
        \\    pub init(owner:Player) { self.owner = owner }
        \\    pub init(owner:Player, count:int) { self.owner = owner; self.count = count }
        \\    pub func get_owner() Player { return self.owner }
        \\    pub func get_count() int { return self.count }
        \\}
        \\func main() { var first = Match(Player()); var second = Match(Player(), 2); print(second.get_count()) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(@as(usize, 2), program.structures[1].constructors.len);
    try std.testing.expect(program.functions[0].statements[0].variable_declaration.initializer.value == .class_initializer);

    try expectResolvedSemanticError(
        "class Session { var token:str; pub init(token:str) { self.token = token } } func main() { var session = Session() }",
        "no compatible constructor for 'Session'; visible constructors: Session(str)",
    );
    try expectResolvedSemanticError(
        "class Session { pub var token:str; pub init(token:str) { self.token = token } } func main() { var session = Session(token:\"abc\") }",
        "class 'Session' declares custom constructors and cannot use a named field initializer",
    );
    try expectResolvedSemanticError(
        "class Session { var token:str; init(token:str) { self.token = token } } func main() { var session = Session(\"abc\") }",
        "constructor of class 'Session' is private",
    );
}

test "class constructors require complete initialization on every path" {
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; pub init(owner:Player, assign:bool) { if assign { self.owner = owner } } } func main() {}",
        "constructor of class 'Match' leaves field 'owner' without a value",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; pub init(owner:Player) { print(self.owner == owner); self.owner = owner } } func main() {}",
        "field 'owner' is read before it is initialized",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; pub init(owner:Player) { self.inspect(); self.owner = owner } func inspect() {} } func main() {}",
        "an instance method cannot be called before every class field is initialized",
    );
    try expectResolvedSemanticError(
        "class Player {} class Match { var owner:Player; pub init(owner:Player) { var alias = self; self.owner = owner } } func main() {}",
        "'self' cannot escape before every class field is initialized",
    );
}

test "class drop can read private state but cannot return" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Texture {
        \\    var handle:int = 1
        \\    drop { print(self.handle) }
        \\}
        \\func main() { var texture = Texture() }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expect(program.structures[0].drop != null);

    try expectResolvedSemanticError(
        "class Texture { drop { return } } func main() {}",
        "'drop' cannot return",
    );
}

test "unique resource structures initialize local owners directly" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    func value() int { return self.handle }
        \\    drop { print(self.handle) }
        \\}
        \\func main() {
        \\    let first = Resource.open(1)
        \\    var second = Resource.open(2)
        \\    print(first.value())
        \\    print(second.value())
        \\}
    );
}

test "noncopyable values compose through fields enums optionals collections classes and generics" {
    const declaration =
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
    ;

    try expectSemanticSuccess(declaration ++
        \\struct Holder { var resource:Resource }
        \\class Owner { pub var resource:Resource }
        \\enum Slot { full(Holder); empty }
        \\func consume(value:Resource) {}
        \\func consume_holder(value:Holder) {}
        \\func inspect(borrow value:Resource) {}
        \\func main() {
        \\    let holder = Holder(resource:Resource.open(1))
        \\    inspect(borrow holder.resource)
        \\    var optional:Resource? = Resource.open(3)
        \\    if value = borrow optional { inspect(borrow value) }
        \\    if var value = move optional { consume(move value) }
        \\    var slot = Slot.full(Holder(resource:Resource.open(4)))
        \\    match borrow slot { full(value) => { inspect(borrow value.resource) }; empty => {} }
        \\    match move slot { full(var value) => { consume_holder(move value) }; empty => {} }
        \\    var values:Resource[] = []
        \\    values.append(Resource.open(5))
        \\    let resource = Resource.open(6)
        \\    values.append(move resource)
        \\    for value in values { inspect(borrow value) }
        \\    for var value in values { inspect(borrow value) }
        \\    consume(values.take_first())
        \\    consume(values.replace(0, Resource.open(7)))
        \\    consume(values.take_last())
        \\    var owner = Owner(resource:Resource.open(8))
        \\    inspect(borrow owner.resource)
        \\}
    );
    try expectSemanticSuccess(
        \\protocol Readable { func value() int }
        \\struct Resource : Readable {
        \\    let handle:int
        \\    func value() int { return self.handle }
        \\    drop {}
        \\}
        \\func inspect(borrow value:Resource) int { return value.value() }
        \\func main() { let resource = Resource(handle:1); print(inspect(borrow resource)) }
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Resource.open(1); let second = first }",
        "cannot copy noncopyable value 'Resource'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func duplicate() Resource { let resource = Resource.open(1); return resource } func main() {}",
        "named noncopyable value 'Resource' must be returned with 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "struct Registry { static var current:Resource } func main() {}",
        "a static field cannot own a noncopyable value",
    );
    try expectResolvedSemanticError(
        declaration ++ "func mutate(resource:&Resource) {} func main() {}",
        "noncopyable value 'Resource' cannot be passed with '&'; use 'borrow' for read-only access",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let callback = func() { print(resource.handle) } }",
        "noncopyable value 'Resource' cannot be captured by a lambda",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Resource.open(1); let second = Resource.open(2); print(first == second) }",
        "type 'Resource' does not support equality",
    );
    try expectResolvedSemanticError(
        declaration ++ "struct Holder { var resource:Resource } func main() { let first = Holder(resource:Resource.open(1)); let second = Holder(resource:Resource.open(2)); print(first == second) }",
        "type 'Holder' does not support equality",
    );
}

test "noncopyable containers require explicit whole-value transfer" {
    const declaration =
        \\struct Resource { let handle:int; drop {} }
        \\struct Holder { var resource:Resource }
        \\enum Slot { full(Holder); empty }
        \\func consume(value:Resource) {}
    ;

    try expectResolvedSemanticError(
        declaration ++ "func main() { let first = Holder(resource:Resource(handle:1)); let second = first }",
        "cannot copy noncopyable value 'Holder'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let slot = Slot.full(Holder(resource:Resource(handle:1))); match slot { full(value) => {}; empty => {} } }",
        "a named noncopyable enum must be matched with 'match move' or 'match borrow'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let pending:Resource? = Resource(handle:1); if value = pending {} }",
        "a named noncopyable optional must be extracted with 'move' or 'borrow'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let holder = Holder(resource:Resource(handle:1)); consume(move holder.resource) }",
        "'move' requires a complete local binding or parameter",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; let copy = values[0] }",
        "cannot copy noncopyable value 'Resource'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; let copy = values[0:1] }",
        "cannot copy noncopyable value 'list'; initialize it directly from a temporary value or use 'move'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let values:Resource[] = [Resource(handle:1)]; for let value in values {} }",
        "'for let' would copy a noncopyable element; use the read loop or 'for var'",
    );
    try expectResolvedSemanticError(
        "protocol Stored {} struct Resource { let handle:int; drop {} } struct Holder : Stored { var resource:Resource } func erase(value:Stored) {} func main() { let holder = Holder(resource:Resource(handle:1)); erase(move holder) }",
        "noncopyable value 'Holder' cannot be converted to dynamic protocol value 'Stored'",
    );
}

test "unique resources transfer explicitly through locals parameters assignments and returns" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\func consume(resource:Resource) {}
        \\func forward(resource:Resource) Resource { return move resource }
        \\func main() {
        \\    let first = Resource.open(1)
        \\    let second = move first
        \\    consume(move second)
        \\    consume(Resource.open(2))
        \\    let third = forward(Resource.open(3))
        \\    var reusable = move third
        \\    reusable = Resource.open(4)
        \\    consume(move reusable)
        \\    reusable = Resource.open(5)
        \\    consume(move reusable)
        \\}
    );
}

test "unique resource availability follows branches matches and loop exits" {
    try expectSemanticSuccess(
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\enum Choice { first; second }
        \\func consume(resource:Resource) {}
        \\func branch(flag:bool) {
        \\    let resource = Resource.open(1)
        \\    if flag { consume(move resource); return }
        \\    consume(move resource)
        \\}
        \\func main() {
        \\    var resource = Resource.open(2)
        \\    if true { consume(move resource); resource = Resource.open(3) }
        \\    else { consume(move resource); resource = Resource.open(4) }
        \\    match Choice.first() {
        \\        first => { consume(move resource); resource = Resource.open(5) }
        \\        second => { consume(move resource); resource = Resource.open(6) }
        \\    }
        \\    var count = 0
        \\    while count < 1 {
        \\        consume(move resource)
        \\        resource = Resource.open(7)
        \\        count += 1
        \\    }
        \\    for index in 0...1 {
        \\        consume(move resource)
        \\        resource = Resource.open(index)
        \\    }
        \\    consume(move resource)
        \\}
    );
}

test "unique resource moves reject invalid sources and consumed uses" {
    const declaration =
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop {}
        \\}
        \\func consume(resource:Resource) {}
    ;

    try expectResolvedSemanticError(
        declaration ++ "func main() { let value = 1; let invalid = move value }",
        "'move' requires a noncopyable value, found 'int'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let invalid = move resource.handle }",
        "'move' requires a complete local binding or parameter",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); consume(resource) }",
        "noncopyable value 'Resource' must be passed with 'move'",
    );
    try expectResolvedSemanticErrorContains(
        declaration ++ "func main() { let resource = Resource.open(1); consume(move resource); print(resource.handle) }",
        "noncopyable value 'resource' was consumed by 'move' at",
    );
    try expectResolvedSemanticErrorContains(
        declaration ++ "func main() { let resource = Resource.open(1); consume(move resource); consume(move resource) }",
        "noncopyable value 'resource' was consumed by 'move' at",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { let resource = Resource.open(1); let other = move resource; resource = move other }",
        "cannot assign to immutable variable 'resource'",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { var resource = Resource.open(1); resource = move resource }",
        "cannot move unique resource 'resource' into itself",
    );
    try expectResolvedSemanticError(
        declaration ++ "func main() { var resource = Resource.open(1); while true { consume(move resource) } }",
        "unique resource 'resource' must have the same availability on every path returning to the loop header",
    );
}

test "unique resource drop has the ordinary drop restrictions" {
    try expectResolvedSemanticError(
        "struct Resource { drop { return } } func main() {}",
        "'drop' cannot return",
    );
}

test "class inheritance constructs one base and converts references upward" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Entity {
        \\    var id:int
        \\    sub var position:int
        \\    sub init(id:int, position:int) { self.id = id; self.position = position }
        \\    pub func advance(delta:int) { self.position += delta }
        \\}
        \\class Player : Entity {
        \\    var name:str
        \\    pub init(id:int, name:str, position:int) : super(id, position) { self.name = name }
        \\    pub func copy_position(other:Entity) { self.position = other.position }
        \\}
        \\func update(entity:Entity) { entity.advance(1) }
        \\func main() {
        \\    var player = Player(1, "Ada", 2)
        \\    var entity:Entity = player
        \\    var optional:Entity? = player
        \\    var entities:Entity[] = [player]
        \\    update(player)
        \\    assert(entity == player, "upcast keeps identity")
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqualStrings(program.structures[0].generated_name, program.structures[1].base.?.generated_name);
    try std.testing.expect(program.structures[1].constructors[0].base_initializer != null);
    try std.testing.expect(program.functions[1].statements[1].variable_declaration.initializer.value == .conversion);

    try expectResolvedSemanticError(
        "class Base { var value:int; sub init() {} } class Child : Base { var value:int; pub init() : super() {} } func main() {}",
        "field 'value' in class 'Child' collides with an inherited field",
    );
    try expectResolvedSemanticError(
        "class Base { func hidden() {} } class Child : Base { pub init() {} pub func reveal() { self.hidden() } } func main() {}",
        "method 'hidden' is private in class 'Base'",
    );
    try expectResolvedSemanticError(
        "class Base { var hidden:int } class Child : Base { pub init() {} pub func reveal() int { return self.hidden } } func main() {}",
        "field 'hidden' is private in class 'Base'",
    );
    try expectResolvedSemanticError(
        "class Base { init() {} } class Child : Base { pub init() : super() {} } func main() {}",
        "constructor of base class 'Base' is private",
    );
    try expectResolvedSemanticError(
        "class First : Second {} class Second : First {} func main() {}",
        "inheritance cycle involving class 'First'",
    );
    try expectResolvedSemanticError(
        "class Base { pub func act() {} } class Child : Base { pub func act() {} } func main() {}",
        "method 'act' matches an inherited signature; declare it with 'override'",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base {} func main() { var children:Child[] = []; var bases:Base[] = children }",
        "expected 'Base[]', found 'Child[]'",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base {} func main() { var base = Base(); var child:Child = base }",
        "expected 'Child', found 'Base'",
    );
    try expectResolvedSemanticError(
        "struct Value {} class Child : Value {} func main() {}",
        "base type 'Value' is not a class",
    );
    try expectResolvedSemanticError(
        "class Dependency {} class Base { var dependency:Dependency } class Child : Base { pub init() {} } func main() {}",
        "base class 'Base' cannot be constructed with 'super()'",
    );
    try expectResolvedSemanticError(
        "class Root { pub init() : super() {} } func main() {}",
        "constructor 'super' call requires a base class",
    );
}

test "class overrides share a dynamic slot and super selects the base implementation" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Child : Base {
        \\    override pub func value(input:int) int { return super.value(input) + 1 }
        \\}
        \\class Base { pub func value(input:int) int { return input } }
        \\func main() {}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqualStrings(program.structures[1].methods[0].generated_name, program.structures[0].methods[0].generated_name);
    try std.testing.expect(program.structures[0].methods[0].is_override);
    const returned = program.structures[0].methods[0].statements[0].return_statement.?;
    try std.testing.expect(returned.value.binary.left.value == .super_method_call);

    try expectResolvedSemanticError(
        "class Base { pub func act() {} } class Child : Base { override pub func other() {} } func main() {}",
        "override method 'other' has no compatible inherited method",
    );
    try expectResolvedSemanticError(
        "class Base { pub func value() int { return 1 } } class Child : Base { override pub func value() str { return \"x\" } } func main() {}",
        "override method 'value' must return 'int'",
    );
    try expectResolvedSemanticError(
        "class Base { pub func act() {} } class Child : Base { override sub func act() {} } func main() {}",
        "override method 'act' cannot reduce inherited visibility",
    );
    try expectResolvedSemanticError(
        "class Base { func hidden() {} } class Child : Base { override pub func hidden() {} } func main() {}",
        "private method 'hidden' cannot be overridden",
    );
    try expectResolvedSemanticError(
        "class Base {} class Child : Base { pub func act() { super.missing() } } func main() {}",
        "base class has no method 'missing'",
    );
    try expectResolvedSemanticError(
        "class Base { pub func classify(value:int) {} } class Child : Base { pub func classify(value:str) {} } func main() { var value:Base = Child(); value.classify(\"child\") }",
        "no compatible signature for method 'classify'; visible signatures: classify(int)",
    );
}

test "let rejects non-independent conditional and iteration bindings" {
    try expectSemanticError(
        "func main() { var callback:(func())? = func() {}; if let selected = callback {} }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
    try expectSemanticError(
        "func main() { var callbacks:func()[] = [func() {}]; for (let callback in callbacks) {} }",
        "type 'func' is not an independent value and cannot be bound with 'let'; use 'var'",
    );
}

test "let accepts non-independent elements only through a local collection shell" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Player { pub var value:int; pub func show() {} }
        \\func main() {
        \\    let players:Player[] = [Player()]
        \\    players[0].show()
        \\    players[0].value = 1
        \\    for player in players { player.show() }
        \\    let fixed:Player[1] = [Player()]
        \\    for (player in fixed) { player.show() }
        \\    let callbacks:func()[] = [func() {}]
        \\    for callback in callbacks { callback() }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    _ = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
}

test "read iteration and let collection shells reject storage mutation" {
    try expectResolvedSemanticError(
        "class Player {} func main() { let players:Player[] = [Player()]; players[0] = Player() }",
        "cannot assign to immutable variable 'players'",
    );
    try expectResolvedSemanticError(
        "class Player {} func main() { let players:Player[] = [Player()]; for player in players { player = Player() } }",
        "cannot assign to immutable control binding 'player'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } func main() { let counters:Counter[] = [Counter(value:0)]; for counter in counters { counter.bump() } }",
        "cannot mutate immutable control binding 'counter'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "class Player {} struct Team { var player:Player } func main() { let teams:Team[] = [Team(player:Player())]; teams[0].player = Player() }",
        "cannot assign to immutable variable 'teams'",
    );
}

test "reject assignment to immutable variable" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; count = 6; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "cannot assign to immutable variable 'count'",
        analyzer.diagnostic.?.message,
    );
}

test "reject duplicate variable in same scope" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count = 5; let count = 6; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "variable 'count' is already declared in this scope",
        analyzer.diagnostic.?.message,
    );
}

test "block variables do not escape their scope" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { if (true) { let inside = 5; } print(inside); }",
    );
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("unknown variable 'inside'", analyzer.diagnostic.?.message);
}

test "reject lexical shadowing from enclosing scopes" {
    try expectSemanticError(
        "func read(value:int) int { if (true) { let value = 1; } return value; } func main() void {}",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let value = 1; if (true) { let value = value + 1; } }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { var count = 1; while (true) { var count = 2; } }",
        "variable 'count' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; for (let value in values) { if (true) { let value = 2; } } }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; let value = 0; for (let value in values) {} }",
        "variable 'value' is already declared in an enclosing scope",
    );
    try expectSemanticError(
        "func main() void { let values = [1]; for (let value in values) { for (let value in values) {} } }",
        "variable 'value' is already declared in an enclosing scope",
    );
}

test "separate scopes may reuse a local name" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    let values = [1]
        \\    if (true) { let value = 1 } else { let value = 2 }
        \\    for (let value in values) {}
        \\    for (let value in values) {}
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(usize, 4), program.functions[0].statements.len);
}

test "local variable may share a structure field name" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Counter {
        \\    var value:int
        \\    func combined() int {
        \\        let value = 1
        \\        return self.value + value
        \\    }
        \\}
        \\func main() void {}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(usize, 2), program.structures[0].methods[0].statements.len);
}

test "analyze compact and named integer ranges" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    for (let i in 0...3) {}
        \\    for (var i in range(3, 0)) { i += 100 }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const compact = program.functions[0].statements[0].for_statement;
    try std.testing.expectEqual(Ast.IterationBinding.immutable, compact.binding);
    try std.testing.expectEqual(Type.int, compact.source.integer_range.start.type);
    const named = program.functions[0].statements[1].for_statement;
    try std.testing.expectEqual(Ast.IterationBinding.mutable, named.binding);
    try std.testing.expectEqual(Type.int, named.source.integer_range.end.type);
}

test "analyze negative collection indexes and slices" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() {
        \\    let values:int[3] = [10, 20, 30]
        \\    let last = values[-1]
        \\    let middle = values[1:-1]
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const last = program.functions[0].statements[1].variable_declaration.initializer;
    try std.testing.expectEqual(Type.int, last.type);
    try std.testing.expect(last.value == .index_access);
    const middle = program.functions[0].statements[2].variable_declaration.initializer;
    try std.testing.expect(middle.type == .list);
    try std.testing.expectEqual(Type.int, middle.type.list.*);
    try std.testing.expect(middle.value == .slice_access);
}

test "reject non-int range bounds" {
    try expectSemanticError(
        "func main() void { for (let i in 0.0...3) {} }",
        "expected 'int', found 'float'",
    );
    try expectSemanticError(
        "func main() void { for (let i in range(0, true)) {} }",
        "expected 'int', found 'bool'",
    );
}

test "reject incompatible type annotation" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let count:bool = 5; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "resolve explicit numeric conversion" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let source:int = 12; let target:uint8 = source as uint8; }");
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const initializer = program.functions[0].statements[1].variable_declaration.initializer;
    try std.testing.expectEqual(Type.uint8, initializer.type);
    try std.testing.expectEqual(Type.uint8, initializer.value.conversion.target_type);
}

test "resolve numeric bases separators and exponents" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let binary = 0b1010_0101; let hexadecimal = 0xCA_FE; let exponent = 1.25e+2; }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(@as(u64, 165), program.functions[0].statements[0].variable_declaration.initializer.value.integer);
    try std.testing.expectEqual(@as(u64, 51966), program.functions[0].statements[1].variable_declaration.initializer.value.integer);
    try std.testing.expectEqualStrings("1.25e+2", program.functions[0].statements[2].variable_declaration.initializer.value.floating);
}

test "resolve string escapes concatenation and length" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { var value = \"A\\u{00E9}\\0\"; value += \"!\"; let count = value.count(); }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const value = program.functions[0].statements[0].variable_declaration.initializer;
    try std.testing.expectEqual(Type.str, value.type);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0xC3, 0xA9, 0 }, value.value.string);
    try std.testing.expectEqual(Type.str, program.functions[0].statements[1].assignment.value.?.type);
    try std.testing.expectEqual(Type.int, program.functions[0].statements[2].variable_declaration.initializer.type);
}

test "reject explicit conversion from bool" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let value = true as int; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "explicit conversion requires numeric source and target types, found 'bool' and 'int'",
        analyzer.diagnostic.?.message,
    );
}

test "reject arithmetic between str and int" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { print(\"Hello\" + 2); }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqual(@as(usize, 34), analyzer.diagnostic.?.position.column);
}

test "comparison and logical expressions produce bool" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let result = !(1 >= 2) && \"Silex\" == \"Silex\"; }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[0].variable_declaration.type);
}

test "reject logical operator with int operand" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = 1 && true; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "logical operator requires 'bool' operands, found 'int' and 'bool'",
        analyzer.diagnostic.?.message,
    );
}

test "reject comparison with str operand" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = \"one\" < 2; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "comparison operator requires numeric operands, found 'str' and 'int'",
        analyzer.diagnostic.?.message,
    );
}

test "reject equality between different types" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let result = 1 == true; }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings(
        "equality operator requires operands of the same type, found 'int' and 'bool'",
        analyzer.diagnostic.?.message,
    );
}

test "resolve structural equality recursively" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int; var y:int }
        \\struct Player { var name:str; var position:Position }
        \\func main() void {
        \\    let first = Player(name:"Ada", position:Position(x:10, y:20))
        \\    let copy = Player(name:"Ada", position:Position(x:10, y:20))
        \\    let equal = first == copy
        \\    let different = first != Player(name:"Ada", position:Position(x:11, y:20))
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));

    try std.testing.expectEqual(Type.bool, program.functions[0].statements[2].variable_declaration.type);
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[3].variable_declaration.type);
}

test "if alternatives and else use separate scopes" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { if false { let value = 1 } elif true { let value = 2 } else if false { let value = 3 } else { let value = 4 } }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    const if_statement = program.functions[0].statements[0].if_statement;
    try std.testing.expectEqual(@as(usize, 2), if_statement.alternatives.len);
    try std.testing.expectEqual(@as(usize, 1), if_statement.else_body.?.len);
}

test "alternative conditions require bool" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { if false {} elif 1 {} }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "while requires bool condition and creates a scope" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { var count = 2; while (count > 0) { let inside = count; count = count - 1; } }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[1].while_statement.condition.expression.type);
    try std.testing.expectEqual(@as(usize, 2), program.functions[0].statements[1].while_statement.body.len);
}

test "reject while condition that is not bool" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { while (1) { print(1); } }");
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(try parser.parse()));
    try std.testing.expectEqualStrings("expected 'bool', found 'int'", analyzer.diagnostic.?.message);
}

test "implicit conditional bindings keep let semantics" {
    try expectSemanticError(
        "func main() { var source:int? = 1; if value = source { value = 2 } }",
        "cannot assign to immutable control binding 'value'; use 'var' in the header",
    );
    try expectResolvedSemanticError(
        "struct Counter { var value:int; func bump() { self.value += 1 } } func main() { var source:Counter? = Counter(value:0); if counter = source { counter.bump() } }",
        "cannot mutate immutable control binding 'counter'; use 'var' in the header",
    );
}

test "resolve forward and recursive function calls" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void { print(factorial(5)) }
        \\func factorial(value:int) int {
        \\    if (value <= 1) { return 1 } else { return value * factorial(value - 1) }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(@as(usize, 2), program.functions.len);
    try std.testing.expectEqual(Type.int, program.functions[1].return_type);
}

test "reject mutation of a let captured by a lambda" {
    try expectSemanticError(
        "func main() { let count = 1; var callback = func() { count += 1; }; callback(); }",
        "cannot assign to immutable variable 'count'",
    );
}

test "reject returning a capturing lambda" {
    try expectSemanticError(
        "func invalid() func() { var count = 1; return func() { count += 1; }; } func main() {}",
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "reject storing a callback beyond a captured block" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Foo {
        \\    var callback:func()
        \\    func set_callback(callback:func()) { self.callback = callback }
        \\}
        \\func main() {
        \\    var foo = Foo(callback:func() {})
        \\    if (true) {
        \\        var count = 1
        \\        foo.set_callback(func() { count += 1 })
        \\    }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    try std.testing.expectError(
        error.InvalidSource,
        analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())),
    );
    try std.testing.expectEqualStrings(
        "capturing callback cannot be stored in a receiver that outlives one of its captures",
        analyzer.diagnostic.?.message,
    );
}

test "reject incompatible lambda signature" {
    try expectSemanticError(
        "func main() { var callback:func(int) int = func(value:str) int { return 1; }; }",
        "expected 'func', found 'func'",
    );
}

test "reject missing default function value" {
    try expectSemanticError(
        "func main() { var callback:func(); }",
        "a function value requires an initializer",
    );
}

test "reject equality of function values" {
    try expectSemanticError(
        "func main() { var callback = func() {}; let same = callback == callback; }",
        "function values and values containing them are not comparable",
    );
}

test "reject extracting an owner callback beyond its owner" {
    try expectSemanticError(
        \\struct Foo { var callback:func() }
        \\func invalid(foo:Foo) func() { return foo.callback }
        \\func main() {}
    ,
        "capturing function value cannot be returned from its lexical scope",
    );
}

test "reject function values at the native boundary" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_hook(callback:func()) void; func main() {}");
    const parsed = try parser.parse();
    const functions = try allocator.dupe(Ast.Function, parsed.functions);
    functions[0].name = "Test.native_hook";
    var program = parsed;
    program.functions = functions;
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings(
        "native parameter 'callback' cannot use 'func'",
        analyzer.diagnostic.?.message,
    );
}

test "reject storing a capturing lambda in a longer-lived collection" {
    try expectSemanticError(
        \\func main() {
        \\    var callbacks:func()[] = []
        \\    if (true) {
        \\        var count = 1
        \\        callbacks.append(func() { count += 1 })
        \\    }
        \\}
    ,
        "capturing function value cannot be stored in a longer-lived collection",
    );
}

test "read borrows preserve owners and support overloads" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\struct Resource {
        \\    var handle:int
        \\    func get_handle() int { return self.handle }
        \\    drop {}
        \\}
        \\func inspect(value:int) int { return value }
        \\func inspect(borrow value:int) int { return value + 1 }
        \\func describe(borrow resource:Resource) int { return resource.get_handle() }
        \\func forward(borrow resource:Resource) int { return describe(borrow resource) }
        \\func pair(borrow left:Resource, borrow right:Resource) int { return left.get_handle() + right.get_handle() }
        \\func main() {
        \\    var resource = Resource(handle:4)
        \\    let copied = inspect(4)
        \\    let borrowed = inspect(borrow copied)
        \\    let described = describe(borrow resource)
        \\    let forwarded = forward(borrow resource)
        \\    let paired = pair(borrow resource, borrow resource)
        \\    let temporary = describe(borrow Resource(handle:5))
        \\    let moved = move resource
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.functions[2].parameters[0].mode);
    try std.testing.expect(program.functions[5].statements[2].variable_declaration.initializer.value == .call);
}

test "read borrows reject mutation conflicts and escape" {
    const resource =
        \\struct Resource {
        \\    var handle:int
        \\    func get_handle() int { return self.handle }
        \\    func increment() { self.handle += 1 }
        \\    drop {}
        \\}
    ;
    try expectResolvedSemanticError(
        resource ++ "func invalid(borrow value:Resource) { value.increment() } func main() {}",
        "cannot call mutating method 'increment' on immutable value 'value'",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(borrow value:Resource) Resource { return value } func main() {}",
        "a 'borrow' parameter cannot be returned from its call",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(borrow value:Resource) { let callback = func() { print(value.handle) } } func main() {}",
        "a 'borrow' parameter cannot be captured by a lambda",
    );
    try expectResolvedSemanticError(
        "struct Data { var value:int } struct Holder { var saved:Data; func save(borrow value:Data) { self.saved = value } } func main() {}",
        "a 'borrow' parameter cannot be stored beyond its call",
    );
    try expectResolvedSemanticError(
        "struct Holder { var saved:int[]; func save(borrow value:int) { self.saved.append(value) } } func main() {}",
        "a 'borrow' parameter cannot be stored beyond its call",
    );
    try expectResolvedSemanticError(
        resource ++ "func invalid(borrow value:Resource) { let moved = move value } func main() {}",
        "a 'borrow' parameter cannot be consumed with 'move'",
    );
    try expectResolvedSemanticError(
        resource ++ "func conflict(borrow first:Resource, second:Resource) {} func main() { let value = Resource(handle:1); conflict(borrow value, move value) }",
        "cannot move borrowed noncopyable value 'value'",
    );
    try expectResolvedSemanticError(
        "func conflict(borrow first:int, second:&int) {} func main() { var value = 1; conflict(borrow value, &value) }",
        "cannot pass a value with '&' while it is read-borrowed",
    );
    try expectResolvedSemanticError(
        "func conflict(first:&int, borrow second:int) {} func main() { var value = 1; conflict(&value, borrow value) }",
        "cannot read-borrow a value while it is mutably borrowed",
    );
    try expectResolvedSemanticError(
        "class Shared {} func inspect(borrow value:Shared) {} func main() {}",
        "class 'Shared' already has shared identity; parameter mode 'borrow' is invalid",
    );
    try expectResolvedSemanticError(
        "protocol Shared { func read() } func inspect(borrow value:Shared) {} func main() {}",
        "a dynamic protocol value cannot be passed with 'borrow'",
    );
}

test "native functions reject read borrow parameters" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator, "native func native_inspect(borrow value:int) void; func main() {}");
    const parsed = try parser.parse();
    const functions = try allocator.dupe(Ast.Function, parsed.functions);
    functions[0].name = "Test.native_inspect";
    var program = parsed;
    program.functions = functions;
    var analyzer = Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Test"};
    try std.testing.expectError(error.InvalidSource, analyzer.analyze(program));
    try std.testing.expectEqualStrings(
        "a native function cannot declare a 'borrow' parameter",
        analyzer.diagnostic.?.message,
    );
}

test "protocol requirements preserve read borrow modes" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = Parser.init(allocator,
        \\protocol Reader { func read(borrow value:int) int }
        \\struct Counter : Reader {
        \\    func read(borrow value:int) int { return value + 1 }
        \\}
        \\func main() { let counter = Counter(); let result = counter.read(borrow 1) }
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse()));
    try std.testing.expectEqual(Ast.ParameterMode.borrow, program.protocols[0].requirements[0].parameter_modes[0]);

    try expectResolvedSemanticError(
        "protocol Reader { func read(borrow value:int) int } struct Counter : Reader { func read(value:int) int { return value } } func main() {}",
        "type 'Counter' does not satisfy method 'read' required by protocol 'Reader'",
    );
}
