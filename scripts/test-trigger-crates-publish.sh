#!/usr/bin/env bash
# Regression tests for scripts/trigger-crates-publish.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_fail() {
  local label="$1"
  local expected="$2"
  shift 2
  local out="$tmp/${label}.out"
  if "$@" >"$out" 2>&1; then
    echo "$label unexpectedly passed" >&2
    cat "$out" >&2
    exit 1
  fi
  if ! grep -F -- "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "gxfkit test"
  printf 'release fixture\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m initial
}

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'secret list --repo benngaihk/gxfkit --json name --jq .[] | select(.name == "CARGO_REGISTRY_TOKEN") | .name')
    if [ "${GXFKIT_FAKE_SECRET:-missing}" = present ]; then
      printf 'CARGO_REGISTRY_TOKEN\n'
    fi
    ;;
  workflow\ run\ *)
    printf '%s\n' "$*" >"${GXFKIT_FAKE_GH_WORKFLOW_LOG:?}"
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$fake_bin/gh"

repo="$tmp/repo"
make_repo "$repo"
remote="$tmp/remote.git"
git init -q --bare "$remote"
git -C "$repo" remote add origin "$remote"

expect_fail \
  bad-version \
  "VERSION must look like X.Y.Z, got: nope" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" nope both publish

expect_fail \
  bad-crate \
  "crate scope must be one of: both, gxfkit-core, gxfkit; got: bad" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 bad publish

expect_fail \
  bad-confirm \
  "refusing to trigger publish workflow: final argument must be exactly 'publish'" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 both nope

expect_fail \
  missing-tag \
  "refusing to publish: required tag v1.2.3 does not exist locally" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 both publish

git -C "$repo" tag v1.2.3
expect_fail \
  missing-remote-tag \
  "refusing to publish: required tag v1.2.3 does not exist on remote origin" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 both publish

git -C "$repo" push -q origin v1.2.3
expect_fail \
  missing-secret \
  "refusing to publish: CARGO_REGISTRY_TOKEN repository secret is not configured for benngaihk/gxfkit" \
  env GXFKIT_ROOT="$repo" PATH="$fake_bin:$PATH" \
    bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 both publish

env \
  GXFKIT_ROOT="$repo" \
  GXFKIT_FAKE_SECRET=present \
  GXFKIT_TRIGGER_CRATES_PUBLISH_DRY_RUN=1 \
  PATH="$fake_bin:$PATH" \
  bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 gxfkit publish \
  >"$tmp/dry-run.out"
grep -F "triggering Crates.io publish workflow for gxfkit 1.2.3 from v1.2.3" \
  "$tmp/dry-run.out" >/dev/null
grep -F "source_ref=v1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "confirm=publish" "$tmp/dry-run.out" >/dev/null

workflow_log="$tmp/workflow.log"
env \
  GXFKIT_ROOT="$repo" \
  GXFKIT_FAKE_SECRET=present \
  GXFKIT_FAKE_GH_WORKFLOW_LOG="$workflow_log" \
  PATH="$fake_bin:$PATH" \
  bash "$ROOT/scripts/trigger-crates-publish.sh" 1.2.3 both publish \
  >"$tmp/trigger.out"
grep -F "triggering Crates.io publish workflow for both 1.2.3 from v1.2.3" \
  "$tmp/trigger.out" >/dev/null
grep -F "workflow run Publish Crates.io --repo benngaihk/gxfkit -f version=1.2.3 -f crate=both -f source_ref=v1.2.3 -f confirm=publish" \
  "$workflow_log" >/dev/null

echo "verified Crates.io publish trigger tests"
