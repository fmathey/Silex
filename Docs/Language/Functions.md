# Functions

A function begins with `func`, has a name and typed parameters, and has an
explicit return type whenever it returns a value.

```sx
func add(left:int, right:int) int {
    return left + right
}

func log(message:str) {
    print(message)
}
```

Omitting a return type means `void`; writing `void` explicitly is valid but not
canonical. A non-void return type is never inferred. The compiler collects
signatures before checking bodies, so functions may be called before their
definition and may be recursive.

## Generic functions

A function may declare type parameters after its name. Calls provide every
type argument explicitly:

```sx
func identity<T>(value:T) T {
    return value
}

func choose<Key, Value>(key:Key, value:Value) Value {
    return value
}

let answer = identity<int>(42)
let name = choose<int, str>(1, "Ada")
```

Type parameters are available throughout the signature and body. They may be
used in local annotations, function types, collections, optionals, and generic
structure specializations:

```sx
func boxed<T>(value:T) Box<T> {
    return Box<T>(value:value)
}
```

Silex does not infer type arguments. Calling `identity(42)` is therefore
invalid unless a concrete overload named `identity` also exists. An explicit
call such as `identity<int>(42)` considers only visible generic overloads with
one type parameter, specializes their complete signatures and bodies, and then
applies ordinary overload resolution.

Repeating the same arguments reuses one concrete specialization. Recursion is
valid when it calls the same specialization; recursively producing ever-new
type arguments is rejected. Public generic functions retain the ordinary
module, `use`, alias, and re-export rules.

One protocol can constrain each parameter with `T : Protocol`. The constraint
permits the protocol's required methods in the generic body and rejects a
concrete argument that did not declare conformance. See
[Protocols](Protocols.md). Type-argument inference is not currently provided.
`main`, `native func`, methods with their own type parameters, and classes
remain non-generic.

## Overloads

Top-level functions and methods in the same structure may share a name when
their ordered parameter lists differ by count, type, or `&` passing. The return
type is not part of a signature: aliases such as `int` and `int64`, `uint` and
`uint64`, or `float` and `float32` therefore do not create distinct overloads.

```sx
func measure() int {
    return 0
}

func measure(value:int) int {
    return value
}
```

At a call site, Silex first keeps the signatures compatible with the argument
count, types and `&` markers. It then prefers an exact type, a same-sign
integer widening or `float` to `float64`, and finally an integer-to-float
conversion. If no single signature is strictly better, the call is rejected as
ambiguous and the remaining signatures are listed. Integer and decimal
literals keep their default `int` and `float` types during this selection.

`main` and every `native func` remain unique by name. A native C symbol does
not encode parameters, so native overloads are not available.

## Assertions

`assert(condition, message)` verifies a runtime invariant. The condition must
be `bool` and the message `str`. If the condition is false, Silex writes the
source location and `assertion failed: <message>` to standard error, then ends
the program with exit code 1. Assertions remain active in every build.

```sx
assert(index < values.count(), "index must address a value")
```

Assertions do not introduce recoverable errors or error propagation.

## Panic

`panic(message)` stops the current execution path. Its message must be `str`.
Silex writes the location of `panic` and `runtime error: <message>` to standard
error, then exits with code 1. A `panic` satisfies a non-`void` function's
mandatory return path, but does not introduce recoverable errors, stack traces,
or error propagation.

```sx
func require_positive(value:int) int {
    if value <= 0 {
        panic("value must be positive")
    }
    return value
}
```

`native func` declares a private, top-level function implemented by a named
module's native runtime rather than by a Silex body. The local or distributed
module, or one of its parents, must contain a `Module.json` with a `native`
section. A standalone main source cannot declare native functions, and
`pub native func` is invalid. Native function names begin with `native_`.

Their ABI is intentionally narrow: scalar booleans and numbers may be passed
or returned, and `str` may be passed or returned. A string parameter is passed
as UTF-8 bytes and a byte length; the native runtime must neither retain nor
modify its byte view. A string return uses two output parameters after the
ordinary parameters:

```cpp
extern "C" void silexNative_Module_native_read_text(
    char** output_bytes,
    std::int64_t* output_length
);
```

The native function allocates `output_bytes` with `malloc` and transfers it to
the generated bridge, which copies exactly `output_length` bytes into an
independent Silex string then releases the buffer with `free`. An empty result
may use `nullptr` with length zero. A negative length, or a null pointer with a
positive length, is a runtime error naming the native function. The bridge
also rejects invalid UTF-8 with `returned invalid UTF-8`; it frees the buffer
on every valid and invalid return path. Embedded null bytes are preserved, so
the length—not C string termination—defines the result. Collections,
references, pointers, callbacks, `Result`, and other non-transferable values
remain unavailable in native-function signatures. Silex derives the C symbol
from the module and function name, so a native runtime never chooses an
arbitrary C symbol.

A native function may also return a copyable, non-generic structure whose
stored fields are directly scalar booleans, numbers, or strings. Its generated
C header defines a transport structure derived from the module and Silex type
name; the native symbol receives an output pointer to that transport after its
ordinary parameters. Each string field becomes an owned `char* <name>_bytes`
and `int64_t <name>_length` pair. No `std::string` crosses the C symbol.

Silex zero-initializes the transport, calls the native symbol, then copies every
field in declaration order into an independent Silex structure. Each string
buffer follows the same `malloc`/`free`, byte-length, embedded-null, empty-value,
and UTF-8 rules as a direct `str` return. All buffers are released exactly once,
including when an exception or an invalid string field prevents the return.
The runtime error names both the native function and invalid field. Successive
calls share no Silex string storage.

The generated C transport—not the structure emitted in `Generated.cpp`—is the
ABI. Static members and methods add no transport field. Nested structures,
enums, classes, protocols, collections, optionals, `Result`, functions, generic
structures, and structures with `drop` remain unavailable in a native return
structure.

A copyable, non-generic structure whose stored fields are directly scalar
booleans or numbers may also be passed by value to a native function. The bridge
evaluates the Silex argument once, copies its fields in declaration order into
an independent C transport, and passes `const SilexNative_Module_Type*`. That
pointer is valid only for the duration of the call: the native function cannot
modify the Silex value or retain its address. Input and output positions reuse
the same named transport definition. Several structured arguments each receive
their own transport. String fields, nested structures, enums, classes,
protocols, collections, references, optionals, `Result`, functions, generic
structures, and structures with `drop` remain unavailable as native structure
parameters.

A native function may return `T?` when `T` is one of the transferable return
types above: a scalar boolean or number, `str`, or an admitted flat structure.
The C symbol returns `bool` to report presence and receives the same transport
for `T` as output parameters after its ordinary parameters. For example:

```cpp
extern "C" bool silexNative_Module_native_poll(
    std::int64_t handle,
    SilexNative_Module_NativeEvent* output
);
```

Silex zero-initializes the output before calling the symbol. `false` produces
`null` without reading the transported value; `true` applies all ordinary
scalar, string, structure, length, and UTF-8 validations before constructing an
independent present value. A native function that reports absence after placing
an owned string buffer in the output violates the contract: the bridge frees
every transferred buffer, then reports a runtime error naming the native
function and, for a structure, the offending field. Native optional parameters,
nested optionals, `Result`, and additional transferable types are not introduced
by this ABI.

Before compiling a native runtime, Silex generates its authoritative C
interface beneath `.silex/build/`. Every module segment becomes a header-path
segment, so a C or C++ implementation of `STD.Console` includes:

```cpp
#include <SilexNative/STD/Console.h>
```

The generated header has ordinary C types from `<stdbool.h>` and `<stdint.h>`,
includes guards, and a C++-protected `extern "C"` block. It contains the exact
symbols and scalar, string, optional-return, or flat-structure ABI above, never
generated-program types, `std::string`, or project paths. Its include root is
supplied automatically to the native runtime that implements the module. A C++
definition that disagrees with a generated declaration therefore fails while
compiling that runtime.

All arguments, return values, and return paths are checked statically. A
non-void function must return a compatible value on every path. A void function
may use `return` without a value. A unique-resource parameter owns its value;
a named owner argument or return uses `move`, while a freshly produced
temporary transfers implicitly. A `name:@T` parameter instead observes the
caller's ordinary argument without taking ownership; the signature alone
selects read-reference binding. See
[Values and mutation](Values-and-References.md#read-references) and
[unique resource structures](Structures.md#unique-resource-structures).

Methods are functions declared inside a structure or class. An instance method
receives the explicit `self` value. A `static func` method is selected through
its complete type and has no receiver. See [Structures](Structures.md) and
[Classes](Classes.md). Structure methods are public by default. Class methods
are private by default and use `pub` for general access or `sub` for access by
future descendants; visibility precedes `static`.

## Function values and lambdas

`func(parameter types) return_type` is a value type. Parameter modes are part
of that type, so `func(Data)`, `func(@Data)`, and `func(&Data)` are
distinct. An omitted return type is
the canonical spelling of `void`; `func(int) void` is also accepted. Function
values may be assigned, passed, stored in fields or collections, and called
with the same argument conversions as a named function.

```sx
func apply(value:int, callback:func(int) int) int {
    return callback(value)
}

let doubled = apply(4, func(value:int) int {
    return value * 2
})
```

A function value itself uses `var`, even when its binding is not reassigned:
its type may carry lexical captures shared with another path and therefore
cannot satisfy the independent-value contract of `let`.

```sx
var callback = func(value:int) int {
    return value * 2
}
```

A lambda begins with `func` but has no name. Every parameter is named and
annotated, and every non-`void` return type and path is explicit. The compiler
captures only the outer bindings actually used. A captured `var` may be read
and changed; a captured `let` remains immutable. Copies of a lambda refer to
the same captured bindings.

A lambda without captures is an unrestricted value. A capturing lambda borrows
its outer bindings and cannot be returned or stored in a variable, field,
structure, or collection that outlives any capture. The same check is applied
when a callback parameter is stored by the called function or method. This is a
lexical check: captures do not allocate shared cells or extend a scope.

Function values and values that contain them are not printable or comparable.
They cannot be bound with `let`, have no intrinsic default, and remain
forbidden in `native func` parameters and returns.
