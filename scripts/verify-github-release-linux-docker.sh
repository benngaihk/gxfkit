#!/usr/bin/env bash
# Verify the published Linux static GitHub Release archive in a clean container.
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

workspace_version="$("$PY" - <<'PY'
from pathlib import Path
import re

text = Path("Cargo.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version = "([^"]+)"$', text)
if not match:
    raise SystemExit("missing workspace version")
print(match.group(1))
PY
)"

repo="${GITHUB_RELEASE_REPOSITORY:-benngaihk/gxfkit}"
tag="${RELEASE_TAG:-v$workspace_version}"
package="${PACKAGE:-linux-x86_64-static}"
image="${VERIFY_GITHUB_RELEASE_LINUX_IMAGE:-alpine:3.20}"
platform="${VERIFY_GITHUB_RELEASE_LINUX_PLATFORM:-linux/amd64}"
dry_run="${VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN:-0}"
verify_no_overwrite="${VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE:-0}"

case "$tag" in
  v*) ;;
  *)
    echo "release tag must start with v, got: $tag" >&2
    exit 2
    ;;
esac
case "$package" in
  linux-x86_64-static | linux-aarch64-static) ;;
  *)
    echo "PACKAGE must be a Linux static release package, got: $package" >&2
    exit 2
    ;;
esac
case "$dry_run" in
  0 | 1) ;;
  *)
    echo "VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac
case "$verify_no_overwrite" in
  0 | 1) ;;
  *)
    echo "VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE must be 0 or 1, got: $verify_no_overwrite" >&2
    exit 2
    ;;
esac

name="gxfkit-${tag}-${package}"
base_url="https://github.com/${repo}/releases/download/${tag}"
archive_url="${base_url}/${name}.tar.gz"
checksum_url="${archive_url}.sha256"

if [ "$dry_run" = 1 ]; then
  printf 'image=%s\n' "$image"
  printf 'platform=%s\n' "$platform"
  printf 'repo=%s\n' "$repo"
  printf 'tag=%s\n' "$tag"
  printf 'package=%s\n' "$package"
  printf 'verify_no_overwrite=%s\n' "$verify_no_overwrite"
  printf 'archive_verifier=%s\n' "/opt/gxfkit/scripts/verify-release-archive.sh"
  printf 'archive=%s\n' "$archive_url"
  printf 'checksum=%s\n' "$checksum_url"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for clean Linux release verification" >&2
  exit 127
fi

docker run --rm --platform "$platform" \
  -v "$ROOT/scripts:/opt/gxfkit/scripts:ro" \
  -e ARCHIVE_URL="$archive_url" \
  -e CHECKSUM_URL="$checksum_url" \
  -e ARCHIVE_NAME="${name}.tar.gz" \
  -e ROOT_DIR="$name" \
  -e RELEASE_VERSION="${tag#v}" \
  -e VERIFY_NO_OVERWRITE="$verify_no_overwrite" \
  "$image" \
  sh -eu -c '
    apk add --no-cache bash ca-certificates curl python3 tar >/dev/null
    mkdir -p /tmp/gxfkit-release
    cd /tmp/gxfkit-release
    download() {
      curl --http1.1 \
        --fail \
        --show-error \
        --no-progress-meter \
        --location \
        --retry 10 \
        --retry-all-errors \
        --retry-delay 2 \
        --retry-max-time 300 \
        --connect-timeout 30 \
        "$1" \
        -o "$2"
    }
    download "$ARCHIVE_URL" "$ARCHIVE_NAME"
    download "$CHECKSUM_URL" "$ARCHIVE_NAME.sha256"
    VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION="$RELEASE_VERSION" \
      VERIFY_RELEASE_ARCHIVE_SMOKE=0 \
      bash /opt/gxfkit/scripts/verify-release-archive.sh "$ARCHIVE_NAME"
    tar -xzf "$ARCHIVE_NAME"
    test -x "$ROOT_DIR/gxfkit"
    version="$("$ROOT_DIR/gxfkit" version)"
    test "$version" = "gxfkit $RELEASE_VERSION"
    echo "$version"
    cat > smoke.gff3 <<'"'"'GFF'"'"'
##gff-version 3
chr1	src	gene	1	100	.	+	.	ID=gene:g1
chr1	src	mRNA	1	100	.	+	.	ID=transcript:t1;Parent=gene:g1
chr1	src	exon	1	50	.	+	.	Parent=transcript:t1;exon_id=e1
GFF
    "$ROOT_DIR/gxfkit" gff2gtf -g smoke.gff3 -o smoke.gtf
    grep '"'"'gene_id "g1"; transcript_id "t1";'"'"' smoke.gtf >/dev/null
    if [ "$VERIFY_NO_OVERWRITE" = 1 ]; then
      if "$ROOT_DIR/gxfkit" gff2gtf -g smoke.gff3 -o smoke.gtf 2> overwrite.err; then
        echo "gxfkit unexpectedly overwrote smoke.gtf" >&2
        exit 1
      fi
      grep "refusing to overwrite" overwrite.err >/dev/null
    fi
  '

echo "verified clean Linux GitHub release install for $name"
