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
version = "$version"
TOML
}

write_good_doc() {
  local dir="$1"
  cat >"$dir/docs/RELEASE-STATUS.md" <<'MD'
# Release Status

## Current public version: `0.0.1`

- GitHub Release `v0.0.1` exists and its release archive passed the basic
  version/conversion smoke used before the strict no-overwrite audit. This was
  re-verified on 2026-07-06 with:

  ```bash
  RELEASE_TAG=v0.0.1 VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0 bash scripts/verify-github-release-install.sh
  ```
- Bioconda `gxfkit 0.0.1` exists and passed the basic version/conversion smoke
  used before the strict no-overwrite audit. This was re-verified from a clean
  micromamba container on 2026-07-06. The upstream recipe PR
  [bioconda-recipes#66815](https://github.com/bioconda/bioconda-recipes/pull/66815)
  is merged, so this is a public Bioconda package state rather than only a local
  recipe expectation. Re-verify the installed package with:

  ```bash
  VERSION=0.0.1 VERIFY_BIOCONDA_NO_OVERWRITE=0 bash scripts/verify-bioconda-install.sh
  ```
- Crates.io `gxfkit 0.0.1` is not published.

## Current Cargo release candidate: `0.0.2`

The Cargo workspace may be ahead of the public version during tag preparation.
The local release preflight uses offline install/package smoke checks and
`python3 scripts/check-release-check.py` guards that deterministic local
preflight contract.

The existing `v0.0.1` tag points at an older commit than this release-hardening
work. Do not publish Crates.io `gxfkit 0.0.1` from any commit other than the
existing `v0.0.1` tag.

The next public release must bump the workspace version and pass the strict
public install audit:

```bash
python3 scripts/release-readiness.py --phase public --check-public --run-public-audit
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
VERSION=X.Y.Z RELEASE_TAG=vX.Y.Z bash scripts/verify-public-installs.sh
```

Run the strict audit through `release-readiness --run-public-audit` so the
captured audit log is also verified.

## Before the next public release

1. Bump the workspace version.
2. Cut a new tag.
MD
}

repo="$tmp/mismatch"
make_repo "$repo" 0.0.1
write_good_doc "$repo"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
git -C "$repo" tag v0.0.1
perl -0pi -e 's/version = "0\.0\.1"/version = "0.0.2"/' "$repo/Cargo.toml"
git -C "$repo" add Cargo.toml
git -C "$repo" commit -q -m "prepare 0.0.2"
GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py" >"$tmp/source-ahead.out"
grep -F "verified release status doc" "$tmp/source-ahead.out" >/dev/null

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

repo="$tmp/missing-github-reverify"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/ This was\n  re-verified on 2026-07-06 with:\n\n  ```bash\n  RELEASE_TAG=v0\.0\.1 VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0 bash scripts\/verify-github-release-install\.sh\n  ```//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-github-reverify \
  "must mention: RELEASE_TAG=v0.0.1 VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0 bash scripts/verify-github-release-install.sh" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-bioconda-reverify"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/ This was re-verified from a clean\n  micromamba container on 2026-07-06\. The upstream recipe PR\n  \[bioconda-recipes#66815\]\(https:\/\/github\.com\/bioconda\/bioconda-recipes\/pull\/66815\)\n  is merged, so this is a public Bioconda package state rather than only a local\n  recipe expectation\. Re-verify the installed package with:\n\n  ```bash\n  VERSION=0\.0\.1 VERIFY_BIOCONDA_NO_OVERWRITE=0 bash scripts\/verify-bioconda-install\.sh\n  ```//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-bioconda-reverify \
  "must mention: re-verified from a clean micromamba container" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/missing-bioconda-pr"
make_repo "$repo" 0.0.2
write_good_doc "$repo"
perl -0pi -e 's/ The upstream recipe PR\n  \[bioconda-recipes#66815\]\(https:\/\/github\.com\/bioconda\/bioconda-recipes\/pull\/66815\)\n  is merged, so this is a public Bioconda package state rather than only a local\n  recipe expectation\.//' \
  "$repo/docs/RELEASE-STATUS.md"
git -C "$repo" add Cargo.toml docs/RELEASE-STATUS.md
git -C "$repo" commit -q -m initial
expect_fail \
  missing-bioconda-pr \
  "must mention: bioconda-recipes#66815" \
  env GXFKIT_ROOT="$repo" "$PY" "$ROOT/scripts/check-release-status-doc.py"

repo="$tmp/occupied-version"
make_repo "$repo" 0.0.1
cat >"$repo/docs/RELEASE-STATUS.md" <<'MD'
# Release Status

## Current public version: `0.0.1`
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
