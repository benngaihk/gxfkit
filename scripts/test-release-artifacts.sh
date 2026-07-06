#!/usr/bin/env bash
# Regression tests for scripts/check-release-artifacts.py.
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

"$PY" scripts/check-release-artifacts.py >"$tmp/real.out"
grep -F "verified release artifact contract" "$tmp/real.out" >/dev/null

mkdir -p "$tmp/dist"
for package in linux-x86_64-static linux-aarch64-static macos-x86_64 macos-aarch64; do
  printf 'archive\n' >"$tmp/dist/gxfkit-v1.2.3-${package}.tar.gz"
  printf 'checksum\n' >"$tmp/dist/gxfkit-v1.2.3-${package}.tar.gz.sha256"
done
"$PY" scripts/check-release-dist.py --tag v1.2.3 --dist "$tmp/dist" \
  >"$tmp/dist-ok.out"
grep -F "verified release dist artifact set: 4 package(s), 8 artifact(s)" \
  "$tmp/dist-ok.out" >/dev/null

rm "$tmp/dist/gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256"
expect_fail \
  missing-dist-checksum \
  "missing release artifact(s): gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256" \
  "$PY" scripts/check-release-dist.py --tag v1.2.3 --dist "$tmp/dist"
printf 'checksum\n' >"$tmp/dist/gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256"

printf 'archive\n' >"$tmp/dist/gxfkit-v1.2.3-linux-riscv64-static.tar.gz"
expect_fail \
  unexpected-dist-archive \
  "unexpected release package artifact(s): gxfkit-v1.2.3-linux-riscv64-static.tar.gz" \
  "$PY" scripts/check-release-dist.py --tag v1.2.3 --dist "$tmp/dist"
rm "$tmp/dist/gxfkit-v1.2.3-linux-riscv64-static.tar.gz"

: >"$tmp/dist/gxfkit-v1.2.3-linux-x86_64-static.tar.gz"
expect_fail \
  empty-dist-archive \
  "release artifact is empty: gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  "$PY" scripts/check-release-dist.py --tag v1.2.3 --dist "$tmp/dist"

expect_fail \
  bad-dist-tag \
  "ERROR --tag must look like vX.Y.Z" \
  "$PY" scripts/check-release-dist.py --tag 1.2.3 --dist "$tmp/dist"

cp .github/workflows/release.yml "$tmp/release.yml"
cp scripts/verify-release-archive.sh "$tmp/verify-release-archive.sh"
cp scripts/release-readiness.py "$tmp/release-readiness.py"

perl -0pi -e 's/\n          rm -rf "dist\/\$\{name\}"//' "$tmp/release.yml"
expect_fail \
  missing-clean-staging \
  'clean archive staging directory is missing: rm -rf "dist/${name}"' \
  "$PY" scripts/check-release-artifacts.py \
    --workflow "$tmp/release.yml" \
    --verifier "$tmp/verify-release-archive.sh"

cp .github/workflows/release.yml "$tmp/release.yml"
perl -0pi -e 's/gxfkit-\$\{RELEASE_TAG\}-\$\{PACKAGE\}/gxfkit-\$\{PACKAGE\}/' \
  "$tmp/release.yml"
expect_fail \
  bad-archive-name \
  'archive base name is missing: name="gxfkit-${RELEASE_TAG}-${PACKAGE}"' \
  "$PY" scripts/check-release-artifacts.py \
    --workflow "$tmp/release.yml" \
    --verifier "$tmp/verify-release-archive.sh"

cp .github/workflows/release.yml "$tmp/release.yml"
perl -0pi -e 's/dist\/\*\.tar\.gz\.sha256/dist\/\*\.sha256/g' "$tmp/release.yml"
expect_fail \
  bad-checksum-upload \
  "artifact upload/release checksums must appear 2 time(s), found 0: dist/*.tar.gz.sha256" \
  "$PY" scripts/check-release-artifacts.py \
    --workflow "$tmp/release.yml" \
    --verifier "$tmp/verify-release-archive.sh"

cp .github/workflows/release.yml "$tmp/release.yml"
perl -0pi -e 's/VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION/VERIFY_RELEASE_ARCHIVE_VERSION/g' \
  "$tmp/release.yml"
expect_fail \
  missing-version-check \
  "archive version verification is missing: VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION" \
  "$PY" scripts/check-release-artifacts.py \
    --workflow "$tmp/release.yml" \
    --verifier "$tmp/verify-release-archive.sh"

cp scripts/release-readiness.py "$tmp/release-readiness.py"
perl -0pi -e 's/"macos-aarch64",/"linux-riscv64-static",/' "$tmp/release-readiness.py"
expect_fail \
  readiness-package-mismatch \
  "release-readiness packages differ from expected set: linux-aarch64-static, linux-riscv64-static, linux-x86_64-static, macos-x86_64; expected: linux-aarch64-static, linux-x86_64-static, macos-aarch64, macos-x86_64" \
  "$PY" scripts/check-release-artifacts.py \
    --workflow .github/workflows/release.yml \
    --verifier "$tmp/verify-release-archive.sh" \
    --readiness "$tmp/release-readiness.py"

cp scripts/release-readiness.py "$tmp/release-readiness.py"
perl -0pi -e 's/"macos-aarch64",/"macos-x86_64",/' "$tmp/release-readiness.py"
expect_fail \
  readiness-package-duplicate \
  "release-readiness RELEASE_PACKAGES must not contain duplicates" \
  "$PY" scripts/check-release-artifacts.py \
    --workflow .github/workflows/release.yml \
    --verifier "$tmp/verify-release-archive.sh" \
    --readiness "$tmp/release-readiness.py"

cp scripts/verify-release-archive.sh "$tmp/verify-release-archive.sh"
perl -0pi -e 's/gxfkit-v\*\.tar\.gz/gxfkit-\*\.tar\.gz/' "$tmp/verify-release-archive.sh"
expect_fail \
  bad-verifier-glob \
  "archive name case glob is missing: gxfkit-v*.tar.gz) ;;" \
  "$PY" scripts/check-release-artifacts.py \
    --workflow .github/workflows/release.yml \
    --verifier "$tmp/verify-release-archive.sh"

echo "verified release artifact contract tests"
