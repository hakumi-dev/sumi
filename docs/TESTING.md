# Testing

Run `sumi test` (or `sumi t`) from the application directory. Sumi selects the
test environment, compiles incrementally, and runs the application's test
executable. The command identifies the selected test unit and reports its exit
status and total duration, including compilation.

## Named cases

Use Neri's `test::Suite` to report individual cases:

```neri
use host
use test

def main(): Void
  let suite = new test::Suite("Application")

  suite.add("adds two numbers") do |context|
    test::assertEqual(2 + 2, 4)
  end
  host::exit(suite.run())
end
```

Register cases in a deterministic order. Each callback runs in a separate
process using the same compiled executable; registering another case does not
compile another executable. A failed assertion fails that case and the runner
continues with the remaining cases. Output includes the running case, its
result and elapsed time, followed by passed/failed counts and suite duration.
The command exits unsuccessfully if any case fails.

Each case currently has a 60-second timeout. Output is captured up to 1 MiB per
stream and displayed with the result; truncation is reported explicitly.

`context.directory` is a fresh temporary directory owned by the parent runner.
Put test databases and other temporary files there; the parent removes it even
when a child assertion terminates the process. For SQLite, use a path such as
`context.directory + "/test.sqlite"`. Tests must not use the development database.

The generated application includes named route tests. Existing executables
containing only `main` and assertions still run, but only their unit-level result
is available. Sumi cannot infer case names or counts from ordinary console text.

## Framework contracts

From a Sumi checkout, `bash scripts/test.sh` validates Debug and Release.
Use `bash scripts/test.sh debug` or `bash scripts/test.sh release` to select one
configuration. Set `SUMI_TEST_REUSE_PACKAGE=1` to validate and reuse the binary
package recorded in `build/latest-package` instead of building another package.
Rebuild the package after changing packaged sources.
Container-based verification requires an init process, such as
Docker's `--init`, to reap orphaned children during process-group shutdown tests.
CLI startup contracts allow time for compilation; prepared server fixtures keep
their separate readiness and shutdown deadlines.

## Responsibilities and references

Neri owns case registration, execution, isolation and reporting. Ito resolves the
project and builds the test executable. Sumi selects the test environment and
provides command and compilation feedback.

The reporting follows the named-case and failure-detail conventions documented
by [Rails](https://guides.rubyonrails.org/testing.html#the-rails-test-runner),
[Laravel's verbose test runner](https://laravel.com/framework/docs/12.x/testing#running-tests),
and [.NET's console test logger](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test-vstest#examples).
These are user-interface references, not a claim of compatibility with their
test frameworks or command-line options.

Binary package contracts require `/usr/bin/time` for process measurements
(the `time` package on Debian and Ubuntu). The `package-contracts` unit accepts
`--source-change <package> <existing-contract-work> <checkout>` to rerun only
the source replacement, installation and rollback contract using an existing
completed installation fixture.
