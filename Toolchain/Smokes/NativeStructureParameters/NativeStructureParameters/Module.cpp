#include <cstdint>
#include <SilexNative/NativeStructureParameters.h>

extern "C" bool silexNative_NativeStructureParameters_native_verify(
    const SilexNative_NativeStructureParameters_NativeScalars* values,
    const SilexNative_NativeStructureParameters_NativeBounds* first,
    const SilexNative_NativeStructureParameters_NativeBounds* second,
    std::int64_t marker
) {
    return values->integer == 1 &&
        values->signed8 == -8 &&
        values->signed16 == -16 &&
        values->signed32 == -32 &&
        values->unsigned8 == 8 &&
        values->unsigned16 == 16 &&
        values->unsigned32 == 32 &&
        values->unsigned64 == 64 &&
        values->decimal32 == 1.5f &&
        values->decimal64 == 2.5 &&
        values->ready &&
        first->width == 10 &&
        first->height == 20 &&
        second->width == 30 &&
        second->height == 40 &&
        marker == 99;
}
