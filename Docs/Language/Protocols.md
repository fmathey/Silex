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

A protocol name is not yet a general value type. In particular,
`var drawable:Drawable = Player()` is reserved for the future dynamic protocol
value feature and is rejected today. Use `T : Drawable` when the concrete type
should remain statically known.
