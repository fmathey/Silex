const std = @import("std");
const Ast = @import("Ast.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const AnalyzeError = Source.Error || Allocator.Error;

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
    list: *const Type,
    fixed_array: FixedArrayType,
    reference: ReferenceType,
};

pub const StructureType = struct {
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
    moved: bool = false,
    immutable_borrows: usize = 0,
    mutable_borrow: bool = false,
    reference: ?Borrow = null,
};

const Borrow = struct {
    root: ?*BindingState,
    mutable: bool,
};

pub const Expression = struct {
    type: Type,
    position: Source.Position,
    borrow: ?Borrow = null,
    owns_borrow: bool = false,
    value: union(enum) {
        integer: u64,
        floating: []const u8,
        boolean: bool,
        string: []const u8,
        string_length: *Expression,
        sequence_literal: []const *Expression,
        collection_method: CollectionMethod,
        cascade_target,
        cascade: Cascade,
        variable: []const u8,
        self,
        call: Call,
        method_call: MethodCall,
        structure_initializer: StructureInitializer,
        member_access: MemberAccess,
        index_access: IndexAccess,
        unary: Unary,
        binary: Binary,
        conversion: Conversion,
    },

    pub const Unary = struct {
        operator: Ast.UnaryOperator,
        operand: *Expression,
    };

    pub const Call = struct {
        generated_name: []const u8,
        arguments: []const *Expression,
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

    pub const MemberAccess = struct {
        object: *Expression,
        generated_name: []const u8,
    };

    pub const IndexAccess = struct {
        object: *Expression,
        index: *Expression,
        from_end: bool,
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
};

pub const Statement = union(enum) {
    print: *Expression,
    variable_declaration: VariableDeclaration,
    assignment: Assignment,
    if_statement: If,
    while_statement: While,
    for_statement: For,
    break_statement,
    continue_statement,
    return_statement: ?*Expression,
    expression_statement: *Expression,

    pub const VariableDeclaration = struct {
        generated_name: []const u8,
        type: Type,
        mutability: Ast.Mutability,
        initializer: *Expression,
    };

    pub const Assignment = struct {
        position: Source.Position,
        target: *Expression,
        operator: Ast.AssignmentOperator,
        value: ?*Expression,
    };

    pub const If = struct {
        condition: *Expression,
        body: []const Statement,
        else_body: ?[]const Statement,
    };

    pub const While = struct {
        condition: *Expression,
        body: []const Statement,
    };

    pub const For = struct {
        generated_name: []const u8,
        element_type: Type,
        mutable: bool,
        iterable: *Expression,
        body: []const Statement,
    };
};

pub const Program = struct {
    structures: []const Structure,
    functions: []const Function,
};

pub const Structure = struct {
    generated_name: []const u8,
    fields: []const StructureField,
    methods: []Method,
};

pub const StructureField = struct {
    generated_name: []const u8,
    type: Type,
};

pub const Parameter = struct {
    generated_name: []const u8,
    type: Type,
};

pub const Function = struct {
    generated_name: []const u8,
    return_type: Type,
    parameters: []const Parameter,
    statements: []const Statement,
    is_main: bool,
};

pub const Method = struct {
    generated_name: []const u8,
    return_type: Type,
    parameters: []const Parameter,
    statements: []const Statement,
    is_mutating: bool,
};

pub const MethodId = struct {
    structure_index: usize,
    method_index: usize,
};

pub const Receiver = union(enum) {
    self,
    borrowed_self,
    mutable,
    immutable: []const u8,
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
    movable: bool = true,
};

const Scope = struct {
    parent: ?*const Scope,
    symbols: std.ArrayList(Symbol) = .empty,
    borrows: std.ArrayList(Borrow) = .empty,
};

fn releaseBorrow(borrow: Borrow) void {
    const root = borrow.root orelse return;
    if (borrow.mutable) {
        root.mutable_borrow = false;
    } else {
        root.immutable_borrows -= 1;
    }
}

const FunctionSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    position: Source.Position,
    is_main: bool,
};

const StructureSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    fields: []StructureFieldSymbol,
    methods: []MethodSymbol,
    position: Source.Position,
};

const MethodSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    return_type: Type,
    parameter_types: []const Type,
    position: Source.Position,
    direct_mutation: bool = false,
    dependencies: []const MethodId = &.{},
    is_mutating: bool = false,
};

const StructureFieldSymbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    position: Source.Position,
    ast_initializer: ?*Ast.Expression,
    default_value: ?*Expression = null,
};

pub const Analyzer = struct {
    allocator: Allocator,
    next_symbol_id: usize = 0,
    functions: std.ArrayList(FunctionSymbol) = .empty,
    structures: std.ArrayList(StructureSymbol) = .empty,
    current_return_type: Type = .void,
    current_structure_index: ?usize = null,
    current_method_index: ?usize = null,
    current_method_direct_mutation: bool = false,
    current_method_dependencies: std.ArrayList(MethodId) = .empty,
    current_self_state: BindingState = .{},
    loop_depth: usize = 0,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator) Analyzer {
        return .{ .allocator = allocator };
    }

    pub fn analyze(self: *Analyzer, program: Ast.Program) !Program {
        try self.collectStructures(program.structures);
        try self.collectFunctions(program.functions);
        try self.validateStructureDefaults();
        var structures: std.ArrayList(Structure) = .empty;
        for (program.structures, self.structures.items, 0..) |ast_structure, symbol, structure_index| {
            var fields: std.ArrayList(StructureField) = .empty;
            for (symbol.fields) |field| try fields.append(self.allocator, .{
                .generated_name = field.generated_name,
                .type = field.type,
            });
            var methods: std.ArrayList(Method) = .empty;
            for (ast_structure.methods, symbol.methods, 0..) |ast_method, method_symbol, method_index| {
                try methods.append(self.allocator, try self.method(ast_method, method_symbol, structure_index, method_index));
            }
            try structures.append(self.allocator, .{
                .generated_name = symbol.generated_name,
                .fields = try fields.toOwnedSlice(self.allocator),
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
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
        try self.validateMethodCalls(result);
        return result;
    }

    fn collectStructures(self: *Analyzer, ast_structures: []const Ast.Structure) AnalyzeError!void {
        for (ast_structures, 0..) |ast_structure, structure_index| {
            if (self.findStructure(ast_structure.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' is already declared", .{ast_structure.name});
                return self.fail(ast_structure.name_position, message);
            }
            try self.structures.append(self.allocator, .{
                .source_name = ast_structure.name,
                .generated_name = try std.fmt.allocPrint(self.allocator, "SilexStruct{d}", .{structure_index}),
                .fields = &.{},
                .methods = &.{},
                .position = ast_structure.name_position,
            });
        }

        for (ast_structures, 0..) |ast_structure, structure_index| {
            var fields: std.ArrayList(StructureFieldSymbol) = .empty;
            for (ast_structure.fields, 0..) |field, field_index| {
                for (fields.items) |existing| {
                    if (std.mem.eql(u8, existing.source_name, field.name)) {
                        const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is already declared in struct '{s}'", .{ field.name, ast_structure.name });
                        return self.fail(field.position, message);
                    }
                }
                const field_type = try typeFromAnnotation(self, field.type, field.position);
                if (field_type == .reference) return self.fail(field.position, "a struct field cannot have a reference type");
                if (field_type == .structure) {
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
                try fields.append(self.allocator, .{
                    .source_name = field.name,
                    .generated_name = try std.fmt.allocPrint(self.allocator, "field{d}", .{field_index}),
                    .type = field_type,
                    .position = field.position,
                    .ast_initializer = field.initializer,
                });
            }
            self.structures.items[structure_index].fields = try fields.toOwnedSlice(self.allocator);

            var methods: std.ArrayList(MethodSymbol) = .empty;
            for (ast_structure.methods, 0..) |ast_method, method_index| {
                for (methods.items) |existing| {
                    if (std.mem.eql(u8, existing.source_name, ast_method.name)) {
                        const message = try std.fmt.allocPrint(self.allocator, "method '{s}' is already declared in struct '{s}'", .{ ast_method.name, ast_structure.name });
                        return self.fail(ast_method.name_position, message);
                    }
                }
                var parameter_types: std.ArrayList(Type) = .empty;
                for (ast_method.parameters) |parameter| {
                    try parameter_types.append(self.allocator, try typeFromAnnotation(self, parameter.type, parameter.position));
                }
                const return_type = try typeFromReturn(self, ast_method.return_type, ast_method.position);
                if (return_type == .reference) return self.fail(ast_method.position, "a method cannot return a reference");
                try methods.append(self.allocator, .{
                    .source_name = ast_method.name,
                    .generated_name = try std.fmt.allocPrint(self.allocator, "method{d}", .{method_index}),
                    .return_type = return_type,
                    .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
                    .position = ast_method.name_position,
                });
            }
            self.structures.items[structure_index].methods = try methods.toOwnedSlice(self.allocator);
        }
    }

    fn collectFunctions(self: *Analyzer, ast_functions: []const Ast.Function) AnalyzeError!void {
        var main_count: usize = 0;
        for (ast_functions, 0..) |ast_function, index| {
            if (self.findFunction(ast_function.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "function '{s}' is already declared", .{ast_function.name});
                return self.fail(ast_function.name_position, message);
            }
            const is_main = std.mem.eql(u8, ast_function.name, "main");
            if (is_main) main_count += 1;
            var parameter_types: std.ArrayList(Type) = .empty;
            for (ast_function.parameters) |parameter| try parameter_types.append(self.allocator, try typeFromAnnotation(self, parameter.type, parameter.position));
            const return_type = try typeFromReturn(self, ast_function.return_type, ast_function.position);
            if (return_type == .reference) return self.fail(ast_function.position, "a function cannot return a reference");
            try self.functions.append(self.allocator, .{
                .source_name = ast_function.name,
                .generated_name = if (is_main) "main" else try std.fmt.allocPrint(self.allocator, "silexFunction{d}", .{index}),
                .return_type = return_type,
                .parameter_types = try parameter_types.toOwnedSlice(self.allocator),
                .position = ast_function.name_position,
                .is_main = is_main,
            });
        }
        if (main_count == 0) return self.fail(.{ .line = 1, .column = 1 }, "missing 'main' function");
        const main = self.findFunction("main").?;
        if (!typeEqual(main.return_type, .void) or main.parameter_types.len != 0) {
            return self.fail(main.position, "'main' must have return type 'void' and no parameters");
        }
    }

    fn validateStructureDefaults(self: *Analyzer) AnalyzeError!void {
        self.current_structure_index = null;
        self.current_method_index = null;
        var empty_scope = Scope{ .parent = null };
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
            .list, .fixed_array => false,
            .reference => false,
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
                "default field value must be a literal or struct initializer of type '{s}'",
                .{typeName(expected_type)},
            );
            return self.fail(ast.position, message);
        }
    }

    fn function(self: *Analyzer, ast: Ast.Function, symbol: FunctionSymbol) AnalyzeError!Function {
        self.current_structure_index = null;
        self.current_method_index = null;
        self.current_self_state = .{};
        self.loop_depth = 0;
        var scope = Scope{ .parent = null };
        var parameters: std.ArrayList(Parameter) = .empty;
        for (ast.parameters, symbol.parameter_types) |parameter, parameter_type| {
            if (findInCurrentScope(&scope, parameter.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
                return self.fail(parameter.position, message);
            }
            const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            try scope.symbols.append(self.allocator, .{ .source_name = parameter.name, .generated_name = generated_name, .type = parameter_type, .mutability = .immutable, .state = try self.newBindingState(parameter_type) });
            try parameters.append(self.allocator, .{ .generated_name = generated_name, .type = parameter_type });
        }
        self.current_return_type = symbol.return_type;
        const function_statements = try self.statements(ast.statements, &scope);
        self.releaseScopeBorrows(&scope);
        if (!typeEqual(symbol.return_type, .void) and !blockAlwaysReturns(function_statements)) {
            const message = try std.fmt.allocPrint(self.allocator, "function '{s}' must return '{s}' on every path", .{ ast.name, typeName(symbol.return_type) });
            return self.fail(ast.name_position, message);
        }
        return .{ .generated_name = symbol.generated_name, .return_type = symbol.return_type, .parameters = try parameters.toOwnedSlice(self.allocator), .statements = function_statements, .is_main = symbol.is_main };
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
        self.current_method_direct_mutation = false;
        self.current_method_dependencies = .empty;
        self.current_self_state = .{};
        self.loop_depth = 0;

        var scope = Scope{ .parent = null };
        var parameters: std.ArrayList(Parameter) = .empty;
        for (ast.parameters, symbol.parameter_types) |parameter, parameter_type| {
            if (findInCurrentScope(&scope, parameter.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
                return self.fail(parameter.position, message);
            }
            const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            try scope.symbols.append(self.allocator, .{
                .source_name = parameter.name,
                .generated_name = generated_name,
                .type = parameter_type,
                .mutability = .immutable,
                .state = try self.newBindingState(parameter_type),
            });
            try parameters.append(self.allocator, .{ .generated_name = generated_name, .type = parameter_type });
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
        };
    }

    fn statements(
        self: *Analyzer,
        ast_statements: []const Ast.Statement,
        scope: *Scope,
    ) AnalyzeError![]const Statement {
        var result: std.ArrayList(Statement) = .empty;
        for (ast_statements) |ast_statement| {
            try result.append(self.allocator, try self.statement(ast_statement, scope));
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
            .variable_declaration => |declaration| self.variableDeclaration(declaration, scope),
            .assignment => |ast_assignment| self.assignment(ast_assignment, scope),
            .if_statement => |if_statement| self.ifStatement(if_statement, scope),
            .while_statement => |while_statement| self.whileStatement(while_statement, scope),
            .for_statement => |for_statement| self.forStatement(for_statement, scope),
            .break_statement => |position| loop_control: {
                if (self.loop_depth == 0) return self.fail(position, "'break' is only available inside a loop");
                break :loop_control .break_statement;
            },
            .continue_statement => |position| loop_control: {
                if (self.loop_depth == 0) return self.fail(position, "'continue' is only available inside a loop");
                break :loop_control .continue_statement;
            },
            .return_statement => |return_statement| self.returnStatement(return_statement, scope),
            .expression_statement => |expression_statement| .{ .expression_statement = try self.expression(expression_statement, scope) },
        };
    }

    fn variableDeclaration(
        self: *Analyzer,
        declaration: Ast.Statement.VariableDeclaration,
        scope: *Scope,
    ) AnalyzeError!Statement {
        if (findInCurrentScope(scope, declaration.name) != null) {
            const message = try std.fmt.allocPrint(
                self.allocator,
                "variable '{s}' is already declared in this scope",
                .{declaration.name},
            );
            return self.fail(declaration.name_position, message);
        }

        const declared_annotation_type = if (declaration.annotation) |annotation|
            try typeFromAnnotation(self, annotation, declaration.name_position)
        else
            null;
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

        if (declared_type == .reference and declaration.mutability == .mutable) {
            return self.fail(declaration.name_position, "a reference must be declared with 'let'");
        }
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        const state = try self.newBindingState(declared_type);
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
        });

        return .{ .variable_declaration = .{
            .generated_name = generated_name,
            .type = declared_type,
            .mutability = declaration.mutability,
            .initializer = initializer,
        } };
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
            return self.checkedAssignment(ast, target, value);
        }

        const root = assignmentRoot(ast.target) orelse return self.fail(ast.position, "invalid assignment target");
        var reinitializing_state: ?*BindingState = null;
        switch (root) {
            .self => {
                if (self.current_method_index == null) return self.fail(ast.position, "'self' is only available inside a method");
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
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "cannot assign to immutable variable '{s}'",
                        .{root_name},
                    );
                    return self.fail(ast.position, message);
                }
                if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow) {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{root_name});
                    return self.fail(ast.position, message);
                }
                if (symbol.state.moved) {
                    if (ast.operator != .assign) {
                        const message = try std.fmt.allocPrint(self.allocator, "cannot update moved variable '{s}'", .{root_name});
                        return self.fail(ast.position, message);
                    }
                    reinitializing_state = symbol.state;
                }
            },
        }

        if (reinitializing_state) |state| state.moved = false;
        const target = try self.expression(ast.target, scope);

        var value: ?*Expression = null;
        if (ast.value) |ast_value| value = try self.expressionForExpected(ast_value, scope, target.type);

        return self.checkedAssignment(ast, target, value);
    }

    fn checkedAssignment(
        self: *Analyzer,
        ast: Ast.Statement.Assignment,
        target: *Expression,
        initial_value: ?*Expression,
    ) AnalyzeError!Statement {
        var value = initial_value;
        switch (ast.operator) {
            .assign => {
                value = try self.coerce(value.?, target.type);
                if (!typeEqual(target.type, value.?.type)) {
                    const message = try typeMismatchMessage(self.allocator, target.type, value.?.type);
                    return self.fail(ast.value.?.position, message);
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

    fn ifStatement(
        self: *Analyzer,
        ast: Ast.Statement.If,
        parent_scope: *const Scope,
    ) AnalyzeError!Statement {
        const condition = try self.expression(ast.condition, parent_scope);
        if (!typeEqual(condition.type, .bool)) {
            const message = try typeMismatchMessage(self.allocator, .bool, condition.type);
            return self.fail(ast.condition.position, message);
        }

        var body_scope = Scope{ .parent = parent_scope };
        const body = try self.statements(ast.body, &body_scope);
        self.releaseScopeBorrows(&body_scope);

        var else_body: ?[]const Statement = null;
        if (ast.else_body) |ast_else_body| {
            var else_scope = Scope{ .parent = parent_scope };
            else_body = try self.statements(ast_else_body, &else_scope);
            self.releaseScopeBorrows(&else_scope);
        }

        return .{ .if_statement = .{
            .condition = condition,
            .body = body,
            .else_body = else_body,
        } };
    }

    fn whileStatement(
        self: *Analyzer,
        ast: Ast.Statement.While,
        parent_scope: *const Scope,
    ) AnalyzeError!Statement {
        const condition = try self.expression(ast.condition, parent_scope);
        if (!typeEqual(condition.type, .bool)) {
            const message = try typeMismatchMessage(self.allocator, .bool, condition.type);
            return self.fail(ast.condition.position, message);
        }

        var body_scope = Scope{ .parent = parent_scope };
        self.loop_depth += 1;
        defer self.loop_depth -= 1;
        const body = try self.statements(ast.body, &body_scope);
        self.releaseScopeBorrows(&body_scope);
        return .{ .while_statement = .{
            .condition = condition,
            .body = body,
        } };
    }

    fn forStatement(
        self: *Analyzer,
        ast: Ast.Statement.For,
        parent_scope: *const Scope,
    ) AnalyzeError!Statement {
        const iterable = try self.expression(ast.iterable, parent_scope);
        const element_type: Type = switch (iterable.type) {
            .list => |element| element.*,
            .fixed_array => |array| array.element.*,
            else => return self.fail(ast.iterable.position, "for source must be an array or list"),
        };

        const root = assignmentRoot(ast.iterable);
        var iteration_borrow: ?Borrow = null;
        if (root) |resolved_root| {
            const state: *BindingState = switch (resolved_root) {
                .self => &self.current_self_state,
                .variable => |name| (findSymbol(parent_scope, name) orelse return self.fail(ast.iterable.position, "unknown iteration source")).state,
            };
            if (ast.mutable) {
                switch (resolved_root) {
                    .self => self.current_method_direct_mutation = true,
                    .variable => |name| {
                        const symbol = findSymbol(parent_scope, name).?;
                        if (symbol.mutability == .immutable) {
                            const message = try std.fmt.allocPrint(self.allocator, "cannot iterate mutably over immutable variable '{s}'", .{name});
                            return self.fail(ast.iterable.position, message);
                        }
                    },
                }
                if (state.mutable_borrow or state.immutable_borrows != 0) {
                    return self.fail(ast.iterable.position, "cannot iterate mutably over an already borrowed collection");
                }
                state.mutable_borrow = true;
            } else {
                if (state.mutable_borrow) return self.fail(ast.iterable.position, "cannot iterate over a mutably borrowed collection");
                state.immutable_borrows += 1;
            }
            iteration_borrow = .{ .root = state, .mutable = ast.mutable };
        } else if (ast.mutable) {
            return self.fail(ast.iterable.position, "mutable iteration requires a mutable collection place");
        }
        defer if (iteration_borrow) |borrow| releaseBorrow(borrow);

        var body_scope = Scope{ .parent = parent_scope };
        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        try body_scope.symbols.append(self.allocator, .{
            .source_name = ast.name,
            .generated_name = generated_name,
            .type = element_type,
            .mutability = if (ast.mutable) .mutable else .immutable,
            .state = try self.newBindingState(element_type),
            .movable = false,
        });

        self.loop_depth += 1;
        defer self.loop_depth -= 1;
        const body = try self.statements(ast.body, &body_scope);
        self.releaseScopeBorrows(&body_scope);
        return .{ .for_statement = .{
            .generated_name = generated_name,
            .element_type = element_type,
            .mutable = ast.mutable,
            .iterable = iterable,
            .body = body,
        } };
    }

    fn returnStatement(
        self: *Analyzer,
        ast: Ast.Statement.Return,
        scope: *const Scope,
    ) AnalyzeError!Statement {
        if (ast.value) |ast_value| {
            if (typeEqual(self.current_return_type, .void)) return self.fail(ast.position, "void function cannot return a value");
            var value = try self.expressionForExpected(ast_value, scope, self.current_return_type);
            value = try self.coerce(value, self.current_return_type);
            if (!typeEqual(value.type, self.current_return_type)) {
                const message = try typeMismatchMessage(self.allocator, self.current_return_type, value.type);
                return self.fail(ast_value.position, message);
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
        return self.expressionForBorrow(ast, scope, null);
    }

    fn expressionForBorrow(
        self: *Analyzer,
        ast: *const Ast.Expression,
        scope: *const Scope,
        expected_mutability: ?bool,
    ) AnalyzeError!*Expression {
        if (ast.value == .unary and ast.value.unary.operator == .borrow) {
            return self.borrowExpression(ast.value.unary, scope, expected_mutability orelse false);
        }
        return switch (ast.value) {
            .integer => |lexeme| self.integerExpression(ast.position, lexeme),
            .floating => |lexeme| self.floatExpression(ast.position, lexeme),
            .boolean => |value| self.newExpression(.{
                .type = .bool,
                .position = ast.position,
                .value = .{ .boolean = value },
            }),
            .string => |value| self.stringExpression(ast.position, value),
            .sequence_literal => |values| self.sequenceLiteralExpression(values, ast.position, scope, null),
            .identifier => |name| self.variableExpression(ast.position, name, scope),
            .self => self.selfExpression(ast.position),
            .call => |call| self.callExpression(call, scope),
            .method_call => |call| self.methodCallExpression(call, scope),
            .cascade => |cascade| self.cascadeExpression(cascade, scope, null),
            .structure_initializer => |initializer| self.structureInitializerExpression(initializer, scope),
            .member_access => |member| self.memberAccessExpression(member, scope),
            .index_access => |access| self.indexAccessExpression(access, scope),
            .unary => |unary| self.unaryExpression(unary, scope),
            .conversion => |conversion| self.conversionExpression(conversion, scope),
            .binary => |binary| self.binaryExpression(binary, scope),
        };
    }

    fn expressionForExpected(
        self: *Analyzer,
        ast: *const Ast.Expression,
        scope: *const Scope,
        expected_type: ?Type,
    ) AnalyzeError!*Expression {
        if (ast.value == .sequence_literal) return self.sequenceLiteralExpression(ast.value.sequence_literal, ast.position, scope, expected_type);
        if (ast.value == .cascade) return self.cascadeExpression(ast.value.cascade, scope, expected_type);
        return self.expressionForBorrow(ast, scope, referenceMutability(expected_type));
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
                element_type = first.type;
                const element = try self.allocator.create(Type);
                element.* = element_type;
                result_type = .{ .list = element };
            },
            else => return self.fail(position, "sequence literal requires an array or list type"),
        }

        var values: std.ArrayList(*Expression) = .empty;
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
            try values.append(self.allocator, value);
        }
        return self.newExpression(.{
            .type = result_type,
            .position = position,
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
            .structure => |structure_type| structure_default: {
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
        if (symbol.state.moved) {
            const message = try std.fmt.allocPrint(self.allocator, "use of moved variable '{s}'", .{name});
            return self.fail(position, message);
        }
        if (symbol.state.mutable_borrow) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot access variable '{s}' while it is mutably borrowed", .{name});
            return self.fail(position, message);
        }
        return self.newExpression(.{
            .type = symbol.type,
            .position = position,
            .borrow = symbol.state.reference,
            .value = .{ .variable = symbol.generated_name },
        });
    }

    fn selfExpression(self: *Analyzer, position: Source.Position) AnalyzeError!*Expression {
        const structure_index = self.current_structure_index orelse return self.fail(position, "'self' is only available inside a method");
        if (self.current_self_state.mutable_borrow) return self.fail(position, "cannot access 'self' while one of its collections is mutably iterated");
        const structure = self.structures.items[structure_index];
        return self.newExpression(.{
            .type = .{ .structure = .{
                .source_name = structure.source_name,
                .generated_name = structure.generated_name,
            } },
            .position = position,
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
        if (isContextualIntegerLiteral(left) and isInteger(right.type)) left = try self.coerce(left, right.type);
        if (isContextualIntegerLiteral(right) and isInteger(left.type)) right = try self.coerce(right, left.type);
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
                if (isNumeric(left.type) and isNumeric(right.type)) {
                    const common_type = commonNumericType(left.type, right.type) orelse {
                        const message = try std.fmt.allocPrint(self.allocator, "equality operator requires compatible numeric operands, found '{s}' and '{s}'", .{ typeName(left.type), typeName(right.type) });
                        return self.fail(binary.operator_position, message);
                    };
                    left = try self.coerce(left, common_type);
                    right = try self.coerce(right, common_type);
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
        const function_symbol = self.findFunction(call.name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown function '{s}'", .{call.name});
            return self.fail(call.name_position, message);
        };
        if (function_symbol.is_main) return self.fail(call.name_position, "'main' cannot be called");
        if (call.arguments.len != function_symbol.parameter_types.len) {
            const message = try std.fmt.allocPrint(self.allocator, "function '{s}' expects {d} arguments, found {d}", .{ call.name, function_symbol.parameter_types.len, call.arguments.len });
            return self.fail(call.name_position, message);
        }
        var arguments: std.ArrayList(*Expression) = .empty;
        for (call.arguments, function_symbol.parameter_types, 0..) |argument, expected_type, index| {
            var value = try self.expressionForExpected(argument, scope, expected_type);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
                return self.fail(argument.position, message);
            }
            try arguments.append(self.allocator, value);
            self.releaseTransientBorrow(value);
        }
        return self.newExpression(.{ .type = function_symbol.return_type, .position = call.name_position, .value = .{ .call = .{ .generated_name = function_symbol.generated_name, .arguments = try arguments.toOwnedSlice(self.allocator) } } });
    }

    fn methodCallExpression(
        self: *Analyzer,
        call: Ast.Expression.MethodCall,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const object = try self.expression(call.object, scope);
        const receiver = receiverFor(
            call.object,
            scope,
            self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0,
        );
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
                allow_temporary_collection_mutation,
            ),
            .structure => {},
            else => return self.fail(call.name_position, "method call requires a struct or collection value"),
        }
        const generated_structure_name = object.type.structure.generated_name;
        const structure_index = self.findStructureIndexByGeneratedName(generated_structure_name).?;
        const structure = self.structures.items[structure_index];
        var method_index: ?usize = null;
        for (structure.methods, 0..) |method_symbol, index| {
            if (std.mem.eql(u8, method_symbol.source_name, call.name)) method_index = index;
        }
        const resolved_method_index = method_index orelse {
            const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' has no method '{s}'", .{ structure.source_name, call.name });
            return self.fail(call.name_position, message);
        };
        const method_symbol = structure.methods[resolved_method_index];
        if (call.arguments.len != method_symbol.parameter_types.len) {
            const message = try std.fmt.allocPrint(self.allocator, "method '{s}' expects {d} arguments, found {d}", .{ call.name, method_symbol.parameter_types.len, call.arguments.len });
            return self.fail(call.name_position, message);
        }
        var arguments: std.ArrayList(*Expression) = .empty;
        for (call.arguments, method_symbol.parameter_types, 0..) |argument, expected_type, index| {
            var value = try self.expressionForExpected(argument, scope, expected_type);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
                return self.fail(argument.position, message);
            }
            try arguments.append(self.allocator, value);
            self.releaseTransientBorrow(value);
        }
        const method_id = MethodId{ .structure_index = structure_index, .method_index = resolved_method_index };
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
        const ordinary_receiver = receiverFor(
            cascade.object,
            scope,
            self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0,
        );
        const owns_temporary = isCascadeOwnedTemporary(cascade.object);
        const receiver: Receiver = if (ordinary_receiver == .temporary and owns_temporary)
            .cascade_temporary
        else
            ordinary_receiver;

        var operations: std.ArrayList(Expression.Cascade.Operation) = .empty;
        for (cascade.operations) |operation| switch (operation) {
            .method_call => |cascade_method| {
                const call = Ast.Expression.MethodCall{
                    .object = cascade.object,
                    .name = cascade_method.name,
                    .name_position = cascade_method.name_position,
                    .arguments = cascade_method.arguments,
                };
                const resolved = try self.methodCallExpressionWithObject(call, target, scope, receiver, owns_temporary);
                try operations.append(self.allocator, .{ .method_call = resolved });
            },
            .field_assignment => |field_assignment| {
                try self.requireMutableCascadeReceiver(
                    cascade.object,
                    scope,
                    field_assignment.name_position,
                    owns_temporary,
                );
                const structure_type = switch (object.type) {
                    .structure => |structure| structure,
                    else => return self.fail(field_assignment.name_position, "cascade field assignment requires a struct value"),
                };
                const structure = self.findStructureByGeneratedName(structure_type.generated_name).?;
                var resolved_field: ?StructureFieldSymbol = null;
                for (structure.fields) |field| {
                    if (std.mem.eql(u8, field.source_name, field_assignment.name)) resolved_field = field;
                }
                const field = resolved_field orelse {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "struct '{s}' has no field '{s}'",
                        .{ structure.source_name, field_assignment.name },
                    );
                    return self.fail(field_assignment.name_position, message);
                };
                var value = try self.expressionForExpected(field_assignment.value, scope, field.type);
                value = try self.coerce(value, field.type);
                if (!typeEqual(value.type, field.type)) {
                    const message = try typeMismatchMessage(self.allocator, field.type, value.type);
                    return self.fail(field_assignment.value.position, message);
                }
                try operations.append(self.allocator, .{ .field_assignment = .{
                    .generated_name = field.generated_name,
                    .value = value,
                } });
            },
        };

        return self.newExpression(.{
            .type = object.type,
            .position = cascade.object.position,
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
            .self => {
                if (self.current_self_state.mutable_borrow or self.current_self_state.immutable_borrows != 0) {
                    return self.fail(position, "cannot mutate 'self' while one of its collections is iterated");
                }
                self.current_method_direct_mutation = true;
            },
            .variable => |name| {
                const symbol = findSymbol(scope, name) orelse return self.fail(position, "unknown cascade receiver");
                if (symbol.mutability == .immutable) {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot assign through cascade on immutable value '{s}'", .{name});
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
                try self.requireMutableCollectionReceiver(call.object, scope, call.name_position, call.name),
        }

        var resolved_operation = operation;
        var arguments: std.ArrayList(*Expression) = .empty;
        for (call.arguments, 0..) |argument, index| {
            if (operation == .append and argument.value == .unary and argument.value.unary.operator == .move) {
                if (assignmentRoot(call.object)) |destination_root| {
                    if (assignmentRoot(argument.value.unary.operand)) |source_root| {
                        if (assignmentRootsEqual(destination_root, source_root)) {
                            return self.fail(argument.value.unary.operator_position, "cannot move a collection into itself");
                        }
                    }
                }
            }
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
                    value = try self.copiedExpression(value, element_type.?, argument.position);
                } else {
                    var range_type = value.type;
                    if (range_type == .reference) range_type = range_type.reference.target.*;
                    if (sequenceElementType(range_type)) |range_element| {
                        if (typeEqual(range_element, element_type.?)) {
                            if (value.type == .reference) {
                                value = try self.newExpression(.{
                                    .type = range_type,
                                    .position = argument.position,
                                    .value = .{ .unary = .{ .operator = .dereference, .operand = value } },
                                });
                            }
                            if (isPlaceValue(value) and !self.supportsCopy(range_element)) {
                                const message = try std.fmt.allocPrint(self.allocator, "cannot append '{s}' values by copy because the type does not support 'copy'", .{typeName(range_element)});
                                return self.fail(argument.position, message);
                            }
                            resolved_operation = .append_range;
                            try arguments.append(self.allocator, value);
                            continue;
                        }
                    }
                }
            }
            if (expects_element) value = try self.valueForOwnedElement(value, expected_type, argument.position);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
                return self.fail(argument.position, message);
            }
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
        scope: *const Scope,
        position: Source.Position,
        method_name: []const u8,
    ) AnalyzeError!void {
        const root = assignmentRoot(ast_object) orelse return self.fail(position, "cannot call mutating collection method on a temporary value");
        switch (root) {
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
                    const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on immutable value '{s}'", .{ method_name, name });
                    return self.fail(position, message);
                }
                if (symbol.state.immutable_borrows != 0 or symbol.state.mutable_borrow) {
                    const message = try std.fmt.allocPrint(self.allocator, "cannot mutate borrowed variable '{s}'", .{name});
                    return self.fail(position, message);
                }
            },
        }
    }

    fn findFunction(self: *const Analyzer, name: []const u8) ?FunctionSymbol {
        for (self.functions.items) |function_symbol| {
            if (std.mem.eql(u8, function_symbol.source_name, name)) return function_symbol;
        }
        return null;
    }

    fn findStructure(self: *const Analyzer, name: []const u8) ?*const StructureSymbol {
        for (self.structures.items) |*structure| {
            if (std.mem.eql(u8, structure.source_name, name)) return structure;
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

    fn structureInitializerExpression(
        self: *Analyzer,
        initializer: Ast.Expression.StructureInitializer,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const structure = self.findStructure(initializer.name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown struct '{s}'", .{initializer.name});
            return self.fail(initializer.name_position, message);
        };
        for (initializer.fields, 0..) |field, field_index| {
            var known = false;
            for (structure.fields) |expected_field| {
                if (std.mem.eql(u8, field.name, expected_field.source_name)) known = true;
            }
            if (!known) {
                const message = try std.fmt.allocPrint(self.allocator, "unknown field '{s}' in struct '{s}'", .{ field.name, initializer.name });
                return self.fail(field.position, message);
            }
            for (initializer.fields[0..field_index]) |previous| {
                if (std.mem.eql(u8, previous.name, field.name)) {
                    const message = try std.fmt.allocPrint(self.allocator, "field '{s}' is initialized more than once", .{field.name});
                    return self.fail(field.position, message);
                }
            }
        }

        var values: std.ArrayList(*Expression) = .empty;
        for (structure.fields) |expected_field| {
            var matching: ?Ast.Expression.FieldInitializer = null;
            for (initializer.fields) |field| {
                if (std.mem.eql(u8, field.name, expected_field.source_name)) {
                    matching = field;
                }
            }
            var value = if (matching) |field|
                try self.expressionForExpected(field.value, scope, expected_field.type)
            else
                expected_field.default_value orelse try self.defaultExpression(expected_field.type, initializer.name_position);
            value = try self.coerce(value, expected_field.type);
            if (!typeEqual(value.type, expected_field.type)) {
                const message = try typeMismatchMessage(self.allocator, expected_field.type, value.type);
                const position = if (matching) |field| field.value.position else initializer.name_position;
                return self.fail(position, message);
            }
            try values.append(self.allocator, value);
        }
        return self.newExpression(.{
            .type = .{ .structure = .{
                .source_name = structure.source_name,
                .generated_name = structure.generated_name,
            } },
            .position = initializer.name_position,
            .value = .{ .structure_initializer = .{
                .generated_name = structure.generated_name,
                .fields = try values.toOwnedSlice(self.allocator),
            } },
        });
    }

    fn memberAccessExpression(
        self: *Analyzer,
        member: Ast.Expression.MemberAccess,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const object = try self.expression(member.object, scope);
        const generated_structure_name = switch (object.type) {
            .structure => |structure_type| structure_type.generated_name,
            else => return self.fail(member.name_position, "member access requires a struct value"),
        };
        const structure = self.findStructureByGeneratedName(generated_structure_name).?;
        for (structure.fields) |field| {
            if (std.mem.eql(u8, field.source_name, member.name)) {
                return self.newExpression(.{
                    .type = field.type,
                    .position = member.name_position,
                    .value = .{ .member_access = .{
                        .object = object,
                        .generated_name = field.generated_name,
                    } },
                });
            }
        }
        const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' has no field '{s}'", .{ structure.source_name, member.name });
        return self.fail(member.name_position, message);
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
            .value = .{ .index_access = .{
                .object = object,
                .index = index,
                .from_end = access.from_end,
            } },
        });
    }

    fn findStructureByGeneratedName(self: *const Analyzer, name: []const u8) ?*const StructureSymbol {
        for (self.structures.items) |*structure| {
            if (std.mem.eql(u8, structure.generated_name, name)) return structure;
        }
        return null;
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
        }
    }

    fn methodSymbol(self: *const Analyzer, id: MethodId) *const MethodSymbol {
        return &self.structures.items[id.structure_index].methods[id.method_index];
    }

    fn validateMethodCalls(self: *Analyzer, program: Program) AnalyzeError!void {
        for (program.structures) |structure| {
            for (structure.methods) |method_value| try self.validateStatements(method_value.statements);
        }
        for (program.functions) |function_value| try self.validateStatements(function_value.statements);
    }

    fn validateStatements(self: *Analyzer, statements_value: []const Statement) AnalyzeError!void {
        for (statements_value) |statement_value| {
            switch (statement_value) {
                .print => |expression_value| try self.validateExpression(expression_value),
                .variable_declaration => |declaration| try self.validateExpression(declaration.initializer),
                .assignment => |assignment_value| {
                    try self.validateExpression(assignment_value.target);
                    if (assignment_value.value) |value| try self.validateExpression(value);
                },
                .if_statement => |if_value| {
                    try self.validateExpression(if_value.condition);
                    try self.validateStatements(if_value.body);
                    if (if_value.else_body) |else_body| try self.validateStatements(else_body);
                },
                .while_statement => |while_value| {
                    try self.validateExpression(while_value.condition);
                    try self.validateStatements(while_value.body);
                },
                .for_statement => |for_value| {
                    try self.validateExpression(for_value.iterable);
                    try self.validateStatements(for_value.body);
                },
                .break_statement, .continue_statement => {},
                .return_statement => |value| if (value) |expression_value| try self.validateExpression(expression_value),
                .expression_statement => |expression_value| try self.validateExpression(expression_value),
            }
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
            .boolean, .string, .variable, .self, .cascade_target => {},
            .string_length => |argument| try self.validateExpression(argument),
            .sequence_literal => |values| for (values) |value| try self.validateExpression(value),
            .collection_method => |collection_method| {
                try self.validateExpression(collection_method.object);
                for (collection_method.arguments) |argument| try self.validateExpression(argument);
            },
            .call => |call| for (call.arguments) |argument| try self.validateExpression(argument),
            .method_call => |call| {
                try self.validateExpression(call.object);
                for (call.arguments) |argument| try self.validateExpression(argument);
                if (!self.methodSymbol(call.method_id).is_mutating) return;
                switch (call.receiver) {
                    .self, .mutable, .cascade_temporary => {},
                    .borrowed_self => return self.fail(call.position, "cannot mutate 'self' while one of its collections is iterated"),
                    .immutable => |name| {
                        const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on immutable value '{s}'", .{ call.source_name, name });
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
            .cascade => |cascade| {
                try self.validateExpression(cascade.object);
                for (cascade.operations) |operation| switch (operation) {
                    .method_call => |cascade_method| try self.validateExpression(cascade_method),
                    .field_assignment => |field_assignment| try self.validateExpression(field_assignment.value),
                };
            },
            .structure_initializer => |initializer| for (initializer.fields) |field| try self.validateExpression(field),
            .member_access => |member| try self.validateExpression(member.object),
            .index_access => |access| {
                try self.validateExpression(access.object);
                try self.validateExpression(access.index);
            },
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
        }
    }

    fn unaryExpression(
        self: *Analyzer,
        unary: Ast.Expression.Unary,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        if (unary.operator == .borrow) return self.borrowExpression(unary, scope, false);
        if (unary.operator == .copy) return self.copyExpression(unary, scope);
        if (unary.operator == .move) return self.moveExpression(unary, scope);
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
            .dereference => dereference: {
                const reference = switch (operand.type) {
                    .reference => |value| value,
                    else => return self.fail(unary.operator_position, "dereference requires a reference operand"),
                };
                break :dereference reference.target.*;
            },
            .borrow, .copy, .move => unreachable,
        };
        return self.newExpression(.{
            .type = result_type,
            .position = unary.operator_position,
            .value = .{ .unary = .{ .operator = unary.operator, .operand = operand } },
        });
    }

    fn borrowExpression(
        self: *Analyzer,
        unary: Ast.Expression.Unary,
        scope: *const Scope,
        mutable: bool,
    ) AnalyzeError!*Expression {
        const symbol = try self.placeRootSymbol(unary.operand, scope, unary.operator_position);
        if (symbol.state.moved) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot borrow moved variable '{s}'", .{symbol.source_name});
            return self.fail(unary.operator_position, message);
        }
        if (mutable) {
            if (symbol.mutability != .mutable) {
                const message = try std.fmt.allocPrint(self.allocator, "cannot mutably borrow immutable variable '{s}'", .{symbol.source_name});
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

    fn moveExpression(self: *Analyzer, unary: Ast.Expression.Unary, scope: *const Scope) AnalyzeError!*Expression {
        if (unary.operand.value != .identifier) {
            return switch (unary.operand.value) {
                .member_access => self.fail(unary.operator_position, "cannot move a field; only a complete local variable can be invalidated"),
                .index_access => self.fail(unary.operator_position, "cannot move an indexed element; use 'copy', 'replace', or 'take'"),
                else => self.fail(unary.operator_position, "'move' requires a complete local variable"),
            };
        }
        const name = unary.operand.value.identifier;
        const symbol = findSymbol(scope, name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown variable '{s}'", .{name});
            return self.fail(unary.operator_position, message);
        };
        if (!symbol.movable) return self.fail(unary.operator_position, "cannot move an iteration alias");
        if (symbol.type == .reference) return self.fail(unary.operator_position, "cannot move a reference; borrowed values have no ownership to transfer");
        if (symbol.state.moved) {
            const message = try std.fmt.allocPrint(self.allocator, "variable '{s}' was already moved", .{name});
            return self.fail(unary.operator_position, message);
        }
        if (symbol.state.mutable_borrow or symbol.state.immutable_borrows != 0) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot move borrowed variable '{s}'", .{name});
            return self.fail(unary.operator_position, message);
        }
        const operand = try self.expression(unary.operand, scope);
        symbol.state.moved = true;
        return self.newExpression(.{ .type = operand.type, .position = unary.operator_position, .value = .{ .unary = .{ .operator = .move, .operand = operand } } });
    }

    fn copyExpression(self: *Analyzer, unary: Ast.Expression.Unary, scope: *const Scope) AnalyzeError!*Expression {
        const operand = try self.expression(unary.operand, scope);
        if (operand.type == .reference) {
            return self.fail(unary.operator_position, "cannot apply 'copy' to a reference; dereference it explicitly with 'copy *value'");
        }
        return self.copiedExpression(operand, operand.type, unary.operator_position);
    }

    fn copiedExpression(
        self: *Analyzer,
        operand: *Expression,
        result_type: Type,
        position: Source.Position,
    ) AnalyzeError!*Expression {
        if (!self.supportsCopy(result_type)) {
            const message = try std.fmt.allocPrint(self.allocator, "cannot copy '{s}' because the type does not support 'copy'", .{typeName(result_type)});
            return self.fail(position, message);
        }
        return self.newExpression(.{
            .type = result_type,
            .position = position,
            .value = .{ .unary = .{ .operator = .copy, .operand = operand } },
        });
    }

    fn valueForOwnedElement(
        self: *Analyzer,
        value: *Expression,
        expected_type: Type,
        position: Source.Position,
    ) AnalyzeError!*Expression {
        if (value.type == .reference and typeEqual(value.type.reference.target.*, expected_type)) {
            return self.copiedExpression(value, expected_type, position);
        }
        if (typeEqual(value.type, expected_type) and !self.isCopyable(expected_type) and isPlaceValue(value)) {
            return self.copiedExpression(value, expected_type, position);
        }
        return value;
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
            .{ operator_name, typeName(left_type), typeName(right_type) },
        );
        return self.fail(position, message);
    }

    fn coerce(self: *Analyzer, expression_value: *Expression, target_type: Type) AnalyzeError!*Expression {
        if (typeEqual(expression_value.type, target_type)) {
            try self.requireCopyableValue(expression_value, target_type);
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

    fn requireCopyableValue(self: *Analyzer, expression_value: *const Expression, type_value: Type) AnalyzeError!void {
        if (self.isCopyable(type_value)) return;
        switch (expression_value.value) {
            .variable => return self.fail(expression_value.position, "cannot implicitly copy an owning value; use 'copy' or 'move'"),
            .member_access, .index_access => return self.fail(expression_value.position, "cannot implicitly copy an owning place; use 'copy', borrow it, replace it, or take it from a list"),
            else => {},
        }
    }

    fn isCopyable(self: *const Analyzer, type_value: Type) bool {
        return switch (type_value) {
            .void => false,
            .list => |element| self.supportsCopy(element.*),
            .fixed_array => |array| self.isCopyable(array.element.*),
            .reference => |reference| !reference.mutable,
            .structure => |structure_type| structure: {
                const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :structure false;
                for (structure.fields) |field| if (!self.isCopyable(field.type)) break :structure false;
                break :structure true;
            },
            else => true,
        };
    }

    fn supportsCopy(self: *const Analyzer, type_value: Type) bool {
        return switch (type_value) {
            .void => false,
            .list => |element| self.supportsCopy(element.*),
            .fixed_array => |array| self.supportsCopy(array.element.*),
            .reference => false,
            .structure => |structure_type| structure: {
                const structure = self.findStructureByGeneratedName(structure_type.generated_name) orelse break :structure false;
                for (structure.fields) |field| if (!self.supportsCopy(field.type)) break :structure false;
                break :structure true;
            },
            else => true,
        };
    }

    fn newExpression(self: *Analyzer, value: Expression) !*Expression {
        const result = try self.allocator.create(Expression);
        result.* = value;
        return result;
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
        .structure => |name| structure_type: {
            const structure = self.findStructure(name) orelse {
                const message = try std.fmt.allocPrint(self.allocator, "unknown type '{s}'", .{name});
                return self.fail(position, message);
            };
            break :structure_type .{ .structure = .{
                .source_name = structure.source_name,
                .generated_name = structure.generated_name,
            } };
        },
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
        .reference => |reference| typeFromReference(self, reference, position),
    };
}

fn typeFromReference(
    self: *Analyzer,
    reference: Ast.TypeName.Reference,
    position: Source.Position,
) AnalyzeError!Type {
    const target = try self.allocator.create(Type);
    target.* = try typeFromAnnotation(self, reference.target.*, position);
    if (target.* == .reference) return self.fail(position, "a reference cannot target another reference");
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
            .return_statement => return true,
            .if_statement => |if_statement| {
                if (if_statement.else_body) |else_body| {
                    if (blockAlwaysReturns(if_statement.body) and blockAlwaysReturns(else_body)) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

fn typeMismatchMessage(allocator: Allocator, expected: Type, found: Type) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "expected '{s}', found '{s}'",
        .{ typeName(expected), typeName(found) },
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
        .structure => |left_structure| switch (right) {
            .structure => |right_structure| std.mem.eql(u8, left_structure.generated_name, right_structure.generated_name),
            else => false,
        },
    };
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
        .structure => |structure_type| structure_type.source_name,
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
    self,
    variable: []const u8,
};

fn isCascadeOwnedTemporary(expression: *const Ast.Expression) bool {
    return switch (expression.value) {
        .call, .method_call, .structure_initializer, .sequence_literal => true,
        .member_access => |member| isCascadeOwnedTemporary(member.object),
        .index_access => |access| isCascadeOwnedTemporary(access.object),
        .unary => |unary| unary.operator == .copy or unary.operator == .move,
        else => false,
    };
}

fn assignmentRoot(expression: *const Ast.Expression) ?AssignmentRoot {
    return switch (expression.value) {
        .self => .self,
        .identifier => |name| .{ .variable = name },
        .member_access => |member| assignmentRoot(member.object),
        .index_access => |access| assignmentRoot(access.object),
        else => null,
    };
}

fn assignmentRootsEqual(left: AssignmentRoot, right: AssignmentRoot) bool {
    return switch (left) {
        .self => right == .self,
        .variable => |left_name| switch (right) {
            .variable => |right_name| std.mem.eql(u8, left_name, right_name),
            .self => false,
        },
    };
}

fn receiverFor(expression: *const Ast.Expression, scope: *const Scope, self_borrowed: bool) Receiver {
    return switch (expression.value) {
        .self => if (self_borrowed) .borrowed_self else .self,
        .identifier => |name| receiver: {
            const symbol = findSymbol(scope, name) orelse break :receiver .temporary;
            if (symbol.state.mutable_borrow or symbol.state.immutable_borrows != 0) break :receiver .{ .borrowed = name };
            break :receiver if (symbol.mutability == .mutable)
                .mutable
            else
                .{ .immutable = name };
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

test "nested scope may shadow an outer variable" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let value = 1; if (true) { let value = 2; print(value); } print(value); }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    const outer_name = program.functions[0].statements[0].variable_declaration.generated_name;
    const inner_name = program.functions[0].statements[1].if_statement.body[0].variable_declaration.generated_name;
    try std.testing.expect(!std.mem.eql(u8, outer_name, inner_name));
    try std.testing.expectEqualStrings(
        inner_name,
        program.functions[0].statements[1].if_statement.body[1].print.value.variable,
    );
    try std.testing.expectEqualStrings(outer_name, program.functions[0].statements[2].print.value.variable);
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
    try std.testing.expectEqual(Type.str, program.functions[0].statements[1].assignment.value.type);
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
        \\struct Position { x:int y:int }
        \\struct Player { name:str position:Position }
        \\func main() void {
        \\    let first = Player { name:"Ada", position:Position { x:10, y:20 } }
        \\    let copy = Player { name:"Ada", position:Position { x:10, y:20 } }
        \\    let equal = first == copy
        \\    let different = first != Player { name:"Ada", position:Position { x:11, y:20 } }
        \\}
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());

    try std.testing.expectEqual(Type.bool, program.functions[0].statements[2].variable_declaration.type);
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[3].variable_declaration.type);
}

test "if and else use separate scopes" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { if (true) { let value = 1; } else { let value = 2; } }",
    );
    var analyzer = Analyzer.init(allocator);
    const program = try analyzer.analyze(try parser.parse());
    try std.testing.expectEqual(@as(usize, 1), program.functions[0].statements[0].if_statement.else_body.?.len);
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
    try std.testing.expectEqual(Type.bool, program.functions[0].statements[1].while_statement.condition.type);
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
