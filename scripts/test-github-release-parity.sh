#!/usr/bin/env bash
# Regression tests for scripts/verify-github-release-parity.sh dry-run behavior.
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

VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  GITHUB_RELEASE_REPOSITORY=example/gxfkit \
  BENCH_FILES=yeast \
  MIN_PARITY=100 \
  bash scripts/verify-github-release-parity.sh >"$tmp/dry-run.out"

grep -F "repo=example/gxfkit" "$tmp/dry-run.out" >/dev/null
grep -F "tag=v1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "package=linux-x86_64-static" "$tmp/dry-run.out" >/dev/null
grep -F "bench_files=yeast" "$tmp/dry-run.out" >/dev/null
grep -F "min_parity=100" "$tmp/dry-run.out" >/dev/null
grep -F "download_dir=" "$tmp/dry-run.out" >/dev/null
grep -F "release_archive=" "$tmp/dry-run.out" >/dev/null
grep -F "release_checksum=" "$tmp/dry-run.out" >/dev/null
grep -F \
  "archive=https://github.com/example/gxfkit/releases/download/v1.2.3/gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  "$tmp/dry-run.out" >/dev/null

VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  DOWNLOAD_DIR=/tmp/gxfkit-cache \
  RELEASE_ARCHIVE=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz \
  RELEASE_CHECKSUM=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 \
  bash scripts/verify-github-release-parity.sh >"$tmp/cache-dry-run.out"
grep -F "download_dir=/tmp/gxfkit-cache" "$tmp/cache-dry-run.out" >/dev/null
grep -F "release_archive=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz" "$tmp/cache-dry-run.out" >/dev/null
grep -F "release_checksum=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256" "$tmp/cache-dry-run.out" >/dev/null

grep -F "sha256sum -c" scripts/verify-github-release-parity.sh >/dev/null
grep -F "bash scripts/verify-release-archive.sh" scripts/verify-github-release-parity.sh >/dev/null
grep -F "VERIFY_RELEASE_ARCHIVE_SMOKE=0" scripts/verify-github-release-parity.sh >/dev/null

VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  bash scripts/verify-github-release-parity.sh >"$tmp/default-dry-run.out"
grep -F "min_parity=100" "$tmp/default-dry-run.out" >/dev/null

expect_fail \
  bad-tag \
  "release tag must start with v" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-parity.sh

expect_fail \
  bad-package \
  "PACKAGE must be a Linux static release package" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=macos-aarch64 \
    bash scripts/verify-github-release-parity.sh

expect_fail \
  unknown-linux-package \
  "PACKAGE must be a Linux static release package" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-riscv64-static \
    bash scripts/verify-github-release-parity.sh

expect_fail \
  bad-dry-run \
  "VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN must be 0 or 1" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=maybe RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-parity.sh

expect_fail \
  empty-bench-files \
  "BENCH_FILES must include at least one corpus name" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    BENCH_FILES="   " bash scripts/verify-github-release-parity.sh

expect_fail \
  duplicate-bench-file \
  "duplicate BENCH_FILES entry: yeast" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    BENCH_FILES="yeast yeast" bash scripts/verify-github-release-parity.sh

expect_fail \
  unsafe-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    BENCH_FILES="../yeast" bash scripts/verify-github-release-parity.sh

expect_fail \
  dot-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    BENCH_FILES="." bash scripts/verify-github-release-parity.sh

expect_fail \
  glob-bench-file \
  "BENCH_FILES entries must be corpus basenames" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    BENCH_FILES="*" bash scripts/verify-github-release-parity.sh

expect_fail \
  bad-min-parity \
  "MIN_PARITY must be a number" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    MIN_PARITY=high bash scripts/verify-github-release-parity.sh

expect_fail \
  too-high-min-parity \
  "MIN_PARITY must be between 0 and 100" \
  env VERIFY_GITHUB_RELEASE_PARITY_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    MIN_PARITY=101 bash scripts/verify-github-release-parity.sh

echo "verified GitHub release parity verifier tests"
