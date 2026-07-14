# Collections

Silex has fixed arrays, written `T[N]`, and dynamic lists, written `T[]`.
Both have value semantics; the fixed length `N` is part of an array type.

```sx
let axes:int[3] = [1, 2, 3]
var scores:int[] = []
```

A non-empty literal without an expected type infers a dynamic list from its
first element. An empty literal requires an explicit or expected collection
type. An array literal must contain exactly `N` values.

Both collection kinds have `count()`, `is_empty()`, indexed reads and writes,
`swap`, `reverse`, and `replace`. Indexes have type `int`; `^1` names the last
element, `^2` the one before it. Out-of-range access is a Silex runtime error.

```sx
var values:int[] = [10, 20, 30]
let last:int = values[^1]
values[1] = 25
let previous:int = values.replace(1, 40)
```

Dynamic lists also provide `append`, `prepend`, `insert`, `take`,
`take_first`, `take_last`, and `clear`. `append` accepts one compatible element
or a compatible sequence. Assigning a list, passing it to an ordinary
parameter, or returning it preserves independent value behaviour; a list is
separated only if one of those values is later mutated.
