const std = @import("std");
const Semantic = @import("Semantic.zig");
const Implementation = @import("CppGenerator/Implementation.zig");

const Allocator = std.mem.Allocator;

pub fn generate(allocator: Allocator, program: Semantic.Program) ![]u8 {
    return Implementation.generate(allocator, program);
}

pub fn generateWithSources(
    allocator: Allocator,
    program: Semantic.Program,
    source_paths: []const []const u8,
) ![]u8 {
    return Implementation.generateWithSources(allocator, program, source_paths);
}

test {
    _ = @import("CppGenerator/Tests.zig");
}
