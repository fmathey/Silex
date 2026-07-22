#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <system_error>

#if defined(_WIN32)
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

struct SilexNative_STD_File {
#if defined(_WIN32)
    HANDLE handle;
#else
    int descriptor;
#endif
};

struct SilexNative_STD_File_NativeFailure {
    std::int64_t kind;
    char* detail_bytes;
    std::int64_t detail_length;
};

#define SILEX_FILE_RESULT(NAME, SUCCESS_FIELD)                                      \
    enum SilexNative_STD_File_##NAME##ResultTag {                                   \
        SilexNative_STD_File_##NAME##ResultTag_success = 0,                         \
        SilexNative_STD_File_##NAME##ResultTag_failure = 1                          \
    };                                                                               \
    struct SilexNative_STD_File_##NAME##Result {                                    \
        SilexNative_STD_File_##NAME##ResultTag tag;                                 \
        SUCCESS_FIELD                                                                \
        SilexNative_STD_File_NativeFailure failure_value;                           \
    }

SILEX_FILE_RESULT(native_open, SilexNative_STD_File* success_value;);
SILEX_FILE_RESULT(native_close, );
SILEX_FILE_RESULT(native_read, std::int64_t success_value;);
SILEX_FILE_RESULT(native_write, std::int64_t success_value;);
SILEX_FILE_RESULT(native_flush, );
SILEX_FILE_RESULT(native_seek, std::int64_t success_value;);
SILEX_FILE_RESULT(native_position, std::int64_t success_value;);
SILEX_FILE_RESULT(native_length, std::int64_t success_value;);
SILEX_FILE_RESULT(native_set_length, );

#undef SILEX_FILE_RESULT

extern "C" std::int64_t silexSystemErrorKindFromPosix(int code);
extern "C" std::int64_t silexSystemErrorKindFromWin32(std::uint32_t code);

namespace {

std::atomic<std::int64_t> liveFiles = 0;
std::atomic<std::int64_t> closedFiles = 0;

char* copyText(const std::string& text) {
    if (text.empty()) return nullptr;
    auto* result = static_cast<char*>(std::malloc(text.size()));
    if (result != nullptr) std::memcpy(result, text.data(), text.size());
    return result;
}

template <typename Result, typename Tag>
void fail(Result* output, Tag tag, std::int64_t kind, const std::string& detail) {
    output->tag = tag;
    output->failure_value.kind = kind;
    output->failure_value.detail_bytes = copyText(detail);
    output->failure_value.detail_length = static_cast<std::int64_t>(detail.size());
}

#if defined(_WIN32)

std::int64_t errorKind(DWORD code) {
    return silexSystemErrorKindFromWin32(code);
}

std::string errorDetail(DWORD code) {
    return std::system_category().message(static_cast<int>(code));
}

bool windowsPath(const char* bytes, std::int64_t length, std::wstring& output) {
    if (length <= 0 || std::memchr(bytes, 0, static_cast<std::size_t>(length)) != nullptr) {
        SetLastError(ERROR_INVALID_NAME);
        return false;
    }
    if (length > std::numeric_limits<int>::max()) {
        SetLastError(ERROR_FILENAME_EXCED_RANGE);
        return false;
    }
    const auto required = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, bytes, static_cast<int>(length), nullptr, 0
    );
    if (required <= 0) return false;
    output.resize(static_cast<std::size_t>(required));
    if (MultiByteToWideChar(
            CP_UTF8, MB_ERR_INVALID_CHARS, bytes, static_cast<int>(length),
            output.data(), required
        ) != required) return false;
    return true;
}

void closeDiscard(SilexNative_STD_File* file) {
    if (file == nullptr) return;
    CloseHandle(file->handle);
    delete file;
    --liveFiles;
    ++closedFiles;
}

#else

std::int64_t errorKind(int code) {
    return silexSystemErrorKindFromPosix(code);
}

std::string errorDetail(int code) {
    return std::system_category().message(code);
}

bool posixPath(const char* bytes, std::int64_t length, std::string& output) {
    if (length <= 0 || std::memchr(bytes, 0, static_cast<std::size_t>(length)) != nullptr) {
        errno = EINVAL;
        return false;
    }
    output.assign(bytes, static_cast<std::size_t>(length));
    return true;
}

void closeDiscard(SilexNative_STD_File* file) {
    if (file == nullptr) return;
    ::close(file->descriptor);
    delete file;
    --liveFiles;
    ++closedFiles;
}

#endif

} // namespace

extern "C" void silexNative_STD_File_discard_file(SilexNative_STD_File* file) {
    closeDiscard(file);
}

extern "C" void silexNative_STD_File_native_open(
    const char* pathBytes,
    std::int64_t pathLength,
    std::int64_t access,
    std::int64_t creation,
    bool append,
    SilexNative_STD_File_native_openResult* output
) {
#if defined(_WIN32)
    std::wstring path;
    if (!windowsPath(pathBytes, pathLength, path)) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_openResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    DWORD desiredAccess = 0;
    if (access == 1) desiredAccess = GENERIC_READ;
    if (access == 2) desiredAccess = append ? FILE_APPEND_DATA : GENERIC_WRITE;
    if (access == 3) desiredAccess = GENERIC_READ | (append ? FILE_APPEND_DATA : GENERIC_WRITE);
    DWORD disposition = OPEN_EXISTING;
    if (creation == 2) disposition = CREATE_NEW;
    if (creation == 3) disposition = OPEN_ALWAYS;
    if (creation == 4) disposition = TRUNCATE_EXISTING;
    if (creation == 5) disposition = CREATE_ALWAYS;
    const HANDLE handle = CreateFileW(
        path.c_str(), desiredAccess,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, disposition, FILE_ATTRIBUTE_NORMAL, nullptr
    );
    if (handle == INVALID_HANDLE_VALUE) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_openResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->tag = SilexNative_STD_File_native_openResultTag_success;
    output->success_value = new SilexNative_STD_File{handle};
#else
    std::string path;
    if (!posixPath(pathBytes, pathLength, path)) {
        const auto code = errno;
        fail(output, SilexNative_STD_File_native_openResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    int flags = access == 1 ? O_RDONLY : (access == 2 ? O_WRONLY : O_RDWR);
    if (creation == 2) flags |= O_CREAT | O_EXCL;
    if (creation == 3) flags |= O_CREAT;
    if (creation == 4) flags |= O_TRUNC;
    if (creation == 5) flags |= O_CREAT | O_TRUNC;
    if (append) flags |= O_APPEND;
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    const int descriptor = ::open(path.c_str(), flags, 0666);
    if (descriptor < 0) {
        const auto code = errno;
        fail(output, SilexNative_STD_File_native_openResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->tag = SilexNative_STD_File_native_openResultTag_success;
    output->success_value = new SilexNative_STD_File{descriptor};
#endif
    ++liveFiles;
}

extern "C" void silexNative_STD_File_native_close(
    SilexNative_STD_File* file,
    SilexNative_STD_File_native_closeResult* output
) {
#if defined(_WIN32)
    const bool succeeded = CloseHandle(file->handle) != 0;
    const auto code = succeeded ? ERROR_SUCCESS : GetLastError();
#else
    const bool succeeded = ::close(file->descriptor) == 0;
    const auto code = succeeded ? 0 : errno;
#endif
    delete file;
    --liveFiles;
    ++closedFiles;
    if (!succeeded) {
        fail(output, SilexNative_STD_File_native_closeResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->tag = SilexNative_STD_File_native_closeResultTag_success;
}

extern "C" void silexNative_STD_File_native_read(
    SilexNative_STD_File* file,
    std::uint8_t* buffer,
    std::int64_t count,
    SilexNative_STD_File_native_readResult* output
) {
#if defined(_WIN32)
    const auto requested = static_cast<DWORD>(std::min<std::uint64_t>(count, MAXDWORD));
    DWORD readCount = 0;
    if (!ReadFile(file->handle, buffer, requested, &readCount, nullptr)) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_readResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = readCount;
#else
    const auto readCount = ::read(file->descriptor, buffer, static_cast<std::size_t>(count));
    if (readCount < 0) {
        const auto code = errno;
        fail(output, SilexNative_STD_File_native_readResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = static_cast<std::int64_t>(readCount);
#endif
    output->tag = SilexNative_STD_File_native_readResultTag_success;
}

extern "C" void silexNative_STD_File_native_write(
    SilexNative_STD_File* file,
    const std::uint8_t* buffer,
    std::int64_t count,
    SilexNative_STD_File_native_writeResult* output
) {
#if defined(_WIN32)
    const auto requested = static_cast<DWORD>(std::min<std::uint64_t>(count, MAXDWORD));
    DWORD written = 0;
    if (!WriteFile(file->handle, buffer, requested, &written, nullptr)) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_writeResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = written;
#else
    const auto written = ::write(file->descriptor, buffer, static_cast<std::size_t>(count));
    if (written < 0) {
        const auto code = errno;
        fail(output, SilexNative_STD_File_native_writeResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = static_cast<std::int64_t>(written);
#endif
    output->tag = SilexNative_STD_File_native_writeResultTag_success;
}

extern "C" void silexNative_STD_File_native_flush(
    SilexNative_STD_File* file,
    SilexNative_STD_File_native_flushResult* output
) {
#if defined(_WIN32)
    if (!FlushFileBuffers(file->handle)) {
        const auto code = GetLastError();
#else
    if (::fsync(file->descriptor) != 0) {
        const auto code = errno;
#endif
        fail(output, SilexNative_STD_File_native_flushResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->tag = SilexNative_STD_File_native_flushResultTag_success;
}

extern "C" void silexNative_STD_File_native_seek(
    SilexNative_STD_File* file,
    std::int64_t offset,
    std::int64_t from,
    SilexNative_STD_File_native_seekResult* output
) {
#if defined(_WIN32)
    LARGE_INTEGER distance{};
    distance.QuadPart = offset;
    LARGE_INTEGER position{};
    const DWORD origin = from == 1 ? FILE_BEGIN : (from == 2 ? FILE_CURRENT : FILE_END);
    if (!SetFilePointerEx(file->handle, distance, &position, origin) || position.QuadPart < 0) {
        const auto code = GetLastError() == ERROR_SUCCESS ? ERROR_NEGATIVE_SEEK : GetLastError();
        fail(output, SilexNative_STD_File_native_seekResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = position.QuadPart;
#else
    const int origin = from == 1 ? SEEK_SET : (from == 2 ? SEEK_CUR : SEEK_END);
    const auto position = ::lseek(file->descriptor, static_cast<off_t>(offset), origin);
    if (position < 0 || static_cast<std::uintmax_t>(position) >
            static_cast<std::uintmax_t>(std::numeric_limits<std::int64_t>::max())) {
        const auto code = errno == 0 ? EOVERFLOW : errno;
        fail(output, SilexNative_STD_File_native_seekResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = static_cast<std::int64_t>(position);
#endif
    output->tag = SilexNative_STD_File_native_seekResultTag_success;
}

extern "C" void silexNative_STD_File_native_position(
    SilexNative_STD_File* file,
    SilexNative_STD_File_native_positionResult* output
) {
#if defined(_WIN32)
    LARGE_INTEGER distance{};
    LARGE_INTEGER position{};
    if (!SetFilePointerEx(file->handle, distance, &position, FILE_CURRENT)) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_positionResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = position.QuadPart;
#else
    const auto position = ::lseek(file->descriptor, 0, SEEK_CUR);
    if (position < 0 || static_cast<std::uintmax_t>(position) >
            static_cast<std::uintmax_t>(std::numeric_limits<std::int64_t>::max())) {
        const auto code = errno == 0 ? EOVERFLOW : errno;
        fail(output, SilexNative_STD_File_native_positionResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = static_cast<std::int64_t>(position);
#endif
    output->tag = SilexNative_STD_File_native_positionResultTag_success;
}

extern "C" void silexNative_STD_File_native_length(
    SilexNative_STD_File* file,
    SilexNative_STD_File_native_lengthResult* output
) {
#if defined(_WIN32)
    LARGE_INTEGER length{};
    if (!GetFileSizeEx(file->handle, &length) || length.QuadPart < 0) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_lengthResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = length.QuadPart;
#else
    struct stat status {};
    if (::fstat(file->descriptor, &status) != 0 || status.st_size < 0 ||
        static_cast<std::uintmax_t>(status.st_size) >
            static_cast<std::uintmax_t>(std::numeric_limits<std::int64_t>::max())) {
        const auto code = errno == 0 ? EOVERFLOW : errno;
        fail(output, SilexNative_STD_File_native_lengthResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    output->success_value = static_cast<std::int64_t>(status.st_size);
#endif
    output->tag = SilexNative_STD_File_native_lengthResultTag_success;
}

extern "C" void silexNative_STD_File_native_set_length(
    SilexNative_STD_File* file,
    std::int64_t length,
    SilexNative_STD_File_native_set_lengthResult* output
) {
#if defined(_WIN32)
    LARGE_INTEGER zero{};
    LARGE_INTEGER original{};
    LARGE_INTEGER target{};
    target.QuadPart = length;
    if (!SetFilePointerEx(file->handle, zero, &original, FILE_CURRENT) ||
        !SetFilePointerEx(file->handle, target, nullptr, FILE_BEGIN) ||
        !SetEndOfFile(file->handle)) {
        const auto code = GetLastError();
        SetFilePointerEx(file->handle, original, nullptr, FILE_BEGIN);
        fail(output, SilexNative_STD_File_native_set_lengthResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
    if (!SetFilePointerEx(file->handle, original, nullptr, FILE_BEGIN)) {
        const auto code = GetLastError();
        fail(output, SilexNative_STD_File_native_set_lengthResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
#else
    if (::ftruncate(file->descriptor, static_cast<off_t>(length)) != 0) {
        const auto code = errno;
        fail(output, SilexNative_STD_File_native_set_lengthResultTag_failure,
            errorKind(code), errorDetail(code));
        return;
    }
#endif
    output->tag = SilexNative_STD_File_native_set_lengthResultTag_success;
}

extern "C" std::int64_t silexFileNativeLiveCount() {
    return liveFiles.load();
}

extern "C" std::int64_t silexFileNativeClosedCount() {
    return closedFiles.load();
}

extern "C" void silexFileNativeResetCounts() {
    liveFiles.store(0);
    closedFiles.store(0);
}
