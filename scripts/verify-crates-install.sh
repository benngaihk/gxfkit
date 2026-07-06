#!/usr/bin/env bash
# Verify the Crates.io install path once gxfkit has been published.
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

version="${VERSION:-}"
if [ -z "$version" ]; then
  version="$("$PY" - <<'PY'
from pathlib import Path
import re

text = Path("Cargo.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version = "([^"]+)"$', text)
if not match:
    raise SystemExit("missing workspace version")
print(match.group(1))
PY
)"
fi

dry_run="${VERIFY_CRATES_INSTALL_DRY_RUN:-0}"
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERSION must look like X.Y.Z, got: $version" >&2
  exit 2
fi
case "$dry_run" in
  0 | 1) ;;
  *)
    echo "VERIFY_CRATES_INSTALL_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac

CARGO_BIN="${CARGO:-cargo}"
if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
  else
    echo "cargo not found on PATH and $HOME/.cargo/bin/cargo is missing" >&2
    exit 127
  fi
fi

if [ "$dry_run" = 1 ]; then
  printf 'version=%s\n' "$version"
  printf 'command=%q install --locked --root ROOT --version %q --registry crates-io gxfkit\n' \
    "$CARGO_BIN" "$version"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$CARGO_BIN" install \
  --locked \
  --root "$tmp/root" \
  --version "$version" \
  --registry crates-io \
  gxfkit

bin="$tmp/root/bin/gxfkit"
if [ ! -x "$bin" ]; then
  echo "installed gxfkit binary is missing or not executable: $bin" >&2
  exit 1
fi

version_output="$("$bin" version)"
if [ "$version_output" != "gxfkit $version" ]; then
  echo "installed gxfkit version mismatch: expected gxfkit $version, got: $version_output" >&2
  exit 1
fi
echo "$version_output"
cat >"$tmp/smoke.gff3" <<'GFF'
##gff-version 3
chr1	src	gene	1	100	.	+	.	ID=gene:g1
chr1	src	mRNA	1	100	.	+	.	ID=transcript:t1;Parent=gene:g1
chr1	src	exon	1	50	.	+	.	Parent=transcript:t1;exon_id=e1
GFF
"$bin" gff2gtf -g "$tmp/smoke.gff3" -o "$tmp/smoke.gtf"
grep 'gene_id "g1"; transcript_id "t1";' "$tmp/smoke.gtf" >/dev/null
if "$bin" gff2gtf -g "$tmp/smoke.gff3" -o "$tmp/smoke.gtf" 2>"$tmp/overwrite.err"; then
  echo "gxfkit unexpectedly overwrote smoke.gtf" >&2
  exit 1
fi
grep 'refusing to overwrite' "$tmp/overwrite.err" >/dev/null

echo "verified Crates.io install for gxfkit $version"
