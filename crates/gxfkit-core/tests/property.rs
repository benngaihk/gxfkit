//! Property-based tests: the parser and converter must never panic on arbitrary
//! input, and well-formed input must always yield structurally-valid GTF.

use gxfkit_core::convert::gff3_to_gtf;
use gxfkit_core::reader::read_all;
use proptest::prelude::*;
use std::io::Cursor;

/// A token safe to drop in any GFF column (no tab / newline).
fn token() -> impl Strategy<Value = String> {
    "[A-Za-z0-9_:.-]{1,8}"
}

/// An attribute column: maybe an ID, maybe a Parent, maybe an exon_id.
fn attrs() -> impl Strategy<Value = String> {
    (
        prop::option::of(token()),
        prop::option::of(token()),
        prop::option::of(token()),
    )
        .prop_map(|(id, parent, exon)| {
            let mut parts = Vec::new();
            if let Some(i) = id {
                parts.push(format!("ID={i}"));
            }
            if let Some(p) = parent {
                parts.push(format!("Parent={p}"));
            }
            if let Some(e) = exon {
                parts.push(format!("exon_id={e}"));
            }
            if parts.is_empty() {
                ".".to_string()
            } else {
                parts.join(";")
            }
        })
}

/// A single well-formed 9-column GFF3 data line.
fn gff_line() -> impl Strategy<Value = String> {
    let ftype = prop_oneof![
        Just("gene"),
        Just("mRNA"),
        Just("exon"),
        Just("CDS"),
        Just("five_prime_UTR"),
        Just("biological_region"),
        Just("chromosome"),
    ];
    (
        token(),
        token(),
        ftype,
        1u64..10_000,
        1u64..10_000,
        "[-+.?]",
        attrs(),
    )
        .prop_map(|(seqid, source, ft, start, end, strand, a)| {
            format!("{seqid}\t{source}\t{ft}\t{start}\t{end}\t.\t{strand}\t.\t{a}")
        })
}

proptest! {
    /// Arbitrary bytes must never panic the reader or converter (worst case an
    /// Err from the reader, which we ignore).
    #[test]
    fn arbitrary_bytes_never_panic(data in prop::collection::vec(any::<u8>(), 0..3000)) {
        if let Ok(recs) = read_all(Cursor::new(&data)) {
            let mut out = Vec::new();
            let _ = gff3_to_gtf(&recs, &mut out);
        }
    }

    /// Arbitrary tab-joined fragments (varying column counts) never panic.
    #[test]
    fn arbitrary_tabbed_lines_never_panic(
        lines in prop::collection::vec(
            prop::collection::vec("[^\t\n]{0,12}", 0..12).prop_map(|f| f.join("\t")),
            0..50,
        )
    ) {
        let input = lines.join("\n");
        if let Ok(recs) = read_all(Cursor::new(input.as_bytes())) {
            let mut out = Vec::new();
            let _ = gff3_to_gtf(&recs, &mut out);
        }
    }

    /// Well-formed input always yields valid GTF: one output line per record,
    /// each with 9 columns and a gene_id.
    #[test]
    fn wellformed_input_yields_valid_gtf(lines in prop::collection::vec(gff_line(), 0..40)) {
        let input = lines.join("\n");
        let recs = read_all(Cursor::new(input.as_bytes())).expect("well-formed parses");
        let mut out = Vec::new();
        gff3_to_gtf(&recs, &mut out).expect("conversion");
        let s = String::from_utf8(out).expect("utf8 out");

        let out_lines: Vec<&str> = s.lines().collect();
        prop_assert_eq!(out_lines.len(), recs.len());
        for l in out_lines {
            prop_assert_eq!(l.matches('\t').count(), 8, "9 columns expected: {}", l);
            prop_assert!(l.contains("gene_id \""), "missing gene_id: {}", l);
        }
    }
}
