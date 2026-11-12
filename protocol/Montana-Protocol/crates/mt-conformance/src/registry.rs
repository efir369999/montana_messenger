// The Registry of mechanisms: an index over the set, held by comparison rather than by
// attention. The gate parses docs/Montana Registry.md and refuses a build in which a row and
// the set disagree — an anchor resolving to no heading, a domain owned twice or not at all,
// a derivation nobody owns, an awaited stage the plan does not carry, a vector name the set
// does not hold, or a count that does not recount.

pub const REGISTRY_RELATIVE: &str = "../../../docs/Montana Registry.md";
pub const PLAN_RELATIVE: &str = "../../ROADMAP.md";

pub const SET_DOCUMENTS: [(&str, &str); 7] = [
    ("Constitution", "../../../docs/Montana Constitution.md"),
    ("Canon", CANON_RELATIVE),
    ("Consensus", "../../../docs/Montana Consensus.md"),
    ("Value", "../../../docs/Montana Value.md"),
    ("Identity", "../../../docs/Montana Identity.md"),
    ("Network", "../../../docs/Montana Network.md"),
    ("App", "../../../docs/Montana App.md"),
];

pub const MECHANISM_PREFIXES: [&str; 6] = ["CNS", "VAL", "IDN", "NET", "APP", "CAN"];

pub struct MechanismRow {
    pub id: String,
    pub mechanism: String,
    pub anchors: Vec<(String, String)>,
    pub derivations: Vec<String>,
    pub domains: Vec<String>,
    pub proven: String,
    pub awaits: Vec<String>,
}

fn table_cells(line: &str, width: usize) -> Option<Vec<String>> {
    let t = line.trim();
    if !t.starts_with('|') || !t.ends_with('|') || t.len() < 2 {
        return None;
    }
    let cells: Vec<String> = t[1..t.len() - 1]
        .split('|')
        .map(|c| c.trim().to_string())
        .collect();
    if cells.len() == width {
        Some(cells)
    } else {
        None
    }
}

fn ticked_names(cell: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut inside = false;
    for part in cell.split('`') {
        if inside {
            out.push(part.to_string());
        }
        inside = !inside;
    }
    out
}

fn quoted_names(cell: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut inside = false;
    for part in cell.split('"') {
        if inside {
            out.push(part.to_string());
        }
        inside = !inside;
    }
    out
}

fn is_mechanism_id(cell: &str) -> bool {
    let Some((prefix, number)) = cell.split_once('-') else {
        return false;
    };
    MECHANISM_PREFIXES.contains(&prefix)
        && number.len() == 2
        && number.bytes().all(|b| b.is_ascii_digit())
}

fn parse_anchor(item: &str) -> Result<(String, String), String> {
    let item = item.trim();
    let doc = item
        .split_once(',')
        .map(|(d, _)| d.trim())
        .ok_or_else(|| format!("an anchor without a document: {item:?}"))?;
    let open = item
        .find('"')
        .ok_or_else(|| format!("an anchor without a heading: {item:?}"))?;
    let close = item
        .rfind('"')
        .filter(|c| *c > open)
        .ok_or_else(|| format!("an anchor with an unclosed heading: {item:?}"))?;
    Ok((doc.to_string(), item[open + 1..close].to_string()))
}

fn heading_stands(doc_md: &str, heading: &str) -> bool {
    doc_md.lines().any(|l| {
        let l = l.trim_end();
        ["## ", "### ", "#### "]
            .iter()
            .any(|p| l.strip_prefix(p) == Some(heading))
    })
}

pub fn derivation_tokens(canon: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in canon.lines() {
        let Some(rest) = line.strip_prefix("### `") else {
            continue;
        };
        if !rest.contains(" = ") {
            continue;
        }
        out.extend(ticked_names(&format!("`{rest}")));
    }
    out.sort();
    out.dedup();
    out
}

pub fn parse_mechanism_registry(registry: &str) -> Result<Vec<MechanismRow>, String> {
    let mut rows = Vec::new();
    for line in registry.lines() {
        let Some(cells) = table_cells(line, 7) else {
            continue;
        };
        if !is_mechanism_id(&cells[0]) {
            continue;
        }
        let anchors = cells[2]
            .split(';')
            .map(parse_anchor)
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("row {}: {e}", cells[0]))?;
        let awaits = if cells[6] == "—" {
            Vec::new()
        } else {
            cells[6].split(';').map(|t| t.trim().to_string()).collect()
        };
        rows.push(MechanismRow {
            id: cells[0].clone(),
            mechanism: cells[1].clone(),
            anchors,
            derivations: ticked_names(&cells[3]),
            domains: ticked_names(&cells[4]),
            proven: cells[5].clone(),
            awaits,
        });
    }
    if rows.is_empty() {
        return Err("the Registry parsed to no rows".to_string());
    }
    Ok(rows)
}

fn parse_counts(registry: &str) -> Result<(usize, usize, usize, usize), String> {
    let mut total = None;
    let mut closed = None;
    let mut staged = None;
    let mut artifact = None;
    for line in registry.lines() {
        let Some(cells) = table_cells(line, 2) else {
            continue;
        };
        let value = || -> Result<usize, String> {
            cells[1]
                .parse::<usize>()
                .map_err(|_| format!("a count that is not a number: {line:?}"))
        };
        match cells[0].as_str() {
            "rows" => total = Some(value()?),
            "closed — nothing awaited" => closed = Some(value()?),
            "awaiting a stage of the plan" => staged = Some(value()?),
            "awaiting the artifact `air_hash`" => artifact = Some(value()?),
            _ => {}
        }
    }
    match (total, closed, staged, artifact) {
        (Some(t), Some(c), Some(s), Some(a)) => Ok((t, c, s, a)),
        _ => Err("the counts table of the Registry is incomplete".to_string()),
    }
}

pub fn check_mechanism_registry(
    registry: &str,
    docs: &[(String, String)],
    canon: &str,
    plan: &str,
) -> Result<(), String> {
    let rows = parse_mechanism_registry(registry)?;

    let mut seen_ids: std::collections::BTreeSet<&str> = std::collections::BTreeSet::new();
    for row in &rows {
        if !seen_ids.insert(&row.id) {
            return Err(format!("the Registry gives the number {} twice", row.id));
        }
        if row.mechanism.is_empty() || row.proven.is_empty() {
            return Err(format!("row {} of the Registry has an empty cell", row.id));
        }
    }

    for row in &rows {
        for (doc, heading) in &row.anchors {
            let Some((_, md)) = docs.iter().find(|(name, _)| name == doc) else {
                return Err(format!(
                    "row {} anchors into a document the set does not hold: {doc}",
                    row.id
                ));
            };
            if !heading_stands(md, heading) {
                return Err(format!(
                    "row {} anchors at a heading {doc} does not carry: {heading:?}",
                    row.id
                ));
            }
        }
    }

    let registered = parse_registry(canon)?;
    let mut owner: std::collections::BTreeMap<&str, &str> = std::collections::BTreeMap::new();
    for row in &rows {
        for domain in &row.domains {
            if !registered.iter().any(|r| r == domain) {
                return Err(format!(
                    "row {} owns a domain the registry of separators does not hold: {domain}",
                    row.id
                ));
            }
            if let Some(prev) = owner.insert(domain, &row.id) {
                return Err(format!(
                    "the domain {domain} has two owners in the Registry: {prev} and {}",
                    row.id
                ));
            }
        }
    }
    for name in &registered {
        if !owner.contains_key(name.as_str()) {
            return Err(format!(
                "the domain {name} of the registry of separators has no owner in the Registry"
            ));
        }
    }

    let derived = derivation_tokens(canon);
    let mut derivation_owned: std::collections::BTreeSet<&str> = std::collections::BTreeSet::new();
    for row in &rows {
        for quantity in &row.derivations {
            if !derived.iter().any(|d| d == quantity) {
                return Err(format!(
                    "row {} names a derivation Canon does not derive: {quantity}",
                    row.id
                ));
            }
            derivation_owned.insert(quantity);
        }
    }
    for quantity in &derived {
        if !derivation_owned.contains(quantity.as_str()) {
            return Err(format!(
                "the derived quantity {quantity} has no owner in the Registry"
            ));
        }
    }

    for row in &rows {
        for token in &row.awaits {
            if token == "air_hash" {
                continue;
            }
            let Some(n) = token.strip_prefix("stage ") else {
                return Err(format!(
                    "row {} awaits something outside the vocabulary: {token:?}",
                    row.id
                ));
            };
            let heading = format!("## Stage {n} — ");
            if !plan.lines().any(|l| l.starts_with(&heading)) {
                return Err(format!(
                    "row {} awaits stage {n}, and the plan carries no such stage",
                    row.id
                ));
            }
        }
    }

    for row in &rows {
        for name in quoted_names(&row.proven) {
            if !canon.contains(&name) {
                return Err(format!(
                    "row {} cites a vector the set does not hold: {name:?}",
                    row.id
                ));
            }
        }
    }

    // The mirror of the two checks above, and the one they were missing. A domain without an owner
    // fails and a derived quantity without an owner fails — but a **section** without an owner used
    // to pass, so a normative mechanism could stand in the set with no row, no stage and nothing
    // that proves it, and nothing counted its absence. What a row cites is a heading, so what this
    // reads is the headings themselves.
    const CARRY_NO_MECHANISM: [&str; 3] = ["Scope", "Observability ledger", "Conformance set"];
    let anchored: std::collections::BTreeSet<(&str, &str)> = rows
        .iter()
        .flat_map(|row| {
            row.anchors
                .iter()
                .map(|(doc, heading)| (doc.as_str(), heading.as_str()))
        })
        .collect();
    for (doc, md) in docs {
        if !matches!(
            doc.as_str(),
            "Consensus" | "Value" | "Identity" | "Network" | "App"
        ) {
            continue;
        }
        // The three are exempt because the rule of the set has every document carry them rather
        // than hold them as mechanisms of its own. They are held against the documents and not
        // merely listed: a document that renamed one of them would otherwise gain an unowned
        // section in silence, which is the very thing this check exists to refuse.
        for carried in CARRY_NO_MECHANISM {
            if !md
                .lines()
                .any(|l| l.strip_prefix("## ").map(str::trim) == Some(carried))
            {
                return Err(format!(
                    "{doc} carries no section {carried:?}, which the rule of the set has every                      document carry"
                ));
            }
        }
        for line in md.lines() {
            let Some(heading) = line.strip_prefix("## ") else {
                continue;
            };
            let heading = heading.trim();
            if CARRY_NO_MECHANISM.contains(&heading) {
                continue;
            }
            if !anchored.contains(&(doc.as_str(), heading)) {
                return Err(format!(
                    "the section {doc}, {heading:?} has no row of the Registry: a mechanism nothing                      anchors has no stage and nothing that proves it"
                ));
            }
        }
    }

    let (total, closed, staged, artifact) = parse_counts(registry)?;
    let recount_closed = rows.iter().filter(|r| r.awaits.is_empty()).count();
    let recount_staged = rows
        .iter()
        .filter(|r| r.awaits.iter().any(|t| t.starts_with("stage ")))
        .count();
    let recount_artifact = rows
        .iter()
        .filter(|r| r.awaits.iter().any(|t| t == "air_hash"))
        .count();
    if (total, closed, staged, artifact)
        != (rows.len(), recount_closed, recount_staged, recount_artifact)
    {
        return Err(format!(
            "the counts of the Registry do not recount: stated {total}/{closed}/{staged}/{artifact}, counted {}/{recount_closed}/{recount_staged}/{recount_artifact}",
            rows.len()
        ));
    }
    Ok(())
}
