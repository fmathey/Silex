# Iterator

`STD.Iteration.Iterator` is an owned, copyable snapshot iterator. It stores no
borrow or pointer to its source.

```sx
use STD.Iteration.Iterator as Iterator

var values = Iterator<int>.empty()
values.push(10)
values.push(20)
while value = values.next() {
    print(value)
}
```

`push` appends after every value already present, including after exhaustion.
`next` returns each value once and then keeps returning `null` until another
push. Returned values are removed from the iterator's storage. `remaining` and
`is_empty` are O(1).

Copying an iterator copies both its remaining snapshot and logical position;
advancing either copy does not move the other. Elements retain their normal
value semantics, including shared class identity. Elements must be recursively
copyable.

`Queue.iterator()` snapshots FIFO order, and `Stack.iterator()` snapshots LIFO
order. `Dictionary.iterator()` returns `Entry<Key, Value>` values and
`Set.iterator()` returns elements in their unspecified table order. Snapshot
construction takes O(n) time and storage. Later source mutations do not affect
the iterator.

`STD.Iteration.Iterator.iterate` snapshots either a borrowed list or a borrowed
contiguous view. Fixed arrays require an explicit complete view, for example
`let view = @values[0:values.count()]` followed by `iterate<int>(view)`. This
API does not extend `for` and does not provide lazy or mutable-reference
iteration.
