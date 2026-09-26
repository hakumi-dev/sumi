# Compatibility

Local development is verified on macOS ARM64. The package builder also has a
Linux x86-64 target; the current console has not been validated there.

## Running apps

- Installed native Neri toolchain and a matching Sumi binary package.
- Ito on `PATH` for applications using `package.json`.
- Bash and standard shell utilities, including `/usr/bin/env -C`.

A Sumi package matches an exact Neri toolchain/runtime identity, not just its
version string. After changing Neri, install a matching Sumi package.
The sources use Neri's `::` namespace qualification, `unsafe def` declarations
and typed session status API. Build them with a toolchain that includes these
contracts; see [local source updates](../CONTRIBUTING.md#build-and-install).
`SUMI_CONSOLE_INCOMPATIBLE` means the package and selected toolchain differ;
`SUMI_PACKAGE_CORRUPT` means installed files are missing or damaged. Reinstall a
complete matching package in either case. Installation instructions are in
[Getting started](GETTING-STARTED.md).

`NERI` may also select a development launcher. If it is outside the installed
package, Sumi asks that compiler for its runtime manifest and uses the package
containing the manifest for compatibility checks. In this development-launcher
case, the console session uses the selected compiler. `SUMI_CONSOLE_TOOLCHAIN`
means the selected compiler cannot report a runtime manifest or the
corresponding Neri package is incomplete; install the package before starting
the console.

Interactive console startup reports project loading, source counts, compilation
phases, and native module cache reuse on one temporary line. Where supported,
the object cache reuses unchanged native code, including modules with shared
native libraries.
Each new console process still analyzes the application's source and types.

## Building and testing Sumi

Use the installed Neri toolchain's compiler prerequisites, a C compiler and
libedit headers/library. Verification also needs Bash 4+, curl and GNU coreutils'
`timeout` or `gtimeout`. On macOS, `brew install bash coreutils` supplies the latter
tools; place Homebrew's `bin` directory before `/bin` in `PATH`.

```sh
scripts/check-compatibility.sh --compile-only
scripts/check-compatibility.sh
```

`NERI=/path/to/neri` selects a toolchain. The full check runs HTTP and application
contracts, starts temporary loopback listeners and verifies their shutdown.
See [Contributing](../CONTRIBUTING.md) for package construction and focused tests.

The server's functional limits are listed in [HTTP](HTTP.md).

Server and console startup share Sumi's transient terminal presentation. `sumi s`
uses a packaged build frontend over Neri's compiler API, including when Ito
resolves the project. Both commands show real compilation phases and native
function progress, clear the line before application output or diagnostics, and
keep redirected output free of startup UI. A server cache hit reuses the Neri
executable receipt; it does not reuse a console JIT module.

Executable receipts and the native object cache currently require macOS ARM64.
Linux supports dependency semantic/native snapshots and secure file metadata,
but recompiles and links the application on repeated startup. The startup
contracts query the runtime cache capability and verify the corresponding
reuse or recompilation behavior. Linux end-to-end validation remains pending.
