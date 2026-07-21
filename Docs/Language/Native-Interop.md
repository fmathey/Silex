# Native interoperability

Native interoperability connects a declaration in a `.sx` source to a C symbol
implemented by one of the C, C++, Objective-C, or Objective-C++ sources listed
in the module's `@Module.json`. Silex generates the C header that is the exact
contract between both sides; native code should include that header instead of
redeclaring symbols or transport structures by hand.

## Public API or private primitive

A public native function is directly callable by users of the module:

```sx
pub native func pow(value:int) int
```

For a declaration in module `Math`, the generated header declares the C symbol
`silexNative_Math_pow`. `use Math` exposes `Math.pow` exactly like an ordinary
`pub func`; module resolution and editor completion do not expose the native
implementation details.

A private native function is intended to sit behind Silex code. Its name follows
the ordinary function naming rules; Silex imposes no `native_` prefix:

```sx
native func pow_implementation(value:int) int

pub func pow(value:int) int {
    return pow_implementation(value)
}
```

Libraries may adopt their own convention. STD currently uses `native_` for
private primitives when that makes the distinction from a public wrapper
clear, but this convention is not part of the language or ABI.

The wrapper is optional. It remains useful when the public operation validates
arguments, translates errors, combines several native calls, or deliberately
exposes different Silex types. A direct `pub native func` is preferable when
the generated ABI already expresses the complete public contract.

Both forms are top-level, have no Silex body, cannot be generic or overloaded,
and require an explicit return type, including `void`. They also require a
named module whose own `@Module.json` or an ancestor manifest has a `native`
section. A standalone main source cannot declare one.

## Opaque native resources

A module associates a nominal opaque type with its sole native destructor:

```sx
pub native resource Buffer {
    drop destroy_buffer
}
```

The declaration may be private by omitting `pub`. It is top-level,
non-generic, has no fields, initializer, inheritance or extension form, and is
available only in a named module backed by native sources. Silex cannot inspect
the pointer, convert it to an integer, or construct a `Buffer`; only a non-null
native return creates its unique owner.

The generated C header exposes an incomplete nominal type and the attached
operation:

```c
typedef struct SilexNative_Buffers_Buffer SilexNative_Buffers_Buffer;
void silexNative_Buffers_destroy_buffer(
    SilexNative_Buffers_Buffer* resource
);
```

Distinct declarations produce distinct incomplete C types. The native module
defines their contents privately. A `Buffer` return transfers ownership to
Silex; `@Buffer` passes a constant borrowed pointer, `&Buffer` a mutable
borrowed pointer, and a value parameter consumes ownership and requires
`move`. The attached destructor is the sole exception:
`destroy_buffer(buffer)` consumes a complete owner implicitly and makes every
later use invalid.

`Buffer?` uses `false` plus a null output pointer for absence.
`Result<Buffer,E>` stores a resource pointer in the corresponding branch. A
null active resource, a resource in an inactive or absent branch, or an unknown
tag is a fatal contract violation. Before reporting it, and when an exception
crosses the C symbol, the bridge invokes the attached destructor for every
non-null resource not adopted by a live Silex value. Ordinary scope,
replacement, early return and `move` then provide exactly-once destruction.

### Composition and acquisition order

When several unique native resources remain in one value, their destruction is
defined by the order in which the program actually acquired them, never by the
declaration order of structure fields. Each adopted handle carries its runtime
acquisition record through `move`, named structure initialization, returns and
noncopyable containers. Remaining resources are released in reverse acquisition
order; a branch may therefore give two values of the same structure type a
different destruction order.

A native function returning a unique resource conservatively makes that result
depend on every unique resource root passed through `@` or `&`. The dependency
is propagated through Silex wrappers and transfers. A dependent cannot outlive,
consume, replace or explicitly destroy its root. Destroying the dependent first
ends the relation and then permits terminal destruction of the root. Returning
a dependent whose root is local is rejected.

The generated C++ retains prior live acquisition records behind the opaque
handles. Consequently, reordering fields cannot make a root disappear before a
later acquisition, including for independent resources. An aggregate `drop`
block runs first while all fields remain alive; automatic native cleanup follows
it. A deferred subscription is not retained by a later unrelated acquisition:
its callback context follows only that subscription's own moves and containing
values, so its capture lifetime ends with that owner. No annotation on fields
and no manual `clear` call participates in this order.

### Borrowed returns

Silex signatures can return a controlled shared alias as `@T` or an exclusive
mutable alias as `&T`. The return is tied to the unique compatible borrowed
parameter, or to a named parameter in an ambiguous signature such as
`@owner:State`. Successive Silex wrappers preserve the actual root.

The alias may live in a local binding and uses direct member access. It cannot
be stored in an aggregate or outlive its root; while it is alive, incompatible
access, mutation, replacement, `move`, and destruction of the root are refused.
The generated C++ uses a typed pointer internally without exposing pointers or
a dereference operation to Silex.

### Contiguous borrowed views

A native function may return contiguous storage owned by an opaque resource as
`@T[..]` or `&T[..]`. The result follows the borrowed-return provenance of that
resource and therefore prevents incompatible mutation, `move`, or destruction
while the view lives. No pointer is observable in Silex.

The C symbol returns through `const T**`/`T**` and `int64_t* output_count`.
The bridge accepts a null pointer only for an empty view, rejects negative or
unrepresentable counts, and never copies, adopts, or frees the native memory.
Conversely, native parameters `@T[..]` and `&T[..]` become a borrowed pointer
plus signed element count valid only during the call.

## Admitted signatures

The native boundary is deliberately narrower than the Silex type system. The
following table is exhaustive for the current language:

| Silex type | Parameter | Return | Native transport |
| --- | --- | --- | --- |
| `void` | no | yes | C `void`; it must be written explicitly |
| `bool` | yes | yes | C `bool` |
| `int`/`int64`, `int8`, `int16`, `int32` | yes | yes | `int64_t`, `int8_t`, `int16_t`, `int32_t` |
| `uint`/`uint64`, `uint8`, `uint16`, `uint32` | yes | yes | `uint64_t`, `uint8_t`, `uint16_t`, `uint32_t` |
| `float`/`float32`, `float64` | yes | yes | C `float`, C `double` |
| `str` | yes | yes | borrowed UTF-8 bytes for input; owned bytes for output |
| admitted flat `struct` | yes | yes | generated C transport passed through a pointer |
| opaque `native resource` | yes, by value/`@`/`&` | yes | distinct incomplete C type pointer |
| `@Resource` / `&Resource` | no | yes | borrowed `const`/mutable native resource pointer tied to the matching parameter |
| `@T[..]` / `&T[..]` | yes | yes | borrowed `const T*`/`T*` plus `int64_t` element count; returns use output parameters |
| `uint8[]` | yes | yes | borrowed byte view for input; owned byte buffer for output |
| `uint8[N]` | yes | no | borrowed byte view and length |
| scalar callback | yes | no | function pointer plus opaque context |
| `T?` | no | yes | presence flag plus the transport of `T` |
| `Result<T,E>` | no | yes | generated tagged output transport |

`int64`, `uint64`, and `float32` are accepted aliases of `int`, `uint`, and
`float`. A callback is admitted only when every parameter is `bool` or a
numeric scalar and its return is `void`, `bool`, or a numeric scalar. `T?`
admits a scalar, `str`, or an admitted flat structure. `Result<T,E>` admits the
same transferable return types in both branches, additionally permits an owned
`uint8[]` branch, and permits `void` only for `T`.

The following types are not native signature types: arbitrary lists and fixed
arrays, nested structures, enums, classes, protocols, references other than
admitted opaque resources and numeric contiguous views, pointers, optional parameters,
`Result` parameters, nested optionals or
Results, generic structures, structures with `drop`, and deferred callbacks.
The compiler rejects these declarations before compiling the native sources.

## Scalars and generated declarations

For the direct public declaration:

```sx
pub native func pow(value:int) int
```

the generated C header contains the equivalent declaration:

```c
int64_t silexNative_Math_pow(int64_t silexValue0);
```

C++ implements it with C linkage and the exact generated types:

```cpp
#include <SilexNative/Math.h>

extern "C" int64_t silexNative_Math_pow(int64_t value) {
    return value * value;
}
```

Including the generated header makes a mismatched name, parameter, or return
type a native compilation error. C++ `int` is not a substitute for Silex
`int`: C++ commonly makes it 32 bits, while Silex `int` maps to `int64_t`.

## Strings

A `str` parameter becomes a borrowed `const char*` byte view and an `int64_t`
byte length. The view is valid only during the call. Native code must not
modify, retain, or free it. The length, rather than a null terminator, defines
the value, so embedded null bytes are preserved.

A `str` return changes the C symbol to `void` and adds `char** output_bytes`
and `int64_t* output_length` after the ordinary parameters. Native code
allocates the returned bytes with `malloc`; Silex copies exactly the declared
length into an independent string and releases the buffer with `free`. An empty
value may use `nullptr` with length zero. A negative length, a null pointer with
a positive length, or invalid UTF-8 is a fatal native contract violation. The
bridge releases the buffer on every success and failure path.

## Flat structures

An admitted structure is copyable, non-generic, has no `drop`, and stores only
direct `bool`, numeric, or `str` fields. Static members and methods do not enter
the transport. Nested structures, collections, enums, classes, protocols,
optionals, Results, and function fields are excluded.

Silex generates a named C transport whose fields follow declaration order. An
input structure is passed through a pointer to a constant transport. A string
field is a borrowed `const char* <field>_bytes` and `int64_t <field>_length`
pair valid only during the call. An output structure is passed through a
mutable output pointer; each string field becomes an owned `char*` and length
pair following the same `malloc`/`free` and UTF-8 rules as a direct string
return. The bridge copies all fields into an independent Silex value.

## Byte collections

`uint8[]` and `uint8[N]` parameters become a borrowed `const uint8_t*` and an
`int64_t` byte length. The contiguous view is read-only and valid only during
the call. An empty sequence has length zero and may use a null pointer.

Only a dynamic `uint8[]` can be returned. The C symbol receives
`uint8_t** output_bytes` and `int64_t* output_length`; native code allocates
with `malloc`, then Silex copies and frees the bytes exactly once. No UTF-8
validation or terminator is involved. Fixed-array returns, adoption without a
copy, and native mutation of caller-owned bytes are not supported.

Native contiguous views admit numeric scalar elements (`int`, the fixed-width
signed and unsigned integers, `float`, and `float64`). They exclude `bool`,
`str`, resources, structures, enums, classes, protocols, and collections.
Unlike the owned `uint8[]` return above, a borrowed view has no allocation or
`free` protocol and must be tied to a borrowed opaque resource parameter.

## Synchronous callbacks

A scalar callback parameter becomes a C function pointer followed by an opaque
`void*` context. For example, `func(int) bool` is transported as:

```c
bool (*visitor)(void*, int64_t), void* visitor_context
```

The native function may call it zero, one, or several times, but only before
the native call returns and only on the calling thread. It must not retain the
function or context pointer, invoke it later, transfer it to another thread, or
pass it to another API. Silex keeps the callback and captures alive for that
synchronous interval. Unique resources cannot be captures. Strings,
structures, collections, references, optionals, Results, and nested callbacks
are excluded from callback signatures.

## Deferred callbacks

`deferred func(...)` is a distinct, noncopyable callback type for a native
subscription that outlives its registration call. A deferred callback returns
`void` and accepts only by-value `bool` or numeric scalar parameters. It cannot
be called directly in Silex, nested in another stored type, used as an ordinary
function parameter or return, or captured by another lambda. A local binding
uses `var`; a named binding is transferred with `move`, while a direct
`deferred func` literal transfers implicitly.

A native registration has exactly one `deferred func(...)` parameter and
returns exactly one `native resource` directly. The callback's function pointer
and context keep the ordinary C shape:

```sx
pub native resource Watch {
    drop stop_watch
}

pub native func start_watch(callback:deferred func(int)) Watch

var total = 0
let watch = start_watch(deferred func(value:int) {
    total += value
})
```

```c
SilexNative_Watcher_Watch* silexNative_Watcher_start_watch(
    void (*callback)(void*, int64_t),
    void* callback_context
);
```

The native object may retain both pointers and invoke them later from one or
several native threads. The trampoline copies each complete scalar argument
tuple into a synchronized FIFO owned by the subscription; it never runs Silex
code, reads captures, or destroys Silex values. Each accepted invocation takes
one position in the queue. Calls from one producer retain their order; calls
that are concurrent across producers are ordered only by their effective entry
into the queue.

`dispatch_callbacks(watch)` is called on the Silex thread that owns the
subscription. It atomically detaches the events present when it enters the
queue, invokes that batch in its established order, and returns its count as
`int`. Events enqueued after the detachment, including reentrant events and
concurrent native arrivals, remain for the next dispatch. The intrinsic
requires a readable, live resource place returned by a deferred registration
and neither consumes nor replaces it.

The generated bridge attaches the callback, queue, and cancellation state to
the returned resource. Moves, containing aggregate fields, and ordinary Silex
function returns transfer that hidden state with the resource and preserve the
shortest lexical lifetime of the callback's captures. A deferred subscription
cannot be transferred by value to an ordinary native function: that ABI would
transfer only the opaque handle and separate it from the hidden callback state.
Only the resource's declared native destructor consumes the subscription at the
native boundary. References, unique resources, and another deferred callback
cannot be captured. The registration's null resource return remains fatal and
releases the callback state without dispatching queued events.

The resource's declared native destructor is the cancellation operation. The
bridge synchronizes the transition to the cancelled state before calling it.
An invocation fully enqueued before that transition remains pending and is
destroyed without running its body; an invocation that observes cancellation
is ignored; an invocation already entering the queue finishes or observes the
transition before the context can be released. Pending events and callback
state are destroyed on the owner thread after the native destructor returns.

The native destructor must make the producer quiescent: it unregisters the
source, requests worker shutdown when needed, waits for all engaged calls, and
returns only when no thread can invoke or retain the function/context pointers.
Calls after that return are native contract violations. Destruction is
synchronous; an API whose shutdown is asynchronous needs an adapter that waits
for observable quiescence before its attached destructor returns.

## Optional and Result returns

A native `T?` return makes the C symbol return `bool` for presence and adds the
ordinary transport of `T` as output parameters. `false` produces `null`
without reading the value; `true` validates and copies it. Silex zeroes output
storage before the call. Owned output data supplied for an absent value is a
contract violation, but the bridge still releases it.

A native `Result<T,E>` return uses a generated structure containing a
success/failure tag and transports for both branches. Native code explicitly
sets the tag and fills only that branch. Silex validates and converts the
active branch, frees all transferred buffers, and constructs an ordinary
Silex `Result`. Unknown tags, owned data in the inactive branch, invalid
strings, and invalid buffer lengths are fatal contract violations. A C++
exception crossing the C symbol is also fatal; native code must select the
failure branch itself for a recoverable error.

## Headers, sources, and caches

The native source layout is independent of the `.sx` layout. The manifest may
compile one aggregator or several implementation files, for example:

```json
{
  "native": {
    "sources": {
      "cpp": ["@Native/Module.cpp"]
    }
  }
}
```

Before compiling those sources, Silex generates per-module headers such as
`SilexNative/Math.h`. An inherited manifest also receives a root header that
aggregates declarations loaded from all modules it serves. The native source
includes whichever generated header matches how that runtime is organized;
the manifest source list does not have to mirror the module tree.

The immutable, content-addressed header used by the build lives under
`.silex/build/`. A synchronized editor-facing copy lives under
`.silex/interfaces/SilexNative/`, and native compilation places that stable
include root before the cached one. These files are generated contracts and
must not be edited. `compile_commands.json` carries the same include path for
Clang-based editor tooling.

The generated header uses only C types from `<stdbool.h>` and `<stdint.h>`,
include guards, and a C++-protected `extern "C"` block. No `std::string`,
generated-program class, arbitrary project path, or hand-chosen symbol crosses
this boundary.
