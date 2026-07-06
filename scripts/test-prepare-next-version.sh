#!/usr/bin/env bash
# Regression tests for scripts/prepare-next-version.py.
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

fixture="$tmp/gxfkit-fixture"
mkdir -p "$fixture/scripts" "$fixture/crates/gxfkit" \
  "$fixture/packaging/bioconda/recipe" "$fixture/packaging/bioconda"
cp scripts/prepare-next-version.py "$fixture/scripts/"
cat >"$fixture/Cargo.toml" <<'TOML'
[workspace.package]
version = "0.0.1"
TOML
cat >"$fixture/crates/gxfkit/Cargo.toml" <<'TOML'
[dependencies]
gxfkit-core = { version = "0.0.1", path = "../gxfkit-core" }
TOML
cat >"$fixture/packaging/bioconda/recipe/meta.yaml" <<'YAML'
{% set version = "0.0.1" %}
source:
  sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
cp "$fixture/packaging/bioconda/recipe/meta.yaml" \
  "$fixture/packaging/bioconda/meta.yaml.template"

sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
(cd "$fixture" && python3 scripts/prepare-next-version.py 0.0.2 --cargo-only) \
  >"$tmp/cargo-only.out"
grep -F "updated Cargo.toml" "$tmp/cargo-only.out" >/dev/null
grep -F 'version = "0.0.2"' "$fixture/Cargo.toml" >/dev/null
grep -F 'gxfkit-core = { version = "0.0.2", path = "../gxfkit-core" }' \
  "$fixture/crates/gxfkit/Cargo.toml" >/dev/null
grep -F '{% set version = "0.0.1" %}' "$fixture/packaging/bioconda/recipe/meta.yaml" >/dev/null
grep -F "sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "$fixture/packaging/bioconda/recipe/meta.yaml" >/dev/null

(cd "$fixture" && python3 scripts/prepare-next-version.py 0.0.2 --bioconda-sha256 "$sha") \
  >"$tmp/bioconda.out"
grep -F "updated packaging/bioconda/recipe/meta.yaml" "$tmp/bioconda.out" >/dev/null
grep -F "updated packaging/bioconda/meta.yaml.template" "$tmp/bioconda.out" >/dev/null
grep -F 'version = "0.0.2"' "$fixture/Cargo.toml" >/dev/null
grep -F 'gxfkit-core = { version = "0.0.2", path = "../gxfkit-core" }' \
  "$fixture/crates/gxfkit/Cargo.toml" >/dev/null
grep -F '{% set version = "0.0.2" %}' "$fixture/packaging/bioconda/recipe/meta.yaml" >/dev/null
grep -F "sha256: $sha" "$fixture/packaging/bioconda/recipe/meta.yaml" >/dev/null
cmp "$fixture/packaging/bioconda/recipe/meta.yaml" \
  "$fixture/packaging/bioconda/meta.yaml.template" >/dev/null

expect_fail \
  missing-sha \
  "one of the arguments --cargo-only --bioconda-sha256 is required" \
  bash -lc "cd '$fixture' && python3 scripts/prepare-next-version.py 0.0.3"

expect_fail \
  bad-version \
  "invalid version" \
  bash -lc "cd '$fixture' && python3 scripts/prepare-next-version.py nope --cargo-only"

expect_fail \
  bad-sha \
  "must be a lowercase 64-character sha256" \
  bash -lc "cd '$fixture' && python3 scripts/prepare-next-version.py 0.0.3 --bioconda-sha256 BAD"

git_fixture="$tmp/gxfkit-git-fixture"
cp -R "$fixture" "$git_fixture"
git -C "$git_fixture" init -q
git -C "$git_fixture" config user.email test@example.invalid
git -C "$git_fixture" config user.name "gxfkit test"
git -C "$git_fixture" add .
git -C "$git_fixture" commit -q -m initial

expect_fail \
  bioconda-sha-without-tag \
  "requires local git tag v0.0.3" \
  bash -lc "cd '$git_fixture' && python3 scripts/prepare-next-version.py 0.0.3 --bioconda-sha256 $sha"

git -C "$git_fixture" tag v0.0.3
(cd "$git_fixture" && python3 scripts/prepare-next-version.py 0.0.3 --bioconda-sha256 "$sha") \
  >"$tmp/git-bioconda.out"
grep -F "updated Cargo.toml" "$tmp/git-bioconda.out" >/dev/null
grep -F "updated packaging/bioconda/recipe/meta.yaml" "$tmp/git-bioconda.out" >/dev/null
grep -F '{% set version = "0.0.3" %}' \
  "$git_fixture/packaging/bioconda/recipe/meta.yaml" >/dev/null

echo "verified prepare next version tests"
