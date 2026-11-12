// The Decree as the model checker reads it. `mt_genesis::get` finds a row by a search of the table,
// a comparison of names at each row, and under the bound of a harness CBMC stops that search at the
// bound: the quorum is the fourteenth row and the finality rule the forty-second, so under a bound of
// nine the path of the close was cut rather than checked (F-438-1). The two rows the path reads are
// found here in a constant, from the table itself, and the stubs answer them with no loop; a name the
// stubs do not know fails the harness rather than reading a value written here.

use mt_genesis::{Entry, PARAMETERS};

const fn same(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

// PANIC-OK: read in a constant only, so a row the Decree does not carry stops the build.
const fn row(name: &str) -> &'static Entry {
    let mut i = 0;
    while i < PARAMETERS.len() {
        if same(PARAMETERS[i].name_const(), name) {
            return &PARAMETERS[i];
        }
        i += 1;
    }
    panic!("the Decree carries no such row")
}

const QUORUM_ROW: &str = "confirmation_quorum";
const FINALITY_ROW: &str = "finality_rule";

const QUORUM: (u64, u64) = match row(QUORUM_ROW) {
    Entry::Ratio(_, num, den) => (*num, *den),
    _ => panic!("the quorum is not a ratio"),
};

const FINALITY: u64 = match row(FINALITY_ROW) {
    Entry::Scalar(_, value) => *value,
    _ => panic!("the finality rule is not a scalar"),
};

fn word(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes([
        bytes[at],
        bytes[at + 1],
        bytes[at + 2],
        bytes[at + 3],
        bytes[at + 4],
        bytes[at + 5],
        bytes[at + 6],
        bytes[at + 7],
    ])
}

// Two names of eight to twenty-four bytes agree when their lengths agree and so do the three words
// that cover every byte -- the first eight, the second eight and the last eight -- read without the
// byte loop the bound would cut.
fn is(name: &str, row: &str) -> bool {
    let (a, b) = (name.as_bytes(), row.as_bytes());
    kani::assert(
        b.len() >= 8 && b.len() <= 24,
        "a row name the three words cover",
    );
    if a.len() != b.len() {
        return false;
    }
    let second = 8usize.min(a.len() - 8);
    word(a, 0) == word(b, 0)
        && word(a, second) == word(b, second)
        && word(a, a.len() - 8) == word(b, b.len() - 8)
}

pub(crate) fn ratio(name: &str) -> Option<(u64, u64)> {
    kani::assert(
        is(name, QUORUM_ROW),
        "the path reads no ratio of the Decree but the quorum",
    );
    Some(QUORUM)
}

pub(crate) fn scalar(name: &str) -> Option<u64> {
    kani::assert(
        is(name, FINALITY_ROW),
        "the path reads no scalar of the Decree but the finality rule",
    );
    Some(FINALITY)
}
