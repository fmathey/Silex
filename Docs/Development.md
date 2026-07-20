# Develop Silex

The compiler lives in the standalone Zig project at `Toolchain/`. It currently
requires Zig 0.16 and translates Silex source to C++ before producing native
executables.

```sh
cd Toolchain
zig build
```

The development executable is installed at `Toolchain/zig-out/bin/silex`.

## Verification

```sh
cd Toolchain
zig build test
zig build smoke
zig build cross-smoke
zig build cross-native-smoke
```

`test` runs targeted compiler checks; `smoke` compiles and runs Silex programs.
The cross-platform checks are available when needed, but macOS ARM64 is the
current development target.

Source-quality checks are explicit: `silex lint <source.sx|project.json>` walks
the parsed AST without starting compilation or creating `.silex` artifacts.
Its diagnostics use stable rule codes and are ordered by source path and
position, which keeps command-line and future editor consumers deterministic.

## Build a distributable toolchain

```sh
cd Toolchain
zig build dist-check
```

The verified distribution is written below
`Toolchain/zig-out/dist/silex-<version>-<arch>-<os>/`.

## Zed integration

The Zed extension and its Tree-sitter grammar are in `Editors/Zed/`. Its local
development workflow is intentionally kept outside this public repository.
The extension starts `silex lsp`; Zed's ordinary format action then uses the
server's whole-document formatter. Formatting always follows the canonical
Silex style, independently of editor tab and space preferences. For every open
`.sx` document, the same server also publishes the warnings produced by
`silex lint` from the current in-memory text; Zed displays them through its
ordinary diagnostics interface without a separate Tree-sitter or Rust linter.
