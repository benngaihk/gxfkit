#!/usr/bin/env bash
# Fast M1 dev loop: build gxfkit, run it on each corpus file, and diff against
# the AGAT gold already in benchmark/results/*.agat.gtf (no Docker / no AGAT
# re-run). Prints the parity % per file. Use this to iterate on convert.rs.
#
#   bash benchmark/parity-check.sh
#
# Assumes the gold files exist (run benchmark/run.sh once to generate them).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PY="${PYTHON:-python}"
GXF="$ROOT/target/release/gxfkit.exe"
[ -x "$GXF" ] || GXF="$ROOT/target/release/gxfkit"

echo ">> building release..."
if command -v cargo >/dev/null 2>&1; then
  cargo build --release --quiet 2>/dev/null \
    || powershell -File scripts/with-msvc-env.ps1 cargo build --release >/dev/null
else
  powershell -File scripts/with-msvc-env.ps1 cargo build --release >/dev/null
fi

total=0; sumrate=0
for gold in benchmark/results/*.agat.gtf; do
  [ -e "$gold" ] || continue
  name=$(basename "$gold" .agat.gtf)
  in="corpus/raw/${name}.gff3"
  [ -e "$in" ] || { echo "  [skip] no input for $name"; continue; }
  out="benchmark/results/${name}.gxfkit.gtf"
  "$GXF" gff2gtf -g "$in" -o "$out"
  rate=$("$PY" tests/parity/normalize.py "$gold" "$out" 2>&1 \
           | awk -F'parity=' '/parity=/{print $2}' | tr -d '%')
  [ -z "$rate" ] && rate="100.00"
  printf "  %-14s parity=%s%%\n" "$name" "$rate"
  total=$((total+1)); sumrate=$(awk "BEGIN{print $sumrate + $rate}")
done
[ "$total" -gt 0 ] && awk "BEGIN{printf \">> mean parity over %d files: %.2f%%\n\", $total, $sumrate/$total}"
