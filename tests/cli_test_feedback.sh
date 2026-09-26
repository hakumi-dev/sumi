#!/usr/bin/env bash
set -euo pipefail
cli="$1"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export NERI="$(command -v "${NERI:-neri}")"
export NERI_CACHE_DIR="$work/cache"
unset SUMI_ENV PORT SUMI_PUBLIC

mkdir -p "$work/manifest" "$work/ito"
cat > "$work/manifest/neri.json" <<'JSON'
{"version":2,"defaultUnit":"spec","units":{"spec":{"kind":"executable","sources":["main.hk"]}}}
JSON
printf 'test=spec\n' > "$work/manifest/sumi.conf"
cat > "$work/manifest/main.hk" <<'NERI'
use console
def main(): Void
  console::println("CHILD_OUTPUT")
end
NERI
"$cli" t --project "$work/manifest" > "$work/stdout" 2> "$work/stderr"
grep -Fxq 'Test target: spec (neri.json)' "$work/stdout"
grep -Fxq CHILD_OUTPUT "$work/stdout"
grep -Eq '^Test run passed in [0-9]+ ms \(includes compilation and execution\)\.$' "$work/stdout"
[[ ! -s "$work/stderr" ]]
! grep -q $'\033' "$work/stdout" "$work/stderr"

cat > "$work/manifest/main.hk" <<'NERI'
use console
use host
def main(): Void
  console::println("CHILD_FAILED")
  host::exit(23)
end
NERI
status=0
"$cli" test --project "$work/manifest" > "$work/stdout" 2> "$work/stderr" || status=$?
[[ "$status" == 23 ]]
grep -Fxq CHILD_FAILED "$work/stdout"
grep -Eq '^Test run failed \(exit 23\) in [0-9]+ ms \(includes compilation and execution\)\.$' "$work/stdout"
[[ ! -s "$work/stderr" ]]
! grep -q $'\033' "$work/stdout" "$work/stderr"

cat > "$work/manifest/main.hk" <<'NERI'
def main(): Void
  missingTestFunction()
end
NERI
status=0
"$cli" test --project "$work/manifest" > "$work/stdout" 2> "$work/stderr" || status=$?
[[ "$status" != 0 ]]
grep -Fq missingTestFunction "$work/stdout" "$work/stderr"
grep -Eq "^Test run failed \\(exit $status\\) in [0-9]+ ms \\(includes compilation and execution\\)\\.$" "$work/stdout"
! grep -q '^Test run passed' "$work/stdout"
! grep -q $'\033' "$work/stdout" "$work/stderr"

printf '{"name":"feedback-fixture","version":"0.1.0","dependencies":{}}\n' > "$work/ito/package.json"
cat > "$work/fake-ito" <<'SH'
#!/bin/sh
printf 'CHILD_STDOUT\n'
printf 'CHILD_STDERR\n' >&2
exit 37
SH
chmod +x "$work/fake-ito"
status=0
ITO="$work/fake-ito" "$cli" t --project "$work/ito" > "$work/stdout" 2> "$work/stderr" || status=$?
[[ "$status" == 37 ]]
grep -Fxq 'Test target: test (Ito)' "$work/stdout"
grep -Fxq CHILD_STDOUT "$work/stdout"
grep -Eq '^Test run failed \(exit 37\) in [0-9]+ ms \(includes compilation and execution\)\.$' "$work/stdout"
[[ "$(cat "$work/stderr")" == CHILD_STDERR ]]
! grep -q $'\033' "$work/stdout" "$work/stderr"
printf 'Sumi test feedback contracts passed\n'
