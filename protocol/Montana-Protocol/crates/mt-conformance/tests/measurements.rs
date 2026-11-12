// The numbers `AUDIT.md` states about this tree, held against the rules that compute them. A number
// of an audit taken by a reading of its author is a number nobody checks — and the day a stage adds
// a constant, a layout or a test, a ledger holding the old value says the tree is what it was.
//
// So the ledger is read here rather than restated: every row this test names is parsed out of
// `AUDIT.md` and compared with the one place that computes it. A row the ledger lost, a row whose
// value moved, and a measurement this test names and the ledger does not — each fails with both
// numbers named, which is the shape the gate holds the set in.
//
// What is verified rather than merely read is not counted here: the recorder that answers it is
// filled by the build script, which is where the coverage pass runs and where a frozen value no
// checker reads already fails the build.

// The ledger of this tree, beside the crate rather than in the set: what it measures is the tree.
fn ledger() -> String {
    std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../AUDIT.md"))
        .expect("the ledger stands beside this tree")
}

// The value a row of the measurements table states. A row is `| what | count |`, and what is taken
// is the leading number of the second cell — the rows that carry a sentence after the number carry
// it as prose, and the number is what this compares.
fn stated(md: &str, label: &str) -> Option<u64> {
    for line in md.lines() {
        let t = line.trim();
        if !t.starts_with('|') || !t.ends_with('|') {
            continue;
        }
        let cells: Vec<&str> = t.trim_matches('|').split('|').map(str::trim).collect();
        if cells.len() < 2 || cells[0] != label {
            continue;
        }
        let digits: String = cells[1]
            .chars()
            .take_while(|c| c.is_ascii_digit() || *c == ' ')
            .filter(|c| c.is_ascii_digit())
            .collect();
        return digits.parse::<u64>().ok();
    }
    None
}

#[test]
fn the_measurements_of_the_audit_are_the_ones_the_rules_compute() {
    let md = ledger();
    let mut wrong: Vec<String> = Vec::new();
    for (label, measure) in mt_conformance::MEASURED {
        let computed = measure().expect("the tree is readable") as u64;
        match stated(&md, label) {
            None => wrong.push(format!(
                "the ledger carries no row `{label}`, which this tree computes as {computed}"
            )),
            Some(held) if held != computed => wrong.push(format!(
                "`{label}`: the ledger states {held} and the tree holds {computed}"
            )),
            Some(_) => {}
        }
    }
    assert!(wrong.is_empty(), "{}", wrong.join("; "));
}

// The three counts of the Registry the ledger restates. The Registry recounts its own table on
// every build, so what this holds is the ledger against that recount rather than a second count of
// its own — a number stated twice is a number that parts the day one of them moves.
#[test]
fn the_counts_of_the_registry_the_ledger_restates_are_the_registry_s_own() {
    let md = ledger();
    let (rows, closed, staged, artifact) =
        mt_conformance::mechanism_counts().expect("the Registry is readable");
    let held = stated(&md, "rows of the Registry of mechanisms")
        .expect("the ledger states the rows of the Registry");
    assert_eq!(held, rows as u64, "the rows of the Registry");
    let line = md
        .lines()
        .find(|l| l.contains("rows of the Registry of mechanisms"))
        .expect("the row stands");
    for (what, value) in [
        ("closed", closed),
        ("awaiting a stage", staged),
        ("awaiting the artifact", artifact),
    ] {
        let expected = format!("{value} {what}");
        assert!(
            line.contains(&expected),
            "the ledger does not state `{expected}` where the Registry counts it: {line}"
        );
    }
}

// The two the build script already answers for, kept beside the rest so the ledger has one test and
// not two: the domains a run takes a preimage under stand in the coverage pass, and the frozen lines
// it reads are counted by that pass itself.
#[test]
fn the_coverage_the_ledger_states_is_the_coverage_the_pass_reads() {
    let canon = std::fs::read_to_string(mt_conformance::canon_path()).expect("the set is readable");
    let (read, _) = mt_conformance::coverage_counts(&canon).expect("the coverage counts");
    let md = ledger();
    let held = stated(
        &md,
        "frozen lines of the set of the shape the coverage pass reads",
    )
    .expect("the ledger states the frozen lines the pass reads");
    assert_eq!(
        held, read as u64,
        "the frozen lines the coverage pass reads"
    );
}
