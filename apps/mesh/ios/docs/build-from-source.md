# Build from source (auditor guide)

## Toolchain
- macOS 15.7+ (built/verified on 15.7.3)
- Xcode 26.2
- Rust (rustup) 1.92.0 with iOS targets:
  `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
  Use `~/.cargo/bin/cargo` (rustup), not Homebrew cargo (lacks iOS targets).

## Rebuild the crypto FFI (mt-bindings → XCFramework)
The protocol crypto is provided by `mt-bindings` from the Montana protocol
`Code` workspace and vendored as `MontanaBindings.xcframework` (device + sim
slices, with `include/module.modulemap`). Rebuild:
```
cd <protocol>/Code
~/.cargo/bin/cargo build --release -p mt-bindings \
  --target aarch64-apple-ios --target aarch64-apple-ios-sim
# repackage slices into MontanaBindings.xcframework (see scripts/)
```

## Build and test the app
```
xcodebuild build -project Montana.xcodeproj -scheme Montana \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project Montana.xcodeproj -scheme Montana \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MontanaTests
```
The conformance suite (`MontanaTests`) runs the KATs in `AUDIT.md §4` and must
report `** TEST SUCCEEDED **`.
