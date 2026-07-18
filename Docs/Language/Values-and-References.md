# Values and mutation

Primitive values, strings, fixed arrays, lists, ordinary structures, and enums
have value semantics. Assignment, an ordinary function argument, a return
value, a field, and an indexed element never create observable shared mutable
state. A structure declaring `drop` is the noncopyable exception: it owns one
unique local resource. A temporary transfers implicitly into its destination;
a named owner transfers only through `move`. See
[Structures](Structures.md#unique-resource-structures).

Function values are copied as values too, but a capturing lambda contains
lexical borrows of the bindings it uses. Copying it copies those borrows, not
the captured values. The compiler therefore prevents the lambda, or any
structure or collection containing it, from surviving the shortest captured
scope.

This shared captured state also means a function value is not independent and
cannot be bound directly with `let`, or inside an ordinary containing value.
A local `let` collection is the exception: its storage is immutable even when
its elements are not independent.

```sx
var callback = func() {}
let callbacks:func()[] = [callback]
```

A structure or optional qualifies for `let` only when its contained types
recursively preserve the independent value behaviour. The same rule applies to
array and list fields, static storage, and collections nested inside another
ordinary value. A local array or list binding may instead use `let` to protect
only its own collection storage. Class references do not otherwise qualify.

```sx
var first:int[] = [1]
var second = first
second[0] = 2

print(first[0])  // 1
print(second[0]) // 2
```

The compiler may optimize list copies internally, but the value behaviour above
is guaranteed, including for nested lists and structures that contain lists.
Copying a list of classes copies its class references: the list remains a
distinct container value, while its elements retain their shared identities.

A dynamic protocol value follows the contained kind. When it contains a
structure, assignment copies an independent structure value. When it contains
a class, assignment copies the reference and preserves the same object
identity. Because the protocol type can hide a class reference, it is not an
independent type and must use `var` directly or inside an ordinary containing
value. It may be an element of a local `let` collection under that
collection-shell rule. Hidden class references remain visible to reference
counting and cycle tracing. See [Protocols](Protocols.md#dynamic-protocol-values).

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

## Reading without copying

Use `borrow name:T` when a function only needs to inspect a value without
copying or consuming it. The call repeats the marker as `borrow value`, making
the temporary alias visible at both ends:

```sx
func describe(borrow file:File) str {
    return file.get_path()
}

let file = File.open("notes.txt")
print(describe(borrow file))
print(file.get_path())
```

The parameter remains nominally `T`; `borrow` is a passing mode, not a
reference type. It accepts a readable `let` or `var`, field, indexed element,
or temporary. The alias ends when the synchronous call returns, and a
temporary lives through that call. Several read borrows of one root may be
arguments of the same call.

A borrowed parameter is read-only. It may inspect fields, index collections,
call non-mutating methods, and forward the alias to another `borrow` parameter.
It cannot be assigned, passed with `&`, used as a mutating receiver, consumed
with `move`, returned, stored beyond the call, or captured by a lambda. While a
read borrow is active, the same root cannot be mutated, moved, or passed with
`&`.

`borrow` works with copyable and noncopyable value types, including unique
resources. It is invalid for a class, whose ordinary value already carries a
shared identity, and for a dynamic protocol value that may hide such an
identity. Native functions do not declare `borrow` parameters.

The marker participates in overload resolution and function types. These are
three distinct signatures:

```sx
func inspect(value:Data) {}
func inspect(borrow value:Data) {}
func inspect(value:&Data) {}

var callback:func(borrow Data) = func(borrow value:Data) {}
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

`&` accepts a mutable variable, `var` field, or indexed element that is not
reached through a `let` field:

```sx
struct Rover {
    var energy:int
}

var rover = Rover(energy:10)
var values:int[] = [1]
increment(&rover.energy)
increment(&values[0])
```

A `let` binding or field, including any nested field or element reached through
it, cannot be passed with `&`.
Several `&` arguments may name the same place at runtime. They are temporary
aliases for the duration of that call, and writes follow the function body's
normal execution order. An `&` argument cannot overlap a `borrow` argument of
the same root in that call.

`&T` exists only in a function or method parameter. Silex has no general
reference type: references cannot be declared locally, stored, returned, or
dereferenced. Ordinary assignment is the value-copy operation for ordinary
values. The distinct `move name` expression transfers a complete unique-resource
local or parameter; it is not a general replacement for copying.

A class reference already has shared identity and cannot be declared as an
`&ClassName` parameter. `&ClassName?` remains valid because it aliases the
caller's optional place so the function can replace that place; it does not add
a second reference layer around the class instance. See [Classes](Classes.md).

The lexical borrows held by a lambda are distinct from the explicit `&`
argument marker: they are detected automatically, may last for several calls
inside their valid scope, and can never escape that scope.
