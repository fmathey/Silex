# Type extensions

`extend` adds methods to an existing nominal structure or class without
changing the declaration, storage, initialization, or identity of that type.
The target may be local or selected with `use`:

```sx
use STD.Randomizer as Randomizer

extend Randomizer {
    pub func get_uint() uint {
        return self.get_int() as uint
    }

    pub static func seeded(seed:int) Randomizer {
        return Randomizer.create(seed)
    }
}
```

An extension method uses the ordinary method syntax. Instance methods declare
`self` implicitly through the target type and become mutating when they write
through `self` or call another mutating method. A `static func` is selected
through the complete type and has no receiver:

```sx
var randomizer = Randomizer.seeded(42)
let value = randomizer.get_uint()
```

Extension methods are resolved statically from the receiver's declared type.
They do not enter class virtual dispatch and are not inherited. Extending
`Entity` does not make the method a member of `Player`, and a value declared as
`Entity` cannot select an extension written for `Player`.

## Generic extension methods

An instance method in `extend` may declare its own type parameters and nominal
constraints. Every argument remains explicit at the call site, and the
signature and body are specialized before ordinary overload selection:

```sx
extend Randomizer {
    pub func choose<T>(values:@T[..]) @T {
        return Algorithms.choose<T>(self, values)
    }
}

let selected:@int = randomizer.choose<int>(values)
```

Type parameters are available everywhere a generic free function permits
them, including composed parameter and return types, local annotations, and
calls to other generic declarations. Repeating the same target, extension
method, declaring module, and concrete arguments reuses one specialization.
Constraints, recursion, overload ambiguity, and arity diagnostics follow the
rules in [Functions](Functions.md#generic-functions).

Calling the method without `<...>` performs no inference and considers only
non-generic methods of that name. When exactly one borrowed parameter exists,
an unqualified borrowed return originates from it; with none it originates
from `self`. Ambiguous methods qualify the root as `@self:T` or
`@parameter:T`. The returned alias keeps that caller root borrowed.

## Protocol conformances

An extension can explicitly add one or more nominal protocol conformances:

```sx
protocol Drawable {
    func draw()
}

struct Sprite {
}

extend Sprite : Drawable {
    func draw() {
    }
}
```

The target then converts to the dynamic protocol type and satisfies a matching
generic constraint wherever that extension is active. Requirement methods must
be public instance methods with the ordinary matching signature. They may
already belong to the target or be declared in an extension. An unmarked
extension method follows its target's member default: public for a structure
and private for a class. A class extension therefore writes `pub func` when its
method satisfies a protocol requirement.

A conformance extension applies only to its exact nominal target. A class
descendant does not inherit it. The conformance changes no field, layout,
initializer, base class, or virtual dispatch slot; the compiler generates its
protocol witness separately.

Only one conformance between a given type and protocol may exist in the whole
compilation. A duplicate in the type declaration or another extension is an
error even when the two extension modules are not directly used together.
This global coherence keeps dynamic witnesses and generic specializations
unambiguous.

## Visibility and uses

An unmarked method takes the target's default member visibility. A structure
extension method is therefore public and becomes active in a source file that
directly selects its declaring module or source unit. A class extension method
remains private to that module unless it uses `pub`. The explicit marker
remains accepted for structure extensions even though it is redundant there:

```sx
use MyLibrary.RandomExtensions as RandomExtensions

func sample(randomizer:Randomizer) uint {
    return randomizer.get_uint()
}
```

That module `use` activates all public extension methods and conformances it
declares. A `use` selecting a unit or declaration activates those supplied
by its same-module unit closure; a `use` selecting a module activates all its
direct units. Merely compiling another module or package reached beyond that
closure does not activate its extensions. Each consuming source file names the
module, unit, or declaration it wants directly, following the ordinary
file-scoped dependency rules.

An extension has the access rights of an outside caller. Its body can use only
the target's `pub` members, never private or `sub` members, even when the
extension is declared in the module that owns the type.

## Coherence and limits

An extension cannot repeat the exact signature of a method declared by the
type. Two visible extensions cannot provide the same exact signature either,
including generic signatures that differ only in their type-parameter names;
the diagnostic names both extension modules instead of choosing according to
source or dependency order. Different signatures remain ordinary overloads.

Extensions add behavior only. They cannot declare fields, constructors,
`drop`, `override`, or `sub` members. Names after `:` must be protocols and can
never add a base class. Extensions cannot target an enum, protocol, scalar,
collection, generic type, or one specialization of a generic type. Generic
methods remain unavailable directly in a structure or class, as static
extension methods, as protocol requirements, and as protocol-conformance
witnesses. Generic constructors, generic native methods, type-argument
inference, and generic extension targets are also unavailable.
