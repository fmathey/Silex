#include <SilexNative/Interop.h>

#include <cstdlib>
#include <cstring>

extern "C" int64_t silexNative_Interop_Api_First_native_add(int64_t left, int64_t right) {
    return left + right;
}

extern "C" void silexNative_Interop_Api_First_native_echo(
    const char* value_bytes,
    int64_t value_length,
    char** output_bytes,
    int64_t* output_length
) {
    *output_bytes = static_cast<char*>(std::malloc(static_cast<std::size_t>(value_length)));
    if (*output_bytes != nullptr) {
        std::memcpy(*output_bytes, value_bytes, static_cast<std::size_t>(value_length));
    }
    *output_length = value_length;
}

extern "C" bool silexNative_Interop_Api_Second_native_ready(void) {
    return true;
}

extern "C" int64_t silexNative_Interop_Status_native_code(void) {
    return 7;
}
