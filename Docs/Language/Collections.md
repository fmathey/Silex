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
`swap`, `reverse`, and `replace`. Indexes have type `int`; negative indexes are
relative to the end, so `-1` names the last element and `-2` the one before it.
Out-of-range access is a Silex runtime error.

```sx
var values:int[] = [10, 20, 30]
let last:int = values[-1]
values[1] = 25
let previous:int = values.replace(1, 40)
```

A local collection declared with `let` has immutable storage even when its
element type is not independent:

```sx
let players:Player[] = [Player(), Player()]
for player in players {
    player.draw()
}
```

The binding cannot be reassigned, resized, reordered, or used to replace an
element. A class instance reached through an element keeps its shared identity
and is not frozen. This rule applies to local fixed arrays and dynamic lists;
`let` fields and static storage keep their recursively independent-value
requirement.

Both collection kinds can also copy a contiguous slice into a dynamic list:

```sx
let middle:int[] = values[1:3]
let without_last:int[] = values[0:-1]
```

The start is included and the end is excluded. A negative bound is relative to
the end, and each bound is clamped between zero and the collection count. If
the normalized start is greater than or equal to the normalized end, the slice
is empty. Both bounds are required and evaluated once from left to right. The
result is an independent dynamic list; it is not a view into the source.
Because slicing copies, it is unavailable when the element type is
noncopyable.

Prefixing the same slice with `@` or `&` creates a non-owning contiguous view
instead of a list copy: `@values[1:3]` reads through `@T[..]`, while
`&values[1:3]` writes through `&T[..]`. See
[Values and mutation](Values-and-References.md#contiguous-borrowed-views).

Dynamic lists also provide `append`, `prepend`, `insert`, `take`,
`take_first`, `take_last`, and `clear`. `append` accepts one compatible element
or a compatible sequence. Assigning a list, passing it to an ordinary
parameter, or returning it preserves independent value behaviour; a list is
separated only if one of those values is later mutated.

A collection of noncopyable elements owns them and is itself noncopyable.
`append`, `prepend`, `insert`, and the replacement value of `replace` require
`move` for a named element and accept a temporary directly. `take`,
`take_first`, `take_last`, and `replace` transfer the removed element. An
indexed read that would copy is rejected; pass `values[index]` to an `@T`
parameter, use a read loop, or use `for var`. A read loop binds each
noncopyable element by temporary read-only alias, while `for let` remains a
copying form and is rejected.
