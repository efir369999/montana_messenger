// The core's ABI version, read from the core itself (mt-bindings/src/lib.rs: `pub const ABI_VERSION`),
// so the version footer names the core this library was built from — one number, one source.
fn main() {
    let lib = "../../../Montana Protocol/Code/crates/mt-bindings/src/lib.rs";
    println!("cargo:rerun-if-changed={lib}");
    let src = std::fs::read_to_string(lib).expect("the core's mt-bindings/src/lib.rs");
    let v = src
        .lines()
        .find_map(|l| l.trim().strip_prefix("pub const ABI_VERSION: u32 = "))
        .and_then(|r| r.trim_end_matches(';').trim().parse::<u32>().ok())
        .expect("ABI_VERSION in mt-bindings/src/lib.rs");
    println!("cargo:rustc-env=MT_ABI_VERSION={v}");
}
