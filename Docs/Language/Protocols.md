# Protocols

A `protocol` is a nominal contract made of public instance-method signatures.
Requirements have no body:

```sx
protocol Describable {
    func describe() str
}

pub protocol Drawable {
    func draw()
}
```

Protocols follow ordinary module visibility. A private protocol is available
inside its module; `pub protocol` can be imported, renamed, or re-exported.
Requirements cannot currently be generic, static, constructors, fields, or
default implementations. Protocol inheritance and generic protocols are not
part of the current language.

## Explicit conformance

A structure or class declares conformance after `:`. Conformance is nominal:
having methods with matching names is insufficient unless the protocol is
listed explicitly.

```sx
struct User : Describable {
    func describe() str {
        return "user"
    }
}

class Player : Entity, Describable, Drawable {
    pub func describe() str {
        return "player"
    }

    pub func draw() {
    }
}
```

For a class, the optional base class is first and every remaining name is a
protocol. When the first name is itself a protocol, the class has no base
class. For a structure, every name is a protocol; structures do not inherit
from structures.

The compiler verifies every declared conformance, even when no generic code
uses it. A matching method has the same name, ordered parameter types, `&`
markers, and return type. It must be an instance method and public. Structure
methods are already public; a class implementation therefore writes `pub`.
An inherited public class method can satisfy a requirement. A child class also
inherits every valid conformance of its base class.

## Static generic constraints

One protocol may constrain each generic type parameter:

```sx
func render<T : Drawable>(value:T) {
    value.draw()
}

render<Player>(Player())
```

Type arguments remain explicit. The concrete argument must declare the
required conformance, directly or through class inheritance. Silex then
specializes the complete generic body for that concrete type exactly as it
does for an unconstrained generic. The protocol adds a compile-time contract;
it does not add a runtime container or dynamic call.

## Dynamic protocol values

A protocol name is also a value type. A concrete structure or class converts
implicitly to that type when it declares the required conformance:

```sx
var drawable:Drawable = Player()
drawable.draw()
drawable = Icon()
```

No `any` marker is used. The static interface of `drawable` contains only the
requirements declared by `Drawable`; members specific to `Player`, its base
class, or another protocol are unavailable. The call dynamically selects the
implementation belonging to the concrete value currently stored.

The same protocol type may appear in parameters, return types, fields,
optionals, arrays, and lists:

```sx
func render(value:Drawable) {
    value.draw()
}

func make_drawable() Drawable {
    return Player()
}

struct Scene {
    var items:Drawable[]
}
```

Erasing a structure stores an independent copy. Copying the protocol value
copies that structure again, so later mutations remain independent. Erasing a
class stores a reference to the same instance: copying the protocol value
preserves object identity and participates in the ordinary reference counting
and cycle tracing rules.

A protocol value may therefore contain shared identity even when its current
concrete value is a structure. It is not considered an independent value and
uses `var` rather than `let`, directly or through a containing value. Calls
through a protocol value are conservatively mutable because a conforming
structure implementation may change its erased state.

`T : Drawable` and `Drawable` remain deliberately distinct. The generic form
keeps `T` concrete and specializes the function statically. The protocol value
erases the concrete type and uses dynamic dispatch. A value outside the
declared conformance cannot convert to `Drawable`, and there is currently no
cast from `Drawable` back to its concrete type.
