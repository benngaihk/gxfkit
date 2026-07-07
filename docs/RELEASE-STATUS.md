# Release Status

This file records release facts that are easy to misread from version numbers
alone.

## Current public GitHub Release: `0.0.2`

- GitHub Release `v0.0.2` exists, is public, and is not a prerelease:
  <https://github.com/benngaihk/gxfkit/releases/tag/v0.0.2>.
- The release has the expected eight assets: four platform archives plus their
  `.sha256` checksum files.
- The release was verified on 2026-07-06 with:

  ```bash
  RELEASE_TAG=v0.0.2 bash scripts/verify-github-release-install.sh
  RELEASE_TAG=v0.0.2 bash scripts/verify-github-release-linux-docker.sh
  RELEASE_TAG=v0.0.2 BENCH_FILES="human_chr1 human_chr21 yeast" bash scripts/verify-github-release-parity.sh
  ```

## Current public Bioconda: `0.0.2`

- Bioconda `gxfkit 0.0.1` exists and passed the basic version/conversion smoke
  used before the strict no-overwrite audit. This was re-verified from a clean
  micromamba container on 2026-07-06. The upstream recipe PR
  [bioconda-recipes#66815](https://github.com/bioconda/bioconda-recipes/pull/66815)
  is merged, so this is a public Bioconda package state rather than only a local
  recipe expectation. Re-verify the installed package with:

  ```bash
  VERSION=0.0.1 VERIFY_BIOCONDA_NO_OVERWRITE=0 bash scripts/verify-bioconda-install.sh
  ```
- Anaconda package metadata lists Bioconda `gxfkit 0.0.2` files for `linux-64`
  and `osx-64` in the `main` label.
- Bioconda `gxfkit 0.0.2` passed clean Linux install verification, smoke
  conversion, and no-overwrite verification on 2026-07-06 with:

  ```bash
  VERSION=0.0.2 bash scripts/verify-bioconda-install.sh
  ```

## Current public Crates.io: `0.0.2`

- Crates.io `gxfkit-core 0.0.2` is published and visible with checksum and
  non-zero crate size.
- Crates.io `gxfkit 0.0.2` is published and visible with checksum and non-zero
  crate size.
- Crates.io `gxfkit 0.0.2` passed clean install verification from the official
  registry on 2026-07-07 with:

  ```bash
  VERSION=0.0.2 bash scripts/verify-crates-install.sh
  ```

## Current Cargo release candidate: `0.0.2`

The Cargo workspace and `gxfkit-core` dependency are prepared for `0.0.2` with:

```bash
python3 scripts/prepare-next-version.py 0.0.2 --cargo-only
RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh
```

The local release preflight uses offline install/package smoke checks after the
normal build warms the Cargo cache, and `python3 scripts/check-release-check.py`
guards that deterministic local preflight contract.

The existing `v0.0.2` tag points at the release-candidate commit. It must not be
moved. The existing `v0.0.2` tag points at an older commit than current `main`.
Bioconda metadata is updated to `0.0.2` with the GitHub source archive sha256:

```text
b60a0c96f4d70abea6a0a77f26e2fe8092aa4ab913936bb502f2561689c27020
```

Crates.io `0.0.2` was published from the existing `v0.0.2` tag, not from
`main` after the Bioconda metadata commit. Do not move the existing tag; the
next public release must bump the workspace version before publishing.

## Important `0.0.1` boundary

The existing `v0.0.1` tag points at an older commit than this release-hardening
work. Do not publish Crates.io `gxfkit 0.0.1` from any commit other than the
existing `v0.0.1` tag. Publishing the same version from a newer commit would
make public channels disagree. If the workspace version is still `0.0.1`,
`bash scripts/release-check.sh` is expected to fail at `>> publish ref` until
the workspace version is bumped or the existing tag is checked out.

Public `v0.0.1` GitHub Release and Bioconda packages predate the no-overwrite
`-o/--output` guard and still overwrite existing output files. GitHub Release
`v0.0.2` has the guard and has passed the strict GitHub release parity checks.
Bioconda `0.0.2` also has the guard and passed clean install verification.
Crates.io `0.0.2` is now strict production evidence after the final public
audit passed.

Full public closure for `0.0.2` passed on 2026-07-07 with:

```bash
python3 scripts/release-readiness.py --phase public --check-public --run-public-audit
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
BENCH_FILES="human_chr1 human_chr21 yeast" \
VERSION=0.0.2 RELEASE_TAG=v0.0.2 bash scripts/verify-public-installs.sh
```

Run the strict audit through `release-readiness --run-public-audit` so the
captured audit log is also verified.

A staged public install audit allowing only the missing Crates.io channel passed
on 2026-07-07 with:

```bash
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
BENCH_FILES="human_chr1 human_chr21 yeast" \
VERSION=0.0.2 RELEASE_TAG=v0.0.2 bash scripts/verify-public-installs.sh
```

The recorded summary was:

```text
public install summary: passed=[github-linux github-parity bioconda ] allowed_missing=[crates ] failed=[]
```

The final strict public install audit passed on 2026-07-07 with:

```text
public install summary: passed=[github-linux github-parity bioconda crates ] allowed_missing=[] failed=[]
```

## Remaining `0.0.2` public closure

None. GitHub Release, Bioconda, Crates.io, and the strict public audit are all
complete for `0.0.2`.

If another release candidate is needed after the existing `v0.0.2` tag, bump the
workspace version rather than moving the public tag.
