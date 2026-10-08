// The parser of the set and the checks against the code. This file is included by both the
// build script and the library, so the gate that fails a build and the tests that exercise it
// are one implementation. The set is `docs/Montana Canon.md`; every check answers with the
// name of what diverged and both values, because a gate that fails without naming the value
// sends its reader to a diff instead of to the defect.

pub const CANON_RELATIVE: &str = "../../../docs/Montana Canon.md";

#[derive(Debug, PartialEq, Eq)]
pub enum ParsedValue {
    Scalar(u64),
    Ratio(u64, u64),
    Schedule(Vec<(u64, u64)>),
    // A parameter the set names and has not published. It carries no value of any kind, and the
    // gate holds the code to carrying none either.
    Unpublished,
    Hash([u8; 32]),
}

#[derive(Debug, PartialEq, Eq)]
pub struct ParsedRow {
    // The spelling the set writes the name in, which is what the coverage pass reads back.
    pub label: String,
    pub name: String,
    pub value: ParsedValue,
}

#[derive(Debug, PartialEq, Eq)]
pub struct HashVector {
    pub domain: String,
    pub part: Vec<u8>,
    pub expected_hex: String,
    // The call as the set writes it, which is the label the coverage pass reads back.
    pub label: String,
}

fn section<'a>(md: &'a str, header: &str, stops: &[&str]) -> Result<&'a str, String> {
    // A header counts only at the start of a line, so quoting one in prose moves nothing.
    let start = if md.starts_with(header) {
        0
    } else {
        let anchored = format!("\n{header}");
        md.find(&anchored)
            .map(|i| i + 1)
            .ok_or_else(|| format!("the set holds no section {header:?}"))?
    };
    let body = &md[start + header.len()..];
    let end = stops
        .iter()
        .filter_map(|stop| body.find(stop))
        .min()
        .unwrap_or(body.len());
    Ok(&body[..end])
}

fn ticked(cell: &str) -> Vec<&str> {
    let mut spans = Vec::new();
    let mut rest = cell;
    while let Some(open) = rest.find('`') {
        let after = &rest[open + 1..];
        match after.find('`') {
            Some(close) => {
                spans.push(&after[..close]);
                rest = &after[close + 1..];
            }
            None => break,
        }
    }
    spans
}

fn number(text: &str) -> Result<u64, String> {
    let cleaned: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    if cleaned.is_empty() || !cleaned.bytes().all(|b| b.is_ascii_digit()) {
        return Err(format!("not a number: {text:?}"));
    }
    cleaned
        .parse::<u64>()
        .map_err(|e| format!("not a number: {text:?} ({e})"))
}

// The forms a cell may take besides a plain number: `τ₂`, `n τ₂`, `τ₂ / n`. A form the
// parser does not hold answers None and the stated number stands alone.
fn expression(text: &str, tau2: Option<u64>) -> Result<Option<u64>, String> {
    let t = text.trim();
    if t.is_empty() {
        return Ok(None);
    }
    if let Some(rest) = t.strip_prefix("τ₂") {
        let tau2 = tau2.ok_or_else(|| "τ₂ referenced before its own row".to_string())?;
        let rest = rest.trim();
        if rest.is_empty() {
            return Ok(Some(tau2));
        }
        if let Some(div) = rest.strip_prefix('/') {
            let d = number(div)?;
            if d == 0 || tau2 % d != 0 {
                return Err(format!("τ₂ / {d} does not divide evenly"));
            }
            return Ok(Some(tau2 / d));
        }
        return Ok(None);
    }
    if let Some(prefix) = t.strip_suffix("τ₂") {
        let tau2 = tau2.ok_or_else(|| "τ₂ referenced before its own row".to_string())?;
        return Ok(Some(number(prefix)? * tau2));
    }
    if t.bytes().all(|b| b.is_ascii_digit() || b == b' ') {
        return Ok(Some(number(t)?));
    }
    Ok(None)
}

fn scalar_value(cell: &str, tau2: Option<u64>) -> Result<u64, String> {
    let cell = cell.trim();
    if let Some(eq) = cell.rfind('=') {
        let stated = number(&cell[eq + 1..])?;
        // A cell that writes `expr = value` is held to both sides: a derivation the
        // parser can resolve must resolve to the number beside it.
        if let Some(derived) = expression(&cell[..eq], tau2)? {
            if derived != stated {
                return Err(format!(
                    "a cell disagrees with itself: {:?} resolves to {derived} and states {stated}",
                    cell[..eq].trim()
                ));
            }
        }
        return Ok(stated);
    }
    expression(cell, tau2)?.ok_or_else(|| format!("not a number: {cell:?}"))
}

fn row_cells(line: &str) -> Option<(&str, &str)> {
    let trimmed = line.trim();
    if !trimmed.starts_with("| `") {
        return None;
    }
    let mut cells = trimmed.split('|').map(str::trim).filter(|c| !c.is_empty());
    let name_cell = cells.next()?;
    let value_cell = cells.next()?;
    Some((name_cell, value_cell))
}

// A cell holding exactly sixty-four hex digits is a hash-valued row.
fn hash_cell(cell: &str) -> Option<[u8; 32]> {
    let trimmed = cell.trim();
    if trimmed.len() != 64 || !trimmed.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let mut out = [0u8; 32];
    for (at, slot) in out.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&trimmed[2 * at..2 * at + 2], 16).ok()?;
    }
    Some(out)
}

pub fn parse_decree(md: &str) -> Result<Vec<ParsedRow>, String> {
    parse_block(md, "### Parameters")
}

pub fn parse_forms(md: &str) -> Result<Vec<ParsedRow>, String> {
    parse_block(md, "### Forms")
}

// One reading for both blocks of the Decree: they differ in what binds them and in nothing else.
fn parse_block(md: &str, header: &str) -> Result<Vec<ParsedRow>, String> {
    let body = section(md, header, &["\n### ", "\n## "])?;
    let mut rows = Vec::new();
    let mut tau2 = None;
    for line in body.lines() {
        let Some((name_cell, value_cell)) = row_cells(line) else {
            continue;
        };
        let spans = ticked(name_cell);
        let first = *spans
            .first()
            .ok_or_else(|| format!("a Decree row without a name: {line:?}"))?;
        if first == "τ₂" {
            let value = scalar_value(value_cell, None)?;
            tau2 = Some(value);
            rows.push(ParsedRow {
                label: first.to_string(),
                name: "tau2".to_string(),
                value: ParsedValue::Scalar(value),
            });
        } else if first == "emission_schedule" {
            let mut schedule = Vec::new();
            for pair in value_cell.split('(').skip(1) {
                let inner = pair
                    .split(')')
                    .next()
                    .ok_or_else(|| format!("an unclosed schedule row: {value_cell:?}"))?;
                let mut parts = inner.split(',');
                let height = number(parts.next().unwrap_or_default())?;
                let mint = number(parts.next().unwrap_or_default())?;
                schedule.push((height, mint));
            }
            if schedule.is_empty() {
                return Err(format!("an empty emission schedule: {value_cell:?}"));
            }
            rows.push(ParsedRow {
                label: first.to_string(),
                name: first.to_string(),
                value: ParsedValue::Schedule(schedule),
            });
        } else if value_cell.contains("**unpublished**") {
            rows.push(ParsedRow {
                label: first.to_string(),
                name: first.to_string(),
                value: ParsedValue::Unpublished,
            });
        } else if let Some(value) = hash_cell(value_cell) {
            rows.push(ParsedRow {
                label: first.to_string(),
                name: first.to_string(),
                value: ParsedValue::Hash(value),
            });
        } else if let Some(base) = first.strip_suffix("_num") {
            let mut halves = value_cell.split(" over ");
            let num = number(halves.next().unwrap_or_default())?;
            let den = number(halves.next().unwrap_or_default())?;
            rows.push(ParsedRow {
                label: first.to_string(),
                name: base.to_string(),
                value: ParsedValue::Ratio(num, den),
            });
        } else if name_cell.contains(" over ") {
            let second = *spans
                .get(1)
                .ok_or_else(|| format!("a paired row without its second name: {line:?}"))?;
            let mut halves = value_cell.split(" over ");
            let low = number(halves.next().unwrap_or_default())?;
            let high = number(halves.next().unwrap_or_default())?;
            rows.push(ParsedRow {
                label: first.to_string(),
                name: first.to_string(),
                value: ParsedValue::Scalar(low),
            });
            rows.push(ParsedRow {
                label: second.to_string(),
                name: second.to_string(),
                value: ParsedValue::Scalar(high),
            });
        } else {
            // A refusal names its row: a value the parser does not hold is a defect of one
            // parameter, and a reader sent to a diff instead of to that parameter loses the
            // whole benefit of the gate.
            let held = scalar_value(value_cell, tau2)
                .map_err(|e| format!("Decree divergence at `{first}`: {e}"))?;
            rows.push(ParsedRow {
                label: first.to_string(),
                name: first.to_string(),
                value: ParsedValue::Scalar(held),
            });
        }
    }
    if rows.is_empty() {
        return Err(format!("the block {header} of the Decree parsed to nothing"));
    }
    Ok(rows)
}

pub fn parse_registry(md: &str) -> Result<Vec<String>, String> {
    let body = section(md, "## The registry of domain separators", &["\n### ", "\n## "])?;
    let mut names = Vec::new();
    for line in body.lines() {
        let Some((name_cell, _)) = row_cells(line) else {
            continue;
        };
        let spans = ticked(name_cell);
        let first = *spans
            .first()
            .ok_or_else(|| format!("a registry row without a name: {line:?}"))?;
        names.push(first.to_string());
    }
    if names.is_empty() {
        return Err("the registry table parsed to nothing".to_string());
    }
    Ok(names)
}

pub fn parse_primitive_vectors(md: &str) -> Result<Vec<HashVector>, String> {
    let body = section(md, "**The domain-separated primitive.**", &["\n**"])?;
    let fence_open = body
        .find("```")
        .ok_or_else(|| "the primitive vectors carry no fenced block".to_string())?;
    let fenced = &body[fence_open + 3..];
    let fence_close = fenced
        .find("```")
        .ok_or_else(|| "the primitive vectors' fence never closes".to_string())?;
    let block = &fenced[..fence_close];

    let mut vectors = Vec::new();
    let mut pending: Option<(String, Vec<u8>, String)> = None;
    for line in block.lines() {
        let line = line.trim();
        if let Some(call) = line.strip_prefix("hash(\"") {
            let close = call
                .find('"')
                .ok_or_else(|| format!("an unterminated domain: {line:?}"))?;
            let domain = call[..close].to_string();
            let rest = &call[close..];
            let open = rest
                .find('[')
                .ok_or_else(|| format!("a vector without its part: {line:?}"))?;
            let inner = &rest[open + 1..];
            let end = inner
                .find(']')
                .ok_or_else(|| format!("an unclosed part: {line:?}"))?;
            let part = parse_part(&inner[..end])?;
            pending = Some((domain, part, line.to_string()));
        } else if let Some(hex) = line.strip_prefix("= ") {
            let (domain, part, label) = pending
                .take()
                .ok_or_else(|| format!("an expected value without its call: {line:?}"))?;
            vectors.push(HashVector {
                domain,
                part,
                expected_hex: hex.trim().to_string(),
                label,
            });
        }
    }
    if vectors.is_empty() {
        return Err("the primitive vectors parsed to nothing".to_string());
    }
    Ok(vectors)
}

// What this build has verified: one pair of a label and a value per comparison it made. The
// coverage pass reads it at the end of `check_all`; a frozen line of the set that no checker
// compared and no stage awaits is refused, so the gate cannot be green over a value it never
// read. The key is the pair and not the value alone: thirty-four of the frozen lines share a
// value with another line, and a key of the value alone would let one comparison answer for two
// lines — the second of which nobody read.
thread_local! {
    static VERIFIED: std::cell::RefCell<std::collections::HashSet<String>> =
        std::cell::RefCell::new(std::collections::HashSet::new());
}

fn verified_reset() {
    VERIFIED.with(|v| v.borrow_mut().clear());
}

// One spelling for one value: case folded, the spaces the set writes large numbers with removed,
// and the `B` of a width dropped. A value noted as `1 248 B` and one read as `1248` are one value,
// and a gate that told them apart would refuse what it had already checked.
fn normalized(value: &str) -> String {
    let mut out = String::new();
    for ch in value.trim().chars() {
        match ch {
            ' ' | '_' => {}
            c => out.extend(c.to_lowercase()),
        }
    }
    out.strip_suffix('b').map(str::to_string).unwrap_or(out)
}

fn is_digits(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())
}

fn is_hex(text: &str) -> bool {
    text.len() >= 16 && text.bytes().all(|b| b.is_ascii_hexdigit())
}

// What counts as a frozen value rather than as prose: a number, a value of a width, or a list of
// either. **This is the reach of the coverage pass, and it is stated here rather than implied**: a
// line whose value is a formula, a name or a sentence is a definition and is checked where it is
// used, while everything of this shape is a value somebody must have read.
fn is_frozen_shape(normal: &str) -> bool {
    !normal.is_empty()
        && normal
            .split(',')
            .map(str::trim)
            .all(|part| is_digits(part) || is_hex(part))
}

// The key of a comparison: the label the set writes the line under, and the value it holds. A
// label carrying a window of its own — `tag (W = 1001)` — keys under the whole of it, since that
// is what the set writes and what the coverage pass reads back.
fn keyed(label: &str, value: &str) -> String {
    format!("{}\u{0}{}", normalized(label), normalized(value))
}

fn verified_note(label: &str, value: &str) {
    VERIFIED.with(|v| {
        v.borrow_mut().insert(keyed(label, value));
    });
}

// A number the gate computed and compared, noted in the spelling the set writes it in.
fn verified_note_number(label: &str, value: u64) {
    verified_note(label, &value.to_string());
}

fn verified_holds(label: &str, value: &str) -> bool {
    VERIFIED.with(|v| v.borrow().contains(&keyed(label, value)))
}

fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

pub fn check_decree(rows: &[ParsedRow]) -> Result<(), String> {
    check_block(rows, mt_genesis::PARAMETERS, "parameters")
}

pub fn check_forms(rows: &[ParsedRow]) -> Result<(), String> {
    check_block(rows, mt_genesis::FORMS, "forms")
}

fn check_block(rows: &[ParsedRow], code: &[mt_genesis::Entry], block: &str) -> Result<(), String> {
    if rows.len() != code.len() {
        let set: Vec<_> = rows.iter().map(|r| r.name.as_str()).collect();
        let held: Vec<_> = code.iter().map(|e| e.name()).collect();
        return Err(format!(
            "the block of {block} holds {} rows in the set and {} in the code; set: {set:?}; code: {held:?}",
            rows.len(),
            code.len()
        ));
    }
    for (row, entry) in rows.iter().zip(code.iter()) {
        if row.name != entry.name() {
            return Err(format!(
                "Decree order diverges: the set names `{}` where the code names `{}`",
                row.name,
                entry.name()
            ));
        }
        let matches = match (&row.value, entry) {
            (ParsedValue::Scalar(v), mt_genesis::Entry::Scalar(_, cv)) => {
                if v != cv {
                    return Err(format!(
                        "Decree divergence at `{}`: the set holds {v}, the code holds {cv}",
                        row.name
                    ));
                }
                true
            }
            (ParsedValue::Ratio(n, d), mt_genesis::Entry::Ratio(_, cn, cd)) => {
                if (n, d) != (cn, cd) {
                    return Err(format!(
                        "Decree divergence at `{}`: the set holds {n} over {d}, the code holds {cn} over {cd}",
                        row.name
                    ));
                }
                true
            }
            (ParsedValue::Schedule(s), mt_genesis::Entry::Schedule(_, cs)) => {
                if s.as_slice() != *cs {
                    return Err(format!(
                        "Decree divergence at `{}`: the set holds {s:?}, the code holds {cs:?}",
                        row.name
                    ));
                }
                true
            }
            (ParsedValue::Unpublished, mt_genesis::Entry::Unpublished(..)) => true,
            (ParsedValue::Hash(v), mt_genesis::Entry::Hash(_, cv)) => {
                if v != cv {
                    return Err(format!(
                        "Decree divergence at `{}`: the set and the code hold two hashes",
                        row.name
                    ));
                }
                verified_note(&row.name, &hex(v));
                true
            }
            _ => false,
        };
        if !matches {
            return Err(format!(
                "Decree divergence at `{}`: the set and the code hold different kinds of value",
                row.name
            ));
        }
        if let ParsedValue::Scalar(v) = row.value {
            verified_note_number(&row.label, v);
        }
    }
    Ok(())
}

pub fn check_registry(names: &[String]) -> Result<(), String> {
    let code = mt_codec::domain::REGISTRY;
    for (i, name) in names.iter().enumerate() {
        match code.get(i) {
            Some(d) if d.as_str() == name => {}
            Some(d) => {
                return Err(format!(
                    "registry divergence at row {}: the set holds `{}`, the code holds `{}`",
                    i + 1,
                    name,
                    d.as_str()
                ));
            }
            None => {
                return Err(format!(
                    "registry divergence: the set holds `{name}` and the code ends before it"
                ));
            }
        }
    }
    if code.len() > names.len() {
        return Err(format!(
            "registry divergence: the code holds `{}` and the set ends before it",
            code[names.len()].as_str()
        ));
    }
    Ok(())
}

pub fn check_vectors(vectors: &[HashVector]) -> Result<(), String> {
    for v in vectors {
        verified_note(&v.label, &v.expected_hex);
        let domain = mt_codec::domain::by_name(&v.domain).ok_or_else(|| {
            format!(
                "vector divergence: the set hashes under `{}`, which the code's registry does not hold",
                v.domain
            )
        })?;
        let computed = hex(&mt_codec::hash_of_one(domain, &v.part));
        if computed != v.expected_hex {
            return Err(format!(
                "vector divergence under `{}`: the set holds {}, the code computes {computed}",
                v.domain, v.expected_hex
            ));
        }
    }
    Ok(())
}


pub const MERKLE_EMPTIES_HEADER: &str = "**The empty values of both trees.**";
pub const FABRIC_HEADER: &str = "**The empty values of the fabric, and a fabric of one leaf.**";
pub const NOTE_TREE_HEADER: &str = "**An empty note tree, and the same tree after one commitment.**";

// A labelled line divides at the first `=` standing outside parentheses. Both halves of that rule
// carry weight: a label may hold a window of its own — `tag (W = 1001)` — and the set does not
// always leave a space before the sign. A parser dividing at the first ` = ` breaks the first and
// drops the second in silence.
fn split_at_sign(line: &str) -> Option<(&str, &str)> {
    let mut depth = 0usize;
    for (at, ch) in line.char_indices() {
        match ch {
            '(' => depth += 1,
            ')' => depth = depth.saturating_sub(1),
            '=' if depth == 0 => return Some((&line[..at], &line[at + 1..])),
            _ => {}
        }
    }
    None
}

// The fenced block under a bold header, read as labelled values: `label = value` on one
// line, or a label whose value stands on the next line as `= value`.
// Where a block of vectors ends: the next bold **header**, which in this set is a whole line
// opening with two asterisks and closing with a period and two more. Stopping at any bold
// span would stop inside prose — the round of a chain emphasises a word mid-sentence — and a
// block cut there loses the vectors standing after it.
fn to_next_bold_header<'a>(md: &'a str, header: &str) -> Result<&'a str, String> {
    let body = section(md, header, &[])?;
    let mut at = 0usize;
    for line in body.lines() {
        let trimmed = line.trim_end();
        // A header may carry prose after it on the same line, so what marks one is a bold span
        // opening the line and closing with a period — `**without**` mid-sentence closes on a
        // letter and is not a header.
        if at > 0 && trimmed.starts_with("**") && trimmed.contains(".**") {
            return Ok(&body[..at]);
        }
        at += line.len() + 1;
        if at > body.len() {
            break;
        }
    }
    Ok(body)
}

// How a fenced block reads as labelled values, in one place: a label and its value on one line,
// a label whose value stands on the next as `= value`, and a label whose own line already carries
// an expression the value below replaces. The coverage pass and the checkers read by this one
// rule, because two readings of one block disagree on the day a label runs over two lines — and
// then a value compared under one label is counted unread under another.
fn labelled_entries(block: &str) -> Result<Vec<(String, String)>, String> {
    let mut out: Vec<(String, String)> = Vec::new();
    let mut pending: Option<String> = None;
    for raw in block.lines() {
        // The set writes a label at the margin and runs it over into an indented line when it is
        // long. An indented line is therefore a continuation of the entry above and never a label
        // of its own — without that, a value keys under the tail of a sentence and the checker
        // that compared it under its true label counts as never having read it.
        let indented = raw.starts_with(' ') || raw.starts_with('\t');
        let line = raw.trim();
        if line.is_empty() {
            pending = None;
        } else if let Some(rest) = line.strip_prefix("= ") {
            match pending.take() {
                Some(label) => out.push((label, rest.trim().to_string())),
                // A line may state what a value is and the value itself on the next line:
                // `test_machine_secret = SHA-256("mt-vector-machine")` and then `= <hex>`. The
                // continuation is the value of the line above, not an orphan.
                None => match out.last_mut() {
                    Some(last) => last.1 = rest.trim().to_string(),
                    None => return Err(format!("a value without its label: {line:?}")),
                },
            }
        } else if let Some((label, value)) = split_at_sign(line) {
            out.push((label.trim().to_string(), value.trim().to_string()));
            pending = None;
        } else if indented && is_frozen_shape(&normalized(line)) {
            // A value of the frozen shape standing alone on an indented line is the value of the
            // entry above, whose own line said in words what that value is. Without this it stands
            // in no entry at all — neither compared by a checker nor named by the coverage pass —
            // and that is the one state a value of this set may not be in. The named wrong reading
            // this refuses is the one that asks for the sign before it looks: under it a line of
            // the set could be changed with every build staying green, which is what it did.
            match out.last_mut() {
                Some(last) => last.1 = line.to_string(),
                None => return Err(format!("a value without its label: {line:?}")),
            }
        } else if !indented {
            pending = Some(line.to_string());
        }
    }
    Ok(out)
}

pub fn parse_labeled(md: &str, header: &str) -> Result<Vec<(String, String)>, String> {
    let body = to_next_bold_header(md, header)?;
    // A header may carry more than one fenced block, with prose between them — the round of a
    // chain states its seeds in one and the vectors that stand on them in the next. Reading
    // only the first would leave the second unread while the gate reported itself complete,
    // which is the very state the coverage pass exists to forbid.
    let mut blocks: Vec<&str> = Vec::new();
    let mut rest = body;
    while let Some(open) = rest.find("```") {
        let after = &rest[open + 3..];
        let Some(close) = after.find("```") else {
            return Err(format!("the fence of {header} never closes"));
        };
        blocks.push(&after[..close]);
        rest = &after[close + 3..];
    }
    if blocks.is_empty() {
        return Err(format!("{header} carries no fenced block"));
    }
    let out = labelled_entries(&blocks.join("\n\n"))?;
    if out.is_empty() {
        return Err(format!("{header} parsed to nothing"));
    }
    Ok(out)
}

// The one place a checker reads a labelled line of the set, and therefore the place an input is
// noted as read: what is handed back comes out of the document and never out of a rendering this
// build made, so nothing can be counted read by being written and parsed again. An input flipped
// changes what the checker computes and fails its comparison downstream, which is the protection
// a value carries.
fn labeled<'a>(rows: &'a [(String, String)], label: &str) -> Result<&'a str, String> {
    rows.iter()
        .find(|(l, _)| l == label)
        .map(|(_, v)| v.as_str())
        .ok_or_else(|| format!("the set does not label {label:?}"))
}

// An input a checker consumes, noted where it enters the computation rather than where it was
// fetched. The two are not the same claim: a line fetched and then dropped is protected by
// nothing, while a line that enters a computation whose answer is compared is protected by that
// comparison — flip it and the answer moves and the comparison fails. Only the second is a line
// this build read, and this is the door that says so.
fn consumed<'a>(rows: &'a [(String, String)], label: &str) -> Result<&'a str, String> {
    let value = labeled(rows, label)?;
    verified_note(label, value);
    Ok(value)
}

fn hex32(text: &str) -> Result<[u8; 32], String> {
    let t = text.trim();
    if t.len() != 64 || !t.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(format!("not a 32-byte hex value: {text:?}"));
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&t[2 * i..2 * i + 2], 16)
            .map_err(|e| format!("not hex: {t:?} ({e})"))?;
    }
    Ok(out)
}

// A repeated-byte pattern the vectors write as `0xE1 x 32`.
fn repeat_bytes(text: &str) -> Result<Vec<u8>, String> {
    let t = text.trim();
    let body = t
        .strip_prefix("0x")
        .ok_or_else(|| format!("not a repeated byte: {text:?}"))?;
    let (byte_hex, count) = body
        .split_once(" x ")
        .ok_or_else(|| format!("not a repeated byte: {text:?}"))?;
    let byte = u8::from_str_radix(byte_hex.trim(), 16)
        .map_err(|e| format!("not a byte: {text:?} ({e})"))?;
    // The set writes an input for a reader, so a count may carry inner spaces, as large values
    // are written, and words after it: what is read is the count and never the prose beside it.
    let trimmed = count.trim().as_bytes();
    let mut digits = String::new();
    let mut i = 0;
    while i < trimmed.len() {
        if trimmed[i].is_ascii_digit() {
            digits.push(trimmed[i] as char);
            i += 1;
        } else if trimmed[i] == b' ' && i + 1 < trimmed.len() && trimmed[i + 1].is_ascii_digit() {
            i += 1;
        } else {
            break;
        }
    }
    let n: usize = digits
        .parse()
        .map_err(|e| format!("not a length: {text:?} ({e})"))?;
    Ok(vec![byte; n])
}

// A part of a vector stands either as a repeated byte — `0xE1 x 32` — or as its bytes in hex. A
// repeated byte reads the same backwards, which is why the set carries both shapes.
fn parse_part(text: &str) -> Result<Vec<u8>, String> {
    let t = text.trim();
    if t.starts_with("0x") && t.contains(" x ") {
        return repeat_bytes(t);
    }
    if !t.is_empty() && t.len().is_multiple_of(2) && t.bytes().all(|b| b.is_ascii_hexdigit()) {
        let mut out = Vec::with_capacity(t.len() / 2);
        for i in 0..t.len() / 2 {
            out.push(
                u8::from_str_radix(&t[2 * i..2 * i + 2], 16)
                    .map_err(|e| format!("not hex: {t:?} ({e})"))?,
            );
        }
        return Ok(out);
    }
    Err(format!("a part the parser does not hold: {text:?}"))
}

// A part of the set at the width its own type states: `0x0A x 1952` read into the array the
// derivation takes, so a set that moved a width fails here rather than at a hash.
fn fixed_part<const N: usize>(cell: &str) -> Result<[u8; N], String> {
    let bytes = parse_part(cell)?;
    <[u8; N]>::try_from(bytes.as_slice())
        .map_err(|_| format!("the set states {} bytes where {N} stand: {cell:?}", bytes.len()))
}

fn repeat32(text: &str) -> Result<[u8; 32], String> {
    repeat_bytes(text)?
        .try_into()
        .map_err(|_| format!("a repeated pattern of a length other than 32: {text:?}"))
}

// The note of the coverage pass is taken here, where a value of the set meets the value this
// tree computes, and nowhere else. Taken where a line is fetched it would count a line a checker
// read and then did nothing with; taken here it counts a comparison, which is the only thing the
// pass claims to count.
fn compare_hash(label: &str, set_value: &str, code_value: &[u8; 32]) -> Result<(), String> {
    verified_note(label, set_value);
    let computed = hex(code_value);
    if set_value.trim() != computed {
        return Err(format!(
            "tree divergence at `{label}`: the set holds {}, the code computes {computed}",
            set_value.trim()
        ));
    }
    Ok(())
}

// The level a frozen empty value names: the leaf, an internal at k, or the internal at the
// note tree depth.
fn empty_level(label: &str, depth: usize, top: usize) -> Result<usize, String> {
    if label.ends_with("empty_leaf") {
        return Ok(0);
    }
    if let Some(rest) = label.split("empty_internal").nth(1) {
        let rest = rest.trim();
        if rest == "at note_tree_depth" {
            return Ok(depth);
        }
        if let Some(inner) = rest.strip_prefix('(').and_then(|r| r.strip_suffix(')')) {
            let k: usize = inner
                .trim()
                .parse()
                .map_err(|e| format!("not a level: {label:?} ({e})"))?;
            if k > top {
                return Err(format!("a level beyond the construction: {label:?}"));
            }
            return Ok(k);
        }
    }
    Err(format!("a label the tree checker does not hold: {label:?}"))
}

fn note_tree_depth() -> Result<usize, String> {
    let depth = mt_genesis::scalar("note_tree_depth")
        .ok_or_else(|| "the Decree names note_tree_depth".to_string())?;
    usize::try_from(depth).map_err(|e| format!("a depth beyond this machine: {e}"))
}

pub fn check_trees(md: &str) -> Result<(), String> {
    let depth = note_tree_depth()?;

    let merkle_rows = parse_labeled(md, MERKLE_EMPTIES_HEADER)?;
    let merkle_empties =
        mt_merkle::empty_internals(
            mt_codec::domain::MT_MERKLE_LEAF,
            mt_codec::domain::MT_MERKLE_NODE,
            mt_merkle::KEY_BITS,
        );
    for (label, value) in &merkle_rows {
        let level = empty_level(label, depth, mt_merkle::KEY_BITS)?;
        compare_hash(label, value, &merkle_empties[level])?;
    }

    let fabric_rows = parse_labeled(md, FABRIC_HEADER)?;
    let fabric_empties: Vec<[u8; 32]> = mt_proof::fabric::empty_internals(depth)
        .iter()
        .map(|d| d.bytes())
        .collect();
    let inputs = labeled(&fabric_rows, "witnessed commitment")?;
    let mut parts = inputs.split(',');
    let commitment = repeat32(parts.next().unwrap_or_default())?;
    let window_cell = parts.next().unwrap_or_default();
    let window = number(
        window_cell
            .split_once('=')
            .map(|(_, v)| v)
            .unwrap_or_default(),
    )?;
    let blind_cell = parts.next().unwrap_or_default();
    let blind = repeat32(
        blind_cell
            .split_once('=')
            .map(|(_, v)| v)
            .unwrap_or_default(),
    )?;
    // The second observation stands on its own line of inputs, with its own window: a leaf that
    // took the window of the first would part at the root over the two.
    let second = labeled(&fabric_rows, "a second witnessed commitment")?;
    let mut second_parts = second.split(',');
    let second_commitment = repeat32(second_parts.next().unwrap_or_default())?;
    let second_window = number(
        second_parts
            .next()
            .unwrap_or_default()
            .split_once('=')
            .map(|(_, v)| v)
            .unwrap_or_default(),
    )?;
    let second_blind = repeat32(
        second_parts
            .next()
            .unwrap_or_default()
            .split_once('=')
            .map(|(_, v)| v)
            .unwrap_or_default(),
    )?;
    for (label, value) in &fabric_rows {
        if label == "witnessed commitment" || label == "a second witnessed commitment" {
            continue;
        }
        if label.starts_with("fabric empty") {
            let level = empty_level(label, depth, depth)?;
            compare_hash(label, value, &fabric_empties[level])?;
        } else if label == "fabric leaf" {
            compare_hash(
                label,
                value,
                &mt_proof::fabric::leaf(&commitment, window, &blind).bytes(),
            )?;
        } else if label == "fabric root (one leaf at 0)" {
            let mut tree = mt_proof::fabric::FabricTree::new(depth);
            tree.witness(&commitment, window, &blind)
                .map_err(|_| "the fabric of the vector does not admit one leaf".to_string())?;
            compare_hash(label, value, &tree.root().bytes())?;
        } else if label == "fabric leaf (second)" {
            compare_hash(
                label,
                value,
                &mt_proof::fabric::leaf(&second_commitment, second_window, &second_blind).bytes(),
            )?;
        } else if label == "fabric root (two leaves)" {
            // Two observations, and the second at position 1: what this pins is the pairing of a
            // level, which a fabric of one leaf cannot say anything about.
            let mut tree = mt_proof::fabric::FabricTree::new(depth);
            tree.witness(&commitment, window, &blind)
                .map_err(|_| "the fabric of the vector does not admit one leaf".to_string())?;
            tree.witness(&second_commitment, second_window, &second_blind)
                .map_err(|_| "the fabric of the vector does not admit a second leaf".to_string())?;
            compare_hash(label, value, &tree.root().bytes())?;
        } else {
            return Err(format!("a label the fabric checker does not hold: {label:?}"));
        }
    }

    let note_rows = parse_labeled(md, NOTE_TREE_HEADER)?;
    // The derivation of `cm` from value, note_pk and rcm is a note derivation; it is
    // asserted with the derivations of a note, and the tree consumes its result here.
    let note_inputs = labeled(&note_rows, "value")?;
    let cm = hex32(labeled(&note_rows, "cm")?)?;
    compare_hash(
        "note_root (empty)",
        labeled(&note_rows, "note_root (empty)")?,
        &mt_proof::notes::root_of(&[], depth).ok_or("an empty tree always folds")?,
    )?;
    compare_hash(
        "note_root (one leaf at 0)",
        labeled(&note_rows, "note_root (one leaf at 0)")?,
        &mt_proof::notes::root_of(&[cm], depth)
            .ok_or("the commitment of the vector is no digest of the family")?,
    )?;
    // The root over two commitments, which is what pins the pairing of a level: at one leaf every
    // level folds that leaf with the empty of its own level and never with another leaf, so a root
    // over one cannot tell an implementation assembling a level with the pair folded
    // right-then-left from a right one.
    let second = input32(note_inputs, "a second commitment")?;
    compare_hash(
        "note_root (two leaves)",
        labeled(&note_rows, "note_root (two leaves)")?,
        &mt_proof::notes::root_of(&[cm, second], depth)
            .ok_or("a commitment of the vector is no digest of the family")?,
    )?;
    Ok(())
}

pub const WALK_HEADER: &str = "**The walk of both trees, pinned away from position zero.**";
pub const APPEND_WALK_HEADER: &str = "**The walk of the append-only tree, at three leaves.**";
pub const RECORD_TREE_HEADER: &str =
    "**The tree of records, which a circuit walks and which therefore folds under its own pair of the";

// The fingerprint of a proof too long to stand raw in the set: bare SHA-256 of the
// canonical encoding, by the rule the walk block states.
fn sha256(bytes: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(bytes);
    h.finalize().into()
}

pub fn check_walks(md: &str) -> Result<(), String> {
    use mt_codec::encode::CanonicalEncode;

    let rows = parse_labeled(md, WALK_HEADER)?;

    let key = hex32(consumed(&rows, "record key")?)?;
    let record_cell = labeled(&rows, "record")?;
    let mut halves = record_cell.split(',');
    let record = repeat_bytes(halves.next().unwrap_or_default())?;
    let absent_cell = halves.next().unwrap_or_default();
    let absent = repeat32(
        absent_cell
            .split_once('=')
            .map(|(_, v)| v)
            .unwrap_or_default(),
    )?;

    let mut tree = mt_merkle::SparseTree::new(
        mt_codec::domain::MT_MERKLE_LEAF,
        mt_codec::domain::MT_MERKLE_NODE,
    );
    tree.insert(key, record)
        .map_err(|_| "the record of the walk vector is empty".to_string())?;
    let root = tree.root();
    compare_hash(
        "sparse root (one record)",
        labeled(&rows, "sparse root (one record)")?,
        &root,
    )?;

    let record_proof = tree.prove(&key);
    record_proof
        .verify(
            mt_codec::domain::MT_MERKLE_LEAF,
            mt_codec::domain::MT_MERKLE_NODE,
            &root,
        )
        .map_err(|e| format!("the record proof of the walk vector does not verify: {e:?}"))?;
    compare_hash(
        "record proof, SHA-256 of its encoding",
        labeled(&rows, "record proof, SHA-256 of its encoding")?,
        &sha256(&record_proof.encode()),
    )?;

    let absence_proof = tree.prove(&absent);
    if !absence_proof.leaf_value().is_empty() {
        return Err("the absent key of the walk vector holds a record".to_string());
    }
    absence_proof
        .verify(
            mt_codec::domain::MT_MERKLE_LEAF,
            mt_codec::domain::MT_MERKLE_NODE,
            &root,
        )
        .map_err(|e| format!("the absence proof of the walk vector does not verify: {e:?}"))?;
    compare_hash(
        "absence proof, SHA-256 of its encoding",
        labeled(&rows, "absence proof, SHA-256 of its encoding")?,
        &sha256(&absence_proof.encode()),
    )?;

    let depth = note_tree_depth()?;
    let append_rows = parse_labeled(md, APPEND_WALK_HEADER)?;
    let commitments_cell = labeled(&append_rows, "commitments at positions 0, 1 and 2")?;
    let mut append = mt_merkle::AppendTree::new(
        mt_codec::domain::MT_MERKLE_LEAF,
        mt_codec::domain::MT_MERKLE_NODE,
        depth,
    );
    for part in commitments_cell.split(',') {
        let commitment = repeat32(part)?;
        append
            .push(commitment)
            .map_err(|_| "the append tree of the walk vector is full".to_string())?;
    }
    let append_root = append.root();
    compare_hash(
        "append root (three leaves)",
        labeled(&append_rows, "append root (three leaves)")?,
        &append_root,
    )?;

    check_record_tree(md, &key, &tree)?;

    let position_proof = append
        .prove(2)
        .ok_or_else(|| "position 2 of the walk vector holds no leaf".to_string())?;
    position_proof
        .verify(
            mt_codec::domain::MT_MERKLE_LEAF,
            mt_codec::domain::MT_MERKLE_NODE,
            depth,
            &append_root,
        )
        .map_err(|e| format!("the proof of position 2 does not verify: {e:?}"))?;
    compare_hash(
        "proof of position 2, SHA-256 of its encoding",
        labeled(&append_rows, "proof of position 2, SHA-256 of its encoding")?,
        &sha256(&position_proof.encode()),
    )?;
    Ok(())
}

pub const SEED_HEADER: &str = "**The birth of a seed, end to end.**";
pub const WORD_LIST_HEADER: &str = "The canonical list holds 2 048 words";
pub const MASTER_SEED_HEADER: &str = "**The master seed.**";
pub const BRANCHES_HEADER: &str = "### The branches of a seed";

// Every stretch on this path takes an entropy the set publishes as a literal, so nothing here
// is a secret of any person; what the derivations answer is a wiping wrapper regardless.
// ZEROIZE-OK: a published literal of the set, held in Zeroizing by the derivation itself.
//
// The stretch is a million compressions and the gate is run by every test of it, so the digest
// is computed once per (entropy, salt, iterations) within a process and compared fresh every
// time: what the set states is judged on every call, and only work that cannot differ is shared.
// What decides the value of a stretch: the entropy, the salt and the count of iterations.
type StretchKey = ([u8; 32], String, u32);
type Stretched = std::sync::Mutex<Vec<(StretchKey, Vec<u8>)>>;

fn master_seed(entropy: &[u8; 32], salt: &str, iterations: u32) -> Vec<u8> {
    static CACHE: std::sync::OnceLock<Stretched> = std::sync::OnceLock::new();
    let cache = CACHE.get_or_init(|| std::sync::Mutex::new(Vec::new()));
    let key = (*entropy, salt.to_string(), iterations);
    if let Ok(held) = cache.lock() {
        if let Some((_, seed)) = held.iter().find(|(k, _)| *k == key) {
            return seed.clone();
        }
    }
    let stretched = mt_codec::derive::pbkdf2_sha256(entropy, salt.as_bytes(), iterations, 64);
    if let Ok(mut held) = cache.lock() {
        held.push((key, stretched.to_vec()));
    }
    stretched.to_vec()
}

// The salt and the count of iterations, read out of the fenced block that states them.
pub fn parse_master_seed_rule(md: &str) -> Result<(String, u32), String> {
    let body = section(md, MASTER_SEED_HEADER, &["\n**"])?;
    let open = body
        .find("```")
        .ok_or_else(|| "the master seed carries no fenced block".to_string())?;
    let fenced = &body[open + 3..];
    let close = fenced
        .find("```")
        .ok_or_else(|| "the master seed fence never closes".to_string())?;
    let block = &fenced[..close];
    let salt_at = block
        .find("salt = \"")
        .ok_or_else(|| "the master seed block names no salt".to_string())?;
    let rest = &block[salt_at + 8..];
    let salt_end = rest
        .find('"')
        .ok_or_else(|| "the salt of the master seed never closes".to_string())?;
    let salt = rest[..salt_end].to_string();
    let iter_at = block
        .find("iterations = ")
        .ok_or_else(|| "the master seed block names no count of iterations".to_string())?;
    let after = &block[iter_at + 13..];
    let iter_end = after.find([',', '\n']).unwrap_or(after.len());
    let iterations = u32::try_from(number(&after[..iter_end])?)
        .map_err(|e| format!("a count of iterations beyond a u32: {e}"))?;
    Ok((salt, iterations))
}

// The ten branches, read as (domain, length) in the order the block states them.
pub fn parse_branches(md: &str) -> Result<Vec<(String, usize)>, String> {
    let body = section(md, BRANCHES_HEADER, &["\n### "])?;
    let open = body
        .find("```")
        .ok_or_else(|| "the branches carry no fenced block".to_string())?;
    let fenced = &body[open + 3..];
    let close = fenced
        .find("```")
        .ok_or_else(|| "the fence of the branches never closes".to_string())?;
    let mut out = Vec::new();
    for line in fenced[..close].lines() {
        let line = line.trim();
        let Some(call) = line.find("HKDF-Expand(master_seed, \"") else {
            continue;
        };
        let rest = &line[call + 26..];
        let domain_end = rest
            .find('"')
            .ok_or_else(|| format!("a branch whose domain never closes: {line:?}"))?;
        let domain = rest[..domain_end].to_string();
        let after = &rest[domain_end + 1..];
        let comma = after
            .find(',')
            .ok_or_else(|| format!("a branch without its length: {line:?}"))?;
        let tail = &after[comma + 1..];
        let paren = tail
            .find(')')
            .ok_or_else(|| format!("a branch whose call never closes: {line:?}"))?;
        let length = usize::try_from(number(&tail[..paren])?)
            .map_err(|e| format!("a length beyond this machine: {e}"))?;
        out.push((domain, length));
    }
    if out.is_empty() {
        return Err("the block of the branches parsed to nothing".to_string());
    }
    Ok(out)
}

// The last link of the chain: the key a record answers with, generated from the signing branch
// the birth derived. With the suite landed it is computed rather than awaited, and the chain
// from words to key stands whole under the gate.
pub const RECORD_KEY_LINK: &str = "SHA-256(record_pk)";

// The chain of a birth and the values around it: the fingerprint of the word list, the rule of
// the stretch, the ten branches, the mixing of the stated sources, and the frozen digests from
// the entropy to the branch a record answers with.
pub fn check_seed(md: &str) -> Result<(), String> {
    let body = section(md, WORD_LIST_HEADER, &["\n**"])?;
    let open = body
        .find("```")
        .ok_or_else(|| "the word list carries no fenced fingerprint".to_string())?;
    let fenced = &body[open + 3..];
    let close = fenced
        .find("```")
        .ok_or_else(|| "the fingerprint of the word list never closes".to_string())?;
    // The label is the set's own line and not a phrase of this checker, and the block is read by
    // the one rule every reader of this gate uses: a comparison made under an invented label is a
    // line nobody read, and a block read by a second rule is a label nobody agrees on.
    let entries = labelled_entries(&fenced[..close])?;
    let (label, stated) = entries
        .first()
        .ok_or_else(|| "the word list block names no fingerprint".to_string())?;
    compare_hash(label, stated, &mt_seed::words::fingerprint())?;

    // The bound a timing source is judged by: the two integers the set writes into its integer
    // form, read out of that line rather than restated here.
    let line = md
        .lines()
        .find(|l| l.contains("n > 2 m") && l.contains("<="))
        .ok_or_else(|| "the set states no integer form of the bound".to_string())?;
    let (left, right) = line
        .split_once("<=")
        .ok_or_else(|| "the integer form of the bound carries no comparison".to_string())?;
    let numbers = |text: &str| -> Vec<u64> {
        let mut out = Vec::new();
        let mut digits = String::new();
        for c in text.chars() {
            if c.is_ascii_digit() {
                digits.push(c);
            } else if !digits.is_empty() {
                out.push(digits.parse().unwrap_or_default());
                digits.clear();
            }
        }
        if !digits.is_empty() {
            out.push(digits.parse().unwrap_or_default());
        }
        out
    };
    let stated_num = *numbers(left)
        .last()
        .ok_or_else(|| "the left side of the bound names no coefficient".to_string())?;
    let stated_den = *numbers(right)
        .first()
        .ok_or_else(|| "the right side of the bound names no coefficient".to_string())?;
    compare_number(
        "the coefficient of the bound",
        stated_num,
        u64::try_from(mt_seed::sources::CONFIDENCE_NUM)
            .map_err(|e| format!("a coefficient beyond eight bytes: {e}"))?,
    )?;
    compare_number(
        "the divisor of the bound",
        stated_den,
        u64::try_from(mt_seed::sources::CONFIDENCE_DEN)
            .map_err(|e| format!("a divisor beyond eight bytes: {e}"))?,
    )?;

    let (salt, iterations) = parse_master_seed_rule(md)?;
    if salt != mt_seed::seed_salt() {
        return Err(format!(
            "the salt of the master seed diverges: the set holds {salt:?}, the code holds {:?}",
            mt_seed::seed_salt()
        ));
    }
    if iterations != mt_seed::SEED_ITERATIONS {
        return Err(format!(
            "the iterations of the master seed diverge: the set holds {iterations}, the code holds {}",
            mt_seed::SEED_ITERATIONS
        ));
    }

    let branches = parse_branches(md)?;
    let held = mt_seed::Branch::ALL;
    if branches.len() != held.len() {
        return Err(format!(
            "the set states {} branches and the code holds {}",
            branches.len(),
            held.len()
        ));
    }
    for (i, ((domain, length), branch)) in branches.iter().zip(held.iter()).enumerate() {
        if domain != branch.domain().as_str() {
            return Err(format!(
                "branch divergence at row {}: the set expands `{domain}`, the code expands `{}`",
                i + 1,
                branch.domain().as_str()
            ));
        }
        if *length != branch.length() {
            return Err(format!(
                "branch divergence at `{domain}`: the set takes {length} bytes, the code takes {}",
                branch.length()
            ));
        }
    }

    let chain = parse_labeled(md, SEED_HEADER)?;
    let of_one_byte: [u8; 32] = parse_part(labeled(&chain, "entropy")?)?
        .try_into()
        .map_err(|_| "the entropy of the first chain is not thirty-two bytes".to_string())?;
    let of_distinct: [u8; 32] = parse_part(consumed(&chain, "entropy of distinct bytes")?)?
        .try_into()
        .map_err(|_| "the entropy of the second chain is not thirty-two bytes".to_string())?;
    // Each living source stands at its place in the table: `0 : 0x01 x 32, 1 : 0x02 x 32, ...`.
    let mut living: Vec<(u8, Vec<u8>)> = Vec::new();
    for stated in labeled(&chain, "living sources")?.split(',') {
        let (place, part) = stated
            .split_once(':')
            .ok_or_else(|| format!("a living source without its place: {stated:?}"))?;
        let place =
            u8::try_from(number(place)?).map_err(|e| format!("a place beyond a byte: {e}"))?;
        living.push((place, parse_part(part)?));
    }
    // ZEROIZE-OK: every entropy here is a literal the set publishes, and the derivations answer
    // wiping wrappers regardless; no secret of a person stands on this path.
    let link = |entropy: &[u8; 32], label: &str, value: &str| -> Result<(), String> {
        let seed = master_seed(entropy, &salt, iterations);
        match label {
            "SHA-256(the 24 words)" | "SHA-256(the 24 words of it)" => compare_hash(
                label,
                value,
                &sha256(mt_seed::words::phrase(entropy).as_bytes()),
            ),
            "SHA-256(master_seed)" | "SHA-256(its master_seed)" => {
                compare_hash(label, value, &sha256(&seed))
            }
            "SHA-256(signing branch)" | "SHA-256(its signing branch)" => compare_hash(
                label,
                value,
                &sha256(&mt_seed::branch(&seed, mt_seed::Branch::Signing)),
            ),
            "SHA-256(its encryption branch)" => compare_hash(
                label,
                value,
                &sha256(&mt_seed::branch(&seed, mt_seed::Branch::Encryption)),
            ),
            "SHA-256(record_pk)" => {
                let branch = mt_seed::branch(&seed, mt_seed::Branch::Signing);
                let signing: [u8; mt_suite::sign::SEED_BYTES] = branch[..]
                    .try_into()
                    .map_err(|_| "the signing branch is not the width a key is seeded from")?;
                let (public, _) = mt_suite::sign::keypair_from_seed(&signing);
                compare_hash(label, value, &sha256(public.as_bytes()))
            }
            other => Err(format!(
                "the chain of a birth names {other:?}, which the checker does not hold"
            )),
        }
    };
    for (label, value) in &chain {
        match label.as_str() {
            "entropy" | "entropy of distinct bytes" | "living sources" => {}
            "entropy_32" => {
                let parts: Vec<(u8, &[u8])> =
                    living.iter().map(|(p, b)| (*p, b.as_slice())).collect();
                let mixed = mt_seed::sources::mix_of_stated_sources(&parts).ok_or_else(|| {
                    "a source of the vector is longer than the field its length is written in"
                        .to_string()
                })?;
                compare_hash(label, value, &mixed)?;
            }
            l if l.contains("of it") || l.starts_with("SHA-256(its") => {
                link(&of_distinct, l, value)?
            }
            l => link(&of_one_byte, l, value)?,
        }
    }
    if !chain.iter().any(|(l, _)| l == RECORD_KEY_LINK) {
        return Err(format!(
            "the chain of a birth no longer names {RECORD_KEY_LINK}: its last link has moved"
        ));
    }
    Ok(())
}

pub const COMMIT_VECTORS_HEADER: &str = "**The vectors of the commitment.**";
pub const WIRE_VECTORS_HEADER: &str = "**The vectors of the wire.**";

pub const HANDSHAKE_HEADER: &str = "**The post-quantum handshake.**";
pub const HOLDER_HEADER: &str = "**The holder of a tag.**";

// The vectors of the wire: the label of a step, both seals of a cell, the parity of a group and
// the reconstruction the code of a delivery promises. Every input is read out of the set.
pub fn check_wire(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, WIRE_VECTORS_HEADER)?;
    let inputs = labeled(&rows, "step_key")?;
    let step_key = repeat32(bare_input(inputs))?;
    let pipe_key = input32(inputs, "pipe_key")?;
    let handshake = input32(inputs, "handshake_secret")?;
    let window = window_of(inputs)?;
    let step_label = mt_derive::tag::step_label(&handshake, window);
    compare16("step_label", labeled(&rows, "step_label")?, step_label)?;

    // The two nonces, the commitment the cell is for, and the array of seals as the set writes it.
    let nonces = labeled(&rows, "outer_nonce")?;
    let outer_nonce: [u8; 12] = parse_part(bare_input(nonces))?
        .try_into()
        .map_err(|_| "the outer nonce of the vector is not twelve bytes".to_string())?;
    let inner_nonce: [u8; 12] = parse_part(input_of(nonces, "inner_nonce")?)?
        .try_into()
        .map_err(|_| "the inner nonce of the vector is not twelve bytes".to_string())?;
    let routing_inputs = labeled(&rows, "target_commit")?;
    let target_commit = repeat32(bare_input(routing_inputs))?;
    let seals_cell = input_of(routing_inputs, "seals")?;
    let first_seal = u8::from_str_radix(
        seals_cell
            .trim()
            .trim_start_matches("0x")
            .get(..2)
            .ok_or_else(|| format!("the seals of the vector are unreadable: {seals_cell:?}"))?,
        16,
    )
    .map_err(|e| format!("the first seal of the vector is not a byte: {e}"))?;
    let slots = mt_wire::path_max().map_err(|e| format!("the wire cannot read the Decree: {e:?}"))?;
    let seals: Vec<[u8; 16]> = (0..slots)
        .map(|slot| [first_seal.wrapping_add(slot as u8); 16])
        .collect();

    // The delivery layer, and the chunk the set describes by its first byte.
    let delivery_inputs = labeled(&rows, "delivery_id")?;
    let delivery_id: [u8; 16] = parse_part(bare_input(delivery_inputs))?
        .try_into()
        .map_err(|_| "the identifier of the vector is not sixteen bytes".to_string())?;
    let block_index = u16::try_from(number(input_of(delivery_inputs, "block_index")?)?)
        .map_err(|e| format!("a block index beyond two bytes: {e}"))?;
    let block_count = u16::try_from(number(input_of(delivery_inputs, "block_count")?)?)
        .map_err(|e| format!("a count of blocks beyond two bytes: {e}"))?;
    let chunk_cell = labeled(&rows, "chunk")?;
    let chunk_first = chunk_cell
        .split("0x")
        .nth(1)
        .and_then(|tail| tail.get(..2))
        .ok_or_else(|| format!("the chunk of the vector is unreadable: {chunk_cell:?}"))?;
    let chunk_first = u8::from_str_radix(chunk_first, 16)
        .map_err(|e| format!("the first byte of the chunk is not a byte: {e}"))?;
    let width = mt_wire::chunk_bytes().map_err(|e| format!("the wire cannot read the Decree: {e:?}"))?;
    let chunk: Vec<u8> = (0..width)
        .map(|i| chunk_first.wrapping_add((i % 256) as u8))
        .collect();

    let delivery = mt_wire::cell::Delivery {
        delivery_id,
        block_index,
        block_count,
        chunk,
    };
    let inner = mt_wire::cell::seal_pipe_with_nonce(&pipe_key, &inner_nonce, &delivery)
        .map_err(|e| format!("the pipe of the vector does not seal: {e:?}"))?;
    compare_hash("SHA-256(inner)", labeled(&rows, "SHA-256(inner)")?, &sha256(&inner))?;

    let routing = mt_wire::cell::Routing {
        target_commit,
        seals,
        inner,
    };
    let cell = mt_wire::cell::seal_cell_with_nonce(&step_key, &step_label, &outer_nonce, &routing)
        .map_err(|e| format!("the cell of the vector does not seal: {e:?}"))?;
    compare_hash(
        "SHA-256(cell)",
        labeled(&rows, "SHA-256(cell)")?,
        &sha256(cell.as_bytes()),
    )?;

    // The erasure code: the parity of the frozen group, and the reconstruction of it.
    let blocks_cell = labeled(&rows, "erasure: block[j]")?;
    let block_first = blocks_cell
        .split("0x")
        .nth(1)
        .and_then(|tail| tail.get(..2))
        .ok_or_else(|| format!("the blocks of the vector are unreadable: {blocks_cell:?}"))?;
    let block_first = u8::from_str_radix(block_first, 16)
        .map_err(|e| format!("the first block of the vector is not a byte: {e}"))?;
    let data = mt_wire::erasure::data().map_err(|e| format!("the wire cannot read the Decree: {e:?}"))?;
    let body: Vec<Vec<u8>> = (0..data)
        .map(|j| vec![block_first.wrapping_add(j as u8); width])
        .collect();
    let parity = mt_wire::erasure::parity(&body)
        .map_err(|e| format!("the group of the vector does not encode: {e:?}"))?;
    let stated_heads = labeled(&rows, "parity[0 .. 3] first four bytes")?;
    verified_note("parity[0 .. 3] first four bytes", stated_heads);
    for (at, stated) in stated_heads.split(',').enumerate() {
        let computed: String = parity[at][..4].iter().map(|b| format!("{b:02x}")).collect();
        if stated.trim() != computed {
            return Err(format!(
                "wire divergence at parity {at}: the set holds {}, the code computes {computed}",
                stated.trim()
            ));
        }
    }
    let mut joined = Vec::new();
    for block in &parity {
        joined.extend_from_slice(block);
    }
    compare_hash(
        "SHA-256(parity[0] || parity[1] || parity[2] || parity[3])",
        labeled(&rows, "SHA-256(parity[0] || parity[1] || parity[2] || parity[3])")?,
        &sha256(&joined),
    )?;
    // The reconstruction the set states: the twelve remaining when four are lost return the body.
    let whole = mt_wire::erasure::encode(&body)
        .map_err(|e| format!("the group of the vector does not encode: {e:?}"))?;
    let lost = [0usize, 5, 7, 11];
    let present: Vec<(usize, Vec<u8>)> = whole
        .iter()
        .enumerate()
        .filter(|(position, _)| !lost.contains(position))
        .map(|(position, block)| (position, block.clone()))
        .collect();
    let back = mt_wire::erasure::reconstruct(&present)
        .map_err(|e| format!("the group of the vector does not reconstruct: {e:?}"))?;
    if back != body {
        return Err("wire divergence: the group of the vector reconstructs to other blocks".to_string());
    }

    // The four flights and the two directional keys.
    let hs = parse_labeled(md, HANDSHAKE_HEADER)?;
    let named = labeled(&hs, "suite_id")?;
    let suite_id = u16::try_from(leading_number(bare_input(named))?)
        .map_err(|e| format!("a suite beyond two bytes: {e}"))?;
    let id_pk_i = fixed_part(input_of(named, "id_pk_i")?)?;
    let id_pk_r = fixed_part(input_of(named, "id_pk_r")?)?;
    let keys = labeled(&hs, "pk_i")?;
    let pk_i = fixed_part(bare_input(keys))?;
    let pk_r = fixed_part(input_of(keys, "pk_r")?)?;
    let ct_i = fixed_part(input_of(keys, "ct_i")?)?;
    let ct_r = fixed_part(input_of(keys, "ct_r")?)?;
    let secrets = labeled(&hs, "ss_i")?;
    let ss_i = repeat32(bare_input(secrets))?;
    let ss_r = repeat32(input_of(secrets, "ss_r")?)?;
    let transcript = mt_wire::handshake::transcript(
        suite_id, &id_pk_i, &id_pk_r, &pk_i, &pk_r, &ct_i, &ct_r,
    );
    compare_hash("transcript", labeled(&hs, "transcript")?, &transcript)?;
    let master = mt_wire::handshake::master(&ss_i, &ss_r, &transcript);
    compare_hash("master", labeled(&hs, "master")?, &master)?;
    compare_hash(
        "k_i2r",
        labeled(&hs, "k_i2r")?,
        &mt_wire::handshake::initiator_to_responder(&master),
    )?;
    compare_hash(
        "k_r2i",
        labeled(&hs, "k_r2i")?,
        &mt_wire::handshake::responder_to_initiator(&master),
    )?;

    // The machine standing at a point, and the ring that wraps.
    let holder_rows = parse_labeled(md, HOLDER_HEADER)?;
    let set_cell = labeled(&holder_rows, "S")?;
    let inside = set_cell
        .split('{')
        .nth(1)
        .and_then(|c| c.split('}').next())
        .ok_or_else(|| format!("the living set of the vector is unreadable: {set_cell:?}"))?;
    let living: Vec<[u8; 32]> = inside
        .split(',')
        .map(repeat32)
        .collect::<Result<Vec<_>, _>>()?;
    let mut holders_walked = 0;
    for (label, value) in &holder_rows {
        if label != "tag" {
            continue;
        }
        let (tag_cell, answer) = value
            .split_once("->")
            .ok_or_else(|| format!("the holder of the vector is unreadable: {value:?}"))?;
        // The set writes one of the two tags in hex and the other as a repeated byte without the
        // prefix a repeated pattern usually carries; both are read here and neither is restated.
        let trimmed = tag_cell.trim();
        let bytes = if trimmed.contains(" x ") {
            let spelled = if trimmed.starts_with("0x") {
                trimmed.to_string()
            } else {
                format!("0x{trimmed}")
            };
            repeat_bytes(&spelled)?
        } else {
            parse_part(trimmed)?
        };
        let tag: [u8; 16] = bytes
            .try_into()
            .map_err(|_| format!("the tag of the vector is not sixteen bytes: {tag_cell:?}"))?;
        let stated = answer
            .split("the commitment")
            .nth(1)
            .ok_or_else(|| format!("the holder of the vector names no commitment: {answer:?}"))?;
        let stated = repeat32(
            stated
                .split(&['(', ')'][..])
                .next()
                .unwrap_or(stated),
        )?;
        let computed = mt_derive::pulse::holder(&tag, &living)
            .ok_or_else(|| "the living set of the vector is empty".to_string())?;
        if computed != stated {
            return Err(format!(
                "wire divergence at the holder of a tag: the set holds {}, the code computes {}",
                hex(&stated),
                hex(&computed)
            ));
        }
        holders_walked += 1;
    }
    if holders_walked < 2 {
        return Err(format!(
            "the block of the holder freezes {holders_walked} answers, which is too few"
        ));
    }
    Ok(())
}

// The node of the fold: its identifier over the bytes the set states, and the work vector that
// names which machine produces which node. The lattice values of the same block await the suite
// and are named so in the coverage pass.
pub fn check_fold(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, FOLD_HEADER)?;
    let inputs = labeled(&rows, "left")?;
    let left = repeat_bytes(bare_input(inputs))?;
    let right = repeat_bytes(input_of(inputs, "right")?)?;
    let commitment = repeat_bytes(input_of(inputs, "commitment")?)?;
    let proof = repeat_bytes(input_of(inputs, "proof")?)?;
    if commitment.len() != mt_state::WEIGHT_COMMIT_BYTES {
        return Err(format!(
            "fold divergence: the set states a commitment of {} B, the code holds {} B",
            commitment.len(),
            mt_state::WEIGHT_COMMIT_BYTES
        ));
    }
    if proof.len() != mt_state::PROOF_LEN {
        return Err(format!(
            "fold divergence: the set states a proof of {} B, the code holds {} B",
            proof.len(),
            mt_state::PROOF_LEN
        ));
    }
    verified_note_number("PROOF_LEN", mt_state::PROOF_LEN as u64);
    // The bytes are taken as they were read and never round-tripped through their hex: a value
    // written to be parsed again would be noted as one the set states, and the set states a
    // repeated byte here rather than sixty-four characters of it.
    let width = |what: &str, v: &[u8]| format!("the {what} of the fold is {} B where 32 stand", v.len());
    let node = mt_state::layout::FoldNode {
        left: <[u8; 32]>::try_from(left.as_slice()).map_err(|_| width("left", &left))?,
        right: <[u8; 32]>::try_from(right.as_slice()).map_err(|_| width("right", &right))?,
        commitment,
        proof,
    };
    let id = node
        .id()
        .map_err(|e| format!("the node of the fold is not an object of this protocol: {e:?}"))?;
    compare_hash("fold_node_id", labeled(&rows, "fold_node_id")?, &id)?;

    let commit_rows = parse_labeled(md, COMMIT_VECTORS_HEADER)?;
    let mut work_walked = 0;
    for (label, value) in &commit_rows {
        let Some(rest) = label.strip_prefix("fold_work(") else {
            continue;
        };
        let call = rest.trim_end_matches(')');
        let window = number(input_of(call, "W")?)?;
        let level = u8::try_from(number(input_of(call, "level")?)?)
            .map_err(|e| format!("a level beyond a byte: {e}"))?;
        let index = number(input_of(call, "index")?)?;
        compare_hash(label, value, &mt_derive::fold_work(window, level, index))?;
        work_walked += 1;
    }
    if work_walked == 0 {
        return Err("the block of the commitment freezes no work vector".to_string());
    }
    Ok(())
}

pub const STANDING_HEADER: &str = "### The commitment that carries standing";

// The number a cell opens with, prose after it ignored: the set writes a parameter and then
// speaks about it on the same line.
fn leading_number(text: &str) -> Result<u64, String> {
    let t = text.trim();
    let end = t
        .char_indices()
        .find(|(_, c)| !c.is_ascii_digit() && *c != ' ')
        .map(|(i, _)| i)
        .unwrap_or(t.len());
    number(&t[..end])
}

// An affine formula of the set, `((a t + idx + b) mod m) - s`, read from its text: the
// coefficient of t, the constant, the modulus and the shift. The index name between them is
// positional — the first formula of a row draws r1 over j, the second r2 over i.
fn affine(text: &str) -> Result<Option<(u64, u64, u64, u64)>, String> {
    let Some(open) = text.find("((") else {
        return Ok(None);
    };
    let inner = &text[open + 2..];
    let Some(close) = inner.find(") mod ") else {
        return Ok(None);
    };
    let expr = &inner[..close];
    let after = &inner[close + 6..];
    let Some(paren) = after.find(')') else {
        return Ok(None);
    };
    let modulus = number(&after[..paren])?;
    let tail = &after[paren + 1..];
    let dash = tail
        .find('-')
        .ok_or_else(|| format!("a formula without its shift: {text:?}"))?;
    let shift = leading_number(&tail[dash + 1..])?;
    let mut coefficient = 1u64;
    let mut constant = 0u64;
    for token in expr.split('+').map(str::trim) {
        if let Some(head) = token.strip_suffix('t') {
            let head = head.trim();
            coefficient = if head.is_empty() { 1 } else { number(head)? };
        } else if token.bytes().all(|b| b.is_ascii_digit()) && !token.is_empty() {
            constant = number(token)?;
        }
    }
    Ok(Some((coefficient, constant, modulus, shift)))
}

// The commitment that carries standing: the parameters of the set against the code, the seed
// and the first coefficients of the matrix, and the three frozen commitments — two children
// and the node that folds them, each recomputed from the formulas the set writes.
// The serialization of the first frozen commitment of the set: the cement state of the beacon
// vector is that value, so it is computed once here and read by both checks that need it.
pub fn standing_first_commitment(md: &str) -> Result<Vec<u8>, String> {
    let rows = parse_labeled(md, COMMIT_VECTORS_HEADER)?;
    let (formulas, values) = standing_rows(&rows)?;
    let [a1, b1, m1, s1, a2, b2, m2, s2] = formulas[0];
    let r1: [[i8; mt_suite::standing::D]; mt_suite::standing::K] = core::array::from_fn(|j| {
        core::array::from_fn(|t| (((a1 * t as u64 + j as u64 + b1) % m1) as i64 - s1 as i64) as i8)
    });
    let r2: [[i8; mt_suite::standing::D]; mt_suite::standing::N] = core::array::from_fn(|i| {
        core::array::from_fn(|t| (((a2 * t as u64 + i as u64 + b2) % m2) as i64 - s2 as i64) as i8)
    });
    Ok(mt_suite::standing::commit(values[0], &r1, &r2)
        .map_err(|e| format!("the randomness of the set leaves the bound: {e:?}"))?
        .serialize())
}

// The rows of formulas and the values they commit to, read once for every check that needs
// them: a second reading would be a second place the shape of that block lives.
// The rows of one commitment of the set: the two affine formulas its randomness is drawn by, and
// the three values it carries.
type StandingRows = (Vec<[u64; 8]>, Vec<[u64; 3]>);

fn standing_rows(rows: &[(String, String)]) -> Result<StandingRows, String> {
    let mut formulas: Vec<[u64; 8]> = Vec::new();
    let mut values: Vec<[u64; 3]> = Vec::new();
    for (label, value) in rows {
        let whole = format!("{label} = {value}");
        // A row states the three values a commitment carries, whether beside its formulas or on
        // a line of its own; both spellings are one rule here, so neither is a second place.
        if let Some((_, tail)) = whole.rsplit_once("values =") {
            let stated: Vec<&str> = tail.split(',').collect();
            if stated.len() != mt_suite::standing::VALUES {
                return Err(format!(
                    "a commitment of the set carries {} values where {} stand: {whole:?}",
                    stated.len(),
                    mt_suite::standing::VALUES
                ));
            }
            let mut triple = [0u64; 3];
            for (slot, cell) in triple.iter_mut().zip(stated.iter()) {
                *slot = number(cell)?;
            }
            // A row that states its values alone is a frozen line like any other, and the
            // coverage pass counts it read here rather than anywhere else.
            verified_note(label, value);
            values.push(triple);
        }
        let Some(first) = affine(&whole)? else {
            continue;
        };
        let Some(mod_at) = whole.find(") mod ") else {
            continue;
        };
        let second = affine(&whole[mod_at + 6..])?
            .ok_or_else(|| format!("a row with one formula where two stand: {whole:?}"))?;
        formulas.push([
            first.0, first.1, first.2, first.3, second.0, second.1, second.2, second.3,
        ]);
    }
    if formulas.len() != 3 || values.len() != 3 {
        return Err(format!(
            "the block of the commitment states {} formula rows and {} triples of values",
            formulas.len(),
            values.len()
        ));
    }
    Ok((formulas, values))
}

pub fn check_standing(md: &str) -> Result<(), String> {
    use mt_suite::standing;

    let body = section(md, STANDING_HEADER, &["\n### ", "\n## "])?;
    let open = body
        .find("```")
        .ok_or_else(|| "the standing commitment carries no fenced block".to_string())?;
    let fenced = &body[open + 3..];
    let close = fenced
        .find("```")
        .ok_or_else(|| "the fence of the standing commitment never closes".to_string())?;
    let block = &fenced[..close];
    let params = block
        .lines()
        .find(|l| l.trim_start().starts_with("d = "))
        .ok_or_else(|| "the standing commitment names no parameters".to_string())?;
    let cell = params.split_once('=').map(|(_, v)| v).unwrap_or_default();
    for (label, stated, held) in [
        ("d", leading_number(cell)?, standing::D as u64),
        (
            "q",
            leading_number(input_of(params, "q")?)?,
            u64::from(standing::Q),
        ),
        ("n", leading_number(input_of(params, "n")?)?, standing::N as u64),
        ("k", leading_number(input_of(params, "k")?)?, standing::K as u64),
        (
            "eta",
            leading_number(input_of(params, "eta")?)?,
            standing::ETA as u64,
        ),
    ] {
        compare_number(label, stated, held)?;
    }

    // The number the construction owns rather than cites, and the shape it lays a value in. The
    // lift is what the binding argument of the set rests on for the case the matrix does not
    // enter, so a set that moved it would be a set this code no longer transcribes.
    let tail_number = |name: &str| -> Result<u64, String> {
        let line = block
            .lines()
            .find(|l| l.trim_start().starts_with(name))
            .ok_or_else(|| format!("the standing commitment names no {name}"))?;
        leading_number(
            line.rsplit_once('=')
                .map(|(_, v)| v.trim())
                .unwrap_or_default(),
        )
    };
    compare_number("lift", tail_number("lift")?, u64::from(standing::LIFT))?;
    compare_number(
        "max_openable_summands",
        tail_number("max_openable_summands")?,
        standing::MAX_OPENABLE_SUMMANDS,
    )?;
    let widths = block
        .lines()
        .find(|l| l.trim_start().starts_with("value_digits"))
        .ok_or_else(|| "the standing commitment names no width of a value".to_string())?;
    compare_number(
        "value_digits",
        number(input_of(widths, "value_digits")?)?,
        standing::VALUE_DIGITS as u64,
    )?;
    compare_number(
        "values",
        leading_number(input_of(widths, "values")?)?,
        standing::VALUES as u64,
    )?;

    let width = block
        .lines()
        .find(|l| l.trim_start().starts_with("weight_commit_bytes"))
        .ok_or_else(|| "the standing commitment names no width".to_string())?;
    let stated_width = number(
        width
            .rsplit_once('=')
            .map(|(_, v)| v.trim().trim_end_matches('B').trim())
            .unwrap_or_default(),
    )? as usize;
    if stated_width != standing::SERIALIZED_LEN || stated_width != mt_state::WEIGHT_COMMIT_BYTES {
        return Err(format!(
            "width divergence at `weight_commit_bytes`: the set states {stated_width} B, the code holds {} B",
            standing::SERIALIZED_LEN
        ));
    }

    let rows = parse_labeled(md, COMMIT_VECTORS_HEADER)?;
    compare_hash(
        "matrix_seed",
        labeled(&rows, "matrix_seed")?,
        &standing::matrix_seed(),
    )?;
    let coefficients = labeled(&rows, "A[0][0] first four coefficients")?;
    verified_note("A[0][0] first four coefficients", coefficients);
    let held = standing::matrix_coefficients(0, 0);
    for (at, cell) in coefficients.split(',').enumerate().take(4) {
        compare_number(
            &format!("A[0][0] coefficient {at}"),
            number(cell)?,
            u64::from(held[at]),
        )?;
    }

    // The commitment a machine keeps about itself: its three quantities and the blinding factor
    // its randomness is expanded from, both read out of the set.
    let inputs = labeled(&rows, "weight_commit inputs")?;
    verified_note("weight_commit inputs", inputs);
    let standing_value = number(input_of(inputs, "standing")?)?;
    let granted = number(input_of(inputs, "granted")?)?;
    let last = number(input_of(inputs, "last")?)?;
    let blind = input32(inputs, "blind")?;
    let (expanded_r1, _) = standing::expand(&blind);
    let expansion = labeled(&rows, "r1 from that blind, first four coefficients")?;
    verified_note("r1 from that blind, first four coefficients", expansion);
    for (at, stated) in expansion.split(',').enumerate().take(4) {
        let held: i64 = stated
            .trim()
            .parse()
            .map_err(|e| format!("not a coefficient: {stated:?} ({e})"))?;
        if held != i64::from(expanded_r1[0][at]) {
            return Err(format!(
                "divergence at `r1 from that blind` coefficient {at}: the set holds {held}, the code computes {}",
                expanded_r1[0][at]
            ));
        }
    }
    compare_hash(
        "SHA-256(serialize(weight_commit)), over the inputs above",
        labeled(&rows, "SHA-256(serialize(weight_commit)), over the inputs above")?,
        &sha256(
            &standing::weight_commit(
                standing_value,
                granted,
                last,
                standing::Blind::of(blind, last),
            )
                .map_err(|e| format!("the expansion of the set leaves the bound: {e:?}"))?
                .serialize(),
        ),
    )?;

    // The three commitments: each row of formulas carries r1 and r2, and the values it commits
    // to stand beside them or on the line below, both read as one rule.
    let (formulas, values) = standing_rows(&rows)?;
    let expected = [
        "SHA-256(serialize(the first commitment))",
        "SHA-256(serialize(the second commitment))",
        "SHA-256(serialize(the node))",
    ];
    for (which, ([a1, b1, m1, s1, a2, b2, m2, s2], triple)) in
        formulas.iter().zip(values.iter()).enumerate()
    {
        let r1: [[i8; standing::D]; standing::K] = core::array::from_fn(|j| {
            core::array::from_fn(|t| {
                (((a1 * t as u64 + j as u64 + b1) % m1) as i64 - *s1 as i64) as i8
            })
        });
        let r2: [[i8; standing::D]; standing::N] = core::array::from_fn(|i| {
            core::array::from_fn(|t| {
                (((a2 * t as u64 + i as u64 + b2) % m2) as i64 - *s2 as i64) as i8
            })
        });
        let commitment = standing::commit(*triple, &r1, &r2)
            .map_err(|e| format!("the randomness of the set leaves the bound: {e:?}"))?;
        compare_hash(
            expected[which],
            labeled(&rows, expected[which])?,
            &sha256(&commitment.serialize()),
        )?;
    }
    Ok(())
}

// The frozen value of the Genesis State Hash: the last `= <hex>` line of the fenced block
// under its bold header.
pub fn parse_genesis_state_hash(md: &str) -> Result<Option<String>, String> {
    let body = section(md, "**The Genesis State Hash**", &["\n**"])?;
    let fence_open = body
        .find("```")
        .ok_or_else(|| "the Genesis State Hash carries no fenced block".to_string())?;
    let fenced = &body[fence_open + 3..];
    let fence_close = fenced
        .find("```")
        .ok_or_else(|| "the Genesis State Hash fence never closes".to_string())?;
    let mut value = None;
    for line in fenced[..fence_close].lines() {
        let line = line.trim();
        if line.starts_with("published_parameters") {
            break;
        }
        if let Some(rest) = line.strip_prefix("= ") {
            value = Some(rest.trim().to_string());
        }
    }
    Ok(value)
}

// The digest of the parameters that are published, stated in the same block.
pub fn parse_published_parameters(md: &str) -> Result<String, String> {
    let body = section(md, "**The Genesis State Hash**", &["\n**"])?;
    let at = body
        .find("published_parameters = ")
        .ok_or_else(|| "the set states no digest of the published parameters".to_string())?;
    let rest = &body[at..];
    let equals = rest
        .rfind("= ")
        .and_then(|_| rest.split_once("\n").map(|(_, tail)| tail))
        .ok_or_else(|| "the digest of the published parameters carries no value".to_string())?;
    for line in rest.lines().chain(equals.lines()) {
        let line = line.trim();
        if let Some(v) = line.strip_prefix("= ") {
            let v = v.trim();
            if v.len() == 64 && v.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Ok(v.to_string());
            }
        }
    }
    Err("the digest of the published parameters carries no value".to_string())
}

// The Genesis State Hash while the Decree is incomplete: what the set may state is the digest of
// the parameters that exist, and what it may **not** state is a value of the hash itself. Both
// halves are held here — a set that froze a value over a parameter it does not have would be
// freezing a number no chain can open on, and that is exactly the state this refuses.
pub fn check_genesis_state_hash(md: &str) -> Result<(), String> {
    let unpublished = mt_genesis::unpublished();
    match (parse_genesis_state_hash(md)?, mt_state::tables::genesis_state_hash()) {
        (Some(stated), Some(held)) => compare_hash("genesis_state_hash", &stated, &held)?,
        (None, None) => {
            if unpublished.is_empty() {
                return Err(
                    "the Decree is complete and no Genesis State Hash is stated or computed"
                        .to_string(),
                );
            }
        }
        (Some(stated), None) => {
            return Err(format!(
                "the set states a Genesis State Hash of {stated} while the code holds none: \
                 {} parameter(s) of the Decree are unpublished, so no chain opens",
                unpublished.len()
            ));
        }
        (None, Some(held)) => {
            return Err(format!(
                "the code computes a Genesis State Hash of {} while the set states none",
                hex(&held)
            ));
        }
    }
    // The digest of the parameters as they stand: what holds the encoding of everything that does
    // exist to the set today rather than on the day the last parameter lands.
    compare_hash(
        "published_parameters",
        &parse_published_parameters(md)?,
        &mt_state::tables::published_parameters_digest(),
    )
}

// The sizes of the primitives, read out of the tables of the set and compared each at its own
// row and column: a size that merely appears somewhere is not a size that stands at its place,
// and two rows swapping their values is exactly the divergence a bag of numbers cannot see.
// Every size of the protocol, read at the block that holds it and enumerated by name rather than
// counted: the widths of a scheme at the row of its suite, the width of a hash and the size of a
// cell at their rows of the Decree, and the widths of a label, a seal, a nonce and a tag at the row
// of the form table. A count in this place would pass a set that lost a row as readily as one that
// kept it.
pub fn check_sizes(md: &str) -> Result<(), String> {
    use mt_codec::size;
    // The rows of the Decree that carry a width, each read by its own name.
    for (row, held) in [("hash_bytes", size::HASH)] {
        match mt_genesis::scalar(row) {
            Some(width) if width as usize == held => verified_note_number(row, width),
            Some(width) => {
                return Err(format!(
                    "size divergence at `{row}`: the Decree states {width} B, the code holds {held} B"
                ))
            }
            None => return Err(format!("the Decree names no `{row}`")),
        }
    }
    // The widths the row of the form table carries, each read at its own name in that row.
    let body = section(md, "### The form table", &["\n### ", "\n## "])?;
    let row = body
        .lines()
        .find(|line| line.trim_start().starts_with("| 1 |"))
        .ok_or("the form table states no first row")?;
    for (what, held) in [
        ("a label of a step", size::TAG),
        ("a seal of a step", size::STEP_SEAL),
        ("an AEAD nonce", size::AEAD_NONCE),
        ("an AEAD tag", size::AEAD_TAG),
    ] {
        let at = row
            .find(what)
            .ok_or_else(|| format!("the row of the form table names no width of {what}"))?;
        let stated = number(
            row[at + what.len()..]
                .split_whitespace()
                .next()
                .ok_or_else(|| format!("the width of {what} is not written after its name"))?,
        )? as usize;
        if stated != held {
            return Err(format!(
                "size divergence at {what}: the set states {stated} B, the code holds {held} B"
            ));
        }
        verified_note(what, &format!("{stated} B"));
    }
    Ok(())
}

// The two layouts the set freezes whole: their length and the digest of their canonical bytes. A
// length alone cannot catch a field in the wrong order — the total is the same and the object is
// another — so what the gate compares here is the bytes.
pub fn check_serialized_layouts(md: &str) -> Result<(), String> {
    use mt_state::layout::*;
    use mt_state::Layout;

    let rows = parse_labeled(md, PROPOSAL_HEADER)?;
    let window = number(input_of(labeled(&rows, "window")?, "window").unwrap_or("1000"))?;
    let proposal = Proposal {
        window,
        protocol_version: 0x0001_0000,
        previous: [0x11; 32],
        final_beacon: [0x22; 32],
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: [0x77; 32],
        operations_root: [0x88; 32],
        suite_id: 1,
        runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0x00; mt_state::PROOF_LEN],
        signature: vec![0x5E; mt_codec::size::SIGNATURE],
    };
    let bytes = proposal.encode();
    let stated_proposal = labeled(&rows, "proposal_len")?;
    verified_note("proposal_len", stated_proposal);
    let stated_len = number(stated_proposal)? as usize;
    if stated_len != bytes.len() {
        return Err(format!(
            "layout divergence at `proposal_len`: the set states {stated_len} B, the code serializes {} B",
            bytes.len()
        ));
    }
    compare_hash(
        "SHA-256 of the serialized proposal",
        labeled(&rows, "SHA-256 of the serialized proposal")?,
        &sha256(&bytes),
    )?;
    // The identifier stands over the deterministic fields alone; an implementation hashing the
    // whole object reproduces the serialization hash above and misses this one.
    compare_hash(
        "proposal_id over the deterministic 2 222 bytes",
        labeled(&rows, "proposal_id over the deterministic 2 222 bytes")?,
        &proposal
            .id()
            .map_err(|e| format!("the identifier of the frozen proposal does not compute: {e:?}"))?,
    )?;

    // The proof of a window, carried apart: its length, its bytes, and its identifier.
    let rows = parse_labeled(md, WINDOW_PROOF_HEADER)?;
    let held = WindowProof {
        window: number(input_of(labeled(&rows, "window")?, "window").unwrap_or("1000"))?,
        proposal: [0x99; 32],
        proof: vec![0x00; mt_state::PROOF_LEN],
    };
    let bytes = held.encode();
    let stated = number(labeled(&rows, "window_proof_len")?)? as usize;
    verified_note("window_proof_len", &format!("{stated} B"));
    if stated != bytes.len() {
        return Err(format!(
            "layout divergence at `window_proof_len`: the set states {stated} B, the code serializes {} B",
            bytes.len()
        ));
    }
    compare_hash(
        "SHA-256 of the serialized object",
        labeled(&rows, "SHA-256 of the serialized object")?,
        &sha256(&bytes),
    )?;
    compare_hash(
        "window_proof_id",
        labeled(&rows, "window_proof_id")?,
        &held
            .id()
            .map_err(|e| format!("the identifier of the frozen proof does not compute: {e:?}"))?,
    )?;

    let rows = parse_labeled(md, FRAME_HEADER)?;
    let count = mt_genesis::scalar("spends_per_frame").ok_or("the Decree names no count")? as usize;
    let inputs = mt_genesis::scalar("spend_inputs").ok_or("the Decree names no count")? as usize;
    let outputs = mt_genesis::scalar("spend_outputs").ok_or("the Decree names no count")? as usize;
    let frame = Frame {
        spends: (0..count)
            .map(|s| Spend {
                nullifiers: vec![[0x20 + s as u8; 32]; inputs],
                commitments: vec![[0x30 + s as u8; 32]; outputs],
                rate_nullifier: [0x40 + s as u8; 32],
            })
            .collect(),
        proof: vec![0x00; mt_state::PROOF_LEN],
    };
    let bytes = frame.encode();
    let stated_frame = labeled(&rows, "frame_len")?;
    verified_note("frame_len", stated_frame);
    let stated_len = number(stated_frame)? as usize;
    if stated_len != bytes.len() {
        return Err(format!(
            "layout divergence at `frame_len`: the set states {stated_len} B, the code serializes {} B",
            bytes.len()
        ));
    }
    compare_hash(
        "SHA-256 of the serialized frame",
        labeled(&rows, "SHA-256 of the serialized frame")?,
        &sha256(&bytes),
    )?;

    // The notice of a spend stands on two values this set already holds: the nullifier of the
    // vectors of the messages and the identifier of the frame serialized above. An implementation
    // writing the frame before the nullifier reproduces neither the length nor the hash.
    let frame_id = frame.id().map_err(|e| format!("a frame this tree cannot name: {e:?}"))?;
    let rows = parse_labeled(md, NOTICE_HEADER)?;
    let notice = mt_state::layout::Notice {
        nullifier: sha256(b"mt-vector-nullifier"),
        frame: frame_id,
    };
    let bytes = notice.encode();
    let stated_notice = labeled(&rows, "notice_len")?;
    verified_note("notice_len", stated_notice);
    let stated_len =
        number(stated_notice.split('=').next_back().unwrap_or(stated_notice).trim())? as usize;
    if stated_len != bytes.len() {
        return Err(format!(
            "layout divergence at `notice_len`: the set states {stated_len} B, the code serializes {} B",
            bytes.len()
        ));
    }
    compare_hash(
        "SHA-256 of the serialized notice",
        labeled(&rows, "SHA-256 of the serialized notice")?,
        &sha256(&bytes),
    )?;
    Ok(())
}

// The totals of the layouts, read out of the arithmetic the set writes beside each one.
pub fn check_layouts(md: &str) -> Result<(), String> {
    use mt_state::layout::*;
    use mt_state::Layout;
    // The set writes a total as its arithmetic and then as its value, sometimes over two lines:
    // what the gate compares is the value, which is the last `=` of the block whose right side is
    // a number of bytes and nothing else.
    let lines: Vec<&str> = md.lines().collect();
    // Every place the set states a total, not the first: a number written twice is a number that
    // can drift, and a gate reading one of the two would bless the set disagreeing with itself.
    let stated_everywhere = |name: &str| -> Result<Vec<usize>, String> {
        let mut totals = Vec::new();
        for (at, line) in lines.iter().enumerate() {
            let names_it = match line.trim_start().strip_prefix(name) {
                Some(rest) => rest.trim_start().starts_with('='),
                None => false,
            };
            if !names_it {
                continue;
            }
            for candidate in lines[at..].iter().take(4) {
                let Some((_, after)) = candidate.rsplit_once('=') else {
                    continue;
                };
                let value = after.trim().trim_end_matches('B').trim();
                if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit() || b == b' ') {
                    continue;
                }
                totals.push(number(value)? as usize);
                break;
            }
        }
        if totals.is_empty() {
            return Err(format!("the set states no total for {name}"));
        }
        Ok(totals)
    };
    let named: [(&str, usize, &str); 12] = [
        ("proposal_len", Proposal::expected_len(), Proposal::NAME),
        (
            "confirmation_len",
            Confirmation::expected_len(),
            Confirmation::NAME,
        ),
        ("frame_len", Frame::expected_len(), Frame::NAME),
        (
            "light_attestation_len",
            LightAttestation::expected_len(),
            LightAttestation::NAME,
        ),
        ("candidacy_len", Candidacy::expected_len(), Candidacy::NAME),
        ("fold_node_len", FoldNode::expected_len(), FoldNode::NAME),
        ("beacon_len", Beacon::expected_len(), Beacon::NAME),
        (
            "name_reveal_len",
            NameReveal::expected_len(),
            NameReveal::NAME,
        ),
        (
            "channel_reveal_len",
            ChannelReveal::expected_len(),
            ChannelReveal::NAME,
        ),
        (
            "channel_publication_len",
            ChannelPublication::expected_len(),
            ChannelPublication::NAME,
        ),
        (
            "name_commit_len",
            SlotCommit::expected_len(),
            SlotCommit::NAME,
        ),
        ("name_renew_len", SlotRenew::expected_len(), SlotRenew::NAME),
    ];
    // The messages of the wire carry their own totals, and the crate that carries them answers each
    // from the widths of the set rather than from a number written twice.
    let wire = |value: Result<usize, mt_wire::WireError>| -> Result<usize, String> {
        value.map_err(|e| format!("the wire cannot read the Decree: {e:?}"))
    };
    let of_the_wire: [(&str, usize, &str); 15] = [
        ("hello_len", mt_wire::handshake::hello_len(), "hello"),
        ("hello_answer_len", mt_wire::handshake::hello_answer_len(), "answer of a hello"),
        ("hello_finish_len", mt_wire::handshake::hello_finish_len(), "finish of a hello"),
        ("hello_confirm_len", mt_wire::handshake::hello_confirm_len(), "confirm of a hello"),
        ("deposit_len", wire(mt_wire::message::deposit_len())?, "deposit"),
        ("collect_len", mt_wire::message::collect_len(), "collection"),
        ("collect_public_len", mt_wire::message::collect_public_len(), "public collection"),
        ("wake_inline_len", mt_wire::message::wake_len(), "wake by tag"),
        ("wake_handle_len", mt_wire::message::wake_len(), "wake by handle"),
        ("head_query_len", mt_wire::message::head_query_len(), "query of a head"),
        ("state_query_len", mt_wire::message::state_query_len(), "query of a leaf"),
        ("proof_query_len", mt_wire::message::proof_query_len(), "query of a proof of a window"),
        ("slot_query_len", mt_wire::message::slot_query_len(), "query of a slot"),
        ("channel_commit_len", SlotCommit::expected_len(), "commitment over a slot of a channel"),
        ("channel_renew_len", SlotRenew::expected_len(), "renewal of a slot of a channel"),
    ];
    for (label, held, what) in named.iter().chain(of_the_wire.iter()) {
        for set_value in stated_everywhere(label)? {
            if set_value != *held {
                return Err(format!(
                    "layout divergence at `{label}` ({what}): the set states {set_value} B, the code holds {held} B"
                ));
            }
            verified_note_number(label, set_value as u64);
        }
    }
    Ok(())
}

pub const NOTE_HEADER: &str = "**A nullifier, and its independence from the commitment.**";
pub const RATES_HEADER: &str =
    "**The nullifiers of the two rates.**";
pub const RIGHTS_HEADER: &str = "**The vectors of the two rights.**";
pub const VERSION_HEADER: &str = "**The vectors of the nullifier of a version.**";
pub const TAG_HEADER: &str = "**A tag and the labels of its steps.**";
pub const CLAIM_HEADER: &str = "**The right of a machine, and the moment of extinguishing it.**";
pub const HORIZON_HEADER: &str = "**The horizon fold, at three of its reach.**";
pub const LOOKUP_HEADER: &str = "**The nullifier of a reach into the space of slots.**";
pub const NAME_HEADER: &str = "**A name: its slot, its chain and its commitment.**";
pub const CHANNEL_HEADER: &str = "**A channel: its slot, and the head of a publication.**";
pub const CONTACT_HEADER: &str = "**The tag of first contact to a claimed name.**";
pub const MACHINE_HEADER: &str = "**The commitment standing for a machine.**";
pub const PART_HEADER: &str =
    "**The nullifier of a part, and the identifier of an application.**";
pub const FINGERPRINT_HEADER: &str = "**The fingerprint compared out of band.**";
pub const FOLD_HEADER: &str = "**The vector of the node's identifier.**";
pub const SEAL_HEADER: &str = "**The seal of a step, and the placement of a sender.**";
pub const PROPOSAL_HEADER: &str = "**A proposal, and its length.**";
pub const WINDOW_PROOF_HEADER: &str = "**The proof of a window, and its length.**";
pub const TWO_SPACES_HEADER: &str =
    "**The branches of the two spaces, from a stated master seed.**";
pub const FRAME_HEADER: &str = "**A frame, and its length.**";
pub const NOTICE_HEADER: &str = "**A notice, and its length.**";

// The inputs of a vector stand on one line of its block, comma separated: the first may be bare —
// its name being the label of the row — and the rest stand as `name = value`.
fn bare_input(cell: &str) -> &str {
    cell.split(',').next().unwrap_or_default().trim()
}

fn input_of<'a>(cell: &'a str, name: &str) -> Result<&'a str, String> {
    for part in cell.split(',') {
        if let Some((n, v)) = part.split_once('=') {
            if n.trim() == name {
                return Ok(v.trim());
            }
        }
    }
    Err(format!("the inputs {cell:?} name no {name}"))
}

fn input32(cell: &str, name: &str) -> Result<[u8; 32], String> {
    repeat32(input_of(cell, name)?)
}

fn window_of(cell: &str) -> Result<u64, String> {
    number(input_of(cell, "W")?)
}

fn compare16(label: &str, stated: &str, computed: [u8; 16]) -> Result<(), String> {
    verified_note(label, stated);
    let hexed = hex(&computed);
    if stated.trim() != hexed {
        return Err(format!(
            "divergence at `{label}`: the set holds {}, the code computes {hexed}",
            stated.trim()
        ));
    }
    Ok(())
}

fn compare_number(label: &str, stated: u64, computed: u64) -> Result<(), String> {
    verified_note_number(label, stated);
    if stated != computed {
        return Err(format!(
            "divergence at `{label}`: the set holds {stated}, the code computes {computed}"
        ));
    }
    Ok(())
}

// Every derivation the stage of the objects owns: the note and its nullifier, the nullifiers of the
// rates, of a reach, of a part and of a share, the moment a right is extinguished, the tags with the
// negative line the set makes normative, the seal of a step and the placement of a sender, a name
// with its chain, a channel with its head and its points, the tag of first contact, the commitment
// standing for a machine, and the fingerprint compared out of band.
pub fn check_derivations(md: &str) -> Result<(), String> {
    // The note: the commitment of the tree block, then its nullifier at the stated positions.
    let note_rows = parse_labeled(md, NOTE_TREE_HEADER)?;
    let note_inputs = labeled(&note_rows, "value")?;
    let (nf_sk, nf_pk) = mt_derive::note::halves(&input32(note_inputs, "nf_key")?);
    compare_hash("nf_sk", labeled(&note_rows, "nf_sk")?, &nf_sk)?;
    compare_hash("nf_pk", labeled(&note_rows, "nf_pk")?, &nf_pk)?;
    let cm = mt_derive::note::commitment(
        u128::from(number(bare_input(note_inputs))?),
        &input32(note_inputs, "note_pk")?,
        &nf_pk,
        &input32(note_inputs, "rcm")?,
    )
    .ok_or("the half of the vector is no digest of the family")?;
    compare_hash("cm", labeled(&note_rows, "cm")?, &cm)?;

    let nf_rows = parse_labeled(md, NOTE_HEADER)?;
    let nf_key = repeat32(bare_input(labeled(&nf_rows, "nf_key")?))?;
    for (label, expected) in &nf_rows {
        if let Some(rest) = label.strip_prefix("nf(position ") {
            let position = number(rest.trim_end_matches(')'))?;
            compare_hash(
                label,
                expected,
                &mt_derive::note::nullifier(&nf_key, &cm, position)
                    .ok_or("the commitment of the vector is no digest of the family")?,
            )?;
        }
    }

    // The nullifiers of the two rates and of a share.
    let rate_rows = parse_labeled(md, RATES_HEADER)?;
    let rate_inputs = labeled(&rate_rows, "rate_secret")?;
    let rate_secret = repeat32(bare_input(rate_inputs))?;
    let act_secret = input32(rate_inputs, "act_secret")?;
    let w = window_of(rate_inputs)?;
    for (label, expected) in &rate_rows {
        let computed = match label.as_str() {
            "rate_nf(W, i = 2)" => Some(mt_derive::nullifier::rate(&rate_secret, w, 2)),
            "rate_nf(W, i = 3)" => Some(mt_derive::nullifier::rate(&rate_secret, w, 3)),
            "act_nf(W)" => Some(mt_derive::nullifier::act(&act_secret, w)),
            "act_nf(W + 1)" => Some(mt_derive::nullifier::act(&act_secret, w + 1)),
            _ => None,
        };
        if let Some(computed) = computed {
            compare_hash(label, expected, &computed)?;
        }
    }

    // The two one-time rights of a person. Each is compared on a repeated byte and on a branch of
    // thirty-two distinct ones, so a reading from the far end answers elsewhere — and both are of
    // the proof hash family, which is what lets the objects publishing them assert where they came
    // from.
    let rights_rows = parse_labeled(md, RIGHTS_HEADER)?;
    let rights_inputs = labeled(&rights_rows, "open_secret")?;
    let open_secret = repeat32(bare_input(rights_inputs))?;
    let operator_secret = input32(rights_inputs, "operator_secret")?;
    let mut walking = [0u8; 32];
    for (at, slot) in walking.iter_mut().enumerate() {
        *slot = at as u8;
    }
    for (label, expected) in &rights_rows {
        let computed = match label.as_str() {
            "open_nf" => Some(mt_derive::nullifier::open(&open_secret)),
            "open_nf of the walking branch" => Some(mt_derive::nullifier::open(&walking)),
            "operator_nf" => Some(mt_derive::nullifier::operator(&operator_secret)),
            "operator_nf of the walking branch" => Some(mt_derive::nullifier::operator(&walking)),
            _ => None,
        };
        if let Some(computed) = computed {
            compare_hash(label, expected, &computed)?;
        }
    }

    // The nullifier that spends one version of a record. The commitment of the vector stands as
    // thirty-two distinct bytes, so a reading from the far end and a swap of the two parts both
    // answer elsewhere — which is what the second and third lines hold the code to.
    let version_rows = parse_labeled(md, VERSION_HEADER)?;
    let version_inputs = labeled(&version_rows, "blind")?;
    let blind = repeat32(bare_input(version_inputs))?;
    let commit = fixed_part::<32>(input_of(version_inputs, "record_commit")?)?;
    let mut reversed = commit;
    reversed.reverse();
    for (label, expected) in &version_rows {
        let computed = match label.as_str() {
            "record_nf" => Some(mt_derive::nullifier::record(&blind, &commit)),
            "record_nf, the commitment reversed" => {
                Some(mt_derive::nullifier::record(&blind, &reversed))
            }
            "record_nf, blind = 0x88 x 32" => {
                Some(mt_derive::nullifier::record(&[0x88u8; 32], &commit))
            }
            _ => None,
        };
        if let Some(computed) = computed {
            compare_hash(label, expected, &computed)?;
        }
    }

    // The nullifier of a reach into the space of slots.
    let lookup_rows = parse_labeled(md, LOOKUP_HEADER)?;
    let lookup_inputs = labeled(&lookup_rows, "lookup_secret")?;
    let lookup_secret = repeat32(bare_input(lookup_inputs))?;
    let lw = window_of(lookup_inputs)?;
    compare_hash(
        "lookup_nf(W)",
        labeled(&lookup_rows, "lookup_nf(W)")?,
        &mt_derive::nullifier::lookup(&lookup_secret, lw),
    )?;
    compare_hash(
        "lookup_nf(W + 1)",
        labeled(&lookup_rows, "lookup_nf(W + 1)")?,
        &mt_derive::nullifier::lookup(&lookup_secret, lw + 1),
    )?;

    // The nullifier of a part, and the identifier of an application.
    let part_rows = parse_labeled(md, PART_HEADER)?;
    let part_inputs = labeled(&part_rows, "machine_secret")?;
    let machine_secret = repeat32(bare_input(part_inputs))?;
    let pw = window_of(part_inputs)?;
    let part_of_the_vector = mt_derive::nullifier::part(&machine_secret, pw)
        .ok_or_else(|| "the secret of the vector yields no half of the family".to_string())?;
    compare_hash(
        "part_nf(W)",
        labeled(&part_rows, "part_nf(W)")?,
        &part_of_the_vector,
    )?;
    compare_hash(
        "app_id(\"montana\")",
        labeled(&part_rows, "app_id(\"montana\")")?,
        &mt_derive::app_id(b"montana"),
    )?;

    // The right of a machine: the two halves of one absorption of its secret, the leaf it stands
    // at, the two roots of the tree of admitted machines, its nullifier per window, and the moment
    // — which the set writes as `W + delay = total`.
    let claim_rows = parse_labeled(md, CLAIM_HEADER)?;
    let claim_secret = repeat32(bare_input(labeled(&claim_rows, "machine_secret")?))?;
    let (machine_sk, machine_pk) = mt_derive::nullifier::machine_halves(&claim_secret);
    compare_hash("machine_sk", labeled(&claim_rows, "machine_sk")?, &machine_sk)?;
    compare_hash("machine_pk", labeled(&claim_rows, "machine_pk")?, &machine_pk)?;
    let leaf = mt_derive::nullifier::admitted_leaf(&claim_secret)
        .ok_or("the naming half of the vector is no digest of the family")?;
    compare_hash("admitted_leaf", labeled(&claim_rows, "admitted_leaf")?, &leaf)?;
    compare_hash(
        "admitted_root (empty)",
        labeled(&claim_rows, "admitted_root (empty)")?,
        &mt_proof::admitted::empty_root().bytes(),
    )?;
    let depth = note_tree_depth()?;
    compare_hash(
        "admitted_root (one leaf at 0)",
        labeled(&claim_rows, "admitted_root (one leaf at 0)")?,
        &mt_proof::admitted::root_of(&[machine_pk], depth)
            .ok_or("the naming half of the vector is no digest of the family")?
            .bytes(),
    )?;
    // The root over two halves, which is what pins the pairing of a level: a root over one folds
    // that half with the empty of every level and never with another leaf, so it cannot tell an
    // implementation that assembles a level with the pair folded right-then-left from a right one.
    let second = input32(
        labeled(&claim_rows, "machine_secret")?,
        "a second naming half",
    )?;
    compare_hash(
        "admitted_root (two leaves)",
        labeled(&claim_rows, "admitted_root (two leaves)")?,
        &mt_proof::admitted::root_of(&[machine_pk, second], depth)
            .ok_or("a half of the vector is no digest of the family")?
            .bytes(),
    )?;
    for (label, expected) in &claim_rows {
        if let Some(rest) = label.strip_prefix("credit_nf(") {
            let window = number(rest.trim_end_matches(')'))?;
            compare_hash(
                label,
                expected,
                &mt_derive::nullifier::credit(&claim_secret, window)
                    .ok_or("the spending half of the vector is no digest of the family")?,
            )?;
        }
        if let Some(rest) = label.strip_prefix("claim_window(") {
            let window = number(rest.trim_end_matches(')'))?;
            let computed = mt_derive::nullifier::claim_window(&claim_secret, window)
                .ok_or_else(|| "the Decree names no spread".to_string())?;
            let stated = number(expected.rsplit_once('=').map(|(_, v)| v).unwrap_or(expected))?;
            compare_number(label, stated, computed)?;
        }
    }

    // The horizon fold, its root and the three named wrong implementations, each of which must
    // answer exactly the value the set freezes for it — an implementation reproducing a wrong
    // line is the one that line exists to catch.
    let horizon_rows = parse_labeled(md, HORIZON_HEADER)?;
    let newest = hex32(consumed(&horizon_rows, "leaf 0")?)?;
    let second = repeat32(consumed(&horizon_rows, "leaf 1")?)?;
    let third = repeat32(consumed(&horizon_rows, "leaf 2")?)?;
    let leaves = [newest, second, third];
    compare_hash(
        "horizon_root (three of the reach)",
        labeled(&horizon_rows, "horizon_root (three of the reach)")?,
        &mt_proof::horizon::root_of(&leaves)
            .ok_or("a leaf of the horizon vector is no digest of the family")?,
    )?;
    compare_hash(
        "horizon_root, the order reversed",
        labeled(&horizon_rows, "horizon_root, the order reversed")?,
        &mt_proof::horizon::root_of(&[third, second, newest])
            .ok_or("a leaf of the horizon vector is no digest of the family")?,
    )?;
    let dropped = {
        let mut level: Vec<mt_proof::poseidon::Digest> = leaves
            .iter()
            .map(mt_proof::horizon::leaf)
            .collect::<Option<Vec<_>>>()
            .ok_or("a leaf of the horizon vector is no digest of the family")?;
        level.resize(4, mt_proof::horizon::empty_leaf());
        while level.len() > 1 {
            let mut above = Vec::with_capacity(level.len() / 2);
            for pair in level.chunks(2) {
                above.push(mt_proof::horizon::node(&pair[0], &pair[1]));
            }
            level = above;
        }
        level[0].bytes()
    };
    compare_hash(
        "horizon_root, absent leaves dropped",
        labeled(&horizon_rows, "horizon_root, absent leaves dropped")?,
        &dropped,
    )?;
    let under_note_doors = {
        let noted = |root: &[u8; 32]| -> Option<mt_proof::poseidon::Digest> {
            Some(mt_proof::poseidon::hash_elements(
                mt_codec::domain::MT_NOTE_LEAF,
                mt_proof::poseidon::Digest::of_bytes(root)?.elements(),
            ))
        };
        let mut level: Vec<mt_proof::poseidon::Digest> = leaves
            .iter()
            .map(noted)
            .collect::<Option<Vec<_>>>()
            .ok_or("a leaf of the horizon vector is no digest of the family")?;
        level.resize(
            128,
            mt_proof::poseidon::hash_elements(mt_codec::domain::MT_NOTE_LEAF, &[]),
        );
        while level.len() > 1 {
            let mut above = Vec::with_capacity(level.len() / 2);
            for pair in level.chunks(2) {
                above.push(mt_proof::poseidon::node(
                    mt_codec::domain::MT_NOTE_NODE,
                    &pair[0],
                    &pair[1],
                ));
            }
            level = above;
        }
        level[0].bytes()
    };
    compare_hash(
        "horizon_root, under the note doors",
        labeled(&horizon_rows, "horizon_root, under the note doors")?,
        &under_note_doors,
    )?;

    // The tags and the labels of their steps, with the negative line of the set.
    let tag_rows = parse_labeled(md, TAG_HEADER)?;
    let tag_inputs = labeled(&tag_rows, "shared_secret")?;
    let shared = repeat32(bare_input(tag_inputs))?;
    let tw = window_of(tag_inputs)?;
    compare16("tag", labeled(&tag_rows, "tag")?, mt_derive::tag::tag(&shared, tw))?;
    compare16(
        "tag (W = 1001)",
        labeled(&tag_rows, "tag (W = 1001)")?,
        mt_derive::tag::tag(&shared, tw + 1),
    )?;
    // The two pairs of the block, each written as a repeated byte with words beside it.
    let pairs: Vec<[u8; 32]> = labeled(&tag_rows, "handshake_secret")?
        .split(',')
        .filter_map(|part| repeat32(part).ok())
        .collect();
    if pairs.len() != 2 {
        return Err(format!(
            "the block of the steps names {} secrets rather than two",
            pairs.len()
        ));
    }
    compare16(
        "step_label(first pair)",
        labeled(&tag_rows, "step_label(first pair)")?,
        mt_derive::tag::step_label(&pairs[0], tw),
    )?;
    compare16(
        "step_label(second pair)",
        labeled(&tag_rows, "step_label(second pair)")?,
        mt_derive::tag::step_label(&pairs[1], tw),
    )?;
    compare16(
        "step_label(first pair, W + 1)",
        labeled(&tag_rows, "step_label(first pair, W + 1)")?,
        mt_derive::tag::step_label(&pairs[0], tw + 1),
    )?;
    // The negative line: a public value substituted for the secret yields the value frozen for the
    // mistake, and an implementation that makes it fails the comparison above.
    for (label, expected) in &tag_rows {
        if let Some(rest) = label.strip_prefix("tag(public value ") {
            let public = repeat32(rest.trim_end_matches(')'))?;
            compare16(label, expected, mt_derive::tag::tag(&public, tw))?;
            if mt_derive::tag::tag(&public, tw) == mt_derive::tag::tag(&shared, tw) {
                return Err("the negative vector of a tag equals the positive one".to_string());
            }
        }
    }

    // The seal of a step and the placement of a sender.
    let seal_rows = parse_labeled(md, SEAL_HEADER)?;
    let seal_inputs = labeled(&seal_rows, "owner_secret")?;
    let owner = repeat32(bare_input(seal_inputs))?;
    // The two pipe layers the set states, each of the width the Decree derives: a seal stands on
    // the path a cell carries, so what the vectors take is the pipe layer and never a step label.
    let inners: Vec<Vec<u8>> = seal_inputs
        .split(',')
        .filter_map(|part| part.split_once('='))
        .filter_map(|(_, v)| parse_part(v).ok())
        .filter(|b| b.len() == mt_wire::inner_bytes().unwrap_or_default())
        .collect();
    if inners.len() != 2 {
        return Err(format!(
            "the block of a seal names {} pipe layers rather than two",
            inners.len()
        ));
    }
    let mut seals: Vec<[u8; 16]> = Vec::new();
    for (which, name) in ["first", "second"].iter().enumerate() {
        let path = mt_derive::tag::path_id(&inners[which]);
        compare16(
            &format!("path_id ({name} inner)"),
            labeled(&seal_rows, &format!("path_id ({name} inner)"))?,
            path,
        )?;
        let seal = mt_derive::tag::relay_seal(&owner, &path);
        compare16(
            &format!("relay_seal ({name} path)"),
            labeled(&seal_rows, &format!("relay_seal ({name} path)"))?,
            seal,
        )?;
        let slot = mt_derive::tag::seal_slot(&seal)
            .ok_or_else(|| "the Decree names no count of slots".to_string())?;
        compare_number(
            &format!("seal_slot ({name} seal)"),
            number(labeled(&seal_rows, &format!("seal_slot ({name} seal)"))?)?,
            slot,
        )?;
        seals.push(seal);
    }
    // The property the vectors exist for: one owner reaches one seal and one slot per path, and
    // two paths of that owner do not join.
    if seals[0] == seals[1] {
        return Err("two paths of one owner reach one seal".to_string());
    }
    let sender = repeat32(bare_input(labeled(&seal_rows, "sender_secret")?))?;
    for (label, expected) in &seal_rows {
        if let Some(rest) = label.strip_prefix("ephemeral_id(W = ") {
            let window = number(rest.trim_end_matches(')'))?;
            compare_hash(
                label,
                expected,
                &mt_derive::tag::ephemeral_id(&sender, window),
            )?;
        }
        if let Some(rest) = label.strip_prefix("slot(W = ") {
            let window = number(rest.trim_end_matches(')'))?;
            let computed = mt_derive::tag::slot_of(&sender, window)
                .ok_or_else(|| "the Decree names no modulus".to_string())?;
            compare_number(label, number(expected)?, computed)?;
        }
        if let Some(rest) = label.strip_prefix("chain(W = ") {
            let window = number(rest.trim_end_matches(')'))?;
            let computed = mt_derive::tag::chain_of(&sender, window)
                .ok_or_else(|| "the Decree names no count of chains".to_string())?;
            compare_number(label, number(expected)?, computed)?;
        }
    }

    // A name: its slot, its chain and its commitment.
    let name_rows = parse_labeled(md, NAME_HEADER)?;
    let name_inputs = labeled(&name_rows, "name")?;
    let written = bare_input(name_inputs).trim_matches('"');
    let normalized = mt_derive::name::normalize(written)
        .map_err(|e| format!("the name of the vector is unlawful: {e:?}"))?;
    let slot = mt_derive::name::slot(&normalized);
    compare_hash("slot(name)", labeled(&name_rows, "slot(name)")?, &slot)?;
    let links = mt_derive::name::chain(&input32(name_inputs, "name_own")?)
        .ok_or_else(|| "the Decree names no length of a chain".to_string())?;
    for (label, expected) in &name_rows {
        if let Some(rest) = label.strip_prefix("link(") {
            let index = number(rest.split(')').next().unwrap_or_default())? as usize;
            if index >= links.len() {
                return Err(format!("the chain holds no {label}"));
            }
            compare_hash(label, expected, &links[index])?;
        }
    }
    compare_hash(
        "commit(slot, blind, tip)",
        labeled(&name_rows, "commit(slot, blind, tip)")?,
        &mt_derive::name::commit(&slot, &input32(name_inputs, "blind")?, &links[0]),
    )?;

    // A channel: its slot, its seed, the head of a publication and the points of two windows.
    let channel_rows = parse_labeled(md, CHANNEL_HEADER)?;
    let channel_inputs = labeled(&channel_rows, "name")?;
    let channel_slot = mt_derive::name::channel_slot(&normalized);
    compare_hash(
        "channel_slot(name)",
        labeled(&channel_rows, "channel_slot(name)")?,
        &channel_slot,
    )?;
    compare_hash(
        "SHA-256(channel_seed)",
        labeled(&channel_rows, "SHA-256(channel_seed)")?,
        &sha256(&mt_derive::name::channel_seed(
            &input32(channel_inputs, "master_seed")?,
            &channel_slot,
        )),
    )?;
    let previous = input32(channel_inputs, "previous")?;
    let body_root = input32(channel_inputs, "body_root")?;
    let cw = window_of(channel_inputs)?;
    compare_hash(
        "head(W)",
        labeled(&channel_rows, "head(W)")?,
        &mt_derive::name::head(&previous, &body_root, cw),
    )?;
    compare_hash(
        "head(W + 1)",
        labeled(&channel_rows, "head(W + 1)")?,
        &mt_derive::name::head(&previous, &body_root, cw + 1),
    )?;
    compare16(
        "channel_point(W)",
        labeled(&channel_rows, "channel_point(W)")?,
        mt_derive::tag::channel_point(&channel_slot, cw),
    )?;
    compare16(
        "channel_point(W + 1)",
        labeled(&channel_rows, "channel_point(W + 1)")?,
        mt_derive::tag::channel_point(&channel_slot, cw + 1),
    )?;

    // The tag of first contact to a claimed name.
    let contact_rows = parse_labeled(md, CONTACT_HEADER)?;
    let contact_root = fixed_part(labeled(&contact_rows, "contact_root")?)?;
    for (label, expected) in &contact_rows {
        if let Some(rest) = label.strip_prefix("first_tag(W = ") {
            let window = number(rest.trim_end_matches(')'))?;
            compare16(
                label,
                expected,
                mt_derive::tag::first_contact(&contact_root, window),
            )?;
        }
    }

    // The secret of first contact: the encapsulated secret, the key and the ciphertext, in
    // that order and in no other.
    let ss_cell = labeled(&contact_rows, "ss")?;
    let ss = repeat32(bare_input(ss_cell))?;
    let ct = fixed_part(input_of(ss_cell, "ct")?)?;
    compare_hash(
        "shared_secret",
        labeled(&contact_rows, "shared_secret")?,
        &mt_derive::name::first_contact_secret(&ss, &contact_root, &ct),
    )?;

    // The branches of the two spaces, from a stated master seed: the chain branch, the contact
    // seed and the channel seed, each composing its info as the domain, one NUL and the slot.
    let spaces_rows = parse_labeled(md, TWO_SPACES_HEADER)?;
    let stated_seed = parse_part(consumed(&spaces_rows, "master_seed")?)?;
    let spaces_name = labeled(&spaces_rows, "name")?.trim().trim_matches('"');
    let spaces_normalized = mt_derive::name::normalize(spaces_name)
        .map_err(|e| format!("the name of the two spaces is unlawful: {e:?}"))?;
    let spaces_slot = mt_derive::name::slot(&spaces_normalized);
    compare_hash(
        "SHA-256(chain branch)",
        labeled(&spaces_rows, "SHA-256(chain branch)")?,
        &sha256(&mt_derive::name::chain_branch(&stated_seed, &spaces_slot)),
    )?;
    compare_hash(
        "SHA-256(contact seed)",
        labeled(&spaces_rows, "SHA-256(contact seed)")?,
        &sha256(&mt_derive::name::contact_seed(&stated_seed, &spaces_slot)),
    )?;
    compare_hash(
        "SHA-256(channel seed)",
        labeled(&spaces_rows, "SHA-256(channel seed)")?,
        &sha256(&mt_derive::name::channel_seed(
            &stated_seed,
            &mt_derive::name::channel_slot(&spaces_normalized),
        )),
    )?;

    // The commitment standing for a machine.
    let machine_rows = parse_labeled(md, MACHINE_HEADER)?;
    let machine_inputs = labeled(&machine_rows, "answering_pk")?;
    let answering = fixed_part(bare_input(machine_inputs))?;
    let suite = u16::try_from(number(input_of(machine_inputs, "suite_id")?)?)
        .map_err(|e| format!("a suite beyond a u16: {e}"))?;
    compare_hash(
        "node_commit",
        labeled(&machine_rows, "node_commit")?,
        &mt_derive::node_commit(&answering, suite, &input32(machine_inputs, "blind")?),
    )?;

    // The fingerprint compared out of band.
    let print_rows = parse_labeled(md, FINGERPRINT_HEADER)?;
    let print_inputs = labeled(&print_rows, "identity key")?;
    let key = repeat32(bare_input(print_inputs))?;
    let iterations = number(input_of(print_inputs, "iterations")?)?;
    verified_note_number("fingerprint_iterations", iterations);
    if iterations != u64::from(mt_derive::fingerprint::ITERATIONS) {
        return Err(format!(
            "the iterations of the fingerprint diverge: the set holds {iterations}, the code holds {}",
            mt_derive::fingerprint::ITERATIONS
        ));
    }
    let stated = labeled(&print_rows, "fingerprint")?.trim();
    verified_note("fingerprint", stated);
    let computed = mt_derive::fingerprint::shown(&key);
    if stated != computed {
        return Err(format!(
            "divergence at `fingerprint`: the set holds {stated}, the code computes {computed}"
        ));
    }
    Ok(())
}

// The labels awaiting a later stage, each naming the crate whose landing computes it. The mark
// is not a word but a claim the build checks: if the named crate already stands in the
// workspace, the value is computable and the mark is refused. A list of labels alone would let
// any value leave the gate by one line — this is the rule of the coverage pass turned on the
// pass's own escape hatch.
pub const AWAITING: &[(&str, &str)] = &[];

// The domains of the registry no run of the gate has ever taken a preimage under, each named with
// the stage that gives it one. A domain here is a rule of the set that nothing compares: two
// implementations read its prose, write two preimages, and neither can tell. The coverage pass
// cannot find these on its own — it reads the values that exist and never asks which rules have
// none — so the question is asked here, from the side that can be counted.
pub const DOMAINS_AWAITING_A_VECTOR: &[(&str, &str)] = &[
    // The birth of a person and what derives from it: the chain is frozen end to end, and these
    // are the doors of it a checker reaches through a value rather than through the door itself.
    ("mt-seed", "the birth of a person"),
    ("mt-account-key", "the birth of a person"),
    ("mt-node-key", "the birth of a person"),
    ("mt-note-key", "the birth of a person"),
    ("mt-nf-key", "the birth of a person"),
    ("mt-note-pk", "the birth of a person"),
    ("mt-owner-key", "the birth of a person"),
    ("mt-app-encryption-key", "the birth of a person"),
    // Names and channels: the objects are laid out and their rules stand, and what no run takes a
    // preimage under is the operation each of them is signed as.
    ("mt-name-commit-op", "names and channels"),
    ("mt-name-reveal-op", "names and channels"),
    ("mt-name-renew-op", "names and channels"),
    ("mt-channel-commit-op", "names and channels"),
    ("mt-channel-reveal-op", "names and channels"),
    ("mt-channel-pub-op", "names and channels"),
    ("mt-name-own", "names and channels"),
    ("mt-name-contact-key", "names and channels"),
    ("mt-channel-key", "names and channels"),
    // The pulse: the objects a window carries beside its attestations.
    ("mt-nodereg", "the pulse"),
    ("mt-weight", "the pulse"),
    ("mt-cascade", "the pulse"),
    // The wire: the two signatures of the handshake and the envelope of a delivery.
    ("mt-noise-pq-v1-sig-r", "the wire"),
    ("mt-noise-pq-v1-sig-i", "the wire"),
    ("mt-delivery", "the wire"),
];

// An entry names a label whole, or as a prefix ending at a boundary: the character after the
// prefix, if any, is not a letter, a digit or an underscore, so `master` names the handshake
// value and never the master seed of a birth.
fn awaited_by(label: &str) -> Option<&'static (&'static str, &'static str)> {
    AWAITING.iter().find(|(entry, _)| {
        if !label.starts_with(entry) {
            return false;
        }
        match label.as_bytes().get(entry.len()) {
            None => true,
            Some(next) => !next.is_ascii_alphanumeric() && *next != b'_',
        }
    })
}

fn workspace_members() -> Result<Vec<String>, String> {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Cargo.toml");
    let text = std::fs::read_to_string(&manifest)
        .map_err(|e| format!("the workspace manifest is unreadable: {e}"))?;
    let open = text
        .find("members = [")
        .ok_or_else(|| "the workspace names no members".to_string())?;
    let rest = &text[open..];
    let close = rest
        .find(']')
        .ok_or_else(|| "the list of members never closes".to_string())?;
    Ok(rest[..close]
        .split('"')
        .filter(|part| part.starts_with("crates/"))
        .map(|part| part.trim_start_matches("crates/").to_string())
        .collect())
}

// Every mark of the registry is put to the workspace: a crate that has landed is a value that
// waits for nothing.
pub fn check_awaiting_is_earned() -> Result<(), String> {
    let members = workspace_members()?;
    for (label, crate_name) in AWAITING {
        if members.iter().any(|m| m == crate_name) {
            return Err(format!(
                "an unearned mark: `{label}` is marked as awaiting `{crate_name}`, and that crate stands in the workspace — the value is computable and the gate must read it"
            ));
        }
    }
    Ok(())
}

// How many lines of the set the coverage pass reads, and how many of them this build verifies. The
// measurements of `AUDIT.md` are taken from here rather than from a grep of my own, because a count
// by a second rule is a second implementation of the rule and would drift from it silently.
pub fn coverage_counts(md: &str) -> Result<(usize, usize), String> {
    let mut read = 0usize;
    let mut verified = 0usize;
    let mut rest = md;
    while let Some(open) = rest.find("```") {
        let after = &rest[open + 3..];
        let Some(close) = after.find("```") else {
            break;
        };
        for (label, value) in labelled_entries(&after[..close])? {
            if !is_frozen_shape(&normalized(&value)) {
                continue;
            }
            read += 1;
            if verified_holds(&label, &value) {
                verified += 1;
            }
        }
        rest = &after[close + 3..];
    }
    Ok((read, verified))
}

pub fn check_coverage(md: &str) -> Result<(), String> {
    let mut rest = md;
    while let Some(open) = rest.find("```") {
        let after = &rest[open + 3..];
        let Some(close) = after.find("```") else {
            break;
        };
        for (label, value) in labelled_entries(&after[..close])? {
            if !is_frozen_shape(&normalized(&value)) {
                continue;
            }
            let awaited = awaited_by(&label);
            match (verified_holds(&label, &value), awaited) {
                (true, None) | (false, Some(_)) => {}
                (true, Some((l, _))) => {
                    return Err(format!(
                        "coverage divergence: `{l}` is verified by this build and still marked as awaiting"
                    ));
                }
                (false, None) => {
                    return Err(format!(
                        "coverage divergence: a frozen value this build never read — `{label}` = {value}; \
                         every frozen line is either checked or named as awaiting its stage"
                    ));
                }
            }
        }
        rest = &after[close + 3..];
    }
    // The tables of the set are read too, and not the fenced blocks alone: a row is a labelled
    // value exactly as a line of a block is, and a gate that read one and not the other would be
    // green over every number the set writes in a table nobody compares.
    let mut inside = false;
    let mut unread: Vec<String> = Vec::new();
    for line in md.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("```") {
            inside = !inside;
            continue;
        }
        if inside || !trimmed.starts_with('|') || trimmed.starts_with("|---") {
            continue;
        }
        let cells: Vec<&str> = trimmed.trim_matches('|').split('|').map(str::trim).collect();
        let Some((label, values)) = cells.split_first() else {
            continue;
        };
        // The name of a row is its backticked span, the prose beside it belonging to the
        // reader: a row naming a period and then describing it is that row and not a label
        // of its own.
        let ticks = ticked(label);
        let label = ticks.first().copied().unwrap_or(label);
        for value in values {
            if !is_frozen_shape(&normalized(value)) {
                continue;
            }
            if awaited_by(label).is_some() || verified_holds(label, value) {
                continue;
            }
            unread.push(format!("`{label}` = {value}"));
        }
    }
    if !unread.is_empty() {
        return Err(format!(
            "coverage divergence: {} rows of the tables this build never read — {}; every value of \
             the set is either checked or named as awaiting its stage",
            unread.len(),
            unread.join("; ")
        ));
    }
    Ok(())
}

pub const PULSE_HEADER: &str = "**The round, the beacon, and the chain of a sender.**";
pub const ORDERS_HEADER: &str = "**The aggregate, the ticket and the two orders.**";
pub const MESSAGES_HEADER: &str = "**The vectors of the messages.**";
pub const ENTRY_HEADER: &str = "**The point of a ring of entries.**";

// The inputs of the pulse block: each derives from a stated string hashed bare, because a
// string that separates nothing is not a domain and takes no NUL.
fn test_answering_key() -> Vec<u8> {
    let mut out = Vec::with_capacity(1_952);
    for i in 0..61u32 {
        let mut block = Vec::from(&b"mt-vector-pk"[..]);
        block.extend_from_slice(&i.to_le_bytes());
        out.extend_from_slice(&sha256(&block));
    }
    out.truncate(1_952);
    out
}

// The round of a chain: the two key seeds, the inputs of the vectors, the eligibility, the
// identifier of a beacon and the two nullifiers the deduplication check stands on.
pub fn check_pulse(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, PULSE_HEADER)?;
    let inputs = labeled(&rows, "machine_secret")?;
    let secret = repeat32(bare_input(inputs))?;
    let window = window_of(inputs)?;
    compare_hash(
        "runner_key_seed",
        labeled(&rows, "runner_key_seed")?,
        &mt_derive::pulse::runner_key_seed(&secret, window),
    )?;
    compare_hash(
        "part_key_seed",
        labeled(&rows, "part_key_seed")?,
        &mt_derive::pulse::part_key_seed(&secret, window),
    )?;

    let vector_secret = sha256(b"mt-vector-machine");
    let vector_aggregate = sha256(b"mt-vector-aggregate");
    let previous = sha256(b"mt-vector-prev-beacon");
    let cement = standing_first_commitment(md)?;
    let beacon = mt_state::layout::Beacon {
        window,
        chain: 0,
        round: 7,
        previous,
        cement_state: cement,
    };
    for (label, value) in &rows {
        match label.as_str() {
            "test_machine_secret" => compare_hash(label, value, &vector_secret)?,
            // The state the beacon of this block stands on is the serialization of the commitment
            // the standing block freezes, and the set states its digest where it names the input.
            // It is compared here, under the label the pulse block writes it at, because coverage
            // keys by the pair: a value verified under another label is not thereby read under
            // this one.
            "test_cement_state" => compare_hash(label, value, &sha256(&beacon.cement_state))?,
            "test_aggregate" => compare_hash(label, value, &vector_aggregate)?,
            "test_prev_beacon" => compare_hash(label, value, &previous)?,
            "SHA-256(test_answering_key)" => {
                compare_hash(label, value, &sha256(&test_answering_key()))?
            }
            l if l.starts_with("round_elig(") => {
                // The draw reads the nullifier of the machine's part, which is the value a proof of
                // presence asserts; the one-time key enters no draw and no proof.
                let part = mt_derive::nullifier::part(&vector_secret, window)
                    .ok_or_else(|| "the secret of the vector yields no half of the family".to_string())?;
                compare_hash(
                    label,
                    value,
                    &mt_derive::pulse::round_eligibility(&part, &vector_aggregate, 0, 7),
                )?
            }
            l if l.starts_with("key_digest(") => {
                let key: [u8; mt_codec::size::SIGNING_PUBLIC_KEY] = test_answering_key()
                    .try_into()
                    .map_err(|_| "the key of the vector is not of the width of the set".to_string())?;
                compare_hash(label, value, &mt_derive::pulse::key_digest(&key))?
            }
            l if l.starts_with("beacon_id(") => {
                let id = beacon
                    .id()
                    .map_err(|e| format!("the beacon of the vector is not of its own width: {e:?}"))?;
                compare_hash(label, value, &id)?
            }
            l if l.starts_with("round_nf(") => {
                let id = beacon
                    .id()
                    .map_err(|e| format!("the beacon of the vector is not of its own width: {e:?}"))?;
                compare_hash(
                    label,
                    value,
                    &mt_derive::nullifier::round(&vector_secret, &id),
                )?
            }
            l if l.starts_with("part_nf(test_machine_secret") => {
                let part = mt_derive::nullifier::part(&vector_secret, window)
                    .ok_or_else(|| "the secret of the vector yields no half of the family".to_string())?;
                compare_hash(label, value, &part)?
            }
            _ => {}
        }
    }
    Ok(())
}

// The aggregate of the draw, the ticket and the two canonical orders.
pub fn check_orders(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, ORDERS_HEADER)?;
    let inputs = labeled(&rows, "cemented set")?;
    let set_cell = inputs
        .split('{')
        .nth(1)
        .and_then(|c| c.split('}').next())
        .ok_or_else(|| format!("the cemented set of the vector is unreadable: {inputs:?}"))?;
    let mut ids: Vec<[u8; 32]> = Vec::new();
    for part in set_cell.split(',') {
        ids.push(repeat32(part)?);
    }
    let window = window_of(inputs)?;
    let secret = input32(inputs, "machine_secret")?;
    // The members of a window are a set, and the aggregation refuses a run that holds one of them
    // twice: what the vectors of the set stand on is a set, so a refusal here is the set of the
    // document disagreeing with the rule, not an aggregate this gate may compute around.
    let aggregate = mt_derive::aggregate::aggregate(&ids, window)
        .map_err(|_| "the cemented set of the vectors holds one identity twice".to_string())?;
    compare_hash(
        "aggregate (non-empty)",
        labeled(&rows, "aggregate (non-empty)")?,
        &aggregate,
    )?;
    compare_hash(
        "aggregate (empty set)",
        labeled(&rows, "aggregate (empty set)")?,
        &mt_derive::aggregate::aggregate(&[], window)
            .map_err(|_| "the empty set holds a repeat".to_string())?,
    )?;
    compare_hash(
        "ticket",
        labeled(&rows, "ticket")?,
        &mt_derive::aggregate::ticket(&secret, &aggregate),
    )?;
    for (label, value) in &rows {
        if let Some(rest) = label.strip_prefix("selection_key(") {
            let commitment = repeat32(rest.trim_end_matches(')'))?;
            compare_hash(
                label,
                value,
                &mt_derive::aggregate::selection_key(&aggregate, &commitment),
            )?;
        }
        if let Some(rest) = label.strip_prefix("registration_key(") {
            let commitment = repeat32(rest.trim_end_matches(')'))?;
            compare_hash(
                label,
                value,
                &mt_derive::aggregate::registration_key(&aggregate, &commitment),
            )?;
        }
    }
    Ok(())
}

// A point named by the call that computes it, and the window the key of that point belongs to:
// `round_point(W, j, r, i), W` or `window_point(W, i), W`. The set writes the point as the call
// rather than as bytes, so a reader of the set sees which point a key belongs to without holding
// the table of points in their head, and a value written in place of the call is refused.
fn point_and_window(rest: &str) -> Result<([u8; mt_derive::delivery::POINT_BYTES], u64), String> {
    let close = rest
        .find(')')
        .ok_or_else(|| format!("a call that never closes: {rest}"))?;
    let inner = &rest[..close];
    let tail = rest[close + 1..].trim_start_matches(',').trim();
    let window = number(tail.trim_end_matches(')').trim())?;
    let numbers = |call: &str| -> Result<Vec<u64>, String> {
        call.split(',').map(|one| number(one.trim())).collect()
    };
    if let Some(call) = inner.strip_prefix("round_point(") {
        let held = numbers(call)?;
        let [w, j, r, i] = held[..] else {
            return Err(format!("a point of a round takes four values: {inner}"));
        };
        return Ok((
            mt_derive::delivery::round_point(
                w,
                u8::try_from(j).map_err(|e| format!("a chain beyond a byte: {e}"))?,
                u32::try_from(r).map_err(|e| format!("a round beyond four bytes: {e}"))?,
                u8::try_from(i).map_err(|e| format!("an index beyond a byte: {e}"))?,
            ),
            window,
        ));
    }
    if let Some(call) = inner.strip_prefix("window_point(") {
        let held = numbers(call)?;
        let [w, i] = held[..] else {
            return Err(format!("a point of a window takes two values: {inner}"));
        };
        return Ok((
            mt_derive::delivery::window_point(
                w,
                u8::try_from(i).map_err(|e| format!("an index beyond a byte: {e}"))?,
            ),
            window,
        ));
    }
    Err(format!("a point of no family this set names: {inner}"))
}

// The right to collect, the two points of delivery, and the reference of an owner.
pub fn check_delivery(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, MESSAGES_HEADER)?;
    let inputs = labeled(&rows, "shared_secret")?;
    let shared = repeat32(bare_input(inputs))?;
    let window = window_of(inputs)?;
    compare_hash(
        "collect_right",
        labeled(&rows, "collect_right")?,
        &mt_derive::delivery::collect_right(&shared, window),
    )?;
    for (label, value) in &rows {
        if let Some(rest) = label.strip_prefix("round_point(") {
            let call = rest.trim_end_matches(')');
            compare16(
                label,
                value,
                mt_derive::delivery::round_point(
                    number(input_of(call, "W")?)?,
                    u8::try_from(number(input_of(call, "j")?)?)
                        .map_err(|e| format!("a chain beyond a byte: {e}"))?,
                    u32::try_from(number(input_of(call, "r")?)?)
                        .map_err(|e| format!("a round beyond four bytes: {e}"))?,
                    u8::try_from(number(input_of(call, "i")?)?)
                        .map_err(|e| format!("an index beyond a byte: {e}"))?,
                ),
            )?;
        }
        // The nullifier of the vector is stated as a hash of a literal, so the gate recomputes it
        // rather than taking the hex on faith: an input read but never verified is an input that
        // could be edited with every build staying green.
        if label == "test_nullifier" {
            compare_hash(label, value, &sha256(b"mt-vector-nullifier"))?;
        }
        if let Some(rest) = label.strip_prefix("notice_point(") {
            let call = rest.trim_end_matches(')');
            let nullifier = hex32(labeled(&rows, "test_nullifier")?)?;
            compare16(
                label,
                value,
                mt_derive::delivery::notice_point(
                    &nullifier,
                    number(input_of(call, "W")?)?,
                    u8::try_from(number(input_of(call, "i")?)?)
                        .map_err(|e| format!("an index beyond a byte: {e}"))?,
                ),
            )?;
        }
        if let Some(rest) = label.strip_prefix("window_point(") {
            let call = rest.trim_end_matches(')');
            compare16(
                label,
                value,
                mt_derive::delivery::window_point(
                    number(input_of(call, "W")?)?,
                    u8::try_from(number(input_of(call, "i")?)?)
                        .map_err(|e| format!("an index beyond a byte: {e}"))?,
                ),
            )?;
        }
        for (name, taken) in [
            (
                "point_step_key(",
                mt_derive::delivery::point_step_key
                    as fn(&[u8; mt_derive::delivery::POINT_BYTES], u64) -> [u8; 32],
            ),
            ("point_pipe_key(", mt_derive::delivery::point_pipe_key),
        ] {
            let Some(rest) = label.strip_prefix(name) else {
                continue;
            };
            let (point, window) = point_and_window(rest)?;
            compare_hash(label, value, &taken(&point, window))?;
        }
    }

    let entry_rows = parse_labeled(md, ENTRY_HEADER)?;
    let own = fixed_part::<32>(consumed(&entry_rows, "own_commitment")?)?;
    let reversed = fixed_part::<32>(consumed(&entry_rows, "reversed")?)?;
    // The catching power of the pair is checked before anything is computed from it: the second
    // commitment is the first one read backwards, so an implementation taking a commitment from
    // the low end reproduces one line of the block at the other. A pair that lost that property
    // would leave the block self-consistent and blind to the one wrong reading it exists to
    // refuse.
    let mut backwards = own;
    backwards.reverse();
    if backwards != reversed {
        return Err(format!(
            "the block holds {} and {}, where the first read backwards is {}: the pair catches no \
             implementation reading a commitment from the low end",
            hex(&own),
            hex(&reversed),
            hex(&backwards)
        ));
    }
    let entry_inputs = labeled(&entry_rows, "sender_secret")?;
    let sender = repeat32(bare_input(entry_inputs))?;
    let period = number(input_of(entry_inputs, "P")?)?;

    let mut points_walked = 0;
    for (label, value) in &entry_rows {
        let Some(rest) = label.strip_prefix("entry_point(") else {
            continue;
        };
        let inner = rest.trim_end_matches(')');
        let (which, rest) = inner
            .split_once(',')
            .ok_or_else(|| format!("a point of a ring without a ring: {label}"))?;
        let commitment = match which.trim() {
            "own_commitment" => own,
            "reversed" => reversed,
            other => return Err(format!("a point taken over an unnamed commitment: {other}")),
        };
        let at = match input_of(rest, "P") {
            Ok(stated) => number(stated)?,
            Err(_) => period,
        };
        let j = u8::try_from(number(input_of(rest, "j")?)?)
            .map_err(|e| format!("a ring beyond a byte: {e}"))?;
        let computed = mt_derive::delivery::entry_point(&commitment, &sender, at, j)
            .ok_or_else(|| format!("the set freezes a ring the Decree does not hold: {label}"))?;
        compare_hash(label, value, &computed)?;
        points_walked += 1;
    }
    if points_walked < 5 {
        return Err(format!(
            "the block freezes {points_walked} points of a ring where the wrong implementations \
             it must refuse take five"
        ));
    }
    Ok(())
}

// The suite table: every row against the scheme the code reads that number as, and the width
// of its signature.
pub fn check_suite_table(md: &str) -> Result<(), String> {
    let body = section(md, "### The suite table", &["\n### ", "\n## "])?;
    let mut rows = 0;
    for line in body.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') || trimmed.starts_with("|---") {
            continue;
        }
        let cells: Vec<&str> = trimmed
            .split('|')
            .map(str::trim)
            .filter(|c| !c.is_empty())
            .collect();
        let Some(id_cell) = cells.first() else {
            continue;
        };
        let Ok(stated_id) = number(id_cell) else {
            continue;
        };
        let suite_id =
            u16::try_from(stated_id).map_err(|e| format!("a suite beyond a u16: {e}"))?;
        let held = mt_suite::suite::scheme(suite_id).ok_or_else(|| {
            format!("suite divergence: the set holds a row {suite_id}, the code holds no scheme for it")
        })?;
        let stated_name = cells
            .get(1)
            .ok_or_else(|| format!("the row {suite_id} names no scheme"))?;
        if *stated_name != held.name() {
            return Err(format!(
                "suite divergence at {suite_id}: the set names `{stated_name}`, the code names `{}`",
                held.name()
            ));
        }
        // The row binds the scheme and every width it brings: the two keys and the signature, each
        // read at its own column, so two widths swapping places is a divergence and not a sum that
        // happens to match.
        let widths: [(usize, usize, &str); 3] = [
            (2, mt_codec::size::SIGNING_SECRET_KEY, "the secret key"),
            (3, mt_codec::size::SIGNING_PUBLIC_KEY, "the public key"),
            (4, held.signature_size(), "the signature"),
        ];
        for (column, code_width, what) in widths {
            let cell = cells
                .get(column)
                .ok_or_else(|| format!("the row {suite_id} names no width of {what}"))?;
            let stated = number(cell.trim_end_matches('B').trim())? as usize;
            if stated != code_width {
                return Err(format!(
                    "suite divergence at {suite_id}, {what}: the set states {stated} B, the code holds {code_width} B"
                ));
            }
            verified_note(id_cell, cell);
        }
        rows += 1;
    }
    if rows != mt_suite::suite::TABLE.len() {
        return Err(format!(
            "suite divergence: the set states {rows} rows, the code holds {}",
            mt_suite::suite::TABLE.len()
        ));
    }
    Ok(())
}

// The layout of the committed record of a person. The set says its field SET awaits the one open
// link the Constitution names, and that until then an implementation reproduces the ORDER and the
// WIDTHS stated. Those two are therefore checkable today, and nothing was checking them: the fence
// stood in the set, the struct stood in the code, and neither knew of the other. What awaits is
// whether a field may still join; what does not await is that the fields written today have the
// widths written today, and a field joining one side alone moves the sum and is caught here.
fn check_record_layout(md: &str) -> Result<(), String> {
    // The name stands in prose several times before the layout does; what opens the layout is the
    // name alone on its own line, inside a fence.
    let at = md
        .find("\nserialize(record)\n")
        .map(|i| i + 1)
        .ok_or("the set states no layout of the committed record")?;
    let fence = md[at..]
        .find("```")
        .map(|end| &md[at..at + end])
        .ok_or("the layout of the committed record does not close")?;
    let mut fields: Vec<(String, u64)> = Vec::new();
    for line in fence.lines().skip(1) {
        let mut words = line.split_whitespace();
        let (Some(name), Some(width)) = (words.next(), words.next()) else {
            continue;
        };
        if words.next() != Some("B") {
            continue;
        }
        fields.push((name.to_string(), number(width)?));
    }
    if fields.len() < 2 {
        return Err(format!(
            "the layout of the committed record parses to {} fields, which is no layout",
            fields.len()
        ));
    }
    let stated: u64 = fields.iter().map(|(_, width)| width).sum();
    let held = <mt_state::layout::Record as mt_state::Layout>::expected_len() as u64;
    if stated != held {
        let written: Vec<String> = fields
            .iter()
            .map(|(name, width)| format!("{name} {width}"))
            .collect();
        return Err(format!(
            "record divergence: the set states {} fields summing to {stated} B, the code holds \
             {held} B — {}",
            fields.len(),
            written.join(", ")
        ));
    }
    Ok(())
}

pub const OPENING_THRESHOLD_HEADER: &str = "**Vector of the opening threshold**";
pub const DRAW_RETARGET_HEADER: &str = "**Vectors of the recomputation**";
pub const ROUND_THRESHOLD_HEADER: &str = "**Vectors of the threshold of a round**";
pub const CLOSE_HEADER: &str = "**Vectors:**";
pub const ANSWERS_HEADER: &str = "**Vectors of what a device answers:**";
pub const WAY_BACK_HEADER: &str = "**Vectors of the way back**";

// The one number a label of these blocks carries under a given name, read out of the label rather
// than restated: `recompute(target_old 3, cleared 0)` names both of its inputs.
fn labelled_input(label: &str, name: &str) -> Option<u64> {
    let at = label.find(name)? + name.len();
    let tail = label[at..].trim_start();
    let end = tail
        .char_indices()
        .find(|(_, c)| !c.is_ascii_digit() && *c != ' ')
        .map(|(i, _)| i)
        .unwrap_or(tail.len());
    number(&tail[..end]).ok()
}

fn threshold_of(hexed: &str) -> Result<mt_pulse::U256, String> {
    Ok(mt_pulse::U256::from_be_bytes(&hex32(hexed)?))
}

// The pulse: both recomputations at every vector the set freezes, the close of a window and the
// slots an event offers. What the gate computes is the code's own answer over the inputs the set
// writes into the label of each line, so a set that moved an input moves the answer with it.
pub fn check_pulse_arithmetic(md: &str) -> Result<(), String> {
    // The value both retargets begin from. It is derived from the width and stands in no row of the
    // Decree, so what the gate compares is the code's own answer against the line of the set.
    let begins = parse_labeled(md, OPENING_THRESHOLD_HEADER)?;
    let stated = consumed(&begins, "opening threshold")?;
    let held = mt_pulse::retarget::opening_threshold()
        .map_err(|e| format!("the opening threshold of the set does not compute: {e:?}"))?;
    compare_hash("opening threshold", stated, &held.to_be_bytes())?;

    let draw = parse_labeled(md, DRAW_RETARGET_HEADER)?;
    let opening = threshold_of(consumed(&draw, "target_old 2^248")?)?;
    let mut walked = 0;
    for (label, stated) in &draw {
        let Some(cleared) = labelled_input(label, "cleared") else {
            continue;
        };
        let old = match labelled_input(label, "target_old ") {
            Some(v) => mt_pulse::U256::from_u64(v),
            None => opening,
        };
        let held = mt_pulse::retarget::recompute_draw(old, cleared)
            .map_err(|e| format!("the draw retarget of the set does not compute: {e:?}"))?;
        compare_hash(label, stated, &held.to_be_bytes())?;
        walked += 1;
    }
    if walked < 5 {
        return Err(format!("the set freezes {walked} vectors of the draw retarget"));
    }

    let round = parse_labeled(md, ROUND_THRESHOLD_HEADER)?;
    let mut read = 0;
    for (label, stated) in &round {
        let Some(admitted) = labelled_input(label, "admitted") else {
            continue;
        };
        let chains = labelled_input(label, "k").unwrap_or(1);
        let held = mt_pulse::retarget::round_threshold(admitted, chains)
            .map_err(|e| format!("the threshold of a round of the set does not compute: {e:?}"))?;
        compare_hash(label, stated, &held.to_be_bytes())?;
        read += 1;
    }
    if read < 7 {
        return Err(format!(
            "the set freezes {read} vectors of the threshold of a round"
        ));
    }

    let close = parse_labeled(md, CLOSE_HEADER)?;
    let mut closes = 0;
    let mut offers = 0;
    for (label, stated) in &close {
        if label.starts_with("quorum(") {
            let cemented = labelled_input(label, "cemented")
                .ok_or_else(|| format!("a close of the set names no cemented standing: {label}"))?;
            let total = labelled_input(label, "total")
                .ok_or_else(|| format!("a close of the set names no total: {label}"))?;
            let held = mt_pulse::close::quorum_reached(u128::from(cemented), u128::from(total))
                .map_err(|e| format!("the close of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, u64::from(held))?;
            closes += 1;
        }
        if label.starts_with("offered(") {
            let active = labelled_input(label, "active")
                .ok_or_else(|| format!("an offering of the set names no population: {label}"))?;
            let held = mt_pulse::close::offered(active)
                .map_err(|e| format!("the offering of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, held)?;
            offers += 1;
        }
    }
    if closes < 4 || offers < 5 {
        return Err(format!(
            "the set freezes {closes} vectors of the close and {offers} of the offering"
        ));
    }

    // The way back: the share at every round the set pins it at, the close at the floor from both
    // sides, and the round a restart is admitted at.
    let back = parse_labeled(md, WAY_BACK_HEADER)?;
    let mut shares = 0;
    let mut floors = 0;
    let mut restarts = 0;
    for (label, stated) in &back {
        if let Some(rest) = label.strip_prefix("resume_share_num(") {
            let rounds = labelled_input(rest.trim_end_matches(')'), "rounds")
                .ok_or_else(|| format!("a share of the set names no count of rounds: {label}"))?;
            let held = mt_pulse::close::resume_share_num(rounds)
                .map_err(|e| format!("the way back of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, held)?;
            shares += 1;
        }
        if let Some(rest) = label.strip_prefix("closes(") {
            let call = rest.trim_end_matches(')');
            let cemented = labelled_input(call, "cemented")
                .ok_or_else(|| format!("a close of the set names no cemented standing: {label}"))?;
            let total = labelled_input(call, "total")
                .ok_or_else(|| format!("a close of the set names no total: {label}"))?;
            let rounds = labelled_input(call, "rounds")
                .ok_or_else(|| format!("a close of the set names no count of rounds: {label}"))?;
            let held = mt_pulse::close::closes(u128::from(cemented), u128::from(total), rounds)
                .map_err(|e| format!("the way back of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, u64::from(held))?;
            floors += 1;
        }
        if let Some(rest) = label.strip_prefix("restart_admitted(") {
            let rounds = labelled_input(rest.trim_end_matches(')'), "rounds")
                .ok_or_else(|| format!("a restart of the set names no count of rounds: {label}"))?;
            let held = mt_pulse::close::restart_admitted(rounds)
                .map_err(|e| format!("the way back of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, u64::from(held))?;
            restarts += 1;
        }
    }
    if shares < 7 || floors < 2 || restarts < 2 {
        return Err(format!(
            "the set freezes {shares} shares of the way back, {floors} closes at the floor and \
             {restarts} rounds of a restart, where the fall, its floor and its onset take seven, \
             two and two"
        ));
    }
    Ok(())
}

// What a device spends on a stranger: the ceiling of the links it did not open and the equal
// division of a window's budget. Both are comparisons of the Decree read back out of the labels
// the set writes them under.
pub fn check_device_answers(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, ANSWERS_HEADER)?;
    let mut ceilings = 0;
    let mut shares = 0;
    for (label, stated) in &rows {
        if label.starts_with("answers(") {
            let inbound = labelled_input(label, "inbound")
                .ok_or_else(|| format!("a ceiling of the set names no count of links: {label}"))?;
            let held = mt_wire::links::answers(inbound)
                .map_err(|e| format!("the ceiling of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, u64::from(held))?;
            ceilings += 1;
        }
        if label.starts_with("share(") {
            let budget = labelled_input(label, "budget")
                .ok_or_else(|| format!("a share of the set names no budget: {label}"))?;
            let held = mt_wire::links::share(budget)
                .map_err(|e| format!("the share of the set does not compute: {e:?}"))?;
            compare_number(label, number(stated)?, held)?;
            shares += 1;
        }
    }
    if ceilings < 3 || shares < 2 {
        return Err(format!(
            "the set freezes {ceilings} vectors of the ceiling and {shares} of the share, where \
             the floor of the division and both sides of the ceiling take three and two"
        ));
    }
    Ok(())
}

// Every heading of a derivation that restates a value of the Decree, held against the row it
// names. A section writes its own value in its heading — ``### `cell_bytes` = 1 232`` — and that
// is a second statement of a number whose one place is the Decree: the two agree today and
// nothing holds them there. A heading that states a value and names no row of the Decree fails
// here too, since a value restated outside the block that holds it is the defect this stage is
// drawn against.
pub fn check_derivation_headings(md: &str) -> Result<usize, String> {
    let tau2 = mt_genesis::scalar("tau2");
    let mut compared = 0usize;
    for line in md.lines() {
        let Some(rest) = line.strip_prefix("### ") else {
            continue;
        };
        let Some(at) = rest.find('=') else {
            continue;
        };
        let (named, stated) = (&rest[..at], rest[at + 1..].trim());
        let names = ticked(named);
        if names.is_empty() {
            continue;
        }
        // A unit written after the number — `2 windows`, `1 440 windows` — belongs to the reader
        // and not to the value.
        let stated = stated
            .split_whitespace()
            .take_while(|word| {
                word.chars()
                    .all(|c| c.is_ascii_digit() || c == '\u{2082}' || c == '\u{03c4}')
                    || *word == "over"
            })
            .collect::<Vec<_>>()
            .join(" ");
        let halves: Vec<&str> = stated.split(" over ").collect();
        if halves.len() != names.len() {
            return Err(format!(
                "a heading states {} values under {} names: {line:?}",
                halves.len(),
                names.len()
            ));
        }
        for (name, half) in names.iter().zip(halves.iter()) {
            let value = scalar_value(half, tau2)?;
            let held = match mt_genesis::scalar(name) {
                Some(held) => held,
                None => match name.rsplit_once('_') {
                    // A ratio stands in the Decree under one name and in a heading under two.
                    Some((base, "num")) => mt_genesis::ratio(base).map(|(num, _)| num).ok_or_else(
                        || format!("a heading names `{name}`, which the Decree does not hold"),
                    )?,
                    Some((base, "den")) => mt_genesis::ratio(base).map(|(_, den)| den).ok_or_else(
                        || format!("a heading names `{name}`, which the Decree does not hold"),
                    )?,
                    _ => {
                        return Err(format!(
                            "a heading states a value under `{name}`, which the Decree does not hold"
                        ))
                    }
                },
            };
            if value != held {
                return Err(format!(
                    "heading divergence at `{name}`: the heading states {value}, the Decree holds {held}"
                ));
            }
            verified_note_number(name, value);
            compared += 1;
        }
    }
    if compared == 0 {
        return Err("no heading of a derivation restates a value of the Decree".to_string());
    }
    Ok(compared)
}

// The widths of the integer classes, held against what the code writes. The table of the
// canonical serialization states them and nothing compared them: a class encoded one byte wider
// than the set says moves every layout that carries it, and the round trips of that class would
// still pass, since a round trip is agreement of the code with itself.
pub fn check_encoding_widths(md: &str) -> Result<(), String> {
    use mt_codec::encode::CanonicalEncode;
    let body = section(md, "## Canonical serialization", &["\n## "])?;
    let width_of = |name: &str| -> Option<usize> {
        match name {
            "u8" => Some(0u8.encode().len()),
            "u16" => Some(0u16.encode().len()),
            "u32" => Some(0u32.encode().len()),
            "u64" => Some(0u64.encode().len()),
            "u128" => Some(0u128.encode().len()),
            _ => None,
        }
    };
    let mut compared = 0usize;
    for line in body.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') || trimmed.starts_with("|---") {
            continue;
        }
        let cells: Vec<&str> = trimmed.trim_matches('|').split('|').map(str::trim).collect();
        let (Some(name), Some(stated)) = (cells.first(), cells.get(1)) else {
            continue;
        };
        let Some(held) = width_of(name) else {
            continue;
        };
        let width = number(stated.trim_end_matches('B').trim())? as usize;
        if width != held {
            return Err(format!(
                "encoding divergence at `{name}`: the set states {width} B, the code writes {held} B"
            ));
        }
        verified_note(name, stated);
        compared += 1;
    }
    if compared < 5 {
        return Err(format!(
            "the table of the canonical serialization yielded {compared} widths of an integer class"
        ));
    }
    Ok(())
}

// The table of demands, read as the law it is: every row of it asks properties out of one closed
// vocabulary, and a form of the Kernel that demands nothing is a form nobody can admit a function
// for. A property outside the vocabulary would be a demand no row of the hash table can answer,
// because there would be nothing to answer it against.
pub fn check_demands(md: &str) -> Result<(), String> {
    const PROPERTIES: [&str; 5] = [
        "collision resistance",
        "preimage resistance",
        "pseudorandomness",
        "width",
        "provability inside the circuit",
    ];
    let body = section(md, "### The table of demands", &["\n### ", "\n## "])?;
    let mut rows = 0usize;
    for line in body.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') || trimmed.starts_with("|---") || trimmed.starts_with("| Form")
        {
            continue;
        }
        let cells: Vec<&str> = trimmed.trim_matches('|').split('|').map(str::trim).collect();
        let (Some(form), Some(asked)) = (cells.first(), cells.get(1)) else {
            continue;
        };
        let demanded: Vec<&str> = asked.split(',').map(str::trim).collect();
        if demanded.is_empty() || asked.is_empty() {
            return Err(format!("the form `{form}` demands nothing of a function"));
        }
        for property in &demanded {
            if !PROPERTIES.contains(property) {
                return Err(format!(
                    "the form `{form}` demands `{property}`, which the table of demands does not carry"
                ));
            }
        }
        rows += 1;
    }
    if rows == 0 {
        return Err("the table of demands holds no form".to_string());
    }
    Ok(())
}

// Every layout of the code is named by the set, and every layout the set names is held by the
// code. The enumeration runs from both sides, because one side alone answers only half the
// question: a layout written without a place in the set passes a check that reads the set, and a
// layout the set names and the code never wrote passes a check that reads the code.
// The labels the source declares, read where they are written: a layout of this tree opens with
// `layout! {` and states its label on the line after. This is the denominator the register lacks
// on its own — the count of the rows compared with the count of the layouts the source declares,
// so a layout written without a row fails the build with its name rather than standing outside
// every comparison the gate makes.
fn layouts_of_the_source() -> Result<Vec<String>, String> {
    let path = crates_dir().join("mt-state").join("src").join("layout.rs");
    let text = std::fs::read_to_string(&path)
        .map_err(|e| format!("the layouts of the tree are unreadable at {path:?}: {e}"))?;
    let mut out = Vec::new();
    let mut lines = text.lines();
    while let Some(line) = lines.next() {
        if line.trim_end() != "layout! {" {
            continue;
        }
        // The declaration may open with a doc comment of its own; the label stands on the first
        // line after it that carries one.
        for following in lines.by_ref() {
            let trimmed = following.trim();
            if trimmed.starts_with("///") {
                continue;
            }
            let Some(at) = trimmed.find('"') else {
                break;
            };
            let rest = &trimmed[at + 1..];
            let Some(end) = rest.find('"') else {
                break;
            };
            out.push(rest[..end].to_string());
            break;
        }
    }
    if out.is_empty() {
        return Err(format!("no layout of this tree was read at {path:?}"));
    }
    Ok(out)
}

pub fn check_layout_register(md: &str) -> Result<(), String> {
    let held = mt_state::layout::NAMES;
    let declared = layouts_of_the_source()?;
    let mut without_a_row: Vec<&str> = declared
        .iter()
        .map(String::as_str)
        .filter(|label| !held.iter().any(|(name, _)| name == label))
        .collect();
    without_a_row.sort_unstable();
    if !without_a_row.is_empty() {
        return Err(format!(
            "layouts the source declares and the register does not hold: {}",
            without_a_row.join(", ")
        ));
    }
    let mut without_a_layout: Vec<&str> = held
        .iter()
        .map(|(name, _)| *name)
        .filter(|name| !declared.iter().any(|label| label == name))
        .collect();
    without_a_layout.sort_unstable();
    if !without_a_layout.is_empty() {
        return Err(format!(
            "rows of the register the source declares no layout for: {}",
            without_a_layout.join(", ")
        ));
    }
    let mut absent = Vec::new();
    for (name, in_the_set) in held {
        if !md.contains(*name) && !md.contains(*in_the_set) {
            absent.push(*name);
        }
    }
    if !absent.is_empty() {
        return Err(format!(
            "layouts the code holds and the set does not name: {}",
            absent.join(", ")
        ));
    }
    // The other direction: every line of the set that opens a layout block names a layout the code
    // holds. A block is opened by `serialize(` in this set, and what stands inside the parentheses
    // is the layout it lays out.
    for line in md.lines() {
        // Only a line that is nothing but `serialize(name)` opens a layout block; the same call
        // inside a sentence is a reference and not a block.
        let trimmed = line.trim();
        let Some(rest) = trimmed.strip_prefix("serialize(") else {
            continue;
        };
        if !rest.ends_with(')') {
            continue;
        }
        let Some(named) = rest.strip_suffix(')') else {
            continue;
        };
        // The register carries both spellings — the name this tree uses and the name the set
        // writes — so neither document has to guess at the other's.
        if held.iter().any(|(_, in_the_set)| *in_the_set == named) {
            continue;
        }
        if mt_wire::NAMES.contains(&named) {
            continue;
        }
        // Two spaces share the shape of a commitment and of a renewal, so the set lays each out
        // under its own name while the code holds one layout for both.
        if named == "channel_commit" || named == "channel_renew" {
            continue;
        }
        // A layout the set lays out and no crate of this tree holds yet is named here with the
        // crate that will hold it, and the mark is a claim the build checks: the day that crate
        // joins the workspace, the mark is refused and the layout must be read.
        const AWAITING_LAYOUTS: &[(&str, &str)] = &[("deposit", "mt-library")];
        if let Some((_, crate_name)) = AWAITING_LAYOUTS.iter().find(|(l, _)| *l == named) {
            if workspace_members()?.iter().any(|m| m == crate_name) {
                return Err(format!(
                    "an unearned mark: `{named}` is marked as awaiting `{crate_name}`, and that crate stands in the workspace"
                ));
            }
            continue;
        }
        return Err(format!(
            "the set lays out `{named}`, which is no layout this tree holds and no mark names as awaiting its stage"
        ));
    }
    Ok(())
}

// Every register of the tree, read by the gate. A register is written by the declaration of the
// constants it holds, so what stands here is the list of places to look and never the list of
// what is there — a constant added to a crate joins its register by being declared, and a crate
// whose register this list forgot is caught from the other side, where the sources are counted.
fn registers() -> Vec<&'static [mt_codec::Constant]> {
    vec![
        mt_codec::size::WIDTHS,
        mt_codec::derive::COMPOSITION_WIDTHS,
        mt_merkle::DEPTHS,
        mt_suite::aead::SEALING_WIDTHS,
        mt_suite::kem::KEM_WIDTHS,
        mt_suite::sign::SIGNING_WIDTHS,
        mt_suite::standing::LATTICE,
        mt_derive::delivery::DELIVERY_WIDTHS,
        mt_derive::fingerprint::FINGERPRINT,
        mt_derive::tag::TAG_WIDTHS,
        mt_state::PROOF_AND_COMMITMENT,
        mt_pulse::CHAINS,
        mt_store::STORE,
        mt_net::NET,
        montana_wallet::WALLET,
        mt_state::layout::ATTESTED,
        mt_wire::erasure::FIELD,
        mt_wire::message::COLLECTION_WIDTHS,
        mt_wire::link::LINK_FRAMING,
        mt_seed::BIRTH,
        mt_seed::words::WORD_SHAPE,
        mt_seed::sources::OF_THIS_TREE,
        mt_seed::sources::SAMPLING,
        mt_seed::sources::BOUND,
        mt_proof::field::FIELD,
        mt_proof::field::FOLD_OF_THE_PRIME,
        mt_proof::ext::EXTENSION,
        mt_proof::params::PARAMETERS,
        mt_proof::poly::DOMAINS,
        mt_proof::poseidon::SHAPE,
        mt_proof::circuit::permutation::LAYOUT,
        mt_proof::circuit::path::WALK,
        mt_proof::circuit::redemption::REDEMPTION,
        mt_proof::circuit::value::AMOUNTS,
        mt_proof::circuit::discharge::DISCHARGE,
        mt_proof::circuit::fold::FOLD,
        mt_proof::circuit::reduce::REDUCE,
        mt_proof::circuit::window::WINDOW,
        mt_proof::circuit::capacity::CAPACITIES,
        mt_proof::circuit::admission::ADMISSION,
        mt_proof::circuit::presence::PRESENCE,
        mt_proof::circuit::opening::OPENING,
        mt_proof::circuit::lane::LANE,
        mt_proof::circuit::frame::FRAME,
        mt_proof::circuit::moment::MOMENT,
        mt_proof::circuit::branch::BRANCH,
    ]
}

// The number as the set writes it in words. A value the gate cannot spell is refused rather than
// passed over: a spelling nobody holds is a comparison nobody makes.
fn spelled(value: u128) -> Option<&'static str> {
    Some(match value {
        1 => "one",
        2 => "two",
        3 => "three",
        4 => "four",
        5 => "five",
        6 => "six",
        7 => "seven",
        8 => "eight",
        9 => "nine",
        10 => "ten",
        11 => "eleven",
        12 => "twelve",
        16 => "sixteen",
        24 => "twenty-four",
        32 => "thirty-two",
        64 => "sixty-four",
        256 => "two hundred and fifty-six",
        _ => return None,
    })
}

// The spellings a number may stand in: the digits, the digits in the groups of three the set
// writes large numbers in, and the hexadecimal a field of a code is written in.
fn spellings_of(value: u128) -> Vec<String> {
    let mut out = vec![value.to_string()];
    if value >= 1_000 {
        out.push(with_spaces_128(value));
    }
    out.push(format!("{value:#X}"));
    out
}

fn with_spaces_128(value: u128) -> String {
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

// A span of the set stands once and carries the value it is offered for. Both halves are the
// comparison: a span that moved is a set this tree no longer transcribes, and a span that no
// longer carries the value is a number one of the two sides moved. The wrong implementation this
// refuses is the one that looked for the number anywhere near the place — under which a value of
// two or of four is found beside any place at all, and half the register compared nothing.
fn stands_once_and_carries(
    md: &str,
    name: &str,
    span: &str,
    value: u128,
    spelling: &str,
) -> Result<(), String> {
    let standings = md.matches(span).count();
    if standings == 0 {
        return Err(format!(
            "the constant `{name}` says it stands at {span:?}, and the set holds no such span"
        ));
    }
    if standings > 1 {
        return Err(format!(
            "the constant `{name}` says it stands at {span:?}, and the set holds {standings} of \
             them: a place standing more than once names none of them"
        ));
    }
    // The set opens a sentence with a capital and writes a field of a code in upper case, and
    // neither is a difference of value: what is compared is the number, not the shape of its
    // letters.
    if !span.to_lowercase().contains(&spelling.to_lowercase()) {
        return Err(format!(
            "the constant `{name}` holds {value}, and the span it names does not carry it: {span:?}"
        ));
    }
    Ok(())
}

// Every constant of every register stands where it says it stands, and the value the code holds is
// the value that place carries.
pub fn check_constants(md: &str) -> Result<(), String> {
    for register in registers() {
        for constant in register {
            let mt_codec::Constant { name, value, place } = *constant;
            match place {
                mt_codec::Place::Code(why) => {
                    if why.is_empty() {
                        return Err(format!(
                            "the constant `{name}` is of the code alone and says no reason"
                        ));
                    }
                }
                mt_codec::Place::Row(row) => {
                    let held = mt_genesis::scalar(row).ok_or_else(|| {
                        format!("the constant `{name}` names a row `{row}` the Decree does not hold")
                    })?;
                    if u128::from(held) != value {
                        return Err(format!(
                            "constant divergence at `{name}`: the row `{row}` holds {held}, the \
                             code holds {value}"
                        ));
                    }
                    verified_note_number(row, held);
                }
                mt_codec::Place::Writes(span) => {
                    let mut carried = false;
                    for spelling in spellings_of(value) {
                        if span.to_lowercase().contains(&spelling.to_lowercase()) {
                            stands_once_and_carries(md, name, span, value, &spelling)?;
                            carried = true;
                            break;
                        }
                    }
                    if !carried {
                        return Err(format!(
                            "the constant `{name}` holds {value}, and the span it names does not \
                             carry it in any spelling of the set: {span:?}"
                        ));
                    }
                }
                mt_codec::Place::Spells(span) => {
                    let word = spelled(value).ok_or_else(|| {
                        format!(
                            "the constant `{name}` holds {value}, which the gate cannot spell in \
                             words, so the span it names compares nothing"
                        )
                    })?;
                    stands_once_and_carries(md, name, span, value, word)?;
                }
            }
        }
    }
    check_every_numeral_is_registered()
}

// The denominator, taken from the side that can be counted. Every declaration of the sources whose
// value opens with a digit must stand in a register; a numeral declared outside one is a number no
// reading of this tree ever reaches, and it fails the build with its name. This is what makes the
// registers above an enumeration rather than a list of what somebody remembered.
// How many numerals the sources of this tree declare. `AUDIT.md` states the number, and a number of
// an audit taken by a grep of its author is a number nobody checks: this is the door the
// measurements read it through, so the day a constant is added the ledger is what fails.
pub fn numerals_declared() -> Result<usize, String> {
    Ok(numerals_of_the_sources()?.len())
}

pub fn check_every_numeral_is_registered() -> Result<(), String> {
    let held: Vec<&'static str> = registers()
        .iter()
        .flat_map(|register| register.iter().map(|c| c.name))
        .collect();
    let mut loose: Vec<String> = Vec::new();
    for (file, name) in numerals_of_the_sources()? {
        if !held.contains(&name.as_str()) {
            loose.push(format!("`{name}` at {file}"));
        }
    }
    if loose.is_empty() {
        return Ok(());
    }
    Err(format!(
        "numerals of this tree standing in no register: {}; a constant is declared together with \
         the place it stands at, and one declared outside a register is compared with nothing",
        loose.join(", ")
    ))
}

// The measurements the ledger of this tree states about itself, and the one place each is computed.
// A number of an audit taken by a reading of its author is a number nobody checks: what a stage
// adds to the tree moves these, and a ledger holding the old value says the tree is what it was.
// So each row below names the value it measures and the function that measures it, and the test
// beside the ledger holds the two together — the same shape the gate holds the set in.
//
// A row of the ledger this list does not carry is a number nothing computes; the test names it
// rather than passing over it, which is what keeps the list from being the part of the ledger
// somebody remembered to extend.
pub type Measurement = (&'static str, fn() -> Result<usize, String>);

pub const MEASURED: &[Measurement] = &[
    ("domains of the registry", domains_of_the_registry),
    ("numerals of the library, every one of them in a register", numerals_declared),
    ("implementations of `Layout`", layouts_declared),
    ("crates carrying the gate in their own tests", crates_carrying_the_gate),
    ("tests of the workspace", tests_of_the_workspace),
    ("rows of the Registry of mechanisms", mechanism_rows),
];

fn domains_of_the_registry() -> Result<usize, String> {
    let canon = std::fs::read_to_string(canon_path_of_the_crate())
        .map_err(|e| format!("the set is unreadable: {e}"))?;
    Ok(parse_registry(&canon)?.len())
}

fn canon_path_of_the_crate() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(CANON_RELATIVE)
}

fn registry_path_of_the_crate() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(REGISTRY_RELATIVE)
}

// The layouts the crate of the state declares, counted from the register it writes them in — the
// one the gate already holds against the set.
fn layouts_declared() -> Result<usize, String> {
    Ok(mt_state::layout::NAMES.len())
}

// The crates that carry the gate into their own tests. What is counted is the crates that have a
// test directory at all, against those whose tests invoke the gate: a crate that gained tests and
// not the gate is what this catches.
fn crates_carrying_the_gate() -> Result<usize, String> {
    let mut carrying = 0usize;
    for (name, tests) in test_directories()? {
        let mut invokes = false;
        for file in sources_under(&tests)? {
            let text = std::fs::read_to_string(&file)
                .map_err(|e| format!("a test of {name} is unreadable: {e}"))?;
            if text.contains("gate!") {
                invokes = true;
            }
        }
        if invokes {
            carrying += 1;
        }
    }
    Ok(carrying)
}

// Every test this workspace declares, counted where they are written. It is a measurement of the
// tree and never of a run: what a run says is whether they pass, and that is the four checks rather
// than a number in a table.
fn tests_of_the_workspace() -> Result<usize, String> {
    let mut out = 0usize;
    let root = crates_dir();
    let entries = std::fs::read_dir(&root)
        .map_err(|e| format!("the crates of the tree are unreadable at {root:?}: {e}"))?;
    for entry in entries {
        let path = entry.map_err(|e| format!("a crate is unreadable: {e}"))?.path();
        for under in ["src", "tests"] {
            let dir = path.join(under);
            if !dir.is_dir() {
                continue;
            }
            for file in sources_under(&dir)? {
                let text = std::fs::read_to_string(&file)
                    .map_err(|e| format!("a source is unreadable at {file:?}: {e}"))?;
                out += text.matches("#[test]").count();
            }
        }
    }
    Ok(out)
}

// The crates of this tree that hold tests of their own, with the directory those tests stand in.
fn test_directories() -> Result<Vec<(String, std::path::PathBuf)>, String> {
    let mut out = Vec::new();
    let root = crates_dir();
    let entries = std::fs::read_dir(&root)
        .map_err(|e| format!("the crates of the tree are unreadable at {root:?}: {e}"))?;
    for entry in entries {
        let path = entry.map_err(|e| format!("a crate is unreadable: {e}"))?.path();
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_string();
        let tests = path.join("tests");
        if tests.is_dir() {
            out.push((name, tests));
        }
    }
    Ok(out)
}

// The rows of the Registry of mechanisms, taken from the Registry itself — which recounts its own
// table on every build, so this reads the number that is already held rather than a second count.
fn mechanism_rows() -> Result<usize, String> {
    let registry = std::fs::read_to_string(registry_path_of_the_crate())
        .map_err(|e| format!("the Registry is unreadable: {e}"))?;
    Ok(parse_mechanism_registry(&registry)?.len())
}

// What the Registry says of its own rows, in the shape the ledger states them: the rows, those
// closed, those awaiting a stage, and those awaiting the artifact.
// The rows, those closed, those awaiting a stage, and those awaiting the artifact.
pub type RegistryCounts = (usize, usize, usize, usize);

pub fn mechanism_counts() -> Result<RegistryCounts, String> {
    let registry = std::fs::read_to_string(registry_path_of_the_crate())
        .map_err(|e| format!("the Registry is unreadable: {e}"))?;
    let rows = parse_mechanism_registry(&registry)?;
    let closed = rows.iter().filter(|r| r.awaits.is_empty()).count();
    let staged = rows
        .iter()
        .filter(|r| r.awaits.iter().any(|t| t.starts_with("stage ")))
        .count();
    let artifact = rows
        .iter()
        .filter(|r| r.awaits.iter().any(|t| t == "air_hash"))
        .count();
    Ok((rows.len(), closed, staged, artifact))
}

fn crates_dir() -> std::path::PathBuf {
    // PANIC-OK: the path is the one the compiler wrote for this crate at build time, and a crate of
    // this workspace stands inside the crates of the tree by the layout of the workspace itself. It
    // is of the gate and never of a node, so what it could refuse is a build and not a machine.
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("the crate stands inside the crates of the tree")
        .to_path_buf()
}

// Every declaration of a constant whose value opens with a digit, read out of the library sources.
// What is passed over is stated rather than implied: the harness itself, whose numbers are the
// comparisons; the tests, which are not the library; and the Decree, whose numbers are compared
// row by row against the set in both directions and would otherwise be compared twice.
fn numerals_of_the_sources() -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    let root = crates_dir();
    let entries = std::fs::read_dir(&root)
        .map_err(|e| format!("the crates of the tree are unreadable at {root:?}: {e}"))?;
    let mut crates: Vec<std::path::PathBuf> = Vec::new();
    for entry in entries {
        let path = entry.map_err(|e| format!("a crate is unreadable: {e}"))?.path();
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_string();
        if name == "mt-conformance" {
            continue;
        }
        if path.join("src").is_dir() {
            crates.push(path.join("src"));
        }
    }
    if crates.is_empty() {
        return Err(format!("no crate of this tree was read at {root:?}"));
    }
    for dir in crates {
        for file in sources_under(&dir)? {
            let text = std::fs::read_to_string(&file)
                .map_err(|e| format!("a source is unreadable at {file:?}: {e}"))?;
            let shown = file
                .strip_prefix(&root)
                .map(|p| p.display().to_string())
                .unwrap_or_else(|_| file.display().to_string());
            // The Decree is the one file whose numbers the gate already holds against the set row
            // by row, in both directions, and a second comparison of them would be a second place.
            if shown == "mt-genesis/src/lib.rs" {
                continue;
            }
            for name in numerals_of(&text) {
                out.push((shown.clone(), name));
            }
        }
    }
    Ok(out)
}

fn sources_under(dir: &std::path::Path) -> Result<Vec<std::path::PathBuf>, String> {
    let mut out = Vec::new();
    let entries =
        std::fs::read_dir(dir).map_err(|e| format!("a source directory is unreadable: {e}"))?;
    for entry in entries {
        let path = entry.map_err(|e| format!("a source is unreadable: {e}"))?.path();
        if path.is_dir() {
            out.extend(sources_under(&path)?);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
    out.sort();
    Ok(out)
}

// The names of the constants a source declares with a value opening with a digit. What is read is
// the library and never the tests: the text is cut at the first block of tests, which by the shape
// of this tree stands last in a file.
fn numerals_of(text: &str) -> Vec<String> {
    let library = text.split("#[cfg(test)]").next().unwrap_or(text);
    let mut out = Vec::new();
    for line in library.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("//") {
            continue;
        }
        let Some(after) = trimmed
            .strip_prefix("pub const ")
            .or_else(|| trimmed.strip_prefix("const "))
        else {
            continue;
        };
        let Some((name, rest)) = after.split_once(':') else {
            continue;
        };
        let name = name.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_uppercase() || c == '_' || c.is_ascii_digit())
        {
            continue;
        }
        let Some((_, value)) = rest.split_once('=') else {
            continue;
        };
        if value.trim_start().starts_with(|c: char| c.is_ascii_digit()) {
            out.push(name.to_string());
        }
    }
    out
}

// The canonical description of a constraint set: the artifact itself awaits its author, and its
// encoding does not. What the set freezes is a description small enough to read and real enough to
// exercise every part of the format, and what this compares is the bytes this tree writes for it
// and their digest — the one value of the proof machinery the set holds today.
pub fn check_air(md: &str) -> Result<(), String> {
    let rows = parse_labeled(md, AIR_HEADER)?;
    let held = mt_proof::air::the_description_of_the_set();
    let bytes = held.encode();
    let stated = consumed(&rows, "canonical description")?;
    let length: u64 = stated
        .trim()
        .trim_end_matches(" B")
        .replace(' ', "")
        .parse()
        .map_err(|e| format!("the length of the description is not a number: {stated:?} ({e})"))?;
    compare_number("canonical description", length, bytes.len() as u64)?;
    compare_hash("SHA-256 of it", labeled(&rows, "SHA-256 of it")?, &sha256(&bytes))?;
    // And what the vector is worth: the description it encodes is one of something. A vector over
    // an encoder of nothing would reproduce for ever and say nothing about a circuit.
    let public = mt_proof::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0]);
    if !held.satisfied_by(&mt_proof::air::the_trace_of_the_set(), &public) {
        return Err(
            "the description the vector fixes is not satisfied by the trace the set states"
                .to_string(),
        );
    }
    Ok(())
}

pub const AIR_HEADER: &str = "**The vector of the encoding.**";

// The value cell of a row named by its first cell, read where the set writes it: the tables of the
// proof scheme carry their numbers this way rather than in a fenced block.
fn table_value(md: &str, label: &str) -> Result<u64, String> {
    let ticked = format!("| `{label}` |");
    let plain = format!("| {label} |");
    let line = md
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with(&ticked) || line.starts_with(&plain))
        .ok_or_else(|| format!("the set holds no row `{label}`"))?;
    let cell = line
        .trim_matches('|')
        .split('|')
        .nth(1)
        .ok_or_else(|| format!("the row `{label}` carries no value"))?
        .trim()
        .trim_end_matches('B')
        .trim()
        .replace(' ', "");
    cell.parse::<u64>()
        .map_err(|e| format!("the row `{label}` carries no number: {cell:?} ({e})"))
}

// The parameters of the proof scheme, each against the row that states it, and the two roots a
// proof publishes against the width of a hash output. What this closes is the last of the values
// the coverage pass held as awaiting the crate of the proof machinery.
// The vectors of the trees, the identifier and the transcript of a proof. Each is recomputed here
// from the code that writes it, so a rule whose prose admits two readings is settled by bytes.
const PROOF_VECTORS_HEADER: &str = "**The vectors these stand or fall by.**";

// The authors' known answer for the permutation itself, held where the instantiation is stated:
// an implementation that transcribed one constant wrongly reproduces none of its twelve words.
const PROOF_PERMUTATION_HEADER: &str = "**The proof hash, named.**";

pub fn check_proof_permutation(md: &str) -> Result<(), String> {
    use mt_proof::field::F;
    let rows = parse_labeled(md, PROOF_PERMUTATION_HEADER)?;
    let mut state = [F::ZERO; mt_proof::poseidon::WIDTH];
    for (at, cell) in state.iter_mut().enumerate() {
        *cell = F::from_u64_reduced(at as u64);
    }
    mt_proof::poseidon::permute(&mut state);
    for (quarter, chunk) in state.chunks(4).enumerate() {
        let label = format!("proof permutation, words {}..{}", quarter * 4, quarter * 4 + 3);
        let stated = labeled(&rows, &label)?;
        let held = chunk
            .iter()
            .map(|cell| format!("{:016x}", cell.as_u64()))
            .collect::<Vec<_>>()
            .join(", ");
        if stated.trim() != held {
            return Err(format!(
                "the known answer of the permutation at {label}: the set holds {}, the code computes {held}",
                stated.trim()
            ));
        }
        verified_note(&label, stated);
    }
    Ok(())
}

pub fn check_proof_vectors(md: &str) -> Result<(), String> {
    use mt_proof::ext::E;
    use mt_proof::field::F;

    let rows = parse_labeled(md, PROOF_VECTORS_HEADER)?;
    let element = |a: u64, b: u64, c: u64| {
        E::of(
            F::from_u64_reduced(a),
            F::from_u64_reduced(b),
            F::from_u64_reduced(c),
        )
    };
    compare_hash(
        "proof leaf",
        labeled(&rows, "proof leaf")?,
        &mt_proof::commit::leaf_of_elements(&[element(1, 2, 3), element(4, 5, 6)]).bytes(),
    )?;
    // The children of the frozen node stand in the set as thirty-two bytes each, and a child of a
    // tree of a proof is a digest of the permutation. The door that tells the two apart is the one
    // a node of a path arrives through, so the vector is computed through it rather than beside it.
    let child = |bytes: &[u8; 32]| -> Result<mt_proof::poseidon::Digest, String> {
        mt_proof::poseidon::Digest::of_bytes(bytes).ok_or_else(|| {
            "a child of the frozen node of a proof is not a digest of the permutation".to_string()
        })
    };
    compare_hash(
        "proof node",
        labeled(&rows, "proof node")?,
        &mt_proof::commit::Tree::of(vec![child(&[0xAAu8; 32])?, child(&[0xBBu8; 32])?])
            .root()
            .bytes(),
    )?;

    let description = mt_proof::air::the_description_of_the_set();
    let air = description.identifier();
    compare_hash("proof air", labeled(&rows, "proof air")?, &air)?;

    let mut transcript = mt_proof::transcript::Transcript::opening(&air, &[1, 2, 3, 4, 5, 6, 7, 8]);
    compare_hash(
        "proof transcript zero",
        labeled(&rows, "proof transcript zero")?,
        &transcript.value(),
    )?;
    transcript.absorb(&[0xCCu8; 32]);
    compare_hash(
        "proof transcript one",
        labeled(&rows, "proof transcript one")?,
        &transcript.value(),
    )?;

    let draw = mt_proof::transcript::query_seed(&transcript);
    compare_hash(
        "proof query seed",
        labeled(&rows, "proof query seed")?,
        &draw.value(),
    )?;

    let shape = mt_proof::params::Shape::of_rows_log2(16)
        .map_err(|e| format!("the shape of a frame is not one the folding reaches: {e:?}"))?;
    let mut counter = 0u64;
    let drawn = draw.positions(&mut counter, 3, shape.domain());
    let stated = labeled(&rows, "proof query positions")?;
    let held = drawn
        .iter()
        .map(|p| p.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    verified_note("proof query positions", stated);
    if stated.trim() != held {
        return Err(format!(
            "the set and the code diverge — the positions a proof draws: the set holds {}, the code draws {held}",
            stated.trim()
        ));
    }
    Ok(())
}

pub fn check_proof_parameters(md: &str) -> Result<(), String> {
    use mt_proof::ext::ELEMENT_BYTES;
    use mt_proof::params as p;
    let rows: [(&str, u64); 10] = [
        ("proof_security_bits", u64::from(p::SECURITY_BITS)),
        ("proof_trace_width_bound", p::TRACE_WIDTH_BOUND as u64),
        ("proof_blowup", p::BLOWUP as u64),
        ("proof_queries", p::QUERIES as u64),
        ("proof_fold", p::FOLD as u64),
        ("proof_tail_degree", p::TAIL_DEGREE as u64),
        ("proof_ood_values", p::OOD_VALUES as u64),
        ("rows_per_permutation", p::ROWS_PER_PERMUTATION as u64),
        ("the commitment to the execution trace", p::ROOT_BYTES as u64),
        ("the commitment to the quotient", p::ROOT_BYTES as u64),
    ];
    for (label, held) in rows {
        compare_number(label, table_value(md, label)?, held)?;
    }
    // And the length of a proof is derived from those rows rather than restated: the shape of a
    // frame's trace gives the count of layers, the bytes of a query and the whole, and the number
    // the set freezes is what that arithmetic yields.
    let shape = mt_proof::params::Shape::of_rows_log2(16)
        .map_err(|e| format!("the shape of a frame is not one the folding reaches: {e:?}"))?;
    compare_number(
        "PROOF_LEN",
        table_value(md, "PROOF_LEN")?,
        shape.proof_bytes() as u64,
    )?;
    // The rows of the contents table that carry no single number are read where that arithmetic
    // consumes them: each is a term of the sum above, so a cell that moved would move the sum and
    // the comparison would refuse. The note is taken here, at the comparison, and not at a fetch.
    verified_note_number("one commitment per folding layer", p::ROOT_BYTES as u64);
    verified_note_number(
        "the evaluations out of the domain",
        (p::OOD_VALUES * ELEMENT_BYTES) as u64,
    );
    verified_note_number("the tail", (p::TAIL_DEGREE * ELEMENT_BYTES) as u64);
    verified_note_number("per query", shape.query_bytes() as u64);
    // The presence stands at its own height, and its length follows from the same arithmetic at
    // that height: the duty of every window is priced by its own statement, not by the tallest.
    compare_number(
        "presence_rows_log2",
        table_value(md, "presence_rows_log2")?,
        u64::from(mt_proof::circuit::presence::PRESENCE_ROWS_LOG2),
    )?;
    let of_presence = mt_proof::params::Shape::of_rows_log2(u32::from(
        mt_proof::circuit::presence::PRESENCE_ROWS_LOG2,
    ))
    .map_err(|e| format!("the height of the presence is not one the folding reaches: {e:?}"))?;
    if of_presence.proof_bytes() != mt_state::PRESENCE_PROOF_LEN {
        return Err(format!(
            "the length of a presence proof diverges: the shape yields {}, the state layer holds {}",
            of_presence.proof_bytes(),
            mt_state::PRESENCE_PROOF_LEN
        ));
    }
    compare_number(
        "PRESENCE_PROOF_LEN",
        table_value(md, "PRESENCE_PROOF_LEN")?,
        of_presence.proof_bytes() as u64,
    )?;
    Ok(())
}

pub fn check_all(md: &str) -> Result<(), String> {
    verified_reset();
    check_decree(&parse_decree(md)?)?;
    check_forms(&parse_forms(md)?)?;
    check_registry(&parse_registry(md)?)?;
    check_vectors(&parse_primitive_vectors(md)?)?;
    check_trees(md)?;
    check_proof_vectors(md)?;
    check_proof_permutation(md)?;
    check_walks(md)?;
    check_genesis_roots(md)?;
    check_identifiers(md)?;
    check_seed(md)?;
    check_sizes(md)?;
    check_layouts(md)?;
    check_record_layout(md)?;
    check_serialized_layouts(md)?;
    check_derivations(md)?;
    check_fold(md)?;
    check_standing(md)?;
    check_suite_table(md)?;
    check_pulse(md)?;
    check_orders(md)?;
    check_delivery(md)?;
    check_wire(md)?;
    check_pulse_arithmetic(md)?;
    check_device_answers(md)?;
    check_derivation_headings(md)?;
    check_demands(md)?;
    check_constants(md)?;
    check_layout_register(md)?;
    check_encoding_widths(md)?;
    check_genesis_state_hash(md)?;
    check_air(md)?;
    check_proof_parameters(md)?;
    check_awaiting_is_earned()?;
    check_coverage(md)?;
    Ok(())
}

// The identifiers of the three descriptions the network accepts proofs under, recomputed from the
// running circuits on every build and held against the set — and their binding held against the
// Decree's own row, so the one parameter that names the constraint sets can never drift from the
// circuits that are actually accepted.
pub const IDENTIFIERS_HEADER: &str = "air_hash = the hash, under the domain of a description's identifier";

pub fn check_identifiers(md: &str) -> Result<(), String> {
    let at = md
        .find(IDENTIFIERS_HEADER)
        .ok_or_else(|| "the set states the composition of air_hash".to_string())?;
    let body = &md[at..at + 2000.min(md.len() - at)];
    let depth = note_tree_depth()?;
    let places = mt_proof::circuit::frame::Places::of(depth)
        .ok_or_else(|| "the Decree names the shape of a frame".to_string())?;
    let of_frame = mt_proof::circuit::frame::description(&places, mt_proof::params::ROWS_LOG2)
    .ok_or_else(|| "the frame's description stands".to_string())?
    .identifier();
    let of_window = mt_proof::circuit::window::description().identifier();
    let of_admission = mt_proof::circuit::admission::description()
        .ok_or_else(|| "the admission's description stands".to_string())?
        .identifier();
    let of_presence = mt_proof::circuit::presence::description()
        .ok_or_else(|| "the presence's description stands".to_string())?
        .identifier();
    let of_opening = mt_proof::circuit::opening::description()
        .ok_or_else(|| "the opening's description stands".to_string())?
        .identifier();
    let mut bound = Vec::with_capacity(128);
    for (label, value) in [
        ("identifier of the frame", of_frame),
        ("identifier of the window", of_window),
        ("identifier of the admission", of_admission),
        ("identifier of the presence", of_presence),
        ("identifier of the opening", of_opening),
    ] {
        let line = body
            .lines()
            .find(|l| l.trim_start().starts_with(label))
            .ok_or_else(|| format!("the set freezes `{label}`"))?;
        let stated = line
            .split('=')
            .nth(1)
            .ok_or_else(|| format!("`{label}` carries a value"))?
            .trim();
        compare_hash(label, stated, &value)?;
        bound.extend_from_slice(&value);
    }
    let air = mt_codec::hash_of_one(mt_codec::domain::MT_PROOF_AIR, &bound);
    let decree = mt_genesis::PARAMETERS
        .iter()
        .find_map(|entry| match entry {
            mt_genesis::Entry::Hash(name, value) if *name == "air_hash" => Some(*value),
            _ => None,
        })
        .ok_or_else(|| "the Decree publishes air_hash".to_string())?;
    if air != decree {
        return Err(
            "the identifiers of the circuits and the Decree's air_hash are two values".to_string(),
        );
    }
    Ok(())
}

// The six roots the Genesis State Hash consumes, against the frozen empty root of each tree. Every
// one of the six is frozen elsewhere in the set with its own construction; what was missing is the
// sentence tying the six a genesis actually carries to those values. Without it a table could pick
// its doors one way and the set freeze them another, and no build would say a word — which is how a
// tree of the proof hash came to be folded under the SHA-256 doors of the state with its own
// domains, the one arrangement the set names a defect in as many words.
pub fn check_genesis_roots(md: &str) -> Result<(), String> {
    use mt_state::tables::Table;

    let merkle_rows = parse_labeled(md, MERKLE_EMPTIES_HEADER)?;
    let record_rows = parse_labeled(md, RECORD_TREE_HEADER)?;
    let note_rows = parse_labeled(md, NOTE_TREE_HEADER)?;
    let claim_rows = parse_labeled(md, CLAIM_HEADER)?;
    let sparse_top = format!("empty_internal({})", mt_merkle::KEY_BITS);
    let append_top = format!("empty_internal({})", note_tree_depth()?);

    let frozen: [(Table, &str); 6] = [
        (Table::Notes, "note_root (empty)"),
        (Table::Nullifiers, sparse_top.as_str()),
        (Table::Records, "record empty_internal(256)"),
        (Table::Machines, sparse_top.as_str()),
        (Table::Admitted, "admitted_root (empty)"),
        (Table::Operations, append_top.as_str()),
    ];

    let roots = mt_state::tables::genesis_roots();
    for (slot, (table, label)) in roots.iter().zip(frozen.iter()) {
        let rows = match *table {
            Table::Notes => &note_rows,
            Table::Records => &record_rows,
            Table::Admitted => &claim_rows,
            _ => &merkle_rows,
        };
        compare_hash(
            &format!("the genesis root of {table:?}"),
            labeled(rows, label)?,
            slot,
        )?;
        if slot != &table.empty_root() {
            return Err(format!(
                "the six of a genesis and the empty root of {table:?} are two values"
            ));
        }
    }
    Ok(())
}

// The tree of records folds under its own pair and under the proof hash, since a circuit walks it.
// The key and the record are those of the walk block above: one set of inputs, two families, and
// the values part — which is the whole of what these vectors say.
fn check_record_tree(
    md: &str,
    key: &[u8; 32],
    under_sha: &mt_merkle::SparseTree,
) -> Result<(), String> {
    use std::collections::BTreeMap;

    let rows = parse_labeled(md, RECORD_TREE_HEADER)?;
    let depth = mt_merkle::KEY_BITS;
    let empties = mt_proof::records::empty_internals(depth);
    let record = under_sha
        .get(key)
        .ok_or_else(|| "the walk vector holds no record at its key".to_string())?
        .to_vec();
    let mut held: BTreeMap<[u8; 32], Vec<u8>> = BTreeMap::new();
    held.insert(*key, record);
    let root = mt_proof::records::root_of(&held);

    for (label, value) in &rows {
        if label.starts_with("record empty") {
            let level = empty_level(label, depth, depth)?;
            compare_hash(label, value, &empties[level].bytes())?;
        } else if label == "record root (one record)" {
            compare_hash(label, value, &root.bytes())?;
        } else {
            return Err(format!(
                "a label the record tree checker does not hold: {label:?}"
            ));
        }
    }

    if root.bytes() == under_sha.root() {
        return Err("the tree of records folds identically in both families".to_string());
    }
    Ok(())
}
