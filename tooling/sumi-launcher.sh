#!/usr/bin/env bash
set -euo pipefail
SUMI_LAUNCHER="${BASH_SOURCE[0]}"
while [[ -L "$SUMI_LAUNCHER" ]]; do
  SUMI_LINK_DIR="$(cd -- "$(dirname -- "$SUMI_LAUNCHER")" && pwd -P)"
  SUMI_LAUNCHER="$(readlink "$SUMI_LAUNCHER")"
  [[ "$SUMI_LAUNCHER" = /* ]] || SUMI_LAUNCHER="$SUMI_LINK_DIR/$SUMI_LAUNCHER"
done
export SUMI_HOME="$(cd -- "$(dirname -- "$SUMI_LAUNCHER")/.." && pwd -P)"
shopt -s execfail
exec "$SUMI_HOME/libexec/sumi" "$@" || {
  printf 'SUMI_PACKAGE_CORRUPT: Cannot execute the installed CLI. Reinstall a compatible Sumi package.\n' >&2
  exit 1
}
