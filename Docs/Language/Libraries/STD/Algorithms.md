# Algorithms

The algorithms are split by responsibility. Import sorting with:

```sx
use STD.Algorithms.Sort.sort
```

Search and transformation functions live in `STD.Algorithms.Iteration`, while
borrowed random selection and shuffling live in `STD.Algorithms.Random`:

```sx
use STD.Algorithms.Iteration.find
use STD.Algorithms.Random as RandomAlgorithms
```

## Search and quantification

`any<T>`, `all<T>`, `count_where<T>`, `find<T>`, and `contains<T>` consume a
local copy of an owned `Iterator<T>`. The caller's cursor is never advanced,
and only the values remaining at the time of that copy are inspected.

`any` returns `false` for an empty source and stops at the first matching
value. `all` returns `true` for an empty source and stops at the first rejected
value. `count_where` calls its predicate once per value. `find` returns the
first matching value, while `contains` uses its explicit equality callback as
`equal(element, expected)` and does not hide `==` or hashing.

For `r` remaining values these functions are O(r) in the worst case and O(1)
in auxiliary storage outside the iterator parameter's value copy. Predicates
receive temporary read borrows. Captures follow ordinary callback lifetime
rules, and a panic propagates without replaying a callback.

## Transformation and filtering

`map<T, U>` calls its transform exactly once for every remaining value and
returns an owned `Iterator<U>` in the same order. `filter<T>` calls its
predicate once per remaining value and copies accepted values into a new
`Iterator<T>`. Empty inputs produce empty outputs.

Both functions evaluate immediately, advance only their local iterator copy,
and leave the original collection and caller cursor unchanged. For `r`
remaining values they take O(r) time. `map` stores exactly `r` results;
`filter` stores between zero and `r`. They provide no lazy chain, flattening,
or mutable in-place transformation.

## In-place sort

```sx
public func sort<T>(
    values:&T[..],
    before:func(@T, @T) bool,
)
```

`sort<T>` reorders only the elements in `values`. `before(left, right)` must
return `true` exactly when `left` belongs before `right`; it must define a
strict weak order. Type arguments remain explicit:

```sx
var values:int[] = [4, 1, 3, 2]
var view = &values[0:values.count()]
sort<int>(view, func(left:@int, right:@int) bool {
    return left < right
})
```

The sort is not stable, so equivalent elements may change relative order. It
performs O(n log n) comparisons and swaps in the worst case, uses O(1)
auxiliary storage, and does not copy elements. Empty and one-element views do
not invoke `before`.

If `before` does not define a strict weak order, the result is unspecified but
the call still terminates and the view remains a permutation of its original
elements. A panic from `before` propagates; the partially reordered view is
still a valid permutation.

Lists, fixed arrays, and mutable sub-views are accepted through `&T[..]`. The
source is neither resized nor extended outside the selected view. Sorting an
iterator, stable sorting, sorting by a cached key, and a default ordering are
not provided.

## Random collection algorithms

```sx
public func choose<T>(
    randomizer:Randomizer,
    values:@T[..],
) @T

public func shuffle<T>(
    randomizer:Randomizer,
    values:&T[..],
)

extend Randomizer {
    public func choose<T>(values:@T[..]) @T
    public func shuffle<T>(values:&T[..])
}
```

`choose<T>` draws one index uniformly from a non-empty view and returns a
shared borrow of that element. The result retains the provenance of `values`:
while the alias is in scope, the source cannot be mutated incompatibly. It
does not copy or allocate. An empty view terminates with
`Algorithms.choose requires a non-empty collection`.

`shuffle<T>` performs an in-place Fisher-Yates permutation. For `n` elements,
it makes exactly `max(n - 1, 0)` bounded random draws, O(n) swaps at worst, and
uses O(1) additional storage. Empty and one-element views perform no draw.
Only the selected view is reordered, and elements outside a mutable sub-view
remain unchanged.

Both operations accept noncopyable elements because `choose` borrows and
`shuffle` uses only `swap`. `Randomizer` is a class, so passing it normally
advances the same shared generator state as direct calls to `get_int`.
Selecting `STD.Algorithms.Random` also activates the two method façades. They delegate
to the functions above and advance the same generator state; the free
`Algorithms.*` forms remain the canonical implementation and API reference.

```sx
use STD.Algorithms.Random as Algorithms
use STD.Randomizer as Randomizer

func show(value:@int) {
    print(value)
}

var randomizer = Randomizer.create(42)
let candidates:int[] = [10, 20, 30]
if true {
    let candidates_view = @candidates[0:candidates.count()]
    let selected:@int = Algorithms.choose<int>(randomizer, candidates_view)
    show(selected)
}

var values:int[] = [1, 2, 3, 4]
var values_view = &values[0:values.count()]
Algorithms.shuffle<int>(randomizer, values_view)

let method_candidates = @candidates[0:candidates.count()]
let method_selected:@int = randomizer.choose<int>(method_candidates)
var method_values = &values[0:values.count()]
randomizer.shuffle<int>(method_values)
```

The same Silex version, seed, input, and sequence of calls produce the same
result. A permutation is not promised to remain identical if the internal
`Randomizer` algorithm changes. These operations provide neither weighted or
multiple selection nor cryptographically secure randomness.
