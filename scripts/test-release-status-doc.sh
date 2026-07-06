#!/usr/bin/env bash
# Regression tests for scripts/check-release-status-doc.py.
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
  local version="$2"
  mkdir -p "$dir/docs"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "gxfkit test"
  cat >"$dir/Cargo.toml" <<TOML
[workspace]
members = []

[workspace.package]
version = "$version"
TOML
}

write_good_doc() {
  local dir="$1"
  cat >"$dir/docs/RELEASE-STATUS.md" <<'MD'
# Release Status

## Current public GitHub Release: `0.0.2`

- GitHub Release `v0.0.2` exists, is public, and is not a prerelease.
- The release has the expected eight assets.
- The release was verified on 2026-07-06 with:

  ```bash
  RELEASE_TAG=v0.0.2 bash scripts/verify-github-release-install.sh
  RELEASE_TAG=v0.0.2 bash scripts/verify-github-release-linux-docker.sh
  RELEASE_TAG=v0.0.2 BENCH_FILES="human_chr1 human_chr21 yeast" bash scripts/verify-github-release-parity.sh
  ```

## Current public Bioconda: `0.0.2`

- Bioconda `gxfkit 0.0.1` exists and passed the basic version/conversion smoke
  used before the strict no-overwrite audit. This was re-verified from a clean
  micromamba container on 2026-07-06. The upstream recipe PR
  [bioconda-recipes#66815](https://github.com/bioconda/bioconda-recipes/pull/66815)
  is merged, so this is a public Bioconda package state rather than only a local
  recipe expectation. Re-verify the installed package with:

  ```bash
  VERSION=0.0.1 VERIFY_BIOCONDA_NO_OVERWRITE=0 bash scripts/verify-bioconda-install.sh
  ```
- Anaconda package metadata lists Bioconda `gxfkit 0.0.2` files for `linux-64`
  and `osx-64` in the `main` label.
- Bioconda `gxfkit 0.0.2` passed clean Linux install verification, smoke
  conversion, and no-overwrite verification on 2026-07-06 with:

  ```bash
  VERSION=0.0.2 bash scripts/verify-bioconda-install.sh
  ```

## Current public Crates.io: none

- Crates.io `gxfkit-core 0.0.2` is not published.
- Crates.io `gxfkit 0.0.2` is not published.
- Publishing is currently blocked by missing credentials. The local environment
  did not have `CARGO_REGISTRY_TOKEN`, `~/.cargo/credentials.toml`, or
  `~/.cargo/credentials`, and the GitHub repository had no configured secrets at
  the time this status was recorded.

## Current Cargo release candidate: `0.0.2`

The local release preflight uses offline install/package smoke checks and
`python3 scripts/check-release-check.py` guards that deterministic local
preflight contract.

The existing `v0.0.2` tag points at the release-candidate commit. It must not be
moved. Do not publish Crates.io `0.0.2` from `main` after the Bioconda metadata
commit, because the existing `v0.0.2` tag points at an older commit. Publishing
must use the existing `v0.0.2` tag, or the next public release must bump the
workspace version before publishing.

## Important `0.0.1` boundary

The existing `v0.0.1` tag points at an older commit than this release-hardening
work. Do not publish Crates.io `gxfkit 0.0.1` from any commit other than the
existing `v0.0.1` tag.

## Remaining `0.0.2` public closure

```bash
python3 scripts/release-readiness.py --phase public --check-public --run-public-audit
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
VERSION=0.0.2 RELEASE_TAG=v0.0.2 bash scripts/verify-public-installs.sh
```

Run the strict audit through `release-readiness --run-public-audit` so the
captured audit log is also verified.
MD
}

repo="$tmp/current"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py" >"$tmp/current.out"
grep -F "verified release status doc" "$tmp/current.out" >/dev/null

repo="$tmp/post-tag-metadata"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m release-candidate
git -C "$repo" tag v0.0.2
echo "# post-tag metadata" >>"$repo/Cargo.toml"
git -C "$repo" add Cargo.toml
git -C "$repo" commit -q -m "post-tag metadata"
GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py" >"$tmp/post-tag-metadata.out"
grep -F "verified release status doc" "$tmp/post-tag-metadata.out" >/dev/null

repo="$tmp/stale"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
cat >>"$repo/docs/RELEASE-STATUS.md" <<'MD'

The current working tree still reports workspace version `0.0.1`.
MD
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  stale-current-version-claim \
  "stale current-working-tree version claim" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/stale-default-smoke"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/basic version\/conversion smoke/default public install smoke/g' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  stale-default-smoke \
  "must not mention: default public install smoke" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-github-release"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/- GitHub Release `v0\.0\.2` exists, is public, and is not a prerelease\.//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-github-release \
  'must mention: GitHub Release `v0.0.2` exists, is public, and is not a prerelease' \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-github-parity"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/  RELEASE_TAG=v0\.0\.2 BENCH_FILES="human_chr1 human_chr21 yeast" bash scripts\/verify-github-release-parity\.sh\n//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-github-parity \
  'must mention: RELEASE_TAG=v0.0.2 BENCH_FILES="human_chr1 human_chr21 yeast" bash scripts/verify-github-release-parity.sh' \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-bioconda-pr"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/Anaconda package metadata lists Bioconda `gxfkit 0\.0\.2` files//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-bioconda-pr \
  'must mention: Anaconda package metadata lists Bioconda `gxfkit 0.0.2` files' \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-crates-credentials"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/Publishing is currently blocked by missing credentials\.//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-crates-credentials \
  "must mention: blocked by missing credentials" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/bad-bioconda-version"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/## Current public Bioconda: `0\.0\.2`/## Current public Bioconda: `0.0.1`/' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  bad-bioconda-version \
  "Current public Bioconda 0.0.1 != workspace version 0.0.2" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/occupied-version"
make_repo "$repo" 0.0.1
cat >"$repo/docs/RELEASE-STATUS.md" <<'MD'
# Release Status

## Current public GitHub Release: `0.0.1`

## Current public Bioconda: `0.0.0`

## Current Cargo release candidate: `0.0.1`
MD
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
git -C "$repo" tag v0.0.1
echo "# changed" >>"$repo/Cargo.toml"
git -C "$repo" add Cargo.toml
git -C "$repo" commit -q -m changed
expect_fail \
  occupied-version-missing-boundary \
  'existing `v0.0.1` tag points at an older commit' \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

echo "verified release status doc tests"
