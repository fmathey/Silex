const Semantic = @import("../Semantic.zig");

pub const NativeResultShape = struct {
    success_type: Semantic.Type,
    failure_type: Semantic.Type,
};

pub const NativeResultOwnedAction = enum { raw_free, guard, reset };
