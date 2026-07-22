# System

```sx
use STD.System

let error = System.Error(
    kind:System.ErrorKind.not_found(),
    operation:"example",
    subject:null,
    detail:"missing"
)
```

`STD.System` defines the portable recoverable error shared by system APIs.

`ErrorKind` is the stable classification intended for control flow. It contains
`not_found`, `already_exists`, `permission_denied`, `invalid_input`,
`invalid_data`, `name_too_long`, `unexpected_end`, `limit_exceeded`,
`not_directory`, `is_directory`, `directory_not_empty`, `resource_busy`,
`resource_exhausted`, `too_many_open_files`, `read_only_file_system`,
`cross_device`, `interrupted`, `would_block`, `timed_out`, `broken_pipe`,
`message_too_large`, `address_in_use`, `address_unavailable`,
`network_unreachable`, `host_unreachable`, `connection_refused`,
`connection_aborted`, `connection_reset`, `not_connected`, `unsupported`, and
`other`. Unknown native codes map to `other`.

`Error` has four immutable public fields:

- `kind:ErrorKind` is stable and may be matched by programs.
- `operation:str` is a stable non-empty producer identifier made of lowercase
  ASCII letters, digits, `.` and `_`, such as `file.open` or `tcp.connect`.
- `subject:str?` is the relevant public path, host, variable name, or other
  object when one exists.
- `detail:str` is a non-empty UTF-8 diagnostic for humans. Its wording and
  punctuation are not stable API.

System APIs return `Result<T,System.Error>`. They validate public
preconditions before invoking the OS, retry transparent interruptions when
possible, and translate POSIX, Win32, and Winsock failures without exposing the
native code. Native ABI violations, impossible lengths, and invalid UTF-8 from
a native source remain fatal interop contract violations.
