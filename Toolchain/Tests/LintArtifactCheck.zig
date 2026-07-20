const std = @import("std");

pub fn main(init: std.process.Init) !void {
    if (std.Io.Dir.cwd().statFile(init.io, ".silex", .{})) |_| {
        return error.LintCreatedCompilationArtifacts;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |other| return other,
    }
}
