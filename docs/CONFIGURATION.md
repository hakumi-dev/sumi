# Configuration

```text
# .env
PORT=3000
LOG_LEVEL=info
SUMI_PUBLIC=public
```

| Setting | Values / default |
| --- | --- |
| `PORT` | 1–65535; generated apps default to 8080. |
| `LOG_LEVEL` | `debug`, `info`, `warning`, `error`, `off`; default `info`. |
| `SUMI_PUBLIC` | Asset directory; default `public`. |
| `SUMI_ENV` | `development`, `test`, `production`. |
| `NO_COLOR` | Any nonempty value disables terminal colors. |

Relative asset paths resolve from the app directory.

## Environments

```sh
sumi s -e production
SUMI_ENV=test sumi t
```

Server, console and build default to `development`; tests default to `test`.
The generated executable defaults to `production` when run directly.
`--environment` overrides `SUMI_ENV`. Dotenv files cannot select the environment.

Values are loaded in this order, with later sources taking precedence:

1. App defaults and legacy `sumi.conf`.
2. `.env`.
3. `.env.<environment>`.
4. Process environment, including explicitly empty values.
5. Command options such as `--port`.

Environment selection does not enable compiler optimizations; use `--release`.
Keep real `.env` files out of Git and share examples through `.env.example`.

## Dotenv syntax

```text
TITLE="My site"
EMPTY=
# Full-line comment
```

Names contain letters, digits and underscores and cannot start with a digit.
Surrounding whitespace is removed; matching quotes preserve their inner text.
Values are single-line and literal. Shell expansion, interpolation, escapes,
`export` and inline comments are not supported. Repeated keys use the last value.

## Application API

`new sumi::Environment(name)` creates settings for an environment.
`load(root)` reads its dotenv files and returns `ConfigurationError?`.
`get(key)` returns `String?`, checking the process environment first.
Check the load error before using values.

| Error | Action |
| --- | --- |
| `SUMI_ENV_NAME` | Choose a supported environment. |
| `SUMI_ENV_READ` | Check the named file and permissions. |
| `SUMI_ENV_SYNTAX` | Fix the reported file, line and variable. |
