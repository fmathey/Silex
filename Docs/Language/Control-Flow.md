# Control flow

`if` and `while` conditions must have type `bool`. Each branch and loop body
opens a lexical scope. Their canonical form places the condition directly
between the keyword and the block:

```sx
if enabled {
    print("enabled")
} else {
    print("disabled")
}

while count > 0 {
    count -= 1
}
```

An `if`, `elif`, `else if`, or `while` header may instead extract an optional
value with `let name = source` or `var name = source`. The source is evaluated
once per reached `if` branch and once before each `while` attempt. Parentheses
may wrap the complete binding; the unparenthesized form is canonical.

`let` requires the extracted type to be an independent value. Function values
and future class references, including values that contain them, use `var`.

```sx
if let position = find_position() {
    print(position.x)
} elif (var fallback = find_fallback()) {
    fallback.translate(1)
}

while let item = next_item() {
    print(item)
}
```

The extracted value is a local copy visible only in its body. A `while`
re-evaluates its source after the body or `continue`; `break` exits without
another evaluation. See [Optional values](Optional-Values.md).

Existing sources may still group the whole condition, as in `if (enabled) {}`
or `while (count > 0) {}`. These parentheses are the ordinary expression
grouping and do not change the compiler AST. They may instead group only a
subexpression: `if (enabled) && count > 0 {}`.

Outside parentheses, an operator at the end of a line continues the condition
on the next line. An operator that appears only at the beginning of the next
line does not. Newlines remain free inside a parenthesized expression, and the
opening brace may follow a completed condition on the next line.

An `if` may continue with any number of conditional branches and one final
`else`. The canonical spelling of a conditional branch is `elif`:

```sx
if first_condition {
    print("first")
} elif second_condition {
    print("second")
} elif third_condition {
    print("third")
} else {
    print("fallback")
}
```

`else if` is accepted as an equivalent spelling and may be mixed with `elif`
in one chain. Conditions are evaluated from top to bottom and stop at the first
successful branch. Every branch body has its own lexical scope. An explicit
`else { if condition {} }` remains a nested `if` inside a separate `else`
block; it is not another spelling of `elif`.

Newlines and comments may separate two branches, including between `else` and
`if`. Parentheses around an alternative condition follow the same rules as the
initial condition. `elif` is reserved and cannot be used as an identifier.

`for` iterates through a fixed array, dynamic list, or exclusive integer range.
Every iteration binding starts with `let` or `var`: `let` creates an immutable
binding for an independent element type, while `var` creates a mutable binding
and is required for non-independent element types such as callbacks.

```sx
for let value in values {
    print(value)
}

for var value in values {
    value += 1
}
```

The historical forms `for (let value in values) {}` and
`for (var value in values) {}` remain accepted. Here the parentheses wrap the
whole iteration binding rather than an expression. The form without them is
canonical.

For a collection, the source is evaluated once and held for the duration of
each loop body. An immutable loop allows other reads but no mutation of the
collection; a mutable loop binds directly to each element and allows no other
direct access to the collection.

An integer range can use `start...end` or the equivalent intrinsic
`range(start, end)`. `range` is reserved and available without an import. The
first bound is produced and the second bound is never produced:

```sx
for let i in 0...3 {
    print(i)
}

for let i in range(3, 0) {
    print(i)
}
```

Without the binding parentheses, `...` at the end of a line continues its
range on the next line; `...` appearing only at the beginning of the next line
does not. Newlines are free throughout a parenthesized binding.

These loops print `0`, `1`, `2`, then `3`, `2`, `1`. The direction follows the
order of the bounds; equal bounds produce no value. Both bounds have type
`int` and are evaluated once, from left to right, before iteration. No list or
array is created. In a range loop, `var` creates a mutable local copy; changing
it does not affect either bound or the next value produced.

`break` exits the nearest loop and `continue` starts its next iteration.

Pattern matching and string iteration are not part of the current language.
