# gxfkit

English | [简体中文](README.zh-CN.md)

> A fast, AGAT-compatible Rust implementation of [AGAT](https://github.com/NBISweden/AGAT)'s
> most-used GTF/GFF operations. AGAT-compatible output on the verified core
> corpus, much faster, with portable release binaries.

`gxfkit` is a small, focused toolkit for the handful of GFF3/GTF operations that
sit on nearly every genome-annotation pipeline's critical path. It aims to be a
**compatible subset** of AGAT: the same CLI shape for supported commands,
AGAT-matched outputs on the verified core corpus (after a documented,
order-only normalization), and a fraction of the wall-clock and memory.

It stands on the shoulders of AGAT — AGAT remains the reference for correctness,
and gxfkit treats its output as the gold standard.

> **Status: alpha.** One subcommand (`gff2gtf`), byte-identical to AGAT after
> normalization on the core corpus (human chr1, human chr21, yeast) — with a
> reproducible benchmark + parity harness. Current focus: packaging and release
> distribution.
> See [docs/ROADMAP.md](docs/ROADMAP.md).

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
| `human_chr1` | 47.19 s | 1.19 s | **39.7×** | 5.50 GB | 2.13 GB | 100.00% |
| `human_chr21` | 6.94 s | 150 ms | **46.3×** | 967 MB | 300 MB | 100.00% |
| `yeast` | 5.70 s | 100 ms | **57.0×** | 778 MB | 229 MB | 100.00% |
<!-- /BENCHMARK_TABLE -->

The harness is the point: anyone can re-run it and check the claim. Where gxfkit
and AGAT differ, the differences are enumerated with rationale in
[docs/PARITY.md](docs/PARITY.md).

---

## Install

### Prebuilt binaries

Tagged GitHub releases publish `.tar.gz` archives for:

- Linux x86_64 (static musl)
- Linux aarch64 (static musl)
- macOS x86_64
- macOS aarch64

Download the archive for your platform from the
[GitHub Releases](https://github.com/benngaihk/gxfkit/releases) page, then put
the `gxfkit` binary on your `PATH`.

```bash
tar -xzf gxfkit-vX.Y.Z-linux-x86_64-static.tar.gz
./gxfkit-vX.Y.Z-linux-x86_64-static/gxfkit version
```

Release maintainers can verify the current platform's published archive with:

```bash
bash scripts/verify-github-release-install.sh
```

Published `v0.0.1` archives predate the no-overwrite output guard. The current
source tree refuses to overwrite `-o/--output`; the public install audit verifies
future releases with no-overwrite and core-corpus parity enabled by default.

### Cargo

Once published to Crates.io:

```bash
cargo install gxfkit
```

Crates.io is not a current public channel while
[docs/RELEASE-STATUS.md](docs/RELEASE-STATUS.md) records `gxfkit` as
unpublished there; do not treat `cargo install gxfkit` as a production install
path until this section stops being conditional.

### Bioconda

```bash
conda install -c conda-forge -c bioconda gxfkit
```

The current public Bioconda package is `0.0.1`. It is useful for basic installs,
but it predates the no-overwrite guard; use the release status before treating a
Bioconda package as strict-audit production evidence.

### From source

```bash
cargo build --release
./target/release/gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

Planned distribution after the first source release: Python bindings
(`pip install gxfkit`).

Release maintainers: see [docs/RELEASE.md](docs/RELEASE.md).

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
gxfkit gff2gtf [-g <input.gff[.gz]>] [-o <output.gtf>] [--sanitize]
  -g, --gff <FILE>      Input GFF3 file, plain or gzipped (default: stdin)
  -o, --output <FILE>   Output GTF file; refuses to overwrite (default: stdout)
  --sanitize            Skip malformed data records with stderr diagnostics
```

Gzip input is auto-detected, so `gxfkit gff2gtf -g ann.gff3.gz` and
`zcat ann.gff3.gz | gxfkit gff2gtf` both work.

Like AGAT, `gxfkit` refuses to overwrite an existing `-o/--output` file; remove
or rename old outputs before rerunning a conversion. This describes the current
source tree and future releases after `v0.0.1`; public `v0.0.1` packages still
overwrite existing output files.

By default, malformed data records stop the conversion. Use `--sanitize` only
when you want to skip records with bad column counts or coordinates and audit
the skipped lines from stderr diagnostics.

Flags mirror the AGAT script they replace (`agat_convert_sp_gff2gtf.pl`), so
swapping it into an existing pipeline is near-zero cost.

AGAT:

```bash
agat_convert_sp_gff2gtf.pl -g annotation.gff3 -o annotation.gtf
```

gxfkit:

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

See [docs/FAQ.md](docs/FAQ.md) for gzip, parity, and pipeline notes.

---

## How correctness is verified

1. **Gold standard = AGAT.** For every corpus file we run both tools.
2. **Order-only normalization.** `tests/parity/normalize.py` absorbs harmless
   differences (line order, attribute order within a line, whitespace) and
   *nothing else*, then diffs. The parity score is symmetric: missing AGAT rows
   and extra gxfkit rows both count as real differences.
3. **Goal:** ≥95% of gated corpus files normalize-identical; every remaining
   divergence is documented and classified in [docs/PARITY.md](docs/PARITY.md)
   before it is treated as acceptable.

---

## Repository layout

```
crates/gxfkit-core/   parsing, model, conversions (library)
crates/gxfkit/        CLI binary
corpus/               download.sh — pinned public GFF3 test data
benchmark/            Dockerfile + run.sh + write-residuals.sh — reproducible benchmark
tests/parity/         normalize.py + residual_summary.py — parity diagnostics
docs/                 DESIGN, PARITY, ROADMAP
```

## License

MIT. AGAT is GPL-3.0 and developed independently by NBIS; gxfkit is a clean-room
reimplementation that uses AGAT only as a black-box reference oracle.
