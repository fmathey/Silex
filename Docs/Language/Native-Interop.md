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
arrays, nested structures, enums, classes, protocols, references (`@T` and
`&T`), pointers, optional parameters, `Result` parameters, nested optionals or
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
