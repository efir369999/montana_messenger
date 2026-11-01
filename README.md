# Montana Core

Montana Core is the native desktop application of Montana for Mac computers with Apple silicon. It is built from the same
Apple sources as Montana for iPhone and iPad: one source tree and one version. The desktop's version is the build number of
the iOS application, 1.0 (N), and a Mac build N and an iPhone build N are the same commit.

This repository is the reference copy of those sources and of the protocol core they link. Its folders `apps/apple` and
`core` are staged by the build road at every build of the main line and are not edited by hand;
[`RELEASES.md`](RELEASES.md) names, for every folder, the build, the source commit and the git tree of the folder.

The first release is planned for 31 October 2026, for review on the Metzdowd cryptography list.

## Status

Protocol closure is open. The 13 acceptance criteria of the protocol and their current status, with source evidence, are
kept in the audit of the Montana repository: [montana_messenger/Audit](https://github.com/efir369999/montana_messenger/tree/main/Audit).
Nothing in this repository claims more than those reports state.

<!-- download -->
## Download

Montana Core 1.0 (2336) for Mac, signed with a Developer ID and notarized by Apple.

|   |   |
| --- | --- |
| Release | [`v1.0-2336`](https://github.com/efir369999/montana_core/releases/tag/v1.0-2336) |
| File | [`Montana-Core-1.0-2336.dmg`](https://github.com/efir369999/montana_core/releases/download/v1.0-2336/Montana-Core-1.0-2336.dmg), the same bytes as https://montana.quest/download/mac/Montana-Core.dmg |
| SHA-256 | `20c8ea7ecc3d6c51b4e83e5bcb27599cfe8d0b1363e9e0543f27235bc2fd6ed6` |
| Source | `apps/apple` at commit `f081de58ab8d` (folder tree `8ef805eef33739cf86e425abfd5b1466f381b408`), staged from commit `d039af024dca` of the application's repository |
| Requires | A Mac with Apple silicon, macOS 14.2 or later |

The Mac build carries no VPN: a packet tunnel distributed outside the Mac App Store must be a system extension, and a Mac
Catalyst application cannot activate one.

### Verify

```sh
shasum -a 256 Montana-Core-1.0-2336.dmg
xcrun stapler validate Montana-Core-1.0-2336.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 Montana-Core-1.0-2336.dmg
hdiutil attach -readonly Montana-Core-1.0-2336.dmg
codesign --verify --deep --strict --verbose=2 "/Volumes/Montana Core/Montana Core.app"
spctl --assess --type execute --verbose=2 "/Volumes/Montana Core/Montana Core.app"
```

The checksum must equal the one above, and Gatekeeper must answer `source=Notarized Developer ID`.

### Reproduce

Anyone can rebuild this app from this repository and compare it with the release, file for file, signatures left out:

```sh
git clone --branch v1.0-2336 https://github.com/efir369999/montana_core.git
cd montana_core/apps/apple
curl -LO https://github.com/efir369999/montana_core/releases/download/v1.0-2336/Montana-Core-1.0-2336.dmg
python3 tools/mt-reproduce-mac.py --core ../../core/Code --compare Montana-Core-1.0-2336.dmg
```

The two digests it prints must be equal, and it must answer `REPRODUCED byte for byte`. It needs Xcode 26.2 (17C52), Rust 1.92.0 with the `aarch64-apple-ios-macabi` target, and the Go that `go.mod` names.
<!-- /download -->

## What this repository holds

| Path | What it is |
|---|---|
| [`apps/apple/`](apps/apple/) | Montana for Mac, iPhone and iPad (Swift). The Mac application is the Mac Catalyst arm64 product of the same Xcode project and target |
| [`core/`](core/) | The protocol core in Rust: the specification (`core/docs`), the reference implementation (`core/Montana-Core`) and the client core the applications link (`core/Code`) |
| [`RELEASES.md`](RELEASES.md) | The source commit, build and git tree of every folder, written by the publisher in the commit that changes the folder |
| [`docs/issue-75/`](docs/issue-75/README.md) | The review package of issue #75 of montana_messenger: transport metadata, link re-keying by ML-KEM-768 and in-band pipe healing, with the proofs and the paper. Written by hand, not staged by the build road |

A reader pins the exact bytes under review with `git rev-parse HEAD:apps/apple` and `git rev-parse HEAD:core`, and compares
them with the Folder tree column of [`RELEASES.md`](RELEASES.md).
