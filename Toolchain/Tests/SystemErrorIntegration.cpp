#include <cassert>
#include <cerrno>
#include <cstddef>
#include <cstdint>

extern "C" std::int64_t silexSystemErrorKindFromPosix(int code);
extern "C" std::int64_t silexSystemErrorKindFromWin32(std::uint32_t code);
extern "C" std::int64_t silexSystemErrorKindFromWinsock(int code);
extern "C" bool silexSystemOperationIsValid(const char* operation, std::size_t length);

int main() {
    assert(silexSystemErrorKindFromPosix(ENOENT) == 0);
    assert(silexSystemErrorKindFromPosix(EACCES) == 2);
    assert(silexSystemErrorKindFromPosix(EINTR) == 16);
    assert(silexSystemErrorKindFromPosix(0x3fffffff) == 30);
    assert(silexSystemErrorKindFromWin32(2) == 0);
    assert(silexSystemErrorKindFromWin32(5) == 2);
    assert(silexSystemErrorKindFromWin32(109) == 19);
    assert(silexSystemErrorKindFromWin32(0xffffffffU) == 30);
    assert(silexSystemErrorKindFromWinsock(10035) == 17);
    assert(silexSystemErrorKindFromWinsock(10048) == 21);
    assert(silexSystemErrorKindFromWinsock(10061) == 25);
    assert(silexSystemErrorKindFromWinsock(-1) == 30);
    assert(silexSystemOperationIsValid("file.open", 9));
    assert(silexSystemOperationIsValid("process_run2", 12));
    assert(!silexSystemOperationIsValid("", 0));
    assert(!silexSystemOperationIsValid("File.open", 9));
    assert(!silexSystemOperationIsValid("file-open", 9));
}
