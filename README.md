# Silex

Silex is a compiled programming language that produces native executables. The
language aims for concise, familiar syntax.

```sx
struct Position {
    x:int
    y:int

    func translate(dx:int, dy:int) {
        self.x += dx
        self.y += dy
    }
}

struct Rover {
    name:str
    position:Position
    energy:int
    trail:int[]

    func travel(dx:int, dy:int) {
        self.position.translate(dx, dy)
        self.energy -= 1
        self.trail.append(self.position.x + self.position.y)
    }
}

func report_energy(energy:int@) {
    print(*energy)
}

func recharge(energy:int&) {
    *energy += 3
}

func main() {
    var rover = Rover {
        name:"Silex",
        position:Position { x:0, y:0 },
        energy:12,
        trail:[]
    }
        ..travel(2, 1)
        ..travel(-1, 3)

    report_energy(&rover.energy)
    recharge(&rover.energy)

    var replay:int[] = copy rover.trail
    replay.append(42)
    let handoff = move replay

    print(rover.name)
    print(handoff.count())
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
