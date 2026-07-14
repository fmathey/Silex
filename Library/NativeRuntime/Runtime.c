#include "Runtime.hpp"

#include <stdio.h>
#include <stdint.h>

__attribute__((constructor)) static void announce_native_runtime(void) {
    puts(SILEX_NATIVE_RUNTIME_MESSAGE);
}

int64_t silexNative_NativeRuntime_native_title_byte_count(const char* title_bytes, int64_t title_length) {
    (void)title_bytes;
    return title_length;
}
