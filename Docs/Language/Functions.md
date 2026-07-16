# Functions

A function begins with `func`, has a name and typed parameters, and has an
explicit return type whenever it returns a value.

```sx
func add(left:int, right:int) int {
    return left + right
}

func log(message:str) {
    print(message)
}
```

Omitting a return type means `void`; writing `void` explicitly is valid but not
canonical. A non-void return type is never inferred. The compiler collects
signatures before checking bodies, so functions may be called before their
definition and may be recursive.

## Overloads

Top-level functions and methods in the same structure may share a name when
their ordered parameter lists differ by count, type, or `&` passing. The return
type is not part of a signature: aliases such as `int` and `int64`, `uint` and
`uint64`, or `float` and `float32` therefore do not create distinct overloads.

```sx
func measure() int {
    return 0
}

func measure(value:int) int {
    return value
}
```

At a call site, Silex first keeps the signatures compatible with the argument
count, types and `&` markers. It then prefers an exact type, a same-sign
integer widening or `float` to `float64`, and finally an integer-to-float
conversion. If no single signature is strictly better, the call is rejected as
ambiguous and the remaining signatures are listed. Integer and decimal
literals keep their default `int` and `float` types during this selection.

`main` and every `native func` remain unique by name. A native C symbol does
not encode parameters, so native overloads are not available.

## Assertions

`assert(condition, message)` verifies a runtime invariant. The condition must
be `bool` and the message `str`. If the condition is false, Silex writes the
source location and `assertion failed: <message>` to standard error, then ends
the program with exit code 1. Assertions remain active in every build.

```sx
assert(index < values.count(), "index must address a value")
```

Assertions do not introduce recoverable errors or error propagation.

## Panic

`panic(message)` stops the current execution path. Its message must be `str`.
Silex writes the location of `panic` and `runtime error: <message>` to standard
error, then exits with code 1. A `panic` satisfies a non-`void` function's
mandatory return path, but does not introduce recoverable errors, stack traces,
or error propagation.

```sx
func require_positive(value:int) int {
    if value <= 0 {
        panic("value must be positive")
    }
    return value
}
```

`native func` declares a private, top-level function implemented by a named
module's native runtime rather than by a Silex body. The local or distributed
module, or one of its parents, must contain a `Module.json` with a `native`
section. A standalone main source cannot declare native functions, and
`pub native func` is invalid. Native function names begin with `native_`.

Their ABI is intentionally narrow: scalar booleans and numbers may be passed
or returned, while `str` may only be a parameter. A string is passed as UTF-8
bytes and a byte length; the native runtime must neither retain nor modify its
byte view. Collections, structures, references, pointers, callbacks and string
returns are not native-function values. Silex derives the C symbol from the
module and function name, so a native runtime never chooses an arbitrary C
symbol.

All arguments, return values, and return paths are checked statically. A
non-void function must return a compatible value on every path. A void function
may use `return` without a value.

Methods are functions declared inside a structure or class. Their receiver is
the explicit `self` value; see [Structures](Structures.md) and
[Classes](Classes.md). Structure methods are public by default. Class methods
are private by default and use `pub` for general access or `sub` for access by
future descendants.

## Function values and lambdas

`func(parameter types) return_type` is a value type. An omitted return type is
the canonical spelling of `void`; `func(int) void` is also accepted. Function
values may be assigned, passed, stored in fields or collections, and called
with the same argument conversions as a named function.

```sx
func apply(value:int, callback:func(int) int) int {
    return callback(value)
}

let doubled = apply(4, func(value:int) int {
    return value * 2
})
```

A function value itself uses `var`, even when its binding is not reassigned:
its type may carry lexical captures shared with another path and therefore
cannot satisfy the independent-value contract of `let`.

```sx
var callback = func(value:int) int {
    return value * 2
}
```

A lambda begins with `func` but has no name. Every parameter is named and
annotated, and every non-`void` return type and path is explicit. The compiler
captures only the outer bindings actually used. A captured `var` may be read
and changed; a captured `let` remains immutable. Copies of a lambda refer to
the same captured bindings.

A lambda without captures is an unrestricted value. A capturing lambda borrows
its outer bindings and cannot be returned or stored in a variable, field,
structure, or collection that outlives any capture. The same check is applied
when a callback parameter is stored by the called function or method. This is a
lexical check: captures do not allocate shared cells or extend a scope.

Function values and values that contain them are not printable or comparable.
They cannot be bound with `let`, have no intrinsic default, and remain
forbidden in `native func` parameters and returns.
