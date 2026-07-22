# Set

`STD.Collections.Set` provides a generic hash set backed by
`STD.Collections.Dictionary`.

```sx
use STD.Collections.Set as Set
use STD.Collections.Hashing

var selected = Set<int>.create(Hashing.hash_int, Hashing.equal_int)
selected.insert(7)
selected.insert(7)
```

`Set<T>` requires recursively copyable elements and explicit hash and equality
callbacks. Equal values must have equal, stable hashes; equality must be an
equivalence relation. The callbacks in `STD.Collections.Hashing` can be used
for `bool`, `int`, `uint`, and `str`.

`insert` returns `true` only for a new equivalence class. A duplicate keeps the
first representative rather than replacing it. `remove` reports whether it
removed a value; `take` returns the representative that was actually stored.
`clear` keeps capacity available for reuse.

Copying a set copies its logical state, so later mutations are independent.
Function callbacks retain their ordinary captures. Their presence requires a
direct `var` binding and makes a set non-comparable, but not noncopyable.

`contains`, `insert`, `remove`, and `take` are O(1) on average under a
reasonably distributed hash and O(n) in the worst case. Growth is amortized,
and `reserve(k)` prevents further growth until at least `k` entries fit.
Capacity is an entry capacity, not a bucket count. No iteration order is
defined. `iterator()` creates an O(n) owned snapshot in that unspecified
order. Negative capacities passed to `create` or `reserve` panic.
