# Structures

A `struct` is a nominal value type with typed fields and optional field
defaults.

```sx
struct Position {
    x:int
    y:int = 10
}

let position = Position { x:10 }
```

An initializer uses named fields in any order. Omitted fields use an explicit
default first, then the intrinsic value of their type. Unknown, repeated, and
incompatible field values are rejected. Explicit defaults are currently limited
to primitive literals and structure initializers; they cannot refer to `self`,
another field, a variable, or a function.

Fields of a `var` structure may be changed, including through nested paths. A
`let` structure is fully immutable. Structures compare by value when they have
the same declared type, except when they contain a function value directly or
recursively; such values are not comparable. A function field has no intrinsic
default and must be supplied by the initializer, for example with `func() {}`.

## Methods

Methods declare `self` explicitly. A method becomes mutating if it writes
through `self` or calls another mutating method on it. This property propagates
through recursive calls; a mutating method requires a `var` receiver.

```sx
struct Counter {
    value:int

    func increment() {
        self.value += 1
    }
}
```

Static methods, custom constructors, classes, inheritance, extensions, and
partial declarations are not part of the current prototype. Methods can be
overloaded by parameter count, type, or `&` passing; see [Functions](Functions.md).

When a method stores a lambda that uses `self` in a function field of that same
structure, `self` means the owner of the field at call time. Copying the
structure therefore preserves value semantics instead of retaining a hidden
address to the original instance.

```sx
struct Counter {
    count:int
    callback:func()

    func bind() {
        self.callback = func() { self.count += 1 }
    }
}
```

An extracted field such as `let callback = counter.callback` is instead bound
to `counter` and cannot outlive it. A direct `counter.callback()` call supplies
the current owner without extracting the field.
