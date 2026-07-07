# gxfkit M3 beta soft-launch kit

Use this as source copy for GitHub Discussions, rust-bio, bioinformatics Slack,
workflow-tool forums, and direct maintainer outreach. Keep the caveats attached
to every post; the trust contract matters more than the headline.

## Positioning

`gxfkit` is a fast Rust implementation of selected AGAT-compatible GFF/GTF
workflows. The release-grade path is `gff2gtf`: AGAT 1.7.0 is the correctness
oracle, and the gated core corpus is 100% normalize-identical after documented
order-only normalization.

The current `main` branch also includes a `gxf2gxf` standardization beta. That
beta is fixture-gated against AGAT and has a large-corpus residual ledger, but
it is not a full AGAT replacement yet.

## Short post

`gxfkit` is moving from "fast gff2gtf beta" toward a broader AGAT-compatible
toolkit.

The production-supported path is still `gff2gtf`: AGAT 1.7.0 is used as the
correctness oracle, the gated core corpus (`human_chr1`, `human_chr21`,
`yeast`) is 100% normalize-identical, and public `0.0.2` packages are available
from GitHub Releases, Bioconda, and Crates.io.

The `main` branch now also has a `gxf2gxf` standardization beta for users who
want to test the next large compatibility slice. It is fixture-gated against
AGAT and ships with a large-corpus residual ledger, so known divergences are
visible rather than hidden.

It is not a full AGAT replacement yet. If you have messy real-world GFF3 files,
especially ones that stress AGAT hierarchy standardization, those are exactly
the cases that would make the beta better.

Install the current public release:

```bash
cargo install gxfkit --version 0.0.2
conda install -c conda-forge -c bioconda gxfkit=0.0.2
```

Try the current `main` beta:

```bash
cargo install --git https://github.com/benngaihk/gxfkit gxfkit
```

Evidence:

- Parity ledger: <https://github.com/benngaihk/gxfkit/blob/main/docs/PARITY.md>
- `gxf2gxf` beta ledger: <https://github.com/benngaihk/gxfkit/blob/main/docs/GXF2GXF-PARITY.md>
- Roadmap: <https://github.com/benngaihk/gxfkit/blob/main/docs/ROADMAP.md>

## One-line post

`gxfkit` now has a release-grade AGAT-compatible `gff2gtf` path plus a
fixture-gated `gxf2gxf` standardization beta on `main`; it is fast, documented,
and still honest about not being a full AGAT replacement.

## Longer post

`gxfkit` is a Rust reimplementation of selected AGAT GFF/GTF workflows. The
project goal is not to claim blanket compatibility with every AGAT command, but
to make the most common expensive paths faster while keeping AGAT output as the
correctness oracle.

What is production-supported today:

- `gff2gtf`, matching `agat_convert_sp_gff2gtf.pl` for the supported path.
- AGAT 1.7.0 as the gold-standard output.
- 100% normalized parity on the gated core corpus:
  `human_chr1`, `human_chr21`, and `yeast`.
- Public installation from GitHub Releases, Bioconda, and Crates.io for
  `0.0.2`.

What is ready for beta feedback:

- `gxf2gxf` standardization on the `main` branch.
- AGAT fixture parity for the implemented standardization slice.
- Documented residuals from larger corpus runs, including cases that still need
  AGAT-compatible synthetic counter behavior.

What is not claimed:

- `gxfkit` is not a full AGAT replacement.
- The current public `0.0.2` package does not include the latest `gxf2gxf` beta.
- Users should not swap it into production without checking their own files
  against AGAT output.

The useful feedback now is concrete: minimal GFF3/GTF examples where AGAT and
`gxfkit` differ, the exact command lines, and the AGAT version. That helps turn
the compatibility ledger into real-world coverage.

## Suggested launch sequence

1. Open a GitHub Discussion, or a pinned issue if Discussions are not enabled,
   using the short post and pin it from the README.
2. Post the one-line version to lightweight social channels with links to the
   README and parity ledgers.
3. Share the short post in rust-bio and bioinformatics Slack/forums, asking for
   messy GFF3 test cases rather than broad praise.
4. Contact maintainers of Snakemake, Nextflow, nf-core, and Galaxy wrappers only
   after at least a few external files have been tested against the beta.
5. Cut a carefully worded `v0.0.3` only after deciding whether the `gxf2gxf`
   beta wording belongs in a public release.

## Target channels

- GitHub Discussions or a pinned issue in this repository.
- rust-bio community channels.
- Bioinformatics Slack/forums where AGAT users already gather.
- Bioconda/GitHub Release notes for installability updates.
- Later: Snakemake wrapper, Nextflow module, nf-core issue, Galaxy tool listing,
  JOSS or Bioinformatics Application Note.

## Caveats to preserve

- AGAT remains the correctness oracle.
- `gff2gtf` is the supported production path.
- `gxf2gxf` is a beta on `main`, not a complete standardization engine.
- Public `0.0.2` installs are still the stable user-facing package.
- Known divergences belong in the parity ledgers before being treated as
  acceptable behavior.
