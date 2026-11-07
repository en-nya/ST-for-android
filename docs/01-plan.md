# SillyTavern → Android 移植方案（定稿候选 v1.0）

> 本文档替代 v0.1 / v0.2。三条研究线（Node-on-Android、ST 源码审计、启动与写入实测）的证据已并入。
> 证据等级：**[实测]** 本机跑过或读到源码行 ｜ **[文档]** 一手官方文档 ｜ **[推断]** 未直接验证
> **目标**：装成一个安卓 APP，打开即用，不装 Termux、不要 root；崩溃 / 划掉 / 断电不丢数据；内容与桌面网页版一致。

---

## 0. 决策记录（已由用户拍板，不再讨论）

| # | 决策 | 结论 |
|---|---|---|
| D1 | 战略 | **从 0 自建**，不 fork 现有实现，但要借鉴并超越它们 |
| D2 | 运行时 | **stock Node 交叉编译成 Android 可执行文件**（**必须不传 `--shared`**），重命名为 `lib*.so` 塞 `jniLibs`，`ProcessBuilder` exec。~~用 fogtape 预编译件作起跑~~ 已否决（见 D5） |
| D3 | Node 版本 | **Node 24 LTS + full ICU**（不是 Node 20；ICU 才是硬需求） |
| D4 | 构建主机 | **GitHub Actions (ubuntu)** 交叉编译，本机不装 WSL |
| D5 | 起跑方式 | ~~先用 fogtape 预编译件跑通~~ → **修正**：fogtape 是 `--shared` 的共享库（实测 `e_entry=0x0`），**不能 exec**。起跑改用**任一真实可执行文件**（Termux `node` 或 CI 自建产物）；fogtape 仅作 `dlopen` 路线备选 |
| D6 | targetSdk / minSdk | **36 / 26** |
| D7 | ABI | 发布只给 **arm64-v8a**；x86_64 仅调试版 |
| D8 | 数据位置 | **应用内部私有目录** + SAF 手动导出/导入 |
| D9 | 划掉进程 | **保活**：前台服务 + 关电池优化引导；通知默认开可关 |
| D10 | 扩展 | **必须像桌面一样装任意第三方扩展**；验收 = 安装+启用+动态加载+重载生效全通 |
| D11 | ML 栈 | **保留完整**（onnxruntime-web + transformers，+112MB），与 D10 一致 |
| D12 | 首启 | APK 内压缩打包（~120–160MB），首启解压 |
| D13 | 冷启动 | 拆两段：**原生壳 UI 可交互 <2s**；**ST 界面**（需服务就绪）目标 <6s 冷启（实测桌面 1.34s，手机 3.5–5.5s）。**不承诺「ST 界面 <2s」** |
| D14 | 生成持久化 | **做**：生成中定期落草稿，杀后重启可恢复/续写 |
| D15 | 验收门禁 | **做 kill -9 随机压测 + 重启恢复断言**，纳入 CI |
| D16 | 导入 | 吃 ST 原生备份 zip + 原始 `config.yaml`/`data` 目录 |
| D17 | 日志 | 内置滚动日志 + 一键导出**脱敏**日志 |
| D18 | 上游形态 | **完整保留上游源码 + 构建期应用补丁集**（不 vendor 修改） |
| D19 | 分发 | 自签 APK + GitHub Release，改名避商标，全量源码开源（AGPL-3.0） |

---

## 1. 事实基线（全部已核验）

### 1.1 SillyTavern 侧
| 项 | 值 | 证据 |
|---|---|---|
| 版本 | **1.19.0**（tag，2026-09-14） | GitHub Releases API **[实测]** |
| 许可 | **AGPL-3.0** | LICENSE **[实测]** |
| 原生依赖 | **零** — 真实 `npm ci --omit=dev` 产出 0 个 `.node`、0 个 `binding.gyp`，20068 文件 / 280MB | 实跑 **[实测]** |
| tiktoken | 纯 WASM，0 依赖 | **[实测]** |
| 向量化 | `sillytavern-transformers` → `onnxruntime-**web**`（WASM） | **[实测]** |
| `child_process` | ST 自身 **0 处** | grep **[实测]** |
| `worker_threads` | **0 处** | grep **[实测]** |
| 前端 | 无 SW / 无 File System Access / 无 `getUserMedia` | 336 文件全扫 **[实测]** |
| 移动端 | 自带 656 行 `mobile-styles.css` | **[实测]** |
| 网络默认 | `127.0.0.1:8000`，白名单含回环，cookie 无 `secure` | **[实测]** |
| 离线 | 首屏无 CDN、无遥测、启动无网络调用 | **[实测]** |

### 1.2 **Node 版本的真实约束（关键修正）**
ST 1.19.0 **没有使用任何 Node 20 专属 API**：`import.meta.dirname` 两处都写了 `?? fileURLToPath(...)` 兜底；`node:sqlite`/`fs.glob`/`Promise.withResolvers`/`Array.fromAsync`/`Object.groupBy`/`crypto.hash` **全部 0 命中**；`.toSorted()` 的 9 处全在 `public/`（那是 WebView 的引擎）。
依赖里唯一声明 `engines.node >= 20` 的是 `host-validation-middleware`，而它是 `^18.0.0 || >=20.0.0`。

**但真正的硬需求是 ICU**：`src/users.js:645` 的登录哈希用 `crypto.scryptSync(password.normalize(), …)`，`String.normalize()` 需要 ICU；`src/util.js:706`、`stable-diffusion.js:26` 用 `Intl.Collator`。
→ **`--with-intl=none` 的构建会让每次登录抛 TypeError。** 这是 nodejs-mobile 默认配置，也是它跑不了 ST 的真因。

**结论：`engines.node >= 20` 是政策声明不是能力要求；真正的门槛是 full ICU。** 我们仍选 Node 24 LTS（生命周期 + 已有预热产物）。

**已亲自复核的 ICU 依赖点**（不是转述研究）：
| 位置 | 代码 | 无 ICU 时 |
|---|---|---|
| `src/users.js:645` | `crypto.scryptSync(password.normalize(), salt, 64)` | **每次登录抛 TypeError** |
| `public/scripts/stream-fadein.js:25` | `new Intl.Segmenter('en-US', …)` | 流式淡入功能异常（浏览器侧，与 Node ICU 无关） |
| `src/util.js:706`、`stable-diffusion.js:26` | `Intl.Collator` | 排序/模糊匹配退化（**待复核，grep 未在 src 命中，可能为旧版本行号**） |

> 注：`Intl.Collator` 的两处行号来自研究报告，我在 `src/` 下 grep `new Intl.` 只命中浏览器侧一处，所以**服务端 ICU 的硬证据是 `users.js:645` 的 `String.normalize`**——这一条已足够强制 full ICU。

### 1.3 本机环境
Node v24.14.0 / npm 11.12.0 / JDK 21 Zulu / Gradle 8.8 缓存 / git 2.54 / Python 3.11.9 / ninja 1.13.1 / cmake 4.1.2。
**无 WSL、无 Docker、无 Android SDK/NDK/adb/emulator。** H 盘 469GB 可用。

---

## 2. 四个必须修的上游缺陷

**这四个都不是「安卓适配」，而是「桌面端碰巧没事」的缺陷。它们是本项目工程的真实工作量。**

### 2.1 【阻断】每次启动强制跑 webpack 编译
`src/server-main.js:353-355` 在 `app.listen` **之前** `await webpackMiddleware.runWebpackCompiler()`（`webpack-serve.js:33-52` 跑完整生产编译）。
原因：`public/script.js:1-12` 从 `./lib.js` 导入裸包名，而随包发布的 `public/lib.js` 只有 **3085 字节源码**。
- **[实测]** 桌面 x86：编译 **12.5 秒**，含模块加载 **17.4 秒**；输出 1.86MB + 11.3MB 缓存。
- 手机 ARM + 冷 JIT + 慢存储：**推断 30–60 秒，且发生在端口打开之前 → 用户看到黑屏。**
- **更糟**：`webpack-serve.js:41` 写成 `(_error, stats)`，**编译错误被完全吞掉**，失败也 resolve → 服务起来了但 UI 永久空白。
- **修法**：构建期预编译 `lib.js`（上游 Dockerfile `:33-35` + `docker/build-lib.js` 的 `forceDist:true` 就是这么做的），运行时短路掉这次编译。**这是补丁集 P1。**

### 2.2 【阻断】安装目录必须可写
`server.js:11` `process.chdir(serverDirectory)`，`serverDirectory` 由模块位置推导（`src/server-directory.js:3`）。所有相对路径落在**安装目录**：`config.yaml`、`./data`、`public/img`、`public/sounds`、`public/scripts/extensions/third-party`、`backups`、`./plugins`。
`src/users.js:113-130` 每次启动**无条件 `mkdirSync`** 这些目录。`--dataRoot` 只搬用户数据，搬不走这些。
- **修法**：ST 整体装在应用**可写的内部目录**（`files/st/`），而不是 APK 只读区。**无需改源码**——只要别装只读区。

### 2.3 【阻断】`config.yaml` 非原子写 → 启动永久变砖
`src/config-init.js:239` 裸 `fs.writeFileSync` 在每次需要迁移 key 的启动写 `config.yaml`。中途被杀 → 截断 → `src/util.js:74-78` 直接 `process.exit(1)`，**此后每次启动都失败，且没有 UI 可报错**。
- 这是「**应用再也打不开**」级事故，与 G2 直接冲突。**补丁集 P2。**

### 2.4 【风险】用户账户表用 node-persist：1 秒缓冲 + 非原子
`src/users.js:558-562` 只传 `dir`/`ttl`/`expiredInterval`，因此继承 `writeQueue:true` + `writeQueueIntervalMs:1000`（**写入可在内存滞留 1 秒**）与 `forgiveParseErrors:false`；底层裸 `fs.writeFile`（无 temp/rename/fsync）。截断后**读取直接 reject**。
- 影响面：仅 `DATA_ROOT/_storage` 的账户记录，不涉及聊天。
- 对照：角色缓存已传 `forgiveParseErrors:true`（`characters.js:108-114`）。**补丁集 P3。**

### 2.5 好消息：用户内容写入本来就是原子 + fsync
约 25 处 `write-file-atomic` 覆盖聊天、角色、世界书、预设、主题、设置、密钥、群聊、统计、向量。**ST 从不传 `fsync:false`**；`write-file-atomic@5.0.1` 是 temp + `fsyncSync` + `renameSync`。
- 残留缺口：无父目录 fsync；`SIGKILL` 跳过临时文件清理 → 孤儿文件堆积。
- **聊天没有"追加"逻辑**：`src/endpoints/chats.js:532-543` 每次保存**整文件重写**，客户端每次 POST 整个聊天数组（`public/script.js:7435-7442`，含 header + 全部消息，body 上限 500MB）。没有断行风险，但每轮是 **O(整个聊天) I/O** —— 这是 D13「长聊天不卡」的主要目标。
- **已有防线可利用**：保存前服务端会做 `checkChatIntegrity`（`chats.js:337-369`）——首行不是合法 JSON object 就**拒绝覆盖**并要求客户端显式确认。这正好是「截断/损坏文件不被静默覆盖」的保护，我们的恢复例程（L4）应当**复用它**而不是另造一套。
- **保存时机**：生成结束（`script.js:3815`）、编辑（debounce `DEFAULT_SAVE_EDIT_TIMEOUT`，`script.js:7377`）、以及多处显式调用；流式过程中**不落盘**（`onProgressStreaming` 只改内存 `chat[messageId].mes`）。→ 这正是 D14/P7 要补的窗口。

---

## 3. 架构

### 3.1 进程模型
```
┌─────────────────────────── APP 主进程 ───────────────────────────┐
│  MainActivity (Compose) + WebView  ← 只渲染 ST 前端              │
│  ServerController：备货 / 探活 / 启停 / 崩溃上报 / 日志脱敏       │
│  ForegroundService (specialUse)                                   │
└───────────────┬──────────────────────────────────────────────────┘
                │ ProcessBuilder(nativeLibraryDir/libnode.so, server.js, --dataRoot …)
                │ env: HOME / TMPDIR / TMP / TEMP / LD_LIBRARY_PATH / PORT
┌───────────────▼──────────── 子进程: node ───────────────────────┐
│  Node 24 LTS (full ICU) → ST server.js（原样）→ 127.0.0.1:PORT   │
│  stdout/stderr → logcat + 滚动日志文件                            │
└──────────────────────────────────────────────────────────────────┘
```

**为什么 exec 而不是 JNI 内嵌 `node::Start()`（三条硬证据）**：
1. `node::Start()` **无协作式停止**：`node::Stop()` → `TerminateExecution()` + `uv_stop`，是拆环境不是干净退出；**同一进程内不能再次 `Start`**（V8 platform 状态一次性）。→ 内嵌模式下「重启服务端」= 杀整个 APP 进程。
2. Android 应用进程是 zygote `fork()` 且**未 `exec()`**，继承 `AT_SECURE=1` + `AT_*ID=0`，Node 的 `SafeGetenv()` 会**静默忽略所有环境变量**（`TMPDIR`/`NODE_OPTIONS`/`NODE_ICU_DATA`/`NODE_EXTRA_CA_CERTS`）——**在每一个 Android 应用进程里，永久**。exec 路线没有这个问题。
3. ST **零原生依赖**，不需要 `node::Start` 的嵌入 API 面；它只是个普通 Node 程序。

**exec 的合法性（[文档] + SELinux 策略实证）**：
- Android 10+ 只禁止 `execve()` **应用 home 目录**内的文件（W^X，SELinux `app_data_file`，`chmod` 无效）。
- 审核读了 `private/app.te`（android-11 至 android-16）：关键规则
  `allow appdomain apk_data_file:file { getattr open read ioctl lock map x_file_perms };`
  其中 `x_file_perms = { getattr execute execute_no_trans map }`，**13/14/15/16 全部存在**。
- Android 10 的 W^X `neverallow` 是 `data_file_type … -apk_data_file`，即 **`apk_data_file` 被显式豁免**。
→ **从 `nativeLibraryDir` exec 今天合法，且一直到 Android 16 都合法；没有任何后续版本收紧。**
→ 必须 `android:extractNativeLibs="true"` **且** `useLegacyPackaging true`；若用 App Bundle 默认（`extractNativeLibs=false`），`nativeLibraryDir` 为空 → ENOENT。

**【易漏但致命】`LD_LIBRARY_PATH` 必须显式设置**：可执行文件被 `execve` 后，动态链接器**不会自动**在 `nativeLibraryDir` 里找 `DT_NEEDED`（`libc++_shared.so` 等）。必须在 `ProcessBuilder.environment()` 里设 `LD_LIBRARY_PATH` 指向依赖所在目录。真实在跑的实现（`STpatch-NodeService.kt:270`）就是这么做的：
```kotlin
val pb = ProcessBuilder(nodePath, serverPath, "--dataRoot", dataRoot)
pb.environment()["HOME"] = filesDir.absolutePath
pb.environment()["LD_LIBRARY_PATH"] = soDir.absolutePath   // ← 缺了它 exec 会在 DT_NEEDED 阶段失败
pb.environment()["SILLYTAVERN_BROWSERLAUNCH_ENABLED"] = "false"
```
**并且 `soDir` 不能懒解析**：`nativeLibraryDir` 是 `/data/app/<pkg>-<hash>/lib/...`，**每次升级都会变**（见 §5.1b）。

### 3.2 Node 产物（**经独立审核修正**）

#### 3.2.1 【阻断，已修正】预编译件不能直接 exec
独立审核用 ELF 头实测推翻了我原先的 D5 设想：

| 产物 | `e_type` | `e_entry` | `PT_INTERP` | 结论 |
|---|---|---|---|---|
| `fogtape` 24.22.1 full arm64 `libnode.so` | 3 = ET_DYN | **0x0** | **无** | **共享库，`execve` 必然 ENOEXEC** |
| `fogtape` lite 24.22.1 | 3 | **0x0** | 无 | 同上 |
| `nodejs-mobile` 18.20.4 | 3 | 0x1479700 | **无** | 也是共享库（只能 `dlopen`+`node::Start`） |

我**亲自复核了这两个 ELF 头**，结论一致。原因：上游 `android_configure.py` **不传 `--shared`**，本应产出可执行文件；而 nodejs-mobile fork **加了 `--shared`**，fogtape 继承了这个行为。

→ **`D5「先用 fogtape 预编译件跑通，成功后一行替换」不成立**：预编译件是 `.so`（model B），自建产物是可执行文件（model A），**两者不是同一类产物**。
→ **修正**：自建产物必须是**可执行文件**（不传 `--shared`，即上游默认 `node_shared=false`），产出 `node` ELF 后**重命名为 `libnode.so`** 放进 `jniLibs`。这正是前作 `ST-patch-android` 做的事（它用的是 Termux 的 `usr/bin/node`）。
→ **D5 改为**：先用**任一真实可执行文件**（如 Termux 的 `node`，或先在 CI 上产出自建可执行文件）打通链路；fogtape 只能作为 `dlopen` 备选，不能作为 exec 路线的起跑件。

#### 3.2.2 【阻断，已修正】交叉编译命令是错的
原稿写的 `--dest-os=android --with-intl=full-icu --cross-compiling` + `LDFLAGS=` 被审核逐条证伪：
- `configure.py` **没有 `--ldflags` 选项，也不读 `LDFLAGS` 环境变量**（grep 0 命中，`common.gypi` 里 `ldflags` 按 OS 写死）。
- `--with-intl=full-icu` **本来就是默认值**（`configure.py:719-724`），写了等于没写。
- `--cross-compiling` 是**宿主**交叉编译语义，不是 `--dest-os=android`；`android_configure.py` 靠 `GYP_DEFINES` + `CC/CXX`。
- `--openssl-no-asm` **是必需的且原稿写对了**（否则 openssl asm 会误判 Android）。

**修正后的构建方式**：
```
# 在 GitHub Actions ubuntu runner 上
export ANDROID_NDK_HOME=<NDK r27d 或 r28+>
export ANDROID_API=26
./android-configure $NDK arm64          # 上游脚本，内部设 GYP_DEFINES/CC/CXX
# 关键：不要加 --shared → 得到可执行文件
# 16KB 对齐由 NDK r27d/r28+ 的链接器默认值保证，不靠 LDFLAGS
make -j$(nproc)
# 产物 out/Release/node → 重命名 libnode.so
```
**16KB 页对齐**：`-Wl,-z,max-page-size=16384` **单独不够**，Google 文档要求**同时**给 `common-page-size=16384`，而 Node 的 gyp 根本不读 `LDFLAGS`。**正解是用 NDK r27d/r28+**，其链接器默认即产出 `p_align=16384`（fogtape 的两个产物都是这么来的，已验证 `vaddr-off` 也是 0x4000 的整数倍）。
**ICU**：`full-icu` 模式下 `<icu>.dat` 经 `genccode` **编译进二进制**（`icu-generic.gyp:222-262`），**不需要 `NODE_ICU_DATA`**。但交叉编译时 `.dat` 由**宿主工具**生成，`want_separate_host_toolset` 是否被正确置位，**是构建期 UNKNOWN，必须在 CI 里实测确认**。
**必带的伴随库**：`libc++_shared.so` 必须与 Node 链接时用的**完全一致**（fogtape 的 `DT_NEEDED` 明确含它），否则 `execve` 在 `DT_NEEDED` 解析阶段就失败；体积预算里**漏了它**，已补。

### 3.3 生命周期（[文档] 已核验）
- **前台服务类型 `specialUse`**，必需 `FOREGROUND_SERVICE_SPECIAL_USE` + `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" …/>`。
  > **审核 A10**：`specialUse` 的 **Play 审核声明确实存在**（"reviewed when you submit your app in the Google Play Console"）。因 **D19 是自签 sideload、不上 Play**，这一条**对我们的实际影响为零**——但 SDS 必须写明「这是选择 sideload 的附带好处，若将来上架则需准备 subtype 说明与审核话术」，而不是把这个 caveat 悄悄删掉。
- **禁止 `dataSync`**：Android 15+ 限 6 小时/24 小时，超时 `Service.onTimeout()` 未停则抛异常杀进程；且 **`BOOT_COMPLETED` 不允许起 `dataSync`**。
- `stopWithTask` 默认 `false` → 划掉任务**不会**停 FGS（符合 D9）。
- `START_STICKY` 只是 hint：系统会持续降低其优先级；**Force-stop / OEM 任务清理器（MIUI/EMUI/ColorOS/Vivo）一律不保**。
- 必须：`POST_NOTIFICATIONS`（13+）否则 FGS 不可见 → 违反"用户可感知"策略；引导用户关闭电池优化（`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，这是明确的后台启动豁免）。
- 健康探活循环 + 重连界面；`onTaskRemoved` 作为 flush 信号而非依赖。

---

## 4. 数据持久性（G2 核心）

### 4.1 分层
| 层 | 措施 | 针对失败 |
|---|---|---|
| L0 | 已存在：`write-file-atomic` temp+fsync+rename（25 处） | 写到一半截断 |
| L1 | 父目录 fsync（补丁 P4） | rename 后目录项未落盘 |
| L2 | `config.yaml` 原子化 + `.bak` 回滚（**P2**） | 2.3 的变砖 |
| L3 | 用户表 node-persist 改 `writeQueueIntervalMs` + `forgiveParseErrors:true` + 原子写（**P3**） | 2.4 账户表损坏 |
| L4 | 启动恢复：扫 `*.tmp`/孤儿文件/截断 jsonl → 修复并上报「上次异常退出，已修复 N 项」 | 崩溃残留 |
| L5 | 备份份数从 50 提高；缩短聊天 10s 节流 | 误删/坏档 |
| L6 | 周期性一致性快照到私有目录（环形保留 N 份） | 逻辑层损坏 |
| L7 | SAF 导出/导入（原生备份 zip + 原始 data 目录） | 清数据、卸载 |
| L8 | 升级只换程序目录，不碰 `data/`，跑迁移 | 升级毁数据 |
| L9 | **生成中草稿落盘**（D14），重启可恢复/续写 | 划掉时丢失进行中的回复 |

### 4.1b P7 草稿持久化的具体设计（审核 A5：原稿只有承诺没有设计）
**为什么需要**：实测确认流式生成期间 `onProgressStreaming` **只改内存** `chat[messageId].mes`（`script.js:3679`），**不落盘**；真正的保存只在 `onFinishStreaming` 触发（`script.js:3815`）。所以进程在生成中途被杀 = 这条回复全丢。

**设计（不改 `.jsonl` 格式）**：
| 项 | 决定 |
|---|---|
| 文件位置 | `files/data/<user>/drafts/<chatid>.<mesid>.json`，**独立于聊天文件**，不进 `chat_*.jsonl` |
| 写入时机 | 客户端**每 N 字符或每 M ms 触发一次**（取先到者，建议 2s），POST 到新增的轻量端点；**不触碰聊天文件** |
| fsync 策略 | 草稿用 `write-file-atomic`（temp+fsync+rename），**每次写都 fsync**——草稿小（几 KB），代价可接受 |
| 草稿内容 | `{ chatId, mesId, text, gen_started, swipe_id, type, updatedAt }` |
| 崩溃恢复 | 启动时扫描 `drafts/`：存在且 `mesId === chat.length-1` → UI 提示「上次生成中断，已恢复 N 字符」并提供 **继续**/**丢弃** |
| 与整文件重写的关系 | 草稿**永远不参与**聊天文件写入。生成正常结束时：写正式聊天（走既有路径）→ **删除草稿**。若删除失败，下次启动按「已存在于 chat」判定为陈旧草稿并清理 |
| 与 10s 备份节流的关系 | 完全解耦（草稿是独立文件，不进 backup 流） |
| 清理 | 超过 24h 的草稿、或对应 `mesId` 已不在聊天尾部 → 删除 |

**验收**：生成到一半 `kill -9` → 重启 → 能看到已生成的部分文本并可继续。这是 D15 门禁的一个用例，**必须**在 SDS 里写成可执行测试，不能只写「应恢复」。

### 4.2 保证边界（SDS 必须原样收录）
- 保证「**已 fsync 的写入不丢**」。断电瞬间正在烧写的最后一块可能丢。
- 存储写满时保证「**失败可见，不静默损坏**」。
- 用户「清除数据」或「卸载」→ 私有目录必毁，只能靠 L7 外部备份。
- 划掉进程后**进行中的生成**依赖 L9 才能恢复；未落草稿的最后一个 token 仍可能丢。

---

## 5. 首启与冷启动

### 5.1 首启
1. APK 内置 `jniLibs/arm64-v8a/libnode.so`（**可执行文件**，非共享库）+ **`libc++_shared.so`** + `assets/st.tar`。
2. **`assets/st.tar` 必须包含**：ST 源码 + `node_modules` + **`dist/_webpack/<cacheVersion>/output/lib.js`**。
   > ⚠ **审核 A2 的坑**：上游 `.gitignore` **和** `.dockerignore` **都含 `/dist`**。任何遵守这两个文件的打包步骤会**静默丢掉 P1 需要的 `lib.js`** → `usePrebuiltLib()` 启动时抛错 → **明明补丁正确却白屏**。打包脚本必须**显式 un-ignore `/dist`**，并在产物里断言该文件存在。
3. 首启：校验版本戳 → **流式 tar 解压**到 `files/st/`（2 万文件，朴素递归复制会**栈溢出**；解压前**检查可用空间**；显示进度）→ `files/data/` → 端口 + token → exec → `GET /` 探活 → WebView。
4. **`--dataRoot` 必须显式指向 `files/data`**（在安装目录**之外**）。不指定的话 ST 会用 `./data`，即安装目录内 → 升级替换安装目录时**用户数据全毁**。这是 L8 的前提。
5. **必须用字面量 `127.0.0.1`**（与 `localhost` 是不同 origin，cookie/localStorage 不通，混用静默掉登录）。
6. **单实例锁**：ST 无单实例保护，端口占用即 `process.exit(1)`（`server-startup.js:383-388`），残留 Node 会让重启**静默失败**。启动器持锁 + 捕获 stderr。
7. 明流：`usesCleartextTraffic` 或 `networkSecurityConfig` 仅限 `127.0.0.1`。

### 5.1b 【审核补充】升级 / 降级 / 多用户 / 崩溃循环 / 停止服务（原稿全部缺失）
| 项 | 问题 | 处置（写进 SDS） |
|---|---|---|
| **APK 升级** | `nativeLibraryDir` 是 `/data/app/<pkg>-<hash>/…`，**每次安装/升级都会变**。任何持久化的绝对路径（PID 文件、`LD_LIBRARY_PATH`、上次的 nativeLibraryDir）都会失效 | **每次启动重新解析 `ApplicationInfo.nativeLibraryDir`**，绝不落盘 |
| **APK 降级** | 版本戳逻辑若只看「已解压树的版本」，降级会被当成「新版本」→ 静默重解压 `files/st/` → **删掉用户装在 `public/scripts/extensions/third-party/` 的全局扩展** | 版本戳用**单调递增的 build number**；降级时**保留** `third-party/` 并提示；或明确禁止降级 |
| **全局扩展会被升级吞掉** | 扩展分 `data/<user>/extensions/`（本地）与 `public/scripts/extensions/third-party/`（全局，在**安装目录内**）。升级替换安装目录 → 全局扩展消失 | `third-party/` 在升级时**必须迁移或保留**；SDS 需明确「全局扩展不是一等公民」，或把安装目录与第三方面板分离 |
| **Work Profile / 多用户** | `nativeLibraryDir` 与 `files/` 都是**按用户**的，但 Android **不**给每个用户独立 netns → 两个 profile 的 Node 会**抢同一个 `127.0.0.1:PORT`** | 端口按 profile 稳定派生（hash(uid) 偏移）或动态选空闲端口；单实例锁需**跨 profile** 也成立（用端口占用探测兜底） |
| **崩溃循环** | ST 有 **≥8 处 `process.exit(1)`**（`util.js:74-78` 等）。配置坏了会**无限重启 + WebView 一直转圈** | **指数退避重启（1s/2s/4s/8s，上限 3 次）**，超限则停在**可读的错误页**并提供「导出日志 / 重置配置 / 查看原始报错」 |
| **用户怎么停服务** | 原稿只有「探活循环 + 重连界面」，没有「停止」 | 常驻通知上的 **Stop action** + App 内「退出并停止服务」入口；停止前 **flush + fsync** |
| **子进程归属** | 原稿 §3.1 图里 `:node` 容易被误读成 `android:process` 组件 | **它不是组件**，就是 `ProcessBuilder` 的普通子进程；文档已改口 |

### 5.2 冷启动两段式（D13）— **已有实测数据**

**[实测] P1 补丁前后，桌面 x86 / Node 24.14 的对照**（5 次取中位数，源见 `.work/runs/`）：

| 场景 | 冷启中位数 | 峰值空闲 RSS |
|---|---|---|
| **打 P1 前**（按上游原样跑运行期 webpack） | **15,714 ms** | **~990–1,048 MiB** |
| **打 P1 后**（预编译 `lib.js` + 短路编译） | **1,503 ms** | **~205 MiB** |
| P1 后 + 已有数据（大聊天集） | **1,378 ms** | ~205 MiB |

→ **P1 带来 10.5× 启动提升与 ~5× 内存下降。** 这不是优化，这是可行性前提。

**启动耗时与数据量无关**（这是最重要的结论，直接支撑 D13）：
```
小数据集 total = 740.9 ms
大数据集 total = 746.9 ms   ← 3000 条聊天 / 8.3MB，几乎不变
```
逐步骤实测（大数据库，总 747ms）：
| 步骤 | ms | 复杂度 |
|---|---|---|
| **import `server-main.js` 依赖图** | **401.6** | O(1) — 最大单笔，解析 JS |
| **`module import: server→server-main`** | **176.8** | O(1) — 含 yargs + config 加载 |
| **`getVersion()`** | **139.4** | **spawn `git` 最多 5 次** ← 平台项，Android 上无 git，可省 |
| `migrateSystemPrompts()` | 14.0 | O(data) |
| `checkForNewContent()` | 3.6 | O(content index) |
| 其余 11 步 | 各 < 3 | 全部 O(1)/O(users) |
| **`webpackMiddleware.usePrebuiltLib()` [P1]** | **1.03** | O(1) — 替代了原来的 12.5 秒 |

**结论（修正 D13 的口径）**：
- **手机估 3.5–5.5s**（按 1/3 单核；无 git 可省 ~139ms）。
- **固定成本 1.13s / 1.35s 中**：模块图解析 **836ms** + git 探测 **139ms** + Node 启动 **145ms**。这三项是**不可约的固定开销**，不是我们代码的问题。
- **要真做到「服务就绪 <2s」在手机上，必须先让桌面降到 ~0.65s**，路径有三条（按性价比排序）：
  | 优化 | 桌面收益 | 说明 |
  |---|---|---|
  | **P2 向量栈延迟加载** | **−483ms** | `vectra` 288ms + `sillytavern-transformers` 195ms，占 router 762ms 的 63%；聊天/文本从不需 ONNX |
  | P3 无 `.git` 时跳过 git 探测 | −139ms | Android 上天然没有 git，白送 |
  | P4 `statsInit` 懒加载 | −256ms（仅首启） | `stats.json` 缺失时会**逐行解析所有聊天**，是唯一真正的 O(data) 路径 |
  | P5 打包 + V8 snapshot | −~600ms | **唯一能突破 2s 的路线**，但工程成本最高 |
- **诚实结论**：**P1 单独只能到 2–3 倍差距**；手机端「服务就绪 <2s」需要 **P2 + P5 同时做到**。
- → **D13 的两段式因此是必需的，不是话术**：UI 可交互 <2s 靠 WebView 首帧 + 本地骨架页与服务进程**并行**达成；服务就绪由其自然完成（3.5–5.5s）。**SDS 必须写死这条边界，不许承诺「冷启 <2s 全就绪」。**

### 5.2b 一个必须记住的平台陷阱（实测发现的上游 Node bug）
**`fs.cpSync` 在路径含非 ASCII 字符时会原生崩溃**：退出码 `0xC0000409`，**没有 JS 异常可捕获**。
- 触发点：ST 首启会 `cpSync` `default/content/Seraphina` → `characters/`。本机工作区路径 `H:\杂七杂八\…` 含中文，**每次全新启动都静默死亡**，实测必须用 ASCII 的 subst 盘才跑通。
- **对项目的影响（两条都写进 SDS）**：
  1. **APK 的应用私有目录必须用纯 ASCII 路径**（如 `/data/data/<pkg>/files/st/`，天然 ASCII，安全）。
  2. **本机构的构建/测试目录也必须切到 ASCII 路径**，否则测出来的"崩溃"是假阳性，会浪费大量排查时间。
- 这与 Android 无关，是 ST 在任意非 ASCII 安装路径下的缺陷；APK 只是恰好避开了它，但**用户若做数据导入到含中文的 SAF 目录仍需注意**（数据目录我们固定为私有 ASCII 路径，可规避）。

### 5.3 WebView 必需配置（[文档]）
- `onShowFileChooser`（ST 的角色卡导入是 `<input type=file>`，**没有它导入就废**）
- `onRenderProcessGone`（否则 renderer 被回收时**整个 APP 崩溃**）
- `CookieManager.flush()` 在 `onPause`（cookie 库懒写，否则进程被杀**静默退出登录**）
- `setDomStorageEnabled(true)`；`setAcceptThirdPartyCookies(false)`
- `configChanges` 防旋转重载 SPA
- `onCreateWindow`：ST 只有 1 处 `window.open`（内置 nanogallery2），返回 false 原地加载即可；不要 `setSupportMultipleWindows`
- 回环是 **secure context**（W3C `127.0.0.0/8` 与 `::1/128`；端口不影响）→ `crypto.subtle`/`clipboard.writeText` 可用；`readText` 脆弱，必要时走 JS bridge

---

## 6. 一致性（G3）与补丁集

### 6.1 原则（D18）
`public/` 与 `src/` **完整保留上游源码不改**；所有改动以**补丁集**在构建期应用，每处有理由、有测试、可 rebase。

### 6.2 补丁集（按实测重排，P1/P2/P3/P4 直接来自测量结论）
| ID | 内容 | 依据 |
|---|---|---|
| **P1** | **构建期预编译 `lib.js`，运行时用它替代 webpack 编译。已产出并实测通过的 diff**（见 §6.2c）。**审核曾判定原设想不可行（F4），因为 `devMiddleware` 会无条件调 `getPublicLibConfig()` 并在 `$DATA_ROOT/_webpack/<hash>/output/lib.js` 缺失时返回 404；且 `isDocker()` 在 Android 上恒为 false，`forceDist` 无法从运行时触达。最终补丁绕开了 `getPublicLibConfig()`，改为启动时扫描 `dist/_webpack/*/output/lib.js` 定位预编译件并 fail-fast** | 2.1 + 实测 **−14.3s / −800MiB** |
| **P2** | **向量栈延迟加载**（`vectra` 288ms + `sillytavern-transformers` 195ms 改为按需 import） | 实测：占 router 762ms 的 63%，桌面 **−483ms** |
| **P3** | **无 `.git` 时跳过 git 探测**（`getVersion()` 最多 spawn 5 次 git） | 实测 **−139ms**，Android 上天然无 git。**审核 A9**：`command-exists` 本身也 `execSync('command -v git')`（`util.js:147`），所以**必须连 `command-exists` 一起短路**，否则仍会 spawn `/bin/sh` |
| **P4** | **`statsInit` 懒加载**（`stats.json` 缺失时会逐行解析全部聊天，是唯一真正的 O(data) 启动路径） | 实测：首启 **−256ms** |
| P5 | 扩展 update/branches/switch/version 改走可插拔 git 后端（**不是一行补丁**：`createGitClient()` 目前**只暴露 `clone`**，需先给 `src/git/client.js` 加 `status`/`fetch`/`pull`/`unshallow`/`checkout`，再改 **5 处**调用 `extensions.js:42,194,241,290,406`；注意 `SimpleGitClient` 构造函数**没有 baseDir**，必须按路径重建实例，否则会操作错仓库；另注意 `isUpToDate` 语义若改成「fetch 前后 hash 比较」**不等价**于原 `log.total===0`，会误报「已最新」） | D10 + `extensions.js:194` |
| P6 | 聊天保存**不改格式**的三项低风险优化：A 字节未变则跳过重写；B1 备份用硬链接（`EXDEV` 退化为复制）；C 开启请求压缩 | 2.5 + 实测 |
| P7 | 生成中草稿落盘 + 恢复（D14） | D14 |
| P8 | `browserLaunch.enabled:false`、`TMPDIR`、`--max-old-space-size` 等平台默认配置 | 平台 |
| P9 | **打包 + V8 snapshot**（唯一能把手机端拉到 <2s 的路线，成本最高，列为二期） | 实测结论 |

### 6.2a0 持久性补丁（与启动优化分开编号，避免混淆）
| ID | 内容 | 依据 |
|---|---|---|
| **D-P1** | `config.yaml` 原子写 + 解析失败回滚 `.bak`（**启动永久变砖**的根因） | §2.3 |
| **D-P2** | 用户表 node-persist：`writeQueueIntervalMs` 收紧 + `forgiveParseErrors:true` + 原子写 | §2.4 |
| **D-P3** | 数据写入父目录 fsync | §2.5 |
| **D-P4** | 启动恢复例程：扫 `*.tmp`/孤儿文件/截断 jsonl，修复并上报 | L4 |

### 6.2c P1 补丁的最终形态（已实测，非纸面设计）
审核（F4/F5）指出了原设想的三处致命缺陷，补丁据此重写并实测通过：

**原设想的三个错**：
1. `devMiddleware`（`webpack-serve.js:13-21`）**无条件** `getPublicLibConfig()`，`globalThis.DATA_ROOT` 有值 → 解析到 `$DATA_ROOT/_webpack/<hash>/output/lib.js`；编译一关，该文件不存在 → **404**（审核实测 `GET /lib.js → 404`，stderr `ENOENT`）。
2. `isDocker()`（`is-docker/index.js:1-29`）靠 `statSync('/.dockerenv')` + 读 `/proc/self/cgroup`，**Android 上恒 false**，所以 `forceDist` 这条路在运行时**永远不可达**。
3. `forceDist` 只是函数入参，没有任何环境变量开关。

**最终补丁（两文件，已实测）**：
- `webpack-serve.js`：去掉静态 `import webpack` 和 `import webpack.config.js`（后者顶层 `await getVersion()` 会 spawn git），新增 `usePrebuiltLib()`——**启动时扫描 `dist/_webpack/*/output/lib.js`，取 mtime 最新者**，找不到就**抛错 fail-fast**（绝不静默 404）；`devMiddleware` 命中预编译件即 `sendFile`，否则 `next()` 交给 `express.static`；`runWebpackCompiler` 改为**惰性 import**，从而 `docker/build-lib.js` 仍然可用。
  > **审核 A3/A4 修正**：①「取 mtime 最新」在 tar 解压后**不确定**（mtime 由打包决定，多目录时可能选中陈旧/半成品）→ **改为：解析 `${appVersion}` 或构建期写入的 `dist/_webpack/BUILD.json` 记录的确切 hash**，找不到再退回唯一目录，多于一个则**报错而不是猜**。② 原「defensive fallback 检查 `dist/_webpack/lib.js`」是**死代码**（该路径永远不存在），已删除。
- `server-main.js`：`await webpackMiddleware.runWebpackCompiler({pruneCache:true})` → `webpackMiddleware.usePrebuiltLib()`。

**实测验证**：3 次全部 HTTP 200，中位数 **1,344 ms**；日志 `Serving prebuilt frontend library: …\output\lib.js (1.86 MiB)`；`GET /lib.js` 返回 **1,947,206 B** 与预编译产物逐字节一致。**不需要环境变量、不需要伪造 `isDocker()`。**

> 注：审核建议的「把 bundle 覆盖写到 `public/lib.js` 让 static 兜底」是**另一条正确路线**，更简单但会改动上游 `public/` 内容（与 D18「上游零修改」冲突）。本方案选了不碰 `public/` 的那条。两条都可接受，SDS 里二选一并说明理由。
**追加式存储不可行**，这是实测结论而非猜测：
- **消息没有稳定 ID**（`public/global.d.ts:66-81` 的 `ChatMessage` 无 `id`/`uid`），身份就是**数组下标**。
- 17 种变更操作里**只有 2 种是纯末尾追加**（新用户消息、生成完成的新助手消息）。其余（编辑旧消息、删消息、swipe 增删/切换、书签、插入、改 metadata）**都会改写前面的行**，且格式里没有 tombstone/override 概念，读取方 `split('\n').map(tryParse)` 会把增量记录当成真实消息。
- `.jsonl` 是**对外交换格式**（导入/导出/备份/Data Maid 都直接解析），改格式代价 8/10。

**改为三项格式不变的优化**（估计把每轮 3N–4N 的持久写降到 1N–2N，diff 约 20–30 行）：
| 项 | 内容 | 收益 |
|---|---|---|
| A | 序列化后与磁盘字节完全相同则**跳过写入** | 干掉 metadata-only / 重复保存等空写 |
| B1 | 备份写入改用**硬链接**（同一文件系统时），`EXDEV` 退化为复制 | 去掉每轮 1N–2N 的**纯重复写**（最大单笔） |
| C | 开启 `performance.requestCompression` | 减少 WebView↔服务端传输与主线程停顿 |

**OOM 轴不在服务端**：`JSON.stringify` 在 WebView 里生成整份聊天字符串（`script.js:7435-7442`），任何服务端补丁都救不了。若要根治需改成流式 body 或只发尾段——后者**就是改格式**，列为二期。
**二期可选**：sidecar delta 文件 + 定期压实回 `.jsonl`，保留主文件为唯一权威，可拿到 O(1) 追加。

### 6.2a P6 的实测细化（修正了 v1.0 的"改追加写"设想）
**追加式存储不可行**，这是代码实证而非猜测：
- **消息没有稳定 ID**（`public/global.d.ts:66-81` 的 `ChatMessage` 无 `id`/`uid`），身份就是**数组下标**。
- 17 种变更操作里**只有 2 种是纯末尾追加**（新用户消息、生成完成的新助手消息）。其余（编辑旧消息、删消息、swipe 增删/切换、书签、插入、改 metadata）**都会改写前面的行**，且格式里没有 tombstone/override 概念，读取方 `split('\n').map(tryParse)` 会把增量记录当成真实消息。
- `.jsonl` 是**对外交换格式**（导入/导出/备份/Data Maid 都直接解析），改格式代价 **8/10**。

**改为三项格式不变的优化**（估计把每轮 3N–4N 的持久写降到 1N–2N，diff 约 20–30 行）：
| 项 | 内容 | 收益 |
|---|---|---|
| A | 序列化后与磁盘字节完全相同则**跳过写入** | 干掉 metadata-only / 重复保存等空写 |
| B1 | 备份写入改用**硬链接**（同一文件系统时），`EXDEV` 退化为复制 | 去掉每轮 1N–2N 的**纯重复写**（最大单笔） |
| C | 开启 `performance.requestCompression` | 减少 WebView↔服务端传输与主线程停顿 |

### 6.2a2 聊天保存的实测数字（P6 的依据）
**[实测]** 3000 条消息 / **8.33 MiB** 的聊天，POST `/api/chats/save`（payload 8,733,422 B，与客户端真实形状一致）：
| 指标 | 值 |
|---|---|
| 单次保存耗时 | min 62.2 / **med 84.5** / max 101.8 ms（桌面 x86；手机估 250–350ms） |
| 每次保存的文件系统操作 | **11 次 fs op，两次完整的 8.33 MiB 写 + fsync**（主文件 + 备份副本，都是 `write-file-atomic` 的 temp+fsync+rename） |
| 每轮对话的 POST 次数 | **2 次**（用户消息 + 生成完成），**不是每个 token** |
| 每轮持久写总量 | **≈33 MiB flash 写 / 轮**，约 170ms（桌面） |

→ 这正是 P6 的 A（跳过空写）+ B1（备份改硬链接）要打的点：**备份那份是纯重复写，占一半。**
→ **`/thumbs` 与聊天无关**（`thumbnails.js` 只处理 bg/avatar/persona），此前审计的该项担忧不成立，已剔除。

**内存实测（这一条改变了产品预期）**：
| 状态 | RSS |
|---|---|
| 启动后空闲（小/大数据库相同） | **192 MiB** — 聊天在启动时根本不加载 |
| 单次 8.33 MiB 保存峰值 | 205 → **238 MiB**（+33） |
| 连续保存 10 次后 | **418 MiB**；24 次后 ~440 |
| 用 `--max-old-space-size=192` 验证 20 次保存 | 20/20 成功，`heapUsed` 平稳 ~67 MiB，RSS 平台期 ~300 MiB |

→ **结论：不是内存泄漏，是 V8 惰性 GC。** 但**预算必须按 300–400 MiB 规划，不能按 200 MiB**。
→ 对 Android 的含义：中端机（4–6GB RAM）安全；低端机（2–3GB）会被 LMK 更早回收 → 这是 D9 保活之外**第二个必须在产品上明说的边界**。
→ **`--max-old-space-size` 的正确说法（审核 A7 修正）**：heap cap **≠ RSS**。实测用 `--max-old-space-size=192` 时 `heapUsed` 平稳 ~67 MiB，但 **RSS 仍会到 ~300 MiB**（V8 之外还有 wasm/ArrayBuffer/线程栈/映射）。所以：**不要**用「取设备 RAM 40%」这种拍脑袋公式；应当**先真机实测峰值 RSS，再留 1.5–2× 余量设 cap**，且明确「设 cap 不会把 RSS 压到 cap 以下」。

### 6.2b 扩展兼容的实测结论（支撑 D10）
三项直接验证，全部指向「扩展在 WebView 里可行」：

| 项 | 实测结论 | 证据 |
|---|---|---|
| CSP | ST **关闭了 CSP**：`server-main.js:104-106` `helmet({ contentSecurityPolicy: false })` | 不存在 `connect-src`/`script-src` 拦截扩展的可能 |
| 「重载生效」 | 就是 `location.reload()`（`extensions.js:478-479`、`495-496`、`1324-1325`），**纯浏览器刷新**，无服务端重载协议 | WebView 原生支持；D10 验收项可达成 |
| 扩展安装 | 走 `/api/extensions/install`（纯 git clone）+ `manifest.json`；**ST 从不给扩展跑 npm install** | 无 Node 侧构建需求 |
| 动态加载 | `await import(url)`（`extensions.js:438`）+ `<script>` 注入（`:824-838`） | WebView 原生支持 ES module 动态导入 |

→ D10 的「安装+启用+动态加载+重载生效」在技术上**全部落在浏览器侧**，不需要 Node 特有能力。剩余风险仅在**更新**（P5），已单列。

**但真正的坑不是 CSP，是 origin**（实测）：
- 扩展以 `<script type="module" src="/scripts/extensions/…">` 注入（`extensions.js:813-841`），**module script 永远做 CORS 检查**。若用 `file://`/`data:`/opaque origin 加载界面，**所有扩展静默全挂**（而 classic script 还能跑，极具迷惑性）。
- → **必须**走 `http://127.0.0.1:<port>` 由内嵌 Node 提供服务，与桌面完全一致。这一条把"用 WebViewAssetLoader 伪装 origin"的省事方案彻底排除。
- 扩展文件在鉴权之后（`server-main.js:248` 的 `requireLoginMiddleware` 先于 `:278` 的 `userDataRouter`）；用户扩展落在 `data/<user>/extensions/`（`users.js:1219`，本地优先于全局）——**这个目录划分必须保留**，否则装好的扩展会消失。

**其余实测风险（都不阻塞，但要进 SDS）**：
| 风险 | 证据 | 处理 |
|---|---|---|
| **全局扩展会在升级时被删**（审核 A8，D10 的核心风险） | 扩展分两类：`data/<user>/extensions/`（本地，在 `dataRoot` 内**安全**）与 `public/scripts/extensions/third-party/`（全局，在**安装目录内**）。升级替换安装目录 → **全局扩展消失** | SDS 必须二选一：① 升级时**迁移** `third-party/`；② **只支持本地安装**并在 UI 禁止「全局」选项。**不能含糊带过** |
| 内置扩展依赖 `index.html` 里的固定容器 id（`#tts_container`、`#qr_container` 等） | 硬编码于 `index.html:5773-5808`；**没有"给我一个设置面板"的 API** | **禁止重写前端外壳**；必须原样用上游 `index.html` |
| TTS 的 `speechSynthesis` / `HTMLAudioElement.play()` 受自动播放手势策略限制，多数调用点**无 `.catch()`** | `tts/system.js` ×11、20+ TTS provider | `setMediaPlaybackRequiresUserGesture(false)` |
| quick-reply 用 `navigator.clipboard` 且 `:199` 无 catch | secure context 下可用（回环满足），`file://` 下按钮直接死 | 回环 serving 已解决 |
| ONNX/WASM 多线程需要 COOP/COEP，ST 不发这两个头 | — | 接受单线程（ST 自己已在 `transformers.js:13-14` 对 Android 强制 `numThreads=1`） |
| `renderTemplate` 里有同步 XHR | `templates.js:15-26` | 无影响（同源回环），但注意不要阻塞 |

### 6.3 适配层（实测需要处理的非常少）
| 项 | 实测 | 处理 |
|---|---|---|
| Service Worker / File System Access / getUserMedia | **各 0 处** | 无需处理 |
| 文件导入导出 | 全是 `<input type=file>` + `FormData` | `onShowFileChooser` → SAF |
| `window.open` | 1 处（第三方库社交分享） | 原地加载 |
| `navigator.clipboard.readText` | 1 条斜杠命令 | 权限委托/降级 |
| HTTPS | 回环天然可信 | **不需要** |
| 移动布局 | 自带 656 行移动 CSS | 真机截图评估 |
| 老 WebView CSS | `color-mix()`/`oklch()` | minSdk 26 设备需实测；必要时降级 CSS |
| 浏览器启动 | 默认 ON，会 spawn `xdg-open` | 配置关闭 |
| 扩展更新 | 硬编码 `simpleGit` | **P5** |

---

## 7. 体积预算（含审核补漏项）

| 组成 | 大小 |
|---|---|
| `public/` | ~24.7MB（**保留**，含 woff/ttf，D11 不砍功能） |
| `default/` | 15.4MB（含 11.2MB 示例背景，保留） |
| `src/` | 17.7MB（16.5MB 分词器词表） |
| `node_modules` | **280MB（D11 保留 ML 栈，不砍）** |
| Node 可执行文件（full ICU） | ~100–130MB |
| **`libc++_shared.so`（必须，审核 A1 补漏）** | **~1MB** — Node 二进制的 `DT_NEEDED` 含它，缺失则 `execve` 在链接阶段失败 |
| `dist/_webpack/<hash>/output/lib.js`（P1 必需） | ~1.9MB |
| **合计（单 ABI，未压缩）** | **≈ 442MB** |
| **APK（压缩后，估算）** | **≈ 160–220MB**（实测参照：`libnode.so` 111.8MB → deflate 35.9MB，压缩率 32%） |

> 注意 1：D11（保留 ML 栈）+ D10（扩展像桌面）使体积**显著高于**研究建议的 150MB 裁剪版。这是用户明确选择的权衡，SDS 必须如实记录。
> 注意 2：**首启需要 ~2× 磁盘余量**（APK + 解压树 + tar 临时）。审核实测 `node_modules` 是 **20,068 个文件 / 280MB**，`public` 592 文件。必须**流式 tar 解压**避免二次临时占用，且**解压前检查可用空间**。
> 注意 3：GitHub Releases 上限 **2GiB/asset、1000 个 asset、无总大小限制** → **200MB 分发不是问题**，此前的 R3「分发困难」权重过高，已下调。

---

## 8. 无同类前作的独特难点（本项目独有）

现有 4 个 ST-on-Android 项目**都不满足本项目的 D9+D14+D15**：

| 项目 | 与我们的差距 |
|---|---|
| `Sanitised/ST-android`（137★，AGPL-3.0） | exec 模型同构 ✔；但自述 **"Extensions are not properly supported yet"** → 不满足 D10 |
| `wancDDY/ST-Ctrl`（72★，AGPL-3.0） | `.so`+JNI 内嵌（`node::Stop` 无解）；`stopWithTask=true` → 不满足 D9 |
| `jialmaster/SillyDroid`（363★） | Termux+GeckoView+targetSdk 28；**PolyForm 非商业许可** ⚠ 不可抄 |
| `JiYeHuanXiang/ST-patch-android`（2★） | Termux Node 26.4；**用 `dataSync`（Android 15+ 已错）** |

→ 我们的差异化：**exec 模型 + `specialUse` FGS + 生成草稿持久化 + kill -9 门禁 + 扩展完整兼容**。

---

## 9. 里程碑（已按审核意见校正）

| 里程碑 | 出口标准 |
|---|---|
| **M0 骨架** | 真机：**一个真实可执行文件**（自建 `node` 或先用 Termux `node` 跨界）经 `ProcessBuilder` 跑起来并响应 HTTP。**不可用 fogtape 的 `.so` 做这一步（F1：`e_entry=0x0`，exec 必失败）** |
| M1 跑通 | ST 1.19.0 启动（P1 已打），WebView 完成一轮真实流式对话 |
| M2 首启 | assets 迭代解压 + 预编译 lib.js + 单实例锁 + 崩溃退避/错误页；**UI（原生壳）可交互 <2s** |
| M3 持久性 | D-P1~D-P4 落地；随机 `kill -9` × 200 次零丢失零变砖（D15 门禁） |
| M4 体验 | P6 长聊天优化 + P7 草稿恢复 + 内存峰值控制（按 300–400MiB 预算） |
| M5 一致性 | 扩展安装/启用/重载全通（D10）；与桌面截图对比 |
| M6 交付 | **CI 自建可执行 Node 产物**替换临时件；APK + 源码 + 可复现构建 + AGPL 合规 |
| M7（可选） | P2 + P9 启动优化冲刺（若坚持要 ST 界面 <2s） |

---

## 10. 风险登记

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| **R1** | **自建可执行 Node 产物失败**（审核证实原编译命令是错的，见 §3.2.2） | **主线阻塞** | 用 `./android-configure` + NDK r27d/r28+；不要传 `--shared`；`LDFLAGS` 无效。CI 先行验证 |
| **R1b** | **预编译件不可 exec**（F1，已实测 `e_entry=0x0`） | 起跑计划失效 | M0 改用真实可执行文件；fogtape 只能作 `dlopen` 备选 |
| R2 | 划掉任务 / OEM 强杀 | 生成中断 | D9 保活 + D14 草稿恢复 + 电池白名单引导 + 明说边界 |
| R3 | 体积：未压缩 ~440MB / APK ~200MB / **首启需 2× 磁盘余量** | 低端机装不下 | 单 ABI；**首启前检查可用空间**；tar 流式解压避免 2× 临时占用 |
| R4 | 长聊天整文件重写 | 每轮 ~33MiB 写、RSS 涨到 300–400MiB | P6；真机压测 3000 条 |
| R5 | 老 WebView CSS（`color-mix`/`oklch`） | 界面错乱 | **minSdk 26 的实际 WebView 版本必须实测**；必要时降级 CSS |
| R6 | `full-icu` 交叉构建时 host toolset 未置位 | ICU 数据缺失 → 登录崩 | CI 里**显式验证 `String.normalize` 可用**作为构建门禁 |
| R7 | 扩展「任意」无法穷尽验收 | 期望落空 | D10 明确口径 = 安装+启用+加载+重载 |
| R8 | AGPL 合规 | 分发受阻 | 全量源码 + 补丁公开 + 改名避商标 |
| **R9** | **`fs.cpSync` 非 ASCII 路径原生崩溃**（无 JS 异常） | 首启静默死 | 数据目录固定 ASCII；构建/测试目录也切 ASCII |
| **R10** | **`Intl.Collator` 依 `LANG` 行为**，Android 通常未设 `LANG` | 与桌面排序有细微差异（G3 边缘） | 启动时显式设 `LANG`/`LC_ALL` 对齐桌面 |
| **R11** | **多 profile 抢同一回环端口** | 第二个实例起不来 | 端口按 uid 派生 + 端口占用探测 |
| **R12** | **无限重启循环**（≥8 处 `process.exit(1)`） | WebView 永久转圈 | 指数退避 + 上限 3 次 + 错误页与日志导出 |

---

## 11. 实测完成度（已关闭 vs 仍缺）

### ✅ 已关闭（有实测证据）
| 缺口 | 结论 |
|---|---|
| 冷启动逐步骤耗时 | ✅ `.work/measure-boot.md`：P1 前后 15.7s → 1.34s；**与数据量无关**；逐步骤耗时表 |
| 聊天保存 I/O 与内存 | ✅ 8.33MiB 聊天单次保存 84.5ms；11 次 fs op / 2×8.33MiB 写；RSS 192→300–400MiB 平台期，**非泄漏** |
| 追加式存储可行性 | ✅ 不可行（无消息 ID；17 种操作仅 2 种可纯追加）；已改为 A+B1 低风险补丁 |
| 扩展加载机制 / CSP | ✅ `<script type=module>` 注入；**CSP 全关**；重载=`location.reload()`；真正的坑是 origin 而非 CSP |
| 扩展 update 的 git 补丁范围 | ✅ 不是一行：`createGitClient()` 只有 `clone`；`simpleGit` 硬编码在 5 处（`:42,194,241,290,406`） |
| P1 补丁可用性 | ✅ diff 已产出并实测：`GET /lib.js` 返回 1,947,206 B，启动 1.34s |
| Node 版本门槛 | ✅ Node 18 即可（0 处 Node20+ API）；**真门槛是 full ICU**（`users.js:645`） |
| exec 合法性 | ✅ SELinux `apk_data_file` 在 11→16 全版本显式豁免 W^X |

### ❌ 仍缺（必须在 M0/M1 关掉，不能带进 SDS 当作已知）
1. **真机 smoke test 完全没做**：没有任何一次在 Android 设备/模拟器上跑过。所有设备侧结论都是文档推断。
2. **自建 Node 可执行文件从未产出过**：构建命令已按审核修正，但**没人真跑过**。`full-icu` 交叉时 host toolset 是否置位仍 UNKNOWN。
3. **`android-configure` 的 16KB 产出未验证**：NDK r27d/r28+ 默认对齐是**推断**，需实测 `readelf -l`。
4. **老 WebView（API 26 设备）的 CSS/JS 兼容面**未测。
5. **OEM 是否额外阻止 exec 提取的 `.so`**（MIUI/ColorOS）无证据，审核标注为 UNKNOWN。
6. **Gradle/Android SDK 未安装**，本机无法构建 APK。

> 这 6 项不是"以后再补"，是 **M0 的出口条件**。SDS 必须把它们写成带验收命令的任务，而不是假设。

*下一步：第二轮独立审核 → 定稿 → 编写 SDS → 审核 SDS。*
