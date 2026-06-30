#!/usr/bin/env bash
# One command to reproduce the whole gxfkit-vs-AGAT comparison.
#
#   bash benchmark/run.sh
#
# Container side (bench.sh): builds gxfkit for Linux, runs AGAT + gxfkit +
# emits GTF outputs + metrics.tsv (best-of-N cold-run wall + memory).
# Host side (summarize.py): computes parity via the normalizer and assembles the
# summary table (host python; the AGAT image has none). Requires Docker + python.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1

PY="${PYTHON:-python}"
RESULTS="$ROOT/benchmark/results"

if [ ! -d corpus/raw ] || [ -z "$(ls -A corpus/raw/*.gff3 2>/dev/null)" ]; then
  echo "No corpus found. Running corpus/download.sh ..."
  bash corpus/download.sh
fi

echo ">> Building benchmark image (compiles gxfkit for Linux)..."
docker build -f benchmark/Dockerfile -t gxfkit-bench .

echo ">> Running in-container measurement..."
mkdir -p "$RESULTS"
# `pwd -W` gives a Windows path for Docker on git-bash; falls back to PWD elsewhere.
hostroot="$(pwd -W 2>/dev/null || pwd)"
docker run --rm \
  -v "$hostroot/corpus/raw:/corpus:ro" \
  -v "$hostroot/benchmark/results:/work/results" \
  -e RUNS="${RUNS:-5}" \
  gxfkit-bench

echo ">> Computing parity + assembling summary (host python)..."
# Pass relative paths so a native-Windows python (under git-bash) resolves them.
"$PY" benchmark/summarize.py benchmark/results tests/parity/normalize.py README.md

echo ">> Done. See benchmark/results/summary.tsv and the README benchmark table."
