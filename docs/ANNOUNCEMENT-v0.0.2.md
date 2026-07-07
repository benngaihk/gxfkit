# gxfkit v0.0.2 announcement draft

Use this as source copy for GitHub Discussions, rust-bio, bioinformatics Slack,
or a short social post. Keep the caveats with the announcement; they are part of
the trust contract.

## Short version

`gxfkit` v0.0.2 is now installable from GitHub Releases, Bioconda, and
Crates.io. It is a fast Rust reimplementation of AGAT's `gff2gtf` path, using
AGAT 1.7.0 as the correctness oracle. On the gated core corpus
(`human_chr1`, `human_chr21`, `yeast`), the release binary reaches 100%
normalized parity with AGAT and remains much faster than the Perl baseline.

Install:

```bash
cargo install gxfkit --version 0.0.2
conda install -c conda-forge -c bioconda gxfkit=0.0.2
```

GitHub Release archives are available at:
<https://github.com/benngaihk/gxfkit/releases/tag/v0.0.2>

## Longer post

`gxfkit` v0.0.2 is the first fully public distribution beta: the same version is
available from GitHub Releases, Bioconda, and Crates.io, and all three install
paths have passed the strict public audit.

What is included:

- `gff2gtf`, with AGAT 1.7.0 treated as the output oracle.
- 100% normalized AGAT parity on the gated core corpus:
  `human_chr1`, `human_chr21`, and `yeast`.
- A no-overwrite guard for `-o` / `--output`, so reruns do not silently replace
  existing files.
- Gzip input auto-detection and `--sanitize` diagnostics for malformed records.
- Release checks that verify GitHub archive install, clean Linux install,
  release-binary parity, Bioconda install, and Crates.io install.

Install from Crates.io:

```bash
cargo install gxfkit --version 0.0.2
gxfkit gff2gtf -i input.gff3 -o output.gtf
```

Install from Bioconda:

```bash
conda install -c conda-forge -c bioconda gxfkit=0.0.2
gxfkit gff2gtf -i input.gff3 -o output.gtf
```

Download a GitHub Release archive:

```bash
curl -L -O https://github.com/benngaihk/gxfkit/releases/download/v0.0.2/gxfkit-v0.0.2-linux-x86_64-static.tar.gz
tar -xzf gxfkit-v0.0.2-linux-x86_64-static.tar.gz
./gxfkit-v0.0.2-linux-x86_64-static/gxfkit version
```

Caveats:

- `gxfkit` is still alpha and currently focuses on `gff2gtf`.
- AGAT's broader hierarchy standardization engine is the next large milestone;
  `gxf2gxf` is not implemented yet.
- Extended Drosophila remains a documented stress-case divergence around AGAT's
  internal synthetic counter ordering. The strict release gate is the core
  corpus.

Evidence:

- Release notes: <https://github.com/benngaihk/gxfkit/blob/main/docs/releases/v0.0.2.md>
- Release status: <https://github.com/benngaihk/gxfkit/blob/main/docs/RELEASE-STATUS.md>
- Parity ledger: <https://github.com/benngaihk/gxfkit/blob/main/docs/PARITY.md>

## One-line post

`gxfkit` v0.0.2 is out: a Rust AGAT-compatible `gff2gtf` path, now installable
from GitHub Releases, Bioconda, and Crates.io, with 100% normalized parity on
the gated core corpus.
