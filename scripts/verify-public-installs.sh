#!/usr/bin/env bash
# Verify public install channels after release propagation.
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

tag="${RELEASE_TAG:-v$version}"
channels="${VERIFY_PUBLIC_INSTALL_CHANNELS:-github-linux github-parity bioconda crates}"
dry_run="${VERIFY_PUBLIC_INSTALLS_DRY_RUN:-0}"
allow_missing_crates="${VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES:-0}"
verify_no_overwrite="${VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE:-1}"
min_parity="${VERIFY_PUBLIC_INSTALLS_MIN_PARITY:-${MIN_PARITY:-100}}"
bench_files="${BENCH_FILES:-human_chr1 human_chr21 yeast}"
crates_install_script="${VERIFY_CRATES_INSTALL_SCRIPT:-scripts/verify-crates-install.sh}"

validate_min_parity() {
  "$PY" - "$min_parity" <<'PY'
import sys

value = sys.argv[1]
try:
    parsed = float(value)
except ValueError:
    raise SystemExit(f"VERIFY_PUBLIC_INSTALLS_MIN_PARITY must be a number, got: {value}")
if not 0 <= parsed <= 100:
    raise SystemExit(
        "VERIFY_PUBLIC_INSTALLS_MIN_PARITY must be between 0 and 100, "
        f"got: {value}"
    )
PY
}

validate_channels() {
  local channel
  local count=0
  local seen=" "
  set -f
  for channel in $channels; do
    count=$((count + 1))
    case "$channel" in
      github-linux | github-parity | bioconda | crates) ;;
      *)
        echo "unknown public install channel: $channel" >&2
        exit 2
        ;;
    esac
    case "$seen" in
      *" $channel "*)
        echo "duplicate public install channel: $channel" >&2
        exit 2
        ;;
    esac
    seen="${seen}${channel} "
  done
  set +f
  if [ "$count" -eq 0 ]; then
    echo "VERIFY_PUBLIC_INSTALL_CHANNELS must include at least one channel" >&2
    exit 2
  fi
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

validate_crates_install_script() {
  case "$crates_install_script" in
    "" | *[[:space:]]*)
      echo "VERIFY_CRATES_INSTALL_SCRIPT must be a non-empty repository-relative scripts/*.sh path without whitespace, got: $crates_install_script" >&2
      exit 2
      ;;
    /* | -* | *"/../"* | ../* | */.. | ..)
      echo "VERIFY_CRATES_INSTALL_SCRIPT must be a repository-relative scripts/*.sh path, got: $crates_install_script" >&2
      exit 2
      ;;
    scripts/*.sh) ;;
    *)
      echo "VERIFY_CRATES_INSTALL_SCRIPT must be a repository-relative scripts/*.sh path, got: $crates_install_script" >&2
      exit 2
      ;;
  esac
  if [ ! -f "$crates_install_script" ]; then
    echo "VERIFY_CRATES_INSTALL_SCRIPT does not exist: $crates_install_script" >&2
    exit 2
  fi
}

validate_allow_missing_crates_scope() {
  if [ "$allow_missing_crates" != 1 ]; then
    return
  fi
  case " $channels " in
    *" crates "*) ;;
    *)
      echo "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 requires the crates channel" >&2
      exit 2
      ;;
  esac
}

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "version must look like X.Y.Z, got: $version" >&2
  exit 2
fi
case "$tag" in
  v*) ;;
  *)
    echo "release tag must start with v, got: $tag" >&2
    exit 2
    ;;
esac
if [ "${tag#v}" != "$version" ]; then
  echo "VERSION and RELEASE_TAG disagree: VERSION=$version RELEASE_TAG=$tag" >&2
  exit 2
fi
case "$dry_run" in
  0 | 1) ;;
  *)
    echo "VERIFY_PUBLIC_INSTALLS_DRY_RUN must be 0 or 1, got: $dry_run" >&2
    exit 2
    ;;
esac
case "$allow_missing_crates" in
  0 | 1) ;;
  *)
    echo "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES must be 0 or 1, got: $allow_missing_crates" >&2
    exit 2
    ;;
esac
case "$verify_no_overwrite" in
  0 | 1) ;;
  *)
    echo "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE must be 0 or 1, got: $verify_no_overwrite" >&2
    exit 2
    ;;
esac
validate_channels
validate_allow_missing_crates_scope
validate_min_parity
validate_bench_files
validate_crates_install_script

if [ "$dry_run" = 1 ]; then
  printf 'version=%s\n' "$version"
  printf 'tag=%s\n' "$tag"
  printf 'channels=%s\n' "$channels"
  printf 'allow_missing_crates=%s\n' "$allow_missing_crates"
  printf 'verify_no_overwrite=%s\n' "$verify_no_overwrite"
  printf 'min_parity=%s\n' "$min_parity"
  printf 'bench_files=%s\n' "$bench_files"
  printf 'crates_install_script=%s\n' "$crates_install_script"
  set -f
  for channel in $channels; do
    case "$channel" in
      github-linux)
        printf 'github-linux=RELEASE_TAG=%q VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE=%q bash scripts/verify-github-release-linux-docker.sh\n' \
          "$tag" "$verify_no_overwrite"
        ;;
      github-parity)
        printf 'github-parity=RELEASE_TAG=%q BENCH_FILES=%q MIN_PARITY=%q bash scripts/verify-github-release-parity.sh\n' \
          "$tag" "$bench_files" "$min_parity"
        ;;
      bioconda)
        printf 'bioconda=VERSION=%q VERIFY_BIOCONDA_NO_OVERWRITE=%q bash scripts/verify-bioconda-install.sh\n' \
          "$version" "$verify_no_overwrite"
        ;;
      crates)
        printf 'crates=VERSION=%q bash %s\n' "$version" "$crates_install_script"
        ;;
    esac
  done
  set +f
  exit 0
fi

status=0
passed=""
failed=""
allowed_missing=""

printf 'public-audit-version=%s\n' "$version"
printf 'public-audit-tag=%s\n' "$tag"
printf 'public-audit-channels=%s\n' "$channels"
printf 'public-audit-allow-missing-crates=%s\n' "$allow_missing_crates"
printf 'public-audit-no-overwrite=%s\n' "$verify_no_overwrite"
printf 'public-audit-min-parity=%s\n' "$min_parity"
printf 'public-audit-bench-files=%s\n' "$bench_files"
printf 'public-audit-crates-install-script=%s\n' "$crates_install_script"

run_check() {
  local channel="$1"
  shift
  echo ">> public install: $channel"
  set +e
  "$@"
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    passed="${passed}${channel} "
    return 0
  fi
  failed="${failed}${channel} "
  status=1
  return 0
}

run_crates_check() {
  local log
  log="$(mktemp)"
  echo ">> public install: crates"
  set +e
  env VERSION="$version" bash "$crates_install_script" >"$log" 2>&1
  local rc=$?
  set -e
  cat "$log"
  if [ "$rc" -eq 0 ]; then
    rm -f "$log"
    passed="${passed}crates "
    return 0
  fi
  if [ "$allow_missing_crates" = 1 ] \
    && grep -Eq 'could not find `gxfkit`|no matching package named `gxfkit`' "$log"; then
    rm -f "$log"
    allowed_missing="${allowed_missing}crates "
    echo "allowed missing Crates.io install for gxfkit $version" >&2
    return 0
  fi
  rm -f "$log"
  failed="${failed}crates "
  status=1
  return 0
}

set -f
for channel in $channels; do
  case "$channel" in
    github-linux)
      run_check "$channel" env RELEASE_TAG="$tag" \
        VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE="$verify_no_overwrite" \
        bash scripts/verify-github-release-linux-docker.sh
      ;;
    github-parity)
      run_check "$channel" env RELEASE_TAG="$tag" \
        BENCH_FILES="$bench_files" \
        MIN_PARITY="$min_parity" \
        bash scripts/verify-github-release-parity.sh
      ;;
    bioconda)
      run_check "$channel" env VERSION="$version" \
        VERIFY_BIOCONDA_NO_OVERWRITE="$verify_no_overwrite" \
        bash scripts/verify-bioconda-install.sh
      ;;
    crates)
      run_crates_check
      ;;
  esac
done
set +f

printf 'public install summary: passed=[%s] allowed_missing=[%s] failed=[%s]\n' \
  "$passed" "$allowed_missing" "$failed"
exit "$status"
