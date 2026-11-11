#!/bin/bash
# WebRTC.xcframework (stage 13, native calls) -- a ~63 MB binary, not in git.
# Build webrtc-sdk 144.7559.10: it contains RTCFrameCryptor (SFrame AES-GCM) -- the post-quantum
# media layer of a call over DTLS-SRTP with the sframe_key (mt_e2e_call_key). The M149 build lacked it.
# The one binary input of the build that is not compiled here: it is taken only with the SHA-256 below (Constitution [I-14] --
# a reproducible build names every byte it did not compile; measured 21.10.2026 against the framework release 2274 carries).
# Usage: fetch-webrtc.sh [DEST] -- by default into Code/Frameworks, where the phone links it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HERE/Code/Frameworks/WebRTC.xcframework}"
[ -d "$DEST" ] && { echo "WebRTC.xcframework is already in place"; exit 0; }
python3 - "$DEST" <<'PY'
import hashlib, os, shutil, subprocess, sys, tempfile, urllib.request
URL = 'https://github.com/webrtc-sdk/Specs/releases/download/144.7559.10/WebRTC.xcframework.zip'
SHA256 = '64e9150f5ad467a11f5adfdf41c251d74278060368777727a981a3320df1d5ff'
dest = sys.argv[1]
with tempfile.TemporaryDirectory(prefix='webrtc-') as work:
    archive = os.path.join(work, 'webrtc.zip')
    urllib.request.urlretrieve(URL, archive)
    got = hashlib.sha256(open(archive, 'rb').read()).hexdigest()
    if got != SHA256:
        sys.exit('REFUSED: WebRTC.xcframework.zip has SHA-256 ' + got + ', not ' + SHA256)
    # ditto keeps the framework's symlinks (Versions/Current), which zipfile would flatten into copies
    subprocess.run(['ditto', '-x', '-k', archive, work], check=True)
    shutil.copytree(os.path.join(work, 'WebRTC.xcframework'), dest, symlinks=True)
print('WebRTC.xcframework (webrtc-sdk 144.7559.10, RTCFrameCryptor, sha256 ' + SHA256[:16] + ') installed into ' + dest)
PY
