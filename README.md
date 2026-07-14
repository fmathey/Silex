# Silex

Silex is a compiled programming language that produces native executables. The
language aims for concise, familiar syntax.

```sx
func main() {
    var values:int[] = [1, 2, 3]
    values.append(4)

    for (value in values) {
        print(value)
    }
}
```

Silex is an early prototype. The implemented core includes functions, local
values, structures and methods, collections, modules, deterministic value
semantics, control flow, and native compilation.

## Documentation

- [Documentation index](Docs/README.md)
- [Install and use Silex](Docs/Installation.md)
- [Language reference](Docs/Language.md)
- [Develop the toolchain](Docs/Development.md)

## Repository layout

```text
Editors/Zed/    Zed extension and Tree-sitter grammar
Toolchain/      standalone Zig project for the `silex` command
  Sources/      compiler implementation
  Tests/        focused invalid programs and expected diagnostics
  Smokes/       end-to-end `.sx` programs
  Benchmarks/   Silex workloads and equivalent native references
```
