#!/usr/bin/env bash
# Pinned AGAT-vs-gxfkit fixture parity for the experimental M3 gxf2gxf path.
#
# The fixtures are intentionally tiny and exact-diffed byte-for-byte. This is
# not a broad corpus benchmark; it is the first standardization regression gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MSYS_NO_PATHCONV=1

BENCH_PLATFORM="${BENCH_PLATFORM:-linux/amd64}"
IMAGE="${GXF2GXF_BENCH_IMAGE:-gxfkit-bench}"
FIXTURES="$ROOT/benchmark/gxf2gxf-fixtures"
RESULTS="$ROOT/benchmark/gxf2gxf-results"

if [ ! -d "$FIXTURES" ] || [ -z "$(find "$FIXTURES" -name '*.gff3' -print -quit)" ]; then
  echo "no gxf2gxf fixtures found at $FIXTURES" >&2
  exit 1
fi

if [ "${GXF2GXF_SKIP_DOCKER_BUILD:-0}" != 1 ]; then
  docker build --platform "$BENCH_PLATFORM" -f benchmark/Dockerfile -t "$IMAGE" .
fi

rm -rf "$RESULTS"
mkdir -p "$RESULTS"
hostroot="$(pwd -W 2>/dev/null || pwd)"

docker run --rm \
  --platform "$BENCH_PLATFORM" \
  --entrypoint bash \
  -v "$hostroot/benchmark/gxf2gxf-fixtures:/fixtures:ro" \
  -v "$hostroot/benchmark/gxf2gxf-results:/results" \
  "$IMAGE" -lc '
    set -euo pipefail
    cd /tmp
    for fixture in /fixtures/*.gff3; do
      name=$(basename "$fixture" .gff3)
      agat="/results/${name}.agat.gff3"
      gxfkit_out="/results/${name}.gxfkit.gff3"
      agat_convert_sp_gxf2gxf.pl -g "$fixture" -o "$agat" >"/results/${name}.agat.log" 2>"/results/${name}.agat.err"
      gxfkit gxf2gxf -g "$fixture" -o "$gxfkit_out"
      diff -u "$agat" "$gxfkit_out" >"/results/${name}.diff"
      if [ -s "/results/${name}.diff" ]; then
        cat "/results/${name}.diff"
        exit 1
      fi
      echo "gxf2gxf fixture ok: $name"
    done
  '

echo "gxf2gxf fixture parity passed"
