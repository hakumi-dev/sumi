#!/usr/bin/env bash
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
cli="$1"
export SUMI_HOME="$SUMI_TEST_ROOT"
export NERI="$(command -v "${NERI:-neri}")"
unset SUMI_ENV PORT
project="$SUMI_TEST_WORK/my site"
cd "$SUMI_TEST_WORK"
"$cli" new "$project"
printf 'user content' > "$project/keep.txt"
if "$cli" new "$project" > "$SUMI_TEST_WORK/error" 2>&1; then fail 'existing project overwritten'; fi
grep -qF SUMI_CLI_DESTINATION "$SUMI_TEST_WORK/error"
[[ "$(cat "$project/keep.txt")" == 'user content' ]]
"$cli" new --help > /dev/null
[[ ! -e "$SUMI_TEST_WORK/--help" ]]
if timeout 5 "$cli" server --project "$project" --port '' > "$SUMI_TEST_WORK/error" 2>&1; then fail 'empty port accepted'; fi
grep -qF 'SUMI_CLI_ARGUMENT: Missing port' "$SUMI_TEST_WORK/error"
mv "$project/app" "$project/application"
mv "$project/public" "$project/assets"
sed -i 's@app/routes.hk@application/routes.hk@g' "$project/neri.json"
sed -i 's@public=public@public=assets@' "$project/sumi.conf"
(cd "$project/application" && "$cli" t)
"$cli" test --project "$project" --release
"$cli" b --project "$project" --release
[[ -x "$project/build/application" ]]
printf 'PORT=1\n' > "$project/.env"
printf 'PORT=2\n' > "$project/.env.development"
start_server 'Sumi listening' "$cli" s --project "$project" --port "$SUMI_TEST_PORT"
request /; expect_status 200
grep -qF 'It all starts' "$SUMI_TEST_WORK/body"
stop_server
if curl -s --max-time 1 "http://127.0.0.1:$SUMI_TEST_PORT/" > /dev/null; then fail 'server still alive'; fi
if "$cli" s --project "$project" --port 0 > "$SUMI_TEST_WORK/error" 2>&1; then fail 'invalid port accepted'; fi
grep -qF SUMI_CLI_PORT "$SUMI_TEST_WORK/error"
if "$cli" c --project "$project" > "$SUMI_TEST_WORK/error" 2>&1; then fail 'unavailable console reported success'; fi
grep -qF SUMI_CONSOLE_UNAVAILABLE "$SUMI_TEST_WORK/error"
printf 'unknown=value\n' > "$project/sumi.conf"
if "$cli" test --project "$project" > "$SUMI_TEST_WORK/error" 2>&1; then fail 'unknown config accepted'; fi
grep -qF SUMI_CLI_CONFIG "$SUMI_TEST_WORK/error"
printf 'public=assets\nserver=web\ntest=test\n' > "$project/sumi.conf"
printf 'def main(): Void\n  missingFunction()\nend\n' > "$project/tests/application.hk"
if "$cli" t --project "$project" > "$SUMI_TEST_WORK/error" 2>&1; then fail 'compiler failure swallowed'; fi
grep -qF application.hk "$SUMI_TEST_WORK/error"
printf 'Sumi CLI contracts passed\n'
