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
        for (self.file_infos) |file| {
            for (file.program.structures) |structure| {
                try structures.append(self.allocator, try self.transformStructure(structure));
            }
            for (file.program.functions) |function| {
                try functions.append(self.allocator, try self.transformFunction(function));
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
                const canonical = if (file.module_index == self.project.target_module and std.mem.eql(u8, function.name, "main"))
                    "main"
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
        const canonical = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, source_name });
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
                const module_index = self.directUseModule(&infos[file_index], use_value.path) orelse continue;
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
                const declaration = try self.resolveUse(file, use_value.path, use_value.position);
                const local_name = use_value.alias orelse lastSegment(use_value.path);
                try self.validateLocalBinding(file, local_name, use_value.position);
                try file.uses.append(self.allocator, .{
                    .local_name = local_name,
                    .declaration = declaration,
                    .position = use_value.position,
                });
                if (is_public) try self.addExport(module_index, local_name, declaration, use_value.position);
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
        var result = structure;
        result.name = declaration.canonical_name;
        result.fields = try fields.toOwnedSlice(self.allocator);
        result.methods = try methods.toOwnedSlice(self.allocator);
        return result;
    }

    fn transformFunction(self: *Resolver, function: Ast.Function) !Ast.Function {
        const declaration = self.findDirectByPosition(function.name_position, .function).?;
        return self.transformFunctionBody(function, declaration.canonical_name);
    }

    fn transformFunctionBody(self: *Resolver, function: Ast.Function, name: []const u8) !Ast.Function {
        var parameters: std.ArrayList(Ast.Parameter) = .empty;
        for (function.parameters) |parameter| {
            var copy = parameter;
            copy.type = try self.transformType(parameter.type, parameter.position);
            try parameters.append(self.allocator, copy);
        }
        var statements: std.ArrayList(Ast.Statement) = .empty;
        for (function.statements) |statement| try statements.append(self.allocator, try self.transformStatement(statement));
        var result = function;
        result.name = name;
        result.return_type = try self.transformReturnType(function.return_type, function.position);
        result.parameters = try parameters.toOwnedSlice(self.allocator);
        result.statements = try statements.toOwnedSlice(self.allocator);
        return result;
    }

    fn transformType(self: *Resolver, value: Ast.TypeName, position: Source.Position) !Ast.TypeName {
        return switch (value) {
            .structure => |name| .{ .structure = (try self.resolveName(position.file, name, .structure, position)).canonical_name },
            else => value,
        };
    }

    fn transformReturnType(self: *Resolver, value: Ast.ReturnType, position: Source.Position) !Ast.ReturnType {
        return switch (value) {
            .structure => |name| .{ .structure = (try self.resolveName(position.file, name, .structure, position)).canonical_name },
            else => value,
        };
    }

    fn transformStatement(self: *Resolver, statement: Ast.Statement) anyerror!Ast.Statement {
        return switch (statement) {
            .print => |value| .{ .print = .{ .position = value.position, .argument = try self.transformExpression(value.argument) } },
            .variable_declaration => |value| declaration: {
                var copy = value;
                if (value.annotation) |annotation| copy.annotation = try self.transformType(annotation, value.name_position);
                if (value.initializer) |initializer| copy.initializer = try self.transformExpression(initializer);
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
                .condition = try self.transformExpression(value.condition),
                .body = try self.transformStatements(value.body),
                .else_body = if (value.else_body) |body| try self.transformStatements(body) else null,
            } },
            .while_statement => |value| .{ .while_statement = .{
                .position = value.position,
                .condition = try self.transformExpression(value.condition),
                .body = try self.transformStatements(value.body),
            } },
            .for_statement => |value| .{ .for_statement = .{
                .position = value.position,
                .name = value.name,
                .name_position = value.name_position,
                .mutable = value.mutable,
                .iterable = try self.transformExpression(value.iterable),
                .body = try self.transformStatements(value.body),
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
        var result: std.ArrayList(Ast.Statement) = .empty;
        for (statements) |statement| try result.append(self.allocator, try self.transformStatement(statement));
        return result.toOwnedSlice(self.allocator);
    }

    fn transformExpression(self: *Resolver, expression: *const Ast.Expression) anyerror!*Ast.Expression {
        var result = try self.allocator.create(Ast.Expression);
        result.position = expression.position;
        result.value = switch (expression.value) {
            .call => |call| .{ .call = .{
                .name = (try self.resolveName(expression.position.file, call.name, .function, call.name_position)).canonical_name,
                .name_position = call.name_position,
                .arguments = try self.transformExpressions(call.arguments),
            } },
            .structure_initializer => |initializer| .{ .structure_initializer = .{
                .name = (try self.resolveName(expression.position.file, initializer.name, .structure, initializer.name_position)).canonical_name,
                .name_position = initializer.name_position,
                .fields = try self.transformFieldInitializers(initializer.fields),
            } },
            .method_call => |call| method: {
                if (try self.expressionPath(call.object)) |prefix| {
                    const path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, call.name });
                    if (self.looksQualified(expression.position.file, path)) {
                        const declaration = try self.resolveName(expression.position.file, path, .function, call.name_position);
                        break :method .{ .call = .{
                            .name = declaration.canonical_name,
                            .name_position = call.name_position,
                            .arguments = try self.transformExpressions(call.arguments),
                        } };
                    }
                }
                break :method .{ .method_call = .{
                    .object = try self.transformExpression(call.object),
                    .name = call.name,
                    .name_position = call.name_position,
                    .arguments = try self.transformExpressions(call.arguments),
                } };
            },
            .member_access => |member| .{ .member_access = .{
                .object = try self.transformExpression(member.object),
                .name = member.name,
                .name_position = member.name_position,
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

    fn directUseModule(self: *const Resolver, file: *const FileInfo, path: []const u8) ?usize {
        for (file.imports) |import_value| {
            if (useHasQualifier(path, import_value.qualifier)) return import_value.module_index;
        }
        const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
        return self.findModule(path[0..separator]);
    }

    fn resolveUse(
        self: *Resolver,
        file: *const FileInfo,
        path: []const u8,
        position: Source.Position,
    ) !*const Declaration {
        const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse {
            if (self.findDirect(file.module_index, path, null)) |declaration| return declaration;
            const message = try std.fmt.allocPrint(self.allocator, "unknown declaration '{s}'", .{path});
            return self.fail(position, message);
        };

        const current_name = self.project.modules[file.module_index].name;
        if (useHasQualifier(path, current_name)) return self.resolveQualified(file, path, null, position);
        for (file.imports) |import_value| {
            if (useHasQualifier(path, import_value.qualifier)) return self.resolveQualified(file, path, null, position);
        }

        const module_name = path[0..separator];
        const public_name = path[separator + 1 ..];
        const module_index = self.findModule(module_name) orelse {
            const message = try std.fmt.allocPrint(self.allocator, "module '{s}' was not found", .{module_name});
            return self.fail(position, message);
        };
        if (self.findExport(module_index, public_name, null)) |export_value| return export_value.declaration;
        if (self.findDirect(module_index, public_name, null)) |_| {
            const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
                public_name, module_name,
            });
            return self.fail(position, message);
        }
        const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
            module_name, public_name,
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
        const current_name = self.project.modules[file.module_index].name;
        if (pathHasQualifier(path, current_name)) {
            const public_name = path[current_name.len + 1 ..];
            if (self.findDirect(file.module_index, public_name, kind)) |declaration| return declaration;
        }
        var matched_import: ?ImportBinding = null;
        for (file.imports) |import_value| {
            if (!pathHasQualifier(path, import_value.qualifier)) continue;
            if (matched_import == null or import_value.qualifier.len > matched_import.?.qualifier.len) {
                matched_import = import_value;
            }
        }
        if (matched_import) |import_value| {
            const public_name = path[import_value.qualifier.len + 1 ..];
            if (std.mem.indexOfScalar(u8, public_name, '.') != null) {
                const message = try std.fmt.allocPrint(self.allocator, "unknown qualified path '{s}'", .{path});
                return self.fail(position, message);
            }
            if (self.findExport(import_value.module_index, public_name, kind)) |export_value| return export_value.declaration;
            if (self.findDirect(import_value.module_index, public_name, kind)) |_| {
                const message = try std.fmt.allocPrint(self.allocator, "declaration '{s}' is private in module '{s}'", .{
                    public_name, self.project.modules[import_value.module_index].name,
                });
                return self.fail(position, message);
            }
            const message = try std.fmt.allocPrint(self.allocator, "module '{s}' has no public declaration '{s}'", .{
                self.project.modules[import_value.module_index].name, public_name,
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

    fn findModule(self: *const Resolver, name: []const u8) ?usize {
        for (self.project.modules, 0..) |module, index| if (std.mem.eql(u8, module.name, name)) return index;
        return null;
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

    fn findExport(self: *Resolver, module_index: usize, name: []const u8, kind: ?Kind) ?*const Export {
        for (self.exports.items) |*export_value| {
            if (export_value.module_index == module_index and (kind == null or export_value.declaration.kind == kind.?) and
                std.mem.eql(u8, export_value.public_name, name)) return export_value;
        }
        return null;
    }

    fn fail(self: *Resolver, position: Source.Position, message: []const u8) Source.Error {
        self.diagnostic = .{ .position = position, .message = message };
        return error.InvalidSource;
    }
};

fn pathHasQualifier(path: []const u8, qualifier: []const u8) bool {
    return path.len > qualifier.len and std.mem.startsWith(u8, path, qualifier) and path[qualifier.len] == '.';
}

fn useHasQualifier(path: []const u8, qualifier: []const u8) bool {
    const separator = std.mem.lastIndexOfScalar(u8, path, '.') orelse return false;
    return separator == qualifier.len and std.mem.startsWith(u8, path, qualifier);
}

fn lastSegment(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[index + 1 ..];
}
