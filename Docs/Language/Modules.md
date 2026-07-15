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
It does not recursively load every submodule. A fully qualified reference under
that import loads only its longest prefix that names an existing module. Thus
`import STD` permits `STD.Time.Stopwatch {}` and loads `STD.Time` on demand.
The same rule applies through an import alias such as `Standard.Time.Stopwatch`
after `import STD as Standard`.

A non-public `use` can name either one declaration or one submodule and
introduce its name or alias into the current file. It can establish that exact
dependency without a preceding `import`; the longest loaded prefix that names
a module is selected. Thus `use STD.Random as Random` introduces a module,
while `use STD.Random.Generator as Generator` introduces a structure. An import
alias can also qualify a `use`, as in `import STD as Standard` followed by
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
from the `native` section of `STD/Module.json`; both types and their duration
calculations remain Silex code in `STD/Time/`.

## Optional module manifest

A directory-backed local or distributed module may contain one optional,
exactly-cased `Module.json`. Pure Silex modules do not need it. The manifest
accepts optional `author`, `description`, `name`, `version`, `dependencies`, and
`native` fields. `name` and `version` become mandatory only when another
package references that directory.

For example, this local module is compiled automatically by
`silex run Sources/Main.sx` as soon as `Main.sx` loads `Math`:

```text
Sources/
├── Main.sx
└── Math/
    ├── Runtime.sx
    ├── Module.json
    └── Module.cpp
```

The `.sx` source declares private `native func` entries and exposes ordinary
Silex functions around them. The C or C++ source defines the C symbols derived
from the full module and function paths; `Math.native_length` becomes
`silexNative_Math_native_length`.

```json
{
  "author": "Ada Lovelace",
  "description": "Local mathematics",
  "native": {
    "sources": {
      "cpp": ["Module.cpp"]
    },
    "targets": {
      "macos": {
        "sources": {
          "objective_cpp": ["Platform/MacOS.mm"]
        },
        "frameworks": ["Foundation"]
      },
      "aarch64-macos-none": {
        "defines": {
          "MATH_ARM64": "1"
        }
      }
    }
  }
}
```

When a descendant is loaded, Silex checks its directory and then each parent
directory for the closest `Module.json` containing `native`. A metadata-only
manifest does not mask a parent's native configuration. The `compile` command
selects one target for the whole application: the host target by default, or
the triple supplied with `--target`. Every loaded native module inherits that
same target. Its configuration is composed from the fields directly under
`native`, then the optional `targets` entry named after the target OS, and
finally the optional entry named after the exact Zig triple. With the example
above, `aarch64-macos-none` receives `Module.cpp`, `Platform/MacOS.mm`, the
Foundation framework, and `MATH_ARM64=1`. A target with no matching override
uses the general configuration and is still compiled.

Native sources are listed explicitly under `c`, `cpp`, `objective_c`, or
`objective_cpp`; relative source and include paths must remain inside the
directory containing the manifest. Sources from the selected levels are
additive, but the same canonical file may appear only once, including across
different native languages. Include directories, system libraries, and
frameworks are deduplicated in their first occurrence order. Defines are
merged by name, with the OS value replacing the general value and the exact
triple replacing both. `Module.cpp` is only a convention: every source remains
explicit and may use another name. The Zig toolchain distributed with Silex
compiles C and Objective-C sources with its C driver, C++ and Objective-C++
sources with its C++ driver, passes the selected target to every invocation,
then links their objects with the generated program.

The manifest may also list include directories, string defines, system-library
names, and Apple frameworks. It cannot provide arbitrary compiler flags,
commands, absolute paths, archives, or prebuilt native binaries. A runtime is
compiled once per manifest when its module or one of its descendants is loaded.
Headers are optional, and a runtime may keep all of its implementation in one
source file or split it across several sources. Its files do not introduce
Silex declarations beyond each module's `.sx` API.

A package can vendor the source distribution of a native library under its
root and make that ownership explicit. For example, an SDL3 package can keep a
single copy under `Vendor/SDL/` while Foundation consumes its headers:

```json
{
  "name": "SDL3",
  "version": "1.2.4",
  "native": {
    "provides": ["SDL3"],
    "sources": {
      "c": ["Vendor/SDL/src/SDL.c"]
    },
    "public_include_dirs": ["Vendor/SDL/include"],
    "public_defines": {
      "SDL_STATIC": "1"
    }
  }
}
```

`provides` contains declared native identities, not inferred symbols. Two
distinct resolved package identities cannot provide the same value; Silex
reports both dependency chains before invoking the C or C++ compiler. Private
C symbols generated for Silex `native func` declarations need no `provides`
entry.

`include_dirs` and `defines` remain private to the package's own native
sources. `public_include_dirs` and `public_defines` also apply to the owner,
then to native sources compiled by packages that declare the owner as a direct
dependency. Public include paths are relative to and confined within the
owner's package root. They do not create Silex imports. The interface is not
transitive: Foundation can compile `#include <SDL3/SDL.h>` when it declares
SDL3, but its consumer must declare SDL3 itself before compiling native source
against that header.

Equal public define names and values are passed once. Conflicting values from
two direct dependencies, or a contradictory private define in the consuming
package, are rejected before native compilation. Resolved package runtimes are
compiled dependency-first. Their source objects are linked once even through a
diamond, while system libraries and frameworks are deduplicated and ordered
with consumers before the owners they depend on.

Vendored native content is part of the Silex package's source, version,
licensing, and cache key. It needs no separate Git origin, and Silex runs no
upstream build script. Static archives, dynamic libraries, and other prebuilt
native binaries remain outside this manifest contract.

Native objects from resolved packages use the shared user cache under
`~/.silex/cache/objects/` on POSIX systems and the equivalent user-local Silex
directory on Windows. An object-set key contains the selected target, native
profile and toolchain version, effective sources, `-I` and `-D` configuration,
and the contents of included package headers. Paths are normalized relative to
their package or public interface, so two projects can reuse one immutable Git
package checkout without their own absolute paths entering the identity.

Changing an included vendored header or the native target creates a new object
set. Changing only a package `.sx` file leaves its native objects reusable;
the application C++ and final link remain local under `.silex/build/`. A
dependency implementation change replaces the objects linked for that owner,
while a dependent package is recompiled only when the public native interface
it consumes changes. System libraries and frameworks are still evaluated for
every required final link and are never stored as cache contents.

The optional manifest can be initialized without changing the module's Silex
sources:

```text
silex module init Sources/Math
silex module init Sources/Math --native
```

The plain form creates `Module.json` containing `{}`. The native form creates
or completes the manifest with `Module.cpp` as a portable C++ source and creates
that file only when it is absent. Existing metadata, source files, and native
configuration are never overwritten implicitly.

## Local packages

A directory remains an implicit module when it only contains Silex sources or
submodule directories. It needs no manifest, and neighboring local modules keep
their existing filesystem resolution.

A directory consumed as an external dependency is a declared package. Its
`Module.json` names the root module, gives it a Semantic Version, and may list
other packages required directly by its sources:

```json
{
  "name": "Foundation",
  "version": "0.3.0",
  "dependencies": {
    "Utility": {
      "path": "../Utility"
    }
  }
}
```

The package root above provides `Foundation`; its `Math/` directory provides
`Foundation.Math`. A `path` is relative to the manifest that declares it and
may leave that package directory. The destination is canonicalized and must be
a directory containing `Module.json`. Its `name` must match the dependency key
exactly and its `version` must be valid Semantic Versioning.

A dependency can instead name a Git repository:

```json
{
  "dependencies": {
    "Utility": {
      "git": "https://example.com/Utility.silex.git",
      "version": "^1.2",
      "rev": "8e0f41c39f2c4be8a65e91a163f2f954af8ebf6d"
    }
  }
}
```

`path` and `git` are mutually exclusive. A Git dependency requires `version`;
`rev` is optional and fixes a precise Git revision. Without `rev`, the first
resolution uses the current commit of the repository's default branch. Silex
accepts exact constraints such as `=1.2.3` and caret constraints such as
`^1.2`, `^1.2.3`, `^0.2`, or `^0.0.3`. A caret range stops at the next value of
the first nonzero component. Prerelease versions only match a constraint that
itself names a prerelease.

An application can declare `dependencies` in a root `Module.json` without
declaring its own `name` or `version`. For a `.sx` entry the project root is the
entry's directory; for a JSON project manifest it is the manifest's directory.
Without that root manifest, local module loading behaves exactly as before.

Silex resolves and validates the complete package graph before reading imported
module sources or compiling native code. The same package name must resolve to
one canonical directory and one version; diamonds reuse that identity once.
Cycles, missing paths, incomplete manifests, name mismatches, and multiple
providers report the dependency chain that led to the error.

Each package can import its own modules, the reserved Silex modules, and the
packages it declares directly. Transitive dependencies are compiled for their
parent but do not become importable by an application or sibling package that
did not declare them.

When the graph contains Git, Silex atomically writes the complete resolution to
`Silex.lock` at the application root. Each transitive entry records its name,
version, canonical `path` or `git` origin, exact Git commit when applicable,
and exact dependency identities. A dependent package's own lockfile is never
consulted. A valid root lockfile prevents `compile` and `run` from following a
moved remote branch. `silex update` recomputes all Git origins without `rev`;
`silex update Utility` limits that refresh to the named package and necessary
transitive changes. The existing lockfile is replaced only after the new graph
has been fully validated.

Exact Git checkouts are content-addressed by canonical origin and commit in the
user Silex cache: `~/.silex/packages/` on POSIX systems and the equivalent
user-local directory on Windows. Projects using the same commit share that
source directory. A build whose locked checkouts are already cached does not
contact Git; deleting the cache causes the same commits to be fetched again.
`path` packages always remain at their declared local locations. Package
resolution runs no repository script and does not download a native library
mentioned by a package during compilation.
