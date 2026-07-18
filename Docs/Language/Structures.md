# Structures

A `struct` is a nominal value type with typed fields and optional field
defaults. Its fields and methods are public by default, except for the storage
of a unique resource structure described below; class-only member markers
`pub` and `sub` are not written in a structure. Every field starts with `let`
or `var`; the older `name:type` form is invalid.

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

A `let` field and an ordinary `let` binding require a recursively independent
value. A function value, class reference, or container that reaches either one
must therefore be declared with `var`. Only a local array or list binding has a
narrow exception: its `let` protects the collection storage without requiring
independent elements.

Structures compare by value when they have the same declared type, except when
they contain a function value directly or recursively or declare `drop`; such
values are not comparable. A function field has no intrinsic default and must
be supplied by the initializer, for example with `func() {}`.

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
`Box<int>.filled(42)`, a used type, or a transparent type alias may
qualify it. A visible local value keeps priority over a type with the same
name. Static methods cannot be selected through a value, extracted as function
values, reached with `?.`, or called after `..`. Conversely, an instance method
cannot be selected through a type.

Custom structure constructors, structure inheritance, and partial declarations
are not part of the current prototype. A structure may list only protocol
conformances after `:`. Methods can be added without changing its representation
through [type extensions](Extensions.md). Shared-identity types are declared
with `class`; see [Classes](Classes.md). Static and instance methods
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

## Unique resource structures

A structure that declares `drop` owns one unique local resource. The block is
both its custom destruction operation and its nominal noncopyable marker; no
additional declaration keyword is used. A structure without `drop` keeps the
ordinary value-copy semantics described above.

```sx
native func native_file_open(path:str) int
native func native_file_close(handle:int)

pub struct File {
    let handle:int
    let path:str

    static func open(path:str) File {
        return File(handle:native_file_open(path), path:path)
    }

    func get_path() str {
        return self.path
    }

    drop {
        native_file_close(self.handle)
    }
}
```

For a public owner structure, its fields and named aggregate initializer are
visible only to source units in the declaring module. Its methods and static
methods retain the ordinary public visibility of structure methods, so an
external caller constructs `File` through `File.open` and reads it through
`get_path`. An extension has the same storage rights as an external caller,
even when it extends the type by name; it cannot access `handle` or invoke the
aggregate initializer. Ordinary structures remain transparent.

A completed owner value can be bound locally with `let` when its fields meet
the ordinary independence rules, or with `var` when its public behaviour needs
a mutable receiver. A temporary owner transfers implicitly into a local,
ordinary parameter, assignment destination, or return value. A static factory
may therefore return a freshly constructed `File`, and this call is valid:

```sx
func close(file:File) {}

close(File.open("notes.txt"))
```

A named owner never transfers implicitly. Prefix `move` names the complete
local binding or ordinary parameter whose ownership is transferred:

```sx
func forward(file:File) File {
    return move file
}

let first = File.open("notes.txt")
let second = move first
close(move second)
```

`move` accepts the complete name of any recursively noncopyable local or
parameter. It rejects ordinary copyable values, `self`, static storage, fields,
indexed elements, partial values, and captured outer bindings. A noncopyable
A parameter of a noncopyable type cannot use `&T`; the value also cannot be
captured by a lambda, converted to a dynamic protocol value, or compared for
equality.
Named owner arguments and returns must spell `move` at the transfer site. A
`resource:@Resource` parameter may inspect the same owner through an ordinary
`resource` argument without transferring or copying it; the
owner remains available after the call.

After `move file`, that binding is consumed: it cannot be read, mutated, moved
again, referenced, or destroyed. A consumed `var` can receive a new temporary or
transferred owner and becomes available again; a consumed `let` cannot be
assigned. Assigning an available owner `var` first evaluates the new owner,
runs the destination's `drop` exactly once, then installs the new owner. Moving
a binding into itself is invalid.

An active `@` reference blocks `move` and `&` on the same owner until the call
returns. The referenced parameter itself cannot be moved, mutated, returned,
stored, or captured. It may call non-mutating methods and forward the same
temporary alias to another `@T` parameter.

At a control-flow join, an owner is available only when it is available on
every path that reaches the join. Paths ending in `return`, `break`, `continue`,
`panic`, or failed `try` do not constrain paths that continue. Every path back
to a loop header must restore the same owner availability it had before the
iteration; otherwise the loop is rejected.

Noncopyability is recursive. A structure, enum, `Result`, optional, array, or
list containing an owner is itself noncopyable; a generic specialization gains
that property from its concrete fields or arguments. A class may own such a
field without making its shared reference noncopyable. Named values placed in
these containers use `move`, while fresh temporaries transfer directly. Static
fields remain unable to own noncopyable values.

`drop` receives `self` implicitly and may access the structure's private
storage. It has no parameters, parentheses, return type, or visibility marker,
cannot be called explicitly, and cannot contain `return` or `try`. It executes
exactly once for each completely constructed and untransferred owner:

- at the lexical end of its block;
- before `return`, `break`, or `continue` leaves its scope;
- before an early `Result` return caused by a failed `try`;
- at the end of `main`, like any other function.

Completed locals are destroyed in reverse construction order. An owner whose
initializer did not complete is not destroyed. Its `drop` body runs before its
fields are destroyed automatically in reverse declaration order. Lists and
arrays destroy elements in reverse index order; optionals destroy their present
value, and enums destroy only the active variant's associated values in reverse
declaration order. A transfer destination becomes responsible for the
eventual `drop`; the consumed source performs no later destruction. An owner
parameter likewise owns its argument until it is dropped or transferred again.

These guarantees cover ordinary language exits. A `panic`, failed `assert`,
forced process termination, or fatal native failure does not promise cleanup;
a failure inside `drop` is fatal. Class `drop` instead follows shared-reference
and cycle-collection lifetime, as described in [Classes](Classes.md).
