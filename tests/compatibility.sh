#!/usr/bin/env bash
set -euo pipefail

SUMI_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUMI_WORK="$(mktemp -d)"
trap 'rm -r -- "$SUMI_WORK"' EXIT

cat > "$SUMI_WORK/neri" <<'COMPILER'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then
  printf 'neri 0.2.0-dev\n'
  exit 0
fi
printf 'NR_FIXTURE: unit selection is unavailable\n' >&2
exit 2
COMPILER
chmod +x "$SUMI_WORK/neri"

if NERI="$SUMI_WORK/neri" "$SUMI_ROOT/scripts/check-compatibility.sh" --compile-only > "$SUMI_WORK/report" 2>&1; then
  printf 'Incompatible compiler was accepted\n' >&2
  exit 1
fi

grep -qF 'NR_FIXTURE: unit selection is unavailable' "$SUMI_WORK/report"
grep -qF 'SUMI_COMPAT_BUILD: Cannot build unit contracts.' "$SUMI_WORK/report"
printf 'Sumi compatibility rejection contract passed\n'
