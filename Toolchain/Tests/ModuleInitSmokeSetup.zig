const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    if (std.mem.eql(u8, args[1], "clean")) {
        try std.Io.Dir.cwd().deleteTree(init.io, args[2]);
        return;
    }
    if (!std.mem.eql(u8, args[1], "populate")) return error.InvalidArguments;

    const main_path = try std.fs.path.join(allocator, &.{ args[2], "Main.sx" });
    const module_directory = try std.fs.path.join(allocator, &.{ args[2], "Answer" });
    const silex_path = try std.fs.path.join(allocator, &.{ module_directory, "Runtime.sx" });
    const native_path = try std.fs.path.join(allocator, &.{ module_directory, "Module.cpp" });
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = main_path,
        .data =
        \\import Answer
        \\
        \\func main() {
        \\    print(Answer.value())
        \\}
        \\
        ,
    });
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = silex_path,
        .data =
        \\native func native_value() int
        \\
        \\pub func value() int {
        \\    return native_value()
        \\}
        \\
        ,
    });
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = native_path,
        .data =
        \\#include <cstdint>
        \\
        \\extern "C" std::int64_t silexNative_Answer_native_value() {
        \\    return 42;
        \\}
        \\
        ,
    });
}
