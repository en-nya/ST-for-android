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
# PATCH 0 — use Node's OWN bundled Android patch for the V8 trap handler.
#
# Failure without it (host tool link, after ~3h of compiling):
#   /usr/bin/ld: obj.host/.../simulator-arm64.o: undefined reference to
#       `v8_internal_simulator_ProbeMemory'
#   /usr/bin/ld: handler-outside.o: undefined reference to
#       `v8::internal::trap_handler::RegisterDefaultTrapHandler()'
#   collect2: error: ld returned 1 exit status
#
# Why: trap-handler.h enables V8_TRAP_HANDLER_VIA_SIMULATOR when
# (V8_TARGET_ARCH_ARM64 && V8_HOST_ARCH_X64 && V8_OS_LINUX). In a cross build the
# HOST tools (mksnapshot) are built with OS=linux but inherit v8_target_arch=arm64,
# so they take the simulator code path, whose asm/definitions do not link for the
# host toolset.
#
# Node ships the fix itself: android_configure.py has a `patch` subcommand that
# rewrites trap-handler.h to `V8_TRAP_HANDLER_SUPPORTED false` on Android.
# We invoke it exactly as upstream documents (2-arg form).
# ---------------------------------------------------------------------------
echo "-- patch 0: disable V8 trap handler on Android (upstream node#36287 fix)"
# Node ships android-patches/trap-handler.h.patch, and android_configure.py's
# `patch` subcommand applies it via the external `patch` binary. That binary is
# not guaranteed to exist on a minimal runner image, and the patch's own
# pre-image text has drifted across Node versions (our v24.22.2 tree differs from
# what the .patch file expects), so `patch -f` can silently no-op.
#
# Instead we perform the exact same transformation the patch describes: replace
# the whole supported/unsupported #if/#elif/#else/#endif chain with a single
# `#define V8_TRAP_HANDLER_SUPPORTED false`. We do it with a small Python script
# that works on any Node version by locating the chain by its anchors.
python3 - <<'PY'
import re, sys, pathlib

p = pathlib.Path("deps/v8/src/trap-handler/trap-handler.h")
src = p.read_text(encoding="utf-8")

start_anchor = "// X64 on Linux, Windows, MacOS, FreeBSD."
end_anchor = "#endif\n"

i = src.find(start_anchor)
if i == -1:
    # Already patched, or anchors changed.
    if "V8_TRAP_HANDLER_SUPPORTED false" in src:
        print("   already patched (SUPPORTED false present)")
        sys.exit(0)
    print("FATAL: cannot find trap-handler chain start anchor")
    sys.exit(1)

# Find the matching #endif that closes the chain: scan forward counting nesting.
j = src.find("\n#if", i)
if j == -1:
    print("FATAL: cannot find '#if' after anchor")
    sys.exit(1)
depth = 0
k = j
lines = src[j:].splitlines(keepends=True)
pos = j
closed_at = None
for ln in lines:
    stripped = ln.strip()
    if stripped.startswith(("#if", "#ifdef", "#ifndef")):
        depth += 1
    elif stripped.startswith("#endif"):
        depth -= 1
        if depth == 0:
            closed_at = pos + len(ln)
            break
    pos += len(ln)

if closed_at is None:
    print("FATAL: unbalanced preprocessor chain in trap-handler.h")
    sys.exit(1)

replacement = "#define V8_TRAP_HANDLER_SUPPORTED false\n"
out = src[:i] + replacement + src[closed_at:]
p.write_text(out, encoding="utf-8")

if "V8_TRAP_HANDLER_VIA_SIMULATOR" in out:
    print("FATAL: simulator path still referenced after patch")
    sys.exit(1)
print("   trap handler force-disabled (V8_TRAP_HANDLER_SUPPORTED false)")
PY

if grep -q "V8_TRAP_HANDLER_VIA_SIMULATOR" deps/v8/src/trap-handler/trap-handler.h; then
  echo "FATAL: trap-handler.h still enables the simulator path"; exit 1
fi
echo "   ok"

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
  sed -i "s/'ARMV8_OS_ANDROID'/'ARMV8_OS_LINUX'/g" deps/zlib/zlib.gyp
  if grep -q "ARMV8_OS_ANDROID" deps/zlib/zlib.gyp; then
    echo "FATAL: ARMV8_OS_ANDROID still present in zlib.gyp"; exit 1
  fi
  echo "   android define now ARMV8_OS_LINUX (getauxval path)"
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
if grep -q "V8_TRAP_HANDLER_VIA_SIMULATOR" deps/v8/src/trap-handler/trap-handler.h; then
  echo "FATAL: trap-handler.h would still select the simulator path"; exit 1
fi
echo "   trap-handler.h will not select the simulator path"

echo "== patches applied =="
