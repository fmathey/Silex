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

## Projects and manifests

For a small program, pass its entry source file directly. Its directory is the
local project root: each subdirectory that is imported becomes a module, and
the `.sx` files directly inside that directory belong to it.

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
The manifest format is currently JSON.

## Command line

```text
silex compile <source.sx|project.json> [-o <executable>] [--emit-cpp]
    [--target <arch-os-abi>] [--native <dependency.json>]
silex run <source.sx|project.json> [--native <dependency.json>]
silex clean
silex --help
silex --version
```

`compile` checks a program, prepares its intermediate output, and writes the
executable into `.silex/bin/` unless `-o` selects a path. `--emit-cpp` keeps
readable intermediate output in `.silex/generated/`. `--target` accepts a Zig
architecture, operating system, and ABI triple. `--native` adds a
JSON-described native dependency with `name`, `sources`, and supported
`targets`.

## Build artifacts

Silex keeps generated files under `.silex/` in the directory from which the
command is invoked:

```text
.silex/
├── bin/          produced executables
├── cache/        content-addressed compilation results
└── generated/    intermediate output kept by `--emit-cpp`
```

`silex clean` removes the `.silex/` directory from the current directory.

## Errors

Diagnostics identify the source file, line, column, and the error in Silex
terms. When useful, they include both expected and actual types.

```text
hello.sx:3:17: error: expected 'int', found 'str'
```
