# exec-proof

Minimal APK that answers one question with evidence: **can an Android app
`execve()` a binary that shipped as `jniLibs/lib*.so`?**

Four experiments, logged to tag `WXTEST`:

| test | what | expected |
|---|---|---|
| T1 | exec `nativeLibraryDir/libprobe.so` with `LD_LIBRARY_PATH` | works |
| T2 | exec a copy in `filesDir` (app-writable) | **BLOCKED, errno 13** |
| T3 | same as T1 but without `LD_LIBRARY_PATH` | **fails: library not found** |
| T4 | `canExecute()` | true |

T1 alone proves little; **T1 vs T2** is what proves the W^X rule is real and that
`nativeLibraryDir` is the *only* option. **T3** proves `LD_LIBRARY_PATH` is
mandatory for `DT_NEEDED` resolution.

## Build and run

```
./build.sh ~/Android/Sdk/ndk/28.2.13676358
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n io.test.wx/.MainActivity
adb logcat -d -s WXTEST:*
```

Requires: Android SDK (platform 34+, build-tools), NDK r26+, JDK 17, Gradle 8.8+.

## Verified result (Android 14 / API 34 / x86_64 emulator, 4 KB pages)

```
T1 exec from nativeLibraryDir -> exit=0 out=[PROBE_OK argc=3 cxx=3]
T2 exec from filesDir -> BLOCKED: IOException: Cannot run program
     ".../files/probe_copy": error=13, Permission denied
T3 exec WITHOUT LD_LIBRARY_PATH -> exit=1 out=[CANNOT LINK EXECUTABLE
     ".../lib/x86_64/libprobe.so": library "libc++_shared.so" not found:
     needed by main executable]
T4 canExecute() before fix = true
```

## What this does NOT prove

- That the **arm64 Node binary** runs — this only tests the exec *mechanism*.
- That **16 KB-page** devices behave the same (test host emulator is 4 KB).
- That a **long-running** process (Node) behaves like a printf-and-exit probe.
- That **OEM ROMs** add no further restrictions.

Those remain open in the SDS (§11.3).
