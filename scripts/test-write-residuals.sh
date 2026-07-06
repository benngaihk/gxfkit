#!/usr/bin/env bash
# Regression tests for benchmark/write-residuals.sh candidate discovery.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

write_pair() {
  local name="$1"
  for suffix in agat gxfkit; do
    cat >"$tmp/${name}.${suffix}.gtf" <<'GTF'
chr1	src	gene	1	100	.	+	.	gene_id "g1"; ID "gene:g1";
GTF
  done
}

write_pair alpha
write_pair beta
cat >"$tmp/missing.agat.gtf" <<'GTF'
chr1	src	gene	1	100	.	+	.	gene_id "g1"; ID "gene:g1";
GTF

cat >"$tmp/summary.tsv" <<'TSV'
file	agat_s	gxfkit_s	speedup	agat_rss	gxfkit_rss	parity_pct
alpha	1.00	0.50	2.0x	1 MB	1 MB	100.00
TSV

bash benchmark/write-residuals.sh "$tmp"

grep -F "SUMMARY matched=1 only_in_a=0 only_in_b=0 parity=100.00%" \
  "$tmp/residuals/alpha.txt" >/dev/null
grep -F "SUMMARY matched=1 only_in_a=0 only_in_b=0 parity=100.00%" \
  "$tmp/residuals/beta.txt" >/dev/null
grep -F "ERROR missing GTF output for missing" \
  "$tmp/residuals/missing.txt" >/dev/null
grep -F "missing: $tmp/missing.gxfkit.gtf" \
  "$tmp/residuals/missing.txt" >/dev/null

cat >"$tmp/synthetic-a.gtf" <<'GTF'
chr1	src	exon	10	20	.	+	.	gene_id "g1"; transcript_id "t1"; ID "agat-exon-2";
chr1	src	exon	30	40	.	+	.	gene_id "g1"; transcript_id "t1"; ID "agat-exon-1";
GTF
cp "$tmp/synthetic-a.gtf" "$tmp/synthetic-b.gtf"
cat >>"$tmp/synthetic-b.gtf" <<'GTF'
chr1	src	exon	50	60	.	+	.	gene_id "g1"; transcript_id "t1"; ID "agat-exon-3";
GTF
PYTHONPATH=tests/parity python3 tests/parity/residual_summary.py \
  "$tmp/synthetic-a.gtf" "$tmp/synthetic-b.gtf" >"$tmp/synthetic-summary.txt"
grep -F "SUMMARY matched=2 only_in_a=0 only_in_b=1 parity=66.67%" \
  "$tmp/synthetic-summary.txt" >/dev/null
grep -F "family=agat-exon" "$tmp/synthetic-summary.txt" >/dev/null
grep -F "line_counter_inversions=1" "$tmp/synthetic-summary.txt" >/dev/null

echo "verified residual writer tests"
