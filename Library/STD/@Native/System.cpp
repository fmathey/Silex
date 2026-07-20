#include <cerrno>
#include <cstddef>
#include <cstdint>

namespace {

enum class ErrorKind : std::int64_t {
    not_found,
    already_exists,
    permission_denied,
    invalid_input,
    invalid_data,
    name_too_long,
    unexpected_end,
    limit_exceeded,
    not_directory,
    is_directory,
    directory_not_empty,
    resource_busy,
    resource_exhausted,
    too_many_open_files,
    read_only_file_system,
    cross_device,
    interrupted,
    would_block,
    timed_out,
    broken_pipe,
    message_too_large,
    address_in_use,
    address_unavailable,
    network_unreachable,
    host_unreachable,
    connection_refused,
    connection_aborted,
    connection_reset,
    not_connected,
    unsupported,
    other,
};

constexpr std::int64_t raw(ErrorKind kind) {
    return static_cast<std::int64_t>(kind);
}

std::int64_t posixErrorKind(int code) {
    switch (code) {
#ifdef ENOENT
        case ENOENT: return raw(ErrorKind::not_found);
#endif
#ifdef EEXIST
        case EEXIST: return raw(ErrorKind::already_exists);
#endif
#ifdef EACCES
        case EACCES: return raw(ErrorKind::permission_denied);
#endif
#if defined(EPERM) && (!defined(EACCES) || EPERM != EACCES)
        case EPERM: return raw(ErrorKind::permission_denied);
#endif
#ifdef EINVAL
        case EINVAL: return raw(ErrorKind::invalid_input);
#endif
#ifdef EILSEQ
        case EILSEQ: return raw(ErrorKind::invalid_data);
#endif
#ifdef ENAMETOOLONG
        case ENAMETOOLONG: return raw(ErrorKind::name_too_long);
#endif
#ifdef EFBIG
        case EFBIG: return raw(ErrorKind::limit_exceeded);
#endif
#ifdef EOVERFLOW
        case EOVERFLOW: return raw(ErrorKind::limit_exceeded);
#endif
#ifdef ENOTDIR
        case ENOTDIR: return raw(ErrorKind::not_directory);
#endif
#ifdef EISDIR
        case EISDIR: return raw(ErrorKind::is_directory);
#endif
#ifdef ENOTEMPTY
        case ENOTEMPTY: return raw(ErrorKind::directory_not_empty);
#endif
#ifdef EBUSY
        case EBUSY: return raw(ErrorKind::resource_busy);
#endif
#ifdef ENOMEM
        case ENOMEM: return raw(ErrorKind::resource_exhausted);
#endif
#ifdef ENOBUFS
        case ENOBUFS: return raw(ErrorKind::resource_exhausted);
#endif
#ifdef EMFILE
        case EMFILE: return raw(ErrorKind::too_many_open_files);
#endif
#if defined(ENFILE) && (!defined(EMFILE) || ENFILE != EMFILE)
        case ENFILE: return raw(ErrorKind::too_many_open_files);
#endif
#ifdef EROFS
        case EROFS: return raw(ErrorKind::read_only_file_system);
#endif
#ifdef EXDEV
        case EXDEV: return raw(ErrorKind::cross_device);
#endif
#ifdef EINTR
        case EINTR: return raw(ErrorKind::interrupted);
#endif
#ifdef EAGAIN
        case EAGAIN: return raw(ErrorKind::would_block);
#endif
#if defined(EWOULDBLOCK) && (!defined(EAGAIN) || EWOULDBLOCK != EAGAIN)
        case EWOULDBLOCK: return raw(ErrorKind::would_block);
#endif
#ifdef ETIMEDOUT
        case ETIMEDOUT: return raw(ErrorKind::timed_out);
#endif
#ifdef EPIPE
        case EPIPE: return raw(ErrorKind::broken_pipe);
#endif
#ifdef EMSGSIZE
        case EMSGSIZE: return raw(ErrorKind::message_too_large);
#endif
#ifdef EADDRINUSE
        case EADDRINUSE: return raw(ErrorKind::address_in_use);
#endif
#ifdef EADDRNOTAVAIL
        case EADDRNOTAVAIL: return raw(ErrorKind::address_unavailable);
#endif
#ifdef ENETUNREACH
        case ENETUNREACH: return raw(ErrorKind::network_unreachable);
#endif
#ifdef EHOSTUNREACH
        case EHOSTUNREACH: return raw(ErrorKind::host_unreachable);
#endif
#ifdef ECONNREFUSED
        case ECONNREFUSED: return raw(ErrorKind::connection_refused);
#endif
#ifdef ECONNABORTED
        case ECONNABORTED: return raw(ErrorKind::connection_aborted);
#endif
#ifdef ECONNRESET
        case ECONNRESET: return raw(ErrorKind::connection_reset);
#endif
#ifdef ENOTCONN
        case ENOTCONN: return raw(ErrorKind::not_connected);
#endif
#ifdef ENOTSUP
        case ENOTSUP: return raw(ErrorKind::unsupported);
#endif
#if defined(EOPNOTSUPP) && (!defined(ENOTSUP) || EOPNOTSUPP != ENOTSUP)
        case EOPNOTSUPP: return raw(ErrorKind::unsupported);
#endif
        default: return raw(ErrorKind::other);
    }
}

std::int64_t win32ErrorKind(std::uint32_t code) {
    switch (code) {
        case 2: case 3: return raw(ErrorKind::not_found);
        case 80: case 183: return raw(ErrorKind::already_exists);
        case 5: return raw(ErrorKind::permission_denied);
        case 87: return raw(ErrorKind::invalid_input);
        case 13: case 23: return raw(ErrorKind::invalid_data);
        case 206: return raw(ErrorKind::name_too_long);
        case 38: return raw(ErrorKind::unexpected_end);
        case 111: return raw(ErrorKind::limit_exceeded);
        case 267: return raw(ErrorKind::not_directory);
        case 145: return raw(ErrorKind::directory_not_empty);
        case 32: case 170: return raw(ErrorKind::resource_busy);
        case 8: case 14: return raw(ErrorKind::resource_exhausted);
        case 19: return raw(ErrorKind::read_only_file_system);
        case 17: return raw(ErrorKind::cross_device);
        case 995: return raw(ErrorKind::interrupted);
        case 997: return raw(ErrorKind::would_block);
        case 121: case 1460: return raw(ErrorKind::timed_out);
        case 109: case 232: return raw(ErrorKind::broken_pipe);
        case 50: case 120: return raw(ErrorKind::unsupported);
        default: return raw(ErrorKind::other);
    }
}

std::int64_t winsockErrorKind(int code) {
    switch (code) {
        case 10004: return raw(ErrorKind::interrupted);
        case 10013: return raw(ErrorKind::permission_denied);
        case 10014: case 10022: return raw(ErrorKind::invalid_input);
        case 10024: return raw(ErrorKind::too_many_open_files);
        case 10035: case 10036: case 10037: return raw(ErrorKind::would_block);
        case 10040: return raw(ErrorKind::message_too_large);
        case 10047: case 10093: return raw(ErrorKind::unsupported);
        case 10048: return raw(ErrorKind::address_in_use);
        case 10049: return raw(ErrorKind::address_unavailable);
        case 10050: case 10051: return raw(ErrorKind::network_unreachable);
        case 10053: return raw(ErrorKind::connection_aborted);
        case 10054: return raw(ErrorKind::connection_reset);
        case 10057: return raw(ErrorKind::not_connected);
        case 10060: return raw(ErrorKind::timed_out);
        case 10061: return raw(ErrorKind::connection_refused);
        case 10064: case 10065: return raw(ErrorKind::host_unreachable);
        default: return raw(ErrorKind::other);
    }
}

} // namespace

extern "C" std::int64_t silexSystemErrorKindFromPosix(int code) { return posixErrorKind(code); }
extern "C" std::int64_t silexSystemErrorKindFromWin32(std::uint32_t code) { return win32ErrorKind(code); }
extern "C" std::int64_t silexSystemErrorKindFromWinsock(int code) { return winsockErrorKind(code); }
extern "C" bool silexSystemOperationIsValid(const char* operation, std::size_t length) {
    if (operation == nullptr || length == 0) return false;
    for (std::size_t index = 0; index < length; ++index) {
        const unsigned char character = static_cast<unsigned char>(operation[index]);
        if (!((character >= 'a' && character <= 'z') ||
              (character >= '0' && character <= '9') || character == '.' || character == '_')) {
            return false;
        }
    }
    return true;
}
