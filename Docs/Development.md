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
