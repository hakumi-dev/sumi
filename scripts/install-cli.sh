#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_BIN="${HOME}/.local/bin"

if [[ $# != 0 ]]; then
  if [[ $# != 2 || "$1" != --bin-dir ]]; then
    printf 'Usage: scripts/install-cli.sh [--bin-dir <directory>]\n' >&2
    exit 2
  fi
  SUMI_BIN="$2"
fi

mkdir -p -- "$SUMI_BIN"
SUMI_TARGET="$SUMI_BIN/sumi"

if [[ -e "$SUMI_TARGET" || -L "$SUMI_TARGET" ]]; then
  if [[ -L "$SUMI_TARGET" && "$(readlink -- "$SUMI_TARGET")" == "$SUMI_ROOT/bin/sumi" ]]; then
    printf 'Sumi is already linked at %s\n' "$SUMI_TARGET"
    exit 0
  fi
  printf 'Refusing to replace an existing command: %s\n' "$SUMI_TARGET" >&2
  exit 1
fi

ln -s -- "$SUMI_ROOT/bin/sumi" "$SUMI_TARGET"
printf 'Installed %s\nKeep this checkout available and include %s in PATH.\n' "$SUMI_TARGET" "$SUMI_BIN"
