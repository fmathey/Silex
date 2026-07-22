const Types = @import("Types.zig");
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

pub fn allFieldsInitialized(initialized: []const FieldInitialization) bool {
    for (initialized) |field_initialized| if (field_initialized != .initialized) return false;
    return true;
}

pub fn containsIndex(values: []const usize, candidate: usize) bool {
    for (values) |value| if (value == candidate) return true;
    return false;
}

pub fn hasDirectDeferredResource(expression_value: *const Expression) bool {
    for (expression_value.deferred_resource_paths) |path| {
        if (path.len == 0) return true;
    }
    return false;
}

pub fn deferredResourcePathStartsWith(path: DeferredResourcePath, prefix: DeferredResourcePath) bool {
    if (path.len < prefix.len) return false;
    for (path[0..prefix.len], prefix) |component, expected| {
        if (!std.mem.eql(u8, component, expected)) return false;
    }
    return true;
}

pub fn containsDeferredResourcePath(paths: []const DeferredResourcePath, candidate: DeferredResourcePath) bool {
    for (paths) |path| {
        if (path.len != candidate.len) continue;
        if (deferredResourcePathStartsWith(path, candidate)) return true;
    }
    return false;
}

pub fn deferredResourcePathsEqual(left: []const DeferredResourcePath, right: []const DeferredResourcePath) bool {
    if (left.len != right.len) return false;
    for (left) |path| if (!containsDeferredResourcePath(right, path)) return false;
    return true;
}

pub const DeferredReturnSummary = struct {
    paths: std.ArrayList(DeferredResourcePath) = .empty,
    saw_return: bool = false,
};

pub fn mergeReturnedDeferredResourcePaths(
    allocator: Allocator,
    summary: *DeferredReturnSummary,
    candidate: []const DeferredResourcePath,
) Allocator.Error!void {
    if (!summary.saw_return) {
        try summary.paths.appendSlice(allocator, candidate);
        summary.saw_return = true;
        return;
    }
    var index = summary.paths.items.len;
    while (index != 0) {
        index -= 1;
        if (!containsDeferredResourcePath(candidate, summary.paths.items[index])) {
            _ = summary.paths.orderedRemove(index);
        }
    }
}

pub fn collectReturnedDeferredResourcePaths(
    allocator: Allocator,
    statements_value: []const Statement,
    summary: *DeferredReturnSummary,
) Allocator.Error!void {
    for (statements_value) |statement| switch (statement) {
        .return_statement => |returned| if (returned) |value| {
            try mergeReturnedDeferredResourcePaths(allocator, summary, value.deferred_resource_paths);
        },
        .if_statement => |conditional| {
            try collectReturnedDeferredResourcePaths(allocator, conditional.body, summary);
            for (conditional.alternatives) |alternative| {
                try collectReturnedDeferredResourcePaths(allocator, alternative.body, summary);
            }
            if (conditional.else_body) |body| try collectReturnedDeferredResourcePaths(allocator, body, summary);
        },
        .while_statement => |loop| try collectReturnedDeferredResourcePaths(allocator, loop.body, summary),
        .for_statement => |loop| try collectReturnedDeferredResourcePaths(allocator, loop.body, summary),
        else => {},
    };
}

pub fn collectReturnedResourceDependencies(
    allocator: Allocator,
    statements_value: []const Statement,
    output: *std.ArrayList(*BindingState),
) Allocator.Error!void {
    for (statements_value) |statement| switch (statement) {
        .return_statement => |returned| if (returned) |value| {
            for (value.resource_dependencies) |dependency| {
                var found = false;
                for (output.items) |existing| if (existing == dependency) {
                    found = true;
                    break;
                };
                if (!found) try output.append(allocator, dependency);
            }
        },
        .if_statement => |conditional| {
            try collectReturnedResourceDependencies(allocator, conditional.body, output);
            for (conditional.alternatives) |alternative| try collectReturnedResourceDependencies(allocator, alternative.body, output);
            if (conditional.else_body) |body| try collectReturnedResourceDependencies(allocator, body, output);
        },
        .while_statement => |loop| try collectReturnedResourceDependencies(allocator, loop.body, output),
        .for_statement => |loop| try collectReturnedResourceDependencies(allocator, loop.body, output),
        else => {},
    };
}

pub fn generatedFieldIndex(structure: *const StructureSymbol, generated_name: []const u8) ?usize {
    for (structure.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.generated_name, generated_name)) return index;
    }
    return null;
}

pub fn directSelfFieldIndex(structure: *const StructureSymbol, target: *const Expression) ?usize {
    if (target.value != .member_access) return null;
    const member = target.value.member_access;
    if (member.object.value != .self) return null;
    return generatedFieldIndex(structure, member.generated_name);
}

pub fn mutationReachesClassIdentity(target: *const Expression) bool {
    return switch (target.value) {
        .member_access => |member| (member.object.type == .structure and member.object.type.structure.is_class) or
            mutationReachesClassIdentity(member.object),
        .index_access => |access| mutationReachesClassIdentity(access.object),
        else => false,
    };
}

pub fn findInCurrentScope(scope: *const Scope, name: []const u8) ?*const Symbol {
    for (scope.symbols.items) |*symbol| {
        if (std.mem.eql(u8, symbol.source_name, name)) return symbol;
    }
    return null;
}

pub fn findSymbol(scope: *const Scope, name: []const u8) ?*const Symbol {
    var current: ?*const Scope = scope;
    while (current) |value| : (current = value.parent) {
        if (findInCurrentScope(value, name)) |symbol| return symbol;
    }
    return null;
}

pub fn typeFromAnnotation(
    self: anytype,
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
        .view => |element_annotation| view_type: {
            const element = try self.allocator.create(Type);
            element.* = try typeFromAnnotation(self, element_annotation.*, position);
            if (element.* == .void or element.* == .reference or element.* == .view) {
                return self.fail(position, "a contiguous view requires a concrete element type");
            }
            break :view_type .{ .view = element };
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

pub fn typeFromReturn(
    self: anytype,
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
        .view => |element| typeFromAnnotation(self, .{ .view = element }, position),
        .structure => |name| typeFromAnnotation(self, .{ .structure = name }, position),
        .generic_structure => |generic| typeFromAnnotation(self, .{ .generic_structure = generic }, position),
        .type_parameter => |name| typeFromAnnotation(self, .{ .type_parameter = name }, position),
        .reference => |reference| typeFromReference(self, reference, position),
        .function => |function| function_return: {
            const value = try typeFromFunction(self, function, position);
            if (value.function.deferred) return self.fail(position, "a Silex function cannot return 'deferred func'");
            break :function_return value;
        },
        .optional => |contained| typeFromAnnotation(self, .{ .optional = contained }, position),
    };
}

pub fn typeFromFunction(
    self: anytype,
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
    if (function.deferred and return_type.* != .void) {
        return self.fail(position, "a 'deferred func' must return 'void'");
    }
    if (function.deferred) {
        for (parameters.items, function.parameter_modes) |parameter, mode| {
            if (mode != .value or !isNativeCallbackScalarType(parameter)) {
                return self.fail(position, "a 'deferred func' parameter must be a scalar bool or numeric value");
            }
        }
    }
    return .{ .function = .{
        .deferred = function.deferred,
        .parameters = try parameters.toOwnedSlice(self.allocator),
        .parameter_modes = try self.allocator.dupe(Ast.ParameterMode, function.parameter_modes),
        .return_type = return_type,
    } };
}

pub fn typeFromReference(
    self: anytype,
    reference: Ast.TypeName.Reference,
    position: Source.Position,
) AnalyzeError!Type {
    const target = try self.allocator.create(Type);
    target.* = try typeFromAnnotation(self, reference.target.*, position);
    if (target.* == .reference) return self.fail(position, "a reference cannot target another reference");
    if (target.* == .structure and target.*.structure.is_class and !reference.generic_target) {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "class '{s}' already has reference semantics; '&{s}' is invalid",
            .{ target.*.structure.source_name, target.*.structure.source_name },
        );
        return self.fail(position, message);
    }
    return .{ .reference = .{ .target = target, .mutable = reference.mutable } };
}

pub fn parseFixedArrayLength(self: anytype, lexeme: []const u8, position: Source.Position) AnalyzeError!usize {
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

pub fn blockAlwaysReturns(statements: []const Statement) bool {
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

pub fn astStatementsFallThrough(statements: []const Ast.Statement) bool {
    for (statements) |statement_value| {
        if (!astStatementFallsThrough(statement_value)) return false;
    }
    return true;
}

pub fn astStatementFallsThrough(statement_value: Ast.Statement) bool {
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

pub fn parameterStored(statements: []const Ast.Statement, name: []const u8) bool {
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

pub fn astCollectionCallStoresIdentifier(expression_value: *const Ast.Expression, name: []const u8) bool {
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

pub fn astExpressionUsesIdentifier(expression_value: *const Ast.Expression, name: []const u8) bool {
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

pub fn typeMismatchMessage(allocator: Allocator, expected: Type, found: Type) ![]const u8 {
    const expected_name = try allocatedTypeName(allocator, expected);
    const found_name = try allocatedTypeName(allocator, found);
    return std.fmt.allocPrint(
        allocator,
        "expected '{s}', found '{s}'",
        .{ expected_name, found_name },
    );
}

pub fn referenceMutability(type_value: ?Type) ?bool {
    const value = type_value orelse return null;
    return switch (value) {
        .reference => |reference| reference.mutable,
        else => null,
    };
}

pub fn normalizeNumericLiteral(allocator: Allocator, lexeme: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, lexeme, '_') == null) return lexeme;
    var normalized: std.ArrayList(u8) = .empty;
    for (lexeme) |character| if (character != '_') try normalized.append(allocator, character);
    return normalized.toOwnedSlice(allocator);
}

pub fn hexDigit(character: u8) ?u21 {
    if (std.ascii.isDigit(character)) return character - '0';
    if (character >= 'a' and character <= 'f') return character - 'a' + 10;
    if (character >= 'A' and character <= 'F') return character - 'A' + 10;
    return null;
}

pub fn appendUnicodeScalar(allocator: Allocator, output: *std.ArrayList(u8), scalar: u21) !void {
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

pub fn isUniqueOwnerType(type_value: Type) bool {
    return type_value == .structure and type_value.structure.is_owner;
}

pub fn containsDeferredCallback(type_value: Type) bool {
    return switch (type_value) {
        .function => |function| function.deferred,
        .optional => |contained| containsDeferredCallback(contained.*),
        .list => |element| containsDeferredCallback(element.*),
        .fixed_array => |array| containsDeferredCallback(array.element.*),
        .view => |element| containsDeferredCallback(element.*),
        .reference => |reference| containsDeferredCallback(reference.target.*),
        else => false,
    };
}

pub fn typeEqual(left: Type, right: Type) bool {
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
        .view => |left_element| switch (right) {
            .view => |right_element| typeEqual(left_element.*, right_element.*),
            else => false,
        },
        .reference => |left_reference| switch (right) {
            .reference => |right_reference| left_reference.mutable == right_reference.mutable and typeEqual(left_reference.target.*, right_reference.target.*),
            else => false,
        },
        .function => |left_function| switch (right) {
            .function => |right_function| function_type: {
                if (left_function.deferred != right_function.deferred) break :function_type false;
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

pub fn rawEnumValuesEqual(left: *const Expression, right: *const Expression) bool {
    if (left.value == .string and right.value == .string) {
        return std.mem.eql(u8, left.value.string, right.value.string);
    }
    const left_integer = rawEnumInteger(left) orelse return false;
    const right_integer = rawEnumInteger(right) orelse return false;
    return left_integer.magnitude == right_integer.magnitude and
        (left_integer.magnitude == 0 or left_integer.negative == right_integer.negative);
}

pub fn rawEnumInteger(value: *const Expression) ?struct { magnitude: u64, negative: bool } {
    if (value.value == .integer) return .{ .magnitude = value.value.integer, .negative = false };
    if (value.value == .unary and value.value.unary.operator == .numeric_negate and value.value.unary.operand.value == .integer) {
        return .{ .magnitude = value.value.unary.operand.value.integer, .negative = true };
    }
    return null;
}

pub fn sameSignature(
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

pub fn sameCallableShape(left_types: []const Type, right_types: []const Type) bool {
    if (left_types.len != right_types.len) return false;
    for (left_types, right_types) |left_type, right_type| {
        if (!typeEqual(left_type, right_type)) return false;
    }
    return true;
}

pub fn containsPosition(positions: []const Source.Position, candidate: Source.Position) bool {
    for (positions) |position| {
        if (position.file == candidate.file and position.line == candidate.line and position.column == candidate.column) return true;
    }
    return false;
}

pub fn overloadScore(source: Type, target: Type) ?u8 {
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

pub fn literalOverloadScore(value: *const Expression, target: Type) ?u8 {
    if (target == .optional) {
        const score = literalOverloadScore(value, target.optional.*) orelse return null;
        return score + 3;
    }
    if (value.value == .integer and isInteger(target) and integerLiteralFits(value.value.integer, target)) return 1;
    if (value.value == .floating and target == .float64) return 1;
    return null;
}

pub fn overloadBetter(left: []const u8, right: []const u8) bool {
    var strictly_better = false;
    for (left, right) |left_score, right_score| {
        if (left_score > right_score) return false;
        if (left_score < right_score) strictly_better = true;
    }
    return strictly_better;
}

pub fn appendSignature(
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
        if (mode == .borrow) try output.append(allocator, '@');
        if (mode == .mutable_reference) try output.append(allocator, '&');
        try output.appendSlice(allocator, try allocatedSignatureTypeName(allocator, parameter_type));
    }
    try output.append(allocator, ')');
}

pub fn functionSignatures(allocator: Allocator, candidates: []const FunctionSymbol) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    for (candidates, 0..) |candidate, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendSignature(allocator, &output, lastNameSegment(candidate.source_name), candidate.parameter_types, candidate.parameter_modes);
    }
    return output.toOwnedSlice(allocator);
}

pub fn methodSignatures(allocator: Allocator, candidates: []const MethodCandidate) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    for (candidates, 0..) |candidate, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendSignature(allocator, &output, candidate.symbol.source_name, candidate.symbol.parameter_types, candidate.symbol.parameter_modes);
    }
    return output.toOwnedSlice(allocator);
}

pub fn constructorSignatures(
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

pub fn isNativeScalarReturnType(value: Type) bool {
    return switch (value) {
        .void, .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool, .str => true,
        .structure, .protocol, .enumeration, .list, .fixed_array, .view, .reference, .function, .optional, .null => false,
    };
}

pub fn isNativeStructureFieldType(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool, .str => true,
        else => false,
    };
}

pub fn isNativeScalarParameterType(value: Type) bool {
    return value == .str or isNativeScalarReturnType(value);
}

pub fn isNativeScalarViewType(value: Type) bool {
    const element = switch (value) {
        .view => |element| element.*,
        else => return false,
    };
    return switch (element) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64 => true,
        else => false,
    };
}

pub fn isNativeCallbackScalarType(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool => true,
        else => false,
    };
}

pub fn isNativeCallbackType(value: Type) bool {
    const function = switch (value) {
        .function => |function_value| function_value,
        else => return false,
    };
    if (function.owner != null) return false;
    if (function.return_type.* != .void and !isNativeCallbackScalarType(function.return_type.*)) return false;
    for (function.parameters, function.parameter_modes) |parameter, mode| {
        if (mode != .value or !isNativeCallbackScalarType(parameter)) return false;
    }
    return true;
}

pub fn isNativeByteViewType(value: Type) bool {
    return switch (value) {
        .list => |element| element.* == .uint8,
        .fixed_array => |array| array.element.* == .uint8,
        else => false,
    };
}

pub fn isNativeByteBufferReturnType(value: Type) bool {
    return value == .list and value.list.* == .uint8;
}

pub fn moduleName(function_name: []const u8) ?[]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, function_name, '.') orelse return null;
    return function_name[0..separator];
}

pub fn lastNameSegment(function_name: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, function_name, '.') orelse return function_name;
    return function_name[separator + 1 ..];
}

pub fn nativeSymbol(allocator: Allocator, function_name: []const u8) Allocator.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, "silexNative_");
    for (function_name) |character| {
        try result.append(allocator, if (character == '.') '_' else character);
    }
    return result.toOwnedSlice(allocator);
}

pub fn typeName(value: Type) []const u8 {
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
        .view => "view",
        .reference => |reference| if (reference.mutable) "reference&" else "reference@",
        .function => |function| if (function.deferred) "deferred func" else "func",
        .optional => "optional",
        .null => "null",
        .structure => |structure_type| structure_type.source_name,
        .protocol => |protocol_type| protocol_type.source_name,
        .enumeration => |enum_type| enum_type.source_name,
    };
}

pub fn allocatedTypeName(allocator: Allocator, value: Type) Allocator.Error![]const u8 {
    return switch (value) {
        .optional => |contained| std.fmt.allocPrint(allocator, "{s}?", .{try allocatedTypeName(allocator, contained.*)}),
        .list => |element| std.fmt.allocPrint(allocator, "{s}[]", .{try allocatedTypeName(allocator, element.*)}),
        .fixed_array => |array| std.fmt.allocPrint(allocator, "{s}[{d}]", .{ try allocatedTypeName(allocator, array.element.*), array.length }),
        .view => |element| std.fmt.allocPrint(allocator, "{s}[..]", .{try allocatedTypeName(allocator, element.*)}),
        else => typeName(value),
    };
}

pub fn allocatedSignatureTypeName(allocator: Allocator, value: Type) Allocator.Error![]const u8 {
    return switch (value) {
        .function => |function| function_name: {
            var output: std.ArrayList(u8) = .empty;
            try output.appendSlice(allocator, if (function.deferred) "deferred func(" else "func(");
            for (function.parameters, function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                if (mode == .borrow) try output.append(allocator, '@');
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

pub fn sequenceElementType(value: Type) ?Type {
    return switch (value) {
        .list => |element| element.*,
        .fixed_array => |array| array.element.*,
        else => null,
    };
}

pub fn isPlaceValue(value: *const Expression) bool {
    return switch (value.value) {
        .variable, .self, .member_access, .index_access => true,
        .unary => |unary| unary.operator == .dereference,
        else => false,
    };
}

pub fn isStructure(value: Type) bool {
    return switch (value) {
        .structure => true,
        else => false,
    };
}

pub fn isNumeric(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64 => true,
        else => false,
    };
}

pub fn isInteger(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

pub fn isUnsignedInteger(value: Type) bool {
    return switch (value) {
        .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

pub fn commonUnsignedIntegerType(left: Type, right: Type) ?Type {
    if (!isUnsignedInteger(left) or !isUnsignedInteger(right)) return null;
    return if (integerBits(left) >= integerBits(right)) left else right;
}

pub fn integerBits(value: Type) u8 {
    return switch (value) {
        .int8, .uint8 => 8,
        .int16, .uint16 => 16,
        .int32, .uint32 => 32,
        .int, .uint64 => 64,
        else => 0,
    };
}

pub fn integerLiteralFits(value: u64, target: Type) bool {
    if (!isInteger(target)) return false;
    const bits = integerBits(target);
    if (isUnsignedInteger(target)) return bits == 64 or value <= (@as(u64, 1) << @intCast(bits)) - 1;
    return value <= (@as(u64, 1) << @intCast(bits - 1)) - 1;
}

pub fn isContextualIntegerLiteral(expression_value: *const Expression) bool {
    if (expression_value.value == .integer) return true;
    return expression_value.value == .unary and
        expression_value.value.unary.operator == .numeric_negate and
        expression_value.value.unary.operand.value == .integer;
}

pub fn canWiden(source: Type, target: Type) bool {
    if (isInteger(source) and isInteger(target)) {
        return isUnsignedInteger(source) == isUnsignedInteger(target) and integerBits(source) < integerBits(target);
    }
    if (isInteger(source) and (target == .float or target == .float64)) return true;
    return source == .float and target == .float64;
}

pub fn commonNumericType(left: Type, right: Type) ?Type {
    if (typeEqual(left, right)) return left;
    if (left == .float64 or right == .float64) return .float64;
    if (left == .float or right == .float) return .float;
    if (isInteger(left) and isInteger(right) and isUnsignedInteger(left) == isUnsignedInteger(right)) {
        return if (integerBits(left) >= integerBits(right)) left else right;
    }
    return null;
}

pub fn isPrintable(value: Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool, .str => true,
        else => false,
    };
}

pub const AssignmentRoot = union(enum) {
    static,
    self,
    variable: []const u8,
};

pub fn isCascadeOwnedTemporary(expression: *const Ast.Expression) bool {
    return switch (expression.value) {
        .call, .method_call, .static_method_call, .super_method_call, .class_initializer, .structure_initializer, .match_expression, .sequence_literal => true,
        .member_access => |member| isCascadeOwnedTemporary(member.object),
        .index_access => |access| isCascadeOwnedTemporary(access.object),
        .slice_access => true,
        else => false,
    };
}

pub fn assignmentRoot(expression: *const Ast.Expression) ?AssignmentRoot {
    return switch (expression.value) {
        .static_field_access => .static,
        .self => .self,
        .identifier => |name| .{ .variable = name },
        .member_access => |member| assignmentRoot(member.object),
        .index_access => |access| assignmentRoot(access.object),
        .slice_access => |access| assignmentRoot(access.object),
        else => null,
    };
}

pub fn expressionScopeDepth(expression: *const Ast.Expression, scope: *const Scope) usize {
    return switch (assignmentRoot(expression) orelse return scope.depth) {
        .static => 0,
        .self => 1,
        .variable => |name| if (findSymbol(scope, name)) |symbol| symbol.scope_depth else scope.depth,
    };
}

pub fn assignmentDestinationDepth(
    expression: *const Ast.Expression,
    self: anytype,
    scope: *const Scope,
) usize {
    return switch (assignmentRoot(expression) orelse return scope.depth) {
        .static => 0,
        .self => self.function_scope_depth,
        .variable => |name| if (findSymbol(scope, name)) |symbol| symbol.scope_depth else scope.depth,
    };
}

pub fn updateDestinationLifetime(expression: *const Ast.Expression, scope: *const Scope, lifetime_depth: usize) void {
    const root = assignmentRoot(expression) orelse return;
    switch (root) {
        .static => {},
        .variable => |name| if (findSymbol(scope, name)) |symbol| {
            symbol.state.lifetime_depth = @max(symbol.state.lifetime_depth, lifetime_depth);
        },
        .self => {},
    }
}

pub fn receiverFor(expression: *const Ast.Expression, scope: *const Scope, self_borrowed: bool) Receiver {
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

pub fn assignmentOperatorText(operator: Ast.AssignmentOperator) []const u8 {
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
pub fn restoreOwnerStates(snapshot: []const OwnerStateSnapshot) void {
    for (snapshot) |entry| {
        entry.state.owner_available = entry.available;
        entry.state.consumed_at = entry.consumed_at;
        entry.state.lifetime_depth = entry.lifetime_depth;
        entry.state.deferred_resource_paths = entry.deferred_resource_paths;
    }
}

pub fn findEnumVariant(enum_symbol: *const EnumSymbol, name: []const u8) ?usize {
    for (enum_symbol.variants, 0..) |variant, index| {
        if (std.mem.eql(u8, variant.source_name, name)) return index;
    }
    return null;
}
