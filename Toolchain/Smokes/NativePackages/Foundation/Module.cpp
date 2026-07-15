#include <TinyMath.h>
#include <cstdint>

extern "C" std::int64_t silexNative_Foundation_native_answer() {
    return tiny_math_answer();
}
