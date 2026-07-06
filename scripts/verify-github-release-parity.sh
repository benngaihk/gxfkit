#!/usr/bin/env bash
# Verify a published GitHub Release binary against AGAT on a small corpus slice.
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
platform="${BENCH_PLATFORM:-linux/amd64}"
agat_image="${AGAT_IMAGE:-quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0}"
bench_files="${BENCH_FILES:-yeast}"
dry_run="${VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN:-0}"
min_parity="${MIN_PARITY:-100}"
download_dir="${DOWNLOAD_DIR:-}"
release_archive="${RELEASE_ARCHIVE:-}"
release_checksum="${RELEASE_CHECKSUM:-}"

validate_min_parity() {
  "$PY" - "$min_parity" <<'PY'
import sys

value = sys.argv[1]
try:
    parsed = float(value)
except ValueError:
    raise SystemExit(f"MIN_PARITY must be a number, got: {value}")
if not 0 <= parsed <= 100:
    raise SystemExit(f"MIN_PARITY must be between 0 and 100, got: {value}")
PY
}

validate_bench_files() {
  local item
  local count=0
  local seen=" "
  set -f
  for item in $bench_files; do
    count=$((count + 1))
    case "$item" in
      *[!A-Za-z0-9._-]* | . | ..)
        echo "BENCH_FILES entries must be corpus basenames, got: $item" >&2
        exit 2
        ;;
    esac
    case "$seen" in
      *" $item "*)
        echo "duplicate BENCH_FILES entry: $item" >&2
        exit 2
        ;;
    esac
    seen="${seen}${item} "
  done
  set +f
  if [ "$count" -eq 0 ]; then
    echo "BENCH_FILES must include at least one corpus name" >&2
    exit 2
  fi
}

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
    echo "VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac
validate_bench_files
validate_min_parity

name="gxfkit-${tag}-${package}"
base_url="https://github.com/${repo}/releases/download/${tag}"
archive_url="${base_url}/${name}.tar.gz"
checksum_url="${archive_url}.sha256"

if [ "$dry_run" = 1 ]; then
  printf 'repo=%s\n' "$repo"
  printf 'tag=%s\n' "$tag"
  printf 'package=%s\n' "$package"
  printf 'platform=%s\n' "$platform"
  printf 'agat_image=%s\n' "$agat_image"
  printf 'bench_files=%s\n' "$bench_files"
  printf 'min_parity=%s\n' "$min_parity"
  printf 'download_dir=%s\n' "$download_dir"
  printf 'release_archive=%s\n' "$release_archive"
  printf 'release_checksum=%s\n' "$release_checksum"
  printf 'archive=%s\n' "$archive_url"
  printf 'checksum=%s\n' "$checksum_url"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download GitHub release artifacts" >&2
  exit 127
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for AGAT parity verification" >&2
  exit 127
fi
if [ ! -d corpus/raw ] || [ -z "$(ls -A corpus/raw/*.gff3 2>/dev/null)" ]; then
  echo "No corpus found. Running corpus/download.sh core ..."
  bash corpus/download.sh core
fi

tmp="$(mktemp -d)"
cleanup_download_dir=0
if [ -z "$download_dir" ]; then
  download_dir="$tmp/download"
  cleanup_download_dir=1
fi
mkdir -p "$download_dir"
trap '[ "$cleanup_download_dir" = 1 ] && rm -rf "$download_dir"; rm -rf "$tmp"' EXIT

archive="$download_dir/${name}.tar.gz"
checksum="$archive.sha256"

checksum_ok() {
  local checksum_file="$1"
  local checksum_dir checksum_name
  checksum_dir="$(cd "$(dirname "$checksum_file")" && pwd)"
  checksum_name="$(basename "$checksum_file")"
  if command -v shasum >/dev/null 2>&1; then
    (cd "$checksum_dir" && shasum -a 256 -c "$checksum_name") >/dev/null 2>&1
  elif command -v sha256sum >/dev/null 2>&1; then
    (cd "$checksum_dir" && sha256sum -c "$checksum_name") >/dev/null 2>&1
  else
    return 127
  fi
}

download() {
  local url="$1" output="$2"
  curl --http1.1 \
    --fail \
    --show-error \
    --no-progress-meter \
    --location \
    --continue-at - \
    --retry 10 \
    --retry-all-errors \
    --retry-delay 2 \
    --retry-max-time 300 \
    --connect-timeout 30 \
    "$url" \
    -o "$output"
}

if [ -n "$release_archive" ]; then
  if [ ! -s "$release_archive" ]; then
    echo "RELEASE_ARCHIVE does not exist or is empty: $release_archive" >&2
    exit 1
  fi
  cp "$release_archive" "$archive"
  if [ -n "$release_checksum" ]; then
    if [ ! -s "$release_checksum" ]; then
      echo "RELEASE_CHECKSUM does not exist or is empty: $release_checksum" >&2
      exit 1
    fi
    cp "$release_checksum" "$checksum"
  elif [ -s "$release_archive.sha256" ]; then
    cp "$release_archive.sha256" "$checksum"
  else
    echo ">> downloading $checksum_url"
    download "$checksum_url" "$checksum"
  fi
else
  if [ ! -s "$checksum" ]; then
    echo ">> downloading $checksum_url"
    download "$checksum_url" "$checksum"
  fi
  if [ -s "$archive" ] && checksum_ok "$checksum"; then
    echo ">> reusing verified archive $archive"
  else
    rm -f "$archive"
    echo ">> downloading $archive_url"
    download "$archive_url" "$archive"
  fi
fi

VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION="${tag#v}" \
  VERIFY_RELEASE_ARCHIVE_SMOKE=0 \
  bash scripts/verify-release-archive.sh "$archive"
tar -xzf "$archive" -C "$tmp"
bin="$tmp/$name/gxfkit"
if [ ! -x "$bin" ]; then
  echo "release archive does not contain an executable gxfkit: $bin" >&2
  exit 1
fi

mkdir -p "$tmp/results"
hostroot="$(pwd -W 2>/dev/null || pwd)"
hosttmp="$(cd "$tmp" && pwd)"

docker run --rm \
  --platform "$platform" \
  --user 0:0 \
  -v "$hostroot/corpus/raw:/corpus:ro" \
  -v "$hosttmp/results:/results" \
  -v "$bin:/usr/local/bin/gxfkit:ro" \
  -e BENCH_FILES="$bench_files" \
  "$agat_image" \
  bash -lc '
    set -euo pipefail
    mkdir -p /tmp/agat-work
    cd /tmp/agat-work
    for name in $BENCH_FILES; do
      input="/corpus/${name}.gff3"
      test -f "$input"
      rm -f "/results/${name}.agat.gtf" "/results/${name}.gxfkit.gtf"
      rm -rf agat_log_* 2>/dev/null
      agat_convert_sp_gff2gtf.pl -i "$input" -o "/results/${name}.agat.gtf" >/dev/null
      gxfkit gff2gtf -i "$input" -o "/results/${name}.gxfkit.gtf" >/dev/null
    done
  '

cat >"$tmp/results/metrics.tsv" <<EOF
file	agat_wall_s	agat_mem_kb	gxfkit_wall_s	gxfkit_mem_kb
EOF
set -f
for name in $bench_files; do
  printf '%s\t1.00\t1\t1.00\t1\n' "$name" >>"$tmp/results/metrics.tsv"
done
set +f

MIN_PARITY="$min_parity" "$PY" benchmark/summarize.py "$tmp/results" tests/parity/normalize.py >/dev/null
echo "verified GitHub release parity for $name on: $bench_files"
