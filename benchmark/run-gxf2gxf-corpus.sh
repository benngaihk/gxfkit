#!/usr/bin/env bash
# Run AGAT-vs-gxfkit gxf2gxf on corpus files and write residual diagnostics.
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

BENCH_PLATFORM="${BENCH_PLATFORM:-linux/amd64}"
IMAGE="${GXF2GXF_BENCH_IMAGE:-gxfkit-bench}"
RESULTS="$ROOT/benchmark/gxf2gxf-corpus-results"

if [ ! -d corpus/raw ] || [ -z "$(find corpus/raw -name '*.gff3' -print -quit)" ]; then
  echo "No corpus found. Running corpus/download.sh ..."
  bash corpus/download.sh
fi

if [ "${GXF2GXF_SKIP_DOCKER_BUILD:-0}" != 1 ]; then
  docker build --platform "$BENCH_PLATFORM" -f benchmark/Dockerfile -t "$IMAGE" .
fi

rm -rf "$RESULTS"
mkdir -p "$RESULTS"
hostroot="$(pwd -W 2>/dev/null || pwd)"

if [ -n "${GXF2GXF_CORPUS_FILES:-}" ]; then
  corpus_files="$GXF2GXF_CORPUS_FILES"
else
  corpus_files="$(find corpus/raw -maxdepth 1 -name '*.gff3' -exec basename {} .gff3 \; | sort | tr '\n' ' ')"
fi

docker run --rm \
  --platform "$BENCH_PLATFORM" \
  --entrypoint bash \
  -v "$hostroot/corpus/raw:/corpus:ro" \
  -v "$hostroot/benchmark/gxf2gxf-corpus-results:/results" \
  "$IMAGE" -lc "
    set -euo pipefail
    for name in $corpus_files; do
      input=\"/corpus/\${name}.gff3\"
      if [ ! -f \"\$input\" ]; then
        echo \"missing corpus file: \$input\" >&2
        exit 1
      fi
      echo \">> gxf2gxf corpus: \$name\"
      agat_convert_sp_gxf2gxf.pl -g \"\$input\" -o \"/results/\${name}.agat.gff3\" >\"/results/\${name}.agat.log\" 2>\"/results/\${name}.agat.err\"
      gxfkit gxf2gxf -g \"\$input\" -o \"/results/\${name}.gxfkit.gff3\" >\"/results/\${name}.gxfkit.log\" 2>\"/results/\${name}.gxfkit.err\"
    done
  "

printf 'file\tlines_a\tlines_b\tmatched\tonly_a\tonly_b\tparity\n' >"$RESULTS/summary.tsv"
for name in $corpus_files; do
  "$PY" tests/parity/gff3_residual_summary.py \
    "$RESULTS/${name}.agat.gff3" \
    "$RESULTS/${name}.gxfkit.gff3" \
    >"$RESULTS/${name}.summary.txt"
  summary_line="$(sed -n '1p' "$RESULTS/${name}.summary.txt")"
  "$PY" - "$name" "$summary_line" >>"$RESULTS/summary.tsv" <<'PY'
import sys

name = sys.argv[1]
fields = {}
for part in sys.argv[2].split("\t")[1:]:
    key, value = part.split("=", 1)
    fields[key] = value.rstrip("%")
print(
    "\t".join(
        [
            name,
            fields["lines_a"],
            fields["lines_b"],
            fields["matched"],
            fields["only_a"],
            fields["only_b"],
            fields["parity"],
        ]
    )
)
PY
done

echo "gxf2gxf corpus residuals written to $RESULTS"
