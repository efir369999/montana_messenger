#!/bin/bash
# WebRTC.xcframework (stage 13, native calls) -- a ~63 MB binary, not in git.
# Build webrtc-sdk 144.7559.10: it contains RTCFrameCryptor (SFrame AES-GCM) -- the post-quantum
# media layer of a call over DTLS-SRTP with the sframe_key (mt_e2e_call_key). The M149 build lacked it.
set -e
cd "$(dirname "$0")"
DEST="Code/Frameworks/WebRTC.xcframework"
[ -d "$DEST" ] && { echo "WebRTC.xcframework is already in place"; exit 0; }
curl -sL -o /tmp/webrtc.zip "https://github.com/webrtc-sdk/Specs/releases/download/144.7559.10/WebRTC.xcframework.zip"
unzip -q -o /tmp/webrtc.zip -d /tmp/webrtc_extract
SRC=$(find /tmp/webrtc_extract -maxdepth 2 -name "WebRTC.xcframework" -type d | head -1)
cp -R "$SRC" "$DEST"
echo "WebRTC.xcframework (webrtc-sdk 144.7559.10, RTCFrameCryptor) installed into Code/Frameworks/"
