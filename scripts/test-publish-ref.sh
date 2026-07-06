#!/usr/bin/env bash
# Regression tests for scripts/check-publish-ref.sh.
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
  cat >"$dir/Cargo.toml" <<'TOML'
[workspace]
members = []
version = "1.2.3"
TOML
  git -C "$dir" add Cargo.toml
  git -C "$dir" commit -q -m initial
}

repo="$tmp/repo"
make_repo "$repo"
expect_fail \
  bad-version \
  "VERSION must look like X.Y.Z, got: nope" \
  env GXFKIT_ROOT="$repo" VERSION=nope bash "$ROOT/scripts/check-publish-ref.sh"

GXFKIT_ROOT="$repo" VERSION=1.2.3 bash "$ROOT/scripts/check-publish-ref.sh" >"$tmp/no-tag.out"
grep -F "tag v1.2.3 does not exist yet" "$tmp/no-tag.out" >/dev/null

git -C "$repo" tag v1.2.3
GXFKIT_ROOT="$repo" VERSION=1.2.3 bash "$ROOT/scripts/check-publish-ref.sh" >"$tmp/matching.out"
grep -F "HEAD matches v1.2.3" "$tmp/matching.out" >/dev/null

echo '# changed' >>"$repo/Cargo.toml"
git -C "$repo" add Cargo.toml
git -C "$repo" commit -q -m changed
expect_fail \
  mismatched-tag \
  "Refusing to publish version 1.2.3" \
  env GXFKIT_ROOT="$repo" VERSION=1.2.3 bash "$ROOT/scripts/check-publish-ref.sh"

echo "verified publish ref tests"
