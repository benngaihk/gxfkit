#!/usr/bin/env bash
# Download a GitHub Release archive for this host and verify it like a user.
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
download_dir="${DOWNLOAD_DIR:-}"
dry_run="${VERIFY_GITHUB_RELEASE_DRY_RUN:-0}"
verify_no_overwrite="${VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE:-1}"
release_archive="${RELEASE_ARCHIVE:-}"
release_checksum="${RELEASE_CHECKSUM:-}"

detect_package() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Darwin:arm64) echo "macos-aarch64" ;;
    Darwin:x86_64) echo "macos-x86_64" ;;
    Linux:x86_64) echo "linux-x86_64-static" ;;
    Linux:aarch64 | Linux:arm64) echo "linux-aarch64-static" ;;
    *)
      echo "unsupported host for native release smoke: $os $arch" >&2
      echo "set PACKAGE and VERIFY_RELEASE_ARCHIVE_SMOKE=0 to do a structure-only check" >&2
      return 1
      ;;
  esac
}

package="${PACKAGE:-$(detect_package)}"
case "$tag" in
  v*) ;;
  *)
    echo "release tag must start with v, got: $tag" >&2
    exit 2
    ;;
esac
case "$package" in
  linux-x86_64-static | linux-aarch64-static | macos-x86_64 | macos-aarch64) ;;
  *)
    echo "PACKAGE must be a known release package, got: $package" >&2
    exit 2
    ;;
esac
case "$dry_run" in
  0 | 1) ;;
  *)
    echo "VERIFY_GITHUB_RELEASE_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac
case "$verify_no_overwrite" in
  0 | 1) ;;
  *)
    echo "VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE must be 0 or 1, got: $verify_no_overwrite" >&2
    exit 2
    ;;
esac

name="gxfkit-${tag}-${package}"
base_url="https://github.com/${repo}/releases/download/${tag}"
archive_url="${base_url}/${name}.tar.gz"
checksum_url="${archive_url}.sha256"

if [ "$dry_run" = 1 ]; then
  printf 'repo=%s\n' "$repo"
  printf 'tag=%s\n' "$tag"
  printf 'package=%s\n' "$package"
  printf 'download_dir=%s\n' "$download_dir"
  printf 'verify_no_overwrite=%s\n' "$verify_no_overwrite"
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

tmp=""
if [ -n "$release_archive" ]; then
  if [ ! -s "$release_archive" ]; then
    echo "RELEASE_ARCHIVE does not exist or is empty: $release_archive" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  cleanup_download_dir=1
  download_dir="$tmp"
elif [ -z "$download_dir" ]; then
  download_dir="$(mktemp -d)"
  cleanup_download_dir=1
else
  cleanup_download_dir=0
  mkdir -p "$download_dir"
fi
trap '[ "${cleanup_download_dir:-0}" = 1 ] && rm -rf "$download_dir"' EXIT

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
VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE="$verify_no_overwrite" \
  bash scripts/verify-release-archive.sh "$archive"
