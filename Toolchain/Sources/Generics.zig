const SpecializerModule = @import("Generics/Specializer.zig");

pub const Specializer = SpecializerModule.Specializer;

test {
    _ = @import("Generics/Tests.zig");
}
