# Sumi

A web framework for Neri: typed routes, middleware, bounded concurrent HTTP,
JSON, forms, binary responses and static files.

```neri
app.get("/hello/:name") do |request|
  let name = request.param("name")
  if name == null
    return sumi::text("Hello, world")
  end
  return sumi::text("Hello, " + name)
end
```

## Commands

Commands require a matching installed Neri and Sumi toolchain.

| Operation | Command |
| --- | --- |
| Create a project | `sumi new my-site` |
| Serve a project | `sumi s --project my-site --port 3000` |
| Run its tests | `sumi t --project my-site` |
| Build its executable | `sumi b --project my-site --release` |

[Installation and project layout](docs/GETTING-STARTED.md) · [Documentation](docs/README.md)

## Documentation

- [Commands and console](docs/CLI.md)
- [Configuration](docs/CONFIGURATION.md)
- [Routes, requests and middleware](docs/API.md)
- [JSON, forms and binary data](docs/BODIES.md)
- [Logs](docs/LOGGING.md)
- [HTTP limits and errors](docs/HTTP.md)

Generated applications use bounded workers with private heaps and graceful
shutdown. Restart after changing code or assets. See
[server contracts](docs/HTTP.md) and [compatibility](docs/COMPATIBILITY.md).

[Contributing](CONTRIBUTING.md)
