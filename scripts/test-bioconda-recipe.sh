#!/usr/bin/env bash
# Regression tests for scripts/check-bioconda-recipe.py.
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

copy_recipe_fixture() {
  local dest="$1"
  mkdir -p "$dest/packaging/bioconda/recipe"
  cp packaging/bioconda/meta.yaml.template "$dest/packaging/bioconda/"
  cp packaging/bioconda/recipe/meta.yaml "$dest/packaging/bioconda/recipe/"
  cp packaging/bioconda/recipe/build.sh "$dest/packaging/bioconda/recipe/"
}

"$PY" scripts/check-bioconda-recipe.py >"$tmp/ok.out"
grep -F "verified Bioconda recipe" "$tmp/ok.out" >/dev/null

fixture="$tmp/mismatch"
copy_recipe_fixture "$fixture"
printf '\n# drift\n' >>"$fixture/packaging/bioconda/recipe/meta.yaml"
expect_fail \
  template-drift \
  "Bioconda recipe and template are not identical" \
  "$PY" scripts/check-bioconda-recipe.py --root "$fixture"

fixture="$tmp/no-overwrite"
copy_recipe_fixture "$fixture"
perl -0pi -e "s/\\n      if gxfkit gff2gtf.*?grep 'refusing to overwrite' overwrite\\.err\\n//s" \
  "$fixture/packaging/bioconda/recipe/meta.yaml" \
  "$fixture/packaging/bioconda/meta.yaml.template"
expect_fail \
  missing-overwrite-smoke \
  "grep 'refusing to overwrite' overwrite.err" \
  "$PY" scripts/check-bioconda-recipe.py --root "$fixture"

fixture="$tmp/no-locked-install"
copy_recipe_fixture "$fixture"
perl -0pi -e 's/cargo install --locked --no-track/cargo install --no-track/' \
  "$fixture/packaging/bioconda/recipe/build.sh"
expect_fail \
  missing-locked-install \
  'cargo install --locked --no-track --root "${PREFIX}" --path crates/gxfkit' \
  "$PY" scripts/check-bioconda-recipe.py --root "$fixture"

fixture="$tmp/run-exports"
copy_recipe_fixture "$fixture"
cat >>"$fixture/packaging/bioconda/recipe/meta.yaml" <<'YAML'
  run_exports:
    - {{ pin_subpackage('gxfkit', max_pin='x') }}
YAML
cp "$fixture/packaging/bioconda/recipe/meta.yaml" \
  "$fixture/packaging/bioconda/meta.yaml.template"
expect_fail \
  run-exports \
  "must not declare run_exports" \
  "$PY" scripts/check-bioconda-recipe.py --root "$fixture"

echo "verified Bioconda recipe tests"
