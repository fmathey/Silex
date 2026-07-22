#include <cstdint>
#include <iostream>

extern "C" std::int64_t silexNative_Resources_Resource_native_open(std::int64_t label) {
    std::cout << "open " << label << '\n';
    return label;
}

extern "C" void silexNative_Resources_Resource_native_close(std::int64_t handle) {
    std::cout << "close " << handle << '\n';
}
