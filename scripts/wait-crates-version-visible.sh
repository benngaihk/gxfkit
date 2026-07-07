#!/usr/bin/env bash
# Wait for a published crate version to become visible on Crates.io.
set -euo pipefail

CRATES_IO_API_BASE="${GXFKIT_CRATES_IO_API_BASE:-https://crates.io/api/v1}"
CRATES_IO_USER_AGENT="${GXFKIT_CRATES_IO_USER_AGENT:-gxfkit-release-state-check}"
CRATES_IO_CONNECT_TIMEOUT="${GXFKIT_CRATES_IO_CONNECT_TIMEOUT:-10}"
CRATES_IO_MAX_TIME="${GXFKIT_CRATES_IO_MAX_TIME:-60}"
WAIT_ATTEMPTS="${GXFKIT_CRATES_IO_WAIT_ATTEMPTS:-30}"
WAIT_INTERVAL="${GXFKIT_CRATES_IO_WAIT_INTERVAL:-20}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/wait-crates-version-visible.sh VERSION CRATE

Waits until CRATE VERSION is visible on Crates.io and not yanked.
USAGE
}

version="${1:-${VERSION:-}}"
crate="${2:-${CRATE:-}}"

if [ -z "$version" ] || [ -z "$crate" ]; then
  usage
  exit 2
fi
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "VERSION must look like X.Y.Z, got: $version" >&2
  exit 2
fi
case "$crate" in
  gxfkit-core | gxfkit) ;;
  *)
    echo "crate must be one of: gxfkit-core, gxfkit; got: $crate" >&2
    exit 2
    ;;
esac
for name in \
  GXFKIT_CRATES_IO_CONNECT_TIMEOUT:$CRATES_IO_CONNECT_TIMEOUT \
  GXFKIT_CRATES_IO_MAX_TIME:$CRATES_IO_MAX_TIME \
  GXFKIT_CRATES_IO_WAIT_ATTEMPTS:$WAIT_ATTEMPTS \
  GXFKIT_CRATES_IO_WAIT_INTERVAL:$WAIT_INTERVAL
do
  key="${name%%:*}"
  value="${name#*:}"
  case "$value" in
    '' | *[!0-9]* | 0)
      echo "$key must be a positive integer, got: $value" >&2
      exit 2
      ;;
  esac
done
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check Crates.io version visibility" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse Crates.io version visibility" >&2
  exit 1
fi

check_once() {
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
      "$CRATES_IO_API_BASE/crates/$crate/$version" \
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
      echo "failed to parse Crates.io response for $crate $version" >&2
      ;;
    404)
      printf 'absent\n'
      rm -f "$response_file" "$error_file"
      return 0
      ;;
    *)
      echo "failed to check Crates.io visibility for $crate $version: HTTP $http_code" >&2
      ;;
  esac
  rm -f "$response_file" "$error_file"
  return 1
}

for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
  state="$(check_once)"
  case "$state" in
    present)
      echo "verified Crates.io visibility for $crate $version"
      exit 0
      ;;
    yanked)
      echo "$crate $version is visible on Crates.io but yanked" >&2
      exit 1
      ;;
    absent)
      echo "$crate $version is not visible yet (attempt ${attempt}/${WAIT_ATTEMPTS})."
      ;;
    *)
      echo "unexpected Crates.io visibility state for $crate $version: $state" >&2
      exit 1
      ;;
  esac
  if [ "$attempt" != "$WAIT_ATTEMPTS" ]; then
    sleep "$WAIT_INTERVAL"
  fi
done

echo "Timed out waiting for $crate $version on Crates.io." >&2
exit 1
