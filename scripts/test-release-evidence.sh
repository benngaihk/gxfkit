#!/usr/bin/env bash
# Regression tests for scripts/release-evidence.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

test -x scripts/release-evidence.sh
scripts/release-evidence.sh --help >"$tmp/help.out"
grep -F "the public-audit-* options validate that" "$tmp/help.out" >/dev/null
grep -F "The final strict" "$tmp/help.out" >/dev/null
grep -F -- "--public-audit-crates-install-script" "$tmp/help.out" >/dev/null

scripts/release-evidence.sh --allow-dirty >"$tmp/report.md"

grep -F "# gxfkit Release Evidence" "$tmp/report.md" >/dev/null
grep -F -- "- Checkout workspace version:" "$tmp/report.md" >/dev/null
grep -F -- "- Target release version:" "$tmp/report.md" >/dev/null
grep -F "## Tag Readiness" "$tmp/report.md" >/dev/null
grep -F "## Maintainer Surface Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-maintainer-surfaces.py" "$tmp/report.md" >/dev/null
grep -F "## Workflow Policy Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-workflow-policy.py" "$tmp/report.md" >/dev/null
grep -F "## Release Artifact Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-release-artifacts.py" "$tmp/report.md" >/dev/null
grep -F "verified release artifact contract" "$tmp/report.md" >/dev/null
grep -F "## Crates.io Metadata Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-crate-metadata.py" "$tmp/report.md" >/dev/null
grep -F "## Package File List Guards" "$tmp/report.md" >/dev/null
grep -F "bash scripts/check-package-files.sh" "$tmp/report.md" >/dev/null
grep -F "verified locked package file lists for gxfkit-core gxfkit" "$tmp/report.md" >/dev/null
grep -F "## Bioconda Recipe Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-bioconda-recipe.py" "$tmp/report.md" >/dev/null
grep -F "## Local Benchmark Summary" "$tmp/report.md" >/dev/null
grep -F "Command: \`python3 scripts/check-benchmark-summary.py benchmark/results/summary.tsv\`" \
  "$tmp/report.md" >/dev/null
grep -F "Exit: \`0\`" "$tmp/report.md" >/dev/null
grep -F "Validation:" "$tmp/report.md" >/dev/null
if [ -f benchmark/results/summary.tsv ]; then
  grep -F "Source: \`benchmark/results/summary.tsv\`" "$tmp/report.md" >/dev/null
  grep -F "verified benchmark summary: human_chr1 human_chr21 yeast parity >= 100%" \
    "$tmp/report.md" >/dev/null
else
  grep -F "RUNS=1 BENCH_FILES=\"human_chr1 human_chr21 yeast\" README_OUT= bash benchmark/run.sh" \
    "$tmp/report.md" >/dev/null
fi
grep -F "## Release Status Doc Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-release-status-doc.py" "$tmp/report.md" >/dev/null
grep -F "## Install Documentation Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-install-docs.py" "$tmp/report.md" >/dev/null
grep -F "## Release Guide Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-release-doc.py" "$tmp/report.md" >/dev/null
grep -F "## Release-Check Contract Guards" "$tmp/report.md" >/dev/null
grep -F "python3 scripts/check-release-check.py" "$tmp/report.md" >/dev/null
grep -F "verified release-check contract" "$tmp/report.md" >/dev/null
grep -F "## Public Readiness" "$tmp/report.md" >/dev/null
grep -F "## Strict Public Audit Dry Run" "$tmp/report.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_DRY_RUN=1" "$tmp/report.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALL_CHANNELS=github-linux\\ github-parity\\ bioconda\\ crates" "$tmp/report.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0" "$tmp/report.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1" "$tmp/report.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100" "$tmp/report.md" >/dev/null
grep -F "BENCH_FILES=human_chr1\\ human_chr21\\ yeast" "$tmp/report.md" >/dev/null
grep -F "github-parity=RELEASE_TAG=" "$tmp/report.md" >/dev/null
grep -F "VERSION=" "$tmp/report.md" >/dev/null
grep -F "RELEASE_TAG=" "$tmp/report.md" >/dev/null
grep -F "## Evidence Status" "$tmp/report.md" >/dev/null
grep -F "One or more evidence blocks exited non-zero" "$tmp/report.md" >/dev/null
grep -F -- "- \`Public Readiness\` exited \`1\`" "$tmp/report.md" >/dev/null
grep -F "## Final Closure Command" "$tmp/report.md" >/dev/null

cat >"$tmp/bad-summary.tsv" <<'TSV'
file	agat_s	gxfkit_s	speedup	agat_mem	gxfkit_mem	parity%
human_chr1	0	1.0	1x	1M	1M	100.00
TSV
RELEASE_EVIDENCE_BENCHMARK_SUMMARY="$tmp/bad-summary.tsv" \
  scripts/release-evidence.sh --allow-dirty >"$tmp/bad-summary-report.md"
grep -F "Command: \`python3 scripts/check-benchmark-summary.py $tmp/bad-summary.tsv\`" \
  "$tmp/bad-summary-report.md" >/dev/null
grep -F "ERROR $tmp/bad-summary.tsv: missing required benchmark rows: human_chr21, yeast" \
  "$tmp/bad-summary-report.md" >/dev/null
grep -F -- "- \`Local Benchmark Summary\` exited \`1\`" \
  "$tmp/bad-summary-report.md" >/dev/null
grep -F "## Final Closure Command" "$tmp/bad-summary-report.md" >/dev/null

VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  >"$tmp/override.md"
grep -F -- "- Target release version: \`9.8.7\`" "$tmp/override.md" >/dev/null
grep -F -- "- Release tag: \`v9.8.7\`" "$tmp/override.md" >/dev/null
grep -F "Command: \`python3 scripts/release-readiness.py --phase public --version 9.8.7 --allow-dirty\`" \
  "$tmp/override.md" >/dev/null
grep -F "python3 scripts/release-readiness.py --phase public --version 9.8.7 --check-public --run-public-audit" \
  "$tmp/override.md" >/dev/null
grep -F "VERSION=9.8.7 RELEASE_TAG=v9.8.7 bash scripts/verify-public-installs.sh" \
  "$tmp/override.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALL_CHANNELS=\"github-linux github-parity bioconda crates\"" \
  "$tmp/override.md" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0" "$tmp/override.md" >/dev/null

cat >"$tmp/release-check.log" <<'LOG'
>> formatting
>> linting
>> tests
>> release build
>> local cargo install
verified local cargo install verifier tests
gxfkit 9.8.7
verified local cargo install
>> Crates.io install verifier
verified Crates.io install verifier tests
>> Crates.io metadata
verified crates.io metadata tests
verified crates.io metadata
>> release archive verifier
verified release archive verifier tests
verified release artifact contract tests
verified release artifact contract
>> GitHub release verifier
verified GitHub release verifier tests
verified GitHub release parity verifier tests
>> Bioconda recipe
verified Bioconda recipe tests
verified GitHub source sha256 helper tests
>> Bioconda install verifier
verified Bioconda install verifier tests
>> public install audit verifier
verified public install verifier tests
verified public audit log tests
verified shell script syntax
verified python script syntax
verified release-check contract
verified release-check contract tests
verified release-check contract
verified release-check log tests
verified repository hygiene ignores
verified directly executable scripts
verified public install audit workflow
verified CI workflow
verified release workflow
verified Crates.io publish workflow
verified GitHub Actions workflow policy for 4 workflow(s)
verified workflow policy guard
>> publish ref verifier
verified publish ref tests
>> benchmark summarizer
verified benchmark summarize tests
verified benchmark summary tests
>> parity doc
verified parity doc tests
verified parity doc
>> residual writer
verified residual writer tests
>> version consistency self-test
verified version consistency tests
verified prepare next version tests
>> version consistency
OK crate versions: 9.8.7
>> release status doc
verified release status doc tests
verified release status doc
verified install docs tests
verified install docs
verified release guide tests
verified release guide
verified release notes for v9.8.7
verified release notes tests
>> release readiness verifier
verified release readiness tests
verified release evidence report tests
>> maintainer surfaces
verified maintainer surfaces tests
>> publish ref
>> package file lists
verified package file list tests
>> package gxfkit-core
>> package gxfkit
gxfkit package verification did not complete.
This is expected before gxfkit-core has been published to the registry.
>> release preflight complete
release-check-exit-code=0
LOG
VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  --release-check-log "$tmp/release-check.log" >"$tmp/recorded-release-check.md"
grep -F "## Recorded Release-Check Log Guards" "$tmp/recorded-release-check.md" >/dev/null
grep -F "python3 scripts/check-release-check-log.py --version 9.8.7" \
  "$tmp/recorded-release-check.md" >/dev/null
grep -F "verified release-check log" "$tmp/recorded-release-check.md" >/dev/null
grep -F "## Recorded Release-Check Output" "$tmp/recorded-release-check.md" >/dev/null
grep -F "release-check-exit-code=%s" \
  "$tmp/recorded-release-check.md" >/dev/null
grep -F ">> release preflight complete" "$tmp/recorded-release-check.md" >/dev/null
grep -F "release-check-exit-code=0" "$tmp/recorded-release-check.md" >/dev/null

cp "$tmp/release-check.log" "$tmp/failed-release-check.log"
printf '\nwarning: spurious network error (3 tries remaining): [28] Timeout was reached\n' \
  >>"$tmp/failed-release-check.log"
VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  --release-check-log "$tmp/failed-release-check.log" >"$tmp/failed-recorded-release-check.md"
grep -F "## Recorded Release-Check Log Guards" "$tmp/failed-recorded-release-check.md" >/dev/null
grep -F "Exit: \`1\`" "$tmp/failed-recorded-release-check.md" >/dev/null
grep -F "release-check log contains forbidden marker: spurious network error" \
  "$tmp/failed-recorded-release-check.md" >/dev/null
grep -F -- "- \`Recorded Release-Check Log Guards\` exited \`1\`" \
  "$tmp/failed-recorded-release-check.md" >/dev/null

cat >"$tmp/public-audit.log" <<'LOG'
public-audit-version=9.8.7
public-audit-tag=v9.8.7
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
VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  --public-audit-log "$tmp/public-audit.log" >"$tmp/recorded-audit.md"
grep -F "## Recorded Public Audit Log Guards" "$tmp/recorded-audit.md" >/dev/null
grep -F "## Final Strict Public Audit Log Guards" "$tmp/recorded-audit.md" >/dev/null
grep -F "python3 scripts/check-public-audit-log.py" "$tmp/recorded-audit.md" >/dev/null
grep -F -- "--version 9.8.7" "$tmp/recorded-audit.md" >/dev/null
grep -F -- "--tag v9.8.7" "$tmp/recorded-audit.md" >/dev/null
grep -F -- "--verify-no-overwrite 1" "$tmp/recorded-audit.md" >/dev/null
grep -F -- "--min-parity 100" "$tmp/recorded-audit.md" >/dev/null
grep -F -- "--crates-install-script scripts/verify-crates-install.sh" "$tmp/recorded-audit.md" >/dev/null
grep -F "verified strict public audit log" "$tmp/recorded-audit.md" >/dev/null
grep -F "## Strict Public Audit Recorded Output" "$tmp/recorded-audit.md" >/dev/null
grep -F 'Command: `VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 BENCH_FILES="human_chr1 human_chr21 yeast" VERSION=9.8.7 RELEASE_TAG=v9.8.7 bash scripts/verify-public-installs.sh`' \
  "$tmp/recorded-audit.md" >/dev/null
grep -F "public install summary: passed=[github-linux github-parity bioconda crates ]" \
  "$tmp/recorded-audit.md" >/dev/null
grep -F "public-audit-exit-code=0" "$tmp/recorded-audit.md" >/dev/null
grep -F "## Evidence Status" "$tmp/recorded-audit.md" >/dev/null

cat >"$tmp/staged-public-audit.log" <<'LOG'
public-audit-version=9.8.7
public-audit-tag=v9.8.7
public-audit-channels=github-linux github-parity bioconda crates
public-audit-allow-missing-crates=1
public-audit-no-overwrite=1
public-audit-min-parity=100
public-audit-bench-files=human_chr1 human_chr21 yeast
public-audit-crates-install-script=scripts/custom-crates-install.sh
>> public install: github-linux
>> public install: github-parity
>> public install: bioconda
>> public install: crates
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[crates ] failed=[]
public-audit-exit-code=0
LOG
VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  --public-audit-log "$tmp/staged-public-audit.log" \
  --public-audit-allow-missing-crates 1 \
  --public-audit-crates-install-script scripts/custom-crates-install.sh \
  >"$tmp/staged-recorded-audit.md"
grep -F "## Recorded Public Audit Log Guards" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F -- "--allow-missing-crates" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F -- "--crates-install-script scripts/custom-crates-install.sh" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F "verified public audit log with allowed missing crates" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F "## Final Strict Public Audit Log Guards" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F "strict public audit must not allow missing channels" "$tmp/staged-recorded-audit.md" >/dev/null
grep -F -- "- \`Final Strict Public Audit Log Guards\` exited \`1\`" \
  "$tmp/staged-recorded-audit.md" >/dev/null

cat >"$tmp/failed-public-audit.log" <<'LOG'
public-audit-version=9.8.7
public-audit-tag=v9.8.7
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
VERSION=9.8.7 RELEASE_TAG=v9.8.7 scripts/release-evidence.sh --allow-dirty \
  --public-audit-log "$tmp/failed-public-audit.log" >"$tmp/failed-recorded-audit.md"
grep -F "## Final Strict Public Audit Log Guards" "$tmp/failed-recorded-audit.md" >/dev/null
grep -F "Exit: \`1\`" "$tmp/failed-recorded-audit.md" >/dev/null
grep -F "strict public audit has failed channels" "$tmp/failed-recorded-audit.md" >/dev/null
grep -F -- "- \`Final Strict Public Audit Log Guards\` exited \`1\`" \
  "$tmp/failed-recorded-audit.md" >/dev/null

if scripts/release-evidence.sh --public-audit-log >"$tmp/missing-log-arg.out" 2>&1; then
  echo "missing --public-audit-log path unexpectedly passed" >&2
  cat "$tmp/missing-log-arg.out" >&2
  exit 1
fi
grep -F -- "--public-audit-log requires a path" "$tmp/missing-log-arg.out" >/dev/null

if scripts/release-evidence.sh --release-check-log >"$tmp/missing-release-check-log-arg.out" 2>&1; then
  echo "missing --release-check-log path unexpectedly passed" >&2
  cat "$tmp/missing-release-check-log-arg.out" >&2
  exit 1
fi
grep -F -- "--release-check-log requires a path" "$tmp/missing-release-check-log-arg.out" >/dev/null

if scripts/release-evidence.sh --public-audit-allow-missing-crates maybe \
  >"$tmp/bad-allow-missing.out" 2>&1; then
  echo "bad --public-audit-allow-missing-crates unexpectedly passed" >&2
  cat "$tmp/bad-allow-missing.out" >&2
  exit 1
fi
grep -F -- "--public-audit-allow-missing-crates must be 0 or 1" \
  "$tmp/bad-allow-missing.out" >/dev/null

if scripts/release-evidence.sh \
  --public-audit-channels github-parity \
  --public-audit-allow-missing-crates 1 \
  >"$tmp/allow-missing-without-crates.out" 2>&1; then
  echo "allow-missing without crates unexpectedly passed" >&2
  cat "$tmp/allow-missing-without-crates.out" >&2
  exit 1
fi
grep -F -- "--public-audit-allow-missing-crates=1 requires the crates channel" \
  "$tmp/allow-missing-without-crates.out" >/dev/null

if scripts/release-evidence.sh --public-audit-no-overwrite maybe \
  >"$tmp/bad-no-overwrite.out" 2>&1; then
  echo "bad --public-audit-no-overwrite unexpectedly passed" >&2
  cat "$tmp/bad-no-overwrite.out" >&2
  exit 1
fi
grep -F -- "--public-audit-no-overwrite must be 0 or 1" \
  "$tmp/bad-no-overwrite.out" >/dev/null

if scripts/release-evidence.sh --public-audit-channels "github-linux unknown" \
  >"$tmp/bad-channels.out" 2>&1; then
  echo "bad --public-audit-channels unexpectedly passed" >&2
  cat "$tmp/bad-channels.out" >&2
  exit 1
fi
grep -F -- "--public-audit-channels contains unknown channel: unknown" \
  "$tmp/bad-channels.out" >/dev/null

if scripts/release-evidence.sh --public-audit-channels "crates crates" \
  >"$tmp/duplicate-channels.out" 2>&1; then
  echo "duplicate --public-audit-channels unexpectedly passed" >&2
  cat "$tmp/duplicate-channels.out" >&2
  exit 1
fi
grep -F -- "--public-audit-channels must not repeat: crates" \
  "$tmp/duplicate-channels.out" >/dev/null

if scripts/release-evidence.sh --public-audit-channels "   " \
  >"$tmp/empty-channels.out" 2>&1; then
  echo "empty --public-audit-channels unexpectedly passed" >&2
  cat "$tmp/empty-channels.out" >&2
  exit 1
fi
grep -F -- "--public-audit-channels must include at least one channel" \
  "$tmp/empty-channels.out" >/dev/null

if scripts/release-evidence.sh --public-audit-min-parity high \
  >"$tmp/bad-min-parity.out" 2>&1; then
  echo "bad --public-audit-min-parity unexpectedly passed" >&2
  cat "$tmp/bad-min-parity.out" >&2
  exit 1
fi
grep -F -- "--public-audit-min-parity must be a number, got: high" \
  "$tmp/bad-min-parity.out" >/dev/null

if scripts/release-evidence.sh --public-audit-min-parity 101 \
  >"$tmp/too-high-min-parity.out" 2>&1; then
  echo "too-high --public-audit-min-parity unexpectedly passed" >&2
  cat "$tmp/too-high-min-parity.out" >&2
  exit 1
fi
grep -F -- "--public-audit-min-parity must be between 0 and 100, got: 101" \
  "$tmp/too-high-min-parity.out" >/dev/null

if scripts/release-evidence.sh --public-audit-bench-files "../yeast" \
  >"$tmp/bad-bench-files.out" 2>&1; then
  echo "bad --public-audit-bench-files unexpectedly passed" >&2
  cat "$tmp/bad-bench-files.out" >&2
  exit 1
fi
grep -F -- "--public-audit-bench-files entries must be corpus basenames, got: ../yeast" \
  "$tmp/bad-bench-files.out" >/dev/null

if scripts/release-evidence.sh --public-audit-bench-files "yeast yeast" \
  >"$tmp/duplicate-bench-files.out" 2>&1; then
  echo "duplicate --public-audit-bench-files unexpectedly passed" >&2
  cat "$tmp/duplicate-bench-files.out" >&2
  exit 1
fi
grep -F -- "--public-audit-bench-files must not repeat: yeast" \
  "$tmp/duplicate-bench-files.out" >/dev/null

if scripts/release-evidence.sh --public-audit-crates-install-script "scripts/bad script.sh" \
  >"$tmp/bad-crates-install-script.out" 2>&1; then
  echo "bad --public-audit-crates-install-script unexpectedly passed" >&2
  cat "$tmp/bad-crates-install-script.out" >&2
  exit 1
fi
grep -F -- "--public-audit-crates-install-script must be a non-empty repository-relative scripts/*.sh path without whitespace" \
  "$tmp/bad-crates-install-script.out" >/dev/null

if scripts/release-evidence.sh --public-audit-crates-install-script "/tmp/verify-crates-install.sh" \
  >"$tmp/absolute-crates-install-script.out" 2>&1; then
  echo "absolute --public-audit-crates-install-script unexpectedly passed" >&2
  cat "$tmp/absolute-crates-install-script.out" >&2
  exit 1
fi
grep -F -- "--public-audit-crates-install-script must be a repository-relative scripts/*.sh path" \
  "$tmp/absolute-crates-install-script.out" >/dev/null

if scripts/release-evidence.sh --public-audit-crates-install-script "scripts/../verify-crates-install.sh" \
  >"$tmp/traversal-crates-install-script.out" 2>&1; then
  echo "traversal --public-audit-crates-install-script unexpectedly passed" >&2
  cat "$tmp/traversal-crates-install-script.out" >&2
  exit 1
fi
grep -F -- "--public-audit-crates-install-script must be a repository-relative scripts/*.sh path" \
  "$tmp/traversal-crates-install-script.out" >/dev/null

if VERSION=nope scripts/release-evidence.sh >"$tmp/bad-version-value.out" 2>&1; then
  echo "bad VERSION unexpectedly passed" >&2
  cat "$tmp/bad-version-value.out" >&2
  exit 1
fi
grep -F "VERSION must look like X.Y.Z, got: nope" "$tmp/bad-version-value.out" >/dev/null

if VERSION=9.8.7 RELEASE_TAG=9.8.7 scripts/release-evidence.sh >"$tmp/bad-tag-prefix.out" 2>&1; then
  echo "bad RELEASE_TAG prefix unexpectedly passed" >&2
  cat "$tmp/bad-tag-prefix.out" >&2
  exit 1
fi
grep -F "RELEASE_TAG must start with v, got: 9.8.7" "$tmp/bad-tag-prefix.out" >/dev/null

if VERSION=9.8.7 RELEASE_TAG=v9.8.8 scripts/release-evidence.sh >"$tmp/bad-version.out" 2>&1; then
  echo "mismatched VERSION/RELEASE_TAG unexpectedly passed" >&2
  cat "$tmp/bad-version.out" >&2
  exit 1
fi
grep -F "VERSION and RELEASE_TAG disagree" "$tmp/bad-version.out" >/dev/null

if scripts/release-evidence.sh --definitely-not-real >"$tmp/bad.out" 2>&1; then
  echo "bad argument unexpectedly passed" >&2
  cat "$tmp/bad.out" >&2
  exit 1
fi
grep -F "unknown argument" "$tmp/bad.out" >/dev/null

echo "verified release evidence report tests"
