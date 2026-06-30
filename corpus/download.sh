#!/usr/bin/env bash
# Download a small, reproducible, public GFF3 corpus for parity + benchmarking.
#
# Files are pinned to a specific Ensembl release so results are reproducible.
# Large/derived files are git-ignored (see corpus/.gitignore); only this script
# and the manifest are tracked.
#
# Usage:  bash corpus/download.sh
set -euo pipefail

REL=110
BASE="https://ftp.ensembl.org/pub/release-${REL}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW="$DIR/raw"
mkdir -p "$RAW"

# tier|name|url
ENTRIES=(
  "small|yeast|${BASE}/gff3/saccharomyces_cerevisiae/Saccharomyces_cerevisiae.R64-1-1.${REL}.gff3.gz"
  "medium|human_chr21|${BASE}/gff3/homo_sapiens/Homo_sapiens.GRCh38.${REL}.chromosome.21.gff3.gz"
  "medium|human_chr1|${BASE}/gff3/homo_sapiens/Homo_sapiens.GRCh38.${REL}.chromosome.1.gff3.gz"
)

for e in "${ENTRIES[@]}"; do
  IFS='|' read -r tier name url <<<"$e"
  gz="$RAW/${name}.gff3.gz"
  out="$RAW/${name}.gff3"
  if [[ -f "$out" ]]; then
    echo "[skip] $name (already present)"
    continue
  fi
  echo "[get ] $tier/$name <- $url"
  curl -fSL --retry 3 --max-time 600 -o "$gz" "$url"
  gunzip -kf "$gz"
  rm -f "$gz"
  lines=$(wc -l <"$out")
  echo "       -> $out ($lines lines)"
done

echo "Done. Corpus in $RAW"
