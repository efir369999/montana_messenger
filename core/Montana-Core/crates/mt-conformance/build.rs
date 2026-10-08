// The gate. A divergence between the set and the code fails the build here, with the value
// named; nothing downstream compiles over a disagreement.

include!("src/parse.rs");
include!("src/registry.rs");
include!("src/completeness.rs");

fn main() {
    let manifest = std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets the manifest dir");
    let path = std::path::Path::new(&manifest).join(CANON_RELATIVE);
    println!("cargo:rerun-if-changed={}", path.display());
    // The gate reads the sources of the tree as well as the set — it counts the numerals they
    // declare against the registers — so a source that changes is a gate that must run again.
    let crates = std::path::Path::new(&manifest)
        .parent()
        .expect("the crate stands inside the crates of the tree");
    println!("cargo:rerun-if-changed={}", crates.display());
    let md = match std::fs::read_to_string(&path) {
        Ok(md) => md,
        Err(e) => panic!("the set is unreadable at {}: {e}", path.display()),
    };
    if let Err(divergence) = check_all(&md) {
        panic!("the set and the code diverge — {divergence}");
    }
    // And the completeness of the denominator itself: a domain of the registry no run of the gate
    // ever takes a preimage under is a rule of the set nothing compares.
    if let Err(divergence) = check_every_domain_is_exercised() {
        panic!("{divergence}");
    }
    // And the Registry of mechanisms: every anchor resolves, every domain and derivation has
    // its one owner, every awaited stage stands in the plan, and the counts recount.
    let manifest_dir = std::path::Path::new(&manifest);
    let read = |rel: &str| -> String {
        let p = manifest_dir.join(rel);
        println!("cargo:rerun-if-changed={}", p.display());
        match std::fs::read_to_string(&p) {
            Ok(s) => s,
            Err(e) => panic!("the set is unreadable at {}: {e}", p.display()),
        }
    };
    let registry = read(REGISTRY_RELATIVE);
    let plan = read(PLAN_RELATIVE);
    let docs: Vec<(String, String)> = SET_DOCUMENTS
        .iter()
        .map(|(name, rel)| (name.to_string(), read(rel)))
        .collect();
    if let Err(divergence) = check_mechanism_registry(&registry, &docs, &md, &plan) {
        panic!("the Registry and the set diverge — {divergence}");
    }
}
