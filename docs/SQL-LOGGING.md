# Database command logging

`sumiweb::databaseLog` projects provider diagnostics onto the same `Options.log`
sink as HTTP events. Enable `Options.databaseQueries` and select a minimum level
of `debug` to include ordinary operations. Slow operations (at least
`Options.slowQueryMs`, default 200 ms) use `warning`; provider failures use
`error`. Intentional stream stops/cancellations carry their category at warning
level without being labeled provider failures. `off` suppresses all events.
Unknown durations remain `n/a`.

Events carry SQL, operation, duration, parameter/statement counts, affected and
returned counts, failure category and the supplied request ID. Terminal output
uses a readable SQL summary; redirected output retains structured fields.
Controls are escaped to keep one physical log line per operation.

Sumi does not depend on a particular database package. Connect Neri Data through
`DiagnosedProvider` and forward its readonly event to `databaseLog`. The SQLite
demo does this per connection/request and passes the same logging options to
the HTTP server and its database observer. The persistent console uses the same
application setup.

The demo enables SQL logging in development, including `sumi s`. Configuration:

| Setting | Behavior |
| --- | --- |
| `LOG_SQL=true` / `false` | Explicitly enable/disable database events |
| `LOG_LEVEL=debug` | Include ordinary SQL; higher levels filter it |
| `LOG_SQL_SLOW_MS=200` | Warning threshold per provider operation |

Production/test disable SQL by default. Explicit SQL enablement also selects
debug unless `LOG_LEVEL` overrides it. Invalid settings fail during startup.
Normal CRUD uses placeholders; bound values and raw provider error messages are
never attached to these events. SQL supplied with inline literals remains SQL
text, so parameterize application queries.

Tracked writes emit one batch event with submitted SQL and total provider time.
Counts describe submitted statements; a failure may occur before all run.
These events do not trace migration internals, individual native SQLite calls,
or source locations. Each request ID comes from the existing HTTP request;
console operations without one leave it empty.

## Verification

The Sumi contracts cover filtering, slow/error categories, unknown durations and
control escaping. The SQLite demo tests check all four statement types, request
correlation and omission of bound form values using a temporary database.

## Verified design references

- [Laravel query listeners](https://laravel.com/docs/12.x/database#listening-for-query-events)
  expose SQL and elapsed time through a callback. Sumi follows that observation
  model; its slow threshold applies per operation, not Laravel's cumulative
  per-request threshold.
- [Rails query logs](https://guides.rubyonrails.org/debugging_rails_applications.html#verbose-query-logs)
  pair SQL with duration and development diagnostics. Sumi provides request IDs;
  it does not synthesize Rails-style source stack traces.
- [EF Core simple logging](https://learn.microsoft.com/en-us/ef/core/logging-events-diagnostics/simple-logging)
  provides filtered logging and explicit sensitive-data opt-in. Sumi keeps bound
  values out of its event model and uses its existing level/sink abstraction.
