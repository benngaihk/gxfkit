#!/usr/bin/env bash
# Fast M1 dev loop: build gxfkit, run it on each corpus file, and diff against
# the AGAT gold already in benchmark/results/*.agat.gtf (no Docker / no AGAT
# re-run). Prints the parity % per file. Use this to iterate on convert.rs.
#
#   bash benchmark/parity-check.sh
#
# Optional env:
#   BENCH_FILES="human_chr1 yeast"  space-separated basenames to run
#
# Assumes the gold files exist (run benchmark/run.sh once to generate them).
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
BENCH_FILES="${BENCH_FILES:-}"
GXF="$ROOT/target/release/gxfkit.exe"
[ -x "$GXF" ] || GXF="$ROOT/target/release/gxfkit"
CARGO_BIN="${CARGO:-cargo}"
if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
  else
    CARGO_BIN=""
  fi
fi

echo ">> building release..."
if [ -n "$CARGO_BIN" ]; then
  if ! "$CARGO_BIN" build --release --locked --quiet 2>/dev/null; then
    if command -v powershell >/dev/null 2>&1; then
      powershell -File scripts/with-msvc-env.ps1 "$CARGO_BIN" build --release --locked >/dev/null
    else
      "$CARGO_BIN" build --release --locked
    fi
  fi
elif command -v powershell >/dev/null 2>&1; then
  powershell -File scripts/with-msvc-env.ps1 cargo build --release --locked >/dev/null
else
  echo "cargo not found on PATH and $HOME/.cargo/bin/cargo is missing" >&2
  exit 127
fi

total=0; sumrate=0
shopt -s nullglob
for gold in benchmark/results/*.agat.gtf; do
  name=$(basename "$gold" .agat.gtf)
  if [ -n "$BENCH_FILES" ] && [[ " $BENCH_FILES " != *" $name "* ]]; then
    continue
  fi
  in="corpus/raw/${name}.gff3"
  [ -e "$in" ] || { echo "  [skip] no input for $name"; continue; }
  out="benchmark/results/${name}.gxfkit.gtf"
  rm -f "$out"
  "$GXF" gff2gtf -g "$in" -o "$out"
  if norm_out=$("$PY" tests/parity/normalize.py "$gold" "$out" 2>&1); then
    rate="100.00"
  else
    rate=$(printf '%s\n' "$norm_out" | awk -F'parity=' '/parity=/{print $2}' | tr -d '%')
    if [ -z "$rate" ]; then
      printf '%s\n' "$norm_out" >&2
      echo "failed to compute parity for $name" >&2
      exit 1
    fi
  fi
  printf "  %-14s parity=%s%%\n" "$name" "$rate"
  total=$((total+1)); sumrate=$(awk "BEGIN{print $sumrate + $rate}")
done
if [ "$total" -eq 0 ]; then
  echo "no AGAT gold files matched BENCH_FILES='${BENCH_FILES}'" >&2
  exit 1
fi
awk "BEGIN{printf \">> mean parity over %d files: %.2f%%\n\", $total, $sumrate/$total}"
