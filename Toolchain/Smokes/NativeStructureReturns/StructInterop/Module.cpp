#include <SilexNative/StructInterop.h>

extern "C" void silexNative_StructInterop_native_read(
    int64_t seed,
    SilexNative_StructInterop_NativeScalars* output
) {
    output->integer = seed;
    output->signed8 = -8;
    output->signed16 = -16;
    output->signed32 = -32;
    output->unsigned8 = 8;
    output->unsigned16 = 16;
    output->unsigned32 = 32;
    output->unsigned64 = 64;
    output->decimal32 = 1.5f;
    output->decimal64 = 2.5;
    output->ready = true;
}
