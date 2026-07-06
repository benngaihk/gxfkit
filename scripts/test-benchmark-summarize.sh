#!/usr/bin/env bash
# Regression tests for benchmark/summarize.py input validation.
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

write_gtf_pair() {
  local name="$1"
  for suffix in agat gxfkit; do
    cat >"$tmp/${name}.${suffix}.gtf" <<'GTF'
chr1	src	gene	1	100	.	+	.	gene_id "g1"; ID "gene:g1";
GTF
  done
}

write_valid_metrics() {
  local name="$1"
  cat >"$tmp/metrics.tsv" <<EOF
file	agat_wall_s	agat_mem_kb	gxfkit_wall_s	gxfkit_mem_kb
${name}	2.00	2048	1.00	1024
EOF
}

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
  if ! grep -F "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

write_gtf_pair yeast
write_valid_metrics yeast
"$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py >"$tmp/ok.out"
grep -F '| `yeast` | 2.00 s | 1.00 s | **2.0×** | 2 MB | 1 MB | 100.00% |' "$tmp/ok.out" >/dev/null
grep -F 'yeast	2.00	1.00	2.0×	2 MB	1 MB	100.00' "$tmp/summary.tsv" >/dev/null

cat >>"$tmp/yeast.gxfkit.gtf" <<'GTF'
chr1	src	exon	1	100	.	+	.	gene_id "g1"; transcript_id "t1"; ID "extra";
GTF
"$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py >"$tmp/extra-b.out"
grep -F 'yeast	2.00	1.00	2.0×	2 MB	1 MB	50.00' "$tmp/summary.tsv" >/dev/null
expect_fail \
  extra-b-fails-min-parity-100 \
  "PARITY REGRESSION: yeast 50.00% < 100.0%" \
  env MIN_PARITY=100 "$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py
write_gtf_pair yeast

cat >"$tmp/metrics.tsv" <<'EOF'
file	agat_wall_s	gxfkit_wall_s
yeast	2.00	1.00
EOF
expect_fail \
  bad-header \
  "unexpected header" \
  "$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py

write_valid_metrics yeast
cat >>"$tmp/metrics.tsv" <<'EOF'
yeast	3.00	2048	1.00	1024
EOF
expect_fail \
  duplicate-name \
  "duplicate file name" \
  "$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py

cat >"$tmp/metrics.tsv" <<'EOF'
file	agat_wall_s	agat_mem_kb	gxfkit_wall_s	gxfkit_mem_kb
../evil	2.00	2048	1.00	1024
EOF
expect_fail \
  unsafe-name \
  "unsafe file name" \
  "$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py

write_valid_metrics yeast
expect_fail \
  bad-min-parity \
  "MIN_PARITY must be a number" \
  env MIN_PARITY=high "$PY" benchmark/summarize.py "$tmp" tests/parity/normalize.py

echo "verified benchmark summarize tests"
