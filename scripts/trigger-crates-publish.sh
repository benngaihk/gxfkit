#!/usr/bin/env bash
# Safely trigger the manual Crates.io publish workflow from an existing release tag.
set -euo pipefail

ROOT="${GXFKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

REPO="${GXFKIT_REPO:-benngaihk/gxfkit}"
WORKFLOW="${GXFKIT_PUBLISH_WORKFLOW:-Publish Crates.io}"
REMOTE="${GXFKIT_REMOTE:-origin}"

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
