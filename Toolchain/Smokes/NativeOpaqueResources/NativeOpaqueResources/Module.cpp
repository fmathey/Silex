#include <SilexNative/NativeOpaqueResources.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

struct SilexNative_NativeOpaqueResources_Buffer {
    std::int64_t value;
    std::int64_t values[4];
};

struct SilexNative_NativeOpaqueResources_Image {
    std::int64_t value;
};

struct SilexNative_NativeOpaqueResources_WindowHandle {
    std::int64_t value;
    bool alive;
};

struct SilexNative_NativeOpaqueResources_Renderer {
    SilexNative_NativeOpaqueResources_WindowHandle* window;
};

namespace {
std::int64_t live = 0;
std::vector<std::int64_t> lifetime_log;
}

extern "C" SilexNative_NativeOpaqueResources_Buffer*
silexNative_NativeOpaqueResources_create_buffer(std::int64_t value) {
    ++live;
    return new SilexNative_NativeOpaqueResources_Buffer{value, {value, value + 1, value + 2, value + 3}};
}

extern "C" bool silexNative_NativeOpaqueResources_maybe_buffer(
    bool present,
    std::int64_t value,
    SilexNative_NativeOpaqueResources_Buffer** output
) {
    if (!present) {
        *output = nullptr;
        return false;
    }
    *output = silexNative_NativeOpaqueResources_create_buffer(value);
    return true;
}

extern "C" void silexNative_NativeOpaqueResources_try_buffer(
    bool succeeds,
    std::int64_t value,
    SilexNative_NativeOpaqueResources_try_bufferResult* output
) {
    if (succeeds) {
        output->tag = SilexNative_NativeOpaqueResources_try_bufferResultTag_success;
        output->success_value = silexNative_NativeOpaqueResources_create_buffer(value);
        return;
    }
    static constexpr char message[] = "unavailable";
    output->tag = SilexNative_NativeOpaqueResources_try_bufferResultTag_failure;
    output->failure_length = sizeof(message) - 1;
    output->failure_bytes = static_cast<char*>(std::malloc(sizeof(message) - 1));
    std::memcpy(output->failure_bytes, message, sizeof(message) - 1);
}

extern "C" std::int64_t silexNative_NativeOpaqueResources_inspect_buffer(
    const SilexNative_NativeOpaqueResources_Buffer* buffer
) {
    return buffer->value;
}

extern "C" const SilexNative_NativeOpaqueResources_Buffer* silexNative_NativeOpaqueResources_borrow_buffer(
    const SilexNative_NativeOpaqueResources_Buffer* buffer
) {
    return buffer;
}

extern "C" void silexNative_NativeOpaqueResources_buffer_values(
    const SilexNative_NativeOpaqueResources_Buffer* buffer,
    const std::int64_t** output_values,
    std::int64_t* output_count
) {
    *output_values = buffer->values;
    *output_count = 4;
}

extern "C" void silexNative_NativeOpaqueResources_buffer_values_mut(
    SilexNative_NativeOpaqueResources_Buffer* buffer,
    std::int64_t** output_values,
    std::int64_t* output_count
) {
    *output_values = buffer->values;
    *output_count = 4;
}

extern "C" std::int64_t silexNative_NativeOpaqueResources_sum_values(
    const std::int64_t* values,
    std::int64_t count
) {
    std::int64_t total = 0;
    for (std::int64_t index = 0; index < count; ++index) total += values[index];
    return total;
}

extern "C" void silexNative_NativeOpaqueResources_increment_values(
    std::int64_t* values,
    std::int64_t count
) {
    for (std::int64_t index = 0; index < count; ++index) ++values[index];
}

extern "C" void silexNative_NativeOpaqueResources_invalid_negative_view(
    const SilexNative_NativeOpaqueResources_Buffer* buffer,
    const std::int64_t** output_values,
    std::int64_t* output_count
) {
    *output_values = buffer->values;
    *output_count = -1;
}

extern "C" void silexNative_NativeOpaqueResources_invalid_null_view(
    const SilexNative_NativeOpaqueResources_Buffer*,
    const std::int64_t** output_values,
    std::int64_t* output_count
) {
    *output_values = nullptr;
    *output_count = 1;
}

extern "C" void silexNative_NativeOpaqueResources_update_buffer(
    SilexNative_NativeOpaqueResources_Buffer* buffer,
    std::int64_t value
) {
    buffer->value = value;
}

extern "C" void silexNative_NativeOpaqueResources_consume_buffer(
    SilexNative_NativeOpaqueResources_Buffer* buffer
) {
    lifetime_log.push_back(100 + buffer->value);
    delete buffer;
    --live;
}

extern "C" void silexNative_NativeOpaqueResources_destroy_buffer(
    SilexNative_NativeOpaqueResources_Buffer* buffer
) {
    lifetime_log.push_back(100 + buffer->value);
    delete buffer;
    --live;
}

extern "C" void silexNative_NativeOpaqueResources_release_image(
    SilexNative_NativeOpaqueResources_Image* image
) {
    delete image;
}

extern "C" std::int64_t silexNative_NativeOpaqueResources_live_buffers() {
    return live;
}

extern "C" SilexNative_NativeOpaqueResources_WindowHandle*
silexNative_NativeOpaqueResources_create_window(std::int64_t value) {
    return new SilexNative_NativeOpaqueResources_WindowHandle{value, true};
}

extern "C" SilexNative_NativeOpaqueResources_Renderer*
silexNative_NativeOpaqueResources_create_renderer(
    const SilexNative_NativeOpaqueResources_WindowHandle* window
) {
    return new SilexNative_NativeOpaqueResources_Renderer{
        const_cast<SilexNative_NativeOpaqueResources_WindowHandle*>(window),
    };
}

extern "C" void silexNative_NativeOpaqueResources_destroy_renderer(
    SilexNative_NativeOpaqueResources_Renderer* renderer
) {
    if (renderer->window == nullptr || !renderer->window->alive) std::abort();
    lifetime_log.push_back(2);
    delete renderer;
}

extern "C" void silexNative_NativeOpaqueResources_destroy_window(
    SilexNative_NativeOpaqueResources_WindowHandle* window
) {
    window->alive = false;
    lifetime_log.push_back(1);
    delete window;
}

extern "C" void silexNative_NativeOpaqueResources_reset_lifetime_log() {
    lifetime_log.clear();
}

extern "C" std::int64_t silexNative_NativeOpaqueResources_lifetime_log_count() {
    return static_cast<std::int64_t>(lifetime_log.size());
}

extern "C" std::int64_t silexNative_NativeOpaqueResources_lifetime_log_at(std::int64_t index) {
    return lifetime_log.at(static_cast<std::size_t>(index));
}
