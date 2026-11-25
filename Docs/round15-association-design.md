# 第 15 轮第 2 项：联想词 + 英文纠错——设计

- 分支：`r15-assoc`（基于 `051128e`，build #38）
- 范围：只做第 2 项。(a) 联想词 (b) 英文纠错。本地语言模型（octagram）由另一路代理并行做（worktree `~/workspace/hamster-round15-lm`），本设计与它衔接但不依赖它、不改它的文件。
- 状态：设计 + 实现（Swift 只能写不能编译，本机无 Swift 工具链；见 §6 验证）。

---

## 0. 用户原话

- 2026-11-24 13:54：联想词。例子：打“大江东去”就联想“浪淘尽”，再打就联想“千古风流人物”。
- 2026-11-24 14:22：顺便看看能否给英文输入法添加错词纠错功能。

---

## 1. 活验证结论（先说结果，证据在 §5）

### 1.1 octagram / `contextual_suggestions` 覆盖不了用户的例子

三条活验证（本机 librime 1.8.5 + `~/workspace/r13probe/` 的 rank 探针，新写 `assoc.c` 双阶段探针，见 §5）：

1. **词库里有这三句，打全了都是 #1**：`dajiangdongqu`→大江东去 #1，`langtaojin`→浪淘尽 #1，`qiangufengliurenwu`→千古风流人物 #1（默认 rime_ice 合并词库，via `cn_dicts/base` import）。
2. **上文提交不改变任何排名**：先提交“大江东去”再打 `langtaojin`，浪淘尽仍是 #1；提交不相干的“你好”再打，同样 #1；新会话不提交直接打，同样 #1。三者候选表逐字相同。
3. **`translator/contextual_suggestions: true` 开了也一样**：复制一份 userdata 打上该补丁、重新部署（deployer exit 0，编译出的 `rime_ice.schema.yaml:901` 确认含 `contextual_suggestions: true`），A/B/C/D 四组探针结果与基线逐字相同。

根因（源码，不是推测）：`src/rime/gear/poet.h` 的 `ContextualWeighted` 第一行就是：

```cpp
if (!translator->contextual_suggestions() || !grammar_) {
  return translation;
}
```

没有 grammar 组件时，这个开关是死的。`MakeSentence` 里 `Grammar::Evaluate` 在 `grammar_ == nullptr` 时对每个词一律扣固定的 `-18.42` 分，`preceding_text` 传进去也被忽略。启动日志里注册的组件也没有任何 `grammar`（grep 计数 0）。这与第 14 轮语言模型提案（`Docs/language-model-proposal.md` §0.2“双重缺失”）一致，本轮在运行时又验证了一遍。

### 1.2 更关键的一点：就算 octagram 装上了，也做不出用户的例子

octagram 只能给**已经打出来的输入**的候选重排序（`ContextualTranslation` 包住一个已有的 translation；`MakeSentence` 只给词图里已有的词条打分）。它永远变不出一个**零输入**的候选：

- 用户打完“大江东去”上屏后，什么都没输，候选栏是空的——octagram 没有任何机制在这里变出“浪淘尽”。
- 只打一半 `langtao` 时，浪淘尽根本不在候选里（活验证：NOT FOUND，因为“尽”的音节还没输）——重排序救不了不存在的候选。

所以**联想词必须有一层引擎之外的客户端机制**：提交后按“上一段”查一张“下一句”表，直接出候选。octagram 落地后两者是互补关系，不是替代关系（见 §4）。

### 1.3 专门的联想语料/词典：需要，为什么

需要。理由就是 1.2：引擎侧（无论有无 LM）都出不了零输入的下一句。数据分两层：

- **内置表（seed）**：手选名篇名句的“上一句→下一句”链，约 17 条链、~75 对（见 `AssociationStore.swift`）。全部是公有领域古诗文（作者逝世数百年），不用授权、不用下载。体积：源码约 6 KB，运行时常驻可忽略。来源以 `gushiwen.cn` 为准核对过锚点诗《念奴娇·赤壁怀古》全文；其余是中小学课本级名篇（静夜思、春晓、登鹳雀楼等），异文在注释里标出（如樯橹/强虏、尊/樽）。
- **学到的对子（learned）**：用户自己连续提交的两段（上一段→这段），记进 App Group UserDefaults，最多 50 条，展示时只取出现过 ≥2 次的（一次可能是两句不相干的话恰好连着打）。这样用户常打的口头禅接龙（比如自己的名字/口号）也能联想，不用等语料扩充。

以后扩充内置表的正规路：从开源古诗文集（如 GitHub `chinese-poetry`，公有领域）按“句→下一句”自动抽表替换 seed，不用改机制。

---

## 2. (a) 联想词设计

### 2.1 触发

- **唯一触发点**：`RimeContext.syncContext()` 里“提交刚发生”的分支（`!isComposing && commitText 非空`）。提交的文字就是 key。
- 匹配：先精确匹配整段提交文字；没有则取提交文字的最长后缀（≥2 字）匹配——用户一段提交里可能含多个分句（一次上屏整句），后缀能接上链（例：一次提交“大江东去浪淘尽”，后缀“浪淘尽”→“千古风流人物”）。
- 只对中文（≥2 字且含 CJK）触发；字母/数字/符号提交不断链以外不触发（`previousCommitText` 在空提交时清掉，联想链断开）。
- **点选联想本身也是触发**：点“浪淘尽”上屏后，立刻按“浪淘尽”查下一句（“千古风流人物”），链不断。这是用户例子里“再打就联想”的实现方式——不用再打，点一下就接下一句；正常打字提交下一句也一样接。
- 退格删掉刚提交的词（`undoLastCommit`）时链断开（`previousCommitText` 清掉）。

### 2.2 排序

内置表在前（按 seed 链顺序），学到的对子在后（按出现次数倒序），去重，总共最多 5 个。首个标 `isAutocomplete`（与现有候选栏“首选高亮”的视觉一致）。

### 2.3 出现位置与样式

- **位置**：现有候选栏本身，不另起一行、不新开面板。联想词复用 `CandidateWordsCollectionView` / `CandidatesPagingView` 的 cell 与 `CandidateBarStyle`（字号、颜色、高亮底色全走现有样式，`isAutocomplete` 的首选底色是 cell 现成的）。
- **显隐**：候选栏平时由 `userInputKey`（组字态）控制显隐；联想/纠错出现时 `userInputKey` 是空的，原逻辑会把栏藏起来。所以 `KeyboardToolbarView.combine()` 多订一个 `rimeContext.$externalSuggestionsKind`：kind 非空时栏显示、工具栏隐藏；kind 回空时按 `userInputKey` 的老逻辑恢复。
- **两种分页模式都覆盖**：划动分页（`CandidateWordsCollectionView`，直接读 `rimeContext.suggestions`）天然支持；手动分页（`CandidatesPagingView`，原来只读引擎 `$rimeContext`）补一个 `$suggestions` 订阅：kind 非空时按外部建议出快照，清掉时按当前引擎 context 重出一次（用 `isShowingExternalSnapshot` 标志避免正常打字时重复出快照）。

### 2.4 点选上屏的完整链路

```
用户点联想词
  → CandidateWordsCollectionView.didSelectItemAt
    / CandidatesPagingView.didSelectItemAt
  → RimeContext.selectCandidate(index:)
    → 分支：externalSuggestionsKind == .association（不是引擎下标，不碰引擎）
    → 记 previousCommitText = 该词（链不断）
    → onApplyAssociationText?(text) —— 回调给 VC
      → KeyboardInputViewController.insertTextPatch(text) 写文档
    → RimeContext.showAssociationSuggestions(afterCommit: text) 链下一句
      （无下一句则栏清空收起）
```

关键点：联想词的 `CandidateSuggestion.index` 是 `-1`（没有引擎下标），`selectCandidate` 必须在算 `engineIndexForDisplayIndex` 之前先分支，否则会拿 `-1` 去选引擎。`nextPage()`（翻页查引擎）在外部建议显示时直接返回；长按菜单（忘掉/置顶）对外部项没有意义，两个候选视图的长按处理里直接 return；`forget/pin/isPinned` 内部也 guard。

### 2.5 与现有行为的隔离

- 外部建议与引擎建议共用 `suggestions` 一个数组（候选栏只认这一个数据源），用 `externalSuggestionsKind: .none / .association / .englishCorrection` 区分。引擎建议每次写入都走 `setEngineSuggestions()`（同时把 kind 置 `.none`），所以中文打字一开始联想就消失，不会串台。
- `reset()` 清 kind；切输入法/切中英/切方案都走 `reset()`，联想不跨键盘残留。
- 不动词库、不动部署、不动 `rime_ice.custom.yaml`（`contextual_suggestions` 开关经活验证是死的，不加）。

---

## 3. (b) 英文纠错设计

### 3.1 结论：可行，用 UITextChecker

- `UITextChecker` 是 UIKit 自带拼写检查（`rangeOfMisspelledWord` + `guessesForWordRange` + `completionsForPartialWordRange`），系统词典，扩展内存成本 0（另一家 iOS 键盘 Dictus 的 2026 架构文档也是这么用的：UITextChecker 做补全/纠错，0 MB）。
- 有现成先例：`ansonl/ios-uitextchecker-autocorrect` 就是给“iOS app 或 custom keyboard extension”写的，Combo Keyboard 扩展在用，做法是空格时取 `guessesForWordRange` 的首个 guess 自动纠正。
- 已知 quirks（照抄进实现，不踩坑）：
  - iOS 上 guesses 的顺序接近字母序而非概率序（文档说按概率，实测不是）——所以只信首个 guess 做空格自动纠正，其余只当点选候选。
  - `completions` 在 iOS 上也是字母序——只当点选补全，不自动上屏。
  - 25+ 字母的词会被当成没错——provider 里词长上限 24，直接不查。

### 3.2 现有英文键盘的钩子（查过代码，全是现成的，只差接线）

- **输入路径**：英文 26 键 `keyboardType.isAlphabetic` 时，`KeyboardInputViewController.insertText` 直接 `textDocumentProxy.insertText`，**完全不走 RIME**（`melt_eng` 方案在英文键盘下是摆设）。所以纠错不能走引擎，只能走 KeyboardKit 的 autocomplete 管线。
- **管线全套现成、全部被注释/禁用**：
  - `AutocompleteProvider` 协议 + `AutocompleteContext.suggestions`（@Published）+ `KeyboardInputViewController.performAutocomplete()` / `insertAutocompleteSuggestion(_:)`（调 `textDocumentProxy.insertAutocompleteSuggestion`，即替换当前词 + 可选补空格）。
  - `StandardKeyboardActionHandler.tryApplyAutocompleteSuggestion`（空格上屏前应用首个 `isAutocomplete` 建议）存在，但两个 `handle()` 里的调用都被注释掉了；`tryRemove/tryReinsertAutocompleteInsertedSpace`（点选后自动补的空格，输标点时删掉）同样被注释。
  - `CandidateWordCell` 已有 `isAutocomplete` 的渲染（首选底色 + 专用文字色），即系统键盘白底圆角那套。
  - 唯一缺的：一个真的 provider（现在是 `DisabledAutocompleteProvider`）、一个触发点（`textDidChange` 里的 `performAutocomplete()` 被注释了）、一个显示面（候选栏平时只认 RIME 的 `suggestions`）。
- **显示面复用联想词同一套**：纠错候选也进 `rimeContext.suggestions`（kind=`.englishCorrection`），走 §2.3 的候选栏与显隐逻辑，不新造 UI。

### 3.3 实现

- 新 provider `EnglishSpellcheckAutocompleteProvider: AutocompleteProvider`（`UITextChecker`，`en_US`）：
  - 词长 2–24、只含字母/`'` 才查；否则 `[]`。
  - 拼错：`guesses` 取前 4 个（去重、去空格多词、去掉被忽略的），首个 `isAutocomplete=true`（空格自动纠正它），其余点选。
  - 拼对：`completions` 取前 3 个（词长 ≥3 才补全），全部 `isAutocomplete=false`（只点选，空格不应用）。
  - `learnWord/unlearnWord/hasLearnedWord` 透传 `UITextChecker` 静态方法（系统级生词）；`ignoreWord` 进本键盘自己的 UserDefaults 忽略表（`ignoredEnglishWords`）。
- 接线（只动英文路径，中文零影响）：
  - `autocompleteProvider` 换成新 provider。
  - `textDidChange` 里：`if keyboardContext.keyboardType.isAlphabetic { performAutocomplete() }`——**必须有这个 guard**。不加的话中文提交也会调 provider，中文词会被当成英文错词，`tryApplyAutocompleteSuggestion` 会在下一个空格把中文词换成英文 guess。触发点选 `textDidChange` 而不是按键处理，是因为删字/粘贴也走这里，一处覆盖全部。
  - VC 里桥接 `autocompleteContext.$suggestions` → `rimeContext.showExternalSuggestions(..., kind: .englishCorrection)`（只在英文键盘下；切走英文键盘时 `resetAutocomplete()` + 清掉 kind=`.englishCorrection` 的外部建议——否则 stale 的纠错会在中文键盘的下一个空格被误应用，见 §6 未验证点）。
  - `StandardKeyboardActionHandler` 两个 `handle()` 里取消注释 `tryRemoveAutocompleteInsertedSpace` / `tryApplyAutocompleteSuggestion` / `tryReinsertAutocompleteRemovedSpace`（`tryEndSentence` 双空格变句号不属于本次范围，继续注释）。中文下这三者都是 no-op：suggestions 为空、`ProxyState` 从未进 `.autoInserted`。
  - 点选纠错：`RimeContext.selectCandidate` 的 `.englishCorrection` 分支调 `onApplyEnglishCorrection`，VC 里走现成的 `insertAutocompleteSuggestion`（替换当前词 + 补空格）。

### 3.4 保持不变的行为

英文键盘打字、删除、大小写切换、空格拖动光标全部不动；只多了：候选栏出现纠错候选、空格应用首个纠错、点选纠错/补全。中文键盘：provider 永远不跑（guard），三个 handler 调用是 no-op，`suggestions` 仍是引擎的。

---

## 4. 与本地语言模型（octagram，另一路）的衔接

- **不重叠**：octagram 管“打出来的输入怎么排”（typed-input 重排序）；联想词管“没输入时下一句出什么”（zero-input 续写）。两者触发点、数据源、显示时机都不同。
- **不冲突**：联想词不读 `.gram`、不改 `translator` 配置、不碰部署；octagram 落地后，`syncContext` 的引擎候选排序变好，联想词照常在提交后出现（引擎候选写入时 `setEngineSuggestions` 会把 kind 置 `.none`，联想栏随打字消失，互不串台）。
- **未来可合并的点（不做）**：octagram 的 `.gram` 也可以从同一批诗句语料里训出搭配分，让“打 `langtaojin` 时浪淘尽更稳”——但它现在已经是 #1，没收益；以及联想表以后可以从 `.gram` 的语料或 `chinese-poetry` 自动生成，替换手写 seed。

---

## 5. 活验证证据

环境：本机 librime 1.8.5（`~/workspace/r12/librime`，与 `InputSchemaBuild.sh` 的 `rime_version=1.8.5 / rime_git_hash=08dd95f` 一致），userdata `~/workspace/r13probe/userdata`（rime_ice 默认合并词库），探针 `~/workspace/r13probe/rank.c`（复用）+ 新写 `~/workspace/r13probe/assoc.c`（双阶段：先 `RimeSelectCandidate` 提交 A，再打 B，打印前 10 + 目标排名；提交路径与 App 的 `RimeContext.selectCandidate` 一致）。

恢复依赖：本机 librime 运行时库被卸过，从 `/var/cache/apt/archives` 的缓存 .deb 装回 `libboost-filesystem/regex/system 1.83.0`、`libgoogle-glog`、`libleveldb`、`libmarisa`、`libyaml-cpp`、`libopencc`（含 `libgflags2.2`、`libopencc-data` 两个依赖），`sudo dpkg -i`，无网络。

| 探针 | 结果 |
|---|---|
| `./rank userdata rime_ice dajiangdongqu 大江东去` | 大江东去 **#1**（前 10：大江东去/大江东/搭建/大奖/大将/大疆/大江/大件/大减/大讲） |
| `./rank userdata rime_ice langtaojin 浪淘尽` | 浪淘尽 **#1**（前 10：浪淘尽/难逃/浪涛/烂桃/滥套/难/男/♂/南/蓝） |
| `./rank userdata rime_ice qiangufengliurenwu 千古风流人物` | 千古风流人物 **#1**（前 10：千古风流人物/千古风流/千古恨/千古/强固/腔骨/钱谷/前/强/👍） |
| `./assoc userdata rime_ice - - langtaojin 浪淘尽`（对照：不提交） | 浪淘尽 #1 |
| `./assoc userdata rime_ice dajiangdongqu 大江东去 langtaojin 浪淘尽` | COMMIT: 大江东去；浪淘尽 #1，前 10 与对照逐字相同 |
| `./assoc userdata rime_ice nihao 你好 langtaojin 浪淘尽` | COMMIT: 你好；浪淘尽 #1，前 10 与对照逐字相同 |
| `./assoc userdata rime_ice dajiangdongqu 大江东去 langtao 浪淘尽` | COMMIT: 大江东去；浪淘尽 **NOT FOUND**（半截输入出不了三音节词） |
| `./assoc userdata rime_ice langtaojin 浪淘尽 qiangufengliurenwu 千古风流人物` | COMMIT: 浪淘尽；千古风流人物 #1 |
| 变体 `/tmp/assoc-ctx`（`rime_ice.custom.yaml` 加 `translator/contextual_suggestions: true`，deployer exit 0，编译出 `build/rime_ice.schema.yaml:901` 含该值）重跑上表后三组 | **结果与基线逐字相同** |

源码核对：`poet.h: ContextualWeighted` 在 `!contextual_suggestions() || !grammar_` 时原样返回；`poet.cc: MakeSentence` 无 grammar 时走 `DynamicProgramming`，`Grammar::Evaluate` 无 grammar 时每词固定扣 `-18.42`；`table_translator.cc:313` 同样走 `poet_->ContextualWeighted`；启动日志（`rime.r15assoc.INFO`）注册组件里 `grammar` 出现 **0 次**；本地构建 `build/plugins/` 为空。

诗句核对：`gushiwen.cn`《念奴娇·赤壁怀古》：大江东去，浪淘尽，千古风流人物。故垒西边，人道是，三国周郎赤壁。乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间，樯橹灰飞烟灭。故国神游，多情应笑我，早生华发。人生如梦，一尊还酹江月。（樯橹一作强虏，尊一作樽。）

---

## 6. 哪些没法验证（本机）

- **Swift 编译**：本机无 Swift 工具链，全部 Swift 代码只能写不能编译。验证靠：逐文件重读 + Python 括号平衡 + 全仓悬空引用 grep（新符号逐个查定义/调用点）。真机编译在用户 Mac 上。
- **UITextChecker 在真机键盘扩展里的实际表现**：本机无 iOS 运行时，`guesses` 的具体内容、排序、en_US 词典是否可用，只能靠文档 + 两个键盘扩展先例（§3.1）佐证，不能活验证。风险已用防御收敛：词典缺失时返回 `[]`（`availableLanguages` 检查）、词长 2–24、只认字母/`'`、猜测只取前 4 且过滤多词、补全只点选不自动上屏。真机第一件事：英文键盘打 `teh`，看候选栏出 `the`、空格上屏 `the`。
- **候选栏在英文键盘下的真实显隐**：`KeyboardToolbarView` 的显隐逻辑是按代码读的（`userInputKey` 驱动 + 新增的 kind 订阅），真机上要看一次：英文打 `teh` 时工具栏是否让位给候选栏、点选后是否恢复。
- **手动分页模式的联想显示**：`CandidatesPagingView` 的 `$suggestions` 订阅是新加的分支，逻辑上与划动模式对称，但真机上要单独切到手动分页测一次。
- **联想学习对子的误触发**：`count >= 2` 的阈值是拍的，没经过真机使用；若用户觉得不相干的句子也被联想了，调阈值或加“长按联想词可删”——后者未做。

## 7. 改动文件清单

见各 commit message；汇总：

- 新增 `Docs/round15-association-design.md`（本文档）
- 新增 `Packages/HamsterKeyboardKit/Sources/RimeContext/AssociationStore.swift`（内置联想表 + 学习对子读取/记录 + `ExternalSuggestionKind`）
- 新增 `Packages/HamsterKeyboardKit/Sources/KeyboardKit/Autocomplete/EnglishSpellcheckAutocompleteProvider.swift`
- 改 `Packages/HamsterKit/Sources/Extensions/UserDefaults+.swift`（`learnedAssociations` / `ignoredEnglishWords` 持久化）
- 改 `Packages/HamsterKeyboardKit/Sources/RimeContext/RimeContext.swift`（外部建议状态机 + 提交触发 + 点选分支 + 隔离 guard）
- 改 `Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift`（kind 订阅，候选栏显隐）
- 改 `Packages/HamsterKeyboardKit/Sources/View/Compoents/CandidateWords/CandidateWordsCollectionView.swift`（长按 guard）
- 改 `Packages/HamsterKeyboardKit/Sources/View/Compoents/CandidateWords/CandidatesPagingView.swift`（长按 guard + `$suggestions` 订阅）
- 改 `Packages/HamsterKeyboardKit/Sources/Controller/KeyboardInputViewController.swift`（provider 换掉 + `textDidChange` 触发 + 桥接 + 两个上屏回调 + 切键盘清理）
- 改 `Packages/HamsterKeyboardKit/Sources/KeyboardKit/Actions/StandardKeyboardActionHandler.swift`（取消注释三个 autocomplete 调用，`tryEndSentence` 不动）
