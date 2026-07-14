const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("Ast.zig");
const Semantic = @import("Semantic.zig");
const Source = @import("Source.zig");

const Allocator = std.mem.Allocator;
const GenerateError = Allocator.Error;

pub fn generate(allocator: Allocator, program: Semantic.Program) ![]u8 {
    return generateWithSources(allocator, program, &.{"<memory>"});
}

pub fn generateWithSources(
    allocator: Allocator,
    program: Semantic.Program,
    source_paths: []const []const u8,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(allocator,
        \\#include <algorithm>
        \\#include <cstddef>
        \\#include <cstdint>
        \\#include <cstdlib>
        \\#include <exception>
        \\#include <array>
        \\#include <bit>
        \\#include <cmath>
        \\#include <iostream>
        \\#include <iterator>
        \\#include <limits>
        \\#include <memory>
        \\#include <string>
        \\#include <type_traits>
        \\#include <utility>
        \\#include <vector>
        \\
    );
    for (program.functions) |function| {
        if (!function.is_native) continue;
        try generateNativeFunctionSignature(allocator, &output, function, true);
        try output.appendSlice(allocator, ";\n");
    }
    if (containsNativeFunction(program.functions)) try output.append(allocator, '\n');
    try output.appendSlice(allocator,
        \\
        \\namespace SilexGenerated {
        \\
        \\// -----------------------------------------------------------------------------
        \\
    );
    try generateSourcePaths(allocator, &output, source_paths);
    try output.appendSlice(allocator,
        \\
        \\struct SilexSourceLocation {
        \\    std::size_t file;
        \\    std::size_t line;
        \\    std::size_t column;
        \\};
        \\
        \\const char* silexSourcePath(SilexSourceLocation location) {
        \\    return location.file < k_silexSourcePathCount ? k_silexSourcePaths[location.file] : "<unknown>";
        \\}
        \\
        \\template <typename T> void printIntegerValue(T value) {
        \\    if constexpr (sizeof(T) == 1) {
        \\        std::cerr << static_cast<int>(value);
        \\    } else {
        \\        std::cerr << value;
        \\    }
        \\}
        \\
        \\template <typename T> void printNumericValue(T value) {
        \\    if constexpr (std::is_integral_v<T>) {
        \\        printIntegerValue(value);
        \\    } else {
        \\        std::cerr << value;
        \\    }
        \\}
        \\
        \\template <typename Source>
        \\[[noreturn, gnu::cold, gnu::noinline]] void conversionRuntimeError(
        \\    SilexSourceLocation location,
        \\    const char* sourceType,
        \\    const char* targetType,
        \\    const char* failure,
        \\    Source value
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: cannot convert '" << sourceType << "' to '" << targetType
        \\              << "': value ";
        \\    printNumericValue(value);
        \\    std::cerr << ' ' << failure << '\n';
        \\    std::exit(1);
        \\}
        \\
        \\[[noreturn]] void nativeFunctionRuntimeError(
        \\    const char* module,
        \\    const char* function,
        \\    const char* message
        \\) {
        \\    std::cerr << "runtime error: native function '" << module << '.' << function
        \\              << "' failed: " << message << '\n';
        \\    std::exit(1);
        \\}
        \\
        \\template <typename Call>
        \\decltype(auto) callNativeFunction(const char* module, const char* function, Call&& call) {
        \\    try {
        \\        return std::forward<Call>(call)();
        \\    } catch (const std::exception& exception) {
        \\        nativeFunctionRuntimeError(module, function, exception.what());
        \\    } catch (...) {
        \\        nativeFunctionRuntimeError(module, function, "unknown native exception");
        \\    }
        \\}
        \\
        \\template <typename Target, typename Source> bool integerIsExactlyRepresentable(Source value) {
        \\    using Unsigned = std::make_unsigned_t<Source>;
        \\    const Unsigned magnitude = [&] {
        \\        if constexpr (std::is_signed_v<Source>) {
        \\            return value < 0 ? static_cast<Unsigned>(-(value + 1)) + 1 : static_cast<Unsigned>(value);
        \\        } else {
        \\            return value;
        \\        }
        \\    }();
        \\    if (magnitude == 0) return true;
        \\    const auto bits = std::bit_width(static_cast<std::uintmax_t>(magnitude));
        \\    constexpr auto precision = std::numeric_limits<Target>::digits;
        \\    if (bits <= precision) return true;
        \\    const auto discardedBits = bits - precision;
        \\    const auto mask = (std::uintmax_t{1} << discardedBits) - 1;
        \\    return (static_cast<std::uintmax_t>(magnitude) & mask) == 0;
        \\}
        \\
        \\template <typename Target, typename Source>
        \\Target checkedConvert(Source value, SilexSourceLocation location, const char* sourceType, const char* targetType) {
        \\    if constexpr (std::is_integral_v<Source> && std::is_integral_v<Target>) {
        \\        if (!std::in_range<Target>(value)) [[unlikely]] {
        \\            conversionRuntimeError(location, sourceType, targetType, "is outside the target range", value);
        \\        }
        \\    } else if constexpr (std::is_floating_point_v<Source> && std::is_integral_v<Target>) {
        \\        const auto numericValue = static_cast<long double>(value);
        \\        const auto limit = std::ldexp(1.0L, std::numeric_limits<Target>::digits);
        \\        const bool inRange = std::is_signed_v<Target>
        \\            ? numericValue >= -limit && numericValue < limit
        \\            : numericValue >= 0 && numericValue < limit;
        \\        if (!std::isfinite(value) || std::trunc(value) != value || !inRange) [[unlikely]] {
        \\            conversionRuntimeError(location, sourceType, targetType, "is not an exactly representable integer", value);
        \\        }
        \\    } else if constexpr (std::is_integral_v<Source> && std::is_floating_point_v<Target>) {
        \\        if (!integerIsExactlyRepresentable<Target>(value)) [[unlikely]] {
        \\            conversionRuntimeError(location, sourceType, targetType, "loses precision", value);
        \\        }
        \\    } else {
        \\        const Target converted = static_cast<Target>(value);
        \\        if (!std::isfinite(converted) || static_cast<Source>(converted) != value) [[unlikely]] {
        \\            conversionRuntimeError(location, sourceType, targetType, "loses precision", value);
        \\        }
        \\    }
        \\    return static_cast<Target>(value);
        \\}
        \\
        \\std::int64_t silexStringLength(const std::string& value) {
        \\    std::int64_t length = 0;
        \\    for (unsigned char byte : value) {
        \\        if ((byte & 0xC0) != 0x80) ++length;
        \\    }
        \\    return length;
        \\}
        \\
        \\std::int64_t silexCollectionCount(std::size_t value, SilexSourceLocation location) {
        \\    if (value > static_cast<std::size_t>(std::numeric_limits<std::int64_t>::max())) [[unlikely]] {
        \\        std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\                  << ": runtime error: collection count is outside the range of 'int'\n";
        \\        std::exit(1);
        \\    }
        \\    return static_cast<std::int64_t>(value);
        \\}
        \\
        \\template <typename T>
        \\class SilexList {
        \\public:
        \\    using value_type = T;
        \\    using iterator = typename std::vector<T>::iterator;
        \\    using const_iterator = typename std::vector<T>::const_iterator;
        \\
        \\    SilexList() : values_(std::make_shared<std::vector<T>>()) {}
        \\    SilexList(std::initializer_list<T> values) : values_(std::make_shared<std::vector<T>>(values)) {}
        \\
        \\    std::size_t size() const { return values_->size(); }
        \\    bool empty() const { return values_->empty(); }
        \\    bool operator==(const SilexList& other) const { return *values_ == *other.values_; }
        \\    bool operator!=(const SilexList& other) const { return !(*this == other); }
        \\    const_iterator begin() const { return values_->begin(); }
        \\    const_iterator end() const { return values_->end(); }
        \\    iterator begin() { ensureUnique(); return values_->begin(); }
        \\    iterator end() { ensureUnique(); return values_->end(); }
        \\    const T& operator[](std::size_t index) const { return (*values_)[index]; }
        \\    T& operator[](std::size_t index) { ensureUnique(); return (*values_)[index]; }
        \\    void reserve(std::size_t count) { ensureUnique(); values_->reserve(count); }
        \\    void push_back(T value) { ensureUnique(); values_->push_back(std::move(value)); }
        \\    iterator insert(iterator position, T value) { ensureUnique(); return values_->insert(position, std::move(value)); }
        \\    template <typename Iterator>
        \\    iterator insert(iterator position, Iterator first, Iterator last) {
        \\        ensureUnique();
        \\        return values_->insert(position, first, last);
        \\    }
        \\    iterator erase(iterator position) { ensureUnique(); return values_->erase(position); }
        \\    void pop_back() { ensureUnique(); values_->pop_back(); }
        \\    void clear() { ensureUnique(); values_->clear(); }
        \\
        \\private:
        \\    void ensureUnique() {
        \\        if (values_.use_count() != 1) values_ = std::make_shared<std::vector<T>>(*values_);
        \\    }
        \\
        \\    std::shared_ptr<std::vector<T>> values_;
        \\};
        \\
        \\template <typename T, typename Operation>
        \\decltype(auto) silexCascade(T&& value, Operation&& operation) {
        \\    operation(value);
        \\    if constexpr (std::is_lvalue_reference_v<T&&>) {
        \\        return (value);
        \\    } else {
        \\        return std::remove_reference_t<T>(std::move(value));
        \\    }
        \\}
        \\
        \\template <typename Collection, typename Range>
        \\void silexListAppendRange(Collection& values, const Range& source) {
        \\    using T = typename Collection::value_type;
        \\    std::vector<T> copied(source.begin(), source.end());
        \\    values.reserve(values.size() + copied.size());
        \\    values.insert(
        \\        values.end(),
        \\        std::make_move_iterator(copied.begin()),
        \\        std::make_move_iterator(copied.end())
        \\    );
        \\}
        \\
        \\std::size_t silexCollectionOffset(
        \\    std::size_t count,
        \\    std::int64_t index,
        \\    bool fromEnd,
        \\    bool allowEnd,
        \\    SilexSourceLocation location
        \\) {
        \\    bool valid = false;
        \\    std::size_t offset = 0;
        \\    if (fromEnd) {
        \\        valid = index > 0 && static_cast<std::uint64_t>(index) <= count;
        \\        if (valid) offset = count - static_cast<std::size_t>(index);
        \\    } else {
        \\        valid = index >= 0 && static_cast<std::uint64_t>(index) <= count;
        \\        if (valid) {
        \\            offset = static_cast<std::size_t>(index);
        \\            valid = allowEnd || offset < count;
        \\        }
        \\    }
        \\    if (!valid) [[unlikely]] {
        \\        std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\                  << ": runtime error: collection index ";
        \\        if (fromEnd) std::cerr << '^';
        \\        std::cerr << index << " is out of bounds for count " << count << '\n';
        \\        std::exit(1);
        \\    }
        \\    return offset;
        \\}
        \\
        \\template <typename Collection>
        \\decltype(auto) silexCollectionAt(Collection&& values, std::int64_t index, bool fromEnd, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionOffset(values.size(), index, fromEnd, false, location);
        \\    return std::forward<Collection>(values)[offset];
        \\}
        \\
        \\template <typename Collection, typename T>
        \\void silexListPrepend(Collection& values, T value) {
        \\    values.insert(values.begin(), std::move(value));
        \\}
        \\
        \\template <typename Collection, typename T>
        \\void silexListInsert(Collection& values, std::int64_t index, T value, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, true, location);
        \\    values.insert(values.begin() + static_cast<std::ptrdiff_t>(offset), std::move(value));
        \\}
        \\
        \\template <typename Collection>
        \\typename Collection::value_type silexListTake(Collection& values, std::int64_t index, SilexSourceLocation location) {
        \\    using T = typename Collection::value_type;
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, false, location);
        \\    T value = std::move(values[offset]);
        \\    values.erase(values.begin() + static_cast<std::ptrdiff_t>(offset));
        \\    return value;
        \\}
        \\
        \\template <typename Collection>
        \\typename Collection::value_type silexListTakeLast(Collection& values, SilexSourceLocation location) {
        \\    using T = typename Collection::value_type;
        \\    const auto offset = silexCollectionOffset(values.size(), 1, true, false, location);
        \\    T value = std::move(values[offset]);
        \\    values.pop_back();
        \\    return value;
        \\}
        \\
        \\template <typename Collection, typename T>
        \\T silexCollectionReplace(Collection& values, std::int64_t index, T value, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, false, location);
        \\    return std::exchange(values[offset], std::move(value));
        \\}
        \\
        \\template <typename Collection>
        \\void silexCollectionSwap(Collection& values, std::int64_t left, std::int64_t right, SilexSourceLocation location) {
        \\    const auto leftOffset = silexCollectionOffset(values.size(), left, false, false, location);
        \\    const auto rightOffset = silexCollectionOffset(values.size(), right, false, false, location);
        \\    std::swap(values[leftOffset], values[rightOffset]);
        \\}
        \\
        \\template <typename Collection>
        \\void silexCollectionReverse(Collection& values) {
        \\    std::reverse(values.begin(), values.end());
        \\}
        \\
        \\template <typename T>
        \\[[noreturn, gnu::cold, gnu::noinline]] void binaryIntegerRuntimeError(
        \\    SilexSourceLocation location,
        \\    const char* typeName,
        \\    const char* operation,
        \\    const char* failure,
        \\    T left,
        \\    const char* symbol,
        \\    T right
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: " << typeName << ' ' << operation << ' ' << failure << ": ";
        \\    printIntegerValue(left);
        \\    std::cerr << ' ' << symbol << ' ';
        \\    printIntegerValue(right);
        \\    std::cerr << '\n';
        \\    std::exit(1);
        \\}
        \\
        \\template <typename T>
        \\[[noreturn, gnu::cold, gnu::noinline]] void unaryIntegerRuntimeError(
        \\    SilexSourceLocation location,
        \\    const char* typeName,
        \\    const char* failure,
        \\    T value
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: " << typeName << " negation " << failure << ": -(";
        \\    printIntegerValue(value);
        \\    std::cerr << ")\n";
        \\    std::exit(1);
        \\}
        \\
        \\template <typename T> inline T checkedAdd(T left, T right, SilexSourceLocation location, const char* typeName) {
        \\    T result;
        \\    if (__builtin_add_overflow(left, right, &result)) [[unlikely]] {
        \\        const char* failure = std::is_unsigned_v<T> || right >= 0 ? "overflow" : "underflow";
        \\        binaryIntegerRuntimeError(location, typeName, "addition", failure, left, "+", right);
        \\    }
        \\    return result;
        \\}
        \\
        \\template <typename T> inline T checkedSubtract(T left, T right, SilexSourceLocation location, const char* typeName) {
        \\    T result;
        \\    if (__builtin_sub_overflow(left, right, &result)) [[unlikely]] {
        \\        const char* failure = std::is_unsigned_v<T> || right >= 0 ? "underflow" : "overflow";
        \\        binaryIntegerRuntimeError(location, typeName, "subtraction", failure, left, "-", right);
        \\    }
        \\    return result;
        \\}
        \\
        \\template <typename T> inline T checkedMultiply(T left, T right, SilexSourceLocation location, const char* typeName) {
        \\    T result;
        \\    if (__builtin_mul_overflow(left, right, &result)) [[unlikely]] {
        \\        const char* failure = std::is_unsigned_v<T> || (left < 0) == (right < 0) ? "overflow" : "underflow";
        \\        binaryIntegerRuntimeError(location, typeName, "multiplication", failure, left, "*", right);
        \\    }
        \\    return result;
        \\}
        \\
        \\template <typename T> inline T checkedDivide(T left, T right, SilexSourceLocation location, const char* typeName) {
        \\    if (right == 0) [[unlikely]] {
        \\        binaryIntegerRuntimeError(location, typeName, "division", "by zero", left, "/", right);
        \\    }
        \\    if constexpr (std::is_signed_v<T>) {
        \\        if (left == std::numeric_limits<T>::min() && right == T{-1}) [[unlikely]] {
        \\            binaryIntegerRuntimeError(location, typeName, "division", "overflow", left, "/", right);
        \\        }
        \\    }
        \\    return left / right;
        \\}
        \\
        \\template <typename T> inline T checkedNegate(T value, SilexSourceLocation location, const char* typeName) {
        \\    T result;
        \\    if (__builtin_sub_overflow(T{0}, value, &result)) [[unlikely]] {
        \\        unaryIntegerRuntimeError(location, typeName, std::is_unsigned_v<T> ? "underflow" : "overflow", value);
        \\    }
        \\    return result;
        \\}
        \\
        \\// -----------------------------------------------------------------------------
        \\
    );
    try output.append(allocator, '\n');
    for (program.structures) |structure| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    if (program.structures.len > 0) try output.append(allocator, '\n');
    for (program.structures) |structure| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, " {\n");
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "    ");
            try appendCppType(allocator, &output, field.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.fields.len > 0 and structure.methods.len > 0) try output.append(allocator, '\n');
        for (structure.methods) |method| {
            try output.appendSlice(allocator, "    ");
            try generateMethodSignature(allocator, &output, method, null, false);
            try output.appendSlice(allocator, ";\n");
        }
        try output.appendSlice(allocator, "};\n\n");
    }
    if (program.structures.len > 0) {
        for (program.structures) |structure| {
            try generateStructureEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
        }
        try output.append(allocator, '\n');
        for (program.structures) |structure| {
            try generateStructureEqualitySignature(allocator, &output, structure, true);
            try output.appendSlice(allocator, " {\n    return ");
            if (structure.fields.len == 0) {
                try output.appendSlice(allocator, "true");
            } else {
                for (structure.fields, 0..) |field, index| {
                    if (index != 0) try output.appendSlice(allocator, " && ");
                    try generateStructureFieldEquality(allocator, &output, field);
                }
            }
            try output.appendSlice(allocator, ";\n}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_main or function.is_native) continue;
        try generateFunctionSignature(allocator, &output, function, false);
        try output.appendSlice(allocator, ";\n");
    }
    if (program.functions.len > 1) try output.append(allocator, '\n');
    for (program.structures) |structure| {
        for (structure.methods) |method| {
            try generateMethodSignature(allocator, &output, method, structure.generated_name, true);
            try output.appendSlice(allocator, " {\n");
            try generateStatements(allocator, &output, method.statements, 1, false);
            try output.appendSlice(allocator, "}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_native) continue;
        try generateFunctionSignature(allocator, &output, function, true);
        try output.appendSlice(allocator, " {\n");
        try generateStatements(allocator, &output, function.statements, 1, function.is_main);
        if (function.is_main) try output.appendSlice(allocator, "    return 0;\n");
        try output.appendSlice(allocator, "}\n\n");
    }
    try output.appendSlice(allocator,
        \\// -----------------------------------------------------------------------------
        \\
        \\} // namespace SilexGenerated
        \\
        \\int main() {
        \\    return SilexGenerated::silexMain();
        \\}
        \\
    );
    return output.toOwnedSlice(allocator);
}

fn generateMethodSignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    method: Semantic.Method,
    owner_name: ?[]const u8,
    include_names: bool,
) !void {
    try appendCppType(allocator, output, method.return_type);
    try output.append(allocator, ' ');
    if (owner_name) |name| {
        try output.appendSlice(allocator, name);
        try output.appendSlice(allocator, "::");
    }
    try output.appendSlice(allocator, method.generated_name);
    try output.append(allocator, '(');
    for (method.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter.type);
        if (parameter.is_mutable_reference) try output.append(allocator, '&');
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
        }
    }
    try output.append(allocator, ')');
    if (!method.is_mutating) try output.appendSlice(allocator, " const");
}

fn generateFunctionSignature(allocator: Allocator, output: *std.ArrayList(u8), function: Semantic.Function, include_names: bool) !void {
    if (function.is_main) {
        try output.appendSlice(allocator, "int silexMain(");
    } else {
        try appendCppType(allocator, output, function.return_type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, function.generated_name);
        try output.append(allocator, '(');
    }
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter.type);
        if (parameter.is_mutable_reference) try output.append(allocator, '&');
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
        }
    }
    try output.append(allocator, ')');
}

fn generateNativeFunctionSignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    function: Semantic.Function,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "extern \"C\" ");
    try appendCppType(allocator, output, function.return_type);
    try output.append(allocator, ' ');
    try output.appendSlice(allocator, function.generated_name);
    try output.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        if (parameter.type == .str) {
            try output.appendSlice(allocator, "const char*");
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Bytes, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Length");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else {
            try appendCppType(allocator, output, parameter.type);
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
            }
        }
    }
    try output.append(allocator, ')');
}

fn containsNativeFunction(functions: []const Semantic.Function) bool {
    for (functions) |function| if (function.is_native) return true;
    return false;
}

fn generateNativeFunctionCall(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    try output.appendSlice(allocator, "callNativeFunction(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() {");
    for (call.arguments, 0..) |argument, index| {
        if (argument.type != .str) continue;
        try output.appendSlice(allocator, "auto&& silexNativeString");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, " = ");
        try generateExpression(allocator, output, argument);
        try output.appendSlice(allocator, ";");
    }
    try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |argument, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        if (argument.type == .str) {
            try output.appendSlice(allocator, "silexNativeString");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeString");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, ".size())");
        } else {
            try generateExpression(allocator, output, argument);
        }
    }
    try output.appendSlice(allocator, "); })");
}

fn generateStructureEqualitySignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.Structure,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "bool ");
    try generateStructureEqualityName(allocator, output, structure.generated_name);
    try output.appendSlice(allocator, "(const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " left");
    try output.appendSlice(allocator, ", const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " right");
    try output.append(allocator, ')');
}

fn generateStructureEqualityName(allocator: Allocator, output: *std.ArrayList(u8), generated_name: []const u8) !void {
    try output.appendSlice(allocator, "silexEqual");
    try output.appendSlice(allocator, generated_name);
}

fn generateStructureFieldEquality(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    field: Semantic.StructureField,
) !void {
    switch (field.type) {
        .structure => |structure_type| {
            try generateStructureEqualityName(allocator, output, structure_type.generated_name);
            try output.appendSlice(allocator, "(left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ", right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.append(allocator, ')');
        },
        else => {
            try output.appendSlice(allocator, "left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " == right.");
            try output.appendSlice(allocator, field.generated_name);
        },
    }
}

fn generateStatements(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    statements: []const Semantic.Statement,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    for (statements) |statement| {
        try generateStatement(allocator, output, statement, indentation, is_main);
    }
}

fn generateStatement(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    statement: Semantic.Statement,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    switch (statement) {
        .print => |argument| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "std::cout << ");
            if (argument.type == .bool) try output.append(allocator, '(');
            if (argument.type == .int8 or argument.type == .uint8) try output.appendSlice(allocator, "static_cast<int>(");
            try generateExpression(allocator, output, argument);
            if (argument.type == .int8 or argument.type == .uint8) try output.append(allocator, ')');
            if (argument.type == .bool) try output.appendSlice(allocator, " ? \"true\" : \"false\")");
            try output.appendSlice(allocator, " << '\\n';\n");
        },
        .variable_declaration => |declaration| {
            try indent(allocator, output, indentation);
            if (declaration.mutability == .immutable and declaration.type != .reference) try output.appendSlice(allocator, "const ");
            try appendCppType(allocator, output, declaration.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, declaration.generated_name);
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, declaration.initializer);
            try output.appendSlice(allocator, ";\n");
        },
        .assignment => |assignment| {
            try indent(allocator, output, indentation);
            const checked_integer = isInteger(assignment.target.type) and assignment.operator != .assign;
            try generateExpression(allocator, output, assignment.target);
            if (checked_integer) {
                try output.appendSlice(allocator, " = ");
                try output.appendSlice(allocator, checkedAssignmentFunction(assignment.operator));
                try output.append(allocator, '(');
                try generateExpression(allocator, output, assignment.target);
                try output.appendSlice(allocator, ", ");
                if (assignment.value) |value| {
                    try generateExpression(allocator, output, value);
                } else {
                    try generateIntegerOne(allocator, output, assignment.target.type);
                }
                try generateRuntimeArguments(allocator, output, assignment.position, assignment.target.type);
                try output.append(allocator, ')');
            } else switch (assignment.operator) {
                .assign, .add, .subtract, .multiply, .divide => {
                    try output.appendSlice(allocator, assignmentOperatorText(assignment.operator));
                    try generateExpression(allocator, output, assignment.value.?);
                },
                .increment => try output.appendSlice(allocator, "++"),
                .decrement => try output.appendSlice(allocator, "--"),
            }
            try output.appendSlice(allocator, ";\n");
        },
        .if_statement => |if_statement| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "if ");
            try generateCondition(allocator, output, if_statement.condition);
            try output.appendSlice(allocator, " {\n");
            try generateStatements(allocator, output, if_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            if (if_statement.else_body) |else_body| {
                try output.appendSlice(allocator, "} else {\n");
                try generateStatements(allocator, output, else_body, indentation + 1, is_main);
                try indent(allocator, output, indentation);
            }
            try output.appendSlice(allocator, "}\n");
        },
        .while_statement => |while_statement| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "while ");
            try generateCondition(allocator, output, while_statement.condition);
            try output.appendSlice(allocator, " {\n");
            try generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .for_statement => |for_statement| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "for (");
            if (!for_statement.mutable) try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, "auto& ");
            try output.appendSlice(allocator, for_statement.generated_name);
            try output.appendSlice(allocator, " : ");
            try generateExpression(allocator, output, for_statement.iterable);
            try output.appendSlice(allocator, ") {\n");
            try generateStatements(allocator, output, for_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .break_statement => {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "break;\n");
        },
        .continue_statement => {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "continue;\n");
        },
        .return_statement => |value| {
            try indent(allocator, output, indentation);
            if (value) |expression| {
                try output.appendSlice(allocator, "return ");
                try generateExpression(allocator, output, expression);
                try output.appendSlice(allocator, ";\n");
            } else {
                try output.appendSlice(allocator, if (is_main) "return 0;\n" else "return;\n");
            }
        },
        .expression_statement => |expression| {
            try indent(allocator, output, indentation);
            try generateExpression(allocator, output, expression);
            try output.appendSlice(allocator, ";\n");
        },
    }
}

fn generateCondition(allocator: Allocator, output: *std.ArrayList(u8), expression: *const Semantic.Expression) !void {
    const already_parenthesized = expression.value == .binary or expression.value == .unary;
    if (!already_parenthesized) try output.append(allocator, '(');
    try generateExpression(allocator, output, expression);
    if (!already_parenthesized) try output.append(allocator, ')');
}

fn generateExpression(allocator: Allocator, output: *std.ArrayList(u8), expression: *const Semantic.Expression) !void {
    switch (expression.value) {
        .integer => |value| {
            const literal = if (isUnsignedInteger(expression.type))
                try std.fmt.allocPrint(allocator, "{s}{{{d}ULL}}", .{ cppType(expression.type), value })
            else
                try std.fmt.allocPrint(allocator, "{s}{{{d}}}", .{ cppType(expression.type), value });
            try output.appendSlice(allocator, literal);
        },
        .floating => |lexeme| {
            try output.appendSlice(allocator, cppType(expression.type));
            try output.append(allocator, '{');
            try output.appendSlice(allocator, lexeme);
            try output.appendSlice(allocator, if (expression.type == .float) "F}" else "}");
        },
        .boolean => |value| try output.appendSlice(allocator, if (value) "true" else "false"),
        .string => |value| {
            try output.appendSlice(allocator, "std::string{");
            try appendCppByteStringLiteral(allocator, output, value);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", {d}}}", .{value.len}));
        },
        .string_length => |argument| {
            try output.appendSlice(allocator, "silexStringLength(");
            try generateExpression(allocator, output, argument);
            try output.append(allocator, ')');
        },
        .sequence_literal => |values| {
            try appendCppType(allocator, output, expression.type);
            try output.append(allocator, '{');
            for (values, 0..) |value, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, value);
            }
            try output.append(allocator, '}');
        },
        .cascade_target => try output.appendSlice(allocator, "silexCascadeValue"),
        .cascade => |cascade| {
            try output.appendSlice(allocator, "silexCascade(");
            try generateExpression(allocator, output, cascade.object);
            try output.appendSlice(allocator, ", [&](auto& silexCascadeValue) {");
            for (cascade.operations) |operation| switch (operation) {
                .method_call => |method| {
                    try generateExpression(allocator, output, method);
                    try output.append(allocator, ';');
                },
                .field_assignment => |assignment| {
                    try output.appendSlice(allocator, "silexCascadeValue.");
                    try output.appendSlice(allocator, assignment.generated_name);
                    try output.appendSlice(allocator, " = ");
                    try generateExpression(allocator, output, assignment.value);
                    try output.append(allocator, ';');
                },
            };
            try output.appendSlice(allocator, " })");
        },
        .collection_method => |method| {
            switch (method.operation) {
                .count => {
                    try output.appendSlice(allocator, "silexCollectionCount(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".size(), ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .is_empty => {
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".empty()");
                },
                .append => {
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".push_back(");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .append_range => {
                    try output.appendSlice(allocator, "silexListAppendRange(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .prepend => {
                    try output.appendSlice(allocator, "silexListPrepend(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.append(allocator, ')');
                },
                .insert => {
                    try output.appendSlice(allocator, "silexListInsert(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .take, .take_first => {
                    try output.appendSlice(allocator, "silexListTake(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    if (method.operation == .take) {
                        try generateExpression(allocator, output, method.arguments[0]);
                    } else {
                        try output.appendSlice(allocator, "std::int64_t{0}");
                    }
                    try output.appendSlice(allocator, ", ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .take_last => {
                    try output.appendSlice(allocator, "silexListTakeLast(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .replace => {
                    try output.appendSlice(allocator, "silexCollectionReplace(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .swap => {
                    try output.appendSlice(allocator, "silexCollectionSwap(");
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[0]);
                    try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, method.arguments[1]);
                    try output.appendSlice(allocator, ", ");
                    try appendCppSourceLocation(allocator, output, method.position);
                    try output.append(allocator, ')');
                },
                .reverse => {
                    try output.appendSlice(allocator, "silexCollectionReverse(");
                    try generateExpression(allocator, output, method.object);
                    try output.append(allocator, ')');
                },
                .clear => {
                    try generateExpression(allocator, output, method.object);
                    try output.appendSlice(allocator, ".clear()");
                },
            }
        },
        .index_access => |access| {
            try output.appendSlice(allocator, "silexCollectionAt(");
            try generateExpression(allocator, output, access.object);
            try output.appendSlice(allocator, ", ");
            try generateExpression(allocator, output, access.index);
            try output.appendSlice(allocator, if (access.from_end) ", true, " else ", false, ");
            try appendCppSourceLocation(allocator, output, expression.position);
            try output.append(allocator, ')');
        },
        .variable => |generated_name| try output.appendSlice(allocator, generated_name),
        .self => try output.appendSlice(allocator, "*this"),
        .call => |call| {
            if (call.is_native) {
                try generateNativeFunctionCall(allocator, output, call);
            } else {
                try output.appendSlice(allocator, call.generated_name);
                try output.append(allocator, '(');
                for (call.arguments, 0..) |argument, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try generateExpression(allocator, output, argument);
                }
                try output.append(allocator, ')');
            }
        },
        .method_call => |call| {
            if (call.object.value != .self) {
                try generateExpression(allocator, output, call.object);
                try output.append(allocator, '.');
            }
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .structure_initializer => |initializer| {
            try output.appendSlice(allocator, initializer.generated_name);
            try output.append(allocator, '{');
            for (initializer.fields, 0..) |field, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, field);
            }
            try output.append(allocator, '}');
        },
        .member_access => |member| {
            if (member.object.value != .self) {
                try generateExpression(allocator, output, member.object);
                try output.append(allocator, '.');
            }
            try output.appendSlice(allocator, member.generated_name);
        },
        .unary => |unary| {
            if (unary.operator == .numeric_negate and isInteger(expression.type) and unary.operand.value == .integer) {
                const magnitude = unary.operand.value.integer;
                const minimum_magnitude = integerMinimumMagnitude(expression.type);
                if (magnitude == minimum_magnitude) {
                    try output.appendSlice(allocator, "std::numeric_limits<");
                    try output.appendSlice(allocator, cppType(expression.type));
                    try output.appendSlice(allocator, ">::min()");
                } else {
                    const literal = try std.fmt.allocPrint(allocator, "{s}{{-{d}}}", .{ cppType(expression.type), magnitude });
                    try output.appendSlice(allocator, literal);
                }
                return;
            } else if (unary.operator == .numeric_negate and isInteger(expression.type)) {
                try output.appendSlice(allocator, "checkedNegate(");
            } else if (unary.operator == .dereference) {
                try output.appendSlice(allocator, "(*");
            } else if (unary.operator == .borrow) {
                try generateExpression(allocator, output, unary.operand);
                return;
            } else {
                try output.appendSlice(allocator, if (unary.operator == .logical_not) "(!" else "(-");
            }
            try generateExpression(allocator, output, unary.operand);
            if (unary.operator == .numeric_negate and isInteger(expression.type)) {
                try generateRuntimeArguments(allocator, output, expression.position, expression.type);
            }
            try output.append(allocator, ')');
        },
        .binary => |binary| {
            if (isInteger(expression.type) and isArithmetic(binary.operator)) {
                try output.appendSlice(allocator, checkedBinaryFunction(binary.operator));
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, binary.right);
                try generateRuntimeArguments(allocator, output, expression.position, expression.type);
                try output.append(allocator, ')');
            } else if ((binary.operator == .equal or binary.operator == .not_equal) and binary.left.type == .structure) {
                const structure_type = binary.left.type.structure;
                if (binary.operator == .not_equal) try output.append(allocator, '!');
                try generateStructureEqualityName(allocator, output, structure_type.generated_name);
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, binary.right);
                try output.append(allocator, ')');
            } else {
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, operatorText(binary.operator));
                try generateExpression(allocator, output, binary.right);
                try output.append(allocator, ')');
            }
        },
        .conversion => |conversion| {
            try output.appendSlice(allocator, "checkedConvert<");
            try output.appendSlice(allocator, cppType(conversion.target_type));
            try output.appendSlice(allocator, ">(");
            try generateExpression(allocator, output, conversion.operand);
            try generateRuntimeArguments(allocator, output, expression.position, conversion.operand.type);
            try output.appendSlice(allocator, ", \"");
            try output.appendSlice(allocator, silexTypeName(conversion.target_type));
            try output.appendSlice(allocator, "\")");
        },
    }
}

fn generateSourcePaths(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    source_paths: []const []const u8,
) !void {
    try output.appendSlice(allocator, "constexpr const char* k_silexSourcePaths[] = {\n");
    if (source_paths.len == 0) {
        try output.appendSlice(allocator, "    \"<unknown>\",\n");
    } else for (source_paths) |source_path| {
        try output.appendSlice(allocator, "    ");
        try appendCppStringLiteral(allocator, output, source_path);
        try output.appendSlice(allocator, ",\n");
    }
    try output.appendSlice(allocator, "};\nconstexpr std::size_t k_silexSourcePathCount = ");
    try output.appendSlice(allocator, if (source_paths.len == 0) "1" else try std.fmt.allocPrint(allocator, "{d}", .{source_paths.len}));
    try output.appendSlice(allocator, ";\n");
}

fn appendCppStringLiteral(allocator: Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append(allocator, '"');
    for (value) |character| switch (character) {
        '\\' => try output.appendSlice(allocator, "\\\\"),
        '"' => try output.appendSlice(allocator, "\\\""),
        '\n' => try output.appendSlice(allocator, "\\n"),
        '\r' => try output.appendSlice(allocator, "\\r"),
        '\t' => try output.appendSlice(allocator, "\\t"),
        else => try output.append(allocator, character),
    };
    try output.append(allocator, '"');
}

fn appendCppByteStringLiteral(allocator: Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append(allocator, '"');
    for (value) |character| switch (character) {
        '\\' => try output.appendSlice(allocator, "\\\\"),
        '"' => try output.appendSlice(allocator, "\\\""),
        else => if (character >= 0x20 and character <= 0x7E) {
            try output.append(allocator, character);
        } else {
            const octal = [_]u8{
                '\\',
                '0' + (character >> 6),
                '0' + ((character >> 3) & 7),
                '0' + (character & 7),
            };
            try output.appendSlice(allocator, &octal);
        },
    };
    try output.append(allocator, '"');
}

fn generateRuntimeArguments(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    position: Source.Position,
    type_name: Semantic.Type,
) !void {
    try output.appendSlice(allocator, try std.fmt.allocPrint(
        allocator,
        ", SilexSourceLocation{{{d}, {d}, {d}}}, ",
        .{ position.file, position.line, position.column },
    ));
    try appendCppStringLiteral(allocator, output, silexTypeName(type_name));
}

fn appendCppSourceLocation(allocator: Allocator, output: *std.ArrayList(u8), position: Source.Position) !void {
    try output.appendSlice(allocator, try std.fmt.allocPrint(
        allocator,
        "SilexSourceLocation{{{d}, {d}, {d}}}",
        .{ position.file, position.line, position.column },
    ));
}

fn indent(allocator: Allocator, output: *std.ArrayList(u8), level: usize) !void {
    var index: usize = 0;
    while (index < level) : (index += 1) try output.appendSlice(allocator, "    ");
}

fn cppType(type_name: Semantic.Type) []const u8 {
    return switch (type_name) {
        .void => "void",
        .int => "std::int64_t",
        .int8 => "std::int8_t",
        .int16 => "std::int16_t",
        .int32 => "std::int32_t",
        .uint8 => "std::uint8_t",
        .uint16 => "std::uint16_t",
        .uint32 => "std::uint32_t",
        .uint64 => "std::uint64_t",
        .float => "float",
        .float64 => "double",
        .bool => "bool",
        .str => "std::string",
        .list, .fixed_array => unreachable,
        .structure => |structure_type| structure_type.generated_name,
        .reference => unreachable,
    };
}

fn appendCppType(allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) !void {
    switch (type_name) {
        .reference => |reference| {
            if (!reference.mutable) try output.appendSlice(allocator, "const ");
            try appendCppType(allocator, output, reference.target.*);
            try output.append(allocator, '*');
        },
        .list => |element| {
            try output.appendSlice(allocator, "SilexList<");
            try appendCppType(allocator, output, element.*);
            try output.append(allocator, '>');
        },
        .fixed_array => |array| {
            try output.appendSlice(allocator, "std::array<");
            try appendCppType(allocator, output, array.element.*);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", {d}>", .{array.length}));
        },
        else => try output.appendSlice(allocator, cppType(type_name)),
    }
}

fn silexTypeName(type_name: Semantic.Type) []const u8 {
    return switch (type_name) {
        .void => "void",
        .int => "int",
        .int8 => "int8",
        .int16 => "int16",
        .int32 => "int32",
        .uint8 => "uint8",
        .uint16 => "uint16",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .float => "float",
        .float64 => "float64",
        .bool => "bool",
        .str => "str",
        .list => "list",
        .fixed_array => "array",
        .structure => |structure_type| structure_type.source_name,
        .reference => |reference| if (reference.mutable) "reference&" else "reference@",
    };
}

fn isInteger(type_name: Semantic.Type) bool {
    return switch (type_name) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

fn isUnsignedInteger(type_name: Semantic.Type) bool {
    return switch (type_name) {
        .uint8, .uint16, .uint32, .uint64 => true,
        else => false,
    };
}

fn isArithmetic(operator: Ast.BinaryOperator) bool {
    return switch (operator) {
        .add, .subtract, .multiply, .divide => true,
        else => false,
    };
}

fn checkedBinaryFunction(operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .add => "checkedAdd",
        .subtract => "checkedSubtract",
        .multiply => "checkedMultiply",
        .divide => "checkedDivide",
        else => unreachable,
    };
}

fn checkedAssignmentFunction(operator: Ast.AssignmentOperator) []const u8 {
    return switch (operator) {
        .add, .increment => "checkedAdd",
        .subtract, .decrement => "checkedSubtract",
        .multiply => "checkedMultiply",
        .divide => "checkedDivide",
        .assign => unreachable,
    };
}

fn generateIntegerOne(allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) !void {
    try output.appendSlice(allocator, cppType(type_name));
    try output.appendSlice(allocator, "{1}");
}

fn integerMinimumMagnitude(type_name: Semantic.Type) u64 {
    return switch (type_name) {
        .int8 => 1 << 7,
        .int16 => 1 << 15,
        .int32 => 1 << 31,
        .int => 1 << 63,
        else => 0,
    };
}

fn operatorText(operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .logical_or => " || ",
        .logical_and => " && ",
        .equal => " == ",
        .not_equal => " != ",
        .less => " < ",
        .less_equal => " <= ",
        .greater => " > ",
        .greater_equal => " >= ",
        .add => " + ",
        .subtract => " - ",
        .multiply => " * ",
        .divide => " / ",
    };
}

fn assignmentOperatorText(operator: Ast.AssignmentOperator) []const u8 {
    return switch (operator) {
        .assign => " = ",
        .add => " += ",
        .subtract => " -= ",
        .multiply => " *= ",
        .divide => " /= ",
        .increment, .decrement => unreachable,
    };
}

test "generate typed variables and control flow" {
    const Parser = @import("Parser.zig").Parser;
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

test "generate checked explicit numeric conversion" {
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator, "func main() void { print(\"A\\u{00E9}\\0\".count()); }");
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::string{\"A\\303\\251\\000\", 4}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexStringLength(std::string{") != null);
}

test "generate recursive structural equality" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { x:int y:int }
        \\struct Player { name:str position:Position }
        \\func main() void {
        \\    print(Player { name:"Ada", position:Position { x:10, y:20 } } == Player { name:"Ada", position:Position { x:10, y:20 } })
        \\}
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "bool silexEqualSilexStruct0(const SilexStruct0&, const SilexStruct0&);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "return left.field0 == right.field0 && silexEqualSilexStruct0(left.field1, right.field1);") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexEqualSilexStruct1(SilexStruct1{") != null);
}

test "generate while loop" {
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    try std.testing.expect(std.mem.indexOf(u8, cpp, "checkedNegate(silexValue0, SilexSourceLocation{") != null);
}

test "optimized backend eliminates a provably unnecessary integer check" {
    if (build_options.developer_zig.len == 0) return error.SkipZigTest;

    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Position { x:int; y:int }
        \\func main() void { var position = Position { y:20, x:10 }; position.x = 12; print(position.x) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "struct SilexStruct0 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0{std::int64_t{10}, std::int64_t{20}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexValue0.field0 = std::int64_t{12};") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "namespace SilexGenerated {") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "int silexMain()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "return SilexGenerated::silexMain();") != null);
}

test "generate inferred const and mutating methods" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\struct Counter {
        \\    value:int
        \\    func current() int { return self.value }
        \\    func increment() void { self.value = self.value + 1 }
        \\}
        \\func main() void { var counter = Counter { value:1 }; counter.increment(); print(counter.current()) }
    );
    var analyzer = Semantic.Analyzer.init(allocator);
    const cpp = try generate(allocator, try analyzer.analyze(try parser.parse()));

    try std.testing.expect(std.mem.indexOf(u8, cpp, "std::int64_t method0() const;") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "void method1();") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0::method0() const") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "SilexStruct0::method1()") != null);
}

test "generate cascades through one stable receiver" {
    const Parser = @import("Parser.zig").Parser;
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
