#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

#if defined(_WIN32)
#include <windows.h>
#else
#include <cerrno>
#include <poll.h>
#include <termios.h>
#include <unistd.h>
#endif

#if !defined(SILEX_CONSOLE_STANDALONE_TEST)
#include <SilexNative/STD.h>
#endif

struct SilexNative_STD_Console_Session_NativeKeyEvent;

namespace {

struct NativeKeyEventOutput {
    std::int64_t code;
    bool shift;
    bool control;
    bool alt;
    std::int64_t number;
    char* textBytes;
    std::int64_t textLength;
};

#if defined(SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_CONSOLE_NATIVEKEYEVENT)
static_assert(
    sizeof(NativeKeyEventOutput) == sizeof(SilexNative_STD_Console_Session_NativeKeyEvent)
);
static_assert(
    alignof(NativeKeyEventOutput) == alignof(SilexNative_STD_Console_Session_NativeKeyEvent)
);
static_assert(
    offsetof(NativeKeyEventOutput, code) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, code)
);
static_assert(
    offsetof(NativeKeyEventOutput, shift) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, shift)
);
static_assert(
    offsetof(NativeKeyEventOutput, control) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, control)
);
static_assert(
    offsetof(NativeKeyEventOutput, alt) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, alt)
);
static_assert(
    offsetof(NativeKeyEventOutput, number) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, number)
);
static_assert(
    offsetof(NativeKeyEventOutput, textBytes) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, text_bytes)
);
static_assert(
    offsetof(NativeKeyEventOutput, textLength) ==
    offsetof(SilexNative_STD_Console_Session_NativeKeyEvent, text_length)
);
#endif

using Clock = std::chrono::steady_clock;

[[maybe_unused]] constexpr int kEscapeDelayMilliseconds = 25;

enum class EventCode : std::int64_t {
    timeout = 0,
    character = 1,
    enter = 2,
    escape = 3,
    tab = 4,
    backspace = 5,
    deleteKey = 6,
    arrowUp = 7,
    arrowDown = 8,
    arrowLeft = 9,
    arrowRight = 10,
    home = 11,
    end = 12,
    pageUp = 13,
    pageDown = 14,
    function = 15,
    unknown = 16,
};

struct Event {
    EventCode code = EventCode::timeout;
    bool shift = false;
    bool control = false;
    bool alt = false;
    std::int64_t number = 0;
    std::string text;
};

struct SessionState {
    std::int64_t handle = 0;
    bool open = false;
    bool alternateScreen = false;

#if defined(_WIN32)
    HANDLE input = INVALID_HANDLE_VALUE;
    HANDLE output = INVALID_HANDLE_VALUE;
    DWORD inputMode = 0;
    DWORD outputMode = 0;
    wchar_t pendingHighSurrogate = 0;
#else
    termios inputMode{};
    termios outputMode{};
    std::deque<unsigned char> bytes;
    std::optional<Clock::time_point> escapeStarted;
#endif
};

SessionState session;
std::atomic<bool> sessionActive = false;
std::int64_t nextHandle = 1;

// -----------------------------------------------------------------------------

[[noreturn]] void fail(const char* method, const char* detail) {
    throw std::runtime_error(
        std::string{"Console.Session."} + method + " failed: " + detail
    );
}

Clock::time_point deadlineFor(std::int64_t timeoutMilliseconds) {
    if (timeoutMilliseconds < 0) return Clock::time_point::max();
    const auto now = Clock::now();
    const auto maximum = std::chrono::duration_cast<std::chrono::milliseconds>(
        Clock::time_point::max() - now
    ).count();
    if (timeoutMilliseconds >= maximum) return Clock::time_point::max();
    return now + std::chrono::milliseconds(timeoutMilliseconds);
}

void requireOpen(std::int64_t handle, const char* method) {
    if (!session.open || session.handle != handle) {
        fail(method, "session is closed");
    }
}

char* copyText(const std::string& text, const char* method) {
    if (text.empty()) return nullptr;
    auto* result = static_cast<char*>(std::malloc(text.size()));
    if (result == nullptr) fail(method, "unable to allocate event text");
    std::memcpy(result, text.data(), text.size());
    return result;
}

void writeEvent(
    const Event& event,
    const char* method,
    NativeKeyEventOutput* output
) {
    char* text = copyText(event.text, method);
    output->code = static_cast<std::int64_t>(event.code);
    output->shift = event.shift;
    output->control = event.control;
    output->alt = event.alt;
    output->number = event.number;
    output->textBytes = text;
    output->textLength = static_cast<std::int64_t>(event.text.size());
}

[[maybe_unused]] std::string hexadecimal(
    const unsigned char* bytes,
    std::size_t length
) {
    constexpr char digits[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(length * 3);
    for (std::size_t index = 0; index < length; ++index) {
        if (index != 0) result.push_back(' ');
        result.push_back(digits[bytes[index] >> 4]);
        result.push_back(digits[bytes[index] & 0x0f]);
    }
    return result;
}

[[maybe_unused]] void setModifiers(Event& event, int parameter) {
    if (parameter < 2 || parameter > 8) return;
    const int value = parameter - 1;
    event.shift = (value & 1) != 0;
    event.alt = (value & 2) != 0;
    event.control = (value & 4) != 0;
}

// -----------------------------------------------------------------------------

#if defined(_WIN32)

void writeControl(const char* text, const char* method) {
    DWORD written = 0;
    const auto length = static_cast<DWORD>(std::strlen(text));
    if (WriteFile(session.output, text, length, &written, nullptr) == 0 ||
        written != length) {
        fail(method, "unable to write terminal control sequence");
    }
}

std::string utf8(std::uint32_t scalar) {
    std::string result;
    if (scalar <= 0x7f) {
        result.push_back(static_cast<char>(scalar));
    } else if (scalar <= 0x7ff) {
        result.push_back(static_cast<char>(0xc0 | (scalar >> 6)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    } else if (scalar <= 0xffff) {
        result.push_back(static_cast<char>(0xe0 | (scalar >> 12)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3f)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    } else {
        result.push_back(static_cast<char>(0xf0 | (scalar >> 18)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 12) & 0x3f)));
        result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3f)));
        result.push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    }
    return result;
}

void applyWindowsModifiers(Event& event, DWORD state) {
    event.shift = (state & SHIFT_PRESSED) != 0;
    event.control = (state & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED)) != 0;
    event.alt = (state & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) != 0;
}

Event windowsKeyEvent(const KEY_EVENT_RECORD& record) {
    Event event;
    applyWindowsModifiers(event, record.dwControlKeyState);
    const WORD key = record.wVirtualKeyCode;
    if (key == VK_RETURN) event.code = EventCode::enter;
    else if (key == VK_ESCAPE) event.code = EventCode::escape;
    else if (key == VK_TAB) event.code = EventCode::tab;
    else if (key == VK_BACK) event.code = EventCode::backspace;
    else if (key == VK_DELETE) event.code = EventCode::deleteKey;
    else if (key == VK_UP) event.code = EventCode::arrowUp;
    else if (key == VK_DOWN) event.code = EventCode::arrowDown;
    else if (key == VK_LEFT) event.code = EventCode::arrowLeft;
    else if (key == VK_RIGHT) event.code = EventCode::arrowRight;
    else if (key == VK_HOME) event.code = EventCode::home;
    else if (key == VK_END) event.code = EventCode::end;
    else if (key == VK_PRIOR) event.code = EventCode::pageUp;
    else if (key == VK_NEXT) event.code = EventCode::pageDown;
    else if (key >= VK_F1 && key <= VK_F24) {
        event.code = EventCode::function;
        event.number = key - VK_F1 + 1;
    } else if (record.uChar.UnicodeChar != 0) {
        const auto value = static_cast<std::uint16_t>(record.uChar.UnicodeChar);
        if (value >= 0xd800 && value <= 0xdbff) {
            session.pendingHighSurrogate = record.uChar.UnicodeChar;
            event.code = EventCode::timeout;
        } else if (value >= 0xdc00 && value <= 0xdfff &&
                   session.pendingHighSurrogate != 0) {
            const auto high = static_cast<std::uint16_t>(
                session.pendingHighSurrogate
            );
            session.pendingHighSurrogate = 0;
            event.code = EventCode::character;
            event.text = utf8(
                0x10000 + ((high - 0xd800) << 10) + (value - 0xdc00)
            );
        } else if (value >= 1 && value <= 26) {
            event.code = EventCode::character;
            event.control = true;
            event.text.assign(1, static_cast<char>('a' + value - 1));
        } else {
            event.code = EventCode::character;
            event.text = utf8(value);
        }
    } else {
        const unsigned char bytes[] = {
            static_cast<unsigned char>(key >> 8),
            static_cast<unsigned char>(key & 0xff),
        };
        event.code = EventCode::unknown;
        event.text = hexadecimal(bytes, sizeof(bytes));
    }
    return event;
}

Event readWindowsEvent(std::int64_t timeoutMilliseconds, const char* method) {
    const auto deadline = deadlineFor(timeoutMilliseconds);
    while (true) {
        DWORD timeout = INFINITE;
        if (timeoutMilliseconds >= 0) {
            const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
                deadline - Clock::now()
            ).count();
            if (remaining <= 0) timeout = 0;
            else timeout = static_cast<DWORD>(std::min<std::int64_t>(
                remaining,
                INFINITE - 1
            ));
        }
        const DWORD status = WaitForSingleObject(session.input, timeout);
        if (status == WAIT_TIMEOUT) {
            if (deadline <= Clock::now()) return Event{};
            continue;
        }
        if (status != WAIT_OBJECT_0) fail(method, "unable to wait for input");
        INPUT_RECORD record{};
        DWORD count = 0;
        if (ReadConsoleInputW(session.input, &record, 1, &count) == 0) {
            fail(method, "unable to read input");
        }
        if (count != 0 && record.EventType == KEY_EVENT &&
            record.Event.KeyEvent.bKeyDown != 0) {
            Event event = windowsKeyEvent(record.Event.KeyEvent);
            if (event.code != EventCode::timeout) return event;
        }
    }
}

#else

void writeControl(const char* text, const char* method) {
    const std::size_t length = std::strlen(text);
    std::size_t offset = 0;
    while (offset < length) {
        const ssize_t written = write(STDOUT_FILENO, text + offset, length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) fail(method, "unable to write terminal control sequence");
        offset += static_cast<std::size_t>(written);
    }
}

void consume(std::size_t count) {
    while (count-- != 0) session.bytes.pop_front();
    if (!session.bytes.empty() && session.bytes.front() == 0x1b) {
        session.escapeStarted = Clock::now();
    } else {
        session.escapeStarted.reset();
    }
}

Event unknown(std::size_t count) {
    std::string text;
    text.reserve(count * 3);
    for (std::size_t index = 0; index < count; ++index) {
        const unsigned char byte = session.bytes[index];
        if (!text.empty()) text.push_back(' ');
        constexpr char digits[] = "0123456789ABCDEF";
        text.push_back(digits[byte >> 4]);
        text.push_back(digits[byte & 0x0f]);
    }
    consume(count);
    Event event;
    event.code = EventCode::unknown;
    event.text = std::move(text);
    return event;
}

std::optional<std::size_t> scalarLength(std::size_t offset) {
    if (offset >= session.bytes.size()) return std::nullopt;
    const unsigned char first = session.bytes[offset];
    std::size_t length = 0;
    if (first <= 0x7f) length = 1;
    else if (first >= 0xc2 && first <= 0xdf) length = 2;
    else if (first >= 0xe0 && first <= 0xef) length = 3;
    else if (first >= 0xf0 && first <= 0xf4) length = 4;
    else return 0;
    if (session.bytes.size() - offset < length) return std::nullopt;
    for (std::size_t index = 1; index < length; ++index) {
        if ((session.bytes[offset + index] & 0xc0) != 0x80) return 0;
    }
    if (length == 3) {
        const unsigned char second = session.bytes[offset + 1];
        if ((first == 0xe0 && second < 0xa0) ||
            (first == 0xed && second >= 0xa0)) return 0;
    }
    if (length == 4) {
        const unsigned char second = session.bytes[offset + 1];
        if ((first == 0xf0 && second < 0x90) ||
            (first == 0xf4 && second >= 0x90)) return 0;
    }
    return length;
}

Event character(std::size_t offset, std::size_t length, bool alt) {
    Event event;
    event.code = EventCode::character;
    event.alt = alt;
    for (std::size_t index = 0; index < length; ++index) {
        event.text.push_back(static_cast<char>(session.bytes[offset + index]));
    }
    consume(offset + length);
    return event;
}

std::optional<Event> controlCharacter(unsigned char byte, bool alt) {
    Event event;
    event.alt = alt;
    if (byte == '\r' || byte == '\n') event.code = EventCode::enter;
    else if (byte == '\t') event.code = EventCode::tab;
    else if (byte == 0x08 || byte == 0x7f) event.code = EventCode::backspace;
    else if (byte >= 1 && byte <= 26) {
        event.code = EventCode::character;
        event.control = true;
        event.text.assign(1, static_cast<char>('a' + byte - 1));
    } else return std::nullopt;
    std::size_t count = alt ? 2 : 1;
    if (!alt && byte == '\r' && session.bytes.size() > 1 &&
        session.bytes[1] == '\n') {
        count = 2;
    }
    consume(count);
    return event;
}

int parseNumber(const std::string& text, std::size_t begin, std::size_t end) {
    int value = 0;
    if (begin == end) return 0;
    for (std::size_t index = begin; index < end; ++index) {
        if (text[index] < '0' || text[index] > '9') return -1;
        const int digit = text[index] - '0';
        if (value > (std::numeric_limits<int>::max() - digit) / 10) return -1;
        value = value * 10 + digit;
    }
    return value;
}

std::optional<Event> csiEvent(const std::string& sequence) {
    Event event;
    const char final = sequence.back();
    const std::string parameters = sequence.substr(2, sequence.size() - 3);
    std::size_t separator = parameters.rfind(';');
    const int modifier = separator == std::string::npos
        ? 1
        : parseNumber(parameters, separator + 1, parameters.size());
    if (modifier < 0) return std::nullopt;
    setModifiers(event, modifier);
    if (final == 'A') event.code = EventCode::arrowUp;
    else if (final == 'B') event.code = EventCode::arrowDown;
    else if (final == 'C') event.code = EventCode::arrowRight;
    else if (final == 'D') event.code = EventCode::arrowLeft;
    else if (final == 'H') event.code = EventCode::home;
    else if (final == 'F') event.code = EventCode::end;
    else if (final == 'P' || final == 'Q' || final == 'R' || final == 'S') {
        event.code = EventCode::function;
        event.number = final - 'P' + 1;
    } else if (final == '~') {
        const std::size_t numberEnd = separator == std::string::npos
            ? parameters.size()
            : separator;
        const int number = parseNumber(parameters, 0, numberEnd);
        if (number == 1 || number == 7) event.code = EventCode::home;
        else if (number == 3) event.code = EventCode::deleteKey;
        else if (number == 4 || number == 8) event.code = EventCode::end;
        else if (number == 5) event.code = EventCode::pageUp;
        else if (number == 6) event.code = EventCode::pageDown;
        else {
            constexpr int codes[] = {
                11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 23, 24,
                25, 26, 28, 29, 31, 32, 33, 34, 42, 43, 44, 45,
            };
            const auto found = std::find(std::begin(codes), std::end(codes), number);
            if (found == std::end(codes)) return std::nullopt;
            event.code = EventCode::function;
            event.number = found - std::begin(codes) + 1;
        }
    } else return std::nullopt;
    return event;
}

std::optional<Event> parseEvent(bool escapeExpired) {
    if (session.bytes.empty()) return std::nullopt;
    const unsigned char first = session.bytes.front();
    if (first != 0x1b) {
        if (const auto event = controlCharacter(first, false)) return event;
        const auto length = scalarLength(0);
        if (!length.has_value()) return std::nullopt;
        if (*length == 0) return unknown(1);
        return character(0, *length, false);
    }
    if (session.bytes.size() == 1) {
        if (!escapeExpired) return std::nullopt;
        consume(1);
        Event event;
        event.code = EventCode::escape;
        return event;
    }
    const unsigned char second = session.bytes[1];
    if (second != '[' && second != 'O') {
        if (const auto event = controlCharacter(second, true)) return event;
        const auto length = scalarLength(1);
        if (!length.has_value()) return escapeExpired
            ? std::optional<Event>{unknown(session.bytes.size())}
            : std::nullopt;
        if (*length == 0) return unknown(2);
        return character(1, *length, true);
    }
    if (second == 'O') {
        if (session.bytes.size() < 3) {
            return escapeExpired ? std::optional<Event>{unknown(session.bytes.size())}
                                 : std::nullopt;
        }
        Event event;
        const unsigned char final = session.bytes[2];
        if (final >= 'P' && final <= 'S') {
            event.code = EventCode::function;
            event.number = final - 'P' + 1;
        } else if (final == 'A') event.code = EventCode::arrowUp;
        else if (final == 'B') event.code = EventCode::arrowDown;
        else if (final == 'C') event.code = EventCode::arrowRight;
        else if (final == 'D') event.code = EventCode::arrowLeft;
        else if (final == 'H') event.code = EventCode::home;
        else if (final == 'F') event.code = EventCode::end;
        else return unknown(3);
        consume(3);
        return event;
    }
    std::size_t finalIndex = 2;
    while (finalIndex < session.bytes.size() &&
           (session.bytes[finalIndex] < 0x40 || session.bytes[finalIndex] > 0x7e)) {
        ++finalIndex;
    }
    if (finalIndex == session.bytes.size()) {
        return escapeExpired ? std::optional<Event>{unknown(session.bytes.size())}
                             : std::nullopt;
    }
    std::string sequence;
    sequence.reserve(finalIndex + 1);
    for (std::size_t index = 0; index <= finalIndex; ++index) {
        sequence.push_back(static_cast<char>(session.bytes[index]));
    }
    const auto event = csiEvent(sequence);
    if (!event.has_value()) return unknown(finalIndex + 1);
    consume(finalIndex + 1);
    return event;
}

bool waitForBytes(int timeoutMilliseconds, const char* method) {
    pollfd descriptor{STDIN_FILENO, POLLIN, 0};
    int status = 0;
    do {
        status = poll(&descriptor, 1, timeoutMilliseconds);
    } while (status < 0 && errno == EINTR);
    if (status < 0) fail(method, "unable to wait for input");
    if (status == 0) return false;
    unsigned char buffer[256];
    ssize_t count = 0;
    do {
        count = read(STDIN_FILENO, buffer, sizeof(buffer));
    } while (count < 0 && errno == EINTR);
    if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return false;
    if (count <= 0) fail(method, "standard input was closed");
    const bool wasEmpty = session.bytes.empty();
    for (ssize_t index = 0; index < count; ++index) session.bytes.push_back(buffer[index]);
    if (wasEmpty && session.bytes.front() == 0x1b) session.escapeStarted = Clock::now();
    return true;
}

Event readPosixEvent(std::int64_t timeoutMilliseconds, const char* method) {
    const auto deadline = deadlineFor(timeoutMilliseconds);
    while (true) {
        bool escapeExpired = false;
        if (session.escapeStarted.has_value()) {
            escapeExpired = Clock::now() - *session.escapeStarted >=
                std::chrono::milliseconds(kEscapeDelayMilliseconds);
        }
        if (const auto event = parseEvent(escapeExpired)) return *event;
        auto wake = deadline;
        if (session.escapeStarted.has_value()) {
            wake = std::min(
                wake,
                *session.escapeStarted + std::chrono::milliseconds(
                    kEscapeDelayMilliseconds
                )
            );
        }
        if (wake != Clock::time_point::max() && Clock::now() >= wake) {
            if (deadline <= wake) return Event{};
            continue;
        }
        int waitMilliseconds = -1;
        if (wake != Clock::time_point::max()) {
            const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
                wake - Clock::now()
            ).count();
            waitMilliseconds = static_cast<int>(std::min<std::int64_t>(
                std::max<std::int64_t>(0, remaining),
                std::numeric_limits<int>::max()
            ));
            if (waitMilliseconds == 0 && wake > Clock::now()) waitMilliseconds = 1;
        }
        if (!waitForBytes(waitMilliseconds, method) && deadline <= Clock::now()) {
            return Event{};
        }
    }
}

#endif

// -----------------------------------------------------------------------------

void restoreSession() {
    bool failed = false;
    if (session.alternateScreen) {
        try {
            writeControl("\x1b[?1049l", "close");
        } catch (...) {
            failed = true;
        }
    }
    try {
        writeControl("\x1b[0m\x1b[?25h", "close");
    } catch (...) {
        failed = true;
    }
#if defined(_WIN32)
    if (SetConsoleMode(session.input, session.inputMode) == 0) failed = true;
    if (SetConsoleMode(session.output, session.outputMode) == 0) failed = true;
#else
    if (tcsetattr(STDIN_FILENO, TCSANOW, &session.inputMode) != 0) failed = true;
    if (tcsetattr(STDOUT_FILENO, TCSANOW, &session.outputMode) != 0) failed = true;
#endif
    session.open = false;
    session.alternateScreen = false;
    sessionActive.store(false);
    if (failed) fail("close", "unable to restore terminal state");
}

std::int64_t createSession() {
    if (sessionActive.load()) fail("create", "a session is already active");
#if defined(_WIN32)
    const HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    const HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD inputMode = 0;
    DWORD outputMode = 0;
    if (input == INVALID_HANDLE_VALUE || output == INVALID_HANDLE_VALUE ||
        GetConsoleMode(input, &inputMode) == 0 ||
        GetConsoleMode(output, &outputMode) == 0) {
        fail("create", "standard input and output must be interactive");
    }
    DWORD rawInput = inputMode;
    rawInput &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT |
                  ENABLE_QUICK_EDIT_MODE);
    rawInput |= ENABLE_EXTENDED_FLAGS;
    DWORD rawOutput = outputMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (SetConsoleMode(input, rawInput) == 0 ||
        SetConsoleMode(output, rawOutput) == 0) {
        SetConsoleMode(input, inputMode);
        SetConsoleMode(output, outputMode);
        fail("create", "unable to activate raw console mode");
    }
    session.input = input;
    session.output = output;
    session.inputMode = inputMode;
    session.outputMode = outputMode;
#else
    if (isatty(STDIN_FILENO) != 1 || isatty(STDOUT_FILENO) != 1 ||
        tcgetattr(STDIN_FILENO, &session.inputMode) != 0 ||
        tcgetattr(STDOUT_FILENO, &session.outputMode) != 0) {
        fail("create", "standard input and output must be interactive");
    }
    termios raw = session.inputMode;
    raw.c_iflag &= ~(
        IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL |
        IXON | IXOFF
    );
#if defined(IXANY)
    raw.c_iflag &= ~IXANY;
#endif
    raw.c_lflag &= ~(ECHO | ECHONL | ICANON | IEXTEN | ISIG);
    raw.c_cflag &= ~(CSIZE | PARENB);
    raw.c_cflag |= CS8;
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
        fail("create", "unable to activate raw terminal mode");
    }
    session.bytes.clear();
    session.escapeStarted.reset();
#endif
    session.handle = nextHandle++;
    session.open = true;
    session.alternateScreen = false;
    sessionActive.store(true);
    return session.handle;
}

} // namespace

extern "C" bool silexConsoleSessionIsActive() {
    return sessionActive.load();
}

extern "C" std::int64_t silexNative_STD_Console_Session_native_session_create() {
    return createSession();
}

extern "C" void silexNative_STD_Console_Session_native_session_close(std::int64_t handle) {
    if (!session.open || session.handle != handle) return;
    restoreSession();
}

extern "C" bool silexNative_STD_Console_Session_native_session_is_open(std::int64_t handle) {
    return session.open && session.handle == handle;
}

extern "C" void silexNative_STD_Console_Session_native_session_read(
    std::int64_t handle,
    SilexNative_STD_Console_Session_NativeKeyEvent* output
) {
    requireOpen(handle, "read_key");
#if defined(_WIN32)
    const Event event = readWindowsEvent(-1, "read_key");
#else
    const Event event = readPosixEvent(-1, "read_key");
#endif
    writeEvent(event, "read_key", reinterpret_cast<NativeKeyEventOutput*>(output));
}

extern "C" bool silexNative_STD_Console_Session_native_session_poll(
    std::int64_t handle,
    std::int64_t timeoutMilliseconds,
    SilexNative_STD_Console_Session_NativeKeyEvent* output
) {
    requireOpen(handle, "poll_key");
    if (timeoutMilliseconds < 0) fail("poll_key", "timeout must be non-negative");
#if defined(_WIN32)
    const Event event = readWindowsEvent(timeoutMilliseconds, "poll_key");
#else
    const Event event = readPosixEvent(timeoutMilliseconds, "poll_key");
#endif
    if (event.code == EventCode::timeout) return false;
    writeEvent(event, "poll_key", reinterpret_cast<NativeKeyEventOutput*>(output));
    return true;
}

extern "C" void silexNative_STD_Console_Session_native_session_enter_alternate_screen(
    std::int64_t handle
) {
    requireOpen(handle, "enter_alternate_screen");
    if (session.alternateScreen) return;
    writeControl("\x1b[?1049h", "enter_alternate_screen");
    session.alternateScreen = true;
}

extern "C" void silexNative_STD_Console_Session_native_session_leave_alternate_screen(
    std::int64_t handle
) {
    requireOpen(handle, "leave_alternate_screen");
    if (!session.alternateScreen) return;
    writeControl("\x1b[?1049l", "leave_alternate_screen");
    session.alternateScreen = false;
}
