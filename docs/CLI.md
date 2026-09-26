# Commands

Run inside an app, or add `--project /path/to/app`.

| Command | Alias | Purpose |
| --- | --- | --- |
| `sumi new <directory>` | `sumi n` | Create an app in a new directory. |
| `sumi server` | `sumi s` | Build and run the server. |
| `sumi test` | `sumi t` | Run the declared app tests. |
| `sumi build` | `sumi b` | Build `build/application`. |
| `sumi console` | `sumi c` | Open an application session. |

| Option | Applies to | Purpose |
| --- | --- | --- |
| `--project <directory>` | server, test, build, console | Select the app. |
| `--environment <name>`, `-e` | server, test, build, console | Select `development`, `test` or `production`. |
| `--port <port>` | server | Select a port from 1 to 65535. |
| `--release` | build, test | Enable optimized compilation. |
| `--timings` | server, build, test | Show compiler phase timings when supported by the selected toolchain. |
| `--output <file>` | build | Set an output path relative to the calling directory. |

```sh
sumi s --port 3000
sumi t --release
sumi b --release --output build/site
```

Stop the server with Ctrl-C. Restart after source or asset changes. Builds keep
assets external; run the executable from the project directory with `public/`
available. Environment selection and optimization are independent.
Server, test, and build show one temporary status line on interactive terminals.
It follows compiler analysis and native code generation, including the current
function and number processed. The line clears before application output,
diagnostics, or the built executable path. Redirected output omits routine
progress. Pass `--timings` to show detailed compiler timings.

`sumi test` names the selected test target before compilation and reports the
overall result and elapsed time afterward. The time includes compilation and
test execution. Test program output appears as produced, and a failed test run
keeps its exit status. Projects can define named test cases through Neri's test
suite API for per-case results; the CLI does not infer case counts from output.

## Console

```text
sumi c
sumi> let response = app.handle(new sumi::Request("GET", "/"))
response: sumi.Response
sumi> response.status
=> 200
```

Variables persist until reset or exit. Every opening creates a new session and
initializes `app`, without starting the HTTP server. Blocks continue until `end`.

| Command | Action |
| --- | --- |
| `:help` | List commands and keys. |
| `:cancel` | Discard pending input. |
| `:reset` | Restart the app and clear variables. |
| `:exit` | Close the session. |

Enter evaluates. When suggestions are open, Up/Down selects and Tab/Enter inserts;
Esc closes the list. Function completion adds `()` with the cursor inside.
With no menu, Up/Down browses history. `NO_COLOR=1` disables colors.

Startup uses one temporary status line on interactive terminals. Native code
generation shows the current function and the number processed; optimization
and object emission have separate phases. The line clears before application
output, diagnostics, and the prompt. Redirected output omits routine progress;
`NO_COLOR=1` preserves status updates without color.

Custom apps must expose a zero-argument `consoleApp(): sumi::App` function in the
server unit that constructs and prepares the app. Generated apps include it.
Reopen the console to load changed application sources. Neri inspects final
expression values, including public entity fields, enum payloads and bounded
collection previews. Sumi displays that result without rerunning the expression.
Database contexts and their configuration come from the application; connection
lifetime and query execution belong to the Neri Data provider.

## Project selection

Sumi searches the current directory and its parents. At the nearest project root,
`package.json` takes precedence over `neri.json`. Commands run with the project
root as their working directory.

Ito manages dependencies and entry points for `package.json` apps. Run
`ito install --locked` to restore their lockfile; use `ito update sumi` to update
the framework from its configured origin. `ITO` and `NERI` can select executables.

Generated `neri.json` projects use `sumi.conf` to select units and assets:

```text
public=public
server=web
test=test
```

Their framework copy is not updated automatically. In Ito projects, `sumi.conf`
is ignored. See [environment configuration](CONFIGURATION.md).
