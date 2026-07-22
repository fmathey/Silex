const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("../Ast.zig");
const Semantic = @import("../Semantic.zig");
const Implementation = @import("Implementation.zig");

const Allocator = std.mem.Allocator;

const generate = Implementation.generate;
const generateWithSources = Implementation.generateWithSources;

fn resolveSingleTestProgram(allocator: Allocator, program: Ast.Program) !Ast.Program {
    const Modules = @import("../Modules.zig");
    const project = @import("../Project.zig").Project{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = true,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = program }});
    return resolver.resolve();
}

test "generate try as an ordinary early Result return" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\enum Failure { denied }
        \\func read() Result<int, Failure> { return Result<int, Failure>.failure(Failure.denied()) }
        \\func load() Result<int, Failure> {
        \\    let value = try read()
        \\    return Result<int, Failure>.success(value)
        \\}
        \\func main() {}
    );
    const resolved = try resolveSingleTestProgram(allocator, try parser.parse());
    var specializer = Generics.Specializer.init(allocator, resolved);
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try specializer.specialize()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "const auto silexTry") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, ".variant == 1) return SilexEnum") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "throw") == null);
}

test "generate Result main boundary" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() Result<void,str> {
        \\    return Result<void,str>.failure("failed")
        \\}
    );
    const resolved = try resolveSingleTestProgram(allocator, try parser.parse());
    var specializer = Generics.Specializer.init(allocator, resolved);
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try specializer.specialize()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexEnum0 silexMain()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const auto result = SilexGenerated::silexMain();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::cerr << \"error: \" << result.get<std::string>(0) << '\\n';") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (result.variant == 1)") != null);
}

test "generate typed variables and control flow" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { let count = 5; if (!(count < 3)) { print(\"yes\"); } else { print(\"no\"); } }",
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "const std::int64_t silexValue0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (!(silexValue0 < std::int64_t{3}))") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "} else {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::string{\"yes\"}") != null);
}

test "generate negative collection indexes and ordered slices" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() { let values = [10, 20, 30]; let last = values[-1]; let middle = values[1:-1]; }",
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexCollectionAt(") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const auto& silexSliceValues") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const std::int64_t silexSliceStart") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const std::int64_t silexSliceEnd") != null);
}

test "generate checked explicit numeric conversion" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { let source:int = 12; print(source as uint8); }");
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "checkedConvert<std::uint8_t>(silexValue0, SilexSourceLocation{0, 1, 66}, \"int\", \"uint8\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "integerIsExactlyRepresentable") != null);
}

test "generate UTF-8 strings and their length" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { print(\"A\\u{00E9}\\0\".count()); }");
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::string{\"A\\303\\251\\000\", 4}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexStringLength(std::string{") != null);
}

test "generate string native return bridge" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "native func native_read_text() str\nfunc main() {}\n");
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Console.native_read_text";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Console"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" void silexNative_Console_native_read_text(char** output_bytes, std::int64_t* output_length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::string callNativeStringFunction") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "void silexNativeRelease(void* pointer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeRelease(outputBytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "returned invalid UTF-8") != null);
}

test "generate scalar structure native return bridge" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeDimensions { let columns:int; let rows:int }
        \\native func native_dimensions() NativeDimensions
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Console.native_dimensions";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Console"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "struct SilexNative_Console_NativeDimensions {",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" void silexNative_Console_native_dimensions(SilexNative_Console_NativeDimensions* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "SilexStruct0(SilexNativeReturnTag{}, silexNativeOutput.field0, silexNativeOutput.field1)",
    ) != null);
}

test "generate owned string structure native return bridge" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeMessage { let code:int; let title:str; let detail:str }
        \\native func native_message() NativeMessage
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Events.native_message";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Events"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "char* field1Bytes = nullptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::int64_t field1Length = 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeRelease(silexNativeOutput.field1Bytes);silexNativeRelease(silexNativeOutput.field2Bytes);throw;") != null);
    try std.testing.expect(std.mem.count(u8, cpp, "silexNativeGuard_field1.reset();") >= 4);
    try std.testing.expect(std.mem.count(u8, cpp, "silexNativeGuard_field2.reset();") >= 4);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "nativeStructureFieldRuntimeError(\"Events\", \"native_message\", \"detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexNativeString_field1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexNativeString_field2)") != null);
}

test "generate optional native return bridges" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Message { let code:int; let text:str }
        \\native func native_integer() int?
        \\native func native_text() str?
        \\native func native_message() Message?
        \\func main() {}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Events.native_integer";
    @constCast(program.functions)[1].name = "Events.native_text";
    @constCast(program.functions)[2].name = "Events.native_message";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Events"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" bool silexNative_Events_native_integer(std::int64_t* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" bool silexNative_Events_native_text(char** output_bytes, std::int64_t* output_length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" bool silexNative_Events_native_message(SilexNative_Events_Message* output);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (!silexNativePresent) return std::nullopt") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "returned an owned buffer while reporting absence") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::optional<SilexStruct0>") != null);
}

test "generate independent scalar structure native parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeBounds { let width:int; let height:int }
        \\native func native_contains(first:NativeBounds, second:NativeBounds) bool
        \\func main() {
        \\    let first = NativeBounds(width:10, height:20)
        \\    let second = NativeBounds(width:30, height:40)
        \\    print(native_contains(first, second))
        \\}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Geometry.native_contains";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Geometry"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" bool silexNative_Geometry_native_contains(const SilexNative_Geometry_NativeBounds* silexValue0, const SilexNative_Geometry_NativeBounds* silexValue1);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const auto& silexNativeStructure0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexNative_Geometry_NativeBounds silexNativeInput0{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeStructure0.field0, silexNativeStructure0.field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNative_Geometry_native_contains(&silexNativeInput0, &silexNativeInput1)") != null);
}

test "generate borrowed string fields in native structure parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeRequest { let path:str; let mode:int; let note:str }
        \\native func native_round_trip(request:NativeRequest) NativeRequest
        \\func main() {
        \\    let request = NativeRequest(path:"é\\0", mode:7, note:"")
        \\    print(native_round_trip(request).mode)
        \\}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Files.native_round_trip";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Files"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexNative_Files_NativeRequestInput {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const char* field0Bytes;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexNative_Files_NativeRequest {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "char* field0Bytes = nullptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0(std::string silexField0") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "silexNativeStructure0.field0.data(), static_cast<std::int64_t>(silexNativeStructure0.field0.size())",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "silexNative_Files_native_round_trip(&silexNativeInput0, &silexNativeOutput)",
    ) != null);
}

test "generate borrowed uint8 collection native parameters" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_checksum(bytes:uint8[]) uint64
        \\native func native_block(bytes:uint8[4]) bool
        \\func main() {
        \\    let list:uint8[] = [0, 1, 255]
        \\    let block:uint8[4] = [1, 2, 3, 4]
        \\    print(native_checksum(list))
        \\    print(native_block(block))
        \\}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Bytes.native_checksum";
    @constCast(program.functions)[1].name = "Bytes.native_block";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Bytes"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" std::uint64_t silexNative_Bytes_native_checksum(const std::uint8_t* silexValue0Bytes, std::int64_t silexValue0Length);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const auto& silexNativeBytes0 = silexVariable0;") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "silexNative_Bytes_native_checksum(silexNativeBytes0.data(), static_cast<std::int64_t>(silexNativeBytes0.size()))",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "silexNative_Bytes_native_block(silexNativeBytes0.data(), static_cast<std::int64_t>(silexNativeBytes0.size()))",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const T* data() const { return values_.data(); }") != null);
}

test "generate synchronous scalar native callback trampolines" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_visit(limit:int, visitor:func(int) bool) int
        \\func main() {
        \\    var total:int = 0
        \\    print(native_visit(3, func(value:int) bool { total += value; return true }))
        \\}
    );
    const program = try parser.parse();
    @constCast(program.functions)[0].name = "Visitors.native_visit";
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Visitors"};
    const cpp = try generate(allocator, try analyzer.analyze(program));

    try std.testing.expect(std.mem.indexOf(
        u8,
        cpp,
        "extern \"C\" std::int64_t silexNative_Visitors_native_visit(std::int64_t silexValue0, bool (*silexValue1)(void*, std::int64_t), void* silexValue1_context);",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "auto silexNativeCallback1 = silexMakeFunction<") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "+[](void* silexNativeContext, std::int64_t silexNativeArgument0) -> bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "static_cast<SilexFunction<bool(std::int64_t)>*>(silexNativeContext)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "}, &silexNativeCallback1") != null);
}

test "generate deferred callback queue ownership and cancellation" {
    const Parser = @import("../Parser.zig").Parser;
    const Modules = @import("../Modules.zig");
    const Project = @import("../Project.zig").Project;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\public native resource Watch { drop stop_watch }
        \\native func start_watch(callback:deferred func(int)) Watch
        \\func main() {
        \\    let watch = start_watch(deferred func(value:int) {})
        \\    print(dispatch_callbacks(watch))
        \\    stop_watch(watch)
        \\}
    );
    const project = Project{
        .program_name = "Events",
        .target_module = 0,
        .modules = &.{.{ .name = "Events", .sources = &.{"Events.sx"} }},
        .single_file = false,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = try parser.parse() }});
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Events"};
    const cpp = try generate(allocator, try analyzer.analyze(try resolver.resolve()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::make_shared<SilexDeferredCallbackStateFor<void(std::int64_t)>>") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeCallback->enqueue(silexNativeArgument0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexNativeDeferred0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeDropResource.silexCancelDeferred()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexDispatchCallbacks(silexValue") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "prior->dispatchDeferred()") == null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (!acquisition->deferred) prior.push_back(acquisition)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeDeferred0->cancel();silexNativeDeferred0.reset();nativeFunctionRuntimeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::scoped_lock lock(mutex)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexDeferredCallbackEnqueueTestGate.engage()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexAcceptedDeferredCallbackEvents.fetch_add(1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "event.markDispatched()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexDestroyedDeferredCallbackEvents.fetch_add(1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexCancelledDeferredCallbackEnqueues.fetch_add(1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "ready.swap(pending)") != null);
}

test "generate owned uint8 list native returns" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\native func native_compress(bytes:uint8[]) uint8[]
        \\native func native_read(path:str) Result<uint8[],str>
        \\func main() {
        \\    let bytes:uint8[] = [0, 255]
        \\    let compressed = native_compress(bytes)
        \\    let read = native_read("file")
        \\}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Bytes.native_compress";
    @constCast(ast.functions)[1].name = "Bytes.native_read";
    var specializer = Generics.Specializer.init(allocator, ast);
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Bytes"};
    const cpp = try generate(allocator, try analyzer.analyze(try specializer.specialize()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "extern \"C\" void silexNative_Bytes_native_compress(const std::uint8_t* silexValue0Bytes, std::int64_t silexValue0Length, std::uint8_t** output_bytes, std::int64_t* output_length);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexList<std::uint8_t> silexNativeResult;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "returned a negative length") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::uint8_t* successBytes = nullptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::unique_ptr<std::uint8_t, decltype(&silexNativeRelease)> silexNativeGuard_success") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexList<std::uint8_t> silexNativeBytes_success;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexNativeBytes_success)") != null);
}

test "generate native resource self arguments in extension methods" {
    const Parser = @import("../Parser.zig").Parser;
    const Modules = @import("../Modules.zig");
    const Project = @import("../Project.zig").Project;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\public native resource File { drop discard_file }
        \\native func native_read(file:&File, buffer:&uint8[..]) Result<int,str>
        \\extend File {
        \\    public func read(buffer:&uint8[..]) Result<int,str> {
        \\        return native_read(self, buffer)
        \\    }
        \\}
        \\func main() {}
    );
    const project = Project{
        .program_name = "Files",
        .target_module = 0,
        .modules = &.{.{ .name = "Files", .sources = &.{"Files.sx"} }},
        .single_file = false,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = try parser.parse() }});
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Files"};
    const cpp = try generate(allocator, try analyzer.analyze(try resolver.resolve()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "(*this).silexBorrowNativeHandle()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "*this.silexBorrowNativeHandle()") == null);
}

test "generate validated native Result bridges" {
    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct NativeFile { let handle:int; let path:str }
        \\native func native_open(path:str) Result<NativeFile,str>
        \\native func native_save() Result<void,str>
        \\func main() {
        \\    let opened = native_open("file")
        \\    let saved = native_save()
        \\}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Files.native_open";
    @constCast(ast.functions)[1].name = "Files.native_save";
    var specializer = Generics.Specializer.init(allocator, ast);
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Files"};
    const cpp = try generate(allocator, try analyzer.analyze(try specializer.specialize()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexNative_Files_native_openResult {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexNative_Files_NativeFile successValue{};") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "char* failureBytes = nullptr;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "returned an owned buffer in the inactive failure branch") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "returned an unknown Result tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexNativeRelease(silexNativeOutput.successValue.field1Bytes)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexNativeString_failure)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexNative_Files_native_saveResult") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(
        u8,
        cpp,
        "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_success_field1",
    ));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(
        u8,
        cpp,
        "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_failure",
    ));
}

test "generate recursive structural equality" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int var y:int }
        \\struct Player { var name:str var position:Position }
        \\func main() void {
        \\    print(Player(name:"Ada", position:Position(x:10, y:20)) == Player(name:"Ada", position:Position(x:10, y:20)))
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "bool silexEqualSilexStruct0(const SilexStruct0&, const SilexStruct0&);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "return left.field0 == right.field0 && silexEqualSilexStruct0(left.field1, right.field1);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexEqualSilexStruct1(SilexStruct1{") != null);
}

test "generate while loop" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(
        allocator,
        "func main() void { var count = 2; while (count > 0) { count = count - 1; } }",
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "while (silexValue0 > std::int64_t{0}) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0 = checkedSubtract(silexValue0, std::int64_t{1}, SilexSourceLocation{") != null);
}

test "generate checked integer operations with backend overflow primitives" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    var value:int8 = 2
        \\    value += 1
        \\    value -= 1
        \\    value *= 2
        \\    value /= 2
        \\    print(value % 2)
        \\    value++
        \\    value--
        \\    print(-value)
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "__builtin_add_overflow(left, right, &result)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "__builtin_sub_overflow(left, right, &result)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "__builtin_mul_overflow(left, right, &result)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "__builtin_sub_overflow(T{0}, value, &result)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "gnu::cold, gnu::noinline") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (right == 0) [[unlikely]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0 = checkedAdd(silexValue0, std::int8_t{1}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0 = checkedSubtract(silexValue0, std::int8_t{1}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0 = checkedMultiply(silexValue0, std::int8_t{2}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0 = checkedDivide(silexValue0, std::int8_t{2}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "checkedRemainder(silexValue0, std::int8_t{2}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "checkedNegate(silexValue0, SilexSourceLocation{") != null);
}

test "native output releases are observed exactly once" {
    if (build_options.developer_zig.len == 0) return error.SkipZigTest;

    const Parser = @import("../Parser.zig").Parser;
    const Generics = @import("../Generics.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Message { let first:str; let second:str }
        \\native func native_text() str
        \\native func native_message() Message
        \\native func native_optional() str?
        \\native func native_bytes() uint8[]
        \\native func native_result() Result<uint8[],str>
        \\native func native_failure() Result<uint8[],str>
        \\native func native_exception() str
        \\func main() {
        \\    let text = native_text()
        \\    let message = native_message()
        \\    let optional = native_optional()
        \\    let bytes = native_bytes()
        \\    let result = native_result()
        \\    let failure = native_failure()
        \\    let exception = native_exception()
        \\}
    );
    const ast = try parser.parse();
    @constCast(ast.functions)[0].name = "Probe.native_text";
    @constCast(ast.functions)[1].name = "Probe.native_message";
    @constCast(ast.functions)[2].name = "Probe.native_optional";
    @constCast(ast.functions)[3].name = "Probe.native_bytes";
    @constCast(ast.functions)[4].name = "Probe.native_result";
    @constCast(ast.functions)[5].name = "Probe.native_failure";
    @constCast(ast.functions)[6].name = "Probe.native_exception";
    var specializer = Generics.Specializer.init(allocator, ast);
    var analyzer = Semantic.Analyzer.init(allocator);
    analyzer.native_module_names = &.{"Probe"};
    const cpp = try generate(allocator, try analyzer.analyze(try specializer.specialize()));

    const observer =
        \\#define SILEX_NATIVE_RELEASE_OBSERVER(pointer) silexNativeTestObserveRelease(pointer)
        \\extern "C" void silexNativeTestObserveRelease(void* pointer);
    ;
    const native_definitions =
        \\#include <cstdlib>
        \\#include <cstring>
        \\#include <cstdio>
        \\#include <stdexcept>
        \\namespace {
        \\struct Allocation { void* pointer; int releases; };
        \\Allocation allocations[32]{};
        \\std::size_t allocationCount = 0;
        \\char* allocateText(const char* text, std::size_t length) {
        \\    auto* result = static_cast<char*>(std::malloc(length));
        \\    std::memcpy(result, text, length);
        \\    allocations[allocationCount++] = {result, 0};
        \\    return result;
        \\}
        \\char* allocateText(const char* text) {
        \\    return allocateText(text, std::strlen(text));
        \\}
        \\std::uint8_t* allocateBytes() {
        \\    auto* result = static_cast<std::uint8_t*>(std::malloc(2));
        \\    result[0] = 4; result[1] = 2;
        \\    allocations[allocationCount++] = {result, 0};
        \\    return result;
        \\}
        \\int testMode() {
        \\    auto* file = std::fopen("Mode.txt", "r");
        \\    if (file == nullptr) std::_Exit(4);
        \\    int mode = 0;
        \\    if (std::fscanf(file, "%d", &mode) != 1) std::_Exit(5);
        \\    std::fclose(file);
        \\    return mode;
        \\}
        \\void verifyReleases() {
        \\    for (std::size_t index = 0; index < allocationCount; index += 1) {
        \\        if (allocations[index].releases != 1) std::_Exit(2);
        \\    }
        \\}
        \\struct RegisterVerifier { RegisterVerifier() { std::atexit(verifyReleases); } } registerVerifier;
        \\}
        \\extern "C" void silexNativeTestObserveRelease(void* pointer) {
        \\    if (pointer == nullptr) return;
        \\    for (std::size_t index = allocationCount; index > 0; index -= 1) {
        \\        auto& allocation = allocations[index - 1];
        \\        if (allocation.pointer != pointer || allocation.releases != 0) continue;
        \\        allocation.releases += 1;
        \\        return;
        \\    }
        \\    std::_Exit(3);
        \\}
        \\extern "C" void silexNative_Probe_native_text(char** bytes, std::int64_t* length) {
        \\    *bytes = allocateText("text"); *length = 4;
        \\}
        \\extern "C" void silexNative_Probe_native_message(SilexNative_Probe_Message* output) {
        \\    output->field0Bytes = allocateText("first"); output->field0Length = 5;
        \\    output->field1Bytes = allocateText("second"); output->field1Length = 6;
        \\    if (testMode() == 1) output->field1Length = -1;
        \\}
        \\extern "C" bool silexNative_Probe_native_optional(char** bytes, std::int64_t* length) {
        \\    *bytes = allocateText("optional"); *length = 8; return testMode() != 2;
        \\}
        \\extern "C" void silexNative_Probe_native_bytes(std::uint8_t** bytes, std::int64_t* length) {
        \\    *bytes = allocateBytes(); *length = testMode() == 3 ? -1 : 2;
        \\}
        \\extern "C" void silexNative_Probe_native_result(SilexNative_Probe_native_resultResult* output) {
        \\    const int mode = testMode();
        \\    if (mode == 7) {
        \\        const char invalid[] = {static_cast<char>(0xff)};
        \\        output->tag = SilexNative_Probe_native_resultResultTag_failure;
        \\        output->failureBytes = allocateText(invalid, 1); output->failureLength = 1;
        \\        return;
        \\    }
        \\    output->successBytes = allocateBytes(); output->successLength = 2;
        \\    output->tag = SilexNative_Probe_native_resultResultTag_success;
        \\    if (mode == 4) {
        \\        output->failureBytes = allocateText("inactive"); output->failureLength = 8;
        \\    } else if (mode == 5) {
        \\        output->failureBytes = allocateText("unknown"); output->failureLength = 7;
        \\        output->tag = static_cast<SilexNative_Probe_native_resultResultTag>(7);
        \\    }
        \\}
        \\extern "C" void silexNative_Probe_native_failure(SilexNative_Probe_native_failureResult* output) {
        \\    output->tag = SilexNative_Probe_native_failureResultTag_failure;
        \\    output->failureBytes = allocateText("failure"); output->failureLength = 7;
        \\}
        \\extern "C" void silexNative_Probe_native_exception(char** bytes, std::int64_t* length) {
        \\    *bytes = allocateText("exception"); *length = 9;
        \\    if (testMode() == 6) throw std::runtime_error("expected");
        \\}
    ;
    const probe = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ cpp, native_definitions });

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Observer.hpp", .data = observer });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Probe.cpp", .data = probe });
    const executable_name = if (builtin.os.tag == .windows) "Probe.exe" else "Probe";
    const compilation = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{ build_options.developer_zig, "c++", "-std=c++23", "-include", "Observer.hpp", "Probe.cpp", "-o", executable_name },
        .cwd = .{ .dir = temporary.dir },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(compilation.stdout);
    defer std.testing.allocator.free(compilation.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (compilation.term) {
        .exited => |code| code,
        else => 1,
    });

    const executable_argument = if (builtin.os.tag == .windows) ".\\Probe.exe" else "./Probe";
    for (0..8) |mode| {
        const mode_text = try std.fmt.allocPrint(allocator, "{d}", .{mode});
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Mode.txt", .data = mode_text });
        const execution = try std.process.run(std.testing.allocator, std.testing.io, .{
            .argv = &.{executable_argument},
            .cwd = .{ .dir = temporary.dir },
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        defer std.testing.allocator.free(execution.stdout);
        defer std.testing.allocator.free(execution.stderr);
        const expected_exit_code: u8 = if (mode == 0) 0 else 1;
        try std.testing.expectEqual(expected_exit_code, switch (execution.term) {
            .exited => |code| code,
            else => 255,
        });
    }
}

test "optimized backend eliminates a provably unnecessary integer check" {
    if (build_options.developer_zig.len == 0) return error.SkipZigTest;

    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    let value:int = 7
        \\    let numerator:int = 84
        \\    print((40 + 2) * 2 - 4)
        \\    print(-value)
        \\    print(numerator / 2)
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "Probe.cpp", .data = cpp });

    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{
            build_options.developer_zig,
            "c++",
            "-O2",
            "-std=c++23",
            "-S",
            "-emit-llvm",
            "Probe.cpp",
            "-o",
            "Probe.ll",
        },
        .cwd = .{ .dir = temporary.dir },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (result.term) {
        .exited => |code| code,
        else => 1,
    });

    const llvm_ir = try temporary.dir.readFileAlloc(
        std.testing.io,
        "Probe.ll",
        std.testing.allocator,
        .limited(4 * 1024 * 1024),
    );
    defer std.testing.allocator.free(llvm_ir);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "llvm.sadd.with.overflow") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "llvm.ssub.with.overflow") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "llvm.smul.with.overflow") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "checkedDivide") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "checkedNegate") == null);

    const executable_name = if (builtin.os.tag == .windows) "Probe.exe" else "Probe";
    const compile_executable = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{
            build_options.developer_zig,
            "c++",
            "-O2",
            "-std=c++23",
            "Probe.cpp",
            "-o",
            executable_name,
        },
        .cwd = .{ .dir = temporary.dir },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(compile_executable.stdout);
    defer std.testing.allocator.free(compile_executable.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (compile_executable.term) {
        .exited => |code| code,
        else => 1,
    });

    const executable_argument = if (builtin.os.tag == .windows) ".\\Probe.exe" else "./Probe";
    const execution = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{executable_argument},
        .cwd = .{ .dir = temporary.dir },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(execution.stdout);
    defer std.testing.allocator.free(execution.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (execution.term) {
        .exited => |code| code,
        else => 1,
    });
    try std.testing.expectEqualStrings("80\n-7\n42\n", execution.stdout);
    try std.testing.expectEqualStrings("", execution.stderr);
}

test "generate function declarations calls and returns" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void { print(double(5)) }
        \\func double(value:int) int { return value * 2 }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::int64_t silexFunction1(std::int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "return checkedMultiply(silexValue0, std::int64_t{2}, SilexSourceLocation{") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexFunction1(std::int64_t{5})") != null);
}

test "generate value structs and member access" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { var x:int; var y:int }
        \\func main() void { var position = Position(y:20, x:10); position.x = 12; print(position.x) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexStruct0 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0{std::int64_t{10}, std::int64_t{20}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0.field0 = std::int64_t{12};") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "namespace SilexGenerated {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "int silexMain()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "const int result = SilexGenerated::silexMain();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "int main(int argumentCount, char** argumentValues)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexRuntimeArgumentCountValue = argumentCount;") != null);
}

test "generate class references identity access and cycle tracing" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Node { var next:Node? = null; public func clear() { self.next = null } }
        \\func main() { var first = Node(); var alias = first; alias.clear(); assert(first == alias) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexClass0 : SilexObject") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexRef<SilexClass0>") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexMake<SilexClass0>") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue1->method0_0()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "(silexValue0 == silexValue1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "unreachable class graph was not collected") != null);
}

test "generate erased protocol storage witnesses and dynamic calls" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\protocol Drawable { func draw() str }
        \\struct Icon : Drawable { func draw() str { return "icon" } }
        \\class Player : Drawable { public func draw() str { return "player" } }
        \\func main() { var value:Drawable = Icon(); value = Player(); print(value.draw()) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexProtocol0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::unique_ptr<StorageBase> clone() const") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexWitness0_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexWitness0_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexProtocol0::make(SilexStruct0{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexProtocol0::make(silexMake<SilexClass1>()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, ".method0_0()") != null);
}

test "generate drop before field clearing with automatic base chaining" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Base { drop { print("base") } }
        \\class Child : Base { drop { print("child") } }
        \\func main() { var child = Child() }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "object->silexDrop();\n        object->silexClear();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "for (SilexObject* object : garbage) object->silexDrop();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexClass1::silexDrop()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexClass0::silexDrop();") != null);
}

test "generate unique resource struct as movable RAII value" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Resource {
        \\    let handle:int
        \\    static func open(handle:int) Resource { return Resource(handle:handle) }
        \\    drop { print(self.handle) }
        \\}
        \\func consume(resource:Resource) {}
        \\func main() {
        \\    var first = Resource.open(7)
        \\    let second = move first
        \\    first = Resource.open(8)
        \\    consume(move first)
        \\    consume(move second)
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0(std::int64_t silexField0) : field0(std::move(silexField0)) {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0(const SilexStruct0&) = delete;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0& operator=(const SilexStruct0&) = delete;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "bool silexOwnsResource = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0(SilexStruct0&& other) noexcept;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0& operator=(SilexStruct0&& other) noexcept;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "void silexDropResource();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "~SilexStruct0();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexOwnsResource(std::exchange(other.silexOwnsResource, false))") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "if (silexOwnsResource) silexDropResource();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::move(silexValue") != null);
}

test "generate inferred const and mutating methods" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Counter {
        \\    var value:int
        \\    func current() int { return self.value }
        \\    func increment() void { self.value = self.value + 1 }
        \\}
        \\func main() void { var counter = Counter(value:1); counter.increment(); print(counter.current()) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::int64_t method0() const;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "void method1();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0::method0() const") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0::method1()") != null);
}

test "generate cascades through one stable receiver" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\func main() void {
        \\    var values:int[] = []
        \\        ..append(1)
        \\        ..reverse()
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "decltype(auto) silexCascade") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexCascade(std::vector<std::int64_t>{}, [&](auto& silexCascadeValue) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexCascadeValue.push_back(std::int64_t{1});") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::reverse(silexCascadeValue.begin(), silexCascadeValue.end());") != null);
}

test "generate read reference parameters as const references" {
    const Parser = @import("../Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Resource { let handle:int; drop {} }
        \\func inspect(resource:@Resource) int { return resource.handle }
        \\func main() { let resource = Resource(handle:1); print(inspect(resource)) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try resolveSingleTestProgram(allocator, try parser.parse())));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::int64_t silexFunction0(const SilexStruct0&") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexFunction0(silexValue") != null);
}

test "read view parameters preserve const elements" {
    var element: Semantic.Type = .uint8;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    var generator = Implementation.Generator{};
    try generator.appendCppParameterType(
        std.testing.allocator,
        &output,
        .{ .view = &element },
        .borrow,
    );
    try std.testing.expectEqualStrings(
        "const SilexView<const std::uint8_t>&",
        output.items,
    );
}
