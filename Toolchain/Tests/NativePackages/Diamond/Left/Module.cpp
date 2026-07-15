#include <Common.h>
#include <cstdint>

extern "C" std::int64_t silexNative_Left_native_value() {
    return common_value();
}
