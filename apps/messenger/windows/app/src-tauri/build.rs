use std::env;
use std::path::PathBuf;

// The core is linked as iOS links it: through its C ABI, from mt_bindings.dll built in the core's own workspace
// (core/Code, its own pinned versions). MONTANA_CORE_DIR names the folder of mt_bindings.dll.lib; by default the
// release folder of the target directory the core and the app share.
fn main() {
    let core = env::var("MONTANA_CORE_DIR").map(PathBuf::from).unwrap_or_else(|_| {
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../target/release")
    });
    if !core.join("mt_bindings.dll.lib").exists() {
        panic!(
            "the core is not built: no mt_bindings.dll.lib in {}. Build it first, in core/Code: \
             cargo +1.92.0-x86_64-pc-windows-msvc build --release -p mt-bindings",
            core.display()
        );
    }
    println!("cargo:rerun-if-env-changed=MONTANA_CORE_DIR");
    println!("cargo:rerun-if-changed={}", core.join("mt_bindings.dll.lib").display());
    println!("cargo:rustc-link-search=native={}", core.display());
    println!("cargo:rustc-link-lib=dylib=mt_bindings.dll");
    tauri_build::build()
}
