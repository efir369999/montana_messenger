# Montana for Windows — Work in Progress

**Status: Work in Progress · Experimental · Partial Implementation · Not Yet Verified as a whole.**
Not a release. Do not use it with an identity that holds anything of value.

A port of Montana for iPhone (`apps/messenger/ios`, the original and the reference, build 1.0 (2305), commit `3926188`) to
Windows 10/11 as a [Tauri 2](https://tauri.app) program: Rust underneath, the interface in React. The goal is a copy of the iOS
app as exact as Windows allows, speaking the same wire with iPhones, Android phones and other Windows computers.

Porting and adaptation to Windows: **DinetPDA — Linkora**. Montana itself — the protocol, the core, the iOS app, its design and
its assets — is the work of its own authors; this port follows it and claims none of it. See [`CREDITS.md`](CREDITS.md).

## What is here

| Path | What it is | Lines |
|---|---|---|
| `app/src-tauri/src/` | The Windows side in Rust: identity, pipes and letters, archive and copies, groups, channels, calls' signalling, coins and the wallet, music, the VPN wall's client, the home node, Windows Hello, notifications | ~34 600 |
| `app/src/` | The interface (React 19 + Vite), drawn after the iOS screens | ~18 800 |
| `app/protocol-core/` | `montana_core.dll`: the core's boundary crate `core/Montana-Core/crates/mt-boundary`, unchanged, as one Windows library | 42 |
| `app/src-tauri/node/` | The home-node files the app installs on a machine one owns — byte for byte iOS's `Code/Node` | ~1 200 |
| `app/tools/` | UI-automation scenes (PowerShell + UI Automation) that drive two or more real windows with test identities on the live network | ~6 800 |

The core is not reimplemented. `mt_bindings.dll` is built from `core/Code` (crate `mt-bindings`, the C ABI iOS links as
`MontanaBindings.xcframework`) and called through that ABI; the keys and the 24 words stay inside the core and the Rust side and
never reach the web view.

## Honest state

Measured against a map of the iOS interface (1 501 rows: screens, pages, sheets, alerts, menus, actions, transitions, states):

| | Rows |
|---|---|
| Code present on Windows / partial / missing / not applicable / unclear | 610 / 495 / 321 / 52 / 23 |
| Functionally verified by a scene | 9 |
| Visually confirmed against iOS | 0 |
| Animations confirmed | 0 |

The UI-automation suite (`app/tools/all.ps1`) has 71 scenes, each driving two or more real windows with throwaway test
identities on the live Montana nodes. Its last full run (24.10.2026, against iOS 2304) passed 52 of 71; the 19 failures were
gone through one by one (12 scenes were out of date and rewritten, one program defect fixed, 6 passed on a fresh pair or on a
repeat). A full re-run since then has not been made. Scenes run since, on the current code: Saved Messages between two Windows
computers of one identity (archive blocks, both ways); drafts per chat; the photo album; deleting an account and coming back by
the same 24 words with another identity in between; the pipe secret's daily walk (iOS 2305, anchor day 20754 = 28.10.2026 UTC)
between Windows and the Android port on an emulator, with the clocks moved past the anchor.

**Not yet verified:** anything against a current iPhone (no iPhone at hand for these checks); most of the interface visually
against iOS; the VPN wall end to end; coin transfers other than between test identities; installation on a clean machine other than
the developer's.

Known gaps, among others: Live Text, Apple-only system features (Wallet passes, iCloud), and history from another device of the
same identity on Android (the Android port lacks iOS's twin mirror; planned).

## Build

Windows 11, MSVC Build Tools, Rust 1.92.0 (`x86_64-pc-windows-msvc`), Node 22, Perl for OpenSSL (Strawberry or Git's).

```powershell
# one target folder for the core and the app: the app finds mt_bindings.dll in its release folder
$env:CARGO_TARGET_DIR = "<repo>/apps/messenger/windows/target"
$env:RUSTUP_TOOLCHAIN = "1.92.0-x86_64-pc-windows-msvc"

# 1. the core's C ABI, in core/Code (needs the core/Code Windows commit of this branch)
cd <repo>/core/Code
$env:OPENSSL_SRC_PERL = "<path to perl.exe>"
cargo build --release -p mt-bindings

# 2. the protocol core's boundary (its own target folder inside, the DLL copied to target/release)
<repo>/apps/messenger/windows/app/tools/protocol-core.ps1

# 3. the program and its installer
cd <repo>/apps/messenger/windows/app
npm ci
npx tauri build
```

The result is `target/release/montana-desktop.exe` beside `mt_bindings.dll` and `montana_core.dll`, and an NSIS installer in
`target/release/bundle/nsis/` that installs for the current user without administrator rights.

## Checks, as last run (24.10.2026, Windows 11, Rust 1.92.0 MSVC)

In `app/src-tauri`:

| Command | Exit code | Result |
|---|---|---|
| `cargo test --lib` (debug) | 0 | 144 passed, 0 failed, 19 ignored |
| `cargo test --release --lib` | 0 | 144 passed, 0 failed, 19 ignored |
| `cargo clippy --all-targets -- -D warnings` | 0 | clean since the second commit of this port (24.10.2026): lints fixed, dead code removed or gated to tests, the core's ABI mirror kept with an `allow`; tests unchanged (144/144 in both profiles) |

The ignored tests need the live network or a second window and are run by the scenes in `app/tools/` instead.
In `core/Code`, before this branch's Windows commit: `cargo test --release --workspace` — 1 421 passed, 0 failed, 1 ignored
upstream (DEV-012).

No constant-time measurements (dudect or otherwise) have been made for this port; none are claimed. The Windows side adds no
secret-dependent cryptographic code of its own beyond what is named below.

## Cryptography

Montana's own protection is the core's: ML-KEM (FIPS 203), ML-DSA (FIPS 204), SHA-256 — called through the core's ABI, unchanged.
The Windows side uses, as iOS does at the same places:

- ChaCha20-Poly1305 and HKDF-SHA-256 for the `.mtbak` v2 backup file (the format iOS and Android read);
- AES-256-GCM (Windows CNG) for a group room's pair words, as iOS `MTRoomSeal` (`aesgcm.rs`);
- the Windows data-protection API (DPAPI) for this computer's seal of the local stores, where iOS uses the Keychain (`vault.rs`).

Classical public-key cryptography appears only where an external standard requires it and is not counted as Montana's
protection: TLS (WinHTTP, the nodes' doors), WebRTC (DTLS-SRTP of calls), SSH (setting up one's own node, `russh`), and the VPN
wall's own protocols. Nothing here was changed to satisfy a "PQ only" rule by removing those: they belong to the external
standards, exactly as on iOS.

**Dinet Device Sync** — a planned, separate add-on by DinetPDA — Linkora for one identity's own devices where iOS has no
mechanism. Design stage only; **no code in this branch**. It will be hybrid (classical + ML-KEM) with mandatory PQ, no silent
downgrade, and will not change the iOS wire.

## License

The core is dual-licensed MIT OR Apache-2.0 (`core/Code/LICENSE-MIT`, `core/Code/LICENSE-APACHE`). This port is offered to the
Montana project on the same terms as the repository it is proposed to. Third-party crates and npm packages keep their own
licenses (see `Cargo.lock`, `package-lock.json`). Every picture in `app/src/assets` and the app icon are Montana's own iOS or
Android assets from this repository, used for the same app; no Apple system artwork is shipped.
