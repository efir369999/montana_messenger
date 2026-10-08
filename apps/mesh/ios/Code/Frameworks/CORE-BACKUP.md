# Code/Frameworks

The frameworks this application links are built locally and never committed:

- `MontanaBindings.xcframework`, the client core: `scripts/build-core.sh` with `MONTANA_CORE_SRC` set to
  `core/Code/crates/mt-bindings` of this repository;
- `MontanaCore.xcframework`, the reference implementation: `scripts/build-protocol-core.sh` with `MONTANA_PROTOCOL_CORE`
  set to `core/Montana-Core`;
- `WebRTC.xcframework`, the call engine: `fetch-webrtc.sh`, which pins the release by digest.
