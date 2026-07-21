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

The native-only `deferred func(...)` form is the noncopyable exception. It may
exist only as a direct local `var` or as the direct temporary argument of its
native registration, and a named value transfers with `move`. Its captures are
then owned indirectly by the returned subscription resource until that resource
is destroyed. See [Native interoperability](Native-Interop.md#deferred-callbacks).

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

## Read references

Use `name:@T` when a function only needs to inspect a value without copying or
consuming it. The signature selects the temporary read-only reference; the
call remains an ordinary call:

```sx
func describe(file:@File) str {
    return file.get_path()
}

let file = File.open("notes.txt")
print(describe(file))
print(file.get_path())
```

`@T` is a parameter mode rather than a general storable type. Its ordinary
argument may be a readable `let` or `var`, field, indexed element, literal, or
temporary. The alias ends when the synchronous call returns, and a temporary
lives through that call.
Several read references to one root may be arguments of the same call.

A read-reference parameter is read-only. It may inspect fields, index
collections, call non-mutating methods, and forward the alias to another `@T`
parameter. It cannot be assigned to an `&T` parameter, used as a mutating
receiver, consumed with `move`, returned, stored beyond the call, or captured
by a lambda. While a read reference is active, the same root cannot be mutated,
moved, or passed to an `&T` parameter.

`@` works with copyable and noncopyable value types, including unique
resources. It is invalid for a class, whose ordinary value already carries a
shared identity, and for a dynamic protocol value that may hide such an
identity. At the native boundary, `@` is restricted to opaque resources and
contiguous views.

The mode remains part of function types, but it is not an overload selector at
the call site. Declarations with the same name and parameter types cannot differ
only by `T`, `@T`, or `&T`, because all three would be called identically:

```sx
var callback:func(@Data) = func(value:@Data) {}
var mutator:func(&Data) = func(value:&Data) {}
```

## Mutating an argument

Use `name:&T` when a function deliberately changes a place owned by its
caller. The signature selects mutable-reference binding; the call passes the
place normally, and inside the function `name` is used directly.

```sx
func increment(value:&int) {
    value += 1
}

var count = 1
increment(count)
print(count) // 2
```

An `&T` parameter accepts a mutable variable, `var` field, or indexed element
that is not reached through a `let` field:

```sx
struct Rover {
    var energy:int
}

var rover = Rover(energy:10)
var values:int[] = [1]
increment(rover.energy)
increment(values[0])
```

A `let` binding or field, including any nested field or element reached through
it, cannot be passed to an `&T` parameter. Several arguments bound to `&T`
parameters may name the same place at runtime. They are temporary aliases for
the duration of that call, and writes follow the function body's
normal execution order. An `&T` parameter cannot overlap an `@T` parameter on
the same root in that call.

`@T` and `&T` can also describe a controlled return and a local alias. A
function writes the mode before its return type and returns an explicit borrow:

```sx
func inspect(owner:@Owner) @State {
    return @owner.state
}

func edit(owner:&Owner) &State {
    return &owner.state
}
```

The provenance is elided when exactly one compatible borrowed parameter exists.
With several possible roots it is qualified symbolically, for example
`@first:State`. A shared result may originate from `@` or `&`; a mutable result
requires `&`. Calls propagate the actual root through successive wrappers.

The result can be inferred or annotated locally as `let view:@State` or
`var edit:&State`. Shared aliases can coexist and be copied; mutable aliases are
exclusive and cannot be copied. Member access stays direct (`view.field`) with
no visible dereference operator. The alias keeps its root borrowed until the end
of its lexical scope, preventing incompatible access, mutation, replacement,
`move`, or destruction.

Reference types remain forbidden in fields, collections, optionals, enums,
static storage, lambda captures and deferred callbacks. They are controlled
aliases, not pointers or independently storable values. Ordinary assignment is
the value-copy operation for ordinary values. The distinct `move name`
expression transfers a complete unique-resource local or parameter; it is not
a general replacement for copying.

A class reference already has shared identity and cannot be declared as an
`&ClassName` parameter. `&ClassName?` remains valid because it aliases the
caller's optional place so the function can replace that place; it does not add
a second reference layer around the class instance. See [Classes](Classes.md).

The lexical borrows held by a lambda are distinct from an `&T` parameter
binding: they are detected automatically, may last for several calls
inside their valid scope, and can never escape that scope.

## Contiguous borrowed views

`T[..]` is the non-owning target for contiguous storage. It never appears by
itself: `@T[..]` is a bounded read view and `&T[..]` is a bounded exclusive
mutable view. Neither form exposes an address, owns storage, changes capacity,
or has a destructor.

```sx
let middle = @values[1:4]
var editable = &values[1:4]
```

Both bounds are required and use the ordinary slice normalization. A subview
uses the same syntax on an existing view and retains the original borrow root.
Views provide `count()`, `is_empty()`, positive and negative indexing, and
iteration. A mutable view additionally permits indexed writes and `for var`.
Operations that resize, reorder, remove, or transfer elements are unavailable.

Standard algorithms can retain or consume these borrow boundaries directly.
`Algorithms.choose<T>` returns an `@T` whose provenance remains the input
`@T[..]`, while `Algorithms.shuffle<T>` reorders only an input `&T[..]` through
`swap`. Their `Randomizer.choose<T>` and `Randomizer.shuffle<T>` extension
façades preserve the same roots. See the
[STD algorithms](Libraries/STD/Algorithms.md) reference.

The ordinary expression `values[start:end]` remains different: it copies into
an independent `T[]`. A borrowed view instead keeps the source collection,
array, or native resource borrowed until the view's lexical scope ends.
