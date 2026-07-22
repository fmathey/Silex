const Implementation = @import("Parser/Implementation.zig");

pub const Parser = Implementation.Parser;

test {
    _ = @import("Parser/TestsLanguage.zig");
    _ = @import("Parser/TestsTypes.zig");
}
