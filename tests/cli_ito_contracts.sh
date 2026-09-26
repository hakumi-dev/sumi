#!/usr/bin/env bash
set -euo pipefail
SUMI_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SUMI_TEST_ROOT/tests/process.sh"
cli="$1"
export SUMI_HOME="${SUMI_PACKAGE_HOME:-$SUMI_TEST_ROOT}"
export NERI="$(command -v "${NERI:-neri}")"
export ITO="$(command -v "${ITO:-ito}")"
export ITO_HOME="$SUMI_TEST_WORK/cache"
unset SUMI_ENV PORT SUMI_PUBLIC
project="$SUMI_TEST_WORK/package app"
mkdir "$project"
cp -R "$SUMI_TEST_ROOT/templates/web/main.hk" "$SUMI_TEST_ROOT/templates/web/app" \
  "$SUMI_TEST_ROOT/templates/web/tests" "$SUMI_TEST_ROOT/templates/web/public" "$project/"
"$ITO" --project "$project" init cli-fixture
mkdir "$SUMI_TEST_WORK/framework"
cp -R "$SUMI_TEST_ROOT/src" "$SUMI_TEST_ROOT/package.json" "$SUMI_TEST_WORK/framework/"
"$ITO" --project "$project" add ../framework
[[ ! -e "$project/neri.json" && ! -e "$project/sumi.conf" && ! -e "$project/vendor" ]]
(cd "$project/app" && "$cli" t)
bash "$SUMI_TEST_ROOT/tests/console_contracts.sh" "$cli" "$project"
terminal_libs=()
if [[ "$(uname -s)" == Linux ]]; then terminal_libs+=(-lutil); fi
cc -std=c11 -Wall -Wextra -Werror "$SUMI_TEST_ROOT/tests/console_terminal.c" \
  "${terminal_libs[@]}" -o "$SUMI_TEST_WORK/console-terminal"
"$SUMI_TEST_WORK/console-terminal" "$cli" "$project"
"$NERI" run --project "$SUMI_TEST_ROOT/neri.json" --unit console-ui-contracts --release -- \
  "$cli" "$project" "$SUMI_TEST_WORK/console-terminal"
"$cli" test --project "$project" --release
"$cli" b --project "$project" --release --output "$project/custom application"
[[ -x "$project/custom application" ]]
# package.json takes precedence over old manifests/configuration left behind.
printf 'obsolete manifest' > "$project/neri.json"
printf 'unknown=obsolete' > "$project/sumi.conf"
printf 'PORT=1\n' > "$project/.env"
printf 'PORT=2\n' > "$project/.env.development"
cd "$project"
start_compiling_server 'Sumi listening' "$cli" s --port "$SUMI_TEST_PORT"
request /; expect_status 200
cmp "$SUMI_TEST_WORK/body" "$project/public/index.html"
request /assets/site.css; expect_status 200
cmp "$SUMI_TEST_WORK/body" "$project/public/site.css"
stop_server
if curl -s --max-time 1 "http://127.0.0.1:$SUMI_TEST_PORT/" > /dev/null; then fail 'server still alive'; fi
printf 'def main(): Void\n  missingFunction()\nend\n' > "$project/tests/application.hk"
if "$cli" t > "$SUMI_TEST_WORK/error" 2>&1; then fail 'Ito compiler failure swallowed'; fi
grep -qF application.hk "$SUMI_TEST_WORK/error"
printf 'Sumi Ito CLI contracts passed\n'
