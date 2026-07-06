#!/usr/bin/env bash
# Verify the local cargo-install path used by source users and the Bioconda recipe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CARGO_BIN="${CARGO:-cargo}"
if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
  else
    echo "cargo not found on PATH and $HOME/.cargo/bin/cargo is missing" >&2
    exit 127
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

network="${VERIFY_LOCAL_CARGO_INSTALL_NETWORK:-1}"
if [ "$network" != 0 ] && [ "$network" != 1 ]; then
  echo "VERIFY_LOCAL_CARGO_INSTALL_NETWORK must be 0 or 1, got: $network" >&2
  exit 2
fi

install_args=(install --locked --no-track --root "$tmp/root" --path crates/gxfkit)
if [ "$network" = 0 ]; then
  install_args+=(--offline)
fi

"$CARGO_BIN" "${install_args[@]}"
bin="$tmp/root/bin/gxfkit"
if [ ! -x "$bin" ]; then
  echo "installed gxfkit binary is missing or not executable: $bin" >&2
  exit 1
fi

"$bin" version
cat >"$tmp/smoke.gff3" <<'GFF'
##gff-version 3
chr1	src	gene	1	100	.	+	.	ID=gene:g1
chr1	src	mRNA	1	100	.	+	.	ID=transcript:t1;Parent=gene:g1
chr1	src	exon	1	50	.	+	.	Parent=transcript:t1;exon_id=e1
GFF
"$bin" gff2gtf -g "$tmp/smoke.gff3" -o "$tmp/smoke.gtf"
grep 'gene_id "g1"; transcript_id "t1";' "$tmp/smoke.gtf" >/dev/null

echo "verified local cargo install"
