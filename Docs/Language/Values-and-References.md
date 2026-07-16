# Values and mutation

Primitive values, strings, fixed arrays, lists, and structures have value
semantics. Assignment, an ordinary function argument, a return value, a field,
and an indexed element never create observable shared mutable state.

Function values are copied as values too, but a capturing lambda contains
lexical borrows of the bindings it uses. Copying it copies those borrows, not
the captured values. The compiler therefore prevents the lambda, or any
structure or collection containing it, from surviving the shortest captured
scope.

This shared captured state also means a function value is not independent and
cannot be bound with `let`, directly or inside another value. Callback storage
uses `var`:

```sx
var callback = func() {}
var callbacks:func()[] = [callback]
```

A structure, array, list, or optional qualifies for `let` only when its
contained types recursively preserve the independent value behaviour. Class
references do not qualify, including when reached through one of these
containers.

```sx
var first:int[] = [1]
var second = first
second[0] = 2

print(first[0])  // 1
print(second[0]) // 2
```

The compiler may optimize list copies internally, but the value behaviour above
is guaranteed, including for nested lists and structures that contain lists.
Copying a list of classes copies its class references: the list remains an
distinct container value, while its elements retain their shared identities.

An ordinary parameter is a local value. A function may change it without
changing its caller.

```sx
func reset(values:int[]) {
    values[0] = 0
}

var source:int[] = [10]
reset(source)
print(source[0]) // 10
```

## Mutating an argument

Use `name:&T` when a function deliberately changes a place owned by its
caller. The call writes `&place`; inside the function, `name` is used directly.

```sx
func increment(value:&int) {
    value += 1
}

var count = 1
increment(&count)
print(count) // 2
```

`&` accepts a mutable variable, field, or indexed element:

```sx
struct Rover {
    energy:int
}

var rover = Rover(energy:10)
var values:int[] = [1]
increment(&rover.energy)
increment(&values[0])
```

A `let`, including one of its fields or elements, cannot be passed with `&`.
Several `&` arguments may name the same place at runtime. They are temporary
aliases for the duration of that call, and writes follow the function body's
normal execution order.

`&T` exists only in a function or method parameter. Silex has no general
reference type: references cannot be declared locally, stored, returned, or
dereferenced. There are no `copy` or `move` expressions; ordinary assignment
is the value-copy operation exposed by the language.

A class reference already has shared identity and cannot be declared as an
`&ClassName` parameter. `&ClassName?` remains valid because it aliases the
caller's optional place so the function can replace that place; it does not add
a second reference layer around the class instance. See [Classes](Classes.md).

The lexical borrows held by a lambda are distinct from the explicit `&`
argument marker: they are detected automatically, may last for several calls
inside their valid scope, and can never escape that scope.
