# Algorithms

Import the generic algorithms with:

```sx
use STD.Algorithms.sort
```

## In-place sort

```sx
pub func sort<T>(
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
