#!/usr/bin/env bash
# Shared preflight checks. Source from verification entry points.
require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'SUMI_PREREQUISITE: Missing %s. %s\n' "$1" "$2" >&2
    return 127
  fi
}

require_test_prerequisites() {
  if (( BASH_VERSINFO[0] < 4 )); then
    printf 'SUMI_PREREQUISITE: Bash 4+ is required. On macOS install Homebrew bash and put it before /bin in PATH.\n' >&2
    return 1
  fi
  require_tool curl 'Install curl and put it in PATH.' || return
  require_tool script 'Install script for pseudo-terminal logging contracts.' || return
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    printf 'SUMI_PREREQUISITE: Missing timeout/gtimeout. Install GNU coreutils (on macOS: brew install coreutils).\n' >&2
    return 127
  fi
  require_tool cc 'Install a C compiler for the native HTTP client boundary tests.' || return
  require_tool "${ITO:-ito}" 'Install native Ito for package-based CLI contracts, or set ITO.' || return
  if ! /usr/bin/env -C / /usr/bin/true; then
    printf 'SUMI_PREREQUISITE: /usr/bin/env must support -C for the Sumi CLI. Use a compatible macOS or Linux installation.\n' >&2
    return 1
  fi
}
