// Capture git SHA + commit date at build time so the resulting binary can
// answer `montana-node --version` with the exact revision it was compiled
// from. The values are exposed as compile-time env vars consumed via
// env!("MONTANA_GIT_SHA") and env!("MONTANA_GIT_COMMIT_DATE") in main.rs.
//
// When the source tree is not a git checkout (e.g. shipped as a tarball)
// both vars default to "unknown" — the binary still answers --version
// without aborting the build.

use std::process::Command;

fn main() {
    // Rerun build.rs on every change to HEAD so the SHA stays current.
    println!("cargo:rerun-if-changed=../../../.git/HEAD");
    println!("cargo:rerun-if-changed=../../../.git/refs/heads");

    let sha = git_output(&["rev-parse", "--short=12", "HEAD"]).unwrap_or_else(|| "unknown".into());
    let date = git_output(&["log", "-1", "--format=%cs"]).unwrap_or_else(|| "unknown".into());

    println!("cargo:rustc-env=MONTANA_GIT_SHA={sha}");
    println!("cargo:rustc-env=MONTANA_GIT_COMMIT_DATE={date}");
}

fn git_output(args: &[&str]) -> Option<String> {
    let out = Command::new("git").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8(out.stdout).ok()?;
    let trimmed = s.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}
