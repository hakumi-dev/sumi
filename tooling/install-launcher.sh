#!/usr/bin/env bash
set -euo pipefail
SUMI_PACKAGE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
shopt -s execfail
exec "$SUMI_PACKAGE/libexec/sumi-package" install "$SUMI_PACKAGE" "$@" || {
  printf 'SUMI_PACKAGE_CORRUPT: Cannot execute the installer. Obtain a compatible Sumi binary package.\n' >&2
  exit 1
}
