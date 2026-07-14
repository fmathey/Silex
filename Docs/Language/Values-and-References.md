# Values and references

Silex distinguishes copyable values, owning values, and references. These rules
are language semantics and cannot vary with compiler implementation details.

Primitive values, strings, arrays, lists, and structures are copyable when all
of their contents are copyable. Assignment, argument passing, returning, and
reading a field or element then produce an independent logical value. The
backend may share storage internally only when no shared mutability or identity
is observable.

`copy value` makes a normal copy explicit. `move value` transfers a complete
local owner. After a move, that local cannot be read, borrowed, passed, or
destroyed again; a `var` binding may receive a complete new value.

```sx
var source:int[] = [1, 2]
var copy_of_source = source
var target = move source
```

## References

`T@` is an immutable reference and `T&` is a mutable reference. `&place`
borrows an existing local value or one of its fields; the expected type selects
the requested access. Dereferencing is explicit with `*`.

```sx
func increment(value:int&) {
    *value += 1
}

var count = 1
let view:int@ = &count
increment(&count)
```

References are non-null. They may only be local `let` bindings or function
parameters; they cannot be returned, stored in a structure, or retained by a
value that survives the call. Immutable borrows exclude mutation and moves;
mutable borrows exclude every other direct access to the borrowed root. These
rules are deliberately conservative for fields and nested collections.

Locals are released in reverse initialization order at scope exit. A return
prepares its value before releasing local values. This deterministic cleanup is
also the required model for future propagated errors and runtime failures.
