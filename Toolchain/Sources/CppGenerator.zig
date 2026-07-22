const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("Ast.zig");
const NativeInterface = @import("NativeInterface.zig");
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
        \\#include <atomic>
        \\#include <cstddef>
        \\#include <cstdint>
        \\#include <cstdlib>
        \\#include <exception>
        \\#include <functional>
        \\#include <array>
        \\#include <bit>
        \\#include <climits>
        \\#include <cmath>
        \\#include <concepts>
        \\#include <iostream>
        \\#include <iterator>
        \\#include <limits>
        \\#include <memory>
        \\#include <mutex>
        \\#include <optional>
        \\#include <stdexcept>
        \\#include <string>
        \\#include <tuple>
        \\#include <type_traits>
        \\#include <unordered_map>
        \\#include <utility>
        \\#include <vector>
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\#include <condition_variable>
        \\#endif
        \\
    );
    var emitted_native_transports: std.ArrayList([]const u8) = .empty;
    for (program.functions) |function| {
        if (!function.is_native) continue;
        if (nativeResultShape(program, function.return_type)) |result| {
            if (nativeStructureForType(program, nativeBranchValueType(result.success_type))) |structure| {
                try generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, function.native_module_name.?, structure, false);
            }
            if (nativeStructureForType(program, nativeBranchValueType(result.failure_type))) |structure| {
                try generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, function.native_module_name.?, structure, false);
            }
            try generateNativeResultTransportIfNew(
                allocator,
                &output,
                &emitted_native_transports,
                program,
                function,
                result,
            );
        }
        if (nativeReturnStructure(program, function)) |structure| {
            try generateNativeTransportIfNew(
                allocator,
                &output,
                &emitted_native_transports,
                function.native_module_name.?,
                structure,
                false,
            );
        }
        for (function.parameters) |parameter| {
            if (nativeStructureForType(program, parameter.type)) |structure| {
                try generateNativeTransportIfNew(
                    allocator,
                    &output,
                    &emitted_native_transports,
                    function.native_module_name.?,
                    structure,
                    true,
                );
            }
        }
    }
    for (program.structures) |structure| {
        if (!structure.is_native_resource) continue;
        try generateNativeTransportIfNew(allocator, &output, &emitted_native_transports, structure.native_module_name.?, structure, false);
    }
    for (program.functions) |function| {
        if (!function.is_native) continue;
        try generateNativeFunctionSignature(allocator, &output, program, function, true);
        try output.appendSlice(allocator, ";\n");
    }
    if (containsNativeFunction(program.functions)) try output.appendSlice(allocator, "\nstruct SilexNativeReturnTag {};\n\n");
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
        \\[[noreturn]] void nativeStructureFieldRuntimeError(
        \\    const char* module,
        \\    const char* function,
        \\    const char* field,
        \\    const char* message
        \\) {
        \\    std::cerr << "runtime error: native function '" << module << '.' << function
        \\              << "' field '" << field << "' failed: " << message << '\n';
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
        \\bool nativeStringIsValidUtf8(const std::string& value) {
        \\    for (std::size_t index = 0; index < value.size();) {
        \\        const auto first = static_cast<unsigned char>(value[index]);
        \\        if (first <= 0x7f) {
        \\            index += 1;
        \\            continue;
        \\        }
        \\        std::size_t continuationCount = 0;
        \\        std::uint32_t scalar = 0;
        \\        std::uint32_t minimum = 0;
        \\        if (first >= 0xc2 && first <= 0xdf) {
        \\            continuationCount = 1;
        \\            scalar = first & 0x1f;
        \\            minimum = 0x80;
        \\        } else if (first >= 0xe0 && first <= 0xef) {
        \\            continuationCount = 2;
        \\            scalar = first & 0x0f;
        \\            minimum = 0x800;
        \\        } else if (first >= 0xf0 && first <= 0xf4) {
        \\            continuationCount = 3;
        \\            scalar = first & 0x07;
        \\            minimum = 0x10000;
        \\        } else {
        \\            return false;
        \\        }
        \\        if (value.size() - index <= continuationCount) return false;
        \\        for (std::size_t offset = 1; offset <= continuationCount; offset += 1) {
        \\            const auto continuation = static_cast<unsigned char>(value[index + offset]);
        \\            if ((continuation & 0xc0) != 0x80) return false;
        \\            scalar = (scalar << 6) | (continuation & 0x3f);
        \\        }
        \\        if (scalar < minimum || (scalar >= 0xd800 && scalar <= 0xdfff) || scalar > 0x10ffff) return false;
        \\        index += continuationCount + 1;
        \\    }
        \\    return true;
        \\}
        \\
        \\#ifndef SILEX_NATIVE_RELEASE_OBSERVER
        \\#define SILEX_NATIVE_RELEASE_OBSERVER(pointer) ((void)0)
        \\#endif
        \\
        \\static void silexNativeRelease(void* pointer) {
        \\    SILEX_NATIVE_RELEASE_OBSERVER(pointer);
        \\    std::free(pointer);
        \\}
        \\
        \\template <typename Call>
        \\std::string callNativeStringFunction(const char* module, const char* function, Call&& call) {
        \\    char* outputBytes = nullptr;
        \\    std::int64_t outputLength = 0;
        \\    try {
        \\        std::forward<Call>(call)(&outputBytes, &outputLength);
        \\    } catch (const std::exception& exception) {
        \\        silexNativeRelease(outputBytes);
        \\        nativeFunctionRuntimeError(module, function, exception.what());
        \\    } catch (...) {
        \\        silexNativeRelease(outputBytes);
        \\        nativeFunctionRuntimeError(module, function, "unknown native exception");
        \\    }
        \\    std::unique_ptr<char, decltype(&silexNativeRelease)> output{outputBytes, &silexNativeRelease};
        \\    if (outputLength < 0) {
        \\        output.reset();
        \\        nativeFunctionRuntimeError(module, function, "returned a negative length");
        \\    }
        \\    if (outputBytes == nullptr && outputLength > 0) {
        \\        output.reset();
        \\        nativeFunctionRuntimeError(module, function, "returned a null pointer with a positive length");
        \\    }
        \\    if (outputBytes == nullptr) return {};
        \\    std::string result{outputBytes, static_cast<std::size_t>(outputLength)};
        \\    output.reset();
        \\    if (!nativeStringIsValidUtf8(result)) {
        \\        nativeFunctionRuntimeError(module, function, "returned invalid UTF-8");
        \\    }
        \\    return result;
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
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\inline std::atomic<std::int64_t> silexLiveDeferredCallbackContexts = 0;
        \\inline std::atomic<std::int64_t> silexLiveDeferredCallbackEvents = 0;
        \\inline std::atomic<std::int64_t> silexLiveCapturedValueStates = 0;
        \\inline std::atomic<std::int64_t> silexAcceptedDeferredCallbackEvents = 0;
        \\inline std::atomic<std::int64_t> silexDispatchedDeferredCallbackEvents = 0;
        \\inline std::atomic<std::int64_t> silexDestroyedDeferredCallbackEvents = 0;
        \\inline std::atomic<std::int64_t> silexCancelledDeferredCallbackEnqueues = 0;
        \\
        \\extern "C" std::int64_t silexGeneratedLiveDeferredCallbackContexts() {
        \\    return silexLiveDeferredCallbackContexts.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedLiveDeferredCallbackEvents() {
        \\    return silexLiveDeferredCallbackEvents.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedLiveCapturedValueStates() {
        \\    return silexLiveCapturedValueStates.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedAcceptedDeferredCallbackEvents() {
        \\    return silexAcceptedDeferredCallbackEvents.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedDispatchedDeferredCallbackEvents() {
        \\    return silexDispatchedDeferredCallbackEvents.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedDestroyedDeferredCallbackEvents() {
        \\    return silexDestroyedDeferredCallbackEvents.load(std::memory_order_relaxed);
        \\}
        \\extern "C" std::int64_t silexGeneratedCancelledDeferredCallbackEnqueues() {
        \\    return silexCancelledDeferredCallbackEnqueues.load(std::memory_order_relaxed);
        \\}
        \\
        \\struct SilexDeferredCallbackEnqueueTestGate {
        \\    std::mutex mutex;
        \\    std::condition_variable condition;
        \\    std::atomic<bool> armed = false;
        \\    bool entered = false;
        \\    bool released = false;
        \\    void arm() {
        \\        std::scoped_lock lock(mutex);
        \\        entered = false;
        \\        released = false;
        \\        armed.store(true, std::memory_order_release);
        \\    }
        \\    void engage() {
        \\        if (!armed.load(std::memory_order_acquire)) return;
        \\        std::unique_lock lock(mutex);
        \\        if (!armed.load(std::memory_order_relaxed)) return;
        \\        entered = true;
        \\        condition.notify_all();
        \\        condition.wait(lock, [this] { return released; });
        \\        armed.store(false, std::memory_order_release);
        \\    }
        \\    void waitUntilEntered() {
        \\        std::unique_lock lock(mutex);
        \\        condition.wait(lock, [this] { return entered; });
        \\    }
        \\    void release() {
        \\        std::scoped_lock lock(mutex);
        \\        released = true;
        \\        condition.notify_all();
        \\    }
        \\};
        \\
        \\inline SilexDeferredCallbackEnqueueTestGate silexDeferredCallbackEnqueueTestGate;
        \\
        \\extern "C" void silexGeneratedArmDeferredCallbackEnqueueTestGate() {
        \\    silexDeferredCallbackEnqueueTestGate.arm();
        \\}
        \\extern "C" void silexGeneratedWaitForDeferredCallbackEnqueueTestGate() {
        \\    silexDeferredCallbackEnqueueTestGate.waitUntilEntered();
        \\}
        \\extern "C" void silexGeneratedReleaseDeferredCallbackEnqueueTestGate() {
        \\    silexDeferredCallbackEnqueueTestGate.release();
        \\}
        \\#endif
        \\
        \\struct SilexDeferredCallbackState {
        \\    std::mutex mutex;
        \\    bool cancelled = false;
        \\    virtual std::int64_t dispatch() = 0;
        \\    void cancel() {
        \\        std::scoped_lock lock(mutex);
        \\        cancelled = true;
        \\    }
        \\    virtual ~SilexDeferredCallbackState() = default;
        \\};
        \\
        \\struct SilexNativeResourceState {
        \\    void* handle;
        \\    void (*drop)(void*);
        \\    std::shared_ptr<SilexDeferredCallbackState> deferred;
        \\    std::vector<std::shared_ptr<SilexNativeResourceState>> priorAcquisitions;
        \\    SilexNativeResourceState(void* value, void (*destroy)(void*), std::shared_ptr<SilexDeferredCallbackState> callback, std::vector<std::shared_ptr<SilexNativeResourceState>> prior)
        \\        : handle(value), drop(destroy), deferred(std::move(callback)), priorAcquisitions(std::move(prior)) {}
        \\    ~SilexNativeResourceState() {
        \\        if (handle != nullptr) {
        \\            if (deferred) deferred->cancel();
        \\            drop(handle);
        \\        }
        \\        deferred.reset();
        \\    }
        \\    void cancelDeferred() { if (deferred) deferred->cancel(); }
        \\    std::int64_t dispatchDeferred() {
        \\        if (deferred) return deferred->dispatch();
        \\        return -1;
        \\    }
        \\    void* release() { return std::exchange(handle, nullptr); }
        \\};
        \\
        \\inline thread_local std::vector<std::weak_ptr<SilexNativeResourceState>> silexNativeAcquisitions;
        \\
        \\std::shared_ptr<SilexNativeResourceState> silexAdoptNativeResource(void* handle, void (*drop)(void*), std::shared_ptr<SilexDeferredCallbackState> deferred = {}) {
        \\    std::vector<std::shared_ptr<SilexNativeResourceState>> prior;
        \\    auto output = silexNativeAcquisitions.begin();
        \\    for (auto current = silexNativeAcquisitions.begin(); current != silexNativeAcquisitions.end(); ++current) {
        \\        if (auto acquisition = current->lock()) {
        \\            if (!acquisition->deferred) prior.push_back(acquisition);
        \\            *output++ = *current;
        \\        }
        \\    }
        \\    silexNativeAcquisitions.erase(output, silexNativeAcquisitions.end());
        \\    auto state = std::make_shared<SilexNativeResourceState>(handle, drop, std::move(deferred), std::move(prior));
        \\    silexNativeAcquisitions.push_back(state);
        \\    return state;
        \\}
        \\
        \\template <typename T> struct SilexNativeTransfer {
        \\    T* handle;
        \\    std::shared_ptr<SilexNativeResourceState> state;
        \\    operator T*() const { return handle; }
        \\};
        \\
        \\template <typename Resource>
        \\std::int64_t silexDispatchCallbacks(const Resource& resource) {
        \\    const auto count = resource.silexNativeState->dispatchDeferred();
        \\    if (count < 0) throw std::runtime_error("native resource has no deferred callback state");
        \\    return count;
        \\}
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
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\    SilexCapturedValuesBase() { silexLiveCapturedValueStates.fetch_add(1, std::memory_order_relaxed); }
        \\#endif
        \\    virtual void trace(const SilexTraceVisitor& visit) const = 0;
        \\    virtual void clear() = 0;
        \\    virtual std::unique_ptr<SilexCapturedValuesBase> clone() const = 0;
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\    virtual ~SilexCapturedValuesBase() { silexLiveCapturedValueStates.fetch_sub(1, std::memory_order_relaxed); }
        \\#else
        \\    virtual ~SilexCapturedValuesBase() = default;
        \\#endif
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
        \\template <typename Signature>
        \\struct SilexDeferredCallbackStateFor;
        \\
        \\template <typename... Arguments>
        \\struct SilexDeferredCallbackEvent {
        \\    explicit SilexDeferredCallbackEvent(Arguments... values)
        \\        : arguments(std::forward<Arguments>(values)...) {
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        silexLiveDeferredCallbackEvents.fetch_add(1, std::memory_order_relaxed);
        \\        silexAcceptedDeferredCallbackEvents.fetch_add(1, std::memory_order_relaxed);
        \\#endif
        \\    }
        \\    SilexDeferredCallbackEvent(const SilexDeferredCallbackEvent&) = delete;
        \\    SilexDeferredCallbackEvent& operator=(const SilexDeferredCallbackEvent&) = delete;
        \\    SilexDeferredCallbackEvent(SilexDeferredCallbackEvent&& other) noexcept
        \\        : arguments(std::move(other.arguments))
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        , dispatched(other.dispatched), counted(std::exchange(other.counted, false))
        \\#endif
        \\    {}
        \\    SilexDeferredCallbackEvent& operator=(SilexDeferredCallbackEvent&& other) noexcept {
        \\        if (this == &other) return *this;
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        retire();
        \\#endif
        \\        arguments = std::move(other.arguments);
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        dispatched = other.dispatched;
        \\        counted = std::exchange(other.counted, false);
        \\#endif
        \\        return *this;
        \\    }
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\    ~SilexDeferredCallbackEvent() { retire(); }
        \\    void markDispatched() {
        \\        dispatched = true;
        \\        silexDispatchedDeferredCallbackEvents.fetch_add(1, std::memory_order_relaxed);
        \\    }
        \\    void retire() {
        \\        if (!counted) return;
        \\        if (!dispatched) silexDestroyedDeferredCallbackEvents.fetch_add(1, std::memory_order_relaxed);
        \\        silexLiveDeferredCallbackEvents.fetch_sub(1, std::memory_order_relaxed);
        \\        counted = false;
        \\    }
        \\#else
        \\    ~SilexDeferredCallbackEvent() = default;
        \\#endif
        \\    std::tuple<Arguments...> arguments;
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\    bool dispatched = false;
        \\    bool counted = true;
        \\#endif
        \\};
        \\
        \\template <typename... Arguments>
        \\struct SilexDeferredCallbackStateFor<void(Arguments...)> final : SilexDeferredCallbackState {
        \\    explicit SilexDeferredCallbackStateFor(SilexFunction<void(Arguments...)> value)
        \\        : callback(std::move(value)) {
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        silexLiveDeferredCallbackContexts.fetch_add(1, std::memory_order_relaxed);
        \\#endif
        \\    }
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\    ~SilexDeferredCallbackStateFor() override {
        \\        silexLiveDeferredCallbackContexts.fetch_sub(1, std::memory_order_relaxed);
        \\    }
        \\#else
        \\    ~SilexDeferredCallbackStateFor() override = default;
        \\#endif
        \\    void enqueue(Arguments... arguments) {
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\        silexDeferredCallbackEnqueueTestGate.engage();
        \\#endif
        \\        std::scoped_lock lock(mutex);
        \\        if (cancelled) {
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\            silexCancelledDeferredCallbackEnqueues.fetch_add(1, std::memory_order_relaxed);
        \\#endif
        \\            return;
        \\        }
        \\        pending.emplace_back(std::forward<Arguments>(arguments)...);
        \\    }
        \\    std::int64_t dispatch() override {
        \\        std::vector<SilexDeferredCallbackEvent<Arguments...>> ready;
        \\        {
        \\            std::scoped_lock lock(mutex);
        \\            ready.swap(pending);
        \\        }
        \\        for (auto& event : ready) {
        \\#if defined(SILEX_DEFERRED_CALLBACK_TEST_INSTRUMENTATION)
        \\            event.markDispatched();
        \\#endif
        \\            std::apply(callback, event.arguments);
        \\        }
        \\        return static_cast<std::int64_t>(ready.size());
        \\    }
        \\    SilexFunction<void(Arguments...)> callback;
        \\    std::vector<SilexDeferredCallbackEvent<Arguments...>> pending;
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
        \\class SilexView {
        \\public:
        \\    using value_type = std::remove_const_t<T>;
        \\    SilexView() = default;
        \\    SilexView(T* values, std::size_t count) : values_(values), count_(count) {}
        \\    std::size_t size() const { return count_; }
        \\    bool empty() const { return count_ == 0; }
        \\    T& operator[](std::size_t index) const { return values_[index]; }
        \\    T* begin() const { return values_; }
        \\    T* end() const { return values_ + count_; }
        \\    T* data() const { return values_; }
        \\private:
        \\    T* values_ { nullptr };
        \\    std::size_t count_ { 0 };
        \\};
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
        \\    SilexList(const SilexList&) requires std::copy_constructible<T> = default;
        \\    SilexList(const SilexList&) requires (!std::copy_constructible<T>) = delete;
        \\    SilexList& operator=(const SilexList&) requires std::copyable<T> = default;
        \\    SilexList& operator=(const SilexList&) requires (!std::copyable<T>) = delete;
        \\    SilexList(SilexList&&) noexcept = default;
        \\    SilexList& operator=(SilexList&&) noexcept = default;
        \\
        \\    std::size_t size() const { return values_.size(); }
        \\    bool empty() const { return values_.empty(); }
        \\    const T* data() const { return values_.data(); }
        \\    T* data() { return values_.data(); }
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
        \\template <>
        \\class SilexList<bool> {
        \\public:
        \\    using value_type = bool;
        \\    using iterator = bool*;
        \\    using const_iterator = const bool*;
        \\
        \\    SilexList() = default;
        \\    SilexList(std::initializer_list<bool> values) {
        \\        reserve(values.size());
        \\        for (bool value : values) push_back(value);
        \\    }
        \\    SilexList(const SilexList& other) { copyFrom(other); }
        \\    SilexList& operator=(const SilexList& other) {
        \\        if (this != &other) copyFrom(other);
        \\        return *this;
        \\    }
        \\    SilexList(SilexList&& other) noexcept
        \\        : values_(std::move(other.values_)), size_(other.size_), capacity_(other.capacity_) {
        \\        other.size_ = 0;
        \\        other.capacity_ = 0;
        \\    }
        \\    SilexList& operator=(SilexList&& other) noexcept {
        \\        if (this == &other) return *this;
        \\        values_ = std::move(other.values_);
        \\        size_ = other.size_;
        \\        capacity_ = other.capacity_;
        \\        other.size_ = 0;
        \\        other.capacity_ = 0;
        \\        return *this;
        \\    }
        \\
        \\    std::size_t size() const { return size_; }
        \\    bool empty() const { return size_ == 0; }
        \\    const bool* data() const { return values_.get(); }
        \\    bool* data() { return values_.get(); }
        \\    bool operator==(const SilexList& other) const {
        \\        if (size_ != other.size_) return false;
        \\        for (std::size_t index = 0; index < size_; ++index) {
        \\            if (values_[index] != other.values_[index]) return false;
        \\        }
        \\        return true;
        \\    }
        \\    bool operator!=(const SilexList& other) const { return !(*this == other); }
        \\    const_iterator begin() const { return values_.get(); }
        \\    const_iterator end() const { return size_ == 0 ? values_.get() : values_.get() + size_; }
        \\    iterator begin() { return values_.get(); }
        \\    iterator end() { return size_ == 0 ? values_.get() : values_.get() + size_; }
        \\    const bool& operator[](std::size_t index) const { return values_[index]; }
        \\    bool& operator[](std::size_t index) { return values_[index]; }
        \\    void reserve(std::size_t count) {
        \\        if (count <= capacity_) return;
        \\        auto replacement = std::make_unique<bool[]>(count);
        \\        for (std::size_t index = 0; index < size_; ++index) replacement[index] = values_[index];
        \\        values_ = std::move(replacement);
        \\        capacity_ = count;
        \\    }
        \\    void push_back(bool value) {
        \\        if (size_ == capacity_) reserve(capacity_ == 0 ? 4 : capacity_ * 2);
        \\        values_[size_++] = value;
        \\    }
        \\    iterator insert(iterator position, bool value) {
        \\        const std::size_t offset = position == nullptr ? 0 : static_cast<std::size_t>(position - begin());
        \\        if (size_ == capacity_) reserve(capacity_ == 0 ? 4 : capacity_ * 2);
        \\        for (std::size_t index = size_; index > offset; --index) values_[index] = values_[index - 1];
        \\        values_[offset] = value;
        \\        ++size_;
        \\        return begin() + offset;
        \\    }
        \\    template <typename Iterator>
        \\    iterator insert(iterator position, Iterator first, Iterator last) {
        \\        const std::size_t offset = position == nullptr ? 0 : static_cast<std::size_t>(position - begin());
        \\        std::size_t inserted = 0;
        \\        while (first != last) {
        \\            insert(begin() + offset + inserted, static_cast<bool>(*first));
        \\            ++first;
        \\            ++inserted;
        \\        }
        \\        return begin() + offset;
        \\    }
        \\    iterator erase(iterator position) {
        \\        const std::size_t offset = static_cast<std::size_t>(position - begin());
        \\        for (std::size_t index = offset + 1; index < size_; ++index) values_[index - 1] = values_[index];
        \\        --size_;
        \\        return offset == size_ ? end() : begin() + offset;
        \\    }
        \\    void pop_back() { --size_; }
        \\    void clear() { size_ = 0; }
        \\    void silexTrace(const SilexTraceVisitor&) const {}
        \\    void silexClear() { clear(); }
        \\
        \\private:
        \\    void copyFrom(const SilexList& other) {
        \\        if (other.size_ > capacity_) {
        \\            values_ = std::make_unique<bool[]>(other.size_);
        \\            capacity_ = other.size_;
        \\        }
        \\        size_ = other.size_;
        \\        for (std::size_t index = 0; index < size_; ++index) values_[index] = other.values_[index];
        \\    }
        \\    std::unique_ptr<bool[]> values_;
        \\    std::size_t size_ { 0 };
        \\    std::size_t capacity_ { 0 };
        \\};
        \\
        \\template <typename T, typename... Values>
        \\SilexList<T> silexMakeList(Values&&... values) {
        \\    SilexList<T> result;
        \\    result.reserve(sizeof...(Values));
        \\    (result.push_back(std::forward<Values>(values)), ...);
        \\    return result;
        \\}
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
        \\struct SilexEnumValue {
        \\    virtual std::unique_ptr<SilexEnumValue> clone() const = 0;
        \\    virtual void trace(const SilexTraceVisitor& visit) const = 0;
        \\    virtual void clear() = 0;
        \\    virtual ~SilexEnumValue() = default;
        \\};
        \\
        \\template <typename T>
        \\struct SilexTypedEnumValue final : SilexEnumValue {
        \\    T value;
        \\    explicit SilexTypedEnumValue(T input) : value(std::move(input)) {}
        \\    std::unique_ptr<SilexEnumValue> clone() const override {
        \\        if constexpr (std::copy_constructible<T>) return std::make_unique<SilexTypedEnumValue<T>>(value);
        \\        std::abort();
        \\    }
        \\    void trace(const SilexTraceVisitor& visit) const override { silexTraceValue(value, visit); }
        \\    void clear() override { silexClearValue(value); }
        \\};
        \\
        \\struct SilexEnumStorage {
        \\    std::size_t variant;
        \\    std::vector<std::unique_ptr<SilexEnumValue>> values;
        \\    template <typename... Values>
        \\    explicit SilexEnumStorage(std::size_t inputVariant, Values&&... inputs) : variant(inputVariant) {
        \\        (values.push_back(std::make_unique<SilexTypedEnumValue<std::decay_t<Values>>>(std::forward<Values>(inputs))), ...);
        \\    }
        \\    SilexEnumStorage(const SilexEnumStorage& other) : variant(other.variant) {
        \\        values.reserve(other.values.size());
        \\        for (const auto& value : other.values) values.push_back(value->clone());
        \\    }
        \\    SilexEnumStorage(SilexEnumStorage&&) noexcept = default;
        \\    SilexEnumStorage& operator=(const SilexEnumStorage& other) {
        \\        if (this == &other) return *this;
        \\        SilexEnumStorage copy(other);
        \\        *this = std::move(copy);
        \\        return *this;
        \\    }
        \\    SilexEnumStorage& operator=(SilexEnumStorage&&) noexcept = default;
        \\    template <typename T> const T& get(std::size_t index) const {
        \\        return static_cast<const SilexTypedEnumValue<T>&>(*values[index]).value;
        \\    }
        \\    template <typename T> T& get(std::size_t index) {
        \\        return static_cast<SilexTypedEnumValue<T>&>(*values[index]).value;
        \\    }
        \\    void silexTrace(const SilexTraceVisitor& visit) const {
        \\        for (const auto& value : values) value->trace(visit);
        \\    }
        \\    void silexClear() {
        \\        for (auto& value : values) value->clear();
        \\        values.clear();
        \\    }
        \\};
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
        \\template <typename Collection>
        \\SilexView<const typename Collection::value_type> silexCollectionReadView(
        \\    const Collection& values,
        \\    std::int64_t start,
        \\    std::int64_t end
        \\) {
        \\    const std::size_t startOffset = silexCollectionSliceBound(values.size(), start);
        \\    const std::size_t endOffset = silexCollectionSliceBound(values.size(), end);
        \\    if (startOffset >= endOffset) return {};
        \\    return { values.data() + startOffset, endOffset - startOffset };
        \\}
        \\
        \\template <typename Collection>
        \\SilexView<typename Collection::value_type> silexCollectionMutableView(
        \\    Collection& values,
        \\    std::int64_t start,
        \\    std::int64_t end
        \\) {
        \\    const std::size_t startOffset = silexCollectionSliceBound(values.size(), start);
        \\    const std::size_t endOffset = silexCollectionSliceBound(values.size(), end);
        \\    if (startOffset >= endOffset) return {};
        \\    return { values.data() + startOffset, endOffset - startOffset };
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
        \\template <typename Collection, typename Value>
        \\typename Collection::value_type silexCollectionReplace(Collection& values, std::int64_t index, Value value, SilexSourceLocation location) {
        \\    using T = typename Collection::value_type;
        \\    const auto offset = silexCollectionOffset(values.size(), index, false, location);
        \\    return std::exchange(values[offset], T(std::move(value)));
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
    for (program.protocols) |protocol| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    for (program.enums) |enum_value| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, enum_value.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    for (program.structures) |structure| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    if (program.protocols.len > 0 or program.enums.len > 0 or program.structures.len > 0) try output.append(allocator, '\n');
    try generateProtocolTypes(allocator, &output, program);
    for (program.enums) |enum_value| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, enum_value.generated_name);
        try output.appendSlice(allocator, " : SilexEnumStorage {\n    using SilexEnumStorage::SilexEnumStorage;\n");
        if (!enum_value.is_copyable) {
            try output.appendSlice(allocator, "    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "(const ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "& operator=(const ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "(");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "& operator=(");
            try output.appendSlice(allocator, enum_value.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n");
        }
        if (enum_value.raw_type) |raw_type| {
            try output.appendSlice(allocator, "    ");
            try appendCppType(allocator, &output, raw_type);
            try output.appendSlice(allocator, " rawValue() const {\n        switch (variant) {\n");
            for (enum_value.variants, 0..) |variant, variant_index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "            case {d}: return ", .{variant_index}));
                try generateExpression(allocator, &output, variant.raw_value.?);
                try output.appendSlice(allocator, ";\n");
            }
            try output.appendSlice(allocator, "        }\n        std::abort();\n    }\n");
        }
        try output.appendSlice(allocator, "};\n\n");
    }
    const structure_order = try structureDefinitionOrder(allocator, program.structures);
    for (structure_order) |structure_index| {
        const structure = program.structures[structure_index];
        const is_native_return = structureIsNativeReturn(program, structure);
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
        for (structure.static_fields) |field| {
            try output.appendSlice(allocator, "    inline static ");
            try appendCppType(allocator, &output, field.type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, &output, field.initializer.?);
            try output.appendSlice(allocator, ";\n");
        }
        if (structure.static_fields.len != 0 and structure.fields.len != 0) try output.append(allocator, '\n');
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
        if (structure.is_native_resource) {
            try output.appendSlice(allocator, "    std::shared_ptr<SilexNativeResourceState> silexNativeState;\n");
        }
        if (is_native_return and !structure.is_native_resource) {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag");
            for (structure.fields, 0..) |field, index| {
                try output.appendSlice(allocator, ", ");
                try appendCppType(allocator, &output, field.type);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexNativeField{d}", .{index}));
            }
            try output.appendSlice(allocator, ")");
            if (structure.fields.len == 0) {
                try output.appendSlice(allocator, " {}\n");
            } else {
                try output.appendSlice(allocator, " : ");
                for (structure.fields, 0..) |field, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, field.generated_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "(silexNativeField{d})", .{index}));
                }
                try output.appendSlice(allocator, " {}\n");
            }
        }
        if (structure.is_native_resource) {
            try output.appendSlice(allocator, "\n    explicit ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag, ::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "* handle) : silexNativeState(silexAdoptNativeResource(handle, +[](void* value) { ");
            try output.appendSlice(allocator, structure.native_drop_symbol.?);
            try output.appendSlice(allocator, "(static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(value)); })) {}\n\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag, ::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "* handle, std::shared_ptr<SilexDeferredCallbackState> deferred) : silexNativeState(silexAdoptNativeResource(handle, +[](void* value) { ");
            try output.appendSlice(allocator, structure.native_drop_symbol.?);
            try output.appendSlice(allocator, "(static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(value)); }, std::move(deferred))) {}\n    auto* silexBorrowNativeHandle() const { return static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(silexNativeState->handle); }\n    auto silexReleaseNativeHandle() { if (silexNativeState.use_count() != 1) throw std::runtime_error(\"native resource still has later acquisitions\"); silexOwnsResource = false; auto state = std::move(silexNativeState); auto* handle = static_cast<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, "*>(state->release()); return SilexNativeTransfer<::");
            try output.appendSlice(allocator, try NativeInterface.transportName(allocator, structure.native_module_name.?, structure.source_name));
            try output.appendSlice(allocator, ">{handle, std::move(state)}; }\n    void silexCancelDeferred() { silexNativeState->cancelDeferred(); }\n");
        }
        if (structure.is_owner) try output.appendSlice(allocator, "    bool silexOwnsResource = true;\n");
        if ((structure.is_class and structure.constructors.len == 0 and structure.implicit_constructor_available) or
            (structure.is_noncopyable and !structure.is_native_resource and structure.constructors.len == 0) or
            (is_native_return and !structure.is_class and structure.constructors.len == 0))
        {
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
        if (structure.is_noncopyable and structure.drop == null and !structure.is_class) {
            try output.appendSlice(allocator, "\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(const ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "& operator=(const ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&) = delete;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "(");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "& operator=(");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "&&) noexcept = default;\n");
        }
        if (structure.drop != null) {
            if (structure.is_class) {
                try output.appendSlice(allocator, "\n    void silexDrop() override;\n");
            } else {
                try output.appendSlice(allocator, "\n    ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "(const ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "&) = delete;\n    ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "& operator=(const ");
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "&) = delete;\n    ");
                if (structure.is_owner) {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept;\n    ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept;\n    void silexDropResource();\n    ~");
                } else {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&&) = delete;\n    ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&&) = delete;\n    ~");
                }
                try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "();\n");
            }
        }
        if (structure.fields.len > 0 and (structure.constructors.len > 0 or structure.methods.len > 0)) try output.append(allocator, '\n');
        for (structure.methods) |method| {
            try output.appendSlice(allocator, "    ");
            if (method.is_static) {
                try output.appendSlice(allocator, "static ");
            } else if (structure.is_class and !method.is_extension and method.visibility != .private_access) try output.appendSlice(allocator, "virtual ");
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
    try generateProtocolMethodDefinitions(allocator, &output, program);
    try generateProtocolWitnesses(allocator, &output, program);
    try output.appendSlice(allocator, "void silexResetStaticFields() {\n");
    for (program.structures) |structure| {
        for (structure.static_fields) |field| {
            try output.appendSlice(allocator, "    ");
            try output.appendSlice(allocator, structure.generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, &output, field.reset_value.?);
            try output.appendSlice(allocator, ";\n");
        }
    }
    try output.appendSlice(allocator, "}\n\n");
    if (program.structures.len > 0) {
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
            try generateStructureEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
            try generateStructureOperatorEqualitySignature(allocator, &output, structure, false);
            try output.appendSlice(allocator, ";\n");
        }
        try output.append(allocator, '\n');
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
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
        for (program.structures) |structure| {
            if (structure.is_class or !structure.equality_comparable) continue;
            try generateStructureOperatorEqualitySignature(allocator, &output, structure, true);
            try output.appendSlice(allocator, " {\n    return ");
            try generateStructureEqualityName(allocator, &output, structure.generated_name);
            try output.appendSlice(allocator, "(left, right);\n}\n\n");
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
            if (structure.is_class) {
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
            } else {
                if (structure.is_owner) {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept : ");
                    for (structure.fields, 0..) |field, field_index| {
                        if (field_index != 0) try output.appendSlice(allocator, ", ");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, "(std::move(other.");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, "))");
                    }
                    if (structure.fields.len != 0) try output.appendSlice(allocator, ", ");
                    if (structure.is_native_resource) try output.appendSlice(allocator, "silexNativeState(std::move(other.silexNativeState)), ");
                    try output.appendSlice(allocator, "silexOwnsResource(std::exchange(other.silexOwnsResource, false)) {}\n\n");

                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "& ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::operator=(");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "&& other) noexcept {\n    if (this == &other) return *this;\n    if (silexOwnsResource) {\n        silexDropResource();\n        silexOwnsResource = false;\n    }\n");
                    for (structure.fields) |field| {
                        try output.appendSlice(allocator, "    ");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, " = std::move(other.");
                        try output.appendSlice(allocator, field.generated_name);
                        try output.appendSlice(allocator, ");\n");
                    }
                    if (structure.is_native_resource) try output.appendSlice(allocator, "    silexNativeState = std::move(other.silexNativeState);\n");
                    try output.appendSlice(allocator, "    silexOwnsResource = std::exchange(other.silexOwnsResource, false);\n    return *this;\n}\n\nvoid ");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::silexDropResource() {\n");
                    if (structure.is_native_resource) {
                        try output.appendSlice(allocator, "    silexNativeState.reset();\n");
                    } else try generateStatements(allocator, &output, drop.statements, 1, false);
                    try output.appendSlice(allocator, "}\n\n");

                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::~");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "() {\n    if (silexOwnsResource) silexDropResource();\n}\n\n");
                } else {
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "::~");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.appendSlice(allocator, "() {\n");
                    try generateStatements(allocator, &output, drop.statements, 1, false);
                    try output.appendSlice(allocator, "}\n\n");
                }
            }
        }
        for (structure.methods) |method| {
            try generateMethodSignature(allocator, &output, method, structure.generated_name, true);
            try output.appendSlice(allocator, " {\n");
            try generateCapturedParameterBindings(allocator, &output, method.parameters, 1);
            try generateStatements(allocator, &output, method.statements, 1, false);
            if (method.return_type != .void) try output.appendSlice(allocator, "    std::abort();\n");
            try output.appendSlice(allocator, "}\n\n");
        }
    }
    for (program.functions) |function| {
        if (function.is_native) continue;
        try generateFunctionSignature(allocator, &output, function, true);
        try output.appendSlice(allocator, " {\n");
        try generateCapturedParameterBindings(allocator, &output, function.parameters, 1);
        try generateStatements(allocator, &output, function.statements, 1, function.is_main);
        if (function.is_main and function.return_type == .void) try output.appendSlice(allocator, "    return 0;\n");
        if (function.return_type != .void) try output.appendSlice(allocator, "    std::abort();\n");
        try output.appendSlice(allocator, "}\n\n");
    }
    const main_function = for (program.functions) |function| {
        if (function.is_main) break function;
    } else unreachable;
    const main_returns_result = main_function.return_type != .void;
    try output.appendSlice(allocator,
        \\// -----------------------------------------------------------------------------
        \\
        \\} // namespace SilexGenerated
        \\
        \\namespace {
        \\int silexRuntimeArgumentCountValue = 0;
        \\char** silexRuntimeArgumentValues = nullptr;
        \\}
        \\
        \\extern "C" std::int64_t silexRuntimeArgumentCount() {
        \\    return silexRuntimeArgumentCountValue;
        \\}
        \\
        \\extern "C" const char* silexRuntimeArgumentValue(
        \\    std::int64_t index,
        \\    std::int64_t* length
        \\) {
        \\    if (index < 0 || index >= silexRuntimeArgumentCountValue) {
        \\        *length = 0;
        \\        return nullptr;
        \\    }
        \\    const char* value = silexRuntimeArgumentValues[index];
        \\    std::int64_t count = 0;
        \\    while (value[count] != '\0') ++count;
        \\    *length = count;
        \\    return value;
        \\}
        \\
        \\int main(int argumentCount, char** argumentValues) {
        \\    silexRuntimeArgumentCountValue = argumentCount;
        \\    silexRuntimeArgumentValues = argumentValues;
    );
    try output.appendSlice(allocator, if (main_returns_result)
        "    const auto result = SilexGenerated::silexMain();\n"
    else
        "    const int result = SilexGenerated::silexMain();\n");
    try output.appendSlice(allocator,
        \\    SilexGenerated::silexResetStaticFields();
        \\    if (SilexGenerated::silexLiveObjects != 0) {
        \\        std::cerr << "silex: runtime error: unreachable class graph was not collected\n";
        \\        return 1;
        \\    }
    );
    if (main_returns_result) {
        try output.appendSlice(allocator,
            \\    if (result.variant == 1) {
            \\        std::cerr << "error: " << result.get<std::string>(0) << '\n';
            \\        return 1;
            \\    }
            \\    return 0;
        );
    } else {
        try output.appendSlice(allocator, "    return result;\n");
    }
    try output.appendSlice(allocator, "}\n");
    return output.toOwnedSlice(allocator);
}

fn generateProtocolTypes(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.protocols) |protocol| {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator,
            \\ {
            \\    struct Witness {
        );
        for (protocol.requirements) |requirement| {
            try output.appendSlice(allocator, "        ");
            try appendCppType(allocator, output, requirement.return_type);
            try output.appendSlice(allocator, " (*");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.appendSlice(allocator, ")(void*");
            for (requirement.parameter_types, requirement.parameter_modes) |parameter_type, mode| {
                try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter_type, mode);
            }
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator,
            \\    };
            \\    struct StorageBase {
            \\        virtual std::unique_ptr<StorageBase> clone() const = 0;
            \\        virtual void* data() = 0;
            \\        virtual void trace(const SilexTraceVisitor& visit) const = 0;
            \\        virtual void clear() = 0;
            \\        virtual ~StorageBase() = default;
            \\    };
            \\    template <typename T>
            \\    struct Storage final : StorageBase {
            \\        explicit Storage(T input) : value(std::move(input)) {}
            \\        std::unique_ptr<StorageBase> clone() const override { return std::make_unique<Storage<T>>(value); }
            \\        void* data() override { return &value; }
            \\        void trace(const SilexTraceVisitor& visit) const override { silexTraceValue(value, visit); }
            \\        void clear() override { silexClearValue(value); }
            \\        T value;
            \\    };
        );
        try output.appendSlice(allocator, "    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "() = default;\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "(const ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& other) : storage_(other.storage_ ? other.storage_->clone() : nullptr), witness_(other.witness_) {}\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "(");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "&&) noexcept = default;\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& operator=(const ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& other) { if (this != &other) { ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, " copy(other); *this = std::move(copy); } return *this; }\n    ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "& operator=(");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, "&&) noexcept = default;\n");
        try output.appendSlice(allocator, "    template <typename T>\n    static ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(allocator, " make(T value, const Witness* witness) {\n        ");
        try output.appendSlice(allocator, protocol.generated_name);
        try output.appendSlice(
            allocator,
            " result;\n        result.storage_ = std::make_unique<Storage<T>>(std::move(value));\n        result.witness_ = witness;\n        return result;\n    }\n",
        );
        for (protocol.requirements) |requirement| {
            try output.appendSlice(allocator, "    ");
            try appendCppType(allocator, output, requirement.return_type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, requirement.generated_name);
            try output.append(allocator, '(');
            for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ");\n");
        }
        try output.appendSlice(allocator,
            \\    void silexTrace(const SilexTraceVisitor& visit) const { if (storage_) storage_->trace(visit); }
            \\    void silexClear() { if (storage_) storage_->clear(); storage_.reset(); witness_ = nullptr; }
            \\private:
            \\    std::unique_ptr<StorageBase> storage_;
            \\    const Witness* witness_ = nullptr;
            \\};
            \\
        );
    }
    for (program.structures) |structure| {
        for (structure.protocol_conformances) |conformance| {
            try output.appendSlice(allocator, "extern const ");
            try output.appendSlice(allocator, conformance.protocol_generated_name);
            try output.appendSlice(allocator, "::Witness ");
            try output.appendSlice(allocator, conformance.witness_name);
            try output.appendSlice(allocator, ";\n");
        }
    }
    if (program.protocols.len != 0) try output.append(allocator, '\n');
}

fn generateProtocolMethodDefinitions(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.protocols) |protocol| {
        for (protocol.requirements) |requirement| {
            try appendCppType(allocator, output, requirement.return_type);
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, protocol.generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.append(allocator, '(');
            for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter_type, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return witness_->");
            try output.appendSlice(allocator, requirement.generated_name);
            try output.appendSlice(allocator, "(storage_->data()");
            for (requirement.parameter_types, 0..) |_, index| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ", silexProtocolArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); }\n");
        }
        try output.append(allocator, '\n');
    }
}

fn generateProtocolWitnesses(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
) !void {
    for (program.structures) |structure| {
        for (structure.protocol_conformances) |conformance| {
            const protocol = program.protocols[conformance.protocol_index];
            for (protocol.requirements, conformance.method_generated_names, 0..) |requirement, method_name, requirement_index| {
                try appendCppType(allocator, output, requirement.return_type);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, conformance.witness_name);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "Method{d}(void* raw", .{requirement_index}));
                for (requirement.parameter_types, requirement.parameter_modes, 0..) |parameter_type, mode, index| {
                    try output.appendSlice(allocator, ", ");
                    try appendCppParameterType(allocator, output, parameter_type, mode);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " argument{d}", .{index}));
                }
                try output.appendSlice(allocator, ") { auto& value = *static_cast<");
                if (structure.is_class) {
                    try output.appendSlice(allocator, "SilexRef<");
                    try output.appendSlice(allocator, structure.generated_name);
                    try output.append(allocator, '>');
                } else try output.appendSlice(allocator, structure.generated_name);
                try output.appendSlice(allocator, "*>(raw); return value");
                try output.appendSlice(allocator, if (structure.is_class) "->" else ".");
                try output.appendSlice(allocator, method_name);
                try output.append(allocator, '(');
                for (requirement.parameter_types, 0..) |_, index| {
                    if (index != 0) try output.appendSlice(allocator, ", ");
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "argument{d}", .{index}));
                }
                try output.appendSlice(allocator, "); }\n");
            }
            try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, conformance.protocol_generated_name);
            try output.appendSlice(allocator, "::Witness ");
            try output.appendSlice(allocator, conformance.witness_name);
            try output.appendSlice(allocator, "{");
            for (protocol.requirements, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, "&");
                try output.appendSlice(allocator, conformance.witness_name);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "Method{d}", .{index}));
            }
            try output.appendSlice(allocator, "};\n\n");
        }
    }
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
        try appendCppParameterType(allocator, output, parameter.type, parameter.mode);
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
    const mutable_return = method.return_type == .reference and method.return_type.reference.mutable;
    if (!method.is_static and !method.is_mutating and !method.requires_mutable_codegen and !mutable_return) {
        try output.appendSlice(allocator, " const");
    }
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
        try appendCppParameterType(allocator, output, parameter.type, parameter.mode);
        if (include_names) {
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, parameter.generated_name);
            if (parameter.capture_box.*) try output.appendSlice(allocator, "Input");
        }
    }
    try output.append(allocator, ')');
}

fn generateFunctionSignature(allocator: Allocator, output: *std.ArrayList(u8), function: Semantic.Function, include_names: bool) !void {
    if (function.is_main and function.return_type == .void) {
        try output.appendSlice(allocator, "int");
    } else {
        try appendCppType(allocator, output, function.return_type);
    }
    try output.append(allocator, ' ');
    try output.appendSlice(allocator, if (function.is_main) "silexMain" else function.generated_name);
    try output.append(allocator, '(');
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendCppParameterType(allocator, output, parameter.type, parameter.mode);
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
    program: Semantic.Program,
    function: Semantic.Function,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "extern \"C\" ");
    const result = nativeResultShape(program, function.return_type);
    const structure = nativeReturnStructure(program, function);
    const returned = nativeReturnValueType(function.return_type);
    const returned_view = nativeReturnedView(returned);
    const returns_bytes = isNativeByteBufferReturnType(returned);
    const optional = function.return_type == .optional;
    const resource = if (structure) |value| value.is_native_resource else false;
    if (result != null or returned_view != null) {
        try output.appendSlice(allocator, "void");
    } else if (optional) {
        try output.appendSlice(allocator, "bool");
    } else if (resource) {
        if (returned == .reference and !returned.reference.mutable) try output.appendSlice(allocator, "const ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, function.native_module_name.?, structure.?.source_name));
        try output.append(allocator, '*');
    } else if (returned == .str or returns_bytes or structure != null) {
        try output.appendSlice(allocator, "void");
    } else {
        try appendCppType(allocator, output, returned);
    }
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
        } else if (parameter.type == .view) {
            if (parameter.mode == .borrow) try output.appendSlice(allocator, "const ");
            try appendCppType(allocator, output, parameter.type.view.*);
            try output.append(allocator, '*');
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Values, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Count");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else if (isNativeByteViewType(parameter.type)) {
            try output.appendSlice(allocator, "const std::uint8_t*");
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Bytes, std::int64_t ");
                try output.appendSlice(allocator, parameter.generated_name);
                try output.appendSlice(allocator, "Length");
            } else {
                try output.appendSlice(allocator, ", std::int64_t");
            }
        } else if (isNativeCallbackType(parameter.type)) {
            try appendCppNativeCallbackParameter(allocator, output, parameter.type.function, if (include_names) parameter.generated_name else null);
        } else if (nativeStructureForType(program, parameter.type)) |parameter_structure| {
            if (!parameter_structure.is_native_resource or parameter.mode == .borrow) try output.appendSlice(allocator, "const ");
            try output.appendSlice(allocator, try NativeInterface.inputTransportName(
                allocator,
                function.native_module_name.?,
                parameter_structure.source_name,
                structureHasString(parameter_structure) and !parameter_structure.is_native_resource,
            ));
            try output.append(allocator, '*');
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
            }
        } else {
            try appendCppType(allocator, output, parameter.type);
            if (include_names) {
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, parameter.generated_name);
            }
        }
    }
    if (result != null) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.resultTransportName(
            allocator,
            function.native_module_name.?,
            function.native_function_name.?,
        ));
        try output.append(allocator, '*');
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (returned_view) |view| {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        if (!returned.reference.mutable) try output.appendSlice(allocator, "const ");
        try appendCppType(allocator, output, view.*);
        try output.appendSlice(allocator, "**");
        if (include_names) try output.appendSlice(allocator, " output_values");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_count");
    } else if (returned == .str) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "char**");
        if (include_names) try output.appendSlice(allocator, " output_bytes");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_length");
    } else if (returns_bytes) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "std::uint8_t**");
        if (include_names) try output.appendSlice(allocator, " output_bytes");
        try output.appendSlice(allocator, ", std::int64_t*");
        if (include_names) try output.appendSlice(allocator, " output_length");
    } else if (optional and resource) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, function.native_module_name.?, structure.?.source_name));
        try output.appendSlice(allocator, "**");
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (structure != null and !resource) {
        const returned_structure = structure.?;
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try NativeInterface.transportName(
            allocator,
            function.native_module_name.?,
            returned_structure.source_name,
        ));
        try output.appendSlice(allocator, if (returned_structure.is_native_resource) "**" else "*");
        if (include_names) try output.appendSlice(allocator, " output");
    } else if (optional) {
        if (function.parameters.len != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, returned);
        try output.append(allocator, '*');
        if (include_names) try output.appendSlice(allocator, " output");
    }
    try output.append(allocator, ')');
}

fn generateNativeTransportIfNew(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    const transport_name = if (input)
        try NativeInterface.inputTransportName(
            allocator,
            module_name,
            structure.source_name,
            structureHasString(structure),
        )
    else
        try NativeInterface.transportName(allocator, module_name, structure.source_name);
    for (emitted.items) |name| {
        if (std.mem.eql(u8, name, transport_name)) return;
    }
    try emitted.append(allocator, transport_name);
    try generateNativeTransportDefinition(allocator, output, module_name, structure, input);
    try output.append(allocator, '\n');
}

fn generateNativeTransportDefinition(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    structure: Semantic.Structure,
    input: bool,
) !void {
    if (structure.is_native_resource) {
        try output.appendSlice(allocator, "struct ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.append(allocator, ';');
        return;
    }
    try output.appendSlice(allocator, "struct ");
    if (input) {
        try output.appendSlice(allocator, try NativeInterface.inputTransportName(
            allocator,
            module_name,
            structure.source_name,
            structureHasString(structure),
        ));
    } else {
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
    }
    try output.appendSlice(allocator, " {\n");
    if (structure.fields.len == 0) {
        try output.appendSlice(allocator, "    std::uint8_t silexUnused;\n");
    } else for (structure.fields) |field| {
        try output.appendSlice(allocator, "    ");
        if (field.type == .str) {
            try output.appendSlice(allocator, if (input) "const char* " else "char* ");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, if (input) "Bytes;\n    std::int64_t " else "Bytes = nullptr;\n    std::int64_t ");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, if (input) "Length;\n" else "Length = 0;\n");
            continue;
        }
        try appendCppType(allocator, output, field.type);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, ";\n");
    }
    try output.appendSlice(allocator, "};");
}

const NativeResultShape = struct {
    success_type: Semantic.Type,
    failure_type: Semantic.Type,
};

fn nativeResultShape(program: Semantic.Program, value: Semantic.Type) ?NativeResultShape {
    const enum_type = switch (value) {
        .enumeration => |enumeration| enumeration,
        else => return null,
    };
    if (!std.mem.startsWith(u8, enum_type.source_name, "Result<")) return null;
    for (program.enums) |enumeration| {
        if (!std.mem.eql(u8, enumeration.generated_name, enum_type.generated_name)) continue;
        if (enumeration.variants.len != 2 or enumeration.variants[1].associated_types.len != 1 or
            enumeration.variants[0].associated_types.len > 1)
        {
            return null;
        }
        return .{
            .success_type = if (enumeration.variants[0].associated_types.len == 0)
                .void
            else
                enumeration.variants[0].associated_types[0],
            .failure_type = enumeration.variants[1].associated_types[0],
        };
    }
    return null;
}

fn nativeBranchValueType(value: Semantic.Type) Semantic.Type {
    return if (value == .optional) value.optional.* else value;
}

fn isNativeByteViewType(value: Semantic.Type) bool {
    return switch (value) {
        .list => |element| element.* == .uint8,
        .fixed_array => |array| array.element.* == .uint8,
        else => false,
    };
}

fn isNativeByteBufferReturnType(value: Semantic.Type) bool {
    return value == .list and value.list.* == .uint8;
}

fn isNativeCallbackType(value: Semantic.Type) bool {
    const function = switch (value) {
        .function => |function_value| function_value,
        else => return false,
    };
    if (function.owner != null) return false;
    if (function.return_type.* != .void and !isNativeCallbackScalarType(function.return_type.*)) return false;
    for (function.parameters, function.parameter_modes) |parameter, mode| {
        if (mode != .value or !isNativeCallbackScalarType(parameter)) return false;
    }
    return true;
}

fn nativeDeferredCallbackIndex(arguments: []const *Semantic.Expression) ?usize {
    for (arguments, 0..) |argument, index| {
        if (argument.type == .function and argument.type.function.deferred) return index;
    }
    return null;
}

fn isNativeCallbackScalarType(value: Semantic.Type) bool {
    return switch (value) {
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float64, .bool => true,
        else => false,
    };
}

fn appendCppNativeCallbackParameter(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
    name: ?[]const u8,
) GenerateError!void {
    try appendCppType(allocator, output, callback.return_type.*);
    try output.appendSlice(allocator, " (*");
    if (name) |parameter_name| try output.appendSlice(allocator, parameter_name);
    try output.appendSlice(allocator, ")(void*");
    for (callback.parameters) |parameter| {
        try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")");
    if (name) |parameter_name| {
        try output.appendSlice(allocator, ", void* ");
        try output.appendSlice(allocator, parameter_name);
        try output.appendSlice(allocator, "_context");
    } else {
        try output.appendSlice(allocator, ", void*");
    }
}

fn generateNativeResultTransportIfNew(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    emitted: *std.ArrayList([]const u8),
    program: Semantic.Program,
    function: Semantic.Function,
    result: NativeResultShape,
) !void {
    const name = try NativeInterface.resultTransportName(
        allocator,
        function.native_module_name.?,
        function.native_function_name.?,
    );
    for (emitted.items) |emitted_name| if (std.mem.eql(u8, emitted_name, name)) return;
    try emitted.append(allocator, name);

    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{name});
    try output.appendSlice(allocator, "enum ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_success = 0,\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_failure = 1\n};\n\nstruct ");
    try output.appendSlice(allocator, name);
    try output.appendSlice(allocator, " {\n    ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, " tag{};\n");
    try generateNativeResultBranchFields(allocator, output, program, function.native_module_name.?, "success", result.success_type);
    try generateNativeResultBranchFields(allocator, output, program, function.native_module_name.?, "failure", result.failure_type);
    try output.appendSlice(allocator, "};\n\n");
}

fn generateNativeResultBranchFields(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    program: Semantic.Program,
    module_name: []const u8,
    prefix: []const u8,
    branch_type: Semantic.Type,
) !void {
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "    bool ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Present{};\n");
    }
    const value = nativeBranchValueType(branch_type);
    if (value == .void) return;
    if (isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "    std::uint8_t* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Bytes = nullptr;\n    std::int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Length = 0;\n");
    } else if (value == .str) {
        try output.appendSlice(allocator, "    char* ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Bytes = nullptr;\n    std::int64_t ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Length = 0;\n");
    } else if (nativeStructureForType(program, value)) |structure| {
        try output.appendSlice(allocator, "    ");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.appendSlice(allocator, if (structure.is_native_resource) "* " else " ");
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, if (structure.is_native_resource) "Value = nullptr;\n" else "Value{};\n");
    } else {
        try output.appendSlice(allocator, "    ");
        try appendCppType(allocator, output, value);
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, "Value{};\n");
    }
}

fn nativeReturnStructure(program: Semantic.Program, function: Semantic.Function) ?Semantic.Structure {
    const returned = nativeReturnValueType(function.return_type);
    return nativeStructureForType(program, if (returned == .reference) returned.reference.target.* else returned);
}

fn nativeStructureForType(program: Semantic.Program, value: Semantic.Type) ?Semantic.Structure {
    const structure_type = switch (value) {
        .structure => |structure| structure,
        else => return null,
    };
    for (program.structures) |structure| {
        if (std.mem.eql(u8, structure.generated_name, structure_type.generated_name)) return structure;
    }
    return null;
}

fn structureIsNativeReturn(program: Semantic.Program, structure: Semantic.Structure) bool {
    for (program.functions) |function| {
        if (!function.is_native) continue;
        if (nativeResultShape(program, function.return_type)) |result| {
            const branches = [_]Semantic.Type{ result.success_type, result.failure_type };
            for (branches) |branch| {
                const value = nativeBranchValueType(branch);
                if (value == .structure and std.mem.eql(u8, value.structure.generated_name, structure.generated_name)) return true;
            }
        }
        const returned = nativeReturnValueType(function.return_type);
        if (returned != .structure) continue;
        if (std.mem.eql(u8, returned.structure.generated_name, structure.generated_name)) return true;
    }
    return false;
}

fn nativeReturnValueType(return_type: Semantic.Type) Semantic.Type {
    return if (return_type == .optional) return_type.optional.* else return_type;
}

fn nativeReturnedView(value: Semantic.Type) ?*const Semantic.Type {
    if (value != .reference or value.reference.target.* != .view) return null;
    return value.reference.target.*.view;
}

fn nativeArgumentViewType(value: Semantic.Type) ?*const Semantic.Type {
    const target = if (value == .reference) value.reference.target.* else value;
    return if (target == .view) target.view else null;
}

fn structureHasString(structure: Semantic.Structure) bool {
    for (structure.fields) |field| if (field.type == .str) return true;
    return false;
}

fn containsNativeFunction(functions: []const Semantic.Function) bool {
    for (functions) |function| if (function.is_native) return true;
    return false;
}

fn nativeTransportHasString(structure: Semantic.NativeStructureTransport) bool {
    for (structure.fields) |field| if (field.type == .str) return true;
    return false;
}

fn generateNativeStringGuardCleanup(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.NativeStructureTransport,
) GenerateError!void {
    for (structure.fields) |field| {
        if (field.type != .str) continue;
        try output.appendSlice(allocator, "silexNativeGuard_");
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, ".reset();");
    }
}

fn generateNativeArgumentPreludes(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
) GenerateError!void {
    for (call.arguments, call.native_parameter_structures, 0..) |argument, parameter_structure, index| {
        if (argument.type == .str) {
            try output.appendSlice(allocator, "auto&& silexNativeString");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (nativeArgumentViewType(argument.type) != null) {
            try output.appendSlice(allocator, "const auto& silexNativeView");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (isNativeByteViewType(argument.type)) {
            try output.appendSlice(allocator, "const auto& silexNativeBytes");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, argument);
            try output.append(allocator, ';');
            continue;
        }
        if (isNativeCallbackType(argument.type)) {
            try output.appendSlice(allocator, if (argument.type.function.deferred) "auto silexNativeDeferred" else "auto silexNativeCallback");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
            if (argument.type.function.deferred) {
                try output.appendSlice(allocator, " = std::make_shared<");
                try appendCppDeferredCallbackStateType(allocator, output, argument.type.function);
                try output.appendSlice(allocator, ">(");
            } else try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, argument);
            try output.appendSlice(allocator, if (argument.type.function.deferred) ");" else ";");
            continue;
        }
        const structure = parameter_structure orelse continue;
        if (structure.is_native_resource) continue;
        try output.appendSlice(allocator, "const auto& silexNativeStructure");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, " = ");
        try generateExpression(allocator, output, argument);
        try output.append(allocator, ';');
        try output.appendSlice(allocator, try NativeInterface.inputTransportName(
            allocator,
            call.native_module_name.?,
            structure.source_name,
            nativeTransportHasString(structure),
        ));
        try output.appendSlice(allocator, " silexNativeInput");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, "{");
        for (structure.fields, 0..) |field, field_index| {
            if (field_index != 0) try output.appendSlice(allocator, ", ");
            if (field.type == .str) {
                try output.appendSlice(allocator, "silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ".size())");
            } else {
                try output.appendSlice(allocator, "silexNativeStructure");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.", .{index}));
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, "};");
    }
}

fn generateNativeArgument(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    index: usize,
) GenerateError!void {
    const argument = call.arguments[index];
    if (argument.type == .str) {
        try output.appendSlice(allocator, "silexNativeString");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeString");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (nativeArgumentViewType(argument.type) != null) {
        try output.appendSlice(allocator, "silexNativeView");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeView");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (isNativeByteViewType(argument.type)) {
        try output.appendSlice(allocator, "silexNativeBytes");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".data(), static_cast<std::int64_t>(silexNativeBytes");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
        try output.appendSlice(allocator, ".size())");
    } else if (isNativeCallbackType(argument.type)) {
        try generateNativeCallbackTrampoline(allocator, output, argument.type.function, index);
    } else if (call.native_parameter_structures[index]) |structure| {
        if (structure.is_native_resource) {
            if (call.is_native_resource_drop) {
                try output.appendSlice(allocator, "([&]() { auto&& silexNativeDropResource = ");
                try generateExpression(allocator, output, argument);
                try output.appendSlice(allocator, "; silexNativeDropResource.silexCancelDeferred(); return silexNativeDropResource.silexReleaseNativeHandle(); }())");
                return;
            }
            try output.append(allocator, '(');
            try generateExpression(allocator, output, argument);
            try output.append(allocator, ')');
            try output.appendSlice(allocator, if (call.native_parameter_modes[index] == .value) ".silexReleaseNativeHandle()" else ".silexBorrowNativeHandle()");
            return;
        }
        try output.appendSlice(allocator, "&silexNativeInput");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
    } else {
        try generateExpression(allocator, output, argument);
    }
}

fn generateNativeCallbackTrampoline(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
    index: usize,
) GenerateError!void {
    try output.appendSlice(allocator, "+[](void* silexNativeContext");
    for (callback.parameters, 0..) |parameter, parameter_index| {
        try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexNativeArgument{d}", .{parameter_index}));
    }
    try output.appendSlice(allocator, ") -> ");
    try appendCppType(allocator, output, callback.return_type.*);
    if (callback.deferred) {
        try output.appendSlice(allocator, " {auto* silexNativeCallback = static_cast<");
        try appendCppDeferredCallbackStateType(allocator, output, callback);
        try output.appendSlice(allocator, "*>(silexNativeContext);silexNativeCallback->enqueue(");
        for (callback.parameters, 0..) |_, parameter_index| {
            if (parameter_index != 0) try output.appendSlice(allocator, ", ");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexNativeArgument{d}", .{parameter_index}));
        }
        try output.appendSlice(allocator, ");}, silexNativeDeferred");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}.get()", .{index}));
        return;
    }
    try output.appendSlice(allocator, " {auto& silexNativeCallback = *static_cast<SilexFunction<");
    try appendCppType(allocator, output, callback.return_type.*);
    try output.append(allocator, '(');
    for (callback.parameters, 0..) |parameter, parameter_index| {
        if (parameter_index != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")>*>(silexNativeContext);");
    if (callback.return_type.* != .void) try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, "silexNativeCallback(");
    for (callback.parameters, 0..) |_, parameter_index| {
        if (parameter_index != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexNativeArgument{d}", .{parameter_index}));
    }
    try output.appendSlice(allocator, ");}, &silexNativeCallback");
    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{index}));
}

fn appendCppDeferredCallbackStateType(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    callback: Semantic.FunctionType,
) GenerateError!void {
    try output.appendSlice(allocator, "SilexDeferredCallbackStateFor<void(");
    for (callback.parameters, 0..) |parameter, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try appendCppType(allocator, output, parameter);
    }
    try output.appendSlice(allocator, ")>");
}

const NativeResultOwnedAction = enum { raw_free, guard, reset };

fn nativeResultBranchHasOwned(
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) bool {
    const value = nativeBranchValueType(branch_type);
    if (value == .str or isNativeByteBufferReturnType(value)) return true;
    return structure != null and (structure.?.is_native_resource or nativeTransportHasString(structure.?));
}

fn generateNativeResultOwnedAction(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
    action: NativeResultOwnedAction,
) GenerateError!void {
    const value = nativeBranchValueType(branch_type);
    if (value == .str or isNativeByteBufferReturnType(value)) {
        try generateNativeResultPointerAction(allocator, output, branch_name, null, isNativeByteBufferReturnType(value), action);
    } else if (structure) |transport| {
        if (transport.is_native_resource) {
            switch (action) {
                .raw_free => {
                    try output.appendSlice(allocator, "if (silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value != nullptr) ");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, "(silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value);");
                },
                .guard => {
                    try output.appendSlice(allocator, "std::unique_ptr<::");
                    try output.appendSlice(allocator, try NativeInterface.transportName(allocator, transport.native_module_name.?, transport.source_name));
                    try output.appendSlice(allocator, ", decltype(&");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, ")> silexNativeGuard_");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "{silexNativeOutput.");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, "Value, &");
                    try output.appendSlice(allocator, transport.native_drop_symbol.?);
                    try output.appendSlice(allocator, "};");
                },
                .reset => {
                    try output.appendSlice(allocator, "silexNativeGuard_");
                    try output.appendSlice(allocator, branch_name);
                    try output.appendSlice(allocator, ".reset();");
                },
            }
            return;
        }
        for (transport.fields) |field| {
            if (field.type != .str) continue;
            try generateNativeResultPointerAction(allocator, output, branch_name, field.generated_name, false, action);
        }
    }
}

fn generateNativeResultPointerAction(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    field_name: ?[]const u8,
    byte_buffer: bool,
    action: NativeResultOwnedAction,
) GenerateError!void {
    switch (action) {
        .raw_free => try output.appendSlice(allocator, "silexNativeRelease("),
        .guard => try output.appendSlice(allocator, if (byte_buffer) "std::unique_ptr<std::uint8_t, decltype(&silexNativeRelease)> silexNativeGuard_" else "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_"),
        .reset => try output.appendSlice(allocator, "silexNativeGuard_"),
    }
    if (action == .guard or action == .reset) {
        try output.appendSlice(allocator, branch_name);
        if (field_name) |field| {
            try output.append(allocator, '_');
            try output.appendSlice(allocator, field);
        }
    }
    if (action == .reset) {
        try output.appendSlice(allocator, ".reset();");
        return;
    }
    if (action == .guard) try output.append(allocator, '{');
    try output.appendSlice(allocator, "silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
        try output.appendSlice(allocator, "Bytes");
    } else {
        try output.appendSlice(allocator, "Bytes");
    }
    try output.appendSlice(allocator, if (action == .guard) ", &silexNativeRelease};" else ");");
}

fn generateNativeResultOwnedCondition(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) GenerateError!void {
    const value = nativeBranchValueType(branch_type);
    if (value == .str or isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Bytes != nullptr");
        return;
    }
    var count: usize = 0;
    if (structure.?.is_native_resource) {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value != nullptr");
        return;
    }
    for (structure.?.fields) |field| {
        if (field.type != .str) continue;
        if (count != 0) try output.appendSlice(allocator, " || ");
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field.generated_name);
        try output.appendSlice(allocator, "Bytes != nullptr");
        count += 1;
    }
}

fn generateNativeResultByteBufferValidation(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length < 0) {");
    try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a negative length", .{branch_name}));
    try output.appendSlice(allocator, "}if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length > 0) {");
    try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null pointer with a positive length", .{branch_name}));
    try output.appendSlice(allocator, "}");
}

fn generateNativeResultByteBufferConstruction(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "SilexList<std::uint8_t> silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ";if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes != nullptr) {silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ".insert(silexNativeBytes_");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, ".end(), silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes, silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Bytes + static_cast<std::size_t>(silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    try output.appendSlice(allocator, "Length));}");
}

fn generateNativeResultFatal(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    message: []const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "silexNativeCleanup();nativeFunctionRuntimeError(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, message);
    try output.appendSlice(allocator, ");");
}

fn generateNativeResultStringValidation(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    const label = if (field_name) |field|
        try std.fmt.allocPrint(allocator, "{s}.{s}", .{ branch_name, field })
    else
        branch_name;
    try output.appendSlice(allocator, "if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length < 0) {");
    try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a negative length", .{label}));
    try output.appendSlice(allocator, "}if (silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length > 0) {");
    try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null pointer with a positive length", .{label}));
    try output.appendSlice(allocator, "}");
}

fn generateNativeResultStringConstruction(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "std::string silexNativeString_");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.append(allocator, '_');
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, " = silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.appendSlice(allocator, "Value.");
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, "Length)};");
}

fn generateNativeResultUtf8Validation(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    module_name: []const u8,
    function_name: []const u8,
    branch_name: []const u8,
    field_name: ?[]const u8,
) GenerateError!void {
    try output.appendSlice(allocator, "if (!nativeStringIsValidUtf8(silexNativeString_");
    try output.appendSlice(allocator, branch_name);
    if (field_name) |field| {
        try output.append(allocator, '_');
        try output.appendSlice(allocator, field);
    }
    try output.appendSlice(allocator, ")) {nativeFunctionRuntimeError(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", ");
    const label = if (field_name) |field|
        try std.fmt.allocPrint(allocator, "Result {s}.{s} returned invalid UTF-8", .{ branch_name, field })
    else
        try std.fmt.allocPrint(allocator, "Result {s} returned invalid UTF-8", .{branch_name});
    try appendCppByteStringLiteral(allocator, output, label);
    try output.appendSlice(allocator, ");}");
}

fn generateNativeResultBranchValue(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    branch_name: []const u8,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
) GenerateError!void {
    const value = nativeBranchValueType(branch_type);
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "std::optional<");
        try appendCppType(allocator, output, value);
        try output.appendSlice(allocator, ">{");
    }
    if (value == .str) {
        try output.appendSlice(allocator, "std::move(silexNativeString_");
        try output.appendSlice(allocator, branch_name);
        try output.append(allocator, ')');
    } else if (isNativeByteBufferReturnType(value)) {
        try output.appendSlice(allocator, "std::move(silexNativeBytes_");
        try output.appendSlice(allocator, branch_name);
        try output.append(allocator, ')');
    } else if (structure) |transport| {
        if (transport.is_native_resource) {
            try output.appendSlice(allocator, transport.generated_name);
            try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeAdopted_");
            try output.appendSlice(allocator, branch_name);
            try output.append(allocator, ')');
            if (branch_type == .optional) try output.append(allocator, '}');
            return;
        }
        try output.appendSlice(allocator, transport.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (transport.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, branch_name);
                try output.append(allocator, '_');
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, branch_name);
                try output.appendSlice(allocator, "Value.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.append(allocator, ')');
    } else {
        try output.appendSlice(allocator, "silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value");
    }
    if (branch_type == .optional) try output.append(allocator, '}');
}

fn generateNativeResultBranchReturn(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    result: Semantic.NativeResultTransport,
    branch_name: []const u8,
    branch_index: usize,
    branch_type: Semantic.Type,
    structure: ?Semantic.NativeStructureTransport,
    module_name: []const u8,
    function_name: []const u8,
) GenerateError!void {
    const has_owned = nativeResultBranchHasOwned(branch_type, structure);
    if (branch_type == .optional) {
        try output.appendSlice(allocator, "if (!silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Present) {");
        if (has_owned) {
            try output.appendSlice(allocator, "if (");
            try generateNativeResultOwnedCondition(allocator, output, branch_name, branch_type, structure);
            try output.appendSlice(allocator, ") {");
            try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned an owned buffer while reporting absence", .{branch_name}));
            try output.appendSlice(allocator, "}");
        }
        try output.appendSlice(allocator, "silexNativeCleanup();return ");
        try output.appendSlice(allocator, result.enum_generated_name);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}, std::optional<", .{branch_index}));
        try appendCppType(allocator, output, nativeBranchValueType(branch_type));
        try output.appendSlice(allocator, ">{}};}");
    }

    const value = nativeBranchValueType(branch_type);
    if (structure != null and structure.?.is_native_resource) {
        try output.appendSlice(allocator, "if (silexNativeOutput.");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, "Value == nullptr) {");
        try generateNativeResultFatal(allocator, output, module_name, function_name, try std.fmt.allocPrint(allocator, "Result {s} returned a null native resource", .{branch_name}));
        try output.appendSlice(allocator, "}");
    }
    if (value == .str) {
        try generateNativeResultStringValidation(allocator, output, module_name, function_name, branch_name, null);
        try generateNativeResultStringConstruction(allocator, output, branch_name, null);
    } else if (isNativeByteBufferReturnType(value)) {
        try generateNativeResultByteBufferValidation(allocator, output, module_name, function_name, branch_name);
        try generateNativeResultByteBufferConstruction(allocator, output, branch_name);
    } else if (structure) |transport| {
        for (transport.fields) |field| if (field.type == .str) {
            try generateNativeResultStringValidation(allocator, output, module_name, function_name, branch_name, field.generated_name);
            try generateNativeResultStringConstruction(allocator, output, branch_name, field.generated_name);
        };
    }
    if (structure != null and structure.?.is_native_resource) {
        try output.appendSlice(allocator, "auto* silexNativeAdopted_");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, " = silexNativeGuard_");
        try output.appendSlice(allocator, branch_name);
        try output.appendSlice(allocator, ".release();");
    }
    try output.appendSlice(allocator, "silexNativeCleanup();");
    if (value == .str) {
        try generateNativeResultUtf8Validation(allocator, output, module_name, function_name, branch_name, null);
    } else if (structure) |transport| {
        for (transport.fields) |field| if (field.type == .str) {
            try generateNativeResultUtf8Validation(allocator, output, module_name, function_name, branch_name, field.generated_name);
        };
    }
    try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, result.enum_generated_name);
    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}", .{branch_index}));
    if (value != .void) {
        try output.appendSlice(allocator, ", ");
        try generateNativeResultBranchValue(allocator, output, branch_name, branch_type, structure);
    }
    try output.appendSlice(allocator, "};");
}

fn generateNativeResultFunctionCall(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    result: Semantic.NativeResultTransport,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const transport_name = try NativeInterface.resultTransportName(allocator, module_name, function_name);
    const tag_name = try std.fmt.allocPrint(allocator, "{s}Tag", .{transport_name});
    try output.appendSlice(allocator, "callNativeFunction(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() {");
    try generateNativeArgumentPreludes(allocator, output, call);
    try output.appendSlice(allocator, transport_name);
    try output.appendSlice(allocator, " silexNativeOutput{};silexNativeOutput.tag = static_cast<");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, ">(2);try {");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    try output.appendSlice(allocator, "&silexNativeOutput);} catch (...) {");
    try generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .raw_free);
    try generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .raw_free);
    try output.appendSlice(allocator, "throw;}");
    try generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .guard);
    try generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .guard);
    try output.appendSlice(allocator, "auto silexNativeCleanup = [&]() {");
    try generateNativeResultOwnedAction(allocator, output, "success", result.success_type, result.success_structure, .reset);
    try generateNativeResultOwnedAction(allocator, output, "failure", result.failure_type, result.failure_structure, .reset);
    try output.appendSlice(allocator, "};");

    try output.appendSlice(allocator, "if (silexNativeOutput.tag == ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_success) {");
    if (nativeResultBranchHasOwned(result.failure_type, result.failure_structure)) {
        try output.appendSlice(allocator, "if (");
        try generateNativeResultOwnedCondition(allocator, output, "failure", result.failure_type, result.failure_structure);
        try output.appendSlice(allocator, ") {");
        try generateNativeResultFatal(allocator, output, module_name, function_name, "returned an owned buffer in the inactive failure branch");
        try output.appendSlice(allocator, "}");
    }
    try generateNativeResultBranchReturn(allocator, output, result, "success", 0, result.success_type, result.success_structure, module_name, function_name);
    try output.appendSlice(allocator, "}if (silexNativeOutput.tag == ");
    try output.appendSlice(allocator, tag_name);
    try output.appendSlice(allocator, "_failure) {");
    if (nativeResultBranchHasOwned(result.success_type, result.success_structure)) {
        try output.appendSlice(allocator, "if (");
        try generateNativeResultOwnedCondition(allocator, output, "success", result.success_type, result.success_structure);
        try output.appendSlice(allocator, ") {");
        try generateNativeResultFatal(allocator, output, module_name, function_name, "returned an owned buffer in the inactive success branch");
        try output.appendSlice(allocator, "}");
    }
    try generateNativeResultBranchReturn(allocator, output, result, "failure", 1, result.failure_type, result.failure_structure, module_name, function_name);
    try output.appendSlice(allocator, "}");
    try generateNativeResultFatal(allocator, output, module_name, function_name, "returned an unknown Result tag");
    try output.appendSlice(allocator, "})");
}

fn generateNativeFunctionCall(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    return_type: Semantic.Type,
) GenerateError!void {
    if (nativeReturnedView(return_type)) |_| {
        const module_name = call.native_module_name.?;
        const function_name = call.native_function_name.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try generateNativeArgumentPreludes(allocator, output, call);
        try appendCppType(allocator, output, return_type);
        try output.appendSlice(allocator, "::value_type");
        if (!return_type.reference.mutable) try output.appendSlice(allocator, " const");
        try output.appendSlice(allocator, "* silexNativeValues = nullptr;std::int64_t silexNativeCount = 0;");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try generateNativeArgument(allocator, output, call, index);
        }
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeValues, &silexNativeCount);if (silexNativeCount < 0) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a negative view count\");if (silexNativeCount > 0 && silexNativeValues == nullptr) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null view with a positive count\");if (static_cast<std::uint64_t>(silexNativeCount) > std::numeric_limits<std::size_t>::max()) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a view count that is not representable\");return ");
        try appendCppType(allocator, output, return_type);
        try output.appendSlice(allocator, "(silexNativeValues, static_cast<std::size_t>(silexNativeCount));})");
        return;
    }
    if (return_type == .reference) {
        const parameter_index = call.borrowed_return_parameter.?;
        const module_name = call.native_module_name.?;
        const function_name = call.native_function_name.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "auto& silexBorrowRoot = ");
        try generateExpression(allocator, output, call.arguments[parameter_index]);
        try output.appendSlice(allocator, ";auto* silexNativeBorrow = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try generateNativeArgument(allocator, output, call, index);
        }
        try output.appendSlice(allocator, ");if (silexNativeBorrow == nullptr) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null borrowed resource\");if (silexNativeBorrow != silexBorrowRoot.silexBorrowNativeHandle()) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a resource outside its declared provenance\");return &silexBorrowRoot;})");
        return;
    }
    if (call.native_result) |result| {
        return generateNativeResultFunctionCall(allocator, output, call, result);
    }
    if (isNativeByteBufferReturnType(return_type)) {
        return generateNativeByteBufferFunctionCall(allocator, output, call);
    }
    if (return_type == .optional) {
        return generateNativeOptionalFunctionCall(allocator, output, call, return_type.optional.*);
    }
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const returns_string = return_type == .str;
    const returned_structure = call.native_return_structure;
    if (returned_structure != null and returned_structure.?.is_native_resource) {
        const resource = returned_structure.?;
        const deferred_index = nativeDeferredCallbackIndex(call.arguments);
        try output.appendSlice(allocator, "callNativeFunction(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() {");
        try generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "auto* silexNativeHandle = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try generateNativeArgument(allocator, output, call, index);
        }
        try output.appendSlice(allocator, ");if (silexNativeHandle == nullptr) {");
        if (deferred_index) |index| {
            try output.appendSlice(allocator, "silexNativeDeferred");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}->cancel();silexNativeDeferred{d}.reset();", .{ index, index }));
        }
        try output.appendSlice(allocator, "nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null native resource\");}return ");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeHandle");
        if (deferred_index) |index| {
            try output.appendSlice(allocator, ", std::move(silexNativeDeferred");
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d})", .{index}));
        }
        try output.appendSlice(allocator, ");})");
        return;
    }
    try output.appendSlice(allocator, if (returns_string) "callNativeStringFunction(" else "callNativeFunction(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, if (returns_string) ", [&](char** output_bytes, std::int64_t* output_length) {" else ", [&]() {");
    try generateNativeArgumentPreludes(allocator, output, call);
    if (returned_structure) |structure| {
        try output.appendSlice(allocator, try NativeInterface.transportName(
            allocator,
            module_name,
            structure.source_name,
        ));
        try output.appendSlice(allocator, " silexNativeOutput{};");
        if (nativeTransportHasString(structure)) try output.appendSlice(allocator, "try {");
    }
    if (!returns_string and returned_structure == null) try output.appendSlice(allocator, "return ");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try generateNativeArgument(allocator, output, call, index);
    }
    if (returns_string) {
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "output_bytes, output_length");
    } else if (returned_structure != null) {
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeOutput");
    }
    try output.appendSlice(allocator, ");");
    if (returned_structure) |structure| {
        if (nativeTransportHasString(structure)) {
            try output.appendSlice(allocator, "} catch (...) {");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes);");
            }
            try output.appendSlice(allocator, "throw;}");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, &silexNativeRelease};");
            }
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length < 0) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a negative length\");}");
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length > 0) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
                try output.appendSlice(allocator, "std::string silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " = silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length)};");
                try output.appendSlice(allocator, "if (!nativeStringIsValidUtf8(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ")) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}");
            }
            try generateNativeStringGuardCleanup(allocator, output, structure);
        }
        try output.appendSlice(allocator, " return ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (structure.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, ");");
    }
    try output.appendSlice(allocator, " })");
}

fn generateNativeByteBufferFunctionCall(
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
    try output.appendSlice(allocator, ", [&]() -> SilexList<std::uint8_t> {");
    try generateNativeArgumentPreludes(allocator, output, call);
    try output.appendSlice(allocator, "std::uint8_t* silexNativeOutputBytes = nullptr;std::int64_t silexNativeOutputLength = 0;try {");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    try output.appendSlice(allocator, "&silexNativeOutputBytes, &silexNativeOutputLength);} catch (...) {silexNativeRelease(silexNativeOutputBytes);throw;}");
    try output.appendSlice(allocator, "std::unique_ptr<std::uint8_t, decltype(&silexNativeRelease)> silexNativeGuard{silexNativeOutputBytes, &silexNativeRelease};");
    try output.appendSlice(allocator, "if (silexNativeOutputLength < 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", \"returned a negative length\");}");
    try output.appendSlice(allocator, "if (silexNativeOutputBytes == nullptr && silexNativeOutputLength > 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
    try output.appendSlice(allocator, "SilexList<std::uint8_t> silexNativeBytes;if (silexNativeOutputBytes != nullptr) {silexNativeBytes.insert(silexNativeBytes.end(), silexNativeOutputBytes, silexNativeOutputBytes + static_cast<std::size_t>(silexNativeOutputLength));}silexNativeGuard.reset();return silexNativeBytes;})");
}

fn generateNativeOptionalFunctionCall(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    call: Semantic.Expression.Call,
    returned_type: Semantic.Type,
) GenerateError!void {
    const module_name = call.native_module_name.?;
    const function_name = call.native_function_name.?;
    const returns_string = returned_type == .str;
    const returned_structure = call.native_return_structure;

    if (returned_structure != null and returned_structure.?.is_native_resource) {
        const resource = returned_structure.?;
        try output.appendSlice(allocator, "callNativeFunction(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", [&]() -> std::optional<");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "> {");
        try generateNativeArgumentPreludes(allocator, output, call);
        try output.appendSlice(allocator, "::");
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, resource.source_name));
        try output.appendSlice(allocator, "* silexNativeHandle = nullptr;const bool silexNativePresent = ");
        try output.appendSlice(allocator, call.generated_name);
        try output.append(allocator, '(');
        for (call.arguments, 0..) |_, index| {
            if (index != 0) try output.appendSlice(allocator, ", ");
            try generateNativeArgument(allocator, output, call, index);
        }
        if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, "&silexNativeHandle);if (!silexNativePresent) {if (silexNativeHandle != nullptr) {");
        try output.appendSlice(allocator, resource.native_drop_symbol.?);
        try output.appendSlice(allocator, "(silexNativeHandle);nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a native resource while reporting absence\");}return std::nullopt;}if (silexNativeHandle == nullptr) nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null native resource\");return ");
        try output.appendSlice(allocator, resource.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}, silexNativeHandle);})");
        return;
    }

    try output.appendSlice(allocator, "callNativeFunction(");
    try appendCppByteStringLiteral(allocator, output, module_name);
    try output.appendSlice(allocator, ", ");
    try appendCppByteStringLiteral(allocator, output, function_name);
    try output.appendSlice(allocator, ", [&]() -> std::optional<");
    try appendCppType(allocator, output, returned_type);
    try output.appendSlice(allocator, "> {");

    try generateNativeArgumentPreludes(allocator, output, call);

    if (returns_string) {
        try output.appendSlice(allocator, "char* silexNativeOutputBytes = nullptr;std::int64_t silexNativeOutputLength = 0;");
    } else if (returned_structure) |structure| {
        try output.appendSlice(allocator, try NativeInterface.transportName(allocator, module_name, structure.source_name));
        try output.appendSlice(allocator, " silexNativeOutput{};");
    } else {
        try appendCppType(allocator, output, returned_type);
        try output.appendSlice(allocator, " silexNativeOutput{};");
    }

    const has_owned_buffers = returns_string or
        (returned_structure != null and nativeTransportHasString(returned_structure.?));
    if (has_owned_buffers) try output.appendSlice(allocator, "bool silexNativePresent = false;try {");
    if (!has_owned_buffers) try output.appendSlice(allocator, "const bool silexNativePresent = ");
    if (has_owned_buffers) try output.appendSlice(allocator, "silexNativePresent = ");
    try output.appendSlice(allocator, call.generated_name);
    try output.append(allocator, '(');
    for (call.arguments, 0..) |_, index| {
        if (index != 0) try output.appendSlice(allocator, ", ");
        try generateNativeArgument(allocator, output, call, index);
    }
    if (call.arguments.len != 0) try output.appendSlice(allocator, ", ");
    if (returns_string) {
        try output.appendSlice(allocator, "&silexNativeOutputBytes, &silexNativeOutputLength");
    } else {
        try output.appendSlice(allocator, "&silexNativeOutput");
    }
    try output.appendSlice(allocator, ");");

    if (has_owned_buffers) {
        try output.appendSlice(allocator, "} catch (...) {");
        if (returns_string) {
            try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutputBytes);");
        } else for (returned_structure.?.fields) |field| {
            if (field.type != .str) continue;
            try output.appendSlice(allocator, "silexNativeRelease(silexNativeOutput.");
            try output.appendSlice(allocator, field.generated_name);
            try output.appendSlice(allocator, "Bytes);");
        }
        try output.appendSlice(allocator, "throw;}");
    }

    if (returns_string) {
        try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard{silexNativeOutputBytes, &silexNativeRelease};");
        try output.appendSlice(allocator, "if (!silexNativePresent) {if (silexNativeOutputBytes != nullptr) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned an owned buffer while reporting absence\");}return std::nullopt;}");
        try output.appendSlice(allocator, "if (silexNativeOutputLength < 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a negative length\");}");
        try output.appendSlice(allocator, "if (silexNativeOutputBytes == nullptr && silexNativeOutputLength > 0) {silexNativeGuard.reset();nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
        try output.appendSlice(allocator, "std::string silexNativeString = silexNativeOutputBytes == nullptr ? std::string{} : std::string{silexNativeOutputBytes, static_cast<std::size_t>(silexNativeOutputLength)};silexNativeGuard.reset();if (!nativeStringIsValidUtf8(silexNativeString)) {nativeFunctionRuntimeError(");
        try appendCppByteStringLiteral(allocator, output, module_name);
        try output.appendSlice(allocator, ", ");
        try appendCppByteStringLiteral(allocator, output, function_name);
        try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}return silexNativeString;");
    } else if (returned_structure) |structure| {
        if (nativeTransportHasString(structure)) {
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "std::unique_ptr<char, decltype(&silexNativeRelease)> silexNativeGuard_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, &silexNativeRelease};");
            }
            try output.appendSlice(allocator, "if (!silexNativePresent) {");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes != nullptr) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned an owned buffer while reporting absence\");}");
            }
            try output.appendSlice(allocator, "return std::nullopt;}");
            for (structure.fields) |field| {
                if (field.type != .str) continue;
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length < 0) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a negative length\");}");
                try output.appendSlice(allocator, "if (silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr && silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length > 0) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned a null pointer with a positive length\");}");
                try output.appendSlice(allocator, "std::string silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, " = silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes == nullptr ? std::string{} : std::string{silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Bytes, static_cast<std::size_t>(silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, "Length)};if (!nativeStringIsValidUtf8(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.appendSlice(allocator, ")) {");
                try generateNativeStringGuardCleanup(allocator, output, structure);
                try output.appendSlice(allocator, "nativeStructureFieldRuntimeError(");
                try appendCppByteStringLiteral(allocator, output, module_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, function_name);
                try output.appendSlice(allocator, ", ");
                try appendCppByteStringLiteral(allocator, output, field.source_name);
                try output.appendSlice(allocator, ", \"returned invalid UTF-8\");}");
            }
            try generateNativeStringGuardCleanup(allocator, output, structure);
        } else {
            try output.appendSlice(allocator, "if (!silexNativePresent) return std::nullopt;");
        }
        try output.appendSlice(allocator, "return ");
        try output.appendSlice(allocator, structure.generated_name);
        try output.appendSlice(allocator, "(SilexNativeReturnTag{}");
        for (structure.fields) |field| {
            if (field.type == .str) {
                try output.appendSlice(allocator, ", std::move(silexNativeString_");
                try output.appendSlice(allocator, field.generated_name);
                try output.append(allocator, ')');
            } else {
                try output.appendSlice(allocator, ", silexNativeOutput.");
                try output.appendSlice(allocator, field.generated_name);
            }
        }
        try output.appendSlice(allocator, ");");
    } else {
        try output.appendSlice(allocator, "if (!silexNativePresent) return std::nullopt;return silexNativeOutput;");
    }
    try output.appendSlice(allocator, " })");
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

fn generateStructureOperatorEqualitySignature(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    structure: Semantic.Structure,
    include_names: bool,
) !void {
    try output.appendSlice(allocator, "bool operator==(const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " left");
    try output.appendSlice(allocator, ", const ");
    try output.appendSlice(allocator, structure.generated_name);
    try output.appendSlice(allocator, "&");
    if (include_names) try output.appendSlice(allocator, " right");
    try output.append(allocator, ')');
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

fn generateTryPreludes(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    expression: *const Semantic.Expression,
    indentation: usize,
) GenerateError!void {
    switch (expression.value) {
        .move_expression => |move_value| try generateTryPreludes(allocator, output, move_value.operand, indentation),
        .borrow_expression => |borrow_value| try generateTryPreludes(allocator, output, borrow_value.operand, indentation),
        .try_expression => |try_value| {
            try generateTryPreludes(allocator, output, try_value.operand, indentation);
            if (expression.type != .void) {
                try indent(allocator, output, indentation);
                try output.appendSlice(allocator, "std::optional<");
                try appendCppType(allocator, output, expression.type);
                try output.append(allocator, '>');
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value;\n");
            }
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "{\n");
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "    auto ");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, try_value.operand);
            try output.appendSlice(allocator, ";\n");
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "    if (");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) return ", .{try_value.failure_variant_index}));
            try output.appendSlice(allocator, try_value.return_enum_generated_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{{std::size_t{{{d}}}, ", .{try_value.failure_variant_index}));
            try output.appendSlice(allocator, "std::move(");
            try output.appendSlice(allocator, try_value.temporary_name);
            try output.appendSlice(allocator, ".get<");
            try appendCppType(allocator, output, try_value.error_type);
            try output.appendSlice(allocator, ">(0))};\n");
            if (expression.type != .void) {
                try indent(allocator, output, indentation);
                try output.appendSlice(allocator, "    ");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value.emplace(std::move(");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, ".get<");
                try appendCppType(allocator, output, expression.type);
                try output.appendSlice(allocator, ">(0)));\n");
            }
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .string_length => |value| try generateTryPreludes(allocator, output, value, indentation),
        .sequence_literal => |values| for (values) |value| try generateTryPreludes(allocator, output, value, indentation),
        .collection_method => |method| {
            try generateTryPreludes(allocator, output, method.object, indentation);
            for (method.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation);
        },
        .call => |call| for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation),
        .value_call => |call| {
            try generateTryPreludes(allocator, output, call.callee, indentation);
            if (call.owner) |owner| try generateTryPreludes(allocator, output, owner, indentation);
            for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation);
        },
        .lambda, .function_reference => {},
        .method_call => |call| {
            try generateTryPreludes(allocator, output, call.object, indentation);
            for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation);
        },
        .protocol_method_call => |call| {
            try generateTryPreludes(allocator, output, call.object, indentation);
            for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation);
        },
        .static_method_call => |call| for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation),
        .super_method_call => |call| for (call.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation),
        .cascade => |cascade| {
            try generateTryPreludes(allocator, output, cascade.object, indentation);
            for (cascade.operations) |operation| switch (operation) {
                .method_call => |call| try generateTryPreludes(allocator, output, call, indentation),
                .field_assignment => |assignment| try generateTryPreludes(allocator, output, assignment.value, indentation),
            };
        },
        .class_initializer => |initializer| for (initializer.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation),
        .structure_initializer => |initializer| for (initializer.fields) |field| try generateTryPreludes(allocator, output, field, indentation),
        .enum_initializer => |initializer| for (initializer.arguments) |argument| try generateTryPreludes(allocator, output, argument, indentation),
        .enum_raw_value => |value| try generateTryPreludes(allocator, output, value, indentation),
        .match_expression => |match_value| try generateTryPreludes(allocator, output, match_value.subject, indentation),
        .member_access => |member| try generateTryPreludes(allocator, output, member.object, indentation),
        .bound_function => |member| try generateTryPreludes(allocator, output, member.object, indentation),
        .adapt_function => |value| try generateTryPreludes(allocator, output, value, indentation),
        .optional_wrap => |value| try generateTryPreludes(allocator, output, value, indentation),
        .safe_access => |access| {
            try generateTryPreludes(allocator, output, access.receiver, indentation);
            try generateTryPreludes(allocator, output, access.end, indentation);
        },
        .index_access => |access| {
            try generateTryPreludes(allocator, output, access.object, indentation);
            try generateTryPreludes(allocator, output, access.index, indentation);
        },
        .slice_access => |access| {
            try generateTryPreludes(allocator, output, access.object, indentation);
            try generateTryPreludes(allocator, output, access.start, indentation);
            try generateTryPreludes(allocator, output, access.end, indentation);
        },
        .unary => |unary| try generateTryPreludes(allocator, output, unary.operand, indentation),
        .binary => |binary| {
            try generateTryPreludes(allocator, output, binary.left, indentation);
            try generateTryPreludes(allocator, output, binary.right, indentation);
        },
        .conversion => |conversion| try generateTryPreludes(allocator, output, conversion.operand, indentation),
        .protocol_conversion => |conversion| try generateTryPreludes(allocator, output, conversion.operand, indentation),
        .integer, .floating, .boolean, .null, .string, .cascade_target, .variable, .self, .owner_self, .static_field_access, .optional_unwrap => {},
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
            try generateTryPreludes(allocator, output, argument, indentation);
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
            try generateTryPreludes(allocator, output, assertion.condition, indentation);
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
            try generateTryPreludes(allocator, output, panic_value.message, indentation);
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "panicRuntimeError(");
            try appendCppSourceLocation(allocator, output, panic_value.position);
            try output.appendSlice(allocator, ", ");
            try generateExpression(allocator, output, panic_value.message);
            try output.appendSlice(allocator, ");\n");
        },
        .variable_declaration => |declaration| {
            try generateTryPreludes(allocator, output, declaration.initializer, indentation);
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
                if (declaration.mutability == .immutable and declaration.type != .reference and !declaration.is_noncopyable) {
                    try output.appendSlice(allocator, "const ");
                }
                try appendCppType(allocator, output, declaration.type);
                try output.append(allocator, ' ');
                try output.appendSlice(allocator, declaration.generated_name);
                try output.appendSlice(allocator, " = ");
                try generateExpression(allocator, output, declaration.initializer);
            }
            try output.appendSlice(allocator, ";\n");
        },
        .assignment => |assignment| {
            try generateTryPreludes(allocator, output, assignment.target, indentation);
            if (assignment.value) |value| try generateTryPreludes(allocator, output, value, indentation);
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
            switch (if_statement.condition) {
                .expression => |condition| try generateTryPreludes(allocator, output, condition, indentation),
                .binding => |binding| try generateTryPreludes(allocator, output, binding.source, indentation),
            }
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
                try generateTryPreludes(allocator, output, while_statement.condition.binding.source, indentation + 1);
                try indent(allocator, output, indentation + 1);
                try output.appendSlice(allocator, switch (binding.mode) {
                    .copy, .move => "auto ",
                    .borrow => "const auto& ",
                });
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
            try output.appendSlice(allocator, "while (true) {\n");
            try generateTryPreludes(allocator, output, while_statement.condition.expression, indentation + 1);
            try indent(allocator, output, indentation + 1);
            try output.appendSlice(allocator, "if (!");
            try generateCondition(allocator, output, while_statement.condition);
            try output.appendSlice(allocator, ") break;\n");
            try generateStatements(allocator, output, while_statement.body, indentation + 1, is_main);
            try indent(allocator, output, indentation);
            try output.appendSlice(allocator, "}\n");
        },
        .for_statement => |for_statement| {
            switch (for_statement.source) {
                .collection => |collection| try generateTryPreludes(allocator, output, collection, indentation),
                .integer_range => |range| {
                    try generateTryPreludes(allocator, output, range.start, indentation);
                    try generateTryPreludes(allocator, output, range.end, indentation);
                },
            }
            switch (for_statement.source) {
                .collection => |collection| {
                    try indent(allocator, output, indentation);
                    try output.appendSlice(allocator, "for (");
                    try output.appendSlice(allocator, switch (for_statement.binding) {
                        .read => if (for_statement.element_noncopyable) "const auto& " else "auto ",
                        .immutable => "const auto& ",
                        .mutable => "auto& ",
                    });
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
            if (value) |expression| try generateTryPreludes(allocator, output, expression, indentation);
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
            if (expression.value == .match_expression and expression.type == .void) {
                try generateImperativeMatch(allocator, output, expression.value.match_expression, indentation, is_main);
                return;
            }
            try generateTryPreludes(allocator, output, expression, indentation);
            try indent(allocator, output, indentation);
            try generateExpression(allocator, output, expression);
            try output.appendSlice(allocator, ";\n");
        },
    }
}

fn generateMatchBindings(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    match_value: Semantic.Expression.Match,
    branch: Semantic.Expression.Match.Branch,
    multiline: bool,
    indentation: usize,
) GenerateError!void {
    for (branch.bindings, 0..) |binding, binding_index| {
        if (multiline) try indent(allocator, output, indentation);
        if (binding.capture_box.*) {
            try output.appendSlice(allocator, "auto ");
            try output.appendSlice(allocator, binding.generated_name);
            try output.appendSlice(allocator, " = silexMake<SilexBinding<");
            try appendCppType(allocator, output, binding.type);
            try output.appendSlice(allocator, ">>(");
        } else {
            if (match_value.mode == .borrow) try output.appendSlice(allocator, "const ");
            if (binding.mutability == .immutable and match_value.mode == .copy) try output.appendSlice(allocator, "const ");
            try appendCppType(allocator, output, binding.type);
            if (match_value.mode == .borrow) try output.append(allocator, '&');
            try output.append(allocator, ' ');
            try output.appendSlice(allocator, binding.generated_name);
            try output.appendSlice(allocator, " = ");
        }
        if (match_value.mode == .move) try output.appendSlice(allocator, "std::move(");
        try output.appendSlice(allocator, match_value.temporary_name);
        try output.appendSlice(allocator, ".get<");
        try appendCppType(allocator, output, binding.type);
        try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ">({d})", .{binding_index}));
        if (match_value.mode == .move) try output.append(allocator, ')');
        if (binding.capture_box.*) try output.append(allocator, ')');
        try output.appendSlice(allocator, if (multiline) ";\n" else "; ");
    }
}

fn generateImperativeMatch(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    match_value: Semantic.Expression.Match,
    indentation: usize,
    is_main: bool,
) GenerateError!void {
    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "{\n");
    try generateTryPreludes(allocator, output, match_value.subject, indentation + 1);
    try indent(allocator, output, indentation + 1);
    try output.appendSlice(allocator, switch (match_value.mode) {
        .copy => "const auto ",
        .move => "auto ",
        .borrow => "const auto& ",
    });
    try output.appendSlice(allocator, match_value.temporary_name);
    try output.appendSlice(allocator, " = ");
    try generateExpression(allocator, output, match_value.subject);
    try output.appendSlice(allocator, ";\n");
    for (match_value.branches, 0..) |branch, branch_index| {
        try indent(allocator, output, indentation + 1);
        if (branch.variant_index) |variant_index| {
            if (branch_index != 0) try output.appendSlice(allocator, "else ");
            try output.appendSlice(allocator, "if (");
            try output.appendSlice(allocator, match_value.temporary_name);
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) {{\n", .{variant_index}));
        } else {
            try output.appendSlice(allocator, if (branch_index == 0) "{\n" else "else {\n");
        }
        try generateMatchBindings(allocator, output, match_value, branch, true, indentation + 2);
        switch (branch.body) {
            .statements => |statements| try generateStatements(allocator, output, statements, indentation + 2, is_main),
            .expression => unreachable,
        }
        try indent(allocator, output, indentation + 1);
        try output.appendSlice(allocator, "}\n");
    }
    try indent(allocator, output, indentation);
    try output.appendSlice(allocator, "}\n");
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
    if (for_statement.binding != .mutable) try output.appendSlice(allocator, "const ");
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
        try output.appendSlice(allocator, switch (binding.mode) {
            .copy, .move => "(auto ",
            .borrow => "(const auto& ",
        });
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
        if (binding.mode == .borrow) try output.appendSlice(allocator, "const ");
        if (binding.mutability == .immutable and binding.mode == .copy) try output.appendSlice(allocator, "const ");
        try appendCppType(allocator, output, binding.type);
        if (binding.mode == .borrow) try output.append(allocator, '&');
        try output.append(allocator, ' ');
        try output.appendSlice(allocator, binding.generated_name);
        try output.appendSlice(allocator, if (binding.mode == .move) " = std::move(*" else " = *");
        try output.appendSlice(allocator, binding.temporary_name);
        if (binding.mode == .move) try output.append(allocator, ')');
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
        .protocol_method_call => |call| {
            try generateExpression(allocator, output, call.object);
            try output.append(allocator, '.');
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .sequence_literal => |values| {
            if (expression.type == .list) {
                try output.appendSlice(allocator, "silexMakeList<");
                try appendCppType(allocator, output, expression.type.list.*);
                try output.appendSlice(allocator, ">(");
            } else {
                try appendCppType(allocator, output, expression.type);
                try output.append(allocator, '{');
            }
            for (values, 0..) |value, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, value);
            }
            try output.append(allocator, if (expression.type == .list) ')' else '}');
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
            try output.appendSlice(allocator, if (access.borrowed and access.mutable) "([&]() { auto& silexSliceValues = " else "([&]() { const auto& silexSliceValues = ");
            try generateExpression(allocator, output, access.object);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceStart = ");
            try generateExpression(allocator, output, access.start);
            try output.appendSlice(allocator, "; const std::int64_t silexSliceEnd = ");
            try generateExpression(allocator, output, access.end);
            try output.appendSlice(allocator, if (!access.borrowed)
                "; return silexCollectionSlice(silexSliceValues, silexSliceStart, silexSliceEnd); }())"
            else if (access.mutable)
                "; return silexCollectionMutableView(silexSliceValues, silexSliceStart, silexSliceEnd); }())"
            else
                "; return silexCollectionReadView(silexSliceValues, silexSliceStart, silexSliceEnd); }())");
        },
        .try_expression => |try_value| {
            if (expression.type == .void) {
                try output.appendSlice(allocator, "(void)0");
            } else {
                try output.appendSlice(allocator, "std::move(*");
                try output.appendSlice(allocator, try_value.temporary_name);
                try output.appendSlice(allocator, "Value)");
            }
        },
        .move_expression => |move_value| {
            try output.appendSlice(allocator, "std::move(");
            try generateExpression(allocator, output, move_value.operand);
            try output.append(allocator, ')');
        },
        .borrow_expression => |borrow_value| {
            if (expression.type == .reference and expression.type.reference.target.* != .view) try output.append(allocator, '&');
            try generateExpression(allocator, output, borrow_value.operand);
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
                try generateNativeFunctionCall(allocator, output, call, expression.type);
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
                try appendCppParameterType(allocator, output, parameter.type, parameter.mode);
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
        .static_method_call => |call| {
            try output.appendSlice(allocator, call.owner_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, call.generated_name);
            try output.append(allocator, '(');
            for (call.arguments, 0..) |argument, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, ')');
        },
        .static_field_access => |access| {
            try output.appendSlice(allocator, access.owner_generated_name);
            try output.appendSlice(allocator, "::");
            try output.appendSlice(allocator, access.generated_name);
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
            if (isClassType(expression.type)) {
                try output.appendSlice(allocator, "silexMake<");
                try output.appendSlice(allocator, initializer.generated_name);
                try output.appendSlice(allocator, ">(");
            } else {
                try output.appendSlice(allocator, initializer.generated_name);
                try output.append(allocator, '(');
            }
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
        .enum_initializer => |initializer| {
            try output.appendSlice(allocator, initializer.enum_generated_name);
            try output.append(allocator, '{');
            try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "std::size_t{{{d}}}", .{initializer.variant_index}));
            for (initializer.arguments) |argument| {
                try output.appendSlice(allocator, ", ");
                try generateExpression(allocator, output, argument);
            }
            try output.append(allocator, '}');
        },
        .enum_raw_value => |value| {
            try generateExpression(allocator, output, value);
            try output.appendSlice(allocator, ".rawValue()");
        },
        .match_expression => |match_value| {
            try output.appendSlice(allocator, "([&]() { ");
            try output.appendSlice(allocator, switch (match_value.mode) {
                .copy => "const auto ",
                .move => "auto ",
                .borrow => "const auto& ",
            });
            try output.appendSlice(allocator, match_value.temporary_name);
            try output.appendSlice(allocator, " = ");
            try generateExpression(allocator, output, match_value.subject);
            try output.appendSlice(allocator, "; ");
            for (match_value.branches, 0..) |branch, branch_index| {
                if (branch.variant_index) |variant_index| {
                    if (branch_index != 0) try output.appendSlice(allocator, " else ");
                    try output.appendSlice(allocator, "if (");
                    try output.appendSlice(allocator, match_value.temporary_name);
                    try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, ".variant == {d}) {{ ", .{variant_index}));
                } else {
                    try output.appendSlice(allocator, if (branch_index == 0) "{ " else " else { ");
                }
                try generateMatchBindings(allocator, output, match_value, branch, false, 0);
                switch (branch.body) {
                    .expression => |value| {
                        try output.appendSlice(allocator, "return ");
                        try generateExpression(allocator, output, value);
                        try output.appendSlice(allocator, "; }");
                    },
                    .statements => unreachable,
                }
            }
            try output.appendSlice(allocator, " std::abort(); }())");
        },
        .member_access => |member| {
            if (member.object.value == .owner_self) {
                try output.appendSlice(allocator, "silexOwner.");
            } else if (member.object.value != .self) {
                if (member.object.type == .reference and isClassType(member.object.type.reference.target.*)) {
                    try output.appendSlice(allocator, "(*");
                    try generateExpression(allocator, output, member.object);
                    try output.appendSlice(allocator, ")->");
                } else {
                    try generateExpression(allocator, output, member.object);
                    try output.appendSlice(allocator, if (isClassType(member.object.type) or member.object.type == .reference) "->" else ".");
                }
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
            for (expression.type.function.parameters, expression.type.function.parameter_modes, 0..) |parameter_type, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter_type, mode);
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
        .function_reference => |generated_name| {
            try output.appendSlice(allocator, "silexMakeFunction<");
            try appendCppType(allocator, output, expression.type);
            try output.appendSlice(allocator, ">([](");
            for (expression.type.function.parameters, expression.type.function.parameter_modes, 0..) |parameter, mode, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter, mode);
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, " silexFunctionArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, ") { return ");
            try output.appendSlice(allocator, generated_name);
            try output.append(allocator, '(');
            for (expression.type.function.parameters, 0..) |_, index| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "silexFunctionArgument{d}", .{index}));
            }
            try output.appendSlice(allocator, "); })");
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
            for (function.parameters, function.parameter_modes, 0..) |parameter_type, mode, index| {
                try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter_type, mode);
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
                if (expression.type == .reference and expression.type.reference.target.* != .view) try output.append(allocator, '&');
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
        .protocol_conversion => |conversion| {
            try output.appendSlice(allocator, expression.type.protocol.generated_name);
            try output.appendSlice(allocator, "::make(");
            try generateExpression(allocator, output, conversion.operand);
            try output.appendSlice(allocator, ", &");
            try output.appendSlice(allocator, conversion.witness_name);
            try output.append(allocator, ')');
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

test "read view parameters preserve const elements" {
    var element: Semantic.Type = .uint8;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try appendCppParameterType(
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
        .list, .fixed_array, .view => unreachable,
        .structure => |structure_type| if (structure_type.is_class) unreachable else structure_type.generated_name,
        .protocol => |protocol_type| protocol_type.generated_name,
        .enumeration => |enum_type| enum_type.generated_name,
        .reference => unreachable,
        .optional, .null => unreachable,
    };
}

fn appendCppType(allocator: Allocator, output: *std.ArrayList(u8), type_name: Semantic.Type) Allocator.Error!void {
    switch (type_name) {
        .reference => |reference| {
            if (reference.target.* == .view) {
                try output.appendSlice(allocator, "SilexView<");
                if (!reference.mutable) try output.appendSlice(allocator, "const ");
                try appendCppType(allocator, output, reference.target.*.view.*);
                try output.append(allocator, '>');
                return;
            }
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
        .view => |element| {
            try output.appendSlice(allocator, "SilexView<");
            try appendCppType(allocator, output, element.*);
            try output.append(allocator, '>');
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
            for (function.parameters, function.parameter_modes) |parameter, mode| {
                if (index != 0) try output.appendSlice(allocator, ", ");
                try appendCppParameterType(allocator, output, parameter, mode);
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
        .protocol => |protocol_type| try output.appendSlice(allocator, protocol_type.generated_name),
        .enumeration => |enum_type| try output.appendSlice(allocator, enum_type.generated_name),
        .null => unreachable,
        else => try output.appendSlice(allocator, cppType(type_name)),
    }
}

fn appendCppParameterType(
    allocator: Allocator,
    output: *std.ArrayList(u8),
    type_name: Semantic.Type,
    mode: Ast.ParameterMode,
) Allocator.Error!void {
    if (type_name == .view) {
        if (mode == .borrow) try output.appendSlice(allocator, "const ");
        try output.appendSlice(allocator, "SilexView<");
        if (mode == .borrow) try output.appendSlice(allocator, "const ");
        try appendCppType(allocator, output, type_name.view.*);
        try output.append(allocator, '>');
        if (mode != .value) try output.append(allocator, '&');
        return;
    }
    if (mode == .borrow) try output.appendSlice(allocator, "const ");
    try appendCppType(allocator, output, type_name);
    if (mode != .value) try output.append(allocator, '&');
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
        .view => "view",
        .structure => |structure_type| structure_type.source_name,
        .protocol => |protocol_type| protocol_type.source_name,
        .enumeration => |enum_type| enum_type.source_name,
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

test "generate try as an ordinary early Result return" {
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
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
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
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

test "generate string native return bridge" {
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
    const Modules = @import("Modules.zig");
    const Project = @import("Project.zig").Project;
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
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
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
    const Parser = @import("Parser.zig").Parser;
    const Modules = @import("Modules.zig");
    const Project = @import("Project.zig").Project;
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
    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
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

test "native output releases are observed exactly once" {
    if (build_options.developer_zig.len == 0) return error.SkipZigTest;

    const Parser = @import("Parser.zig").Parser;
    const Generics = @import("Generics.zig");
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
    try std.testing.expect(std.mem.indexOf(u8, cpp, "int main(int argumentCount, char** argumentValues)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cpp, "silexRuntimeArgumentCountValue = argumentCount;") != null);
}

test "generate class references identity access and cycle tracing" {
    const Parser = @import("Parser.zig").Parser;
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
    const Parser = @import("Parser.zig").Parser;
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

test "generate unique resource struct as movable RAII value" {
    const Parser = @import("Parser.zig").Parser;
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

test "generate read reference parameters as const references" {
    const Parser = @import("Parser.zig").Parser;
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
