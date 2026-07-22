pub const std = @import("std");
pub const Ast = @import("../Ast.zig");
pub const Source = @import("../Source.zig");

pub const Allocator = std.mem.Allocator;
pub const AnalyzeError = Source.Error || Allocator.Error;
pub const never_capture_box = false;
pub const DeferredResourcePath = []const []const u8;

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
    view: *const Type,
    reference: ReferenceType,
    function: FunctionType,
    optional: *const Type,
    null,
};

pub const FunctionType = struct {
    deferred: bool = false,
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

pub const BindingState = struct {
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
    resource_dependencies: []const *BindingState = &.{},
    resource_dependents: usize = 0,
    deferred_resource_paths: []const DeferredResourcePath = &.{},
};

pub const Borrow = struct {
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
    owner_state: ?*BindingState = null,
    resource_dependencies: []const *BindingState = &.{},
    transfers_resource_dependencies: bool = false,
    deferred_resource_paths: []const DeferredResourcePath = &.{},
    deferred_storage_state: ?*BindingState = null,
    deferred_storage_path: DeferredResourcePath = &.{},
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
        function_reference: []const u8,
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
        native_return_structure: ?NativeStructureTransport = null,
        native_result: ?NativeResultTransport = null,
        native_parameter_structures: []const ?NativeStructureTransport = &.{},
        native_parameter_modes: []const Ast.ParameterMode = &.{},
        borrowed_return_parameter: ?usize = null,
        is_native_resource_drop: bool = false,
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
            source_name: []const u8 = "",
            position: Source.Position = .{ .line = 1, .column = 1 },
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
        borrowed: bool = false,
        mutable: bool = false,
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
        source_name: []const u8 = "",
        position: Source.Position = .{ .line = 1, .column = 1 },
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
        source_name: []const u8 = "",
        position: Source.Position = .{ .line = 1, .column = 1 },
        source: *Expression,
        temporary_name: []const u8,
        generated_name: []const u8,
        type: Type,
        mode: TransferMode,
        mutability: Ast.Mutability,
        capture_box: *const bool,
    };

    pub const For = struct {
        source_name: []const u8 = "",
        position: Source.Position = .{ .line = 1, .column = 1 },
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
    source_name: []const u8,
    generated_name: []const u8,
    is_class: bool,
    is_owner: bool = false,
    is_native_resource: bool = false,
    native_module_name: ?[]const u8 = null,
    native_drop_name: ?[]const u8 = null,
    native_drop_symbol: ?[]const u8 = null,
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
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    visibility: Ast.MemberVisibility,
    mutability: Ast.Mutability,
    initializer: ?*Expression,
    reset_value: ?*Expression = null,
};

pub const NativeStructureTransport = struct {
    source_name: []const u8,
    generated_name: []const u8,
    fields: []const NativeTransportField,
    is_native_resource: bool = false,
    native_module_name: ?[]const u8 = null,
    native_drop_name: ?[]const u8 = null,
    native_drop_symbol: ?[]const u8 = null,
};

pub const NativeTransportField = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
};

pub const NativeResultTransport = struct {
    enum_generated_name: []const u8,
    success_type: Type,
    failure_type: Type,
    success_structure: ?NativeStructureTransport,
    failure_structure: ?NativeStructureTransport,
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
    source_name: []const u8 = "",
    position: Source.Position = .{ .line = 1, .column = 1 },
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
    is_native_resource_drop: bool,
    native_module_name: ?[]const u8,
    native_function_name: ?[]const u8,
    borrowed_return_parameter: ?usize = null,
    deferred_callback_index: ?usize = null,
};

pub const Method = struct {
    generated_name: []const u8,
    return_type: Type,
    parameters: []const Parameter,
    statements: []const Statement,
    is_mutating: bool,
    requires_mutable_codegen: bool,
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

pub const Symbol = struct {
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

pub const Scope = struct {
    parent: ?*const Scope,
    depth: usize,
    symbols: std.ArrayList(Symbol) = .empty,
    borrows: std.ArrayList(Borrow) = .empty,
};

pub const OwnerStateSnapshot = struct {
    name: []const u8,
    state: *BindingState,
    available: bool,
    consumed_at: ?Source.Position,
    lifetime_depth: usize,
    deferred_resource_paths: []const DeferredResourcePath,
};

pub const LoopFlow = struct {
    tracked: []const OwnerStateSnapshot,
    break_states: std.ArrayList([]const OwnerStateSnapshot) = .empty,
    continue_states: std.ArrayList([]const OwnerStateSnapshot) = .empty,
};

pub const LambdaContext = struct {
    local_depth: usize,
    captures: std.ArrayList(Expression.Lambda.Capture) = .empty,
    captures_self: bool = false,
    owner_self: bool = false,
    lifetime_depth: usize = 0,
    parent: ?*LambdaContext,
};

pub fn releaseBorrow(borrow: Borrow) void {
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

pub const FunctionSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    parameter_stored: []const bool,
    position: Source.Position,
    is_main: bool,
    is_native: bool,
    is_native_resource_drop: bool,
    native_module_name: ?[]const u8,
    native_function_name: ?[]const u8,
    return_dependency_parameters: []const usize = &.{},
    return_deferred_resource_paths: []const DeferredResourcePath = &.{},
    return_borrow_parameter: ?usize = null,
    deferred_callback_index: ?usize = null,
};

pub const StructureSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    is_class: bool,
    is_owner: bool,
    is_native_resource: bool,
    native_module_name: ?[]const u8,
    native_drop_name: ?[]const u8,
    native_drop_symbol: ?[]const u8,
    is_generic: bool,
    module_files: []const usize,
    base_index: ?usize,
    protocol_conformances: []const ProtocolConformanceSymbol,
    fields: []StructureFieldSymbol,
    static_fields: []StructureFieldSymbol,
    constructors: []ConstructorSymbol,
    methods: []MethodSymbol,
    position: Source.Position,
};

pub const ProtocolConformanceSymbol = struct {
    protocol_index: usize,
    position: Source.Position,
    extension_visible_files: ?[]const usize,
    extension_module_name: ?[]const u8,
};

pub const ProtocolSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    requirements: []const ProtocolRequirement,
    position: Source.Position,
};

pub const ProtocolRequirement = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    position: Source.Position,
};

pub const EnumSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    raw_type: ?Type,
    variants: []const EnumVariantSymbol,
    position: Source.Position,
};

pub const EnumVariantSymbol = struct {
    source_name: []const u8,
    associated_types: []const Type,
    raw_value: ?*Expression,
    position: Source.Position,
};

pub const ConstructorSymbol = struct {
    parameter_types: []const Type,
    parameter_modes: []const Ast.ParameterMode,
    parameter_stored: []const bool,
    position: Source.Position,
    visibility: Ast.MemberVisibility,
};

pub const ConstructorCandidate = struct {
    symbol: ConstructorSymbol,
    index: usize,
};

pub const ImplicitBaseInitialization = struct {
    available: bool,
    initializer: ?BaseInitializer,
};

pub const MethodSymbol = struct {
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
    return_borrow_parameter: ?usize = null,
    direct_mutation: bool = false,
    direct_mutable_codegen: bool = false,
    dependencies: []const MethodId = &.{},
    is_mutating: bool = false,
    requires_mutable_codegen: bool = false,
};

pub const MethodCandidate = struct {
    symbol: MethodSymbol,
    structure_index: usize,
    index: usize,
};

pub fn methodCandidatesContainSlot(candidates: []const MethodCandidate, generated_name: []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate.symbol.generated_name, generated_name)) return true;
    }
    return false;
}

pub fn fileSetContains(files: []const usize, target: usize) bool {
    for (files) |file| if (file == target) return true;
    return false;
}

pub fn fileSetsOverlap(left: []const usize, right: []const usize) bool {
    for (left) |file| if (fileSetContains(right, file)) return true;
    return false;
}

pub fn visibilityRank(visibility: Ast.MemberVisibility) u2 {
    return switch (visibility) {
        .private_access => 0,
        .subclass => 1,
        .public_access => 2,
    };
}

pub const FieldCandidate = struct {
    symbol: StructureFieldSymbol,
    structure_index: usize,
};

pub const StructureFieldSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    position: Source.Position,
    ast_initializer: ?*Ast.Expression,
    visibility: Ast.MemberVisibility,
    mutability: Ast.Mutability,
    default_value: ?*Expression = null,
};

pub const FieldInitialization = enum {
    uninitialized,
    maybe_initialized,
    initialized,
};
