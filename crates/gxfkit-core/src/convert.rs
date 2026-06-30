//! GFF3 -> GTF conversion.
//!
//! Covers a `gene -> transcript -> exon/CDS/UTR` hierarchy linked by
//! `ID`/`Parent`. We resolve each feature's `gene_id`/`transcript_id` by climbing
//! the `Parent` chain to the root, derive `gene_id`/`transcript_id` the way AGAT
//! does (Ensembl prefix stripping), synthesize missing feature IDs with AGAT's
//! uniqueness + `agat-<type>-<N>` rules, and serialize multi-value attributes as
//! GTF lists. This reaches byte-parity with AGAT (after normalization) on the
//! human corpus; see docs/PARITY.md for the rules and the one open divergence.
//!
//! Known not-yet-handled cases (see docs/PARITY.md):
//!   * AGAT's `transposable_element` remodeling (DIV-1),
//!   * AGAT-faithful output sort order (parity harness is order-insensitive),
//!   * multi-parent features (we take the first parent).

use crate::model::{Record, Strand};
use std::collections::{HashMap, HashSet};
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

/// The effective identifier of each record, plus whether it was synthesized.
struct EffectiveId {
    id: String,
    /// True when the source feature had no `ID` and we created one (so it must
    /// be emitted as a new `ID "..."` attribute).
    synthesized: bool,
}

/// Assign every record an effective `ID`, mirroring AGAT's ID synthesis. AGAT
/// guarantees globally-unique feature IDs, processing in document order:
///   * a real `ID` attribute is used as-is;
///   * otherwise an `exon_id` (Ensembl exons carry one but no `ID`) is promoted,
///     but only if that value is still free — a shared exon_id reused across
///     transcripts keeps the name on its *first* occurrence and gets a
///     `agat-exon-<N>` counter on every later one;
///   * otherwise (no usable source attribute) a per-type counter
///     `agat-<type>-<N>` is assigned (AGAT's scheme for `biological_region` etc.).
fn assign_effective_ids(records: &[Record]) -> Vec<EffectiveId> {
    let mut counters: HashMap<String, usize> = HashMap::new();
    let mut used: HashSet<String> = HashSet::new();
    let mut out = Vec::with_capacity(records.len());

    for r in records {
        if let Some(id) = r.id() {
            used.insert(id.to_string());
            out.push(EffectiveId {
                id: id.to_string(),
                synthesized: false,
            });
        } else if let Some(exon_id) = r.attributes.get("exon_id").filter(|e| !used.contains(*e)) {
            used.insert(exon_id.to_string());
            out.push(EffectiveId {
                id: exon_id.to_string(),
                synthesized: true,
            });
        } else {
            out.push(EffectiveId {
                id: next_agat_id(&mut counters, &mut used, &r.feature_type),
                synthesized: true,
            });
        }
    }
    out
}

/// Next free `agat-<type>-<N>` id, per-type counter, skipping any taken value.
/// AGAT lowercases the feature type here (e.g. `five_prime_UTR` -> `..._utr`).
fn next_agat_id(
    counters: &mut HashMap<String, usize>,
    used: &mut HashSet<String>,
    feature_type: &str,
) -> String {
    let ftype = feature_type.to_ascii_lowercase();
    let c = counters.entry(ftype.clone()).or_insert(0);
    loop {
        *c += 1;
        let id = format!("agat-{}-{}", ftype, c);
        if used.insert(id.clone()) {
            return id;
        }
    }
}

/// Resolve (gene_id, transcript_id) for a record given its ancestry chain.
///
/// The root of the chain is the gene; the node directly beneath the root is the
/// transcript. Matching AGAT (observed on Ensembl input):
///   * `gene_id` strips a leading `gene:` prefix from the root's effective ID;
///   * `transcript_id` strips a leading `transcript:` prefix from the transcript;
///   * a root feature that is gene-like or a top-level region (chromosome,
///     contig, ...) gets a `gene_id` but no `transcript_id`.
///
/// See docs/PARITY.md for how this rule was derived and its known limits.
fn resolve_ids(
    records: &[Record],
    eff: &[EffectiveId],
    chain: &[usize],
) -> (String, Option<String>) {
    let root = *chain.last().unwrap();
    let gene_id = strip_prefix(&eff[root].id, "gene:");

    let transcript_id = if chain.len() >= 2 {
        let tx = chain[chain.len() - 2];
        Some(strip_prefix(&eff[tx].id, "transcript:"))
    } else {
        // single-node chain: a root feature. Genes and top-level regions get no
        // transcript_id; anything else is treated as its own transcript so the
        // output stays valid GTF.
        let r = &records[root];
        if is_gene_like(&r.feature_type) || is_toplevel_like(&r.feature_type) {
            None
        } else {
            Some(strip_prefix(&eff[root].id, "transcript:"))
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

/// Serialize one record as a GTF line into `out`.
fn write_gtf_line(
    out: &mut impl Write,
    r: &Record,
    gene_id: &str,
    transcript_id: Option<&str>,
    eff: &EffectiveId,
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
    // If the source feature had no ID, AGAT emits the one it synthesized.
    if eff.synthesized {
        write!(out, " ID \"{}\";", eff.id)?;
    }
    for (k, v) in &r.attributes.pairs {
        // Some sources (e.g. Ensembl) already carry gene_id/transcript_id in the
        // GFF attributes. We emit our own canonical pair above, so drop the
        // originals to avoid duplicates — this matches AGAT.
        if k == "gene_id" || k == "transcript_id" {
            continue;
        }
        write_attr(out, k, v)?;
    }
    out.write_all(b"\n")
}

/// Write one GTF attribute. A GFF3 multi-value attribute (unescaped commas, e.g.
/// `tag=basic,Ensembl_canonical`) becomes separately-quoted, comma-joined values
/// (`tag "basic","Ensembl_canonical";`) — AGAT's GTF serialization of a list.
fn write_attr(out: &mut impl Write, key: &str, value: &str) -> std::io::Result<()> {
    write!(out, " {} ", key)?;
    for (i, part) in value.split(',').enumerate() {
        if i > 0 {
            out.write_all(b",")?;
        }
        write!(out, "\"{}\"", part)?;
    }
    out.write_all(b";")
}

/// Convert a slice of GFF3 records to GTF, writing to `out`.
///
/// Output order matches input order for the spike; the parity harness applies a
/// normaliser that is order-insensitive, and AGAT-faithful sorting is an M1 task.
pub fn gff3_to_gtf(records: &[Record], out: &mut impl Write) -> std::io::Result<()> {
    let by_id = index_by_id(records);
    let eff = assign_effective_ids(records);
    for (i, r) in records.iter().enumerate() {
        let chain = ancestry(records, &by_id, i);
        let (gene_id, transcript_id) = resolve_ids(records, &eff, &chain);
        write_gtf_line(out, r, &gene_id, transcript_id.as_deref(), &eff[i])?;
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

    #[test]
    fn synthesizes_exon_id_from_exon_id_attr() {
        // exon has no ID but carries exon_id -> AGAT promotes it to ID.
        let gff = "\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tParent=transcript:t1;exon_id=E1;Name=E1
";
        let gtf = convert(gff);
        let exon = gtf.lines().nth(2).unwrap();
        assert!(exon.contains("ID \"E1\";"), "exon line: {exon}");
    }

    #[test]
    fn duplicate_exon_id_gets_agat_counter() {
        // A shared exon_id keeps the name on first use, gets agat-exon-N after.
        let gff = "\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t2;Parent=gene:g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tParent=transcript:t1;exon_id=SHARED
chr1\tsrc\texon\t1\t50\t.\t+\t.\tParent=transcript:t2;exon_id=SHARED
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert!(lines[3].contains("ID \"SHARED\";"), "first: {}", lines[3]);
        assert!(
            lines[4].contains("ID \"agat-exon-1\";"),
            "second: {}",
            lines[4]
        );
    }

    #[test]
    fn idless_feature_gets_lowercased_agat_id() {
        let gff = "chr1\t.\tfive_prime_UTR\t1\t9\t.\t+\t.\tParent=transcript:t1\n";
        let gtf = convert(gff);
        assert!(gtf.contains("ID \"agat-five_prime_utr-1\";"), "{gtf}");
    }

    #[test]
    fn multivalue_attribute_is_split_quoted() {
        let gff =
            "chr1\tsrc\tmRNA\t1\t9\t.\t+\t.\tID=transcript:t1;Parent=gene:g1;tag=basic,canonical\n";
        let gtf = convert(gff);
        assert!(
            gtf.contains("tag \"basic\",\"canonical\";"),
            "expected split-quoted tag, got: {gtf}"
        );
    }
}
