#!/usr/bin/env bash
# Verify that the requested Crates.io publish scope is safe to run.
set -euo pipefail

CRATES_IO_API_BASE="${GXFKIT_CRATES_IO_API_BASE:-https://crates.io/api/v1}"
CRATES_IO_USER_AGENT="${GXFKIT_CRATES_IO_USER_AGENT:-gxfkit-release-state-check}"
CRATES_IO_CONNECT_TIMEOUT="${GXFKIT_CRATES_IO_CONNECT_TIMEOUT:-10}"
CRATES_IO_MAX_TIME="${GXFKIT_CRATES_IO_MAX_TIME:-60}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/check-crates-publish-state.sh VERSION [both|gxfkit-core|gxfkit]

Checks Crates.io version state before publishing:
- both: both gxfkit-core and gxfkit VERSION must be absent
- gxfkit-core: gxfkit-core VERSION must be absent
- gxfkit: gxfkit-core VERSION must be present and not yanked, gxfkit VERSION must be absent
USAGE
}

version="${1:-${VERSION:-}}"
crate="${2:-${CRATE:-both}}"

if [ -z "$version" ]; then
  usage
  exit 2
fi
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERSION must look like X.Y.Z, got: $version" >&2
  exit 2
fi
case "$crate" in
  both | gxfkit-core | gxfkit) ;;
  *)
    echo "crate scope must be one of: both, gxfkit-core, gxfkit; got: $crate" >&2
    exit 2
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check Crates.io version state before publishing" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse Crates.io version state before publishing" >&2
  exit 1
fi
case "$CRATES_IO_CONNECT_TIMEOUT" in
  '' | *[!0-9]*)
    echo "GXFKIT_CRATES_IO_CONNECT_TIMEOUT must be a positive integer, got: $CRATES_IO_CONNECT_TIMEOUT" >&2
    exit 2
    ;;
  0)
    echo "GXFKIT_CRATES_IO_CONNECT_TIMEOUT must be a positive integer, got: 0" >&2
    exit 2
    ;;
esac
case "$CRATES_IO_MAX_TIME" in
  '' | *[!0-9]*)
    echo "GXFKIT_CRATES_IO_MAX_TIME must be a positive integer, got: $CRATES_IO_MAX_TIME" >&2
    exit 2
    ;;
  0)
    echo "GXFKIT_CRATES_IO_MAX_TIME must be a positive integer, got: 0" >&2
    exit 2
    ;;
esac

crates_io_version_state() {
  local crate_name="$1"
  local crate_version="$2"
  local response_file
  local error_file
  local http_code
  response_file="$(mktemp)"
  error_file="$(mktemp)"
  if ! http_code="$(
    curl -sS -L \
      --connect-timeout "$CRATES_IO_CONNECT_TIMEOUT" \
      --max-time "$CRATES_IO_MAX_TIME" \
      -H "User-Agent: $CRATES_IO_USER_AGENT" \
      -o "$response_file" \
      -w '%{http_code}' \
      "$CRATES_IO_API_BASE/crates/$crate_name/$crate_version" \
      2>"$error_file"
  )"; then
    cat "$error_file" >&2
    rm -f "$response_file" "$error_file"
    return 1
  fi
  case "$http_code" in
    200)
      if python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)
print("yanked" if payload.get("version", {}).get("yanked") else "present")
PY
      then
        rm -f "$response_file" "$error_file"
        return 0
      fi
      echo "failed to parse Crates.io response for $crate_name $crate_version" >&2
      ;;
    404)
      printf 'absent\n'
      rm -f "$response_file" "$error_file"
      return 0
      ;;
    *)
      echo "failed to check Crates.io state for $crate_name $crate_version: HTTP $http_code" >&2
      ;;
  esac
  rm -f "$response_file" "$error_file"
  return 1
}

require_crate_absent() {
  local crate_name="$1"
  local crate_version="$2"
  local state="$3"
  if [ "$state" != absent ]; then
    echo "refusing to publish: $crate_name $crate_version is already reserved on Crates.io (state: $state)" >&2
    exit 1
  fi
}

case "$crate" in
  both)
    core_state="$(crates_io_version_state gxfkit-core "$version")"
    if [ "$core_state" != absent ]; then
      echo "refusing to publish: gxfkit-core $version is already reserved on Crates.io (state: $core_state); use crate scope 'gxfkit' if only the CLI crate remains" >&2
      exit 1
    fi
    cli_state="$(crates_io_version_state gxfkit "$version")"
    require_crate_absent gxfkit "$version" "$cli_state"
    ;;
  gxfkit-core)
    core_state="$(crates_io_version_state gxfkit-core "$version")"
    require_crate_absent gxfkit-core "$version" "$core_state"
    ;;
  gxfkit)
    core_state="$(crates_io_version_state gxfkit-core "$version")"
    if [ "$core_state" = absent ]; then
      echo "refusing to publish: gxfkit-core $version is not visible on Crates.io; publish gxfkit-core first and wait for registry propagation" >&2
      exit 1
    fi
    if [ "$core_state" = yanked ]; then
      echo "refusing to publish: gxfkit-core $version is yanked on Crates.io" >&2
      exit 1
    fi
    cli_state="$(crates_io_version_state gxfkit "$version")"
    require_crate_absent gxfkit "$version" "$cli_state"
    ;;
esac

printf 'verified Crates.io publish state for %s %s\n' "$crate" "$version"
