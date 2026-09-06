# Sumi core

Sumi separates application configuration, route selection, and middleware
execution. Its public boundary is `Request → Response` and has no socket
ownership or process lifecycle.

| Source | Responsibility |
| --- | --- |
| `src/core/app.hk` | Configuration state, preparation, and the public dispatch entry point. |
| `src/core/message.hk` | Requests, responses, configuration errors, and matched parameters. |
| `src/core/path.hk` | Path segmentation, pattern validation, and specificity. |
| `src/core/router.hk` | Route registration, conflict detection, and handler selection. |
| `src/core/middleware.hk` | Middleware composition and per-invocation continuation guards. |

## Configuration

An application owns its router and middleware registry. Registration parses each
pattern once and rejects structural duplicates. The first configuration error
is retained until the application is discarded.

Preparation builds the middleware chain once and closes registration. Handlers
and middleware are typed function values; their captured dependencies retain
normal managed-object lifetime and mutability. Preparation does not freeze the
state of application services.

## Dispatch

Dispatch copies the incoming request, invokes the middleware chain, and selects
a matching GET route. The router scans registered patterns and chooses the most
specific match. Only the selected handler receives a new request with populated
parameters. Unmatched requests produce an ordinary response inside the same
middleware chain.

Paths and route registries use linked nodes. Segment construction is linear in
path size and avoids repeatedly copying growing arrays. Matching scans routes
and their segments; it does not use an index. Registering many routes requires
pairwise conflict checks. The core has no configurable route or path-size limits.

Each middleware invocation owns a continuation guard. The guard tracks whether
it is active and whether it has already dispatched. It expires when the callback
returns. These guards apply to synchronous execution and do not provide thread
synchronization.

## Source integration

An application and Sumi's sources compile together in one module. The documented API
is exposed through `sumi`. Supporting classes have module-internal visibility;
helper functions share the compilation namespace. This is not a separately
enforced package boundary.

The core owns routing and response composition. The `sumiweb` adapter in
`src/http` owns listener lifecycle, serialization, and request diagnostics.
It uses Neri's HTTP parsing, socket, and deadline helpers directly. Those
lower-level helpers are a toolchain compatibility dependency; the real HTTP
contracts verify their integration.

The example's `application(publicDirectory)` constructs routes independently
of startup. The caller supplies filesystem configuration. No source folder
is discovered or loaded by convention, and no persistence contract is imposed.

The adapter accepts one request at a time and closes each accepted connection.
It does not implement request bodies, streaming, TLS, or concurrent handlers.
Static content is loaded once per registration and retained for the application's
lifetime. File loading may allocate up to Neri's host read limit before Sumi
checks its smaller response-size limit.
