# ST for Android — build inputs

This repository carries the **design documents** and the **CI job** that produces the
one artifact the project cannot build on Windows: a stock Node.js LTS cross-compiled
as an **Android arm64 executable**.

## Why this repo exists

ndroid_configure.py refuses to run anywhere but Linux/Darwin, and this workstation
has no WSL and no admin rights. So the Node build runs on GitHub Actions and the
resulting binary is consumed by the Android app build.

## Contents

| Path | What |
|---|---|
| `docs/00-draft-plan.md` | initial draft (kept for history) |
| `docs/01-plan.md` | the porting plan (19 locked decisions) |
| `docs/02-sds.md` | the software design spec (15 sections, 4 adversarial review rounds) |
| `.github/workflows/build-android-node.yml` | builds Node LTS as an Android executable |
| `patches/` | the P1 SillyTavern patches (boot-time webpack removal) |
| `tools/verify-gates.js` | self-test for the ELF gates the workflow enforces |
| `tools/inspect-node.js` | checks the Node source for the build assumptions |

## The three hard gates (a build that fails these is useless)

1. **Must be an executable.** `e_entry != 0`. A `.so` (`ET_DYN` with `e_entry=0`)
   cannot be `execve`'d from an APK. This is exactly how the off-the-shelf
   `nodejs-mobile` / fogtape artifacts fail.
2. **16 KB page alignment** on every `PT_LOAD` (`p_align=0x4000` and
   `(vaddr-offset) % 0x4000 == 0`). Required by Play and by Android 15+ 16 KB devices.
   Newer NDK defaults do this; `-Wl,-z,max-page-size` alone is not the mechanism.
3. **full ICU.** `src/users.js:645` calls `String.prototype.normalize()` on the
   login path. An `--with-intl=none` build starts fine and then cannot log in.

## Run it

Actions -> `build-android-node` -> *Run workflow*. Artifact:
`node-android-arm64` containing `libnode-arm64` (the executable, rename to
`libnode.so` when packaging into `jniLibs`) and its `SHA256SUMS`.

Verify the gates locally at any time:

```
node tools/verify-gates.js
```

## Known-correct build facts (verified against node v24.22.2 source)

- `--shared` default is `None` -> default output is an executable. Do not pass `--shared`.
- `--with-intl` default is `full-icu`.
- `configure.py` has **no** `--ldflags` option and never reads ``.
- `android_configure.py` takes **exactly 3** positional args (`<ndk> <api> <arch>`)
  and does **not** read `ANDROID_NDK_HOME` / `ANDROID_API`.
- `android_configure.py` never sets `CC_host`, but `configure.py` reads it to detect
  the *host* arch; `node_js2c` is built with `toolsets: ['host']`. Without
  `CC_host`/`CXX_host` the host tools become ARM binaries and the build dies.
