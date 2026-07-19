#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>

struct SilexNative_STD_Console_NativeKeyEvent {
    std::int64_t code;
    bool shift;
    bool control;
    bool alt;
    std::int64_t number;
    char* text_bytes;
    std::int64_t text_length;
};

#if defined(_WIN32)

#include <windows.h>

extern "C" std::int64_t silexNative_STD_Console_native_session_create();
extern "C" void silexNative_STD_Console_native_session_close(std::int64_t handle);
extern "C" bool silexNative_STD_Console_native_session_is_open(std::int64_t handle);
extern "C" void silexNative_STD_Console_native_session_read(
    std::int64_t handle,
    SilexNative_STD_Console_NativeKeyEvent* output
);
extern "C" bool silexNative_STD_Console_read_line(
    char** outputBytes,
    std::int64_t* outputLength
);

bool failsWith(const std::string& expected, const auto& operation) {
    try {
        operation();
    } catch (const std::runtime_error& error) {
        return std::string{error.what()}.find(expected) != std::string::npos;
    }
    return false;
}

int main() {
    const HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    const HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD inputMode = 0;
    DWORD outputMode = 0;
    if (GetConsoleMode(input, &inputMode) == 0 ||
        GetConsoleMode(output, &outputMode) == 0) return 0;
    const std::int64_t handle = silexNative_STD_Console_native_session_create();
    DWORD rawInput = 0;
    bool valid = GetConsoleMode(input, &rawInput) != 0;
    valid = valid && (rawInput & (ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT |
        ENABLE_PROCESSED_INPUT)) == 0;
    valid = valid && failsWith("Console.Session.create", [] {
        static_cast<void>(silexNative_STD_Console_native_session_create());
    });
    valid = valid && failsWith("Console.read_line", [] {
        char* bytes = nullptr;
        std::int64_t length = 0;
        static_cast<void>(silexNative_STD_Console_read_line(&bytes, &length));
    });
    silexNative_STD_Console_native_session_close(handle);
    DWORD restoredInput = 0;
    DWORD restoredOutput = 0;
    valid = valid && GetConsoleMode(input, &restoredInput) != 0 &&
        GetConsoleMode(output, &restoredOutput) != 0;
    valid = valid && restoredInput == inputMode && restoredOutput == outputMode;
    valid = valid && !silexNative_STD_Console_native_session_is_open(handle);
    valid = valid && failsWith("Console.Session.read_key", [handle] {
        SilexNative_STD_Console_NativeKeyEvent output{};
        silexNative_STD_Console_native_session_read(handle, &output);
    });
    silexNative_STD_Console_native_session_close(handle);
    return valid ? 0 : 10;
}

#else

#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

namespace {

// -----------------------------------------------------------------------------

extern "C" std::int64_t silexNative_STD_Console_native_session_create();
extern "C" void silexNative_STD_Console_native_session_close(std::int64_t handle);
extern "C" bool silexNative_STD_Console_native_session_is_open(std::int64_t handle);
extern "C" void silexNative_STD_Console_native_session_read(
    std::int64_t handle,
    SilexNative_STD_Console_NativeKeyEvent* output
);
extern "C" void silexNative_STD_Console_native_session_enter_alternate_screen(
    std::int64_t handle
);
extern "C" bool silexNative_STD_Console_read_line(
    char** outputBytes,
    std::int64_t* outputLength
);
extern "C" void silexNative_STD_Console_wait_for_enter();

bool sameMode(const termios& left, const termios& right);

bool failsWith(const std::string& expected, const auto& operation) {
    try {
        operation();
    } catch (const std::runtime_error& error) {
        return std::string{error.what()}.find(expected) != std::string::npos;
    }
    return false;
}

int testNativeContract() {
    int master = -1;
    int slave = -1;
    termios original{};
    if (openpty(&master, &slave, nullptr, nullptr, nullptr) != 0) return 20;
    const int savedInput = dup(STDIN_FILENO);
    const int savedOutput = dup(STDOUT_FILENO);
    if (savedInput < 0 || savedOutput < 0 || dup2(slave, STDIN_FILENO) < 0 ||
        dup2(slave, STDOUT_FILENO) < 0 || tcgetattr(slave, &original) != 0) return 21;
    const std::int64_t handle = silexNative_STD_Console_native_session_create();
    bool valid = silexNative_STD_Console_native_session_is_open(handle);
    const bool secondRejected = failsWith("Console.Session.create", [] {
        static_cast<void>(silexNative_STD_Console_native_session_create());
    });
    const bool lineRejected = failsWith("Console.read_line", [] {
        char* bytes = nullptr;
        std::int64_t length = 0;
        static_cast<void>(silexNative_STD_Console_read_line(&bytes, &length));
    });
    const bool waitRejected = failsWith("Console.wait_for_enter", [] {
        silexNative_STD_Console_wait_for_enter();
    });
    valid = valid && secondRejected && lineRejected && waitRejected;
    silexNative_STD_Console_native_session_close(handle);
    valid = valid && !silexNative_STD_Console_native_session_is_open(handle);
    const bool alternateRejected = failsWith(
        "Console.Session.enter_alternate_screen",
        [handle] {
        silexNative_STD_Console_native_session_enter_alternate_screen(handle);
    });
    const bool readRejected = failsWith("Console.Session.read_key", [handle] {
        SilexNative_STD_Console_NativeKeyEvent output{};
        silexNative_STD_Console_native_session_read(handle, &output);
    });
    valid = valid && alternateRejected && readRejected;
    silexNative_STD_Console_native_session_close(handle);
    termios restored{};
    valid = valid && tcgetattr(slave, &restored) == 0 && sameMode(original, restored);
    const bool descriptorsRestored = dup2(savedInput, STDIN_FILENO) >= 0 &&
        dup2(savedOutput, STDOUT_FILENO) >= 0;
    close(savedInput);
    close(savedOutput);
    close(slave);
    close(master);
    if (!valid || !descriptorsRestored) {
        std::fprintf(
            stderr,
            "native contract: second=%d line=%d wait=%d alternate=%d read=%d "
            "descriptors=%d\n",
            secondRejected,
            lineRejected,
            waitRejected,
            alternateRejected,
            readRejected,
            descriptorsRestored
        );
        std::fprintf(
            stderr,
            "termios: iflag=%lx/%lx oflag=%lx/%lx cflag=%lx/%lx "
            "lflag=%lx/%lx\n",
            static_cast<unsigned long>(original.c_iflag),
            static_cast<unsigned long>(restored.c_iflag),
            static_cast<unsigned long>(original.c_oflag),
            static_cast<unsigned long>(restored.c_oflag),
            static_cast<unsigned long>(original.c_cflag),
            static_cast<unsigned long>(restored.c_cflag),
            static_cast<unsigned long>(original.c_lflag),
            static_cast<unsigned long>(restored.c_lflag)
        );
    }
    return valid && descriptorsRestored ? 0 : 22;
}

// -----------------------------------------------------------------------------

bool sameMode(const termios& left, const termios& right) {
    tcflag_t leftLocal = left.c_lflag;
    tcflag_t rightLocal = right.c_lflag;
#if defined(PENDIN)
    // PENDIN is a transient kernel state, not a configurable terminal mode.
    leftLocal &= ~PENDIN;
    rightLocal &= ~PENDIN;
#endif
    return left.c_iflag == right.c_iflag && left.c_oflag == right.c_oflag &&
        left.c_cflag == right.c_cflag && leftLocal == rightLocal &&
        std::memcmp(left.c_cc, right.c_cc, sizeof(left.c_cc)) == 0;
}

bool writeAll(int descriptor, const char* bytes, std::size_t length) {
    std::size_t offset = 0;
    while (offset < length) {
        const ssize_t written = write(descriptor, bytes + offset, length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return false;
        offset += static_cast<std::size_t>(written);
    }
    return true;
}

bool readUntil(
    int descriptor,
    std::string& output,
    const std::string& marker,
    int timeoutMilliseconds
) {
    const auto deadline = std::chrono::steady_clock::now() +
        std::chrono::milliseconds(timeoutMilliseconds);
    while (output.find(marker) == std::string::npos) {
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
            deadline - std::chrono::steady_clock::now()
        ).count();
        if (remaining <= 0) return false;
        pollfd pollDescriptor{descriptor, POLLIN, 0};
        int status = 0;
        do {
            status = poll(&pollDescriptor, 1, static_cast<int>(remaining));
        } while (status < 0 && errno == EINTR);
        if (status <= 0) return false;
        char buffer[4096];
        const ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        output.append(buffer, static_cast<std::size_t>(count));
    }
    return true;
}

std::size_t occurrences(const std::string& text, const std::string& value) {
    std::size_t count = 0;
    std::size_t offset = 0;
    while ((offset = text.find(value, offset)) != std::string::npos) {
        ++count;
        offset += value.size();
    }
    return count;
}

bool containsExpectedEvents(const std::string& output) {
    constexpr const char* expected[] = {
        "true\r\ntrue\r\n\x1b[?1049h",
        "---:character:é\r\n",
        "---:arrow_up\r\n",
        "SC-:arrow_up\r\n",
        "-C-:character:a\r\n",
        "--A:character:z\r\n",
        "---:unknown:1B 5B 39 39 7E\r\n",
        "---:function\r\n24\r\n",
        "---:home\r\n",
        "---:end\r\n",
        "---:page_up\r\n",
        "---:page_down\r\n",
        "---:delete\r\n",
        "---:backspace\r\n",
        "---:tab\r\n",
        "---:enter\r\n",
        "true\r\n---:escape\r\n",
        "\x1b[?1049l\x1b[0m\x1b[?25hfalse\r\n",
    };
    std::size_t offset = 0;
    for (const char* fragment : expected) {
        const std::size_t found = output.find(fragment, offset);
        if (found == std::string::npos) return false;
        offset = found + std::strlen(fragment);
    }
    return occurrences(output, "\x1b[?1049h") == 1 &&
        occurrences(output, "\x1b[?1049l") == 1;
}

// -----------------------------------------------------------------------------

} // namespace

int main(int argumentCount, char** arguments) {
    if (argumentCount != 2) return 2;
    const int nativeContractStatus = testNativeContract();
    if (nativeContractStatus != 0) return nativeContractStatus;
    int master = -1;
    int slave = -1;
    termios original{};
    if (openpty(&master, &slave, nullptr, nullptr, nullptr) != 0 ||
        tcgetattr(slave, &original) != 0) return 3;
    const pid_t child = fork();
    if (child < 0) return 4;
    if (child == 0) {
        close(master);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, nullptr) < 0 ||
            dup2(slave, STDIN_FILENO) < 0 ||
            dup2(slave, STDOUT_FILENO) < 0 ||
            dup2(slave, STDERR_FILENO) < 0) _exit(120);
        if (slave > STDERR_FILENO) close(slave);
        execl(arguments[1], arguments[1], nullptr);
        _exit(121);
    }
    close(slave);
    std::string output;
    if (!readUntil(master, output, "\x1b[?1049h", 5000)) {
        kill(child, SIGKILL);
        waitpid(child, nullptr, 0);
        return 5;
    }
    constexpr char input[] =
        "é"
        "\x1b[A"
        "\x1b[1;6A"
        "\x01"
        "\x1b"
        "z"
        "\x1b[99~"
        "\x1b[45~"
        "\x1b[H"
        "\x1b[F"
        "\x1b[5~"
        "\x1b[6~"
        "\x1b[3~"
        "\x7f"
        "\x09"
        "\r\n"
        "\x1b";
    if (!writeAll(master, input, sizeof(input) - 1) ||
        !readUntil(master, output, "false\r\n", 5000)) {
        kill(child, SIGKILL);
        waitpid(child, nullptr, 0);
        return 6;
    }
    int status = 0;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 0) return 7;
    termios restored{};
    if (tcgetattr(master, &restored) != 0 || !sameMode(original, restored)) return 8;
    if (!containsExpectedEvents(output)) {
        std::fwrite(output.data(), 1, output.size(), stderr);
        return 9;
    }
    close(master);
    return 0;
}

#endif
