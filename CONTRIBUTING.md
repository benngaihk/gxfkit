# Contributing

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

Thanks for helping make `gxfkit` faster and more trustworthy.

The project is intentionally conservative: AGAT is the correctness oracle, and
every meaningful output difference needs to be either fixed or documented in
`docs/PARITY.md`.

## Development Setup

```bash
cargo test --all
cargo clippy --all-targets -- -D warnings
cargo fmt --all -- --check
```

On Windows with the MSVC toolchain, use:

```powershell
powershell -File scripts/with-msvc-env.ps1 cargo test
```

## Parity Workflow

For changes that can affect conversion output:

```bash
bash corpus/download.sh core
bash benchmark/run.sh
```

If AGAT and `gxfkit` differ:

1. Confirm the difference survives `tests/parity/normalize.py`.
2. Add or update a focused unit test when the behavior is small enough.
3. Record any accepted divergence in `docs/PARITY.md`.

Do not silently change output behavior just because it looks cleaner than AGAT.

## Release Checks

Before cutting a release:

```bash
bash scripts/release-check.sh
```

The GitHub release workflow performs the cross-platform archive builds and smoke
tests.
