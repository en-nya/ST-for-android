# SillyTavern → Android 移植方案（初稿 v0.2 — 证据修订版）

> v0.1 的多条技术前提已被两个研究 agent 的实测推翻。本版按证据重写。
> 每节标注证据等级：**[实测]** 本机跑过/读到源码行号 ｜ **[文档]** 一手文档 ｜ **[推测]** 未验证。
> 一句话目标不变：**装成一个安卓 APP，点开即用，不装 Termux、不要 root；崩溃/划掉/断电不丢数据；内容与桌面网页版一致。**

---

## 0. 事实基线（全部已核验）

| 项 | 值 | 证据 |
|---|---|---|
| 上游 | SillyTavern **1.19.0**（tag，2026-09-14） | GitHub Releases API **[实测]** |
| 运行要求 | Node **>= 20**，ESM，Express 4 + jQuery SPA | `package.json` **[实测]** |
| 许可 | **AGPL-3.0** | LICENSE **[实测]** |
| **原生依赖** | **零**。真实的 `npm ci --omit=dev` 产出 0 个 `.node`、0 个 `binding.gyp`，20068 个文件 / 280MB | 实跑安装 **[实测]** |
| tiktoken | 纯 WASM，0 依赖 | **[实测]** |
| 向量化 | `sillytavern-transformers` → `onnxruntime-**web**`（WASM，非 onnxruntime-node） | **[实测]** |
| `child_process` | ST 自身代码 **0 处** | grep **[实测]** |
| 前端 | 无 Service Worker、无 File System Access API、无 `getUserMedia` | 336 文件全扫 **[实测]** |
| 移动端 | 自带 656 行 `mobile-styles.css`（`dvh`、长按替代 hover、全屏抽屉） | **[实测]** |
| 启动必做 | **每次启动在 listen 之前跑一遍完整 webpack 生产编译** | `server-main.js:353` **[实测]** |
| 网络默认 | `listen:false` → `127.0.0.1:8000`；白名单默认含回环；cookie 无 `secure` | **[实测]** |
| 体积 | `public/` 24.7MB + `default/` 15.4MB + `src/` 17.7MB + 生产 `node_modules` 280MB ≈ 338MB；裁剪后 ≈ **150MB** | 实跑 **[实测]** |

**本机环境**：Node v24.14.0 / npm 11.12.0 / JDK 21 Zulu / Gradle 8.8 缓存已存在；**无 Android SDK / NDK / adb / emulator**；H 盘 469GB 可用。

---

## 1. 结论摘要：方案从「自建 libnode.so」改为「把 stock Node 编译成 Android 可执行文件」

v0.1 的路线 A（`dlopen libnode.so` + `node::Start()` JNI 内嵌）**不是最优解**，原因有三条硬证据：

1. **`node::Start()` 没有协作式停止接口**。社区唯一成熟的 `.so` 方案（ST-Ctrl）自己的注释写明：join 会死锁，只能 `killProcess()` 整个进程。→ 走 `.so` 必须把 Node 关进 `android:process=":node"` 的牺牲进程，复杂度不减反增。
2. **Android 应用进程是 zygote `fork()` 出来且不 `exec()`**，会继承 `AT_SECURE=1` 与 `AT_{,E}{U,G}ID=0`。Node 的 `SafeGetenv()` 因此**在该进程里拒绝所有环境变量**（`TMPDIR`/`NODE_OPTIONS`/`NODE_ICU_DATA`…）。这是 `dlopen` 路线独有的坑，`fork+exec` 路线天然没有。
3. **零原生依赖**意味着我们**完全不需要** `node::Start` 的嵌入式 API 面——ST 只是一个普通 Node 程序，`node server.js` 就够了。

**推荐主线（A'）：把官方 `nodejs/node` 交叉编译成 Android **可执行文件**，改名塞进 `jniLibs/arm64-v8a/libnode.so`，靠 `extractNativeLibs=true` 落地到 `nativeLibraryDir`，再用 `ProcessBuilder` 直接 exec。**
- 合法性：Android 10+ 只禁止 `execve()` **应用 home 目录**里的文件（W^X）；`nativeLibraryDir` 是官方许可的可执行位置。
- 环境变量正常（真 fork+exec）。
- 有真正的 pid，`destroyForcibly()` 可回收。
- `targetSdk 36` 完全合规。
- 代价：**每个 ABI 编译 Node 首次约 2–3 小时**，单 ABI 可执行文件约 100MB。

**备选（B'）：`fogtape/nodejs-mobile`** — 已发布 Node **24.22.1 LTS**（另有 26.12.1 预发布），覆盖 arm64-v8a / armeabi-v7a / x86_64，**已修 16KB 页对齐**，附带 EMBEDDING.md。但它仍是「单维护者 + 预发布 + `dlopen` 语义」，只作加速器。

**已废弃路线**：
- **上游 `nodejs-mobile`（janeasystems）** — 最新版 **18.20.4（2024-10）**，Node 22/24 升级 PR 至今未合并，维护者公开表示无力维护，16KB 修复已合并但**未发版**（Play 会硬拒）。**不能用**。
- **`node-on-android` / libnode** — 2019 年停更，Node 8–10 时代。
- **C 路线（打包 Termux rootfs）** — 唯一成功案例 SillyDroid 靠 **`targetSdk 28`** 规避 W^X，而 2026-08-31 起新应用/更新必须 `targetSdk 36`。**路线已死**（除非放弃 Play 与现代 Android 加固，且它自身许可为 PolyForm 非商业 + 内嵌 AGPL，不能照抄）。
- **Deno 上 Android** — 官方无 target（issue #19759 仍开）。**Bun 有官方 Android 二进制**（1.4.4），但只能 exec 不能嵌入。

---

## 2. 必须修的 4 个上游缺陷（这是移植的真正工作量）

研究实测发现 ST 1.19.0 有四个会直接摧毁移动端体验的点。**它们都不是「安卓适配」，而是「桌面端碰巧没事」的缺陷。**

### 2.1 【阻断】每次启动强制跑 webpack 编译
`server-main.js:353-355` 在 `app.listen` **之前** `await runWebpackCompiler()`；`webpack-serve.js:33-52` 跑完整生产编译。原因：`public/script.js` 从 `./lib.js` 导入裸包名，而随包发布的 `public/lib.js` 只有 3085 字节源码。
- 实测桌面 x86：**12.5 秒**（含模块加载 17.4 秒）。手机 ARM + 冷 JIT + 慢存储，推测 **30–60 秒**，**而且是在端口打开之前**——用户看到的是黑屏。
- 更糟：`webpack-serve.js:41` 写的是 `(_error, stats)`，**编译错误被完全吞掉**，失败也 resolve → 服务启动但 UI 永久空白。
- **修法**：构建期预编译 `lib.js`（上游 Dockerfile 就是这么做的：`Dockerfile:33-35` + `docker/build-lib.js` 的 `forceDist:true`），运行时把这次编译短路掉。

### 2.2 【阻断】安装目录必须可写
`server.js:11` `process.chdir(serverDirectory)`，而 `serverDirectory` 由模块自身位置推导（`src/server-directory.js:3`）。所以 ST 的所有相对路径（`config.yaml`、`./data`、`public/img`、`public/sounds`、`public/scripts/extensions/third-party`、`backups`、`./plugins`）都落在**安装目录**。
- `src/users.js:113-130` 每次启动无条件 `mkdirSync` 这些目录。
- `--dataRoot` 只能搬走**用户数据**，搬不走 `public/img`、`public/sounds`、`third-party`、`backups`、`config.yaml`。
- **结论**：ST 必须整体装在**应用可写的内部目录**（如 `files/st/`），而不是 APK 的只读区。

### 2.3 【阻断】`config.yaml` 非原子写 → 启动永久变砖
`src/config-init.js:239` 用裸 `fs.writeFileSync` 在**每次需要迁移 key 的启动**写 `config.yaml`。中途被杀 → 文件截断 → `src/util.js:74-78` 直接 `process.exit(1)`，**此后每次启动都失败，且没有 UI 可报错**。
- 这与「崩溃不丢数据」直接冲突：它是**应用再也打不开**级别的事故。
- **修法**：原子写 + 解析失败时回滚到 `.bak`。或彻底避免运行期改写（随包发最终 `config.yaml` + `--configPath` 指向可写区）。

### 2.4 【风险】用户账户表用 node-persist，1 秒缓冲 + 非原子
`src/users.js:558-562` 初始化用户存储只传了 `dir`/`ttl`/`expiredInterval`，因此继承默认 `writeQueue:true` + `writeQueueIntervalMs:1000`（**写入可在内存里滞留 1 秒**）与 `forgiveParseErrors:false`，底层是裸 `fs.writeFile`——无 temp、无 rename、无 fsync。截断后**读取直接 reject**。
- 影响面：仅 `DATA_ROOT/_storage` 里的账户记录（`user:<handle>`），不涉及聊天。
- 对照：ST 的角色缓存已经传 `forgiveParseErrors:true`（`characters.js:108-114`），用户表应当对齐。

### 2.5 好消息：用户内容写入本来就是原子 + fsync
约 25 处 `write-file-atomic` 覆盖了聊天、角色、世界书、预设、主题、设置、密钥、群聊、统计、向量。**ST 从不传 `fsync:false`**；`write-file-atomic@5.0.1` 实测是 temp + `fsyncSync` + `renameSync`。
- 残留缺口：无父目录 fsync；`SIGKILL` 会跳过临时文件清理，堆积孤儿文件。
- 且**聊天根本没有"追加"逻辑**——`src/endpoints/chats.js:532-543` 每次保存**整文件重写**，客户端每次都 POST 整个聊天数组（body 上限 500MB）。**没有断行风险，但每轮对话 O(整个聊天) 的 I/O**，长聊天在手机上要观察内存与耗时。

---

## 3. 目标与非目标

### 3.1 目标（可验收）
1. **G1 打开即用**：安装 → 首屏可用，不联网下载运行时。
2. **G2 数据不丢**：崩溃 / 划掉任务 / 低内存被杀 / 断电 / 存储写满，重启后已确认的聊天不丢不坏。
3. **G3 与桌面一致**：UI、功能、行为与同版本桌面对齐；差异仅限平台适配层。
4. **G4 可维护**：补丁集独立可审计，能按季度 rebase 上游。
5. **G5 可交付**：可安装 APK + 源码 + 构建脚本，符合 AGPL-3.0。

### 3.2 非目标
- root / Magisk；本地跑 Stable Diffusion 或本地大模型；重写前端（**必须原样复用 `public/`**）。

### 3.3 已确认的允许降级（第一轮讨论结论）
- 本地向量化 / 本地 TTS：允许降级为「走 API」或「关闭」，并在 UI 明确标注。

---

## 4. 进程与生命周期模型

```
┌────────────────────────── APP 进程（主） ──────────────────────────┐
│  MainActivity（Compose）+ WebView   ← 只渲染 ST 前端               │
│  ServerController：备货、探活、启停、崩溃上报                       │
└──────────────┬─────────────────────────────────────────────────────┘
               │ ProcessBuilder( nativeLibraryDir/libnode.so, server.js, … )
               │ + 环境：HOME / TMPDIR / TMP / TEMP / LD_LIBRARY_PATH / PORT
┌──────────────▼──────────── 子进程: node ──────────────────────────┐
│  stock Node 24 LTS → ST server.js（原样）→ 127.0.0.1:PORT         │
│  stdout/stderr → logcat + 滚动日志文件                             │
└────────────────────────────────────────────────────────────────────┘
```

**为什么是独立子进程**：WebView renderer 崩溃 / V8 OOM / 原生段错误不能带走 UI；UI 重建也不该重启服务端。`destroyForcibly()` 拿到真 pid，比 `node::Stop()` 可靠。

**安卓平台的硬约束（[文档] 已核验）**：
- **前台服务**：`specialUse` 类型 + `FOREGROUND_SERVICE_SPECIAL_USE` + 必须声明 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`；无通知则通道被拦、服务更快被杀。
- **不允许 `dataSync`**：target 35+ 不能从 `BOOT_COMPLETED` 起 `dataSync` FGS。
- **后台不能起 FGS**（target 31+）：`ForegroundServiceStartNotAllowedException`。合法时机只有「从可见 Activity 的 `onStart`」「用户点通知/微件」「BOOT_COMPLETED」「用户已关闭电池优化」。
- **划掉任务无法保证存活**：`START_STICKY` 只是 best-effort；MIUI/ColorOS/EMUI 直接 force-stop。**这是唯一真正无法解决的 UX 项**（见第一轮讨论）。
- **无 `/tmp`**：`os.tmpdir()` 会 ENOENT，必须显式设 `TMPDIR`。
- **超 cgroup 上限会杀掉整个 APP**，不是只杀子进程 → 必须给 Node 设 `--max-old-space-size`。

---

## 5. 数据持久性设计（G2 核心）

### 5.1 分层加固
| 层 | 措施 | 针对的失败 |
|---|---|---|
| L1 已存在 | `write-file-atomic` 的 temp+fsync+rename（25 处） | 写到一半截断 |
| L2 新增 | 父目录 fsync | rename 后目录项未落盘的窗口 |
| L3 新增 | `config.yaml` 原子化 + `.bak` 回滚 | **2.3 的变砖** |
| L4 新增 | 用户表 `node-persist` 改 `writeQueueIntervalMs` + `forgiveParseErrors:true` + 原子写 | **2.4 的账户表损坏** |
| L5 新增 | 启动恢复例程：扫 `*.tmp`/孤儿文件/截断 jsonl → 修复并上报「上次异常退出，已修复 N 项」 | 崩溃残留 |
| L6 新增 | 备份份数从 50 提高；聊天节流 10 秒 + 退出 flush（**`SIGKILL` 不触发 flush，故不足恃**） | 误删/坏档 |
| L7 新增 | 周期性一致性快照到私有目录（环形保留 N 份） | 逻辑层损坏 |
| L8 新增 | 外部备份出口（SAF 导出到用户选的目录/云盘） | 清数据、卸载 |
| L9 新增 | 应用升级时不碰 `data/`，只换程序目录 + 跑迁移 | 升级毁数据 |

### 5.2 保证边界（必须写进 SDS，不能含糊）
- 保证的是「**已 fsync 的写入不丢**」；断电瞬间正在烧写的最后一块可能丢。
- 存储写满时保证「**失败可见，不静默损坏**」。
- 用户「清除数据」或「卸载」→ 私有目录必毁，只能靠 L8 外部备份。
- **划掉进程后「正在生成的这条回复」可能丢**——ST 没有生成任务持久化。这需要产品决策（见第一轮 Q）。

---

## 6. 「打开即用」首启设计

1. APK 内置：`jniLibs/<abi>/libnode.so`（≈100MB/ABI）、`assets/st.tar`（ST 源码 + **预装 node_modules** + **预编译 lib.js**，裁剪后 ≈150MB）。
2. 首启：校验版本戳 → 解压到 `files/st/`（显示进度）→ 确保 `files/data/` → 生成随机端口与 token → exec Node → `GET /` 探活 → WebView 打开 `http://127.0.0.1:PORT/`。
3. **必须用字面量 `127.0.0.1` 而不是 `localhost`**：两者是不同 origin，cookie/localStorage 不通，混用会静默掉登录；且 `hostValidationMiddleware` 会 403 白名单外的 Host。
4. 单实例保护：端口占用即 `process.exit(1)`（`server-startup.js:383-388`），**ST 没有单实例锁**——残留 Node 会让重启静默失败。必须由启动器持 `flock` + 捕获 stderr。
5. 数据导入：接受 ST 的 `config.yaml + data/` 打包（`tar.gz`/`zip`），导入前自动备份。
6. 冷启目标：热 < 2s（不含首装解压）。

---

## 7. 一致性（G3）与平台适配层

**原则**：`public/` 与 `src/` 尽量逐字节保留上游，所有改动进受控补丁集，每处有理由、有测试。

### 7.1 实测需要的适配（比 v0.1 预估**少得多**）
| 差异点 | 实测结论 | 处理 |
|---|---|---|
| Service Worker | **0 处** | 无需处理 |
| File System Access API | **0 处** | 无需处理 |
| 麦克风 `getUserMedia` | **0 处** | 无需处理 |
| 文件导入导出 | 全部是 `<input type=file>` + `FormData` | `WebChromeClient.onShowFileChooser` → SAF |
| `window.open` | **仅 1 处**（内置 nanogallery2 社交分享） | `onCreateWindow` 返回 false 原地加载即可 |
| `navigator.clipboard.readText` | 1 条斜杠命令 | 权限委托或降级 |
| 安全上下文 | `127.0.0.0/8` 与 `localhost` 均为 potentially trustworthy（W3C，端口不影响） | **无需 HTTPS** |
| 移动布局 | 自带 656 行移动 CSS | 真机截图评估，必要时补 CSS 补丁 |
| 老 WebView CSS | `color-mix()`/`oklch()` 在老版本不支持 | minSdk 26 的设备 WebView 版本需实测；必要时补降级 CSS |
| 浏览器启动 | 默认 ON，`open` 包在 Android 上 spawn `xdg-open` | 配置 `browserLaunch.enabled: false` |
| 扩展更新 | 硬编码 `simpleGit`（`extensions.js:194`），需真 git；安装走 isomorphic-git 不需要 | 更新功能标注「暂不支持」，或内置 git 二进制 |

### 7.2 离线
- 首屏无 CDN 依赖（`index.html` 外链全是文档链接，不是资源）；无遥测；启动无网络调用（`checkForNewContent` 是纯文件播种）。**[实测]**

---

## 8. 已存在的同类实现（必须正视）

研究在 2026-11 查到 **4 个真实的 ST-on-Android 项目**，其中一个与我们的方案几乎identical：

| 项目 | ★ | 许可 | 技术 | 与我们的关系 |
|---|---|---|---|---|
| **`Sanitised/ST-android`**（2026-10-21） | 137 | **AGPL-3.0** | **stock Node 24.22.1 编译成可执行文件 → `jniLibs/arm64-v8a/libnode.so` → `ProcessBuilder` exec**；`extractNativeLibs=true` + `useLegacyPackaging=true`；minSdk 26 / **targetSdk 36**；Compose UI；ST 1.19.0；7 个 gyp 补丁，无 Node 源码 fork | **几乎就是本方案**。它自述短板：*"intended primarily for basic on-device chatting. **Extensions are not properly supported yet.**"* |
| `wancDDY/ST-Ctrl`（2026-10-20） | 72 | AGPL-3.0 | `.so` + JNI `dlopen` + `node::Start`，自编译 Node 24.20.0，`:node` 进程，`flock` 单实例，**fork 了 ST**（15 条运行时补丁 + Vue runtime + 旧 WebView CSS shim） | 反面参考：告诉我们 `.so` 路线要付出什么 |
| `jialmaster/SillyDroid`（2026-09） | 363 | **PolyForm 非商业** ⚠ | Termux rootfs + **GeckoView** + targetSdk 28 | **不能抄**（许可冲突 + 路线已死） |
| `Aegis-plus/SillyTavern-Android` | 56 | — | Capacitor 纯 WebView 壳，自带 Node | 只作 WebView 配置参考 |

**这带来一个必须由你定夺的战略问题：从零自建，还是在这两个 AGPL 项目的基础上起步？**

---

## 9. 体积预算

| 组成 | 现状 | 裁剪后 |
|---|---|---|
| `public/` | 24.7MB | ~19MB（去 woff/ttf 4.9MB） |
| `default/` | 15.4MB | ~4MB（去 11.2MB 示例背景） |
| `src/` | 17.7MB | 17.7MB（16.5MB 是分词器词表，建议保留） |
| `node_modules` | 280MB | **~150MB**（去 onnxruntime-web 65MB + transformers 47MB 重复 wasm、去 `.map` 45.8MB、去 `@types` 3.9MB、tiktoken 保留或换纯 JS） |
| Node 可执行文件 | — | ~100MB / ABI |
| **合计（单 ABI）** | — | **≈ 250MB APK** |

→ 单 ABI 是唯一现实的交付形态；双 ABI 会让 APK 接近 400MB。

---

## 10. 里程碑

| 里程碑 | 出口标准 |
|---|---|
| M0 骨架 | 真机：点开 APP → 看到 Node 起的 `Hello` 页面（验证 exec 链路 + 16KB 对齐 + targetSdk 36） |
| M1 跑通 | ST 1.19.0 在设备上启动，WebView 完成一轮真实对话（含流式） |
| M2 首启体验 | assets 解压 + 预编译 lib.js + 单实例锁，冷启 < 5s |
| M3 持久性 | 4 个上游缺陷修复；随机 `kill -9` × 200 次零丢失零变砖 |
| M4 一致性 | 适配层逐项真机通过；与桌面截图对比 |
| M5 交付 | 发布 APK + 源码 + 可复现构建 + AGPL 合规文件 |

---

## 11. 风险登记

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | 首次交叉编译 Node 失败（2–3h/ABI） | 主线阻塞 | M0 先验证；失败切 fogtape 预编译件 |
| R2 | 划掉任务必死 | 生成中断 | 前台服务 + 电池白名单引导 + **产品层面明说** |
| R3 | 退出时 ST 的退出钩子在 `SIGKILL` 下不触发 | 10 秒节流的聊天写可能丢最后一轮 | 提高备份份数；缩短节流；子进程收到 `SIGTERM` 再强杀 |
| R4 | 长聊天整文件重写导致 OOM/卡顿 | 体验崩 | 真机压测 3k 条聊天；必要时打补丁改追加写 |
| R5 | 老 WebView CSS 不支持 | 界面错乱 | 实测 Top 设备 WebView 版本；补降级 CSS |
| R6 | 厂商 ROM 杀后台 | 断流 | FGS + 白名单引导 + 重连 UI |
| R7 | 扩展生态不完整 | 违背「与原生一致」 | **需你定义边界** |
| R8 | AGPL 合规 | 分发受阻 | 全量源码 + 补丁公开 + 改名 |

---

## 12. 需要你定夺（第二轮 grill 预告）

1. 是否复用 `Sanitised/ST-android` 起步？
2. `targetSdk` 取 36 还是 34？
3. 「划掉进程」的产品策略：保活前台服务，还是优雅退出 + 重连？
4. 扩展生态的边界在哪？
5. 单个 x86_64 是否降级为「仅调试用」？

*本文档是讨论稿。下一步：第二轮 grill → 独立审核 → 定稿 → SDS。*
