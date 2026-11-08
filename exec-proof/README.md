# exec-proof

Minimal APK that answers one question with evidence: **can an Android app
`execve()` a binary that shipped as `jniLibs/lib*.so`?**

Four experiments, logged to tag `WXTEST`:

| test | what | expected |
|---|---|---|
| T1 | exec `nativeLibraryDir/libprobe.so` with `LD_LIBRARY_PATH` | works |
| T2 | exec a copy in `filesDir` (app-writable) | **BLOCKED, errno 13 (SELinux)** |
| T3 | same as T1 but without `LD_LIBRARY_PATH` | **fails: library not found** |
| T4 | `canExecute()` | true |

T1 alone proves little; **T1 vs T2** is what proves the W^X rule is real and that
`nativeLibraryDir` is the only *supported* location. **T3** proves
`LD_LIBRARY_PATH` is mandatory for `DT_NEEDED` resolution (bionic does not search
the executable's own directory).

## Reproduce

Requires: Android SDK (platform 34+, build-tools, **cmake not needed**), NDK r26+,
JDK 17, Gradle 8.8+, and a **running device/emulator**.

```bash
# 1. build the probe executables into app/src/main/jniLibs/<abi>/libprobe.so
python3 build.py --ndk /path/to/ndk        # or set ANDROID_NDK_HOME

# 2. package (useLegacyPackaging=true is what makes the .so get extracted)
gradle assembleDebug                       # or ./gradlew assembleDebug

# 3. install + observe
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n io.test.wx/.MainActivity
adb logcat -d -s WXTEST:*
```

`build.py` handles both ABIs and also copies the matching `libc++_shared.so`
next to each probe, so T3 has a real `DT_NEEDED` entry to fail on.

### Traps this project documents so you don't hit them

- **Do not override the entry point.** `-Wl,-e,main` bypasses libc's `_start`
  and segfaults at *any* size. Let `-fPIE -pie` do its job.
- **`add_executable` + `OUTPUT_NAME` under AGP is a trap.** The default output is
  `libprobe` with **no `.so`**, and AGP silently ignores it — the library never
  reaches the APK. The direct `clang++ -o .../libprobe.so` path in `build.py`
  avoids the whole issue.
- **`useLegacyPackaging = true` is load-bearing.** With the AGP default the
  native-library dir is created but **empty**, and T1 fails with `error=2`.

## Verified result

Android 14 / API 34 / x86_64 emulator, `PAGE_SIZE=4096`, Google userdebug image:

```
nativeLibraryDir = /data/app/~~.../io.test.wx-.../lib/x86_64
T1 exec from nativeLibraryDir -> exit=0 out=[PROBE_OK argc=3 cxx=3]
T2 exec from filesDir -> BLOCKED: IOException: ... error=13, Permission denied
T3 exec WITHOUT LD_LIBRARY_PATH -> exit=1 out=[CANNOT LINK EXECUTABLE ".../libprobe.so":
     library "libc++_shared.so" not found: needed by main executable]
T4 canExecute() before fix = true
```

T2's denial is SELinux, proven from the kernel's own log:
`avc: denied { execute_no_trans } ... scontext=u:r:untrusted_app
tcontext=u:object_r:app_data_file:s0`. The file was mode 0711 (x-bit set) and
still denied — `setExecutable()` cannot fix it.

## What this does NOT prove

- **The arm64 Node binary has never executed anywhere.** This project produced
  no arm64 exec data; it validates the exec *mechanism* on x86_64.
- **16 KB pages** — the host emulator is 4 KB.
- **A ~90 MB payload** — the probe is 5.5 KB.
- **A long-running process** — the probe is `printf` + `exit`, microseconds.
  V8 init, JIT, threads, signals, and LMK reaping are all untested.
- **Shipping `user` builds** — this ran on `ro.debuggable=1`.
- **OEM ROMs** — no MIUI/ColorOS/etc. data.

Those all remain open in `docs/02-sds.md` §11.3.
