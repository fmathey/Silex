# Modules

A module is a logical namespace. Files assigned to the same module share their
structures and functions. A file does not contain a `module` declaration.

When compiling an entry file without a manifest, a directory defines a local
module: `Math/` provides `Math`, and `Math/Geometry/` provides `Math.Geometry`.
Only `.sx` files directly inside a directory contribute to that module.

```sx
import Math
import NK.Rendering as Rendering
use Math.Vec3

func create() NK.Window.Session {
    let direction:Vec3
    return Rendering.create_session()
}
```

`import` names a module and makes it available through its full name or alias.
`use` names one declaration and introduces its name into the current file; it
can establish the dependency without a preceding `import`. Declarations are
private by default. `pub` exposes a structure or function, while `pub use`
re-exports an existing declaration under the current module namespace.

Duplicate providers, missing modules, dependency cycles, ambiguous aliases, and
access to private declarations are compile-time errors. Dependencies are never
implicitly transitive. A project manifest can define this module layout
explicitly; see [Installation and command-line use](../Installation.md).
