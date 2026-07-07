# gxf2gxf standardization parity

**Baseline:** AGAT `1.7.0`
(`quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0`).
**Subcommand:** `gxf2gxf` (`agat_convert_sp_gxf2gxf.pl`).

This is the GFF3 standardization ledger for the experimental M3 `gxf2gxf`
engine. It complements [PARITY.md](PARITY.md), which tracks the release-grade
`gff2gtf` converter.

The fixture gate is byte-for-byte: every file under
`benchmark/gxf2gxf-fixtures/` is exact-diffed against AGAT in CI. The corpus
report below is broader and intentionally diagnostic. It normalizes only
comments, line order, whitespace, and GFF3 attribute order; values, coordinates,
sources, feature types, `ID`, and `Parent` links remain real residuals.

## Reproduction

```bash
bash corpus/download.sh
bash benchmark/run-gxf2gxf-corpus.sh
```

Outputs are written to the ignored directory
`benchmark/gxf2gxf-corpus-results/`:

- `<name>.agat.gff3`
- `<name>.gxfkit.gff3`
- `<name>.summary.txt`
- `summary.tsv`

The diagnostic helper is
`tests/parity/gff3_residual_summary.py`.

## Current corpus snapshot

Measured locally on 2026-07-07 from the currently pinned corpus files present
under `corpus/raw/`.

| file | AGAT lines | gxfkit lines | matched | AGAT-only | gxfkit-only | parity |
|------|------------|--------------|---------|-----------|-------------|--------|
| yeast | 28,695 | 28,695 | 28,691 | 4 | 4 | **99.97%** |
| drosophila | 506,317 | 508,218 | 311,784 | 194,533 | 196,434 | 44.37% |
| human_chr1 | 316,543 | 316,638 | 186,175 | 130,368 | 130,463 | 41.65% |
| human_chr21 | 39,819 | 39,859 | 22,429 | 17,390 | 17,430 | 39.18% |
| ecoli_refseq | 18,016 | 18,165 | 5,130 | 12,886 | 13,035 | 16.52% |

## What this proves

- The M3 fixture gate is now exercising the intended first beta slice:
  direct-child hierarchy completion, multi-CDS fragments, FlyBase/TE remodeling,
  orphan exon/CDS children, and self-parent exon cycles.
- On the yeast corpus, structural TE remodeling is effectively closed for
  `gxf2gxf`; the remaining measured residual is four idless `five_prime_UTR`
  rows where AGAT creates `agat-five_prime_utr-N` IDs and gxfkit preserves the
  original idless rows.
- Large Ensembl/FlyBase files are still dominated by AGAT synthetic-ID rewrite
  policy for idless or duplicate rows: `agat-exon-N`, `agat-five_prime_utr-N`,
  `agat-three_prime_utr-N`, `agat-biological_region-N`, and
  `agat-transposable_element-N`.
- RefSeq `gxf2gxf` is not yet corpus-close even though focused direct-CDS
  fixtures match AGAT. The E. coli residual is mostly synthetic counter drift
  and broader AGAT hierarchy/rewrite policy: AGAT-only rows include 4,310 exon,
  4,288 mRNA, 4,273 gene, and 15 pseudogene records, mirrored by gxfkit rows
  with different synthetic counters plus a small number of extra source-shaped
  pseudogene/CDS/root rows.

## Main residual families

### YEAST-GXF2GXF-1 — four idless UTR IDs

**Where:** yeast `five_prime_UTR` rows on chromosomes IX, X, XIII, and XV.
**AGAT:** assigns `ID=agat-five_prime_utr-1..4`.
**gxfkit:** currently preserves the idless source rows with only `Parent`.
**Impact:** 99.97% normalized corpus parity.
**Class:** GAP. This is small and should be closed with an AGAT probe fixture
before broad UTR ID rewrite work.

### FLYBASE-GXF2GXF-1 — synthetic counter policy at scale

**Where:** Drosophila exon, UTR, RNA, and transposable-element rows.
**AGAT-only dominant families:** 102,234 `exon ID:agat-exon`, 46,773
`five_prime_UTR ID:agat-five_prime_utr`, 33,736
`three_prime_UTR ID:agat-three_prime_utr`, and 5,895
`transposable_element ID:agat-transposable_element` rows.
**gxfkit:** preserves many source/idless child rows and uses deterministic TE
counter assignment rather than AGAT's internal large-corpus counter order.
**Class:** GAP/PARTIAL. Fixture-level TE structure is covered; large-corpus
counter policy remains open.

### ENSEMBL-GXF2GXF-1 — idless feature rewrite policy

**Where:** human chr1 and chr21.
**AGAT:** assigns synthetic IDs to idless/duplicate exon, UTR, and
`biological_region` rows.
**gxfkit:** currently preserves source-shaped rows for most of these cases.
**Impact:** human chr1 is 41.65%; human chr21 is 39.18%.
**Class:** GAP. This is not a line-order issue; it is AGAT standardization's
feature-ID rewrite policy.

### REFSEQ-GXF2GXF-1 — broader RefSeq standardization

**Where:** E. coli RefSeq.
**AGAT:** rewrites most gene/CDS hierarchy rows into synthetic `agat-gene-N`,
`agat-pseudogene-N`, and `agat-exon-N` families.
**gxfkit:** matches the focused direct-child fixtures but still diverges on
large-corpus counter order and additional RefSeq root/pseudogene/CDS cases.
**Impact:** 16.52% normalized corpus parity.
**Class:** GAP. This is the highest-value next corpus-driven rule family if M3
continues beyond the beta fixture slice.

## Beta interpretation

This ledger is intentionally not a victory lap. It says the current M3 beta
slice has a real regression harness and a measured residual surface:

- **Beta-ready:** fixture-backed standardization behavior is explicit, tested,
  and CI-gated against AGAT 1.7.0.
- **Not complete AGAT compatibility:** large-corpus GFF3 standardization remains
  open, especially synthetic-ID rewrite/counter policy and broader RefSeq
  normalization.

Do not cut a release that advertises `gxf2gxf` as a full AGAT replacement from
this state.
