#!/usr/bin/env bash
# Regression tests for scripts/verify-github-release-install.sh URL construction.
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

VERIFY_GITHUB_RELEASE_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  GITHUB_RELEASE_REPOSITORY=example/gxfkit \
  bash scripts/verify-github-release-install.sh >"$tmp/dry-run.out"

grep -F "repo=example/gxfkit" "$tmp/dry-run.out" >/dev/null
grep -F "tag=v1.2.3" "$tmp/dry-run.out" >/dev/null
grep -F "package=linux-x86_64-static" "$tmp/dry-run.out" >/dev/null
grep -F "download_dir=" "$tmp/dry-run.out" >/dev/null
grep -F "verify_no_overwrite=1" "$tmp/dry-run.out" >/dev/null
grep -F "release_archive=" "$tmp/dry-run.out" >/dev/null
grep -F "release_checksum=" "$tmp/dry-run.out" >/dev/null
grep -F \
  "archive=https://github.com/example/gxfkit/releases/download/v1.2.3/gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  "$tmp/dry-run.out" >/dev/null
grep -F \
  "checksum=https://github.com/example/gxfkit/releases/download/v1.2.3/gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256" \
  "$tmp/dry-run.out" >/dev/null

VERIFY_GITHUB_RELEASE_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  DOWNLOAD_DIR=/tmp/gxfkit-cache \
  RELEASE_ARCHIVE=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz \
  RELEASE_CHECKSUM=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 \
  bash scripts/verify-github-release-install.sh >"$tmp/cache-dry-run.out"
grep -F "download_dir=/tmp/gxfkit-cache" "$tmp/cache-dry-run.out" >/dev/null
grep -F "release_archive=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  "$tmp/cache-dry-run.out" >/dev/null
grep -F "release_checksum=/tmp/gxfkit-cache/gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256" \
  "$tmp/cache-dry-run.out" >/dev/null

VERIFY_GITHUB_RELEASE_DRY_RUN=1 \
  VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  bash scripts/verify-github-release-install.sh >"$tmp/no-overwrite-compat-dry-run.out"
grep -F "verify_no_overwrite=0" "$tmp/no-overwrite-compat-dry-run.out" >/dev/null

grep -F "sha256sum -c" scripts/verify-github-release-install.sh >/dev/null
grep -F "bash scripts/verify-release-archive.sh" scripts/verify-github-release-install.sh >/dev/null
grep -F 'VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE="$verify_no_overwrite"' \
  scripts/verify-github-release-install.sh >/dev/null

expect_fail \
  bad-tag \
  "release tag must start with v" \
  env VERIFY_GITHUB_RELEASE_DRY_RUN=1 RELEASE_TAG=1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-install.sh

expect_fail \
  bad-dry-run \
  "VERIFY_GITHUB_RELEASE_DRY_RUN must be 0 or 1" \
  env VERIFY_GITHUB_RELEASE_DRY_RUN=maybe RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-install.sh

expect_fail \
  bad-package \
  "PACKAGE must be a known release package" \
  env VERIFY_GITHUB_RELEASE_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-riscv64-static \
    bash scripts/verify-github-release-install.sh

expect_fail \
  bad-release-archive-no-overwrite \
  "VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE must be 0 or 1" \
  env VERIFY_GITHUB_RELEASE_DRY_RUN=1 VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=maybe \
    RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-install.sh

VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  GITHUB_RELEASE_REPOSITORY=example/gxfkit \
  VERIFY_GITHUB_RELEASE_LINUX_IMAGE=alpine:3.20 \
  VERIFY_GITHUB_RELEASE_LINUX_PLATFORM=linux/amd64 \
  bash scripts/verify-github-release-linux-docker.sh >"$tmp/linux-dry-run.out"

grep -F "image=alpine:3.20" "$tmp/linux-dry-run.out" >/dev/null
grep -F "platform=linux/amd64" "$tmp/linux-dry-run.out" >/dev/null
grep -F "verify_no_overwrite=0" "$tmp/linux-dry-run.out" >/dev/null
grep -F "archive_verifier=/opt/gxfkit/scripts/verify-release-archive.sh" "$tmp/linux-dry-run.out" >/dev/null
grep -F \
  "archive=https://github.com/example/gxfkit/releases/download/v1.2.3/gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  "$tmp/linux-dry-run.out" >/dev/null

grep -F "bash /opt/gxfkit/scripts/verify-release-archive.sh" \
  scripts/verify-github-release-linux-docker.sh >/dev/null
grep -F 'VERIFY_RELEASE_ARCHIVE_SMOKE=0' \
  scripts/verify-github-release-linux-docker.sh >/dev/null
grep -F "download \"\$ARCHIVE_URL\" \"\$ARCHIVE_NAME\"" \
  scripts/verify-github-release-linux-docker.sh >/dev/null
grep -F "download \"\$CHECKSUM_URL\" \"\$ARCHIVE_NAME.sha256\"" \
  scripts/verify-github-release-linux-docker.sh >/dev/null
for curl_arg in \
  "--retry 10" \
  "--retry-all-errors" \
  "--retry-delay 2" \
  "--retry-max-time 300" \
  "--connect-timeout 30"
do
  grep -F -- "$curl_arg" scripts/verify-github-release-linux-docker.sh >/dev/null
done

VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN=1 \
  VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE=1 \
  RELEASE_TAG=v1.2.3 \
  PACKAGE=linux-x86_64-static \
  bash scripts/verify-github-release-linux-docker.sh >"$tmp/linux-strict-dry-run.out"
grep -F "verify_no_overwrite=1" "$tmp/linux-strict-dry-run.out" >/dev/null

expect_fail \
  bad-linux-package \
  "PACKAGE must be a Linux static release package" \
  env VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=macos-aarch64 \
    bash scripts/verify-github-release-linux-docker.sh

expect_fail \
  unknown-linux-package \
  "PACKAGE must be a Linux static release package" \
  env VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN=1 RELEASE_TAG=v1.2.3 PACKAGE=linux-riscv64-static \
    bash scripts/verify-github-release-linux-docker.sh

expect_fail \
  bad-linux-no-overwrite \
  "VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE must be 0 or 1" \
  env VERIFY_GITHUB_RELEASE_LINUX_DRY_RUN=1 VERIFY_GITHUB_RELEASE_LINUX_NO_OVERWRITE=maybe \
    RELEASE_TAG=v1.2.3 PACKAGE=linux-x86_64-static \
    bash scripts/verify-github-release-linux-docker.sh

echo "verified GitHub release verifier tests"
