# Contributing

See [prerequisites](docs/COMPATIBILITY.md) before building.

## Build and install

| Operation | Command from repository root |
| --- | --- |
| Build a package | `bash scripts/build-package.sh` |
| Install the completed package | `bash scripts/install-cli.sh --prefix "$HOME/.sumi"` |
| Validate current sources and rebuild the package | `scripts/test.sh` |
| Check source formatting | `neri format --check` |

The package directory is recorded in `build/latest-package`, with an adjacent
`.tar.gz`. The checkout's `bin/sumi` runs that snapshot. Rebuild after changing
CLI, console or framework sources; installing never builds implicitly.
See the [build directory layout](docs/internals/BUILD-DIRECTORY.md) for the
package and compiler-cache paths.

Use `NERI` to select a toolchain and `LLVM_PREFIX` to select its LLVM installation.
An interrupted build can leave `build/package.lock`; remove it only after the
builder has stopped, then retry.

Local Neri sources must be installed as a complete toolchain with
`scripts/build.sh install --prefix "$HOME/.neri"` from the Neri checkout.
`NERI="$HOME/.neri/bin/neri"` selects that installation for Sumi commands.

The test suite rebuilds Sumi against the selected Neri package. Keep `NERI` set
when running Sumi if that compiler is not first on `PATH`. A development version
such as `0.2.0-dev` can cover multiple source revisions; use the packaged source
manifest and Sumi's compatibility check to identify the actual toolchain.

## Verify

The suite covers routing, middleware, HTTP, generated apps, console input and
package installation.

The optional Data integration contract requires a sibling `../neri` source
checkout with its concurrency-token mapping generated and a compiler built from
that checkout:

```sh
NERI=/path/to/neri bash tests/data_contracts.sh
```

It builds separate server and HTTP client executables, opens one SQLite session
per server worker, and creates a fresh Data context per request. An isolated
temporary database exercises concurrent reads, writer contention, commit,
request rollback, and session cleanup while SIGTERM drains an active request.
The contract uses source checkouts; package installation is covered separately.
To reuse debug or release binaries, pass the server and driver paths as the two
arguments to `tests/data_contracts.sh`.

Focused console tests:

```sh
mkdir -p build/cache/console-ui
cc -std=c11 -Wall -Wextra -Werror tests/console_terminal.c -o build/cache/console-ui/console-terminal
neri run --project neri.json --unit console-ui-contracts --release -- \
  "$HOME/.sumi/bin/sumi" /path/to/app "$PWD/build/cache/console-ui/console-terminal"
```

Add `-lutil` when linking the PTY driver on Linux. To measure fresh and subsequent
console sessions, use an unused cache directory:

```sh
mkdir -p build/cache
neri run --project neri.json --unit package-contracts --release -- \
  --benchmark "$HOME/.sumi/bin/sumi" /path/to/app "$PWD/build/cache/console-benchmark"
```

This empties the application code cache, not the OS page cache.
`SUMI_CONSOLE_TIMINGS=1 sumi c` exposes initializer and evaluation timings.

[Architecture](docs/internals/ARCHITECTURE.md) · [Packaging](docs/internals/PACKAGING.md)

Shared server startup feedback is covered by `tests/cli_startup_feedback.sh`.
Run it against a built package's `bin/sumi`. It uses finite fixture applications
(no HTTP listener) to verify both manifest and Ito projects, cold and cached
builds, source invalidation, diagnostic cleanup, exit status, and redirected
output. The PTY driver is compiled by the script.
