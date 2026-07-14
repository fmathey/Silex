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

All arguments, return values, and return paths are checked statically. A
non-void function must return a compatible value on every path. A void function
may use `return` without a value.

Methods are functions declared inside a structure. Their receiver is the
explicit `self` value; see [Structures](Structures.md).
