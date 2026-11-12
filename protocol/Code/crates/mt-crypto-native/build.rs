use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=csrc/mt_crypto.c");
    println!("cargo:rerun-if-changed=csrc/mt_crypto.h");
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=MT_OPENSSL_BUILD_DIR");
    println!("cargo:rerun-if-env-changed=SOURCE_DATE_EPOCH");

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
            // THE SAME BYTES FROM ANY FOLDER (decision 822 a, 11.11.2026): OpenSSL writes its install folder into the
            // library (ENGINESDIR, MODULESDIR) and its sources' paths into its objects, and OUT_DIR lies inside the tree,
            // so two clones built the same commit into different bytes. The release script names one fixed folder
            // (MT_OPENSSL_BUILD_DIR, one target in it) and SOURCE_DATE_EPOCH, which OpenSSL reads for «built on»;
            // other builds keep OUT_DIR, so tests of several trees never share a folder.
            let mut openssl = openssl_src::Build::new();
            // The C flags that rename the folders (TARGET_CFLAGS) stay out of OpenSSL: it writes its compiler flags into the
            // library, and they name this Mac's folders; its own folder is fixed already.
            let renaming = env::var_os("TARGET_CFLAGS");
            if let Some(fixed) = env::var_os("MT_OPENSSL_BUILD_DIR") {
                let target = env::var("TARGET").expect("TARGET set by cargo");
                openssl.out_dir(PathBuf::from(fixed).join(target));
                env::remove_var("TARGET_CFLAGS");
            }
            built = openssl.build();
            if let Some(flags) = renaming {
                env::set_var("TARGET_CFLAGS", flags);
            }
            (
                built.include_dir().to_path_buf(),
                built.lib_dir().to_path_buf(),
            )
        },
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
