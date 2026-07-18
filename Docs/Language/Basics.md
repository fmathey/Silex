# Basics

Silex is a compiled language with native executables as its initial output.
The `main` function is the single program entry point.

```sx
func main() {
    print("Hello from Silex")
}
```

An explicit `void` return type is accepted, but omitting it is canonical for a
program that handles all recoverable errors itself. A command-line program may
instead return `Result<void,str>` so that its last recoverable error becomes a
deterministic diagnostic and exit code. See [Recoverable errors](Error-Handling.md#the-main-boundary).
`print` is a built-in function.

## Naming

Program-defined type names use `PascalCase`. Functions, methods, variables,
parameters, and fields use `snake_case`. Identifiers remain permissive; these
forms are the canonical style used by documentation and future formatting.

Type annotations have no spaces around `:`:

```sx
struct WindowSession {
    var frame_count:int
}
```

## Local variables

`let` declares a constant value. Except for a local collection shell, its type
must also be independent. `var` declares general mutable state. A declaration
needs an initializer, an explicit type, or both.

```sx
let count = 3
let doubled:int = count * 2
var enabled:bool = true
var attempts:int
let title:str
```

Outside the collection exception, `let` is accepted only when the complete type
has independent value semantics: no mutation through another path can change
what the binding observes. Scalars, strings, and structures recursively
composed from such values qualify. Function values do not qualify because
their captures may share mutable bindings. Class references and values that
contain one do not qualify either. Use `var` for those types even when the
local name is not eventually reassigned.

A local fixed array or dynamic list may use `let` with any element type. In
that case, `let` protects the collection storage: it prevents reassignment,
element replacement, and collection mutation. It does not freeze class
instances referenced by its elements.

```sx
class Session {}

let sessions:Session[] = [Session()] // accepted: immutable list storage
let session = Session()              // invalid: shared class reference

var callback = func() {}
```

The choice does not control optimization. A `var` that is never written can be
compiled exactly like a `let`; `let` exists only to request the constant-value
guarantee.

An uninitialized typed declaration receives the intrinsic value of its type:
zero for numbers, `false` for `bool`, an empty string for `str`, an empty list
for `T[]`, recursively initialized arrays and structures, and declared field
defaults where present. A class has no intrinsic instance and an enum has no
intrinsic variant: `var player:Player` and `var state:State` are invalid, so
their construction must be explicit. A declaration with neither type nor
initializer is invalid.

Assignments preserve the variable type. A local declaration may not reuse the
name of a parameter, variable, or iteration binding that remains visible in
its scope or an enclosing scope. Separate scopes that are not nested, such as
two sibling branches or successive loops, may reuse the same local name.
