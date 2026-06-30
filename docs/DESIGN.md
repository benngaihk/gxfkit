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
1. Index records by `ID`.
2. For each record, climb the `Parent` chain to the root (cycle-guarded).
3. The root is the gene; the node beneath it is the transcript.
4. Derive `gene_id` (strip a leading `gene:`) and `transcript_id` (strip
   `transcript:`) — the Ensembl convention AGAT follows.
5. Emit GTF: `gene_id` then `transcript_id` lead, then the original attributes
   verbatim (minus any source `gene_id`/`transcript_id`, which we replace).

The spike preserves input order; the parity normalizer is order-insensitive, and
AGAT-faithful sorting is an M1 task. Known gaps vs AGAT are in [PARITY.md](PARITY.md).

## Performance posture
- Release profile: `lto=thin`, `codegen-units=1`, `panic=abort`.
- Current memory model owns every field (simple, correct). The M1 optimization
  is to borrow from a single buffered input and/or stream, which should cut the
  resident footprint substantially (see ROADMAP M1).

## Testing
- Unit tests in each module (parsing, attribute handling, conversion rules).
- **Parity tests** are the real correctness bar: diff against AGAT output on a
  real corpus via `tests/parity/normalize.py`. These will run in CI (M1).
