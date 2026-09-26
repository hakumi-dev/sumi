#!/usr/bin/env bash
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
fixture="$1"
export PORT="$SUMI_TEST_PORT" MODE=idle

wait_for() {
  local marker="$1" deadline=$((SECONDS + 5))
  until grep -qF "$marker" "$SUMI_TEST_WORK/server.log"; do
    (( SECONDS < deadline )) || fail "missing $marker"
    sleep 0.01
  done
}

expect_exit() {
  local expected="$1" deadline=$((SECONDS + 6)) status=0
  while kill -0 "$SUMI_TEST_PID" 2>/dev/null; do
    (( SECONDS < deadline )) || fail 'lifecycle fixture did not exit'
    sleep 0.01
  done
  wait "$SUMI_TEST_PID" || status=$?
  SUMI_TEST_PID=""
  [[ "$status" == "$expected" ]] || fail "expected exit $expected, got $status"
}

expect_cleanup() {
  [[ "$(grep -c '^SHUTDOWN_START$' "$SUMI_TEST_WORK/server.log")" == 1 ]] || fail 'shutdown callback count'
  [[ "$(grep -c '^SHUTDOWN_END$' "$SUMI_TEST_WORK/server.log")" == 1 ]] || fail 'shutdown callback incomplete'
  [[ "$(tail -n 1 "$SUMI_TEST_WORK/server.log")" == EXIT_NORMAL ]] || fail 'normal shutdown was reported as failure'
}

for signal in INT TERM; do
  start_server READY "$fixture"
  kill -"$signal" -- "-$SUMI_TEST_PID"
  wait_for SHUTDOWN_START
  # A hook executes only after the listening socket has closed.
  if curl --silent --max-time 1 "http://127.0.0.1:$PORT/probe" >/dev/null 2>&1; then
    fail 'listener accepted a request during cleanup'
  fi
  expect_exit 0
  expect_cleanup
done

for signal in INT TERM; do
  start_server READY "$fixture"
  curl --silent --show-error --max-time 4 "http://127.0.0.1:$PORT/slow" > "$SUMI_TEST_WORK/active.body" &
  client=$!
  wait_for HANDLER_START
  kill -"$signal" -- "-$SUMI_TEST_PID"
  curl --silent --max-time 2 "http://127.0.0.1:$PORT/probe" > /dev/null 2>&1 || true
  wait "$client"
  [[ "$(cat "$SUMI_TEST_WORK/active.body")" == finished ]] || fail 'active response did not finish'
  expect_exit 0
  expect_cleanup
  ! grep -q '^HANDLER_PROBE$' "$SUMI_TEST_WORK/server.log" || fail 'handler ran after stop'
  [[ "$(sed -n '/^HANDLER_START$/,$p' "$SUMI_TEST_WORK/server.log")" == $'HANDLER_START\nHANDLER_END\nSHUTDOWN_START\nSHUTDOWN_END\nEXIT_NORMAL' ]] || fail 'shutdown order'
done

start_server READY "$fixture"
request /stop
expect_status 200
expect_exit 0
expect_cleanup

export MODE=signal-on-dispatch
start_server READY "$fixture"
if curl --silent --max-time 3 "http://127.0.0.1:$PORT/probe" > /dev/null 2>&1; then
  fail 'dispatch signal still produced a response'
fi
expect_exit 0
expect_cleanup
grep -q '^DISPATCH_SIGNAL$' "$SUMI_TEST_WORK/server.log" || fail 'dispatch callback was not exercised'
! grep -q '^HANDLER_PROBE$' "$SUMI_TEST_WORK/server.log" || fail 'handler ran after dispatch callback signalled stop'

export MODE=deadline
start_server READY "$fixture"
kill -TERM -- "-$SUMI_TEST_PID"
expect_exit 124
grep -q '^SHUTDOWN_START$' "$SUMI_TEST_WORK/server.log" || fail 'deadline cleanup never started'
! grep -q '^SHUTDOWN_END$' "$SUMI_TEST_WORK/server.log" || fail 'deadline was cancelled before cleanup'
! grep -q '^EXIT_NORMAL$' "$SUMI_TEST_WORK/server.log" || fail 'deadline exit reported success'

export MODE=idle
start_server READY "$fixture"
MODE=prestopped "$fixture" > "$SUMI_TEST_WORK/prestopped.log" 2>&1
[[ "$(cat "$SUMI_TEST_WORK/prestopped.log")" == EXIT_NORMAL ]] || fail 'prestopped server opened a listener or ran hooks'
if MODE=invalid-budget "$fixture" > "$SUMI_TEST_WORK/invalid.log" 2>&1; then
  fail 'invalid deadline accepted'
fi
grep -qF SUMI_LIFETIME_OPEN "$SUMI_TEST_WORK/invalid.log" || fail 'invalid deadline was not checked before bind'
! grep -q 'SHUTDOWN_' "$SUMI_TEST_WORK/invalid.log" || fail 'cleanup hook ran without a listener'
if "$fixture" > "$SUMI_TEST_WORK/occupied.log" 2>&1; then
  fail 'occupied port accepted'
fi
grep -qF 'SUMI_LISTEN_SETUP' "$SUMI_TEST_WORK/occupied.log" || fail 'occupied port error was lost'
! grep -q 'SHUTDOWN_' "$SUMI_TEST_WORK/occupied.log" || fail 'cleanup hook ran before successful listen'
kill -TERM -- "-$SUMI_TEST_PID"
expect_exit 0
expect_cleanup
printf 'Sumi lifecycle contracts passed\n'
