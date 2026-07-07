# Release Checklist

This project treats AGAT parity as the correctness bar, so releases should be
boring: run the checks, publish artifacts, verify the binary, then announce.
For the current public-channel state and same-version publishing constraints,
also read [RELEASE-STATUS.md](RELEASE-STATUS.md).

## 1. Preflight

From the repository root:

```bash
set +e
RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh > release-check.log 2>&1
rc=$?
printf 'release-check-exit-code=%s\n' "$rc" >> release-check.log
set -e
scripts/release-evidence.sh --allow-dirty --release-check-log release-check.log > release-evidence.md
exit "$rc"
```

The local preflight verifies the source/Bioconda install path via
`cargo install --locked --path crates/gxfkit`, using an offline install smoke
inside `release-check.sh` after the normal build has warmed the Cargo cache,
exercises the release archive
verifier (including checksum, unsafe-tar-member, and no-overwrite smoke
regressions), checks the release artifact contract so the workflow matrix,
readiness asset list, archive names, and upload globs stay aligned, verifies
the GitHub Release URL verifier, validates the Bioconda
recipe/template/build script, verifies the benchmark summarizer's metrics
validation, verifies residual-diagnostic candidate discovery, syntax-checks all
repository shell and Python scripts, checks that `release-check.sh` keeps its
deterministic local preflight contract, checks repository hygiene ignores for local
cache/evidence artifacts, verifies executable bits for scripts that docs or
workflows invoke directly, checks
release-facing version fields for consistency through both the normal check and
its CLI regression test, validates `benchmark/results/summary.tsv` when present
so core rows are present at 100% parity, checks that `docs/PARITY.md` still
matches the release gate, checks that an existing `vX.Y.Z` tag (if any) points to
the current commit, verifies workflow policy, crates.io metadata, release status,
install-doc, and release-guide consistency, verifies the `gxfkit-core` package
archive, includes the release-check contract guard in the release evidence
report, and uses `scripts/check-package-files.sh` to confirm both crate
archives include `Cargo.toml`, `README.md`, `LICENSE`, and the crate source
entrypoint (`src/lib.rs` for `gxfkit-core`, `src/main.rs` for `gxfkit`) under
`cargo package --locked`. Local `release-check.sh` runs its final `cargo package` smoke in
offline mode by default, reusing the cache already exercised by the build and
test steps instead of depending on registry mirror availability; set
`RELEASE_CHECK_PACKAGE_NETWORK=1` only when deliberately checking the online
registry path from the local machine. The workflow policy keeps release
automation on least privilege:
`release.yml` may use `contents: write` to create the GitHub Release, while CI,
Crates.io publish, and public-install audit workflows must stay at
`contents: read`. The `gxfkit` package is fully verified in the Crates.io GitHub
workflow after `gxfkit-core` is visible in the registry, because the binary crate
depends on the library by version.
Local package-file checks allow a dirty worktree by default so staged release
prep can run before every file is committed; CI and the Crates.io publish
workflow run the same guard with `PACKAGE_FILES_ALLOW_DIRTY=0` so public
packages are checked from a clean checkout.

If `bash scripts/release-check.sh` fails at `>> publish ref`, either check out
the existing tag for that version or bump the workspace version before release.
The preflight also checks that `docs/releases/vX.Y.Z.md` exists for the current
workspace version and contains the release evidence commands expected in the
GitHub Release notes, and verifies that maintainer-facing issue templates and
manual workflow prompts show the current workspace version rather than stale
release examples.

To prepare a new Cargo version before cutting the tag:

```bash
python3 scripts/prepare-next-version.py X.Y.Z --cargo-only
RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh
python3 scripts/release-readiness.py --phase tag
```

The scoped preflight checks the Cargo workspace/package version and skips the
Bioconda recipe, because the Bioconda checksum cannot be final until the
`vX.Y.Z` source archive exists.

After the tag exists and the GitHub source archive checksum is known, update
Bioconda metadata with:

```bash
python3 scripts/github-source-sha256.py X.Y.Z --format prepare-command
python3 scripts/prepare-next-version.py X.Y.Z \
  --bioconda-sha256 <sha256-of-vX.Y.Z-source-archive>
```

The first command prints the exact second command with the computed source
archive sha256. The second command updates both Bioconda recipe files together.
It intentionally requires the Bioconda sha256 and a local `vX.Y.Z` git tag, so a
release-prep commit cannot contain a placeholder checksum or point Bioconda at a
source archive that does not exist yet. After the Bioconda metadata update,
rerun the normal unscoped preflight:

```bash
bash scripts/release-check.sh
```

For a full parity refresh before a public release:

```bash
bash corpus/download.sh core
bash benchmark/run.sh
python3 scripts/check-benchmark-summary.py --require
```

Commit the regenerated README benchmark table only if the numbers changed for a
good reason. The release evidence report is meant to be pasted into the release
PR, GitHub Release notes, or issue thread; keep it as a temporary artifact unless
you intentionally want to version a specific release transcript. The report
can validate and include a recorded `release-check.log` via
`--release-check-log`; that recorded log must include `release-check-exit-code=0`.
Generate the report before re-exiting with the captured release-check status so
failed preflight runs still leave pasteable diagnostics. It includes an
`Evidence Status` section that lists every non-zero evidence block, so a
generated report is not by itself proof that the release is closed.

## 2. Crates.io

Publish the library crate first, then the binary crate:

```bash
cargo login
cargo publish -p gxfkit-core --registry crates-io
# Wait until the registry index sees gxfkit-core.
cargo publish -p gxfkit --registry crates-io
```

The `gxfkit` package depends on `gxfkit-core` by version, so `gxfkit` cannot be
verified against the registry until `gxfkit-core` is visible there.

On machines that replace crates.io with a mirror in `~/.cargo/config.toml`, the
explicit `--registry crates-io` flag may still use the configured replacement for
`cargo package` / `cargo publish`. For the real publish, prefer the manual
GitHub workflow below or run from a clean Cargo environment with no
`source.crates-io.replace-with`.

Alternatively, run the manual **Publish Crates.io** GitHub Actions workflow.
The safest entrypoint is:

```bash
scripts/trigger-crates-publish.sh X.Y.Z both publish
```

That wrapper checks that `vX.Y.Z` exists locally and on `origin`, verifies the
remote tag resolves to the same commit as the local tag, verifies the
`CARGO_REGISTRY_TOKEN` repository secret is configured, and triggers the
workflow with `source_ref=vX.Y.Z`.
It first validates that the requested version looks like `X.Y.Z`, that
`source_ref` is non-empty and contains no whitespace, and that `confirm` is
exactly `publish`, before checking out the publish ref. It requires a repository
secret named `CARGO_REGISTRY_TOKEN` and verifies that the secret is configured
before the expensive publish preflight starts. By default it checks out
`vX.Y.Z` for the requested version. Treat that release tag as the Crates.io
source of truth; do not publish an already-tagged public version from a newer
branch or SHA.
The workflow verifies the Cargo package versions against the requested publish version, runs
fmt/clippy/tests plus a release build and local
`cargo install --locked --path` smoke test, runs the release-archive,
GitHub-release, Bioconda-recipe, publish-ref, benchmark-summary,
package-file-list, residual-writer, and version-consistency regressions,
publishes `gxfkit-core` first, waits for registry visibility, packages `gxfkit`
against the visible registry crate, then publishes `gxfkit`, waits for `gxfkit`
registry visibility, and verifies `cargo install gxfkit` from Crates.io with a
smoke conversion.
Even a `gxfkit-core`-only workflow run waits for `gxfkit-core` registry
visibility before succeeding, so a retry leaves a concrete propagation signal
rather than only a publish API response.
If the second step needs to be retried, rerun the workflow with the crate scope
set to `gxfkit`.

If a `vX.Y.Z` tag already exists, the publish-ref check requires the workflow's
HEAD to match that tag. This prevents publishing the same version from a newer
commit after GitHub Release or Bioconda artifacts with that version already
exist.

After a manual publish, verify the Crates.io install path directly:

```bash
VERSION=X.Y.Z bash scripts/verify-crates-install.sh
```

To audit all public install channels after release propagation:

```bash
python3 scripts/release-readiness.py --phase public --check-public
python3 scripts/release-readiness.py --phase public --check-public --run-public-audit
VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates" \
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0 \
VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1 \
VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100 \
BENCH_FILES="human_chr1 human_chr21 yeast" \
VERSION=X.Y.Z RELEASE_TAG=vX.Y.Z bash scripts/verify-public-installs.sh
```

The `--run-public-audit` readiness mode runs the same strict audit, captures the
audit output, appends the audit exit code, and validates the recorded log with
`scripts/check-public-audit-log.py`. Public closure requires both public channel
discovery and this verified audit log to pass. Public channel discovery checks
that the GitHub Release tag exists as a non-draft, non-prerelease release, and
that the remote GitHub tag resolves to the local tag commit when the local tag is
available. It requires all four platform archives plus their `.sha256` files to
be attached, uploaded, non-empty, and have the expected GitHub download URLs
before treating the GitHub channel as ready. The expected package asset set is
closed: duplicate asset names fail readiness, and extra `gxfkit-vX.Y.Z-*.tar.gz`
or `gxfkit-vX.Y.Z-*.tar.gz.sha256` assets fail unless the release matrix and
readiness package list are updated together. Ordinary non-package release notes
attachments are allowed. The `.sha256` files must each contain one checksum
line that points at the matching archive name, and the four checksum digests must
be unique. It also
requires Bioconda `linux-64` and `osx-64` build `0` main package files to be
present without the `broken` label and with valid checksums and non-zero sizes, and
requires the Crates.io versions to be present, explicitly `yanked: false`, and
published with a valid checksum plus non-zero crate size before treating those
registry channels as ready. Public channel discovery uses bounded retries and
timeouts for remote metadata requests so release checks fail fast enough to
diagnose.

The same audit is available as the manual **Public Install Audit** GitHub
Actions workflow. Use that workflow for final release evidence from a clean
Ubuntu runner. It validates the requested `version`/`tag` pair before checkout,
so malformed versions or mismatched tags fail before any public install work
starts. The workflow uploads `release-evidence.md` as an artifact even
when the audit fails, together with the captured `public-audit.log`, so the
failed channel, exact command output, and audit exit code are available for
follow-up. The audit step records its exit code instead of stopping the job
immediately, and the always-running log-validation step enforces the final
workflow status from the structured log. If you run the workflow with staged inputs such as
`allow_missing_crates`, the workflow validates the recorded log against those
requested staged inputs and `release-evidence.md` includes a
`Recorded Public Audit Log Guards` block for that exact run; the
`Final Strict Public Audit Log Guards` block still fails until all four public
channels pass and no missing channel is allowed. The workflow also records and
validates the Crates.io install verifier path, defaulting to
`scripts/verify-crates-install.sh`. If that input is overridden, it must be a
repository-relative `scripts/*.sh` path; absolute paths, path traversal, shell
options, and paths with whitespace are rejected before the audit runs.
After propagation, rerun the evidence report with public checks enabled:

```bash
scripts/release-evidence.sh --check-public > release-evidence.md
```

The audit is strict by default: the GitHub Release Linux binary must refuse
unsafe overwrites, that same release binary must reproduce AGAT on the core
corpus at `MIN_PARITY=100`, and Bioconda plus Crates.io must install and run the
smoke conversion. During the short window after GitHub Release/Bioconda are live
but before Crates.io has been published, use:

```bash
VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=1 \
  VERSION=X.Y.Z RELEASE_TAG=vX.Y.Z bash scripts/verify-public-installs.sh
```

Keep the default `VERIFY_PUBLIC_INSTALLS_NO_OVERWRITE=1` and
`VERIFY_PUBLIC_INSTALLS_MIN_PARITY=100`, leave
`VERIFY_PUBLIC_INSTALL_CHANNELS="github-linux github-parity bioconda crates"`,
and keep `VERIFY_PUBLIC_INSTALLS_ALLOW_MISSING_CRATES=0` unless a release
explicitly documents a weaker public binary threshold. Public `v0.0.1` packages
predate the no-overwrite behavior and are expected to fail the default strict
audit.

## 3. GitHub Release

Tag from a clean main branch:

```bash
gh auth status
# If the token scopes do not include `workflow` and this release prep changes
# `.github/workflows/*.yml`, refresh before pushing main:
gh auth refresh -h github.com -s workflow
git push origin main
git tag -a vX.Y.Z -m "gxfkit vX.Y.Z"
git push origin vX.Y.Z
```

The release workflow builds draft artifacts for:

- `linux-x86_64-static`
- `linux-aarch64-static`
- `macos-x86_64`
- `macos-aarch64`

The release workflow verifies each archive on its native build runner by
checking that `vX.Y.Z` exists as a git tag, that the checkout `HEAD` matches that
tag, and that the tag matches the Cargo workspace version, then checking the
`.sha256`, extracting the tarball, and running a small `gff2gtf` conversion with
the extracted binary, including the no-overwrite guard. The final publish job
first verifies that the downloaded artifact set contains exactly the expected
four platform archives plus matching `.sha256` files, then re-checks every
downloaded archive in structure-only mode, because one Ubuntu runner cannot
execute macOS or non-native Linux binaries. The draft GitHub Release body is
loaded from `docs/releases/vX.Y.Z.md`, and that file is checked before the draft
is created. Before creating the draft, the publish job also runs
`scripts/release-readiness.py --phase tag --version X.Y.Z`, so the workflow
reuses the same tag-readiness guard as local release prep. It also uploads a
`release-evidence.md` artifact from the clean tag checkout before creating the
draft release, so the GitHub Release workflow leaves a maintainer evidence
trail even when a later publish step fails. The evidence step runs
`RELEASE_CHECK_VERSION_SCOPE=cargo bash scripts/release-check.sh` from the clean
tag checkout, appends `release-check-exit-code`, validates that recorded log via
`scripts/release-evidence.sh --release-check-log`, and stops before creating the
draft if the preflight failed. Release, Crates.io publish, and public-install
audit workflows are serialized by release version/tag and do not auto-cancel
in-progress runs. Crates.io publishes are serialized across all crate scopes for
the same version, so a `gxfkit-core` retry cannot race a `gxfkit` publish. CI
and release jobs also set explicit timeouts so stalled runners or registry
polling cannot occupy a release queue indefinitely.

Before publishing the draft, verify at least the current host's archive from the
published GitHub asset URL. This verifier checks the no-overwrite guard by
default:

```bash
RELEASE_TAG=vX.Y.Z bash scripts/verify-github-release-install.sh
```

Only for legacy packages that predate the no-overwrite guard, set
`VERIFY_RELEASE_ARCHIVE_NO_OVERWRITE=0` to keep checksum, archive-safety,
version, and conversion smoke checks while skipping the no-overwrite smoke.

Verify the Linux static archive in a clean container:

```bash
RELEASE_TAG=vX.Y.Z bash scripts/verify-github-release-linux-docker.sh
```

This clean-container verifier also runs `scripts/verify-release-archive.sh`
inside the container with `VERIFY_RELEASE_ARCHIVE_SMOKE=0`, so the published
Linux tarball must pass the same checksum, path-safety, and member-whitelist
checks before the binary smoke test executes.

To check a published Linux binary against AGAT on a small corpus slice:

```bash
RELEASE_TAG=vX.Y.Z BENCH_FILES=yeast bash scripts/verify-github-release-parity.sh
```

The default `MIN_PARITY` for this release-binary smoke is 100. Lower it only
when deliberately checking an extended stress file whose residual is already
documented in [PARITY.md](PARITY.md).
Use `DOWNLOAD_DIR=/path/to/cache` to reuse downloaded release assets across
retries. If the archive was downloaded elsewhere, pass `RELEASE_ARCHIVE=/path/to/archive.tar.gz`;
`RELEASE_CHECKSUM=/path/to/archive.tar.gz.sha256` is optional when the checksum
sits next to the archive.

To inspect a non-native archive without executing it, set `PACKAGE` and disable
the smoke run:

```bash
PACKAGE=linux-x86_64-static VERIFY_RELEASE_ARCHIVE_SMOKE=0 \
  RELEASE_TAG=vX.Y.Z bash scripts/verify-github-release-install.sh
```

## 4. Bioconda

After the GitHub release is public, open or update the Bioconda recipe with the
release archive URL and sha256. Keep the recipe pointed at the published source
or release archive, not a moving branch.

Verify the recipe version fields and, when network access is available, the
remote source checksum:

```bash
python3 scripts/check-bioconda-recipe.py
bash scripts/test-bioconda-recipe.sh
python3 scripts/check-version-consistency.py --check-remote-bioconda-sha256
```

After the Bioconda PR is merged and the package upload has propagated, verify
the actual install path in a clean micromamba container. This verifier checks
the no-overwrite guard by default:

```bash
VERSION=X.Y.Z bash scripts/verify-bioconda-install.sh
```

For `v0.0.1`, PR
[bioconda-recipes#66815](https://github.com/bioconda/bioconda-recipes/pull/66815)
merged and the install verifier passed for `gxfkit 0.0.1`; because that package
predates the no-overwrite guard, verify it with
`VERIFY_BIOCONDA_NO_OVERWRITE=0`.

## 5. Announcement

Link to:

- the GitHub release
- the README benchmark table
- `docs/PARITY.md`
- the exact AGAT baseline version
