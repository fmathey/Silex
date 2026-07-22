const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Ast = @import("../Ast.zig");
const NativeInterface = @import("../NativeInterface.zig");
const Semantic = @import("../Semantic.zig");
const Source = @import("../Source.zig");
const Types = @import("Types.zig");

const Allocator = std.mem.Allocator;
const GenerateError = Allocator.Error;
const NativeResultShape = Types.NativeResultShape;
const NativeResultOwnedAction = Types.NativeResultOwnedAction;

pub fn appendRuntime(_: anytype, allocator: Allocator, output: *std.ArrayList(u8)) !void {
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
}
