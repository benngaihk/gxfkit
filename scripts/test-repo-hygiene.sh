#!/usr/bin/env bash
# Guard against committing generated caches and local release evidence scratch files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tracked_generated="$(
  git ls-files \
    '*__pycache__*' \
    '*.pyc' \
    '*.pyo' \
    '*.pyd' \
    '.pytest_cache/*' \
    '.ruff_cache/*' \
    'dist/*' \
    'release-evidence.md' \
    'public-audit.log'
)"
if [ -n "$tracked_generated" ]; then
  echo "generated/cache files must not be tracked:" >&2
  printf '%s\n' "$tracked_generated" >&2
  exit 1
fi

for path in \
  tests/parity/__pycache__/normalize.cpython-312.pyc \
  .pytest_cache/v/cache/nodeids \
  .ruff_cache/0.9.0/cache \
  dist/gxfkit-v0.0.2-linux-x86_64-static.tar.gz \
  benchmark/gxf2gxf-corpus-results/summary.tsv \
  release-evidence.md \
  public-audit.log
do
  if ! git check-ignore -q "$path"; then
    echo ".gitignore must ignore generated artifact: $path" >&2
    exit 1
  fi
done

echo "verified repository hygiene ignores"
