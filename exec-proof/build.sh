#!/usr/bin/env bash
# Build the exec-model proof APK for both ABIs, then install and read the results.
#
#   ./build.sh <NDK path>            # e.g. ./build.sh ~/Android/Sdk/ndk/28.2.13676358
#
# The point of this project: prove that a binary shipped as jniLibs/lib*.so and
# extracted to nativeLibraryDir can be execve'd, that the same binary in filesDir
# cannot, and that LD_LIBRARY_PATH is required for DT_NEEDED resolution.
set -euo pipefail

NDK="${1:?usage: $0 <ndk-path>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
JNI="$HERE/app/src/main/jniLibs"

# Locate the host toolchain dir (linux-x86_64, darwin-x86_64, windows-x86_64).
TC="$(echo "$NDK"/toolchains/llvm/prebuilt/*)"
echo "toolchain: $TC"

for pair in "x86_64:x86_64-linux-android26" "arm64-v8a:aarch64-linux-android26"; do
  dir="${pair%%:*}"
  trip="${pair##*:}"
  echo "building probe for $dir ($trip)"
  mkdir -p "$JNI/$dir"
  "$TC/bin/${trip}-clang++" -O2 "$HERE/probe_src/probe.cpp" -o "$JNI/$dir/libprobe.so"
  # ship the C++ runtime too, so DT_NEEDED actually resolves
  cp "$TC/sysroot/usr/lib/$trip/libc++_shared.so" "$JNI/$dir/" 2>/dev/null || true
done

echo "building APK"
cd "$HERE"
if [ -x ./gradlew ]; then ./gradlew assembleDebug; else gradle assembleDebug; fi

cat <<'EOF'

Now run:
  adb install -r app/build/outputs/apk/debug/app-debug.apk
  adb shell am start -n io.test.wx/.MainActivity
  adb logcat -d -s WXTEST:*
EOF
