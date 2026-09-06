# Neri compatibility

Sumi targets Linux with Neri's native compiler and runtime. Compatibility depends
on the available language and runtime contracts, not just the version string.
The verified installation is `neri 0.2.0-dev`, toolchain identity
`0441f03f145c22393c2746d48785dd601921726739d4b985f8bacd0abb6e4286`.
An installation with the same version string may expose different capabilities.

## Verification

From the framework checkout:

```sh
scripts/check-compatibility.sh --compile-only
scripts/check-compatibility.sh
```

`NERI` selects an executable. The checker resolves its launcher path once and
reports that path, launcher SHA-256, and version. The launcher hash identifies
that file, not every compiler, runtime, or standard-library component.

The compile-only check builds all declared framework source sets and the native
CLI without starting a listener. A failure preserves the compiler diagnostic and
adds the failed source set and compatibility guidance. It proves compilation,
not runtime behavior.

The full check runs the behavior suite in Debug and Release: routing and
middleware, environment precedence and errors, real HTTP requests, and generated
projects outside the checkout with renamed directories. It briefly starts
loopback listeners and stops every listener it starts. It requires Bash, curl,
GNU core utilities, and `setsid`, along with the compiler's own build prerequisites.
A failing test can indicate a local environment problem; it does not by itself
prove a compiler defect.

## Required contracts

| Boundary | Required behavior |
| --- | --- |
| Projects | `build` and `run` with `--project` and named `--source-set`; explicit source paths; Debug and Release native executables. |
| Language | Classes, nullable values with narrowing, arrays, contextual callbacks, trailing `do` blocks, and managed captured state that survives its declaring call. |
| Host | UTF-8 text reads and writes, byte inspection and boundary-safe slicing, integer parsing, absolute paths, arguments, process environment, synchronous child execution with argument arrays and exit status. |
| Clock | `clock.milliseconds()` returns an optional millisecond reading suitable for elapsed durations. A missing reading is reported as duration `-1`. |
| Listener | `http.netOpen`, `netConfigure`, `netBind`, `netListen`, `netPoll`, `netAccept`, `netClose`, and `socketError`. Accepted descriptors belong to the adapter until closed. |
| Request | `http.readHead` bounds headers to 8192 bytes and applies a two-second deadline; `http.parse` validates the supported HTTP/1.1 request and exposes method, path, query, and rejection status. |
| Response | `http.writeText` writes the serialized UTF-8 response with a two-second deadline and reports whether delivery succeeded. |

`src/http/http.hk` owns the transport boundary. Application routes use Sumi's
request and response types. The adapter serializes responses, enforces the
1 MiB response limit, and attaches request IDs and diagnostics.

The current transport uses low-level standard-library helpers. Their presence
and behavior are required; they are not treated as a stable versioned transport
interface. Run the full check when changing toolchains.

## Current limits

- Multi-source project roots must use ASCII characters on the verified
  toolchain; spaces are supported.
- The server is synchronous, GET-only, loopback-only, and serves UTF-8 bodies.
- Some parser and socket failures expose grouped status or Boolean results.
  Sumi reports those categories without inventing a more specific cause.
- Process interruption stops the server; graceful connection draining is not
  available.
- Persistent typed application evaluation is unavailable, so `sumi console`
  reports `SUMI_CONSOLE_UNAVAILABLE`.

Compilation success does not imply these missing capabilities are available.
