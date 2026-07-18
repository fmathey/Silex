# Structures

A `struct` is a nominal value type with typed fields and optional field
defaults. Its fields and methods are public by default; class-only member
markers `pub` and `sub` are not written in a structure. Every field starts
with `let` or `var`; the older `name:type` form is invalid.

```sx
struct Position {
    var x:int
    var y:int = 10
}

let origin = Position()
let position = Position(x:10)
```

An initializer uses parentheses and named fields in any order. A final comma is
allowed, including in a multiline initializer, and a field value may itself be
another initializer. `Position()` supplies no field explicitly. Omitted fields
use an explicit default first, then the intrinsic value of their type. Unknown,
repeated, and incompatible field values are rejected.

Arguments are either all positional or all named. Positional arguments invoke a
function or callable value and cannot initialize a structure; named fields
select a structure and are not function arguments. For an empty invocation, a
visible callable local has priority; otherwise the module declaration determines
whether `Name()` is a function call or a structure initializer. The same rules
apply to qualified names such as `Geometry.Position(x:10)`, without relying on
letter case.

Explicit defaults are currently limited to primitive literals and structure
initializers; they cannot refer to `self`, another field, a variable, or a
function. Braces delimit declarations and blocks; `Position { x:10 }` is not an
initializer.

## Generic structures

A structure may declare type parameters after its name. Every use supplies one
explicit type argument per parameter:

```sx
struct Pair<T> {
    var first:T
    var second:T
}

struct Entry<Key, Value> {
    var key:Key
    var value:Value
}

let coordinates = Pair<int>(first:10, second:20)
let names:Pair<str> = Pair<str>(first:"Ada", second:"Grace")
let indexed = Entry<int, Pair<str>>(
    key:1,
    value:Pair<str>(first:"left", second:"right"),
)
```

`Pair<int>` and `Pair<str>` are distinct concrete types. Repeating the same
arguments denotes the same type throughout the application and across module
boundaries. Arguments may themselves be structures, classes, enums,
collections, optionals, function types, or generic type specializations.

Type arguments are not inferred. A generic structure name without arguments
is incomplete, including in an initializer whose fields would otherwise reveal
the arguments. A non-generic structure does not accept type arguments.

The structure's parameters are in scope in its fields and methods. Methods do
not redeclare them:

```sx
struct Box<T> {
    var value:T

    func get() T {
        return self.value
    }

    func replace(value:T) {
        self.value = value
    }
}

var score = Box<int>(value:10)
score.replace(20)
```

Silex checks every concrete specialization with its ordinary type rules. One
protocol can constrain a type parameter, for example
`struct Box<T : Serializable>`. Only explicitly conforming arguments can create
that specialization. Unconstrained parameters retain their existing behavior.
Generic classes and methods with their own type parameters are not currently
part of the language. Free generic functions are described in
[Functions](Functions.md), and constraints in [Protocols](Protocols.md).

A `var` field can be changed only through a mutable receiver. A structure
binding declared with `var` therefore permits writes to its `var` fields, while
a binding declared with `let` remains fully immutable. A `let` field cannot be
assigned or mutated through a nested path after construction, including by a
mutating method on a contained structure or collection.

Both a `let` binding and a `let` field require a recursively independent value.
A function value, class reference, or container that reaches either one must
therefore be declared with `var`.
Structures compare by value when they have the same declared type, except when
they contain a function value directly or recursively; such values are not
comparable. A function field has no intrinsic default and must be supplied by
the initializer, for example with `func() {}`.

## Static fields

`static let` and `static var` declare one storage location attached to a
concrete type rather than copied into each value. A static field always has an
explicit `name:type` annotation and is selected only through its complete type:

```sx
struct Counter {
    static var value:int
}

Counter.value += 1
```

A value cannot select a static field, and a type cannot select an instance
field. The two namespaces are distinct, so one type may declare a static field
and an instance field with the same name. A transparent alias selects the same
storage as its source type. Each used generic specialization instead owns an
independent location: `Cache<int>.hits` and `Cache<str>.hits` do not share a
value.

An omitted initializer is accepted only when the field type has an intrinsic
value. Static initializers follow the restricted field-default grammar:
compatible literals, `null`, an empty collection, or a named structure
initializer recursively composed from those forms. They cannot call code,
construct a class, read another static field, or depend on source-file order.
Elaborate setup is written explicitly in a static method.

`static let` is deeply immutable and accepts only recursively independent
types. `static var` permits assignment and mutation through nested fields,
collections, and ordinary mutable paths. Static storage exists before `main`
and is a strong root during the call. After `main` returns, every static field
is reset to its intrinsic value before the runtime checks for remaining class
instances; retained class references and cycles are therefore released under
the ordinary `drop` and cycle-collection rules. Silex currently provides no
concurrency model, atomic access, or implicit synchronization for this storage.

Structure static fields are public and do not accept `pub` or `sub`. Class
visibility and inheritance rules are described in [Classes](Classes.md).

## Methods

Methods declare `self` explicitly. A method becomes mutating if it writes
through `self` or calls another mutating method on it. This property propagates
through recursive calls; a mutating method requires a `var` receiver.

```sx
struct Counter {
    var value:int

    func increment() {
        self.value += 1
    }
}
```

`static func` declares a method attached to the structure itself. It is called
through a complete type and has no `self` receiver:

```sx
struct Position {
    var x:int
    var y:int

    static func origin() Position {
        return Position(x:0, y:0)
    }
}

let origin = Position.origin()
```

A static method belongs to a separate overload set from instance methods and
can use the structure's type parameters. A specialization such as
`Box<int>.filled(42)`, an imported type, or a transparent type alias may
qualify it. A visible local value keeps priority over a type with the same
name. Static methods cannot be selected through a value, extracted as function
values, reached with `?.`, or called after `..`. Conversely, an instance method
cannot be selected through a type.

Custom structure constructors, structure inheritance, extensions, and partial
declarations are not part of the current prototype. A structure may list only
protocol conformances after `:`. Shared-identity types are declared with
`class`; see [Classes](Classes.md). Static and instance methods
can each be overloaded by parameter count, type, or `&` passing; see
[Functions](Functions.md).

When a method stores a lambda that uses `self` in a function field of that same
structure, `self` means the owner of the field at call time. Copying the
structure therefore preserves value semantics instead of retaining a hidden
address to the original instance.

```sx
struct Counter {
    var count:int
    var callback:func()

    func bind() {
        self.callback = func() { self.count += 1 }
    }
}
```

An extracted field such as `var callback = counter.callback` is instead bound
to `counter` and cannot outlive it. A direct `counter.callback()` call supplies
the current owner without extracting the field.
