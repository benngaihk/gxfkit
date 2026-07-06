#!/usr/bin/env bash
# Regression tests for scripts/github-source-sha256.py.
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

printf 'gxfkit source archive fixture\n' >"$tmp/source.tar.gz"
expected="$(shasum -a 256 "$tmp/source.tar.gz" | awk '{print $1}')"

"$PY" scripts/github-source-sha256.py 1.2.3 --url "$tmp/source.tar.gz" \
  >"$tmp/plain.out"
grep -Fx "$expected" "$tmp/plain.out" >/dev/null

"$PY" scripts/github-source-sha256.py 1.2.3 \
  --url "file://$tmp/source.tar.gz" \
  --format prepare-command \
  >"$tmp/command.out"
grep -Fx "python3 scripts/prepare-next-version.py 1.2.3 --bioconda-sha256 $expected" \
  "$tmp/command.out" >/dev/null

fake_curl_bin="$tmp/fake-curl-bin"
mkdir -p "$fake_curl_bin"
cat >"$fake_curl_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
for required in \
  "--retry 3" \
  "--retry-delay 2" \
  "--retry-max-time 60" \
  "--connect-timeout 10" \
  "--max-time 30" \
  "-H User-Agent: gxfkit-github-source-sha256"
do
  case "$args" in
    *" $required "*) ;;
    *)
      echo "curl missing bounded network option: $required" >&2
      exit 22
      ;;
  esac
done
printf 'fallback source archive fixture\n'
SH
chmod +x "$fake_curl_bin/curl"
fallback_expected="$(printf 'fallback source archive fixture\n' | shasum -a 256 | awk '{print $1}')"
PATH="$fake_curl_bin:$PATH" "$PY" scripts/github-source-sha256.py 1.2.3 \
  --url "http://127.0.0.1:9/source.tar.gz" \
  >"$tmp/curl-fallback.out"
grep -Fx "$fallback_expected" "$tmp/curl-fallback.out" >/dev/null

expect_fail \
  bad-version \
  "ERROR invalid version" \
  "$PY" scripts/github-source-sha256.py v1.2.3 --url "$tmp/source.tar.gz"

expect_fail \
  missing-url \
  "ERROR failed to compute sha256" \
  "$PY" scripts/github-source-sha256.py 1.2.3 --url "$tmp/missing.tar.gz"

echo "verified GitHub source sha256 helper tests"
