#!/usr/bin/env bash
# Regression tests for scripts/check-benchmark-summary.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python >/dev/null 2>&1; then
    PY=python
  else
    PY=python3
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

cat >"$tmp/summary.tsv" <<'TSV'
file	agat_s	gxfkit_s	speedup	agat_mem	gxfkit_mem	parity%
human_chr1	46.96	1.20	39.1×	5.50 GB	2.13 GB	100.00
human_chr21	6.97	0.16	43.6×	966 MB	300 MB	100.00
yeast	5.63	0.10	56.3×	770 MB	229 MB	100.00
TSV

"$PY" scripts/check-benchmark-summary.py "$tmp/summary.tsv" --require >"$tmp/ok.out"
grep -F "verified benchmark summary: human_chr1 human_chr21 yeast parity >= 100%" \
  "$tmp/ok.out" >/dev/null

"$PY" scripts/check-benchmark-summary.py "$tmp/missing.tsv" >"$tmp/missing-optional.out"
grep -F "benchmark summary not found; generate with" "$tmp/missing-optional.out" >/dev/null

expect_fail \
  missing-required-file \
  "missing required benchmark rows: drosophila" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/summary.tsv" --required-files "human_chr1 yeast drosophila"

perl -0pe 's/yeast\t5\.63\t0\.10\t56\.3×\t770 MB\t229 MB\t100\.00/yeast\t5.63\t0.10\t56.3×\t770 MB\t229 MB\t99.99/' \
  "$tmp/summary.tsv" >"$tmp/low.tsv"
expect_fail \
  low-parity \
  "yeast parity 99.99% < 100%" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/low.tsv"

cat >"$tmp/duplicate.tsv" <<'TSV'
file	agat_s	gxfkit_s	speedup	agat_mem	gxfkit_mem	parity%
human_chr1	46.96	1.20	39.1×	5.50 GB	2.13 GB	100.00
human_chr1	46.96	1.20	39.1×	5.50 GB	2.13 GB	100.00
human_chr21	6.97	0.16	43.6×	966 MB	300 MB	100.00
yeast	5.63	0.10	56.3×	770 MB	229 MB	100.00
TSV
expect_fail \
  duplicate-file \
  "duplicate file name 'human_chr1'" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/duplicate.tsv"

cat >"$tmp/bad-header.tsv" <<'TSV'
file	agat_s	gxfkit_s	parity%
human_chr1	46.96	1.20	100.00
TSV
expect_fail \
  bad-header \
  "unexpected header" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/bad-header.tsv"

expect_fail \
  missing-required-summary \
  "benchmark summary not found" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/missing.tsv" --require

expect_fail \
  bad-min-parity \
  "argument --min-parity: must be a number, got: high" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/summary.tsv" --min-parity high

expect_fail \
  duplicate-required-files \
  "argument --required-files: duplicate corpus name: yeast" \
  "$PY" scripts/check-benchmark-summary.py "$tmp/summary.tsv" --required-files "yeast yeast"

echo "verified benchmark summary tests"
