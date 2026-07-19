# Recoverable errors

Silex exposes the intrinsic generic type `Result<T,E>` without a `use`. A
function uses it explicitly when an expected failure belongs to its ordinary
control flow:

```sx
enum ParseError {
    empty
    invalid_character(str)
    overflow
}

func parse_port(text:str) Result<int, ParseError> {
    if text.count() == 0 {
        return Result<int, ParseError>.failure(ParseError.empty())
    }
    return Result<int, ParseError>.success(8080)
}
```

`Result<T,E>` is a canonical enum with exactly two variants: `success(T)` and
`failure(E)`. It is handled by the same exhaustive `match` as a declared enum:

```sx
match parse_port(text) {
    success(port) => { print(port) }
    failure(error) => { print("invalid port") }
}
```

There is no implicit conversion from `T` or `E`, no implicit variant, and no
default success.

## Propagation with `try`

The prefix expression `try` evaluates a `Result<T,E>` once. A success produces
its `T` value; a failure immediately returns the same `E` from the current
function:

```sx
func load_port(text:str) Result<int, ParseError> {
    let port = try parse_port(text)
    return Result<int, ParseError>.success(port)
}
```

The containing function or lambda must itself return `Result<U,E>`. The success
types `T` and `U` may differ, but the error type must be exactly the same after
transparent aliases are resolved. No conversion or error transformation is
attempted. A failure leaves a lambda that contains `try`, not its enclosing
function.

`try` has prefix precedence: calls and member access bind to its operand before
it, while binary operators bind after it. Thus `try parse_port(text) + 1` means
`(try parse_port(text)) + 1`.

When the `Result` is noncopyable, `try` consumes it. A temporary call remains
`try load()`, while a named result is written `try move result`. Success moves
`T` into the surrounding expression and failure moves `E` into the early
return.

For `Result<void,E>`, `try operation()` is a complete statement:

```sx
func save_all() Result<void, SaveError> {
    try save_header()
    try save_body()
    return Result<void, SaveError>.success()
}
```

Propagation is compiled as an ordinary early return. It uses no exception, and
the same scope cleanup and destruction as an explicit `return` still occurs.
For unique-resource availability, the failure path is terminal: it does not
constrain a continuing path at a later control-flow join.
`try` is invalid outside a function or lambda returning a compatible `Result`,
including constructors and `drop` blocks. Error transformation remains
explicit.

## Explicit error transformation

The intrinsic generic function `map_error` transforms only the failure of a
`Result<T,E>` into a `Result<T,F>`:

```sx
enum AppError {
    input(ParseError)
    storage(IOError)
}

let config = try map_error<Config, ParseError, AppError>(
    parse_config(text),
    func(error:ParseError) AppError {
        return AppError.input(error)
    }
)
```

On success, the original `T` value is preserved and the transformation is not
called. On failure, the `E` value is passed to the transformation exactly once
and its `F` result becomes the new failure. The transformation is an ordinary
function value: its captures follow the usual lifetime rules, and it is neither
stored nor called after `map_error` returns.

`Result<void,E>` uses the overload with two explicit type arguments:

```sx
let saved = map_error<IOError, AppError>(
    save(),
    func(error:IOError) AppError {
        return AppError.storage(error)
    }
)
```

`map_error` performs no implicit conversion, success transformation, or error
recovery. A transformation that calls `panic` or fails an `assert` remains
fatal. The function is intrinsic rather than declared by `STD`; its call name
is reserved and cannot be shadowed by a function, module alias, or local
binding. As with other generic functions, all type arguments are explicit.
For a noncopyable result, a named argument is supplied with `move`; the returned
`Result` owns either the original success value or the transformed error.

## Success without a value

`Result<void,E>` represents a recoverable operation with no success value. Its
success variant is constructed and matched without parentheses in the pattern:

```sx
func save() Result<void, SaveError> {
    return Result<void, SaveError>.success()
}

match save() {
    success => { print("saved") }
    failure(error) => { print("not saved") }
}
```

This is the only generic use of `void`: it must be the first argument of
`Result`. `Result<T,void>`, `Result<void,void>`, and `Enum<void>` are invalid.
A function type such as `func()` remains an ordinary value type.

`Result` has enum value semantics. An immutable `let` is accepted only when
both possible contents are recursively independent; a function value, class
reference, or another non-independent value requires `var`.

`Result` is a language type rather than an `STD` declaration or implicit
module. Its name is reserved and cannot be declared or introduced by a type or
module alias. It has no fields or methods. A `Result<T,E>` whose branches are
already transferable may be returned by a `native func`; it cannot be passed as
a native parameter. The native return transport and ownership contract are
defined in [Native interoperability](Native-Interop.md#optional-and-result-returns).

## The `main` boundary

The program entry point may return `void` or exactly `Result<void,str>`:

```sx
func run_application() Result<void,str> {
    return Result<void,str>.failure("configuration missing")
}

func main() Result<void,str> {
    try run_application()
    return Result<void,str>.success()
}
```

A final `success()` exits with code `0` and writes nothing. A final
`failure(message)` writes `error: `, the exact UTF-8 bytes of `message`, then
one `\n` byte to standard error, and exits with code `1`. The boundary does not
trim or normalize the message; if it already ends in `\n`, the added newline
still follows it.

No other `Result` specialization is accepted for `main`. A structured error
must be handled or transformed explicitly to `str`, for example with
`map_error`, before it reaches the entry point. For the same reason, `try` in
`main` can propagate only a `Result` whose error type is `str`.

`main` remains unique, non-generic, and parameterless. A non-void `main` must
return on every ordinary path. This boundary does not intercept or rewrite a
`panic` or failed `assert`: those remain fatal runtime errors with their own
source-located diagnostics.

`panic` and `assert` remain fatal. They never create `failure` and cannot be
caught with `match`. Cancellation or a system error that an API wishes to
expose is represented by an ordinary variant of `E`.
