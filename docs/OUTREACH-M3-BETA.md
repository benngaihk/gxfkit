# M3 beta outreach playbook

This is the execution checklist for the first public feedback sweep. The goal
is not broad launch noise. The goal is to collect real GFF3/GTF files that
stress AGAT hierarchy standardization, then turn those cases into documented
parity coverage.

Public feedback thread:
<https://github.com/benngaihk/gxfkit/issues/7>

Source copy:
[SOFT-LAUNCH-M3-BETA.md](SOFT-LAUNCH-M3-BETA.md)

## Guardrails

- Ask for reproducible test cases, not praise.
- Keep `gff2gtf` and `gxf2gxf` separate: `gff2gtf` is production-supported;
  `gxf2gxf` is a `main`-branch beta.
- Never describe `gxfkit` as a full AGAT replacement.
- Link to the parity ledgers whenever making a compatibility claim.
- Prefer one high-signal post per community over repeated cross-posting.
- Do not ask wrapper ecosystems to adopt `gxf2gxf` before external beta files
  have been tested.

## Wave 1: feedback, not adoption

Run this wave first. Success means at least one external user or maintainer
shares a concrete file, command, or divergence.

| Channel | Action | Primary ask | Done when |
|---|---|---|---|
| GitHub pinned issue | Already created as #7 | Minimal AGAT-vs-gxfkit divergences | Issue is pinned and linked from README |
| Biostars | Post a feedback request, not a support answer | Messy GFF3/GTF files and AGAT commands | Post URL is added below |
| Rust-Bio / Rust bioinformatics circles | Share the one-line technical summary | Rust users who process annotation files | Post URL is added below |
| Personal / lab network | Send direct note to AGAT or workflow users | Private files or smallest public repro | At least 3 people contacted |

### Biostars draft

Suggested title:

```text
Looking for messy GFF3 examples to test a Rust AGAT-compatible gxf2gxf beta
```

Suggested body:

```markdown
I am testing `gxfkit`, a Rust implementation of selected AGAT-compatible
GFF/GTF workflows.

The production-supported path is `gff2gtf`, using AGAT 1.7.0 as the correctness
oracle. On the gated core corpus (`human_chr1`, `human_chr21`, `yeast`), the
output is 100% normalize-identical after documented order-only normalization.

The current `main` branch also has a `gxf2gxf` standardization beta. It is
fixture-gated against AGAT and has a public residual ledger, but it is not a
full AGAT replacement yet.

I am looking for real GFF3 files that stress AGAT hierarchy standardization:
missing parents, direct CDS/exon/UTR children, transposable-element loci,
or unusual RefSeq/FlyBase-style structures.

Useful feedback would include:

- AGAT version.
- `gxfkit` version or commit.
- Original command lines.
- Minimal input snippet if possible.
- The smallest AGAT-vs-gxfkit output difference.

Feedback thread:
https://github.com/benngaihk/gxfkit/issues/7

Parity ledgers:
https://github.com/benngaihk/gxfkit/blob/main/docs/PARITY.md
https://github.com/benngaihk/gxfkit/blob/main/docs/GXF2GXF-PARITY.md
```

### Rust-Bio / Rust bioinformatics draft

```markdown
`gxfkit` is a Rust implementation of selected AGAT-compatible GFF/GTF
workflows. The stable path is `gff2gtf`; AGAT 1.7.0 is the correctness oracle,
with 100% normalized parity on the gated core corpus.

The `main` branch now has a fixture-gated `gxf2gxf` standardization beta. I am
looking for real annotation files that stress AGAT hierarchy repair, especially
messy GFF3 files with missing parents, direct CDS/exon/UTR children, or TE
loci.

Feedback thread:
https://github.com/benngaihk/gxfkit/issues/7

Install release:
`cargo install gxfkit --version 0.0.2`

Try beta:
`cargo install --git https://github.com/benngaihk/gxfkit gxfkit`
```

### Direct maintainer note

```text
Hi <name>,

I am testing gxfkit, a Rust implementation of selected AGAT-compatible GFF/GTF
workflows. The stable path is gff2gtf; the current main branch also has a
fixture-gated gxf2gxf standardization beta.

If you have a messy GFF3 file that you currently rely on AGAT to normalize, I
would value a minimal repro or a command/output difference. The goal is to turn
real-world AGAT behavior into documented parity tests, not to claim full AGAT
replacement yet.

Feedback thread:
https://github.com/benngaihk/gxfkit/issues/7
```

## Wave 2: workflow ecosystem

Start this only after Wave 1 produces at least one real external test case or a
clear "no divergence on my files" report.

| Ecosystem | Gate before contact | Action |
|---|---|---|
| Snakemake | `gff2gtf` examples are stable and documented | Add a minimal wrapper example or ask for review |
| Nextflow / nf-core | Public release behavior is enough for `gff2gtf`; beta evidence exists for `gxf2gxf` | Propose a module only after checking current nf-core module conventions |
| Galaxy | CLI and conda package are stable; wrapper tests exist | Prototype wrapper locally before asking IUC / Tool Shed maintainers |
| JOSS / paper | External users or issue links exist | Draft only after there is public usage evidence |

## Tracking

Add links as posts go live.

| Date | Channel | URL | Result | Follow-up |
|---|---|---|---|---|
| 2026-07-07 | GitHub issue | https://github.com/benngaihk/gxfkit/issues/7 | Pinned feedback thread | Watch for reproductions |
|  | Biostars |  |  |  |
|  | Rust-Bio / Rust bioinformatics |  |  |  |
|  | Direct maintainer 1 |  |  |  |
|  | Direct maintainer 2 |  |  |  |
|  | Direct maintainer 3 |  |  |  |

## Response templates

### When someone reports a divergence

```text
Thanks, this is exactly the kind of case that helps. Could you add the AGAT
version, original command line, and the smallest input/output fragment that
reproduces the difference? I will classify it in the parity ledger before
treating it as accepted behavior.
```

### When someone asks if this replaces AGAT

```text
Not yet. `gff2gtf` is the production-supported path. `gxf2gxf` is a
standardization beta on `main`, fixture-gated against AGAT and documented with
a corpus residual ledger, but it is not a full AGAT replacement.
```

### When someone asks which version to install

```text
Use `cargo install gxfkit --version 0.0.2` or
`conda install -c conda-forge -c bioconda gxfkit=0.0.2` for the current public
release. To test the unreleased `gxf2gxf` beta, install from `main` with
`cargo install --git https://github.com/benngaihk/gxfkit gxfkit`.
```

## Success criteria

The first outreach wave is successful if any of these happen:

- One external file becomes a new fixture or documented residual.
- One user confirms `gff2gtf` works in an existing workflow.
- One maintainer identifies a blocker for Snakemake/Nextflow/Galaxy adoption.
- One issue is opened with enough data to reproduce an AGAT divergence.

If none of these happen after one week, revise the ask to be narrower:
"send one AGAT command and one small GFF3 that you consider hard to normalize."
