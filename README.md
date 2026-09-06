# Sumi

Sumi is a web framework written in Neri. Applications register typed handlers,
serve pages and static assets, and compose synchronous middleware. Dependencies
are ordinary constructor arguments and captured values.

The routing core works in memory. The HTTP adapter connects it to a loopback
server and records structured request diagnostics.

## Run the website

Install Neri with trailing `do` blocks and the HTTP and clock standard libraries.
From this repository:

```sh
scripts/run.sh
```

Open **http://127.0.0.1:8080/**. The example serves a page, a stylesheet, and a
JavaScript interaction. The terminal shows request events and errors.

```sh
PORT=3000 scripts/run.sh
NERI=/path/to/neri scripts/run.sh
```

The script selects the example's public directory independently of the current
working directory. Set `SUMI_PUBLIC` to serve a different directory containing
the three files registered by the example. Files are read during registration;
restart the process after editing them.

To build and run from the repository root:

```sh
mkdir -p build
neri build examples/web/main.hk examples/web/app/*.hk src/core/*.hk src/http/*.hk --output build/sumi
./build/sumi
```

The executable needs its configured public directory at runtime. It does not
embed the website files.

## An application

```neri
use sumi
use sumiweb
use console
use host

def main(): Void
  let app = new sumi.App()
  app.get("/") do |request|
    return sumi.html("<!doctype html><html lang=\"en\"><title>Hello</title><h1>Hello, Sumi!</h1></html>")
  end

  let options = new sumiweb.Options()
  options.onListening = fn(address)
    console.println("Listening on http://" + address)
  end
  options.log = fn(event)
    console.println(sumiweb.format(event))
  end

  let error = sumiweb.serve(app, "127.0.0.1:8080", options)
  console.println(error.code + ": " + error.message)
  host.exit(1)
end
```

Save this as `app.hk` and compile it alongside `src/core/*.hk src/http/*.hk`.
`serve` prepares the application before opening a socket. Startup and listener
failures return a `ServerError` with separate `code` and `message` fields; a running server serves until terminated.

To register files:

```neri
app.file("/", "public/index.html", "text/html; charset=utf-8")
app.file("/assets/site.css", "public/site.css", "text/css; charset=utf-8")
```

Only registered URLs are exposed. There is no directory browsing or automatic
conversion from a request path to a disk path. Static files are UTF-8 text,
including HTML, CSS, JavaScript, and SVG, up to 1 MiB each. Binary images and
fonts are not supported by the current file API.

## Project structure

Applications choose their directory layout. An optional convention is:

```text
app/           Routes, handlers, and application services
public/        Website assets
config/        Configuration, when needed
tests/         Application contracts
main.hk        Composition and startup
```

The compiler receives source files explicitly, and file registration receives
explicit filesystem paths. Folder names have no special runtime meaning.

This repository separates library code from examples:

```text
src/core/             Requests, responses, routing, middleware, static registration
src/http/             HTTP adapter, response serialization, structured logging
examples/web/app/     Example route registration
examples/web/public/  Example HTML, CSS, and JavaScript
examples/web/main.hk  Example startup
tests/                In-memory and real HTTP contracts
scripts/              Run and verification commands
```

Application services do not need to know about sockets. Handlers receive services
through captured values; Sumi does not define a persistence layer.

## Reference and verification

- [API](docs/API.md): configuration, routing, middleware, and static content.
- [HTTP and diagnostics](docs/HTTP.md): serving, logs, error codes, and limits.
- [Core structure](docs/ARCHITECTURE.md): responsibilities and lifetime.

```sh
scripts/test.sh
```

Requires Neri and Python 3. Compiles and executes the core contracts, the
in-memory example, and real HTTP tests in Debug and Release. HTTP tests cover
asset bytes and content types, route isolation, error responses, startup
failures, and diagnostic correlation.
