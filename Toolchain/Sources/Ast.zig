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
    multiply,
    divide,
};

pub const UnaryOperator = enum {
    logical_not,
    numeric_negate,
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
        string: []const u8,
        identifier: []const u8,
        self,
        call: Call,
        method_call: MethodCall,
        structure_initializer: StructureInitializer,
        member_access: MemberAccess,
        unary: Unary,
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
    };

    pub const MethodCall = struct {
        object: *Expression,
        name: []const u8,
        name_position: Source.Position,
        arguments: []const *Expression,
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

    pub const Binary = struct {
        operator: BinaryOperator,
        operator_position: Source.Position,
        left: *Expression,
        right: *Expression,
    };
};

pub const Statement = union(enum) {
    print: Print,
    variable_declaration: VariableDeclaration,
    assignment: Assignment,
    if_statement: If,
    while_statement: While,
    return_statement: Return,
    expression_statement: *Expression,

    pub const Print = struct {
        position: Source.Position,
        argument: *Expression,
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
        condition: *Expression,
        body: []const Statement,
        else_body: ?[]const Statement,
    };

    pub const While = struct {
        position: Source.Position,
        condition: *Expression,
        body: []const Statement,
    };

    pub const Return = struct {
        position: Source.Position,
        value: ?*Expression,
    };
};

pub const Program = struct {
    structures: []const Structure,
    functions: []const Function,
};

pub const Structure = struct {
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
};

pub const Function = struct {
    position: Source.Position,
    name: []const u8,
    name_position: Source.Position,
    return_type: ReturnType,
    parameters: []const Parameter,
    statements: []const Statement,
};
