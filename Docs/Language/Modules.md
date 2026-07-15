# Modules

A module is a logical node in a hierarchy. Files assigned to the same module
share their structures and functions, and directories below it provide its
submodules. A file does not contain a `module` declaration.

When compiling an entry file without a manifest, a directory defines a local
module: `Math/` provides `Math`, and `Math/Geometry/` provides `Math.Geometry`.
A directory remains a module when it contains no direct `.sx` source and only
groups submodules. Only `.sx` files directly inside a directory contribute
declarations to that module.

The distributed library is installed with Silex. Its root modules `STD` and
`Silex` are reserved: `STD/` provides `STD`, `STD/Random/` provides its
`STD.Random` submodule, and `Silex/Window/` provides `Silex.Window`. Other
distributed modules follow the same path rule: `SDL3/` provides `SDL3`.
Distributed modules work from a single entry file and from a JSON manifest; do
not list reserved modules in a manifest. If a local module and a distributed
module provide the same imported name, compilation fails instead of choosing
one implicitly.

```sx
import Math
import NK.Rendering as Rendering
import STD

use STD.Random as Random
use STD.Random.Generator as Generator
use Math.Vec3

func create() NK.Window.Session {
    let direction:Vec3
    let random:Generator = Random.create(42)
    return Rendering.create_session()
}
```

`import` names a module and makes it available through its full name or alias.
It does not recursively load every submodule. A non-public `use` can name
either one declaration or one submodule and introduce its name or alias into
the current file. It can establish that exact dependency without a preceding
`import`; the longest loaded prefix that names a module is selected. Thus
`use STD.Random as Random` introduces a module, while
`use STD.Random.Generator as Generator` introduces a structure. An import alias
can also qualify a submodule, as in `import STD as Standard` followed by
`use Standard.Random as Random`.

Declarations are private by default. `pub` exposes a structure or function,
while `pub use` re-exports an existing declaration under the current module
name. Modules cannot currently be re-exported with `pub use`.

Duplicate providers, missing modules, dependency cycles, ambiguous aliases, and
access to private declarations are compile-time errors. Dependencies are never
implicitly transitive. A project manifest can define this module layout
explicitly; parent modules of its dotted module names are inferred even when
they have no sources of their own. See
[Installation and command-line use](../Installation.md).

## STD.Random

`STD.Random` provides a deterministic generator for games, simulations, and
tests. It is not cryptographically secure. `create(seed)` builds a reproducible
generator, while `system()` chooses an initial seed from the host.

```sx
var random = STD.Random.create(42)

let raw = random.get_int()
let die = random.get_int(1, 7)
let ratio = random.get_float()
let temperature = random.get_float(-10.0, 40.0)
let enabled = random.get_bool()
```

`get_int()` returns an `int` from `1` through `9223372036854775807`.
`get_int(minimum, maximum)` returns an unbiased `int` in
`[minimum, maximum)` and requires `minimum < maximum` with a positive `int`
width. `get_float()` returns a `float` in `[0.0, 1.0)`; its bounded overload
returns a `float` in `[minimum, maximum)` and requires finite, ordered bounds.
`get_bool()` returns either boolean value. Every call advances only its own
generator. Two generators with the same seed and sequence of calls return the
same sequence of values.

## STD.Time

`STD.Time.Stopwatch` is initially stopped with a zero elapsed duration.
`start()` starts or resumes without clearing, `stop()` freezes the accumulated
duration, `reset()` clears and stops, and `restart()` clears and starts.
Calling `start()` while running or `stop()` while stopped has no effect.

`STD.Time.Clock` has no `start()` or `stop()`. The first `tick()` initializes
its monotonic origin and returns zero. Every active tick after it returns the
scaled interval since the preceding tick and adds that value to the logical
total. A paused tick returns zero. Pausing or changing the scale preserves any
partial interval so that the next active tick loses no active time and excludes
all suspended time. `reset()` clears the total and partial interval, exits the
paused state, and makes the next tick return zero. Reset does not change the
configured time scale.

The implementation uses one native monotonic-microsecond reading inherited
from `STD/Native.json`; both types and their duration calculations remain Silex
code in `STD/Time/`.

## Native module runtime

A distributed module may contain one `Native.json`. It supplies the native
runtime for that module and its descendants. When a descendant is loaded,
Silex checks its directory and then each parent directory; the closest manifest
wins. Its `common` configuration is combined with the configuration selected
by the requested target triple in `targets`. A missing target entry is an
error. Native sources are listed explicitly under `c`, `cpp`, `objective_c`,
or `objective_cpp`; relative source and include paths must remain inside the
directory containing the manifest. Zig compiles C sources with its C driver and
C++ sources with its C++ driver, then links their objects with the generated
program.

The manifest may also list include directories, string defines, system-library
names, and Apple frameworks. It cannot provide arbitrary compiler flags,
commands, absolute paths, archives, or prebuilt native binaries. A runtime is
compiled once per manifest when its module or one of its descendants is loaded.
Headers are optional, and a runtime may keep all of its implementation in one
source file or split it across several sources. Its files do not introduce
Silex declarations beyond each module's `.sx` API.
