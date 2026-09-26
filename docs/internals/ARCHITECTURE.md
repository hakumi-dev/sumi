# Architecture

| Area | Responsibility |
| --- | --- |
| `src/core/` | Request/response types, route registration, selection and middleware. |
| `src/http/` | Listener, request parsing, serialization and diagnostics. |
| `cli/` | Commands, project selection, environment loading and Ito integration. |
| `console/` | App sessions and completion UI; C handles libedit terminal operations. |
| `tooling/` | Binary package construction, verification and installation. |
| `templates/`, `examples/` | Generated app and runnable examples. |
| `tests/` | Core, HTTP, CLI, terminal and packaging contracts. |

## Request lifetime

Preparation validates routes and builds the middleware chain. Registration then
closes. Dispatch copies the request, runs middleware and selects the most specific
route. Only the handler's copy receives matched parameters. Continuation guards
permit one synchronous `next` call per middleware invocation.

The router scans registered patterns; it has no route index. Static files are
loaded during registration. The HTTP adapter owns accepted sockets and processes
one request per connection, sequentially.

## Toolchain boundary

Neri supplies typed compilation, runtime, file/process/clock/crypto operations and
low-level HTTP helpers. Ito owns package restoration, lockfiles and generated
compiler manifests for package-based apps. Sumi owns framework behavior and
presentation; it does not implement another compiler or interpreter.

The console creates an `ExecutableSession` and calls `initializeProject` with
`consoleApp` exposed as `app`. Evaluation uses `prepare`/`execute`; completion uses
`complete` and validates the returned generation and UTF-8 edit range. Completion
never executes a candidate. Session state is fresh per opening/reset.

The libedit bridge yields input events to Neri on the same thread. Neri owns
candidate selection and edits; native code owns terminal input, geometry and
redraw. PTY tests exercise that boundary through the installed command.
