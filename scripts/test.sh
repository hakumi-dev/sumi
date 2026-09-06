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

bash "$SUMI_ROOT/tests/compatibility.sh"

for mode in debug release; do
  flags=()
  if [[ "$mode" == release ]]; then flags+=(--release); fi
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit contracts "${flags[@]}" --output "$SUMI_WORK/contracts-$mode"
  "$SUMI_WORK/contracts-$mode"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit memory "${flags[@]}" --output "$SUMI_WORK/example-$mode"
  "$SUMI_WORK/example-$mode" > "$SUMI_WORK/actual"
  printf '/hello/Ada -> 200\nHello, Ada!\n' > "$SUMI_WORK/expected"
  diff -u "$SUMI_WORK/expected" "$SUMI_WORK/actual"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit web "${flags[@]}" --output "$SUMI_WORK/site-$mode"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit http-contracts "${flags[@]}" --output "$SUMI_WORK/web-$mode"
  bash "$SUMI_ROOT/tests/http_contracts.sh" "$SUMI_WORK/site-$mode" "$SUMI_WORK/web-$mode"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit logging "${flags[@]}" --output "$SUMI_WORK/logging-$mode"
  "$SUMI_WORK/logging-$mode"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit environment "${flags[@]}" --output "$SUMI_WORK/environment-$mode"
  mkdir "$SUMI_WORK/env-$mode"
  SUMI_FIXTURE_EXTERNAL=process "$SUMI_WORK/environment-$mode" "$SUMI_WORK/env-$mode"
  "$SUMI_COMPILER" build --project "$SUMI_ROOT/neri.json" --unit cli "${flags[@]}" --output "$SUMI_WORK/cli-$mode"
  NERI="$SUMI_COMPILER" bash "$SUMI_ROOT/tests/cli_contracts.sh" "$SUMI_WORK/cli-$mode"
  printf 'Sumi %s passed\n' "$mode"
done
