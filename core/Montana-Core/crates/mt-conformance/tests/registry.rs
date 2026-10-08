use mt_conformance::*;

fn read(p: std::path::PathBuf) -> String {
    std::fs::read_to_string(&p).unwrap_or_else(|e| panic!("readable at {}: {e}", p.display()))
}

fn material() -> (String, Vec<(String, String)>, String, String) {
    let registry = read(registry_path());
    let docs: Vec<(String, String)> = set_document_paths()
        .into_iter()
        .map(|(name, path)| (name, read(path)))
        .collect();
    let canon = read(canon_path());
    let plan = read(plan_path());
    (registry, docs, canon, plan)
}

#[test]
fn the_registry_and_the_set_agree() {
    let (registry, docs, canon, plan) = material();
    check_mechanism_registry(&registry, &docs, &canon, &plan).expect("no divergence");
}

#[test]
fn every_row_holds_an_id_a_mechanism_and_an_anchor() {
    let (registry, ..) = material();
    let rows = parse_mechanism_registry(&registry).expect("the Registry parses");
    for row in &rows {
        assert!(!row.anchors.is_empty(), "{} anchors nowhere", row.id);
    }
}

#[test]
fn a_renamed_heading_breaks_the_build_naming_the_row() {
    let (registry, mut docs, canon, plan) = material();
    let consensus = docs
        .iter_mut()
        .find(|(name, _)| name == "Consensus")
        .expect("the set holds Consensus");
    consensus.1 = consensus.1.replace("## The TimeChain", "## The TimeChains");
    let err = check_mechanism_registry(&registry, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("CNS-01"), "{err}");
}

#[test]
fn a_domain_moved_between_rows_is_refused_twice_over() {
    let (registry, docs, canon, plan) = material();
    let doctored = registry.replace("| `mt-slot` |", "| `mt-tag` |");
    assert_ne!(registry, doctored, "the doctoring must land");
    let err = check_mechanism_registry(&doctored, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("mt-tag") || err.contains("mt-slot"), "{err}");
}

#[test]
fn a_count_that_does_not_recount_is_refused_with_both_countings() {
    let (registry, docs, canon, plan) = material();
    // The count is read out of the Registry and then moved, rather than written here: a number of
    // its own would be a second place the count lives, and the day the table grows this test would
    // doctor nothing and pass over the very thing it exists to catch.
    let stated = registry
        .lines()
        .find_map(|line| line.strip_prefix("| rows | ")?.strip_suffix(" |"))
        .and_then(|value| value.trim().parse::<usize>().ok())
        .expect("the Registry states its count of rows");
    let doctored = registry.replace(
        &format!("| rows | {stated} |"),
        &format!("| rows | {} |", stated + 1),
    );
    assert_ne!(registry, doctored, "the doctoring must land");
    let err = check_mechanism_registry(&doctored, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("recount"), "{err}");
}

#[test]
fn a_stage_the_plan_does_not_carry_is_refused() {
    let (registry, docs, canon, plan) = material();
    let doctored = registry.replace("stage 21", "stage 42");
    assert_ne!(registry, doctored, "the doctoring must land");
    let err = check_mechanism_registry(&doctored, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("stage 42"), "{err}");
}

#[test]
fn a_cited_vector_the_set_does_not_hold_is_refused() {
    let (registry, docs, canon, plan) = material();
    let doctored = registry.replace(
        "\"A proposal, and its length\"",
        "\"A proposal, and its width\"",
    );
    assert_ne!(registry, doctored, "the doctoring must land");
    let err = check_mechanism_registry(&doctored, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("width"), "{err}");
}

#[test]
fn an_unowned_derivation_is_refused_by_name() {
    let (registry, docs, canon, plan) = material();
    let doctored = registry.replace("`target_rounds`", "—");
    assert_ne!(registry, doctored, "the doctoring must land");
    let err = check_mechanism_registry(&doctored, &docs, &canon, &plan)
        .expect_err("the gate must refuse");
    assert!(err.contains("target_rounds"), "{err}");
}
