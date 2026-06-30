//! End-to-end CLI tests: run the built binary on plain and gzipped input.

use std::io::Write;
use std::process::{Command, Stdio};

const BIN: &str = env!("CARGO_BIN_EXE_gxfkit");

const GFF: &[u8] = b"\
##gff-version 3
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tParent=transcript:t1;exon_id=e1
";

/// Feed `input` to `gxfkit gff2gtf` on stdin, return stdout.
fn run_gff2gtf(input: &[u8]) -> String {
    let mut child = Command::new(BIN)
        .args(["gff2gtf"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn gxfkit");
    child.stdin.take().unwrap().write_all(input).unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}

#[test]
fn plain_stdin_produces_gtf() {
    let gtf = run_gff2gtf(GFF);
    assert!(gtf.contains("gene_id \"g1\";"));
    assert!(gtf.contains("transcript_id \"t1\";"));
    assert!(gtf.contains("ID \"e1\";")); // synthesized exon ID
}

#[test]
fn gzipped_input_is_autodetected() {
    let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    enc.write_all(GFF).unwrap();
    let gz = enc.finish().unwrap();

    let from_gz = run_gff2gtf(&gz);
    let from_plain = run_gff2gtf(GFF);
    assert_eq!(from_gz, from_plain, "gzipped and plain output must match");
}
