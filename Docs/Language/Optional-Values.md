# Optional values

`T?` contains either one value of non-`void` type `T` or the explicit absence
`null`. The intrinsic value of every optional is `null`; intrinsic values of
non-optional types remain unchanged. `void?` and a directly nested `T??` are
invalid.

```sx
let count:int?                 // null
let title:str? = "Silex"      // implicit str -> str?
let positions:Position?[] = []
let cache:Position[]?          // null
var callback:(func(int))? = null
```

`null` is a reserved keyword and needs an expected optional type from an
annotation, parameter, return, field, or already typed collection. It cannot
infer `let value = null`, an untyped `[null]`, or `null == null`. A plain `T`
promotes to `T?`; an optional never converts implicitly to `T`. Native function
interfaces do not accept optional parameters or returns.

## Presence and equality

An optional compares with `null` using `==` or `!=`. Two compatible optionals
are equal when both are absent or when both contained values are equal. A
direct comparison between a local optional binding and `null` narrows that
name to `T` in the branch proving presence. The comparison may use either
operand order. No proof is propagated through `!`, `&&`, or `||`, and fields
and indexed elements are not narrowed.

```sx
if position != null {
    print(position.x)
} else {
    print("missing")
}
```

An immutable `let` remains narrowed throughout that branch. A mutable `var`
loses the proof when it is assigned or passed through a mutable `&` parameter;
subsequent uses again have type `T?`.

## Conditional bindings

`if`, `elif`, `else if`, and `while` can extract a present value. The binding
contains exactly one unannotated name. Without a marker it is an implicit
`let`, hence an immutable local copy. An explicit `let` remains accepted;
`var` creates a mutable local copy. The implicit form and `let` are available
only when the extracted type is an independent value; an optional function or
class uses `var`. The binding is visible only in the associated body.

```sx
if position = find_position() {
    print(position.x)
}

while (var position = find_position()) {
    position.translate(1)
}
```

An `if` source is evaluated once if its branch is reached. A `while` source is
evaluated once before every attempt, including after `continue`; `null` ends
the loop and `break` does not evaluate the source again.

## Safe member access

`receiver?.member` evaluates an optional receiver once. If absent, the member
is skipped. A safe call also skips its arguments. A value result `U` becomes
`U?`, an existing `U?` stays flat, and a `void` call stays `void`. Every
nullable step needs its own `?.`.

```sx
let x:int? = profile?.position?.x

var position:Position?
position = Position(x:1, y:2)
position?.translate(3)
```

A mutating safe method call requires a mutable optional place. It is invalid
through `let`. Safe assignment, safe indexing, forced extraction, substitution
such as `??`, and direct calls of optional function values are not defined.
