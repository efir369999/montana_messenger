#!/usr/bin/env bash
# Build mt-bindings for all 3 Android ABIs and stage into the Android app's jniLibs.
# Usage: bash crates/mt-bindings/build-android.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$HERE/../../.."

: "${ANDROID_NDK_HOME:=/opt/homebrew/share/android-commandlinetools/ndk/26.3.11579264}"
export ANDROID_NDK_HOME

source "$HOME/.cargo/env" 2>/dev/null || true

JNI="$WORKSPACE/../../Android/MontanaApp/app/src/main/jniLibs"
mkdir -p "$JNI/arm64-v8a" "$JNI/armeabi-v7a" "$JNI/x86_64"

cd "$WORKSPACE"

cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 build -p mt-bindings --release

cp "$WORKSPACE/target/aarch64-linux-android/release/libmt_bindings.so"      "$JNI/arm64-v8a/"
cp "$WORKSPACE/target/armv7-linux-androideabi/release/libmt_bindings.so"   "$JNI/armeabi-v7a/"
cp "$WORKSPACE/target/x86_64-linux-android/release/libmt_bindings.so"      "$JNI/x86_64/"

echo "staged:"
ls -lh "$JNI"/*/libmt_bindings.so
