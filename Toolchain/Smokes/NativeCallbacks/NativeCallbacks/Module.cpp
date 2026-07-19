#include <cstdint>
#include <SilexNative/NativeCallbacks.h>

extern "C" std::int64_t silexNative_NativeCallbacks_native_visit(
    std::int64_t limit,
    bool (*visitor)(void*, std::int64_t),
    void* visitorContext
) {
    std::int64_t calls = 0;
    for (std::int64_t value = 1; value <= limit; value += 1) {
        calls += 1;
        if (!visitor(visitorContext, value)) break;
    }
    return calls;
}

extern "C" void silexNative_NativeCallbacks_native_notify(
    void (*visitor)(void*),
    void* visitorContext
) {
    visitor(visitorContext);
}

extern "C" std::int64_t silexNative_NativeCallbacks_native_increment(
    std::int64_t value
) {
    return value + 1;
}
