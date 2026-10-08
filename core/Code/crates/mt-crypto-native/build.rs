use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=csrc/mt_crypto.c");
    println!("cargo:rerun-if-changed=csrc/mt_crypto.h");
    println!("cargo:rerun-if-changed=build.rs");

    // Mac Catalyst is the only Apple target the OpenSSL builder does not know by name: it
    // answers "don't know how to configure". Its configuration is exactly the macOS one, differing only in
    // the three-part platform triple in object files, which is set by compiler flags. This way
    // one tree builds for phone, tablet and Mac without a second crypto source.
    // A prebuilt OpenSSL, built separately, is used when the source builder does not know the target by name.
    // This way one tree builds for Mac (Catalyst) from the same crypto source.
    let prebuilt = env::var("MT_OPENSSL_DIR").ok().map(PathBuf::from);
    let built;
    let (openssl_include, openssl_lib) = match &prebuilt {
        Some(d) => (d.join("include"), d.join("lib")),
        None => {
            built = openssl_src::Build::new().build();
            (built.include_dir().to_path_buf(), built.lib_dir().to_path_buf())
        }
    };

    cc::Build::new()
        .file("csrc/mt_crypto.c")
        .include("csrc")
        .include(&openssl_include)
        .flag_if_supported("-std=c11")
        .flag_if_supported("-Wall")
        .flag_if_supported("-Wextra")
        .flag_if_supported("-Wpedantic")
        .flag_if_supported("-Werror")
        .flag_if_supported("-Wno-unused-parameter")
        .flag_if_supported("-Wno-unused-command-line-argument")
        .compile("mt_crypto");

    println!(
        "cargo:rustc-link-search=native={}",
        openssl_lib.to_str().expect("openssl lib path utf8")
    );
    println!("cargo:rustc-link-lib=static=ssl");
    println!("cargo:rustc-link-lib=static=crypto");

    let target_os = env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS set by cargo");
    if target_os == "macos" {
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
    } else if target_os == "linux" {
        println!("cargo:rustc-link-lib=dylib=dl");
        println!("cargo:rustc-link-lib=dylib=pthread");
    }

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR set by cargo"));
    println!("cargo:include={}", openssl_include.display());
    println!("cargo:lib={}", openssl_lib.display());
    println!("cargo:out={}", out_dir.display());
}
