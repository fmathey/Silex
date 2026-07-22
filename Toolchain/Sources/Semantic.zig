const Types = @import("Semantic/Types.zig");
const AnalyzerModule = @import("Semantic/Analyzer.zig");
const Support = @import("Semantic/Support.zig");

pub const TransferMode = Types.TransferMode;
pub const Type = Types.Type;
pub const FunctionType = Types.FunctionType;
pub const StructureType = Types.StructureType;
pub const ProtocolType = Types.ProtocolType;
pub const EnumType = Types.EnumType;
pub const ReferenceType = Types.ReferenceType;
pub const FixedArrayType = Types.FixedArrayType;
pub const Expression = Types.Expression;
pub const Statement = Types.Statement;
pub const Program = Types.Program;
pub const Protocol = Types.Protocol;
pub const ProtocolMethod = Types.ProtocolMethod;
pub const ProtocolConformance = Types.ProtocolConformance;
pub const Enum = Types.Enum;
pub const EnumVariant = Types.EnumVariant;
pub const Structure = Types.Structure;
pub const BaseInitializer = Types.BaseInitializer;
pub const StructureField = Types.StructureField;
pub const NativeStructureTransport = Types.NativeStructureTransport;
pub const NativeTransportField = Types.NativeTransportField;
pub const NativeResultTransport = Types.NativeResultTransport;
pub const Constructor = Types.Constructor;
pub const Drop = Types.Drop;
pub const Parameter = Types.Parameter;
pub const Function = Types.Function;
pub const Method = Types.Method;
pub const MethodId = Types.MethodId;
pub const Receiver = Types.Receiver;
pub const Analyzer = AnalyzerModule.Analyzer;
pub const astStatementsFallThrough = Support.astStatementsFallThrough;
pub const astStatementFallsThrough = Support.astStatementFallsThrough;

test {
    _ = @import("Semantic/TestsDeclarations.zig");
    _ = @import("Semantic/TestsTypes.zig");
    _ = @import("Semantic/TestsOwnership.zig");
    _ = @import("Semantic/TestsCalls.zig");
}
