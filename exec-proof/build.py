#!/usr/bin/env python3
"""
Build the exec-proof probe binaries and drop them into app/src/main/jniLibs/,
then let Gradle package the APK.

Why not CMake/AGP externalNativeBuild:
  Getting AGP to package a CMake-built *executable* as lib*.so is fiddly -- the
  default OUTPUT_NAME produces `libprobe` (no `.so`), AGP ignores it, and the
  library silently never reaches the APK. The direct clang++ -> jniLibs path is
  explicit, debuggable, and is what was actually verified on device.

Requirements: Android NDK (r26+), ANDROID_NDK_HOME or --ndk.

Usage:
    python build.py --ndk /path/to/ndk
    python build.py --ndk C:\\Android\\Sdk\\ndk\\28.2.13676358

Then:
    gradle assembleDebug          (or ./gradlew assembleDebug)
    adb install -r app/build/outputs/apk/debug/app-debug.apk
    adb shell am start -n io.test.wx/.MainActivity
    adb logcat -d -s WXTEST:*
"""
import argparse
import os
import platform
import shutil
import subprocess
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
PROBE_SRC = HERE / "probe_src" / "probe.cpp"
JNI = HERE / "app" / "src" / "main" / "jniLibs"

# (jniLibs dir, clang target triple)
TARGETS = [
    ("x86_64", "x86_64-linux-android26"),
    ("arm64-v8a", "aarch64-linux-android26"),
]


def toolchain_dir(ndk: pathlib.Path) -> pathlib.Path:
    prebuilt = ndk / "toolchains" / "llvm" / "prebuilt"
    if not prebuilt.is_dir():
        sys.exit(f"FATAL: {prebuilt} not found -- is this really an NDK?")
    # linux-x86_64 / darwin-x86_64 / windows-x86_64
    dirs = list(prebuilt.iterdir())
    if not dirs:
        sys.exit(f"FATAL: no toolchains under {prebuilt}")
    return dirs[0]


def exe(name: str) -> str:
    return name + (".cmd" if platform.system() == "Windows" else "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ndk", default=os.environ.get("ANDROID_NDK_HOME"),
                    help="path to NDK (or set ANDROID_NDK_HOME)")
    ap.add_argument("--api", default="26", help="ANDROID_API level (default 26)")
    args = ap.parse_args()
    if not args.ndk:
        sys.exit("FATAL: pass --ndk or set ANDROID_NDK_HOME")

    ndk = pathlib.Path(args.ndk)
    tc = toolchain_dir(ndk)
    print(f"ndk      : {ndk}")
    print(f"toolchain: {tc}")

    if not PROBE_SRC.is_file():
        sys.exit(f"FATAL: missing {PROBE_SRC}")

    for jni_dir, triple_tpl in TARGETS:
        triple = triple_tpl.replace("26", args.api)
        out_dir = JNI / jni_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        so = out_dir / "libprobe.so"

        clang = tc / "bin" / exe(f"{triple}-clang++")
        if not clang.is_file():
            print(f"WARN: {clang} missing, skipping {jni_dir}")
            continue

        cmd = [
            str(clang),
            "-O2",
            # normal PIE executable; DO NOT override the entry point
            "-fPIE", "-pie",
            str(PROBE_SRC),
            "-o", str(so),
            # dynamic libc++ -> DT_NEEDED: libc++_shared.so (needed for the T3 test)
            "-stdlib=libc++",
        ]
        print(f"building {jni_dir}: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)

        # Ship the matching C++ runtime next to it. The sysroot dir is named by
        # the *arch* triple (no API suffix), e.g. x86_64-linux-android.
        arch_triple = triple.replace("-android" + args.api, "-android")
        for cand in [
            tc / "sysroot" / "usr" / "lib" / arch_triple / "libc++_shared.so",
            tc / "sysroot" / "usr" / "lib" / triple / "libc++_shared.so",
        ]:
            if cand.is_file():
                shutil.copy2(cand, out_dir / "libc++_shared.so")
                print(f"  libc++_shared.so <- {cand}")
                break
        else:
            print(f"WARN: libc++_shared.so not found for {jni_dir} (looked in {arch_triple})")

        size = so.stat().st_size
        print(f"  -> {so} ({size} bytes)")

    print("\ndone. Next: gradle assembleDebug")
    return 0


if __name__ == "__main__":
    sys.exit(main())
