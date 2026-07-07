//! Conservative GFF3 -> standardized GFF3 support.
//!
//! This is the first M3 slice: a reusable standardization-oriented writer plus
//! the AGAT-observed rules that are already safe to exercise with small
//! fixtures. Broader AGAT parser behavior belongs here as we add pinned parity
//! fixtures.

use crate::model::{Record, Strand};
use std::collections::{HashMap, HashSet};
use std::io::Write;

fn is_gene_like(feature_type: &str) -> bool {
    let t = feature_type.to_ascii_lowercase();
    t == "gene" || t.ends_with("_gene") || t == "pseudogene"
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

fn level1_category(feature_type: &str) -> u8 {
    match feature_type.to_ascii_lowercase().as_str() {
        "chromosome" | "contig" | "scaffold" | "supercontig" | "region" => 0,
        "biological_region" => 1,
        _ => 2,
    }
}

fn index_by_id(records: &[Record]) -> HashMap<&str, usize> {
    let mut m = HashMap::new();
    for (i, r) in records.iter().enumerate() {
        if let Some(id) = r.id() {
            m.entry(id).or_insert(i);
        }
    }
    m
}

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

#[derive(Clone)]
struct SyntheticTranscriptPlan {
    gene_id: String,
    transcript_id: String,
    feature_type: &'static str,
    template_child: usize,
}

#[derive(Clone)]
struct TransposableElementPlan {
    gene_id: String,
    rna_id: String,
    template_child: usize,
}

#[derive(Clone)]
struct OrphanTranscriptPlan {
    gene_id: String,
    transcript_id: String,
    feature_type: &'static str,
    template_child: usize,
    children: Vec<usize>,
    coords: (u64, u64),
}

struct Layout {
    children: Vec<Vec<usize>>,
    roots: Vec<usize>,
    coords: Vec<(u64, u64)>,
    skip_record: Vec<bool>,
    gene_id_override: Vec<Option<String>>,
    parent_override: Vec<Option<String>>,
    synthetic_tx: Vec<Option<SyntheticTranscriptPlan>>,
    te_plan: Vec<Option<TransposableElementPlan>>,
    orphan_plans: Vec<OrphanTranscriptPlan>,
    synthetic_exon_id: Vec<Option<String>>,
}

fn compute_layout(records: &[Record]) -> Layout {
    let n = records.len();
    let by_id = index_by_id(records);
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut roots = Vec::new();
    for (i, r) in records.iter().enumerate() {
        match r.parent().and_then(|p| by_id.get(p)) {
            Some(&p) if p != i => children[p].push(i),
            _ => roots.push(i),
        }
    }

    let mut used_ids: HashSet<String> = records
        .iter()
        .filter_map(|r| r.id().map(ToString::to_string))
        .collect();
    let mut counters: HashMap<String, usize> = HashMap::new();
    let mut gene_id_override = vec![None; n];
    let mut parent_override = vec![None; n];
    let mut synthetic_tx = vec![None; n];
    let mut te_plan = vec![None; n];
    let mut orphan_plans = Vec::new();
    let mut synthetic_exon_id = vec![None; n];
    let mut synthetic_exon_needed = vec![false; n];
    let mut skip_record = vec![false; n];
    let mut coords: Vec<(u64, u64)> = records.iter().map(|r| (r.start, r.end)).collect();

    let mut te_candidates = Vec::new();
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
        records[a_parent]
            .id()
            .unwrap_or("")
            .cmp(records[b_parent].id().unwrap_or(""))
            .then(
                records[a_te]
                    .id()
                    .unwrap_or("")
                    .cmp(records[b_te].id().unwrap_or("")),
            )
            .then(a_te.cmp(&b_te))
    });
    for (parent, te, template_child) in te_candidates {
        let gene_id = next_agat_id(&mut counters, &mut used_ids, "transposable_element");
        let Some(rna_id) = records[te].id().map(ToString::to_string) else {
            continue;
        };
        gene_id_override[te] = Some(gene_id.clone());
        te_plan[te] = Some(TransposableElementPlan {
            gene_id,
            rna_id,
            template_child,
        });
        skip_record[parent] = true;
    }

    let mut orphan_groups: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, record) in records.iter().enumerate() {
        if !needs_transcript_parent(&record.feature_type) {
            continue;
        }
        let Some(parent_id) = record.parent() else {
            continue;
        };
        if parent_id.is_empty() {
            continue;
        }
        match by_id.get(parent_id) {
            Some(&parent_idx) if parent_idx != i => {}
            _ => {
                orphan_groups
                    .entry(parent_id.to_string())
                    .or_default()
                    .push(i);
            }
        }
    }
    let mut orphan_candidates: Vec<(String, Vec<usize>)> = orphan_groups.into_iter().collect();
    orphan_candidates.sort_by(|(a_parent, a_children), (b_parent, b_children)| {
        orphan_group_rank(records, a_children)
            .cmp(&orphan_group_rank(records, b_children))
            .then(a_parent.cmp(b_parent))
    });
    for (parent_id, mut group_children) in orphan_candidates {
        group_children.sort_by(|&a, &b| {
            records[a]
                .start
                .cmp(&records[b].start)
                .then(records[a].end.cmp(&records[b].end))
                .then(type_rank(&records[a].feature_type).cmp(&type_rank(&records[b].feature_type)))
                .then(a.cmp(&b))
        });
        let gene_id = next_agat_id(&mut counters, &mut used_ids, "gene");
        let feature_type = if group_children
            .iter()
            .any(|&child| records[child].feature_type.eq_ignore_ascii_case("CDS"))
        {
            "mRNA"
        } else {
            "RNA"
        };
        let mut start = u64::MAX;
        let mut end = 0;
        for &child in &group_children {
            start = start.min(records[child].start);
            end = end.max(records[child].end);
            if records[child].id() == Some(parent_id.as_str()) {
                gene_id_override[child] = Some(next_agat_id(
                    &mut counters,
                    &mut used_ids,
                    &records[child].feature_type,
                ));
            }
            if !records[child].feature_type.eq_ignore_ascii_case("exon") {
                synthetic_exon_id[child] = Some(next_agat_id(&mut counters, &mut used_ids, "exon"));
            }
        }
        orphan_plans.push(OrphanTranscriptPlan {
            gene_id,
            transcript_id: parent_id,
            feature_type,
            template_child: group_children[0],
            children: group_children,
            coords: (start, end),
        });
    }
    orphan_plans.sort_by(|a, b| {
        records[a.template_child]
            .seqid
            .cmp(&records[b.template_child].seqid)
            .then(a.coords.0.cmp(&b.coords.0))
            .then(a.coords.1.cmp(&b.coords.1))
            .then(a.gene_id.cmp(&b.gene_id))
    });

    for parent in 0..n {
        if !is_gene_like(&records[parent].feature_type) {
            continue;
        }
        let Some(source_gene_id) = records[parent].id().map(ToString::to_string) else {
            continue;
        };
        let Some(&template_child) = children[parent]
            .iter()
            .find(|&&c| needs_transcript_parent(&records[c].feature_type))
        else {
            continue;
        };

        let new_gene_id = next_agat_id(&mut counters, &mut used_ids, &records[parent].feature_type);
        gene_id_override[parent] = Some(new_gene_id.clone());
        let has_direct_exon_child = children[parent]
            .iter()
            .any(|&child| records[child].feature_type.eq_ignore_ascii_case("exon"));
        synthetic_tx[parent] = Some(SyntheticTranscriptPlan {
            gene_id: new_gene_id.clone(),
            transcript_id: source_gene_id.clone(),
            feature_type: if records[template_child]
                .feature_type
                .eq_ignore_ascii_case("CDS")
            {
                "mRNA"
            } else {
                "RNA"
            },
            template_child,
        });

        for &child in &children[parent] {
            if needs_transcript_parent(&records[child].feature_type) {
                parent_override[child] = Some(source_gene_id.clone());
                if !has_direct_exon_child
                    && !records[child].feature_type.eq_ignore_ascii_case("exon")
                {
                    synthetic_exon_needed[child] = true;
                }
            } else if records[child].parent() == Some(source_gene_id.as_str()) {
                parent_override[child] = Some(new_gene_id.clone());
            }
        }
    }

    merge_adjacent_direct_cds(
        records,
        &children,
        &mut coords,
        &mut synthetic_exon_needed,
        &mut skip_record,
    );

    for child in 0..n {
        if synthetic_exon_needed[child] {
            synthetic_exon_id[child] = Some(next_agat_id(&mut counters, &mut used_ids, "exon"));
        }
    }
    promote_missing_child_ids(records, &mut used_ids, &mut gene_id_override);

    for kids in &mut children {
        kids.sort_by(|&a, &b| {
            type_rank(&records[a].feature_type)
                .cmp(&type_rank(&records[b].feature_type))
                .then(records[a].start.cmp(&records[b].start))
                .then(records[a].end.cmp(&records[b].end))
                .then(
                    records[a]
                        .id()
                        .unwrap_or("")
                        .cmp(records[b].id().unwrap_or("")),
                )
                .then(a.cmp(&b))
        });
    }

    let mut visiting = vec![false; n];
    let mut visited = vec![false; n];
    for i in 0..n {
        shrink_to_child_span(i, &children, &mut coords, &mut visiting, &mut visited);
    }

    roots.sort_by(|&a, &b| {
        records[a]
            .seqid
            .cmp(&records[b].seqid)
            .then(
                level1_category(&records[a].feature_type)
                    .cmp(&level1_category(&records[b].feature_type)),
            )
            .then(coords[a].0.cmp(&coords[b].0))
            .then(coords[a].1.cmp(&coords[b].1))
            .then(
                records[a]
                    .id()
                    .unwrap_or("")
                    .cmp(records[b].id().unwrap_or("")),
            )
            .then(a.cmp(&b))
    });

    Layout {
        children,
        roots,
        coords,
        skip_record,
        gene_id_override,
        parent_override,
        synthetic_tx,
        te_plan,
        orphan_plans,
        synthetic_exon_id,
    }
}

fn orphan_group_rank(records: &[Record], children: &[usize]) -> u8 {
    // AGAT assigns counters before final coordinate-sorted output. The observed
    // fixture order is CDS-backed orphan transcripts, then self-parent cycles,
    // then other missing-parent transcript groups.
    if children
        .iter()
        .any(|&child| records[child].feature_type.eq_ignore_ascii_case("CDS"))
    {
        0
    } else if children
        .iter()
        .any(|&child| records[child].id() == records[child].parent())
    {
        1
    } else {
        2
    }
}

fn promote_missing_child_ids(
    records: &[Record],
    used_ids: &mut HashSet<String>,
    id_override: &mut [Option<String>],
) {
    for (i, record) in records.iter().enumerate() {
        if record.id().is_some() || id_override[i].is_some() {
            continue;
        }
        if record.feature_type.eq_ignore_ascii_case("exon") {
            if let Some(exon_id) = record.attributes.get("exon_id") {
                if used_ids.insert(exon_id.to_string()) {
                    id_override[i] = Some(exon_id.to_string());
                }
            }
        }
    }
}

fn merge_adjacent_direct_cds(
    records: &[Record],
    children: &[Vec<usize>],
    coords: &mut [(u64, u64)],
    synthetic_exon_needed: &mut [bool],
    skip_record: &mut [bool],
) {
    for kids in children {
        let mut cds_children: Vec<usize> = kids
            .iter()
            .copied()
            .filter(|&child| {
                synthetic_exon_needed[child]
                    && records[child].feature_type.eq_ignore_ascii_case("CDS")
            })
            .collect();
        cds_children.sort_by(|&a, &b| {
            records[a]
                .id()
                .unwrap_or("")
                .cmp(records[b].id().unwrap_or(""))
                .then(records[a].start.cmp(&records[b].start))
                .then(records[a].end.cmp(&records[b].end))
                .then(a.cmp(&b))
        });

        let mut kept: Vec<usize> = Vec::new();
        for child in cds_children {
            if let Some(&last) = kept.last() {
                let same_group = same_direct_cds_group(&records[last], &records[child]);
                if same_group && records[child].start <= coords[last].1.saturating_add(1) {
                    coords[last].0 = coords[last].0.min(records[child].start);
                    coords[last].1 = coords[last].1.max(records[child].end);
                    synthetic_exon_needed[child] = false;
                    skip_record[child] = true;
                    continue;
                }
            }
            kept.push(child);
        }
    }
}

fn same_direct_cds_group(a: &Record, b: &Record) -> bool {
    a.seqid == b.seqid
        && a.strand == b.strand
        && a.id().is_some()
        && a.id() == b.id()
        && a.parent() == b.parent()
}

fn shrink_to_child_span(
    i: usize,
    children: &[Vec<usize>],
    coords: &mut [(u64, u64)],
    visiting: &mut [bool],
    visited: &mut [bool],
) -> (u64, u64) {
    if visited[i] {
        return coords[i];
    }
    if visiting[i] {
        return coords[i];
    }
    visiting[i] = true;
    if !children[i].is_empty() {
        let mut start = u64::MAX;
        let mut end = 0;
        for &child in &children[i] {
            let (child_start, child_end) =
                shrink_to_child_span(child, children, coords, visiting, visited);
            start = start.min(child_start);
            end = end.max(child_end);
        }
        if start != u64::MAX {
            coords[i] = (start, end);
        }
    }
    visiting[i] = false;
    visited[i] = true;
    coords[i]
}

/// Standardize GFF3 records and write GFF3.
pub fn gff3_to_gff3(records: &[Record], out: &mut impl Write) -> std::io::Result<()> {
    let layout = compute_layout(records);
    out.write_all(b"##gff-version 3\n")?;

    let mut emitted = vec![false; records.len()];
    for plan in &layout.orphan_plans {
        emit_orphan_plan(plan, records, &layout, &mut emitted, out)?;
    }
    for &root in &layout.roots {
        emit_tree(root, records, &layout, &mut emitted, out)?;
    }
    for i in 0..records.len() {
        if !emitted[i] {
            emit_tree(i, records, &layout, &mut emitted, out)?;
        }
    }
    Ok(())
}

fn emit_orphan_plan(
    plan: &OrphanTranscriptPlan,
    records: &[Record],
    layout: &Layout,
    emitted: &mut [bool],
    out: &mut impl Write,
) -> std::io::Result<()> {
    write_synthetic_gene(
        out,
        &records[plan.template_child],
        &plan.gene_id,
        plan.coords,
    )?;
    write_synthetic_orphan_transcript(out, &records[plan.template_child], plan)?;

    for &child in &plan.children {
        if let Some(exon_id) = &layout.synthetic_exon_id[child] {
            write_synthetic_exon(
                out,
                &records[child],
                exon_id,
                &plan.transcript_id,
                layout.coords[child],
            )?;
        }
    }
    for &child in &plan.children {
        emit_tree(child, records, layout, emitted, out)?;
    }
    Ok(())
}

fn emit_tree(
    i: usize,
    records: &[Record],
    layout: &Layout,
    emitted: &mut [bool],
    out: &mut impl Write,
) -> std::io::Result<()> {
    if layout.skip_record[i] {
        emitted[i] = true;
        return Ok(());
    }
    if emitted[i] {
        return Ok(());
    }
    emitted[i] = true;

    write_record_line(
        out,
        &records[i],
        layout.coords[i],
        layout.gene_id_override[i].as_deref(),
        layout.parent_override[i].as_deref(),
    )?;
    if let Some(plan) = &layout.synthetic_tx[i] {
        write_synthetic_transcript(
            out,
            &records[i],
            i,
            &records[plan.template_child],
            plan,
            layout,
        )?;
    }
    if let Some(plan) = &layout.te_plan[i] {
        write_synthetic_te_rna(
            out,
            &records[i],
            i,
            &records[plan.template_child],
            plan,
            layout,
        )?;
    }

    for &child in &layout.children[i] {
        if let Some(exon_id) = &layout.synthetic_exon_id[child] {
            let parent_id = layout.parent_override[child]
                .as_deref()
                .or_else(|| records[child].parent())
                .unwrap_or(planless_parent_fallback(&records[child]));
            write_synthetic_exon(
                out,
                &records[child],
                exon_id,
                parent_id,
                layout.coords[child],
            )?;
        }
    }

    for &child in &layout.children[i] {
        emit_tree(child, records, layout, emitted, out)?;
    }
    Ok(())
}

fn write_synthetic_gene(
    out: &mut impl Write,
    template: &Record,
    id: &str,
    coords: (u64, u64),
) -> std::io::Result<()> {
    writeln!(
        out,
        "{}\tAGAT\tgene\t{}\t{}\t{}\t{}\t.\tID={}",
        template.seqid,
        coords.0,
        coords.1,
        if template.score.is_empty() {
            "."
        } else {
            &template.score
        },
        strand_gff3(template.strand),
        id,
    )
}

fn write_synthetic_orphan_transcript(
    out: &mut impl Write,
    template: &Record,
    plan: &OrphanTranscriptPlan,
) -> std::io::Result<()> {
    write!(
        out,
        "{}\tAGAT\t{}\t{}\t{}\t{}\t{}\t.\t",
        template.seqid,
        plan.feature_type,
        plan.coords.0,
        plan.coords.1,
        if template.score.is_empty() {
            "."
        } else {
            &template.score
        },
        strand_gff3(template.strand),
    )?;
    write_synthetic_attrs(out, template, &plan.transcript_id, &plan.gene_id)
}

fn write_synthetic_te_rna(
    out: &mut impl Write,
    parent: &Record,
    parent_idx: usize,
    template: &Record,
    plan: &TransposableElementPlan,
    layout: &Layout,
) -> std::io::Result<()> {
    write!(
        out,
        "{}\tAGAT\tRNA\t{}\t{}\t{}\t{}\t.\t",
        parent.seqid,
        layout.coords[parent_idx].0,
        layout.coords[parent_idx].1,
        if parent.score.is_empty() {
            "."
        } else {
            &parent.score
        },
        strand_gff3(parent.strand),
    )?;
    write_synthetic_attrs(out, template, &plan.rna_id, &plan.gene_id)
}

fn planless_parent_fallback(record: &Record) -> &str {
    record.id().unwrap_or(".")
}

fn write_record_line(
    out: &mut impl Write,
    r: &Record,
    coords: (u64, u64),
    id_override: Option<&str>,
    parent_override: Option<&str>,
) -> std::io::Result<()> {
    write!(
        out,
        "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t",
        r.seqid,
        r.source,
        r.feature_type,
        coords.0,
        coords.1,
        if r.score.is_empty() { "." } else { &r.score },
        strand_gff3(r.strand),
        if r.phase.is_empty() { "." } else { &r.phase },
    )?;
    write_attrs(out, &r.attributes.pairs, id_override, parent_override)
}

fn write_synthetic_transcript(
    out: &mut impl Write,
    parent: &Record,
    parent_idx: usize,
    template: &Record,
    plan: &SyntheticTranscriptPlan,
    layout: &Layout,
) -> std::io::Result<()> {
    write!(
        out,
        "{}\tAGAT\t{}\t{}\t{}\t{}\t{}\t.\t",
        parent.seqid,
        plan.feature_type,
        layout.coords[parent_idx].0,
        layout.coords[parent_idx].1,
        if parent.score.is_empty() {
            "."
        } else {
            &parent.score
        },
        strand_gff3(parent.strand),
    )?;
    write_synthetic_attrs(out, template, &plan.transcript_id, &plan.gene_id)
}

fn write_synthetic_exon(
    out: &mut impl Write,
    template: &Record,
    exon_id: &str,
    parent_id: &str,
    coords: (u64, u64),
) -> std::io::Result<()> {
    write!(
        out,
        "{}\tAGAT\texon\t{}\t{}\t{}\t{}\t.\t",
        template.seqid,
        coords.0,
        coords.1,
        if template.score.is_empty() {
            "."
        } else {
            &template.score
        },
        strand_gff3(template.strand),
    )?;
    write_synthetic_attrs(out, template, exon_id, parent_id)
}

fn write_synthetic_attrs(
    out: &mut impl Write,
    template: &Record,
    id: &str,
    parent: &str,
) -> std::io::Result<()> {
    let mut pairs = Vec::with_capacity(template.attributes.pairs.len() + 2);
    pairs.push(("ID", id));
    pairs.push(("Parent", parent));
    for (k, v) in &template.attributes.pairs {
        if k == "ID" || k == "Parent" || k == "gene_id" || k == "transcript_id" {
            continue;
        }
        pairs.push((k.as_str(), v.as_str()));
    }
    write_raw_pairs(out, pairs)
}

fn write_attrs(
    out: &mut impl Write,
    source_pairs: &[(String, String)],
    id_override: Option<&str>,
    parent_override: Option<&str>,
) -> std::io::Result<()> {
    if source_pairs.is_empty() && id_override.is_none() && parent_override.is_none() {
        out.write_all(b".\n")?;
        return Ok(());
    }

    let mut pairs = Vec::with_capacity(source_pairs.len() + 2);
    if let Some(id) = id_override {
        pairs.push(("ID", id));
    }
    if let Some(parent) = parent_override {
        pairs.push(("Parent", parent));
    }
    for (k, v) in source_pairs {
        if id_override.is_some() && k == "ID" {
            continue;
        }
        if parent_override.is_some() && k == "Parent" {
            continue;
        }
        pairs.push((k.as_str(), v.as_str()));
    }
    write_raw_pairs(out, pairs)
}

fn write_raw_pairs(out: &mut impl Write, pairs: Vec<(&str, &str)>) -> std::io::Result<()> {
    let mut head = Vec::new();
    let mut rest = Vec::new();
    for pair in pairs {
        if pair.0 == "ID" || pair.0 == "Parent" {
            head.push(pair);
        } else {
            rest.push(pair);
        }
    }
    head.sort_by_key(|pair| if pair.0 == "ID" { 0 } else { 1 });
    rest.sort_by(|a, b| a.0.cmp(b.0));
    head.extend(rest);

    for (idx, (k, v)) in head.into_iter().enumerate() {
        if idx > 0 {
            out.write_all(b";")?;
        }
        write!(out, "{k}={v}")?;
    }
    out.write_all(b"\n")
}

fn strand_gff3(strand: Strand) -> &'static str {
    strand.as_str()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reader::read_all;
    use std::io::Cursor;

    fn standardize(gff: &str) -> String {
        let recs = read_all(Cursor::new(gff)).unwrap();
        let mut buf = Vec::new();
        gff3_to_gff3(&recs, &mut buf).unwrap();
        String::from_utf8(buf).unwrap()
    }

    #[test]
    fn complete_tree_is_written_as_standardized_gff3() {
        let gff = "\
chr1\tsrc\tgene\t1\t100\t.\t+\t.\tID=g1
chr1\tsrc\tmRNA\t1\t100\t.\t+\t.\tID=t1;Parent=g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tID=e1;Parent=t1
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tsrc\tgene\t1\t50\t.\t+\t.\tID=g1
chr1\tsrc\tmRNA\t1\t50\t.\t+\t.\tID=t1;Parent=g1
chr1\tsrc\texon\t1\t50\t.\t+\t.\tID=e1;Parent=t1
"
        );
    }

    #[test]
    fn direct_cds_gets_synthetic_transcript_and_exon() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t100\t.\t+\t.\tID=gene1;locus_tag=LT001
chr1\tRefSeq\tCDS\t10\t50\t.\t+\t0\tID=cds1;Parent=gene1;protein_id=p1;locus_tag=LT001
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t50\t.\t+\t.\tID=agat-gene-1;locus_tag=LT001
chr1\tAGAT\tmRNA\t10\t50\t.\t+\t.\tID=gene1;Parent=agat-gene-1;locus_tag=LT001;protein_id=p1
chr1\tAGAT\texon\t10\t50\t.\t+\t.\tID=agat-exon-1;Parent=gene1;locus_tag=LT001;protein_id=p1
chr1\tRefSeq\tCDS\t10\t50\t.\t+\t0\tID=cds1;Parent=gene1;locus_tag=LT001;protein_id=p1
"
        );
    }

    #[test]
    fn split_direct_cds_fragments_get_split_synthetic_exons() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t200\t.\t+\t.\tID=geneFrag;locus_tag=LTF
chr1\tRefSeq\tCDS\t10\t20\t.\t+\t0\tID=cdsFrag;Parent=geneFrag;protein_id=pFrag;locus_tag=LTF
chr1\tRefSeq\tCDS\t50\t70\t.\t+\t2\tID=cdsFrag;Parent=geneFrag;protein_id=pFrag;locus_tag=LTF
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t70\t.\t+\t.\tID=agat-gene-1;locus_tag=LTF
chr1\tAGAT\tmRNA\t10\t70\t.\t+\t.\tID=geneFrag;Parent=agat-gene-1;locus_tag=LTF;protein_id=pFrag
chr1\tAGAT\texon\t10\t20\t.\t+\t.\tID=agat-exon-1;Parent=geneFrag;locus_tag=LTF;protein_id=pFrag
chr1\tAGAT\texon\t50\t70\t.\t+\t.\tID=agat-exon-2;Parent=geneFrag;locus_tag=LTF;protein_id=pFrag
chr1\tRefSeq\tCDS\t10\t20\t.\t+\t0\tID=cdsFrag;Parent=geneFrag;locus_tag=LTF;protein_id=pFrag
chr1\tRefSeq\tCDS\t50\t70\t.\t+\t2\tID=cdsFrag;Parent=geneFrag;locus_tag=LTF;protein_id=pFrag
"
        );
    }

    #[test]
    fn adjacent_direct_cds_fragments_are_merged_like_agat() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t200\t.\t+\t.\tID=geneAdj;locus_tag=LTA
chr1\tRefSeq\tCDS\t10\t20\t.\t+\t0\tID=cdsAdj;Parent=geneAdj;protein_id=pAdj;locus_tag=LTA
chr1\tRefSeq\tCDS\t21\t40\t.\t+\t2\tID=cdsAdj;Parent=geneAdj;protein_id=pAdj;locus_tag=LTA
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t40\t.\t+\t.\tID=agat-gene-1;locus_tag=LTA
chr1\tAGAT\tmRNA\t10\t40\t.\t+\t.\tID=geneAdj;Parent=agat-gene-1;locus_tag=LTA;protein_id=pAdj
chr1\tAGAT\texon\t10\t40\t.\t+\t.\tID=agat-exon-1;Parent=geneAdj;locus_tag=LTA;protein_id=pAdj
chr1\tRefSeq\tCDS\t10\t40\t.\t+\t0\tID=cdsAdj;Parent=geneAdj;locus_tag=LTA;protein_id=pAdj
"
        );
    }

    #[test]
    fn transposable_element_gene_is_remodeled_like_agat() {
        let gff = "\
chr1\tFlyBase\ttransposable_element_gene\t10\t20\t.\t+\t.\tID=gene:B;Name=B;biotype=transposable_element;gene_id=B
chr1\tFlyBase\ttransposable_element\t10\t20\t.\t+\t.\tID=transcript:B-RA;Parent=gene:B;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=B-RA
chr1\tFlyBase\texon\t10\t20\t.\t+\t.\tParent=transcript:B-RA;Name=B-RA-E1;exon_id=B-RA-E1;rank=1
chr1\tFlyBase\ttransposable_element_gene\t30\t40\t.\t+\t.\tID=gene:A;Name=A;biotype=transposable_element;gene_id=A
chr1\tFlyBase\ttransposable_element\t30\t40\t.\t+\t.\tID=transcript:A-RA;Parent=gene:A;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=A-RA
chr1\tFlyBase\texon\t30\t40\t.\t+\t.\tParent=transcript:A-RA;Name=A-RA-E1;exon_id=A-RA-E1;rank=1
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tFlyBase\ttransposable_element\t10\t20\t.\t+\t.\tID=agat-transposable_element-2;Parent=gene:B;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=B-RA
chr1\tAGAT\tRNA\t10\t20\t.\t+\t.\tID=transcript:B-RA;Parent=agat-transposable_element-2;Name=B-RA-E1;exon_id=B-RA-E1;rank=1
chr1\tFlyBase\texon\t10\t20\t.\t+\t.\tID=B-RA-E1;Parent=transcript:B-RA;Name=B-RA-E1;exon_id=B-RA-E1;rank=1
chr1\tFlyBase\ttransposable_element\t30\t40\t.\t+\t.\tID=agat-transposable_element-1;Parent=gene:A;biotype=transposable_element;tag=Ensembl_canonical;transcript_id=A-RA
chr1\tAGAT\tRNA\t30\t40\t.\t+\t.\tID=transcript:A-RA;Parent=agat-transposable_element-1;Name=A-RA-E1;exon_id=A-RA-E1;rank=1
chr1\tFlyBase\texon\t30\t40\t.\t+\t.\tID=A-RA-E1;Parent=transcript:A-RA;Name=A-RA-E1;exon_id=A-RA-E1;rank=1
"
        );
    }

    #[test]
    fn orphan_exon_gets_synthetic_gene_and_rna_like_agat() {
        let gff = "\
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=e_orphan;Parent=missing
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tAGAT\tgene\t10\t20\t.\t+\t.\tID=agat-gene-1
chr1\tAGAT\tRNA\t10\t20\t.\t+\t.\tID=missing;Parent=agat-gene-1
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=e_orphan;Parent=missing
"
        );
    }

    #[test]
    fn orphan_cds_gets_synthetic_gene_mrna_and_exon_like_agat() {
        let gff = "\
chr1\tsrc\tCDS\t10\t20\t.\t+\t0\tID=cds_orphan;Parent=missing
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tAGAT\tgene\t10\t20\t.\t+\t.\tID=agat-gene-1
chr1\tAGAT\tmRNA\t10\t20\t.\t+\t.\tID=missing;Parent=agat-gene-1
chr1\tAGAT\texon\t10\t20\t.\t+\t.\tID=agat-exon-1;Parent=missing
chr1\tsrc\tCDS\t10\t20\t.\t+\t0\tID=cds_orphan;Parent=missing
"
        );
    }

    #[test]
    fn self_parent_exon_renames_child_id_like_agat() {
        let gff = "\
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=e_self;Parent=e_self
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tAGAT\tgene\t10\t20\t.\t+\t.\tID=agat-gene-1
chr1\tAGAT\tRNA\t10\t20\t.\t+\t.\tID=e_self;Parent=agat-gene-1
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=agat-exon-1;Parent=e_self
"
        );
    }

    #[test]
    fn orphan_counter_order_is_separate_from_output_order_like_agat() {
        let gff = "\
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=e_orphan;Parent=missing_exon
chr1\tsrc\tCDS\t30\t40\t.\t+\t0\tID=cds_orphan;Parent=missing_cds
chr1\tsrc\texon\t50\t60\t.\t+\t.\tID=e_self;Parent=e_self
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tAGAT\tgene\t10\t20\t.\t+\t.\tID=agat-gene-3
chr1\tAGAT\tRNA\t10\t20\t.\t+\t.\tID=missing_exon;Parent=agat-gene-3
chr1\tsrc\texon\t10\t20\t.\t+\t.\tID=e_orphan;Parent=missing_exon
chr1\tAGAT\tgene\t30\t40\t.\t+\t.\tID=agat-gene-1
chr1\tAGAT\tmRNA\t30\t40\t.\t+\t.\tID=missing_cds;Parent=agat-gene-1
chr1\tAGAT\texon\t30\t40\t.\t+\t.\tID=agat-exon-1;Parent=missing_cds
chr1\tsrc\tCDS\t30\t40\t.\t+\t0\tID=cds_orphan;Parent=missing_cds
chr1\tAGAT\tgene\t50\t60\t.\t+\t.\tID=agat-gene-2
chr1\tAGAT\tRNA\t50\t60\t.\t+\t.\tID=e_self;Parent=agat-gene-2
chr1\tsrc\texon\t50\t60\t.\t+\t.\tID=agat-exon-2;Parent=e_self
"
        );
    }

    #[test]
    fn direct_exon_gets_synthetic_rna_like_agat() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t100\t.\t+\t.\tID=gene2;locus_tag=LT003
chr1\tRefSeq\texon\t10\t40\t.\t+\t.\tID=ex1;Parent=gene2;locus_tag=LT003
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t40\t.\t+\t.\tID=agat-gene-1;locus_tag=LT003
chr1\tAGAT\tRNA\t10\t40\t.\t+\t.\tID=gene2;Parent=agat-gene-1;locus_tag=LT003
chr1\tRefSeq\texon\t10\t40\t.\t+\t.\tID=ex1;Parent=gene2;locus_tag=LT003
"
        );
    }

    #[test]
    fn direct_utr_children_get_synthetic_exons_without_natural_exon() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t100\t.\t+\t.\tID=geneU;locus_tag=LTU
chr1\tRefSeq\tfive_prime_UTR\t10\t20\t.\t+\t.\tID=utr5;Parent=geneU;locus_tag=LTU
chr1\tRefSeq\tthree_prime_UTR\t80\t90\t.\t+\t.\tID=utr3;Parent=geneU;locus_tag=LTU
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=agat-gene-1;locus_tag=LTU
chr1\tAGAT\tRNA\t10\t90\t.\t+\t.\tID=geneU;Parent=agat-gene-1;locus_tag=LTU
chr1\tAGAT\texon\t10\t20\t.\t+\t.\tID=agat-exon-1;Parent=geneU;locus_tag=LTU
chr1\tAGAT\texon\t80\t90\t.\t+\t.\tID=agat-exon-2;Parent=geneU;locus_tag=LTU
chr1\tRefSeq\tfive_prime_UTR\t10\t20\t.\t+\t.\tID=utr5;Parent=geneU;locus_tag=LTU
chr1\tRefSeq\tthree_prime_UTR\t80\t90\t.\t+\t.\tID=utr3;Parent=geneU;locus_tag=LTU
"
        );
    }

    #[test]
    fn direct_codon_children_get_synthetic_exons_without_natural_exon() {
        let gff = "\
chr1\tRefSeq\tgene\t1\t100\t.\t+\t.\tID=geneC;locus_tag=LTC
chr1\tRefSeq\tstart_codon\t10\t12\t.\t+\t0\tID=start1;Parent=geneC;locus_tag=LTC
chr1\tRefSeq\tstop_codon\t88\t90\t.\t+\t0\tID=stop1;Parent=geneC;locus_tag=LTC
";
        let out = standardize(gff);
        assert_eq!(
            out,
            "\
##gff-version 3
chr1\tRefSeq\tgene\t10\t90\t.\t+\t.\tID=agat-gene-1;locus_tag=LTC
chr1\tAGAT\tRNA\t10\t90\t.\t+\t.\tID=geneC;Parent=agat-gene-1;locus_tag=LTC
chr1\tAGAT\texon\t10\t12\t.\t+\t.\tID=agat-exon-1;Parent=geneC;locus_tag=LTC
chr1\tAGAT\texon\t88\t90\t.\t+\t.\tID=agat-exon-2;Parent=geneC;locus_tag=LTC
chr1\tRefSeq\tstart_codon\t10\t12\t.\t+\t0\tID=start1;Parent=geneC;locus_tag=LTC
chr1\tRefSeq\tstop_codon\t88\t90\t.\t+\t0\tID=stop1;Parent=geneC;locus_tag=LTC
"
        );
    }
}
