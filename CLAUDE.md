# CLAUDE.md

Project context for AI assistants working in this repo.

## What this is
`gxfkit` — a fast Rust reimplementation of a subset of [AGAT](https://github.com/NBISweden/AGAT)'s
GFF/GTF tools. Drop-in CLI, AGAT output as the correctness oracle. See
[README.md](README.md), [docs/DESIGN.md](docs/DESIGN.md), [docs/ROADMAP.md](docs/ROADMAP.md).

## Layout
- `crates/gxfkit-core/` — library (model, parser, conversions)
- `crates/gxfkit/` — CLI binary
- `corpus/download.sh` — pinned public GFF3 test data (git-ignored once fetched)
- `benchmark/` — `Dockerfile` + `run.sh` + `bench.sh`: one-command AGAT-vs-gxfkit
- `tests/parity/normalize.py` — order-insensitive GTF comparison

## Build (Windows note)
The MSVC toolchain needs the Windows SDK libs on `LIB`, and on this machine
`vswhere.exe` is missing so `vcvars64.bat` doesn't set them. Build via:

```powershell
powershell -File scripts/with-msvc-env.ps1 cargo build --release
powershell -File scripts/with-msvc-env.ps1 cargo test
```

On Linux/CI a plain `cargo build` works.

## Benchmark / parity
```bash
bash corpus/download.sh          # fetch corpus (once)
bash benchmark/run.sh            # build image, run AGAT+gxfkit, time + diff
```
Requires Docker. In git-bash set `MSYS_NO_PATHCONV=1` and use `$(pwd -W)` for
`-v` mounts to avoid path mangling. Both tools take `-i <in> -o <out>`.

## Correctness bar
AGAT (pinned **1.7.0**) is the gold standard. Changes to `convert.rs` must be
checked against AGAT output via the parity harness; record any new divergence in
[docs/PARITY.md](docs/PARITY.md). Do not silently diverge.

## Status
M0 spike complete (gate met: ~73× faster on human chr1). M1 = close the
documented parity gaps + add parity CI. See [docs/M0-REPORT.md](docs/M0-REPORT.md).
