#!/usr/bin/env bash
# One command to reproduce the whole gxfkit-vs-AGAT comparison.
#
#   bash benchmark/run.sh
#
# Optional env:
#   BENCH_PLATFORM=linux/amd64  Docker platform for AGAT+gxfkit image
#   BENCH_FILES="ecoli_refseq"  space-separated basenames to run
#   README_OUT=                skip README benchmark-table injection
#
# Container side (bench.sh): builds gxfkit for Linux, runs AGAT + gxfkit +
# emits GTF outputs + metrics.tsv (best-of-N cold-run wall + memory).
# Host side (summarize.py): computes parity via the normalizer and assembles the
# summary table (host python; the AGAT image has none). Requires Docker + Python.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python >/dev/null 2>&1; then
    PY=python
  else
    PY=python3
  fi
fi
RESULTS="$ROOT/benchmark/results"
README_OUT="${README_OUT-README.md}"
# AGAT 1.7.0's biocontainer is linux/amd64. Pin the whole benchmark image to
# that platform so Docker Desktop on Apple Silicon does not build an arm64
# gxfkit binary and copy it into an amd64 AGAT runtime image.
BENCH_PLATFORM="${BENCH_PLATFORM:-linux/amd64}"

if [ ! -d corpus/raw ] || [ -z "$(ls -A corpus/raw/*.gff3 2>/dev/null)" ]; then
  echo "No corpus found. Running corpus/download.sh ..."
  bash corpus/download.sh
fi

echo ">> Building benchmark image for $BENCH_PLATFORM (compiles gxfkit for Linux)..."
docker build --platform "$BENCH_PLATFORM" -f benchmark/Dockerfile -t gxfkit-bench .

echo ">> Running in-container measurement..."
mkdir -p "$RESULTS"
# `pwd -W` gives a Windows path for Docker on git-bash; falls back to PWD elsewhere.
hostroot="$(pwd -W 2>/dev/null || pwd)"
docker run --rm \
  --platform "$BENCH_PLATFORM" \
  -v "$hostroot/corpus/raw:/corpus:ro" \
  -v "$hostroot/benchmark/results:/work/results" \
  -e RUNS="${RUNS:-5}" \
  -e BENCH_FILES="${BENCH_FILES:-}" \
  gxfkit-bench

echo ">> Computing parity + assembling summary (host python)..."
# Pass relative paths so a native-Windows python (under git-bash) resolves them.
if [ -n "$README_OUT" ]; then
  "$PY" benchmark/summarize.py benchmark/results tests/parity/normalize.py "$README_OUT"
else
  "$PY" benchmark/summarize.py benchmark/results tests/parity/normalize.py
fi

echo ">> Writing residual diagnostics..."
PYTHON="$PY" bash benchmark/write-residuals.sh benchmark/results

if [ -n "$README_OUT" ]; then
  echo ">> Done. See benchmark/results/summary.tsv, residual diagnostics, and the README benchmark table."
else
  echo ">> Done. See benchmark/results/summary.tsv and residual diagnostics."
fi
