# M3 standardization plan

M3 starts the shift from one focused converter (`gff2gtf`) to AGAT-style
feature standardization. The first public shape is `gxf2gxf`: read GFF3, repair
or synthesize the hierarchy, and write standardized GFF3.

Tracking issue: <https://github.com/benngaihk/gxfkit/issues/4>

## Goal

Implement the shared standardization engine that can normalize messy real-world
GFF3 into the AGAT-style gene -> transcript -> exon/child hierarchy, then reuse
that engine from both `gxf2gxf` and the existing `gff2gtf` path where it is safe
to do so.

The engine should make AGAT-standardization decisions explicit and testable:

- classify roots, genes, transcripts, exons, CDS, UTRs, codons, biological
  regions, and special feature families such as transposable elements;
- synthesize missing transcript parents under genes;
- synthesize missing exon rows when AGAT does so for direct CDS-like children;
- rewrite IDs and Parent links with AGAT-compatible counters;
- preserve source attributes unless AGAT standardization intentionally rewrites
  them;
- emit deterministic output while documenting any remaining AGAT-internal order
  that cannot be reproduced safely.

## Non-goals for the first slice

- Do not add the whole AGAT command matrix at once.
- Do not refactor the parser or CLI argument system unless the new subcommand
  requires a narrow extension.
- Do not chase Drosophila synthetic counter order with corpus-specific sorting.
  Treat DIV-4 as part of the standardization investigation and keep the parity
  ledger honest.
- Do not weaken the existing `gff2gtf` core-corpus parity gate.

## First implementation slice

1. [x] Add a core standardization module behind `gxfkit-core`, separate from GTF
   emission.
2. [ ] Move the already-covered direct-child RefSeq and transposable-element
   hierarchy rules behind standardization-oriented helpers without changing
   `gff2gtf` output.
3. [x] Add `gxfkit gxf2gxf -i <in.gff3> -o <out.gff3>` with the same input/output
   safety behavior as `gff2gtf`, including gzip input and no-overwrite output.
4. [x] Build the first GFF3 writer around the existing ordered attributes model.
5. [ ] Add fixtures for:
   - [x] gene or pseudogene with direct CDS child;
   - [ ] gene with direct exon/UTR/codon children;
   - missing transcript parent with multiple CDS fragments;
   - FlyBase-style transposable-element locus;
   - orphan child and malformed Parent cases that AGAT tolerates.
6. [x] Compare fixture output against AGAT's `agat_convert_sp_gxf2gxf.pl` or the
   equivalent pinned AGAT standardization path, then record every divergence in
   `docs/PARITY.md`.

## Acceptance gate

M3's first gate is not "all AGAT tools"; it is a credible reusable engine:

- `gxf2gxf` exists and has CLI smoke tests.
- Existing `gff2gtf` tests and the core AGAT parity CI remain green.
- A pinned AGAT-vs-gxfkit `gxf2gxf` fixture harness exists in CI.
- The common RefSeq direct-child standardization fixtures match AGAT.
- Any Drosophila or large-corpus residuals are summarized with
  `tests/parity/residual_summary.py` or an equivalent GFF3 residual helper.
- `docs/PARITY.md` distinguishes fixed gaps from accepted or open divergences.

## Useful commands

Fetch the corpus once:

```bash
bash corpus/download.sh
```

Run the existing release-safe baseline before touching standardization:

```bash
cargo test
bash benchmark/run.sh
```

After `gxf2gxf` has a harness, the expected local loop should look like:

```bash
bash benchmark/run.sh
bash benchmark/run-gxf2gxf.sh
python3 tests/parity/normalize.py agat.gff3 > agat.norm
python3 tests/parity/normalize.py gxfkit.gff3 > gxfkit.norm
diff -u agat.norm gxfkit.norm
```

The exact script names can change during implementation, but the invariant
should not: AGAT 1.7.0 remains the oracle, and every mismatch gets measured
before it gets explained.

## Risks to watch

- AGAT's synthetic counter order can depend on internal standardization state,
  not simple source or output order.
- GFF3 output has stricter Parent/ID consistency requirements than GTF output,
  so rewrites need graph-level validation before emission.
- Borrowed-input memory work (#3) and standardization both touch graph storage;
  keep them separate unless one change clearly lowers the risk of the other.
- `gff2gtf` already embeds a subset of standardization behavior. Extract it in
  small steps and prove byte or normalized parity after each step.
