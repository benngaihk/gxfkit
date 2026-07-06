//! GFF3 -> GTF conversion.
//!
//! Covers a `gene -> transcript -> exon/CDS/UTR` hierarchy linked by
//! `ID`/`Parent`. We resolve each feature's `gene_id`/`transcript_id` by carrying
//! IDs through AGAT's tree traversal, derive `gene_id`/`transcript_id` the way
//! AGAT does (Ensembl prefix stripping), synthesize missing feature IDs with
//! AGAT's uniqueness + `agat-<type>-<N>` rules, and serialize multi-value
//! attributes as GTF lists. This reaches byte-parity with AGAT (after
//! normalization) on the core corpus; see docs/PARITY.md for the rules and the
//! remaining extended-corpus divergences.
//!
//! Output is emitted in AGAT's tree-traversal order (see [`compute_layout`]) so
//! it also reaches raw byte-parity on most lines, not just normalized parity.
//!
//! Known not-yet-handled cases (see docs/PARITY.md):
//!   * full AGAT `transposable_element` counter ordering for all corpora,
//!   * a few AGAT internal-clustering orderings (raw-diff only; normalized OK),
//!   * the broader NCBI standardization engine beyond the direct-CDS RefSeq
//!     slice covered here,
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
#[derive(Clone)]
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
        "chromosome"
            | "contig"
            | "scaffold"
            | "supercontig"
            | "region"
            | "biological_region"
            | "mobile_genetic_element"
            | "origin_of_replication"
            | "sequence_feature"
    )
}

fn skip_orphan_refseq_root(r: &Record) -> bool {
    if !r.source.eq_ignore_ascii_case("RefSeq") {
        return false;
    }
    if r.feature_type.eq_ignore_ascii_case("origin_of_replication") {
        return true;
    }
    is_gene_like(&r.feature_type) && r.attributes.get("gene_biotype") == Some("other")
}

/// Serialize one record as a GTF line into `out`.
fn write_gtf_line(
    out: &mut impl Write,
    r: &Record,
    gene_id: &str,
    transcript_id: Option<&str>,
    eff: &EffectiveId,
    parent_override: Option<&str>,
    coords_override: Option<(u64, u64)>,
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
        r.seqid,
        r.source,
        r.feature_type,
        coords_override.map_or(r.start, |(start, _)| start),
        coords_override.map_or(r.end, |(_, end)| end),
        score,
        strand,
        phase
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
    if let Some(parent) = parent_override {
        rest.push(("Parent", parent));
    }
    for (k, v) in &r.attributes.pairs {
        if eff.synthesized && k == "ID" {
            continue;
        }
        if parent_override.is_some() && k == "Parent" {
            continue;
        }
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
        "start_codon" => 2,
        "stop_codon" => 3,
        "five_prime_utr" => 4,
        "three_prime_utr" => 5,
        "utr" => 6,
        _ => 7,
    }
}

fn needs_transcript_parent(feature_type: &str) -> bool {
    matches!(
        feature_type.to_ascii_lowercase().as_str(),
        "exon"
            | "cds"
            | "start_codon"
            | "stop_codon"
            | "five_prime_utr"
            | "three_prime_utr"
            | "utr"
    )
}

fn is_transcript_like(feature_type: &str) -> bool {
    !is_gene_like(feature_type)
        && !is_toplevel_like(feature_type)
        && !needs_transcript_parent(feature_type)
}

fn cds_group_key(r: &Record) -> Option<&str> {
    r.id()
        .or_else(|| r.attributes.get("protein_id"))
        .or_else(|| r.attributes.get("orig_protein_id"))
}

#[derive(Hash, Eq, PartialEq, Ord, PartialOrd)]
struct TranscriptPart {
    feature_type: String,
    seqid: String,
    start: u64,
    end: u64,
    strand: &'static str,
    phase: String,
}

fn transcript_structure_signature(
    records: &[Record],
    children: &[Vec<usize>],
    tx: usize,
) -> Vec<TranscriptPart> {
    let mut parts: Vec<TranscriptPart> = children[tx]
        .iter()
        .filter_map(|&child| {
            let r = &records[child];
            if !(needs_transcript_parent(&r.feature_type)
                || r.feature_type.eq_ignore_ascii_case("CDS"))
            {
                return None;
            }
            Some(TranscriptPart {
                feature_type: r.feature_type.to_ascii_lowercase(),
                seqid: r.seqid.clone(),
                start: r.start,
                end: r.end,
                strand: match r.strand {
                    Strand::Unknown => ".",
                    s => s.as_str(),
                },
                phase: if r.phase.is_empty() {
                    ".".to_string()
                } else {
                    r.phase.clone()
                },
            })
        })
        .collect();
    parts.sort();
    parts
}

fn mark_subtree_skipped(children: &[Vec<usize>], skip_record: &mut [bool], root: usize) {
    let mut stack = vec![root];
    while let Some(i) = stack.pop() {
        if skip_record[i] {
            continue;
        }
        skip_record[i] = true;
        stack.extend(children[i].iter().copied());
    }
}

fn natural_locus_key(r: &Record) -> Option<(&str, u64)> {
    let locus = r.attributes.get("locus_tag")?;
    let digit_start = locus.find(|c: char| c.is_ascii_digit())?;
    if digit_start == 0 {
        return None;
    }
    let (prefix, digits) = locus.split_at(digit_start);
    if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    Some((prefix, digits.parse().ok()?))
}

fn all_have_natural_locus(records: &[Record], indices: &[usize]) -> bool {
    !indices.is_empty()
        && indices
            .iter()
            .all(|&i| natural_locus_key(&records[i]).is_some())
}

fn cmp_natural_locus(records: &[Record], a: usize, b: usize) -> std::cmp::Ordering {
    let (ap, an) = natural_locus_key(&records[a]).expect("natural locus key");
    let (bp, bn) = natural_locus_key(&records[b]).expect("natural locus key");
    ap.cmp(bp)
        .then(an.cmp(&bn))
        .then(records[a].start.cmp(&records[b].start))
        .then(records[a].end.cmp(&records[b].end))
        .then(a.cmp(&b))
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

/// One line in the GTF output stream.
enum OutputRow {
    Record(usize),
    SyntheticTranscript {
        parent: usize,
        plan: SyntheticTranscriptPlan,
    },
    SyntheticTeRna {
        parent: usize,
        plan: TransposableElementPlan,
    },
    SyntheticExon {
        child: usize,
        exon_id: String,
        gene_id: String,
        transcript_id: String,
        parent_id: String,
    },
}

#[derive(Clone)]
struct SyntheticTranscriptPlan {
    /// Canonical GTF gene_id for the standardized gene.
    gene_id: String,
    /// Attribute ID for the synthetic transcript: the original gene ID moved
    /// down one level, so existing children keep pointing at it via Parent.
    synthetic_id: String,
    /// Attribute Parent for the synthetic transcript: the renamed gene ID.
    parent_id: String,
    /// Canonical GTF transcript_id for the synthetic transcript and its children.
    transcript_id: String,
    /// Direct child whose annotation attributes seed the synthetic transcript.
    template_child: usize,
}

#[derive(Clone)]
struct TransposableElementPlan {
    /// Canonical GTF gene_id for the remodeled transposable-element root.
    gene_id: String,
    /// Attribute ID for the synthesized RNA: the source transposable-element ID
    /// moved down one level so existing children keep pointing at it.
    rna_id: String,
    /// Canonical GTF transcript_id for the level1 transposable-element row.
    root_transcript_id: String,
    /// Canonical GTF transcript_id for the synthetic RNA and its children.
    rna_transcript_id: String,
    /// Direct child whose annotation attributes seed the synthetic RNA.
    template_child: usize,
}

/// Emission order plus the resolved `(gene_id, transcript_id)` for each record.
struct Layout {
    /// Record indices in AGAT output order.
    order: Vec<OutputRow>,
    /// `ids[i]` = (gene_id, transcript_id) for record `i`.
    ids: Vec<(String, Option<String>)>,
    /// Effective IDs to use when serializing records. Usually this is the same
    /// as `assign_effective_ids`, but NCBI-style hierarchy completion renames a
    /// gene to `agat-gene-N` and moves the original ID onto a synthetic mRNA.
    eff: Vec<EffectiveId>,
    /// Optional replacement for a record's serialized Parent attribute. This is
    /// needed for mixed complete/incomplete genes: existing transcript children
    /// must point at the renamed gene, while direct CDS/exon children keep
    /// pointing at the moved original ID on the synthetic mRNA.
    parent_override: Vec<Option<String>>,
    /// Optional coordinate override for standardized records. AGAT merges
    /// adjacent direct CDS fragments with the same CDS identity before emitting
    /// the CDS and its synthetic exon.
    coords_override: Vec<Option<(u64, u64)>>,
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

    let mut layout_eff = eff.to_vec();
    let seqids_with_non_region: HashSet<&str> = records
        .iter()
        .filter(|r| !r.feature_type.eq_ignore_ascii_case("region"))
        .map(|r| r.seqid.as_str())
        .collect();
    let mut used_ids: HashSet<String> = eff.iter().map(|e| e.id.clone()).collect();
    let mut synthetic_tx: Vec<Option<SyntheticTranscriptPlan>> = vec![None; n];
    let mut te_plan: Vec<Option<TransposableElementPlan>> = vec![None; n];
    let mut synthetic_exon_id: Vec<Option<String>> = vec![None; n];
    let mut parent_override: Vec<Option<String>> = vec![None; n];
    let mut skip_record = vec![false; n];
    let mut coords_override = vec![None; n];
    let mut counters: HashMap<String, usize> = HashMap::new();

    let mut te_candidates: Vec<(usize, usize, usize)> = Vec::new();
    for parent in 0..n {
        if !records[parent]
            .feature_type
            .eq_ignore_ascii_case("transposable_element_gene")
        {
            continue;
        }
        for &te in &children[parent] {
            if !records[te]
                .feature_type
                .eq_ignore_ascii_case("transposable_element")
            {
                continue;
            }
            let Some(&template_child) = children[te]
                .iter()
                .find(|&&c| needs_transcript_parent(&records[c].feature_type))
            else {
                continue;
            };
            te_candidates.push((parent, te, template_child));
        }
    }
    te_candidates.sort_by(|&(a_parent, a_te, _), &(b_parent, b_te, _)| {
        eff[a_parent]
            .id
            .cmp(&eff[b_parent].id)
            .then(eff[a_te].id.cmp(&eff[b_te].id))
            .then(a_te.cmp(&b_te))
    });
    for (parent, te, template_child) in te_candidates {
        let gene_id = next_agat_id(&mut counters, &mut used_ids, "transposable_element");
        let rna_id = eff[te].id.clone();
        let root_transcript_id = records[te]
            .attributes
            .get("transcript_id")
            .map(ToString::to_string)
            .unwrap_or_else(|| strip_prefix(&rna_id, "transcript:"));
        te_plan[te] = Some(TransposableElementPlan {
            gene_id: gene_id.clone(),
            rna_id,
            root_transcript_id,
            rna_transcript_id: eff[te].id.clone(),
            template_child,
        });
        layout_eff[te] = EffectiveId {
            id: gene_id,
            synthesized: true,
        };
        skip_record[parent] = true;
    }

    let mut synthetic_candidates: Vec<(usize, usize)> = Vec::new();
    for i in 0..n {
        if !is_gene_like(&records[i].feature_type) {
            if children[i].is_empty()
                && ((records[i].feature_type.eq_ignore_ascii_case("region")
                    && !seqids_with_non_region.contains(records[i].seqid.as_str()))
                    || skip_orphan_refseq_root(&records[i]))
            {
                skip_record[i] = true;
            }
            continue;
        }
        let Some(&template_child) = children[i]
            .iter()
            .find(|&&c| needs_transcript_parent(&records[c].feature_type))
        else {
            if (records[i].source.eq_ignore_ascii_case("RefSeq")
                && records[i].feature_type.eq_ignore_ascii_case("pseudogene"))
                || (children[i].is_empty() && skip_orphan_refseq_root(&records[i]))
            {
                skip_record[i] = true;
            }
            continue;
        };
        synthetic_candidates.push((i, template_child));
    }
    let synthetic_candidate_parents: Vec<usize> = synthetic_candidates
        .iter()
        .map(|&(parent, _)| parent)
        .collect();
    if all_have_natural_locus(records, &synthetic_candidate_parents) {
        synthetic_candidates.sort_by(|&(a, _), &(b, _)| cmp_natural_locus(records, a, b));
    }
    for (i, template_child) in synthetic_candidates {
        let gene_id = next_agat_id(&mut counters, &mut used_ids, &records[i].feature_type);
        let synthetic_id = eff[i].id.clone();
        let tx_id = strip_prefix(&eff[i].id, "gene:");
        synthetic_tx[i] = Some(SyntheticTranscriptPlan {
            gene_id: gene_id.clone(),
            synthetic_id,
            parent_id: gene_id.clone(),
            transcript_id: tx_id,
            template_child,
        });
        layout_eff[i] = EffectiveId {
            id: gene_id,
            synthesized: true,
        };
    }
    let mut synthetic_exon_candidates = Vec::new();
    for (parent, plan) in synthetic_tx
        .iter()
        .enumerate()
        .filter_map(|(i, p)| p.as_ref().map(|plan| (i, plan)))
    {
        let template = &records[plan.template_child];
        let template_group = if template.feature_type.eq_ignore_ascii_case("CDS") {
            cds_group_key(template)
        } else {
            None
        };
        let mut selected_children = Vec::new();
        for &child in &children[parent] {
            if !records[child].feature_type.eq_ignore_ascii_case("CDS")
                || records[child].attributes.get("Parent") != Some(plan.synthetic_id.as_str())
            {
                continue;
            }
            let same_selected_group = match template_group {
                Some(group) => cds_group_key(&records[child]) == Some(group),
                None => child == plan.template_child,
            };
            if same_selected_group {
                selected_children.push(child);
            } else {
                skip_record[child] = true;
            }
        }
        selected_children.sort_by(|&a, &b| {
            records[a]
                .start
                .cmp(&records[b].start)
                .then(records[a].end.cmp(&records[b].end))
                .then(a.cmp(&b))
        });
        let mut kept_children: Vec<usize> = Vec::new();
        for child in selected_children {
            if let Some(&last) = kept_children.last() {
                let same_group = cds_group_key(&records[last]) == cds_group_key(&records[child]);
                let (last_start, last_end) =
                    coords_override[last].unwrap_or((records[last].start, records[last].end));
                if same_group && records[child].start <= last_end {
                    coords_override[last] = Some((last_start, last_end.max(records[child].end)));
                    skip_record[child] = true;
                    continue;
                }
            }
            kept_children.push(child);
        }
        synthetic_exon_candidates.extend(kept_children);
    }
    if all_have_natural_locus(records, &synthetic_exon_candidates) {
        synthetic_exon_candidates.sort_by(|&a, &b| cmp_natural_locus(records, a, b));
    }
    for child in synthetic_exon_candidates {
        synthetic_exon_id[child] = Some(next_agat_id(&mut counters, &mut used_ids, "exon"));
    }
    for (parent, plan) in synthetic_tx
        .iter()
        .enumerate()
        .filter_map(|(i, p)| p.as_ref().map(|plan| (i, plan)))
    {
        for &child in &children[parent] {
            let is_moved_under_synthetic_tx = needs_transcript_parent(&records[child].feature_type);
            let parent_attr_is_single_source_id =
                records[child].attributes.get("Parent") == Some(plan.synthetic_id.as_str());
            if !is_moved_under_synthetic_tx && parent_attr_is_single_source_id {
                parent_override[child] = Some(plan.parent_id.clone());
            }
        }
    }
    for parent in 0..n {
        if !is_gene_like(&records[parent].feature_type) {
            continue;
        }
        // AGAT collapses duplicate transcript structures under a gene, keeping
        // the lexicographically lowest transcript ID. Plain `mRNA` exon-only
        // models are retained, but CDS-bearing models and exon-only
        // retained-intron / CDS-not-defined transcript types are collapsed.
        let mut duplicate_groups: HashMap<Vec<TranscriptPart>, Vec<usize>> = HashMap::new();
        for &child in &children[parent] {
            if skip_record[child] || !is_transcript_like(&records[child].feature_type) {
                continue;
            }
            let signature = transcript_structure_signature(records, &children, child);
            if signature.is_empty() {
                continue;
            }
            let has_cds = signature.iter().any(|p| p.feature_type == "cds");
            if !has_cds && records[child].feature_type.eq_ignore_ascii_case("mRNA") {
                continue;
            }
            duplicate_groups.entry(signature).or_default().push(child);
        }
        for mut group in duplicate_groups.into_values().filter(|g| g.len() > 1) {
            group.sort_by(|&a, &b| {
                strip_prefix(&eff[a].id, "transcript:")
                    .cmp(&strip_prefix(&eff[b].id, "transcript:"))
                    .then(a.cmp(&b))
            });
            for duplicate in group.into_iter().skip(1) {
                mark_subtree_skipped(&children, &mut skip_record, duplicate);
            }
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
        let (gene, tx) = node_ids(records, &layout_eff, i, &ig, &itx, depth);
        let (gene, tx) = if let Some(plan) = &te_plan[i] {
            (plan.gene_id.clone(), Some(plan.root_transcript_id.clone()))
        } else {
            (gene, tx)
        };
        if !skip_record[i] {
            if let (Some(exon_id), Some(transcript_id)) = (&synthetic_exon_id[i], &tx) {
                order.push(OutputRow::SyntheticExon {
                    child: i,
                    exon_id: exon_id.clone(),
                    gene_id: gene.clone(),
                    transcript_id: transcript_id.clone(),
                    parent_id: records[i]
                        .parent()
                        .unwrap_or(transcript_id.as_str())
                        .to_string(),
                });
            }
            order.push(OutputRow::Record(i));
            if let Some(plan) = &synthetic_tx[i] {
                order.push(OutputRow::SyntheticTranscript {
                    parent: i,
                    plan: plan.clone(),
                });
            }
            if let Some(plan) = &te_plan[i] {
                order.push(OutputRow::SyntheticTeRna {
                    parent: i,
                    plan: plan.clone(),
                });
            }
        }
        for &c in children[i].iter().rev() {
            if !emitted[c] {
                if let Some(plan) = &te_plan[i] {
                    if needs_transcript_parent(&records[c].feature_type) {
                        stack.push((
                            c,
                            plan.gene_id.clone(),
                            Some(plan.rna_transcript_id.clone()),
                            depth.saturating_add(2),
                        ));
                        continue;
                    }
                }
                if let Some(plan) = &synthetic_tx[i] {
                    if needs_transcript_parent(&records[c].feature_type) {
                        stack.push((
                            c,
                            plan.gene_id.clone(),
                            Some(plan.transcript_id.clone()),
                            depth.saturating_add(2),
                        ));
                        continue;
                    }
                }
                stack.push((c, gene.clone(), tx.clone(), depth.saturating_add(1)));
            }
        }
        ids[i] = (gene, tx);
    }
    // Any record not reachable from a root (e.g. a Parent cycle) is emitted last
    // in input order and treated as its own root, so every line appears once.
    for i in 0..n {
        if !emitted[i] {
            order.push(OutputRow::Record(i));
            ids[i] = node_ids(records, &layout_eff, i, "", &None, 0);
        }
    }
    Layout {
        order,
        ids,
        eff: layout_eff,
        parent_override,
        coords_override,
    }
}

fn write_synthetic_transcript_line(
    out: &mut impl Write,
    parent: &Record,
    template: &Record,
    gene_id: &str,
    synthetic_id: &str,
    parent_id: &str,
    transcript_id: &str,
) -> std::io::Result<()> {
    let strand = match parent.strand {
        Strand::Unknown => ".",
        s => s.as_str(),
    };
    let score = if parent.score.is_empty() {
        "."
    } else {
        &parent.score
    };

    write!(
        out,
        "{}\tAGAT\tmRNA\t{}\t{}\t{}\t{}\t.\tgene_id \"{}\"; transcript_id \"{}\";",
        parent.seqid, parent.start, parent.end, score, strand, gene_id, transcript_id
    )?;
    write_synthetic_attrs(out, template, synthetic_id, parent_id)?;
    out.write_all(b"\n")
}

fn write_synthetic_te_rna_line(
    out: &mut impl Write,
    parent: &Record,
    template: &Record,
    gene_id: &str,
    rna_id: &str,
    parent_id: &str,
    transcript_id: &str,
) -> std::io::Result<()> {
    let strand = match parent.strand {
        Strand::Unknown => ".",
        s => s.as_str(),
    };
    let score = if parent.score.is_empty() {
        "."
    } else {
        &parent.score
    };

    write!(
        out,
        "{}\tAGAT\tRNA\t{}\t{}\t{}\t{}\t.\tgene_id \"{}\"; transcript_id \"{}\";",
        parent.seqid, parent.start, parent.end, score, strand, gene_id, transcript_id
    )?;
    write_synthetic_attrs(out, template, rna_id, parent_id)?;
    out.write_all(b"\n")
}

fn write_synthetic_exon_line(
    out: &mut impl Write,
    child: &Record,
    gene_id: &str,
    transcript_id: &str,
    exon_id: &str,
    parent_id: &str,
    coords_override: Option<(u64, u64)>,
) -> std::io::Result<()> {
    let strand = match child.strand {
        Strand::Unknown => ".",
        s => s.as_str(),
    };
    let score = if child.score.is_empty() {
        "."
    } else {
        &child.score
    };

    write!(
        out,
        "{}\tAGAT\texon\t{}\t{}\t{}\t{}\t.\tgene_id \"{}\"; transcript_id \"{}\";",
        child.seqid,
        coords_override.map_or(child.start, |(start, _)| start),
        coords_override.map_or(child.end, |(_, end)| end),
        score,
        strand,
        gene_id,
        transcript_id
    )?;
    write_synthetic_attrs(out, child, exon_id, parent_id)?;
    out.write_all(b"\n")
}

fn write_synthetic_attrs(
    out: &mut impl Write,
    template: &Record,
    synthetic_id: &str,
    parent_id: &str,
) -> std::io::Result<()> {
    let mut rest: Vec<(&str, &str)> = Vec::with_capacity(template.attributes.pairs.len() + 2);
    rest.push(("ID", synthetic_id));
    rest.push(("Parent", parent_id));
    for (k, v) in &template.attributes.pairs {
        if k == "ID" || k == "Parent" || k == "gene_id" || k == "transcript_id" {
            continue;
        }
        rest.push((k.as_str(), v.as_str()));
    }
    rest.sort_by(|a, b| a.0.cmp(b.0));
    for (k, v) in rest {
        write_attr(out, k, v)?;
    }
    Ok(())
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
    for row in &layout.order {
        match row {
            OutputRow::Record(i) => {
                let (gene_id, transcript_id) = &layout.ids[*i];
                write_gtf_line(
                    out,
                    &records[*i],
                    gene_id,
                    transcript_id.as_deref(),
                    &layout.eff[*i],
                    layout.parent_override[*i].as_deref(),
                    layout.coords_override[*i],
                )?;
            }
            OutputRow::SyntheticTranscript { parent, plan } => {
                write_synthetic_transcript_line(
                    out,
                    &records[*parent],
                    &records[plan.template_child],
                    &plan.gene_id,
                    &plan.synthetic_id,
                    &plan.parent_id,
                    &plan.transcript_id,
                )?;
            }
            OutputRow::SyntheticTeRna { parent, plan } => {
                write_synthetic_te_rna_line(
                    out,
                    &records[*parent],
                    &records[plan.template_child],
                    &plan.gene_id,
                    &plan.rna_id,
                    &plan.gene_id,
                    &plan.rna_transcript_id,
                )?;
            }
            OutputRow::SyntheticExon {
                child,
                exon_id,
                gene_id,
                transcript_id,
                parent_id,
            } => {
                write_synthetic_exon_line(
                    out,
                    &records[*child],
                    gene_id,
                    transcript_id,
                    exon_id,
                    parent_id,
                    layout.coords_override[*child],
                )?;
            }
        }
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
    fn orphan_region_seqid_is_skipped_like_agat() {
        let gff = "\
scaffold_only\tsrc\tregion\t1\t100\t.\t.\t.\tID=region:scaffold_only
annotated\tsrc\tregion\t1\t100\t.\t.\t.\tID=region:annotated
annotated\tsrc\tgene\t10\t90\t.\t+\t.\tID=gene:g1
";
        let gtf = convert(gff);

        assert!(!gtf.contains("region:scaffold_only"), "{gtf}");
        assert!(gtf.contains("region:annotated"), "{gtf}");
        assert!(gtf.contains("gene:g1"), "{gtf}");
    }

    #[test]
    fn remodels_transposable_element_gene_like_agat() {
        let gff = "\
chr1\tFlyBase\ttransposable_element_gene\t10\t20\t.\t+\t.\tID=gene:B;Name=B;biotype=transposable_element;gene_id=B
chr1\tFlyBase\ttransposable_element\t10\t20\t.\t+\t.\tID=transcript:B-RA;Parent=gene:B;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=B-RA
chr1\tFlyBase\texon\t10\t20\t.\t+\t.\tParent=transcript:B-RA;Name=B-RA-E1;exon_id=B-RA-E1;rank=1
chr1\tFlyBase\ttransposable_element_gene\t30\t40\t.\t+\t.\tID=gene:A;Name=A;biotype=transposable_element;gene_id=A
chr1\tFlyBase\ttransposable_element\t30\t40\t.\t+\t.\tID=transcript:A-RA;Parent=gene:A;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=A-RA
chr1\tFlyBase\texon\t30\t40\t.\t+\t.\tParent=transcript:A-RA;Name=A-RA-E1;exon_id=A-RA-E1;rank=1
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert_eq!(lines.len(), 6, "{gtf}");
        assert!(lines[0].contains("\ttransposable_element\t"), "{gtf}");
        assert!(
            lines[0].contains("gene_id \"agat-transposable_element-2\"; transcript_id \"B-RA\";"),
            "{gtf}"
        );
        assert!(
            lines[0].contains("ID \"agat-transposable_element-2\";"),
            "{gtf}"
        );
        assert!(lines[0].contains("Parent \"gene:B\";"), "{gtf}");
        assert!(lines[1].contains("\tAGAT\tRNA\t"), "{gtf}");
        assert!(
            lines[1].contains(
                "gene_id \"agat-transposable_element-2\"; transcript_id \"transcript:B-RA\";"
            ),
            "{gtf}"
        );
        assert!(lines[1].contains("ID \"transcript:B-RA\";"), "{gtf}");
        assert!(
            lines[1].contains("Parent \"agat-transposable_element-2\";"),
            "{gtf}"
        );
        assert!(
            lines[2].contains(
                "gene_id \"agat-transposable_element-2\"; transcript_id \"transcript:B-RA\";"
            ),
            "{gtf}"
        );
        assert!(
            lines[3].contains("ID \"agat-transposable_element-1\";"),
            "{gtf}"
        );
        assert!(!gtf.contains("\ttransposable_element_gene\t"), "{gtf}");
    }

    #[test]
    fn mobile_genetic_element_is_toplevel_like_agat() {
        let gff =
            "chr1\tRefSeq\tmobile_genetic_element\t10\t90\t.\t+\t.\tID=mge1;gbkey=mobile_element\n";
        let gtf = convert(gff);
        assert!(gtf.contains("gene_id \"mge1\";"), "{gtf}");
        assert!(!gtf.contains("transcript_id"), "{gtf}");
    }

    #[test]
    fn refseq_misc_roots_do_not_get_transcript_id() {
        let gff = "\
chr1\tRefSeq\tsequence_feature\t10\t20\t.\t+\t.\tID=frag1;gbkey=misc_feature
chr1\tRefSeq\torigin_of_replication\t30\t40\t.\t+\t.\tID=ori1;gbkey=rep_origin
";
        let gtf = convert(gff);
        assert!(gtf.lines().all(|l| !l.contains("transcript_id")), "{gtf}");
    }

    #[test]
    fn orphan_refseq_origin_is_skipped_like_agat() {
        let gff =
            "chr1\tRefSeq\torigin_of_replication\t30\t40\t.\t+\t.\tID=ori1;gbkey=rep_origin\n";
        let gtf = convert(gff);
        assert!(gtf.is_empty(), "{gtf}");
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
    fn completes_gene_to_cds_hierarchy_with_synthetic_mrna() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=geneA;Name=A
chr1\tRefSeq\tCDS\t20\t80\t.\t+\t0\tID=cdsA;Parent=geneA
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert_eq!(lines.len(), 4, "{gtf}");

        assert!(lines[0].contains("\tgene\t"), "{gtf}");
        assert!(lines[0].contains("gene_id \"agat-gene-1\";"), "{gtf}");
        assert!(lines[0].contains("ID \"agat-gene-1\";"), "{gtf}");
        assert!(!lines[0].contains("ID \"geneA\";"), "{gtf}");

        assert!(lines[1].contains("\tmRNA\t"), "{gtf}");
        assert!(
            lines[1].contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
        assert!(
            lines[1].contains("ID \"geneA\"; Parent \"agat-gene-1\";"),
            "{gtf}"
        );

        assert!(lines[2].contains("\texon\t"), "{gtf}");
        assert!(
            lines[2].contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
        assert!(lines[2].contains("Parent \"geneA\";"), "{gtf}");
        assert!(lines[2].contains("ID \"agat-exon-1\";"), "{gtf}");

        assert!(lines[3].contains("\tCDS\t"), "{gtf}");
        assert!(
            lines[3].contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
        assert!(lines[3].contains("Parent \"geneA\";"), "{gtf}");
    }

    #[test]
    fn refseq_synthetic_gene_ids_follow_locus_tag_natural_order() {
        let gff = "\
chr1\tRefSeq\tgene\t100\t190\t.\t+\t.\tID=gene-b0002;locus_tag=b0002
chr1\tRefSeq\tCDS\t120\t180\t.\t+\t0\tID=cds2;Parent=gene-b0002;locus_tag=b0002
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=gene-b0001;locus_tag=b0001
chr1\tRefSeq\tCDS\t20\t80\t.\t+\t0\tID=cds1;Parent=gene-b0001;locus_tag=b0001
";
        let gtf = convert(gff);
        let early_gene = gtf
            .lines()
            .find(|l| l.contains("\tgene\t") && l.contains("locus_tag \"b0001\";"))
            .unwrap();
        let late_gene = gtf
            .lines()
            .find(|l| l.contains("\tgene\t") && l.contains("locus_tag \"b0002\";"))
            .unwrap();

        assert!(early_gene.contains("gene_id \"agat-gene-1\";"), "{gtf}");
        assert!(late_gene.contains("gene_id \"agat-gene-2\";"), "{gtf}");
    }

    #[test]
    fn pseudogene_hierarchy_completion_uses_pseudogene_counter() {
        let gff = "\
chr1\tRefSeq\tpseudogene\t10\t90\t.\t+\t.\tID=gene-b0240;locus_tag=b0240;pseudo=true
chr1\tRefSeq\tCDS\t20\t80\t.\t+\t0\tID=cds1;Parent=gene-b0240;locus_tag=b0240;pseudo=true
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();

        assert!(lines[0].contains("gene_id \"agat-pseudogene-1\";"), "{gtf}");
        assert!(lines[0].contains("ID \"agat-pseudogene-1\";"), "{gtf}");
        assert!(lines[1].contains("Parent \"agat-pseudogene-1\";"), "{gtf}");
    }

    #[test]
    fn alternative_direct_cds_groups_are_suppressed_like_agat() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t100\t.\t+\t.\tID=gene-b0001;locus_tag=b0001
chr1\tRefSeq\tCDS\t10\t100\t.\t+\t0\tID=cds-main;Parent=gene-b0001;locus_tag=b0001;product=main
chr1\tRefSeq\tCDS\t20\t80\t.\t+\t0\tID=cds-alt;Parent=gene-b0001;locus_tag=b0001;product=alt
";
        let gtf = convert(gff);

        assert_eq!(gtf.lines().count(), 4, "{gtf}");
        assert!(gtf.contains("product \"main\";"), "{gtf}");
        assert!(!gtf.contains("product \"alt\";"), "{gtf}");
    }

    #[test]
    fn adjacent_direct_cds_fragments_are_merged_like_agat() {
        let gff = "\
chr1\tRefSeq\tpseudogene\t10\t100\t.\t+\t.\tID=gene-b4623;locus_tag=b4623;pseudo=true
chr1\tRefSeq\tCDS\t10\t20\t.\t+\t0\tID=cds-frag;Parent=gene-b4623;locus_tag=b4623;pseudo=true
chr1\tRefSeq\tCDS\t50\t70\t.\t+\t0\tID=cds-frag;Parent=gene-b4623;locus_tag=b4623;pseudo=true
chr1\tRefSeq\tCDS\t70\t100\t.\t+\t0\tID=cds-frag;Parent=gene-b4623;locus_tag=b4623;pseudo=true
";
        let gtf = convert(gff);
        let cds_lines: Vec<&str> = gtf.lines().filter(|l| l.contains("\tCDS\t")).collect();
        let exon_lines: Vec<&str> = gtf.lines().filter(|l| l.contains("\texon\t")).collect();

        assert_eq!(cds_lines.len(), 2, "{gtf}");
        assert_eq!(exon_lines.len(), 2, "{gtf}");
        assert!(cds_lines.iter().any(|l| l.contains("\t50\t100\t")), "{gtf}");
        assert!(
            exon_lines.iter().any(|l| l.contains("\t50\t100\t")),
            "{gtf}"
        );
    }

    #[test]
    fn synthetic_mrna_keeps_prefixed_source_id_attribute() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=gene:G1
chr1\tRefSeq\texon\t20\t80\t.\t+\t.\tID=exon1;Parent=gene:G1
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert_eq!(lines.len(), 3, "{gtf}");

        assert!(lines[1].contains("\tmRNA\t"), "{gtf}");
        assert!(
            lines[1].contains("gene_id \"agat-gene-1\"; transcript_id \"G1\";"),
            "{gtf}"
        );
        assert!(
            lines[1].contains("ID \"gene:G1\"; Parent \"agat-gene-1\";"),
            "{gtf}"
        );
        assert!(
            lines[2].contains("Parent \"gene:G1\";"),
            "child should still point at the moved source ID: {gtf}"
        );
    }

    #[test]
    fn pseudogene_without_cds_is_skipped_like_agat() {
        let gff =
            "chr1\tRefSeq\tpseudogene\t10\t90\t.\t+\t.\tID=gene-b0218;locus_tag=b0218;pseudo=true\n";
        let gtf = convert(gff);
        assert!(gtf.is_empty(), "{gtf}");
    }

    #[test]
    fn non_refseq_pseudogene_with_transcript_is_retained() {
        let gff = "\
chr1\thavana\tpseudogene\t10\t90\t.\t+\t.\tID=gene:g1;biotype=processed_pseudogene
chr1\thavana\tpseudogenic_transcript\t10\t90\t.\t+\t.\tID=transcript:t1;Parent=gene:g1
";
        let gtf = convert(gff);

        assert_eq!(gtf.lines().count(), 2, "{gtf}");
        assert!(gtf.contains("\tpseudogene\t"), "{gtf}");
        assert!(gtf.contains("\tpseudogenic_transcript\t"), "{gtf}");
    }

    #[test]
    fn orphan_refseq_other_biotype_gene_is_skipped_like_agat() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=gene-b2621;gene_biotype=other;locus_tag=b2621
";
        let gtf = convert(gff);
        assert!(gtf.is_empty(), "{gtf}");
    }

    #[test]
    fn completes_gene_to_codon_hierarchy_with_synthetic_mrna() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=geneA
chr1\tRefSeq\tstart_codon\t20\t22\t.\t+\t0\tID=start1;Parent=geneA
chr1\tRefSeq\tstop_codon\t78\t80\t.\t+\t0\tID=stop1;Parent=geneA
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert_eq!(lines.len(), 4, "{gtf}");

        assert!(lines[1].contains("\tmRNA\t"), "{gtf}");
        assert!(lines[2].contains("\tstart_codon\t"), "{gtf}");
        assert!(lines[3].contains("\tstop_codon\t"), "{gtf}");
        assert!(
            lines[2].contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
        assert!(
            lines[3].contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
    }

    #[test]
    fn mixed_complete_and_incomplete_children_keep_parent_graph_consistent() {
        let gff = "\
chr1\tRefSeq\tgene\t10\t200\t.\t+\t.\tID=geneA
chr1\tRefSeq\tmRNA\t10\t100\t.\t+\t.\tID=tx1;Parent=geneA
chr1\tRefSeq\texon\t10\t100\t.\t+\t.\tID=exon1;Parent=tx1
chr1\tRefSeq\tCDS\t120\t180\t.\t+\t0\tID=cds1;Parent=geneA
";
        let gtf = convert(gff);
        let lines: Vec<&str> = gtf.lines().collect();
        assert_eq!(lines.len(), 6, "{gtf}");

        let synthetic = lines
            .iter()
            .find(|l| l.contains("\tmRNA\t") && l.contains("ID \"geneA\";"))
            .unwrap();
        assert!(
            synthetic.contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );

        let existing_tx = lines
            .iter()
            .find(|l| l.contains("\tmRNA\t") && l.contains("ID \"tx1\";"))
            .unwrap();
        assert!(
            existing_tx.contains("Parent \"agat-gene-1\";"),
            "existing transcript should point at the renamed gene: {gtf}"
        );

        let direct_cds = lines.iter().find(|l| l.contains("\tCDS\t")).unwrap();
        let synthetic_exon = lines
            .iter()
            .find(|l| l.contains("\texon\t") && l.contains("ID \"agat-exon-1\";"))
            .unwrap();
        assert!(
            synthetic_exon.contains("Parent \"geneA\";"),
            "synthetic exon should point at the synthetic transcript ID: {gtf}"
        );
        assert!(
            direct_cds.contains("gene_id \"agat-gene-1\"; transcript_id \"geneA\";"),
            "{gtf}"
        );
        assert!(
            direct_cds.contains("Parent \"geneA\";"),
            "direct CDS should point at the synthetic transcript ID: {gtf}"
        );
    }

    #[test]
    fn duplicate_transcript_structures_keep_lowest_transcript_id_like_agat() {
        let gff = "\
chr1\tFlyBase\tgene\t10\t90\t.\t+\t.\tID=gene:g1
chr1\tFlyBase\tmRNA\t10\t90\t.\t+\t.\tID=transcript:tx2;Parent=gene:g1
chr1\tFlyBase\texon\t10\t30\t.\t+\t.\tID=exon2a;Parent=transcript:tx2
chr1\tFlyBase\tCDS\t20\t30\t.\t+\t0\tID=cds2;Parent=transcript:tx2;protein_id=p2
chr1\tFlyBase\texon\t50\t90\t.\t+\t.\tID=exon2b;Parent=transcript:tx2
chr1\tFlyBase\tmRNA\t10\t90\t.\t+\t.\tID=transcript:tx1;Parent=gene:g1
chr1\tFlyBase\texon\t10\t30\t.\t+\t.\tID=exon1a;Parent=transcript:tx1
chr1\tFlyBase\tCDS\t20\t30\t.\t+\t0\tID=cds1;Parent=transcript:tx1;protein_id=p1
chr1\tFlyBase\texon\t50\t90\t.\t+\t.\tID=exon1b;Parent=transcript:tx1
";
        let gtf = convert(gff);

        assert!(gtf.contains("transcript_id \"tx1\";"), "{gtf}");
        assert!(!gtf.contains("transcript_id \"tx2\";"), "{gtf}");
        assert!(gtf.contains("protein_id \"p1\";"), "{gtf}");
        assert!(!gtf.contains("protein_id \"p2\";"), "{gtf}");
        assert_eq!(gtf.lines().count(), 5, "{gtf}");
    }

    #[test]
    fn duplicate_exon_only_transcript_structures_are_suppressed_like_agat() {
        let gff = "\
chr1\thavana\tgene\t10\t90\t.\t+\t.\tID=gene:g1
chr1\thavana\tlnc_RNA\t10\t90\t.\t+\t.\tID=transcript:tx2;Parent=gene:g1;biotype=retained_intron
chr1\thavana\texon\t10\t30\t.\t+\t.\tID=exon2a;Parent=transcript:tx2
chr1\thavana\texon\t50\t90\t.\t+\t.\tID=exon2b;Parent=transcript:tx2
chr1\thavana\tlnc_RNA\t10\t90\t.\t+\t.\tID=transcript:tx1;Parent=gene:g1;biotype=retained_intron
chr1\thavana\texon\t10\t30\t.\t+\t.\tID=exon1a;Parent=transcript:tx1
chr1\thavana\texon\t50\t90\t.\t+\t.\tID=exon1b;Parent=transcript:tx1
";
        let gtf = convert(gff);

        assert!(gtf.contains("transcript_id \"tx1\";"), "{gtf}");
        assert!(!gtf.contains("transcript_id \"tx2\";"), "{gtf}");
        assert_eq!(gtf.lines().count(), 4, "{gtf}");
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
