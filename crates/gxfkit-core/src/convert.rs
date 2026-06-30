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
//! Output is emitted in AGAT's tree-traversal order (see [`compute_layout`]) so
//! it also reaches raw byte-parity on most lines, not just normalized parity.
//!
//! Known not-yet-handled cases (see docs/PARITY.md):
//!   * AGAT's `transposable_element` remodeling (DIV-1),
//!   * a few AGAT internal-clustering orderings (raw-diff only; normalized OK),
//!   * NCBI-RefSeq-style hierarchy completion (synthesize missing mRNA),
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
    // Remaining attributes follow AGAT's order: ASCII-ascending by key (so
    // uppercase keys like ID/Name/Parent precede lowercase ones). The
    // synthesized ID (when the source had none) joins this set so it sorts into
    // the same position AGAT puts it. We drop any source gene_id/transcript_id
    // since we emit our own canonical pair above.
    let mut rest: Vec<(&str, &str)> = Vec::with_capacity(r.attributes.pairs.len() + 1);
    if eff.synthesized {
        rest.push(("ID", eff.id.as_str()));
    }
    for (k, v) in &r.attributes.pairs {
        if k == "gene_id" || k == "transcript_id" {
            continue;
        }
        rest.push((k.as_str(), v.as_str()));
    }
    rest.sort_by(|a, b| a.0.cmp(b.0)); // stable: ties keep source order
    for (k, v) in rest {
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

/// Output rank of a level3 feature type within a transcript (AGAT order).
fn type_rank(feature_type: &str) -> u8 {
    match feature_type.to_ascii_lowercase().as_str() {
        "exon" => 0,
        "cds" => 1,
        "five_prime_utr" => 2,
        "three_prime_utr" => 3,
        _ => 4,
    }
}

/// Level-1 (root) feature category, which AGAT emits in this bucket order within
/// each seqid: top-level regions first, then biological_region, then gene trees.
fn level1_category(feature_type: &str) -> u8 {
    match feature_type.to_ascii_lowercase().as_str() {
        "chromosome" | "contig" | "scaffold" | "supercontig" | "region" => 0,
        "biological_region" => 1,
        _ => 2,
    }
}

/// Emission order plus the resolved `(gene_id, transcript_id)` for each record.
struct Layout {
    /// Record indices in AGAT output order.
    order: Vec<usize>,
    /// `ids[i]` = (gene_id, transcript_id) for record `i`.
    ids: Vec<(String, Option<String>)>,
}

/// Resolve `(gene_id, transcript_id)` for one node given its depth in the tree
/// and the values inherited from its ancestors. Mirrors AGAT: `gene_id` is the
/// root's (prefix-stripped) ID, `transcript_id` is the level-1 node's; a root
/// that is gene-like or a top-level region has no transcript_id.
fn node_ids(
    records: &[Record],
    eff: &[EffectiveId],
    node: usize,
    inherited_gene: &str,
    inherited_tx: &Option<String>,
    depth: u32,
) -> (String, Option<String>) {
    match depth {
        0 => {
            let gene = strip_prefix(&eff[node].id, "gene:");
            let ft = &records[node].feature_type;
            let tx = if is_gene_like(ft) || is_toplevel_like(ft) {
                None
            } else {
                Some(strip_prefix(&eff[node].id, "transcript:"))
            };
            (gene, tx)
        }
        1 => (
            inherited_gene.to_string(),
            Some(strip_prefix(&eff[node].id, "transcript:")),
        ),
        _ => (inherited_gene.to_string(), inherited_tx.clone()),
    }
}

/// Build the AGAT-order traversal and resolve every record's gene/transcript IDs
/// in a single O(n log n) pass (the sort dominates).
///
/// AGAT emits a *tree traversal*, not a flat sort: per seqid (lexicographic),
/// root features are bucketed by [`level1_category`] then `(start, end)`; each
/// root is followed immediately by its subtree, with a node's children ordered
/// by `(type_rank, start, end)` (so a gene's transcripts sort by position, and a
/// transcript's children come out exon → CDS → 5'UTR → 3'UTR). IDs are resolved
/// by propagating gene/transcript down the DFS, so we never re-walk ancestry
/// per record (which would be O(n²) on a deep Parent chain). A few AGAT
/// internal-clustering quirks are not reproduced by this pure key — see PARITY.md.
fn compute_layout(records: &[Record], by_id: &HashMap<&str, usize>, eff: &[EffectiveId]) -> Layout {
    let n = records.len();
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut roots: Vec<usize> = Vec::new();
    for (i, r) in records.iter().enumerate() {
        match r.parent().and_then(|p| by_id.get(p)) {
            Some(&p) if p != i => children[p].push(i),
            _ => roots.push(i),
        }
    }
    // Siblings: (type_rank, start, end), tie-broken by effective ID — AGAT orders
    // same-coordinate features (e.g. two transcripts spanning the same range) by
    // their ID lexicographically.
    for kids in &mut children {
        kids.sort_by(|&a, &b| {
            type_rank(&records[a].feature_type)
                .cmp(&type_rank(&records[b].feature_type))
                .then(records[a].start.cmp(&records[b].start))
                .then(records[a].end.cmp(&records[b].end))
                .then(eff[a].id.cmp(&eff[b].id))
        });
    }
    roots.sort_by(|&a, &b| {
        records[a]
            .seqid
            .cmp(&records[b].seqid)
            .then(
                level1_category(&records[a].feature_type)
                    .cmp(&level1_category(&records[b].feature_type)),
            )
            .then(records[a].start.cmp(&records[b].start))
            .then(records[a].end.cmp(&records[b].end))
            .then(eff[a].id.cmp(&eff[b].id))
    });

    // Pre-order DFS via explicit stack (no recursion depth limit). Each stack
    // entry carries the gene/transcript inherited from the parent so IDs are
    // computed once per node.
    let mut order = Vec::with_capacity(n);
    let mut ids: Vec<(String, Option<String>)> = vec![(String::new(), None); n];
    let mut emitted = vec![false; n];
    let mut stack: Vec<(usize, String, Option<String>, u32)> = roots
        .iter()
        .rev()
        .map(|&r| (r, String::new(), None, 0))
        .collect();
    while let Some((i, ig, itx, depth)) = stack.pop() {
        if emitted[i] {
            continue;
        }
        emitted[i] = true;
        let (gene, tx) = node_ids(records, eff, i, &ig, &itx, depth);
        order.push(i);
        for &c in children[i].iter().rev() {
            if !emitted[c] {
                stack.push((c, gene.clone(), tx.clone(), depth.saturating_add(1)));
            }
        }
        ids[i] = (gene, tx);
    }
    // Any record not reachable from a root (e.g. a Parent cycle) is emitted last
    // in input order and treated as its own root, so every line appears once.
    for i in 0..n {
        if !emitted[i] {
            order.push(i);
            ids[i] = node_ids(records, eff, i, "", &None, 0);
        }
    }
    Layout { order, ids }
}

/// Convert a slice of GFF3 records to GTF, writing to `out`.
///
/// Records are emitted in AGAT's tree-traversal order (see [`compute_layout`]);
/// the per-record content is independent of order, so this reaches AGAT
/// byte-parity (modulo a few documented clustering quirks) while the parity
/// harness — which is order-insensitive — stays unaffected.
pub fn gff3_to_gtf(records: &[Record], out: &mut impl Write) -> std::io::Result<()> {
    let by_id = index_by_id(records);
    let eff = assign_effective_ids(records);
    let layout = compute_layout(records, &by_id, &eff);
    for &i in &layout.order {
        let (gene_id, transcript_id) = &layout.ids[i];
        write_gtf_line(out, &records[i], gene_id, transcript_id.as_deref(), &eff[i])?;
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
        // Output is in tree order, so locate the two exon lines by content.
        let exons: Vec<&str> = gtf.lines().filter(|l| l.contains("\texon\t")).collect();
        assert_eq!(exons.len(), 2, "{gtf}");
        // The first-in-document exon (under t1) keeps SHARED; the later one (t2)
        // gets the agat counter. Both must appear exactly once.
        assert!(
            exons.iter().any(|l| l.contains("ID \"SHARED\";")),
            "expected a SHARED exon: {gtf}"
        );
        assert!(
            exons.iter().any(|l| l.contains("ID \"agat-exon-1\";")),
            "expected an agat-exon-1 exon: {gtf}"
        );
    }

    #[test]
    fn idless_feature_gets_lowercased_agat_id() {
        let gff = "chr1\t.\tfive_prime_UTR\t1\t9\t.\t+\t.\tParent=transcript:t1\n";
        let gtf = convert(gff);
        assert!(gtf.contains("ID \"agat-five_prime_utr-1\";"), "{gtf}");
    }

    #[test]
    fn emits_in_agat_tree_order() {
        // Input deliberately out of order; expect gene -> transcript -> exon,CDS
        // (type rank), with the topfeature first and biological_region before genes.
        let gff = "\
chr1\tsrc\tCDS\t1\t50\t.\t+\t0\tID=c1;Parent=transcript:t1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tID=e1;Parent=transcript:t1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g1
chr1\t.\tbiological_region\t1\t9\t.\t+\t.\tfoo=bar
chr1\tsrc\tchromosome\t1\t1000\t.\t.\t.\tID=chromosome:1
";
        let gtf = convert(gff);
        let types: Vec<&str> = gtf.lines().map(|l| l.split('\t').nth(2).unwrap()).collect();
        assert_eq!(
            types,
            vec![
                "chromosome",
                "biological_region",
                "gene",
                "mRNA",
                "exon",
                "CDS"
            ],
            "got: {types:?}\n{gtf}"
        );
    }

    #[test]
    fn deep_chain_resolves_and_terminates() {
        // A long Parent chain must resolve in O(n) (not re-walk ancestry per
        // node) and not hang. Every node's gene_id is the root's.
        let mut gff = String::from("chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=gene:g\n");
        for i in 0..2000 {
            let parent = if i == 0 {
                "gene:g".to_string()
            } else {
                format!("n{}", i - 1)
            };
            gff.push_str(&format!(
                "chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=n{i};Parent={parent}\n"
            ));
        }
        let gtf = convert(&gff);
        assert_eq!(gtf.lines().count(), 2001);
        // every line carries the root gene_id
        assert!(gtf.lines().all(|l| l.contains("gene_id \"g\";")));
    }

    #[test]
    fn self_parent_cycle_does_not_hang_or_panic() {
        // Self-referential Parent (malformed) must still emit each line once.
        let gff = "\
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=s1;Parent=s1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=s2;Parent=s2
";
        let gtf = convert(gff);
        assert_eq!(gtf.lines().count(), 2);
        assert!(gtf.contains("gene_id \"s1\";"));
        assert!(gtf.contains("gene_id \"s2\";"));
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
