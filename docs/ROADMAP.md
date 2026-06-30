# Roadmap

Derived from the feasibility plan. Each milestone has a **Gate** — we do not
advance until it is met. Honesty and reproducibility are the differentiators, so
every speed/parity claim must be re-runnable by a third party.

## M0 — Feasibility spike  ✅ in progress
Prove one subcommand can be ≥10× faster than AGAT with a clear path to output
parity. If not, stop.

- [x] Repo + Rust workspace + CI-ready layout
- [x] `gff2gtf` happy-path implementation (`crates/gxfkit-core` + CLI)
- [x] Pinned public corpus (`corpus/download.sh`: yeast, human chr21, chr1)
- [x] Parity normalizer (`tests/parity/normalize.py`) + AGAT gold via Docker
- [x] One-command reproducible benchmark (`benchmark/run.sh`: AGAT + gxfkit +
      one container, timed with /usr/bin/time)
- [x] Parity gaps characterized + documented ([PARITY.md](PARITY.md))
- [ ] **Gate:** ≥10× wall-clock on ≥1 corpus file **and** clear parity path
      → see [M0-REPORT.md](M0-REPORT.md)

## M1 — First publishable subcommand + parity CI
- [x] Close GAP-1..4 (see [PARITY.md](PARITY.md)) → ≥95% normalize-identical
      (now 100% human / 99% yeast; one documented divergence DIV-1 remains)
- [x] GitHub Actions: build + test + parity regression vs pinned AGAT on push
      (parity gate at 98%, `MIN_PARITY` in `benchmark/summarize.py`)
- [x] AGAT-faithful output sort order → raw byte-parity ~84-98% (DIV-2 residual)
- [x] Expand corpus with other conventions (NCBI RefSeq, Drosophila, Arabidopsis)
      → core (gated) vs extended (stress) split
- [x] Robustness pass: tolerate non-UTF-8 input, accurate parse errors, gzip
      input (.gff.gz auto-detect, file/stdin)
- [ ] Reduce memory: stream / borrow instead of owning every field (already ~4×
      better than AGAT; gff2gtf needs the full graph, so this means borrowing
      from a single buffer, not true streaming)
- [ ] README benchmark table + asciinema demo; soft release (rust-bio circle)

## M2 — Standardization engine + PyO3 + Top-5 subcommands
The big remaining feature is AGAT's hierarchy **standardization** (DIV-3): when a
gene has children with a missing intermediate level (e.g. NCBI RefSeq gene→CDS
with no mRNA), AGAT synthesizes the transcript level. This is what makes AGAT
valuable ("it eats any messy GFF") and unblocks `gxf2gxf` + most other tools.
- [ ] `gxf2gxf` standardization (GFF3→standardized GFF3); the engine that
      synthesizes missing parents / completes the gene→transcript→exon hierarchy
- [ ] `transposable_element` remodeling (DIV-1) — closes yeast/drosophila
- [ ] PyO3 wrapper; publish to PyPI + Bioconda; `cargo install`
- [ ] Add: gtf2gff, sequence extraction, stats/filter
- [ ] **Gate:** `pip install gxfkit` / `conda install gxfkit` works; 5
      subcommands each with parity + benchmark

## M3 — Robustness moat
- [x] Property tests on the parser + converter (proptest): never panic on
      arbitrary bytes/tab structures; well-formed input always yields valid GTF
      (`crates/gxfkit-core/tests/property.rs`)
- [x] Fixed an O(n²) hang on deep Parent chains (found by adversarial review)
- [ ] cargo-fuzz target for continuous fuzzing
- [ ] Match AGAT's tolerance of the ugliest real-world GFF/GTF flavors
- [ ] Exhaustive divergence ledger

## M4 — Publish & distribute
- [ ] bioRxiv preprint → JOSS / Bioinformatics Application Note
- [ ] nf-core / Galaxy tool listings; BOSC / Rust-meetup talk

---

### Pinned versions
- AGAT parity baseline: **1.7.0** (`quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0`)
- Corpus: **Ensembl release 110**
