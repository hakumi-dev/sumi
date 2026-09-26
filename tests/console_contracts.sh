#!/usr/bin/env bash
set -euo pipefail
cli="$1"
project="$2"
output="$(mktemp)"
trap 'status=$?; if [[ "$status" != 0 ]]; then cat "$output"; fi; rm -- "$output"; exit "$status"' EXIT
printf '%s\n' \
  '1 + 1' \
  '2*2*2*2*2*2' \
  'console::println("printed-once")' \
  'console::println("á水")' \
  'def twice(value: Int): Int' 'return value * 2' 'end' 'twice(4)' \
  'var count = 40' \
  'count = count + 2' \
  'console::println(count as String)' \
  $'\xff' 'count' \
  'missingConsoleFunction()' \
  'console::println(count as String)' \
  'class ConsoleCounter' 'public value: Int = 100' \
  'def bump(): Int' 'this.value = this.value + 1' 'return this.value' 'end' 'end' \
  'let meter = new ConsoleCounter()' 'meter.bump()' 'meter.value' \
  'let response = app.handle(new sumi::Request("GET", "/"))' \
  'response.status' \
  'def unfinished(): Void' ':cancel' '1 + 1' \
  ':reset' \
  'app.handle(new sumi::Request("GET", "/")).status' \
  ':exit' | SUMI_CONSOLE_TIMINGS=1 "$cli" c --project "$project" > "$output" 2>&1 || { cat "$output"; exit 1; }
grep -qF 'Sumi console' "$output"
grep -qF '=> 2' "$output"
grep -qF '=> 8' "$output"
grep -qF '=> 64' "$output"
grep -qF 'á水' "$output"
grep -qF 'SUMI_CONSOLE_INPUT: Input is not valid UTF-8' "$output"
! grep -qF 'Neri panic' "$output"
[[ "$(grep -c 'printed-once' "$output")" == 1 ]]
grep -A1 'sumi> printed-once$' "$output" | grep -qF 'context=app'
grep -A1 'sumi> 42$' "$output" | grep -qF 'context=app'
grep -qF 'Input cleared' "$output"
[[ "$(grep -c '42' "$output")" -ge 2 ]]
[[ "$(grep -c '200' "$output")" -ge 2 ]]
grep -qF missingConsoleFunction "$output"
grep -qF 'App reinitialized' "$output"
[[ "$(grep -cF '=> 101' "$output")" == 2 ]]
printf 'Sumi persistent console contracts passed\n'
