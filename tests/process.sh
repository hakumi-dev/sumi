#!/usr/bin/env bash
# Process lifecycle helpers for loopback integration fixtures.
set -euo pipefail
SUMI_TEST_PID=""
SUMI_TEST_WORK="$(mktemp -d)"
SUMI_TEST_PORT="$((20000 + BASHPID % 30000))"
stop_server() {
  if [[ -n "$SUMI_TEST_PID" ]]; then
    kill -TERM -- "-$SUMI_TEST_PID" 2>/dev/null || true
    wait "$SUMI_TEST_PID" 2>/dev/null || true
    SUMI_TEST_PID=""
  fi
}
cleanup() { stop_server; rm -rf -- "$SUMI_TEST_WORK"; }
trap cleanup EXIT
fail() { printf 'Integration failure: %s\n' "$*" >&2; exit 1; }
start_server() {
  local ready="$1"
  shift
  : > "$SUMI_TEST_WORK/server.log"
  setsid "$@" > "$SUMI_TEST_WORK/server.log" 2>&1 &
  SUMI_TEST_PID=$!
  local deadline=$((SECONDS + 10))
  until grep -qF "$ready" "$SUMI_TEST_WORK/server.log"; do
    if ! kill -0 "$SUMI_TEST_PID" 2>/dev/null || (( SECONDS >= deadline )); then
      cat "$SUMI_TEST_WORK/server.log" >&2
      fail 'server did not become ready'
    fi
    sleep 0.02
  done
}
request() {
  SUMI_TEST_STATUS="$(curl --silent --show-error --path-as-is --max-time 4 \
    -D "$SUMI_TEST_WORK/headers" -o "$SUMI_TEST_WORK/body" -w '%{http_code}' \
    "http://127.0.0.1:$SUMI_TEST_PORT$1" "${@:2}")"
}
expect_status() { [[ "$SUMI_TEST_STATUS" == "$1" ]] || fail "expected $1, got $SUMI_TEST_STATUS"; }
header() { tr -d '\r' < "$SUMI_TEST_WORK/headers" | sed -n "s/^$1: //p"; }
