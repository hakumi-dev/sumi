#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_COMPILER="${NERI:-neri}"
SUMI_MODE=full

if [[ $# == 1 && "$1" == --compile-only ]]; then
  SUMI_MODE=compile
elif [[ $# != 0 ]]; then
  printf 'Usage: scripts/check-compatibility.sh [--compile-only]\n' >&2
  exit 2
fi

if ! command -v "$SUMI_COMPILER" >/dev/null 2>&1; then
  printf 'SUMI_COMPAT_COMPILER: Neri was not found. Install Neri or set NERI to its executable.\n' >&2
  exit 127
fi

# Resolve the installation once so a launcher symlink update cannot switch it
# halfway through a compatibility run.
export NERI="$(readlink -f -- "$(command -v "$SUMI_COMPILER")")"
printf 'Compiler: %s\n' "$NERI"
sha256sum -- "$NERI"

if ! "$NERI" --version; then
  printf 'SUMI_COMPAT_COMPILER: Cannot read the compiler version. Check the selected Neri installation.\n' >&2
  exit 1
fi

SUMI_WORK="$(mktemp -d)"
trap 'rm -r -- "$SUMI_WORK"' EXIT

if [[ "$SUMI_MODE" == compile ]]; then
  for unit in contracts memory web http-contracts logging environment cli; do
    printf 'Checking unit: %s\n' "$unit"
    if ! "$NERI" build --project "$SUMI_ROOT/neri.json" --unit "$unit" --output "$SUMI_WORK/$unit"; then
      printf 'SUMI_COMPAT_BUILD: Cannot build unit %s. Compiler diagnostics above identify the failed contract; see docs/COMPATIBILITY.md before selecting another toolchain.\n' "$unit" >&2
      exit 1
    fi
  done

  printf 'Sumi compilation contracts passed; runtime and HTTP behavior were not checked.\n'
else
  if ! "$SUMI_ROOT/scripts/test.sh"; then
    printf 'SUMI_COMPAT_CONTRACT: Sumi verification failed. Inspect the failing compiler or contract diagnostic above; check docs/COMPATIBILITY.md and local test prerequisites.\n' >&2
    exit 1
  fi

  printf 'Sumi compilation and runtime contracts passed in Debug and Release.\n'
fi
