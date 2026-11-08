# ST 鈫?Android 绉绘 路 椤圭洰褰掓。

> **褰掓。鏃ユ湡**锛?026-11-08
> **浠撳簱**锛歨ttps://github.com/en-nya/ST-for-android 锛?3 commits锛屽伐浣滃尯骞插噣锛?> **鏈湴鏂囨。**锛歚H:\鏉備竷鏉傚叓\瀹夊崜閫嗗悜\ST閰掗\docs\`
> **涓€鍙ヨ瘽**锛氳璁℃枃妗ｅ凡瀹屾垚骞堕€氳繃 8 杞嫭绔嬪鏍革紱Node 杩愯鏃跺凡鎴愬姛浜ゅ弶缂栬瘧涓?Android arm64 鍙墽琛屾枃浠跺苟閫氳繃璁惧渚?exec 鏈哄埗瀹炶瘉锛?*APK 鏈綋灏氭湭寮€濮?*銆?
---

## 涓€銆佸綋鍓嶇姸鎬侊紙涓€鍙ヨ瘽鐗堬級

| 灞傞潰 | 鐘舵€?| 璇佹嵁寮哄害 |
|---|---|---|
| 鏂规 + SDS 鏂囨。 | 鉁?瀹屾垚 | 8 杞鎶楀紡瀹℃牳 |
| SDK/NDK 宸ュ叿閾?| 鉁?瑁呴綈骞堕獙璇?| 瀹炴祴 |
| Node arm64 鍙墽琛屾枃浠?| 鉁?宸蹭骇鍑?| 涓ゆ鏋勫缓 SHA256 涓€鑷?|
| exec 鏈哄埗鍙鎬?| 鉁?宸插疄璇?| Android 14 璁惧瀹炴祴锛坸86_64锛?|
| **APK 鏈綋锛圵ebView 澹?+ P1鈥揚12 琛ヤ竵锛?* | 鉂?**鏈紑濮?* | 鈥?|
| **arm64 鐪熸満杩愯** | 鉂?**浠庢湭鍙戠敓** | 鈥?|

---

## 浜屻€佷氦浠樼墿娓呭崟

### 2.1 鏂囨。锛堟湰鍦?`docs/`锛屽凡鍚屾浠撳簱锛?
| 鏂囦欢 | 瑙勬ā | 鍐呭 |
|---|---|---|
| `00-draft-plan.md` | 19.5 KB | 鍒濈锛堜繚鐣欒璁烘紨杩涜褰曪級 |
| `01-plan.md` | 50.8 KB | **鏂规瀹氱** 路 19 鏉″喅绛?/ 4 涓笂娓哥己闄?/ 琛ヤ竵闆?/ 閲岀▼纰?/ 椋庨櫓鐧昏 |
| `02-sds.md` | 104.8 KB / 942 琛?| **杞欢璁捐瑙勬牸涔?* 路 15 绔狅紝鍚?15 鏉¤鎺ㄧ炕璁捐鐨勮褰?|

### 2.2 瀹℃牳杞ㄨ抗锛坄.work/review-*.md`锛屽叡 9 浠?/ 263 KB锛?
| 杞 | 瀵硅薄 | 缁撴灉 |
|---|---|---|
| plan-r1 | 璁″垝 | 2 BLOCKER + 鍙戠幇 鈫?淇 |
| plan-r2 | 璁″垝锛堝鏍革級 | 2 BLOCKER锛團1 杩愯鏃朵骇鐗╀笉鍙?exec銆丗5 鏋勫缓鍛戒护閿欒锛夆啋 淇 |
| sds-r1 | SDS | 1 BLOCKER锛坄forgiveParseErrors` 鏈夊锛夆啋 淇 |
| sds-r2 | SDS | 2 BLOCKER锛圥11 鏃跺簭銆丳10 浜や粯鏈哄埗锛夆啋 淇 |
| sds-r3 | SDS | 2 BLOCKER锛坄--port 0`銆丳12 缂?import锛夆啋 淇 |
| sds-r4 | SDS锛堥獙璇佷慨澶嶏級 | 鍏ㄩ儴 FIXED |
| **sds-r5** | SDS锛?*棣栨鏈夌湡瀹炴瀯寤鸿瘉鎹?*锛?| **4 涓瀯寤哄け璐ュ師鏂囦竴鏉℃湭璁板綍** 鈫?宸茶ˉ |
| build-r1 | 鏋勫缓浜х墿 | 纭鍙俊锛涙寚鍑?AVD 鍧囦负 x86_64 |
| device-r1 | 璁惧渚ц瘉鎹?| 纭 T1/T2/T3锛?*鎺ㄧ炕鎴?鍞竴鍙璺緞"鐨勭粷瀵瑰寲琛ㄨ堪** |

### 2.3 瀹炴祴璇佹嵁锛坄.work/`锛?
| 鏂囦欢 | 鍐呭 |
|---|---|
| `research-node-android.md` (101 KB) | Node-on-Android 鍙鎬у叏涔?|
| `research-st-audit.md` (72.5 KB) | ST 1.19.0 婧愮爜瀹¤锛堥浂鍘熺敓渚濊禆绛夛級 |
| `research-chatwrite-ext.md` (94.1 KB) | 鑱婂ぉ鍐欒矾寰?+ 鎵╁睍鍔犺浇鏈哄埗 |
| `measure-boot.md` (37.2 KB) | 鍚姩/淇濆瓨/鍐呭瓨瀹炴祴閲忓寲 |

### 2.4 浠ｇ爜鎴愭灉

| 浣嶇疆 | 鍐呭 |
|---|---|
| 浠撳簱 `.github/workflows/build-android-node.yml` | Node arm64 浜ゅ弶缂栬瘧娴佹按绾匡紙13 姝ワ級 |
| 浠撳簱 `tools/apply-node-android-patches.sh` | 2 涓繀瑕佽ˉ涓侊紙zlib getauxval銆乂8 trap-handler锛?|
| 浠撳簱 `tools/verify-gates.js` | 闂ㄧ閫昏緫鑷锛?/6 閫氳繃锛?|
| 浠撳簱 `exec-proof/` | **鍙鐜扮殑 exec 楠岃瘉宸ョ▼** |
| 浠撳簱 `patches/` | P1 琛ヤ竵锛堝惎鍔ㄦ湡 webpack 绉婚櫎锛?|
| 鏈湴 `H:\Android\artifacts2\libnode-arm64` | **90 MB 鍙墽琛屼骇鐗?* |

---

## 涓夈€佸叧閿妧鏈粨璁猴紙鍙鐢級

### 3.1 杩愯鏃惰矾绾匡細exec 鑰岄潪 JNI 鍐呭祵

| 浜嬪疄 | 璇佹嵁 |
|---|---|
| fogtape / nodejs-mobile 鐨?9 涓?`libnode.so` **鍏ㄩ儴 `PT_INTERP: False`** | 閫愪釜 `llvm-readelf -lW` 瀹炴煡 |
| 杩欎簺鏄叡浜簱锛岀洿鎺ョ敤 `linker64` 褰撶▼搴忓姞杞戒細 **SIGSEGV** | 瀹炴祴 RC=139 |
| 姝ｈВ锛?*涓嶄紶 `--shared`** 缂栨垚鍙墽琛屾枃浠讹紝鏀瑰悕 `libnode.so` 鏀?`jniLibs` | `configure.py` 鐨?`--shared` 榛樿 `None` |
| 鎴戜滑鐨勪骇鐗?`e_entry=0x3898000` + `PT_INTERP=/system/bin/linker64` | 鐪?PIE |

### 3.2 Node 鏋勫缓鐨?4 涓湡瀹炲潙锛堟瘡涓兘鍚冭繃鏁板皬鏃讹級

| # | 鐥囩姸 | 鏍瑰洜 | 淇硶 |
|---|---|---|---|
| B1 | `Failed to find package 'tools'` | `android-actions/setup-android@v3` 鍐呴儴瑁呭凡绉婚櫎鐨勫寘 | 涓嶇敤璇?action |
| B2 | `yes: Broken pipe` 鍚?job 涓 | SIGPIPE + `pipefail` | 鐢ㄦ湁闄?`printf` 鏂囦欢鍠?stdin |
| B3 | `undefined symbol: android_getCpuFeatures` | zlib 瀹氫箟 `ARMV8_OS_ANDROID` 鈫?璋?NDK cpufeatures锛孨ode 涓嶉摼鎺?| 鏀?`ARMV8_OS_LINUX` 璧?`getauxval` |
| **B4** | **3 灏忔椂鍚?* `mksnapshot` 閾炬帴澶辫触 | host toolset 鐢?`OS=linux` 鍗寸户鎵?`v8_target_arch=arm64` 鈫?璧?simulator 璺緞 | 绂佺敤 V8 trap handler |

### 3.3 璁惧渚т笁椤瑰疄璇侊紙Android 14 / x86_64锛?
```
T1  nativeLibraryDir exec  鈫? exit=0  PROBE_OK
T2  filesDir exec          鈫? error=13 (SELinux app_data_file 鎷掔粷)
T3  鏃?LD_LIBRARY_PATH     鈫? CANNOT LINK: "libc++_shared.so" not found
```

**T1 vs T2 鐨勭粍鍚?*鎵嶆槸鍏抽敭鈥斺€斿悓涓€璁惧銆佸悓涓€浜岃繘鍒讹紝璇佹槑 `nativeLibraryDir` 鏄敮涓€**鍙楁敮鎸?*鐨勬墽琛屼綅缃€?**T3** 鎶?`LD_LIBRARY_PATH` 浠庢枃妗ｆ帹鏂彉鎴愬疄娴嬪繀闇€锛坆ionic 涓嶆悳绱㈠彲鎵ц鏂囦欢鑷韩鐩綍锛夈€?
### 3.4 琚鏍告帹缈荤殑 15 涓?鐪嬭捣鏉ュ"鐨勮璁?
瀹屾暣璁板綍鍦?`02-sds.md` 搂14銆傛渶閲嶈鐨?4 涓細

1. **棰勭紪璇戜欢涓嶈兘 exec** 鈥?fogtape 鏄?`--shared` 鍏变韩搴?2. **`forgiveParseErrors: true` 鏈夊** 鈥?璁╁潖璁板綍鍙樻垚 `{}` 鈫?TypeError 鈫?杩涚▼姘镐笉 listen
3. **P7 鐢?`emit(MESSAGE_RECEIVED)` 涓嶉噸缁?* 鈥?璇ヤ簨浠?`script.js` 娉ㄥ唽 0 涓洃鍚€咃紝姝ｆ枃姘镐笉鏄剧ず
4. **P11 椤跺眰璇?`DATA_ROOT` 浼氬穿** 鈥?`constants.js` 鍦?`DATA_ROOT` 璧嬪€煎墠姹傚€?
---

## 鍥涖€佷粛鏈棴鍚堢殑缂哄彛锛堣瘹瀹炴竻鍗曪級

### 4.1 鐜纭檺鍒讹紙鏈満鏃犳硶瑙ｅ喅锛?
| 缂哄彛 | 鍘熷洜 |
|---|---|
| **arm64 浜岃繘鍒朵粠鏈墽琛?* | 鏈満 x86_64 涓?QEMU2 鏄庣‘鎷掔粷 arm64 闀滃儚锛歚Avd's CPU Architecture 'arm64' is not supported by the QEMU2 emulator on x86_64 host` |
| **16KB 椤电湡鏈烘湭楠岃瘉** | 妯℃嫙鍣?`PAGE_SIZE=4096` |
| **閲忎骇 `user` ROM 鏈獙璇?* | 褰撳墠鏄?`ro.debuggable=1` 鐨?userdebug 闀滃儚锛屾瘮閲忎骇瀹芥澗 |
| **OEM ROM锛圡IUI/ColorOS锛夋湭楠岃瘉** | 鏃犺澶?|

### 4.2 宸ョ▼缂哄彛锛堝彲浠ュ仛浣嗘湭鍋氾級

| 缂哄彛 | 褰卞搷 |
|---|---|
| **APK 鏈綋鏈瀯寤?* | WebView 澹炽€丳1鈥揚12 琛ヤ竵銆佸墠鍙版湇鍔°€丳7 鑽夌鎭㈠鍏ㄩ儴鏈惤鍦?|
| ST 婧愮爜鏍戞湭鍑嗗 | 闇€瑕佷笅杞?ST 1.19.0 + `npm ci --omit=dev` + 棰勭紪璇?`lib.js` |
| P10 閴存潈鏈疄娴?| `basicAuthMode` + `setHttpAuthUsernamePassword` 鏂规宸茶璁℃湭楠岃瘉 |
| 90 MB 杞借嵎鐨勮涓哄樊寮?| 鎺㈤拡 5.5 KB vs 鐪熷疄 90 MB锛孷8 鍒濆鍖?JIT/闀块┗鏈祴 |

### 4.3 宸茬煡浣嗗彲鎺ュ彈鐨勯闄?
- **棣栨鏋勫缓闇€ ~2.5 灏忔椂**锛圴8 浠庨浂缂栬瘧锛夛紝鏃犲閲忕紦瀛?- **APK 棰勮 ~200 MB**锛圖11 淇濈暀瀹屾暣 ML 鏍堢殑浠ｄ环锛岀敤鎴峰凡纭锛?- **鍒掓帀杩涚▼鍚庢鍦ㄧ敓鎴愮殑鍥炲**渚濊禆 P7 鑽夌鎭㈠锛屾湭瀹炵幇

---

## 浜斻€佸鏋滆缁х画锛屼粠鍝噷寮€濮?
### 浼樺厛绾?1锛氳ˉ涓?arm64 瀹炴祴锛堜环鍊兼渶楂橈級

褰撳墠鏈€鍏抽敭鐨勭┖鐧芥槸"arm64 浜岃繘鍒朵粠鏈湡璺戣繃"銆備笁鏉¤矾锛?
| 鏂规 | 璇存槑 |
|---|---|
| **鐪熸満** | 浠绘剰 Android 8+ arm64 鎵嬫満锛宍adb install` 鍗冲彲 |
| 浜戞墜鏈?/ 杩滅▼璁惧 | AWS Device Farm銆丗irebase Test Lab銆丅rowserStack |
| arm64 Linux 鏈嶅姟鍣?+ QEMU 鐢ㄦ埛鎬?| 鑳借窇 `libnode-arm64` 鐨?`--version`锛屼絾涓嶆槸鐪?Android |

**鏈€灏忛獙璇佸懡浠?*锛堟嬁鍒拌澶囧悗锛夛細
```
adb push libnode-arm64 /data/local/tmp/
adb shell chmod 755 /data/local/tmp/libnode-arm64
adb push libc++_shared.so /data/local/tmp/
adb shell "LD_LIBRARY_PATH=/data/local/tmp /data/local/tmp/libnode-arm64 -e 'console.log(process.version, \"谩z\".normalize(\"NFD\"))'"
```
鑻ヨ繖鏉¤兘鎵撳嚭 `v24.22.2 谩` 骞舵甯搁€€鍑猴紝**SDS 搂11.3 鐨勪袱椤规牳蹇冩湭楠岃瘉椤瑰悓鏃跺叧闂?*銆?
### 浼樺厛绾?2锛氭惌 APK 楠ㄦ灦

闇€瑕侊細ST 婧愮爜鏍?+ P1/P2 琛ヤ竵 + WebView Activity + `ProcessBuilder` 鍚姩閫昏緫銆?`exec-proof/` 宸茬粡鎶婃渶闅剧殑 exec 閮ㄥ垎楠岃瘉閫氫簡锛屽彲浠ョ収鎶勩€?
### 浼樺厛绾?3锛氭寔涔呭寲灞?
D-P1~D-P4 + P6 + P7锛岃繖浜涙槸"宕╂簝涓嶄涪鏁版嵁"鐨勬牳蹇冿紝涓?*鍙互鍦?x86_64 妯℃嫙鍣ㄤ笂瀹屾暣楠岃瘉**锛堜笉渚濊禆 arm64锛夈€?
---

## 鍏€佷竴鍙ヨ瘽缁忛獙

> **杩欎釜椤圭洰閲屾墍鏈?鐪嬭捣鏉ュ"鐨勭粨璁猴紝鏈変竴鍗婃槸閿欑殑銆?*
> 15 涓鎺ㄧ炕鐨勮璁′腑锛屾湁 4 涓槸鎴戣嚜宸卞啓鐫€鍐欑潃灏辩‘淇′簡銆佺洿鍒板鏍告嬁瀹炴祴鎶婃垜鎵撳洖鏉ョ殑銆?> 鍞竴鍙潬鐨勫垽鍒柟寮忔槸**璺戜竴閬嶆垨璇诲埌婧愮爜琛?*鈥斺€旀枃妗ｉ噷姣忎釜 鉁?閮藉簲璇ヨ兘鎸囧嚭瀵瑰簲鐨勫懡浠や笌杈撳嚭銆?
---

## 闄勶細蹇€熺储寮?
| 鎯充簡瑙?| 鐪嬪摢閲?|
|---|---|
| 涓轰粈涔堣杩欎箞璁捐 | `docs/01-plan.md` 搂0 鍐崇瓥璁板綍锛?9 鏉★級 |
| 鍏蜂綋鎬庝箞瀹炵幇 | `docs/02-sds.md` 搂2鈥撀?1 |
| 鍝簺璁捐琚帹缈讳簡 | `docs/02-sds.md` 搂14锛?5 鏉★級 |
| 杩樻湁浠€涔堟病鍋?| `docs/02-sds.md` 搂11.3 + 鏈綊妗?搂4 |
| 鏋勫缓鎬庝箞璺?| 浠撳簱 `README.md` + `.github/workflows/build-android-node.yml` |
| exec 鎬庝箞楠岃瘉 | 浠撳簱 `exec-proof/README.md` |
| 鍘熷瀹炴祴鏁版嵁 | `.work/measure-boot.md`銆乣.work/research-*.md` |
