#!/usr/bin/env bash
# Process lifecycle helpers for loopback integration fixtures.
set -euo pipefail
if ! command -v timeout >/dev/null 2>&1 && command -v gtimeout >/dev/null 2>&1; then
  timeout() { gtimeout "$@"; }
fi
SUMI_TEST_PID=""
SUMI_TEST_WORK="$(mktemp -d)"
SUMI_TEST_PORT="$((20000 + BASHPID % 30000))"
stop_server() {
  if [[ -n "$SUMI_TEST_PID" ]]; then
    local deadline=$((SECONDS + 5))
    kill -INT -- "-$SUMI_TEST_PID" 2>/dev/null || true
    while kill -0 -- "-$SUMI_TEST_PID" 2>/dev/null; do
      if (( SECONDS >= deadline )); then
        kill -KILL -- "-$SUMI_TEST_PID" 2>/dev/null || true
        wait "$SUMI_TEST_PID" 2>/dev/null || true
        SUMI_TEST_PID=""
        fail 'server process group did not stop after SIGINT'
      fi
      sleep 0.02
    done
    wait "$SUMI_TEST_PID" 2>/dev/null || true
    SUMI_TEST_PID=""
  fi
}
cleanup() { stop_server; rm -rf -- "$SUMI_TEST_WORK"; }
trap cleanup EXIT
fail() { printf 'Integration failure: %s\n' "$*" >&2; exit 1; }
start_server() {
  start_server_with_budget 10 "$@"
}
# CLI server commands compile before listening; budget that work separately
# from the default readiness deadline for already-built server fixtures.
start_compiling_server() {
  start_server_with_budget 120 "$@"
}
start_server_with_budget() {
  local readiness_seconds="$1"
  local ready="$2"
  shift 2
  : > "$SUMI_TEST_WORK/server.log"
  # Bash job control creates a separate process group on both macOS and Linux.
  # Keep SIGINT enabled in the child, as for a foreground terminal command.
  set -m
  "$@" > "$SUMI_TEST_WORK/server.log" 2>&1 &
  SUMI_TEST_PID=$!
  set +m
  local deadline=$((SECONDS + readiness_seconds))
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
