# STD

Silex distributes the source of `STD` with the compiler. `STD` is a reserved
root module: its modules and source units are compiled with the program when
explicitly selected with `use`. They are versioned with Silex itself, so a
project must not list `STD` in its `@Module.json` dependencies.

```sx
use STD.Randomizer as Randomizer

func main() {
    var random = Randomizer.create()
    print(random.get_int() > 0)
}
```

## APIs

- [Randomizer](Randomizer.md) — reproducible pseudo-random values for games,
  simulations, and tests.
- [Console](Console.md) — text output and optional interactive-terminal
  display control.
- [System](System.md) — portable structured errors for system resources and
  I/O.
- [Time](Time/README.md) — monotonic elapsed-time and logical-loop utilities.
  - [Stopwatch](Time/Stopwatch.md) measures bounded real durations.
  - [Clock](Time/Clock.md) drives scaled and pausable logical time.

Each API page gives the exact `use` path, behavior, limits, and available
operations. Native implementation details shared by the library remain
described with the API that exposes them.
