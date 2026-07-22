const std = @import("std");
const ServerModule = @import("Lsp/Server.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn run(allocator: Allocator, io: Io, environ_map: *const std.process.Environ.Map) !u8 {
    return ServerModule.run(allocator, io, environ_map);
}

test {
    _ = @import("Lsp/Tests.zig");
}
