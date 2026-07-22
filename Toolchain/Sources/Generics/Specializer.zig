const Types = @import("Types.zig");
const Support = @import("Support.zig");
const Rewrite = @import("Rewrite.zig");
const Instantiate = @import("Instantiate.zig");
const Constraints = @import("Constraints.zig");
const std = Types.std;
const Ast = Types.Ast;
const Parser = Types.Parser;
const Source = Types.Source;
const Allocator = Types.Allocator;
const SpecializeError = Types.SpecializeError;
const Binding = Types.Binding;
const State = Types.State;
const StructureSpecialization = Types.StructureSpecialization;
const EnumSpecialization = Types.EnumSpecialization;
const result_type_parameters = Types.result_type_parameters;
const result_success_types = Types.result_success_types;
const result_failure_types = Types.result_failure_types;
const result_variants = Types.result_variants;
const intrinsic_result = Types.intrinsic_result;
const intrinsic_function_source = Types.intrinsic_function_source;
const FunctionSpecialization = Types.FunctionSpecialization;
const MethodSpecialization = Types.MethodSpecialization;
const functionIsVisible = Support.functionIsVisible;
const fileSetContains = Support.fileSetContains;
const positionsEqual = Support.positionsEqual;
const typeNameToReturnType = Support.typeNameToReturnType;
const appendTypeName = Support.appendTypeName;

pub const Specializer = struct {
    allocator: Allocator,
    program: Ast.Program,
    enums: std.ArrayList(Ast.Enum) = .empty,
    structures: std.ArrayList(Ast.Structure) = .empty,
    functions: std.ArrayList(Ast.Function) = .empty,
    function_templates: []const Ast.Function = &.{},
    enum_specializations: std.ArrayList(EnumSpecialization) = .empty,
    structure_specializations: std.ArrayList(StructureSpecialization) = .empty,
    function_specializations: std.ArrayList(FunctionSpecialization) = .empty,
    method_specializations: std.ArrayList(MethodSpecialization) = .empty,
    active_constraint_protocols: []const []const u8 = &.{},
    active_extension_visibility_file: ?usize = null,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, program: Ast.Program) Specializer {
        return .{ .allocator = allocator, .program = program };
    }

    pub fn specialize(self: *Specializer) SpecializeError!Ast.Program {
        var intrinsic_parser = Parser.init(self.allocator, intrinsic_function_source);
        const intrinsic_program = intrinsic_parser.parse() catch |err| {
            self.diagnostic = intrinsic_parser.diagnostic;
            return err;
        };
        var function_templates: std.ArrayList(Ast.Function) = .empty;
        try function_templates.appendSlice(self.allocator, intrinsic_program.functions);
        try function_templates.appendSlice(self.allocator, self.program.functions);
        self.function_templates = try function_templates.toOwnedSlice(self.allocator);

        for (self.program.enums) |enum_value| {
            if (enum_value.type_parameters.len != 0) continue;
            try self.enums.append(self.allocator, try self.rewriteEnum(enum_value, &.{}));
        }
        for (self.program.structures) |structure| {
            if (structure.type_parameters.len != 0) continue;
            const concrete = try self.rewriteStructure(structure, &.{});
            try self.structures.append(self.allocator, concrete);
        }

        for (self.program.functions) |function| {
            if (function.type_parameters.len != 0) continue;
            try self.functions.append(self.allocator, try self.rewriteFunction(function, &.{}));
        }

        for (self.method_specializations.items) |specialization| {
            const method = specialization.method orelse continue;
            for (self.structures.items) |*structure| {
                if (!std.mem.eql(u8, structure.name, specialization.target_name)) continue;
                var methods: std.ArrayList(Ast.Function) = .empty;
                try methods.appendSlice(self.allocator, structure.methods);
                try methods.append(self.allocator, method);
                structure.methods = try methods.toOwnedSlice(self.allocator);
                break;
            }
        }

        var protocols: std.ArrayList(Ast.Protocol) = .empty;
        for (self.program.protocols) |protocol| {
            var requirements: std.ArrayList(Ast.Function) = .empty;
            for (protocol.requirements) |requirement| {
                try requirements.append(self.allocator, try self.rewriteFunction(requirement, &.{}));
            }
            var rewritten = protocol;
            rewritten.requirements = try requirements.toOwnedSlice(self.allocator);
            try protocols.append(self.allocator, rewritten);
        }

        return .{
            .enums = try self.enums.toOwnedSlice(self.allocator),
            .protocols = try protocols.toOwnedSlice(self.allocator),
            .extensions = self.program.extensions,
            .structures = try self.structures.toOwnedSlice(self.allocator),
            .functions = try self.functions.toOwnedSlice(self.allocator),
        };
    }

    pub const rewriteEnum = Rewrite.rewriteEnum;
    pub const rewriteStructure = Rewrite.rewriteStructure;
    pub const rewriteFunction = Rewrite.rewriteFunction;
    pub const rewriteType = Rewrite.rewriteType;
    pub const rewriteTypePointer = Rewrite.rewriteTypePointer;
    pub const rewriteReturnType = Rewrite.rewriteReturnType;
    pub const instantiate = Rewrite.instantiate;
    pub const instantiateEnum = Rewrite.instantiateEnum;
    pub const rewriteStatements = Rewrite.rewriteStatements;
    pub const rewriteStatement = Rewrite.rewriteStatement;
    pub const rewriteCondition = Rewrite.rewriteCondition;
    pub const rewriteExpression = Rewrite.rewriteExpression;
    pub const rewriteExpressions = Rewrite.rewriteExpressions;
    pub const rewriteFieldInitializers = Rewrite.rewriteFieldInitializers;
    pub const rewriteTypes = Rewrite.rewriteTypes;
    pub const findTemplate = Instantiate.findTemplate;
    pub const findEnumTemplate = Instantiate.findEnumTemplate;
    pub const findConcreteEnum = Instantiate.findConcreteEnum;
    pub const findConcreteStructure = Instantiate.findConcreteStructure;
    pub const instantiateFunctions = Instantiate.instantiateFunctions;
    pub const instantiateFunction = Instantiate.instantiateFunction;
    pub const instantiateMethods = Instantiate.instantiateMethods;
    pub const genericExtensionMethodRequiresArguments = Instantiate.genericExtensionMethodRequiresArguments;
    pub const instantiateMethod = Instantiate.instantiateMethod;
    pub const typeArgumentsSatisfyConstraints = Constraints.typeArgumentsSatisfyConstraints;
    pub const validateTypeArgumentConstraints = Constraints.validateTypeArgumentConstraints;
    pub const typeConformsTo = Constraints.typeConformsTo;
    pub const structureConformsTo = Constraints.structureConformsTo;
    pub const findAvailableStructure = Constraints.findAvailableStructure;
    pub const findProtocol = Constraints.findProtocol;
    pub const hasVisibleGenericFunction = Constraints.hasVisibleGenericFunction;
    pub const hasVisibleConcreteFunction = Constraints.hasVisibleConcreteFunction;
    pub const activeConstraintRequires = Constraints.activeConstraintRequires;
    pub const genericTypeName = Constraints.genericTypeName;
    pub const fail = Constraints.fail;
};
