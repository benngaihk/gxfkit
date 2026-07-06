#!/usr/bin/env bash
# Regression tests for scripts/verify-bioconda-install.sh dry-run behavior.
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

VERIFY_BIOCONDA_INSTALL_DRY_RUN=1 \
  VERSION=1.2.3 \
  VERIFY_BIOCONDA_IMAGE=mambaorg/micromamba:test \
  VERIFY_BIOCONDA_PLATFORM=linux/amd64 \
  bash scripts/verify-bioconda-install.sh >"$tmp/dry-run.out"

grep -F "version=1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "image=mambaorg/micromamba:test" "$tmp/dry-run.out" >/dev/null
grep -F "platform=linux/amd64" "$tmp/dry-run.out" >/dev/null
grep -F "channels=conda-forge,bioconda" "$tmp/dry-run.out" >/dev/null
grep -F "verify_no_overwrite=1" "$tmp/dry-run.out" >/dev/null
grep -F "install=gxfkit=1.2.3" "$tmp/dry-run.out" >/dev/null

VERIFY_BIOCONDA_INSTALL_DRY_RUN=1 \
  VERIFY_BIOCONDA_NO_OVERWRITE=1 \
  VERSION=1.2.3 \
  bash scripts/verify-bioconda-install.sh >"$tmp/strict-dry-run.out"
grep -F "verify_no_overwrite=1" "$tmp/strict-dry-run.out" >/dev/null

VERIFY_BIOCONDA_INSTALL_DRY_RUN=1 \
  VERIFY_BIOCONDA_NO_OVERWRITE=0 \
  VERSION=1.2.3 \
  bash scripts/verify-bioconda-install.sh >"$tmp/compat-dry-run.out"
grep -F "verify_no_overwrite=0" "$tmp/compat-dry-run.out" >/dev/null

expect_fail \
  bad-dry-run \
  "VERIFY_BIOCONDA_INSTALL_DRY_RUN must be 0 or 1" \
  env VERIFY_BIOCONDA_INSTALL_DRY_RUN=maybe VERSION=1.2.3 \
    bash scripts/verify-bioconda-install.sh

expect_fail \
  bad-version \
  "VERSION must look like X.Y.Z" \
  env VERIFY_BIOCONDA_INSTALL_DRY_RUN=1 VERSION=nope \
    bash scripts/verify-bioconda-install.sh

expect_fail \
  bad-no-overwrite \
  "VERIFY_BIOCONDA_NO_OVERWRITE must be 0 or 1" \
  env VERIFY_BIOCONDA_INSTALL_DRY_RUN=1 VERIFY_BIOCONDA_NO_OVERWRITE=maybe VERSION=1.2.3 \
    bash scripts/verify-bioconda-install.sh

echo "verified Bioconda install verifier tests"
