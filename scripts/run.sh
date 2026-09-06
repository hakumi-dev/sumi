#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_COMPILER="${NERI:-neri}"
if ! command -v "$SUMI_COMPILER" >/dev/null 2>&1; then
  printf 'Neri compiler not found. Set NERI to its executable path.\n' >&2
  exit 127
fi
export SUMI_PUBLIC="${SUMI_PUBLIC:-$SUMI_ROOT/examples/web/public}"
exec "$SUMI_COMPILER" run --project "$SUMI_ROOT/neri.json" --unit web "$@"
