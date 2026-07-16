# Classes

A `class` is a nominal type with shared identity. Copying a class reference,
passing it as an ordinary argument, returning it, or storing it in a field or
collection keeps the same instance instead of copying its fields.

```sx
class Player {
    health:int = 100

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
syntax as structures. Every field without a declared default must be supplied.
Construction is explicit: a non-optional declaration such as
`var player:Player` is invalid, because a class has no intrinsic instance.
`var player:Player?` is valid and starts as `null` under the ordinary
optional-value rules. A class may be declared `pub`.

## Constructors

`init` declares a class constructor. It has no `func` prefix or return type and
receives `self` implicitly:

```sx
class Session {
    token:str
    attempts:int = 1

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

Before the constructor body, fields receive their declared default or their
type's intrinsic value when one exists. A field with neither must be assigned
on every normal path. An uninitialized field cannot be read, and `self` cannot
escape or receive an instance-method call until every field is initialized.
A bare `return` is valid only after that point.

Declaring any `init` closes the named field initializer for that class. Every
construction must then select a visible constructor; defaults do not synthesize
missing overloads:

```sx
class Session {
    token:str

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

## Member visibility

Every class field and method is private by default. A private member is
accessible from methods of its declaring class, including through another
instance of that same class, but not from other code in the module.

`pub` exposes a member everywhere the class is visible. `sub` reserves a member
for its declaring class and its future descendants:

```sx
pub class Session {
    secret:str = ""
    sub generation:int = 0
    pub token:str

    pub func reset_from(other:Session) {
        self.secret = other.secret
        self.generation = other.generation
    }
}
```

Inheritance is not currently part of Silex, so a `sub` member can presently be
used only by its declaring class. There is no explicit `private` keyword: the
absence of a marker is the canonical private form.

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

A class reference always uses `var`. Another reference can mutate the same
instance without assigning the local name, so it cannot satisfy `let`'s
independent-value guarantee. This restriction is recursive: an optional,
structure, array, list, or function value that can reach a class also uses
`var`.

```sx
struct Selection {
    player:Player?
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

Two values of the same class compare equal only when they designate the same
instance. Their field contents do not participate in equality. Two optionals
of that class compare equal when both are `null` or both contain the same
instance. Different class types are not comparable.

## Automatic lifetime

Class memory is automatic. Dropping the last reference releases an acyclic
instance immediately. The runtime also traces class references stored through
optionals, structures, arrays, lists, and captured function values, and
collects an unreachable cycle without requiring `weak`, manual destruction, or
a public collector call.

A lambda still captures its outer binding under the ordinary lexical rules.
When that binding contains a class, the runtime keeps the binding in the traced
graph: mutation and reassignment inside the lambda remain visible through the
outer `var`, and the lambda still cannot outlive its lexical scope.

An object that is still reachable from program state remains alive even if the
program will not use it again. Native resources therefore keep an explicit,
idempotent operation such as `close()` for deterministic release; cycle
collection is not an observable Silex destructor or finalizer.

Inheritance, interfaces, virtual methods, weak references, user destructors,
and finalizers are not part of the current language.
