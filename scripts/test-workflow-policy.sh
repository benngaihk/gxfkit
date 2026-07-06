#!/usr/bin/env bash
# Regression checks for the GitHub Actions workflow policy guard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 scripts/check-workflow-policy.py

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/good.yml" <<'YAML'
name: good
on: push
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo ok
YAML
python3 scripts/check-workflow-policy.py "$tmpdir/good.yml"

cat >"$tmpdir/release.yml" <<'YAML'
name: release
on:
  push:
    tags:
      - "v*"
permissions:
  contents: write
jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo ok
YAML
python3 scripts/check-workflow-policy.py "$tmpdir/release.yml"

cat >"$tmpdir/missing-permissions.yml" <<'YAML'
name: missing permissions
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo ok
YAML
if python3 scripts/check-workflow-policy.py "$tmpdir/missing-permissions.yml"; then
  echo "workflow without explicit permissions unexpectedly passed" >&2
  exit 1
fi

cat >"$tmpdir/missing-timeout.yml" <<'YAML'
name: missing timeout
on: push
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
if python3 scripts/check-workflow-policy.py "$tmpdir/missing-timeout.yml"; then
  echo "workflow job without timeout unexpectedly passed" >&2
  exit 1
fi

cat >"$tmpdir/too-large-timeout.yml" <<'YAML'
name: large timeout
on: push
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 361
    steps:
      - run: echo ok
YAML
if python3 scripts/check-workflow-policy.py "$tmpdir/too-large-timeout.yml"; then
  echo "workflow job with oversized timeout unexpectedly passed" >&2
  exit 1
fi

cat >"$tmpdir/ci-with-write.yml" <<'YAML'
name: ci write
on: push
permissions:
  contents: write
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo ok
YAML
if python3 scripts/check-workflow-policy.py "$tmpdir/ci-with-write.yml"; then
  echo "non-release workflow with write permission unexpectedly passed" >&2
  exit 1
fi

cat >"$tmpdir/release.yml" <<'YAML'
name: release read
on:
  push:
    tags:
      - "v*"
permissions:
  contents: read
jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo ok
YAML
if python3 scripts/check-workflow-policy.py "$tmpdir/release.yml"; then
  echo "release workflow without write permission unexpectedly passed" >&2
  exit 1
fi

echo "verified workflow policy guard"
