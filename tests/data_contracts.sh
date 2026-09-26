#!/usr/bin/env bash
# Opt-in integration fixture: requires a sibling Neri source checkout.
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
export PORT="$SUMI_TEST_PORT" SUMI_TEST_WORK
client_pid=""
cleanup_data() {
  if [[ -n "$client_pid" ]] && kill -0 "$client_pid" 2>/dev/null; then
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
  fi
  cleanup
}
trap cleanup_data EXIT

if [[ $# == 2 ]]; then
  server="$1"
  driver="$2"
else
  compiler="${NERI:-neri}"
  mkdir "$SUMI_TEST_WORK/bin"
  "$compiler" build-batch --project "$SUMI_TEST_ROOT/tests/data/manifest.json" \
    --output-dir "$SUMI_TEST_WORK/bin" --unit server --unit driver
  server="$SUMI_TEST_WORK/bin/server"
  driver="$SUMI_TEST_WORK/bin/driver"
fi
start_server READY "$server"
"$driver" > "$SUMI_TEST_WORK/driver.log" 2>&1 &
client_pid=$!
deadline=$((SECONDS + 12))
until [[ -f "$SUMI_TEST_WORK/signal-ready" ]]; do
  if ! kill -0 "$client_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    cat "$SUMI_TEST_WORK/driver.log" "$SUMI_TEST_WORK/server.log" >&2
    fail 'Data HTTP driver did not reach active shutdown request'
  fi
  sleep 0.01
done
kill -TERM -- "-$SUMI_TEST_PID"
printf ready > "$SUMI_TEST_WORK/drain-release"
wait "$client_pid"
client_pid=""
deadline=$((SECONDS + 8))
while kill -0 "$SUMI_TEST_PID" 2>/dev/null; do
  (( SECONDS < deadline )) || fail 'Data server did not drain after SIGTERM'
  sleep 0.01
done
wait "$SUMI_TEST_PID"
SUMI_TEST_PID=""
[[ "$(grep -c '^DATA_WORKER_CLOSED$' "$SUMI_TEST_WORK/server.log")" == 2 ]] || fail 'worker sessions did not close'
[[ "$(tail -n 2 "$SUMI_TEST_WORK/server.log")" == $'DATA_SHUTDOWN\nDATA_EXIT' ]] || fail 'shutdown ran before session cleanup'
MODE=verify "$server"
printf 'Sumi Data concurrent HTTP contracts passed\n'
