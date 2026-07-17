# Classes

A `class` is a nominal type with shared identity. Copying a class reference,
passing it as an ordinary argument, returning it, or storing it in a field or
collection keeps the same instance instead of copying its fields.

```sx
class Player {
    var health:int = 100

    pub func take_damage(amount:int) {
        self.health -= amount
    }

    pub func get_health() int {
        return self.health
    }
}

var first = Player()
var second = first
second.take_damage(10)
print(first.get_health()) // 90
```

Without a custom constructor, classes use the same named initializer and member
syntax as structures. Named fields initialize `let` and `var` alike; an omitted
field uses its declared default, then its type's intrinsic value. Every field
starts with `let` or `var`.
Construction is explicit: a non-optional declaration such as
`var player:Player` is invalid, because a class has no intrinsic instance.
`var player:Player?` is valid and starts as `null` under the ordinary
optional-value rules. A class may be declared `pub`.

## Constructors

`init` declares a class constructor. It has no `func` prefix or return type and
receives `self` implicitly:

```sx
class Session {
    var token:str
    var attempts:int = 1

    pub init(token:str) {
        self.token = token
    }

    pub init(token:str, attempts:int) {
        self.token = token
        self.attempts = attempts
    }

    pub func get_token() str {
        return self.token
    }
}

var session = Session("abc")
var retried = Session("def", 3)
```

Constructor arguments are positional and overload selection follows function
rules. A constructor is private without a marker, `sub` for the declaring class
and future descendants, and `pub` for ordinary callers. It cannot be invoked as
an instance method or return a value.

Before the constructor body, every `var` field receives its declared default or
its type's intrinsic value when one exists. A `var` field with neither must be
assigned on every normal path. A `let` field with a declared default is already
initialized and cannot be assigned in the body. A `let` field without a default
starts uninitialized even when its type has an intrinsic value; every
constructor of the declaring class must assign it exactly once on every normal
path. An uninitialized field cannot be read, and `self` cannot escape or receive
an instance-method call until every field is initialized. A bare `return` is
valid only after that point.

Declaring any `init` closes the named field initializer for that class. Every
construction must then select a visible constructor; defaults do not synthesize
missing overloads:

```sx
class Session {
    var token:str

    pub init(token:str) {
        self.token = token
    }
}

var session = Session("abc") // accepted
var empty = Session()        // rejected: no init()
Session(token:"abc")         // rejected: named fields are closed
```

A class without any `init` keeps its existing named field initializer,
including `Type()` when its fields permit it. Structures do not have custom
constructors.

## Single inheritance

A class may name one immediate base class after `:`. The base is part of the
same shared-identity instance; it is not a copied or separately allocated
object:

```sx
class Entity {
    sub var position:int

    sub init(position:int) {
        self.position = position
    }

    pub func move(delta:int) {
        self.position += delta
    }
}

class Player : Entity {
    var name:str

    pub init(name:str, position:int) : super(position) {
        self.name = name
    }
}

var player = Player("Ada", 1)
player.move(2)
```

Inheritance is transitive but always single. The base must be a visible class;
structures, multiple bases and inheritance cycles are rejected.

The `: super(...)` suffix selects a `sub` or `pub` constructor of the immediate
base with positional overload rules. A private base constructor is not
accessible. Omitting the suffix means `: super()` and is valid only when the
base has an accessible zero-argument construction. The complete base is built
before the child's declared field values and constructor body. Base
constructors are never inherited as constructors of the child. Only the
constructor of the class that declares a `let` field may initialize it; a child
may read an inherited `sub let` field but cannot replace it.

When a base has no custom constructor, `super()` uses its historical field
construction only if every required base field has a declared or intrinsic
value. A child without custom constructors keeps the named initializer for its
own `pub` fields when that same base construction is available. Inherited
fields never become named arguments of the child initializer.

An inherited `pub` method remains available through the child. Code in a child
may also use `sub` fields and methods declared anywhere in its base chain,
including through another instance from that hierarchy. Private members remain
exclusive to their declaring class. A child field cannot reuse an inherited
field name. An identical accessible inherited method signature requires the
explicit `override` marker.

A child reference converts implicitly to any base reference for a binding,
argument, return value or optional promotion. The conversion keeps a strong
reference to the complete instance, so related references compare by the same
identity:

```sx
func update(entity:Entity) {
    entity.move(1)
}

var player = Player("Ada", 1)
var entity:Entity = player
update(player)
print(entity == player) // true
```

The reverse conversion is not implicit. Mutable collections are invariant:
`Player[]` does not convert to `Entity[]`. A new `Entity[]` may nevertheless be
built from player expressions because each element is converted while the new
collection is created.

## Method overriding and dynamic dispatch

Every `sub` or `pub` instance method can be overridden. The child writes
`override` before the visibility marker, and keeps the same ordered parameter
types, `&` markers, and return type. An override cannot reduce visibility: a
`pub` method remains `pub`, while a `sub` method may remain `sub` or become
`pub`. The base method needs no prior marker such as `virtual`.

```sx
class Entity {
    pub func update() {
        print("entity")
    }
}

class Player : Entity {
    override pub func update() {
        super.update()
        print("player")
    }
}

var entity:Entity = Player()
entity.update() // entity, then player
```

The call first selects a signature from the static type, using ordinary
overload rules. It then runs the matching implementation from the instance's
real class. A base-typed binding, parameter, return, field, or unwrapped
optional therefore preserves dynamic dispatch, but child-only overloads do not
become visible through the base type.

Inside a child method, `super.method(...)` directly calls the implementation
available from the immediate base and does not dispatch back into the child.
It is not a value and cannot access private base members. During construction,
a call on `self` remains attached to the class whose constructor is currently
running; child overrides become active only after the complete instance has
been built.

A private method is never overridable. A child may independently declare the
same name and signature without `override`: calls written in the base keep its
private method, while calls written in the child use the child's method.

## Member visibility

Every class field and method is private by default. A private member is
accessible from methods of its declaring class, including through another
instance of that same class, but not from other code in the module.

For a field, visibility precedes mutability: `pub var name:str`,
`sub let generation:int`, or the private form `let id:int`.

`pub` exposes a member everywhere the class is visible. `sub` reserves a member
for its declaring class and descendants:

```sx
pub class Session {
    var secret:str = ""
    sub var generation:int = 0
    pub var token:str

    pub func reset_from(other:Session) {
        self.secret = other.secret
        self.generation = other.generation
    }
}
```

There is no explicit `private` keyword: the absence of a marker is the
canonical private form.

A named initializer is also an external member access. It can name only `pub`
fields, while private and `sub` fields must obtain their declared defaults:

```sx
var session = Session(token:"abc") // accepted
Session(secret:"abc", token:"def") // rejected: secret is private
```

A private required field without a default can be established by a visible
custom constructor. Structure members remain public by default; `pub` and
`sub` member markers are specific to classes.

## Bindings and shared mutation

A class reference always uses `var`, whether it is a local binding or a field.
Another reference can mutate the same instance without assigning the local name,
so it cannot satisfy `let`'s independent-value guarantee. This restriction is
recursive: an optional, structure, array, list, or function value that can reach
a class also uses `var`.

```sx
struct Selection {
    var player:Player?
}

var selection = Selection(player:Player())
var players = [Player()]
```

The container itself still has its normal value behaviour. For example, copying
`players` creates a distinct list, but the corresponding elements in both lists
refer to the same `Player` instances.

`&Player` is invalid because `Player` already has reference semantics. An
`&Player?` parameter is valid: it aliases the caller's optional place and may
replace that place with another player or with `null`.

## Optionals and identity

`Player?` follows the generic optional contract: `null`, promotion from
`Player`, narrowing, `var` conditional bindings, safe access with `?.`, and
replacement through `&Player?`. Extracting or copying a present optional keeps
the instance identity.

Two class references compare equal only when they designate the same instance.
Their field contents do not participate in equality. References from the same
inheritance chain are compared after conversion to their common related type;
unrelated class types are not comparable. Two optionals compare equal when both
are `null` or both contain the same instance under those rules.

## Automatic lifetime

Class memory is automatic. An upcast keeps one strong reference to the entire
most-derived instance; base parts are never released separately. Dropping the
last reference releases an acyclic instance immediately. The runtime also
traces fields from every class in the base chain and class references stored
through optionals, structures, arrays, lists, and captured function values, and
collects an unreachable cycle without requiring `weak`, manual destruction,
or a public collector call.

A class may declare one automatic `drop` block for native resources:

```sx
class Texture {
    var handle:SDL.Texture

    pub init(renderer:Renderer) {
        self.handle = SDL.create_texture(renderer.get_handle())
    }

    drop {
        SDL.destroy_texture(self.handle)
    }
}
```

`drop` has no parameters, parentheses, return type, or visibility marker. It
receives `self` implicitly, can read private state, cannot return, and cannot be
called explicitly. Structures cannot declare it.

The runtime calls `drop` exactly once before clearing the instance fields. An
acyclic instance runs it when its last strong reference disappears. For an
unreachable cycle, every instance runs its block while the graph fields are
still intact, before the runtime breaks the internal references; the order
between distinct instances in that graph is unspecified.

Each class in an inheritance chain may declare its own block. The most-derived
block runs first, followed automatically by each base block. This is not an
override and requires no `super` call.

A lambda still captures its outer binding under the ordinary lexical rules.
When that binding contains a class, the runtime keeps the binding in the traced
graph: mutation and reassignment inside the lambda remain visible through the
outer `var`, and the lambda still cannot outlive its lexical scope.

An object that is still reachable from program state remains alive even if the
program will not use it again. A native wrapper may therefore also expose an
explicit, idempotent operation such as `close()` when its resource must be
released before the instance itself becomes unreachable. `drop` remains the
automatic final guarantee and must tolerate that earlier release.

Interfaces and weak references are not part of the current language.
