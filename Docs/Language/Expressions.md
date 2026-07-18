# Expressions and statements

## Operators

The current precedence order, from highest to lowest, is explicit conversion
(`as type`), prefix `try`, `move`, `!`, and `-`, `*`, `/`, and `%`, `+` and `-`, `<<` and `>>`,
`&`, `^`, ordering comparisons, equality, `&&`, then `||`. Binary operators
associate to the left. `&&` and `||` short-circuit.

Arithmetic and ordering comparisons require compatible numeric operands, except
that `+` also concatenates two strings. Equality uses the same numeric
compatibility rules, compares strings by bytes, and compares two values of the
same ordinary structure type recursively by their fields. A unique resource
structure declaring `drop`, and every structure or container recursively made
noncopyable by such a value, does not support equality. `print` accepts
numbers, `bool`, and `str`.

Mutable numeric places support `+=`, `-=`, `*=`, `/=`, `++`, and `--`; `+=`
also concatenates strings. `++` and `--` are postfix statements, not values.

Optional values only support `==` and `!=` directly. They may be compared with
`null`, with a compatible optional, or with a plain value promoted to an
optional. `?.` performs safe member or method access and evaluates its receiver
once; a missing receiver skips the access and all call arguments. See
[Optional values](Optional-Values.md).

`%` computes the remainder of an integer division. Its operands use the same
compatible integer widening as `/`, and its result has that common integer
type. Signed division truncates toward zero, so `-17 % 5` is `-2`. A zero
divisor and the signed minimum modulo `-1` stop execution with the same
division runtime errors as `/`.

`&` and `^` operate on compatible unsigned integers and widen to the wider
unsigned operand type. `<<` and `>>` keep the type of their unsigned left
operand; their count may be any integer, but must be at least zero and smaller
than that type's width, otherwise execution stops with a runtime error. A left
shift discards bits that leave its fixed-width value; a right shift fills with
zeroes. Parentheses are the canonical form when combining shifts and bitwise
operations.

## Statement endings

A simple statement ends at a newline, before `}`, or at an explicit semicolon.
Semicolons only separate multiple statements on one line.

```sx
let first = 1; let second = 2; print(first + second)
```

An expression may continue after `=` or an operator. Newlines are free inside
parentheses. Outside parentheses, an operator at the beginning of a new line
does not continue the previous statement, except for the cascade operator.

## Cascades

`..` applies several operations to the same receiver. The receiver is evaluated
once; every segment targets it directly, and ignored method results do not feed
the next segment. The distinct `...` operator is reserved for an integer range
inside `for`.

```sx
var values:int[] = []
    ..append(10)
    ..append(20)
    ..reverse()
```

A cascade accepts a method call or direct field assignment. Its receiver must
be mutable whenever an operation writes to it. The two dots are one token and
cannot be separated by whitespace; indentation is conventional only.

A single `.` ends the cascade and resumes ordinary member access on its
receiver. This makes it possible to mutate an object through several cascade
segments, then use the result of a regular query:

```sx
let running = stopwatch..reset()..start().is_running()
```

A range whose second bound is a call remains unambiguous:

```sx
for i in start...compute_end() {}
```

For long bounds, the named form `range(start, compute_end())` can remain easier
to read.
