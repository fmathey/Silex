const std = @import("std");
const Ast = @import("Ast.zig");
const ProjectModule = @import("Project.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;

pub const File = struct {
    module_index: usize,
    program: Ast.Program,
};

const Kind = enum { structure, function };
const VisitState = enum { fresh, visiting, done };

const Declaration = struct {
    module_index: usize,
    source_name: []const u8,
    canonical_name: []const u8,
    kind: Kind,
    is_public: bool,
    position: Source.Position,
};

const Export = struct {
    module_index: usize,
    public_name: []const u8,
    declaration: *const Declaration,
    position: Source.Position,
};

const ImportBinding = struct {
    module_index: usize,
    qualifier: []const u8,
    position: Source.Position,
    from_use: bool = false,
};

const QualifiedTarget = struct {
    module_index: usize,
    public_name: []const u8,
};

const Dependency = struct {
    module_index: usize,
    position: Source.Position,
};

const UseBinding = struct {
    local_name: []const u8,
    declaration: *const Declaration,
    position: Source.Position,
};

const FileInfo = struct {
    module_index: usize,
    program: Ast.Program,
    imports: []const ImportBinding,
    dependencies: std.ArrayList(Dependency) = .empty,
    uses: std.ArrayList(UseBinding) = .empty,
};

pub const Resolver = struct {
    allocator: Allocator,
    project: ProjectModule.Project,
    files: []const File,
    declarations: std.ArrayList(Declaration) = .empty,
    exports: std.ArrayList(Export) = .empty,
    file_infos: []FileInfo = &.{},
    local_scopes: std.ArrayList(std.ArrayList([]const u8)) = .empty,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, project: ProjectModule.Project, files: []const File) Resolver {
        return .{ .allocator = allocator, .project = project, .files = files };
    }

    pub fn resolve(self: *Resolver) !Ast.Program {
        try self.collectDeclarations();
        try self.collectImports();
        const order = try self.moduleOrder();
        for (order) |module_index| {
            try self.collectModuleUses(module_index);
        }
        try self.validatePublicModuleCollisions();

        var structures: std.ArrayList(Ast.Structure) = .empty;
        var functions: std.ArrayList(Ast.Function) = .empty;
        for (order) |module_index| {
            for (self.file_infos) |file| {
                if (file.module_index != module_index) continue;
                for (file.program.structures) |structure| {
                    try structures.append(self.allocator, try self.transformStructure(structure));
                }
                for (file.program.functions) |function| {
                    try functions.append(self.allocator, try self.transformFunction(function));
                }
            }
        }
        return .{
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
    }

    fn collectDeclarations(self: *Resolver) !void {
        for (self.files) |file| {
            const module_name = self.project.modules[file.module_index].name;
            for (file.program.structures) |structure| {
                try self.addDeclaration(file.module_index, module_name, structure.name, .structure, structure.is_public, structure.name_position);
            }
            for (file.program.functions) |function| {
                const canonical = if (self.project.single_file or
                    (file.module_index == self.project.target_module and std.mem.eql(u8, function.name, "main")))
                    function.name
                else
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, function.name });
                try self.addDeclarationWithCanonical(file.module_index, function.name, canonical, .function, function.is_public, function.name_position);
            }
        }
        for (self.declarations.items) |*declaration| {
            if (declaration.is_public) try self.addExport(declaration.module_index, declaration.source_name, declaration, declaration.position);
        }
    }

    fn addDeclaration(
        self: *Resolver,
        module_index: usize,
        module_name: []const u8,
        source_name: []const u8,
        kind: Kind,
        is_public: bool,
        position: Source.Position,
    ) !void {
        const canonical = if (self.project.single_file)
            source_name
        else
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, source_name });
        try self.addDeclarationWithCanonical(module_index, source_name, canonical, kind, is_public, position);
    }

    fn addDeclarationWithCanonical(
        self: *Resolver,
        module_index: usize,
        source_name: []const u8,
        canonical_name: []const u8,
        kind: Kind,
        is_public: bool,
        position: Source.Position,
    ) !void {
        for (self.declarations.items) |existing| {
            if (existing.module_index == module_index and std.mem.eql(u8, existing.source_name, source_name)) {
                if (existing.kind == .function and kind == .function) continue;
                const message = try std.fmt.allocPrint(self.allocator, "{s} '{s}' is already declared in module '{s}'", .{
                    @tagName(kind), source_name, self.project.modules[module_index].name,
                });
                return self.fail(position, message);
            }
        }
        try self.declarations.append(self.allocator, .{
            .module_index = module_index,
            .source_name = source_name,
            .canonical_name = canonical_name,
            .kind = kind,
            .is_public = is_public,
            .position = position,
        });
    }

    fn collectImports(self: *Resolver) !void {
        var infos = try self.allocator.alloc(FileInfo, self.files.len);
        for (self.files, 0..) |file, file_index| {
            var imports: std.ArrayList(ImportBinding) = .empty;
            for (file.program.imports) |import_value| {
                const module_index = self.findModule(import_value.path) orelse {
                    const message = try std.fmt.allocPrint(self.allocator, "module '{s}' was not found", .{import_value.path});
                    return self.fail(import_value.position, message);
                };
                if (module_index == file.module_index) {
                    const message = try std.fmt.allocPrint(self.allocator, "module '{s}' cannot import itself", .{import_value.path});
                    return self.fail(import_value.position, message);
                }
                const qualifier = import_value.alias orelse import_value.path;
                for (imports.items) |existing| {
                    if (std.mem.eql(u8, existing.qualifier, qualifier)) {
                        const message = try std.fmt.allocPrint(self.allocator, "import qualifier '{s}' is already declared", .{qualifier});
                        return self.fail(import_value.position, message);
                    }
                }
                if (self.findDirect(file.module_index, qualifier, null) != null) {
                    const message = try std.fmt.allocPrint(self.allocator, "import qualifier '{s}' collides with a module declaration", .{qualifier});
                    return self.fail(import_value.position, message);
                }
                try imports.append(self.allocator, .{
                    .module_index = module_index,
                    .qualifier = qualifier,
                    .position = import_value.position,
                });
            }
            for (file.program.uses) |use_value| {
                const module_index = try self.moduleIndexFromUsePath(imports.items, use_value.path) orelse continue;
                if (use_value.is_public) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "module '{s}' cannot be re-exported with 'pub use'",
                        .{self.project.modules[module_index].name},
                    );
                    return self.fail(use_value.position, message);
                }
                if (module_index == file.module_index) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "module '{s}' cannot use itself",
                        .{self.project.modules[module_index].name},
                    );
                    return self.fail(use_value.position, message);
                }
                const qualifier = use_value.alias orelse lastSegment(use_value.path);
                for (imports.items) |existing| {
                    if (std.mem.eql(u8, existing.qualifier, qualifier)) {
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "module qualifier '{s}' is already declared",
                            .{qualifier},
                        );
                        return self.fail(use_value.position, message);
                    }
                }
                if (self.findDirect(file.module_index, qualifier, null) != null) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "module qualifier '{s}' collides with a module declaration",
                        .{qualifier},
                    );
                    return self.fail(use_value.position, message);
                }
                try imports.append(self.allocator, .{
                    .module_index = module_index,
                    .qualifier = qualifier,
                    .position = use_value.position,
                    .from_use = true,
                });
            }
            infos[file_index] = .{
                .module_index = file.module_index,
                .program = file.program,
                .imports = try imports.toOwnedSlice(self.allocator),
            };
            for (infos[file_index].imports) |import_value| {
                try infos[file_index].dependencies.append(self.allocator, .{
                    .module_index = import_value.module_index,
                    .position = import_value.position,
                });
            }
            for (file.program.uses) |use_value| {
                if (moduleUseAt(&infos[file_index], use_value.position)) continue;
                const target = try self.qualifiedUseTarget(&infos[file_index], use_value.path) orelse continue;
                const module_index = target.module_index;
                if (module_index == file.module_index) continue;
                try infos[file_index].dependencies.append(self.allocator, .{
                    .module_index = module_index,
                    .position = use_value.position,
                });
            }
        }
        self.file_infos = infos;
    }

    fn moduleOrder(self: *Resolver) ![]const usize {
        const states = try self.allocator.alloc(VisitState, self.project.modules.len);
        @memset(states, .fresh);
        var stack: std.ArrayList(usize) = .empty;
        var result: std.ArrayList(usize) = .empty;
        for (0..self.project.modules.len) |module_index| try self.visitModule(module_index, states, &stack, &result);
        return result.toOwnedSlice(self.allocator);
    }

    fn visitModule(
        self: *Resolver,
        module_index: usize,
        states: []VisitState,
        stack: *std.ArrayList(usize),
        result: *std.ArrayList(usize),
    ) !void {
        if (states[module_index] == .done) return;
        if (states[module_index] == .visiting) {
            var message: std.ArrayList(u8) = .empty;
            try message.appendSlice(self.allocator, "module dependency cycle: ");
            var started = false;
            for (stack.items) |entry| {
                if (entry == module_index) started = true;
                if (started) try message.appendSlice(
                    self.allocator,
                    try std.fmt.allocPrint(self.allocator, "{s} -> ", .{self.project.modules[entry].name}),
                );
            }
            try message.appendSlice(self.allocator, self.project.modules[module_index].name);
            const position = self.firstDependencyPosition(stack.items[stack.items.len - 1], module_index);
            return self.fail(position, try message.toOwnedSlice(self.allocator));
        }
        states[module_index] = .visiting;
        try stack.append(self.allocator, module_index);
        for (self.file_infos) |file| if (file.module_index == module_index) {
            for (file.dependencies.items) |dependency| {
                if (dependency.module_index != module_index) {
                    try self.visitModule(dependency.module_index, states, stack, result);
                }
            }
        };
        _ = stack.pop();
        states[module_index] = .done;
        try result.append(self.allocator, module_index);
    }

    fn firstDependencyPosition(self: *const Resolver, from: usize, to: usize) Source.Position {
        for (self.file_infos) |file| if (file.module_index == from) {
            for (file.dependencies.items) |dependency| if (dependency.module_index == to) return dependency.position;
        };
        return .{ .line = 1, .column = 1 };
    }

    fn collectModuleUses(self: *Resolver, module_index: usize) !void {
        try self.collectModuleUsesWithVisibility(module_index, true);
        try self.collectModuleUsesWithVisibility(module_index, false);
    }

    fn collectModuleUsesWithVisibility(self: *Resolver, module_index: usize, is_public: bool) !void {
        for (self.file_infos) |*file| {
            if (file.module_index != module_index) continue;
            for (file.program.uses) |use_value| {
                if (use_value.is_public != is_public) continue;
                if (moduleUseAt(file, use_value.position)) continue;
                const declarations = try self.resolveUses(file, use_value.path, use_value.position);
                const local_name = use_value.alias orelse lastSegment(use_value.path);
                try self.validateLocalBinding(file, local_name, use_value.position);
                for (declarations) |declaration| {
                    try file.uses.append(self.allocator, .{
                        .local_name = local_name,
                        .declaration = declaration,
                        .position = use_value.position,
                    });
                    if (is_public) try self.addExport(module_index, local_name, declaration, use_value.position);
                }
            }
        }
    }

    fn validateLocalBinding(self: *Resolver, file: *const FileInfo, name: []const u8, position: Source.Position) !void {
        try self.validateIntroducedName(file, name, position);
        for (file.imports) |import_value| if (std.mem.eql(u8, import_value.qualifier, name)) {
            const message = try std.fmt.allocPrint(self.allocator, "name '{s}' collides with an import alias", .{name});
            return self.fail(position, message);
        };
    }

    fn validateIntroducedName(self: *Resolver, file: *const FileInfo, name: []const u8, position: Source.Position) !void {
        for (file.uses.items) |existing| if (std.mem.eql(u8, existing.local_name, name)) {
            const message = try std.fmt.allocPrint(self.allocator, "name '{s}' is already introduced by use", .{name});
            return self.fail(position, message);
        };
        if (self.findDirect(file.module_index, name, null) != null) {
            const message = try std.fmt.allocPrint(self.allocator, "name '{s}' collides with a module declaration", .{name});
            return self.fail(position, message);
        }
    }

    fn addExport(self: *Resolver, module_index: usize, name: []const u8, declaration: *const Declaration, position: Source.Position) !void {
        for (self.exports.items) |existing| {
            if (existing.module_index == module_index and std.mem.eql(u8, existing.public_name, name)) {
                if (existing.declaration == declaration) return;
                if (existing.declaration.kind == .function and declaration.kind == .function) continue;
                const message = try std.fmt.allocPrint(self.allocator, "public name '{s}' is ambiguous in module '{s}'", .{
                    name, self.project.modules[module_index].name,
                });
                return self.fail(position, message);
            }
        }
        try self.exports.append(self.allocator, .{
            .module_index = module_index,
            .public_name = name,
            .declaration = declaration,
            .position = position,
        });
    }

    fn validatePublicModuleCollisions(self: *Resolver) !void {
        for (self.exports.items) |export_value| {
            const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{
                self.project.modules[export_value.module_index].name, export_value.public_name,
            });
            if (self.findModule(path) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "public symbol '{s}' collides with module '{s}'", .{ path, path });
                return self.fail(export_value.position, message);
            }
        }
    }

    fn transformStructure(self: *Resolver, structure: Ast.Structure) !Ast.Structure {
        const declaration = self.findDirectByPosition(structure.name_position, .structure).?;
        var fields: std.ArrayList(Ast.StructureField) = .empty;
        for (structure.fields) |field| {
            var copy = field;
            copy.type = try self.transformType(field.type, field.position);
            if (field.initializer) |initializer| copy.initializer = try self.transformExpression(initializer);
            try fields.append(self.allocator, copy);
        }
        var methods: std.ArrayList(Ast.Function) = .empty;
        for (structure.methods) |method| try methods.append(self.allocator, try self.transformFunctionBody(method, method.name));
        var constructors: std.ArrayList(Ast.Constructor) = .empty;
        for (structure.constructors) |constructor| {
            try self.pushLocalScope();
            defer self.popLocalScope();
            var parameters: std.ArrayList(Ast.Parameter) = .empty;
            for (constructor.parameters) |parameter| {
                var copy = parameter;
                copy.type = try self.transformType(parameter.type, parameter.position);
                try parameters.append(self.allocator, copy);
                try self.declareLocal(parameter.name);
            }
            try constructors.append(self.allocator, .{
                .visibility = constructor.visibility,
                .position = constructor.position,
                .parameters = try parameters.toOwnedSlice(self.allocator),
                .statements = try self.transformStatementsInCurrentScope(constructor.statements),
            });
        }
        var result = structure;
        result.name = declaration.canonical_name;
        result.fields = try fields.toOwnedSlice(self.allocator);
        result.constructors = try constructors.toOwnedSlice(self.allocator);
        result.methods = try methods.toOwnedSlice(self.allocator);
        return result;
    }

    fn transformFunction(self: *Resolver, function: Ast.Function) !Ast.Function {
        const declaration = self.findDirectByPosition(function.name_position, .function).?;
        return self.transformFunctionBody(function, declaration.canonical_name);
    }

    fn transformFunctionBody(self: *Resolver, function: Ast.Function, name: []const u8) !Ast.Function {
        try self.pushLocalScope();
        defer self.popLocalScope();
        var parameters: std.ArrayList(Ast.Parameter) = .empty;
        for (function.parameters) |parameter| {
            var copy = parameter;
            copy.type = try self.transformType(parameter.type, parameter.position);
            try parameters.append(self.allocator, copy);
            try self.declareLocal(parameter.name);
        }
        var result = function;
        result.name = name;
        result.return_type = try self.transformReturnType(function.return_type, function.position);
        result.parameters = try parameters.toOwnedSlice(self.allocator);
        result.statements = try self.transformStatementsInCurrentScope(function.statements);
        return result;
    }

    fn transformType(self: *Resolver, value: Ast.TypeName, position: Source.Position) anyerror!Ast.TypeName {
        return switch (value) {
            .structure => |name| .{ .structure = (try self.resolveName(position.file, name, .structure, position)).canonical_name },
            .list => |element| .{ .list = try self.transformTypePointer(element.*, position) },
            .fixed_array => |array| .{ .fixed_array = .{
                .element = try self.transformTypePointer(array.element.*, position),
                .length = array.length,
            } },
            .reference => |reference| .{ .reference = .{
                .target = try self.transformTypePointer(reference.target.*, position),
                .mutable = reference.mutable,
            } },
            .function => |function| function_type: {
                var parameters: std.ArrayList(Ast.TypeName) = .empty;
                for (function.parameters) |parameter| try parameters.append(self.allocator, try self.transformType(parameter, position));
                break :function_type .{ .function = .{
                    .parameters = try parameters.toOwnedSlice(self.allocator),
                    .parameter_is_mutable_references = try self.allocator.dupe(bool, function.parameter_is_mutable_references),
                    .return_type = if (function.return_type) |return_type| try self.transformTypePointer(return_type.*, position) else null,
                } };
            },
            .optional => |contained| .{ .optional = try self.transformTypePointer(contained.*, position) },
            else => value,
        };
    }

    fn transformTypePointer(self: *Resolver, value: Ast.TypeName, position: Source.Position) anyerror!*Ast.TypeName {
        const result = try self.allocator.create(Ast.TypeName);
        result.* = try self.transformType(value, position);
        return result;
    }

    fn transformReturnType(self: *Resolver, value: Ast.ReturnType, position: Source.Position) !Ast.ReturnType {
        return switch (value) {
            .structure => |name| .{ .structure = (try self.resolveName(position.file, name, .structure, position)).canonical_name },
            .function => |function| .{ .function = (try self.transformType(.{ .function = function }, position)).function },
            .optional => |contained| .{ .optional = try self.transformTypePointer(contained.*, position) },
            else => value,
        };
    }

    fn transformStatement(self: *Resolver, statement: Ast.Statement) anyerror!Ast.Statement {
        return switch (statement) {
            .print => |value| .{ .print = .{ .position = value.position, .argument = try self.transformExpression(value.argument) } },
            .assertion => |value| .{ .assertion = .{
                .position = value.position,
                .condition = try self.transformExpression(value.condition),
                .message = try self.transformExpression(value.message),
            } },
            .panic_statement => |value| .{ .panic_statement = .{
                .position = value.position,
                .message = try self.transformExpression(value.message),
            } },
            .variable_declaration => |value| declaration: {
                var copy = value;
                if (value.annotation) |annotation| copy.annotation = try self.transformType(annotation, value.name_position);
                if (value.initializer) |initializer| copy.initializer = try self.transformExpression(initializer);
                try self.declareLocal(value.name);
                break :declaration .{ .variable_declaration = copy };
            },
            .assignment => |value| .{ .assignment = .{
                .position = value.position,
                .target = try self.transformExpression(value.target),
                .operator = value.operator,
                .value = if (value.value) |expression| try self.transformExpression(expression) else null,
            } },
            .if_statement => |value| .{ .if_statement = .{
                .position = value.position,
                .condition = try self.transformCondition(value.condition),
                .body = try self.transformConditionalBody(value.body, value.condition),
                .alternatives = alternatives: {
                    var alternatives: std.ArrayList(Ast.Statement.If.Alternative) = .empty;
                    for (value.alternatives) |alternative| try alternatives.append(self.allocator, .{
                        .condition = try self.transformCondition(alternative.condition),
                        .body = try self.transformConditionalBody(alternative.body, alternative.condition),
                    });
                    break :alternatives try alternatives.toOwnedSlice(self.allocator);
                },
                .else_body = if (value.else_body) |body| try self.transformStatements(body) else null,
            } },
            .while_statement => |value| .{ .while_statement = .{
                .position = value.position,
                .condition = try self.transformCondition(value.condition),
                .body = try self.transformConditionalBody(value.body, value.condition),
            } },
            .for_statement => |value| .{ .for_statement = .{
                .position = value.position,
                .name = value.name,
                .name_position = value.name_position,
                .mutability = value.mutability,
                .source = switch (value.source) {
                    .collection => |collection| .{ .collection = try self.transformExpression(collection) },
                    .integer_range => |range| .{ .integer_range = .{
                        .start = try self.transformExpression(range.start),
                        .end = try self.transformExpression(range.end),
                    } },
                },
                .body = try self.transformForBody(value.body, value.name),
            } },
            .break_statement => |position| .{ .break_statement = position },
            .continue_statement => |position| .{ .continue_statement = position },
            .return_statement => |value| .{ .return_statement = .{
                .position = value.position,
                .value = if (value.value) |expression| try self.transformExpression(expression) else null,
            } },
            .expression_statement => |value| .{ .expression_statement = try self.transformExpression(value) },
        };
    }

    fn transformStatements(self: *Resolver, statements: []const Ast.Statement) anyerror![]const Ast.Statement {
        try self.pushLocalScope();
        defer self.popLocalScope();
        return self.transformStatementsInCurrentScope(statements);
    }

    fn transformCondition(self: *Resolver, condition: Ast.Statement.Condition) anyerror!Ast.Statement.Condition {
        return switch (condition) {
            .expression => |expression| .{ .expression = try self.transformExpression(expression) },
            .binding => |binding| .{ .binding = .{
                .position = binding.position,
                .name = binding.name,
                .name_position = binding.name_position,
                .mutability = binding.mutability,
                .source = try self.transformExpression(binding.source),
            } },
        };
    }

    fn transformConditionalBody(
        self: *Resolver,
        statements: []const Ast.Statement,
        condition: Ast.Statement.Condition,
    ) anyerror![]const Ast.Statement {
        try self.pushLocalScope();
        defer self.popLocalScope();
        if (condition == .binding) try self.declareLocal(condition.binding.name);
        return self.transformStatementsInCurrentScope(statements);
    }

    fn transformStatementsInCurrentScope(self: *Resolver, statements: []const Ast.Statement) anyerror![]const Ast.Statement {
        var result: std.ArrayList(Ast.Statement) = .empty;
        for (statements) |statement| try result.append(self.allocator, try self.transformStatement(statement));
        return result.toOwnedSlice(self.allocator);
    }

    fn transformForBody(self: *Resolver, statements: []const Ast.Statement, name: []const u8) anyerror![]const Ast.Statement {
        try self.pushLocalScope();
        defer self.popLocalScope();
        try self.declareLocal(name);
        return self.transformStatementsInCurrentScope(statements);
    }

    fn transformExpression(self: *Resolver, expression: *const Ast.Expression) anyerror!*Ast.Expression {
        var result = try self.allocator.create(Ast.Expression);
        result.position = expression.position;
        result.value = switch (expression.value) {
            .call => |call| call: {
                if (call.named_fields) |fields| {
                    if ((try self.visibleDeclarationKind(expression.position.file, call.name)) == .function) {
                        const message = try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept named arguments; named fields initialize a struct", .{call.name});
                        return self.fail(call.name_position, message);
                    }
                    const declaration = try self.resolveName(expression.position.file, call.name, .structure, call.name_position);
                    break :call .{ .structure_initializer = .{
                        .name = declaration.canonical_name,
                        .name_position = call.name_position,
                        .fields = try self.transformFieldInitializers(fields),
                    } };
                }
                const arguments = try self.transformExpressions(call.arguments);
                if (self.findLocal(call.name)) {
                    break :call .{ .call = .{
                        .name = call.name,
                        .name_position = call.name_position,
                        .arguments = arguments,
                        .visible_declarations = null,
                    } };
                }
                if ((try self.visibleDeclarationKind(expression.position.file, call.name)) == .structure) {
                    const declaration = try self.resolveName(expression.position.file, call.name, .structure, call.name_position);
                    if (self.declarationIsClass(declaration)) {
                        break :call .{ .class_initializer = .{
                            .name = declaration.canonical_name,
                            .name_position = call.name_position,
                            .arguments = arguments,
                        } };
                    }
                    if (arguments.len != 0) {
                        const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' requires named fields such as 'field:value'", .{call.name});
                        return self.fail(call.name_position, message);
                    }
                    break :call .{ .structure_initializer = .{
                        .name = declaration.canonical_name,
                        .name_position = call.name_position,
                        .fields = &.{},
                    } };
                }
                const declarations = try self.visibleFunctionDeclarations(expression.position.file, call.name, call.name_position);
                break :call .{ .call = .{
                    .name = declarations[0].canonical_name,
                    .name_position = call.name_position,
                    .arguments = arguments,
                    .visible_declarations = try declarationPositions(self.allocator, declarations),
                } };
            },
            .value_call => |call| .{ .value_call = .{
                .callee = try self.transformExpression(call.callee),
                .parenthesis_position = call.parenthesis_position,
                .arguments = try self.transformExpressions(call.arguments),
            } },
            .lambda => |lambda| lambda_expression: {
                try self.pushLocalScope();
                defer self.popLocalScope();
                var parameters: std.ArrayList(Ast.Parameter) = .empty;
                for (lambda.parameters) |parameter| {
                    var copy = parameter;
                    copy.type = try self.transformType(parameter.type, parameter.position);
                    try parameters.append(self.allocator, copy);
                    try self.declareLocal(parameter.name);
                }
                break :lambda_expression .{ .lambda = .{
                    .position = lambda.position,
                    .parameters = try parameters.toOwnedSlice(self.allocator),
                    .return_type = try self.transformReturnType(lambda.return_type, lambda.position),
                    .statements = try self.transformStatementsInCurrentScope(lambda.statements),
                } };
            },
            .sequence_literal => |values| .{ .sequence_literal = try self.transformExpressions(values) },
            .structure_initializer => |initializer| .{ .structure_initializer = .{
                .name = (try self.resolveName(expression.position.file, initializer.name, .structure, initializer.name_position)).canonical_name,
                .name_position = initializer.name_position,
                .fields = try self.transformFieldInitializers(initializer.fields),
            } },
            .class_initializer => |initializer| .{ .class_initializer = .{
                .name = (try self.resolveName(expression.position.file, initializer.name, .structure, initializer.name_position)).canonical_name,
                .name_position = initializer.name_position,
                .arguments = try self.transformExpressions(initializer.arguments),
            } },
            .method_call => |call| method: {
                if (try self.expressionPath(call.object)) |prefix| {
                    const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, call.name });
                    if (self.looksQualified(expression.position.file, path)) {
                        if (call.named_fields) |fields| {
                            if ((try self.visibleDeclarationKind(expression.position.file, path)) == .function) {
                                const message = try std.fmt.allocPrint(self.allocator, "function '{s}' does not accept named arguments; named fields initialize a struct", .{path});
                                return self.fail(call.name_position, message);
                            }
                            const declaration = try self.resolveName(expression.position.file, path, .structure, call.name_position);
                            break :method .{ .structure_initializer = .{
                                .name = declaration.canonical_name,
                                .name_position = call.name_position,
                                .fields = try self.transformFieldInitializers(fields),
                            } };
                        }
                        if ((try self.visibleDeclarationKind(expression.position.file, path)) == .structure) {
                            const declaration = try self.resolveName(expression.position.file, path, .structure, call.name_position);
                            if (self.declarationIsClass(declaration)) {
                                break :method .{ .class_initializer = .{
                                    .name = declaration.canonical_name,
                                    .name_position = call.name_position,
                                    .arguments = try self.transformExpressions(call.arguments),
                                } };
                            }
                            if (call.arguments.len != 0) {
                                const message = try std.fmt.allocPrint(self.allocator, "struct '{s}' requires named fields such as 'field:value'", .{path});
                                return self.fail(call.name_position, message);
                            }
                            break :method .{ .structure_initializer = .{
                                .name = declaration.canonical_name,
                                .name_position = call.name_position,
                                .fields = &.{},
                            } };
                        }
                        const declarations = try self.visibleFunctionDeclarations(expression.position.file, path, call.name_position);
                        break :method .{ .call = .{
                            .name = declarations[0].canonical_name,
                            .name_position = call.name_position,
                            .arguments = try self.transformExpressions(call.arguments),
                            .visible_declarations = try declarationPositions(self.allocator, declarations),
                        } };
                    }
                }
                if (call.named_fields != null) {
                    return self.fail(call.name_position, "named arguments require a struct invocation");
                }
                break :method .{ .method_call = .{
                    .object = try self.transformExpression(call.object),
                    .name = call.name,
                    .name_position = call.name_position,
                    .arguments = try self.transformExpressions(call.arguments),
                } };
            },
            .cascade => |cascade| cascade_expression: {
                var operations: std.ArrayList(Ast.Expression.Cascade.Operation) = .empty;
                for (cascade.operations) |operation| {
                    try operations.append(self.allocator, switch (operation) {
                        .method_call => |call| .{ .method_call = .{
                            .name = call.name,
                            .name_position = call.name_position,
                            .arguments = try self.transformExpressions(call.arguments),
                        } },
                        .field_assignment => |assignment| .{ .field_assignment = .{
                            .name = assignment.name,
                            .name_position = assignment.name_position,
                            .value = try self.transformExpression(assignment.value),
                        } },
                    });
                }
                break :cascade_expression .{ .cascade = .{
                    .object = try self.transformExpression(cascade.object),
                    .operations = try operations.toOwnedSlice(self.allocator),
                } };
            },
            .member_access => |member| .{ .member_access = .{
                .object = try self.transformExpression(member.object),
                .name = member.name,
                .name_position = member.name_position,
            } },
            .safe_member_access => |member| .{ .safe_member_access = .{
                .object = try self.transformExpression(member.object),
                .name = member.name,
                .name_position = member.name_position,
                .arguments = if (member.arguments) |arguments| try self.transformExpressions(arguments) else null,
                .named_fields = if (member.named_fields) |fields| try self.transformFieldInitializers(fields) else null,
            } },
            .index_access => |access| .{ .index_access = .{
                .object = try self.transformExpression(access.object),
                .index = try self.transformExpression(access.index),
                .bracket_position = access.bracket_position,
            } },
            .slice_access => |access| .{ .slice_access = .{
                .object = try self.transformExpression(access.object),
                .start = try self.transformExpression(access.start),
                .end = try self.transformExpression(access.end),
                .bracket_position = access.bracket_position,
            } },
            .unary => |unary| .{ .unary = .{
                .operator = unary.operator,
                .operator_position = unary.operator_position,
                .operand = try self.transformExpression(unary.operand),
            } },
            .binary => |binary| .{ .binary = .{
                .operator = binary.operator,
                .operator_position = binary.operator_position,
                .left = try self.transformExpression(binary.left),
                .right = try self.transformExpression(binary.right),
            } },
            else => expression.value,
        };
        return result;
    }

    fn transformExpressions(self: *Resolver, values: []const *Ast.Expression) anyerror![]const *Ast.Expression {
        var result: std.ArrayList(*Ast.Expression) = .empty;
        for (values) |value| try result.append(self.allocator, try self.transformExpression(value));
        return result.toOwnedSlice(self.allocator);
    }

    fn transformFieldInitializers(self: *Resolver, values: []const Ast.Expression.FieldInitializer) anyerror![]const Ast.Expression.FieldInitializer {
        var result: std.ArrayList(Ast.Expression.FieldInitializer) = .empty;
        for (values) |value| try result.append(self.allocator, .{
            .name = value.name,
            .position = value.position,
            .value = try self.transformExpression(value.value),
        });
        return result.toOwnedSlice(self.allocator);
    }

    fn resolveUses(
        self: *Resolver,
        file: *const FileInfo,
        path: []const u8,
        position: Source.Position,
    ) ![]const *const Declaration {
        if (std.mem.lastIndexOfScalar(u8, path, '.') == null) {
            const declarations = try self.declarationsNamed(file.module_index, path, null, false);
            if (declarations.len != 0) return declarations;
            const message = try std.fmt.allocPrint(self.allocator, "unknown declaration '{s}'", .{path});
            return self.fail(position, message);
        }
        const target = try self.qualifiedUseTarget(file, path) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "unknown declaration '{s}'", .{path});
            return self.fail(position, message);
        };
        const is_current = target.module_index == file.module_index;
        const declarations = try self.declarationsNamed(target.module_index, target.public_name, null, !is_current);
        if (declarations.len != 0) return declarations;
        if (!is_current and (try self.declarationsNamed(target.module_index, target.public_name, null, false)).len != 0) {
            const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
                target.public_name, self.project.modules[target.module_index].name,
            });
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
            self.project.modules[target.module_index].name, target.public_name,
        });
        return self.fail(position, message);
    }

    fn expressionPath(self: *Resolver, expression: *const Ast.Expression) !?[]const u8 {
        return switch (expression.value) {
            .identifier => |name| name,
            .member_access => |member| if (try self.expressionPath(member.object)) |prefix|
                try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, member.name })
            else
                null,
            else => null,
        };
    }

    fn looksQualified(self: *const Resolver, file_index: usize, path: []const u8) bool {
        const file = self.file_infos[file_index];
        for (file.imports) |import_value| {
            if (pathHasQualifier(path, import_value.qualifier)) return true;
        }
        return pathHasQualifier(path, self.project.modules[file.module_index].name);
    }

    fn visibleDeclarationKind(self: *Resolver, file_index: usize, name: []const u8) !?Kind {
        const file = &self.file_infos[file_index];
        if (std.mem.indexOfScalar(u8, name, '.') == null) {
            if (self.findDirect(file.module_index, name, null)) |declaration| return declaration.kind;
            for (file.uses.items) |binding| {
                if (std.mem.eql(u8, binding.local_name, name)) return binding.declaration.kind;
            }
            return null;
        }
        const target = try self.qualifiedExpressionTarget(file, name) orelse return null;
        if (self.findDirect(target.module_index, target.public_name, null)) |declaration| return declaration.kind;
        return null;
    }

    fn visibleFunctionDeclarations(
        self: *Resolver,
        file_index: usize,
        name: []const u8,
        position: Source.Position,
    ) ![]const *const Declaration {
        const file = &self.file_infos[file_index];
        if (std.mem.indexOfScalar(u8, name, '.') == null) {
            const direct = try self.declarationsNamed(file.module_index, name, .function, false);
            if (direct.len != 0) return direct;
            var used: std.ArrayList(*const Declaration) = .empty;
            for (file.uses.items) |binding| {
                if (binding.declaration.kind == .function and std.mem.eql(u8, binding.local_name, name)) {
                    try used.append(self.allocator, binding.declaration);
                }
            }
            if (used.items.len != 0) return used.toOwnedSlice(self.allocator);
            _ = try self.resolveName(file_index, name, .function, position);
            unreachable;
        }

        if (try self.qualifiedExpressionTarget(file, name)) |target| {
            const is_current = target.module_index == file.module_index;
            const declarations = try self.declarationsNamed(
                target.module_index,
                target.public_name,
                .function,
                !is_current,
            );
            if (declarations.len != 0) return declarations;
        }
        _ = try self.resolveName(file_index, name, .function, position);
        unreachable;
    }

    fn resolveName(self: *Resolver, file_index: usize, name: []const u8, kind: Kind, position: Source.Position) !*const Declaration {
        const file = &self.file_infos[file_index];
        if (std.mem.indexOfScalar(u8, name, '.') != null) return self.resolveQualified(file, name, kind, position);
        if (self.findDirect(file.module_index, name, kind)) |declaration| return declaration;
        for (file.uses.items) |binding| {
            if (std.mem.eql(u8, binding.local_name, name) and binding.declaration.kind == kind) return binding.declaration;
        }
        const label = if (kind == .structure) "type" else "function";
        const message = try std.fmt.allocPrint(self.allocator, "unknown {s} '{s}'", .{ label, name });
        return self.fail(position, message);
    }

    fn resolveQualified(
        self: *Resolver,
        file: *const FileInfo,
        path: []const u8,
        kind: ?Kind,
        position: Source.Position,
    ) !*const Declaration {
        if (try self.qualifiedExpressionTarget(file, path)) |target| {
            if (std.mem.indexOfScalar(u8, target.public_name, '.') != null) {
                return self.fail(
                    position,
                    try std.fmt.allocPrint(self.allocator, "unknown qualified path '{s}'", .{path}),
                );
            }
            if (target.module_index == file.module_index) {
                if (self.findDirect(target.module_index, target.public_name, kind)) |declaration| return declaration;
            } else if (self.findExport(target.module_index, target.public_name, kind)) |export_value| {
                return export_value.declaration;
            }
            if (target.module_index != file.module_index and self.findDirect(target.module_index, target.public_name, kind) != null) {
                const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
                    target.public_name, self.project.modules[target.module_index].name,
                });
                return self.fail(position, message);
            }
            const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
                self.project.modules[target.module_index].name, target.public_name,
            });
            return self.fail(position, message);
        }
        for (self.project.modules, 0..) |module, module_index| {
            if (pathHasQualifier(path, module.name) and module_index != file.module_index) {
                const message = try std.fmt.allocPrint(self.allocator, "module '{s}' is not imported in this file", .{module.name});
                return self.fail(position, message);
            }
        }
        const message = try std.fmt.allocPrint(self.allocator, "unknown qualified path '{s}'", .{path});
        return self.fail(position, message);
    }

    fn moduleIndexFromUsePath(
        self: *Resolver,
        bindings: []const ImportBinding,
        path: []const u8,
    ) !?usize {
        if (try self.canonicalPathFromBindings(bindings, path)) |canonical| {
            return self.findModule(canonical);
        }
        return self.findModule(path);
    }

    fn qualifiedUseTarget(self: *Resolver, file: *const FileInfo, path: []const u8) !?QualifiedTarget {
        if (try self.canonicalPathFromBindings(file.imports, path)) |canonical| {
            if (self.longestModuleTarget(canonical)) |target| return target;
        }
        return self.longestModuleTarget(path);
    }

    fn qualifiedExpressionTarget(self: *Resolver, file: *const FileInfo, path: []const u8) !?QualifiedTarget {
        const current_name = self.project.modules[file.module_index].name;
        if (pathHasQualifier(path, current_name)) {
            if (self.longestModuleTarget(path)) |target| return target;
        }
        if (try self.canonicalPathFromBindings(file.imports, path)) |canonical| {
            return self.longestModuleTarget(canonical);
        }
        return null;
    }

    fn canonicalPathFromBindings(
        self: *Resolver,
        bindings: []const ImportBinding,
        path: []const u8,
    ) !?[]const u8 {
        var matched: ?ImportBinding = null;
        for (bindings) |binding| {
            if (!pathHasQualifier(path, binding.qualifier)) continue;
            if (matched == null or binding.qualifier.len > matched.?.qualifier.len) matched = binding;
        }
        const binding = matched orelse return null;
        const canonical: []const u8 = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{
            self.project.modules[binding.module_index].name,
            path[binding.qualifier.len + 1 ..],
        });
        return canonical;
    }

    fn longestModuleTarget(self: *const Resolver, canonical_path: []const u8) ?QualifiedTarget {
        var matched_index: ?usize = null;
        for (self.project.modules, 0..) |module, module_index| {
            if (!pathHasQualifier(canonical_path, module.name)) continue;
            if (matched_index == null or module.name.len > self.project.modules[matched_index.?].name.len) {
                matched_index = module_index;
            }
        }
        const module_index = matched_index orelse return null;
        const module_name = self.project.modules[module_index].name;
        return .{
            .module_index = module_index,
            .public_name = canonical_path[module_name.len + 1 ..],
        };
    }

    fn findModule(self: *const Resolver, name: []const u8) ?usize {
        for (self.project.modules, 0..) |module, index| if (std.mem.eql(u8, module.name, name)) return index;
        return null;
    }

    fn declarationsNamed(
        self: *Resolver,
        module_index: usize,
        name: []const u8,
        kind: ?Kind,
        public_only: bool,
    ) ![]const *const Declaration {
        var result: std.ArrayList(*const Declaration) = .empty;
        if (public_only) {
            for (self.exports.items) |*export_value| {
                if (export_value.module_index == module_index and
                    std.mem.eql(u8, export_value.public_name, name) and
                    (kind == null or export_value.declaration.kind == kind.?))
                {
                    try result.append(self.allocator, export_value.declaration);
                }
            }
        } else {
            for (self.declarations.items) |*declaration| {
                if (declaration.module_index == module_index and
                    std.mem.eql(u8, declaration.source_name, name) and
                    (kind == null or declaration.kind == kind.?))
                {
                    try result.append(self.allocator, declaration);
                }
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn findDirect(self: *Resolver, module_index: usize, name: []const u8, kind: ?Kind) ?*const Declaration {
        for (self.declarations.items) |*declaration| {
            if (declaration.module_index == module_index and (kind == null or declaration.kind == kind.?) and
                std.mem.eql(u8, declaration.source_name, name)) return declaration;
        }
        return null;
    }

    fn findDirectByPosition(self: *Resolver, position: Source.Position, kind: Kind) ?*const Declaration {
        for (self.declarations.items) |*declaration| {
            if (declaration.kind == kind and declaration.position.file == position.file and
                declaration.position.line == position.line and declaration.position.column == position.column) return declaration;
        }
        return null;
    }

    fn declarationIsClass(self: *const Resolver, declaration: *const Declaration) bool {
        if (declaration.kind != .structure) return false;
        for (self.files) |file| {
            for (file.program.structures) |structure| {
                if (structure.name_position.file == declaration.position.file and
                    structure.name_position.line == declaration.position.line and
                    structure.name_position.column == declaration.position.column)
                {
                    return structure.is_class;
                }
            }
        }
        return false;
    }

    fn findExport(self: *Resolver, module_index: usize, name: []const u8, kind: ?Kind) ?*const Export {
        for (self.exports.items) |*export_value| {
            if (export_value.module_index == module_index and (kind == null or export_value.declaration.kind == kind.?) and
                std.mem.eql(u8, export_value.public_name, name)) return export_value;
        }
        return null;
    }

    fn pushLocalScope(self: *Resolver) !void {
        try self.local_scopes.append(self.allocator, .empty);
    }

    fn popLocalScope(self: *Resolver) void {
        _ = self.local_scopes.pop();
    }

    fn declareLocal(self: *Resolver, name: []const u8) !void {
        try self.local_scopes.items[self.local_scopes.items.len - 1].append(self.allocator, name);
    }

    fn findLocal(self: *const Resolver, name: []const u8) bool {
        var scope_index = self.local_scopes.items.len;
        while (scope_index != 0) {
            scope_index -= 1;
            for (self.local_scopes.items[scope_index].items) |local| {
                if (std.mem.eql(u8, local, name)) return true;
            }
        }
        return false;
    }

    fn fail(self: *Resolver, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn pathHasQualifier(path: []const u8, qualifier: []const u8) bool {
    return path.len > qualifier.len and std.mem.startsWith(u8, path, qualifier) and path[qualifier.len] == '.';
}

fn lastSegment(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[index + 1 ..];
}

fn moduleUseAt(file: *const FileInfo, position: Source.Position) bool {
    for (file.imports) |binding| {
        if (!binding.from_use) continue;
        if (binding.position.file == position.file and binding.position.line == position.line and
            binding.position.column == position.column) return true;
    }
    return false;
}

fn declarationPositions(allocator: Allocator, declarations: []const *const Declaration) ![]const Source.Position {
    var positions: std.ArrayList(Source.Position) = .empty;
    for (declarations) |declaration| try positions.append(allocator, declaration.position);
    return positions.toOwnedSlice(allocator);
}
