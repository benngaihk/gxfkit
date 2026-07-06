# Parity with AGAT

**Baseline:** AGAT `1.7.0` (biocontainer `quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0`).
**Subcommand:** `gff2gtf` (`agat_convert_sp_gff2gtf.pl`, default `--gtf_version relax`).

Parity is measured by running both tools on every corpus file, passing each
output through `tests/parity/normalize.py` (order- and whitespace-insensitive,
but value-preserving), and diffing. The reported percentage is a symmetric
multiset score: both AGAT-only lines and gxfkit-only extra lines reduce parity.
The goal for a subcommand to be considered "done" is **≥95% of corpus files
normalize-identical**, with every residual difference listed here and
classified.

This file is the project's honesty ledger. Each divergence is either:

- **EQUIV** — semantically equivalent, normalized away; or
- **GAP** — gxfkit not yet matching AGAT (tracked, will close); or
- **FIX** — an intentional deviation because AGAT's behavior is a bug.

---

## Current status (M1)

`gff2gtf`, post-normalization parity. The corpus has two tiers: a **core** set
(Ensembl, where gxfkit guarantees parity — enforced by CI at 100%) and an
**extended** stress set (different conventions, exercising known divergences).

| tier     | file              | lines  | parity      | dominant residual              |
|----------|-------------------|--------|-------------|--------------------------------|
| core     | human_chr1        | ~316k  | **100.00%** | none                           |
| core     | human_chr21       | ~40k   | **100.00%** | none                           |
| core     | yeast             | ~28.7k | **100.00%** | none                           |
| extended | drosophila        | ~506k  | **44.91%**  | DIV-4 (synthetic counters)     |
| extended | ecoli_refseq      | 18,016 | **100.00%** | none in normalized output      |
| extended | arabidopsis_refseq| ~710k  | (NCBI)      | needs refreshed measurement    |

Core Ensembl files are **byte-identical to AGAT after normalization**. The
extended set deliberately surfaces remaining out-of-corpus risks: AGAT's
large-corpus synthetic counter ordering (`agat-exon`, UTR, and
`transposable_element`) and broader NCBI standardization beyond the RefSeq
direct-CDS cases now covered. M1's ≥95% target is met on core.

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

The raw residual is **DIV-2** below; normalized parity is unaffected (100% on
the core set).

## Open divergences

### DIV-1 — `transposable_element` / `transposable_element_gene` remodeling
**Where:** FlyBase-style loci (`transposable_element_gene` →
`transposable_element` → `exon`/UTR/CDS). This is small in yeast and large in
Drosophila.
**AGAT:** remodels the locus — reclassifies `transposable_element` as a
transcript (`RNA`) under a *synthesized* gene `agat-transposable_element-<N>`,
reparenting the children to it.
**gxfkit (now):** implements the AGAT structural remodel: the outer
`transposable_element_gene` is suppressed, the `transposable_element` receives a
synthetic `agat-transposable_element-<N>` ID, a synthetic AGAT `RNA` row is
inserted using the first child as template, and child `gene_id`/`transcript_id`
values are propagated through that RNA. This closes yeast normalized parity.
**Class:** PARTIAL. **Remaining DIV-1b:** AGAT's large-corpus counter ordering
for synthetic transposable-element IDs is not a clean coordinate or input-order
sort; Drosophila still has 5,898 TE loci with only the
`agat-transposable_element-<N>` value different, which cascades into child
exon/UTR rows. gxfkit keeps a deterministic source-ID order rather than
hard-coding corpus-specific chromosome/hash order.

### DIV-4 — AGAT synthetic counter ordering at large scale
**Where:** Drosophila idless / duplicate-ID exon and UTR rows that AGAT rewrites
as `agat-exon-<N>`, `agat-five_prime_utr-<N>`, or
`agat-three_prime_utr-<N>`.
**AGAT:** assigns these counters during its feature-level standardization. On
large FlyBase files, the counter order is not plain input order, output order,
or a simple feature-key sort; it appears coupled to AGAT's internal locus
hashes/chunks.
**gxfkit (now):** assigns deterministic counters in input order, which matches
the core corpus and many ordinary cases but leaves Drosophila counter values
different at scale.
**Measured residual:** `tests/parity/residual_summary.py` reports, for
Drosophila, exactly symmetric residuals after duplicate transcript structures
are collapsed. Under the symmetric multiset parity score this is **44.91%**:
only-in-AGAT and only-in-gxfkit both contain 99,289
`ID:agat-exon`, 43,920 `ID:agat-five_prime_utr`, 31,584
`ID:agat-three_prime_utr`, and 5,898 `ID:agat-transposable_element` families
(plus their propagated `gene_id:agat-transposable_element` RNA/exon rows). No
plain source-ID `mRNA`/`CDS`/`exon` rows remain in the normalized residual; the
`counter drift` diagnostic pairs all 192,487 residual rows one-to-one with
`ambiguous_a=0`, `ambiguous_b=0`, `unpaired_a=0`, and `unpaired_b=0`. The
remaining difference is counter value assignment. The diagnostic also prints
short counter-order runs: for Drosophila exons, AGAT's residual counter order
begins `4:1-2048`, then `Unmapped_Scaffold_8_D1580_D1567:2049-2052`,
then `X:2053-5746`, while gxfkit begins with one long `2L:1-17171` run.
The same diagnostic now prints the first-seen seqid order by synthetic counter:
exon counters appear as
`4,Unmapped_Scaffold_8_D1580_D1567,X,Y,2L,2R,3L,3R` in AGAT but
`2L,2R,3L,3R,4,Unmapped_Scaffold_8_D1580_D1567,X,Y` in gxfkit. UTRs show the
same AGAT prefix while transposable-element counters use another interleaving.
The raw-order section also rules out final output order: for AGAT Drosophila
exons, `seqids_by_line` starts `2L,2R,3L,3R,4,...` while `seqids_by_counter`
starts `4,Unmapped_Scaffold_8_D1580_D1567,X,Y,...`.
That supports treating DIV-4 as AGAT-internal standardization order, not a
simple source order, seqid order, output traversal mismatch, or one safe
chromosome-order tweak.
**Class:** PARTIAL. Reproducing this exactly likely belongs with the broader
AGAT standardization engine rather than one-off sorting tweaks.

### DIV-2 — AGAT internal locus-clustering order (raw diff only)
**Where:** the order in which AGAT emits some sibling transcripts within a gene
(and the exact slot of the `chromosome` line). AGAT uses an internal
overlapping-locus clustering / isoform heuristic that is not reproducible from a
clean `(start, end, id)` key.
**Impact:** **raw**-diff only — affects line *position*, never line *content*, so
**normalized parity is 100% on the core set (unchanged)**. ~13-16% of human
lines; yeast is normalized-identical after DIV-1's structural remodel.
**Class:** DIV (accepted). gxfkit uses a deterministic `(start, end, id)` order.

### DIV-3 — Broader NCBI-RefSeq-style hierarchy completion
**Where:** annotations where a gene has a CDS child with no intervening
mRNA/transcript (common in NCBI RefSeq), and other incomplete hierarchies.
**AGAT:** synthesizes the missing transcript level (inserts an `mRNA`, moves the
gene's ID onto it, renames the gene `agat-gene-<N>` / `agat-pseudogene-<N>`),
i.e. its full standardization engine.
**gxfkit (now):** covers the common RefSeq direct-child slice used by the E. coli
sample: `gene/pseudogene -> CDS/exon/UTR/start_codon/stop_codon`, synthetic
`mRNA`, synthetic exon for direct CDS, AGAT-style natural `locus_tag` numbering,
direct-CDS isoform suppression, adjacent same-CDS fragment merging, and RefSeq
orphan root skips observed in AGAT output.
**Impact:** the pinned E. coli RefSeq stress sample now normalizes identical to
AGAT (18,016 lines). Broader NCBI corpora such as Arabidopsis still need a fresh
AGAT measurement before claiming full standardization parity.
**Class:** PARTIAL (roadmapped). The remaining risk is not the E. coli direct-CDS
shape; it is AGAT's broader `gxf2gxf` feature-level standardization.

---

## Notes on method

- The normalizer pins `gene_id`/`transcript_id` first (GTF spec) and sorts the
  remaining attributes, so attribute *order within a line* never causes a false
  divergence. Line order is also normalized. Anything else — a different value,
  a missing/extra attribute, a different coordinate — is a real difference and
  shows up in the diff.
- `tests/parity/residual_summary.py AGAT.gtf gxfkit.gtf` groups the normalized
  residuals by feature type and synthetic ID family. Its `counter drift` section
  also canonicalizes `agat-*-N` values, reports whether the remaining rows pair
  one-to-one as pure counter-value drift, and prints compact AGAT-vs-gxfkit
  counter-order runs plus first-seen seqid order for each synthetic family. Its
  raw-order section compares counter order with file line order, which helps
  rule out misleading "just reuse output traversal" fixes; use it before
  updating this ledger.
- `benchmark/write-residuals.sh benchmark/results` writes the same diagnostics
  for every file listed in `summary.tsv` plus any available `*.agat.gtf` output;
  CI uploads these files with the parity artifact so regressions have
  inspectable evidence.
- AGAT is a moving target; we pin a version. When we bump it, re-run the harness
  and reconcile this ledger.
