# STD

Silex distributes the source of `STD` with the compiler. `STD` is a reserved
root namespace: its file namespaces are compiled with the program when
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
  simulations, tests, and the random collection algorithms.
- [Algorithms](Algorithms.md) — generic in-place sorting, borrowed random
  selection, and in-place shuffling over contiguous views.
- [Console](Console.md) — text output and optional interactive-terminal
  display control.
- [System](System.md) — portable structured errors for system resources and
  I/O.
- [Path](Path.md) — portable UTF-8 paths and deterministic lexical operations.
- [IO](IO.md) — synchronous binary stream contracts and bounded algorithms.
- [File](File.md) — owned seekable binary files, explicit creation policies,
  and bounded whole-file helpers.
- [FileSystem](FileSystem.md) — deterministic directory discovery, metadata,
  and explicit non-recursive filesystem mutations.
- [Environment](Environment.md) — copied process variables with strict Unicode,
  platform name comparison, and deterministic enumeration.
- [Process](Process.md) — arguments, current directory, executable image path,
  and native identifier of the current process.
- [Subprocess](Subprocess.md) — exact blocking child execution with binary
  stdin, concurrent captured outputs, controlled environment, and hard limit.
- [JSON](JSON.md) — immutable ordered DOM, strict RFC 8259 parsing, exact number
  lexemes, and deterministic compact or pretty serialization.
- [Network](Network.md) — portable IP addresses, scoped endpoints, blocking
  resolution, and the synchronous TCP/UDP modules.
- [Queue](Queue.md) — generic FIFO value container with amortized constant-time
  head operations.
- [Stack](Stack.md) — generic LIFO value container with constant-time top
  operations.
- [Dictionary](Dictionary.md) — generic hash table with value semantics and
  caller-provided hash and equality functions.
- [Set](Set.md) — generic hash set that preserves the first representative of
  each equivalence class.
- [Iterator](Iterator.md) — owned snapshots for standard collections, lists,
  and contiguous views.
- [Text](Text.md) — strict UTF conversions, scalar access, normalization,
  casing, and grapheme segmentation.
- [Time](Time/README.md) — monotonic elapsed-time and logical-loop utilities.
  - [Stopwatch](Time/Stopwatch.md) measures bounded real durations.
  - [Clock](Time/Clock.md) drives scaled and pausable logical time.

Each API page gives the exact `use` path, behavior, limits, and available
operations. Native implementation details shared by the library remain
described with the API that exposes them.
