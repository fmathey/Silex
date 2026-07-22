# IO

```sx
use STD.IO
```

`STD.IO` defines synchronous binary stream contracts. They keep the concrete
resource type and its ownership through static generic constraints; they do not
create a universal stream object.

```sx
public protocol Reader {
    func read(buffer:&uint8[..]) Result<int,System.Error>
}

public protocol Writer {
    func write(buffer:@uint8[..]) Result<int,System.Error>
}
```

A successful `read` returns a count between zero and the supplied view size.
For a non-empty buffer, zero is definitive end-of-stream. An empty buffer is a
successful no-op. Only the returned prefix is modified; later bytes remain
unchanged.

`write` may consume only a prefix and returns its exact size. It must make
progress for non-empty input: returning zero is an error. Neither operation may
retain its borrowed view after returning.

The generic algorithms are:

```sx
public func read_exact<T:Reader>(reader:&T, buffer:&uint8[..]) Result<void,System.Error>
public func read_to_end<T:Reader>(reader:&T, maximum_bytes:int) Result<uint8[],System.Error>
public func write_all<T:Writer>(writer:&T, buffer:@uint8[..]) Result<void,System.Error>
public func copy<R:Reader, W:Writer>(reader:&R, writer:&W, maximum_bytes:int) Result<int,System.Error>
```

`read_exact` fills the complete view or returns `unexpected_end`. `write_all`
continues through partial writes and rejects a zero write. `read_to_end` and
`copy` reject negative limits with `invalid_input`; when another byte exists
beyond the limit, they return `limit_exceeded` without retaining or writing
that byte. `copy` uses a fixed-size working buffer and returns the exact total.
Reader and writer errors are propagated unchanged.

These APIs are blocking and add no implicit buffering, text encoding, flush,
positioning, async operation, cancellation, or multiplexing. Concrete resource
types may expose such independent capabilities when they actually exist.
