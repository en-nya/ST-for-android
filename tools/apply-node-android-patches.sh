#!/usr/bin/env bash
# Apply the minimal set of patches needed to cross-compile stock Node.js for
# Android/arm64 on a Linux host.
#
# Context (docs/02-sds.md §2.1): Node's Android build is not officially supported,
# but it is close. Each patch below fixes one concrete, reproducible failure.
#
# Usage: ./apply-node-android-patches.sh <node-source-dir>
set -euo pipefail

SRC="${1:?usage: $0 <node-source-dir>}"
cd "$SRC"

echo "== Node Android patches =="
echo "source: $SRC"

# ---------------------------------------------------------------------------
# PATCH 1 — zlib: use getauxval() instead of Android cpufeatures
#
# Failure without it:
#   ld.lld: error: undefined symbol: android_getCpuFeatures
#   >>> referenced by cpu_features.c
#   deps/zlib/cpu_features.o:(_cpu_check_features) in archive libzlib.a
#
# Why: deps/zlib/zlib.gyp defines ARMV8_OS_ANDROID on Android, which makes
# cpu_features.c call android_getCpuFeatures() from the NDK cpufeatures library.
# Node's gyp files do not link that library, so the link step of openssl-cli (and
# later node itself) fails.
#
# Fix: define ARMV8_OS_LINUX instead. On bionic, getauxval(AT_HWCAP) is in libc
# and returns the same CRC32/PMULL capability bits, so feature detection is
# unchanged in effect while needing no extra library.
#
# This mirrors the approach used by the community patches
# (e.g. "deps-zlib-cpu-features-android-getauxval").
# ---------------------------------------------------------------------------
echo "-- patch 1: zlib ARMV8_OS_ANDROID -> ARMV8_OS_LINUX"
if grep -q "ARMV8_OS_ANDROID" deps/zlib/zlib.gyp; then
  # Replace ONLY the Android condition's define, leaving the existing linux /
  # openharmony condition (which already defines ARMV8_OS_LINUX) untouched.
  # Both blocks look like:
  #     ['OS=="android"', {
  #       'defines': [ 'ARMV8_OS_ANDROID' ],
  #     }],
  # and we want the android arm to define ARMV8_OS_LINUX instead.
  #
  # Doing a blind s/// on 'ARMV8_OS_ANDROID' would work but leaves two different
  # gyp conditions both defining ARMV8_OS_LINUX; that is harmless for the C
  # preprocessor but makes the tree confusing to audit. Target the value only.
  sed -i "s/'ARMV8_OS_ANDROID'/'ARMV8_OS_LINUX'/g" deps/zlib/zlib.gyp
  if grep -q "ARMV8_OS_ANDROID" deps/zlib/zlib.gyp; then
    echo "FATAL: ARMV8_OS_ANDROID still present in zlib.gyp"; exit 1
  fi
  echo "   android define now ARMV8_OS_LINUX (getauxval path)"
  grep -n "ARMV8_OS_LINUX" deps/zlib/zlib.gyp | head -8
  echo "   ok"
else
  echo "   already patched or not applicable (no ARMV8_OS_ANDROID)"
fi

# ---------------------------------------------------------------------------
# Verification — fail loudly if the gyp inputs are still in a state that
# cannot link. Only the gyp files matter here: deps/zlib/*.c and BUILD.gn also
# mention ARMV8_OS_ANDROID, but they are either guarded by `#if defined(...)`
# (harmless once the define is gone) or not used by the gyp build at all.
# ---------------------------------------------------------------------------
echo "-- verify"
if grep -n "ARMV8_OS_ANDROID" deps/zlib/zlib.gyp 2>/dev/null; then
  echo "FATAL: zlib.gyp still defines ARMV8_OS_ANDROID"; exit 1
fi
echo "   zlib.gyp no longer defines ARMV8_OS_ANDROID (getauxval path is selected)"
if grep -q "ARMV8_OS_LINUX" deps/zlib/zlib.gyp; then
  echo "   ARMV8_OS_LINUX present -> getauxval branch will compile"
else
  echo "FATAL: neither define present in zlib.gyp; unexpected tree state"; exit 1
fi

echo "== patches applied =="
