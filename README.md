# gxfkit

> A fast, drop-in Rust reimplementation of [AGAT](https://github.com/NBISweden/AGAT)'s
> most-used GTF/GFF operations. Identical output, much faster. One-line install.

`gxfkit` is a small, focused toolkit for the handful of GFF3/GTF operations that
sit on nearly every genome-annotation pipeline's critical path. It aims to be a
**drop-in subset** of AGAT: same inputs, byte-equivalent outputs (after a
documented, order-only normalization), a fraction of the wall-clock and memory.

It stands on the shoulders of AGAT — AGAT remains the reference for correctness,
and gxfkit treats its output as the gold standard.

> **Status: alpha (M1).** One subcommand (`gff2gtf`), byte-identical to AGAT
> after normalization on the human corpus (100%), 99% on yeast — with a
> reproducible benchmark + parity harness. See [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Benchmark

Numbers are produced by `benchmark/run.sh` — both tools run in the **same Linux
container** (AGAT 1.7.0 + gxfkit, timed with `/usr/bin/time`, best of N cold
runs — AGAT caches per-input, so each run clears that cache), against pinned public
Ensembl annotation files. Reproduce with one command; see
[benchmark/](benchmark/).

<!-- BENCHMARK_TABLE -->
| file | AGAT | gxfkit | speedup | AGAT mem | gxfkit mem | parity |
|------|------|--------|---------|----------|------------|--------|
| `human_chr1` | 78.47 s | 1.25 s | **62.8×** | 5.47 GB | 1.41 GB | 100.00% |
| `human_chr21` | 12.52 s | 140 ms | **89.4×** | 935 MB | 194 MB | 100.00% |
| `yeast` | 9.68 s | 120 ms | **80.7×** | 752 MB | 155 MB | 99.05% |
<!-- /BENCHMARK_TABLE -->

The harness is the point: anyone can re-run it and check the claim. Where gxfkit
and AGAT differ, the differences are enumerated with rationale in
[docs/PARITY.md](docs/PARITY.md).

---

## Install

Pre-alpha — build from source for now:

```bash
cargo build --release
./target/release/gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

Planned distribution (M2): `cargo install gxfkit`, `pip install gxfkit`,
`conda install -c bioconda gxfkit`.

### Windows build note

The default MSVC Rust toolchain needs the Windows SDK import libs on `LIB`. If a
plain `cargo build` fails with `LNK1181: cannot open input file 'kernel32.lib'`,
build through the bundled helper, which discovers and sets the MSVC + SDK paths:

```powershell
powershell -File scripts/with-msvc-env.ps1 cargo build --release
```

---

## Usage

```text
gxfkit gff2gtf [-g <input.gff>] [-o <output.gtf>]
  -g, --gff <FILE>      Input GFF3 file (default: stdin)
  -o, --output <FILE>   Output GTF file (default: stdout)
```

Flags mirror the AGAT script they replace (`agat_convert_sp_gff2gtf.pl`), so
swapping it into an existing pipeline is near-zero cost.

---

## How correctness is verified

1. **Gold standard = AGAT.** For every corpus file we run both tools.
2. **Order-only normalization.** `tests/parity/normalize.py` absorbs harmless
   differences (line order, attribute order within a line, whitespace) and
   *nothing else*, then diffs. Real differences still surface.
3. **Goal:** ≥95% of corpus files normalize-identical; every remaining
   divergence documented in [docs/PARITY.md](docs/PARITY.md) as "semantically
   equivalent" or "intentional AGAT-bug fix", with a reason.

---

## Repository layout

```
crates/gxfkit-core/   parsing, model, conversions (library)
crates/gxfkit/        CLI binary
corpus/               download.sh — pinned public GFF3 test data
benchmark/            Dockerfile + run.sh — one-command reproducible benchmark
tests/parity/         normalize.py — order-insensitive GTF comparison
docs/                 DESIGN, PARITY, ROADMAP
```

## License

MIT. AGAT is GPL-3.0 and developed independently by NBIS; gxfkit is a clean-room
reimplementation that uses AGAT only as a black-box reference oracle.
