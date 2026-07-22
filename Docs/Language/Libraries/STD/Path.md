# Path

```sx
use STD.Path as Path

let normalized = Path.normalize("project/./Sources")
let source = Path.join("project", "Sources/Main.sx")
```

`Path` is a transparent alias of `str`, not a distinct runtime value. Every
system boundary validates a path even when it did not come from an operation in
this module. Silex strings are valid UTF-8; a path additionally rejects an
embedded null byte and malformed native roots.

Portable source writes `/` as its separator. POSIX accepts only `/`. Windows
also accepts `\` on input, while every returned path uses `/`. Windows absolute
roots have the form `C:/` or `//server/share/`; letter case is preserved.

The module provides:

```sx
public func validate(path:Path) Result<void,System.Error>
public func normalize(path:Path) Result<Path,System.Error>
public func join(base:Path, child:Path) Result<Path,System.Error>
public func parent(path:Path) Result<Path?,System.Error>
public func name(path:Path) Result<str?,System.Error>
public func stem(path:Path) Result<str?,System.Error>
public func extension(path:Path) Result<str?,System.Error>
public func is_absolute(path:Path) Result<bool,System.Error>
```

`normalize` is lexical. It condenses separators, removes `.`, resolves `..`
without crossing an absolute root, retains leading `..` in a relative path,
and returns `.` for an empty result. It does not inspect the filesystem or
follow symbolic links. `join` returns a normalized absolute child unchanged;
otherwise it joins and normalizes both operands.

Roots have no parent or name. `.profile` has no extension, while
`archive.tar.gz` has stem `archive.tar` and extension `gz`. POSIX paths whose
native names contain non-UTF-8 bytes cannot be represented. Windows conversion
at system boundaries is strict UTF-8/UTF-16, and internal Win32 prefixes are
never returned. Unicode normalization, filesystem identity, reserved names,
case rules, and length limits are outside lexical normalization.
