# Modules

A module is a logical node in a hierarchy. Each `.sx` file assigned directly
to it is a source unit whose name is the exact filename without `.sx`. Files
assigned to the same module share their enums, protocols, structures, classes,
and functions, and directories below it provide its submodules. A file does
not contain a `module` declaration.

A source unit is selectable but does not add a namespace segment. For example,
`STD/Time/Stopwatch.sx` is the unit `STD.Time.Stopwatch`, while its public
`Stopwatch` structure remains named `STD.Time.Stopwatch` rather than
`STD.Time.Stopwatch.Stopwatch`. Private declarations in the file remain private
to `STD.Time`. Manifest modules use the basename of each `sources` path by the
same rule and reject duplicate unit names.

When compiling an entry file without a manifest, a directory defines a local
module by the same path rule as the installed standard library: `STD/` provides
`STD`, and `STD/Time/` provides `STD.Time`. A directory remains a module when
it contains no direct `.sx` source and only groups submodules. Only `.sx` files
directly inside a directory contribute declarations to that module, so
`STD/Randomizer.sx` declares `STD.Randomizer` directly in `STD`.

A directory whose name starts with `@` is infrastructure rather than a Silex
module. Automatic module discovery and completion skip that directory and its
descendants at every depth. Explicit file-oriented mechanisms may still use
it: `@Module.json` can list a native source under `@Native/`, and C or C++ code
can include headers stored there. A library may likewise keep documentation in
`@Docs/` or use another `@` name for infrastructure that must not become a
module. A leading `_` has no special meaning and remains available for ordinary
modules, including a future private-module convention.

The distributed library is installed with Silex. Its currently available
public root is `STD`; it declares `STD.Randomizer` directly and provides
`STD.Time` as a submodule.
The root names `STD` and `Silex` are reserved for distributed modules, so they
must not be listed as dependencies in a manifest. Distributed modules work
from a single entry file and from a JSON project manifest. If a local module
and a distributed module provide the same used name, compilation fails
instead of choosing one implicitly.

```sx
use STD as Standard

use Standard.Randomizer as Randomizer
use Standard.Time.Stopwatch as Stopwatch

func create_randomizer(seed:int) Randomizer {
    return Randomizer.create(seed)
}

func create_stopwatch() Stopwatch {
    return Stopwatch()
}
```

`use` names a dependency and makes a selected module available through its last
path segment or an explicit alias. It does not recursively load every submodule.
A fully qualified reference under that module use resolves the longest module
prefix and then selects the required source unit or declaration. Thus `use STD`
permits `STD.Time.Stopwatch()`
and loads `Stopwatch.sx` and its explicit dependencies on demand.
The same rule applies through a module alias such as `Standard.Time.Stopwatch`
after `use STD as Standard`.

A direct module `use` also activates the used module's public extension methods
and protocol conformances in that source file. This activation is not
transitive; see [Type extensions](Extensions.md#visibility-and-uses).

A non-public `use` can name a module, a source unit, or a declaration and can
establish that exact dependency. Thus
`use STD.Time as Time` selects every direct unit of that module, while
`use STD.Time.Stopwatch` selects only `Stopwatch.sx` and introduces its public
homonymous structure. Selecting a unit with no homonymous declaration, such as
`use STD.Time.Internal`, only loads it; it creates no fictitious `Internal`
type or value. A declaration whose name differs from its file selects the unit
that provides it. A path which is simultaneously a unit and a declaration from
another unit is ambiguous and rejected.

Inside a source unit, an unqualified `use` can select a sibling unit or a
declaration from the same module:

```sx
use Internal

pub struct Stopwatch {
}
```

The loader opens each selected unit once and follows its `use` directives to a
stable transitive closure. Neighboring units outside that closure are not
parsed or added to the program. Cycles between units of one module are allowed
and loaded as one closure; module and package cycles retain their existing
errors. A module alias can qualify another `use`, as in `use STD as Standard`
followed by `use Standard.Randomizer as Randomizer`.

Loading and activation are distinct. A file directly using one unit activates
the public extensions and protocol conformances in that unit and in the
same-module units reached through its `use` closure. A dependency that crosses
into another module or package is compiled but does not activate that other
module's extensions in the original consumer. Selecting a complete module
activates all its direct units. Activation stays local to the file containing
the explicit `use`; dependency aliases never propagate back to its
consumer.

## Transparent type aliases

`use` can introduce a name for any complete type, not only for a named
declaration. A composed or scalar type requires an explicit alias:

```sx
use Vec3<int> as Vec3i
use int as Integer
use Integer[] as Integers
use str? as OptionalString
use func(int) bool as Predicate
```

The alias is transparent. It does not declare a new nominal type, perform a
conversion, change representation, or create another generic specialization.
The alias and its source type are interchangeable:

```sx
let position = Vec3i(x:1, y:2, z:3)
let explicit:Vec3<int> = position

let values:Integers = [1, 2, 3]
let ordinary:int[] = values
```

Aliases may name other aliases. Their chains resolve to one underlying type;
cycles are rejected. A type alias cannot be called or used as a runtime value,
except that an alias whose underlying type is a structure, class, or enum can
use that type's ordinary initializer or variant constructors.

`pub use <type> as <name>` exports the transparent alias. A consumer may
qualify, use, rename, or re-export it like another public type declaration.
The source type is resolved in the file declaring the alias and is not
reinterpreted in the consumer. Type aliases cannot currently declare their own
type parameters.

Declarations are private by default. `pub` exposes an enum, protocol, structure,
class, or function, while `pub use` re-exports an existing declaration or type alias
under the current module name. Every variant of a public enum follows the
visibility of its enum. Modules cannot currently be re-exported with `pub use`.

For a class, declaration and member visibility are independent: `pub class`
exposes the type outside its module, while only its `pub` members are accessible
outside the class. See [Classes](Classes.md).

A public structure that declares `drop` exposes its type and methods but keeps
its fields and named aggregate initializer private to its declaring module.
Every source unit assigned to that module may use the storage directly; a type
extension retains external-caller rights and may not. See
[unique resource structures](Structures.md#unique-resource-structures).

Duplicate providers, missing modules, dependency cycles, ambiguous aliases, and
access to private declarations are compile-time errors. Dependencies and type
extensions are never implicitly transitive. A project manifest can define this
module layout explicitly; parent modules of its dotted module names are inferred
even when they have no sources of their own. See
[Installation and command-line use](../Installation.md).

The modules and public APIs currently provided under `STD` are documented in
the [STD library reference](Libraries/STD/README.md).

## Optional module manifest

A directory-backed local or distributed module may contain one optional,
exactly-cased `@Module.json`. Pure Silex modules do not need it. The manifest
accepts optional `author`, `description`, `name`, `version`, `dependencies`, and
`native` fields. `name` and `version` become mandatory only when another
package references that directory. The former exact name `Module.json` is not
accepted: when Silex encounters it while looking for a module manifest, it asks
the developer to rename it to `@Module.json` instead of ignoring it.

The installed `STD` module is the concrete native module currently shipped by
the project:

```text
Library/STD/
├── @Module.json
├── @Native/
│   ├── Console.cpp
│   ├── Randomizer.cpp
│   ├── Session.cpp
│   └── Time.cpp
├── Console/
│   ├── Console.sx
│   └── Session.sx
├── Randomizer.sx
└── Time/
    ├── Clock.sx
    ├── Internal.sx
    └── Stopwatch.sx
```

`Randomizer.sx` and `Internal.sx` declare private `native func` entries and
expose ordinary Silex types around them. The single native runtime is owned by
`STD/@Module.json`; each of its four private C++ units includes the generated
root interface directly:

```cpp
#include <SilexNative/STD.h>
```

`STD.native_seed` becomes `silexNative_STD_native_seed`, and
`STD.Time.native_monotonic_microseconds` becomes
`silexNative_STD_Time_native_monotonic_microseconds`.

`Console.sx` uses `pub native func` directly when its public Silex signature is
the complete native contract. Scalar and string operations include `write`,
`flush`, and `is_interactive`; `get_dimensions() Dimensions?` and
`read_line() str?` exercise optional flat-structure and string returns.
Operations that validate coordinates or translate enums retain a private
primitive—named with STD's internal `native_` convention—behind an ordinary
Silex function. For example,
`STD.Console.write` becomes `silexNative_STD_Console_write`.

```json
{
  "native": {
    "sources": {
      "cpp": [
        "@Native/Console.cpp",
        "@Native/Session.cpp",
        "@Native/Randomizer.cpp",
        "@Native/Time.cpp"
      ]
    }
  }
}
```

When a descendant is loaded, Silex checks its directory and then each parent
directory for the closest `@Module.json` containing `native`. A metadata-only
manifest does not mask a parent's native configuration. The sole
`Library/STD/@Module.json` therefore provides one runtime to `STD` and every
loaded descendant. Its root header `SilexNative/STD.h` is always generated for
that selected runtime and aggregates the native declarations actually loaded
from `STD`, `STD.Console`, `STD.Time`, or another descendant. It does not need
headers for modules absent from the program.

The `compile` command selects one target for the whole application: the host
target by default, or the triple supplied with `--target`. Every loaded native
module inherits that same target. Its configuration is composed from the
fields directly under `native`, then an optional `targets` entry named after
the target OS, and finally an optional entry named after the exact Zig triple.
`STD` currently uses only the general configuration, so
its four sources under `@Native/` apply to every supported target.

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
root and make that ownership explicit. `STD` does not currently vendor a
third-party library: its sources under `@Native/` only implement its private
Silex `native func` declarations, so its manifest needs neither `provides` nor
a public native interface. A future package that owns a native library can
list its identity in `provides`, its source files in `sources`, and the headers
or defines intended for direct consumers in `public_include_dirs` and
`public_defines`.

`provides` contains declared native identities, not inferred symbols. Two
distinct resolved package identities cannot provide the same value; Silex
reports both dependency chains before invoking the C or C++ compiler. C symbols
generated for Silex `native func` declarations are implementation symbols
regardless of their Silex visibility and need no `provides` entry.

`include_dirs` and `defines` remain private to the package's own native
sources. `public_include_dirs` and `public_defines` also apply to the owner,
then to native sources compiled by packages that declare the owner as a direct
dependency. Public include paths are relative to and confined within the
owner's package root. They do not create Silex dependencies. The interface is not
transitive: a direct consumer can include an owner's public header, but the
consumer's own dependents must also declare that owner before compiling native
source against the same header.

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

Changing an included vendored header, generated Silex native interface, or the
native target creates a new object set. Changing a package `.sx` file otherwise
leaves its native objects reusable; the application C++ and final link remain
local under `.silex/build/`. A dependency implementation change replaces the
objects linked for that owner, while a dependent package is recompiled only
when the public native interface it consumes changes. System libraries and
frameworks are still evaluated for every required final link and are never
stored as cache contents.

The optional manifest can be initialized without changing the module's Silex
sources:

```text
silex module init PATH/TO/MODULE
silex module init PATH/TO/MODULE --native
```

The plain form creates `@Module.json` containing `{}`. The native form creates
or completes the manifest with `@Native/Module.cpp` as a portable C++ source
and creates that file only when it is absent. Existing metadata, source files,
and native configuration are never overwritten implicitly. A library author
can then replace this starting point with any explicit source layout;
`Library/STD` lists four independent `.cpp` units instead.

## Local packages

A directory remains an implicit module when it only contains Silex sources or
submodule directories. It needs no manifest, and neighboring local modules keep
their existing filesystem resolution.

A directory consumed as an external dependency is a declared package. Its
`@Module.json` names the root module, gives it a Semantic Version, and may list
other packages required directly by its sources. `STD` is not such a package:
it is a reserved distributed module and must be used directly without a
`dependencies` entry. The repository does not currently ship a public external
package, so the following fragments use explicit placeholders to describe the
manifest shape rather than names of available modules:

```json
{
  "name": "<package-name>",
  "version": "<semantic-version>",
  "dependencies": {
    "<dependency-name>": {
      "path": "<relative-directory>"
    }
  }
}
```

The package root provides the module named by `name`; a subdirectory adds its
own segment below that root module, exactly as `Time/` provides `STD.Time`
below `STD/`. A `path` is relative to the manifest that declares it and may
leave that package directory. The destination is canonicalized and must be a
directory containing `@Module.json`. Its `name` must match the dependency key
exactly and its `version` must be valid Semantic Versioning.

A dependency can instead name a Git repository:

```json
{
  "dependencies": {
    "<dependency-name>": {
      "git": "<repository-url>",
      "version": "<version-constraint>",
      "rev": "<commit-id>"
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

An application can declare `dependencies` in a root `@Module.json` without
declaring its own `name` or `version`. For a `.sx` entry the project root is the
entry's directory; for a JSON project manifest it is the manifest's directory.
Without that root manifest, local module loading behaves exactly as before.

Silex resolves and validates the complete package graph before reading used
module sources or compiling native code. The same package name must resolve to
one canonical directory and one version; diamonds reuse that identity once.
Cycles, missing paths, incomplete manifests, name mismatches, and multiple
providers report the dependency chain that led to the error.

Each package can use its own modules, reserved distributed modules such as
`STD`, and the packages it declares directly. Transitive dependencies are
compiled for their parent but do not become importable by an application or
sibling package that did not declare them.

When the graph contains Git, Silex atomically writes the complete resolution to
`Silex.lock` at the application root. Each transitive entry records its name,
version, canonical `path` or `git` origin, exact Git commit when applicable,
and exact dependency identities. A dependent package's own lockfile is never
consulted. A valid root lockfile prevents `compile` and `run` from following a
moved remote branch. `silex update` recomputes all Git origins without `rev`;
`silex update DEPENDENCY_NAME` limits that refresh to the named package and
necessary transitive changes. The existing lockfile is replaced only after the
new graph has been fully validated.

Exact Git checkouts are content-addressed by canonical origin and commit in the
user Silex cache: `~/.silex/packages/` on POSIX systems and the equivalent
user-local directory on Windows. Projects using the same commit share that
source directory. A build whose locked checkouts are already cached does not
contact Git; deleting the cache causes the same commits to be fetched again.
`path` packages always remain at their declared local locations. Package
resolution runs no repository script and does not download a native library
mentioned by a package during compilation.
