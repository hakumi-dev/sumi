# Sumi CLI

The Sumi CLI creates applications and runs their declared Neri source sets.
Its command implementation is written in Neri. A shell launcher locates the
checkout and compiler. The current development installation supports Linux and
requires Neri, Bash, and GNU `env`, `mkdir`, `cp`, `test`, and `readlink` utilities.

## Installation

From the framework checkout:

```sh
scripts/install-cli.sh
sumi --help
```

The installer creates `~/.local/bin/sumi` as a link to this checkout. Keep the
checkout available and include that directory in `PATH`. It refuses to replace
an unrelated command. `--bin-dir <directory>` selects another command directory.
You can also use `bin/sumi` directly without installing it.

`NERI` selects the compiler executable; otherwise the launcher uses `neri` from
`PATH`. Source compilation requires named project source sets, contextual
callbacks, managed captures, host process/file operations, and the HTTP and clock
standard libraries used by the framework. The CLI forwards compiler diagnostics
and nonzero exit status. A missing compiler produces `SUMI_CLI_COMPILER`.
Use the [compatibility checker](COMPATIBILITY.md) to verify a selected toolchain
before starting an application.

## Commands

| Command | Alias | Behavior |
| --- | --- | --- |
| `sumi new <directory>` | `sumi n` | Creates a project in a new directory. |
| `sumi server` | `sumi s` | Compiles and runs the server source set. |
| `sumi test` | `sumi t` | Compiles and executes the test source set. |
| `sumi build` | `sumi b` | Builds the server executable. |
| `sumi console` | `sumi c` | Reserved; returns an explicit unavailable diagnostic. |

`console` does not start a shell or a request simulator. A persistent typed
application session is not currently available. No objects are loaded or evaluated
when this command returns `SUMI_CONSOLE_UNAVAILABLE`.

```sh
sumi new my-site
cd my-site
sumi t
sumi s --port 3000
sumi b --release
```

`build` writes `build/application` by default. `--output <file>` selects another
path, resolved from the caller's working directory. Assets remain separate;
this command does not produce a complete deployment archive.

`server` starts the local synchronous server in the foreground. Terminal process
group interruption stops it; there is no graceful drain or automatic reload yet.
`test` executes the project's declared test program, rather than discovering test
files by naming convention. `--release` is available for `test` and `build`.

## Project discovery and layout

Commands search the current directory and its parents for `neri.json`.
`--project <directory>` selects a project explicitly, including from outside it.
The compiler receives an absolute manifest path, and application processes run
with the project directory as their working directory.

A new project contains:

```text
app/routes.hk        Application construction and route registration
public/              HTML, CSS, and JavaScript
main.hk              Startup and diagnostic reporting
tests/application.hk Application contracts
vendor/sumi/         Framework source snapshot
neri.json            Explicit Neri source sets
sumi.conf            CLI source-set and public-directory selection
.env.example         Example local settings
```

`new` copies a source snapshot; subsequent changes in the framework checkout do
not update existing applications automatically. No database or persistence layer
is generated. Existing destination directories are rejected without overwriting
their files. If copying fails after creation, the error is reported and the
incomplete directory remains available for inspection.

Folder names are suggestions. Update source paths in `neri.json` when moving
files. The required `sumi.conf` uses these keys:

```text
public=public
server=web
test=test
```

Keys and values are literal, without surrounding whitespace. Empty lines and
lines beginning with `#` are ignored. Unknown keys and empty values are errors.
Repeated keys use the last value. This file configures the CLI; it is not a
replacement for application-specific configuration.

Multi-source project roots containing non-ASCII characters currently encounter a
compiler UTF-8 slicing failure on the tested toolchain. Use an ASCII project path
until that compiler limitation is resolved. Paths containing spaces are supported.

## Environments

`server` defaults to `development`; `test` defaults to `test`; `build` defaults
to `development`. Select `development`, `test`, or `production` with `SUMI_ENV`
or `--environment` / `-e`. An explicit option overrides the process variable.
The environment selection happens before loading files; a value inside a dotenv
file does not select another environment.

```sh
sumi s -e production
SUMI_ENV=test sumi t
```

Values are resolved in this order, from lowest to highest priority:

1. Application defaults and `sumi.conf` public-directory configuration.
2. Project `.env`.
3. Project `.env.<selected-environment>`.
4. Existing process environment variables, including explicitly empty values.
5. Explicit CLI options, such as `--port`.

`SUMI_PUBLIC`, when supplied through the environment, overrides `sumi.conf`.
Relative public paths are resolved against the project directory. The CLI passes
the effective settings to the application without modifying the parent shell.
The Neri compiler is chosen by the launcher, not by a dotenv file.

The generated server also loads environment settings when its executable is run
directly. It defaults to `production` in that case. Files are located relative
to its working directory. Environment selection does not set compiler optimization;
use `--release` to request an optimized build.

Dotenv files are optional. Production can use only process variables supplied
by its service manager. Actual dotenv files are ignored by Git; `.env.example`
is versioned and should contain examples, never real credentials.

## Dotenv syntax and API

```text
PORT=8080
TITLE="A place for ideas"
EMPTY=
# A full-line comment
```

Names use letters, digits, and underscores and cannot start with a digit.
Whitespace around names and values is removed. Matching single or double quotes
preserve the inner value literally. Empty values are supported. Later definitions
win. Values are single-line; shell execution, variable interpolation, escape
expansion, `export`, and inline comments are not implemented. A `#` inside a value
is literal text. NUL values are rejected.

Applications may use `new sumi.Environment(name)`, `load(root)`, and `get(key)`.
`load` returns `ConfigurationError?` and resets previously loaded file values.
`get` returns `String?`, checking the process environment before file values.
Check the load error before consuming settings.

Syntax failures identify the file, line, and variable when known, without its
value. `SUMI_ENV_NAME`, `SUMI_ENV_READ`, and `SUMI_ENV_SYNTAX` distinguish selection,
file access, and parsing failures. An invalid configuration prevents startup.
