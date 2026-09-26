# Installation and project layout

Sumi requires an installed native Neri toolchain. Applications with `package.json`
also require Ito on `PATH`. See [compatibility](COMPATIBILITY.md).

## Installation commands

| Input | Command | Working directory |
| --- | --- | --- |
| Matching Sumi binary package | `./install.sh --prefix "$HOME/.sumi"` | Unpacked package |
| Sumi source checkout | `bash scripts/build-package.sh` | Checkout root |
| Completed local package | `bash scripts/install-cli.sh --prefix "$HOME/.sumi"` | Checkout root |

The installed command is `$HOME/.sumi/bin/sumi`; add its `bin` directory to
`PATH`. Installation consumes a completed package and never builds implicitly.
Updating Neri requires a matching Sumi package. Existing console processes keep
their loaded toolchain until closed.

## Application layout

`sumi new my-site` creates this layout:

| File | Purpose |
| --- | --- |
| `app/routes.hk` | Build the app and register routes. |
| `main.hk` | Start the server and initialize the console app. |
| `public/` | Static assets. |
| `tests/application.hk` | App tests. |

`new` currently generates a `neri.json` project with a framework copy in
`vendor/sumi`. Existing Ito apps use `package.json` and `ito.lock` instead;
Sumi supports both layouts.

## Application commands

Commands below use the project directory as their working directory. `--project`
selects a different directory explicitly.

| Operation | Command | Result |
| --- | --- | --- |
| Serve | `sumi s --port 3000` | Listener at `http://127.0.0.1:3000/` |
| Test | `sumi t` | Named test results and process exit status |
| Console | `sumi c` | Persistent application session |
| Build | `sumi b --release` | Native executable at `build/application` |

The console exposes the application as `app`; `:exit` closes it. Ctrl-C requests
server shutdown. Code and asset changes require a restart.

Direct execution requires the configured assets, such as `public/`, and a
working directory from which those paths resolve:

```sh
PORT=3000 ./build/application
```

[Routing contract](API.md) · [Configuration reference](CONFIGURATION.md)
