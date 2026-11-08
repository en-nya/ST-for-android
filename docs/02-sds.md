# SillyTavern Android 移植 — 软件设计规格书（SDS）v1.5

> 状态：**已过四轮独立对抗式审核。全部 BLOCKER / MAJOR 已关闭**（最终判定："可实施，仅余次要编辑"，且那几条已全部落地）。
> 上游文档：`docs/01-plan.md`（计划 v1.1，已过两轮审核）。
> **标 ⚠ 的地方是尚未被真实验证的前提**，必须在对应里程碑关闭，不得当作已知。
> **本 SDS 的设计原则：凡是"看起来对"的方案，必须跑过或读到源码行才写进来。** 四轮审核共推翻我 **16** 个"看起来对"的设计（见 §14），这条原则不是修辞。
> **§11.0 是硬性流程规则**：任何 ✅ 必须附可复现命令与输出；任何未运行的代码片段必须标注 `⚠ PSEUDOCODE`。
> **可审计性**：§0.3 有 **D1–D19 全量映射表**，每条决策都能在本文档里定位到落点；12 个功能补丁 + 4 个持久性补丁（D-P1~D-P4）均有验收标准。

---

## 0. 范围与依据

### 0.1 本文档回答什么
计划文档回答「做什么、为什么」；本 SDS 回答「**具体怎么实现、接口长什么样、怎么算通过**」。

### 0.2 目标（复述，不可协商）
| ID | 目标 |
|---|---|
| G1 | 打开即用：安装后无需 Termux/root/命令行，不联网下载运行时 |
| G2 | 崩溃 / 划掉 / 断电 / 存储写满：**已确认的聊天不丢不坏** |
| G3 | 与桌面 web 版**行为一致**；差异仅限平台适配层 |
| G4 | 补丁集可审计、可 rebase 上游 |
| G5 | 可交付 APK + 源码 + 可复现构建，合规 AGPL-3.0 |

### 0.3 决策基线（D1–D19 见计划 §0；本 SDS 只列影响设计的）

> **完整映射表**（保证计划的 19 条决策在 SDS 里都有落点，可逐条审计）：

| 决策 | 内容 | SDS 落点 |
|---|---|---|
| D1 | 从 0 自建 | §8 全章（构建/升级/端口） |
| D2 | stock Node 编成**可执行文件**，非 `.so` | §2.1、§2.2 |
| D3 | Node 24 LTS + **full ICU** | §2.1、§2.2 门禁③④ |
| D4 | GitHub Actions 构建 | §2.1 |
| D5 | 起跑用**真实可执行文件**（非 fogtape `.so`） | §2.1、§14 #1 |
| D6 | minSdk 26 / targetSdk 36 | §2.3（`extractNativeLibs`/`useLegacyPackaging`） |
| D7 | 发布仅 arm64-v8a | §7 体积预算 |
| D8 | 数据在应用内部私有目录 | §1.2 目录布局、§3.1 |
| D9 | 保活：`specialUse` 前台服务 | §4.2 |
| D10 | 扩展：安装+启用+加载+重载 全通 | §7.1–7.4 |
| D11 | **保留完整 ML 栈** | **§7.5（含技术前提与验收）** |
| D12 | APK 内压缩打包，首启解压 | §5.1、§8.1 |
| D13 | 冷启动三段口径 | §5.3、§10 |
| D14 | 生成草稿落盘 + 恢复 | §3.6b |
| D15 | kill -9 门禁 | §11.1 |
| D16 | 吃 ST 原生备份 / 原始目录导入 | §8.3 |
| D17 | 滚动日志 + 脱敏导出 | §9.1 |
| D18 | 上游源码完整保留 + 构建期补丁集 | §6.1–6.2 |
| D19 | 自签分发、不上 Play | §4.2（`specialUse` 审核影响为零）、§13
- **D1** 从 0 自建（不 fork 现有实现，但可借鉴）
- **D2** stock Node 交叉编译为**可执行文件**（不传 `--shared`），重命名 `lib*.so` 放 `jniLibs`
- **D3** Node 24 LTS + **full ICU**
- **D6** minSdk 26 / targetSdk 36
- **D7** 发布仅 arm64-v8a
- **D8** 数据在应用**内部私有目录**
- **D9** 保活：`specialUse` 前台服务
- **D10** 扩展：安装+启用+动态加载+重载生效 全通算兼容
- **D16** 导入吃 ST 原生备份 zip / 原始 `config.yaml`+`data`
- **D19** 自签 APK + GitHub Release，不上 Play

---

## 1. 系统架构

### 1.1 进程与线程拓扑

```
┌───────────────────────────────────────────────────────────────────┐
│ APP 主进程 (com.example.st / :main)                               │
│                                                                   │
│  ┌─ MainActivity (Compose) ───────────────────────────────────┐   │
│  │  ComposeHost: 启动骨架 / 进度 / 错误页 / 主 WebView         │   │
│  └────────────────────────────────────────────────────────────┘   │
│  ┌─ ServerController (单例, 有状态机) ────────────────────────┐   │
│  │  状态: IDLE→EXTRACTING→STARTING→READY / FAILED / STOPPED   │   │
│  │  职责: 备货、端口分配、ProcessBuilder、探活、退避重启、     │   │
│  │        日志脱敏、崩溃上报                                    │   │
│  └────────────────────────────────────────────────────────────┘   │
│  ┌─ StForegroundService (specialUse) ────────────────────────┐   │
│  │  常驻通知 + Stop action；进程看护；onTaskRemoved 时 flush   │   │
│  └────────────────────────────────────────────────────────────┘   │
│  ┌─ DataStore / Snapshots / Drafts / Logs ───────────────────┐   │
│  └────────────────────────────────────────────────────────────┘   │
└────────────────────────┬──────────────────────────────────────────┘
                         │ ProcessBuilder
┌────────────────────────▼──────────────────────────────────────────┐
│ 子进程: node  (PID 独立, 非 android:process 组件)                 │
│  cmd: nativeLibraryDir/libnode.so <files/st>/server.js            │
│       --dataRoot <files/data>  --port <p>  [--browserLaunch=false]│
│  env: HOME / TMPDIR / TMP / TEMP / LD_LIBRARY_PATH / LANG / PORT  │
│  Node 24 LTS (full ICU) → ST Express → 127.0.0.1:<p>              │
│  stdout/stderr → logcat + 滚动文件                                 │
└───────────────────────────────────────────────────────────────────┘
```

### 1.2 目录布局

```
/data/data/<pkg>/
├── files/
│   ├── st/                       # ST 安装目录（可写，升级时整体替换）
│   │   ├── server.js  src/  public/  default/
│   │   ├── node_modules/
│   │   ├── config.yaml           # 指向 dataRoot 的配置
│   │   └── dist/_webpack/<hash>/output/lib.js   # P1 必需
│   ├── data/                     # ★ 用户数据，--dataRoot 指向此处，永不被升级触碰
│   │   ├── default-user/
│   │   │   ├── chats/  characters/  groups/  worlds/  presets/
│   │   │   ├── settings.json  secrets.json  stats.json
│   │   │   ├── extensions/       # 本地扩展（D10 安全区）
│   │   │   └── drafts/           # P7 生成草稿
│   │   ├── _storage/             # node-persist 账户表
│   │   └── _webpack/             # 注：P1 后不再使用此路径
│   └── meta/version.json         # 版本戳（单调递增 build number）
└── cache/
    └── tmp/                      # TMPDIR 指向此处（Android 无 /tmp）
```

**关键不变量**
- `files/data/` **永远不在 `files/st/` 内部** → 升级替换 `files/st/` 不伤数据。
- 所有路径 **纯 ASCII**（规避 `fs.cpSync` 非 ASCII 原生崩溃，R9）。
- `nativeLibraryDir` **每次启动重新解析**，绝不持久化（升级后路径会变）。

---

## 2. 运行时层（Node on Android）

### 2.1 产物规格

| 项 | 规格 |
|---|---|
| 源码 | 官方 `nodejs/node` v24 LTS，**不 fork** |
| 构建主机 | GitHub Actions `ubuntu-latest`（本机无 WSL/Docker，Node 的 Android 构建 Linux-only；已核实 `android_configure.py:13-15` 非 Linux/Darwin 直接 exit 1） |
| 命令 | `./android-configure <NDK 绝对路径> 26 arm64 && make -j$(nproc)` |
| **⚠ 必须先用 NDK r28+** | 16KB 对齐**只能靠 NDK r28+ 的链接器默认值**。`configure.py` **无 `--ldflags` 选项、不读 `$LDFLAGS`**（实测 0 命中），`android_configure.py` 调 configure 时参数写死、不转发 `"$@"` → **没有任何 flag 通道**。**已实测**：NDK r28c + 零 flag 编译 arm64，四个 `PT_LOAD` 全部 `p_align=0x4000` 且同余。**r27 的"两个 page-size flag"建议在本构建方式下不可实施，不要照抄。** |
| **⚠ 参数必须是 3 个位置参数** | 脚本签名是 `len(sys.argv) != 4: usage; sys.exit(1)`（`android_configure_v24.py:21-23`），即 **`<ndk> <sdk> <arch>` 三个**。**它不读 `ANDROID_NDK_HOME` / `ANDROID_API` 环境变量**（grep 0 命中）。写 `./android-configure $NDK arm64`（2 个参数）会**直接 usage 退出** |
| **⚠ 必须自己补 `CC_host`/`CXX_host`** | 上游脚本只设 `CC`/`CXX` 为 **NDK 的 aarch64 clang**，**不设 `CC_host`**（实测 grep 为空）；而 `configure.py:1506` 会读 `CC_host` 推断宿主架构。缺了它 → 宿主工具被误判为 arm64 → `node_js2c`/`torque`/`mksnapshot`/`genccode` 被编译成 **ARM64 二进制，在 x86_64 runner 上无法执行** → 构建失败。两个可用的 fork 都补了这一行（`njm-android_configure.py:69-70`） |
| 构建前补丁 | **⚠ 不要盲抄 forks 的一行（审核 N5）**：<br>① 两个 fork 用的**不是同一个编译器**——`njm` 用 `command -v gcc`/`g++`，`fogtape` 用 `command -v clang`/`clang++`；<br>② **`clang` 在 `ubuntu-latest` runner 上不保证存在**（gcc/g++ 才有）。若 `$(command -v clang)` 取到**空值**，`configure.py:1454` 的 `shlex.split(cc or CC)` 会**回退到交叉用的 `CC`（aarch64 clang）**→ **静默地把 B2 那个 bug 装回去，且不报错**。<br>**正确做法**：用 **gcc/g++**（runner 必有），并**断言非空**：<br>`export CC_host=$(command -v gcc) CXX_host=$(command -v g++)`<br>`[ -n "$CC_host" ] && [ -n "$CXX_host" ] || { echo "host compiler missing"; exit 1; }`<br>③ **仍需实测确认**：`configure.py` 用 `CC_host` 只做**架构探测**，并不会把它写进 `config.gypi`；gyp 的 `_toolset=="host"` 段是否真拿到 `CC_host` 取决于 gyp 的环境传递 —— **CI 里必须验证宿主工具（`node_js2c`/`torque`/`mksnapshot`）确实是 x86_64 且可执行**（例如 `file out/host/Release/node_js2c` 或直接跑它）。 |
| **关键** | **不传 `--shared`**（`configure.py` 的 `--shared` 默认 `None`）→ 产出**可执行文件** |
| NDK | **必须 r28+**（16KB 由链接器默认值保证，见上行）。原写"r27 需给 `--max-page-size` + `--common-page-size`"——**在 `android_configure.py` 下无法实施，已作废** |
| ICU | `--with-intl` 默认 `full-icu`，`<icu>.dat` 经 `genccode` **编进二进制**，无需 `NODE_ICU_DATA` |
| 必备 flag | `--openssl-no-asm`（android_configure 已内置） |
| 伴随库 | `libc++_shared.so`（**必须**，`DT_NEEDED` 含它） |

### 2.2 构建期门禁（CI，缺一不可）

> ⚠ **本节经真实构建修正（第 5 轮审核）**：原文把门禁③④写成"跑 `node -e ...`"，但那是 **aarch64 二进制，在 x86_64 runner 上根本跑不了**。实际可行的门禁必须是**静态可验证**的。下面同时给出"设计意图"和"CI 里真正能执行的检查"。

| # | 门禁 | 设计意图 | CI 里怎么真正执行 | 失败后果 |
|---|---|---|---|---|
| ① | **是可执行文件** | `e_entry ≠ 0`（`.so` 的 `e_entry=0`，`execve` 会 ENOEXEC） | `llvm-readelf -h` 取 Entry point，断言 `!= 0x0` | APK 装好后 `libnode.so` 起不来 |
| ② | **16KB 页对齐** | 每个 `PT_LOAD` `p_align=0x4000` 且 `(vaddr-offset)%0x4000==0` | `llvm-readelf -lW` + shell 算术（**已实测本机算法正反向都正确**） | Android 15+ 16KB 设备 SIGSEGV；Play 拒收 |
| ③ | **full ICU 已编入** | 登录路径 `users.js:645` 用 `String.normalize()` | **不能跑二进制** → 只能静态查：`nm`/`readelf -s` 找 `unorm2_*`/`ucol_*`/`icudt` 符号，**并且必须 `exit 1`**（只 warn 等于没有门禁） | 能启动、**永远登不了录** |
| ④ | **Intl 可用** | `Intl.Collator` 等 | 同③，与③合并为一次符号扫描 | 排序/本地化异常 |
| ⑤ | **可执行位** | `chmod +x` 后在 APK 里能 exec | `test -x`（构建机上），运行时另有 `canExecute()` 断言（§2.3） | `EACCES` |

> **⚠ ③④ 是硬门禁**：`--with-intl=none` 会让**每次登录**抛 TypeError（`users.js:645`），而这类构建"能启动、不能登录"，最难排查。**符号扫描不到 ICU 就必须 `exit 1`，不能只打 WARN。**
> **待办（M0 关闭前）**：把 ③ 的 WARN 改成硬失败，并补一条"用 `readelf -sW | grep -c 'unorm2_'` 断言 > 0"的检查。当前 CI 里这条还是软警告 —— 已在 §12 记为 U16。

### 2.2b 【第 5 轮审核补充】真实构建踩到的 4 个坑（原文完全未记录）

这四个失败都是**实际构建时炸出来的**，每个都吃掉 10 分钟到 3 小时。SDS 原文一条都没写，违反 §11.0 自己的规则。现按"症状 → 根因 → 修法 → 是否已固化"记录：

| # | 症状 | 根因 | 修法 | 已固化？ |
|---|---|---|---|---|
| **B1** | `android-actions/setup-android@v3` 失败：`Failed to find package 'tools'` | 该 action 内部执行 `sdkmanager --install tools`，而 Google **已移除** `tools` 这个包 | **不要用这个 action**；runner 自带可用的 SDK，直接定位 `$ANDROID_SDK_ROOT` 并用 `cmdline-tools/*/bin/sdkmanager` | ✅ 已从 workflow 移除 |
| **B2** | `yes \| sdkmanager --licenses` 后 job 突然 abort，日志只有 `yes: standard output: Broken pipe` | `sdkmanager` 接受完就退出，`yes` 收到 SIGPIPE；在 `set -o pipefail` 下退出码非 0 → 整个 step 失败 | **不要用 `yes \|`**；用 `printf 'y\n%.0s' $(seq 1 200) > /tmp/lic.txt` 再从文件重定向，并 `\|\| true` 容忍退出码 | ✅ |
| **B3** | `ld.lld: error: undefined symbol: android_getCpuFeatures`（链接 `openssl-cli` 时） | `deps/zlib/zlib.gyp` 在 Android 上定义 `ARMV8_OS_ANDROID` → `cpu_features.c:109` 调 NDK 的 cpufeatures 库，而 Node 的 gyp **从不链接**该库 | 把该 define 改成 `ARMV8_OS_LINUX`，走 `cpu_features.c:117` 的 `getauxval(AT_HWCAP)` 分支（bionic 的 libc 自带，语义等价：同样读 CRC32/PMULL 位） | ✅ 已写进 `apply-node-android-patches.sh` |
| **B4** | **约 3 小时后**，链接 **host 工具** `mksnapshot` 失败：`undefined reference to v8::internal::trap_handler::TryHandleSignal` / `RegisterDefaultTrapHandler` / `v8_internal_simulator_ProbeMemory`，且链接里出现 `simulator-arm64.o` | `deps/v8/src/trap-handler/trap-handler.h:33-37` 在 **`V8_TARGET_ARCH_ARM64 && V8_HOST_ARCH_X64 && V8_OS_LINUX`** 时启用 `V8_TRAP_HANDLER_VIA_SIMULATOR`。交叉编译时 **host toolset 用 `OS=linux` 编译，却继承了 `v8_target_arch=arm64`** → host 工具走 simulator 路径 → 其汇编/实现对 host toolset 不可链接。**注意：这与 `CC_host` 是两回事**——即使 host 工具正确编成 x86_64，这条路径依然会炸 | Node **自带**修复：`android-patches/trap-handler.h.patch` 把整段条件链替换成 `#define V8_TRAP_HANDLER_SUPPORTED false`。官方入口是 `./android-configure patch`，但**依赖外部 `patch` 二进制**、且该 `.patch` 的 pre-image 会随版本漂移。我们改为用 Python 做等价变换（按锚点定位整条 `#if/#elif/#else/#endif` 链并替换），不依赖 `patch`；**锚点漂移时 exit 1 而非静默跳过**（否则要等 3 小时才在 mksnapshot 链接处失败） | ✅ 已写进 patch 脚本，**本机实测 223→185 行、`VIA_SIMULATOR` 清零、`#if/#endif` 配对平衡** |

> **关键教训（写进 §11.0 规则）**：`configure.py` **完全没有 LDFLAGS 通道**（无 `--ldflags` 选项、不读 `$LDFLAGS`，实测 0 命中）。所以 §2.1 里"r27 需要给 `--max-page-size` 和 `--common-page-size`"这条**在 `android_configure.py` 下无法实施**——它调 configure 时用的是写死的参数表，不转发 `"$@"`。**唯一可行做法是直接用 r28+**，让链接器默认产出 16KB（已实测：零 flag 下 `p_align=0x4000`）。

### 2.3 启动参数与环境

**⚠ 前置：`jniLibs` 必须真的被解压出来（S8，M0 的硬前提）**
`nativeLibraryDir` 只在安装器**解压**了原生库时才有内容。AGP 默认 `extractNativeLibs=false`（库留在 APK 里不落地）→ `nativeLibraryDir` 为空 → `ProcessBuilder` 在 `ENOENT` 处失败。
**必须同时设置**：
```xml
<!-- AndroidManifest.xml -->
<application android:extractNativeLibs="true" ... >
```
```kotlin
// app/build.gradle.kts
android {
    packaging { jniLibs { useLegacyPackaging = true } }   // AGP 4.2+ 用它取代 manifest 属性
}
```
> 两者是同一件事的两种写法，**本项目两个都写**（manifest 属性在旧 AGP 生效，`useLegacyPackaging` 在新 AGP 生效）。缺了它 M0 直接过不了，且报错会指向 `libnode.so` 不存在。

**⚠ 还有一步不能省（审核 N16）：spawn 前断言可执行位**
某些 ROM（MIUI/ColorOS 的重打包）会丢掉可执行位。真实在跑的实现（`STpatch-NodeService.kt:232`）在 `ProcessBuilder` 之前显式做了 `nodeBin.setExecutable(true, false)`。
**SDS 要求**：`ServerController` 在 `ProcessBuilder` 前执行：
```kotlin
val nodeBin = File(applicationInfo.nativeLibraryDir, "libnode.so")
if (!nodeBin.canExecute()) { nodeBin.setExecutable(true, false) }
check(nodeBin.canExecute()) { "libnode.so is not executable: ${nodeBin.absolutePath}" }   // 必须 fail-fast 到错误页
```
> 这条要进 M0 的退出条件：**先断言 `canExecute()`，再 spawn**。否则在部分设备上表现为 `ENOENT`/`EACCES`，且极难归因。

```kotlin
val pb = ProcessBuilder(nativeDir + "/libnode.so", "$stDir/server.js",
                        "--dataRoot", dataDir.absolutePath,
                        "--port", port.toString(),
                        "--browserLaunchEnabled", "false")   // ★ 真实 CLI flag（command-line.js:142）
pb.directory(stDir)                          // 必须在 st/ 内，server.js 会 chdir
pb.environment().apply {
    put("HOME", filesDir.absolutePath)
    put("TMPDIR", cacheDir.resolve("tmp").apply{ mkdirs() }.absolutePath)  // Android 无 /tmp
    put("TMP",  get("TMPDIR")!!)
    put("TEMP", get("TMPDIR")!!)
    put("LD_LIBRARY_PATH", nativeDir)        // ★ 缺了它 exec 会在 DT_NEEDED 阶段失败
    put("LANG", "en_US.UTF-8")               // ★ 对齐桌面，避免 Intl.Collator 行为漂移（R10）
    put("NODE_ENV", "production")
}
```

**CLI 参数（**已核对 `src/command-line.js`**）**
| 参数 | 真实存在 | 说明 |
|---|---|---|
| `--dataRoot <path>` | ✅ `:212` | 用户数据根，必须指向 `files/data` |
| `--port <n>` | ✅ `:132` | 覆盖 config 里的 port |
| `--browserLaunchEnabled <bool>` | ✅ `:142`（`type: boolean`） | **关掉浏览器启动** |
| ⚠ `SILLYTAVERN_BROWSERLAUNCH_ENABLED` | ❌ **不存在** | 早期设计稿误用了环境变量；ST 源码里**没有**这个变量。已改为真实 CLI flag |

**`LD_LIBRARY_PATH` 是硬要求**：可执行文件被 `execve` 后，动态链接器**不会**自动在 `nativeLibraryDir` 找 `DT_NEEDED`。真实在跑的实现（`STpatch-NodeService.kt:270`）同样设置了它。

### 2.3b ✅ exec 模型已用真实 APK 在 Android 14 上实证（2026-11-08）

之前 SDS 只能说"按 SELinux 策略文档，`apk_data_file` 有 `execute`"。现在有**同一台设备上正反两面的实测**。

**验证方法**：写一个最小 APK（`io.test.wx`），把探针编成 `jniLibs/x86_64/libprobe.so` 并让它的 `DT_NEEDED` 含 `libc++_shared.so`；用 `useLegacyPackaging = true` + `android:extractNativeLibs="true"` 打包；安装后从 `nativeLibraryDir` 执行。

| 测试 | 条件 | **实测输出（原文）** | 结论 |
|---|---|---|---|
| **T1** | exec `nativeLibraryDir/libprobe.so` + 设 `LD_LIBRARY_PATH` | `exit=0  PROBE_OK argc=3 cxx=3` | ✅ **exec 模型成立**：APK 内作为 `lib*.so` 打包、被安装器解压到 `nativeLibraryDir` 的二进制**可以 execve** |
| **T2**（反向对照） | 复制到 `filesDir` 后 exec | `IOException: ... error=13, Permission denied`；内核 AVC：`avc: denied { execute_no_trans } ... scontext=u:r:untrusted_app tcontext=u:object_r:app_data_file:s0` | ✅ **W^X 被实证**。注意：被拒是 **SELinux**（`app_data_file` vs `apk_data_file`），文件实际是 0711（x 位已设）仍被拒 → **`setExecutable()` 修不了** |
| **T3** | exec `nativeLibraryDir/libprobe.so` + **不设** `LD_LIBRARY_PATH` | `exit=1  CANNOT LINK EXECUTABLE ".../libprobe.so": library "libc++_shared.so" not found: needed by main executable` | ✅ **`LD_LIBRARY_PATH` 确实必需**。且 `libc++_shared.so` 就在同一目录 → 证明 **bionic 不搜索可执行文件自身目录**（审核另行实测：两文件同目录、不设 `LD_LIBRARY_PATH` 仍 `CANNOT LINK`；设了则 `PROBE_OK`） |
| **T4** | `canExecute()` | `true` | ⚠ **机制说明更正（审核核实）**：不是"安装器保留了执行位"——APK 里 zip entry 是 `0100644`（无 x 位），是**安装器解压时创建为 0755**。结论（要显式断言）不变，但理由不同 |

> **T1+T2 的组合是根基性验证**：`nativeLibraryDir` 能跑 / `filesDir` 不能跑，同一设备、同一二进制、同一进程上下文。
>
> **⚠ W^X 不是绝对的（审核 T5/T6 实测，必须记录）**：`execve` 直接执行 `filesDir` 里的文件确实被 SELinux 拒（T2）；**但** 用 `linker64 <path>` 把它当**解释器的输入**加载则**可以跑**：
> ```
> T5: linker64 /data/.../files/probe_copy  -> exit=0 PROBE_OK   （无 AVC 拒绝）
> T6: 同一文件直接 exec                        -> error=13
> ```
> 因为 `linker64` 只是 **read+mmap** 该文件（不需要 `execute_no_trans`）。
> **对项目的含义**：这**不**意味着我们可以走这条路——① 它依赖 `linker64` 存在于 `/system/bin`（有，但要硬编码路径）；② 它绕过了 SELinux 的 W^X 设计意图，属于**平台不推荐、未来可能被封堵**的用法；③ 我们用 `nativeLibraryDir` 是**官方支持的干净路径**，没必要冒险。**记录它是为了诚实**：SDS 不能声称"filesDir 绝对跑不了"。
>
> **⚠ 关键局限（审核强化，必须与上表同权重阅读）**：T1–T4 用的是 **5.5KB 的 `printf` 探针**，而真实目标是 **~90MB 的 Node**。二者之间隔着：V8 初始化/JIT/快照加载、多线程、长生命周期、信号处理、LMK。**"一个 PIE 能 exec" ≠ "Node 能跑"。**
> 审核还实测：42KB/2MB/8MB/20MB/62MB 的合成 PIE **都能跑**（说明体积本身不是问题）；但把 `.work/dl/njm/` 里那个 **62MB x86_64 `libnode.so`** 直接执行会 **SIGSEGV (RC=139)** —— 原因正是它 **`PT_INTERP: False`**（是 `--shared` 共享库，见 §3.2.1），用 `linker64` 硬当程序加载当然崩。**这反过来印证了本文档 §3.2.1 的判断，不是反例。**
> **复现**（工程在 `H:\Android\wxtest`）：
> ```
> adb install -r app-debug.apk
> adb shell am start -n io.test.wx/.MainActivity
> adb logcat -d -s WXTEST:*
> ```
> **⚠ 该验证是在 x86_64 模拟器（Android 14 / API 34 / 4KB 页 / **Google userdebug 镜像**，`ro.debuggable=1`，比量产 user 版宽松）上做的**。它验证的是 **exec 机制**，**不是** arm64 二进制、**不是** 16KB 页设备、**不是** 90MB 载荷、**不是**长驻进程、**不是** OEM ROM。arm64 二进制**至今从未在任何设备上执行过**（详见 §11.3）。


**`pb.directory(stDir)` 与 `process.chdir` 的关系（不矛盾）**：`server.js:11` 会 `process.chdir(serverDirectory)`，把 cwd 强制设为**模块所在目录**。所以 `pb.directory` 只是保证启动瞬间的相对路径可解析；**真正的 cwd 由 ST 自己决定**。

**`--dataRoot` 的优先级已核对（`command-line.js:288-290`）**：
```js
const dataRoot = isGlobal
    ? defaultConfig.dataRoot
    : (cliArguments.dataRoot ?? getConfigValue('dataRoot', defaultConfig.dataRoot));
```
→ **CLI 参数优先于 `config.yaml`**。但默认 `config.yaml:3` 里写的是 `dataRoot: ./data`（**相对路径**），且 `chdir` 到安装目录后相对路径会解析成 `files/st/data` —— **正好是我们最不想要的位置**（升级会被清）。
→ **因此必须**：① 传**绝对路径** `--dataRoot`；② 同时把 `config.yaml` 里的 `dataRoot` 也改成绝对路径（双保险，防止某条路径漏传 CLI）。

### 2.4 探活与就绪
- 轮询 `GET http://127.0.0.1:<port>/`，间隔 150ms，超时 30s。
- 200 且 body 含 ST 特征串 → `READY`。
- 进程提前退出 → 读 stderr 尾 200 行 → 判定原因（端口占用 / config 损坏 / 缺文件）→ 进 `FAILED` 或退避重试。

---

## 3. 数据持久性设计（G2）

### 3.1 保证层次（**这是对用户的承诺原文，不可弱化**）
> **我们保证**：已 `fsync` 的写入，在崩溃 / 划掉 / 断电 / OOM kill 后重启仍然存在且可解析。
> **我们不保证**：
> - 断电瞬间正在烧写的**最后一个 block**（未 fsync 部分）
> - 存储写满时的写入成功（但**失败必须可见，绝不静默损坏**）
> - 用户「清除数据」或「卸载」后的数据（只能靠外部备份）
> - 进程被杀瞬间**尚未落草稿**的生成 token（草稿每 2s 落一次，最多丢 2s）

### 3.2 写入原语矩阵

| 数据类型 | 现状 | 加固 | 补丁 |
|---|---|---|---|
| 聊天 `.jsonl` | 已有 `write-file-atomic`（temp+fsync+rename） | 父目录 fsync；跳过未变更写；备份改硬链接 | P6-A/B1, D-P3 |
| 角色 / 世界书 / 预设 / 主题 | 同上 | 同聊天 | D-P3 |
| `settings.json` / `secrets.json` | 同上 | 同上 + 保留 `.bak.prev` | D-P3 |
| **`config.yaml`** | ❌ **裸 `fs.writeFileSync`（`config-init.js:239`）** | **原子写 + 解析失败回滚 `.bak`** | **D-P1** |
| **账户表 `_storage`** | ❌ node-persist（1s 缓冲 + 裸 write） | 收紧 `writeQueueIntervalMs` + `forgiveParseErrors:true` + 原子写 | **D-P2** |
| 生成草稿 | 不存在 | 新建独立文件，每次 fsync | P7 |
| 快照 | 不存在 | 周期性环形快照 | L6 |
| 外部备份 | 不存在 | SAF 导出 | L7 |

### 3.3 启动恢复例程（**D-P4**，每次启动无条件执行）
```
1. 清理 write-file-atomic 残留
   ⚠ 审核 S5：它不叫 *.tmp/*.part。实测 write-file-atomic@5.0.1 的临时文件名是
     <目标文件>.<murmurhash>（例如 "settings.json.1a2b3c4d"），前缀是目标名本身。
   → 正确做法：对每个已知数据文件，删除同目录下名为 "<basename>.<8位hex>" 且不匹配
     任何真实文件的残留；或更稳：只在启动后按 mtime > 1 小时的孤儿文件清理。
2. 扫描所有 *.jsonl：末行不可解析 → 截断到最后一个完整行，记录事件
   （ST 自带 checkChatIntegrity (chats.js:337-369) 会拒绝覆盖坏文件，可复用其判定）
3. 扫描 drafts/：按 §3.6b 的三段判定恢复或删除（**比内容长度，不比索引存在性**）
4. 校验 settings.json / secrets.json：解析失败 → 回滚 .bak.prev
5. 校验 config.yaml：
   ⚠ 审核 S5：yaml.parse 对截断文件常常**不抛错**——实测 0/10/40 字节返回 null，
     120/8395/16750 字节仍能解析成功 → 原设计"解析失败就回滚"大部分时候不触发，
     而"解析成 null"会导致**静默重置为默认配置**（用户配置无声丢失）。
   → 正确判据是三选一：① 解析结果为 null/非对象；② 缺少必备顶层键（如 dataRoot）；
     ③ 为空文件。任一成立即回滚 .bak。
6. 结果汇总写入 recovery-report.json，UI 启动后若 count>0 显示「上次异常退出，已修复 N 项」
```

### 3.4 补丁 D-P1：`config.yaml` 原子化
**问题**：`src/config-init.js:239` 是裸 `fs.writeFileSync`，而 `src/util.js:74-78` 在 YAML 解析失败时**直接 `process.exit(1)`** → 截断即**永久变砖**（无 UI 可报错）。

**设计**：
```js
// src/config-init.js，替换 :239
writeFileAtomic.sync(configPath, yaml.stringify(config), { fsync: true });
// 并在写成功后立即刷新 .bak
try { fs.copyFileSync(configPath, configPath + '.bak'); } catch {}
```
**读取侧**（`util.js:70-79`）：
```js
try {
  const parsed = yaml.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  // ⚠ 不能只靠 try/catch（实测三种失败形态）：
  //   ""        -> null（不抛错）
  //   截断的引号 -> 抛 YAMLParseError ✅ 能抓到
  //   截一半    -> 抛错 ✅ 但另一种「截在值中间」会**成功解析成缺字段的对象**，
  //               例如 browserLaunch: "en"（string 而非 object）→ 不抛错、也不是 null
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('config.yaml did not parse to an object');
  }
  // 必备顶层键校验：README 保证这些键一定存在，缺任何一个即视为损坏
  for (const key of ['dataRoot', 'listen', 'port', 'browserLaunch']) {
    if (!(key in parsed)) { throw new Error(`config.yaml missing required key: ${key}`); }
  }
  CACHED_CONFIG = parsed;
  return CACHED_CONFIG;
} catch (e) {
  const bak = CONFIG_PATH + '.bak';
  if (fs.existsSync(bak)) {
    console.warn(`config.yaml 损坏 (${e.message})，已从 .bak 恢复`);
    fs.copyFileSync(bak, CONFIG_PATH);
    CACHED_CONFIG = yaml.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    return CACHED_CONFIG;
  }
  /* 原逻辑 exit(1) */
}
```
> **为什么必须加必备键校验**：`yaml.parse` 在"截断但语法仍合法"时返回**结构完整度不足的对象**，不抛错、不是 null，只靠类型判断会**静默接受半份配置** —— 用户设置被无声重置。

### 3.5 补丁 D-P2：账户表（**原设计已被实测推翻，改用写侧加固**）

**我原本的设计（错，保留记录防复现）**：给 `storage.init` 加 `writeQueueIntervalMs: 50` + `forgiveParseErrors: true`，理由写的是"最多丢 50ms 而非 1s"、"坏文件可被宽容解析"。
**两项实测都证伪：**

**❌ 被证伪 1：`writeQueueIntervalMs` 根本没有 1 秒窗口。**
`startWriteQueueInterval`（`local-storage.js:411-416`）会**先同步调 `processWriteQueue()` 再装 interval**；`queueWriteFile`（`:357-360`）在 `nextTick` 再排一次。实测 `setItem` 落到磁盘是 **0–1 ms**，`=1000` 与 `=50` **无差别**。
→ 所谓"50ms vs 1s 的取舍"描述的是一个**不存在**的现象。

**❌ 被证伪 2：`forgiveParseErrors: true` 不能救坏文件，反而把启动错误变成致命 TypeError。**
真实代码链：
1. `local-storage.js:349`：解析失败且 flag 为真 → `resolve({})`（**一个没有 `.key` 的空对象**）
2. `:305-330` `readDirectory` 把它塞进数组
3. `users.js:673` `getAllUserHandles()` 执行 `storage.keys(x => x.key.startsWith(...))` → **`TypeError: Cannot read properties of undefined`**
4. `server-main.js:480-490` 的 `initUserStorage(...).then(...).then(...)` **没有 `.catch`** → Node 以 **1** 退出，**`listen` 永远不到**

**实测 4 种情形（真跑 node-persist）**：
| 情形 | 结果 |
|---|---|
| `forgive=true` + 截断 | **THREW TypeError: …reading 'startsWith'** |
| `forgive=false` + 截断 | THREW `Error: [node-persist][readFile] … does not look like a valid storage file!` |
| `forgive=true` + 空文件 | **THREW 同一个 TypeError** |
| `forgive=true` + 完好 | OK `["user:default-user"]` |

→ **flag 没救回任何东西**：截断在两种设置下都失败，它只是把"文件名明确的损坏错误"换成"别处的 TypeError"，并把失败从"启动时报错"变成"服务永不监听"。

**✅ 正确设计（D-P2 v2）：写侧加固 + 读侧防御，双管齐下**
1. **写侧（根治）**：把 `_storage` 的写入改成原子写。node-persist 内部用裸 `fs.writeFile`，所以最干净的做法是**不依赖它**——在 patch 里把存储目录的写入换成 `write-file-atomic`（temp + fsync + rename），从根上消除"截断文件"这种状态。
2. **读侧（兜底）**：`users.js:673` 的取值加防御：
```js
// src/users.js，getAllUserHandles()
const keys = await storage.keys(x => typeof x?.key === 'string' && x.key.startsWith(KEY_PREFIX));
```
并把解析失败的记录**隔离**（移到 `_storage/_corrupt/`）而不是让它在数组里变成 `{}`。
3. **启动链加 `.catch`**：`server-main.js:480-490` 的 promise 链补 `.catch(err => { 记录 + 进入可读错误页 })`，任何账户表异常都不能表现为"静默不监听"。
4. **删掉** `writeQueueIntervalMs` 与 `forgiveParseErrors` 这两个"修复"——前者无效果，后者有害。

> **D-P2 的验收（重写）**：把 `_storage` 里的某个用户记录**截断一半** → 重启 → **必须**能起来（进错误页或正常进 UI 且账户被隔离），**不能**出现 `listen` 永不发生。这条要在 M3 的 kill-9 门禁里单独跑一遍。

**⚠ M2（审核发现）：`config.yaml` 住在安装目录，升级会重置用户配置**
- `command-line.js:55` 里 `configPath` 默认是 `./config.yaml`，即**安装目录内** → 每次替换 `files/st/` 就**丢掉用户所有配置**（包括 P6-C 的压缩开关、主题、备份份数等）。
- **处置**：把 `config.yaml` **移出安装目录**，用 `--configPath` 指向 `files/data/config.yaml`（`command-line.js:117` 有该 flag）。
- **⚠ 但首启会直接 exit(1)（审核 N10，已复现）**：`config-init.js:164-170` 写 `configPath` 时**没有 `mkdirSync` 父目录**，而 `command-line.js:283` 唯一的 `mkdirSync` 被 `if (isGlobal)` 包着。所以 `--configPath <不存在的目录>/config.yaml` → `ENOENT` → `util.js:64-67` `process.exit(1)`，提示 "No config file found"。
  **而 Android 首启时 `files/data/` 本来就不存在** → 按原样会**首启即砖**。
- **✅ 修正**：**启动器在 exec Node 之前必须先 `mkdir -p files/data`**（以及 `files/data/default-user` 等）。这是 `ServerController` 的职责，必须写进 §8.1 的首启流程，不能假设 ST 会建目录。
- 迁移规则：首启/升级时若 `files/data/config.yaml` 不存在而 `files/st/config.yaml` 存在 → **搬过去**（不要重新生成）。
- 这样 L8「升级只换程序目录」才真正成立；否则 L8 是假承诺。

**⚠ M2 续（进一步核查：搬走 `config.yaml` 还不够，但 P11 的动机需要修正）**

**审核 N11 实测纠正了我原先的表**：我原写"图片/音频上传会写进安装目录"——**这是错的**。逐个写位点核查后：

| 路径 | 真实写入情况 | 需要 P11 吗 |
|---|---|---|
| `config.yaml` | `config-init.js:239` 裸写 | ✅ 用 `--configPath` 搬走 |
| **`backups/_migration/<date>/`** | **`users.js:382-386`——`PUBLIC_DIRECTORIES.backups` 唯一的运行时写位点**，且用 `path.join(process.cwd(), …)` | ✅ **P11 的真实目标** |
| `public/scripts/extensions/third-party/` | `extensions.js:118,486` **仅在全局扩展路径**，而 §7.2 已禁止全局 | ⚠ 已被禁止全局覆盖，P11 不必管 |
| `public/img/`、`public/sounds` | **零写入位点**。图片/资产/音频上传都走 `request.user.directories.*`（`DATA_ROOT` 下）：`assets.js:85,224,288`、`images.js:65,95,117`、`users.js:1216` | ❌ 不需要 |
| `public/error/*.html`、`public/css/user.css` | `migratePublicOverrides`（`users.js:521-523`）把它们**搬出**到 `DATA_ROOT`，单向迁移，安全 | ❌ 不需要 |

→ **P11 的真实范围只有两处：`config.yaml`（用 `--configPath`）+ `PUBLIC_DIRECTORIES.backups`（改指向 `DATA_ROOT`）**。原表把 `images`/`sounds` 列进来是过度设计，且**真正的元凶 `users.js:382` 的 `path.join(process.cwd(), …)` 恰恰会被"绝对路径"改法搞坏**（见下 N1）。

→ **P11 定稿（范围已按 N11 收窄）**：只需要处理 `PUBLIC_DIRECTORIES.backups`，其余保持原相对值不动。

**⚠ 天真写法会让整个进程无法加载（审核 N1，已实测复现）**：
```js
// ❌ 错：constants.js 在 DATA_ROOT 赋值之前就被求值
const DATA = globalThis.DATA_ROOT;
export const PUBLIC_DIRECTORIES = { backups: path.join(DATA, 'backups/'), ... };
```
实测：`server.js:2` 静态 `import './src/command-line.js'` → `config-init.js` → `util.js:21` → `constants.js`，**全部早于 `server.js:9` 的 `globalThis.DATA_ROOT = cliArgs.dataRoot`**。
探针输出：`[PROBE] after command-line import, DATA_ROOT = undefined` → `path.join(undefined, …)` **抛 TypeError，31 个 import 者全挂**。

**⚠ 第二个坑（N1）**：`users.js:382` 是 `PUBLIC_DIRECTORIES.backups` 唯一的**路径拼接写位点**，写的是
`path.join(process.cwd(), PUBLIC_DIRECTORIES.backups, '_migration', date)`。
若把 `.backups` 改成**绝对路径**，`path.join` 会把绝对段当普通段拼 → 得到**安装目录下名为 `<数据根绝对路径>` 的怪目录**，正好制造 P11 要消灭的写入。

**✅ 正确写法：惰性 getter + 同时修掉那个 `path.join(process.cwd(), …)`**
```js
// src/constants.js（P11 正确版）——只动 backups，其余保持相对
export const PUBLIC_DIRECTORIES = {
    images: 'public/img/',
    sounds: 'public/sounds',
    extensions: 'public/scripts/extensions',
    globalExtensions: 'public/scripts/extensions/third-party',
    get backups() {
        const root = globalThis.DATA_ROOT;
        if (!root) throw new Error('DATA_ROOT not initialised before PUBLIC_DIRECTORIES.backups');
        return path.join(root, 'backups/');      // 绝对路径，惰性求值
    },
};
```
```js
// src/users.js:382（必须同时改，否则上面的绝对路径会拼出怪目录）
- const backupDirectory = path.join(process.cwd(), PUBLIC_DIRECTORIES.backups, '_migration', currentDate);
+ const backupDirectory = path.join(PUBLIC_DIRECTORIES.backups, '_migration', currentDate);
```

**`PUBLIC_DIRECTORIES` 的全部消费方（审核复核后的完整清单，别只改一处）**：
| 位置 | 用法 | 受 P11 影响？ |
|---|---|---|
| `users.js:114-118` `ensurePublicDirectoriesExist` | `Object.values(PUBLIC_DIRECTORIES)` 逐个 `mkdirSync` | ✅ **是**——每次启动都会遍历。**已实测**：惰性 getter 在 `Object.values` 下正常工作（返回 5 个值，backups 是绝对路径） |
| `users.js:382` | `path.join(process.cwd(), PUBLIC_DIRECTORIES.backups, …)` | ✅ **必须去掉 `process.cwd()`** |
| `users.js:246` | 仅 `console.log` 打印 backups 路径（**注意：模板字符串会调用 getter**） | 无需改（打印绝对路径反而更清楚） |
| `extensions.js:117-118, 485-486` | `globalExtensions` 的 `mkdirSync` | ⚠ 仅全局扩展路径；已禁止全局，可不改 |
| `extensions.js:507-525` | `readdirSync(PUBLIC_DIRECTORIES.extensions)` / `globalExtensions` | 读操作，保持原相对值即可 |
| `users.js:1106-1112` | `globalExtensions` 的静态文件发送（`sendFile` root） | 读操作，保持原相对值即可 |

> **实测确认（惰性 getter 可行性）**：
> - `Object.values(PUBLIC_DIRECTORIES)` → `["public/img/","public/sounds",…,"<DATA_ROOT>/backups/"]`，**混合相对与绝对，但每个都是 string**，`mkdirSync` 循环正常。
> - 在 `DATA_ROOT` 赋值前访问 `.backups` → **抛出 `DATA_ROOT not initialised before PUBLIC_DIRECTORIES.backups`**（明确报错，不是 `path.join(undefined)` 的晦涩 TypeError）。
> **P11 验收（四条）**：
> 1. 服务能启动（证明没有 module-eval 时序崩）；
> 2. 触发一次数据迁移（或直接调用该路径）→ 备份落在 `files/data/backups/_migration/`；
> 3. **升级替换 `files/st/` 后该备份仍在**；
> 4. 断言安装目录内**没有**出现名为数据根路径的怪子目录（防 `path.join` 绝对段陷阱）。

### 3.6b 补丁 P7：生成草稿持久化（D14）
**为什么需要**：实测确认流式生成期间只改内存（`script.js:3679` `chat[messageId].mes = processedText`），**不落盘**；真正保存只在 `onFinishStreaming`（`script.js:3815`）。生成中途被杀 = 这条回复全丢。

| 项 | 规格 |
|---|---|
| 位置 | `files/data/<user>/drafts/<chatId>.<mesId>.json`，**独立文件，永不进聊天 `.jsonl`** |
| 触发 | 客户端节流：每 **2s** 或每 **256 字符**（先到者），POST 轻量端点 `/api/drafts/put` |
| 内容 | `{chatId, mesId, text, genStarted, swipeId, type, updatedAt}` |
| fsync | 每次写都 `write-file-atomic`（temp+fsync+rename）；草稿只有几 KB，代价可接受 |
| **恢复判定（关键，别写反）** | 启动时对每个草稿：<br>• 草稿 `mesId >= chat.length` → **磁盘上根本没有这条 → 这是被打断的生成 → 恢复**<br>• 草稿 `mesId < chat.length` 时**再比内容**：<br>&nbsp;&nbsp;– 磁盘那条是**空或明显更短**（`disk.mes.length < draft.text.length`）→ 磁盘是**半成品**（见下"第二种情况"）→ **恢复草稿，覆盖那条**<br>&nbsp;&nbsp;– 磁盘那条**已完整**（长度 ≥ 草稿）→ 陈旧草稿 → 删除<br>• 聊天文件不存在 → 恢复 |
| 正常结束 | 写正式聊天 → 删除草稿。删除失败不影响正确性（下次按上面规则判陈旧） |
| 清理 | 超过 24h 的草稿、或 `chatId` 已不存在 → 删除 |
| 与备份节流 | 完全解耦 |

**⚠ 缺失的一环（审核 N14）：草稿留下来了，但没有代码把它显示出来**
- §3.3 的恢复例程跑在 **Node 进程启动时**，它只能"保留"草稿文件；**它无法把文本重新注入聊天 UI** —— 因为 `mesId >= chat.length` 的判定只有**知道当前聊天内容的客户端**才能做。
- 补丁表里 **P7 只写了服务端**，没有前端组件 → **`am force-stop` 之后，草稿被正确保留，却没有任何代码路径会展示它** → D15 的"重启后看到已生成的部分"**不可达**。

**✅ 补全：P7 必须包含三件东西**
| # | 组件 | 位置 | 职责 |
|---|---|---|---|
| 1 | `/api/drafts/put`、`/api/drafts/list`、`/api/drafts/delete` | 服务端新增路由 | 存取草稿（**必须纳入 P10 的鉴权范围，也要过 CSRF**） |
| 2 | 流式期间的节流上报 | 前端（**这是唯一必须动 `public/` 的补丁**，需在 §6.1 里显式登记例外） | 每 2s / 256 字符 POST 一次 |
| 3 | **启动恢复提示组件** | 前端 | 聊天加载后调 `/api/drafts/list`；若存在 `mesId >= chat.length` 的草稿 → 弹提示「上次生成中断，已恢复 N 字符」+ **继续/丢弃** 两个按钮；选"继续"则把文本塞回该消息并允许续写 |

> **对 §6.1「`public/` 逐字节保留」的例外声明**：P7 是**唯一**需要改前端的补丁。必须在补集里单列、单独评审，并做成**独立小文件**（`public/scripts/android-draft-recovery.js`）+ 一行 `<script>` 引入，而不是改 `script.js` 主体，以便 rebase 上游。

**恢复组件的最小可用实现（审核 MAJOR 2 + 第三轮修正：必须写清"文本怎么回到 chat 里并且真的画出来"）**

> **⚠ 第三轮实测推翻了我的第一版**：我原写 `eventSource.emit(event_types.MESSAGE_RECEIVED, idx)` 来触发重绘。**这不会重绘任何东西。**
> 枚举 `public/` 下全部监听者：只有 `vectors/index.js:2089`（`onChatEvent`）与 `PromptManager.js:760`（`renderDebounced`），**`script.js` 注册了 0 个**；两者都不碰 `.mes_text`。
> 结果就是：`chat[i].mes` 改了、toast 弹了、提示出现了，**但消息正文永远不显示**——恰好违反本 SDS 自己写的验收（"不是仅弹了个提示但正文没回来"）。
> **正确 API 是 `updateMessageBlock`（`script.js:2033` 导出）**，它在 `:2033` 起真正写 `.mes_text` 的 innerHTML。

```js
// public/scripts/android-draft-recovery.js  —— 独立文件，不改 script.js 主体
// ⚠ PSEUDOCODE — 未运行：本片段依赖 toastr / showRecoverUI / deleteDraft（需自行实现），
//   仅用于说明注入路径与重绘 API。按 §11.0，未运行的片段必须带此标记。
import {
    chat,                       // script.js:411  export let chat = []   ← 可变、同一引用
    getCurrentChatId,           // script.js:541  export function
    getRequestHeaders,          // script.js:647
    updateMessageBlock,         // script.js:2033 export function updateMessageBlock(id, message)
    addOneMessage,              // script.js:2551 export function addOneMessage(mes, { forceId })
} from '../script.js';

async function recoverDrafts() {
    const chatId = getCurrentChatId();
    if (!chatId) return;
    // ★ chatId 必须过 ST 自己的 forbiddenRegExp/sanitize，否则会做成路径穿越写入
    const res = await fetch('/api/drafts/list?chatId=' + encodeURIComponent(chatId),
                            { headers: getRequestHeaders() });
    if (!res.ok) return;

    for (const d of await res.json()) {
        const disk = chat[d.mesId];
        // 需要恢复：磁盘上没有这条，或磁盘那条明显比草稿短（生成中被"其它保存"写了半成品）
        const needRecover = !disk || (typeof disk.mes === 'string' && disk.mes.length < d.text.length);
        if (!needRecover) { await deleteDraft(d); continue; }

        if (!disk) {
            // 分支 A：磁盘上没有这条（即 d.mesId >= chat.length）。
            // ⚠ 绝不留下空洞：ST 的保存是 chat.map(m => JSON.stringify(m)).join('\n')，
            //   遇到空槽时 JSON.stringify(undefined) === undefined → join 出**空行**
            //   → 产出不可解析的 .jsonl（实测：chat.length=1 时写 chat[5] 会得到 4 个空行，
            //   保存结果 .split('\n').map(JSON.parse) 抛错）。
            //   本分支只在 mesId >= chat.length 时可达，故处理方式二选一：
            //   - mesId === chat.length → 直接追加（无洞，安全）
            //   - mesId >  chat.length → 索引不一致，**丢弃草稿**（补洞会造假数据）
            if (d.mesId > chat.length) {
                console.warn('[draft] mesId', d.mesId, 'beyond chat.length', chat.length, '- discarding');
                await deleteDraft(d);
                continue;
            }
            chat[d.mesId] = {
                name: d.name ?? 'Character', is_user: false, is_system: false,
                mes: d.text, send_date: d.genStarted, extra: {},
                swipes: [d.text], swipe_id: 0, swipe_info: [],
            };
            addOneMessage(chat[d.mesId], { forceId: d.mesId });       // ← 真正渲染
        } else {
            // 分支 B：磁盘上有半成品 → 覆盖正文后重绘该条
            disk.mes = d.text;                                        // continue 是"后缀"，整体替换
            if (Array.isArray(disk.swipes) && disk.swipes[d.swipe_id] !== undefined) {
                disk.swipes[d.swipe_id] = d.text;
            }
            updateMessageBlock(d.mesId, disk);                        // ← 真正重绘 .mes_text
        }

        toastr.warning(`上次生成中断，已恢复 ${d.text.length} 字符`);
        showRecoverUI(d, d.mesId);   // 提供「继续 / 丢弃」，**选之前不删草稿**
    }
}
```
> **四条必须遵守的约束**：
> 1. **重绘必须用 `updateMessageBlock` / `addOneMessage`**，不是 emit 事件（emit 只通知扩展，不改 DOM）。
> 2. **`chat` 是 `script.js:411` 的 `export let chat = []`**，ES module 单例，直接改元素/push 会真正改内存状态。
> 3. **`continue` 类型的 `draft.text` 是最终文本的后缀**（`script.js:6701` 是 `+=`），所以**整体替换**，不能拼接。
> 4. **`chatId` 必须 sanitize**——`chatId` 会参与 `path.join(dir, chatId + '.jsonl')`，ST 自己的 `forbiddenRegExp` 没有作用于这里；不清洗就是路径穿越写入洞。
> 5. **`chat[d.mesId] = …` 绝不能留下空洞**（第三轮实测）：`chat.length=1` 时写 `chat[5]` 会产生 4 个空槽，而 ST 的保存是
>    `chat.map(m => JSON.stringify(m)).join('\n')` → `JSON.stringify(undefined)` 返回 `undefined` → `join` 出**空行** → **产出不可解析的 `.jsonl`**。
>    分支 A 只在 `mesId >= chat.length` 时可达，因此只需两个分支：`==` 直接追加、`>` **丢弃草稿**（补洞等于伪造消息）。
>    **实测的判别性用例**（`chat.length=1` 时）：`mesId=1 → 追加且可解析`；`mesId=2 → 丢弃`；`mesId=5 → 丢弃`。三条都不产生空洞。
>    > ⚠ 上一版我写了"7 种组合全通过"——那 7 条里有 4 条是死路径（`mesId < length` 在分支 A 里不可能出现），**属于凑数的证据**。这里换成能真正区分的 3 条。
>
> **N14 的验收（最终）**：生成到一半 `am force-stop` → 重启 → 打开该聊天 → **必须同时满足**：① 看到恢复提示；② **消息正文确实出现在聊天里**（不是只有提示）；③ 点「丢弃」才删除草稿。

> **审核 M3 教训**：曾把规则写成「`mesId === chat.length-1` 才恢复」，这是**反的**——生成中的消息只在内存，磁盘上还没有，所以索引正好**等于** `length`。按错的规则草稿会被当陈旧删掉，D15 验收必然失败。
>
> **第二种情况（更隐蔽，必须处理）**：消息在生成**开始前**就已 push 进内存 `chat[]`（`script.js:2552` 注释「Callers push the new message to chat before calling addOneMessage」），而保存发生在 `onFinishStreaming`（`:3811`）。因此中途发生**任何其他保存**（用户再发一条、编辑别的消息触发 debounce）时，**这条半成品会被整份写进磁盘**。此时磁盘 `chat.length` 已包含它 → `mesId < chat.length` → 若只按"已存在即陈旧"就会**删掉唯一能救回的草稿**。
> → 所以判定**必须是"比内容长度"而不是"比索引存在性"**。这是本条设计的核心。

### 3.6 补丁 P6：聊天保存（**不改 `.jsonl` 格式**）
实测：3000 条消息 / 8.33MiB 聊天，单次保存 **84.5ms**、**11 次 fs op**、**两次完整 8.33MiB 写**（主文件 + 备份）。每轮 2 次保存 ⇒ **~33MiB 写/轮**。

- **A｜未变更跳过**：序列化后与磁盘字节完全一致则不写（干掉 metadata-only 等空写）。
- **B1｜备份改硬链接**：`fs.linkSync(chatFile, backupFile)`，`EXDEV` 退化为复制。**去掉一半的纯重复写。**
- **C｜开请求压缩**：`performance.requestCompression.enabled: true`。

**安全性已核对源码（`chats.js:532-543`）**：
```js
export async function trySaveChat(chatData, filePath, skipIntegrityCheck, handle, cardName, backupDirectory) {
    const jsonlData = chatData?.map(m => JSON.stringify(m)).join('\n');   // 533
    // …完整性校验 (535-540)…
    tryWriteFileSync(filePath, jsonlData);                                 // 541  主文件
    getBackupFunction(handle, cardName)(backupDirectory, cardName, jsonlData); // 542 备份
}
```
- **没有隐藏副作用**：`trySaveChat` 除了写主文件 + 排队备份，**不更新** `date_last_chat`、不刷新完整性元数据。→ 在 `:540` 之后插入「字节相同则 return」是**安全的**，不会漏掉任何 ST 期望的连带动作。
- **硬链接安全**：备份文件名含时间戳（`backupChat:67` `…_${generateTimestamp()}.jsonl`），**只写一次、从不原地修改**；`removeOldBackups` 只 `unlink`。硬链接后主文件因 `write-file-atomic` 走 rename（换 inode），旧备份仍指向旧 inode → **历史快照语义不变**。
- **注意**：备份节流是 `_.throttle(backupChat, 10_000, {leading:true, trailing:true})`（`:96`），leading 会在首次保存立刻写一份备份。硬链接方案对 leading 同样有效。
> **明确不做**：追加式存储。实测消息**没有稳定 ID**（`global.d.ts:66-81`），身份是数组下标；17 种变更操作里**只有 2 种可纯追加**；`.jsonl` 是对外交换格式。改格式代价 8/10，二期再议（sidecar delta + 定期压实）。

---

## 4. 生命周期与前台服务

### 4.1 状态机
```
IDLE ──需要备货──> EXTRACTING ──> STARTING ──探活成功──> READY
                                        └──失败──> BACKOFF ──(≤3次)──> STARTING
                                                       └──(>3次)──> FAILED(错误页)
READY ──用户停止──> STOPPING ──flush──> STOPPED
```

### 4.2 前台服务规格
| 项 | 值 | 依据 |
|---|---|---|
| type | **`specialUse`** | `dataSync` 在 Android 15+ 有 6h/24h 上限，且禁止从 `BOOT_COMPLETED` 启动 |
| 必需权限 | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS` | — |
| 必需属性 | `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="local_node_web_server"/>` | — |
| `stopWithTask` | **`false`**（划掉任务不停服务，符合 D9） | — |
| `START_STICKY` | 使用，但**只作为 hint**，不依赖 | — |
| 通知 | 常驻 + **Stop action**；`POST_NOTIFICATIONS` 被拒也要有通知（否则 FGS 不可见→更快被杀） | — |
| 电池优化 | 引导用户 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（这是明确的**后台启动豁免**） | — |
| Play 审核 | `specialUse` 需 subtype 说明；**D19 自签不上 Play ⇒ 实际不受约束**，但若将来上架需补 | — |

### 4.3 崩溃与重启
```
重启退避: 1s → 2s → 4s，最多 3 次
第 3 次失败 → 停在 FAILED 错误页：
   ┌ 上次启动失败
   ├ 原因: <从 stderr 提取>
   ├ [导出日志]  [重置配置]  [重试]  [查看原始报错]
   └
```
> ST 实际有 **16 处 `process.exit(`**（实测 grep `src/**`）：`healthcheck.js`×5、`recover-password.js`×2、`server-main.js:96,326`、`server-startup.js:210,437,444`。其中 **`:437/:444` 正是端口占用 / 监听失败的致命退出**。没有退避会变成「无限重启 + WebView 永久转圈」。

### 4.4 停止路径
```
通知 Stop action → STOPPING
  → 子进程 SIGTERM
  → ST 的 exitProcess() (server-main.js:317-327) 执行:
       await statsOnExit()        // 统计落盘
       await cleanupPlugins()
       diskCache.dispose()
       process.exit()             // ← 这会触发 'exit' 事件
  → chats.js:118 注册的 process.on('exit') 此时执行 _.throttle.flush()  // 备份队列冲刷
  → 等待 3s → 若进程仍在，destroyForcibly()
```

**准确的保证边界（不要说过头）**：
- `SIGTERM` 会让 ST 跑 `exitProcess`，它会 flush **统计**、**插件**、以及 **`chats.js` 的备份节流队列**（`process.on('exit')`）。
- 但 **`exitProcess` 本身不 flush 聊天主文件**——聊天主文件的写入是每次保存时同步完成的（`write-file-atomic`），不存在"待 flush 的主文件写"。所以真正靠 `SIGTERM` 救回的是**被 10s 节流压住的备份**，不是主文件。
- **`SIGKILL`（`destroyForcibly`）会跳过 `process.on('exit')`** → 丢失节流窗口内的最后一份备份。因此**必须**先 `SIGTERM` 再强杀。
- **诚实表述**：停止路径保证「主文件不丢已保存的消息」+「尽量保留最后一份备份」；**不保证**「强杀时备份完整」。

---

## 5. WebView 层

### 5.0 入站访问控制（回环能进得来吗？——实测确认：能，且零配置）
WebView 访问 `http://127.0.0.1:<port>` 会经过 ST 两道入站检查，两道的默认值都已核对：

| 检查 | 默认 | 对回环的影响 |
|---|---|---|
| `whitelistMode` 的 IP 白名单（`src/middleware/whitelist.js:57-95`） | `whitelistMode: true`，且 `whitelist: ["::1", "127.0.0.1"]`（`default/config.yaml`） | `isIPInWhitelist()` 对 `127.0.0.1` **直接通过**，无需改动 |
| `hostValidationMiddleware`（`src/middleware/hostWhitelist.js:8-13`） | **`hostWhitelist.enabled: false`** | 默认**不启用**，不校验 `Host:` 头 |

→ **结论：WebView 连回环**不需要 `--disableCsrf`、不改白名单、不改 hostWhitelist。

### 5.0b 【安全·BLOCKER 级风险，必须实现 P10】回环就是唯一边界，而设备上每个 APP 都在环内
**这是原稿最大的遗漏**（审核 S7 定性：未记录、可利用、一行可修）：

| 前提（全部已核对） | 后果 |
|---|---|
| ST 默认 `enableUserAccounts: false` | `request.user.profile` 直接是冻结的 **`DEFAULT_USER`，`admin: true`** → **每个请求都是管理员** |
| `whitelistMode` 是 **IP 白名单** | 设备上所有 APP 的连接都来自 `127.0.0.1` → **对本地攻击者等于没设** |
| `/csrf-token` 挂在鉴权**之前**（`server-main.js:206-212`） | 攻击者可直接取 token |
| `/api/secrets/read` 无额外保护 | **任何持 `INTERNET` 的 APP 能读走全部 API key 与聊天** |

**这不是理论风险**：手机上装着的任何 APP 都能发 `127.0.0.1` 请求。

**处置（三选一，推荐 A）**：
| 方案 | 做法 | 代价 |
|---|---|---|
| **A（推荐）** | **随机高位端口 + 启动时生成的一次性 Bearer token**，由原生层注入；加一个小 patch 校验 `Authorization` / `?token=` | 需要 P10 补丁（约 30 行）；token 存 `files/meta/`，重启重新生成 |
| B | 启用 ST 自带的 `basicAuthMode`/`enableUserAccounts` | 改动小，但把"再登录一次"塞进"打开即用" |
| C | 接受风险，写进威胁模型 | 零成本，但**对"装着各种国产 APP 的手机"不负责**，SDS 不允许静默选 C |

**SDS 定稿：采用 A。新增补丁 P10。位置极其关键（审核 M1 修正）**：
实测中间件顺序（`server-main.js`）：
```
:104 helmet        :107 compression    :110 bodyParser
:138 cors          :142 basicAuth      :147 whitelist
:150 hostWhitelist :153 accessLogger   :156 cookieSession
:164 setUserData   :202 csrfSync       :240 webpackMiddleware
:242 express.static(public)   ← 静态资源
:245 /api/users 路由
:248 requireLoginMiddleware
```
→ **P10 必须挂在 `:104`（helmet）之前**，否则：① 静态资源（`:242`）会**先于**鉴权被服务 —— 虽然 `index.html` 本身无害，但 `public/` 下可能有用户上传内容；② `/api/users`（`:245`）在 `requireLoginMiddleware`（`:248`）**之前**。
→ 但 `:104` 之前 **`cookieSession`（:156）尚未挂载**，所以 P10 **不能依赖 `req.cookies`**。修正实现：
```js
// src/server-main.js，在 app.use(helmet(...)) 之前插入
app.use((req, res, next) => {
    const expected = process.env.ST_LOCAL_TOKEN;
    if (!expected) { return next(); }                   // 桌面/开发环境不启用

    // 原生层注入的 Bearer，或首屏 URL 上的 ?token=
    const hdr = req.headers['authorization'] || '';
    const given = hdr.startsWith('Bearer ') ? hdr.slice(7)
                : (typeof req.query.token === 'string' ? req.query.token : '');
    if (given === expected) { return next(); }

    // 同一浏览器后续请求：WebView 在首次成功加载后由原生层统一加头
    return res.status(401).type('text/plain').send('Unauthorized: missing local token');
});
```
> **关键约束（审核 N2 实测推翻了我的首选方案）**：
> 1. **不能靠 cookie**——`cookieSession` 在 `:156`，晚于本中间件（`:104`）。
> 2. **❌ 不能靠 `shouldInterceptRequest` 加请求头**：该 API 的契约是"返回一个 `WebResourceResponse`，或返回 null 交给 WebView"，它是**内容拦截器，不是请求改写器**。（实测确认：`index.html` 有 20 个 `<script>` + 28 个 `<link>` + 21 个 `<img>`，`script.js` 有 35 处 `fetch(`，全部会被 401。）
> 3. **❌ 不能靠 `WebView.loadUrl(url, extraHeaders)`**：它只作用于**那一次导航**，不覆盖 XHR/fetch、子资源、以及 `location.reload()`（而扩展重载正是 reload）。
> 4. **❌ 不能改前端**（§6.1/§13 明令 `public/` 逐字节保留）。
>
> **✅ 正确落地方案 —— N-1 已实测可行，定为最终方案（审核 N3 修正我的误判）**
>
> **⚠ 先破一个我自己的误判**：我原本把 `basicAuthMode` 判为"要再登录一次，违背打开即用"。**这是错的。** `basicAuth.js:42` 发的是 `WWW-Authenticate: Basic`，WebView 可用 `WebViewDatabase.setHttpAuthUsernamePassword(host, realm, user, pass)` **自动应答挑战，零 UI、零交互**。它**不用**用户登录。
>
> **⚠ `basicAuthMode` 有隐藏前提（`server-main.js:141`）**：
> ```js
> if (cliArgs.listen && cliArgs.basicAuthMode) { app.use(basicAuthMiddleware); }
> ```
> `default/config.yaml:6` 是 `listen: false` → **只开 `basicAuthMode` 而不开 `listen`，中间件不挂载，静默无效。**
>
> **我已经实测过这条组合（不是推断）**：
> ```yaml
> listen: true
> listenAddress: { ipv4: "127.0.0.1" }     # ← 钉死回环，不对外
> basicAuthMode: true
> basicAuthUser: { username: "tester", password: "s3cret" }
> ```
> 启动结果：`SillyTavern is listening on IPv4: 127.0.0.1:8131`，**无报错、不要求 SSL 证书**。
> 请求结果：**不带凭据 → 401；带 `Authorization: Basic …` → 200（734,837 B）**。
>
> **关于 `verifySecuritySettings` 的告警（`users.js:152-196`）**：`listen:true` 时它会打印
> *"Your current SillyTavern configuration is insecure (listening to non-localhost)"* 与
> *"per-user basic authentication is enabled, but user accounts are disabled"* 等。**这些都是 `console.warn`/`logSecurityAlert`，不是硬失败**，且对我们的配置**属于误报**（我们恰恰只听 `127.0.0.1`）。**但要接受"启动日志里会有安全告警"这一噪音**，并在日志脱敏/展示时说明。
>
> **SDS 定稿：采用 N-1。零源码改动、零前端改动、覆盖全部子请求（含 XHR/reload/子资源）。**
>
> **凭据注入：用环境变量，不写进 config.yaml（第三轮审核实测的最优解）**
> `getConfigValue` 是 **env 优先**的（`util.js:88-95`：`const envKey = keyToEnv(key); if (envKey in process.env) return process.env[envKey];`）。
> 因此直接给子进程注入两个环境变量即可，**完全不需要把明文密码写进 `config.yaml`**：
> ```kotlin
> pb.environment()["SILLYTAVERN_BASICAUTHUSER_USERNAME"] = "st"
> pb.environment()["SILLYTAVERN_BASICAUTHUSER_PASSWORD"] = randomPassword   // 每次启动重新生成
> ```
> 审核已实测：**env 里的凭据 → 200；config 里的凭据 → 401；无凭据 → 401**。确认 env 优先级真的生效。
> → **收益**：`config.yaml` 里没有明文密码，§U15（凭据写入磁盘的暴露面）**直接消失**；密码每启动轮换，不落盘。
> → **仍需**：`basicAuthMode: true` 要写进 `config.yaml`（布尔值，非敏感），且**必须 `listen: true`**（否则中间件不挂载）。
> **验收**：不带凭据请求 `GET /`、`GET /lib.js`、`GET /api/secrets/read` → 全部 **401**；WebView 内正常使用全程无感、无弹窗。
> **回退方案**（若某设备 WebView 不自动应答挑战）：本地转发端口补 `Authorization` 头（N-2）。

### 5.0c 其余入站细节
- **不要**开启 `hostWhitelist.enabled`：一旦开启，`Host: 127.0.0.1:<port>` 必须出现在 `hosts` 列表里，否则**403**。这是我们自己会踩的坑，SDS 明确规定**保持默认关闭**。
- CSRF（`csrf-sync`）在**同源**下正常工作（SPA 从 `/csrf-token` 取 token，同 origin fetch）。**扩展重载 = `location.reload()`，属同源整页刷新，token 会重新获取**，不受影响（已核实 `csrf-sync` 的 `generateToken` 会复用 session 里的 token，而 cookie-session 的密钥持久化在 `cookie-secret.txt`，重启不掉登录）。
- 必须用字面量 `127.0.0.1`（与 cookie origin 一致，避免 IPv4/IPv6 解析歧义）。

### 5.1 必需配置（缺一即功能受损）| 配置 | 不做的后果 |
|---|---|
| `onShowFileChooser` → SAF | **角色卡导入彻底失效**（ST 全靠 `<input type=file>`） |
| `onRenderProcessGone` | renderer 被系统回收时**整个 APP 崩溃** |
| `CookieManager.flush()` in `onPause` | cookie 懒写，进程被杀 → **静默退出登录** |
| `setDomStorageEnabled(true)` | localStorage 全废（扩展设置依赖） |
| `setMediaPlaybackRequiresUserGesture(false)` | TTS 全部无声（多数调用点**无 `.catch()`**，静默失败） |
| `configChanges` 含 orientation/screenSize | 旋转即重载 SPA，丢失未保存状态 |
| `networkSecurityConfig` 仅放行 `127.0.0.1` clear text | 明文全局放行 = 安全债 |

### 5.2 明确**不**做
- ❌ `WebViewAssetLoader`：它提供虚拟 origin，而**扩展是 module script，永远做 CORS 检查** → 换 origin 会让**所有扩展静默全挂**。必须走真实 `http://127.0.0.1:<port>`。
- ❌ `setSupportMultipleWindows`：ST 只有 1 处 `window.open`（内置 nanogallery2 社交分享），原地加载即可。

### 5.3 两段式启动（兑现 D13）
```
t=0      Compose 骨架屏立即显示（原生，不等任何东西）
t≈300ms  WebView 实例化（与 Node 启动并行！）
t≈1.3s   (桌面实测) Node listen 完成 → 探活成功 → WebView.loadUrl
t≈3.0-4.5s (手机估) 同上
t≈?      ST 界面真正可交互
```
- **第一段：「APP 可交互」<2s** —— 靠原生骨架屏，**成立且可验收**。
- **第二段：服务就绪** —— 桌面 **1.34s 实测**（5 次中位数）；手机 **3.0–4.5s**（×1/3 单核 + 慢存储，含无 git 的 −139ms）。**这是全文档唯一的服务就绪口径。**
- **第三段：ST 界面可交互** —— **审核 N13 实测**：前端 JS 解析不是瓶颈。实测本机 V8 parse/compile：`lib.js` 1.86MiB → **26.9ms**、`script.js` 0.47MiB → **6.1ms**、jQuery+jQueryUI → ~1ms，**合计脚本载荷 3.04MiB / 约 35ms**；手机按 1/4 单核 ≈ **140–200ms**。
  → **真正的瓶颈不是解析**，而是 **3.0MiB 的解压/传输 + 字体/CSS 阻塞 + `firstLoadInit`/`printMessages` 的实际工作**。
  → **诚实的口径：6–10s 作为"冷启上界"是合理的，但比"本地资源 + 热 WebView"的真实情况偏悲观**。验收应写成**区间 + 条件**：
  > 「冷启到原生骨架可交互 **<2s**；到服务就绪 **<4.5s**（手机）；到 ST 界面可交互 **≤10s**（冷 WebView）/ **≤6s**（热 WebView、本地资源）」
- 若要 ST 界面 <2s：需 P2（向量栈延迟加载，−483ms）+ P9（V8 snapshot，−600ms），且仍未必够。列为 M7 可选。

---

## 6. 一致性层（G3）

### 6.1 原则
上游 `src/` 与 `public/` **逐字节保留**；所有改动以补丁集在构建期应用。

> **唯一登记在册的前端例外：P7 的草稿恢复**（§3.6b）。它必须做成独立文件 `public/scripts/android-draft-recovery.js` + `index.html` 一行 `<script>`，**不得改 `script.js` 主体**，以便 rebase 上游。除此之外任何改 `public/` 的提议都必须先推翻这条。

### 6.2 补丁清单与验收

| ID | 内容 | 验收方法 |
|---|---|---|
| **P1** | 预编译 `lib.js`，运行时 `usePrebuiltLib()` 替代编译 | `GET /lib.js` 返回 200 且字节数 == 构建产物；启动无 webpack 日志 |
| **P2** | 向量栈延迟加载 | 冷启降 ~483ms；聊天不用向量功能不加载 ONNX |
| **P3** | 无 `.git` 跳过 git 探测（含 `command-exists`） | 冷启降 ~139ms；无 `/bin/sh -c command -v git` 子进程 |
| **P4** | `statsInit` 懒加载 | `stats.json` 缺失时首启降 ~256ms |
| **P5** | 扩展 update/branches/switch/version 走可插拔 git | 5 处（`extensions.js:42,194,241,290,406`）全部打通；**注意 `isUpToDate` 语义不能改等价** |
| **P6** | 聊天保存 A+B1+C | 每轮写量 33MiB → ~17MiB；`.jsonl` 字节格式不变（用 fixture 比对） |
| **P7** | 生成草稿 + 恢复（§3.6b，注意 `mesId >= chat.length` 判定） | 生成中 `kill -9` → 重启可见部分文本并可继续 |
| **P8** | 平台默认配置（浏览器启动关、TMPDIR、LANG） | 启动日志无 `Launching in a browser` |
| **P10** | **本地鉴权 = ST 自带 `basicAuthMode` + `listen:true` + `listenAddress:127.0.0.1` + WebView `setHttpAuthUsernamePassword`**（§5.0b，**四件组合已实测：无凭据 401 / 有凭据 200，且不要求 SSL**）。**零源码改动、零前端改动。** ~~自定义 token 中间件~~ 已否决（`shouldInterceptRequest` 不能加头） | 不带凭据请求 `/`、`/lib.js`、`/api/secrets/read` → **401**；WebView 内无感 |
| **P11** | **`PUBLIC_DIRECTORIES.backups` 惰性 getter 指向 `DATA_ROOT`** + `users.js:382` 去掉 `process.cwd()`（§3.6 M2 续） | 数据迁移备份落在 `files/data/backups/`；升级后仍在；安装目录内无怪子目录 |
| **P12** | **把真实监听端口写入 `files/meta/port`**（§8.4 N18；`--port 0` 时横幅只印配置端口） | 启动器能读到真实端口并成功 loadUrl |
| **D-P1** | `config.yaml` 原子化 + 回滚 | 写到一半 kill → 下次能启动 |
| **D-P2** | 账户表加固（§3.5 已按实测重写：**写侧原子化 + 读侧 `typeof key === 'string'` 防御 + 启动链 `.catch`**；~~`forgiveParseErrors`~~ 已证伪，不可用） | 截断 `_storage` 后重启**必须能起来**，不得出现 `listen` 永不发生 |
| **D-P3** | 父目录 fsync | — |
| **D-P4** | **启动恢复例程**（§3.3）：清 `write-file-atomic` 残留 + 断尾 jsonl 修复 + 草稿判定 + `settings/secrets` 回滚 + `config.yaml` 必备键校验 | 人工制造各类损坏后重启，逐项能被修复并写进 `recovery-report.json` |

### 6.3 P1 补丁要点（**这是最容易被坑的一个**）
```
问题: devMiddleware (webpack-serve.js:13-21) 无条件调 getPublicLibConfig()
      → 解析到 $DATA_ROOT/_webpack/<hash>/output/lib.js（编译关掉后该文件不存在）
      → res.sendFile → ENOENT → 404 → 白屏
      且 isDocker() 在 Android 恒 false，forceDist 运行时不可达

方案: usePrebuiltLib() 启动时定位预编译件，命中即 serve，未命中 next()
      找不到 → 抛错 fail-fast（绝不静默 404）
      runWebpackCompiler 改惰性 import（保住 docker/build-lib.js）

★ 打包陷阱: `/dist` 在 **三个** 忽略文件里 —— `.gitignore`、`.dockerignore`、`.npmignore`
   → 遵守它们的打包步骤会静默丢掉 lib.js → 补丁正确却白屏
   → 构建脚本必须显式 un-ignore，并断言产物里该文件存在
★ 确定性: 不要靠 mtime / 不要靠内容嗅探 → 用 BUILD.json（cacheVersion+bytes+sha256）
★ 交付形态: 补丁是 `docs/../.work/patch/p1-server-main.diff` + `p1-webpack-serve.diff`，
   已实测 `git apply --check` 对**干净上游**通过（路径为标准 `a/`·`b/` 形式）
```
实测验证：`GET /lib.js → 200`；冷启 **1,344ms**（打补丁前 15,714ms）。**注意字节数会随构建变化**（不同机器/依赖版本会产生 1,945,796 或 1,947,206 等），**验收以"200 + sha256 与 BUILD.json 一致"为准，不要写死字节数**。

### 6.3b P1 选择逻辑（**最终设计：manifest + sha256，不做内容嗅探**）

**演进过程（这段历史必须保留，否则会被"简化"回坏的版本）**：
| 版本 | 做法 | 实测结果 |
|---|---|---|
| v1 | 取 mtime 最新 | ❌ **截断的 4KB `lib.js` 因 mtime 更新而被选中**，返回 HTTP 200，**UI 白屏且日志显示成功** |
| v2 | 内容嗅探：体积下限 + webpack banner + `export{` 尾部 | ❌ **双向失败**：①「banner + 填充 + `export{a as b};`」的 300KB 假货**通过**；② 合法的 `export {`（带空格）、带 sourcemap 注释使 export 离 EOF >4KB、合法的小体积包（205KB）**全部被误拒** |
| **v3（定稿）** | **不做内容嗅探**。`dist/_webpack/BUILD.json` 是唯一事实来源，记录 `cacheVersion`/`filename`/`bytes`/`sha256`；运行时按 manifest 精确定位并校验大小 + sha256 | ✅ **本文件列 14 条，第三方复核跑到 19 条，全部通过**，见下 |

**为什么内容嗅探是错的**：它无法区分"真包"和"看起来像真包的字节"，同时把某个打包器的**具体输出形状写死**（换个 webpack 版本/配置就误拒）。而 manifest 由**同一个构建步骤**产出，天然包含身份信息。

**v3 规则**：
| 条件 | 行为 |
|---|---|
| 无 `BUILD.json` | **抛错**（不扫描、不猜） |
| manifest 无 `cacheVersion` | 抛错 |
| `cacheVersion` 含 `..` / `/` / `\` | **抛错**（防路径逃逸；manifest 来自可写的安装树） |
| **`filename` 含 `..` / `/` / `\`** | **抛错**（审核实测：不校验 `filename` 时 manifest 可指向 `../../../README.md` 等任意文件；**"目标不存在于是 ENOENT"不是防御，是运气**） |
| **解析后的绝对路径不在 `outputPath` 内** | **抛错**（`path.resolve` 后比对前缀，双保险） |
| 文件不存在 / 非普通文件 | 抛错 |
| 大小与 manifest 不符 | 抛错 |
| sha256 与 manifest 不符 | 抛错 |
| 为空文件 | 抛错 |
| manifest 有 BOM | **剥掉后正常解析**（实测 Windows/CI 会写 BOM，`JSON.parse` 会抛） |
| manifest 缺 `sha256` | 降级为"仅大小校验"并**大声警告**（不静默信任） |
| 全部通过 | 记录结果并服务 |

**14 条验收（全部实测通过）**：
| # | 输入 | 期望 | 结果 |
|---|---|---|---|
| 1 | 正确 manifest + 精确匹配的包 | OK | ✅ |
| 2 | manifest 的 sha256 指向另一个内容 | 抛错 | ✅ sha256 mismatch |
| 3 | manifest 的 bytes 不符 | 抛错 | ✅ size mismatch |
| 4 | 截断包 + manifest 称完整 | 抛错 | ✅ size mismatch |
| 5 | 无 manifest | 抛错 | ✅ |
| 6 | 有 manifest 但包不存在 | 抛错 | ✅ ENOENT |
| 7 | `cacheVersion: "../../etc"` | 抛错 | ✅ 路径逃逸被拦 |
| 8 | manifest 是坏 JSON | 抛错 | ✅ 解析失败明示 |
| 9 | 带 BOM 的正确 manifest | OK | ✅ BOM 被剥 |
| 10 | 空文件 + manifest | 抛错 | ✅ |
| 11 | **合法的小包（205KB）自带 manifest** | **OK** | ✅ **不再误拒** |
| 12 | manifest 指向其一（v3 **不扫描目录**，只按 manifest 解析） | OK | ✅ |
| 13 | dist 根不存在 | 抛错 | ✅ |
| **14** | **`filename: "../../../README.md"` 且目标文件真实存在、sha256 匹配**（审核在 22:12 前测出此例可绕过；修复后已亲手验证三种变体全部被拦） | 抛错 | ✅ 被 `unsafe filename` 结构性拦住 |

> **审核 N8 的提醒（保留）**：v3 **不再扫描 dist 目录**，因此"有多个 cache 目录时靠 manifest 消歧"这个描述是 v2 的遗产。v3 是**只按 manifest 解析**——manifest 成了单一事实来源，**没有交叉校验**：若构建残留了第二个目录而 manifest 仍指旧的，会服务旧包并打上"sha256-verified"。实践中打包只发一个目录，风险低，但**不要在文档里宣称存在目录扫描**。若要更稳，可在构建末尾**删除其它 cache 目录**。

**端到端**：真实启动 → `GET /lib.js → 200, 1,945,796 B`；`GET / → 200`；日志 `Serving prebuilt frontend library: … (1.86 MiB, sha256-verified)`。

**渲染层**：`devMiddleware` 只服务启动时校验通过的那个文件；若从未调用 `usePrebuiltLib()`（纯源码 checkout），`prebuilt === null` → `next()` 交给 `express.static`（上游原本行为）。**v1 的"防御性 fallback"死代码已删除**。

---

## 7. 扩展兼容（D10）

### 7.1 机制（实测）
| 环节 | 机制 | Android 影响 |
|---|---|---|
| 安装 | `/api/extensions/install` → git clone（isomorphic-git，**不需要真 git**） | 可用 |
| 发现 | `/api/extensions/discover` + `manifest.json` | 可用 |
| 加载 | `<script type="module" src="/scripts/extensions/<name>/<js>">` 注入 `document.body`（`extensions.js:813-841`） | **需要真实 http origin**，否则 CORS 全挂 |
| 启用/禁用 | 改 `settings.json` → `location.reload()` | 纯浏览器刷新，WebView 原生支持 |
| CSS | `<link>` 注入 | 可用 |
| CSP | **`contentSecurityPolicy: false`**（`server-main.js:104-106`） | **零限制**，第三方 API `fetch` 不受 CSP 影响 |

### 7.2 目录与升级风险（**已定稿：只支持本地扩展**）
- **本地扩展**：`files/data/<user>/extensions/` —— 在 `dataRoot` 内，**升级安全**。
- **全局扩展**：`files/st/public/scripts/extensions/third-party/` —— **在安装目录内，升级会被删**。

**服务端已经有闸门（实测 `extensions.js:94-98, 175-183`）**：
```js
const { url, global, branch } = request.body;
if (global && !request.user.profile.admin) {
    return response.status(403).send('Forbidden: No permission to install global extensions.');
}
```
→ 全局安装/更新**需要管理员权限**，且是**服务端 403 硬拦截**。

**⚠ 但我原本的落地手段（"把用户设为非 admin"）不可实现（审核 S3）**：
- `DEFAULT_USER` 是 **`Object.freeze({ ..., admin: true, ... })`**（`constants.js:54-62`），而默认 `enableUserAccounts: false` 意味着 `request.user.profile` **就是**这个冻结对象（`users.js:957-966`）→ **改不动**。
- 且 `extensions.js:357` 的 `/move` 只判 `!admin`、**没有 `global` 判断** → 变成非 admin 会**连本地扩展移动都丢掉**。

**✅ 定稿手段：保留 admin，在服务端把这几个 handler 里的 `global` 请求直接拒掉**（比 UI 层禁言更强，且不误伤本地功能）：
```js
// extensions.js 的 install / update / branches / switch / move / delete 六处，统一在最前面加：
if (request.body?.global === true) {
    return response.status(400).send('Global extensions are not supported on this build.');
}
```
> 这样「升级删掉全局扩展」从"需要迁移逻辑"降级为**服务端不可能发生**。
> **代价**：桌面端的「全局扩展」能力在 APP 上不可用，属 G3 允许的平台适配范畴，**UI 上要说明原因**。
> **验收**：`POST /api/extensions/install` 带 `global: true` → **400**；带 `global: false` → **正常安装**（本地扩展对普通用户开放，因为判据是 `global && !admin`）。

### 7.3 已知会坏的内置扩展
| 扩展 | 问题 | 处置 |
|---|---|---|
| TTS（`speechSynthesis` / `HTMLAudioElement.play()`） | 自动播放手势策略；多数调用点**无 catch** | `setMediaPlaybackRequiresUserGesture(false)` |
| quick-reply 的 `navigator.clipboard` | 需 secure context；`:199` 无 catch | 回环即 secure context，可用 |
| ONNX 多线程 | 需要 COOP/COEP，ST 不发 | 接受单线程（ST 自己已在 `transformers.js:13-14` 对 Android 强制 `numThreads=1`） |
| 依赖 `index.html` 固定容器 id 的内置扩展 | 硬编码 `#tts_container` 等（`index.html:5773-5808`），**没有"给我一个面板"的 API** | **禁止重写前端外壳**，必须原样用上游 `index.html` |

### 7.4 验收口径（D10 定稿）
一条扩展**算兼容**当且仅当：**能安装 → 能出现在扩展列表 → 能启用 → 页面重载后功能生效**。
「扩展自己调用的第三方服务是否可用」不在验收范围（与桌面一致，取决于扩展自身）。

### 7.5 ML 栈（D11：保留完整 onnxruntime-web + transformers，+112MB）

**为什么可以保留——这是 D11 成立的技术前提（必须写清，否则会被当成"打包了但跑不了"）**：

| 事实 | 证据 | 含义 |
|---|---|---|
| `sillytavern-transformers` 用的是 **`onnxruntime-web`**，不是 `onnxruntime-node` | 真实 `npm ci --omit=dev` 后 0 个 `.node`、0 个 `binding.gyp` | **是 WASM，不是原生模块** → 不需要 Android NDK 编译，不需要按 ABI 分发 |
| `tiktoken` 是纯 WASM、0 依赖 | 同上 | 同上 |
| ST **无条件**把 ONNX WASM 线程数设为 1 | `src/transformers.js:10` 调用 `configureTransformers()`，`:13-14` 设 `numThreads = 1`，注释写 *"to avoid issues on Android"* | **单线程是所有平台上的现状**（注释提到 Android 只是起因），我们**不改变这一点**，因此不引入额外降级 |
| ONNX 的 wasm 从本地 node_modules 加载，不联网 | `transformers.js:16` `wasmPaths = <serverDirectory>/node_modules/sillytavern-transformers/dist` | **离线可用**，不依赖 CDN |
| Android 的 V8 **支持 WASM** | Node 24 / WebView 均支持 | WASM 可实例化 |

**因此 D11 的实际风险不是"能不能跑"，而是"跑得有多慢"**。这一点必须诚实：
- 本地向量化（embedding）在手机上会**明显慢于桌面**，但**不会崩**。
- `numThreads = 1` 是 ST 自身的固定行为（与平台无关），我们沿用 → **与桌面完全一致**，不是降级。
- **多线程 WASM 需要 COOP/COEP 响应头，ST 明确不发**（`server-main.js` 全文无 `Cross-Origin-Opener/Embedder-Policy`）→ 多线程在本项目里**本来就不存在**，桌面也一样，**不构成"与原生不一致"**。

**体积账（D11 的代价，已计入 §7）**：`onnxruntime-web` 65MB + `sillytavern-transformers` 47MB，二者有 **37MB wasm 重复**。
> **可选优化**：`transformers.js:16` 只从 `sillytavern-transformers/dist` 取 wasm，理论上可去掉 `onnxruntime-web` 里的重复份 37MB。**但这属于裁剪，会破坏"与上游一致"，D11 明确不砍** → 记为**可选**（M7 之后），不进入主线。

**验收（M5 的一部分）**：
- [ ] 在设备上启用内置 `vectors` 扩展 → 建索引不抛错（速度慢可接受）
- [ ] `expressions` / `caption` 扩展能加载（它们依赖 transformers）
- [ ] 确认 `numThreads === 1`（这是 ST 的固定行为，**不是我们加的**）——记录实际值即可
- [ ] 确认 ONNX 的 wasm 从本地 node_modules 加载、**无外部 CDN 请求**（断网可跑）
- [ ] **不要求**手机端 embedding 速度接近桌面——这不是 G3 的验收项

---

## 8. 首启、升级与迁移

### 8.1 首启流程
```
0. ★ 先建目录（否则 --configPath 会 ENOENT → exit(1)，审核 N10）
   mkdir -p files/data files/data/default-user files/meta files/logs
1. 校验 files/meta/version.json vs APK buildNumber
2. 若需解压:
   a. 检查可用空间 ≥ 解压后大小 × 1.2
   b. 流式 tar 解压 assets/st.tar → files/st/   （2万文件；递归复制会栈溢出，必须迭代）
   c. 断言 files/st/dist/_webpack/**/output/lib.js 存在 ★
   d. 写 version.json（原子）
3. 确保 files/data/default-user/ 结构存在（不覆盖已有）
4. 分配端口（见 8.4）
5. 启动 Node → 探活 → READY → WebView
```

### 8.2 升级
- **只替换 `files/st/`，绝不触碰 `files/data/`**。
- 若 `data/` 内 schema 需迁移 → 走 ST 自己的迁移路径（`migrateSystemPrompts` 等）。
- `version.json` 用**单调递增 build number**，不用语义版本比较。
- **降级**：buildNumber 变小 → 视为用户主动降级 → **保留 `files/st/`**（不重解压），仅提示「版本已回退」。

**⚠ 升级的原子性（原稿遗漏，必须实现）**：解压到 `files/st/` 是**非原子**的——中途被杀会留下**半新半旧的安装目录**，ST 起来会报错甚至崩。正确做法：
```
1. 解压到 files/st.new/ （全新目录）
2. 断言完整性：server.js 存在 + dist/_webpack/**/output/lib.js 存在 + 关键文件存在
3. 原子切换：mv files/st → files/st.old ; mv files/st.new → files/st
   （同分区 rename 是原子的；两步之间被杀 → 启动时发现 st 缺失但 st.old 存在 → 回滚）
4. 启动成功后异步删除 files/st.old
```
启动自检：
```kotlin
if (!stDir.exists() && stOldDir.exists()) { rename(stOldDir, stDir) }   // 回滚
if (stNewDir.exists()) { delete(stNewDir) }                            // 清理半成品
```
**同理，§8.3 的数据导入也必须"解压到临时目录 → 校验 → 原子 rename 替换"，不能就地解压覆盖。**

### 8.3 数据导入（D16）
- 接受：ST 原生备份 zip、`.tar`/`.tar.gz`、含 `config.yaml`+`data/` 的目录（SAF 选入）。
- 流程：选文件 → **先自动备份现有 `data/`** → 解压到临时目录 → 校验结构 → 原子替换 → 重启服务。
- **导入前必须提示**：「将覆盖当前所有聊天与角色」。

### 8.4 端口分配

**⚠ N18（第二轮审核实测，BLOCKER 级）：`--port 0` 拿不到真实端口**
我原写「`--port 0` 让内核选端口，再从启动日志读回」。**实测推翻了它**：
```
SillyTavern is listening on IPv4: 127.0.0.1:0
Go to: http://127.0.0.1:0/ to open SillyTavern
```
原因（已读源码）：横幅用的是 `cliArgs.getIPv4ListenUrl().host`（`server-main.js:421-433`），即**配置里的端口**，不是实际绑定的端口；`ServerStartup.start()` 只返回失败标志（`server-startup.js:325`），**没有任何路径把 `server.address().port` 暴露出来**。
→ **启动器无法从日志或返回值得知真实端口。**

**✅ 正确做法：新增小补丁 P12，把真实端口写出来**

> **⚠ 审核 N19 抓到的实现缺陷**：我第一版 P12 片段用了 `path` 和 `writeFileAtomic`，但 `server-startup.js` 的导入只有
> `https` / `http` / `fs` / `{ color, urlHostnameToIPv6, getHasIP }`（见 `:1-4`）——**没有 `path`，也没有 `writeFileAtomic`**。
> 照抄会在 `listening` 回调里抛 `ReferenceError`，而那正好在 `resolve()` 之前 → **服务永不 resolve**。这就是"看起来对、跑不通"的典型。

**P12 最终代码（只用已导入的 `fs`，且覆盖 HTTP 与 HTTPS 两个 listen 点）**
> **⚠ 第三轮第二个残留**：P12 必须同时加到 `#createHttpServer` **和** `#createHttpsServer`（`server-startup.js:285` 与 `:308` 各有一个 `listening` 回调）。只改前者时，一旦启用 SSL 方案就拿不到端口。

```js
// src/server-startup.js
// [ANDROID-PORT P12] --port 0 时横幅只打印配置端口（server-main.js:421-433 用的是 cliArgs 的 URL），
// 启动器无法得知真实端口。把 server.address().port 写到固定路径，供原生层读取。
// ★ HTTP 与 HTTPS 两处 listening 回调都要加（:285 / :308）。
// ★ recordListeningPort 必须**声明在各自的 new Promise((resolve, reject) => { … }) 执行器内部**，
//   因为 resolve 是每个 Promise 自己的，不是模块作用域变量。
const recordListeningPort = () => {
    try {
        const actual = server.address();
        const metaDir = path.join(globalThis.DATA_ROOT, '..', 'meta');
        fs.mkdirSync(metaDir, { recursive: true });
        fs.writeFileSync(path.join(metaDir, 'port'), String(actual.port), 'utf8');
        console.log(`[P12] listening on actual port ${actual.port}`);
    } catch (e) {
        console.error('[P12] failed to record listening port:', e.message);
    } finally {
        resolve();     // ★ 无论记录成功与否都必须 resolve，否则服务挂死
    }
};
server.on('listening', recordListeningPort);
```
**P12 必须同时补的 import**（`server-startup.js` 顶部）：
```js
import path from 'node:path';
```
> 用 `fs.writeFileSync` 而非 `writeFileAtomic`：写的是**一个几字节的端口号**，且下游会校验内容；不引入新依赖更安全。**`finally { resolve() }` 是关键**——端口记录失败绝不能导致服务不启动。

**P12 机制已单独证明可行**（不依赖 ST）：
```js
// 实测：listen({host:'127.0.0.1', port:0}) 后，在 'listening' 回调里
server.address()  →  { port: 10345, family: 'IPv4', address: '127.0.0.1' }
```
→ 请求端口 0 时，`server.address().port` **确实返回内核分配的真实端口（>0）**。所以 P12 的取数方式是成立的；只是 ST 自己的横幅没有用它（`server-main.js:421-433` 用的是配置值）。
```kotlin
// 原生侧：等文件出现（有超时），读真实端口
val portFile = File(filesDir, "meta/port")
val port = waitForFile(portFile, 30_000)?.readText()?.trim()?.toIntOrNull()
    ?: failToErrorPage("server did not report a listening port")
```
> **为什么用文件而不是解析 stdout**：stdout 是流式的、可能被截断/缓冲，且 `console.log` 有颜色转义；文件是原子的、可轮询的、不依赖日志格式。
> **`--port 0` 仍然保留**，因为它让内核保证不冲突（比 uid 派生可靠）。**只是端口发现方式改为 P12。**
> **回退**：若不想加 P12，就固定一个高位端口（如 `20000 + (pid % 5000)`）**并接受偶发冲突**——冲突会被 ST 的 `EADDRINUSE` → `exit(1)` 捕获，再由退避重试换端口。**但不推荐，因为它把"确定性"换成了"重试"**。

**为什么不再用 uid 派生（原方案已废弃）**：Android `PER_USER_RANGE` 是 100000，`uid % 1000` 对不同 profile **相同**、且会**混叠同 profile 内不同应用**——靠运气避开冲突，不是靠构造。

### 8.4b 跨 profile（Work Profile）
`android:sharedUserId` **本项目不使用**（已废弃），所以不受其影响。
两个 profile 各自有**独立的 `files/`**，但**共享同一网络栈**（Android 不给每个 user 独立 netns）。
由于最终方案是 **P12 写真实端口 + `--port 0` 让内核分配**，两个 profile 会各自拿到不同端口，**按构造不冲突**（不再依赖任何 uid 派生公式）。

---

## 9. 可观测性

### 9.1 日志
| 项 | 规格 |
|---|---|
| 位置 | `files/logs/st-YYYYMMDD.log`，滚动保留 7 天 |
| 来源 | 子进程 stdout/stderr + 启动器自身事件 |
| 大小上限 | 单文件 5MB |
| **脱敏** | 导出前必过：`sk-*`、`Bearer *`、`api_key`/`token`/`password` 字段值、URL query 中的 key |
| 导出 | 一键打包 → SAF 保存；同时附 `version.json` + 环境快照（ABI/API/WebView 版本/RAM/可用空间） |

### 9.2 崩溃上报字段
`buildNumber` / `appVersion` / `ST version` / `state` / `exitCode` / `stderrTail(200行, 脱敏)` / `recoveryReport` / `deviceInfo`

---

## 10. 内存与性能预算

| 项 | 预算 | 依据 |
|---|---|---|
| Node 空闲 RSS | **192 MiB** | 实测 |
| 聊天后稳态 RSS | **300–400 MiB**（平台期，非泄漏） | 实测 10 次保存 → 418MiB，`--max-old-space-size=192` 时平台 ~300MiB |
| 单次保存峰值增量 | +33 MiB（8.33MiB 聊天） | 实测 |
| 冷启（桌面） | 1.34s | 实测 |
| 冷启→服务就绪（手机，估） | **3.0–4.5s** | ×1/3 单核 + 慢存储；与 §5.3 一致 |
| 冷启→ST 界面可交互（手机） | **≤10s（冷 WebView）/ ≤6s（热）** | 前端解析仅 ~140–200ms，主要成本是 3MiB 解压/传输与首屏工作 |
| 冷启固定成本 | 1.13s（模块图 836ms + git 139ms + Node 启动 145ms） | 实测，**不可约** |
| APK | 160–220MB | 估算（`libnode.so` 111.8MB → deflate 32%） |
| 首启磁盘 | ~442MB × 1.2 余量 | 估算 |

> `--max-old-space-size` **不等于** RSS 上限（实测 cap=192 时 RSS 仍 ~300MiB）。**不要用「设备RAM 40%」这类公式**；先真机测峰值，再留 1.5–2× 余量。

---

## 11. 测试与验收

### 11.0 验收表可信度规则（审核提出的流程问题，必须遵守）
三轮审核共发现 **7 次**"文档先写了 ✅ 实测通过 / 给出了能跑通的代码，实际并不成立"。**这不是笔误，是流程缺陷。** 因此规定：

> **任何标 ✅ 的验收行，必须同时给出「可复现命令 + 该命令的原始输出片段」。**
> 没有命令与输出的 ✅ 一律视为**未验证**，下游不得据此推进。
>
> **任何代码片段，必须注明它是"已运行验证"还是"伪代码"。**
> 尚未运行的片段一律标注 `// ⚠ PSEUDOCODE — 未运行`。第三轮实测：我在响应审核意见时新写的 3 个片段里有 2 个跑不通（P12 v1 缺 import、P7 v1 用错重绘 API），**都是"看起来对"**。

自检清单（每个里程碑结束前跑）：
- [ ] 文档里每个 ✅ 能否在 5 分钟内被第三方重跑出来？
- [ ] 文档描述的防护，在**当前**代码里 grep 得到吗？（不是"我刚改过所以应该有"）
- [ ] 有没有把"计划要做"写成"已经做了"？
- [ ] 每个代码片段的每个 `import`，在目标文件里真的存在吗？

### 11.1 G2 门禁：kill -9 压测（D15）
**可执行性说明（重要）**：`adb shell` 以 `shell` 用户运行，**默认无法 kill 其他 APP 的子进程**（不同 uid）。因此压测**不能**用 `adb shell kill -9 <pid>`。三种可行机制，按推荐顺序：

| 机制 | 做法 | 代价 |
|---|---|---|
| **A（推荐）** | APP 内置一个 **debug-only 的 `ACTION_KILL_NODE` 广播接收器**（仅 `debuggable` 构建启用），由测试脚本 `adb shell am broadcast` 触发，用 `Process.destroyForcibly()` 自杀子进程 | 需要 debug 构建；但**真实模拟 SIGKILL**、无需 root、可在模拟器跑 |
| B | 用 `run-as <pkg> kill -9 <pid>` | 仅 debuggable 有效；部分 ROM 限制 `run-as` |
| C | 直接 `adb shell am force-stop <pkg>` | 杀的是整个 APP，不是只杀 Node；测的是「整进程被杀」而非「子进程崩溃」 |

**测试用例（用机制 A）**：
```
for i in 1..200:
   随机时机 ∈ {启动中, 保存中(保存请求发出后), 生成中, 空闲}
   adb shell am broadcast -a com.example.st.DEBUG_KILL_NODE
   重启 → 断言:
     a. 服务能起来
     b. 每份聊天 .jsonl 可解析（末行完整）
     c. 消息数 ≥ 上次确认保存的数量
     d. config.yaml 可解析
     e. 账户表可读
   任一失败 → 保存现场（data 快照 + 日志）并 FAIL
```
**另需单独跑一遍机制 C**（整 APP 被 force-stop），验证「用户从设置里强行停止」这条最坏路径下，L2/L4 恢复例程仍能救回数据。
**这是发版门禁，不可跳过。**

### 11.2 其余验收
| 目标 | 验收方法 |
|---|---|
| G1 | 全新模拟器装 APK → 不联网 → 3 分钟内可发第一条消息 |
| G3 | 桌面/手机对同一 ST 版本做 30 项功能清单逐项截图比对 |
| G4 | 补丁集在 `git apply` 到干净上游时零冲突或冲突可控 |
| G5 | 第三方按 README 从零构建出同一 APK（哈希可不同，功能一致） |

### 11.3 M0 出口（**必须真机，不能纸上过**）

> **当前真实进度（2026-11-08 实测更新）：构建产物已产出并通过全部静态门禁；真机项仍未闭合。**

**✅ 已关闭（有实测证据）**
| 项 | 证据 |
|---|---|
| **CI 产出可执行 Node** | run `42418429182` 全 13 步 success；产物 35.7MB zip |
| **门禁① 可执行文件** | `llvm-readelf -h`：`e_entry=0x3898000`（≠0）、`PT_INTERP=/system/bin/linker64` → **真 PIE 可执行文件**，与 fogtape 的 `e_entry=0x0` 有本质区别 |
| **门禁② 16KB 对齐** | 4 个 `PT_LOAD` 全部 `p_align=0x4000` 且同余 0（NDK r28c 零 flag） |
| **门禁③ full ICU** | **8,724 个 ICU 符号**，含 `icu_78` 命名空间、`unorm2_`×22（`String.normalize` 依赖）、`icudt` 数据块 |
| **产物完整性** | 下载后自算 SHA256 = `0cdc2c43…09356`，与仓库 `SHA256SUMS` **逐字节一致** |
| **依赖库** | `DT_NEEDED` = `libm/libdl/liblog/libc++_shared/libc.so`，与 §2.1 预测**完全一致** |
| **构建可复现** | 4 个构建失败已固化为补丁（§2.2b），单次全绿 151.6 分钟 |

**❌ 仍未闭合（真机/arm64 相关）**
- [ ] **arm64 二进制在真机上跑起来**（**关键：从未发生**。本机 x86_64 上 QEMU2 明确不支持 arm64 镜像，实测报 `Avd's CPU Architecture 'arm64' is not supported by the QEMU2 emulator on x86_64 host`）
- [ ] `String.normalize` / `Intl.Collator` **在设备上**实际可用（符号存在 ≠ 数据能加载）
- [ ] **Node 进程真的启动**（V8 初始化 / JIT / 快照加载 / 多线程 / 长生命周期）—— 已实测"PIE 能 exec"（5.5KB 探针）与"Node 能跑"是**两件事**
- [ ] `--port 0` + P12 端口发现
- [ ] 16KB **真机**（16KB 页设备）上不崩 —— 本机模拟器是 **4KB 页**（`getconf PAGE_SIZE` = 4096），无法验证
- [ ] `nodeBin.canExecute()` 在真机上 spawn 前断言
- [ ] OEM 是否有额外 exec 阻断（U4）
- [ ] **量产 `user` 版 ROM**（本机是 `ro.debuggable=1` 的 userdebug 镜像，比量产宽松）

**（原本列在此处的两项已移到上方"已关闭"表：`nativeLibraryDir` exec 可行性、`LD_LIBRARY_PATH` 必要性。）**

---

## 12. 风险与未验证前提（**SDS 必须显式列出**）

| # | 未验证项 | 影响 | 关闭时机 |
|---|---|---|---|
| U1 | ~~自建可执行 Node 从未真正构建过~~ | ✅ **已关闭**：run 42418429182 产出 90MB 可执行文件，`e_entry=0x3898000` + `PT_INTERP` + 16KB 对齐 + 8,724 ICU 符号，SHA256 与仓库一致 | 已关闭 |
| U2 | `full-icu` 交叉构建时 host toolset 是否置位（**已知必须自己设 `CC_host`**，见 §2.1） | 登录崩 / 构建失败 | M0（CI 门禁③④） |
| U3 | 16KB 对齐（NDK r28+ 默认；r27 需双 flag） | 装不上/崩 | M0 |
| U4 | OEM（MIUI/ColorOS）是否额外阻止 exec 提取的 `.so` | 部分设备不可用 | M0 真机 |
| U5 | API 26 老设备的 WebView CSS（`color-mix`/`oklch`） | 界面错乱 | M2 |
| U6 | 本机无 Android SDK/Gradle | 无法本地构建 | M0 前装 |
| **U7** | **P10 鉴权中间件是否与 CSRF / 静态路由冲突**（`/csrf-token` 在鉴权前挂载） | 安全洞 | M2 |
| **U8** | **P11 后静态资源路由是否跟着指向新路径** | 图片/音效 404 | M3 |
| **U9** | **`extractNativeLibs`/`useLegacyPackaging` 在各 AGP 版本的实际行为** + **可执行位是否被 ROM 保留** | M0 `ENOENT`/`EACCES` | M0（最先验证） |
| **U10** | **`write-file-atomic` 临时文件名的精确模式**（决定恢复例程第 1 步的匹配规则；审核实测是 `<target>.<murmurhash>`，不是 `*.tmp`） | 残留清理失效 | M3 |
| **U11** | **`--port 0` 的真实端口暴露**（已实测：横幅只印 `:0`）→ 需 P12 写文件 | 启动器拿不到端口 | ✅ 已定方案 P12，M1 验证 |
| **U12** | **~~`listen: true` + `listenAddress: 127.0.0.1` 是否触发 SSL/whitelist 强制~~** | ✅ **已实测关闭**：启动无错、不要求证书、401/200 行为正确（见 §5.0b） | 已关闭 |
| **U13** | **`basicAuthMode` 在 `listen:false` 时不挂载**（已核实 `:141`）→ 必须 `listen:true` | 空鉴权 | ✅ 已在设计里固化 |
| **U14** | **`setHttpAuthUsernamePassword` 在各 OEM WebView 上是否都自动应答挑战**（不回弹窗） | 用户看到登录框 | M2 真机 |
| **U15** | ~~明文凭据存在 `files/data/config.yaml` 里的暴露面~~ | ✅ **已消除**：改用 `SILLYTAVERN_BASICAUTHUSER_*` 环境变量（`util.js:88-95` env 优先），密码不落盘、每次启动轮换 | 已关闭 |
| **U16** | **ICU 门禁在 CI 里只是 WARN，不是硬失败**（第 5 轮审核实测：该分支无 `exit 1`） | 可能产出"能启动、不能登录"的包 | **M0 前必须改成硬失败** |
| **U17** | **`tools/` 与 `.github/workflows/` 尚未进入仓库根**（当前 workflow 与脚本在 `.work/ci/`，靠手工拷贝运行） | G4/G5「可复现构建」不成立 | M0 |
| **U18** | ~~构建从未完整绿灯一次~~ | ✅ **已关闭**：run `42418429182` 151.6 分钟、全 13 步 success，产物 90MB | 已关闭 |

---

## 13. 附录：不做清单（防止范围蔓延）
- ❌ 追加式聊天存储（改格式代价 8/10，二期）
- ❌ JNI 内嵌 `node::Start()`（`node::Stop` 不可重启；`SafeGetenv` 在 zygote 环境静默失效）
- ❌ WebViewAssetLoader / 虚拟 origin（module script CORS 会杀死所有扩展）
- ❌ 重写前端外壳（内置扩展依赖 `index.html` 固定容器 id）
- ❌ 全局扩展（升级会删；只支持本地）
- ❌ 上 Google Play（NSFW + AGPL + specialUse 审核）
- ❌ 本地跑 Stable Diffusion / 本地大模型
- ❌ `--shared` 构建（产出 `.so` 不能 exec）
- ❌ 靠 mtime 选预编译件（实测会选到截断文件并返回 200 白屏）
- ❌ `--disableCsrf`（同源下不需要，且会降低安全性）
- ❌ 开启 `hostWhitelist.enabled`（会让回环 403）

### 13b. 本地扩展不需要 admin（已核实，支撑 §7.2 决策）
```js
// src/endpoints/extensions.js:96-99
if (global && !request.user.profile.admin) {
    return response.status(403).send('Forbidden: No permission to install global extensions.');
}
```
→ 判据是 **`global && !admin`**，**纯本地安装（`global: false`）对普通用户开放**。
→ 所以 §7.2「把用户设为非 admin 以禁掉全局扩展」**不会误伤本地扩展安装**。（M5 必测项可降级为验证项。）

---

*本 SDS 已过 5 轮独立审核（计划 2 轮 + SDS 3 轮以上）。第 5 轮基于**真实 Android 构建证据**，补齐了 §2.2b 的 4 个构建失败记录。*

---

## 14. 审核记录（被推翻的设计 — 必读，防止重犯）

本 SDS 经历两轮对抗式审核。以下是**被证据推翻**的设计，逐条记录是为了让后来者（或未来的我）不要再把它们"改回去"。

| # | 我原本的设计 | 被什么推翻 | 现方案 |
|---|---|---|---|
| 1 | P1 取 **mtime 最新**的预编译件 | 实测：截断 4KB 文件 mtime 更新 → 被选中 → **HTTP 200 + 白屏** | manifest + sha256 |
| 2 | P1 用**内容嗅探**（体积下限 + banner + `export{`） | 实测双向失败：300KB 假货**通过**；合法的 `export {`/sourcemap/小包**误拒** | **不做嗅探**，只按 manifest 校验身份 |
| 3 | D-P2 加 `forgiveParseErrors:true` + `writeQueueIntervalMs:50` | 实测：前者让坏记录变成 `{}` → `users.js:673` **TypeError** → 进程**永不 listen**；后者**根本无 1s 窗口**（实测 0–1ms 落盘） | 写侧原子化 + 读侧 `typeof key === 'string'` + 启动链 `.catch` |
| 4 | G2 草稿恢复判定 `mesId === chat.length-1` | 代码实证：生成中的消息**已在内存数组里**，磁盘没有 → 索引恰好**等于** `length`；按原判据草稿会被当陈旧删掉 | 比**内容长度**，不比索引存在性 |
| 5 | P11 在 `constants.js` 顶层读 `globalThis.DATA_ROOT` | 实测复现：`constants.js` 在 `DATA_ROOT` 赋值**之前**被求值（探针输出 `undefined`）→ `path.join(undefined)` 抛错，31 个 import 者全挂 | **惰性 getter** + 同时修 `users.js:382` 的 `path.join(process.cwd(), …)` |
| 6 | P10 用 `shouldInterceptRequest` 给 WebView 所有请求加 token 头 | 文档实证：该 API 是**内容拦截器**，契约里没有"改写请求头"；能加头的 `loadUrl(url, headers)` 只作用**一次导航** | 改判：`basicAuthMode` + `setHttpAuthUsernamePassword`（或本地转发），**且已知它需要 `listen:true`** |
| 7 | "图片/音频上传会写进安装目录" | 逐写位点核查：`public/img`、`public/sounds` **零写入位点**，上传都走 `DATA_ROOT` | P11 范围收窄到 `backups` 一处 |
| 8 | `--configPath` 搬到 `files/data/config.yaml` | 实测：父目录不存在时 `configInit` **无 mkdirSync** → `ENOENT` → `exit(1)`；Android 首启 `files/data` 本来就不存在 | 启动器**先 `mkdir -p`** 再 exec |
| 9 | 端口 `20000 + (uid % 1000) * 10` | `PER_USER_RANGE` 为 100000，`uid % 1000` 对多 profile **相同**，且会**混叠同 profile 内不同应用** | `--port 0` 交给内核 + 从日志读回真实端口 |
| 10 | `CSP 关闭` ⇒ 扩展 `fetch` 不受限 | 这条**是对的**（已核实 `server-main.js:105`），但真正的制约是 **module script 的 CORS 与 origin** | 必须走真实 `http://127.0.0.1` origin |
| 11 | `--port 0` + **从启动日志读回真实端口** | 实测：横幅 `listening on IPv4: 127.0.0.1:0`，因为横幅用的是**配置端口**（`server-main.js:421-433`），`start()` 不返回端口 | **P12：把 `server.address().port` 写入 `files/meta/port`** |
| 12 | 「图片/音频上传写安装目录」的 P11 范围 | 逐个写位点核查后收窄 | P11 只处理 `backups` 一处 |
| 13 | P12 片段用 `path` + `writeFileAtomic` | 审核 N19：`server-startup.js` **只 import 了** `https`/`http`/`fs`/`{color,…}`，没有 `path`/`writeFileAtomic` → `ReferenceError` 且在 `resolve()` 之前 → **服务永不 resolve** | 只用 `fs`，补 `import path`，**`finally { resolve() }`** |
| 15 | P7 用 `eventSource.emit(MESSAGE_RECEIVED)` 触发重绘 | 第三轮实测：该事件的监听者只有 `vectors/index.js:2089` 与 `PromptManager.js:760`，**`script.js` 注册 0 个，都不碰 `.mes_text`** → 改内存、弹提示，**正文永不显示** | 改用 `updateMessageBlock()`（`script.js:2033`）/ `addOneMessage(…, {forceId})`（`:2551`） |
| 16 | P1 差异文件（`.diff`）乱码 | 第三轮实测：8 行注释、104 个 CJK 替换字符；`git apply` 后哈希 ≠ 验收文件 | 用 node 以 UTF-8 重新生成 + `.gitattributes`；**已实测 apply 后与验收文件一致**（仅 EOL） |

**保留下来的判断（经审核确认正确，勿再质疑）**：
- exec 模型可行：SELinux `apk_data_file` 在 Android 11→16 **始终保留 `execute`**（从 W^X neverallow 中豁免）。
- `android-configure` 要求**恰好 3 个位置参数**，且**不读** `ANDROID_NDK_HOME`/`ANDROID_API`。
- 不传 `--shared` 产出可执行文件（`--shared` 默认 `None`）。
- `LD_LIBRARY_PATH` **必需**（动态链接器不会在可执行文件所在目录找 `DT_NEEDED`）。
- `node::Start()` 不可重启、`SafeGetenv` 在 zygote 进程静默失效 → **exec 优于 JNI 内嵌**。
- 聊天保存**无隐藏副作用**（`trySaveChat` 只写主文件 + 排备份），跳过未变更写安全；备份**只写一次不改**，硬链接安全。
- `csrf-sync` 能跨 `location.reload()`（session token 复用，密钥持久化在 `cookie-secret.txt`）。
