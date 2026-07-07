#!/usr/bin/env bash
# Safely trigger the manual Crates.io publish workflow from an existing release tag.
set -euo pipefail

ROOT="${GXFKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

REPO="${GXFKIT_REPO:-benngaihk/gxfkit}"
WORKFLOW="${GXFKIT_PUBLISH_WORKFLOW:-Publish Crates.io}"
REMOTE="${GXFKIT_REMOTE:-origin}"
CRATES_IO_API_BASE="${GXFKIT_CRATES_IO_API_BASE:-https://crates.io/api/v1}"
CRATES_IO_USER_AGENT="${GXFKIT_CRATES_IO_USER_AGENT:-gxfkit-release-trigger}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/trigger-crates-publish.sh VERSION [both|gxfkit-core|gxfkit] publish

Triggers the GitHub Actions "Publish Crates.io" workflow from vVERSION.
The final argument must be exactly "publish".
USAGE
}

version="${1:-${VERSION:-}}"
crate="${2:-${CRATE:-both}}"
confirm="${3:-}"

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
if [ "$confirm" != publish ]; then
  usage
  echo "refusing to trigger publish workflow: final argument must be exactly 'publish'" >&2
  exit 2
fi

tag="v$version"
if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null; then
  echo "refusing to publish: required tag $tag does not exist locally" >&2
  exit 1
fi
local_tag_commit="$(git rev-parse "refs/tags/$tag^{commit}")"
remote_tag_commit="$(git ls-remote --tags "$REMOTE" "refs/tags/$tag^{}" | awk 'NR == 1 {print $1}')"
if [ -z "$remote_tag_commit" ]; then
  remote_tag_commit="$(git ls-remote --tags "$REMOTE" "refs/tags/$tag" | awk 'NR == 1 {print $1}')"
fi
if [ -z "$remote_tag_commit" ]; then
  echo "refusing to publish: required tag $tag does not exist on remote $REMOTE" >&2
  exit 1
fi
if [ "$remote_tag_commit" != "$local_tag_commit" ]; then
  echo "refusing to publish: remote $REMOTE tag $tag resolves to $remote_tag_commit, local tag resolves to $local_tag_commit" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required to trigger the Publish Crates.io workflow" >&2
  exit 1
fi
if ! gh secret list --repo "$REPO" --json name --jq '.[] | select(.name == "CARGO_REGISTRY_TOKEN") | .name' \
  | grep -Fx CARGO_REGISTRY_TOKEN >/dev/null; then
  echo "refusing to publish: CARGO_REGISTRY_TOKEN repository secret is not configured for $REPO" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check Crates.io version state before publishing" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse Crates.io version state before publishing" >&2
  exit 1
fi

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

core_state="$(crates_io_version_state gxfkit-core "$version")"
cli_state="$(crates_io_version_state gxfkit "$version")"

case "$crate" in
  both)
    if [ "$core_state" != absent ]; then
      echo "refusing to publish: gxfkit-core $version is already reserved on Crates.io (state: $core_state); use crate scope 'gxfkit' if only the CLI crate remains" >&2
      exit 1
    fi
    require_crate_absent gxfkit "$version" "$cli_state"
    ;;
  gxfkit-core)
    require_crate_absent gxfkit-core "$version" "$core_state"
    ;;
  gxfkit)
    if [ "$core_state" = absent ]; then
      echo "refusing to publish: gxfkit-core $version is not visible on Crates.io; publish gxfkit-core first and wait for registry propagation" >&2
      exit 1
    fi
    if [ "$core_state" = yanked ]; then
      echo "refusing to publish: gxfkit-core $version is yanked on Crates.io" >&2
      exit 1
    fi
    require_crate_absent gxfkit "$version" "$cli_state"
    ;;
esac
cmd=(
  gh workflow run "$WORKFLOW"
  --repo "$REPO"
  -f "version=$version"
  -f "crate=$crate"
  -f "source_ref=$tag"
  -f "confirm=publish"
)

printf 'triggering Crates.io publish workflow for %s %s from %s\n' "$crate" "$version" "$tag"
if [ "${GXFKIT_TRIGGER_CRATES_PUBLISH_DRY_RUN:-0}" = 1 ]; then
  printf 'dry-run command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
