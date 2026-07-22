# Subprocess

```sx
use STD.Subprocess
use STD.System.Error as Error

func execute(command:Subprocess.Command) Result<Subprocess.Output, Error> {
    return Subprocess.run(command)
}
```

`STD.Subprocess.run` launches the exact executable in `Command` without a shell
and without searching `PATH`. Arguments are passed as literal strings; Windows
uses quoting that round-trips through the platform command-line parser. A
relative executable is resolved from the selected child directory, itself
resolved from the parent's directory at the start of the call.

The environment starts from the parent or from an empty block, then applies
`EnvironmentChange` values in order using POSIX case-sensitive or Windows
case-insensitive names. stdin receives every configured byte and closes.
stdout and stderr are drained concurrently and returned separately as binary
arrays, so neither pipe can block while the other fills.

`maximum_output_bytes` bounds the combined outputs. A negative value is
`invalid_input`; exceeding the bound terminates and reaps the child, closes all
handles, and returns `limit_exceeded` without partial output. Ordinary nonzero
exit and POSIX signal termination remain successful `Output` statuses.

This first API is blocking and has no shell, `PATH` lookup, live handle,
interactive pipe, timeout, detachment, pseudo-terminal, or pipeline.
