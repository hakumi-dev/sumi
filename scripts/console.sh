#!/usr/bin/env bash
set -euo pipefail
SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ "${1:-}" == --prepare ]]; then
  printf 'SUMI_CHECKOUT_COMMAND: Console compilation belongs to package construction. Run: bash "%s/scripts/build-package.sh"\n' "$SUMI_ROOT" >&2
  exit 1
fi
IFS= read -r SUMI_PACKAGE < "$SUMI_ROOT/build/latest-package"
if [[ "${1:-}" == --check ]]; then
  exec "$SUMI_PACKAGE/libexec/sumi-package" check "$SUMI_PACKAGE"
fi
exec "$SUMI_PACKAGE/libexec/sumi-package" console "$SUMI_PACKAGE" "$@"
