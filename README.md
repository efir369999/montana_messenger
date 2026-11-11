# Montana Messenger

Elegance. Aesthetics. Safety.

A simple, fast messenger for every day: chats, voice and video calls, groups and channels, on iPhone and iPad.

The app's page, its privacy policy, terms and support: https://montana.one

This repository is the source of the iOS app as it is built for the App Store: the app, the client core it links and the part
of the Montana protocol core it links, and nothing else. Staged from app a9adf31100ffc6ec4908b2fdbb4dcf27ce378df3, client core a427e913d4ecfa6d34d1f923fd6ec783bcca17af, protocol core 2f5a1a220d8668104b53eb6b71f0b4a70a3319a8.

## Layout

- ios/ -- the app: the targets MontanaMessenger (the app), MontanaMessengerNSE (notification service),
  MontanaMessengerShare (share extension) and MontanaMessengerBroadcast (screen broadcast), in
  ios/MontanaMessenger.xcodeproj, which holds these four targets alone.
- core/Code/ -- the Rust crates of the client core, built into MontanaBindings.xcframework. This snapshot is staged
  without the core's coin feature: the code only that feature compiles is not here.
- core/Montana-Core/ -- the Rust crates of the Montana protocol core the app links as libmt_boundary.a
  (MontanaCore.xcframework): the app's own node on the Montana network.
- core/Montana wordlist.txt -- the canonical mnemonic wordlist core/Code/crates/mt-mnemonic compiles in.

## Building

You need macOS with Xcode, rustup and python3. The frameworks the app links are built locally into ios/Code/Frameworks
and are never committed. Build from a git clone (the protocol core script records the commit it was built from), from
the repository root:

```sh
rustup toolchain install 1.92.0
rustup target add aarch64-apple-ios --toolchain 1.92.0
mkdir -p ios/Code/Frameworks
MT_EDITION=messenger bash core/Code/crates/mt-bindings/build-ios-xcframework.sh "$PWD/ios/Code/Frameworks/MontanaBindings.xcframework"
MONTANA_PROTOCOL_CORE="$PWD/core/Montana-Core" bash ios/scripts/build-protocol-core.sh
bash ios/fetch-webrtc.sh
open ios/MontanaMessenger.xcodeproj
```

fetch-webrtc.sh takes WebRTC.xcframework (webrtc-sdk 144.7559.10) only with the SHA-256 it pins. The frameworks are built
for devices only (arm64): run the scheme MontanaMessenger on an iPhone, with your own team under Signing.

## License

MIT or Apache-2.0, at your option: LICENSE-MIT, LICENSE-APACHE.
