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
        \\#include <functional>
        \\#include <array>
        \\#include <bit>
        \\#include <climits>
        \\#include <cmath>
        \\#include <iostream>
        \\#include <iterator>
        \\#include <limits>
        \\#include <memory>
        \\#include <optional>
        \\#include <string>
        \\#include <tuple>
        \\#include <type_traits>
        \\#include <unordered_map>
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
        \\[[noreturn, gnu::cold, gnu::noinline]] void assertionRuntimeError(
        \\    SilexSourceLocation location,
        \\    const std::string& message
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: assertion failed: " << message << '\n';
        \\    std::exit(1);
        \\}
        \\
        \\[[noreturn, gnu::cold, gnu::noinline]] void panicRuntimeError(
        \\    SilexSourceLocation location,
        \\    const std::string& message
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: " << message << '\n';
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
        \\struct SilexObject;
        \\using SilexTraceVisitor = std::function<void(SilexObject*)>;
        \\template <typename T> void silexTraceValue(const T& value, const SilexTraceVisitor& visit);
        \\template <typename T> void silexClearValue(T& value);
        \\
        \\inline bool silexCollectingCycles = false;
        \\inline std::size_t silexLiveObjects = 0;
        \\
        \\struct SilexObject {
        \\    std::size_t references = 1;
        \\    bool collecting = false;
        \\    virtual void silexTrace(const SilexTraceVisitor& visit) const = 0;
        \\    virtual void silexDrop() {}
        \\    virtual void silexClear() = 0;
        \\    virtual ~SilexObject() { --silexLiveObjects; }
        \\};
        \\
        \\void silexCollectCycles(SilexObject* candidate);
        \\
        \\void silexRelease(SilexObject* object) {
        \\    if (object == nullptr) return;
        \\    --object->references;
        \\    if (object->collecting) return;
        \\    if (object->references == 0) {
        \\        object->collecting = true;
        \\        object->silexDrop();
        \\        object->silexClear();
        \\        delete object;
        \\    } else if (!silexCollectingCycles) {
        \\        silexCollectCycles(object);
        \\    }
        \\}
        \\
        \\template <typename T>
        \\class SilexRef {
        \\public:
        \\    SilexRef() = default;
        \\    SilexRef(const SilexRef& other) : object_(other.object_) { retain(); }
        \\    template <typename U> requires std::is_base_of_v<T, U>
        \\    SilexRef(const SilexRef<U>& other) : object_(other.base()) { retain(); }
        \\    SilexRef(SilexRef&& other) noexcept : object_(std::exchange(other.object_, nullptr)) {}
        \\    ~SilexRef() { reset(); }
        \\
        \\    SilexRef& operator=(const SilexRef& other) {
        \\        if (this == &other) return *this;
        \\        reset();
        \\        object_ = other.object_;
        \\        retain();
        \\        return *this;
        \\    }
        \\    SilexRef& operator=(SilexRef&& other) noexcept {
        \\        if (this == &other) return *this;
        \\        reset();
        \\        object_ = std::exchange(other.object_, nullptr);
        \\        return *this;
        \\    }
        \\    template <typename U> requires std::is_base_of_v<T, U>
        \\    SilexRef& operator=(const SilexRef<U>& other) {
        \\        reset();
        \\        object_ = other.base();
        \\        retain();
        \\        return *this;
        \\    }
        \\
        \\    T* operator->() const { return static_cast<T*>(object_); }
        \\    T& operator*() const { return *static_cast<T*>(object_); }
        \\    explicit operator bool() const { return object_ != nullptr; }
        \\    template <typename U> bool operator==(const SilexRef<U>& other) const { return object_ == other.base(); }
        \\    template <typename U> bool operator!=(const SilexRef<U>& other) const { return object_ != other.base(); }
        \\    SilexObject* base() const { return object_; }
        \\    void reset() {
        \\        SilexObject* previous = std::exchange(object_, nullptr);
        \\        silexRelease(previous);
        \\    }
        \\    static SilexRef adopt(T* object) {
        \\        SilexRef result;
        \\        result.object_ = object;
        \\        return result;
        \\    }
        \\
        \\private:
        \\    void retain() { if (object_ != nullptr) ++object_->references; }
        \\    SilexObject* object_ = nullptr;
        \\};
        \\
        \\template <typename T, typename... Arguments>
        \\SilexRef<T> silexMake(Arguments&&... arguments) {
        \\    T* object = new T(std::forward<Arguments>(arguments)...);
        \\    ++silexLiveObjects;
        \\    return SilexRef<T>::adopt(object);
        \\}
        \\
        \\template <typename T>
        \\SilexRef<std::remove_const_t<T>> silexShare(T* object) {
        \\    using Value = std::remove_const_t<T>;
        \\    Value* mutableObject = const_cast<Value*>(object);
        \\    ++mutableObject->references;
        \\    return SilexRef<Value>::adopt(mutableObject);
        \\}
        \\
        \\template <typename T>
        \\struct SilexBinding final : SilexObject {
        \\    explicit SilexBinding(T initial) : value(std::move(initial)) {}
        \\    void silexTrace(const SilexTraceVisitor& visit) const override { silexTraceValue(value, visit); }
        \\    void silexClear() override { silexClearValue(value); }
        \\    T value;
        \\};
        \\
        \\template <typename T>
        \\void silexTraceValue(const SilexRef<T>& value, const SilexTraceVisitor& visit) {
        \\    if (value.base() != nullptr) visit(value.base());
        \\}
        \\template <typename T>
        \\void silexClearValue(SilexRef<T>& value) { value.reset(); }
        \\template <typename T>
        \\void silexTraceValue(const std::optional<T>& value, const SilexTraceVisitor& visit) {
        \\    if (value.has_value()) silexTraceValue(*value, visit);
        \\}
        \\template <typename T>
        \\void silexClearValue(std::optional<T>& value) {
        \\    if (value.has_value()) silexClearValue(*value);
        \\    value.reset();
        \\}
        \\template <typename T, std::size_t Count>
        \\void silexTraceValue(const std::array<T, Count>& value, const SilexTraceVisitor& visit) {
        \\    for (const auto& element : value) silexTraceValue(element, visit);
        \\}
        \\template <typename T, std::size_t Count>
        \\void silexClearValue(std::array<T, Count>& value) {
        \\    for (auto& element : value) silexClearValue(element);
        \\}
        \\
        \\struct SilexCapturedValuesBase {
        \\    virtual void trace(const SilexTraceVisitor& visit) const = 0;
        \\    virtual void clear() = 0;
        \\    virtual std::unique_ptr<SilexCapturedValuesBase> clone() const = 0;
        \\    virtual ~SilexCapturedValuesBase() = default;
        \\};
        \\
        \\template <typename... Values>
        \\struct SilexCapturedValues final : SilexCapturedValuesBase {
        \\    explicit SilexCapturedValues(Values... captured) : values(std::move(captured)...) {}
        \\    void trace(const SilexTraceVisitor& visit) const override {
        \\        std::apply([&](const auto&... value) { ((silexTraceValue(value, visit), silexTraceValue(value, visit)), ...); }, values);
        \\    }
        \\    void clear() override {
        \\        std::apply([&](auto&... value) { (silexClearValue(value), ...); }, values);
        \\    }
        \\    std::unique_ptr<SilexCapturedValuesBase> clone() const override {
        \\        return std::make_unique<SilexCapturedValues>(*this);
        \\    }
        \\    std::tuple<Values...> values;
        \\};
        \\
        \\template <typename Signature>
        \\class SilexFunction;
        \\
        \\template <typename Return, typename... Arguments>
        \\class SilexFunction<Return(Arguments...)> {
        \\public:
        \\    SilexFunction() = default;
        \\    SilexFunction(std::function<Return(Arguments...)> callable, std::unique_ptr<SilexCapturedValuesBase> captures)
        \\        : callable_(std::move(callable)), captures_(std::move(captures)) {}
        \\    SilexFunction(const SilexFunction& other)
        \\        : callable_(other.callable_), captures_(other.captures_ ? other.captures_->clone() : nullptr) {}
        \\    SilexFunction(SilexFunction&&) noexcept = default;
        \\    SilexFunction& operator=(const SilexFunction& other) {
        \\        if (this == &other) return *this;
        \\        callable_ = other.callable_;
        \\        captures_ = other.captures_ ? other.captures_->clone() : nullptr;
        \\        return *this;
        \\    }
        \\    SilexFunction& operator=(SilexFunction&&) noexcept = default;
        \\    Return operator()(Arguments... arguments) const {
        \\        return callable_(std::forward<Arguments>(arguments)...);
        \\    }
        \\    void silexTrace(const SilexTraceVisitor& visit) const {
        \\        if (captures_) captures_->trace(visit);
        \\    }
        \\    void silexClear() {
        \\        callable_ = {};
        \\        if (captures_) captures_->clear();
        \\        captures_.reset();
        \\    }
        \\
        \\private:
        \\    std::function<Return(Arguments...)> callable_;
        \\    std::unique_ptr<SilexCapturedValuesBase> captures_;
        \\};
        \\
        \\template <typename Function, typename Callable, typename... Captures>
        \\Function silexMakeFunction(Callable&& callable, Captures&&... captures) {
        \\    using State = SilexCapturedValues<std::decay_t<Captures>...>;
        \\    return Function(
        \\        std::forward<Callable>(callable),
        \\        std::make_unique<State>(std::forward<Captures>(captures)...)
        \\    );
        \\}
        \\
        \\template <typename T>
        \\class SilexList {
        \\public:
        \\    using value_type = T;
        \\    using iterator = typename std::vector<T>::iterator;
        \\    using const_iterator = typename std::vector<T>::const_iterator;
        \\
        \\    SilexList() = default;
        \\    SilexList(std::initializer_list<T> values) : values_(values) {}
        \\
        \\    std::size_t size() const { return values_.size(); }
        \\    bool empty() const { return values_.empty(); }
        \\    bool operator==(const SilexList& other) const { return values_ == other.values_; }
        \\    bool operator!=(const SilexList& other) const { return !(*this == other); }
        \\    const_iterator begin() const { return values_.begin(); }
        \\    const_iterator end() const { return values_.end(); }
        \\    iterator begin() { return values_.begin(); }
        \\    iterator end() { return values_.end(); }
        \\    const T& operator[](std::size_t index) const { return values_[index]; }
        \\    T& operator[](std::size_t index) { return values_[index]; }
        \\    void reserve(std::size_t count) { values_.reserve(count); }
        \\    void push_back(T value) { values_.push_back(std::move(value)); }
        \\    iterator insert(iterator position, T value) { return values_.insert(position, std::move(value)); }
        \\    template <typename Iterator>
        \\    iterator insert(iterator position, Iterator first, Iterator last) {
        \\        return values_.insert(position, first, last);
        \\    }
        \\    iterator erase(iterator position) { return values_.erase(position); }
        \\    void pop_back() { values_.pop_back(); }
        \\    void clear() { values_.clear(); }
        \\    void silexTrace(const SilexTraceVisitor& visit) const {
        \\        for (const auto& value : values_) silexTraceValue(value, visit);
        \\    }
        \\    void silexClear() {
        \\        for (auto& value : values_) silexClearValue(value);
        \\        values_.clear();
        \\    }
        \\
        \\private:
        \\    std::vector<T> values_;
        \\};
        \\
        \\template <typename T>
        \\void silexTraceValue(const T& value, const SilexTraceVisitor& visit) {
        \\    if constexpr (requires { value.silexTrace(visit); }) value.silexTrace(visit);
        \\}
        \\template <typename T>
        \\void silexClearValue(T& value) {
        \\    if constexpr (requires { value.silexClear(); }) value.silexClear();
        \\}
        \\
        \\void silexCollectCycles(SilexObject* candidate) {
        \\    std::vector<SilexObject*> graph;
        \\    std::unordered_map<SilexObject*, std::size_t> indexes;
        \\    graph.push_back(candidate);
        \\    indexes.emplace(candidate, 0);
        \\    for (std::size_t cursor = 0; cursor < graph.size(); ++cursor) {
        \\        graph[cursor]->silexTrace([&](SilexObject* edge) {
        \\            if (edge == nullptr || indexes.contains(edge)) return;
        \\            indexes.emplace(edge, graph.size());
        \\            graph.push_back(edge);
        \\        });
        \\    }
        \\    std::vector<std::size_t> internal(graph.size(), 0);
        \\    for (SilexObject* object : graph) {
        \\        object->silexTrace([&](SilexObject* edge) {
        \\            const auto found = indexes.find(edge);
        \\            if (found != indexes.end()) ++internal[found->second];
        \\        });
        \\    }
        \\    std::vector<bool> live(graph.size(), false);
        \\    std::vector<std::size_t> pending;
        \\    for (std::size_t index = 0; index < graph.size(); ++index) {
        \\        if (graph[index]->references > internal[index]) {
        \\            live[index] = true;
        \\            pending.push_back(index);
        \\        }
        \\    }
        \\    for (std::size_t cursor = 0; cursor < pending.size(); ++cursor) {
        \\        graph[pending[cursor]]->silexTrace([&](SilexObject* edge) {
        \\            const auto found = indexes.find(edge);
        \\            if (found == indexes.end() || live[found->second]) return;
        \\            live[found->second] = true;
        \\            pending.push_back(found->second);
        \\        });
        \\    }
        \\    std::vector<SilexObject*> garbage;
        \\    for (std::size_t index = 0; index < graph.size(); ++index) {
        \\        if (!live[index]) garbage.push_back(graph[index]);
        \\    }
        \\    if (garbage.empty()) return;
        \\    silexCollectingCycles = true;
        \\    for (SilexObject* object : garbage) object->collecting = true;
        \\    for (SilexObject* object : garbage) object->silexDrop();
        \\    for (SilexObject* object : garbage) object->silexClear();
        \\    for (SilexObject* object : garbage) delete object;
        \\    silexCollectingCycles = false;
        \\}
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
        \\    bool allowEnd,
        \\    SilexSourceLocation location
        \\) {
        \\    bool valid = index >= 0 && static_cast<std::uint64_t>(index) <= count;
        \\    std::size_t offset = 0;
        \\    if (valid) {
        \\        offset = static_cast<std::size_t>(index);
        \\        valid = allowEnd || offset < count;
        \\    }
        \\    if (!valid) [[unlikely]] {
        \\        std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\                  << ": runtime error: collection index " << index
        \\                  << " is out of bounds for count " << count << '\n';
        \\        std::exit(1);
        \\    }
        \\    return offset;
        \\}
        \\
        \\std::size_t silexCollectionIndexOffset(
        \\    std::size_t count,
        \\    std::int64_t index,
        \\    SilexSourceLocation location
        \\) {
        \\    bool valid = false;
        \\    std::size_t offset = 0;
        \\    if (index < 0) {
        \\        const std::uint64_t distance = static_cast<std::uint64_t>(-(index + 1)) + 1;
        \\        valid = distance <= count;
        \\        if (valid) offset = count - static_cast<std::size_t>(distance);
        \\    } else {
        \\        valid = static_cast<std::uint64_t>(index) < count;
        \\        if (valid) offset = static_cast<std::size_t>(index);
        \\    }
        \\    if (!valid) [[unlikely]] {
        \\        std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\                  << ": runtime error: collection index " << index
        \\                  << " is out of bounds for count " << count << '\n';
        \\        std::exit(1);
        \\    }
        \\    return offset;
        \\}
        \\
        \\std::size_t silexCollectionSliceBound(std::size_t count, std::int64_t bound) {
        \\    if (bound < 0) {
        \\        const std::uint64_t distance = static_cast<std::uint64_t>(-(bound + 1)) + 1;
        \\        if (distance >= count) return 0;
        \\        return count - static_cast<std::size_t>(distance);
        \\    }
        \\    const std::uint64_t offset = static_cast<std::uint64_t>(bound);
        \\    if (offset >= count) return count;
        \\    return static_cast<std::size_t>(offset);
        \\}
        \\
        \\template <typename Collection>
        \\decltype(auto) silexCollectionAt(Collection&& values, std::int64_t index, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionIndexOffset(values.size(), index, location);
        \\    return std::forward<Collection>(values)[offset];
        \\}
        \\
        \\template <typename Collection>
        \\SilexList<typename Collection::value_type> silexCollectionSlice(
        \\    const Collection& values,
        \\    std::int64_t start,
        \\    std::int64_t end
        \\) {
        \\    const std::size_t startOffset = silexCollectionSliceBound(values.size(), start);
        \\    const std::size_t endOffset = silexCollectionSliceBound(values.size(), end);
        \\    SilexList<typename Collection::value_type> result;
        \\    if (startOffset >= endOffset) return result;
        \\    result.reserve(endOffset - startOffset);
        \\    for (std::size_t index = startOffset; index < endOffset; ++index) {
        \\        result.push_back(values[index]);
        \\    }
        \\    return result;
        \\}
        \\
        \\template <typename Collection, typename T>
        \\void silexListPrepend(Collection& values, T value) {
        \\    values.insert(values.begin(), std::move(value));
        \\}
        \\
        \\template <typename Collection, typename T>
        \\void silexListInsert(Collection& values, std::int64_t index, T value, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionOffset(values.size(), index, true, location);
        \\    values.insert(values.begin() + static_cast<std::ptrdiff_t>(offset), std::move(value));
        \\}
        \\
        \\template <typename Collection>
        \\typename Collection::value_type silexListTake(Collection& values, std::int64_t index, SilexSourceLocation location) {
        \\    using T = typename Collection::value_type;
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, location);
        \\    T value = std::move(values[offset]);
        \\    values.erase(values.begin() + static_cast<std::ptrdiff_t>(offset));
        \\    return value;
        \\}
        \\
        \\template <typename Collection>
        \\typename Collection::value_type silexListTakeLast(Collection& values, SilexSourceLocation location) {
        \\    using T = typename Collection::value_type;
        \\    const auto offset = silexCollectionIndexOffset(values.size(), -1, location);
        \\    T value = std::move(values[offset]);
        \\    values.pop_back();
        \\    return value;
        \\}
        \\
        \\template <typename Collection, typename T>
        \\T silexCollectionReplace(Collection& values, std::int64_t index, T value, SilexSourceLocation location) {
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, location);
        \\    return std::exchange(values[offset], std::move(value));
        \\}
        \\
        \\template <typename Collection>
        \\void silexCollectionSwap(Collection& values, std::int64_t left, std::int64_t right, SilexSourceLocation location) {
        \\    const auto leftOffset = silexCollectionOffset(values.size(), left, false, location);
        \\    const auto rightOffset = silexCollectionOffset(values.size(), right, false, location);
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
        \\template <typename T> inline T checkedRemainder(T left, T right, SilexSourceLocation location, const char* typeName) {
        \\    if (right == 0) [[unlikely]] {
        \\        binaryIntegerRuntimeError(location, typeName, "division", "by zero", left, "%", right);
        \\    }
        \\    if constexpr (std::is_signed_v<T>) {
        \\        if (left == std::numeric_limits<T>::min() && right == T{-1}) [[unlikely]] {
        \\            binaryIntegerRuntimeError(location, typeName, "division", "overflow", left, "%", right);
        \\        }
        \\    }
        \\    return left % right;
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
        \\template <typename Count>
        \\[[noreturn, gnu::cold, gnu::noinline]] void shiftRuntimeError(
        \\    SilexSourceLocation location,
        \\    const char* typeName,
        \\    const char* operation,
        \\    Count count
        \\) {
        \\    std::cerr << silexSourcePath(location) << ':' << location.line << ':' << location.column
        \\              << ": runtime error: " << typeName << ' ' << operation << " count out of range: ";
        \\    printIntegerValue(count);
        \\    std::cerr << '\n';
        \\    std::exit(1);
        \\}
        \\
        \\template <typename T, typename Count> inline T checkedShiftLeft(T value, Count count, SilexSourceLocation location, const char* typeName) {
        \\    static_assert(std::is_unsigned_v<T>);
        \\    if constexpr (std::is_signed_v<Count>) {
        \\        if (count < 0) [[unlikely]] shiftRuntimeError(location, typeName, "left shift", count);
        \\    }
        \\    using UnsignedCount = std::make_unsigned_t<Count>;
        \\    if (static_cast<UnsignedCount>(count) >= sizeof(T) * CHAR_BIT) [[unlikely]] shiftRuntimeError(location, typeName, "left shift", count);
        \\    return static_cast<T>(value << count);
        \\}
        \\
        \\template <typename T, typename Count> inline T checkedShiftRight(T value, Count count, SilexSourceLocation location, const char* typeName) {
        \\    static_assert(std::is_unsigned_v<T>);
        \\    if constexpr (std::is_signed_v<Count>) {
        \\        if (count < 0) [[unlikely]] shiftRuntimeError(location, typeName, "right shift", count);
        \\    }
        \\    using UnsignedCount = std::make_unsigned_t<Count>;
        \\    if (static_cast<UnsignedCount>(count) >= sizeof(T) * CHAR_BIT) [[unlikely]] shiftRuntimeError(location, typeName, "right shift", count);
        \\    return static_cast<T>(value >> count);
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
    const structure_order = try structureDefinitionOrder(allocator, program.structures);
    for (structure_order) |structure_index| {
        const structure = program.structures[structure_index];
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        if (structure.is_class) {
            try output.appendSlice(allocator, " : ");
            if (structure.base) |base| {
                try output.appendSlice(allocator, "public ");
                try output.appendSlice(allocator, base.generated_name);
            } else {
                try output.appendSlice(allocator, "SilexObject");
            }
        }
        try output.appendSlice(allocator, " {\n");
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "    ");
            try appendCppType(allocator, &output, field.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, field.generated_name);
            if (structure.constructors.len != 0) {
                if (field.initializer) |initializer| {
                    try output.appendSlice(allocator, " = ");
                    try generateExpression(allocator, &output, initializer);
                } else {
                    try output.appendSlice(allocator, "{}");
                }
            }
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.is_class and structure.constructors.len == 0 and structure.implicit_constructor_available) {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.append(allocator, '(');
            for (structure.fields, 0..) |field, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, &output, field.type);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexField{d}", .{index}));
            }
            try output.append(allocator, ')');
            if (structure.fields.len == 0 and structure.implicit_base_initializer == null) {
                try output.appendSlice(allocator, " = default;\n");
            } else {
                try output.appendSlice(allocator, " : ");
                var initializer_count: usize = 0;
                if (structure.implicit_base_initializer) |base_initializer| {
                    try generateBaseInitializer(allocator, &output, base_initializer);
                    initializer_count += 1;
                }
                for (structure.fields, 0..) |field, index| {
                    if (initializer_count != 0 or index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, field.generated_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "(std::move(silexField{d}))", .{index}));
                    initializer_count += 1;
                }
                try output.appendSlice(allocator, " {}\n");
            }
        }
        for (structure.constructors) |constructor| {
            try output.appendSlice(allocator, "\n    ");
            try generateConstructorSignature(allocator, &output, structure.generated_name, constructor, false);
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.drop != null) {
            try output.appendSlice(allocator, "\n    void silexDrop() override;\n");
        }
        if (structure.fields.len > 0 and (structure.constructors.len > 0 or structure.methods.len > 0)) try output.append(allocator, '\n');
        for (structure.methods) |method| {
            try output.appendSlice(allocator, "    ");
            if (structure.is_class and method.visibility != .private_access) try output.appendSlice(allocator, "virtual ");
            try generateMethodSignature(allocator, &output, method, null, false);
            if (method.is_override) try output.appendSlice(allocator, " override");
            try output.appendSlice(allocator, ";\n");
        }
        try output.appendSlice(allocator, "\n    void silexTrace(const SilexTraceVisitor& visit) const");
        if (structure.is_class) try output.appendSlice(allocator, " override");
        try output.appendSlice(allocator, " {\n");
        if (structure.base) |base| {
            try output.appendSlice(allocator, "        ");
            try output.appendSlice(allocator, base.generated_name);
            try output.appendSlice(allocator, "::silexTrace(visit);\n");
        }
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "        silexTraceValue(");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ", visit);\n");
        }
        try output.appendSlice(allocator, "    }\n    void silexClear()");
        if (structure.is_class) try output.appendSlice(allocator, " override");
        try output.appendSlice(allocator, " {\n");
        if (structure.base) |base| {
            try output.appendSlice(allocator, "        ");
            try output.appendSlice(allocator, base.generated_name);
            try output.appendSlice(allocator, "::silexClear();\n");
        }
        for (structure.fields) |field| {
            try output.appendSlice(allocator, "        silexClearValue(");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator, "    }\n");
        try output.appendSlice(allocator, "};\n\n");
    }
    if (program.structures.len > 0) {
        for (program.structures) |structure| {
            if (structure.is_class) continue;
            try generateStructureEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
        }
        try output.append(allocator, '\n');
        for (program.structures) |structure| {
            if (structure.is_class) continue;
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
        for (structure.constructors) |constructor| {
            try generateConstructorSignature(allocator, &output, structure.generated_name, constructor, true);
            if (constructor.base_initializer) |base_initializer| {
                try output.appendSlice(allocator, " : ");
                try generateBaseInitializer(allocator, &output, base_initializer);
            }
            try output.appendSlice(allocator, " {\n");
            try generateCapturedParameterBindings(allocator, &output, constructor.parameters, 1);
            try generateStatements(allocator, &output, constructor.statements, 1, false);
            try output.appendSlice(allocator, "}\n\n");
        }
        if (structure.drop) |drop| {
            try output.appendSlice(allocator, "void ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "::silexDrop() {\n");
            try generateStatements(allocator, &output, drop.statements, 1, false);
            try output.appendSlice(allocator, "    ");
            if (structure.base) |base| {
                try output.appendSlice(allocator, base.generated_name);
            } else {
                try output.appendSlice(allocator, "SilexObject");
            }
            try output.appendSlice(allocator, "::silexDrop();\n}\n\n");
        }
        for (structure.methods) |method| {
            try generateMethodSignature(allocator, &output, method, structure.generated_name, true);
            try output.appendSlice(allocator, " {\n");
            try generateCapturedParameterBindings(allocator, &output, method.parameters, 1);
            try generateStatements(allocator, &output, method.statements, 1, false);
            try output.appendSlice(allocator, "}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_native) continue;
        try generateFunctionSignature(allocator, &output, function, true);
        try output.appendSlice(allocator, " {\n");
        try generateCapturedParameterBindings(allocator, &output, function.parameters, 1);
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
        \\    const int result = SilexGenerated::silexMain();
        \\    if (SilexGenerated::silexLiveObjects != 0) {
        \\        std::cerr << "silex: runtime error: unreachable class graph was not collected\n";
        \\        return 1;
        \\    }
        \\    return result;
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
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
    if (!method.is_mutating) try output.appendSlice(allocator, " const");
}

fn generateBaseInitializer(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    initializer: Semantic.BaseInitializer,
) !void {
    try output.appendSlice(allocator, initializer.generated_name);
    try output.append(allocator, '(');
    for (initializer.arguments, 0..) |argument, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try generateExpression(allocator, output, argument);
    }
    try output.append(allocator, ')');
}

fn structureDefinitionOrder(allocator: Allocator, structures: []const Semantic.Structure) ![]const usize {
    const emitted = try allocator.alloc(bool, structures.len);
    @memset(emitted, false);
    var order: std.ArrayList(usize) = .empty;
    while (order.items.len != structures.len) {
        var progressed = false;
        for (structures, 0..) |structure, index| {
            if (emitted[index]) continue;
            if (structure.base) |base| {
                var base_index: ?usize = null;
                for (structures, 0..) |candidate, candidate_index| {
                    if (std.mem.eql(u8, candidate.generated_name, base.generated_name)) base_index = candidate_index;
                }
                if (base_index == null or !emitted[base_index.?]) continue;
            }
            emitted[index] = true;
            try order.append(allocator, index);
            progressed = true;
        }
        if (!progressed) unreachable;
    }
    return order.toOwnedSlice(allocator);
}

fn generateConstructorSignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    owner_name: []const u8,
    constructor: Semantic.Constructor,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, owner_name);
    if (include_names) {
        try output.appendSlice(allocator, "::");
        try output.appendSlice(allocator, owner_name);
    }
    try output.append(allocator, '(');
    for (constructor.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter.type);
        if (parameter.is_mutable_reference) try output.append(allocator, '&');
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
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
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
}

fn generateCapturedParameterBindings(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    parameters: []const Semantic.Parameter,
    indentation: usize,
) !void {
    for (parameters) |parameter| {
        if (!parameter.capture_box.*) continue;
        try indent(allocator, output, indentation);
        try output.appendSlice(allocator, "auto ");
        try output.appendSlice(allocator, parameter.generated_name);
        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
        try appendCppType(allocator, output, parameter.type);
        try output.appendSlice(allocator, ">>(");
        try output.appendSlice(allocator, parameter.generated_name);
        try output.appendSlice(allocator, "Input);\n");
    }
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
        .function => try output.appendSlice(allocator, "false"),
        .structure => |structure_type| {
            if (structure_type.is_class) {
                try output.appendSlice(allocator, "left.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " == right.");
                try output.appendSlice(allocator, field.generated_name);
            } else {
                try generateStructureEqualityName(allocator, output, structure_type.generated_name);
                try output.appendSlice(allocator, "(left.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ", right.");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            }
        },
        .optional => |contained| if (contained.* == .structure and !contained.*.structure.is_class) {
            try output.appendSlice(allocator, "((!left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && !right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value()) || (left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ".has_value() && ");
            try generateStructureEqualityName(allocator, output, contained.*.structure.generated_name);
            try output.appendSlice(allocator, "(*left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ", *right.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, ")))");
        } else {
            try output.appendSlice(allocator, "left.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " == right.");
            try output.appendSlice(allocator, field.generated_name);
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
        .assertion => |assertion| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "if (!");
            try generateCondition(allocator, output, .{ .expression = assertion.condition });
            try output.appendSlice(allocator, ") assertionRuntimeError(");
            try appendCppSourceLocation(allocator, output, assertion.position);
            try output.appendSlice(allocator, ", ");
            try generateExpression(allocator, output, assertion.message);
            try output.appendSlice(allocator, ");\n");
        },
        .panic_statement => |panic_value| {
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "panicRuntimeError(");
            try appendCppSourceLocation(allocator, output, panic_value.position);
            try output.appendSlice(allocator, ", ");
            try generateExpression(allocator, output, panic_value.message);
            try output.appendSlice(allocator, ");\n");
        },
        .variable_declaration => |declaration| {
            try indent(allocator, output, indentation);
            if (declaration.capture_box.*) {
                try output.appendSlice(allocator, "auto ");
                try output.appendSlice(allocator, declaration.generated_name);
                try output.appendSlice(allocator, " = silexMake<SilexBinding<");
                try appendCppType(allocator, output, declaration.type);
                try output.appendSlice(allocator, ">>(");
                try generateExpression(allocator, output, declaration.initializer);
                try output.append(allocator, ')');
            } else {
                if (declaration.mutability == .immutable and declaration.type != .reference) try output.appendSlice(allocator, "const ");
                try appendCppType(allocator, output, declaration.type);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, declaration.generated_name);
                try output.appendSlice(allocator, " = ");
                try generateExpression(allocator, output, declaration.initializer);
            }
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
            try generateConditionalBindingDeclaration(allocator, output, if_statement.condition, indentation + 1);
            try generateStatements(allocator, output, if_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            for (if_statement.alternatives) |alternative| {
                try output.appendSlice(allocator, "} else if ");
                try generateCondition(allocator, output, alternative.condition);
                try output.appendSlice(allocator, " {\n");
                try generateConditionalBindingDeclaration(allocator, output, alternative.condition, indentation + 1);
                try generateStatements(allocator, output, alternative.body, indentation + 1, is_main);
                try indent(allocator, output, indentation);
            }
            if (if_statement.else_body) |else_body| {
                try output.appendSlice(allocator, "} else {\n");
                try generateStatements(allocator, output, else_body, indentation + 1, is_main);
                try indent(allocator, output, indentation);
            }
            try output.appendSlice(allocator, "}\n");
        },
        .while_statement => |while_statement| {
            if (while_statement.condition == .binding) {
                const binding = while_statement.condition.binding;
                try indent(allocator, output, indentation);
                try output.appendSlice(allocator, "while (true) {\n");
                try indent(allocator, output, indentation + 1);
                try output.appendSlice(allocator, "auto ");
                try output.appendSlice(allocator, binding.temporary_name);
                try output.appendSlice(allocator, " = ");
                try generateExpression(allocator, output, binding.source);
                try output.appendSlice(allocator, ";\n");
                try indent(allocator, output, indentation + 1);
                try output.appendSlice(allocator, "if (!");
                try output.appendSlice(allocator, binding.temporary_name);
                try output.appendSlice(allocator, ".has_value()) break;\n");
                try generateConditionalBindingDeclaration(allocator, output, while_statement.condition, indentation + 1);
                try generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
                try indent(allocator, output, indentation);
                try output.appendSlice(allocator, "}\n");
                return;
            }
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "while ");
            try generateCondition(allocator, output, while_statement.condition);
            try output.appendSlice(allocator, " {\n");
            try generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .for_statement => |for_statement| {
            switch (for_statement.source) {
                .collection => |collection| {
                    try indent(allocator, output, indentation);
                    try output.appendSlice(allocator, "for (");
                    if (for_statement.mutability == .immutable) try output.appendSlice(allocator, "const ");
                    try output.appendSlice(allocator, "auto& ");
                    try output.appendSlice(allocator, for_statement.generated_name);
                    if (for_statement.capture_box.*) try output.appendSlice(allocator, "Input");
                    try output.appendSlice(allocator, " : ");
                    try generateExpression(allocator, output, collection);
                    try output.appendSlice(allocator, ") {\n");
                    if (for_statement.capture_box.*) {
                        try indent(allocator, output, indentation + 1);
                        try output.appendSlice(allocator, "auto ");
                        try output.appendSlice(allocator, for_statement.generated_name);
                        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
                        try appendCppType(allocator, output, for_statement.element_type);
                        try output.appendSlice(allocator, ">>(");
                        try output.appendSlice(allocator, for_statement.generated_name);
                        try output.appendSlice(allocator, "Input);\n");
                    }
                    try generateStatements(allocator, output, for_statement.body, indentation + 1, is_main);
                    try indent(allocator, output, indentation);
                    try output.appendSlice(allocator, "}\n");
                },
                .integer_range => |range| try generateIntegerRangeStatement(
                    allocator,
                    output,
                    for_statement,
                    range,
                    indentation,
                    is_main,
                ),
            }
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

fn generateIntegerRangeStatement(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    for_statement: Semantic.Statement.For,
    range: Semantic.Statement.For.IntegerRange,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    std.debug.assert(!for_statement.capture_box.*);
    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, " = ");
    try generateExpression(allocator, output, range.start);
    try output.appendSlice(allocator, ";\n");

    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, " = ");
    try generateExpression(allocator, output, range.end);
    try output.appendSlice(allocator, ";\n");

    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "const std::int64_t ");
    try output.appendSlice(allocator, range.generated_step_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, " < ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, " ? 1 : -1;\n");

    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "for (std::int64_t ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_start_name);
    try output.appendSlice(allocator, "; ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " != ");
    try output.appendSlice(allocator, range.generated_end_name);
    try output.appendSlice(allocator, "; ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, " += ");
    try output.appendSlice(allocator, range.generated_step_name);
    try output.appendSlice(allocator, ") {\n");

    try indent(allocator, output, indentation + 1);
    if (for_statement.mutability == .immutable) try output.appendSlice(allocator, "const ");
    try output.appendSlice(allocator, "std::int64_t ");
    try output.appendSlice(allocator, for_statement.generated_name);
    try output.appendSlice(allocator, " = ");
    try output.appendSlice(allocator, range.generated_current_name);
    try output.appendSlice(allocator, ";\n");
    try generateStatements(allocator, output, for_statement.body, indentation + 1, is_main);
    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "}\n");
}

fn generateCondition(allocator: Allocator, output: *std.ArrayList(u8), condition: Semantic.Statement.Condition) !void {
    if (condition == .binding) {
        const binding = condition.binding;
        try output.appendSlice(allocator, "(auto ");
        try output.appendSlice(allocator, binding.temporary_name);
        try output.appendSlice(allocator, " = ");
        try generateExpression(allocator, output, binding.source);
        try output.appendSlice(allocator, "; ");
        try output.appendSlice(allocator, binding.temporary_name);
        try output.appendSlice(allocator, ".has_value())");
        return;
    }
    const expression = condition.expression;
    const already_parenthesized = expression.value == .binary or expression.value == .unary;
    if (!already_parenthesized) try output.append(allocator, '(');
    try generateExpression(allocator, output, expression);
    if (!already_parenthesized) try output.append(allocator, ')');
}

fn generateConditionalBindingDeclaration(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    condition: Semantic.Statement.Condition,
    indentation: usize,
) !void {
    if (condition != .binding) return;
    const binding = condition.binding;
    try indent(allocator, output, indentation);
    if (binding.capture_box.*) {
        try output.appendSlice(allocator, "auto ");
        try output.appendSlice(allocator, binding.generated_name);
        try output.appendSlice(allocator, " = silexMake<SilexBinding<");
        try appendCppType(allocator, output, binding.type);
        try output.appendSlice(allocator, ">>(*");
        try output.appendSlice(allocator, binding.temporary_name);
        try output.append(allocator, ')');
    } else {
        if (binding.mutability == .immutable) try output.appendSlice(allocator, "const ");
        try appendCppType(allocator, output, binding.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, binding.generated_name);
        try output.appendSlice(allocator, " = *");
        try output.appendSlice(allocator, binding.temporary_name);
    }
    try output.appendSlice(allocator, ";\n");
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
        .null => try output.appendSlice(allocator, "std::nullopt"),
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
            try output.appendSlice(allocator, ", ");
            try appendCppSourceLocation(allocator, output, expression.position);
            try output.append(allocator, ')');
        },
        .slice_access => |access| {
            try output.appendSlice(allocator, "([&]() { const auto& silexSliceValues = ");
            try generateExpression(allocator, output, access.object);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceStart = ");
            try generateExpression(allocator, output, access.start);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceEnd = ");
            try generateExpression(allocator, output, access.end);
            try output.appendSlice(allocator, "; return silexCollectionSlice(silexSliceValues, silexSliceStart, silexSliceEnd); }())");
        },
        .variable => |variable| {
            try output.appendSlice(allocator, variable.generated_name);
            if (variable.capture_box.*) try output.appendSlice(allocator, "->value");
        },
        .self => if (isClassType(expression.type))
            try output.appendSlice(allocator, "silexShare(this)")
        else
            try output.appendSlice(allocator, "*this"),
        .owner_self => try output.appendSlice(allocator, "silexOwner"),
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
        .value_call => |call| {
            try generateExpression(allocator, output, call.callee);
            try output.append(allocator, '(');
            if (call.owner) |owner| {
                if (owner.value == .self) {
                    try output.appendSlice(allocator, "*this");
                } else if (owner.value == .owner_self) {
                    try output.appendSlice(allocator, "silexOwner");
                } else {
                    if (isClassType(owner.type)) try output.append(allocator, '*');
                    try generateExpression(allocator, output, owner);
                }
            }
            for (call.arguments, 0..) |argument, index| {
                if (index != 0 or call.owner != null) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .lambda => |lambda| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.append(allocator, '[');
            var capture_index: usize = 0;
            if (lambda.captures_self) {
                try output.appendSlice(allocator, "this");
                capture_index += 1;
            }
            for (lambda.captures) |capture| {
                if (capture_index != 0) try output.appendSlice(allocator, ", ");
                if (!capture.by_value) try output.append(allocator, '&');
                try output.appendSlice(allocator, capture.generated_name);
                capture_index += 1;
            }
            try output.appendSlice(allocator, "](");
            var parameter_index: usize = 0;
            if (expression.type.function.owner) |owner| {
                try output.appendSlice(allocator, owner.generated_name);
                try output.appendSlice(allocator, "& silexOwner");
                parameter_index += 1;
            }
            for (lambda.parameters) |parameter| {
                if (parameter_index != 0) try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, output, parameter.type);
                if (parameter.is_mutable_reference) try output.append(allocator, '&');
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
                parameter_index += 1;
            }
            try output.appendSlice(allocator, ") {\n");
            try generateCapturedParameterBindings(allocator, output, lambda.parameters, 1);
            try generateStatements(allocator, output, lambda.statements, 1, false);
            try output.append(allocator, '}');
            for (lambda.captures) |capture| {
                if (!capture.by_value) continue;
                try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, capture.generated_name);
            }
            if (lambda.captures_self and lambda.self_is_class) {
                try output.appendSlice(allocator, ", silexShare(this)");
            }
            try output.append(allocator, ')');
        },
        .method_call => |call| {
            if (call.object.value == .owner_self) {
                try output.appendSlice(allocator, "silexOwner.");
            } else if (call.object.value != .self) {
                try generateExpression(allocator, output, call.object);
                try output.appendSlice(allocator, if (isClassType(call.object.type)) "->" else ".");
            }
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .super_method_call => |call| {
            try output.appendSlice(allocator, call.base_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .class_initializer => |initializer| {
            try output.appendSlice(allocator, "silexMake<");
            try output.appendSlice(allocator, initializer.generated_name);
            try output.appendSlice(allocator, ">(");
            for (initializer.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .structure_initializer => |initializer| {
            if (isClassType(expression.type)) {
                try output.appendSlice(allocator, "silexMake<");
                try output.appendSlice(allocator, initializer.generated_name);
                try output.appendSlice(allocator, ">(");
            } else {
                try output.appendSlice(allocator, initializer.generated_name);
                try output.append(allocator, '{');
            }
            for (initializer.fields, 0..) |field, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, field);
            }
            try output.append(allocator, if (isClassType(expression.type)) ')' else '}');
        },
        .member_access => |member| {
            if (member.object.value == .owner_self) {
                try output.appendSlice(allocator, "silexOwner.");
            } else if (member.object.value != .self) {
                try generateExpression(allocator, output, member.object);
                try output.appendSlice(allocator, if (isClassType(member.object.type)) "->" else ".");
            }
            try output.appendSlice(allocator, member.generated_name);
        },
        .bound_function => |member| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.appendSlice(allocator, if (isClassType(member.object.type))
                "[silexBoundOwner = "
            else
                "[&silexBoundOwner = ");
            try generateExpression(allocator, output, member.object);
            try output.appendSlice(allocator, "](");
            for (expression.type.function.parameters, expression.type.function.parameter_is_mutable_references, 0..) |parameter_type, is_mutable_reference, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, output, parameter_type);
                if (is_mutable_reference) try output.append(allocator, '&');
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexBoundArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, if (isClassType(member.object.type))
                ") { return silexBoundOwner->"
            else
                ") { return silexBoundOwner.");
            try output.appendSlice(allocator, member.generated_name);
            try output.appendSlice(allocator, if (isClassType(member.object.type))
                "(*silexBoundOwner"
            else
                "(silexBoundOwner");
            for (expression.type.function.parameters, 0..) |_, index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", silexBoundArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }");
            if (isClassType(member.object.type)) {
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, member.object);
            }
            try output.append(allocator, ')');
        },
        .adapt_function => |value| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">(");
            try output.appendSlice(allocator, "[silexCallback = ");
            try generateExpression(allocator, output, value);
            try output.appendSlice(allocator, "](");
            const function = expression.type.function;
            try output.appendSlice(allocator, function.owner.?.generated_name);
            try output.appendSlice(allocator, "&");
            for (function.parameters, function.parameter_is_mutable_references, 0..) |parameter_type, is_mutable_reference, index| {
                try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, output, parameter_type);
                if (is_mutable_reference) try output.append(allocator, '&');
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexAdaptedArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return silexCallback(");
            for (function.parameters, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexAdaptedArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }, ");
            try generateExpression(allocator, output, value);
            try output.append(allocator, ')');
        },
        .optional_wrap => |value| {
            try appendCppType(allocator, output, expression.type);
            try output.append(allocator, '{');
            try generateExpression(allocator, output, value);
            try output.append(allocator, '}');
        },
        .optional_unwrap => |variable| {
            try output.appendSlice(allocator, "(*");
            try output.appendSlice(allocator, variable.generated_name);
            if (variable.capture_box.*) try output.appendSlice(allocator, "->value");
            try output.append(allocator, ')');
        },
        .safe_access => |access| {
            try output.appendSlice(allocator, "[&]()");
            if (expression.type != .void) {
                try output.appendSlice(allocator, " -> ");
                try appendCppType(allocator, output, expression.type);
            }
            try output.appendSlice(allocator, " { auto&& silexOptionalValue = ");
            try generateExpression(allocator, output, access.receiver);
            if (expression.type == .void) {
                try output.appendSlice(allocator, "; if (silexOptionalValue.has_value()) { ");
                try generateExpression(allocator, output, access.end);
                try output.appendSlice(allocator, "; } }()");
            } else {
                try output.appendSlice(allocator, "; if (!silexOptionalValue.has_value()) return std::nullopt; return ");
                try generateExpression(allocator, output, access.end);
                try output.appendSlice(allocator, "; }()");
            }
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
            } else if (isShift(binary.operator)) {
                try output.appendSlice(allocator, checkedShiftFunction(binary.operator));
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, binary.right);
                try generateRuntimeArguments(allocator, output, expression.position, expression.type);
                try output.append(allocator, ')');
            } else if ((binary.operator == .equal or binary.operator == .not_equal) and binary.left.type == .optional and
                binary.right.type == .optional and binary.left.value != .null and binary.right.value != .null and
                binary.left.type.optional.* == .structure and !binary.left.type.optional.*.structure.is_class)
            {
                try output.append(allocator, '(');
                if (binary.operator == .not_equal) try output.append(allocator, '!');
                try output.appendSlice(allocator, "[&]() { const auto& silexOptionalLeft = ");
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, "; const auto& silexOptionalRight = ");
                try generateExpression(allocator, output, binary.right);
                try output.appendSlice(allocator, "; return (!silexOptionalLeft.has_value() && !silexOptionalRight.has_value()) || (silexOptionalLeft.has_value() && silexOptionalRight.has_value() && ");
                try generateStructureEqualityName(allocator, output, binary.left.type.optional.*.structure.generated_name);
                try output.appendSlice(allocator, "(*silexOptionalLeft, *silexOptionalRight)); }())");
            } else if ((binary.operator == .equal or binary.operator == .not_equal) and binary.left.type == .structure and
                !binary.left.type.structure.is_class)
            {
                const structure_type = binary.left.type.structure;
                try output.append(allocator, '(');
                if (binary.operator == .not_equal) try output.append(allocator, '!');
                try generateStructureEqualityName(allocator, output, structure_type.generated_name);
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, binary.right);
                try output.appendSlice(allocator, "))");
            } else {
                try output.append(allocator, '(');
                try generateExpression(allocator, output, binary.left);
                try output.appendSlice(allocator, operatorText(binary.operator));
                try generateExpression(allocator, output, binary.right);
                try output.append(allocator, ')');
            }
        },
        .conversion => |conversion| {
            if (isClassType(conversion.target_type)) {
                try generateExpression(allocator, output, conversion.operand);
                return;
            }
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
        .function => unreachable,
        .list, .fixed_array => unreachable,
        .structure => |structure_type| if (structure_type.is_class) unreachable else structure_type.generated_name,
        .reference => unreachable,
        .optional, .null => unreachable,
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
        .function => |function| {
            try output.appendSlice(allocator, "SilexFunction<");
            try appendCppType(allocator, output, function.return_type.*);
            try output.append(allocator, '(');
            var index: usize = 0;
            if (function.owner) |owner| {
                try output.appendSlice(allocator, owner.generated_name);
                try output.append(allocator, '&');
                index += 1;
            }
            for (function.parameters, function.parameter_is_mutable_references) |parameter, is_mutable_reference| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, output, parameter);
                if (is_mutable_reference) try output.append(allocator, '&');
                index += 1;
            }
            try output.appendSlice(allocator, ")>");
        },
        .optional => |contained| {
            try output.appendSlice(allocator, "std::optional<");
            try appendCppType(allocator, output, contained.*);
            try output.append(allocator, '>');
        },
        .structure => |structure_type| {
            if (structure_type.is_class) {
                try output.appendSlice(allocator, "SilexRef<");
                try output.appendSlice(allocator, structure_type.generated_name);
                try output.append(allocator, '>');
            } else {
                try output.appendSlice(allocator, structure_type.generated_name);
            }
        },
        .null => unreachable,
        else => try output.appendSlice(allocator, cppType(type_name)),
    }
}

fn isClassType(type_name: Semantic.Type) bool {
    return type_name == .structure and type_name.structure.is_class;
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
        .function => "func",
        .optional => "optional",
        .null => "null",
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
        .add, .subtract, .multiply, .divide, .remainder => true,
        else => false,
    };
}

fn isShift(operator: Ast.BinaryOperator) bool {
    return switch (operator) {
        .shift_left, .shift_right => true,
        else => false,
    };
}

fn checkedBinaryFunction(operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .add => "checkedAdd",
        .subtract => "checkedSubtract",
        .multiply => "checkedMultiply",
        .divide => "checkedDivide",
        .remainder => "checkedRemainder",
        else => unreachable,
    };
}

fn checkedShiftFunction(operator: Ast.BinaryOperator) []const u8 {
    return switch (operator) {
        .shift_left => "checkedShiftLeft",
        .shift_right => "checkedShiftRight",
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
        .shift_left => " << ",
        .shift_right => " >> ",
        .bit_and => " & ",
        .bit_xor => " ^ ",
        .multiply => " * ",
        .divide => " / ",
        .remainder => " % ",
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

fn resolveSingleTestProgram(allocator: Allocator, program: Ast.Program) !Ast.Program {
    const Modules = @import("Modules.zig");
    const project = @import("Project.zig").Project{
        .program_name = "Test",
        .target_module = 0,
        .modules = &.{.{ .name = "Test", .sources = &.{"Test.sx"} }},
        .single_file = true,
    };
    var resolver = Modules.Resolver.init(allocator, project, &.{.{ .module_index = 0, .program = program }});
    return resolver.resolve();
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

test "generate negative collection indexes and ordered slices" {
    const Parser = @import("Parser.zig").Parser;
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
}

test "generate class references identity access and cycle tracing" {
    const Parser = @import("Parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator,
        \\class Node { var next:Node? = null; pub func clear() { self.next = null } }
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

test "generate drop before field clearing with automatic base chaining" {
    const Parser = @import("Parser.zig").Parser;
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

test "generate inferred const and mutating methods" {
    const Parser = @import("Parser.zig").Parser;
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
