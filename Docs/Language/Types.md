# Types and conversions

## Primitive types

Silex provides `void`, `bool`, signed integers from `int8` through `int64`,
unsigned integers from `uint8` through `uint64`, `float32`, `float64`, and
UTF-8 strings (`str`). `int`, `uint`, and `float` are aliases for `int64`,
`uint64`, and `float32`.

An integer literal defaults to `int`; a decimal literal defaults to `float`.
Integer literals accept decimal, binary (`0b`), octal (`0o`), and hexadecimal
(`0x`) bases. `_` may separate digits. Decimal floating literals require digits
on both sides of the decimal point and may use an exponent.

## Numeric operations

Integer operations keep an exact type and check overflow and division by zero
at runtime. They never silently wrap or saturate. `float32` and `float64`
follow IEEE-754. Compatible integer types widen to the wider type of the same
signedness; `float32` can widen to `float64`; integers may widen to floating
point values. Signed and unsigned integers never mix implicitly.

`expression as type` performs an explicit numeric conversion. Both types must
be numeric. Narrowing, integer-to-float, and float-to-integer conversions are
checked at runtime: no loss of range, sign, fractional part, or precision is
accepted silently.

```sx
let byte:uint8 = count as uint8
let whole:int = (ratio * 10.0) as int
```

## Strings

`str` is an immutable sequence of valid UTF-8 bytes. Equality compares bytes;
Silex does not normalize Unicode. Strings support `+`, `+=`, and `count()`,
which returns the number of Unicode scalar values. String indexing and slicing
are not part of the language yet.

Permitted escapes are `\\`, `\"`, `\n`, `\r`, `\t`, `\0`, and
`\u{H...}` for a valid Unicode scalar. A raw newline or an invalid escape is a
compile-time error.

## Function types

`func(int, str) bool` accepts an `int` and a `str` and returns `bool`.
`func(int)` returns `void`; the explicit spelling `func(int) void` is accepted
but is not canonical. Function types may be nested in collection and structure
types. A lambda supplies a function value; named overloaded declarations do not
implicitly convert to one.

`func(&int)` has a mutable-reference parameter. Its calls use an ordinary
argument such as `callback(place)`; the function type selects mutable-reference
binding exactly like a named function whose parameter is written `value:&int`.

## Protocol types

A protocol name such as `Drawable` is a dynamic value type. It can contain any
structure or class that explicitly declares that conformance, while exposing
only the methods required by the protocol. The source spelling is simply
`value:Drawable`; Silex does not use an `any` prefix. See
[Protocols](Protocols.md#dynamic-protocol-values) for dispatch, copy, and
lifetime rules.

## Type suffixes and grouping

`?`, `[]`, and `[N]` are type suffixes applied from left to right. Thus
`Position?[]` is a list of optional positions, `Position[]?` is an optional
list, and `int?[3]` is an array of optional integers. Parentheses may group any
complete type; `(func(int))?` is an optional function value, while
`func(int) Position?` is a function returning an optional position.

See [Optional values](Optional-Values.md) for `null`, presence checks,
conditional bindings, and safe access.

## Type aliases

`use <type> as <name>` gives a complete type a transparent local name. For
example, `use int[] as Integers` makes `Integers` and `int[]` exactly the same
type. See [Modules](Modules.md#transparent-type-aliases) for local aliases,
exports, chains, and diagnostics.
