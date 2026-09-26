#!/usr/bin/env bash
set -euo pipefail
SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ ! -f "$SUMI_ROOT/build/latest-package" ]]; then
  printf 'SUMI_PACKAGE_MISSING: Build or obtain a binary package first. Checkout: bash "%s/scripts/build-package.sh"\n' "$SUMI_ROOT" >&2
  exit 1
fi
IFS= read -r SUMI_PACKAGE < "$SUMI_ROOT/build/latest-package"
if [[ $# == 0 ]]; then
  set -- --prefix "$HOME/.sumi"
fi
exec "$SUMI_PACKAGE/install.sh" "$@"
