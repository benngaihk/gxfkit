# Roadmap

Derived from the feasibility plan. Each milestone has a **Gate** — we do not
advance until it is met. Honesty and reproducibility are the differentiators, so
every speed/parity claim must be re-runnable by a third party.

## M0 — Feasibility spike  ✅ complete
Prove one subcommand can be ≥10× faster than AGAT with a clear path to output
parity. If not, stop.

- [x] Repo + Rust workspace + CI-ready layout
- [x] `gff2gtf` happy-path implementation (`crates/gxfkit-core` + CLI)
- [x] Pinned public corpus (`corpus/download.sh`: yeast, human chr21, chr1)
- [x] Parity normalizer (`tests/parity/normalize.py`) + AGAT gold via Docker
- [x] One-command reproducible benchmark (`benchmark/run.sh`: AGAT + gxfkit +
      one container, timed with /usr/bin/time)
- [x] Parity gaps characterized + documented ([PARITY.md](PARITY.md))
- [x] **Gate:** ≥10× wall-clock on ≥1 corpus file **and** clear parity path
      → see [M0-REPORT.md](M0-REPORT.md)

## M1 — First publishable subcommand + parity CI  ✅ mostly complete
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
- [x] README benchmark table
- [ ] Demo/screencast + soft announcement (rust-bio / bioinformatics circles)

## M2 — Distribution beta: make `gxfkit` easy to install
The next practical bottleneck is not conversion correctness, but adoption:
users should be able to install a binary without a Rust toolchain and reproduce
the benchmark/parity claims from the release artifact.

- [x] Release workflow skeleton: tag-triggered GitHub Releases with Linux and
      macOS archives
- [x] Release checklist and local preflight script
- [x] Bioconda starter recipe template
- [x] Cut the first draft GitHub release and verify every archive runs
- [x] Crates.io dry-run for `gxfkit-core`
- [x] Public GitHub `v0.0.1` release with verified assets
- [ ] Publish `gxfkit-core` and `gxfkit` to Crates.io
- [ ] Add Bioconda recipe (`conda install -c bioconda gxfkit`)
- [x] Expand install docs and FAQ with common pipeline swap-in examples
- [ ] **Gate:** a clean machine can install `gxfkit` from GitHub Releases,
      `cargo install gxfkit`, or Bioconda and run `gff2gtf`

## M3 — Standardization engine + command matrix
The big remaining feature is AGAT's hierarchy **standardization** (DIV-3): when a
gene has children with a missing intermediate level (e.g. NCBI RefSeq gene→CDS
with no mRNA), AGAT synthesizes the transcript level. This is what makes AGAT
valuable ("it eats any messy GFF") and unblocks `gxf2gxf` + most other tools.
- [ ] `gxf2gxf` standardization (GFF3→standardized GFF3); the engine that
      synthesizes missing parents / completes the gene→transcript→exon hierarchy
- [ ] `transposable_element` remodeling (DIV-1) — closes yeast/drosophila
- [ ] Add: `gtf2gff`
- [ ] Add: fast `validate`
- [ ] Add: `extract` / `filter` by seqid, feature type, and attribute value
- [ ] PyO3 wrapper; publish Python bindings via maturin
- [ ] **Gate:** 5 subcommands each have parity/behavior tests and benchmark data

## M4 — Robustness moat
- [x] Property tests on the parser + converter (proptest): never panic on
      arbitrary bytes/tab structures; well-formed input always yields valid GTF
      (`crates/gxfkit-core/tests/property.rs`)
- [x] Fixed an O(n²) hang on deep Parent chains (found by adversarial review)
- [ ] cargo-fuzz target for continuous fuzzing
- [ ] Sanitize mode: skip or repair common malformed records with diagnostics
- [ ] Match AGAT's tolerance of the ugliest real-world GFF/GTF flavors
- [ ] Exhaustive divergence ledger

## M5 — Production and ecosystem
- [ ] Nextflow module and Snakemake wrapper
- [ ] v1.0.0 stable release with compatibility policy
- [x] Issue templates and CONTRIBUTING.md
- [ ] bioRxiv preprint → JOSS / Bioinformatics Application Note
- [ ] nf-core / Galaxy tool listings; BOSC / Rust-meetup talk

---

### Pinned versions
- AGAT parity baseline: **1.7.0** (`quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0`)
- Corpus: **Ensembl release 110**
