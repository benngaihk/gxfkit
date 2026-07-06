#!/usr/bin/env bash
# Write per-file normalized residual diagnostics from benchmark/results.
#
# Usage:
#   bash benchmark/write-residuals.sh [benchmark/results]
#
# Uses the union of summary.tsv entries and every *.agat.gtf in the results
# directory. Writes one residual file per candidate, including an ERROR file
# when one side of the pair is missing, so CI failures still leave inspectable
# artifacts.
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

RESULTS="${1:-benchmark/results}"
SUMMARY="$RESULTS/summary.tsv"

mkdir -p "$RESULTS/residuals"
names=()
add_name() {
  local candidate="$1"
  local existing
  [ -n "$candidate" ] || return 0
  if [ "${#names[@]}" -gt 0 ]; then
    for existing in "${names[@]}"; do
      [ "$existing" = "$candidate" ] && return 0
    done
  fi
  names+=("$candidate")
}

if [ -e "$SUMMARY" ]; then
  while IFS=$'\t' read -r name _; do
    [ "$name" = "file" ] && continue
    add_name "$name"
  done < "$SUMMARY"
else
  echo "warning: no summary at $SUMMARY; inferring residual candidates from AGAT outputs" >&2
fi
shopt -s nullglob
for agat in "$RESULTS"/*.agat.gtf; do
  add_name "$(basename "$agat" .agat.gtf)"
done
shopt -u nullglob

if [ "${#names[@]}" -eq 0 ]; then
  echo "ERROR no residual candidates found" > "$RESULTS/residuals/_error.txt"
  exit 0
fi

for name in "${names[@]}"; do
  agat="$RESULTS/${name}.agat.gtf"
  gxf="$RESULTS/${name}.gxfkit.gtf"
  if [ ! -e "$agat" ] || [ ! -e "$gxf" ]; then
    {
      echo "ERROR missing GTF output for $name"
      [ -e "$agat" ] || echo "missing: $agat"
      [ -e "$gxf" ] || echo "missing: $gxf"
    } > "$RESULTS/residuals/${name}.txt"
    continue
  fi
  "$PY" tests/parity/residual_summary.py "$agat" "$gxf" \
    > "$RESULTS/residuals/${name}.txt"
done
