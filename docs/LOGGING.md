# Logging

```sh
LOG_LEVEL=debug sumi s
NO_COLOR=1 sumi s
```

Levels are `debug`, `info`, `warning`, `error` and `off`; the default is `info`.
Debug includes an event before application dispatch, useful when a handler stalls.

## Read a request log

```text
[2026-09-08T12:34:56.789Z] GET "/users/:id" → 200 · 6ms #550e8400-e29b-41d4-a716-446655440000 | read 1ms · app 3ms · send 0ms
```

| Value | Meaning |
| --- | --- |
| Timestamp | UTC time of the event. |
| Method and route | HTTP method and matched pattern; unmatched requests show their path. |
| Status | Selected HTTP response status. |
| Total time | Request processing, including response validation and serialization. |
| `#id` | UUID shared with `request.requestId` and the response's `X-Request-Id`. |
| `read` | Reading and parsing the request. |
| `app` | Routing, middleware and handler execution. |
| `send` | Writing the response to the socket. |
| Code and message | Cause of a failure, when available. |

Stage times need not sum to the total. `0ms` is below clock resolution; `n/a`
means unavailable or not executed. `SEND FAILED` means the response was not fully
written, even if its selected status was 200. A successful write does not prove
that the client consumed the response.

Queries, headers and bodies are not logged. Matched routes use patterns, while
404 paths can contain user-supplied segments. Sumi generates its own UUID v4 and
ignores incoming request IDs. This is request correlation, not distributed tracing.

## Customize output

```neri
let options = new sumiweb::Options()
options.minimumLevel = "info"
options.log = fn(event)
  sumiweb::logConsole(event)
end
```

`logConsole` uses readable terminal output and structured text when redirected.
`format(event)` returns plain key/value text for a custom sink. `formatReadable`
accepts an event and a color flag. No sink is configured by default in the library;
generated apps enable one.

`LogEvent` exposes `level`, `event`, `timestamp`, `requestId`, `status`, `method`,
`route`, `path`, `durationMs`, `readMs`, `appMs`, `writeMs`, `code` and `message`.
Events include `http.request.started`, `http.request.completed`,
`http.response.write_failed` and `http.connection.failed`. Terminal summaries omit
repetitive start events. Callbacks run synchronously; keep them short.

See [HTTP error codes](HTTP.md#error-codes) for corrective actions.
