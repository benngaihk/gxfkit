#!/usr/bin/env bash
# Regression tests for scripts/check-release-notes.py.
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
  mkdir -p "$dir/docs/releases"
  cat >"$dir/Cargo.toml" <<'TOML'
[workspace.package]
version = "1.2.3"
TOML
  cat >"$dir/docs/releases/v1.2.3.md" <<'MD'
# gxfkit v1.2.3 Release Notes

Status: public GitHub Release, Bioconda, and Crates.io package. Full public
readiness is tracked by scripts/release-evidence.sh --check-public and passed
with the strict public install audit. Full public readiness passed.

AGAT 1.7.0 remains the oracle. This release has 100.00% normalized parity on
human_chr1, human_chr21, and yeast. It includes the no-overwrite behavior.
It also keeps a deterministic local `release-check.sh` contract guard.

## Install Now

```bash
conda install -c conda-forge -c bioconda gxfkit=1.2.3
```

```bash
set +e
RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh > release-check.log 2>&1
rc=$?
printf 'release-check-exit-code=%s\n' "$rc" >> release-check.log
set -e
python3 scripts/check-release-check.py
scripts/release-evidence.sh --allow-dirty --release-check-log release-check.log > release-evidence.md
exit "$rc"
python3 scripts/github-source-sha256.py 1.2.3 --format prepare-command
python3 scripts/release-readiness.py --phase public --check-public --run-public-audit
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
BENCH_FILES="human_chr1 human_chr21 yeast" \
VERSION=1.2.3 RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh
A staged public install audit allowing only the missing Crates.io channel passed
on 2026-07-07 with:
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
BENCH_FILES="human_chr1 human_chr21 yeast" \
VERSION=1.2.3 RELEASE_TAG=v1.2.3 bash scripts/verify-public-installs.sh
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[crates ] failed=[]
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
scripts/release-evidence.sh --check-public > release-evidence.md
```

```bash
cargo install gxfkit --version 1.2.3
```

- `VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates"`
- `VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0`
- `VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1`
- `VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100`
- `BENCH_FILES="human_chr1 human_chr21 yeast"`

## Known Limits

Public `v0.0.1` packages predate the no-overwrite guard. Drosophila remains an
extended stress case.
MD
}

"$PY" scripts/check-release-notes.py >"$tmp/current.out"
grep -F "verified release notes for v" "$tmp/current.out" >/dev/null
"$PY" scripts/check-release-notes.py --expected-version 0.0.2 >"$tmp/current-expected.out"
grep -F "verified release notes for v0.0.2" "$tmp/current-expected.out" >/dev/null

fixture="$tmp/good"
make_fixture "$fixture"
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-release-notes.py" >"$tmp/good.out"
grep -F "verified release notes for v1.2.3" "$tmp/good.out" >/dev/null
GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-release-notes.py" \
  --expected-version 1.2.3 >"$tmp/good-expected.out"
grep -F "verified release notes for v1.2.3" "$tmp/good-expected.out" >/dev/null

fixture="$tmp/missing"
make_fixture "$fixture"
rm "$fixture/docs/releases/v1.2.3.md"
expect_fail \
  missing \
  "missing release notes" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-release-notes.py"

fixture="$tmp/missing-audit"
make_fixture "$fixture"
perl -0pi -e 's/VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \\\n//' \
  "$fixture/docs/releases/v1.2.3.md"
expect_fail \
  missing-audit \
  "release notes must mention: VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-release-notes.py"

fixture="$tmp/version-mismatch"
make_fixture "$fixture"
cp "$fixture/docs/releases/v1.2.3.md" "$fixture/docs/releases/v2.0.0.md"
perl -0pi -e 's/v1\.2\.3/v2.0.0/g; s/1\.2\.3/2.0.0/g' \
  "$fixture/docs/releases/v2.0.0.md"
expect_fail \
  version-mismatch \
  "workspace version 1.2.3 does not match expected release version 2.0.0" \
  env GXFKIT_ROOT="$fixture" "$PY" "$ROOT/scripts/check-release-notes.py" --expected-version 2.0.0

expect_fail \
  bad-expected-version \
  "ERROR invalid expected version" \
  "$PY" "$ROOT/scripts/check-release-notes.py" --expected-version nope

echo "verified release notes tests"
