#!/usr/bin/env bash
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
site="$1"
fixture="$2"
cd "$SUMI_TEST_ROOT"
export PORT="$SUMI_TEST_PORT" SUMI_PUBLIC="$SUMI_TEST_ROOT/examples/web/public"
start_server 'Sumi listening' "$site"
while IFS='|' read -r url filename mime; do
  request "$url"
  expect_status 200
  [[ "$(header Content-Type)" == "$mime" ]] || fail 'incorrect media type'
  cmp "$SUMI_TEST_WORK/body" "$SUMI_PUBLIC/$filename"
  [[ "$(header Content-Length)" == "$(wc -c < "$SUMI_TEST_WORK/body" | tr -d ' ')" ]] || fail 'incorrect byte length'
  [[ "$(header X-Content-Type-Options)" == nosniff ]] || fail 'missing nosniff'
done <<'CASES'
/?private=SECRET|index.html|text/html; charset=utf-8
/assets/site.css|site.css|text/css; charset=utf-8
/assets/site.js|site.js|text/javascript; charset=utf-8
CASES
for path in /missing /../README.md /%2e%2e/README.md /assets/ /assets/site.css/; do
  request "$path"; expect_status 404
done
request / --head; expect_status 405
[[ "$(header Allow)" == GET ]] || fail 'incorrect Allow'
request / -X POST; expect_status 405
if timeout 5 "$site" > "$SUMI_TEST_WORK/failure" 2>&1; then fail 'occupied port accepted'; fi
grep -qF 'Cannot bind listener' "$SUMI_TEST_WORK/failure"
grep -qF "$PORT" "$SUMI_TEST_WORK/failure"
! grep -qF SECRET "$SUMI_TEST_WORK/server.log"
stop_server
start_server READY "$fixture"
while IFS='|' read -r path code; do
  request "$path"; expect_status 500
  [[ "$(cat "$SUMI_TEST_WORK/body")" == 'Internal Server Error' ]] || fail 'diagnostic leaked'
  ! grep -qF Injected "$SUMI_TEST_WORK/headers"
  id="$(header X-Request-Id)"
  grep -F 'event="http.request.completed"' "$SUMI_TEST_WORK/server.log" | grep -F "request_id=\"$id\"" | grep -qF "code=\"$code\""
done <<'CASES'
/failure/PRIVATE|APP_GREETING_UNAVAILABLE
/invalid|SUMI_RESPONSE_CONTENT_TYPE
/unicode|APP_UNICODE
CASES
request '/context?key=SECRET'
[[ "$(cat "$SUMI_TEST_WORK/body")" == "key=SECRET:$(header X-Request-Id)" ]] || fail 'request context lost'
request / -H 'Host:'; expect_status 400
# Wait for the terminal log after the client received its last response.
deadline=$((SECONDS + 2))
until [[ "$(grep -cF 'event="http.request.completed"' "$SUMI_TEST_WORK/server.log")" == 5 ]]; do
  (( SECONDS < deadline )) || fail 'missing terminal events'
  sleep 0.01
done
[[ "$(grep -cF 'event="http.request.started"' "$SUMI_TEST_WORK/server.log")" == 5 ]]
! grep -Eq 'PRIVATE|SECRET|duration_ms=-' "$SUMI_TEST_WORK/server.log"
grep -qF 'code="SUMI_HTTP_400"' "$SUMI_TEST_WORK/server.log"
grep -qF 'route="/failure/:name"' "$SUMI_TEST_WORK/server.log"
grep -qF 'Diagnóstico: 水?second line' "$SUMI_TEST_WORK/server.log"
for status in 204 205 304; do
  request "/status/$status"; expect_status "$status"
  [[ ! -s "$SUMI_TEST_WORK/body" ]] || fail 'bodyless status included a body'
  if [[ "$status" == 205 ]]; then
    [[ "$(header Content-Length)" == 0 ]]
  else
    [[ -z "$(header Content-Length)" ]]
  fi
done
for status in 199 600; do request "/status/$status"; expect_status 500; done
stop_server
if SUMI_PUBLIC="$SUMI_TEST_WORK/missing" timeout 5 "$site" > "$SUMI_TEST_WORK/failure" 2>&1; then fail 'missing assets accepted'; fi
grep -qF SUMI_STATIC_READ "$SUMI_TEST_WORK/failure"
grep -qF index.html "$SUMI_TEST_WORK/failure"
! grep -qF 'Sumi listening' "$SUMI_TEST_WORK/failure"
printf 'Sumi HTTP contracts passed\n'
