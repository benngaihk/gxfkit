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
      (now 100% on the core corpus; extended Drosophila still documents DIV-4)
- [x] GitHub Actions: build + test + parity regression vs pinned AGAT on push
      (core parity gate at 100%, `MIN_PARITY` in `benchmark/summarize.py`)
- [x] AGAT-faithful output sort order → raw byte-parity ~84-98% (DIV-2 residual)
- [x] Expand corpus with other conventions (NCBI RefSeq, Drosophila, Arabidopsis)
      → core (gated) vs extended (stress) split
- [x] Robustness pass: tolerate non-UTF-8 input, accurate parse errors, gzip
      input (.gff.gz auto-detect, file/stdin)
- [ ] Reduce memory: stream / borrow instead of owning every field ([#3](https://github.com/benngaihk/gxfkit/issues/3); already ~4×
      better than AGAT; gff2gtf needs the full graph, so this means borrowing
      from a single buffer, not true streaming)
- [x] README benchmark table
- [ ] Demo/screencast + community feedback collection

## M2 — Distribution beta: make `gxfkit` easy to install  ✅ complete
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
- [x] Native GitHub Release install smoke via
      `scripts/verify-github-release-install.sh`
- [x] Clean Linux container install smoke for the GitHub Release static archive
      (`scripts/verify-github-release-linux-docker.sh`)
- [x] GitHub Release binary parity smoke against AGAT
      (`scripts/verify-github-release-parity.sh`)
- [x] Crates.io install smoke script and publish-workflow post-publish gate
      (`scripts/verify-crates-install.sh`; waits until registry visibility)
- [x] Bioconda install smoke script for post-merge/upload verification
      (`scripts/verify-bioconda-install.sh`)
- [x] Public install audit script for GitHub Release + Bioconda + Crates.io
      (`scripts/verify-public-installs.sh`)
- [x] Manual GitHub Actions public-install audit workflow for clean-runner
      release evidence
- [x] Publish-ref guard so Crates.io cannot publish an existing version from a
      different commit than its `vX.Y.Z` tag
- [x] Version-prep helper with separate Cargo bump and Bioconda-sha update
      phases, so no placeholder checksum is needed
- [x] Publish `gxfkit-core` and `gxfkit` to Crates.io ([#1](https://github.com/benngaihk/gxfkit/issues/1))
- [x] Add Bioconda recipe and verify install
      (`conda install -c conda-forge -c bioconda gxfkit`; PR
      [bioconda-recipes#66815](https://github.com/bioconda/bioconda-recipes/pull/66815))
- [x] Expand install docs and FAQ with common pipeline swap-in examples
- [x] Cut a post-`v0.0.1` public release whose GitHub/Bioconda/Crates.io
      packages pass the default strict public install audit
      (no-overwrite plus core-corpus release-binary parity at 100%)
- [x] **Gate:** a clean machine can install `gxfkit` from GitHub Releases,
      Crates.io, or Bioconda and run `gff2gtf` → see
      [RELEASE-STATUS.md](RELEASE-STATUS.md) and
      [releases/v0.0.2.md](releases/v0.0.2.md)

## M3 — Standardization engine + command matrix
The big remaining feature is AGAT's broader hierarchy **standardization** engine
(DIV-3 beyond the `gff2gtf` direct-CDS slice now covered): when a gene has
children with missing or irregular intermediate levels, AGAT synthesizes and
normalizes the hierarchy. This is what makes AGAT valuable ("it eats any messy
GFF") and unblocks `gxf2gxf` + most other tools.
- [ ] `gxf2gxf` standardization (GFF3→standardized GFF3) ([#4](https://github.com/benngaihk/gxfkit/issues/4);
      entry plan: [M3-STANDARDIZATION-PLAN.md](M3-STANDARDIZATION-PLAN.md),
      corpus ledger: [GXF2GXF-PARITY.md](GXF2GXF-PARITY.md)); beta fixture slice
      is CI-gated, but full corpus AGAT compatibility remains open
- [ ] Reproduce AGAT's large-corpus synthetic counter ordering (DIV-4) for
      rewritten exon/UTR/TE IDs — structural TE remodeling is implemented and
      closes yeast; Drosophila remains divergent on counter values
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
- [x] cargo-fuzz targets for parser and converter inputs ([#5](https://github.com/benngaihk/gxfkit/issues/5))
- [x] Sanitize mode: skip malformed records with diagnostics ([#6](https://github.com/benngaihk/gxfkit/issues/6))
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
