#!/usr/bin/env bash
# Regression tests for scripts/check-public-audit-log.py.
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
  if ! grep -F "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

cat >"$tmp/ok.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
python3 scripts/check-public-audit-log.py "$tmp/ok.log" >"$tmp/ok.out"
grep -F "verified strict public audit log" "$tmp/ok.out" >/dev/null
python3 scripts/check-public-audit-log.py \
  --version 1.2.3 \
  --tag v1.2.3 \
  --verify-no-overwrite 1 \
  --min-parity 100 \
  --bench-files "human_chr1 human_chr21 yeast" \
  "$tmp/ok.log" \
  >"$tmp/ok-version-tag.out"
grep -F "verified strict public audit log" "$tmp/ok-version-tag.out" >/dev/null

expect_fail \
  wrong-version \
  "public audit version must be 1.2.4, got 1.2.3" \
  python3 scripts/check-public-audit-log.py --version 1.2.4 "$tmp/ok.log"

expect_fail \
  wrong-tag \
  "public audit tag must be v1.2.4, got v1.2.3" \
  python3 scripts/check-public-audit-log.py --tag v1.2.4 "$tmp/ok.log"

expect_fail \
  bad-expected-version \
  "argument --version: must look like X.Y.Z, got: nope" \
  python3 scripts/check-public-audit-log.py --version nope "$tmp/ok.log"

expect_fail \
  bad-expected-tag-prefix \
  "argument --tag: must start with v, got: 1.2.3" \
  python3 scripts/check-public-audit-log.py --tag 1.2.3 "$tmp/ok.log"

expect_fail \
  bad-expected-tag-version \
  "argument --tag: must look like vX.Y.Z, got: vnope" \
  python3 scripts/check-public-audit-log.py --tag vnope "$tmp/ok.log"

expect_fail \
  expected-version-tag-mismatch \
  "ERROR version and tag disagree: version=1.2.3 tag=v1.2.4" \
  python3 scripts/check-public-audit-log.py --version 1.2.3 --tag v1.2.4 "$tmp/ok.log"

expect_fail \
  bad-expected-crates-install-script-absolute \
  "argument --crates-install-script: must be a repository-relative scripts/*.sh path" \
  python3 scripts/check-public-audit-log.py --crates-install-script /tmp/verify-crates-install.sh "$tmp/ok.log"

expect_fail \
  bad-expected-crates-install-script-traversal \
  "argument --crates-install-script: must be a repository-relative scripts/*.sh path" \
  python3 scripts/check-public-audit-log.py --crates-install-script scripts/../verify-crates-install.sh "$tmp/ok.log"

expect_fail \
  wrong-no-overwrite \
  "public audit no-overwrite must be 0, got 1" \
  python3 scripts/check-public-audit-log.py --verify-no-overwrite 0 "$tmp/ok.log"

cp "$tmp/ok.log" "$tmp/bad-crates-install-script-absolute.log"
perl -0pi -e 's#public-audit-crates-install-script=scripts/verify-crates-install\.sh#public-audit-crates-install-script=/tmp/verify-crates-install.sh#' \
  "$tmp/bad-crates-install-script-absolute.log"
expect_fail \
  bad-crates-install-script-absolute \
  "public audit crates install script must be a repository-relative scripts/*.sh path" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-crates-install-script-absolute.log"

cp "$tmp/ok.log" "$tmp/bad-crates-install-script-traversal.log"
perl -0pi -e 's#public-audit-crates-install-script=scripts/verify-crates-install\.sh#public-audit-crates-install-script=scripts/../verify-crates-install.sh#' \
  "$tmp/bad-crates-install-script-traversal.log"
expect_fail \
  bad-crates-install-script-traversal \
  "public audit crates install script must be a repository-relative scripts/*.sh path" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-crates-install-script-traversal.log"

expect_fail \
  wrong-min-parity \
  "public audit min parity must be 99, got 100" \
  python3 scripts/check-public-audit-log.py --min-parity 99 "$tmp/ok.log"

expect_fail \
  wrong-bench-files \
  "public audit bench files must be yeast, got human_chr1 human_chr21 yeast" \
  python3 scripts/check-public-audit-log.py --bench-files yeast "$tmp/ok.log"

expect_fail \
  wrong-crates-install-script \
  "public audit crates install script must be scripts/other-crates-install.sh, got scripts/verify-crates-install.sh" \
  python3 scripts/check-public-audit-log.py \
    --crates-install-script scripts/other-crates-install.sh "$tmp/ok.log"

expect_fail \
  bad-expected-no-overwrite \
  "argument --verify-no-overwrite: must be 0 or 1, got: maybe" \
  python3 scripts/check-public-audit-log.py --verify-no-overwrite maybe "$tmp/ok.log"

expect_fail \
  bad-expected-min-parity \
  "argument --min-parity: must be a number, got: high" \
  python3 scripts/check-public-audit-log.py --min-parity high "$tmp/ok.log"

expect_fail \
  too-high-expected-min-parity \
  "argument --min-parity: must be between 0 and 100, got: 101" \
  python3 scripts/check-public-audit-log.py --min-parity 101 "$tmp/ok.log"

expect_fail \
  duplicate-expected-bench-files \
  "argument --bench-files: must not repeat: yeast" \
  python3 scripts/check-public-audit-log.py --bench-files "yeast yeast" "$tmp/ok.log"

expect_fail \
  bad-expected-crates-install-script \
  "argument --crates-install-script: must be a repository-relative scripts/*.sh path without whitespace" \
  python3 scripts/check-public-audit-log.py --crates-install-script "scripts/bad script.sh" "$tmp/ok.log"

expect_fail \
  path-expected-bench-file \
  "argument --bench-files: entries must be corpus basenames, got: corpus/yeast" \
  python3 scripts/check-public-audit-log.py --bench-files "corpus/yeast" "$tmp/ok.log"

expect_fail \
  glob-expected-bench-file \
  "argument --bench-files: entries must be corpus basenames, got: *" \
  python3 scripts/check-public-audit-log.py --bench-files "*" "$tmp/ok.log"

expect_fail \
  dot-expected-bench-file \
  "argument --bench-files: entries must be corpus basenames, got: ." \
  python3 scripts/check-public-audit-log.py --bench-files "." "$tmp/ok.log"

expect_fail \
  duplicate-expected-channels \
  "argument --channels: channels must not repeat: github-linux" \
  python3 scripts/check-public-audit-log.py \
    --channels "github-linux github-linux github-parity bioconda crates" \
    "$tmp/ok.log"

expect_fail \
  unknown-expected-channel \
  "argument --channels: unknown channels: unknown" \
  python3 scripts/check-public-audit-log.py \
    --channels "github-linux unknown" \
    "$tmp/ok.log"

cat >"$tmp/duplicate-metadata.log" <<'LOG'
public-audit-version=old
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-metadata \
  "public audit log has duplicate metadata key: public-audit-version" \
  python3 scripts/check-public-audit-log.py --version 1.2.3 --tag v1.2.3 "$tmp/duplicate-metadata.log"

cat >"$tmp/duplicate-metadata-channel.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-metadata-channel \
  "public audit metadata channels must not repeat: github-linux" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-metadata-channel.log"

cat >"$tmp/wrong-metadata-channel-order.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux bioconda github-parity crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  wrong-metadata-channel-order \
  "public audit metadata channel order must be ['github-linux', 'github-parity', 'bioconda', 'crates'], got ['github-linux', 'bioconda', 'github-parity', 'crates']" \
  python3 scripts/check-public-audit-log.py "$tmp/wrong-metadata-channel-order.log"

cat >"$tmp/unknown-metadata.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
public-audit-min-paroty=100
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  unknown-metadata \
  "public audit log has unknown metadata key: public-audit-min-paroty" \
  python3 scripts/check-public-audit-log.py "$tmp/unknown-metadata.log"

cat >"$tmp/duplicate-summary.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[] failed=[crates ]
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-summary \
  "public audit log must contain exactly one public install summary" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-summary.log"

cat >"$tmp/decorated-summary.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
noise public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[] trailing
public-audit-exit-code=0
LOG
expect_fail \
  decorated-summary \
  "public audit log is missing the public install summary" \
  python3 scripts/check-public-audit-log.py "$tmp/decorated-summary.log"

cat >"$tmp/duplicate-summary-channel.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-summary-channel \
  "public audit summary must account for each channel once, got github-linux 2 times" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-summary-channel.log"

cat >"$tmp/duplicate-exit-code.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=1
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-exit-code \
  "public audit log must contain exactly one public-audit-exit-code" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-exit-code.log"

cat >"$tmp/duplicate-channel-section.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-channel-section \
  "public audit log has duplicate channel section: github-linux" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-channel-section.log"

cat >"$tmp/unexpected-channel-section.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
>> public install: unknown
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  unexpected-channel-section \
  "public audit log has unexpected channel section: unknown" \
  python3 scripts/check-public-audit-log.py "$tmp/unexpected-channel-section.log"

cat >"$tmp/wrong-channel-section-order.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: bioconda
>> public install: github-parity
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  wrong-channel-section-order \
  "public audit channel sections must be in order ['github-linux', 'github-parity', 'bioconda', 'crates'], got ['github-linux', 'bioconda', 'github-parity', 'crates']" \
  python3 scripts/check-public-audit-log.py "$tmp/wrong-channel-section-order.log"

cat >"$tmp/missing-version-tag.log" <<'LOG'
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  missing-version \
  "public audit log is missing public-audit-version" \
  python3 scripts/check-public-audit-log.py --version 1.2.3 "$tmp/missing-version-tag.log"
expect_fail \
  missing-tag \
  "public audit log is missing public-audit-tag" \
  python3 scripts/check-public-audit-log.py --tag v1.2.3 "$tmp/missing-version-tag.log"

cat >"$tmp/bad-metadata-version.log" <<'LOG'
public-audit-version=nope
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-metadata-version \
  "public audit version must look like X.Y.Z, got nope" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-metadata-version.log"

cat >"$tmp/bad-metadata-tag.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-metadata-tag \
  "public audit tag must start with v, got 1.2.3" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-metadata-tag.log"

cat >"$tmp/mismatched-metadata-version-tag.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.4
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  mismatched-metadata-version-tag \
  "public audit version and tag disagree: version=1.2.3 tag=v1.2.4" \
  python3 scripts/check-public-audit-log.py "$tmp/mismatched-metadata-version-tag.log"

cat >"$tmp/missing-required-metadata.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  missing-metadata-channels \
  "public audit log is missing public-audit-channels" \
  python3 scripts/check-public-audit-log.py "$tmp/missing-required-metadata.log"

cat >"$tmp/missing-strict-metadata.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  missing-no-overwrite \
  "public audit log is missing public-audit-no-overwrite" \
  python3 scripts/check-public-audit-log.py "$tmp/missing-strict-metadata.log"

cat >"$tmp/bad-metadata-allow-missing.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=maybe
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-metadata-allow-missing \
  "public audit allow-missing-crates must be 0 or 1, got: maybe" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-metadata-allow-missing.log"

cat >"$tmp/bad-metadata-no-overwrite.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=maybe
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-metadata-no-overwrite \
  "public audit no-overwrite must be 0 or 1, got: maybe" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-metadata-no-overwrite.log"

cat >"$tmp/bad-metadata-min-parity.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=high
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-metadata-min-parity \
  "public audit min parity must be a number, got: high" \
  python3 scripts/check-public-audit-log.py "$tmp/bad-metadata-min-parity.log"

cat >"$tmp/too-high-metadata-min-parity.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=101
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  too-high-metadata-min-parity \
  "public audit min parity must be between 0 and 100, got: 101" \
  python3 scripts/check-public-audit-log.py "$tmp/too-high-metadata-min-parity.log"

cat >"$tmp/path-metadata-bench-file.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 corpus/yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  path-metadata-bench-file \
  "public audit bench files entries must be corpus basenames, got: corpus/yeast" \
  python3 scripts/check-public-audit-log.py "$tmp/path-metadata-bench-file.log"

cat >"$tmp/duplicate-metadata-bench-file.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 yeast yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  duplicate-metadata-bench-file \
  "public audit bench files must not repeat: yeast" \
  python3 scripts/check-public-audit-log.py "$tmp/duplicate-metadata-bench-file.log"

cat >"$tmp/missing-channel.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux bioconda crates ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  missing-channel \
  "public audit channels must be" \
  python3 scripts/check-public-audit-log.py "$tmp/missing-channel.log"

cat >"$tmp/allowed-missing.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=1
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[crates ] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  allowed-missing \
  "strict public audit must not allow missing channels" \
  python3 scripts/check-public-audit-log.py "$tmp/allowed-missing.log"
python3 scripts/check-public-audit-log.py --allow-missing-crates "$tmp/allowed-missing.log" \
  >"$tmp/allowed-missing-ok.out"
grep -F "verified public audit log with allowed missing crates" \
  "$tmp/allowed-missing-ok.out" >/dev/null

expect_fail \
  allow-missing-metadata-mismatch \
  "public audit allow-missing-crates must be 0, got 1" \
  python3 scripts/check-public-audit-log.py "$tmp/allowed-missing.log"

cat >"$tmp/subset.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-parity
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-parity
public install summary: passed=[github-parity ] allowed_missing=[] failed=[]
public-audit-exit-code=0
LOG
python3 scripts/check-public-audit-log.py --channels "github-parity" "$tmp/subset.log" \
  >"$tmp/subset.out"
grep -F "verified strict public audit log" "$tmp/subset.out" >/dev/null

cat >"$tmp/bad-allowed-missing.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=1
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity crates ] allowed_missing=[bioconda ] failed=[]
public-audit-exit-code=0
LOG
expect_fail \
  bad-allowed-missing \
  "public audit may only allow missing crates" \
  python3 scripts/check-public-audit-log.py --allow-missing-crates "$tmp/bad-allowed-missing.log"

cat >"$tmp/failed.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[] failed=[crates ]
public-audit-exit-code=1
LOG
expect_fail \
  failed-channel \
  "strict public audit has failed channels" \
  python3 scripts/check-public-audit-log.py "$tmp/failed.log"

cat >"$tmp/no-exit-code.log" <<'LOG'
public-audit-version=1.2.3
public-audit-tag=v1.2.3
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=0
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/verify-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
LOG
expect_fail \
  no-exit-code \
  "public audit log is missing public-audit-exit-code" \
  python3 scripts/check-public-audit-log.py "$tmp/no-exit-code.log"

echo "verified public audit log tests"
