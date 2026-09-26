#!/usr/bin/env bash
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
fixture="$1"
export PORT="$SUMI_TEST_PORT" MODE=concurrent SUMI_TEST_WORK
partial=""
blocked=""
cleanup_concurrent() {
  if [[ -n "$blocked" ]]; then
    kill "$blocked" 2>/dev/null || true
    wait "$blocked" 2>/dev/null || true
  fi
  if [[ -n "$partial" ]] && kill -0 "$partial" 2>/dev/null; then
    kill "$partial" 2>/dev/null || true
    wait "$partial" 2>/dev/null || true
  fi
  cleanup
}
trap cleanup_concurrent EXIT

count_files() {
  local prefix="$1"
  find "$SUMI_TEST_WORK" -maxdepth 1 -type f -name "$prefix*" | wc -l | tr -d ' '
}
wait_files() {
  local prefix="$1" expected="$2" deadline=$((SECONDS + 8))
  until (( $(count_files "$prefix") >= expected )); do
    (( SECONDS < deadline )) || fail "missing $expected $prefix markers"
    sleep 0.01
  done
}
wait_exit() {
  local expected="${1:-0}" budget="${2:-10}" status=0
  local deadline=$((SECONDS + budget))
  while kill -0 "$SUMI_TEST_PID" 2>/dev/null; do
    (( SECONDS < deadline )) || fail 'concurrent server did not stop'
    sleep 0.01
  done
  wait "$SUMI_TEST_PID" || status=$?
  SUMI_TEST_PID=""
  [[ "$status" == "$expected" ]] || fail "expected server exit $expected, got $status"
}

# Startup is bounded even before any worker reports readiness.
status=0
MODE=startup-slow timeout --signal=KILL 4 "$fixture" > "$SUMI_TEST_WORK/startup-slow.log" 2>&1 || status=$?
[[ "$status" == 124 ]] || fail "expected startup deadline exit 124, got $status"
grep -q '^WORKER_STARTING$' "$SUMI_TEST_WORK/startup-slow.log" || fail 'startup deadline did not exercise worker initialization'
! grep -q '^READY$' "$SUMI_TEST_WORK/startup-slow.log" || fail 'listener opened before workers were ready'

start_server READY "$fixture"
# Failed bind must arm the shutdown deadline before joining worker cleanup.
status=0
MODE=cleanup-slow timeout --signal=KILL 4 "$fixture" > "$SUMI_TEST_WORK/bind-cleanup.log" 2>&1 || status=$?
[[ "$status" == 124 ]] || fail "expected failed-bind cleanup deadline exit 124, got $status"
grep -q '^WORKER_CLEANUP_BEGIN$' "$SUMI_TEST_WORK/bind-cleanup.log" || fail 'failed bind did not reach worker cleanup'
! grep -q '^READY$' "$SUMI_TEST_WORK/bind-cleanup.log" || fail 'occupied listener was accepted'
rm -f "$SUMI_TEST_WORK/release"
# Two gated requests must enter before either is released; each worker owns its counter.
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/gate-a" & gate_a=$!
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/gate-b" & gate_b=$!
wait_files entered- 2
[[ "$(count_files finished-)" == 0 ]] || fail 'gated request finished before barrier release'
touch "$SUMI_TEST_WORK/release"
wait "$gate_a"; wait "$gate_b"
[[ "$(cat "$SUMI_TEST_WORK/gate-a")" == gate-1 ]] || fail 'first worker counter was not private'
[[ "$(cat "$SUMI_TEST_WORK/gate-b")" == gate-1 ]] || fail 'second worker counter was not private'
wait_files finished- 2

# The configured outstanding limit rejects a third request while two are gated.
rm -f "$SUMI_TEST_WORK"/{entered-,finished-,release}* "$SUMI_TEST_WORK/release"
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/limited-a" & limited_a=$!
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/limited-b" & limited_b=$!
wait_files entered- 2
request /fast
expect_status 503
touch "$SUMI_TEST_WORK/release"
wait "$limited_a"; wait "$limited_b"

# A client that has not completed its request body cannot block another client.
rm -f "$SUMI_TEST_WORK/partial-ready" "$SUMI_TEST_WORK/partial-release"
MODE=partial-client "$fixture" > "$SUMI_TEST_WORK/partial.log" 2>&1 & partial=$!
wait_files partial-ready 1
request /fast
expect_status 200
touch "$SUMI_TEST_WORK/partial-release"
wait "$partial"
partial=""

# Binary packets cross several reads and writes without UTF-8 conversion.
MODE=binary-payload "$fixture"
request /echo -X POST -H 'Expect:' --data-binary "@$SUMI_TEST_WORK/payload"
expect_status 200
cmp "$SUMI_TEST_WORK/payload" "$SUMI_TEST_WORK/body" || fail 'binary worker response was corrupted'
request /fast --head
expect_status 200
[[ "$(header Content-Length)" == 4 ]] || fail 'HEAD lost representation length'

# Active responses drain before the last shutdown callback and all workers return.
rm -f "$SUMI_TEST_WORK"/{entered-,finished-,release}*
rm -f "$SUMI_TEST_WORK/release"
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/drain-a" & drain_a=$!
curl --silent --show-error --max-time 8 "http://127.0.0.1:$PORT/gate" > "$SUMI_TEST_WORK/drain-b" & drain_b=$!
wait_files entered- 2
kill -TERM -- "-$SUMI_TEST_PID"
touch "$SUMI_TEST_WORK/release"
wait "$drain_a"; wait "$drain_b"
grep -Eq '^gate-[1-9][0-9]*$' "$SUMI_TEST_WORK/drain-a" || fail 'first active response was not drained'
grep -Eq '^gate-[1-9][0-9]*$' "$SUMI_TEST_WORK/drain-b" || fail 'second active response was not drained'
wait_exit
[[ "$(grep -c '^SHUTDOWN_LAST$' "$SUMI_TEST_WORK/server.log")" == 1 ]] || fail 'shutdown callback did not run once'
[[ "$(tail -n 1 "$SUMI_TEST_WORK/server.log")" == EXIT_NORMAL ]] || fail 'normal exit was not reported after shutdown'
cleanup_line="$(grep -n '^WORKER_CLEANUP$' "$SUMI_TEST_WORK/server.log" | tail -n 1 | cut -d: -f1)"
shutdown_line="$(grep -n '^SHUTDOWN_LAST$' "$SUMI_TEST_WORK/server.log" | cut -d: -f1)"
[[ "$(grep -c '^WORKER_CLEANUP$' "$SUMI_TEST_WORK/server.log")" == 2 ]] || fail 'not all workers reported cleanup'
(( cleanup_line < shutdown_line )) || fail 'shutdown callback ran before worker cleanup'

# A handler that outlives shutdown is terminated by the fatal budget, without
# claiming a normal response or resource unwind. Its barrier is never released.
rm -f "$SUMI_TEST_WORK"/{entered-,finished-,release}*
export MODE=handler-slow
start_server READY "$fixture"
curl --silent --show-error --max-time 6 "http://127.0.0.1:$PORT/gate" \
  > "$SUMI_TEST_WORK/blocked.body" 2> "$SUMI_TEST_WORK/blocked.log" & blocked=$!
wait_files entered- 1
kill -TERM -- "-$SUMI_TEST_PID"
wait_exit 124 4
status=0
wait "$blocked" || status=$?
blocked=""
[[ "$status" != 0 && "$status" != 28 ]] || fail 'blocked client succeeded or reached its own timeout'
[[ ! -s "$SUMI_TEST_WORK/blocked.body" ]] || fail 'blocked handler produced a response'
[[ "$(count_files finished-)" == 0 ]] || fail 'blocked handler finished before forced exit'
! grep -Eq '^(WORKER_CLEANUP|SHUTDOWN_LAST|EXIT_NORMAL)$' "$SUMI_TEST_WORK/server.log" || fail 'forced exit claimed normal cleanup'

# Callback time counts toward the absolute request deadline.
export MODE=slow-log
start_server READY "$fixture"
# Closing a timed-out socket with unread input can reset the TCP connection
# after the 408 headers; both outcomes must still avoid application dispatch.
status=0
request /fast 2> "$SUMI_TEST_WORK/timeout-client.log" || status=$?
[[ "$status" == 0 || "$status" == 56 ]] || fail "unexpected timeout client exit $status"
expect_status 408
! grep -q '^HANDLER_FAST$' "$SUMI_TEST_WORK/server.log" || fail 'expired request reached a worker'
kill -TERM -- "-$SUMI_TEST_PID"
wait_exit

# Worker preparation failure is reported before a listener is opened.
rm -f "$SUMI_TEST_WORK"/*
touch "$SUMI_TEST_WORK/startup-failure"
status=0
PORT="$SUMI_TEST_PORT" SUMI_TEST_WORK="$SUMI_TEST_WORK" MODE=startup-failure timeout 10 "$fixture" > "$SUMI_TEST_WORK/startup.log" 2>&1 || status=$?
[[ "$status" == 1 ]] || fail "expected worker preparation failure exit 1, got $status"
grep -qF 'worker prepare failed' "$SUMI_TEST_WORK/startup.log"
[[ "$(grep -c '^WORKER_PREPARE_FAILURE$' "$SUMI_TEST_WORK/startup.log")" == 2 ]] || fail 'not all workers reported preparation failure'
if curl --silent --max-time 1 "http://127.0.0.1:$PORT/fast" >/dev/null 2>&1; then
  fail 'listener opened after worker preparation failure'
fi
printf 'Sumi concurrent contracts passed\n'
