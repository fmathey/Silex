#include <cstdint>
#include <random>
#include <SilexNative/STD.h>

extern "C" std::int64_t silexNative_STD_Randomizer_native_seed() {
    std::random_device source;
    return static_cast<std::int64_t>(source());
}
