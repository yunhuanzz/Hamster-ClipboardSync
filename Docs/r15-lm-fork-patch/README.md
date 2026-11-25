# 第 15 轮第 1 项：本地语言模型（RIME octagram）—— LibrimeKit fork 补丁包

- 分支：`r15-lm`（自 `0eec4b3`，即 build #39 的 hotfix 之后）
- 状态：**探测 + Linux 活验证已完成；iOS fork 本身还没建**（本机无 macOS/Xcode，xcframework
  只能在 Mac 上编）。本目录的两个补丁就是建 fork 时要打的全部内容。
- 用户决定（2026-11-24 13:54）：本地模型，**不用云端**；体积 +10MB、内存大一点都无所谓。

## 1. 探测结论（先说最重要的三条）

### 1.1 xcframework 从哪来

- 键盘用的 librime 是预编译的 **`amorphobia/LibrimeKit v0.1.0`**（`librimeFramework.sh`
  下载 `Frameworks.tgz`，内含 10 个 xcframework：`librime` + boost×4 + glog + leveldb
  + marisa + opencc + yaml-cpp）。
- 它的构建脚本 `librimeBuild.sh`（v0.1.0 tag 版，全文核过）**0 处出现 "octagram"/"grammar"**，
  只装了一个插件：`imfuxiao/librime-lua@main`，然后把 lua 源码拷进 `librime/src/rime/lua`，
  并**重写 `core_module.cc`**，在 `rime_core_initialize()` 里注册 gears + lua 全部组件。
- 仓库根目录没有 `librimeBuild.sh`，`Packages/` 里也没有 grammar/octagram 引用——
  构建脚本只存在于 LibrimeKit 那个仓库里。所以接入 octagram 必须 **fork LibrimeKit
  改构建**，没有“只改本仓库就能绕过去”的路（`traits.modules` 本仓库从来没传过，
  `Rime.swift` 里 `models` 参数所有调用点都是空，改它也救不了静态链接下被
  dead-strip 的模块初始化函数）。

### 1.2 怎么注册进来（照 lua 的现成路子，一共 4 处）

`librimeBuild-octagram.patch`（打在 v0.1.0 的 `librimeBuild.sh` 上，`patch -p1` 已验证
能干净应用）做的事：

1. `install-plugins.sh lotem/librime-octagram@57d18b9f58`（pin 到 master HEAD，
   2026-08-31；浅克隆 + 该 SHA 就是 master 尖端，已实测 `git checkout <sha>` 能成功；
   失败时退回 `@master`）。
2. 只拷 6 个实现文件进 `librime/src/rime/octagram/`（`gram_db.h/.cc`、`gram_encoding.h/.cc`、
   `octagram.h/.cc`）；**不拷 `grammar_module.cc`**——它的 `RIME_REGISTER_MODULE` 会把
   `"grammar"` 再注册一次。
3. 重写后的 `core_module.cc` 里加 `#include "octagram/octagram.h"`，在 lua 注册之后加
   `r.Register("grammar", new OctagramComponent)`（附 `LOG(INFO)` 一行，运行时日志可查）。
4. 重写后的 `src/CMakeLists.txt` 里加 `aux_source_directory(rime/octagram ...)`，并把
   `${rime_octagram_src}` 放进 `rime_core_module_src`（lua 也在那里面；这样无论
   `BUILD_SEPARATE_LIBS` 开关（release 构建是关，debug 是开）都编得进去，不会重复编）。

### 1.3 上游 master 不能直接对 1.8.5 编译——差一个 7 行垫片

- lotem/librime-octagram 在 2024-02-05（`bd12863f45` "init GramDb with path" 等 3 提交）
  跟进了新版 librime 的 `rime::path` / `MappedFile::file_path()`；1.8.5 里没有 `rime::path`，
  `MappedFile` 构造只认 `const string&`，访问器叫 `file_name()`。
- `gram_db-1.8.5-compat.patch`（打在 `@57d18b9f58` 的那两个文件上，已验证应用后与
  活验证用的文件**逐字节一致**）：构造改成 `const boost::filesystem::path&` + 转
  `.string()` 传给基类，4 处 `file_path()` 日志改成 `file_name()`。纯 API 改名，零行为变化。
- 替代方案是 pin 到 2024-02-05 之前的 `a6ced5a1d6`（2023-01-25）：能省垫片，但会丢掉
  2026-07-10 的 gram_encoding 修编码 bug（`c030e30e4d`）。选了 master + 垫片。

## 2. 模型文件（实测数字，和方案里写的不一样）

| 文件 | 大小 | SHA256 | 结论 |
|---|---|---|---|
| `zh-hans-t-essay-bgw.gram`（词模型，hans 分支） | **40,925,228 字节（约 39MB）** | `d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e` | 采用（见 §4） |
| `zh-hans-t-essay-bgc.gram`（字模型，hans 分支） | 10,397,740 字节（约 10MB） | `c52deb56b1642e4f56a18926fffcb4b70385828f921bfac92c5ff4055cce5377` | **实测否决**（见 §4） |

- 方案（`Docs/language-model-proposal.md` §1.2）写的“简体模型约 10MB、IPA 28→38MB”是错的：
  10.5MB 那个数字对应的是字模型（bgc）或繁体旧数据；**词模型 bgw 实测 41MB，IPA 会到约 69MB**。
  用户当时接受的“+10MB”是按错误数字接受的，**上线前需要他按 41MB 重新点头**。
- 配置照 `lotem/rime-octagram-data` 的 `grammar.yaml` 的 `hans:` 段原样抄：
  `grammar/language: zh-hans-t-essay-bgw` + `translator/contextual_suggestions: true` +
  `translator/max_homophones: 7` + `translator/max_homographs: 7`。
  本仓库的接入方式是运行时补丁（`Packages/HamsterKit/Sources/Rime/LanguageModel.swift`，
  写法同 `FuzzyPinyin`/`T9SyllableInitials` 的 marker-block），打进
  `rime_ice.custom.yaml` / `t9.custom.yaml`，部署时重打，不改上游方案本身。

## 3. Linux 活验证（librime 1.8.5 真实构建 + 真实词库，不是推测）

- 实验目录 `~/workspace/r15lm/`（不在本仓库里）：r12 的 librime 1.8.5 源码（commit `08dd95f`）
  + 上述 6 文件 + 垫片 + `core_module.cc` 内联注册（与 fork 补丁等价的改法）+ CMakeLists，
  编译通过；`grammar` 组件注册日志、`use grammar: zh-hans-t-essay-bgw`、
  `loading gram db: .../zh-hans-t-essay-bgw.gram`、`found double array image of size 10231296`
  全部在日志里出现过。
- 验收（t9，r13 同款 userdata + r13 `rank` 探针，`#1` 指 Poet 造句的首选）：

| 用例 | 无模型基线 | 有 bgw 模型 | 说明 |
|---|---|---|---|
| 4263 → 好的 | #1 | #1 | 回归通过 |
| 64426 → 你好 | #1 | #1 | 回归通过 |
| 6269454782674464 脑子里全是你 | #1 脑子里软实力 | **#1 脑子里全是你** | 修好了 |
| 96924842692462494664 我在挑外卖中 | #1 我在天外来种 | #1 我在挑战比中 | 没修好（见 §5） |
| 3687443342628426 都是湿的好不好 | #1 都是格调不高 | #1 都是和好不好 | 没修好（见 §5） |
| 3687447443342628426 都是屁格调不高 | #1 都是格调不高 | #1 都是死的好不好 | 没修好（见 §5） |
| 26 键 wozaitiaowaimaizhong 我在挑外卖中 | #1 我在条外卖中 | #1 我再跳外卖中 | 没修好（见 §5） |

- 对照组（证明上面那行“修好了”是语言模型的功劳，不是别的改动带的）：
  新 lib + 无配置改动、新 lib + 只有 translator 三项（无 `grammar/language`），
  6 个用例的首选和基线**完全一致**。只有加上 `grammar/language` 后 C 翻正、A/B/B2 变了。
- bgc 字模型（`collocation_max_length/min_length: 2`，照 `grammar.yaml` 的 `hans_char:` 段）：
  A `#1 我在天在那个这里那个`、B `#1 的女是个的的好不好`、C `#1 那里一级全是那个`——
  造句质量比基线还差。**bgc 否决**，不要拿“10MB 更小”当理由换它。

## 4. 内存实测（键盘扩展 ~50MB 上限，方案附录标了未核实）

- 机制已核实：`GramDb : MappedFile`，`Load()` 是 **mmap 只读映射**，不是全量读入堆。
  `VmSize` 固定 +40MB（bgw）/+10MB（bgc）是地址空间，不是常驻。
- 常驻（Linux，免部署探针 `rank2`，`VmHWM`，每组 3 次，稳定）：

| 输入 | 无模型 | +bgw | 差值 |
|---|---|---|---|
| t9 4263（短） | 18.1MB | 18.3MB | **+0.2MB** |
| t9 9692484269246（13 位） | 46.9MB | 72.0MB | +25.1MB |
| t9 6269454782674464（17 位） | 57.7MB | 81.9MB | +24.2MB |
| 26 键 wozaitiaowaimaizhong | 24.5MB | 39.5MB | +15.0MB |

- 解读：差值跟着词图大小走——短输入几乎不花钱，长句九宫格（歧义最大、词图最大）
  要多碰约 24MB 的 trie 页。**Linux 的绝对值不能直接套 iOS**：无模型基线在 Linux 上
  打长句就已经 57.7MB，超过 50MB，但用户真机键盘每天打长句并没有天天被杀——
  两边常驻统计口径/词典加载方式不同。能带走的结论只有：mmap 机制 + 差值量级。
  **真机结论必须在 Xcode 里看键盘扩展的 Memory Report（打验收长句时）才能下，
  本机没有 iOS 设备和 Xcode，做不了。**

## 5. A/B/B2 为什么没修好（beam 探针实测，不是猜的）

- 临时给 `Poet` 加了 beam-dump（只在实验目录里，**不在 fork 补丁里**），
  打印最终 beam 里每条候选的全文 + 权重。结论：
  - C 的目标 `脑子里全是你` 在最终 beam 里，权重最高，赢了。
  - A/B/B2 的目标（`我在挑外卖中` / `都是湿的好不好` / `都是屁格调不高`）
    在**整个日志里一次都没出现**——在到达终点前就被剪掉了。
  - A 的最终 beam 里：`我在挑战比中 -30.5036` 赢，`我在天外来种 -42.775`、
    `我在天外卖中 -43.8383` 在列，`我在挑外卖中` 不在列。
- 根因：`Poet::BeamSearch::kMaxLineCandidates = 7`（librime 源码写死）——每步只把
  权重前 7 的 partial 展开；九宫格歧义大，`挑`（8426 里排第 6 的单字）、`湿`（744 里
  排第 20）、`屁`这种低频字在半路就被挤出前 7，后面的 `外卖/好不好/格调不高`
  再强也救不回来。26 键 A 也一样（`挑`本身在 essay 语料里接 `外卖` 的搭配太弱）。
- 这不是接线问题，是 **beam 宽度 + 语料覆盖** 的上限。改 beam 宽度是动 librime
  核心（`poet.cc` 常量，改了全局行为 + 每键算力），不在本轮做，记为后续项；
  个别顽固句仍可用 userdb 学习/自定义词组（方案 C）收尾。

## 6. .gram 怎么送到用户手里（本仓库已接好，见下面文件）

- `InputSchemaBuild.sh`：构建时从 `raw.githubusercontent.com/lotem/rime-octagram-data/hans/`
  下载 `zh-hans-t-essay-bgw.gram`，SHA256 校验（`d3cb24…`），放进
  `Resources/SharedSupport/`（**不进 git**，`.gitignore` 已加 `Resources/SharedSupport/*.gram`）。
- `Hamster.xcodeproj`：`Copy Rime SharedSupport` 阶段加了这个文件，装进安装包的
  `SharedSupport/`。**注意：它是散文件，不在 `SharedSupport.zip` 里**——因为
  `SharedSupport.zip` 只在首次运行/重置时才解压，老用户升级收不到新文件；
  散文件才能走下面的部署时拷入。
- `LanguageModel.ensureGramFile()`：部署/同步时（主 App）把安装包里的 `.gram`
  拷进沙盒 SharedSupport（缺失或大小不对才拷），部署末尾现成的
  `syncSandboxSharedSupportDirectoryToAppGroup()` 再把它同步到 App Group，
  键盘扩展从 App Group 读（`Service::CreateResourceResolver` 本来就是用户目录优先、
  共享目录后备）。`.custom.yaml` 补丁文件走现成的 `copyAppGroupUserDict` 拷回保护，
  不会被部署覆盖。
- 依赖：用户升级后要点一次「重新部署」（和其他所有补丁一样，见
  `InputSchemaViewModel`/`RimeViewModel`/`SettingsViewModel` 的调用点），
  否则补丁和 `.gram` 都不会生效。

## 7. 没做的 / 没法验证的 / 需要别人拍板的

- **没建 fork、没编 xcframework、没改 `librimeFramework.sh` 的下载地址**：需要一台 Mac
  跑 fork 里的 `librimeBuild.sh` 出新的 `Frameworks.tgz`，再把
  `librimeFramework.sh` 的 `amorphobia/LibrimeKit v0.1.0` 换成 fork 的 release。
  本机无 macOS/Xcode，做不了。
- **`ci_scripts/ci_post_clone.sh` 还是 `imfuxiao/LibrimeKit 2.3.0`**，而
  `librimeFramework.sh` 早在 `03348ba` 就改成 amorphobia v0.1.0 了（注释写 imfuxiao
  已 404）。如果 CI 还走这条路，它现在就是坏的；fork 落地时两边要一起改。
  本轮没动它（不知道 CI 是不是还在用）。
- **IPA +41MB（28→约 69MB）需要用户按真实数字重新点头**（§2）。
- **键盘扩展真机内存峰值**需要 Xcode + 真机实测（§4）。
- **A/B/B2** 需要 beam 宽度或语料层面的后续工作（§5）；用户后续发的验收长句
  先按这套流程跑一遍再看。
- 明确没做：librime 不升级（还是 1.8.5）、不做云端排序、不做热词更新。
