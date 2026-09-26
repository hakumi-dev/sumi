#!/usr/bin/env bash
set -euo pipefail
binary="$1"
work="$(mktemp -d)"
trap 'rm -r -- "$work"' EXIT
escape=$'\033'
pty() {
  if [[ "$(uname -s)" == Darwin ]]; then
    script -q "$1" "$binary" > /dev/null
  else
    local command
    printf -v command '%q' "$binary"
    script -q -e -c "$command" "$1" > /dev/null
  fi
  grep -qF 'Sumi logging contracts passed' "$1"
}
TERM=xterm NO_COLOR= pty "$work/colored"
for pair in '32m200' '36m302' '33m404' '31m500'; do
  grep -qF "${escape}[$pair" "$work/colored"
done
TERM=xterm NO_COLOR=1 pty "$work/disabled"
TERM=dumb NO_COLOR= pty "$work/dumb"
TERM=xterm NO_COLOR= "$binary" > "$work/redirected"
grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z\] GET' "$work/disabled"
grep -qE '^timestamp="[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z" level=' "$work/redirected"
for output in disabled dumb redirected; do
  if grep -qF "$escape" "$work/$output"; then
    printf 'Unexpected ANSI escapes in %s\n' "$output" >&2
    exit 1
  fi
done
printf 'Sumi terminal color contracts passed\n'
