#!/usr/bin/env bash
set -euo pipefail
SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec "${NERI:-neri}" run --project "$SUMI_ROOT/neri.json" --unit package-tool --release -- build "$SUMI_ROOT" "$@"
