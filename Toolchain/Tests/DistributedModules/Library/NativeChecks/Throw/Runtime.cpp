#include <stdexcept>

extern "C" void silexNative_NativeChecks_Throw_native_fail() {
    throw std::runtime_error("planned native failure");
}
