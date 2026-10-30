#!/usr/bin/env bash
# Checks a built APK with the pinned toolchain: the signature, the package and its processors, the page alignment of
# the native libraries (in the package and in the ELF), and the JNI functions libmontana.so exports.
#   tools/verify-apk.sh out/Montana-<commit>-<abis>.apk
set -euo pipefail
apk="$(readlink -f "$1")"
SDK=/opt/montana-tools/android-sdk
BT="$SDK/build-tools/35.0.0"
LLVM="$SDK/ndk/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/bin"
export JAVA_HOME=/opt/montana-tools/jdk-17
export PATH="$JAVA_HOME/bin:$PATH"

echo "== $(basename "$apk")"
sha256sum "$apk" | cut -c1-64
echo "--- signature"
"$BT/apksigner" verify --print-certs -v "$apk" \
  | grep -E '^(Verifies|Verified using v[0-9]|Number of signers|Signer #1 certificate (DN|SHA-256))' || true
echo "--- package"
"$BT/aapt2" dump badging "$apk" \
  | grep -E "^(package|minSdkVersion|sdkVersion|targetSdkVersion|native-code|application-label:|launchable-activity)" || true
echo "--- zip alignment (16 KiB pages for the libraries)"
"$BT/zipalign" -c -P 16 4 "$apk" && echo "zipalign -c -P 16 4: OK"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$apk" 'lib/*' -d "$tmp"
echo "--- native libraries (ELF LOAD alignment: 0x4000 = 16 KiB, 0x1000 = 4 KiB)"
for so in "$tmp"/lib/*/*.so; do
  abi="$(basename "$(dirname "$so")")"
  align="$("$LLVM/llvm-readelf" -lW "$so" | awk '$1 == "LOAD" { print $NF }' | sort -u | paste -sd, -)"
  printf '%-12s %-36s %10d bytes  LOAD align %s\n' "$abi" "$(basename "$so")" "$(stat -c %s "$so")" "$align"
done
for so in "$tmp"/lib/*/libmontana.so; do
  abi="$(basename "$(dirname "$so")")"
  n="$("$LLVM/llvm-nm" -D --defined-only "$so" | grep -c ' T Java_quest_montana_app_MtBindings_' || true)"
  echo "$abi libmontana.so: $n JNI functions Java_quest_montana_app_MtBindings_*"
done
