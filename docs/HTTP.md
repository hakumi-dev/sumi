# HTTP and diagnostics

## Serving

`sumiweb.serve(app: sumi.App, address: String, options: sumiweb.Options? = null):
sumiweb.ServerError` prepares the application and binds a loopback listener.
Addresses must be `127.0.0.1:<port>`, with a port from 1 to 65535.

The function serves synchronously until process termination or listener failure.
Failures return `ServerError.code` and `ServerError.message`. It has no normal
successful return. The caller reports the error and chooses its process exit code.

`Options.onListening: (fn(String): Void)?` runs once after bind and listen
succeed. `Options.log: (fn(LogEvent): Void)?` receives structured events.
Both callbacks run synchronously. With no callbacks, the adapter prints nothing.

The example enables terminal logging. `PORT` chooses its port and `SUMI_PUBLIC`
chooses its asset directory. These variables belong to the example; the library
receives configuration as arguments.

## Requests and responses

Accepted requests use GET and HTTP/1.1, with one nonempty Host header and no body.
The adapter copies the method, path, encoded query, and request identifier into
the core request. The query excludes `?`; neither the path nor query is decoded.

Each connection carries one request and closes after its response. Headers have
an 8192-byte limit and a two-second read deadline. Writes have a two-second
deadline. Handlers have no execution deadline.

Responses include the content type, a byte-counted content length,
`Connection: close`, `X-Content-Type-Options: nosniff`, and `X-Request-Id`.
The adapter accepts statuses 200–599 and bodies up to 1048576 bytes. Invalid status,
content type, or body size produces a generic 500 with a diagnostic event.
Statuses 204 and 304 omit the body and content length; 205 sends an empty body.

Unsupported methods receive 405 with `Allow: GET`. HEAD is unsupported, and its
rejection has no body. Malformed requests or unsupported body framing receive
400; Expect receives 417; unsupported versions receive 505. Header size and
deadline violations receive 431 and 408 when a response can be sent.

The core returns 404 for unmatched paths. Only explicitly registered asset
paths are exposed. There is no directory listing, path decoding, automatic index
selection, or request-driven filesystem access.

## Log events

A `LogEvent` has these fields:

| Field | Meaning |
| --- | --- |
| `level` | `info`, `warning`, or `error`. |
| `event` | The operation and outcome. |
| `requestId` | Decimal connection sequence within this listener invocation. |
| `status` | Status selected for the wire response, or 0 when none exists. |
| `durationMs` | Elapsed read, handler, and write time, including incomplete reads; -1 if the clock is unavailable. Start events use 0. |
| `method` | Accepted request method; empty for requests rejected before dispatch. |
| `route` | Selected route pattern; empty if routing did not select one. |
| `code` | Machine-readable diagnostic code, empty for ordinary success. |
| `message` | Human-readable cause or operational detail. |

`http.request.started` is emitted before reading headers. It is followed by
`http.request.completed`, `http.request.incomplete`, or
`http.response.write_failed` on supported return paths. Connection setup errors
emit `http.connection.failed` before request processing starts.

Successful responses use `info`, 4xx responses use `warning`, and 5xx responses
use `error`. Write failures are errors even when the selected response status
was 200. Completion means the local socket accepted the bytes; it does not prove
that the client consumed them.

`sumiweb.format(event)` renders one line of quoted key/value fields. Quotes,
backslashes, and controls are escaped or replaced; Unicode text is preserved.
Applications can supply another formatter or destination through `Options.log`.

`Options.minimumLevel` defaults to `info`. Select `debug`, `info`, `warning`,
`error`, or `off`; only events at or above the selected level reach the sink.
`off` disables event delivery. An invalid level returns `SUMI_LOG_LEVEL` before
opening a listener. Filtering does not alter HTTP responses. It can omit start
events while retaining failure events, so a filtered sink may see incomplete
event pairs. The generated server and web example read this option from
`LOG_LEVEL`. Startup failures are always reported by their entry points.

```text
level="error" event="http.request.completed" request_id="4" status=500 duration_ms=1 method="GET" route="/hello/:name" code="APP_GREETING_UNAVAILABLE" message="Greeting service unavailable"
```

The ID is included in the response header and passed to handlers as
`request.requestId`. It resets when the listener restarts and is not a global
or distributed trace identifier. The adapter does not trust an incoming ID.

Default events contain route patterns, not raw paths or parameter values.
Queries, request headers, and bodies are not logged. Application-supplied
diagnostic messages remain the application's responsibility.

## Error codes

| Code | Meaning and corrective action |
| --- | --- |
| `SUMI_LOG_LEVEL` | Invalid minimum log level. Use `debug`, `info`, `warning`, `error`, or `off`. |
| `SUMI_STATIC_READ` | A registered file could not be read as UTF-8. The message names its source and route and includes the host error. Check the path, permissions, and encoding. |
| `SUMI_STATIC_SIZE` | A file exceeds 1 MiB. Reduce the asset size. |
| `SUMI_CONTENT_TYPE` | A static registration has an invalid content type. Supply a media type, optionally followed by `; charset=utf-8`. |
| `SUMI_ROUTE_PATTERN` | Invalid route pattern. Check leading slash, empty segments, and parameter names. |
| `SUMI_ROUTE_DUPLICATE` | An equivalent pattern already exists. Remove or distinguish it. |
| `SUMI_CONFIG_CLOSED` | Registration occurred after preparation. Construct all routes and middleware before serving. |
| `SUMI_APP_NOT_READY` | Dispatch was attempted before valid preparation. Inspect `prepare()`. |
| `SUMI_NEXT_REPEATED` | Middleware called `next` more than once. Reuse the first response. |
| `SUMI_NEXT_EXPIRED` | Middleware called `next` after its callback returned. Keep the call inside the synchronous callback. |
| `SUMI_ROUTE_NOT_FOUND` | No route was selected for the request. |
| `SUMI_RESPONSE_STATUS` | A response status is outside 200–599. The message includes the invalid status. |
| `SUMI_RESPONSE_SIZE` | A handler response exceeds 1 MiB. |
| `SUMI_RESPONSE_CONTENT_TYPE` | A response has an invalid media type or header controls. |
| `SUMI_HANDLER_ERROR` | The application returned a 5xx without an explicit diagnostic. Attach diagnostic fields or use `sumi.failure`. |
| `SUMI_HTTP_<status>` | The request was rejected before dispatch. The message identifies the supported protocol limit or rejection category. |
| `SUMI_HTTP_READ` | The connection ended or failed before complete headers arrived. |
| `SUMI_HTTP_WRITE` | A write failed or timed out. Delivery is incomplete. |
| `SUMI_CONNECTION_CONFIGURE` | Socket setup for an accepted connection failed. |
| `SUMI_LISTEN_ADDRESS`, `SUMI_LISTEN_PORT` | Invalid listener configuration. |
| `SUMI_LISTEN_OPEN` | A socket could not be created. |
| `SUMI_LISTEN_SETUP` | Configure, bind, or listen failed. The message includes the exact operation, address, and OS detail. |
| `SUMI_LISTEN_POLL`, `SUMI_LISTEN_ACCEPT` | Listener I/O failed. The server returns the error. |
| `SUMI_LISTEN_STOPPED` | The listener stopped without another reported cause. |

Application diagnostics should use their own codes and actionable messages.
Internal diagnostic fields are not serialized into error responses. Static
configuration errors stop startup before the listener opens.

The parser currently reports a shared 400 category for malformed headers,
targets, and unsupported body framing; it does not identify a specific offending
header. Socket read and write helpers similarly group timeout and I/O failures.
Sumi does not invent a more specific cause than those helpers report.

## Execution limits

The server is local and sequential. TLS, concurrent handlers, keep-alive,
streaming, request bodies, binary assets, graceful shutdown, and cache validators
are outside the current interface. Application callbacks, including logging,
must finish promptly.

Fatal runtime failures and forced termination cannot be caught by this adapter.
They may leave a started event without a terminal event. Sumi does not promise
automatic recovery or stack traces for failures the language cannot unwind.
