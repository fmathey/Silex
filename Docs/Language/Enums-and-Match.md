# Enums and exhaustive match

An `enum` is a closed nominal value type. Its variants may carry zero or more
positional associated values, or the enum may declare one fixed raw value per
variant. Variants have no implicit integer value and an enum has no intrinsic
default value.

```sx
enum Connection {
    waiting
    connected(str)
    closed(str)
}

let waiting = Connection.waiting()
let connected = Connection.connected("server")
```

A variant is always constructed through its enum type and always uses
parentheses, including a variant without associated values. Associated values
must match the declared count and types. Variant names are unique within their
enum; different enums may reuse the same names.

Enums have value semantics. Copying an enum copies its active variant and all
associated values. An enum qualifies for `let` exactly when every associated
type of every variant is recursively independent. A variant containing a
function value or class reference therefore requires a `var` binding, directly
or through another value.

Enums do not declare methods or fields and do not receive automatic conversions
or equality operations.

## Generic enums

An associated-value enum may declare type parameters after its name. Every use
supplies one explicit type argument per parameter:

```sx
enum Outcome<T, E> {
    success(T)
    failure(E)
}

enum ParseError {
    invalid
}

let parsed = Outcome<int, ParseError>.success(42)
let text = match parsed {
    success(number) => "success"
    failure(error) => "failure"
}
```

`Outcome<int, ParseError>` and `Outcome<str, ParseError>` are distinct nominal
types. Repeating the same arguments denotes the same specialization throughout
the application and across module boundaries. Type parameters may appear in
any associated value type, including collections, optionals, function types,
and other generic specializations.

Arguments are never inferred: annotations, function parameters and returns,
aliases, and variant constructors use the complete specialization. `void` is a
return type rather than a value type and cannot be an argument; a function type
such as `func()` remains a valid argument. A specialization is checked by the
ordinary enum rules, so copying, `let`, and match binding independence depend
on its concrete associated types.

Raw `int` and `str` enums cannot be generic. Generic enums have no constraints,
default arguments, or independently generic variants.

## Raw enum values

An enum may declare `int` or `str` as its raw type. Every variant then assigns
one unique literal of that type:

```sx
enum Direction:int {
    north = 1
    south = 2
}

enum DirectionName:str {
    north = "north"
    south = "south"
}
```

The fixed value is exposed through the read-only `raw_value` property:

```sx
let direction = Direction.north()
let code:int = direction.raw_value
let text:str = DirectionName.south().raw_value
```

`raw_value` is intrinsic to a raw enum rather than a declared field. It cannot
be assigned or passed with `&`. An enum without a raw type has no such
property. There is no implicit or explicit conversion between the enum and its
raw type, and a raw value cannot construct an enum in this version.

Raw values and associated values are deliberately separate forms. A raw enum
variant cannot carry `(Type)`, while an associated-value enum cannot write
`= value`. Raw integer values are signed `int` literals, including a leading
minus. Raw strings compare after escape decoding when uniqueness is checked.
Calculations, function calls, conversions, omitted values and duplicate raw
values are compile-time errors.

## Match expressions

`match` evaluates its subject once and requires one branch for every variant
of that enum. Each variant must appear exactly once; an unknown, repeated, or
missing variant is a compile-time error unless a terminal `else` branch covers
the variants not named explicitly.

```sx
func describe(connection:Connection) str {
    return match connection {
        waiting => "waiting"
        connected(name) => name
        closed(reason) => reason
    }
}
```

An expression match has one expression after every `=>`. All branches must
resolve to exactly the same type. Branches do not apply numeric widening,
optional wrapping, or another convergence conversion to manufacture a common
type. The resulting match is itself an expression and may initialize a value,
be returned, or be passed as an argument.

## Default branch

A terminal `else` branch handles every variant that was not named before it:

```sx
let vertical = match direction {
    north => true
    south => true
    else => false
}
```

`else` is optional. Without it, the match remains exhaustive and adding a new
enum variant reveals every match that must be updated. With it, adding a new
variant deliberately routes that variant through the existing default branch.

Only one `else` branch is allowed, it must be last, and it cannot bind
associated values. The branch is rejected when every variant was already
handled because it would be unreachable. Its body follows the same form and
type rules as every other branch: an expression match requires an expression
of the common result type, while an imperative match requires a block.

An ordinary pattern names only the variant. Parentheses bind every associated
value in declaration order. A binding without a marker is an implicit `let`;
explicit `let` is equivalent, and `var` creates a mutable local copy:

```sx
let text = match connection {
    waiting => "waiting"
    connected(name) => name
    closed(let reason) => reason
}
```

An immutable binding requires an independent associated type, under the same
rule as an ordinary `let`. Use `var` for a mutable binding or for a function,
class, or recursively non-independent associated value. Bindings exist only
inside their branch and copy the associated values; matching never consumes or
mutates the subject.

## Imperative match

When every branch body is a block, `match` is a statement-like expression of
type `void`:

```sx
match connection {
    waiting => {
        print("waiting")
    }
    connected(var name) => {
        name += "!"
        print(name)
    }
    closed(reason) => {
        print(reason)
    }
}
```

Expression branches and block branches cannot be mixed. `break`, `continue`,
and `return` inside an imperative branch retain their ordinary meaning in the
surrounding loop or function.

The initial pattern language remains intentionally exact outside this explicit
escape hatch: there is no wildcard, guard, literal pattern, nested pattern, or
fallthrough.
