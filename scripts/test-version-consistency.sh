#!/usr/bin/env bash
# Regression tests for scripts/check-version-consistency.py CLI validation.
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

workspace_version="$("$PY" - <<'PY'
from pathlib import Path
import re

text = Path("Cargo.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version = "([^"]+)"$', text)
if not match:
    raise SystemExit("missing workspace version")
print(match.group(1))
PY
)"
bioconda_version="$("$PY" - <<'PY'
from pathlib import Path
import re

text = Path("packaging/bioconda/recipe/meta.yaml").read_text(encoding="utf-8")
match = re.search(r'\{% set version = "([^"]+)" %\}', text)
if not match:
    raise SystemExit("missing Bioconda version")
print(match.group(1))
PY
)"

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

if [ "$workspace_version" = "$bioconda_version" ]; then
  "$PY" scripts/check-version-consistency.py >"$tmp/ok.out"
  grep -F "OK crate versions: ${workspace_version}" "$tmp/ok.out" >/dev/null
  grep -F "OK Bioconda versions: ${workspace_version}" "$tmp/ok.out" >/dev/null

  "$PY" scripts/check-version-consistency.py \
    --expected-version "$workspace_version" >"$tmp/expected-ok.out"
  grep -F "OK expected release version: ${workspace_version}" "$tmp/expected-ok.out" >/dev/null
else
  expect_fail \
    current-all-detects-cargo-bioconda-mismatch \
    "ERROR Bioconda versions mismatch:" \
    "$PY" scripts/check-version-consistency.py
fi

"$PY" scripts/check-version-consistency.py \
  --scope cargo \
  --expected-version "$workspace_version" >"$tmp/cargo-scope-ok.out"
grep -F "OK expected release version: ${workspace_version}" "$tmp/cargo-scope-ok.out" >/dev/null
grep -F "OK crate versions: ${workspace_version}" "$tmp/cargo-scope-ok.out" >/dev/null
if grep -F "Bioconda" "$tmp/cargo-scope-ok.out" >/dev/null; then
  echo "cargo scope unexpectedly checked Bioconda metadata" >&2
  cat "$tmp/cargo-scope-ok.out" >&2
  exit 1
fi

"$PY" scripts/check-version-consistency.py \
  --scope bioconda \
  --expected-version "$bioconda_version" >"$tmp/bioconda-scope-ok.out"
grep -F "OK expected Bioconda version: ${bioconda_version}" "$tmp/bioconda-scope-ok.out" >/dev/null
grep -F "OK Bioconda versions: ${bioconda_version}" "$tmp/bioconda-scope-ok.out" >/dev/null
grep -F "OK Bioconda sha256 values:" "$tmp/bioconda-scope-ok.out" >/dev/null
if grep -F "crate versions" "$tmp/bioconda-scope-ok.out" >/dev/null; then
  echo "Bioconda scope unexpectedly checked crate metadata" >&2
  cat "$tmp/bioconda-scope-ok.out" >&2
  exit 1
fi

expect_fail \
  expected-version-mismatch \
  "ERROR expected release version mismatch:" \
  "$PY" scripts/check-version-consistency.py --expected-version 999.999.999

expect_fail \
  cargo-expected-version-mismatch \
  "ERROR expected release version mismatch:" \
  "$PY" scripts/check-version-consistency.py --scope cargo --expected-version 999.999.999

expect_fail \
  bioconda-expected-version-mismatch \
  "ERROR expected Bioconda version mismatch:" \
  "$PY" scripts/check-version-consistency.py --scope bioconda --expected-version 999.999.999

expect_fail \
  expected-version-missing-value \
  "--expected-version requires a value" \
  "$PY" scripts/check-version-consistency.py --expected-version

expect_fail \
  scope-missing-value \
  "--scope requires a value" \
  "$PY" scripts/check-version-consistency.py --scope

expect_fail \
  scope-invalid-value \
  "--scope must be one of: all, cargo, bioconda" \
  "$PY" scripts/check-version-consistency.py --scope nope

expect_fail \
  remote-sha-cargo-scope \
  "--check-remote-bioconda-sha256 requires --scope all or --scope bioconda" \
  "$PY" scripts/check-version-consistency.py --scope cargo --check-remote-bioconda-sha256

expect_fail \
  unexpected-argument \
  "unexpected argument: --definitely-not-a-real-option" \
  "$PY" scripts/check-version-consistency.py --definitely-not-a-real-option

fixture="$tmp/fixture"
mkdir -p \
  "$fixture/scripts" \
  "$fixture/crates/gxfkit" \
  "$fixture/packaging/bioconda/recipe" \
  "$fixture/packaging/bioconda"
cp scripts/check-version-consistency.py "$fixture/scripts/"
cp Cargo.toml "$fixture/"
cp crates/gxfkit/Cargo.toml "$fixture/crates/gxfkit/"
cp packaging/bioconda/recipe/meta.yaml "$fixture/packaging/bioconda/recipe/"
cp packaging/bioconda/meta.yaml.template "$fixture/packaging/bioconda/"
perl -0pi -e 's/^version = "[^"]+"$/version = "1.2.3"/m' "$fixture/Cargo.toml"
perl -0pi -e 's/^gxfkit-core = \{ version = "[^"]+", path = "\.\.\/gxfkit-core" \}$/gxfkit-core = { version = "1.2.3", path = "..\/gxfkit-core" }/m' \
  "$fixture/crates/gxfkit/Cargo.toml"
(cd "$fixture" && "$PY" scripts/check-version-consistency.py --scope cargo --expected-version 1.2.3) \
  >"$tmp/fixture-cargo-scope-ok.out"

expect_fail \
  fixture-all-detects-bioconda-mismatch \
  "ERROR Bioconda versions mismatch:" \
  bash -lc "cd '$fixture' && '$PY' scripts/check-version-consistency.py --expected-version 1.2.3"

perl -0pi -e 's/\{% set version = "[^"]+" %\}/{% set version = "4.5.6" %}/g' \
  "$fixture/packaging/bioconda/recipe/meta.yaml" \
  "$fixture/packaging/bioconda/meta.yaml.template"
(cd "$fixture" && "$PY" scripts/check-version-consistency.py --scope bioconda --expected-version 4.5.6) \
  >"$tmp/fixture-bioconda-scope-ok.out"

expect_fail \
  fixture-all-detects-cargo-bioconda-mismatch \
  "ERROR Bioconda versions mismatch:" \
  bash -lc "cd '$fixture' && '$PY' scripts/check-version-consistency.py"

echo "verified version consistency tests"
