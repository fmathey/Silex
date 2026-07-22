#include <cstdint>

extern "C" std::uint64_t silexNative_STD_Collections_Hashing_native_hash_str(
    const char* bytes,
    std::int64_t length
) {
    constexpr std::uint64_t offset = 14695981039346656037ULL;
    constexpr std::uint64_t prime = 1099511628211ULL;
    std::uint64_t hash = offset;
    for (std::int64_t index = 0; index < length; ++index) {
        hash ^= static_cast<unsigned char>(bytes[index]);
        hash *= prime;
    }
    return hash;
}
