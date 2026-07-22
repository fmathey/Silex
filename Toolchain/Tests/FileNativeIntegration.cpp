#include <cstdio>
#include <cstdlib>
#include <string>

#include "../../Library/STD/@Native/File.cpp"

namespace {

SilexNative_STD_File* createFile(const std::string& path) {
    SilexNative_STD_File_native_openResult result{};
    silexNative_STD_File_native_open(
        path.data(), static_cast<std::int64_t>(path.size()), 3, 5, false, &result
    );
    if (result.tag != SilexNative_STD_File_native_openResultTag_success) {
        std::free(result.failure_value.detail_bytes);
        return nullptr;
    }
    return result.success_value;
}

bool automaticReturn(const std::string& path) {
    auto* file = createFile(path);
    if (file == nullptr) return false;
    silexNative_STD_File_discard_file(file);
    return true;
}

} // namespace

int main(int argumentCount, char** arguments) {
    if (argumentCount != 2) return 2;
    const std::string path = arguments[1];
    std::remove(path.c_str());
    silexFileNativeResetCounts();

    if (!automaticReturn(path) || silexFileNativeLiveCount() != 0 ||
        silexFileNativeClosedCount() != 1) return 3;

    auto* explicitFile = createFile(path);
    if (explicitFile == nullptr || silexFileNativeLiveCount() != 1) return 4;
    SilexNative_STD_File_native_closeResult closeResult{};
    silexNative_STD_File_native_close(explicitFile, &closeResult);
    if (closeResult.tag != SilexNative_STD_File_native_closeResultTag_success ||
        silexFileNativeLiveCount() != 0 || silexFileNativeClosedCount() != 2) return 5;

    auto* failingFile = createFile(path);
    if (failingFile == nullptr) return 6;
#if defined(_WIN32)
    if (!CloseHandle(failingFile->handle)) return 7;
#else
    if (::close(failingFile->descriptor) != 0) return 7;
#endif
    SilexNative_STD_File_native_closeResult failedClose{};
    silexNative_STD_File_native_close(failingFile, &failedClose);
    const bool failureConsumed =
        failedClose.tag == SilexNative_STD_File_native_closeResultTag_failure &&
        silexFileNativeLiveCount() == 0 && silexFileNativeClosedCount() == 3;
    std::free(failedClose.failure_value.detail_bytes);
    std::remove(path.c_str());
    return failureConsumed ? 0 : 8;
}
