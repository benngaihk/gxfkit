# Design

## Goals
1. **Drop-in:** same CLI flags and outputs as the AGAT script being replaced.
2. **Fast & lean:** an order of magnitude less wall-clock, less memory.
3. **Provably correct:** AGAT is the oracle; every divergence is documented.

## Crate layout
- `gxfkit-core` — library: model, parsing, conversions. No CLI concerns, so it
  can back both the binary and (M2) the PyO3 module.
- `gxfkit` — thin CLI binary. Hand-rolled arg parsing for now (zero deps, fast
  compile); will move to a parser lib if subcommand count justifies it.

## Why a hand-written parser (not `noodles`)?
GFF/GTF is column-oriented TSV with a structured 9th column. A custom reader is
small and fast, and — decisive for AGAT byte-parity — gives total control over
re-serialization (quoting, attribute order, trailing separators, how `.` is
emitted). `noodles`/`rust-bio` remain options behind the same `Record` API if a
format edge case makes them worthwhile.

## Data model (`model.rs`)
A `Record` mirrors the 9 GFF columns. `score` and `phase` are kept as **raw
strings** rather than parsed numbers, so the original token is never reformatted
or lost. `strand` is an enum (`+ - . ?`). Attributes are an **ordered** list of
`(key, value)` pairs (GFF3 allows duplicates and multi-value comma lists).

## gff2gtf algorithm (`convert.rs`)
1. Index records by `ID` and build an in-memory parent/child graph. Malformed
   parent links become roots; self-cycles are guarded so every source line emits
   at most once.
2. Assign effective IDs using AGAT's rules: source `ID`, promotable `exon_id`,
   or `agat-<lowercased_type>-N` counters with global uniqueness.
3. Apply the `gff2gtf` slice of AGAT's standardization:
   - common RefSeq `gene/pseudogene -> CDS/exon/UTR/start_codon/stop_codon`
     shapes get a synthetic `mRNA` level;
   - direct CDS children get synthetic AGAT exon rows;
   - RefSeq synthetic gene/exon counters follow natural `locus_tag` order;
   - alternate direct-CDS isoforms are suppressed like AGAT, and adjacent
     same-CDS fragments are merged before GTF emission;
   - CDS-bearing duplicate transcript subtrees under the same gene, with
     identical exon/UTR/CDS structure, are collapsed by keeping the lowest
     transcript ID;
   - FlyBase-style `transposable_element_gene -> transposable_element -> child`
     loci are remodeled into AGAT's synthetic
     `transposable_element -> RNA -> child` shape.
4. Compute AGAT's tree-traversal output order: per seqid, top-level regions,
   then `biological_region`, then gene trees; inside transcripts, children are
   ordered exon -> CDS -> codons -> UTRs. While traversing, propagate the
   canonical `gene_id` and `transcript_id` once per node.
5. Emit GTF: `gene_id` then `transcript_id` lead, then attributes in AGAT's
   order. Source `gene_id`/`transcript_id` are replaced; original `ID`/`Parent`
   are retained unless AGAT standardization rewrites them.

Known gaps vs AGAT are tracked in [PARITY.md](PARITY.md). The important current
gap is not ordinary RefSeq gene->CDS completion (E. coli now matches AGAT after
normalization), nor the basic transposable-element structure (yeast now matches
AGAT after normalization), but AGAT's broader `gxf2gxf` feature-level
standardization and its large-corpus synthetic counter ordering for rewritten
exon, UTR, and transposable-element IDs.

## gxf2gxf standardization (`standardize.rs`)
M3 starts with a deliberately small, testable standardization module. It writes
GFF3, shrinks parent coordinates to child spans like AGAT, and covers the first
AGAT-observed hierarchy completion slice: a gene/pseudogene with direct
CDS/exon/UTR/codon children gets a renamed `agat-<type>-N` parent, a synthetic
`AGAT mRNA` or `AGAT RNA` carrying the original gene ID, AGAT-compatible
synthetic exon rows where observed, contiguous same-ID direct CDS fragment
merging, FlyBase-style transposable-element locus remodeling, and rewritten
child `Parent` links. This is not the full AGAT parser yet; broader
standardization remains tracked in
[M3-STANDARDIZATION-PLAN.md](M3-STANDARDIZATION-PLAN.md).

## Performance posture
- Release profile: `lto=thin`, `codegen-units=1`, `panic=abort`.
- Current memory model owns every field and builds the full graph. That is
  deliberate for `gff2gtf`, because AGAT-compatible ordering and RefSeq
  standardization need global parent/child context. The remaining M1 memory
  optimization is to borrow from a single buffered input instead of allocating
  every string independently (see ROADMAP M1).

## Testing
- Unit tests in each module (parsing, attribute handling, conversion rules).
- **Parity tests** are the real correctness bar: diff against AGAT output on a
  real corpus via `tests/parity/normalize.py`. These will run in CI (M1).
