# Montana Messenger

Elegance. Aesthetics. Safety.

A simple, fast messenger for every day: chats, voice and video calls, groups and channels, on iPhone and iPad.

The app's page, its privacy policy, terms and support: https://montana.one

This repository is the source of the iOS app as it is built for the App Store: the app and the client core it links, and
nothing else. Staged from app b72b5ed286276c3dd5ba989824a484097754ad68, client core fd0c7a45155330057bbf0bb966ce2355430f7161.

## Layout

- ios/ -- the app: the targets MontanaMessenger (the app), MontanaMessengerNSE (notification service),
  MontanaMessengerShare (share extension) and MontanaMessengerBroadcast (screen broadcast), in
  ios/MontanaMessenger.xcodeproj, which holds these four targets alone.
- protocol/Code/ -- the Rust crates of the client core, built into MontanaBindings.xcframework. This snapshot is staged
  without the core's coin feature: the code only that feature compiles is not here.
- protocol/Montana wordlist.txt -- the canonical mnemonic wordlist protocol/Code/crates/mt-mnemonic compiles in.

## Building

You need macOS with Xcode, rustup and python3. The frameworks the app links are built locally into ios/Code/Frameworks
and are never committed. Build from the
repository root:

```sh
rustup toolchain install 1.92.0
rustup target add aarch64-apple-ios --toolchain 1.92.0
mkdir -p ios/Code/Frameworks
MT_EDITION=messenger bash protocol/Code/crates/mt-bindings/build-ios-xcframework.sh "$PWD/ios/Code/Frameworks/MontanaBindings.xcframework"
bash ios/fetch-webrtc.sh
open ios/MontanaMessenger.xcodeproj
```

fetch-webrtc.sh takes WebRTC.xcframework (webrtc-sdk 144.7559.10) only with the SHA-256 it pins. The frameworks are built
for devices only (arm64): run the scheme MontanaMessenger on an iPhone, with your own team under Signing.

## Verifying

Build 1.0 (2421) links one static library built from the revision above with rustc 1.92.0. The release
1.0-2421 of this repository holds it as the build linked it (https://github.com/efir369999/montana_messenger/releases/tag/1.0-2421):

- libmt_bindings.a (protocol/Code), SHA-256 c446c063b70b88ee6c60fb8fce80ce71905a413344dddb5a7281999b88225c32

Build it as under Building, download the archive beside the repository root and compare them (python3 alone):

```sh
python3 tools/compare-archives.py ios/Code/Frameworks/MontanaBindings.xcframework/ios-arm64/libmt_bindings.a libmt_bindings.a
```

Both archives are built the same in any folder: the compiler names the tree /montana and the crates' home /cargo,
and OpenSSL builds in /tmp/montana-openssl with "built on" the epoch. A build of yours from these revisions has the
same SHA-256, and compare-archives.py ends with SAME BYTES. One build at a time: the OpenSSL folder is shared.

## License

MIT or Apache-2.0, at your option: LICENSE-MIT, LICENSE-APACHE.
