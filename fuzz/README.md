# Fuzzing

Fuzz targets exercise the byte-oriented GFF reader and the `gff2gtf`
conversion path. Install `cargo-fuzz`, then run a target from the repository
root:

```bash
cargo install cargo-fuzz
cargo fuzz run reader
cargo fuzz run gff3_to_gtf
```

If a crash is found, minimize the corpus input and turn it into a regression
test under `crates/gxfkit-core/tests/` before fixing it.
