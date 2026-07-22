const Types = @import("Types.zig");
const Support = @import("Support.zig");
const Declarations = @import("Declarations.zig");
const Transform = @import("Transform.zig");
const Resolution = @import("Resolution.zig");
const std = Types.std;
const Ast = Types.Ast;
const ProjectModule = Types.ProjectModule;
const Source = Types.Source;
const Allocator = Types.Allocator;
const File = Types.File;
const Kind = Types.Kind;
const VisitState = Types.VisitState;
const Declaration = Types.Declaration;
const Export = Types.Export;
const ModuleBinding = Types.ModuleBinding;
const QualifiedTarget = Types.QualifiedTarget;
const Dependency = Types.Dependency;
const UseBinding = Types.UseBinding;
const FileInfo = Types.FileInfo;
const pathHasQualifier = Support.pathHasQualifier;
const sourceFileIndex = Support.sourceFileIndex;
const appendFunctions = Support.appendFunctions;
const appendProtocolReferences = Support.appendProtocolReferences;
const lastSegment = Support.lastSegment;
const parentModuleName = Support.parentModuleName;
const sameModuleParent = Support.sameModuleParent;
const moduleUseAt = Support.moduleUseAt;
const moduleBindingAt = Support.moduleBindingAt;
const loadOnlyUseAt = Support.loadOnlyUseAt;
const declarationPositions = Support.declarationPositions;
const typeNameToReturnType = Support.typeNameToReturnType;

pub const Resolver = struct {
    allocator: Allocator,
    project: ProjectModule.Project,
    files: []const File,
    declarations: std.ArrayList(Declaration) = .empty,
    exports: std.ArrayList(Export) = .empty,
    file_infos: []FileInfo = &.{},
    local_scopes: std.ArrayList(std.ArrayList([]const u8)) = .empty,
    current_type_parameters: []const Ast.TypeParameter = &.{},
    alias_stack: std.ArrayList(*const Declaration) = .empty,
    diagnostic: ?Source.Diagnostic = null,

    pub fn init(allocator: Allocator, project: ProjectModule.Project, files: []const File) Resolver {
        return .{ .allocator = allocator, .project = project, .files = files };
    }

    pub fn resolve(self: *Resolver) !Ast.Program {
        try self.collectDeclarations();
        try self.collectModuleBindings();
        const order = try self.moduleOrder();
        for (order) |module_index| {
            try self.collectModuleUses(module_index);
        }
        try self.validateTypeAliases();
        try self.validateNamespaceCollisions();

        var enums: std.ArrayList(Ast.Enum) = .empty;
        var protocols: std.ArrayList(Ast.Protocol) = .empty;
        var extensions: std.ArrayList(Ast.Extension) = .empty;
        var structures: std.ArrayList(Ast.Structure) = .empty;
        var functions: std.ArrayList(Ast.Function) = .empty;
        for (order) |module_index| {
            for (self.file_infos) |file| {
                if (file.module_index != module_index) continue;
                for (file.program.enums) |enum_value| {
                    try enums.append(self.allocator, try self.transformEnum(enum_value));
                }
                for (file.program.protocols) |protocol| {
                    try protocols.append(self.allocator, try self.transformProtocol(protocol));
                }
                for (file.program.structures) |structure| {
                    try structures.append(self.allocator, try self.transformStructure(structure));
                }
                for (file.program.functions) |function| {
                    try functions.append(self.allocator, try self.transformFunction(function));
                }
            }
        }
        for (order) |module_index| {
            for (self.file_infos) |file| {
                if (file.module_index != module_index) continue;
                for (file.program.extensions) |extension| {
                    const transformed = try self.transformExtension(extension, file.module_index);
                    try extensions.append(self.allocator, transformed);
                    var found = false;
                    for (structures.items) |*structure| {
                        if (!std.mem.eql(u8, structure.name, transformed.target)) continue;
                        if (structure.type_parameters.len != 0) {
                            return self.fail(extension.target_position, "generic structures cannot be extended");
                        }
                        structure.methods = try appendFunctions(self.allocator, structure.methods, transformed.methods);
                        structure.conformances = try appendProtocolReferences(
                            self.allocator,
                            structure.conformances,
                            transformed.conformances,
                        );
                        found = true;
                        break;
                    }
                    if (!found) return self.fail(extension.target_position, "only a struct or class can be extended");
                }
            }
        }
        return .{
            .enums = try enums.toOwnedSlice(self.allocator),
            .protocols = try protocols.toOwnedSlice(self.allocator),
            .extensions = try extensions.toOwnedSlice(self.allocator),
            .structures = try structures.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
        };
    }

    pub const transformExtension = Declarations.transformExtension;
    pub const extensionVisibleFiles = Declarations.extensionVisibleFiles;
    pub const collectDeclarations = Declarations.collectDeclarations;
    pub const addDeclaration = Declarations.addDeclaration;
    pub const addDeclarationWithCanonical = Declarations.addDeclarationWithCanonical;
    pub const collectModuleBindings = Declarations.collectModuleBindings;
    pub const appendTypeDependencies = Declarations.appendTypeDependencies;
    pub const appendNamedTypeDependency = Declarations.appendNamedTypeDependency;
    pub const moduleOrder = Declarations.moduleOrder;
    pub const visitModule = Declarations.visitModule;
    pub const firstDependencyPosition = Declarations.firstDependencyPosition;
    pub const collectModuleUses = Declarations.collectModuleUses;
    pub const collectModuleTypeAliases = Declarations.collectModuleTypeAliases;
    pub const collectModuleUsesWithVisibility = Declarations.collectModuleUsesWithVisibility;
    pub const validateLocalBinding = Declarations.validateLocalBinding;
    pub const validateIntroducedName = Declarations.validateIntroducedName;
    pub const addExport = Declarations.addExport;
    pub const validateNamespaceCollisions = Declarations.validateNamespaceCollisions;
    pub const validatePrincipalMemberCollision = Declarations.validatePrincipalMemberCollision;
    pub const transformStructure = Transform.transformStructure;
    pub const transformProtocol = Transform.transformProtocol;
    pub const transformEnum = Transform.transformEnum;
    pub const transformFunction = Transform.transformFunction;
    pub const transformTypeParameters = Transform.transformTypeParameters;
    pub const transformFunctionBody = Transform.transformFunctionBody;
    pub const transformType = Transform.transformType;
    pub const transformTypePointer = Transform.transformTypePointer;
    pub const transformTypeArguments = Transform.transformTypeArguments;
    pub const transformReturnType = Transform.transformReturnType;
    pub const isCurrentTypeParameter = Transform.isCurrentTypeParameter;
    pub const visibleTypeAlias = Transform.visibleTypeAlias;
    pub const resolveAliasType = Transform.resolveAliasType;
    pub const validateTypeAliases = Transform.validateTypeAliases;
    pub const validateAliasedType = Transform.validateAliasedType;
    pub const findDeclarationByCanonicalName = Transform.findDeclarationByCanonicalName;
    pub const namedTypeParameterCount = Transform.namedTypeParameterCount;
    pub const transformStatement = Transform.transformStatement;
    pub const transformStatements = Transform.transformStatements;
    pub const transformCondition = Transform.transformCondition;
    pub const transformConditionalBody = Transform.transformConditionalBody;
    pub const transformStatementsInCurrentScope = Transform.transformStatementsInCurrentScope;
    pub const transformForBody = Transform.transformForBody;
    pub const transformExpression = Transform.transformExpression;
    pub const transformExpressions = Transform.transformExpressions;
    pub const transformFieldInitializers = Transform.transformFieldInitializers;
    pub const transformAliasInvocation = Transform.transformAliasInvocation;
    pub const resolveUses = Resolution.resolveUses;
    pub const expressionPath = Resolution.expressionPath;
    pub const staticOwnerType = Resolution.staticOwnerType;
    pub const looksQualified = Resolution.looksQualified;
    pub const visibleDeclarationKind = Resolution.visibleDeclarationKind;
    pub const visibleFunctionDeclarations = Resolution.visibleFunctionDeclarations;
    pub const resolveName = Resolution.resolveName;
    pub const resolveQualified = Resolution.resolveQualified;
    pub const moduleIndexFromUsePath = Resolution.moduleIndexFromUsePath;
    pub const siblingModuleIndex = Resolution.siblingModuleIndex;
    pub const qualifiedUseTarget = Resolution.qualifiedUseTarget;
    pub const qualifiedExpressionTarget = Resolution.qualifiedExpressionTarget;
    pub const canonicalPathFromBindings = Resolution.canonicalPathFromBindings;
    pub const longestModuleTarget = Resolution.longestModuleTarget;
    pub const findModule = Resolution.findModule;
    pub const internalAccess = Resolution.internalAccess;
    pub const declarationsNamed = Resolution.declarationsNamed;
    pub const findDirect = Resolution.findDirect;
    pub const findDirectByPosition = Resolution.findDirectByPosition;
    pub const declarationIsClass = Resolution.declarationIsClass;
    pub const declarationHasConstructors = Resolution.declarationHasConstructors;
    pub const declarationIsEnum = Resolution.declarationIsEnum;
    pub const findExport = Resolution.findExport;
    pub const pushLocalScope = Resolution.pushLocalScope;
    pub const popLocalScope = Resolution.popLocalScope;
    pub const declareLocal = Resolution.declareLocal;
    pub const findLocal = Resolution.findLocal;
    pub const fail = Resolution.fail;
};
