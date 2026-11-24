# Hamster 输入法：词库 vs 语言模型——书面方案

- 状态：**研究方案，不改代码**（第 14 轮语言模型研究）
- 基于：main 的 facd94e（build #36），分支 `round14-lm-local`
- 日期：2026-11-24
- 结论先行：**这是语言模型的问题，不是词库的问题。** 词库权重是对的，缺的是“词与词之间搭不搭”的上下文打分。主方案是本地 n-gram 语言模型（RIME 自带 octagram 机制）；云端只做备选。

---

## 0. 先说现状：已经实测确认的东西

以下每一条都在本轮研究里对着真实源码/配置文件核过，不是推测。

### 0.1 当前构建里根本没有语言模型

- librime 1.8.5 源码（`~/workspace/r12/librime`，commit `08dd95f`，与 `InputSchemaBuild.sh` 用的 `rime_version=1.8.5 / rime_git_hash=08dd95f` 一致）：
  - `src/rime/gear/grammar.h`：`Grammar` 只是一个抽象类。`Grammar::Evaluate()` 里写死了 `kPenalty = -18.420680743952367`（即 `log(1e-8)`）：**没有 grammar 时，每个词不论上下文一律扣 18.42 分**。
  - `src/rime/gear/poet.cc`：`Poet` 构造时调 `Grammar::Require("grammar")`；拿不到就 `grammar_ == nullptr`，`MakeSentence` 走单线动态规划（`DynamicProgramming`），句子分 = 词典权重对数和 − 18.42×词数；拿到了才走束搜索（`BeamSearch`，每状态保留 7 条候选）。`Line::context()` 只回看前 2 个词。
  - `src/rime/dict/dict_settings.cc`：`kDefaultVocabulary = "essay"`——`essay.txt` 是**建词典时用的预设词汇表**，和语言模型是两个东西，别混淆（见 §1.4）。
- `rime_ice.schema.yaml`（雾凇拼音 2026-03-08 版，build 时从 `github.com/iDvel/rime-ice` 现场 clone）：全文 852 行，**没有任何 `grammar:` 配置**；`translator:` 下也没有 `contextual_suggestions`、`max_homophones`。`melt_eng` 明确 `enable_sentence: false`。
- 本仓库 `grep grammar|essay|octagram`：唯一命中是 `InputSchemaBuild.sh` 里 `plum install prelude rime-essay`（只装了 essay 词表，没装语言模型数据）。

### 0.2 更关键的一点：当前 librime 构建里连加载语言模型的插件都没有

- 键盘用的 librime 是预编译的 `amorphobia/LibrimeKit v0.1.0`（`librimeFramework.sh` 下载 `Frameworks.tgz`）。它的构建脚本 `librimeBuild.sh`（v0.1.0 tag 版，全文核过，**0 处出现 "octagram"**）只装了一个插件：`imfuxiao/librime-lua`，然后把 lua 源码拷进 `librime/src/rime/lua`，并重写 `core_module.cc`，在 `rime_core_initialize()` 里注册 gears + lua 全部组件。
- 10 个 xcframework 是：`librime` + `boost_atomic/filesystem/regex/system` + `libglog` + `libleveldb` + `libmarisa` + `libopencc` + `libyaml-cpp`——没有独立的 octagram 框架；而重写后的 `core_module.cc` 里也没有注册任何 `grammar` 组件。
- 所以现状是双重缺失：**既没有 `.gram` 模型文件，也没有能读它的插件代码**。就算现在把 `.gram` 文件丢进用户目录，`Grammar::Require("grammar")` 依然返回空，行为不会有任何变化。
- 注意：网上有资料写 "Hamster bundles the librime-octagram plugin"（例如 SSARCandy 的 rime-bopomofo-t9 说明），那指的是上游 Hamster 用的另一套 LibrimeKit 构建，**不能套用到本仓库现在用的 amorphobia v0.1.0**。实施前必须实测验证（见 §1.6 验证清单第一条）。

### 0.3 第 13 轮三个长句例子，根因归类

| 例子 | 根因 | 语言模型能不能帮 |
|---|---|---|
| 挑 / 天（单字同音选错） | 词典权重本身是对的语料频率（第 13 轮结论）；错在**没有上下文**：当前打分看不出“前面那个词后面跟 天 更顺还是跟 挑 更顺” | **部分能**。只有当区分性的上下文落在前 2 个词以内时才有效（octagram 的上下文窗口，见 §1.3）；光杆单字、无上下文时帮不了 |
| 都是屁格调不高 | 同上：分词/选词全靠单字词频相加，“是屁”这种搭配在语料里极罕见，但当前打分器不知道 | **很可能改善**。“格调不高”是强搭配；“都是屁”在模型里会吃到重罚，整句排名会被“都是…格调不高”的正确切分超过 |
| 难以计算是你（想打“脑子里全是你”） | 同上，叠加一层：这是九宫格数字输入下的歧义切分；两个候选串都是“合法词拼出来的句子”，只拼词频分不出高下 | **可能改善，但不保证**。“脑子里全是你”是高频口语搭配，“难以计算是你”语义别扭、搭配弱；但前提是该数字串确实能切出“脑子”这个候选——如果候选根本不在词图里，语言模型也变不出来，需实施时拿真机按键序列验证 |

共同点：**三个都不是“词库里缺词”或“权重标错”**，而是“所有候选都是合法词，缺一个按搭配 plausibility 排序的裁判”。这正是语言模型干的活。

---

## 1. 方案 A（主方案）：本地 n-gram 语言模型——RIME octagram

### 1.1 机制：RIME 自带，不用发明轮子

语言模型在 librime 里的官方实现就是 **librime-octagram**（“八股文”插件，`github.com/lotem/librime-octagram`，BSD-3-Clause，2019 年建库，50 stars；2026-07 还有人在修编码 bug，核心稳定；Debian 官方打包了 `librime-plugin-octagram`，1.8.5 和 1.17.0 都有，说明它能对得上我们这个 1.8.5 版本）。

工作原理（对着 `src/octagram.cc` 读的，不是文档转述）：

- 方案配置里写 `grammar/language: zh-hans-t-essay-bgw`，插件就去加载同名 `.gram` 文件（资源类型 `{"gram_db", "", ".gram"}`；解析顺序在 `service.cc` 里写死：**用户数据目录优先，共享数据目录为后备**——所以 `.gram` 放用户目录或随安装包放共享目录都行）。
- `.gram` 是 n-gram 统计库（double-array trie 存的，`GramDb`）：对每个候选词，拿它前面最多 3 个字做上下文去查“上下文 + 这个词”在语料里出现过没有、多常见，返回一个对数概率分。
- 查不到搭配时给固定罚分。默认参数（`octagram.cc` 里 `GrammarConfig` 的默认值）：`collocation_max_length 4 / collocation_min_length 3 / collocation_penalty -12 / non_collocation_penalty -12 / weak_collocation_penalty -24 / rear_penalty -18`。
- 关键变化：装上之后，**每个词的基础罚分从 -18.42 变成 -12**，而真实搭配会在此基础上再加一个语料概率分；于是“有搭配”和“没搭配”的句子之间拉开了分差，`Poet` 也从单线动态规划升级成束搜索（每步保留 7 条）。另外 `translator/contextual_suggestions: true` 会让**下一段输入**也参考已上屏的文字（`script_translator.cc`：`GetPrecedingText` 取当前段之前的已输入文字或上一次提交记录）来加权候选——长句连续输入时越打越准。

一句话：**它不改变词库、不改权重，只在现有候选之上加一层“搭配合理性”打分**。这正好对症。

### 1.2 模型文件：有现成的，不用自己训

- 数据仓库 `github.com/lotem/rime-octagram-data`（LGPL-3.0，100 stars），`hans` 分支里就有简体模型现成文件：
  - `zh-hans-t-essay-bgw.gram`——**词模型**（bgw = 词组），配简化字为主的词典用，就是我们要的；
  - `zh-hans-t-essay-bgc.gram`——字模型（bgc），适合习惯把词拆成单字输入的用户。
- 配套配置文件 `grammar.yaml`（同一仓库 master 分支）已经写好了补丁，简体版原样照抄就行：

```yaml
hans:
  grammar:
    language: zh-hans-t-essay-bgw
  translator/contextual_suggestions: true
  translator/max_homophones: 7
  translator/max_homographs: 7
```

- 也就是说方案侧的改动就是往 `rime_ice.custom.yaml`（和 `t9.custom.yaml`，九宫格是独立方案，必须两边都打——部署代码里两个补丁文件本来就是一起维护的，见 `RimeContext.deployment()`）里加上面这段 patch。补丁机制现成，不用新写部署逻辑。
- 体积：繁体模型有实测记录约 **10.5 MB**（SSARCandy 提交说明）；简体模型同量级，实施时以下载实测为准。build #36 的 IPA 是 29,523,508 字节（约 28 MB），**加进去约 +35%**，到 ~38 MB。两个选择：随安装包打包（简单、离线可用、体积一次到位），或首次启动后按需下载（IPA 不变大，但多一次下载、首次部署变复杂）。建议先随包打包，简单可靠。
- 内存：`ClipboardSyncService.swift` 里注明键盘扩展内存上限约 50 MB。`.gram` 是 10 MB 级文件，`GramDb::Load()` 的加载方式（mmap 还是全量读入）**实施时必须实测**，确认键盘扩展里加载后不超限。这是本方案唯一需要实测才能排除的风险点之一。

### 1.3 语料从哪来（版权/来源交代）

- `.gram` 是拿 `essay.txt` 语料做 n-gram 统计，再用插件自带的 `tools/build_grammar.cc` 编译出来的（输入是“词 + 频次”行，输出 `<language>.gram`）。
- `essay.txt` 来自 `github.com/rime/rime-essay`（“八股文”，LGPL-3.0）：RIME 官方的预设词汇表及语言模型语料，本仓库 `InputSchemaBuild.sh` 已经用 plum 装了它——**语料源头本来就在我们的构建依赖里**，只是之前只用它建了词典，没用它建语言模型。
- 出处说明（上游原话）：配方文件“以開放的互聯網語料精煉而成，全程自動處理，絕無人工干預”。即：开源互联网语料、无人工审核、LGPL-3.0。接受这个，就能直接用现成 `.gram`；不接受，就得自己找语料重建（见 §1.5）。
- 其他开源中文语料如果将来要自建模型：CLUECorpus2020、THUCNews 等是常见选择；LDC 的 Chinese Web 5-gram 语料是授权收费的（约 30 GB 压缩包），不推荐。**但第一阶段完全没必要自建**——先用现成模型验证效果，差了再谈自建。

### 1.4 两个容易混淆的概念，先划清

- **`essay.txt` ≠ 语言模型**。它是建词典时的词汇表来源（`dict_settings.cc` 的 `kDefaultVocabulary = "essay"` 指的就是这个）。装了 rime-essay 不等于装了语言模型——这正是 build #36 的现状：词典有 essay 词表，语言模型是空。
- **词模型（bgw）vs 字模型（bgc）**。雾凇是整词输入为主，首选 bgw；bgc 是给单字输入习惯准备的。先上 bgw。

### 1.5 工期估算（主方案）

| 步骤 | 内容 | 估算 |
|---|---|---|
| 1. 探测 | 确认当前 LibrimeKit 构建到底有没有 octagram（查 xcframework 符号 / 运行时日志看 `Grammar::Require("grammar")` 是否为空） | 0.5 天 |
| 2. 接入插件 | 二选一（见 §4 决策点 2）：(a) 在 amorphobia/LibrimeKit 构建脚本里加 `install-plugins.sh lotem/librime-octagram`，照 lua 的样子把源码拷进 `librime/src/rime/` 并在 `core_module.cc` 里注册 `r.Register("grammar", new OctagramComponent)`；(b) 不动 LibrimeKit，在 Hamster 自己的构建里另起静态模块。lua 的先例证明 (a) 的路是通的 | 1–2 天 |
| 3. 模型与配置 | 下载 `zh-hans-t-essay-bgw.gram`，放进打包流程；`rime_ice.custom.yaml` + `t9.custom.yaml` 加 hans 补丁；部署时保证 `.gram` 不被增量复制逻辑误删（现有 `deployment()` 对 `.custom.yaml`、`.userdb` 有白名单式保护，`.gram` 要确认走哪条路径） | 0.5–1 天 |
| 4. 测试调优 | 固定测试集（见 §1.6）前后对比；确认键盘内存；如有需要调 `collocation_penalty` 等参数 | 1 天 |
| **合计** | | **约 3–5 天**（若插件在 iOS 静态构建上要额外移植，+2 天） |

### 1.6 预期改善（定性，按 §0.3 的例子）

- **能明显改善的**：多字词的搭配排序（“格调不高”这类）、长句切分（ beam search 保留 7 条候选，不再一条道走到黑）、连续输入的后段（`contextual_suggestions` 看得到前文）。
- **改善有限的**：无上下文的单字同音选择（挑/天在光杆情况下）；超出 2 个词回看范围的长距离搭配（octagram 本质是短窗口 n-gram，不是语义理解）。
- **完全帮不了的**：词库里没有的词、syllabifier 剪枝类 bug（第 13 轮 4263 那种）、部署时 userdb 被覆盖这类工程问题（第 14 轮第 1 项是另一回事）。
- **验收办法（实施前先定）**：固定 10–20 条用户日常常打的长句（把 §0.3 的三条放进去），记录装模型前后每条首选候选的变化；同时抽查单字输入、九宫格、短词输入**没有退化**（`max_homophones: 7` 会改变进入词图的同音字数量，短输入也可能受影响，必须回归）。

---

## 2. 方案 B（备选）：云端语言模型 / 云词典

### 2.1 服务器端：现成的，放得下

- BWG MegaBox Pro（95.181.188.70）现状：Xray、Hysteria2（UDP 8443）、Komari（Caddy 反代 8443）、Docker 已装。加一个轻量排序服务（例如 Python + FastAPI）在资源上毫无压力；Caddy 再加一个反代端口即可（之前 SyncClipboard 就是这么挂的，8444——那套已拆除，端口可复用）。
- 但注意：如果云端只是部署**同款 n-gram 模型**（KenLM 之类），那它在质量上和本地 octagram 是同一档，纯多出 150ms 延迟——**没有意义**。云端唯一有质量优势的形态是**神经网络重排序模型**（例如 `metasequoiaime/chinese-ime-lm` 这类专为拼音输入法做的字符级重排序小模型，4M 参数 int8 约 4.5 MB、25M 参数约 25.5 MB），它能学到 n-gram 学不到的长距离搭配。

### 2.2 键盘侧注入：这是最难的部分（第 5 轮已评估过）

- 网络本身不是问题：键盘扩展里已经有现成的联网代码——`ClipboardSyncService`（`URLSession`）在键盘出现时就同步（`KeyboardInputViewController.swift:56 syncOnKeyboardAppear`）。所以“键盘能不能联网”已验证。
- 难的是**把云端结果塞进 RIME 的选词流程**：
  - RIME 的翻译是**同步、进程内**的，`ScriptTranslator::Query` 里没有异步候选注入的钩子。没有“等云端回来了再补几个候选”的官方机制。
  - 路线 B1（同步查云）：每个按键都等一次网络往返再出候选——按 Komari 实测福建电信 → 洛杉矶 CN2 GIA 约 153–158ms，**每键 ≥150ms 延迟**，打字会明显发粘，不可用。
  - 路线 B2（异步合并）：本地先出候选，后台请求云端，回来后再刷新候选栏重排——要动 Swift 侧候选 UI 与 RIME 会话状态的协同，复杂度最高；还要处理“云端回来前用户已经选词上屏”的竞态。
  - 路线 B3（云词典同步）：只同步词组/权重表，不逐键联网——技术上就是 SyncClipboard 的翻版，简单；但它**不解决长句排序问题**（见 §3），等于白做。
- 第 5 轮给云词典的估算是 2–4 天，难的正是键盘侧注入。云端神经网络重排序（B1/B2 形态）要再加服务端模型 + 协议 + 异步合并 + 降级 fallback，**估算 1–2 周**，且要长期维护服务端。

### 2.3 延迟与隐私

- 延迟：RTT 约 150ms 是物理距离决定的（福建 → 洛杉矶），改不了。本地输入的可接受延迟是每键几十毫秒以内；云端只适合“整句打完后重排一次”这种低频操作，不适合逐键。
- 隐私：**输入内容要上云**。哪怕服务器是自己的 BWG，数据也要离开手机：键盘敲的每一个字（包括密码框外的聊天、工作内容）都会经过网络。必须做到：全程 HTTPS、服务端不记日志、不存原始输入；且这件事**必须用户明确点头**（见 §4 决策点 4）。iOS 键盘“完全访问”权限本来就已经开了，但“发到自己服务器”和“只在本地算”是两回事。

### 2.4 小结

云端不是不能做，而是**投入产出比目前很差**：质量上唯一能赢本地的形态（神经网络重排）成本最高、延迟最差、还要过隐私这一关。建议只作为“本地模型验证后仍不满意”时的第二阶段。

---

## 3. 方案 C：只改本地词库权重 / 自定义词组——上限说清楚

这是零成本、现在就能做的事，也是第 12–13 轮一直在用的手段，但必须说清它的天花板。

### 3.1 能改善什么

- **个案修复**：某个词总排错，加一条自定义词组（`custom_phrase.txt`，`initial_quality: 99`）或 pin 置顶（rime_ice 已内置 `pin_cand_filter`，`d→的、m→吗` 就是这么干的）就能立刻修好。
- **个人高频词**：用户自己的常用句式、名字、术语，靠 userdb 学习（第 12 轮 F24 落盘修复后已确认工作）越用越准。
- **确实缺的词**：词库里没有的词，补进去就有了。

### 3.2 改善不了什么（结合第 13 轮结论）

- **长句排序是组合问题，不是词频问题**。一个 10 字长句有指数级种切分，单字词的权重是上下文无关的：为修 A 句把“挑”调高，就会在所有 B 句里压过“天”。第 13 轮已经确认：天 / 条 / 格调这些权重**都是正确的语料频率**，不该动——动了就是拆东墙补西墙。
- **自定义词组只认 exact match**。用户得事先把句子登记进去才生效；没登记过的句子、换个说法，一点都帮不上。覆盖面永远追不上日常输入的组合数。
- **它和语言模型是互补，不是替代**。词库管“有没有这个词”，语言模型管“这些词搭在一起顺不顺”。第 13 轮的三个例子全是后者，所以只改词库到顶也修不好。

### 3.3 结论

方案 C 作为日常维护继续做（成本为零），但**不要指望它解决用户这次提的问题**。把它当作 A 方案的配套（A 上线后，个别顽固个案再用 C 收尾），而不是 A 的替代品。

---

## 4. 推荐与决策

### 4.1 推荐

**主方案 A：本地 octagram（先用 lotem 预编译简体词模型 `zh-hans-t-essay-bgw.gram`），约 3–5 天。**

理由：唯一同时满足——对症（直接补上确认缺失的 grammar 环节）、零延迟、零隐私成本、可逆（一个补丁 + 一个文件，关掉就回滚）、有官方现成模型不用训。云端（B）在 A 验证不满意之前不启动；词库微调（C）继续作为日常配套。

**备选顺序**：A →（若 A 验收不达标）B-神经网络云端重排 →（远期）本地神经网络重排序（`chinese-ime-lm` 4M 模型，4.5 MB，可跑在端侧；但要接 CoreML/ONNX，工作量不在本轮评估内，先记一笔）。

**明确不推荐**：升级 librime 到 1.17 换 `max_sentences` 等新特性——1.8.5 的整套构建（LibrimeKit、lua 插件、部署逻辑）都是对着 1.8.5 调通的，升级是另一个大工程，且与本次问题无关。

### 4.2 需要用户决定的点

1. **App 体积 +10 MB 接受吗？**（IPA 约 28 MB → 约 38 MB。）接受就随包打包；不接受就改首次启动后按需下载。
2. **LibrimeKit 构建要不要 fork？** 接入插件需要在 amorphobia/LibrimeKit 的构建脚本里加 octagram（照 lua 的现成路子）。这意味着我们要维护自己的一份 librime 构建分支，上游更新时自己合。替代做法是先只做探测（§1.5 步骤 1），确认插件确实缺失后再定——**建议先探测，探测结果出来再由你拍板 fork 与否**。
3. **语料接受 lotem 预编译模型吗？** LGPL-3.0、互联网语料、无人工审核（上游 README 有免责声明）。接受就直接用；不接受就得走自建语料路线（工期 +1 周起，且效果未必更好）。
4. **云端（备选 B）是否允许输入内容上云？** 主方案 A 不需要决定这个；只有 A 验收不达标、要启动 B 时才需要你点头。现在不用答，先知道有这回事。
5. **验收标准**：请给 10–20 条你日常常打、现在排得不准的长句（§0.3 的三条已在内），实施时按这个清单前后对比，达标才算做完。

### 4.3 实施前验证清单（给下一轮执行代理）

- [ ] 探测：当前 LibrimeKit v0.1.0 是否含 octagram（查符号 / 运行时日志确认 `Grammar::Require("grammar")` 为空）。
- [ ] `.gram` 下载实测：`zh-hans-t-essay-bgw.gram` 的准确大小、SHA，确认 `hans` 分支文件未变。
- [ ] 键盘扩展内存：加载 10 MB 级 `.gram` 后，键盘进程内存峰值（上限约 50 MB）。
- [ ] 回归：单字、短词、九宫格输入在 `max_homophones: 7` 下无退化；t9 与 rime_ice 两方案都打补丁。
- [ ] 部署路径：`.gram` 放在用户目录还是共享目录；确认不被 `deployment()` 的增量复制/清理逻辑误删。
- [ ] 验收：§4.2 第 5 点的句子清单，前后对比记录。

---

## 附录：核查过的资料来源

- librime 1.8.5 源码（本地 `~/workspace/r12/librime`，commit `08dd95f`）：`src/rime/gear/grammar.h`、`src/rime/gear/poet.{h,cc}`、`src/rime/gear/script_translator.cc`、`src/rime/gear/translator_commons.cc`、`src/rime/dict/dict_settings.cc`、`src/rime/service.cc`、`src/rime/resource.cc`、`src/rime/setup.cc`、`data/minimal/essay.txt`。
- `rime_ice.schema.yaml`（雾凇拼音 2026-03-08，`raw.githubusercontent.com/iDvel/rime-ice/main/rime_ice.schema.yaml`，2026-11-24 实取）：全文无 `grammar`。
- `lotem/librime-octagram`（`src/octagram.{h,cc}`、`tools/build_grammar.cc`，master，2026-11-24 实取）：`grammar/language` 配置键、默认罚分参数、`.gram` 资源类型。
- `lotem/rime-octagram-data`（`grammar.yaml`、`customize.recipe.yaml`、README、`hans` 分支文件列表，2026-11-24 实取）：`hans` 补丁原文、LGPL-3.0、互联网语料免责声明。
- `rime/rime-essay`（README，2026-11-24 实取）：“預設詞彙表及語言模型”，LGPL-3.0。
- `amorphobia/LibrimeKit`（`librimeBuild.sh` v0.1.0 tag 版与 main 版、`Package.swift`，2026-11-24 实取）：只装 lua 插件，全文 0 处 "octagram"；10 个 xcframework 清单。
- 本仓库：`InputSchemaBuild.sh`、`librimeFramework.sh`、`Packages/RimeKit/Sources/Swift/Rime.swift`（`traits.modules` 机制）、`Packages/HamsterKeyboardKit/Sources/RimeContext/RimeContext.swift`（`deployment()` 补丁白名单）、`Packages/HamsterKit/Sources/ClipboardSync/ClipboardSyncService.swift`（键盘扩展内 `URLSession` 联网已验证、键盘内存上限约 50 MB 注释）。
- 未能核实、留待实施时确认的数字：`zh-hans-t-essay-bgw.gram` 的精确大小（繁体模型约 10.5 MB 有据，简体同量级；本轮 GitHub API 查询被 403 拒绝，未拿到 hans 分支文件元数据）；`.gram` 在键盘扩展内的加载方式（mmap 或全量读入）。
