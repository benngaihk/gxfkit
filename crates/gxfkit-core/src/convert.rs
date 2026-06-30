//! GFF3 -> GTF conversion.
//!
//! Scope (M0 spike): the happy path that covers the overwhelming majority of
//! real annotation files — a `gene -> transcript -> exon/CDS/UTR` hierarchy
//! linked by `ID`/`Parent`. We resolve each feature's `gene_id` and
//! `transcript_id` by climbing the `Parent` chain to the root.
//!
//! Known not-yet-handled cases (tracked for M1 parity work, see docs/PARITY.md):
//!   * synthesising missing gene/transcript parents,
//!   * AGAT's feature-type normalisation and output sort order,
//!   * multi-parent features (we take the first parent),
//!   * attribute value URL-decoding.

use crate::model::{Record, Strand};
use std::collections::HashMap;
use std::io::Write;

/// Build a map from feature `ID` to its index in `records`.
fn index_by_id(records: &[Record]) -> HashMap<&str, usize> {
    let mut m = HashMap::new();
    for (i, r) in records.iter().enumerate() {
        if let Some(id) = r.id() {
            m.entry(id).or_insert(i);
        }
    }
    m
}

/// Climb the Parent chain from `idx` to the root, returning the chain of indices
/// from the starting node up to (and including) the root.
fn ancestry(records: &[Record], by_id: &HashMap<&str, usize>, idx: usize) -> Vec<usize> {
    let mut chain = vec![idx];
    let mut cur = idx;
    // Guard against cycles in malformed input.
    let mut seen = 0usize;
    while let Some(parent_id) = records[cur].parent() {
        match by_id.get(parent_id) {
            Some(&p) => {
                chain.push(p);
                cur = p;
            }
            None => break, // dangling parent: treat current as root
        }
        seen += 1;
        if seen > records.len() {
            break;
        }
    }
    chain
}

/// Resolve (gene_id, transcript_id) for a record given its ancestry chain.
///
/// The root of the chain is the gene; the node directly beneath the root is the
/// transcript. Matching AGAT (observed on Ensembl input):
///   * `gene_id` strips a leading `gene:` prefix from the root ID;
///   * `transcript_id` strips a leading `transcript:` prefix from the transcript ID;
///   * a root feature that is gene-like or a top-level region (chromosome,
///     contig, ...) gets a `gene_id` but no `transcript_id`.
///
/// See docs/PARITY.md for how this rule was derived and its known limits.
fn resolve_ids(records: &[Record], chain: &[usize]) -> (String, Option<String>) {
    let root = *chain.last().unwrap();
    let raw_gene = records[root]
        .id()
        .map(str::to_string)
        .unwrap_or_else(|| synthetic_id(&records[root]));
    let gene_id = strip_prefix(&raw_gene, "gene:");

    let transcript_id = if chain.len() >= 2 {
        // node directly beneath root
        let tx = chain[chain.len() - 2];
        let raw_tx = records[tx]
            .id()
            .map(str::to_string)
            .unwrap_or_else(|| synthetic_id(&records[tx]));
        Some(strip_prefix(&raw_tx, "transcript:"))
    } else {
        // single-node chain: a root feature. Genes and top-level regions get no
        // transcript_id; anything else is treated as its own transcript so the
        // output stays valid GTF.
        let r = &records[root];
        if is_gene_like(&r.feature_type) || is_toplevel_like(&r.feature_type) {
            None
        } else {
            Some(strip_prefix(&raw_gene, "transcript:"))
        }
    };

    (gene_id, transcript_id)
}

/// Strip an exact leading `prefix` (e.g. `gene:`), otherwise return as-is.
fn strip_prefix(id: &str, prefix: &str) -> String {
    id.strip_prefix(prefix).unwrap_or(id).to_string()
}

fn is_gene_like(feature_type: &str) -> bool {
    let t = feature_type.to_ascii_lowercase();
    t == "gene" || t.ends_with("_gene") || t == "pseudogene"
}

fn is_toplevel_like(feature_type: &str) -> bool {
    matches!(
        feature_type.to_ascii_lowercase().as_str(),
        "chromosome" | "contig" | "scaffold" | "supercontig" | "region" | "biological_region"
    )
}

/// Fallback identifier for a record lacking an explicit ID.
fn synthetic_id(r: &Record) -> String {
    format!("{}:{}-{}", r.seqid, r.start, r.end)
}

/// Serialize one record as a GTF line into `out`.
fn write_gtf_line(
    out: &mut impl Write,
    r: &Record,
    gene_id: &str,
    transcript_id: Option<&str>,
) -> std::io::Result<()> {
    let strand = match r.strand {
        Strand::Unknown => ".", // GTF has no '?'; collapse to '.'
        s => s.as_str(),
    };
    let score = if r.score.is_empty() { "." } else { &r.score };
    let phase = if r.phase.is_empty() { "." } else { &r.phase };

    write!(
        out,
        "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t",
        r.seqid, r.source, r.feature_type, r.start, r.end, score, strand, phase
    )?;

    // GTF attribute column: gene_id and transcript_id lead (GTF spec), then the
    // original GFF attributes are carried over verbatim — AGAT keeps ID/Parent
    // and everything else, so we do too. Attribute *order* within the line is
    // not meaningful and is normalized away by the parity harness.
    write!(out, "gene_id \"{}\";", gene_id)?;
    if let Some(tx) = transcript_id {
        write!(out, " transcript_id \"{}\";", tx)?;
    }
    for (k, v) in &r.attributes.pairs {
        // Some sources (e.g. Ensembl) already carry gene_id/transcript_id in the
        // GFF attributes. We emit our own canonical pair above, so drop the
        // originals to avoid duplicates — this matches AGAT.
        if k == "gene_id" || k == "transcript_id" {
            continue;
        }
        write!(out, " {} \"{}\";", k, v)?;
    }
    out.write_all(b"\n")
}

/// Convert a slice of GFF3 records to GTF, writing to `out`.
///
/// Output order matches input order for the spike; the parity harness applies a
/// normaliser that is order-insensitive, and AGAT-faithful sorting is an M1 task.
pub fn gff3_to_gtf(records: &[Record], out: &mut impl Write) -> std::io::Result<()> {
    let by_id = index_by_id(records);
    for (i, r) in records.iter().enumerate() {
        let chain = ancestry(records, &by_id, i);
        let (gene_id, transcript_id) = resolve_ids(records, &chain);
        write_gtf_line(out, r, &gene_id, transcript_id.as_deref())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reader::read_all;
    use std::io::Cursor;

    fn convert(gff: &str) -> String {
        let recs = read_all(Cursor::new(gff)).unwrap();
        let mut buf = Vec::new();
        gff3_to_gtf(&recs, &mut buf).unwrap();
        String::from_utf8(buf).unwrap()
    }

    #[test]
    fn propagates_gene_and_transcript_ids() {
        let gff = "\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=g1;Name=FOO
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=t1;Parent=g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tID=e1;Parent=t1
chr1\tsrc\tCDS\t1\t50\t.\t+\t0\tID=c1;Parent=t1
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        // gene line: only gene_id; ID is retained
        assert!(lines[0].contains("gene_id \"g1\";"));
        assert!(!lines[0].contains("transcript_id"));
        assert!(lines[0].contains("ID \"g1\";"));
        assert!(lines[0].contains("Name \"FOO\";"));
        // mRNA line: gene + transcript; Parent retained
        assert!(lines[1].contains("gene_id \"g1\"; transcript_id \"t1\";"));
        assert!(lines[1].contains("Parent \"g1\";"));
        // exon/CDS climb to g1
        assert!(lines[2].contains("gene_id \"g1\"; transcript_id \"t1\";"));
        assert!(lines[3].contains("gene_id \"g1\"; transcript_id \"t1\";"));
        // CDS keeps its phase
        assert!(lines[3].starts_with("chr1\tsrc\tCDS\t1\t50\t.\t+\t0\t"));
    }

    #[test]
    fn strips_ensembl_prefixes_like_agat() {
        let gff = "\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:G1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:T1;Parent=gene:G1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tID=e1;Parent=transcript:T1
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert!(lines[0].contains("gene_id \"G1\";"));
        assert!(lines[0].contains("ID \"gene:G1\";")); // original ID kept verbatim
        assert!(lines[1].contains("gene_id \"G1\"; transcript_id \"T1\";"));
        assert!(lines[2].contains("gene_id \"G1\"; transcript_id \"T1\";"));
    }

    #[test]
    fn toplevel_region_gets_gene_id_only() {
        let gff = "I\tsrc\tchromosome\t1\t230218\t.\t.\t.\tID=chromosome:I\n";
        let gtf = convert(gff);
        // gene_id keeps full ID (no `gene:` prefix to strip), no transcript_id
        assert!(gtf.contains("gene_id \"chromosome:I\";"));
        assert!(!gtf.contains("transcript_id"));
    }
}
