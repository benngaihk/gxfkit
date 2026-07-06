#!/usr/bin/env bash
# Regression tests for scripts/check-parity-doc.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 scripts/check-parity-doc.py

expect_fail() {
  local label="$1"
  local expected="$2"
  shift 2
  local out="$tmp/${label}.out"
  if "$@" >"$out" 2>&1; then
    echo "$label unexpectedly passed" >&2
    cat "$out" >&2
    exit 1
  fi
  if ! grep -F -- "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

fixture="$tmp/fixture"
mkdir -p "$fixture/docs"
cp docs/PARITY.md "$fixture/docs/PARITY.md"

perl -0pi -e 's/enforced by CI at 100%/enforced by CI at ≥98%/' \
  "$fixture/docs/PARITY.md"
expect_fail \
  stale-core-gate \
  "docs/PARITY.md must mention: enforced by CI at 100%" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-parity-doc.py

cp docs/PARITY.md "$fixture/docs/PARITY.md"
perl -0pi -e 's/\| core     \| yeast             \| ~28\.7k \| \*\*100\.00%\*\* \| none/\| core     | yeast             | ~28.7k | **99.99%**  | regression/' \
  "$fixture/docs/PARITY.md"
expect_fail \
  stale-core-row \
  "docs/PARITY.md must mention: | core     | yeast             | ~28.7k | **100.00%** | none" \
  env GXFKIT_ROOT="$fixture" python3 scripts/check-parity-doc.py

echo "verified parity doc tests"
