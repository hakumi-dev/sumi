# Sumi implementation backlog

Review-ready cards for the static-web milestone. IDs below are local planning
IDs, not published issue numbers. Every card is proposed unless stated otherwise.
The product reference is in `docs/`; this file tracks pending work.

## Verified baseline

- Typed in-memory GET routing, parameters, precedence, configuration validation,
  captured dependencies, and synchronous middleware are implemented.
- The HTTP adapter serves explicitly registered UTF-8 HTML, CSS, and JavaScript.
- Structured events include a listener-local request ID, status, duration, route,
  and diagnostic code. Startup errors have separate code and message fields.
- The example has separate application, public assets, and startup files.
- Core and real HTTP contracts pass in Debug and Release through `scripts/test.sh`.
- Existing issue #1 remains open and describes the former `main.hk` sketch.
  Its implementation is now represented by the core and in-memory example;
  reconcile its acceptance and links before closing it on the board.

Current gaps include dependence on low-level HTTP helpers, grouped parser/I/O
errors, IDs that repeat after restart, manual restart for asset changes, text-only
bodies, no successful HEAD handling, no graceful stop, and no cache validators.

## Delivery sequence

Priority is P0 foundation, P1 usable development, P2 complete static delivery.
A Neri dependency is a gate to verify or deliver in Neri, not permission to modify
its compiler from a Sumi card. Do not mark a dependent card complete while its
language/runtime contract remains unavailable.

| ID | Priority | Title | Depends on |
| --- | --- | --- | --- |
| SUMI-01 | P0 | Define the supported Neri transport contract | Baseline |
| SUMI-02 | P0 | Preserve precise error causes across boundaries | 01 |
| SUMI-03 | P0 | Make request logs configurable and correlatable | 02 |
| SUMI-04 | P0 | Stop the server and release resources cleanly | 01, 02 |
| SUMI-05 | P1 | Reload the application during development | 03, 04 |
| SUMI-06 | P1 | Create applications with an optional directory convention | 01 |
| SUMI-07 | P1 | Support headers and correct HEAD responses | 01, 02 |
| SUMI-08 | P1 | Return useful, customizable error pages | 02, 03, 07 |
| SUMI-09 | P2 | Serve binary assets without text conversion | 01, 07 |
| SUMI-10 | P2 | Mount static directories with explicit boundaries | 05, 09 |
| SUMI-11 | P2 | Revalidate cached assets | 07, 10 |
| SUMI-12 | P2 | Build and verify a standalone website distribution | 04, 06, 08, 10, 11 |
| SUMI-13 | P2 | Operate a packaged website as a managed service | 12 |

Start with 01–04. Card 06 can proceed independently after 01. Deliver 05 next
for the immediate edit/restart pain. This sequence adds no database or ORM.

## SUMI-01 — Define the supported Neri transport contract

**Problem:** The adapter calls low-level HTTP helpers; a shared `0.2.0-dev`
version string alone cannot establish compatibility.

**Scope:** Specify the smallest supported socket, parser, byte-body, clock, and
shutdown contracts. Record an exact tested toolchain identity and expose an
explicit compatibility check. Identify missing contracts as Neri work.

**Acceptance:** A fresh supported installation runs the example and HTTP suite;
an incompatible one fails before serving with the missing capability and remedy.
Sumi uses a declared transport boundary instead of depending silently on helper
implementation details. Issue #1's acceptance is mapped to current files.

**Focused verification:** Supported-toolchain smoke test and one incompatible
capability fixture; no compiler test duplication.

**Neri dependency:** [neri#27](https://github.com/hakumi-dev/neri/issues/27), [neri#31](https://github.com/hakumi-dev/neri/issues/31), [neri#35](https://github.com/hakumi-dev/neri/issues/35). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-02 — Preserve precise error causes across boundaries

**Problem:** Some 400s share one message; read/write failures combine timeouts
and socket errors; continuation misuse combines repeated and expired calls.

**Scope:** Carry code, operation, cause, safe context, and corrective guidance.
Keep diagnostic data separate from public responses. Preserve a diagnostic when
middleware replaces a response, without emitting duplicate reports.

**Acceptance:** Timeout, peer closure, malformed input, bind failure, invalid
configuration, repeated `next`, and expired `next` are distinguishable whenever
the underlying API provides that evidence. Unknown causes remain explicitly
unknown. Codes are stable; a route/registration error identifies the conflicting
registration. No diagnostic depends on parsing human-readable messages.

**Focused verification:** Table of distinct failure categories; one middleware
replacement regression; assert internal details never appear in public bodies.

**Neri dependency:** [neri#25](https://github.com/hakumi-dev/neri/issues/25), [neri#29](https://github.com/hakumi-dev/neri/issues/29), [neri#31](https://github.com/hakumi-dev/neri/issues/31). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-03 — Make request logs configurable and correlatable

**Problem:** IDs repeat after restart, there is one formatter, and early exits
lack consistent timing. Application logs have no shared request-scoped API.

**Scope:** Typed log sink, level filtering, readable console and JSON-line
formatters, server-instance/request correlation, timestamps, duration, and an
explicit request context for application logs.

**Acceptance:** Two server instances produce distinguishable request identities.
A request's framework and application events share context. Every supported exit
has one terminal event; failed writes do not claim delivered responses. Logging
can be disabled or redirected. Queries, headers, and bodies stay excluded by
default. Sink failures have an explicit bounded policy without recursive logging.

**Focused verification:** Parse emitted JSON; correlate events across two starts;
exercise an early exit, disabled level, Unicode/control input, and failing sink.

**Neri dependency:** [neri#25](https://github.com/hakumi-dev/neri/issues/25), [neri#33](https://github.com/hakumi-dev/neri/issues/33), [neri#34](https://github.com/hakumi-dev/neri/issues/34). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-04 — Stop the server and release resources cleanly

**Problem:** Serving has no normal success return or graceful-stop operation.

**Scope:** Explicit stop handle, interruptible accept, bounded drain, socket
ownership, and distinct normal-stop versus fatal-listener outcomes.

**Acceptance:** A programmatic stop and Ctrl+C stop accepting new requests,
finish or terminate the current request according to a documented deadline,
release the port, and report the outcome. An occupied port still fails precisely.
Fatal listener errors remain errors. A fresh instance can bind immediately.

**Focused verification:** Stop while idle and during a request; verify exit
outcome and port reuse. Avoid tests that depend on arbitrary sleeps.

**Neri dependency:** [neri#29](https://github.com/hakumi-dev/neri/issues/29), [neri#32](https://github.com/hakumi-dev/neri/issues/32). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-05 — Reload the application during development

**Problem:** Editing HTML or CSS requires manually stopping and restarting Sumi.

**Scope:** Explicit development runner with configurable source/asset roots,
debounced changes, child-process ownership, rebuild/restart, and visible compiler
and startup diagnostics. No browser automation or live DOM replacement required.

**Acceptance:** Editing an asset updates the next response; editing Neri source
rebuilds once per change batch. A failed build shows its source diagnostic and
clearly states whether the last successful instance is still serving. A later
valid edit recovers automatically. Stop leaves no child process or occupied port.
Distribution mode never watches or reloads files.

**Focused verification:** One edit/build-failure/recovery/stop lifecycle scenario.

**Neri dependency:** [neri#35](https://github.com/hakumi-dev/neri/issues/35). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-06 — Create applications with an optional directory convention

**Problem:** Source lists and asset roots must currently be assembled manually.

**Scope:** A project creation command or generator with `app/`, `public/`,
`tests/`, and `main.hk`; add `config/` only when useful. Explicit source and asset
configuration remains authoritative. Provide run, check, and build entry points.

**Acceptance:** A generated app builds outside the framework checkout. Renaming
`app/` and `public/` and updating configuration preserves behavior. Paths resolve
consistently from another working directory. Generation never silently overwrites
existing files. No automatic service scanning or persistence folders are added.

**Focused verification:** Generate, relocate folders, run/build, and reject one
conflicting destination using a disposable project.

**Neri dependency:** [neri#27](https://github.com/hakumi-dev/neri/issues/27), [neri#35](https://github.com/hakumi-dev/neri/issues/35). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-07 — Support headers and correct HEAD responses

**Problem:** Headers are fixed by the serializer, and HEAD always receives 405.

**Scope:** Validated request/response header access, transport-owned framing,
GET-equivalent HEAD metadata with no body, and accurate `Allow` handling.
Preserve bodyless status semantics and existing protocol limits.

**Acceptance:** HEAD on a registered resource returns the GET status and relevant
representation headers without body bytes. Unknown resources retain 404.
Applications cannot inject headers or contradict transport framing. Repeated
headers follow explicit per-field rules. Unsupported methods remain 405.

**Focused verification:** GET/HEAD pair, missing resource, malformed header,
framing conflict, and 204/205/304 boundary cases over real HTTP.

**Neri dependency:** [neri#31](https://github.com/hakumi-dev/neri/issues/31). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-08 — Return useful, customizable error pages

**Problem:** The browser sees only generic text for errors; public presentation
and internal diagnostic policies need an explicit application boundary.

**Scope:** Default HTML 404/500 pages, replaceable renderers, visible request
reference, and separate development/distribution policies. Preserve status and
record the original diagnostic when rendering fails.

**Acceptance:** Applications customize presentation without copying the transport
loop. Public pages contain no source paths, secrets, or stack details. Development
mode can display available diagnostics safely with HTML escaping. Renderer failure
falls back once to a minimal response rather than recursively rendering errors.

**Focused verification:** Custom 404, escaped diagnostic, distribution redaction,
and renderer failure with preserved request correlation.

**Neri dependency:** [neri#25](https://github.com/hakumi-dev/neri/issues/25). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-09 — Serve binary assets without text conversion

**Problem:** `file` accepts UTF-8 text only, excluding ordinary images and fonts.

**Scope:** Byte-oriented response bodies and bounded file reads for binary assets;
keep text/HTML helpers ergonomic and MIME selection explicit or deterministic.

**Acceptance:** PNG and font bytes, including NUL and invalid UTF-8 sequences,
reach the client unchanged. Content length counts bytes. Oversized reads fail
before allocating the full file. A static response owns its data for its required
lifetime, and MIME failures have actionable diagnostics.

**Focused verification:** Exact byte equality for one binary fixture, a size-limit
boundary, and an unreadable file. Verify existing text responses still work.

**Neri dependency:** [neri#28](https://github.com/hakumi-dev/neri/issues/28), [neri#29](https://github.com/hakumi-dev/neri/issues/29), [neri#31](https://github.com/hakumi-dev/neri/issues/31). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-10 — Mount static directories with explicit boundaries

**Problem:** Every asset requires a separate registration.

**Scope:** Mount a configured directory under a URL prefix. Define path decoding,
root containment, dotfile and symlink policy, MIME mapping, and route precedence.
Explicit file registrations remain available.

**Acceptance:** Nested assets resolve under their mount only. Traversal, encoded
separators, dotfiles, and symlink escapes cannot expose unrelated files. No
implicit directory listing. Conflicts with routes are deterministic. Development
and distribution modes have explicit freshness behavior and clear missing-file
versus configuration-error outcomes.

**Focused verification:** One nested asset plus a table of traversal/encoding/
symlink cases and one route-conflict regression.

**Neri dependency:** [neri#29](https://github.com/hakumi-dev/neri/issues/29). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-11 — Revalidate cached assets

**Problem:** Every browser request transfers the entire asset.

**Scope:** Representation validators, conditional GET/HEAD, and explicit cache
policy. Use ETag as the initial validator; modification-time support is optional
only if its precision and precedence are specified.

**Acceptance:** A matching validator returns 304 without a body; changed content
returns 200 with a new validator. HEAD remains bodyless. Development avoids stale
assets, and distribution policy is configurable. Cache metadata describes the
exact served bytes, not a different filesystem snapshot.

**Focused verification:** Initial request, unchanged revalidation, changed asset,
and conditional HEAD against one fixture.

**Neri dependency:** [neri#34](https://github.com/hakumi-dev/neri/issues/34). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-12 — Build and verify a standalone website distribution

**Problem:** The example runs from the checkout with external asset paths;
there is no validated application distribution contract.

**Scope:** Build output containing executable and declared assets, explicit
configuration/root resolution, supported toolchain identity, and a static example
that exercises the documented public API. Add the corresponding automated gate.

**Acceptance:** Build from a clean checkout, copy output to another directory,
and start without the source checkout. Pages, binary assets, diagnostics, cache
revalidation, and graceful stop work there. Missing required configuration fails
before listening. Document exact run/build commands and supported local serving
limits. Do not imply Internet deployment, TLS, or concurrency is complete.

**Focused verification:** One relocated-distribution smoke scenario and the
existing Debug/Release suites. Compile runnable documentation examples.

**Neri dependency:** [neri#27](https://github.com/hakumi-dev/neri/issues/27), [neri#35](https://github.com/hakumi-dev/neri/issues/35). Consume the verified contracts from these cards; language/runtime implementation belongs to the Neri board.

## SUMI-13 — Operate a packaged website as a managed service

**Problem:** Producing an executable does not establish repeatable installation,
HTTPS access, service supervision, or rollback on a remote machine.

**Scope:** A versioned release directory, external environment configuration,
a dedicated unprivileged service account, process supervision, an HTTPS reverse
proxy, health verification, log access, and explicit activation/rollback commands.
Keep the application listener local to the machine.

**Acceptance:** A packaged site starts after reboot on a declared compatible
Linux x86-64 host. Public traffic reaches it through HTTPS; its internal port is
not exposed. A failed candidate is not activated. Rollback restores the previous
release and passes an HTTP check. Logs distinguish proxy failures, service
startup failures, and application failures. Demonstrate the procedure on an EC2
test instance before claiming AWS deployment support. No zero-downtime claim
without a tested traffic-switch/drain mechanism.

**Focused verification:** Install, reboot/start, failed candidate, successful
activation, and rollback in one controlled deployment scenario. Verify service
identity, listener binding, TLS access, and logs.

**Neri dependency:** [neri#35](https://github.com/hakumi-dev/neri/issues/35) for declared runtime dependencies; consume the artifact contract from SUMI-12.

## Shared completion contract

Every card delivers the smallest coherent public behavior described by its
acceptance, with focused regression coverage and an English commit. Update the
API and usage documentation for implemented behavior only. Keep comparative
research in the review conversation, not product documentation. Dependencies
must be verified on the installed toolchain before a card is accepted.

The current milestone excludes database access, ORM, authentication, sessions,
form handling, queues, template engines, and concurrency. They require separately
scoped cards after the static-web milestone; no placeholder persistence
abstractions are required to preserve explicit application-service injection.
