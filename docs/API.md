# API

Public application types use the `sumi` namespace.

## Application

| API | Purpose |
| --- | --- |
| `new App()` | Create an app. |
| `get`, `head`, `post`, `put`, `patch`, `delete`, `options` `(path, handler)` | Register a `fn(Request): Response` handler. |
| `route(method, path, handler)` | Register one of the seven supported methods by name. |
| `file(path, source, contentType)` | Register a bounded binary or text file as a GET response. |
| `around(handler)` | Register synchronous middleware. |
| `prepare(): ConfigurationError?` | Validate configuration and close registration. |
| `handle(request: Request): Response` | Dispatch a request in memory. |

Register everything before preparation. `sumiweb::serve` prepares automatically;
call `prepare()` yourself before in-memory dispatch. Check its `code` and `message`
on failure. An invalid or unprepared app returns 500. The first configuration
error is retained; create a new app to replace an invalid configuration.

## Routes

```neri
app.get("/users/:id") do |request|
  let id = request.param("id")
  if id == null
    return sumi::text("Missing user ID", 400)
  end
  return sumi::text(id)
end

app.post("/echo") do |request|
  return sumi::binary(request.body, "application/octet-stream", 201)
end
```

- Paths start with `/`; no repeated or trailing slashes except the root `/`.
- `:name` matches one segment. Names use `[A-Za-z_][A-Za-z0-9_]*` and cannot repeat
  within a pattern.
- Matching is case-sensitive. Paths and parameters are not percent-decoded.
- Literals win over parameters at the first differing segment, regardless of
  registration order: `/users/new` wins over `/users/:id`.
- Equivalent patterns for the same method are rejected, including
  `/users/:id` and `/users/:name`. Different methods may share a path.

Unknown or invalid paths return 404. A known path without the requested method
returns 405 with `allowedMethods`. HEAD uses an explicit handler or falls back to
GET. OPTIONS defaults to 204 with the available methods unless explicitly handled.
These defaults do not enable CORS.

## Request

`new Request(method: String, path: String)` creates a request for in-memory use.

| Member | Value |
| --- | --- |
| `method`, `path` | Request method and path without the query. |
| `query` | Encoded query, without `?`. |
| `body: Byte[]` | Authoritative raw body bytes; empty when absent. |
| `headers: http::Headers` | Ordered fields with case-insensitive lookup; repeated values remain separate. |
| `text(): result::Result<String, BodyFailure>` | Decode UTF-8 explicitly; invalid bytes return `invalid_utf8`. |
| `json(options)` / `form(options)` | Decode JSON or URL-encoded forms explicitly, with typed failures. |
| `contentType` | Request Content-Type; empty when absent. |
| `requestId` | UUID supplied by the HTTP adapter. |
| `param(name): String?` | Matched path parameter, or `null`. |

Raw transport never rejects a body merely because it is not UTF-8. Decode only
when the handler requires text, JSON or a form, and choose an application response
for a `BodyFailure` (`code`, `message`, `offset`). Multipart parsing is not supplied.
See [Request and response bodies](BODIES.md) for codec limits and error handling.
`handle` snapshots incoming body bytes and headers once; handler mutations do not
change the original request. Matched parameters belong only to the selected handler.

## Response

| API | Result |
| --- | --- |
| `text(body, status = 200)` | Plain-text response. |
| `html(body, status = 200)` | HTML response. |
| `json(value: json::Value, status = 200, options = null)` | JSON response wrapped in `result::Result<Response, BodyFailure>`. |
| `binary(body: Byte[], contentType = "application/octet-stream", status = 200)` | Binary response. |
| `new Response(status, body: Byte[])` | Response with plain-text content type by default. |
| `response.text(): result::Result<String, BodyFailure>` | Explicit UTF-8 decoding of response bytes. |
| `failure(code, message, status = 500)` | Generic error body with internal diagnostics. |

`status`, `body`, `headers`, `contentType`, `allowedMethods`, `route`, `diagnosticCode` and
`diagnosticMessage` are response fields. Diagnostic fields are logged, not sent
to the client. Use `text` or `html` for messages the client should receive.
Middleware replacing a response should preserve relevant route/diagnostic fields.
See [HTTP](HTTP.md) for status, size and header limits.

`text` and `html` encode strings as UTF-8. `binary` and the constructor retain
the supplied byte array; callers control later mutation. `headers.add(name, value)`
returns `false` for invalid or over-budget fields. Repeated fields such as
`Set-Cookie` retain insertion order. The adapter owns framing and standard response
fields; attempting to override a reserved field produces a generic 500.

## Static files

```neri
app.file("/", "public/index.html", "text/html; charset=utf-8")
app.file("/assets/site.css", "public/site.css", "text/css; charset=utf-8")
app.file("/assets/logo.png", "public/logo.png", "image/png")
```

Files are read at registration, up to 1 MiB each. Restart after editing them.
Source paths resolve from the process working directory. Register every URL
explicitly; there is no directory serving. Images, fonts and other binary files
are served without decoding. File metadata is checked against the limit before
body allocation. Each response receives its own byte copy, so middleware cannot
alter the stored file for later requests.

Missing, unreadable, oversized or unsuccessfully closed files fail preparation. Content
types accept a media type and optionally the exact suffix `; charset=utf-8`.

## Middleware

```neri
app.around() do |request, next|
  if request.method == "POST" && request.body.Length == 0
    return sumi::text("Body required", 400)
  end
  return next(request)
end
```

Middleware runs in registration order before the handler, then in reverse order
afterward. It can return early. Call `next(request)` at most once, synchronously,
before returning; do not store it. Repeated or expired calls return 500 without
running downstream code again. Earlier effects are not undone.

Execution is synchronous. Handlers receive dependencies through captured values
or ordinary constructor arguments.
