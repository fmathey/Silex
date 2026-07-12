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
};

pub const StructureType = struct {
    source_name: []const u8,
    generated_name: []const u8,
};

pub const Expression = struct {
    type: Type,
    position: Source.Position,
    value: union(enum) {
        integer: u64,
        floating: []const u8,
        boolean: bool,
        string: []const u8,
        variable: []const u8,
        self,
        call: Call,
        method_call: MethodCall,
        structure_initializer: StructureInitializer,
        member_access: MemberAccess,
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

    pub const StructureInitializer = struct {
        generated_name: []const u8,
        fields: []const *Expression,
    };

    pub const MemberAccess = struct {
        object: *Expression,
        generated_name: []const u8,
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
    return_statement: ?*Expression,
    expression_statement: *Expression,

    pub const VariableDeclaration = struct {
        generated_name: []const u8,
        type: Type,
        mutability: Ast.Mutability,
        initializer: *Expression,
    };

    pub const Assignment = struct {
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
    mutable,
    immutable: []const u8,
    temporary,
};

const Symbol = struct {
    source_name: []const u8,
    generated_name: []const u8,
    type: Type,
    mutability: Ast.Mutability,
};

const Scope = struct {
    parent: ?*const Scope,
    symbols: std.ArrayList(Symbol) = .empty,
};

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
                try methods.append(self.allocator, .{
                    .source_name = ast_method.name,
                    .generated_name = try std.fmt.allocPrint(self.allocator, "method{d}", .{method_index}),
                    .return_type = try typeFromReturn(self, ast_method.return_type, ast_method.position),
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
            try self.functions.append(self.allocator, .{
                .source_name = ast_function.name,
                .generated_name = if (is_main) "main" else try std.fmt.allocPrint(self.allocator, "silexFunction{d}", .{index}),
                .return_type = try typeFromReturn(self, ast_function.return_type, ast_function.position),
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
                var value = try self.expression(ast_initializer, &empty_scope);
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
        var scope = Scope{ .parent = null };
        var parameters: std.ArrayList(Parameter) = .empty;
        for (ast.parameters, symbol.parameter_types) |parameter, parameter_type| {
            if (findInCurrentScope(&scope, parameter.name) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "parameter '{s}' is already declared", .{parameter.name});
                return self.fail(parameter.position, message);
            }
            const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
            self.next_symbol_id += 1;
            try scope.symbols.append(self.allocator, .{ .source_name = parameter.name, .generated_name = generated_name, .type = parameter_type, .mutability = .immutable });
            try parameters.append(self.allocator, .{ .generated_name = generated_name, .type = parameter_type });
        }
        self.current_return_type = symbol.return_type;
        const function_statements = try self.statements(ast.statements, &scope);
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
            });
            try parameters.append(self.allocator, .{ .generated_name = generated_name, .type = parameter_type });
        }

        self.current_return_type = symbol.return_type;
        const method_statements = try self.statements(ast.statements, &scope);
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
            try self.expression(ast_initializer, scope)
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

        const generated_name = try std.fmt.allocPrint(self.allocator, "silexValue{d}", .{self.next_symbol_id});
        self.next_symbol_id += 1;
        try scope.symbols.append(self.allocator, .{
            .source_name = declaration.name,
            .generated_name = generated_name,
            .type = declared_type,
            .mutability = declaration.mutability,
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
        const root = assignmentRoot(ast.target) orelse return self.fail(ast.position, "invalid assignment target");
        switch (root) {
            .self => {
                if (self.current_method_index == null) return self.fail(ast.position, "'self' is only available inside a method");
                if (ast.target.value == .self) return self.fail(ast.position, "cannot assign to 'self'");
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
            },
        }

        const target = try self.expression(ast.target, scope);
        var value: ?*Expression = null;
        if (ast.value) |ast_value| value = try self.expression(ast_value, scope);

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
                if (!isNumeric(target.type) or !typeEqual(target.type, value.?.type)) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "operator '{s}' requires a numeric target and compatible value, found '{s}' and '{s}'",
                        .{ assignmentOperatorText(ast.operator), typeName(target.type), typeName(value.?.type) },
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
        return .{ .assignment = .{ .target = target, .operator = ast.operator, .value = value } };
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

        var else_body: ?[]const Statement = null;
        if (ast.else_body) |ast_else_body| {
            var else_scope = Scope{ .parent = parent_scope };
            else_body = try self.statements(ast_else_body, &else_scope);
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
        return .{ .while_statement = .{
            .condition = condition,
            .body = try self.statements(ast.body, &body_scope),
        } };
    }

    fn returnStatement(
        self: *Analyzer,
        ast: Ast.Statement.Return,
        scope: *const Scope,
    ) AnalyzeError!Statement {
        if (ast.value) |ast_value| {
            var value = try self.expression(ast_value, scope);
            if (typeEqual(self.current_return_type, .void)) return self.fail(ast.position, "void function cannot return a value");
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
        return switch (ast.value) {
            .integer => |lexeme| self.integerExpression(ast.position, lexeme),
            .floating => |lexeme| self.floatExpression(ast.position, lexeme),
            .boolean => |value| self.newExpression(.{
                .type = .bool,
                .position = ast.position,
                .value = .{ .boolean = value },
            }),
            .string => |value| self.newExpression(.{
                .type = .str,
                .position = ast.position,
                .value = .{ .string = value },
            }),
            .identifier => |name| self.variableExpression(ast.position, name, scope),
            .self => self.selfExpression(ast.position),
            .call => |call| self.callExpression(call, scope),
            .method_call => |call| self.methodCallExpression(call, scope),
            .structure_initializer => |initializer| self.structureInitializerExpression(initializer, scope),
            .member_access => |member| self.memberAccessExpression(member, scope),
            .unary => |unary| self.unaryExpression(unary, scope),
            .binary => |binary| self.binaryExpression(binary, scope),
        };
    }

    fn integerExpression(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
        const value = std.fmt.parseInt(u64, lexeme, 10) catch {
            return self.fail(position, "integer literal is outside the range of 'int'");
        };
        return self.newExpression(.{
            .type = .int,
            .position = position,
            .value = .{ .integer = value },
        });
    }

    fn floatExpression(self: *Analyzer, position: Source.Position, lexeme: []const u8) AnalyzeError!*Expression {
        const value = std.fmt.parseFloat(f64, lexeme) catch {
            return self.fail(position, "float literal is outside the range of 'float'");
        };
        if (!std.math.isFinite(value)) return self.fail(position, "float literal is outside the range of 'float'");
        return self.newExpression(.{
            .type = .float,
            .position = position,
            .value = .{ .floating = lexeme },
        });
    }

    fn defaultExpression(self: *Analyzer, type_value: Type, position: Source.Position) AnalyzeError!*Expression {
        return switch (type_value) {
            .void => self.fail(position, "type 'void' has no default value"),
            .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .integer = 0 } }),
            .float, .float64 => self.newExpression(.{ .type = type_value, .position = position, .value = .{ .floating = "0.0" } }),
            .bool => self.newExpression(.{ .type = .bool, .position = position, .value = .{ .boolean = false } }),
            .str => self.newExpression(.{ .type = .str, .position = position, .value = .{ .string = "" } }),
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
        return self.newExpression(.{
            .type = symbol.type,
            .position = position,
            .value = .{ .variable = symbol.generated_name },
        });
    }

    fn selfExpression(self: *Analyzer, position: Source.Position) AnalyzeError!*Expression {
        const structure_index = self.current_structure_index orelse return self.fail(position, "'self' is only available inside a method");
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
                } else if (!typeEqual(left.type, right.type) or isStructure(left.type)) {
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
            .position = left.position,
            .value = .{ .binary = .{ .operator = binary.operator, .left = left, .right = right } },
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
            var value = try self.expression(argument, scope);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
                return self.fail(argument.position, message);
            }
            try arguments.append(self.allocator, value);
        }
        return self.newExpression(.{ .type = function_symbol.return_type, .position = call.name_position, .value = .{ .call = .{ .generated_name = function_symbol.generated_name, .arguments = try arguments.toOwnedSlice(self.allocator) } } });
    }

    fn methodCallExpression(
        self: *Analyzer,
        call: Ast.Expression.MethodCall,
        scope: *const Scope,
    ) AnalyzeError!*Expression {
        const object = try self.expression(call.object, scope);
        const generated_structure_name = switch (object.type) {
            .structure => |structure_type| structure_type.generated_name,
            else => return self.fail(call.name_position, "method call requires a struct value"),
        };
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
            var value = try self.expression(argument, scope);
            value = try self.coerce(value, expected_type);
            if (!typeEqual(value.type, expected_type)) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} of method '{s}' expects '{s}', found '{s}'", .{ index + 1, call.name, typeName(expected_type), typeName(value.type) });
                return self.fail(argument.position, message);
            }
            try arguments.append(self.allocator, value);
        }
        const receiver = receiverFor(call.object, scope);
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
                try self.expression(field.value, scope)
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
            .boolean, .string, .variable, .self => {},
            .call => |call| for (call.arguments) |argument| try self.validateExpression(argument),
            .method_call => |call| {
                try self.validateExpression(call.object);
                for (call.arguments) |argument| try self.validateExpression(argument);
                if (!self.methodSymbol(call.method_id).is_mutating) return;
                switch (call.receiver) {
                    .self, .mutable => {},
                    .immutable => |name| {
                        const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on immutable value '{s}'", .{ call.source_name, name });
                        return self.fail(call.position, message);
                    },
                    .temporary => {
                        const message = try std.fmt.allocPrint(self.allocator, "cannot call mutating method '{s}' on a temporary value", .{call.source_name});
                        return self.fail(call.position, message);
                    },
                }
            },
            .structure_initializer => |initializer| for (initializer.fields) |field| try self.validateExpression(field),
            .member_access => |member| try self.validateExpression(member.object),
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
        };
        return self.newExpression(.{
            .type = result_type,
            .position = unary.operator_position,
            .value = .{ .unary = .{ .operator = unary.operator, .operand = operand } },
        });
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

    fn newExpression(self: *Analyzer, value: Expression) !*Expression {
        const result = try self.allocator.create(Expression);
        result.* = value;
        return result;
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
        .structure => |name| typeFromAnnotation(self, .{ .structure = name }, position),
    };
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
        .structure => |structure_type| structure_type.source_name,
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

fn assignmentRoot(expression: *const Ast.Expression) ?AssignmentRoot {
    return switch (expression.value) {
        .self => .self,
        .identifier => |name| .{ .variable = name },
        .member_access => |member| assignmentRoot(member.object),
        else => null,
    };
}

fn receiverFor(expression: *const Ast.Expression, scope: *const Scope) Receiver {
    return switch (expression.value) {
        .self => .self,
        .identifier => |name| receiver: {
            const symbol = findSymbol(scope, name) orelse break :receiver .temporary;
            break :receiver if (symbol.mutability == .mutable)
                .mutable
            else
                .{ .immutable = name };
        },
        .member_access => |member| receiverFor(member.object, scope),
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
