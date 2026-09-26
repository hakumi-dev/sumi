# Binary packaging

The package contains the CLI, console, installer, framework sources and app
scaffold. It excludes the Neri compiler/SDK sources. Only package construction
compiles the console; installation and `sumi c` use its prepared executable.

## Identity

`compatibility.txt` (`sumi-console-contract-v1`) records the target and SHA-256 of
Neri's `ARTIFACTS.sha256`, `lib/neri-runtime.json` and `share/neri/manifest.json`.
Installed Neri trees are treated as immutable. Neri validates generated code's
runtime ABI and session layouts.

`SOURCE-MANIFEST.sha256` records build inputs. `ARTIFACTS.sha256` covers distributed
files, including configuration and compatibility metadata. Installation verifies
both the source package and copied tree; console launch verifies the installed
tree and compatibility before app initialization. Hashes detect corruption;
there is no publisher-signing or remote registry protocol.

## Publication

Builds share the stable `build/package-work/source` path and serialize through
`build/package.lock`. A finished package is published under `build/packages/`.
See the [build directory layout](BUILD-DIRECTORY.md) for retention and local
report and cache locations.

Each installation stages a unique directory under `<prefix>/packages`, verifies
it, then renames it into a complete generation. A temporary symlink is renamed to
`<prefix>/bin/sumi`. Concurrent installs activate complete generations; the last
activation wins. Old generations remain for open processes. Source/destination
paths are canonicalized before checking that they do not contain one another.
These are same-filesystem atomic updates, not power-loss durability guarantees.

## Verification

`tests/package_contracts.hk` covers missing/corrupt/incompatible artifacts, clean
installation without SDK sources or the public compiler, updates, concurrent
activation, rollback and independent sessions. See [Contributing](../../CONTRIBUTING.md)
for commands.

Contracts: [POSIX rename](https://pubs.opengroup.org/onlinepubs/9799919799/functions/rename.html).
Design references: [Nix, LISA 2004](https://www.usenix.org/legacy/publications/library/proceedings/lisa04/tech/full_papers/dolstra/dolstra_html/index.html)
and [reproducible build paths](https://reproducible-builds.org/docs/build-path/).

The package includes `sumi-build`, a precompiled consumer of Neri's compiler API.
Server, test, and build dispatch select it for direct manifest projects and as
Ito's compiler.
Ito retains dependency preparation and application execution. The build frontend
uses Neri's existing executable and object caches and suppresses the compiler's
artifact-path announcement when running an app. Builds still announce their
output path. `startup/progress.hk` and its
terminal bridge are compiled into both this frontend and `sumi-console`, so
phase labels, clipping, and line clearing have one implementation.
