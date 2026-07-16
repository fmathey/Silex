const Source = @import("Source.zig");

pub const BinaryOperator = enum {
    logical_or,
    logical_and,
    equal,
    not_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    add,
    subtract,
    shift_left,
    shift_right,
    bit_and,
    bit_xor,
    multiply,
    divide,
    remainder,
};

pub const UnaryOperator = enum {
    logical_not,
    numeric_negate,
    dereference,
    borrow,
};

pub const TypeName = union(enum) {
    int,
    int8,
    int16,
    int32,
    int64,
    uint,
    uint8,
    uint16,
    uint32,
    uint64,
    float,
    float32,
    float64,
    bool,
    str,
    structure: []const u8,
    list: *TypeName,
    fixed_array: FixedArray,
    reference: Reference,
    function: FunctionType,
    optional: *TypeName,

    pub const FixedArray = struct {
        element: *TypeName,
        length: []const u8,
    };

    pub const Reference = struct {
        target: *TypeName,
        mutable: bool,
    };

    pub const FunctionType = struct {
        parameters: []const TypeName,
        parameter_is_mutable_references: []const bool,
        return_type: ?*TypeName,
    };
};

pub const ReturnType = union(enum) {
    void,
    int,
    int8,
    int16,
    int32,
    int64,
    uint,
    uint8,
    uint16,
    uint32,
    uint64,
    float,
    float32,
    float64,
    bool,
    str,
    structure: []const u8,
    list: *TypeName,
    fixed_array: TypeName.FixedArray,
    reference: TypeName.Reference,
    function: TypeName.FunctionType,
    optional: *TypeName,
};

pub const Mutability = enum {
    immutable,
    mutable,
};

pub const AssignmentOperator = enum {
    assign,
    add,
    subtract,
    multiply,
    divide,
    increment,
    decrement,
};

pub const Expression = struct {
    position: Source.Position,
    value: union(enum) {
        integer: []const u8,
        floating: []const u8,
        boolean: bool,
        null,
        string: []const u8,
        sequence_literal: []const *Expression,
        identifier: []const u8,
        self,
        call: Call,
        value_call: ValueCall,
        lambda: Lambda,
        method_call: MethodCall,
        cascade: Cascade,
        structure_initializer: StructureInitializer,
        member_access: MemberAccess,
        safe_member_access: SafeMemberAccess,
        index_access: IndexAccess,
        slice_access: SliceAccess,
        unary: Unary,
        conversion: Conversion,
        binary: Binary,
    },

    pub const Unary = struct {
        operator: UnaryOperator,
        operator_position: Source.Position,
        operand: *Expression,
    };

    pub const Call = struct {
        name: []const u8,
        name_position: Source.Position,
        arguments: []const *Expression,
        named_fields: ?[]const FieldInitializer = null,
        visible_declarations: ?[]const Source.Position = null,
    };

    pub const ValueCall = struct {
        callee: *Expression,
        parenthesis_position: Source.Position,
        arguments: []const *Expression,
    };

    pub const Lambda = struct {
        position: Source.Position,
        parameters: []const Parameter,
        return_type: ReturnType,
        statements: []const Statement,
    };

    pub const MethodCall = struct {
        object: *Expression,
        name: []const u8,
        name_position: Source.Position,
        arguments: []const *Expression,
        named_fields: ?[]const FieldInitializer = null,
    };

    pub const Cascade = struct {
        object: *Expression,
        operations: []const Operation,

        pub const Operation = union(enum) {
            method_call: CascadeMethodCall,
            field_assignment: FieldAssignment,
        };

        pub const CascadeMethodCall = struct {
            name: []const u8,
            name_position: Source.Position,
            arguments: []const *Expression,
        };

        pub const FieldAssignment = struct {
            name: []const u8,
            name_position: Source.Position,
            value: *Expression,
        };
    };

    pub const StructureInitializer = struct {
        name: []const u8,
        name_position: Source.Position,
        fields: []const FieldInitializer,
    };

    pub const FieldInitializer = struct {
        name: []const u8,
        position: Source.Position,
        value: *Expression,
    };

    pub const MemberAccess = struct {
        object: *Expression,
        name: []const u8,
        name_position: Source.Position,
    };

    pub const SafeMemberAccess = struct {
        object: *Expression,
        name: []const u8,
        name_position: Source.Position,
        arguments: ?[]const *Expression = null,
        named_fields: ?[]const FieldInitializer = null,
    };

    pub const IndexAccess = struct {
        object: *Expression,
        index: *Expression,
        bracket_position: Source.Position,
    };

    pub const SliceAccess = struct {
        object: *Expression,
        start: *Expression,
        end: *Expression,
        bracket_position: Source.Position,
    };

    pub const Conversion = struct {
        operand: *Expression,
        target_type: TypeName,
        as_position: Source.Position,
    };

    pub const Binary = struct {
        operator: BinaryOperator,
        operator_position: Source.Position,
        left: *Expression,
        right: *Expression,
    };
};

pub const Statement = union(enum) {
    print: Print,
    assertion: Assert,
    panic_statement: Panic,
    variable_declaration: VariableDeclaration,
    assignment: Assignment,
    if_statement: If,
    while_statement: While,
    for_statement: For,
    break_statement: Source.Position,
    continue_statement: Source.Position,
    return_statement: Return,
    expression_statement: *Expression,

    pub const Print = struct {
        position: Source.Position,
        argument: *Expression,
    };

    pub const Assert = struct {
        position: Source.Position,
        condition: *Expression,
        message: *Expression,
    };

    pub const Panic = struct {
        position: Source.Position,
        message: *Expression,
    };

    pub const VariableDeclaration = struct {
        position: Source.Position,
        name: []const u8,
        name_position: Source.Position,
        mutability: Mutability,
        annotation: ?TypeName,
        initializer: ?*Expression,
    };

    pub const Assignment = struct {
        position: Source.Position,
        target: *Expression,
        operator: AssignmentOperator,
        value: ?*Expression,
    };

    pub const If = struct {
        position: Source.Position,
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
        position: Source.Position,
        condition: Condition,
        body: []const Statement,
    };

    pub const Condition = union(enum) {
        expression: *Expression,
        binding: ConditionalBinding,
    };

    pub const ConditionalBinding = struct {
        position: Source.Position,
        name: []const u8,
        name_position: Source.Position,
        mutability: Mutability,
        source: *Expression,
    };

    pub const For = struct {
        position: Source.Position,
        name: []const u8,
        name_position: Source.Position,
        mutability: Mutability,
        source: IterationSource,
        body: []const Statement,

        pub const IterationSource = union(enum) {
            collection: *Expression,
            integer_range: IntegerRange,
        };

        pub const IntegerRange = struct {
            start: *Expression,
            end: *Expression,
        };
    };

    pub const Return = struct {
        position: Source.Position,
        value: ?*Expression,
    };
};

pub const Program = struct {
    imports: []const Import = &.{},
    uses: []const Use = &.{},
    structures: []const Structure,
    functions: []const Function,
};

pub const Import = struct {
    path: []const u8,
    alias: ?[]const u8,
    position: Source.Position,
};

pub const Use = struct {
    path: []const u8,
    alias: ?[]const u8,
    is_public: bool,
    position: Source.Position,
};

pub const Structure = struct {
    is_public: bool = false,
    is_class: bool = false,
    position: Source.Position,
    name: []const u8,
    name_position: Source.Position,
    fields: []const StructureField,
    methods: []const Function,
};

pub const StructureField = struct {
    name: []const u8,
    position: Source.Position,
    type: TypeName,
    initializer: ?*Expression,
};

pub const Parameter = struct {
    name: []const u8,
    position: Source.Position,
    type: TypeName,
    is_mutable_reference: bool = false,
};

pub const Function = struct {
    is_public: bool = false,
    is_native: bool = false,
    position: Source.Position,
    name: []const u8,
    name_position: Source.Position,
    return_type: ReturnType,
    parameters: []const Parameter,
    statements: []const Statement,
};
