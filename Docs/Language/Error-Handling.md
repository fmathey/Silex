# Recoverable errors

Silex exposes the intrinsic generic type `Result<T,E>` without an import. A
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
default success. Propagation is still written manually with `match`; `try` and
error transformation are not part of this version.

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
import alias. It has no fields or methods and cannot cross a `native func`
signature. `main` continues to return `void`.

`panic` and `assert` remain fatal. They never create `failure` and cannot be
caught with `match`. Cancellation or a system error that an API wishes to
expose is represented by an ordinary variant of `E`.
