# Basics

Silex is a compiled language with native executables as its initial output.
The `main` function is the single program entry point.

```sx
func main() {
    print("Hello from Silex")
}
```

An explicit `void` return type is accepted, but omitting it is canonical.
`print` is a built-in function.

## Naming

Program-defined type names use `PascalCase`. Functions, methods, variables,
parameters, and fields use `snake_case`. Identifiers remain permissive; these
forms are the canonical style used by documentation and future formatting.

Type annotations have no spaces around `:`:

```sx
struct WindowSession {
    frame_count:int
}
```

## Local variables

`let` declares an immutable value. `var` declares a reassignable variable. A
declaration needs an initializer, an explicit type, or both.

```sx
let count = 3
let doubled:int = count * 2
var enabled:bool = true
var attempts:int
let title:str
```

An uninitialized typed declaration receives the intrinsic value of its type:
zero for numbers, `false` for `bool`, an empty string for `str`, an empty list
for `T[]`, recursively initialized arrays and structures, and declared field
defaults where present. A declaration with neither type nor initializer is
invalid.

Assignments preserve the variable type. A nested block may shadow an outer
name; two declarations in the same scope may not use the same name.
