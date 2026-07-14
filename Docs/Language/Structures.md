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
the same declared type.

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

Static methods, custom constructors, overloads, classes, inheritance,
extensions, and partial declarations are not part of the current prototype.
