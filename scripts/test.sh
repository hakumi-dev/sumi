#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_COMPILER="${NERI:-neri}"
SUMI_MODES=("$@")
if [[ ${#SUMI_MODES[@]} == 0 ]]; then SUMI_MODES=(debug release); fi
for mode in "${SUMI_MODES[@]}"; do
  case "$mode" in
    debug|release) ;;
    *) printf 'Usage: scripts/test.sh [debug|release ...]\n' >&2; exit 2 ;;
  esac
done
source "$SUMI_ROOT/scripts/prerequisites.sh"
require_test_prerequisites
if ! command -v "$SUMI_COMPILER" >/dev/null 2>&1; then
  printf 'Neri compiler not found. Set NERI to its executable path.\n' >&2
  exit 127
fi
SUMI_WORK="$(mktemp -d)"
trap 'rm -rf -- "$SUMI_WORK"' EXIT

bash "$SUMI_ROOT/tests/compatibility.sh"
if [[ "${SUMI_TEST_REUSE_PACKAGE:-0}" != 1 ]]; then
  bash "$SUMI_ROOT/scripts/build-package.sh"
fi
IFS= read -r SUMI_PACKAGE_HOME < "$SUMI_ROOT/build/latest-package"
if [[ "${SUMI_TEST_REUSE_PACKAGE:-0}" == 1 ]]; then
  "$SUMI_PACKAGE_HOME/libexec/sumi-package" check "$SUMI_PACKAGE_HOME"
fi
export SUMI_PACKAGE_HOME
cc -std=c11 -Wall -Wextra -Werror "$SUMI_ROOT/tests/http_methods.c" -o "$SUMI_WORK/http-methods"

for mode in "${SUMI_MODES[@]}"; do
  flags=()
  if [[ "$mode" == release ]]; then flags+=(--release); fi
  mkdir "$SUMI_WORK/$mode"
  "$SUMI_COMPILER" build-batch --project "$SUMI_ROOT/neri.json" --output-dir "$SUMI_WORK/$mode" \
    --unit contracts --unit body-codecs --unit form-contracts --unit memory --unit web \
    --unit http-contracts --unit request-reader-contracts --unit worker-codec-contracts --unit concurrent-contracts --unit lifecycle-contracts --unit logging --unit environment --unit cli "${flags[@]}"
  "$SUMI_WORK/$mode/contracts"
  "$SUMI_WORK/$mode/body-codecs"
  "$SUMI_WORK/$mode/form-contracts"
  "$SUMI_WORK/$mode/memory" > "$SUMI_WORK/actual"
  printf '/hello/Ada -> 200\nHello, Ada!\n' > "$SUMI_WORK/expected"
  diff -u "$SUMI_WORK/expected" "$SUMI_WORK/actual"
  bash "$SUMI_ROOT/tests/http_contracts.sh" "$SUMI_WORK/$mode/web" "$SUMI_WORK/$mode/http-contracts" "$SUMI_WORK/http-methods"
  "$SUMI_WORK/$mode/request-reader-contracts"
  "$SUMI_WORK/$mode/worker-codec-contracts"
  bash "$SUMI_ROOT/tests/concurrent_contracts.sh" "$SUMI_WORK/$mode/concurrent-contracts"
  bash "$SUMI_ROOT/tests/lifecycle_contracts.sh" "$SUMI_WORK/$mode/lifecycle-contracts"
  "$SUMI_WORK/$mode/logging"
  bash "$SUMI_ROOT/tests/logging_terminal.sh" "$SUMI_WORK/$mode/logging"
  mkdir "$SUMI_WORK/$mode/environment-fixture"
  SUMI_FIXTURE_EXTERNAL=process "$SUMI_WORK/$mode/environment" "$SUMI_WORK/$mode/environment-fixture"
  NERI="$SUMI_COMPILER" bash "$SUMI_ROOT/tests/cli_contracts.sh" "$SUMI_WORK/$mode/cli"
  NERI="$SUMI_COMPILER" bash "$SUMI_ROOT/tests/cli_ito_contracts.sh" "$SUMI_WORK/$mode/cli"
  bash "$SUMI_ROOT/tests/cli_startup_feedback.sh" "$SUMI_WORK/$mode/cli"
  printf 'Sumi %s passed\n' "$mode"
done

# Refresh the installed native CLI and cover the launcher used by developers.
bash "$SUMI_ROOT/scripts/install-cli.sh" --prefix "$SUMI_WORK/installed"
bash "$SUMI_ROOT/tests/cli_contracts.sh" "$SUMI_ROOT/bin/sumi"
bash "$SUMI_ROOT/tests/cli_ito_contracts.sh" "$SUMI_ROOT/bin/sumi"
bash "$SUMI_ROOT/tests/cli_startup_feedback.sh" "$SUMI_ROOT/bin/sumi"
"$SUMI_COMPILER" run --project "$SUMI_ROOT/neri.json" --unit package-contracts --release -- "$SUMI_PACKAGE_HOME" "$SUMI_WORK/package-contracts" "$SUMI_ROOT"
printf 'Sumi public launcher contracts passed\n'
