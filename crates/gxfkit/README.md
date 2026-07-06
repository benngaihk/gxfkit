# gxfkit

Fast command-line GFF/GTF utilities, implemented in Rust as an AGAT-compatible
subset. The current alpha focuses on `gff2gtf` parity for the verified core
corpus.

The first supported command is:

```bash
gxfkit gff2gtf -g annotation.gff3 -o annotation.gtf
```

`-o/--output` refuses to overwrite an existing file, matching AGAT's safer
default for pipeline reruns.

See the repository README for benchmark, parity, and roadmap details:
https://github.com/benngaihk/gxfkit
