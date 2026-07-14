# Control flow

`if` and `while` conditions must have type `bool`. Each branch and loop body
opens a lexical scope.

```sx
if (enabled) {
    print("enabled")
} else {
    print("disabled")
}

while (count > 0) {
    count -= 1
}
```

`for` iterates through a fixed array or dynamic list. The source is evaluated
once. By default, the iteration name is immutable; `var` requests a mutable
element binding and requires a mutable collection.

```sx
for (value in values) {
    print(value)
}

for (var value in values) {
    value += 1
}
```

The collection is held for the duration of each loop body. An immutable loop
allows other reads but no mutation of the collection; a mutable loop allows no
other direct access to it. `break` exits the nearest loop and `continue` starts
its next iteration.

Pattern matching and string iteration are not part of the current language.
