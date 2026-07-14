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

`native func` declares a private, top-level function implemented by a
distributed module's native runtime rather than by a Silex body. The module
must contain `native.json`; applications cannot declare native functions, and
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

Methods are functions declared inside a structure. Their receiver is the
explicit `self` value; see [Structures](Structures.md).
