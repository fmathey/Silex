#include <chrono>
#include <cstdint>
#include <SilexNative/STD.h>

extern "C" std::int64_t silexNative_STD_Time_Internal_native_monotonic_microseconds() {
    const auto elapsed = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<std::int64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count()
    );
}
