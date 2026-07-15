# Standard library

Silex distributes its standard-library sources with the compiler. `STD` is its
reserved root module; directories below it provide submodules that are compiled
with the program when explicitly imported or used. They are versioned with
Silex itself; projects do not list them in a JSON manifest.

```sx
import STD

use STD.Random as Random
use STD.Random.Generator as Generator

func main() {
    var random:Generator = Random.system()
    let value = random.get_int()
    print(value > 0)
}
```

## Random

`STD.Random.create(seed)` returns a deterministic `Generator`. Equal seeds
produce equal sequences. `STD.Random.system()` returns a generator initialized
from the platform runtime. `get_int()`, `get_float()`, and `get_bool()` produce
typed values, while the overloads with minimum and maximum arguments produce a
value in the requested half-open interval. Every call advances only that
generator's state.

The deterministic transition is implemented in Silex. Only the system seed is
provided by the private native runtime declared at the `STD` root and linked
automatically when `STD.Random` is loaded.

## Time

`STD.Time.Stopwatch` measures a real duration for benchmarks and other bounded
operations. `start()` begins or resumes accumulation, `stop()` freezes it,
`reset()` clears it while remaining stopped, and `restart()` clears and starts
in one operation. `get_elapsed_seconds()` and
`get_elapsed_milliseconds()` remain readable while running or stopped.

`STD.Time.Clock` drives a logical loop. Its first `tick()` establishes the
monotonic origin and returns zero; subsequent ticks return the scaled seconds
since the previous tick and advance the logical total. `pause()` with
`resume()` excludes suspended time. `set_time_scale(scale)` preserves the
already elapsed segment under the previous scale before selecting the new one.
`reset()` clears the logical timeline and makes the next tick a new first tick.

All state transitions and conversions are implemented in Silex. The shared
native runtime only supplies a monotonic timestamp in microseconds.
