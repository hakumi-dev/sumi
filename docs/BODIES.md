# Request and response bodies

Sumi preserves HTTP bodies as bytes. Decode them in a handler using
`request.text()`, `request.json()` or `request.form()`. Each returns
`result::Result<Value, sumi::BodyFailure>` with the appropriate value type.
The handler chooses the response for a failure; decoding does not implicitly
send a response or modify the request.

```neri
app.post("/echo-json") do |request|
  match request.json()
    case result::Result.Error(error)
      return sumi::text("Invalid JSON", 400)
    case result::Result.Ok(value)
      match sumi::json(value)
        case result::Result.Ok(response)
          return response
        case result::Result.Error(error)
          return sumi::failure("APP_JSON_RESPONSE", error.message)
      end
  end
end
```

Import `sumi`, `json` and `result` in code using this example. JSON tree values
and encoding belong to Neri's `json` module; Sumi validates HTTP media types and
applies its transport limit. JSON numbers retain their exact source spelling,
so parsing does not silently round large integers through a floating-point type.
Objects reject duplicate decoded keys. Use `get(name)`, `at(index)`, `kind()`
and `text()` to inspect a value, checking optional results before using them.

## Media types

JSON accepts `application/json` and `application/*+json`. Forms accept
`application/x-www-form-urlencoded`. Type names, parameter names and the
`UTF-8` charset name are case-insensitive. An absent charset means UTF-8;
other charsets and repeated charset parameters fail. Quoted parameter values
and valid unknown parameters are accepted. A missing or unsupported media type
returns `unsupported_media_type`; malformed parameters return
`invalid_content_type`; an unsupported charset returns `unsupported_charset`.

Parameter parsing follows [RFC 9110 §5.6.6](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.6.6).
No whitespace is allowed around a parameter's equals sign. Empty parameter
segments are accepted. The media type input is bounded to 8192 bytes.

`request.text()` only validates UTF-8 bytes, without interpreting Content-Type.
`sumi::parseForm(bytes, options)` decodes a form independently of HTTP headers.
The `decodeJson(request, options)` and `decodeForm(request, options)` functions
are equivalent to the corresponding request methods.

## JSON limits

`request.json(options: json::Options? = null)` applies a 1 MiB body limit and
the supplied Neri JSON limits. Defaults are 1 MiB input/output, depth 64 and
100,000 value nodes. The JSON grammar follows
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259).

`sumi::json(value, status = 200, options = null)` returns
`Result<Response, BodyFailure>`. Its Content-Type is `application/json`.
It validates the supplied options, copies them and caps encoded output at
1 MiB. Caller options remain unchanged. An output failure never exposes a
partial response. Codes include `invalid_options`, `input_limit`, `body_limit`,
`output_limit`, `depth_limit`, `node_limit`, `invalid_utf8`, `invalid_json`
and `duplicate_key`.

## URL-encoded forms

```neri
app.post("/greet") do |request|
  match request.form()
    case result::Result.Error(error)
      return sumi::text("Invalid form", 400)
    case result::Result.Ok(form)
      let name = form.get("name")
      if name == null
        return sumi::text("Name required", 422)
      end
      return sumi::text("Hello, " + name)
  end
end
```

Forms preserve insertion order and repeated names. `get(name)` returns the
first value or `null`; `values(name)` returns an independent array of all
matching values. `count()` counts fields, including repeats. `each(visit)`
visits `(name, value)` pairs in order. Lookups scan the fields linearly.

Parsing splits nonempty `&` segments at the first `=`, converts `+` to space,
percent-decodes and validates UTF-8. A field without `=` has an empty value.
Empty names are allowed. Brackets remain literal characters in a name;
there is no implicit nested-object conversion. These splitting rules follow
the [WHATWG form parser](https://url.spec.whatwg.org/#urlencoded-parsing).
Sumi deliberately rejects malformed percent escapes and invalid UTF-8 instead
of replacing invalid input as a browser parser may do.

| `FormOptions` member | Default | Accepted range |
| --- | ---: | ---: |
| `maxBytes` | 1,048,576 | 0–1,048,576 |
| `maxFields` | 1,024 | 0–65,536 |
| `maxKeyBytes` | 4,096 | 0–1,048,576 |
| `maxFieldBytes` | 1,048,576 | 0–1,048,576 |

`maxBytes` counts encoded input. Key and field limits count decoded UTF-8 bytes;
`maxFieldBytes` applies to each value, separately from its key. Empty `&` segments
do not count as fields. Limits are checked before allocating each decoded
component. Form errors use `invalid_options`, `body_limit`, `field_limit`,
`key_limit`, `value_limit`, `invalid_percent` or `invalid_utf8`.

`BodyFailure.offset` is zero-based. Form errors locate the offending byte in
the original encoded body; truncated UTF-8 points to its leading byte. JSON
syntax errors locate input bytes. Content-Type errors locate header bytes.
Errors without a source location, including invalid options and output limits,
use zero. Failure messages omit request contents.

## Binary data

Return `sumi::binary(bytes, contentType, status)` for arbitrary bytes or register
an asset with `app.file(path, source, contentType)`. Neither decodes text.
`binary` retains its input array; registered files receive a fresh copy for
each response. The HTTP adapter counts bytes for Content-Length and suppresses
body transmission for HEAD while retaining representation length.

See [HTTP](HTTP.md) for framing, header budgets and status rules, and
[API](API.md) for request snapshots and static-file ownership. Multipart,
streaming and automatic model binding are outside these codecs.
