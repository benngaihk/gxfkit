#!/usr/bin/env bash
# Verify scripts that are intentionally invoked directly keep their executable bit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_direct_scripts=(
  scripts/release-evidence.sh
)

for script in "${required_direct_scripts[@]}"; do
  if [ ! -x "$script" ]; then
    echo "$script must be executable because docs/workflows invoke it directly" >&2
    exit 1
  fi
done

echo "verified directly executable scripts"
