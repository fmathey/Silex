# Expressions and statements

## Operators

The current precedence order, from highest to lowest, is explicit conversion
(`as type`), prefix `!` and `-`, `*` and `/`, `+` and `-`, ordering
comparisons, equality, `&&`, then `||`. Binary operators associate to the left.
`&&` and `||` short-circuit.

Arithmetic and ordering comparisons require compatible numeric operands, except
that `+` also concatenates two strings. Equality uses the same numeric
compatibility rules, compares strings by bytes, and compares two values of the
same structure type recursively by their fields. `print` accepts numbers,
`bool`, and `str`.

Mutable numeric places support `+=`, `-=`, `*=`, `/=`, `++`, and `--`; `+=`
also concatenates strings. `++` and `--` are postfix statements, not values.

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
the next segment.

```sx
var values:int[] = []
    ..append(10)
    ..append(20)
    ..reverse()
```

A cascade accepts a method call or direct field assignment. It follows the
ordinary mutability, borrow, and move rules. The two dots are one token and
cannot be separated by whitespace; indentation is conventional only.
