# Sumi

Sumi is an experimental web framework design for Neri. [main.hk](main.hk) is a
consumer-side API sketch, not an executable example or an installed library.
This repository contains the framework design; it has no runnable library or
automated test suite yet. The [Neri language contract](https://github.com/hakumi-dev/neri/blob/main/docs/LANGUAGE.md)
describes implemented language features.

The sketch covers a static route, a captured application dependency, validated
integer input, and a middleware wrapping dispatch. It uses an in-memory request;
there is no listening socket. Its intended output is:

```text
/hello/Ada -> 200
Hello, Ada!
```

## Proposed API contracts

Function types below use proposed `fn(ArgumentTypes): ReturnType` notation.
These are design signatures, not declarations accepted by the current compiler.

| API | Proposed type and behavior |
| --- | --- |
| `App()` | Creates a mutable route and middleware registry. |
| `app.get(path, handler)` | Takes `String` and `fn(Request): Response`; returns `Void`. Duplicate GET patterns are registration errors. |
| `app.around(middleware)` | Takes `fn(Request, fn(Request): Response): Response`; returns `Void`. First registered middleware is outermost. |
| `app.handle(request)` | Takes `Request`, returns `Response`. Dispatches by method and path; an unmatched request returns 404. Middleware wraps that response too. |
| `Request(method, path)` | Creates an in-memory request from two strings. This sketch uses literal paths without query strings or percent encoding. |
| `request.path` | A `String` path. |
| `request.param(name)` | Takes `String`, returns `String?`. A missing key is explicit, not a cast or exception. |
| `text(body, status = 200)` | Takes `String` and `Int`, returns a plain-text `Response`. |
| `response.status`, `response.body` | Readable `Int` and `String` values. |

A `:name` pattern matches one nonempty path segment. Literal routes take
precedence over parameterized routes. Structurally equivalent parameterized
patterns are registration errors, even if their parameter names differ.
Route parameters belong to the matched handler's request; middleware receives
the incoming request. Middleware may return early or call its continuation once
synchronously. This is a framework contract, not an exactly-once type guarantee.

## Typing and syntax boundary

Already supported by Neri: classes, explicit function signatures, local type
inference, optional strings and integers, null refinement, checked arithmetic,
and `host.parseInt`. The numeric range check keeps multiplication within bounds.

Proposed language additions used by this sketch:

- `fn(parameters) ... end` expressions passed as ordinary call arguments.
- Function values, their type notation, and calls through a function value.
- Contextual callback typing: `get` supplies `Request` and `Response`; `around`
  also supplies the continuation type. Each return must satisfy that contract.
- Escaping closures that retain captured managed values after `application`
  returns. The sketch captures the immutable `greetings` binding; it does not
  establish semantics for capturing reassigned local variables.

`App`, `Request`, `Response`, and `text` are proposed Sumi APIs. `use sumi` only
exposes a namespace in current Neri; it does not fetch or load a package.

The sketch deliberately keeps public application signatures explicit and
infers callback parameters from those contracts. Dependencies are constructor
arguments. Input begins as text and becomes an `Int` only after checked parsing;
this is not schema-based body decoding. It requires no user-defined generics,
reflection, dependency container, or implicit error propagation.

## Review cases

These are acceptance examples for the design, not an automated test suite.

| Request | Expected status | Expected body |
| --- | --- | --- |
| `GET /` | 200 | `Hello, Sumi!` |
| `GET /hello/Ada` | 200 | `Hello, Ada!` |
| `GET /square/12` | 200 | `144` |
| `GET /square/nope` | 400 | `Expected an integer` |
| `GET /square/1001` | 400 | `Expected an integer between -1000 and 1000` |
| `GET /missing` | 404 | Framework-defined plain-text body |

The dependency remains usable after `application` returns. Logging occurs after
dispatch, once per request, including validation failures and unmatched routes.
Callbacks with incompatible parameter or return types must fail compilation.

Delivery scope and ordering are tracked in [issue #1](https://github.com/hakumi-dev/sumi/issues/1).
