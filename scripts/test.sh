#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_COMPILER="${NERI:-neri}"
if ! command -v "$SUMI_COMPILER" >/dev/null 2>&1; then
  printf 'Neri compiler not found. Set NERI to its executable path.\n' >&2
  exit 127
fi
SUMI_WORK="$(mktemp -d)"
trap 'rm -rf -- "$SUMI_WORK"' EXIT

for mode in debug release; do
  flags=()
  if [[ "$mode" == release ]]; then flags+=(--release); fi
  "$SUMI_COMPILER" build "$SUMI_ROOT/tests/contracts.hk" "$SUMI_ROOT/examples/application.hk" "$SUMI_ROOT"/src/core/*.hk "${flags[@]}" --output "$SUMI_WORK/contracts-$mode"
  "$SUMI_WORK/contracts-$mode"
  "$SUMI_COMPILER" build "$SUMI_ROOT/examples/memory.hk" "$SUMI_ROOT/examples/application.hk" "$SUMI_ROOT"/src/core/*.hk "${flags[@]}" --output "$SUMI_WORK/example-$mode"
  "$SUMI_WORK/example-$mode" > "$SUMI_WORK/actual"
  printf '/hello/Ada -> 200\nHello, Ada!\n' > "$SUMI_WORK/expected"
  diff -u "$SUMI_WORK/expected" "$SUMI_WORK/actual"
  "$SUMI_COMPILER" build "$SUMI_ROOT/examples/web/main.hk" "$SUMI_ROOT"/examples/web/app/*.hk "$SUMI_ROOT"/src/core/*.hk "$SUMI_ROOT"/src/http/*.hk "${flags[@]}" --output "$SUMI_WORK/site-$mode"
  "$SUMI_COMPILER" build "$SUMI_ROOT/tests/web.hk" "$SUMI_ROOT"/src/core/*.hk "$SUMI_ROOT"/src/http/*.hk "${flags[@]}" --output "$SUMI_WORK/web-$mode"
  python3 "$SUMI_ROOT/tests/http_contracts.py" "$SUMI_WORK/site-$mode" "$SUMI_WORK/web-$mode"
  printf 'Sumi %s passed\n' "$mode"
done
