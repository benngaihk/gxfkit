# Parity with AGAT

**Baseline:** AGAT `1.7.0` (biocontainer `quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0`).
**Subcommand:** `gff2gtf` (`agat_convert_sp_gff2gtf.pl`, default `--gtf_version relax`).

Parity is measured by running both tools on every corpus file, passing each
output through `tests/parity/normalize.py` (order- and whitespace-insensitive,
but value-preserving), and diffing. The goal for a subcommand to be considered
"done" is **≥95% of corpus files normalize-identical**, with every residual
difference listed here and classified.

This file is the project's honesty ledger. Each divergence is either:

- **EQUIV** — semantically equivalent, normalized away; or
- **GAP** — gxfkit not yet matching AGAT (tracked, will close); or
- **FIX** — an intentional deviation because AGAT's behavior is a bug.

---

## Current status (M0 spike)

`gff2gtf`, post-normalization parity on the pinned corpus:

| file        | lines  | parity | dominant residual                       |
|-------------|--------|--------|-----------------------------------------|
| yeast       | ~28.7k | ~73%   | GAP-1 (synthesized exon IDs)            |
| human_chr21 | ~40k   | ~31%   | GAP-1, GAP-2, GAP-3                     |
| human_chr1  | ~316k  | ~34%   | GAP-1, GAP-2, GAP-3                     |

These are an honest *starting* baseline: the spike implements the GFF→GTF core
(hierarchy resolution, gene_id/transcript_id derivation incl. Ensembl prefix
stripping, attribute carry-over). The remaining gaps are all **systematic and
enumerated below** — closing them is the M1 work item, and none requires new
ideas, only faithfully reproducing AGAT's deterministic feature-mangling rules.

---

## Divergences

### GAP-1 — AGAT synthesizes a missing `ID` on child features
**Where:** `exon` (and any feature) lines whose source GFF3 has no `ID=`.
**AGAT:** adds `ID "<value>"`, taking the value from `exon_id` / `Name` (for
exons) so every emitted feature has an `ID`.
**gxfkit (now):** omits `ID` when the source had none.
**Class:** GAP. **Plan:** replicate AGAT's ID-synthesis: for a child feature
lacking `ID`, derive it (exon → `exon_id`, else `<transcript_id>-<type><rank>`).
This single rule accounts for the bulk of the residual on every file.

### GAP-2 — AGAT's `agat-<type>-<N>` counter for ID-less standalone features
**Where:** `biological_region` and similar features with neither `ID` nor parent.
**AGAT:** assigns `gene_id "agat-biological_region-1"; ID "agat-biological_region-1"`,
an incrementing per-type counter.
**gxfkit (now):** uses a coordinate-based synthetic id, e.g.
`gene_id "21:5020208-5023177"`.
**Class:** GAP. **Plan:** implement AGAT's `agat-<type>-<counter>` scheme
(counter is per feature-type, assigned in document order).

### GAP-3 — multi-value `tag` handling
**Where:** transcript features with `tag=basic,Ensembl_canonical`.
**AGAT:** appears to split/relocate multi-value `tag` attributes (single-value
`tag` is preserved as-is — see yeast `tag "Ensembl_canonical"`).
**gxfkit (now):** carries the raw comma-joined value `tag "basic,Ensembl_canonical"`.
**Class:** GAP (needs confirmation of AGAT's exact rule). **Plan:** characterize
on more samples, then match (likely emit one `tag "x"` per value).

### GAP-4 — `Alias` dropped on the top-level region line
**Where:** the `chromosome` feature.
**AGAT:** emits only `gene_id` + `ID` (drops `Alias`).
**gxfkit (now):** carries `Alias` through.
**Class:** GAP (low impact: 1 line/file). **Plan:** confirm whether AGAT drops
`Alias` generally or only on top-level features, then match.

---

## Notes on method

- The normalizer pins `gene_id`/`transcript_id` first (GTF spec) and sorts the
  remaining attributes, so attribute *order within a line* never causes a false
  divergence. Line order is also normalized. Anything else — a different value,
  a missing/extra attribute, a different coordinate — is a real difference and
  shows up in the diff.
- AGAT is a moving target; we pin a version. When we bump it, re-run the harness
  and reconcile this ledger.
