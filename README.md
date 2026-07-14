# Silex

Silex is a compiled programming language that produces native executables. The
language aims for concise, familiar syntax.

```sx
struct Rover {
    name:str
    energy:int
    trail:int[]

    func travel(cost:int) int {
        self.energy -= cost
        self.trail.append(self.energy)
        return self.energy
    }
}

func recharge(energy:&int, amount:int) int {
    energy += amount
    return energy
}

func main() {
    var rover = Rover {
        name:"Silex",
        energy:12,
        trail:[]
    }
        ..travel(2)
        ..travel(3)

    let before:int = rover.energy
    let after:int = recharge(&rover.energy, 3)

    var replay = rover.trail
    replay.reverse()

    print(rover.name)
    print(before)
    print(after)
    print(replay[^1])
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
