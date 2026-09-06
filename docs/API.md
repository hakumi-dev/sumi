# Sumi API

All public names belong to the `sumi` namespace.

## Application

| Operation | Contract |
| --- | --- |
| `new App()` | Creates an application with an empty configuration. |
| `get(path: String, handler: fn(Request): Response): Void` | Registers a GET handler. |
| `file(path: String, source: String, contentType: String): Void` | Reads a UTF-8 file and registers its captured content as a GET response. |
| `around(action: fn(Request, fn(Request): Response): Response): Void` | Registers synchronous middleware. |
| `prepare(): ConfigurationError?` | Returns the first configuration error, or closes registration and returns `null`. |
| `handle(request: Request): Response` | Dispatches a copy of the incoming request through the prepared middleware chain. |

Registration records the first error and ignores subsequent additions. Calling
`prepare()` again after successful preparation is harmless. Registering a route
or middleware after preparation invalidates the application; a subsequent
`prepare()` returns `Application is already prepared`.

An unprepared or invalid application returns `500`, `Internal Server Error`,
without invoking middleware or handlers. Configuration details are available
through `ConfigurationError.code` and `ConfigurationError.message`, not through that response. Create a new
application to replace an invalid configuration.

## Routes

Patterns and request paths start with `/`. The root path is `/`. Other paths
contain nonempty segments separated by `/`; trailing slashes and repeated slashes
are not accepted. Query strings and fragments are not part of a Sumi path.

A segment beginning with `:` declares a parameter. Its name matches
`[A-Za-z_][A-Za-z0-9_]*` and must be unique within its pattern. Each parameter
matches exactly one nonempty segment. All other segments match literally.
Matching is case-sensitive and preserves UTF-8 and percent escapes; Sumi does
not decode or normalize paths.

Among matching routes, compare segments from left to right. A literal wins over
a parameter at the first difference. Registration order does not change the
result:

| Registered patterns | Request | Selected pattern |
| --- | --- | --- |
| `/users/:id`, `/users/new` | `/users/new` | `/users/new` |
| `/:section/new`, `/users/:id` | `/users/new` | `/users/:id` |

Equivalent patterns are configuration errors. This includes repeated literal
patterns and patterns differing only in parameter names, such as `/users/:id`
and `/users/:name`.

Malformed patterns produce `Invalid GET pattern: <pattern>`. Equivalent patterns
produce `Duplicate GET pattern: <pattern>`.

An unmatched request returns `404`, `Not Found`. This includes unsupported
methods, invalid path shapes, and paths with no registered handler. The method
must be exactly `GET` to reach a route. Middleware can intercept any request
before routing.

## Request and response

`new Request(method: String, path: String)` creates an incoming request.
`method`, `path`, `query`, and `requestId` are readable and writable strings.
The last two default to empty; the HTTP adapter supplies the encoded query and
connection-local request identifier. `param(name: String):
String?` returns a matched path value or `null`.

`handle` copies the caller's request before middleware runs. Middleware may
change that copy or forward a different request. Dispatch creates a separate
request for the selected handler and attaches only that route's parameters.
Handler changes to its request do not change the middleware or caller request.
Parameters do not persist between calls to `handle`.

`text(body: String, status: Int = 200): Response` constructs a text response.
`new Response(status: Int, body: String)` is its explicit constructor. `status`
and `body` are readable and writable. The in-memory core stores these values
without HTTP serialization or status-range validation. `contentType` defaults to
`text/plain; charset=utf-8`. `html(body, status = 200)` creates a response with
`text/html; charset=utf-8`.

`file` reads at registration, before `prepare`, and retains that snapshot.
Missing, unreadable, invalid UTF-8, and oversized files invalidate configuration.
A file may be up to 1048576 bytes. Content types accept a token/token media type
and optionally the exact suffix `; charset=utf-8`. Controls and malformed media
types are rejected. Each dispatch creates a fresh response.

Source paths resolve against the process working directory. Registered files
are trusted application configuration, including any symlink targets. Request
paths never select filesystem paths. Register each asset explicitly; automatic
index resolution, binary bodies, ranges, and cache validators are not provided.

`failure(code: String, message: String, status: Int = 500)` returns a generic
`Internal Server Error` body with internal diagnostic fields. The HTTP logger
receives `diagnosticCode` and `diagnosticMessage`; neither is serialized to the
client. Use explicit `text` or `html` responses for messages intended for users.
The router sets `Response.route` to the winning pattern for diagnostics.
Middleware that replaces a response should preserve its diagnostic fields and
route when those still describe the returned result.

Parsing and validation belong to the application. For example, `host.parseInt`
returns an optional integer; an application can respond with `400` when parsing
fails or a parsed value falls outside its domain's allowed range.

## Middleware

For registrations `A`, then `B`, dispatch runs in this order:

```text
A before → B before → handler or 404 → B after → A after
```

Middleware may return early. A continuation belongs to one invocation: call it
at most once, synchronously, before the middleware returns. Do not store it for
later use. Each request receives fresh continuation state.

A repeated call returns `500`, `Internal Server Error`, without running downstream
code again. The violating middleware invocation also returns that error even
if its callback ignores the repeated call's result. A call after the middleware
has returned receives the same error and cannot dispatch; it does not change a
response already returned to the caller. An outer middleware may transform any
returned response, including errors.

These checks do not undo downstream side effects from the first call and do not
catch fatal language/runtime failures. Execution is synchronous; the core does
not schedule concurrent requests or enforce handler deadlines.
