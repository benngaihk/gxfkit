#!/usr/bin/env bash
# Regression tests for scripts/verify-release-archive.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_release() {
  local name="$1"
  local root="$tmp/$name"
  rm -rf "$root"
  mkdir -p "$root"
  cp README.md LICENSE "$root/"
  cat >"$root/gxfkit" <<'SH'
#!/usr/bin/env sh
set -eu
if [ "${1:-}" = version ]; then
  echo "gxfkit 0.0.0-test"
  exit 0
fi
if [ "${1:-}" = gff2gtf ]; then
  out=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o | --output)
        shift
        out="${1:-}"
        ;;
    esac
    shift || true
  done
  if [ -z "$out" ]; then
    echo "missing output path" >&2
    exit 2
  fi
  if [ -e "$out" ]; then
    echo "output file already exists, refusing to overwrite: $out" >&2
    exit 1
  fi
  printf '%s\n' 'chr1	src	exon	1	50	.	+	.	gene_id "g1"; transcript_id "t1";' >"$out"
  exit 0
fi
echo "unexpected fake gxfkit invocation: $*" >&2
exit 2
SH
  chmod +x "$root/gxfkit"
  tar -C "$tmp" -czf "$tmp/$name.tar.gz" "$name"
  (cd "$tmp" && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
}

repack_fake_release() {
  local name="$1"
  tar -C "$tmp" -czf "$tmp/$name.tar.gz" "$name"
  (cd "$tmp" && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
}

expect_fail() {
  local label="$1"
  local expected="$2"
  shift 2
  local out="$tmp/$label.out"
  if "$@" >"$out" 2>&1; then
    echo "$label unexpectedly passed" >&2
    cat "$out" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$out" >/dev/null; then
    echo "$label failed, but did not mention: $expected" >&2
    cat "$out" >&2
    exit 1
  fi
}

valid="gxfkit-v0.0.0-test-local"
make_fake_release "$valid"
bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"
VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=0.0.0-test \
  bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"
VERIFY_RELEASE_ARCHIVE_SMOKE=0 VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=0.0.0-test \
  bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"

fallback_bin="$tmp/fallback-bin"
mkdir -p "$fallback_bin"
for tool in bash sh tar gzip wc tr grep mktemp rm find basename dirname pwd python3; do
  tool_path="$(command -v "$tool")"
  ln -s "$tool_path" "$fallback_bin/$tool"
done
shasum_path="$(command -v shasum)"
cat >"$fallback_bin/sha256sum" <<SH
#!/usr/bin/env sh
exec "$shasum_path" -a 256 "\$@"
SH
chmod +x "$fallback_bin/sha256sum"
env PATH="$fallback_bin" VERIFY_RELEASE_ARCHIVE_SMOKE=0 \
  bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"

expect_fail \
  bad-expected-version-env \
  "VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION must look like X.Y.Z" \
  env VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=nope \
    bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"

expect_fail \
  bad-no-overwrite-env \
  "VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE must be 0 or 1" \
  env VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=maybe \
    bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"

wrong_name_version="gxfkit-v9.9.9-local"
make_fake_release "$wrong_name_version"
expect_fail \
  mismatched-version \
  "archive gxfkit version mismatch: expected gxfkit 9.9.9" \
  env VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=9.9.9 \
    bash scripts/verify-release-archive.sh "$tmp/$wrong_name_version.tar.gz"

expect_fail \
  mismatched-archive-name-version \
  "archive name must match expected version 0.0.0-test" \
  env VERIFY_RELEASE_ARCHIVE_SMOKE=0 VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=0.0.0-test \
    bash scripts/verify-release-archive.sh "$tmp/$wrong_name_version.tar.gz"

expect_fail \
  mismatched-name-before-smoke \
  "archive name must match expected version 9.9.9" \
  env VERIFY_RELEASE_ARCHIVE_EXPECTED_VERSION=9.9.9 \
    bash scripts/verify-release-archive.sh "$tmp/$valid.tar.gz"

bad_checksum_target="gxfkit-vtest-bad-checksum-target"
make_fake_release "$bad_checksum_target"
checksum="$(awk '{print $1}' "$tmp/$bad_checksum_target.tar.gz.sha256")"
printf '%s  other.tar.gz\n' "$checksum" >"$tmp/$bad_checksum_target.tar.gz.sha256"
expect_fail \
  bad-checksum-target \
  "checksum file must verify $bad_checksum_target.tar.gz" \
  bash scripts/verify-release-archive.sh "$tmp/$bad_checksum_target.tar.gz"

bad_archive_name="not-gxfkit-vtest"
make_fake_release "$bad_archive_name"
expect_fail \
  bad-archive-name \
  "archive name must look like gxfkit-v*.tar.gz" \
  bash scripts/verify-release-archive.sh "$tmp/$bad_archive_name.tar.gz"

bad_checksum_lines="gxfkit-vtest-bad-checksum-lines"
make_fake_release "$bad_checksum_lines"
checksum_line="$(cat "$tmp/$bad_checksum_lines.tar.gz.sha256")"
printf '%s\n%s\n' "$checksum_line" "$checksum_line" >"$tmp/$bad_checksum_lines.tar.gz.sha256"
expect_fail \
  bad-checksum-lines \
  "checksum file must contain exactly one line" \
  bash scripts/verify-release-archive.sh "$tmp/$bad_checksum_lines.tar.gz"

uppercase_checksum="gxfkit-vtest-uppercase-checksum"
make_fake_release "$uppercase_checksum"
checksum="$(awk '{print toupper($1)}' "$tmp/$uppercase_checksum.tar.gz.sha256")"
printf '%s  %s.tar.gz\n' "$checksum" "$uppercase_checksum" >"$tmp/$uppercase_checksum.tar.gz.sha256"
expect_fail \
  uppercase-checksum \
  "checksum file does not start with a lowercase sha256 digest" \
  bash scripts/verify-release-archive.sh "$tmp/$uppercase_checksum.tar.gz"

missing_readme="gxfkit-vtest-missing-readme"
make_fake_release "$missing_readme"
rm "$tmp/$missing_readme/README.md"
repack_fake_release "$missing_readme"
expect_fail \
  missing-readme \
  "archive missing README.md" \
  bash scripts/verify-release-archive.sh "$tmp/$missing_readme.tar.gz"

missing_license="gxfkit-vtest-missing-license"
make_fake_release "$missing_license"
rm "$tmp/$missing_license/LICENSE"
repack_fake_release "$missing_license"
expect_fail \
  missing-license \
  "archive missing LICENSE" \
  bash scripts/verify-release-archive.sh "$tmp/$missing_license.tar.gz"

extra_member="gxfkit-vtest-extra-member"
make_fake_release "$extra_member"
printf 'surprise\n' >"$tmp/$extra_member/NOTES.txt"
repack_fake_release "$extra_member"
expect_fail \
  extra-member \
  "archive has unexpected member: $extra_member/NOTES.txt" \
  bash scripts/verify-release-archive.sh "$tmp/$extra_member.tar.gz"

non_executable="gxfkit-vtest-non-executable"
make_fake_release "$non_executable"
chmod -x "$tmp/$non_executable/gxfkit"
repack_fake_release "$non_executable"
expect_fail \
  non-executable \
  "archive gxfkit binary is not executable" \
  bash scripts/verify-release-archive.sh "$tmp/$non_executable.tar.gz"

overwrites_output="gxfkit-vtest-overwrites-output"
make_fake_release "$overwrites_output"
python3 - "$tmp/$overwrites_output/gxfkit" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    '  if [ -e "$out" ]; then\n'
    '    echo "output file already exists, refusing to overwrite: $out" >&2\n'
    '    exit 1\n'
    '  fi\n',
    '',
)
path.write_text(text, encoding="utf-8")
PY
repack_fake_release "$overwrites_output"
expect_fail \
  overwrites-output \
  "gxfkit unexpectedly overwrote smoke.gtf" \
  bash scripts/verify-release-archive.sh "$tmp/$overwrites_output.tar.gz"
VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0 \
  bash scripts/verify-release-archive.sh "$tmp/$overwrites_output.tar.gz"

unsafe="gxfkit-vtest-unsafe-member"
make_fake_release "$unsafe"
python3 - "$tmp" "$unsafe" <<'PY'
import io
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    root = tarfile.TarInfo(name)
    root.type = tarfile.DIRTYPE
    root.mode = 0o755
    tar.addfile(root)
    info = tarfile.TarInfo(f"{name}/../evil")
    data = b"nope"
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))
PY
(cd "$tmp" && shasum -a 256 "$unsafe.tar.gz" > "$unsafe.tar.gz.sha256")
expect_fail \
  unsafe-member \
  "archive member has unsafe path" \
  bash scripts/verify-release-archive.sh "$tmp/$unsafe.tar.gz"

outside="gxfkit-vtest-outside-member"
make_fake_release "$outside"
python3 - "$tmp" "$outside" <<'PY'
import io
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    root = tarfile.TarInfo(name)
    root.type = tarfile.DIRTYPE
    root.mode = 0o755
    tar.addfile(root)
    info = tarfile.TarInfo("outside")
    data = b"nope"
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))
PY
(cd "$tmp" && shasum -a 256 "$outside.tar.gz" > "$outside.tar.gz.sha256")
expect_fail \
  outside-member \
  "archive member is outside $outside" \
  bash scripts/verify-release-archive.sh "$tmp/$outside.tar.gz"

duplicate_member="gxfkit-vtest-duplicate-member"
make_fake_release "$duplicate_member"
python3 - "$tmp" "$duplicate_member" <<'PY'
import io
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    tar.add(tmp / name, arcname=name)
    info = tarfile.TarInfo(f"{name}/gxfkit")
    data = b"#!/bin/sh\necho duplicate\n"
    info.size = len(data)
    info.mode = 0o755
    tar.addfile(info, io.BytesIO(data))
PY
(cd "$tmp" && shasum -a 256 "$duplicate_member.tar.gz" > "$duplicate_member.tar.gz.sha256")
expect_fail \
  duplicate-member \
  "archive has duplicate member: $duplicate_member/gxfkit" \
  bash scripts/verify-release-archive.sh "$tmp/$duplicate_member.tar.gz"

symlink_member="gxfkit-vtest-symlink-member"
make_fake_release "$symlink_member"
python3 - "$tmp" "$symlink_member" <<'PY'
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    for path in (tmp / name).rglob("*"):
        tar.add(path, arcname=f"{name}/{path.relative_to(tmp / name)}")
    info = tarfile.TarInfo(f"{name}/linked-readme")
    info.type = tarfile.SYMTYPE
    info.linkname = "README.md"
    info.mode = 0o777
    tar.addfile(info)
PY
(cd "$tmp" && shasum -a 256 "$symlink_member.tar.gz" > "$symlink_member.tar.gz.sha256")
expect_fail \
  symlink-member \
  "archive has unexpected member: $symlink_member/linked-readme" \
  bash scripts/verify-release-archive.sh "$tmp/$symlink_member.tar.gz"

allowed_symlink_member="gxfkit-vtest-allowed-symlink-member"
make_fake_release "$allowed_symlink_member"
python3 - "$tmp" "$allowed_symlink_member" <<'PY'
import io
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    root = tarfile.TarInfo(name)
    root.type = tarfile.DIRTYPE
    root.mode = 0o755
    tar.addfile(root)
    for filename in ("gxfkit", "LICENSE"):
        tar.add(tmp / name / filename, arcname=f"{name}/{filename}")
    info = tarfile.TarInfo(f"{name}/README.md")
    info.type = tarfile.SYMTYPE
    info.linkname = "LICENSE"
    info.mode = 0o777
    tar.addfile(info)
PY
(cd "$tmp" && shasum -a 256 "$allowed_symlink_member.tar.gz" > "$allowed_symlink_member.tar.gz.sha256")
expect_fail \
  allowed-symlink-member \
  "archive member must not be a link: $allowed_symlink_member/README.md" \
  bash scripts/verify-release-archive.sh "$tmp/$allowed_symlink_member.tar.gz"

hardlink_member="gxfkit-vtest-hardlink-member"
make_fake_release "$hardlink_member"
python3 - "$tmp" "$hardlink_member" <<'PY'
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    for path in (tmp / name).rglob("*"):
        tar.add(path, arcname=f"{name}/{path.relative_to(tmp / name)}")
    info = tarfile.TarInfo(f"{name}/hardlinked-readme")
    info.type = tarfile.LNKTYPE
    info.linkname = f"{name}/README.md"
    info.mode = 0o644
    tar.addfile(info)
PY
(cd "$tmp" && shasum -a 256 "$hardlink_member.tar.gz" > "$hardlink_member.tar.gz.sha256")
expect_fail \
  hardlink-member \
  "archive has unexpected member: $hardlink_member/hardlinked-readme" \
  bash scripts/verify-release-archive.sh "$tmp/$hardlink_member.tar.gz"

allowed_hardlink_member="gxfkit-vtest-allowed-hardlink-member"
make_fake_release "$allowed_hardlink_member"
python3 - "$tmp" "$allowed_hardlink_member" <<'PY'
import sys
import tarfile
from pathlib import Path

tmp = Path(sys.argv[1])
name = sys.argv[2]
archive = tmp / f"{name}.tar.gz"
with tarfile.open(archive, "w:gz") as tar:
    root = tarfile.TarInfo(name)
    root.type = tarfile.DIRTYPE
    root.mode = 0o755
    tar.addfile(root)
    for filename in ("gxfkit", "README.md"):
        tar.add(tmp / name / filename, arcname=f"{name}/{filename}")
    info = tarfile.TarInfo(f"{name}/LICENSE")
    info.type = tarfile.LNKTYPE
    info.linkname = f"{name}/README.md"
    info.mode = 0o644
    tar.addfile(info)
PY
(cd "$tmp" && shasum -a 256 "$allowed_hardlink_member.tar.gz" > "$allowed_hardlink_member.tar.gz.sha256")
expect_fail \
  allowed-hardlink-member \
  "archive member must not be a link: $allowed_hardlink_member/LICENSE" \
  bash scripts/verify-release-archive.sh "$tmp/$allowed_hardlink_member.tar.gz"

echo "verified release archive verifier tests"
