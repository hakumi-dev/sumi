#!/usr/bin/env bash
set -euo pipefail
cli="$1"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SUMI_HOME="${SUMI_PACKAGE_HOME:-$root}"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
unset SUMI_ENV PORT SUMI_PUBLIC
export NERI_CACHE_DIR="$work/cache"
export ITO_HOME="$work/ito"
export TERM=xterm-256color
cat > "$work/cache-capability.hk" <<'NERI'
use console

@cabiImport("neri_rt_v1_cache_supported")
unsafe def cacheSupported(): Int
end

def main(): Void
  unsafe
    console::println(cacheSupported() as String)
  end
end
NERI
cache_supported="$("${NERI:-neri}" run "$work/cache-capability.hk")"
case "$cache_supported" in
  1) repeated_mode=warm; repeated_timing=incremental-hit ;;
  0) repeated_mode=cold; repeated_timing=incremental-miss ;;
  *) printf 'Unexpected runtime cache capability: %s\n' "$cache_supported" >&2; exit 1 ;;
esac
terminal_libs=()
if [[ "$(uname -s)" == Linux ]]; then terminal_libs+=(-lutil); fi
cc -std=c11 -Wall -Wextra -Werror "$root/tests/startup_terminal.c" \
  "${terminal_libs[@]}" -o "$work/terminal"
mkdir -p "$work/manifest/public" "$work/manifest/tests" "$work/package/public" "$work/package/tests"
cat > "$work/manifest/neri.json" <<'JSON'
{"version":2,"defaultUnit":"web","units":{"web":{"kind":"executable","sources":["main.hk"]},"spec":{"kind":"executable","sources":["tests/main.hk"]}}}
JSON
printf 'server=web\ntest=spec\npublic=public\n' > "$work/manifest/sumi.conf"
cat > "$work/package/package.json" <<'JSON'
{"name":"startup-fixture","version":"0.1.0","dependencies":{}}
JSON
for project in manifest package; do
  cat > "$work/$project/main.hk" <<'NERI'
use console
def main(): Void
  console::println("STARTUP_READY")
end
NERI
  cat > "$work/$project/tests/main.hk" <<'NERI'
use console
def main(): Void
  console::println("STARTUP_READY")
end
NERI
  # Finite applications exercise server dispatch without opening a port.
  "$work/terminal" "$cli" "$work/$project" cold > "$work/$project-cold"
  "$work/terminal" "$cli" "$work/$project" "$repeated_mode" > "$work/$project-warm"
  "$cli" s --project "$work/$project" --timings > "$work/timings" 2>&1
  grep -q "neri timing $repeated_timing " "$work/timings"
  printf '%s repeated startup: ' "$project"
  grep "neri timing $repeated_timing " "$work/timings"
  "$cli" s --project "$work/$project" > "$work/redirected" 2>&1
  [[ "$(cat "$work/redirected")" == STARTUP_READY ]]
  # A changed source invalidates the executable receipt. Unchanged library
  # objects remain reusable by the ordinary compiler cache.
  sed 's/STARTUP_READY/STARTUP_READY_CHANGED/' "$work/$project/main.hk" > "$work/new-source"
  mv "$work/new-source" "$work/$project/main.hk"
  "$work/terminal" "$cli" "$work/$project" cold > "$work/$project-changed"
  grep -q STARTUP_READY_CHANGED "$work/$project-changed"
  sed 's/STARTUP_READY_CHANGED/BUILD_READY/' "$work/$project/main.hk" > "$work/new-source"
  mv "$work/new-source" "$work/$project/main.hk"
  "$work/terminal" "$cli" "$work/$project" cold b "$work/$project/application" > "$work/$project-build"
  [[ -x "$work/$project/application" ]]
  "$cli" b --project "$work/$project" --output "$work/$project/application" > "$work/build-redirected" 2>&1
  grep -Fxq "$work/$project/application" "$work/build-redirected" ||
    grep -Fxq "$(realpath "$work/$project/application")" "$work/build-redirected"
  ! grep -q 'Loading application project' "$work/build-redirected"
  "$work/terminal" "$cli" "$work/$project" cold t > "$work/$project-test"
  "$cli" t --project "$work/$project" > "$work/test-redirected" 2>&1
  grep -Fxq STARTUP_READY "$work/test-redirected"
  grep -q '^Test run passed in [0-9][0-9]* ms (includes compilation and execution).$' "$work/test-redirected"
  printf 'use host\ndef main(): Void\n  host::exit(23)\nend\n' > "$work/$project/main.hk"
  status=0
  "$cli" s --project "$work/$project" > "$work/exit" 2>&1 || status=$?
  [[ "$status" == 23 ]]
  printf 'def main(): Void\n  missingStartupFunction()\nend\n' > "$work/$project/main.hk"
  "$work/terminal" "$cli" "$work/$project" error > "$work/$project-error"
  grep -q missingStartupFunction "$work/$project-error"
done
printf 'Sumi shared startup feedback contracts passed\n'
