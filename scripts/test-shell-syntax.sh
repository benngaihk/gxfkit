#!/usr/bin/env bash
# Syntax-check every repository shell script that can participate in release flow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

while IFS= read -r script; do
  bash -n "$script"
done < <(
  find . \
    -path ./.git -prune -o \
    -path ./target -prune -o \
    -path ./benchmark/results -prune -o \
    -path ./benchmark/gxf2gxf-results -prune -o \
    -path ./benchmark/gxf2gxf-corpus-results -prune -o \
    -path ./corpus/raw -prune -o \
    -type f -name '*.sh' -print | sort
)

echo "verified shell script syntax"
