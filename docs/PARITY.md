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

## Current status (M1)

`gff2gtf`, post-normalization parity on the pinned corpus:

| file        | lines  | parity   | residual                            |
|-------------|--------|----------|-------------------------------------|
| human_chr1  | ~316k  | **100.00%** | none                             |
| human_chr21 | ~40k   | **100.00%** | none                             |
| yeast       | ~28.7k | **99.05%**  | DIV-1 (transposable_element remodel) |

Both human files are **byte-identical to AGAT after normalization**. The single
remaining yeast residual is one documented, deliberately-deferred AGAT quirk
(below). M1's ≥95% parity target is met with margin.

GAP-1..4 from the M0 spike are now **closed** — see the rules in `convert.rs`
(`assign_effective_ids`, `write_attr`):

- exon ID synthesis from `exon_id`, with AGAT's global-uniqueness rule (a shared
  exon_id keeps the name on first use, gets `agat-exon-<N>` thereafter);
- `agat-<lowercased_type>-<N>` per-type counter for features with no usable ID;
- multi-value (comma list) attributes serialized as `key "v1","v2"` — this also
  resolved the chromosome `Alias` difference (it was the same rendering issue).

---

## Output ordering & raw byte-parity

Beyond *normalized* parity, gxfkit emits features in AGAT's **tree-traversal
order** (per seqid → topfeature, then `biological_region`, then gene trees by
`(start,end)`; each gene followed by its transcripts, each transcript by its
children in `exon → CDS → 5'UTR → 3'UTR` order; ties broken by ID). Attributes
within a line are emitted in AGAT's order (`gene_id`, `transcript_id`, then the
rest ASCII-sorted by key). Result: **raw, un-normalized** diff vs AGAT:

| file        | raw-identical lines |
|-------------|---------------------|
| yeast       | ~98%                |
| human_chr21 | ~87%                |
| human_chr1  | ~84%                |

The raw residual is **DIV-2** below; normalized parity is unaffected (100%/99%).

## Open divergences

### DIV-1 — `transposable_element` / `transposable_element_gene` remodeling
**Where:** yeast Ty retrotransposon loci (`transposable_element_gene` →
`transposable_element` → `exon`); ~273 lines (0.95% of yeast).
**AGAT:** remodels the locus — reclassifies `transposable_element` as a
transcript (`RNA`) under a *synthesized* gene `agat-transposable_element-<N>`,
reparenting the children to it.
**gxfkit (now):** carries the original feature types and hierarchy through.
**Class:** DIV (deferred). **Why deferred:** this is AGAT's bespoke,
`feature_levels.yaml`-driven feature reclassification — high complexity, tiny
footprint, and arguably the original typing is more faithful to the input.
**Plan:** revisit if a real consumer needs it; otherwise document and move on.

### DIV-2 — AGAT internal locus-clustering order (raw diff only)
**Where:** the order in which AGAT emits some sibling transcripts within a gene
(and the exact slot of the `chromosome` line). AGAT uses an internal
overlapping-locus clustering / isoform heuristic that is not reproducible from a
clean `(start, end, id)` key.
**Impact:** **raw**-diff only — affects line *position*, never line *content*, so
**normalized parity is 100%/99% (unchanged)**. ~13-16% of human lines, ~2% yeast.
**Class:** DIV (accepted). gxfkit uses a deterministic `(start, end, id)` order.

### DIV-3 — NCBI-RefSeq-style hierarchy completion
**Where:** annotations where a gene has a CDS child with no intervening
mRNA/transcript (common in NCBI RefSeq), and other "incomplete" hierarchies.
**AGAT:** synthesizes the missing transcript level (inserts an `mRNA`, moves the
gene's ID onto it, renames the gene `agat-gene-<N>`), i.e. its full
standardization engine. gxfkit currently carries the input hierarchy through.
**Impact:** large on NCBI RefSeq corpus (ecoli ~4%, arabidopsis); Ensembl
unaffected (100%).
**Class:** DIV (roadmapped). This *is* AGAT's `gxf2gxf` standardization — the
single biggest remaining feature and the natural next subcommand.

---

## Notes on method

- The normalizer pins `gene_id`/`transcript_id` first (GTF spec) and sorts the
  remaining attributes, so attribute *order within a line* never causes a false
  divergence. Line order is also normalized. Anything else — a different value,
  a missing/extra attribute, a different coordinate — is a real difference and
  shows up in the diff.
- AGAT is a moving target; we pin a version. When we bump it, re-run the harness
  and reconcile this ledger.
