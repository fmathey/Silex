# Values and mutation

Primitive values, strings, fixed arrays, lists, and structures have value
semantics. Assignment, an ordinary function argument, a return value, a field,
and an indexed element never create observable shared mutable state.

```sx
var first:int[] = [1]
var second = first
second[0] = 2

print(first[0])  // 1
print(second[0]) // 2
```

Lists use copy-on-write internally: an assignment or an ordinary function call
may initially share storage, then separate it when one value is written. This
is an implementation detail; the value behaviour above is guaranteed,
including for nested lists and structures that contain lists.

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

var rover = Rover { energy:10 }
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
