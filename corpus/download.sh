#!/usr/bin/env bash
# Download a small, reproducible, public GFF3 corpus for parity + benchmarking.
#
# Files are pinned to a specific Ensembl release so results are reproducible.
# Large/derived files are git-ignored; only this script is tracked.
#
# Usage:
#   bash corpus/download.sh          # everything (local stress testing)
#   bash corpus/download.sh core     # only the CI-gated, parity-guaranteed set
#
# The "core" set is the Ensembl files gxfkit reaches full parity on (used by the
# CI parity gate). The rest are larger / different-convention stress files
# (NCBI RefSeq, etc.) that exercise known divergences — see docs/PARITY.md.
set -euo pipefail

WHICH="${1:-all}"
REL=110
BASE="https://ftp.ensembl.org/pub/release-${REL}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW="$DIR/raw"
mkdir -p "$RAW"

CORE=" yeast human_chr21 human_chr1 "  # space-delimited membership test

# tier|name|url
# A spread of providers/conventions on purpose: Ensembl (gene:/transcript: ID
# prefixes) AND NCBI RefSeq (gene-/rna-/cds- IDs, Dbxref, different attribute
# style) so parity is tested beyond a single annotation dialect.
ENTRIES=(
  # Ensembl
  "small|yeast|${BASE}/gff3/saccharomyces_cerevisiae/Saccharomyces_cerevisiae.R64-1-1.${REL}.gff3.gz"
  "medium|human_chr21|${BASE}/gff3/homo_sapiens/Homo_sapiens.GRCh38.${REL}.chromosome.21.gff3.gz"
  "medium|human_chr1|${BASE}/gff3/homo_sapiens/Homo_sapiens.GRCh38.${REL}.chromosome.1.gff3.gz"
  "medium|drosophila|${BASE}/gff3/drosophila_melanogaster/Drosophila_melanogaster.BDGP6.46.${REL}.gff3.gz"
  # NCBI RefSeq (different ID/attribute conventions)
  "small|ecoli_refseq|https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.gff.gz"
  "large|arabidopsis_refseq|https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/735/GCF_000001735.4_TAIR10.1/GCF_000001735.4_TAIR10.1_genomic.gff.gz"
)

for e in "${ENTRIES[@]}"; do
  IFS='|' read -r tier name url <<<"$e"
  if [[ "$WHICH" == "core" && "$CORE" != *" $name "* ]]; then
    continue
  fi
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
