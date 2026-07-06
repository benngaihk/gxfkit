#!/usr/bin/env bash
# Regression tests for scripts/release-readiness.py.
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

make_fixture() {
  local dir="$1"
  local version="$2"
  mkdir -p "$dir/crates/gxfkit" "$dir/packaging/bioconda/recipe" \
    "$dir/scripts" "$dir/docs/releases"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "gxfkit test"
  cat >"$dir/Cargo.toml" <<TOML
[workspace]
members = ["crates/gxfkit-core", "crates/gxfkit"]

[workspace.package]
version = "$version"
TOML
  cat >"$dir/crates/gxfkit/Cargo.toml" <<TOML
[package]
name = "gxfkit"

[dependencies]
gxfkit-core = { version = "$version", path = "../gxfkit-core" }
TOML
  cat >"$dir/packaging/bioconda/recipe/meta.yaml" <<YAML
{% set version = "$version" %}
source:
  sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
  cat >"$dir/docs/releases/v${version}.md" <<MD
# gxfkit v${version} Release Notes
MD
  cat >"$dir/scripts/check-release-notes.py" <<'PY'
#!/usr/bin/env python3
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--expected-version", required=True)
args = parser.parse_args()
path = Path("docs/releases") / f"v{args.expected_version}.md"
if not path.is_file():
    raise SystemExit(f"missing release notes: {path}")
print(f"verified release notes for v{args.expected_version}")
PY
  cat >"$dir/scripts/check-maintainer-surfaces.py" <<'PY'
#!/usr/bin/env python3
print("verified maintainer surfaces")
PY
  cat >"$dir/scripts/check-workflow-policy.py" <<'PY'
#!/usr/bin/env python3
print("verified GitHub Actions workflow policy")
PY
  cat >"$dir/scripts/test-ci-workflow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified CI workflow"
SH
  cat >"$dir/scripts/test-release-workflow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified release workflow"
SH
  cat >"$dir/scripts/test-publish-crates-workflow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified Crates.io publish workflow"
SH
  cat >"$dir/scripts/test-public-install-audit-workflow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified public install audit workflow"
SH
  cat >"$dir/scripts/check-release-artifacts.py" <<'PY'
#!/usr/bin/env python3
print("verified release artifact contract")
PY
  cat >"$dir/scripts/check-crate-metadata.py" <<'PY'
#!/usr/bin/env python3
print("verified crates.io metadata")
PY
  cat >"$dir/scripts/check-package-files.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified package file lists for gxfkit-core gxfkit"
SH
  cat >"$dir/scripts/check-version-consistency.py" <<'PY'
#!/usr/bin/env python3
print("OK version consistency")
PY
  cat >"$dir/scripts/check-bioconda-recipe.py" <<'PY'
#!/usr/bin/env python3
print("verified Bioconda recipe")
PY
  cat >"$dir/scripts/check-benchmark-summary.py" <<'PY'
#!/usr/bin/env python3
print("verified benchmark summary: human_chr1 human_chr21 yeast parity >= 100%")
PY
  cat >"$dir/scripts/check-release-status-doc.py" <<'PY'
#!/usr/bin/env python3
print("verified release status doc")
PY
  cat >"$dir/scripts/check-install-docs.py" <<'PY'
#!/usr/bin/env python3
print("verified install docs")
PY
  cat >"$dir/scripts/check-release-doc.py" <<'PY'
#!/usr/bin/env python3
print("verified release guide")
PY
  cat >"$dir/scripts/check-release-check.py" <<'PY'
#!/usr/bin/env python3
print("verified release-check contract")
PY
  cat >"$dir/scripts/check-parity-doc.py" <<'PY'
#!/usr/bin/env python3
print("verified parity doc")
PY
  cat >"$dir/scripts/test-shell-syntax.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified shell script syntax"
SH
  cat >"$dir/scripts/test-python-syntax.py" <<'PY'
#!/usr/bin/env python3
print("verified python script syntax")
PY
  cat >"$dir/scripts/test-repo-hygiene.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified repository hygiene ignores"
SH
  cat >"$dir/scripts/test-executable-scripts.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "verified directly executable scripts"
SH
  git -C "$dir" add .
  git -C "$dir" commit -q -m initial
}

fixture="$tmp/tag-ready"
make_fixture "$fixture" 1.2.3
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag >"$tmp/tag-ready.out"
grep -F "PASS    cargo versions" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    git worktree: clean" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    publish ref: v1.2.3 does not exist yet" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    release notes: docs/releases/v1.2.3.md is ready" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    maintainer surfaces:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    workflow policy:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    workflow contracts:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    release artifacts:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    crate metadata:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    package file lists:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    version consistency:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    bioconda recipe:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    benchmark summary: verified benchmark summary: human_chr1 human_chr21 yeast parity >= 100%" \
  "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    release status doc:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    install docs:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    release guide:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    release-check contract:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    parity doc:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    shell syntax:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    python syntax:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    repo hygiene:" "$tmp/tag-ready.out" >/dev/null
grep -F "PASS    executable scripts:" "$tmp/tag-ready.out" >/dev/null
grep -F "status: ready" "$tmp/tag-ready.out" >/dev/null

fixture="$tmp/dirty"
make_fixture "$fixture" 1.2.3
printf '# dirty\n' >>"$fixture/Cargo.toml"
expect_fail \
  dirty \
  "PENDING git worktree: worktree has uncommitted changes" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag --allow-dirty \
  >"$tmp/dirty-allowed.out"
grep -F "WARN    git worktree: worktree has uncommitted changes (--allow-dirty)" \
  "$tmp/dirty-allowed.out" >/dev/null
grep -F "status: ready" "$tmp/dirty-allowed.out" >/dev/null

fixture="$tmp/bad-dep"
make_fixture "$fixture" 1.2.3
perl -0pi -e 's/gxfkit-core = \{ version = "1\.2\.3"/gxfkit-core = { version = "1.2.2"/' \
  "$fixture/crates/gxfkit/Cargo.toml"
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-dep
expect_fail \
  bad-dep \
  "FAIL    cargo versions: target is 1.2.3, workspace is 1.2.3, gxfkit-core dependency is 1.2.2" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/missing-release-notes"
make_fixture "$fixture" 1.2.3
rm "$fixture/docs/releases/v1.2.3.md"
git -C "$fixture" add -A
git -C "$fixture" commit -q -m missing-release-notes
expect_fail \
  missing-release-notes \
  "FAIL    release notes: missing release notes: docs/releases/v1.2.3.md" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-workflow-policy"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-workflow-policy.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("workflow missing timeout")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-workflow-policy
expect_fail \
  bad-workflow-policy \
  "FAIL    workflow policy: workflow missing timeout" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-workflow-contracts"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/test-public-install-audit-workflow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "public install audit workflow lost release-evidence upload" >&2
exit 1
SH
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-workflow-contracts
expect_fail \
  bad-workflow-contracts \
  "FAIL    workflow contracts: verified release workflow; verified Crates.io publish workflow; public install audit workflow lost release-evidence upload" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-release-artifacts"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-release-artifacts.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("release archive upload path is stale")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-release-artifacts
expect_fail \
  bad-release-artifacts \
  "FAIL    release artifacts: release archive upload path is stale" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-package-files"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-package-files.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "gxfkit package is missing LICENSE" >&2
exit 1
SH
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-package-files
expect_fail \
  bad-package-files \
  "FAIL    package file lists: gxfkit package is missing LICENSE" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-version-consistency"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-version-consistency.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("ERROR Bioconda sha256 values mismatch:")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-version-consistency
expect_fail \
  bad-version-consistency \
  "FAIL    version consistency: ERROR Bioconda sha256 values mismatch:" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/missing-benchmark-summary"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-benchmark-summary.py" <<'PY'
#!/usr/bin/env python3
print('benchmark summary not found; generate with RUNS=1 BENCH_FILES="human_chr1 human_chr21 yeast" README_OUT= bash benchmark/run.sh')
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m missing-benchmark-summary
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag >"$tmp/missing-benchmark-summary.out"
grep -F "WARN    benchmark summary: benchmark summary not found; generate with" \
  "$tmp/missing-benchmark-summary.out" >/dev/null
grep -F "status: ready" "$tmp/missing-benchmark-summary.out" >/dev/null

fixture="$tmp/bad-benchmark-summary"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-benchmark-summary.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("benchmark/results/summary.tsv: yeast parity 99.99% < 100%")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-benchmark-summary
expect_fail \
  bad-benchmark-summary \
  "FAIL    benchmark summary: benchmark/results/summary.tsv: yeast parity 99.99% < 100%" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-install-docs"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-install-docs.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("README install section is stale")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-install-docs
expect_fail \
  bad-install-docs \
  "FAIL    install docs: README install section is stale" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-release-guide"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-release-doc.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("release guide is stale")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-release-guide
expect_fail \
  bad-release-guide \
  "FAIL    release guide: release guide is stale" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-release-check-contract"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-release-check.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("release-check package smoke lost --offline")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-release-check-contract
expect_fail \
  bad-release-check-contract \
  "FAIL    release-check contract: release-check package smoke lost --offline" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/bad-parity-doc"
make_fixture "$fixture" 1.2.3
cat >"$fixture/scripts/check-parity-doc.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit("docs/PARITY.md must mention: enforced by CI at 100%")
PY
git -C "$fixture" add .
git -C "$fixture" commit -q -m bad-parity-doc
expect_fail \
  bad-parity-doc \
  "FAIL    parity doc: docs/PARITY.md must mention: enforced by CI at 100%" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase tag

fixture="$tmp/public-pending"
make_fixture "$fixture" 1.2.3
perl -0pi -e 's/{% set version = "1\.2\.3" %}/{% set version = "1.2.2" %}/' \
  "$fixture/packaging/bioconda/recipe/meta.yaml"
git -C "$fixture" add .
git -C "$fixture" commit -q -m lag-bioconda
expect_fail \
  public-pending \
  "PENDING release tag: v1.2.3 does not exist" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase public
grep -F "PENDING bioconda release metadata: recipe is 1.2.2" "$tmp/public-pending.out" >/dev/null
grep -F "PENDING public channel discovery: rerun python3 scripts/release-readiness.py --phase public --version 1.2.3 --check-public after publishing" \
  "$tmp/public-pending.out" >/dev/null
grep -F "PENDING strict public audit:" "$tmp/public-pending.out" >/dev/null
grep -F "python3 scripts/release-readiness.py --phase public --version 1.2.3 --check-public --run-public-audit" \
  "$tmp/public-pending.out" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALL_CHANNELS='github-linux github-parity bioconda crates'" \
  "$tmp/public-pending.out" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES='0'" "$tmp/public-pending.out" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE='1'" "$tmp/public-pending.out" >/dev/null
grep -F "VERIFY_PUBLIC_INSTALLS_MIN_PARITY='100'" "$tmp/public-pending.out" >/dev/null
grep -F "BENCH_FILES='human_chr1 human_chr21 yeast'" "$tmp/public-pending.out" >/dev/null

fixture="$tmp/strict-public-audit-env"
make_fixture "$fixture" 1.2.3
cp "$ROOT/scripts/check-public-audit-log.py" "$fixture/scripts/check-public-audit-log.py"
cat >"$fixture/scripts/verify-public-installs.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
test "$VERIFY_PUBLIC_INSTALL_CHANNELS" = "github-linux github-parity bioconda crates"
test "$VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES" = 0
test "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE" = 1
test "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY" = 100
test "$BENCH_FILES" = "human_chr1 human_chr21 yeast"
test "$VERSION" = 1.2.3
test "$RELEASE_TAG" = v1.2.3
printf 'public-audit-version=%s\n' "$VERSION"
printf 'public-audit-tag=%s\n' "$RELEASE_TAG"
printf 'public-audit-channels=%s\n' "$VERIFY_PUBLIC_INSTALL_CHANNELS"
printf 'public-audit-allow-missing-crates=%s\n' "$VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"
printf 'public-audit-no-overwrite=%s\n' "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"
printf 'public-audit-min-parity=%s\n' "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"
printf 'public-audit-bench-files=%s\n' "$BENCH_FILES"
printf 'public-audit-crates-install-script=scripts/verify-crates-install.sh\n'
echo ">> public install: github-linux"
echo ">> public install: github-parity"
echo ">> public install: bioconda"
echo ">> public install: crates"
echo "public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]"
SH
chmod +x "$fixture/scripts/verify-public-installs.sh"
git -C "$fixture" add .
git -C "$fixture" commit -q -m strict-public-audit-env
env \
  GXFKIT_ROOT="$fixture" \
  VERIFY_PUBLIC_INSTALL_CHANNELS=crates \
  VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
  VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=0 \
  VERIFY_PUBLIC_INSTALLS_MIN_PARITY=1 \
  BENCH_FILES=yeast \
  "$PY" "$ROOT/scripts/release-readiness.py" --phase public --run-public-audit \
  >"$tmp/strict-public-audit-env.out" || true
grep -F "PASS    strict public audit: verify-public-installs.sh passed and audit log verified" \
  "$tmp/strict-public-audit-env.out" >/dev/null
grep -F "PENDING public channel discovery: rerun python3 scripts/release-readiness.py --phase public --version 1.2.3 --check-public after publishing; strict audit does not replace public channel discovery" \
  "$tmp/strict-public-audit-env.out" >/dev/null

fixture="$tmp/strict-public-audit-failed-log"
make_fixture "$fixture" 1.2.3
cp "$ROOT/scripts/check-public-audit-log.py" "$fixture/scripts/check-public-audit-log.py"
cat >"$fixture/scripts/verify-public-installs.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'public-audit-version=%s\n' "$VERSION"
printf 'public-audit-tag=%s\n' "$RELEASE_TAG"
printf 'public-audit-channels=%s\n' "$VERIFY_PUBLIC_INSTALL_CHANNELS"
printf 'public-audit-allow-missing-crates=%s\n' "$VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES"
printf 'public-audit-no-overwrite=%s\n' "$VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE"
printf 'public-audit-min-parity=%s\n' "$VERIFY_PUBLIC_INSTALLS_MIN_PARITY"
printf 'public-audit-bench-files=%s\n' "$BENCH_FILES"
printf 'public-audit-crates-install-script=scripts/verify-crates-install.sh\n'
echo ">> public install: github-linux"
echo ">> public install: github-parity"
echo ">> public install: bioconda"
echo ">> public install: crates"
echo "public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[] failed=[crates ]"
exit 1
SH
chmod +x "$fixture/scripts/verify-public-installs.sh"
git -C "$fixture" add .
git -C "$fixture" commit -q -m strict-public-audit-failed-log
expect_fail \
  strict-public-audit-failed-log \
  "FAIL    strict public audit: verify-public-installs.sh failed; audit log guard failed:" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase public --run-public-audit
grep -F "strict public audit has failed channels: ['crates']" \
  "$tmp/strict-public-audit-failed-log.out" >/dev/null

fixture="$tmp/strict-public-audit-invalid-log"
make_fixture "$fixture" 1.2.3
cp "$ROOT/scripts/check-public-audit-log.py" "$fixture/scripts/check-public-audit-log.py"
cat >"$fixture/scripts/verify-public-installs.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "strict audit command returned zero but did not emit a valid audit log"
SH
chmod +x "$fixture/scripts/verify-public-installs.sh"
git -C "$fixture" add .
git -C "$fixture" commit -q -m strict-public-audit-invalid-log
expect_fail \
  strict-public-audit-invalid-log \
  "FAIL    strict public audit: audit log invalid:" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase public --run-public-audit

fake_api_bin="$tmp/fake-api/bin"
mkdir -p "$fake_api_bin"
cat >"$fake_api_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
for required in \
  "--retry 3" \
  "--retry-delay 2" \
  "--retry-max-time 60" \
  "--connect-timeout 10" \
  "--max-time 30"
do
  case "$args" in
    *" $required "*) ;;
    *)
      echo "curl missing bounded network option: $required" >&2
      exit 22
      ;;
  esac
done
url="${@: -1}"
asset_mode="${GXFKIT_FAKE_GITHUB_ASSETS:-complete}"
tag_mode="${GXFKIT_FAKE_GITHUB_TAG:-complete}"
crate_mode="${GXFKIT_FAKE_CRATES:-complete}"
bioconda_mode="${GXFKIT_FAKE_BIOCONDA:-complete}"
add_asset_urls() {
  python3 -c '
import json
import os
import sys

data = json.load(sys.stdin)
tag = data.get("tag_name", "v1.2.3")
repo = "benngaihk/gxfkit"
asset_mode = os.environ.get("GXFKIT_FAKE_GITHUB_ASSETS", "complete")
for asset in data.get("assets", []):
    name = asset.get("name")
    if not isinstance(name, str):
        continue
    if asset_mode == "bad-url" and name == "gxfkit-v1.2.3-linux-x86_64-static.tar.gz":
        asset["browser_download_url"] = "https://example.invalid/bad-asset.tar.gz"
    else:
        asset["browser_download_url"] = f"https://github.com/{repo}/releases/download/{tag}/{name}"
json.dump(data, sys.stdout)
sys.stdout.write("\n")
'
}
case "$url" in
	  https://github.com/benngaihk/gxfkit/releases/download/v1.2.3/*.sha256)
	    name="${url##*/}"
	    target="${name%.sha256}"
	    if [ "$asset_mode" = checksum-forbidden ] \
	      && [ "$name" = gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 ]; then
	      echo "curl: (56) The requested URL returned error: 403" >&2
	      exit 56
	    elif [ "$asset_mode" = bad-sha-content ] \
	      && [ "$name" = gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 ]; then
	      printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.tar.gz\n'
	    elif [ "$asset_mode" = duplicate-sha-content ]; then
	      printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  %s\n' "$target"
	    else
	      digest="$(printf '%s' "$target" | shasum -a 256 | awk '{print $1}')"
	      printf '%s  %s\n' "$digest" "$target"
	    fi
	    ;;
  https://api.github.com/repos/benngaihk/gxfkit/releases/tags/v1.2.3)
    if [ "$asset_mode" = forbidden ]; then
      echo "curl: (56) The requested URL returned error: 403" >&2
      exit 56
    elif [ "$asset_mode" = missing-sha ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96}
]}
JSON
    elif [ "$asset_mode" = bad-upload ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":0},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"starter","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96}
]}
JSON
    elif [ "$asset_mode" = prerelease ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","draft":false,"prerelease":true,"assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96}
]}
JSON
    elif [ "$asset_mode" = draft ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","draft":true,"prerelease":false,"assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96}
]}
JSON
    elif [ "$asset_mode" = extra-gxfkit-asset ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-riscv64-static.tar.gz","state":"uploaded","size":1000}
]}
JSON
    elif [ "$asset_mode" = duplicate-asset ]; then
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":2000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96}
]}
JSON
    else
      add_asset_urls <<'JSON'
{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz","state":"uploaded","size":1000},
  {"name":"gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256","state":"uploaded","size":96},
  {"name":"extra-release-note.txt","state":"uploaded","size":12}
]}
JSON
    fi
    ;;
  https://api.github.com/repos/benngaihk/gxfkit/commits/v1.2.3)
    if [ "$tag_mode" = forbidden ]; then
      echo "curl: (56) The requested URL returned error: 403" >&2
      exit 56
    elif [ "$tag_mode" = bad-sha ]; then
      printf '{"sha":"not-a-sha"}\n'
    elif [ "$tag_mode" = mismatch ]; then
      printf '{"sha":"ffffffffffffffffffffffffffffffffffffffff"}\n'
    elif [ "$tag_mode" = match-local ]; then
      printf '{"sha":"%s"}\n' "$(git rev-parse HEAD)"
    else
      printf '{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}\n'
    fi
    ;;
  https://api.anaconda.org/package/bioconda/gxfkit)
    if [ "$bioconda_mode" = forbidden ]; then
      echo "curl: (56) The requested URL returned error: 403" >&2
      exit 56
    elif [ "$bioconda_mode" = missing-osx ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-habc_0.conda","labels":["main"],"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":123456,"attrs":{"subdir":"linux-64"}}
]}
JSON
    elif [ "$bioconda_mode" = invalid-file ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-habc_0.conda","labels":["dev"],"sha256":"not-a-sha","size":0,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"osx-64/gxfkit-1.2.3-hdef_0.conda","labels":["main"],"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":234567,"attrs":{"subdir":"osx-64"}}
]}
JSON
    elif [ "$bioconda_mode" = broken-label ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-habc_0.conda","labels":["main","broken"],"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":123456,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"osx-64/gxfkit-1.2.3-hdef_0.conda","labels":["main"],"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":234567,"attrs":{"subdir":"osx-64"}}
]}
JSON
    elif [ "$bioconda_mode" = build-number-one ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-habc_1.conda","labels":["main"],"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":123456,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"osx-64/gxfkit-1.2.3-hdef_0.conda","labels":["main"],"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":234567,"attrs":{"subdir":"osx-64"}}
]}
JSON
    elif [ "$bioconda_mode" = invalid-versions ]; then
      cat <<'JSON'
{"versions":{},"files":[]}
JSON
    elif [ "$bioconda_mode" = invalid-files ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":{}}
JSON
    elif [ "$bioconda_mode" = multiple-builds ]; then
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-hbroken_0.conda","labels":["main","broken"],"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":123456,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-hgood_0.conda","labels":["main"],"sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","size":345678,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"osx-64/gxfkit-1.2.3-hdef_0.conda","labels":["main"],"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":234567,"attrs":{"subdir":"osx-64"}}
]}
JSON
    else
      cat <<'JSON'
{"versions":["1.2.3"],"files":[
  {"version":"1.2.3","basename":"linux-64/gxfkit-1.2.3-habc_0.conda","labels":["main"],"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":123456,"attrs":{"subdir":"linux-64"}},
  {"version":"1.2.3","basename":"osx-64/gxfkit-1.2.3-hdef_0.conda","labels":["main"],"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":234567,"attrs":{"subdir":"osx-64"}}
]}
JSON
    fi
    ;;
  https://crates.io/api/v1/crates/gxfkit-core)
    if [ "$crate_mode" = forbidden-core ]; then
      echo "curl: (56) The requested URL returned error: 403" >&2
      exit 56
    else
      printf '{"versions":[{"num":"1.2.3","yanked":false,"checksum":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","crate_size":123456}]}\n'
    fi
    ;;
  https://crates.io/api/v1/crates/gxfkit)
    if [ "$crate_mode" = forbidden-gxfkit ]; then
      echo "curl: (56) The requested URL returned error: 403" >&2
      exit 56
    elif [ "$crate_mode" = yanked-gxfkit ]; then
      printf '{"versions":[{"num":"1.2.3","yanked":true,"checksum":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","crate_size":234567}]}\n'
    elif [ "$crate_mode" = invalid-gxfkit ]; then
      printf '{"versions":[{"num":"1.2.3","yanked":false,"checksum":"not-a-sha","crate_size":0}]}\n'
    elif [ "$crate_mode" = missing-yanked-gxfkit ]; then
      printf '{"versions":[{"num":"1.2.3","checksum":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","crate_size":234567}]}\n'
    elif [ "$crate_mode" = invalid-versions-gxfkit ]; then
      printf '{"versions":{}}\n'
    else
      printf '{"versions":[{"num":"1.2.3","yanked":false,"checksum":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","crate_size":234567}]}\n'
    fi
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 22
    ;;
esac
SH
chmod +x "$fake_api_bin/curl"

fixture="$tmp/public-channels-complete"
make_fixture "$fixture" 1.2.3
GXFKIT_ROOT="$fixture" PATH="$fake_api_bin:$PATH" \
  "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public \
  >"$tmp/public-channels-complete.out" || true
grep -F "PASS    GitHub release: v1.2.3 exists" "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    GitHub release assets: 8 expected asset(s) are uploaded, non-empty, and downloadable" \
  "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    GitHub release checksums: 4 checksum asset(s) point at matching archives with unique digests" \
  "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    GitHub release tag commit: v1.2.3 resolves to eeeeeeeeeeee" \
  "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    Bioconda public: gxfkit 1.2.3 is available" "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    Bioconda package files: main linux-64 and osx-64 build 0 packages are present with sha256 and non-zero size" \
  "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    Crates.io gxfkit-core: 1.2.3 is available with checksum and non-zero crate size" "$tmp/public-channels-complete.out" >/dev/null
grep -F "PASS    Crates.io gxfkit: 1.2.3 is available with checksum and non-zero crate size" "$tmp/public-channels-complete.out" >/dev/null

fixture="$tmp/public-channels-multiple-bioconda-builds"
make_fixture "$fixture" 1.2.3
GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=multiple-builds PATH="$fake_api_bin:$PATH" \
  "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public \
  >"$tmp/public-channels-multiple-bioconda-builds.out" || true
grep -F "PASS    Bioconda package files: main linux-64 and osx-64 build 0 packages are present with sha256 and non-zero size" \
  "$tmp/public-channels-multiple-bioconda-builds.out" >/dev/null

fixture="$tmp/public-channels-missing-bioconda-file"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-missing-bioconda-file \
  "FAIL    Bioconda package files: missing subdir(s): osx-64" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=missing-osx PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-bioconda-file"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-bioconda-file \
  "FAIL    Bioconda package files: invalid: linux-64 labels=['dev']; linux-64 sha256='not-a-sha'; linux-64 size=0" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=invalid-file PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-broken-bioconda-file"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-broken-bioconda-file \
  "FAIL    Bioconda package files: invalid: linux-64 labels=['main', 'broken']" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=broken-label PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-bioconda-build-number-one"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-bioconda-build-number-one \
  "FAIL    Bioconda package files: invalid: linux-64 build_number basename='linux-64/gxfkit-1.2.3-habc_1.conda'" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=build-number-one PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-bioconda-versions"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-bioconda-versions \
  "FAIL    Bioconda public: invalid metadata: versions={}" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=invalid-versions PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-bioconda-files"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-bioconda-files \
  "FAIL    Bioconda package files: invalid metadata: files={}" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=invalid-files PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-bioconda-forbidden"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-bioconda-forbidden \
  "PENDING Bioconda public: gxfkit not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_BIOCONDA=forbidden PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-yanked-crate"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-yanked-crate \
  "FAIL    Crates.io gxfkit: 1.2.3 is yanked" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=yanked-gxfkit PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-crate"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-crate \
  "FAIL    Crates.io gxfkit: invalid metadata: checksum='not-a-sha'; crate_size=0" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=invalid-gxfkit PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-missing-yanked-crate"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-missing-yanked-crate \
  "FAIL    Crates.io gxfkit: invalid metadata: yanked=None" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=missing-yanked-gxfkit PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-crate-versions"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-crate-versions \
  "FAIL    Crates.io gxfkit: invalid metadata: versions={}" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=invalid-versions-gxfkit PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-forbidden-core-crate"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-forbidden-core-crate \
  "PENDING Crates.io gxfkit-core: gxfkit-core 1.2.3 not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=forbidden-core PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-forbidden-gxfkit-crate"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-forbidden-gxfkit-crate \
  "PENDING Crates.io gxfkit: gxfkit 1.2.3 not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_CRATES=forbidden-gxfkit PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-missing-asset"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-missing-asset \
  "FAIL    GitHub release assets: missing: gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=missing-sha PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-release-forbidden"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-release-forbidden \
  "PENDING GitHub release: v1.2.3 not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=forbidden PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-invalid-asset"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-invalid-asset \
  "FAIL    GitHub release assets: invalid: gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 state=uploaded size=0; gxfkit-v1.2.3-macos-x86_64.tar.gz state=starter size=1000" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=bad-upload PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-extra-gxfkit-asset"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-extra-gxfkit-asset \
  "FAIL    GitHub release assets: unexpected package asset(s): gxfkit-v1.2.3-linux-riscv64-static.tar.gz" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=extra-gxfkit-asset PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-duplicate-asset"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-duplicate-asset \
  "FAIL    GitHub release assets: duplicate asset name(s): gxfkit-v1.2.3-linux-x86_64-static.tar.gz" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=duplicate-asset PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-bad-asset-url"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-bad-asset-url \
  "FAIL    GitHub release assets: invalid: gxfkit-v1.2.3-linux-x86_64-static.tar.gz browser_download_url='https://example.invalid/bad-asset.tar.gz'" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=bad-url PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-bad-checksum-content"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-bad-checksum-content \
  "FAIL    GitHub release checksums: invalid: gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 verifies 'other.tar.gz', expected 'gxfkit-v1.2.3-linux-x86_64-static.tar.gz'" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=bad-sha-content PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-duplicate-checksum-content"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-duplicate-checksum-content \
  "FAIL    GitHub release checksums: invalid: duplicate checksum digest for gxfkit-v1.2.3-linux-aarch64-static.tar.gz.sha256, gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256, gxfkit-v1.2.3-macos-aarch64.tar.gz.sha256, gxfkit-v1.2.3-macos-x86_64.tar.gz.sha256" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=duplicate-sha-content PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-checksum-forbidden"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-checksum-forbidden \
  "PENDING GitHub release checksums: pending: gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 fetch pending: gxfkit-v1.2.3-linux-x86_64-static.tar.gz.sha256 not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=checksum-forbidden PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-tag-commit-mismatch"
make_fixture "$fixture" 1.2.3
git -C "$fixture" tag v1.2.3
expect_fail \
  public-channels-tag-commit-mismatch \
  "FAIL    GitHub release tag commit: v1.2.3 remote ffffffffffff != local" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_TAG=mismatch PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-tag-commit-bad-sha"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-tag-commit-bad-sha \
  "FAIL    GitHub release tag commit: invalid sha='not-a-sha'" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_TAG=bad-sha PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-tag-commit-forbidden"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-tag-commit-forbidden \
  "PENDING GitHub release tag commit: v1.2.3 commit not available or access limited" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_TAG=forbidden PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-prerelease"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-prerelease \
  "FAIL    GitHub release: v1.2.3 is marked as prerelease" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=prerelease PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

fixture="$tmp/public-channels-draft"
make_fixture "$fixture" 1.2.3
expect_fail \
  public-channels-draft \
  "FAIL    GitHub release: v1.2.3 is still a draft" \
  env GXFKIT_ROOT="$fixture" GXFKIT_FAKE_GITHUB_ASSETS=draft PATH="$fake_api_bin:$PATH" \
    "$PY" "$ROOT/scripts/release-readiness.py" --phase public --check-public

expect_fail \
  public-flags-on-tag-phase \
  "--check-public and --run-public-audit require --phase public" \
  "$PY" scripts/release-readiness.py --phase tag --check-public

fixture="$tmp/version-override"
make_fixture "$fixture" 1.2.3
expect_fail \
  version-override \
  "FAIL    cargo versions: target is 2.0.0, workspace is 1.2.3, gxfkit-core dependency is 1.2.3" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/release-readiness.py" --phase public --version 2.0.0

expect_fail \
  bad-version \
  "ERROR invalid release version" \
  "$PY" scripts/release-readiness.py --version nope

echo "verified release readiness tests"
