# Install and use Silex

## Install a distribution

A Silex distribution is self-contained. Extract the archive for your host
platform and add its `bin/` directory to `PATH`:

```sh
export PATH="$PWD/silex-<version>-<arch>-<os>/bin:$PATH"
silex --version
```

The distribution includes the Zig executable and library it requires. Its
`silex` binary does not fall back to an arbitrary Zig installation on the host.

## Compile and run a program

```sx
func main() {
    print("Hello from Silex")
}
```

```sh
silex compile hello.sx
silex run hello.sx
```

`compile` writes a native executable. `run` compiles and executes the program.
The source layout and module model are in the [language reference](Language.md).
The installed distribution also contains Silex's distributed-library sources,
so `use STD`, declarations such as `STD.Randomizer`, and submodules such as
`STD.Time` work without cloning this repository or adding their module files to
the project.
The available APIs are indexed in the [library reference](Language.md#libraries).
A directory-backed local or distributed module may provide an optional
`@Module.json`. Its `native` section is compiled and linked once when any module
that inherits it is loaded.

## Projects and manifests

For a small program, pass its entry source file directly. Its directory is the
local project root: each subdirectory is a module, including a parent that only
contains submodules, and the `.sx` files directly inside that directory belong
to it. Using a parent does not recursively load all of its descendants. A
directory beginning with `@` is reserved for non-module infrastructure and is
skipped by automatic module discovery; explicit native source and include paths
may still point into it. A project can therefore use `@Native/`, `@Docs/`, or
another infrastructure name without exposing it through `use` completion.

Pass a JSON manifest when the target program itself spans several source files,
or when the project needs to assign files to modules explicitly:

```json
{
  "target": "Example.App",
  "modules": [
    {
      "name": "Example.App",
      "sources": ["Main.sx", "Commands.sx"]
    },
    {
      "name": "NK.Window",
      "sources": ["Window.sx"]
    }
  ]
}
```

Run it as an input to `compile` or `run`:

```sh
silex run path/to/project.json
```

`target` is the name of the module that supplies `main`. Every entry in
`modules` has a logical `name` and a non-empty list of `sources`, whose paths
are relative to the manifest. A source belongs to one module only, and each
module name has one provider. Files in the same module share their declarations.
Every dotted module name also makes its parent names available as source-less
modules: declaring `NK.Window` makes `NK` importable without an artificial
source entry. A module can discover `@Module.json` from the directory matching
its logical name relative to the project manifest, such as `Math/@Module.json`
for `Math`. The project manifest format is currently JSON.

## Command line

```text
silex compile <source.sx|project.json> [-o <executable>] [--emit-cpp]
    [--target <arch-os-abi>] [--native <dependency.json>]
silex run <source.sx|project.json> [--native <dependency.json>]
silex module init <directory> [--native]
silex update [package]
silex clean
silex --help
silex --version
```

`compile` checks a program, prepares its intermediate output, and writes the
executable into `.silex/bin/` unless `-o` selects a path. `--emit-cpp` keeps
readable intermediate output in `.silex/generated/`. `--target` accepts a Zig
architecture, operating system, and ABI triple. `--native` adds a JSON-described
link dependency with `name`, `sources`, and supported `targets`. It is separate
from the optional `native` section of an automatically discovered `@Module.json`,
which authorizes that named module's native function implementations.

When a link is required, `compile` reports each native package compiled or
reused, then reports the application link separately. An unchanged local build
is reported as up to date; internal cache paths are not part of this command's
output contract.

`module init` creates the optional `@Module.json` for a directory-module without
changing any existing source. The plain form writes an empty manifest. With
`--native`, it adds the portable `native.sources.cpp` configuration and creates
`@Native/Module.cpp` only when that file does not already exist. Existing
metadata and native sources are preserved; invalid manifests and path
collisions are reported before any file is created. An old `Module.json` found
at a module location is rejected with an instruction to rename it to
`@Module.json`.

A root `@Module.json` may also declare local package dependencies. Each entry
maps an importable root module name to a package directory relative to that
manifest:

```json
{
  "dependencies": {
    "Foundation": {
      "path": "../Foundation"
    }
  }
}
```

Referenced packages declare matching `name` and Semantic `version` fields in
their own `@Module.json`. A package shared through Git uses `git` instead of
`path` and adds a version constraint:

```json
{
  "dependencies": {
    "Foundation": {
      "git": "https://example.com/Foundation.silex.git",
      "version": "^1.2"
    }
  }
}
```

The first successful resolution writes `Silex.lock` beside the application's
root `@Module.json`. Later `compile` and `run` commands reuse the exact Git
commits in that file. `silex update` refreshes every dependency that does not
declare `rev`; `silex update Foundation` refreshes only that package and the
transitive changes its new checkout requires. A failed update leaves the old
lockfile intact.

## Build artifacts

Silex keeps generated files under `.silex/` in the directory from which the
command is invoked:

```text
.silex/
├── bin/          produced executables
├── build/        generated C++, local objects, logs, and link results
├── generated/    intermediate output kept by `--emit-cpp`
└── interfaces/   stable native headers for editors
```

When the resolved program contains native sources owned by the application or
its local modules, `compile` and `run` also write `compile_commands.json` beside
`.silex/` in the working directory. Each C, C++, Objective-C, or Objective-C++
source receives the effective Zig driver, target, profile, generated
native-interface include path, module include paths, defines, and language
standard used by its object compilation.

Generated native contracts remain immutable under the content-addressed build
cache used by the compiler. The same header contents are refreshed at stable
paths under `.silex/interfaces/SilexNative/`, and the compilation database
places `.silex/interfaces` before the cached include root for editor navigation.
`.silex/interfaces/.generation` records the matching cached interface hash.
Stable headers are generated output and must not be edited.

The project database excludes the distributed Silex library, Git packages and
other external package sources even when they participate in the same build.
Those sources live outside the application tree and their compilation metadata
belongs to their own development workspace.

When Silex itself is built from this repository, the development build creates
`Repository/compile_commands.json` separately. That database covers the native
sources maintained under `Repository/Library`, points to those editable files
rather than their installed copies under `zig-out`, and includes the generated
`SilexNative` interface required by the library implementation. This repository
artifact is ignored by Git and is not generated by an installed distribution.

No compilation database is created for a program without native module
sources. Silex refreshes the stable headers and database as soon as the native
graph and commands are known, before compiling or linking native code. A newly
declared `native func` is therefore visible to editor tooling even when that
command then fails because its C or C++ implementation is still missing. Cache
hits refresh the same tooling outputs. The most recent native `compile` or
`run` defines the graph and target presented to native editor tooling.

`silex clean` removes the `.silex/` directory from the current directory.
It does not remove `Silex.lock` or anything in the user Silex directory.

Resolved Git sources and compiled package objects are shared separately:

```text
~/.silex/
├── packages/          immutable Git source checkouts
└── cache/
    └── objects/       native package objects keyed by content and target
```

The equivalent user-local Silex directory is used on Windows. The object cache
is disposable: deleting `cache/objects/` only forces packages to compile again.
Its entries are published atomically and reused only when their completion
marker and every expected `.o` are present. It never contains the application's
generated C++, executable, or final system-library and framework checks.

## Errors

Diagnostics identify the source file, line, column, and the error in Silex
terms. When useful, they include both expected and actual types.

```text
hello.sx:3:17: error: expected 'int', found 'str'
```
