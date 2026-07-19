#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <SilexNative/NativeByteBuffers.h>

#if defined(__APPLE__)
#include <malloc/malloc.h>
#endif

namespace {

struct TrackedAllocation {
    void* pointer { nullptr };
    int frees { 0 };
};

TrackedAllocation trackedAllocations[16];
std::size_t trackedAllocationCount = 0;
bool trackerRegistered = false;

bool trackedOutputsFreed();

void verifyTrackedAllocations() {
    if (!trackedOutputsFreed()) std::_Exit(2);
}

void trackAllocation(void* pointer) {
    if (pointer == nullptr) return;
    if (!trackerRegistered) {
        std::atexit(verifyTrackedAllocations);
        trackerRegistered = true;
    }
    trackedAllocations[trackedAllocationCount++] = {pointer, 0};
}

void trackFree(void* pointer) {
    for (std::size_t index = trackedAllocationCount; index > 0; index -= 1) {
        auto& allocation = trackedAllocations[index - 1];
        if (allocation.pointer != pointer || allocation.frees != 0) continue;
        allocation.frees += 1;
        return;
    }
}

std::uint8_t* copyBytes(const std::uint8_t* bytes, std::int64_t length) {
    if (length == 0) return nullptr;
    auto* result = static_cast<std::uint8_t*>(std::malloc(static_cast<std::size_t>(length)));
    if (result != nullptr) std::memcpy(result, bytes, static_cast<std::size_t>(length));
    trackAllocation(result);
    return result;
}

bool trackedOutputsFreed() {
    for (std::size_t index = 0; index < trackedAllocationCount; index += 1) {
        if (trackedAllocations[index].frees != 1) return false;
    }
    return true;
}

} // namespace

#if defined(__APPLE__)
extern "C" void free(void* pointer) {
    if (pointer == nullptr) return;
    trackFree(pointer);
    malloc_zone_free(malloc_zone_from_ptr(pointer), pointer);
}
#endif

extern "C" void silexNative_NativeByteBuffers_native_compress(
    const std::uint8_t* bytes,
    std::int64_t length,
    std::uint8_t** outputBytes,
    std::int64_t* outputLength
) {
    *outputBytes = copyBytes(bytes, length);
    *outputLength = length;
}

extern "C" void silexNative_NativeByteBuffers_native_empty(
    std::uint8_t** outputBytes,
    std::int64_t* outputLength
) {
    *outputBytes = nullptr;
    *outputLength = 0;
}

extern "C" void silexNative_NativeByteBuffers_native_large(
    std::uint8_t** outputBytes,
    std::int64_t* outputLength
) {
    constexpr std::int64_t length = 1024;
    auto* bytes = static_cast<std::uint8_t*>(std::malloc(static_cast<std::size_t>(length)));
    for (std::int64_t index = 0; index < length; index += 1) bytes[index] = static_cast<std::uint8_t>(index);
    trackAllocation(bytes);
    *outputBytes = bytes;
    *outputLength = length;
}

extern "C" void silexNative_NativeByteBuffers_native_read(
    std::int64_t sequence,
    SilexNative_NativeByteBuffers_native_readResult* output
) {
    if (sequence == 2) {
        output->tag = SilexNative_NativeByteBuffers_native_readResultTag_failure;
        output->failure_bytes = nullptr;
        output->failure_length = 9;
        output->failure_bytes = static_cast<char*>(std::malloc(9));
        std::memcpy(output->failure_bytes, "not found", 9);
        trackAllocation(output->failure_bytes);
        return;
    }
    const std::uint8_t bytes[] = {0, 255, static_cast<std::uint8_t>(sequence), 0};
    output->tag = SilexNative_NativeByteBuffers_native_readResultTag_success;
    output->success_bytes = copyBytes(bytes, 4);
    output->success_length = 4;
}

extern "C" void silexNative_NativeByteBuffers_native_negative_length(
    std::uint8_t** outputBytes,
    std::int64_t* outputLength
) {
    const std::uint8_t byte = 7;
    *outputBytes = copyBytes(&byte, 1);
    *outputLength = -1;
}

extern "C" void silexNative_NativeByteBuffers_native_null_with_positive_length(
    std::uint8_t** outputBytes,
    std::int64_t* outputLength
) {
    *outputBytes = nullptr;
    *outputLength = 1;
}

extern "C" bool silexNative_NativeByteBuffers_native_outputs_freed() {
    return trackedOutputsFreed();
}
