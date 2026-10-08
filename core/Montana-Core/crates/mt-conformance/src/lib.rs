// The conformance harness of Montana Core. The build script is the gate: it parses the
// normative set and refuses a build in which the set and the code diverge, naming the value.
// This library exposes the same parser and checks so that the gate itself is testable.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

include!("parse.rs");
include!("registry.rs");

pub fn canon_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(CANON_RELATIVE)
}

pub fn registry_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(REGISTRY_RELATIVE)
}

pub fn plan_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(PLAN_RELATIVE)
}

pub fn set_document_paths() -> Vec<(String, std::path::PathBuf)> {
    SET_DOCUMENTS
        .iter()
        .map(|(name, rel)| {
            (
                name.to_string(),
                std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(rel),
            )
        })
        .collect()
}

// The gate as one declaration, invoked by every crate of this tree in a test of its own. What the
// plan promises is that nothing downstream compiles over a disagreement between the set and the
// code; a build of the whole workspace gives that through the build script here, and a build of one
// crate does not — and what a client written outside this tree compiles is the crate. So every
// crate carries the comparison into its own tests, and it carries it by **calling** this rather
// than by repeating it: ten copies of one invocation part at the first edit, and a copy that fell
// behind reads exactly like one that did not.
#[macro_export]
macro_rules! gate {
    () => {
        #[test]
        fn the_set_and_this_crate_agree() {
            let canon =
                ::std::fs::read_to_string($crate::canon_path()).expect("the set is readable");
            $crate::check_all(&canon).expect("no divergence between the set and the code");
        }
    };
}
