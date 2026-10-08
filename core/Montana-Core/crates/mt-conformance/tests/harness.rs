use mt_conformance::*;

fn canon() -> String {
    std::fs::read_to_string(canon_path()).expect("the set is readable")
}

// The full line of a Decree or registry row, found by its backticked name. Tests doctor what
// they read out of the set rather than restating it, so no value of the Decree lives here.
fn row_line(md: &str, name: &str) -> String {
    let prefix = format!("| `{name}`");
    md.lines()
        .find(|line| line.trim_start().starts_with(&prefix))
        .unwrap_or_else(|| panic!("the set holds a row `{name}`"))
        .to_string()
}

// Byte offsets of the value cell of a row: between its second and third pipe.
fn value_cell_span(line: &str) -> (usize, usize) {
    let mut pipes = line
        .char_indices()
        .filter(|(_, c)| *c == '|')
        .map(|(i, _)| i);
    pipes.next().expect("a row opens with a pipe");
    let second = pipes.next().expect("a row has a name cell");
    let third = pipes.next().expect("a row has a value cell");
    (second + 1, third)
}

// Bumps the last number of the value cell by one, returning the doctored line and both
// values. A number may carry inner spaces, as the set writes large values.
fn bump_last_number(line: &str) -> (String, u64, u64) {
    let (a, b) = value_cell_span(line);
    let cell = &line[a..b];
    let bytes = cell.as_bytes();
    let mut last: Option<(usize, usize)> = None;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let start = i;
            let mut end = i + 1;
            let mut j = i + 1;
            while j < bytes.len() {
                if bytes[j].is_ascii_digit() {
                    end = j + 1;
                    j += 1;
                } else if bytes[j] == b' ' && j + 1 < bytes.len() && bytes[j + 1].is_ascii_digit() {
                    j += 1;
                } else {
                    break;
                }
            }
            last = Some((start, end));
            i = end;
        } else {
            i += 1;
        }
    }
    let (s, e) = last.expect("the value cell holds a number");
    let old: u64 = cell[s..e]
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .expect("digits parse");
    let new = old + 1;
    let doctored = format!("{}{}{}", &line[..a + s], new, &line[a + e..]);
    (doctored, old, new)
}

fn doctored_canon(md: &str, from: &str, to: &str) -> String {
    let out = md.replacen(from, to, 1);
    assert_ne!(out, md, "the mutation must land");
    out
}

// The full 64-character value the set states, found by its opening bytes: a test reads a frozen
// value out of the set rather than restating it.
fn hex_of(md: &str, opening: &str) -> String {
    let at = md
        .find(opening)
        .unwrap_or_else(|| panic!("the set holds a value opening with {opening}"));
    md[at..at + 64].to_string()
}

// A large number as the set writes it, in groups of three digits separated by spaces.
fn with_spaces(value: u32) -> String {
    let digits = value.to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(' ');
        }
        out.push(c);
    }
    out
}

// The total a layout states, as the set writes it, found by the name that opens its line. A line
// whose tail is an arithmetic rather than a number is passed over: the same name opens both.
fn total_as_written(md: &str, name: &str) -> String {
    md.lines()
        .filter_map(|line| {
            if !line.trim_start().starts_with(name) {
                return None;
            }
            let at = line.find('=')?;
            let tail = line[at + 1..].trim().trim_end_matches('B').trim();
            let numeric = !tail.is_empty() && tail.chars().all(|c| c.is_ascii_digit() || c == ' ');
            numeric.then(|| tail.to_string())
        })
        .next()
        .unwrap_or_else(|| panic!("the set states a total for {name}"))
}

fn digits_of(written: &str) -> u32 {
    written
        .chars()
        .filter(char::is_ascii_digit)
        .collect::<String>()
        .parse()
        .expect("a total is a number")
}

// The value that follows a label, read out of the set: sixty-four hexadecimal characters.
fn hex_after(md: &str, label: &str) -> String {
    let at = md
        .find(label)
        .unwrap_or_else(|| panic!("the set holds a label {label}"));
    md[at + label.len()..at + label.len() + 64].to_string()
}

fn flip_first_hex(hex: &str) -> String {
    let mut chars: Vec<char> = hex.chars().collect();
    chars[0] = if chars[0] == '0' { '1' } else { '0' };
    chars.into_iter().collect()
}

#[test]
fn the_set_and_the_code_agree() {
    check_all(&canon()).expect("no divergence");
}

#[test]
fn the_decree_parses_to_what_the_code_holds_row_by_row() {
    let md = canon();
    let rows = parse_decree(&md).expect("the parameters parse");
    assert_eq!(rows.len(), mt_genesis::PARAMETERS.len());
    let forms = parse_forms(&md).expect("the forms parse");
    assert_eq!(forms.len(), mt_genesis::FORMS.len());
    // A row is found by its name and never by its place: the order of the Decree is compared
    // row by row by the gate itself, and a test pinning the first place would move with it.
    let tau2 = rows
        .iter()
        .find(|row| row.name == "tau2")
        .expect("the Decree names the period");
    assert_eq!(tau2.value, ParsedValue::Scalar(mt_genesis::TAU2));
}

#[test]
fn the_registry_parses_to_the_code_registry() {
    let names = parse_registry(&canon()).expect("the registry parses");
    assert_eq!(names.len(), mt_codec::domain::REGISTRY.len());
    assert_eq!(names[0], "mt-op");
}

#[test]
fn a_changed_decree_value_breaks_the_build_with_both_values() {
    let md = canon();
    let line = row_line(&md, "selection_interval");
    let (doctored, old, new) = bump_last_number(&line);
    assert_eq!(Some(old), mt_genesis::scalar("selection_interval"));
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("selection_interval"), "{err}");
    assert!(err.contains(&old.to_string()), "{err}");
    assert!(err.contains(&new.to_string()), "{err}");
}

#[test]
fn a_changed_tau2_reference_breaks_the_build() {
    let md = canon();
    let line = row_line(&md, "membership_term");
    let (doctored, _, _) = bump_last_number(&line);
    let resolved = mt_genesis::scalar("membership_term").expect("the Decree names it");
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("membership_term"), "{err}");
    assert!(err.contains(&resolved.to_string()), "{err}");
    assert!(
        err.contains(&(resolved + mt_genesis::TAU2).to_string()),
        "{err}"
    );
}

#[test]
fn a_changed_ratio_breaks_the_build_with_both_ratios() {
    let md = canon();
    let line = row_line(&md, "confirmation_quorum_num");
    let (doctored, old_den, new_den) = bump_last_number(&line);
    let (_, den) = mt_genesis::ratio("confirmation_quorum").expect("the Decree names it");
    assert_eq!(old_den, den);
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("confirmation_quorum"), "{err}");
    assert!(err.contains(&old_den.to_string()), "{err}");
    assert!(err.contains(&new_den.to_string()), "{err}");
}

#[test]
fn a_changed_emission_row_breaks_the_build_with_both_schedules() {
    let md = canon();
    let line = row_line(&md, "emission_schedule");
    let (doctored, old_mint, new_mint) = bump_last_number(&line);
    let Some(mt_genesis::Entry::Schedule(_, rows)) = mt_genesis::get("emission_schedule") else {
        panic!("the Decree holds the schedule");
    };
    assert_eq!(old_mint, rows[0].1);
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("emission_schedule"), "{err}");
    assert!(err.contains(&old_mint.to_string()), "{err}");
    assert!(err.contains(&new_mint.to_string()), "{err}");
}

#[test]
fn reordered_decree_rows_break_the_build_with_both_names() {
    let md = canon();
    let first = row_line(&md, "slot_modulus");
    let second = row_line(&md, "retarget_period");
    let block = format!("{first}\n{second}");
    let swapped = format!("{second}\n{first}");
    let err = check_all(&doctored_canon(&md, &block, &swapped)).expect_err("the gate must refuse");
    assert!(err.contains("slot_modulus"), "{err}");
    assert!(err.contains("retarget_period"), "{err}");
}

#[test]
fn a_renamed_domain_breaks_the_build_with_both_names() {
    let md = canon();
    let line = row_line(&md, "mt-ticket");
    let doctored = line.replacen("mt-ticket", "mt-tickets", 1);
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("mt-tickets"), "{err}");
    assert!(err.contains("mt-ticket"), "{err}");
}

#[test]
fn a_missing_registry_row_is_refused_rather_than_absorbed() {
    let md = canon();
    let line = row_line(&md, "mt-app-encryption-key");
    let with_newline = format!("{line}\n");
    let err = check_all(&doctored_canon(&md, &with_newline, "")).expect_err("the gate must refuse");
    assert!(err.contains("mt-app-encryption-key"), "{err}");
}

#[test]
fn a_changed_vector_breaks_the_build_with_both_values() {
    let md = canon();
    let vectors = parse_primitive_vectors(&md).expect("the vectors parse");
    let original = vectors[0].expected_hex.clone();
    let flipped = flip_first_hex(&original);
    let err =
        check_all(&doctored_canon(&md, &original, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains(&vectors[0].domain), "{err}");
    assert!(err.contains(&original), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_row_of_the_wrong_kind_is_refused() {
    let md = canon();
    let (num, _) = mt_genesis::ratio("confirmation_quorum").expect("the Decree names it");
    let line = row_line(&md, "confirmation_quorum_num");
    let doctored = format!("| `confirmation_quorum` | {num} |");
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("confirmation_quorum"), "{err}");
    assert!(err.contains("different kinds"), "{err}");
}

#[test]
fn a_value_written_in_place_of_an_unpublished_parameter_is_refused() {
    // The one parameter the set has not published carries no value of any kind. A set that wrote
    // one — a stand-in of zeros as much as a real-looking digest — is a set the code no longer
    // transcribes, and the gate says so rather than computing over it.
    let md = canon();
    let line = row_line(&md, "air_hash");
    for written in [
        "00".repeat(32),
        "ab".repeat(32),
        "the stand-in of thirty-two zero bytes".into(),
    ] {
        let doctored = format!("| `air_hash` | {written} |");
        let err =
            check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
        assert!(err.contains("air_hash"), "{err}");
    }
}

#[test]
fn a_moved_genesis_state_hash_breaks_the_build_with_both_values() {
    // The Decree is complete and the value stands; what the gate must refuse now is a set whose
    // stated hash is not the one the frozen procedure yields — the day\'s symmetric of the old
    // refusal to freeze a number over a parameter that did not exist.
    let md = canon();
    let stated = parse_genesis_state_hash(&md)
        .expect("the block parses")
        .expect("the set states the value");
    let flipped = flip_first_hex(&stated);
    let err = check_all(&doctored_canon(&md, &stated, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("genesis_state_hash"), "{err}");
    assert!(err.contains(&stated) || err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_digest_of_the_published_parameters_breaks_the_build_with_both_values() {
    let md = canon();
    let stated = parse_published_parameters(&md).expect("the set holds it");
    let flipped = flip_first_hex(&stated);
    let err = check_all(&doctored_canon(&md, &stated, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("published_parameters"), "{err}");
    assert!(err.contains(&stated), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn the_objects_of_the_stage_agree_with_the_set() {
    let md = canon();
    check_sizes(&md).expect("no divergence of a size");
    check_layouts(&md).expect("no divergence of a layout");
    check_derivations(&md).expect("no divergence of a derivation");
}

#[test]
fn a_changed_value_of_any_derivation_breaks_the_build_with_both_values() {
    // Every frozen value of every block this stage owns is walked, and each is flipped in turn.
    let md = canon();
    let blocks = [
        NOTE_HEADER,
        RATES_HEADER,
        TAG_HEADER,
        LOOKUP_HEADER,
        NAME_HEADER,
        CHANNEL_HEADER,
        CONTACT_HEADER,
        MACHINE_HEADER,
        PART_HEADER,
        SEAL_HEADER,
        TWO_SPACES_HEADER,
    ];
    let mut walked = 0;
    for header in blocks {
        let rows = parse_labeled(&md, header).unwrap_or_else(|e| panic!("{header}: {e}"));
        for (label, stated) in rows {
            let hexish = (stated.len() == 64 || stated.len() == 32)
                && stated.bytes().all(|b| b.is_ascii_hexdigit());
            if !hexish {
                continue;
            }
            // A value the set states twice — the tag of first contact is also the tag whose
            // holder the ring vector names — would be doctored at its first standing, which is
            // not the one this block owns. Those are walked where they are checked instead.
            if md.matches(stated.as_str()).count() != 1 {
                continue;
            }
            walked += 1;
            let flipped = flip_first_hex(&stated);
            let err = check_all(&doctored_canon(&md, &stated, &flipped))
                .expect_err("the gate must refuse a changed value");
            assert!(err.contains(&stated), "{label}: {err}");
            assert!(err.contains(&flipped), "{label}: {err}");
        }
    }
    assert!(
        walked >= 25,
        "the blocks hold {walked} frozen values, which is too few"
    );
}

#[test]
fn a_changed_fingerprint_or_its_count_of_iterations_breaks_the_build() {
    let md = canon();
    // Both values are read out of the set and doctored where they stand: a test restating one
    // would be the second place for a number whose one place is the set, and the two would part
    // the first time the number moved.
    let stated = value_after(&md, "fingerprint  = ");
    let flipped = bump_last_number_of(&stated).0;
    let err = check_all(&doctored_canon(&md, &stated, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("fingerprint"), "{err}");
    assert!(err.contains(&stated), "{err}");

    let iterations = md
        .lines()
        .find(|line| line.contains("identity key") && line.contains("iterations ="))
        .expect("the set states the count of iterations of the fingerprint")
        .trim()
        .to_string();
    let (moved, _, changed) = bump_last_number_of(&iterations);
    let err =
        check_all(&doctored_canon(&md, &iterations, &moved)).expect_err("the gate must refuse");
    assert!(err.contains("iterations"), "{err}");
    assert!(err.contains(&changed), "{err}");
}

// The value a label carries, read where the set writes it.
fn value_after(md: &str, label: &str) -> String {
    let at = md
        .find(label)
        .unwrap_or_else(|| panic!("the set writes {label:?}"));
    md[at + label.len()..]
        .lines()
        .next()
        .expect("a label carries a value")
        .trim()
        .to_string()
}

// The same text with the last digit of its last number moved, and both numbers beside it as the
// gate spells them. The digit is moved rather than the number parsed, because a value of the set
// may be wider than any integer this tree holds — a fingerprint is thirty digits.
fn bump_last_number_of(text: &str) -> (String, String, String) {
    let bytes = text.as_bytes();
    let mut last: Option<(usize, usize)> = None;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let start = i;
            let mut end = i + 1;
            while end < bytes.len() && (bytes[end].is_ascii_digit() || bytes[end] == b' ') {
                end += 1;
            }
            while end > start && bytes[end - 1] == b' ' {
                end -= 1;
            }
            last = Some((start, end));
            i = end;
        } else {
            i += 1;
        }
    }
    let (start, end) = last.expect("the text carries a number");
    let stated = &text[start..end];
    let mut digits: Vec<char> = stated.chars().collect();
    let at = digits.len() - 1;
    digits[at] = if digits[at] == '9' {
        '8'
    } else {
        char::from(digits[at] as u8 + 1)
    };
    let moved: String = digits.into_iter().collect();
    let text_moved = format!("{}{}{}", &text[..start], moved, &text[end..]);
    (text_moved, stated.replace(' ', ""), moved.replace(' ', ""))
}

#[test]
fn a_changed_length_of_a_layout_breaks_the_build_with_both_lengths() {
    let md = canon();
    // The set states this total twice — as the arithmetic of the layout and as the length of the
    // frozen serialization — and the gate reads both, so either one moving fails the build. Both
    // the total and the places it stands are read out of the set: a test that restated the number
    // would have to be edited every time the set moves, which is the drift it exists to catch.
    let written = total_as_written(&md, "proposal_len");
    let bumped = with_spaces(digits_of(&written) + 1);
    let holding: Vec<String> = md
        .lines()
        .filter(|line| line.contains(&written))
        .map(str::to_string)
        .collect();
    assert!(
        holding.len() >= 2,
        "the set states the length of a proposal in fewer than two places: {holding:?}"
    );
    for line in holding {
        let doctored = line.replace(&written, &bumped);
        let err =
            check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
        let bare = |v: &str| v.replace(' ', "");
        assert!(
            err.contains(&bare(&written)) || err.contains(&written),
            "{err}"
        );
        assert!(
            err.contains(&bare(&bumped)) || err.contains(&bumped),
            "{err}"
        );
    }
}

#[test]
fn a_changed_serialization_of_a_layout_breaks_the_build_with_both_values() {
    let md = canon();
    for stated in [
        hex_after(&md, "SHA-256 of the serialized proposal = "),
        hex_after(&md, "SHA-256 of the serialized frame = "),
    ] {
        let flipped = flip_first_hex(&stated);
        let err =
            check_all(&doctored_canon(&md, &stated, &flipped)).expect_err("the gate must refuse");
        assert!(err.contains(&stated), "{err}");
        assert!(err.contains(&flipped), "{err}");
    }
}

#[test]
fn a_changed_size_of_a_primitive_breaks_the_build() {
    let md = canon();
    // The row of the suite table, read out of the set and doctored in place: the width of a
    // signature lives there and in no test.
    let row = md
        .lines()
        .find(|line| line.trim_start().starts_with("| 1 |"))
        .expect("the set states the first row of the suite table")
        .to_string();
    let (moved, old, new) = bump_last_number_of(&row);
    let err = check_all(&doctored_canon(&md, &row, &moved)).expect_err("the gate must refuse");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&new), "{err}");
}

#[test]
fn the_trees_and_the_genesis_state_hash_agree() {
    let md = canon();
    check_trees(&md).expect("no tree divergence");
    check_walks(&md).expect("no walk divergence");
    check_genesis_state_hash(&md).expect("no genesis divergence");
}

#[test]
fn a_changed_walk_root_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, WALK_HEADER).expect("the walk block parses");
    let (_, old) = rows
        .iter()
        .find(|(l, _)| l == "sparse root (one record)")
        .expect("the root stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("sparse root (one record)"), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_proof_fingerprint_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, APPEND_WALK_HEADER).expect("the append walk block parses");
    let (label, old) = rows
        .iter()
        .find(|(l, _)| l.starts_with("proof of position 2"))
        .expect("the fingerprint stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains(&label), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_derived_cell_that_disagrees_with_itself_is_refused() {
    let md = canon();
    let line = row_line(&md, "segment_windows");
    let doctored = line.replacen("τ₂ / 14", "τ₂ / 15", 1);
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("15"), "{err}");
}

#[test]
fn a_changed_tree_vector_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, MERKLE_EMPTIES_HEADER).expect("the empties parse");
    let (label, old) = rows
        .iter()
        .find(|(l, _)| l.contains("empty_internal"))
        .expect("an internal stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains(&label), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_fabric_root_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, FABRIC_HEADER).expect("the fabric block parses");
    let (_, old) = rows
        .iter()
        .find(|(l, _)| l.starts_with("fabric root"))
        .expect("the root stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("fabric root"), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn the_birth_of_a_seed_agrees_with_the_set() {
    check_seed(&canon()).expect("no divergence of a birth");
}

#[test]
fn a_changed_word_list_fingerprint_breaks_the_build_with_both_values() {
    let md = canon();
    let stated = hex_of(&md, "2f5eed53");
    let flipped = flip_first_hex(&stated);
    let err = check_all(&doctored_canon(&md, &stated, &flipped)).expect_err("the gate must refuse");
    // The gate names the line as the set writes it, not as a checker would paraphrase it.
    assert!(err.contains("word_0"), "{err}");
    assert!(err.contains(&stated), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_count_of_iterations_breaks_the_build_with_both_counts() {
    let md = canon();
    let stated = format!("iterations = {}", with_spaces(mt_seed::SEED_ITERATIONS));
    let doctored = format!("iterations = {}", with_spaces(mt_seed::SEED_ITERATIONS + 1));
    let err =
        check_all(&doctored_canon(&md, &stated, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("iterations"), "{err}");
    assert!(
        err.contains(&(mt_seed::SEED_ITERATIONS + 1).to_string()),
        "{err}"
    );
}

#[test]
fn a_changed_salt_breaks_the_build_with_both_salts() {
    let md = canon();
    let err = check_all(&doctored_canon(
        &md,
        "salt = \"mt-seed\"",
        "salt = \"mt-seeds\"",
    ))
    .expect_err("the gate must refuse");
    assert!(err.contains("mt-seeds"), "{err}");
    assert!(err.contains("mt-seed"), "{err}");
}

#[test]
fn a_widened_branch_breaks_the_build_with_both_lengths() {
    let md = canon();
    let err = check_all(&doctored_canon(
        &md,
        "\"mt-app-encryption-key\", 64)",
        "\"mt-app-encryption-key\", 32)",
    ))
    .expect_err("the gate must refuse");
    assert!(err.contains("mt-app-encryption-key"), "{err}");
    assert!(err.contains("32"), "{err}");
    assert!(err.contains("64"), "{err}");
}

#[test]
fn a_reordered_branch_breaks_the_build_with_both_domains() {
    let md = canon();
    let err = check_all(&doctored_canon(
        &md,
        "\"mt-note-key\",           32)",
        "\"mt-nf-key\",             32)",
    ))
    .expect_err("the gate must refuse");
    assert!(err.contains("mt-nf-key"), "{err}");
    assert!(err.contains("mt-note-key"), "{err}");
}

#[test]
fn a_changed_value_of_either_chain_breaks_the_build_with_both_values() {
    // Every frozen line of the block is walked rather than named here, so a value the set adds
    // is covered the day it lands and none is covered by having been remembered.
    let md = canon();
    let rows = parse_labeled(&md, SEED_HEADER).expect("the block of a birth parses");
    let mut walked = 0;
    for (label, stated) in rows {
        let hexish = stated.len() == 64 && stated.bytes().all(|b| b.is_ascii_hexdigit());
        if !hexish {
            continue;
        }
        walked += 1;
        let flipped = flip_first_hex(&stated);
        let err = check_all(&doctored_canon(&md, &stated, &flipped))
            .expect_err("the gate must refuse a changed value");
        if label.starts_with("SHA-256") {
            assert!(err.contains(&stated), "{label}: {err}");
            assert!(err.contains(&flipped), "{label}: {err}");
        }
    }
    assert!(
        walked >= 8,
        "the block holds {walked} frozen values, which is too few"
    );
}

#[test]
fn a_chain_that_loses_the_value_it_awaits_breaks_the_build() {
    let md = canon();
    let line = md
        .lines()
        .find(|l| l.trim_start().starts_with("SHA-256(record_pk)"))
        .expect("the chain names the value it awaits")
        .to_string();
    let with_newline = format!("{line}\n");
    let err = check_all(&doctored_canon(&md, &with_newline, "")).expect_err("the gate must refuse");
    assert!(err.contains("record_pk"), "{err}");
}

#[test]
fn a_value_the_checker_does_not_hold_is_refused_rather_than_skipped() {
    let md = canon();
    let line = md
        .lines()
        .find(|l| l.trim_start().starts_with("SHA-256(record_pk)"))
        .expect("the chain names it")
        .to_string();
    let doctored = format!("{line}\nSHA-256(something new)     = {}", "ab".repeat(32));
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("something new"), "{err}");
}

#[test]
fn the_set_states_the_genesis_state_hash_and_the_code_computes_the_same() {
    let md = canon();
    let stated = parse_genesis_state_hash(&md)
        .expect("the block parses")
        .expect("the set states the value");
    let held = mt_state::tables::genesis_state_hash().expect("the Decree is complete");
    assert_eq!(
        stated,
        held.iter().map(|b| format!("{b:02x}")).collect::<String>()
    );
    assert_eq!(mt_genesis::unpublished().len(), 0);
}

// The full line of the set beginning with a prefix, and the same line with the number after
// its last `=` bumped by one: tests doctor what they read out of the set, restating nothing.
fn bump_after_last_sign(md: &str, prefix: &str) -> (String, String, u64, u64) {
    let line = md
        .lines()
        .find(|l| l.trim_start().starts_with(prefix))
        .unwrap_or_else(|| panic!("the set holds a line beginning {prefix:?}"))
        .to_string();
    let at = line.rfind('=').expect("the line carries a sign");
    let tail = &line[at + 1..];
    let old: u64 = tail
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .expect("digits parse");
    let new = old + 1;
    let suffix = if tail.trim_end().ends_with('B') {
        " B"
    } else {
        ""
    };
    let doctored = format!("{}= {}{}", &line[..at], new, suffix);
    (line, doctored, old, new)
}

#[test]
fn a_changed_identifier_of_the_fold_node_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, FOLD_HEADER).expect("the fold block parses");
    let (_, old) = rows
        .iter()
        .find(|(l, _)| l == "fold_node_id")
        .expect("the identifier stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("fold_node_id"), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_work_vector_of_the_fold_breaks_the_build_with_both_values() {
    let md = canon();
    let rows = parse_labeled(&md, COMMIT_VECTORS_HEADER).expect("the block parses");
    let (label, old) = rows
        .iter()
        .find(|(l, _)| l.starts_with("fold_work("))
        .expect("the work vector stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains(&label), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_confirmation_total_breaks_the_build_with_both_lengths() {
    let md = canon();
    let (line, doctored, old, new) = bump_after_last_sign(&md, "confirmation_len");
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains(&old.to_string()), "{err}");
    assert!(err.contains(&new.to_string()), "{err}");
}

#[test]
fn two_widths_swapped_inside_the_row_of_a_suite_break_the_build() {
    // A bag of numbers cannot see a swap: both values still appear. The gate reads each width at
    // its own column of the row that carries it, so the swap fails at the first column it
    // corrupts. The two cells are read out of the set and exchanged, restating neither.
    let md = canon();
    let row = md
        .lines()
        .find(|l| l.trim_start().starts_with("| 1 | ML-DSA-65 |"))
        .expect("the set holds the first row of the suite table")
        .to_string();
    let cells: Vec<&str> = row.split('|').collect();
    let (secret, public) = (cells[3].trim().to_string(), cells[4].trim().to_string());
    assert_ne!(secret, public);
    let swapped = row
        .replacen(&secret, "@@", 1)
        .replacen(&public, &secret, 1)
        .replacen("@@", &public, 1);
    let err = check_all(&doctored_canon(&md, &row, &swapped)).expect_err("the gate must refuse");
    assert!(err.contains("suite divergence"), "{err}");
}

#[test]
fn a_changed_chain_of_a_placement_breaks_the_build_with_both_values() {
    let md = canon();
    let (line, doctored, old, new) = bump_after_last_sign(&md, "chain(W = ");
    let err = check_all(&doctored_canon(&md, &line, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("chain(W = "), "{err}");
    assert!(err.contains(&old.to_string()), "{err}");
    assert!(err.contains(&new.to_string()), "{err}");
}

#[test]
fn a_frozen_value_nobody_reads_is_refused_by_the_coverage_pass() {
    let md = canon();
    let stray = format!(
        "\n```\nstray value               = {}\n```\n",
        "ab".repeat(32)
    );
    let mut doctored = md.clone();
    doctored.push_str(&stray);
    let err = check_all(&doctored).expect_err("the gate must refuse");
    assert!(err.contains("stray value"), "{err}");
    assert!(err.contains("never read"), "{err}");
}

#[test]
fn a_value_named_as_awaiting_its_stage_passes_and_the_mark_is_held_to_its_crate() {
    // Coverage keys by the pair of a label and a value, so a stale mark is refused the day a
    // checker verifies that pair — which is the day the stage lands and not a day a document can
    // be doctored into. What a document can show is the other half: a line named as awaiting and
    // read by nobody passes, and the mark itself is a claim about the workspace that the gate
    // holds separately.
    // The registry stands empty: every value of the set is read by a checker, and nothing hides
    // behind a word. What is held here is the machinery itself, so the day a value must wait it
    // waits under a rule that works — a line no checker reads is refused, which is the half a
    // document can show.
    let md = canon();
    let stray = "\n```\nno checker reads this = 00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n```\n";
    let err = check_all(&format!("{md}{stray}")).expect_err("a line nobody reads must be refused");
    assert!(
        err.contains("coverage divergence") && err.contains("no checker reads this"),
        "the refusal names the line: {err}"
    );
    check_awaiting_is_earned().expect("an empty registry is earned by construction");
}

#[test]
fn the_secret_of_first_contact_and_the_two_spaces_break_the_build_when_changed() {
    let md = canon();
    for (block, label) in [
        (CONTACT_HEADER, "shared_secret"),
        (TWO_SPACES_HEADER, "SHA-256(chain branch)"),
        (TWO_SPACES_HEADER, "SHA-256(contact seed)"),
        (TWO_SPACES_HEADER, "SHA-256(channel seed)"),
    ] {
        let rows = parse_labeled(&md, block).expect("the block parses");
        let (_, old) = rows
            .iter()
            .find(|(l, _)| l == label)
            .unwrap_or_else(|| panic!("{label} stands frozen"))
            .clone();
        let flipped = flip_first_hex(&old);
        let err =
            check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
        assert!(err.contains(&old), "{label}: {err}");
        assert!(err.contains(&flipped), "{label}: {err}");
    }
}

#[test]
fn a_changed_matrix_seed_of_the_standing_commitment_breaks_the_build() {
    let md = canon();
    let rows = parse_labeled(&md, COMMIT_VECTORS_HEADER).expect("the block parses");
    let (_, old) = rows
        .iter()
        .find(|(l, _)| l == "matrix_seed")
        .expect("the seed stands frozen")
        .clone();
    let flipped = flip_first_hex(&old);
    let err = check_all(&doctored_canon(&md, &old, &flipped)).expect_err("the gate must refuse");
    assert!(err.contains("matrix_seed"), "{err}");
    assert!(err.contains(&old), "{err}");
    assert!(err.contains(&flipped), "{err}");
}

#[test]
fn a_changed_parameter_of_the_standing_commitment_breaks_the_build_with_both_values() {
    // The parameters are those of ML-DSA-65 taken whole; a set that moves one of them is a
    // set the code no longer transcribes. The value of q is read out of the set and bumped.
    let md = canon();
    let line = md
        .lines()
        .find(|l| l.trim_start().starts_with("d = ") && l.contains("q ="))
        .expect("the set states the parameters")
        .to_string();
    let q_at = line.find("q =").expect("q stands in the line");
    let after = &line[q_at + 3..];
    let end = after.find(',').expect("a comma follows q");
    let old_text = after[..end].trim().to_string();
    let old: u64 = old_text
        .chars()
        .filter(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .expect("digits parse");
    let new = old + 1;
    let doctored_line = line.replacen(&old_text, &new.to_string(), 1);
    let err =
        check_all(&doctored_canon(&md, &line, &doctored_line)).expect_err("the gate must refuse");
    assert!(err.contains(&old.to_string()), "{err}");
    assert!(err.contains(&new.to_string()), "{err}");
}

#[test]
fn a_changed_value_of_the_pulse_the_orders_or_the_delivery_breaks_the_build() {
    // Every frozen value of the three blocks the suite made computable is walked and flipped
    // in turn: what the gate reads it must also refuse when it moves.
    let md = canon();
    let mut walked = 0;
    for header in [PULSE_HEADER, ORDERS_HEADER, MESSAGES_HEADER, ENTRY_HEADER] {
        let rows = parse_labeled(&md, header).unwrap_or_else(|e| panic!("{header}: {e}"));
        for (label, stated) in rows {
            let hexish = (stated.len() == 64 || stated.len() == 32)
                && stated.bytes().all(|b| b.is_ascii_hexdigit());
            if !hexish || md.matches(stated.as_str()).count() != 1 {
                continue;
            }
            walked += 1;
            let flipped = flip_first_hex(&stated);
            let err = check_all(&doctored_canon(&md, &stated, &flipped))
                .expect_err("the gate must refuse a changed value");
            assert!(err.contains(&stated), "{label}: {err}");
            assert!(err.contains(&flipped), "{label}: {err}");
        }
    }
    assert!(
        walked >= 12,
        "the three blocks hold {walked} frozen values, which is too few"
    );
}

#[test]
fn a_mark_of_awaiting_whose_crate_has_landed_is_refused() {
    // The escape hatch of the coverage pass is itself held to account: a value marked as
    // awaiting a crate that already stands in the workspace is a value hiding behind a word.
    // Every mark is put to the workspace as it stands, and then to one that has landed.
    check_awaiting_is_earned().expect("every mark of the registry is earned");
    assert!(
        AWAITING.is_empty(),
        "a value stands behind a word: every value of the set is read by a checker"
    );
}

#[test]
fn a_changed_row_of_the_suite_table_breaks_the_build() {
    let md = canon();
    let line = md
        .lines()
        .find(|l| l.trim_start().starts_with("| 1 |") && l.contains("ML-DSA-65"))
        .expect("the set holds the row of the one suite")
        .to_string();
    let renamed = line.replacen("ML-DSA-65", "ML-DSA-87", 1);
    let err = check_all(&doctored_canon(&md, &line, &renamed)).expect_err("the gate must refuse");
    assert!(err.contains("ML-DSA-87"), "{err}");
    assert!(err.contains("ML-DSA-65"), "{err}");
    // And a width that moves fails the same way. The width is read out of the row rather than
    // restated: what is doctored is the set's own number.
    let width_cell = line
        .split('|')
        .map(str::trim)
        .filter(|c| !c.is_empty())
        .nth(2)
        .expect("the row states a width");
    let digits: String = width_cell.chars().filter(|c| c.is_ascii_digit()).collect();
    let moved: u64 = digits.parse::<u64>().expect("digits parse") + 1;
    let doctored_row = line.replacen(width_cell, &format!("{moved} B"), 1);
    let err =
        check_all(&doctored_canon(&md, &line, &doctored_row)).expect_err("the gate must refuse");
    assert!(err.contains(&moved.to_string()), "{err}");
    assert!(err.contains(&digits), "{err}");
}

// The layout whose field set awaits does not therefore stand unchecked: its order and its widths
// are stated and reproducible today, and the gate holds them. The named wrong implementation this
// catches is the one that widened a field on one side alone — a key of another suite written into
// the record while the set still states the size of this one, which changes every commitment of a
// person and every proof about one, and which nothing caught before this stood here.
#[test]
fn a_widened_field_of_the_committed_record_breaks_the_build() {
    let md = canon();
    let at = md
        .find("\nserialize(record)\n")
        .expect("the set states the layout of the committed record");
    let fence = &md[at + 1..at + 1 + md[at + 1..].find("```").expect("the layout closes")];
    let field = fence
        .lines()
        .find(|line| line.contains(" B "))
        .expect("the layout states a field of a width in bytes");
    let mut words = field.split_whitespace();
    let name = words.next().expect("a field opens with its name");
    let width = words.next().expect("a field states its width");
    let wider = (width.parse::<u64>().expect("a width is a number") + 8).to_string();
    let doctored = field.replacen(width, &wider, 1);

    let err = check_all(&doctored_canon(&md, field, &doctored)).expect_err("the gate must refuse");
    assert!(err.contains("record divergence"), "{err}");
    assert!(err.contains(name), "{err}");
}

#[test]
fn a_changed_vector_of_the_draw_or_of_a_round_threshold_breaks_the_build_with_both_values() {
    // Every frozen line of both blocks is walked rather than named here, so a vector the set adds
    // is covered the day it lands and none is covered by having been remembered.
    let md = canon();
    let mut walked = 0;
    for header in [DRAW_RETARGET_HEADER, ROUND_THRESHOLD_HEADER] {
        let rows = parse_labeled(&md, header).unwrap_or_else(|e| panic!("{header}: {e}"));
        for (label, stated) in rows {
            let hexish = stated.len() == 64 && stated.bytes().all(|b| b.is_ascii_hexdigit());
            if !hexish || md.matches(stated.as_str()).count() != 1 {
                continue;
            }
            walked += 1;
            let flipped = flip_first_hex(&stated);
            let err = check_all(&doctored_canon(&md, &stated, &flipped))
                .expect_err("the gate must refuse a changed vector");
            assert!(err.contains(&stated), "{label}: {err}");
            assert!(err.contains(&flipped), "{label}: {err}");
        }
    }
    assert!(
        walked >= 4,
        "the two blocks hold {walked} vectors of their own"
    );
}

#[test]
fn a_changed_input_of_a_frozen_vector_of_the_pulse_breaks_the_build() {
    // The inputs stand in the label, so moving one moves what the code computes and the frozen
    // value no longer answers for it. Both the label and its number are read out of the set.
    let md = canon();
    for (header, name) in [
        (DRAW_RETARGET_HEADER, "cleared "),
        (ROUND_THRESHOLD_HEADER, "admitted "),
    ] {
        let rows = parse_labeled(&md, header).expect("the block parses");
        // **Every vector of the block is tried, and one of them has to refuse.** A rule may hold a
        // stretch over which its answer does not move — the threshold of a round is the whole width
        // at every population up to the floor of the crowd — and a vector taken from that stretch
        // would say nothing about whether the gate reads the input at all. What is asserted is that
        // the block as a whole is read, not that any one line of it is sensitive.
        let mut refused = 0;
        for (label, _) in rows
            .iter()
            .filter(|(l, _)| l.contains(name) && !l.contains("_old "))
        {
            let at = label.find(name).expect("the label names it") + name.len();
            let tail = &label[at..];
            let end = tail
                .char_indices()
                .find(|(_, c)| !c.is_ascii_digit() && *c != ' ')
                .map(|(i, _)| i)
                .unwrap_or(tail.len());
            let stated = tail[..end].trim_end();
            let held: u64 = stated
                .chars()
                .filter(char::is_ascii_digit)
                .collect::<String>()
                .parse()
                .expect("a number");
            let doctored = label.replacen(stated, &with_spaces((held + 1) as u32), 1);
            if let Err(err) = check_all(&doctored_canon(&md, label, &doctored)) {
                assert!(err.contains("divergence"), "{err}");
                refused += 1;
            }
        }
        assert!(
            refused > 0,
            "{header}: no vector of the block refused a moved input, so the gate does not read them"
        );
    }
}

#[test]
fn a_changed_close_or_offering_breaks_the_build_with_both_values() {
    // Every row of the block is walked and its answer moved by one: what the gate reads it must
    // also refuse when it moves, and nothing of the set is restated here.
    let md = canon();
    let rows = parse_labeled(&md, CLOSE_HEADER).expect("the block parses");
    let mut walked = 0;
    for (label, _) in rows {
        if !label.starts_with("quorum(") && !label.starts_with("offered(") {
            continue;
        }
        // The line of the set itself is doctored, with the number after its last sign moved by
        // one: nothing of it is assembled here.
        let (line, doctored, _, _) = bump_after_last_sign(&md, &label);
        walked += 1;
        let err = check_all(&doctored_canon(&md, &line, &doctored))
            .expect_err("the gate must refuse a moved answer");
        assert!(err.contains("divergence"), "{label}: {err}");
    }
    assert!(walked >= 4, "the block holds {walked} rows the gate reads");
}

// A heading of a derivation restates the value of its row, and the gate holds the two together.
// The wrong implementation this refuses: one that reads the Decree and leaves the prose of the
// derivations to a reader — under which a section keeps a number the Decree no longer holds, and
// whoever implements from the derivation implements the old one.
#[test]
fn a_heading_that_disagrees_with_its_row_breaks_the_build_with_both_values() {
    let md = canon();
    let heading = md
        .lines()
        .find(|line| line.starts_with("### `cell_bytes`"))
        .expect("the set derives the size of a cell under its own heading")
        .to_string();
    let held = mt_genesis::scalar("cell_bytes").expect("the Decree names it");
    let doctored = heading.replace(&format_number(held), &format_number(held + 1));
    assert_ne!(doctored, heading, "the heading states the value of its row");
    let err = check_derivation_headings(&md.replace(&heading, &doctored))
        .expect_err("the gate must refuse a heading that disagrees with its row");
    assert!(err.contains("cell_bytes"), "{err}");
    assert!(err.contains(&(held + 1).to_string()), "{err}");
    assert!(err.contains(&held.to_string()), "{err}");
}

// The spelling the set writes large numbers in: groups of three, separated by a space.
fn format_number(value: u64) -> String {
    let digits = value.to_string();
    let mut out = String::new();
    for (at, digit) in digits.chars().enumerate() {
        if at > 0 && (digits.len() - at).is_multiple_of(3) {
            out.push(' ');
        }
        out.push(digit);
    }
    out
}

// Every heading that restates a value is compared, and the count is what the set holds today.
#[test]
fn every_heading_that_restates_a_value_of_the_decree_is_compared() {
    let md = canon();
    // Two enumerations of one thing: what the set writes, and what the gate compared. A number
    // written here instead would pass a set that lost a heading.
    let headings = md
        .lines()
        .filter(|line| line.starts_with("### `") && line.contains('='))
        .count();
    let names_in_those_headings: usize = md
        .lines()
        .filter(|line| line.starts_with("### `") && line.contains('='))
        .map(|line| line.matches('`').count() / 2)
        .sum();
    assert!(headings > 0);
    let compared = check_derivation_headings(&md).expect("the set agrees with itself");
    assert_eq!(compared, names_in_those_headings);
}

// Coverage keys by the pair of a label and a value, and this is what the pair buys. The wrong
// implementation it refuses: a pass keyed by the value alone, under which a line carrying a value
// some other line already carries counts as read without anyone reading it — thirty-four of the
// frozen lines of the set share a value with another line.
#[test]
fn a_second_line_carrying_a_verified_value_is_not_thereby_read() {
    let md = canon();
    let anchor = md
        .lines()
        .find(|line| {
            line.trim_start().starts_with("= ")
                && line.trim().len() == 66
                && line.trim()[2..].bytes().all(|b| b.is_ascii_hexdigit())
        })
        .expect("the set freezes a value of thirty-two bytes")
        .to_string();
    let value = anchor.trim()[2..].to_string();
    let doctored = md.replacen(
        &anchor,
        &format!("{anchor}\na line no checker reads\n= {value}"),
        1,
    );
    let err = check_all(&doctored).expect_err("the gate must refuse a line nobody read");
    assert!(err.contains("a line no checker reads"), "{err}");
    assert!(err.contains(&value), "{err}");
}

// The register of a crate is written by the declaration of its constants, and what the gate holds
// it against is the sources of the tree. These three say the comparison is a comparison: a place
// that moved fails, a place standing twice fails, and every numeral of the sources stands in a
// register — which is the denominator the register would otherwise lack.
#[test]
fn a_place_a_constant_names_that_moves_breaks_the_build_with_the_constant() {
    let md = canon();
    // A depth of the trees, whose place is a sentence of its own: a span sharing a cell of a table
    // with the span of a neighbour would take the neighbour down with it, and the refusal would
    // then name a constant this test did not move.
    let span = match mt_merkle::DEPTHS
        .iter()
        .find(|c| c.name == "KEY_BITS")
        .expect("the depths hold the sparse tree")
        .place
    {
        mt_codec::Place::Writes(span) => span,
        _ => panic!("the depth of the sparse tree stands at a span of the set"),
    };
    // The check itself is put to the doctored set rather than the whole gate: a checker standing
    // before this one would refuse the doctored sentence first, and its refusal would say nothing
    // about the register.
    let err = check_constants(&doctored_canon(&md, span, "a sentence nobody wrote"))
        .expect_err("the gate must refuse");
    assert!(err.contains("KEY_BITS"), "{err}");
    assert!(err.contains(span), "{err}");
}

#[test]
fn a_place_standing_twice_names_none_of_them_and_is_refused() {
    let md = canon();
    let span = match mt_codec::size::WIDTHS
        .iter()
        .find(|c| c.name == "AEAD_NONCE")
        .expect("the widths hold the nonce")
        .place
    {
        mt_codec::Place::Writes(span) => span,
        _ => panic!("the width of a nonce stands at a span of the set"),
    };
    let doubled = format!("{md}\n\n{span}\n");
    let err = check_all(&doubled).expect_err("the gate must refuse");
    assert!(err.contains("AEAD_NONCE"), "{err}");
    assert!(err.contains("more than once"), "{err}");
}

#[test]
fn every_numeral_of_the_sources_stands_in_a_register() {
    // The check the gate runs on every build, put here as well so a reader of the tests sees the
    // denominator: what is counted is the declarations of the sources, not the rows somebody
    // remembered to write.
    check_every_numeral_is_registered().expect("no numeral of this tree stands outside a register");
}

// And the rows of the tables are read as the lines of the blocks are.
#[test]
fn a_row_of_a_table_nobody_reads_breaks_the_build() {
    let md = canon();
    let anchor = "| u8 | 1 B | the raw byte |";
    assert!(md.contains(anchor), "the set states the width of a byte");
    let doctored = md.replacen(
        anchor,
        &format!("{anchor}\n| `a row nobody compares` | 7 B | prose |"),
        1,
    );
    let err = check_all(&doctored).expect_err("the gate must refuse a row nobody read");
    assert!(err.contains("a row nobody compares"), "{err}");
}
