# HTTP and diagnostics

## Serving

`sumiweb::serve(app: sumi::App, address: String, options: sumiweb::Options? = null):
sumiweb::ServerError?` prepares the application and binds a loopback listener.
Addresses must be `127.0.0.1:<port>`, with a port from 1 to 65535.

The function serves synchronously and returns `null` after graceful shutdown.
Failures return `ServerError.code` and `ServerError.message`. Callers report an
error and choose a failure exit code only when the return value is non-null.

`Options.handleInterrupts` defaults to `true`: SIGINT and SIGTERM stop accepting
requests, allow an already running handler and its response to finish, and close
the listener. `Options.stop: http::Stop?` also supports synchronous stop requests
from callbacks. A stop requested before serving prevents listener creation.
No new handler starts once shutdown is observed.

`Options.onShutdown: (fn(): Void)?` runs once after the listener closes, on every
exit following a successful listen. It does not run for setup failures or a stop
requested before listening. Use it to finish application cleanup. The lifetime
watcher remains active throughout this callback.

`Options.forceExitAfterStopMilliseconds: Int?` defaults to `null`, meaning no
forced exit. A value from 1 to 60000 starts a fatal deadline when stop is requested
or a listener failure begins shutdown;
if requests or cleanup outlive it, the process exits with status 124. Generated
applications and the web example explicitly choose 30000 milliseconds. This is a
shutdown budget, not a normal request execution timeout.

The sequence of stopping dispatch, finishing active work, and releasing resources
follows the [ASP.NET Core host lifetime](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/generic-host#ihostapplicationlifetime).
Signal handlers only mark native state; application callbacks run on the serving
thread. A forced exit does not unwind application resources or finish cleanup.

`Options.onListening: (fn(String): Void)?` runs once after bind and listen
succeed. `Options.log: (fn(LogEvent): Void)?` receives structured events.
All callbacks run synchronously. With no callbacks, the adapter prints nothing.

The example enables terminal logging. `PORT` chooses its port and `SUMI_PUBLIC`
chooses its asset directory. These variables belong to the example; the library
receives configuration as arguments.

## Concurrent serving

`sumiweb::serveConcurrent(entry: fn(Byte[]): Void, config: Byte[], address: String,
options: sumiweb::ConcurrentOptions): sumiweb::ServerError?` runs a bounded worker
pool behind a nonblocking socket coordinator. The web example and generated
applications use this entry point. `serve` remains the synchronous single-handler
entry point.

The entry must be a named module function. Neri copies configuration into each
worker's private heap; the entry constructs its own application, calls
`sumiweb::runWorker(app)`, and closes its resources when that function returns.
Report initialization, serving or cleanup failures through `workers::fail`.
For example:

```neri
def applicationWorker(config: Byte[]): Void
  let root = text::fromBytes(config)

  if root == null
    workers::fail(text::bytes("Invalid public directory configuration"))
    return
  end
  let app = exampleweb::application(root)

  match sumiweb::runWorker(app)
    case result::Result.Ok(value)
    case result::Result.Error(failure)
      workers::fail(text::bytes(failure.code + ": " + failure.detail))
  end
end
```

`runWorker` prepares routes and assets before reporting readiness. Each worker
handles one request at a time and retains its application state across requests.
Applications, captured mutable objects and database connections belong to the
worker that creates them. Create request-specific state within the handler and
finish transactions within their owning scope. Requests and replies cross heaps
as bounded byte packets; object references and socket handles do not cross.

| Option | Default | Accepted range |
| --- | --- | --- |
| `workerCount` | 4 | 1–64 |
| `maxConnections` | 64 | 1–1024 |
| `maxOutstanding` | 32 | 1–`maxConnections` |
| `maxReservedBytes` | 67108864 | 2228224–1073741824 |
| `startupTimeoutMilliseconds` | 30000 | 1–60000 |
| `forceExitAfterStopMilliseconds` | 30000 | 1–60000, or `null` to disable forced shutdown |

Connection slots cover reading, queued, executing and writing requests. At the
connection limit the coordinator pauses acceptance, leaving the kernel backlog
to apply backpressure. At the job or message-reservation limit it returns 503
with `Retry-After: 1`. Each worker input and output packet is limited to 1114112
bytes. The reservation budget bounds native in-flight message storage; it is
not a bound on application heaps or the complete process memory footprint.
Independent request and response body limits remain 1 MiB.

One coordinator multiplexes socket and worker readiness. Partial reads or writes
do not occupy an application worker. Each connection keeps the same absolute
two-second read and write deadlines as `serve`; synchronous logging time counts
toward an active deadline. HTTP events run on the coordinator; callbacks invoked
by application code, including database observers, run in the owning worker and
may interleave across workers.

The listener opens after all workers are ready. The startup budget includes
worker initialization, listener acquisition and `onListening`. Expiry exits the
process with status 124. Shutdown closes the listener, drops requests not yet
admitted to the pool, drains admitted jobs and response writes, then stops and
joins workers. `onShutdown` runs after worker cleanup. Failed listener acquisition
also arms the shutdown budget before joining workers. Forced exit has the same
cleanup limitations described above.

Bounded stages and admission backpressure follow
[SEDA: An Architecture for Well-Conditioned, Scalable Internet Services](https://www.sosp.org/2001/papers/welsh.pdf).
Sumi uses fixed configured limits; it does not implement SEDA's adaptive resource
controllers.

## Requests and responses

The adapter accepts GET, HEAD, POST, PUT, PATCH, DELETE and OPTIONS over
HTTP/1.1, with one nonempty Host header and origin-form targets (`/path?query`).
It copies method, path, encoded query, request ID, raw body bytes, ordered headers and Content-Type into the
core request. Path and query are not decoded. TRACE, CONNECT and extension
methods are not implemented (501 for syntactically valid origin-form requests).
`OPTIONS *` and proxy/tunnel request targets are outside this local interface.

Each connection carries one request and closes after its response. Headers have
an 8192-byte limit, at most 64 fields and a 7168-byte field budget. One two-second
deadline covers headers and body together. Bodies use a single decimal
Content-Length, up to 1048576 bytes. Every byte value is accepted. No Content-Length
means an empty body. Duplicate lengths and Transfer-Encoding (including chunked)
are rejected with 400. Expect is rejected with 417. Oversized bodies receive 413;
premature body closure receives 400; incomplete reads
that exceed the deadline receive 408 when a response can be sent. Parsing happens
before handlers run. Text, JSON and form decoding is explicit in the application;
decoding failures never change the raw body. Multipart parsing is not supplied.

Socket reads reuse a 16 KiB buffer. Incremental framing preserves partial header
delimiters and body bytes delivered in the same read as the headers. Fragmentation
does not reset the request deadline or relax the header and body limits.

One absolute two-second write deadline covers both header and binary body writes.
Handlers have no execution deadline.
Responses include content type, byte-counted content length, `Connection: close`,
`X-Content-Type-Options: nosniff`, and `X-Request-Id`. The adapter accepts statuses
200–599 and byte bodies up to 1048576 bytes. Invalid status, content type, Allow
methods, reserved custom headers or body size produces a generic 500 and an internal diagnostic.
Statuses 204 and 304 omit the body and content length; 205 sends an empty body.

Custom response fields use `http::Headers`, retaining order and duplicate values.
The adapter reserves `Content-Length`, `Transfer-Encoding`, `Connection`,
`Content-Type`, `Allow`, `X-Request-Id`, `X-Content-Type-Options`, `Trailer`,
`Upgrade`, `Keep-Alive`, `Proxy-Connection` and `TE`, case-insensitively.
Use response properties for content type and allowed methods. Invalid field
syntax or exceeded header budgets are rejected by `Headers.add` before insertion.
Custom headers allow at most 64 fields and 7168 bytes, including field names,
values and separators. The adapter rejects repeated `Location`, `Content-Location`,
`ETag`, `Last-Modified`, `Retry-After`, `Date` and `Server` fields regardless of
capitalization, returning a generic 500. `Set-Cookie` remains repeatable. Other
extension fields retain duplicates; callers must ensure their field definition
permits repetition, following [RFC 9110 section 5.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.3).

HEAD uses an explicit route or falls back to GET, retaining status and
representation metadata while omitting all body bytes, including on errors.
Its Content-Length is the byte length of the corresponding body, even for binary content.
Known paths with no matching method receive 405 and `Allow` for that path.
OPTIONS defaults to 204 with `Allow`, or dispatches an explicit OPTIONS handler.
An unknown path retains 404 for supported methods. No CORS policy is implied.
Malformed requests receive 400; unsupported versions receive 505; oversized
headers receive 431. These are bounded local serving semantics, not a claim of
complete HTTP/1.1 support. Method and framing rules are based on
[RFC 9110 sections 8.6 and 9.3.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-8.6) and
[RFC 9112 section 6.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3).

The core returns 404 for unmatched paths. Only explicitly registered asset
paths are exposed. There is no directory listing, path decoding, automatic index
selection, or request-driven filesystem access.

See [Logs](LOGGING.md) for events, request IDs and debugging.

## Error codes

| Code | Meaning and corrective action |
| --- | --- |
| `SUMI_REQUEST_ID_ENTROPY` | OS secure randomness is unavailable. Restore it before restarting; no fallback ID is used. |
| `SUMI_LOG_LEVEL` | Invalid minimum log level. Use `debug`, `info`, `warning`, `error`, or `off`. |
| `SUMI_STATIC_READ` | A registered file could not be read or closed. The message names its source and route and includes the operation/OS failure. Check the path and permissions. |
| `SUMI_STATIC_SIZE` | A file exceeds 1 MiB. Reduce the asset size. |
| `SUMI_CONTENT_TYPE` | A static registration has an invalid content type. Supply a media type, optionally followed by `; charset=utf-8`. |
| `SUMI_ROUTE_METHOD` | Unsupported registration method. Use GET, HEAD, POST, PUT, PATCH, DELETE or OPTIONS. |
| `SUMI_ROUTE_PATTERN` | Invalid route pattern. Check leading slash, empty segments, and parameter names. |
| `SUMI_ROUTE_DUPLICATE` | An equivalent pattern already exists. Remove or distinguish it. |
| `SUMI_CONFIG_CLOSED` | Registration occurred after preparation. Construct all routes and middleware before serving. |
| `SUMI_APP_NOT_READY` | Dispatch was attempted before valid preparation. Inspect `prepare()`. |
| `SUMI_NEXT_REPEATED` | Middleware called `next` more than once. Reuse the first response. |
| `SUMI_NEXT_EXPIRED` | Middleware called `next` after its callback returned. Keep the call inside the synchronous callback. |
| `SUMI_ROUTE_NOT_FOUND` | No route was selected for the request. |
| `SUMI_RESPONSE_STATUS` | A response status is outside 200–599. The message includes the invalid status. |
| `SUMI_RESPONSE_ALLOW` | Response Allow contains a method outside the supported set. |
| `SUMI_RESPONSE_HEADERS` | A custom response header conflicts with a field managed by the adapter or repeats a known singleton field. |
| `SUMI_RESPONSE_SIZE` | A handler response exceeds 1 MiB. |
| `SUMI_RESPONSE_CONTENT_TYPE` | A response has an invalid media type or header controls. |
| `SUMI_HANDLER_ERROR` | The application returned a 5xx without an explicit diagnostic. Attach diagnostic fields or use `sumi::failure`. |
| `SUMI_HTTP_<status>` | The request was rejected before dispatch. The message identifies the supported protocol limit or rejection category. |
| `SUMI_HTTP_WRITE` | A write failed or timed out. Delivery is incomplete. |
| `SUMI_HTTP_STOPPED` | Shutdown was observed before application dispatch; the connection closes without invoking a handler. |
| `SUMI_CONNECTION_CONFIGURE` | Socket setup for an accepted connection failed. |
| `SUMI_LISTEN_ADDRESS`, `SUMI_LISTEN_PORT` | Invalid listener configuration. |
| `SUMI_LISTEN_OPEN` | A socket could not be created. |
| `SUMI_LISTEN_SETUP` | Configure, bind, or listen failed. The message includes the exact operation, address, and OS detail. |
| `SUMI_LISTEN_POLL`, `SUMI_LISTEN_ACCEPT` | Listener I/O failed. The server returns the error. |
| `SUMI_LIFETIME_OPEN` | Interrupt ownership or the shutdown deadline could not be established. Check the supplied budget and existing server lifetime. |
| `SUMI_SOCKET_CLOSE`, `SUMI_LIFETIME_CLOSE` | Resource cleanup failed. If another error already exists, its code is retained and cleanup details are appended to its message. |
| `SUMI_CONCURRENCY_OPTIONS` | Invalid worker, connection, message or startup limits. |
| `SUMI_CONCURRENT_START`, `SUMI_CONCURRENT_CLOSE` | Concurrent resource acquisition or cleanup failed. The message includes the underlying operation and failure chain. |
| `SUMI_SERVER_BUSY` | The bounded worker admission limit was reached; response status is 503. |
| `SUMI_WORKER_PROTOCOL`, `SUMI_WORKER_REPLY_SIZE` | A worker packet or its HTTP framing is invalid or exceeds the packet budget. |
| `SUMI_WORKER_FAILED`, `SUMI_WORKERS_STOPPED`, `SUMI_WORKER_POLL`, `SUMI_WORKER_ADMISSION`, `SUMI_WORKER_STOP` | Worker execution, availability or lifecycle failed; the server begins shutdown. |
| `SUMI_WORKER_CANCELLED` | An admitted job was cancelled; response status is 503. |

Application diagnostics should use their own codes and actionable messages.
Internal diagnostic fields are not serialized into error responses. Static
configuration errors stop startup before the listener opens.

The adapter currently reports a shared 400 category for malformed headers,
targets, unsupported framing and early connection closure; it does not identify
a specific offending header. Write helpers group timeout and I/O failures.
Sumi does not invent a more specific cause than those helpers report.

## Execution limits

The server binds loopback. TLS, keep-alive,
streaming, multipart parsing, and cache validators
are outside the current interface. Application callbacks, including logging,
must finish promptly.

Fatal runtime failures and forced termination cannot be caught by this adapter.
They may leave a started event without a terminal event. Sumi does not promise
automatic recovery or stack traces for failures the language cannot unwind.
