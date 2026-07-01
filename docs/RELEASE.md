# Release Checklist

This project treats AGAT parity as the correctness bar, so releases should be
boring: run the checks, publish artifacts, verify the binary, then announce.

## 1. Preflight

From the repository root:

```bash
bash scripts/release-check.sh
```

For a full parity refresh before a public release:

```bash
bash corpus/download.sh core
bash benchmark/run.sh
```

Commit the regenerated README benchmark table only if the numbers changed for a
good reason.

## 2. Crates.io

Publish the library crate first, then the binary crate:

```bash
cargo login
cargo publish -p gxfkit-core
# Wait until the registry index sees gxfkit-core.
cargo publish -p gxfkit
```

The `gxfkit` package depends on `gxfkit-core` by version, so `gxfkit` cannot be
verified against the registry until `gxfkit-core` is visible there.

## 3. GitHub Release

Tag from a clean main branch:

```bash
git tag -a vX.Y.Z -m "gxfkit vX.Y.Z"
git push origin vX.Y.Z
```

The release workflow builds draft artifacts for:

- `linux-x86_64-static`
- `linux-aarch64-static`
- `macos-x86_64`
- `macos-aarch64`

Before publishing the draft, download each archive and run:

```bash
./gxfkit version
./gxfkit gff2gtf -g small.gff3 -o /tmp/small.gtf
```

Also check the `.sha256` file:

```bash
shasum -a 256 -c gxfkit-vX.Y.Z-linux-x86_64-static.tar.gz.sha256
```

## 4. Bioconda

After the GitHub release is public, open or update the Bioconda recipe with the
release archive URL and sha256. Keep the recipe pointed at the published source
or release archive, not a moving branch.

## 5. Announcement

Link to:

- the GitHub release
- the README benchmark table
- `docs/PARITY.md`
- the exact AGAT baseline version
