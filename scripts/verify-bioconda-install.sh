#!/usr/bin/env bash
# Verify the Bioconda install path once the recipe has been merged and uploaded.
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

image="${VERIFY_BIOCONDA_IMAGE:-mambaorg/micromamba:1.5.10}"
platform="${VERIFY_BIOCONDA_PLATFORM:-linux/amd64}"
dry_run="${VERIFY_BIOCONDA_INSTALL_DRY_RUN:-0}"
verify_no_overwrite="${VERIFY_BIOCONDA_NO_OVERWRITE:-1}"

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERSION must look like X.Y.Z, got: $version" >&2
  exit 2
fi
case "$dry_run" in
  0 | 1) ;;
  *)
    echo "VERIFY_BIOCONDA_INSTALL_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac
case "$verify_no_overwrite" in
  0 | 1) ;;
  *)
    echo "VERIFY_BIOCONDA_NO_OVERWRITE must be 0 or 1, got: $verify_no_overwrite" >&2
    exit 2
    ;;
esac

if [ "$dry_run" = 1 ]; then
  printf 'version=%s\n' "$version"
  printf 'image=%s\n' "$image"
  printf 'platform=%s\n' "$platform"
  printf 'channels=conda-forge,bioconda\n'
  printf 'verify_no_overwrite=%s\n' "$verify_no_overwrite"
  printf 'install=gxfkit=%s\n' "$version"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for clean Bioconda install verification" >&2
  exit 127
fi

docker run --rm --platform "$platform" \
  --entrypoint /bin/bash \
  -e VERSION="$version" \
  -e VERIFY_NO_OVERWRITE="$verify_no_overwrite" \
  "$image" \
  -lc '
    set -euo pipefail
    micromamba install -y -n base -c conda-forge -c bioconda "gxfkit=${VERSION}"
    version="$(micromamba run -n base gxfkit version)"
    test "$version" = "gxfkit $VERSION"
    echo "$version"
    cat > /tmp/smoke.gff3 <<'"'"'GFF'"'"'
##gff-version 3
chr1	src	gene	1	100	.	+	.	ID=gene:g1
chr1	src	mRNA	1	100	.	+	.	ID=transcript:t1;Parent=gene:g1
chr1	src	exon	1	50	.	+	.	Parent=transcript:t1;exon_id=e1
GFF
    micromamba run -n base gxfkit gff2gtf -g /tmp/smoke.gff3 -o /tmp/smoke.gtf
    grep '"'"'gene_id "g1"; transcript_id "t1";'"'"' /tmp/smoke.gtf >/dev/null
    if [ "$VERIFY_NO_OVERWRITE" = 1 ]; then
      if micromamba run -n base gxfkit gff2gtf -g /tmp/smoke.gff3 -o /tmp/smoke.gtf 2> /tmp/overwrite.err; then
        echo "gxfkit unexpectedly overwrote smoke.gtf" >&2
        exit 1
      fi
      grep "refusing to overwrite" /tmp/overwrite.err >/dev/null
    fi
  '

echo "verified Bioconda install for gxfkit $version"
