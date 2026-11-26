//
//  T9SyllableInitials.swift
//  HamsterKit
//
//  九宫格常用音节首字母拼写 (第 13 轮第 3 项 a 小点)。
//
//  问题: 九宫格打 4263 应该是“好的” (hao + d 缩写), 实际候选里根本
//  没有“好的” (200 个候选里都找不到); 单按 3 也出不了“的/得/地”。
//  同类: 9434 出不了“这个”、4266 出不了“好吗/好呢”、74366 出不了
//  “什么”、7446 出不了“是你”、9246 出不了“在哪”、94 出不了“这”,
//  6968 出不了“没有”、7443 出不了“是的”。
//
//  根因 (librime 1.8.5 源码 + 真机同款 deployer/驱动活验证, 不是猜的):
//  1. 方案自带的超级简拼是 abbrev 规则 (t9.schema.yaml:
//     abbrev/^([a-z]).+$/$1/): “de”能派生出“d”, 但派生出的拼写类型是
//     kAbbreviation。
//  2. 查询时 syllabifier.cc 的 BuildSyllableGraph 在清理音节图:
//     只要存在一条全是普通拼写的路径走到输入末尾, last_type 就定成
//     kFuzzySpelling, 所有 kAbbreviation 音节一律从图里删掉
//     (“remove disqualified syllables when there is a path of more
//     favored type”)。九宫格数字太粗, 几乎任何数字串都有一条全普通
//     拼写的切分 (4263 能切成 42|63 ga|le), 所以缩写读法系统性被剪掉;
//     26 键 "haod" 能出“好的”, 只是因为它没有全普通切分、缩写边活下来了。
//  3. derive 规则派生的拼写保持 kNormalSpelling 类型 (calculus.h:
//     Derivation 不改类型, 只有 Fuzzing/Abbreviation 才改),
//     不会被清理剪掉。所以把常用功能音节的首字母形式改写成 derive
//     规则, 就能让它以普通拼写活下来。
//
//  做法 (不改上游仓库本身, 不改大词典权重): 只给 t9.custom.yaml 打
//  补丁, 在 speller/algebra 里加 14 条 derive 规则, 每条只针对一个
//  常用音节 (整音节锚定 ^...$, 不会误伤别的音节):
//    de->d (的/得/地: 好的/是的), ge->g (个: 这个),
//    ne->n (呢: 好呢), na->n (那/哪: 在哪),
//    ma->m (吗: 好吗), me->m (么: 什么), ni->n (你: 是你),
//    zhe->zh (这), shi->sh (是), chi->ch (吃), mei->m (没: 没有)。
//    yi->y (以/意/一: 可以), dou->d (都: 都得), dian->d (点: 买点)。
//  其中 shi->sh、chi->ch 在模糊音开着时是冗余的 (“shi”能经模糊规则
//  derive 成“si”, “chi”能成“ci”, 都是普通类型, 74 是 #1、24 吃 #7
//  本来就成立); 留着它们是让缩写不依赖模糊音开关——实测模糊音全关
//  时 74 是、24 吃仍成立, 4263 好的、9434 这个、64426 你好也都成立。
//
//  序号: 沿用模糊音块的 @before 标量写法 (第 11 轮实测结论, 列表写法
//  会清空整个 algebra), 从 12 开始排 (模糊音占 00..11), 保证两边都
//  插在方案自带规则之前、数字映射规则之前: 模糊音先在字母拼写上派生,
//  再由本块给出首字母形式, 最后数字映射规则把字母拼写转成数字码。
//  模糊音关掉时本块序号仍有效: @before 12..25 落在自带规则
//  [iu]a 之后、数字映射之前, 顺序不变。
//  只写 t9.custom.yaml (26 键 "haod" 本来就能出“好的”, 不需要)。
//  常开, 不跟模糊音开关走。
//
//  活验证 (librime 1.8.5 真实 deployer + 驱动, 干净无学习词库):
//  改前 4263 的“好的”在 200 候选里 NOT FOUND, 单 3 的“的”在 43 候选里
//  NOT FOUND, 9434 的“这个”、4266 的“好吗/好呢”、74366 的“什么”,
//  7446 的“是你”、9246 的“在哪”、94 的“这”、6968 的“没有”全部
//  NOT FOUND; 改后 4263 好的 #1、9434 这个 #2、4266 好吗 #2/好呢 #8、
//  74366 什么 #1、7446 是你 #15、94 这 #3、74 是 #1、24 吃 #7、
//  6968 没有 #1、7443 是的 #4; 回归: 64426 你好 #1、42633 好的 #1、
//  4265 好了 #4 不变, (a)(b)(c) 三个长句首选不变,
//  26 键 haod 好的 #1、wozaitiaowaimaizhong 我在条外卖中不变。
//  单键行为变化 (实测, 补全机制本来就会给单键出补全候选, 所以变化很小):
//  单 3 由 饿/呃/恶… 变成 的/地/得/德/饿…, 单 6 由 哦/噢/喔… 变成
//  那/吗/没/里…, 单 4 首选仍是个、单 5/单 7 与改前完全相同。
//  例外: 9246 的“在哪”改后只排 #109——找得到但太靠后, 是它本身词频
//  低 (89000, 对比 这个 503750、好的 500784), 不是缩写问题, 不修权重。
//
//  2026-11-26 扩展 (+3 条: yi->y, dou->d, dian->d; 原因见下):
//  9 键 539/59 的“可以”改前在 3000 候选里 NOT FOUND——“yi”是 2 字母
//  缩写读法, 被 round-17 的 IsShortAbbrevTail 跳过 (它只放过 derive
//  成普通拼写的音节); “dou”“dian”同理 (33 都得 NOT FOUND)。
//  改后 539 可以 #1、59 可以 #4、33 都得 #29 (可选中, 再由学习接管);
//  回归 r17-verify.sh PASS=14 FAIL=0 (644 你好 #4、94266 小鸟 #44、
//  笑尿学习、haod/4263/64426/脑子里全是你均不变)。
//  336243743663744468 的“分别什么时候”仍 NOT FOUND——那是 Poet
//  beam (kMaxLineCandidates=7) 在第 3 音节处剪掉了 fen|bie 路径,
//  不是权重/.gram 问题 (26 键全拼 fenbieshenmeshihou 是 #1);
//  需另做引擎改动, 不在本批。
//
//  补丁写法复用第 5/10 轮的 marker-block 做法: 只动
//  "# BEGIN/END hamster-t9-syllable-initials" 标记块, 与模糊音块、
//  词库块共存于同一个顶级 patch: 键下 (三块是兄弟关系, 互不嵌套)。
//  插入点取 patch: 映射的末尾 (模糊音块、词库块的 END 行之后),
//  模糊音块是 full block 形态时先把它改成 nested 形态
//  (与 LayoutDictionary.insertingDictionaryBlock 同款处理)。
//  删除本块时若块里嵌着别人的块, 原样保留 (防御性, 正常流程不会发生)。
//  改完需要点「重新部署」才生效 (librime 要重新编译方案)。
//  部署/同步/重置时 RimeContext 会重打一次, 文件丢了也能恢复。
//

import Foundation
import OSLog

/// 九宫格常用音节首字母拼写 (常开, 只写 t9)。
public enum T9SyllableInitials {
  /// 14 条 derive 规则: 常用音节 -> 首字母 (普通拼写类型, 不会被
  /// syllabifier 的缩写清理剪掉)。顺序即 @before 序号顺序。
  public static let rules: [String] = [
    "derive/^de$/d/",
    "derive/^ge$/g/",
    "derive/^ne$/n/",
    "derive/^na$/n/",
    "derive/^ma$/m/",
    "derive/^me$/m/",
    "derive/^ni$/n/",
    "derive/^zhe$/zh/",
    "derive/^shi$/sh/",
    "derive/^chi$/ch/",
    "derive/^mei$/m/",
    "derive/^yi$/y/",
    "derive/^dou$/d/",
    "derive/^dian$/d/",
  ]

  /// @before 序号从 12 起 (模糊音块占 00..11), 零填充到两位,
  /// 保证 ConfigMap 按字母序应用时顺序是 12..25。
  /// 每行值是单个规则字符串 (标量), 绝不能写成列表
  /// (见 FuzzyPinyin.swift 文件头: 列表会被 SetAt 原样塞进
  /// algebra[0], 导致整个 projection 被清空)。
  static var algebraPatchLines: [String] {
    rules.enumerated().map { index, rule in
      "speller/algebra/@before \(String(format: "%02d", index + 12)): \(rule)"
    }
  }

  /// 只打补丁的方案文件 (中文 9 键 t9)。
  public static let schemaFileName = "t9.custom.yaml"

  /// 补丁块的标记 (文件里只改这一段)。
  static let beginMarker = "# BEGIN hamster-t9-syllable-initials (九宫格常用音节首字母拼写, 请勿手动改这段)"
  static let endMarker = "# END hamster-t9-syllable-initials"

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static var fullBlock: String {
    ([beginMarker, "patch:"] + algebraPatchLines.map { "  " + $0 } + [endMarker])
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static var nestedBlock: String {
    ([("  " + beginMarker)] + algebraPatchLines.map { "  " + $0 } + [("  " + endMarker)])
      .joined(separator: "\n")
  }

  /// 把补丁打进两个用户数据目录 (沙盒 + App Group, 与
  /// FuzzyPinyin.apply 同款); 失败由调用方记日志、不阻断部署。
  public static func apply() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      try apply(to: dir.appendingPathComponent(schemaFileName))
    }
  }

  /// 更新单个 custom.yaml 文件 (文件不存在时视为 ""; 内容没变不重写,
  /// 不碰 mtime, 免得下次部署误判配置变了; 内容为空时删文件)。
  static func apply(to fileURL: URL) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    let updated = insertingBlock(into: removingBlock(from: content))
    if updated == content {
      return
    }
    if updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? FileManager.default.removeItem(at: fileURL)
      return
    }
    try updated.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 删掉本块 (BEGIN 行到 END 行, 含两行本身); 没有本块时原样返回。
  /// 例外: 块里嵌着别人的块 (模糊音/词库) 时原样保留并还挂在
  /// patch: 下面——本块是 full block 时 patch: 行在本块里, 要留一行
  /// patch: 给它; 本块是 nested 时 patch: 行本来就在块外, 不用留。
  /// (防御性: 正常流程里别的块不会嵌进本块, 见 insertingBlock。)
  static func removingBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    // BEGIN/END 在同一行 (手写文件才有): 直接删这一行。
    if begin == end {
      lines.remove(at: begin)
      return lines.joined(separator: "\n")
    }
    let inner = Array(lines[(begin + 1)..<end])
    var foreign: [String] = []
    for (foreignBeginMarker, foreignEndMarker) in [
      (FuzzyPinyin.beginMarker, FuzzyPinyin.endMarker),
      (LayoutDictionary.beginMarker, LayoutDictionary.endMarker),
    ] {
      if let foreignBegin = inner.firstIndex(where: { $0.contains(foreignBeginMarker) }),
         let foreignEnd = inner.firstIndex(where: { $0.contains(foreignEndMarker) }),
         foreignBegin <= foreignEnd {
        foreign += Array(inner[foreignBegin...foreignEnd])
      }
    }
    if foreign.isEmpty {
      lines.removeSubrange(begin...end)
    } else {
      let patchLineInside = inner.contains { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }
      let replacement = (patchLineInside ? ["patch:"] : []) + foreign
      lines.replaceSubrange(begin...end, with: replacement)
    }
    return lines.joined(separator: "\n")
  }

  /// 插入本块: 文件里已有 patch: 顶级键时挂在 patch: 映射的末尾
  /// (模糊音块、词库块的 END 行之后), 三块是 patch: 下面的兄弟关系,
  /// 互不嵌套; 模糊音块是 full block 形态 (BEGIN 行在 patch: 行正上方)
  /// 时先把它改成 nested 形态再插 (与 LayoutDictionary 同款处理,
  /// 否则本块插到它 END 行之后仍在它标记范围内,
  /// 下次关模糊音会连本块一起删掉)。
  /// 没有 patch: 键时在文件末尾追加完整的 patch: 块。
  static func insertingBlock(into content: String) -> String {
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullBlock + "\n"
    }
    var lines = content.components(separatedBy: .newlines)
    // 顶级 patch: 键 (行首无缩进; 带行内注释的也算, flow 写法除外, 这里不会出现)。
    if var patchIndex = lines.firstIndex(where: { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }) {
      // 模糊音块是 full block 形态时先改成 nested 形态
      // (BEGIN 行缩进 2 格挪到 patch: 下面, END 行若在行首也缩进
      // 2 格): 只挪注释行, 模糊音内容与标记本身不动; FuzzyPinyin
      // 按 contains() 找标记, 缩进不影响它, 下次它重打时也会
      // 按自己的写法恢复成 nested 块。
      if patchIndex > 0, lines[patchIndex - 1].contains(FuzzyPinyin.beginMarker) {
        lines.remove(at: patchIndex - 1)
        patchIndex -= 1
        lines.insert("  " + FuzzyPinyin.beginMarker, at: patchIndex + 1)
        if let fuzzyEnd = lines.firstIndex(where: { $0.contains(FuzzyPinyin.endMarker) }),
           !lines[fuzzyEnd].hasPrefix(" "), !lines[fuzzyEnd].hasPrefix("\t") {
          lines[fuzzyEnd] = "  " + lines[fuzzyEnd]
        }
      }
      // 插到 patch: 映射的末尾: 最后一个缩进行之后; 已知的块 END 行
      // 即使因手写文件在行首, 也要越过它再停 (它只是注释行),
      // 否则会插进那个块的标记范围里。
      var insertAt = patchIndex + 1
      while insertAt < lines.count {
        if lines[insertAt].contains(FuzzyPinyin.endMarker)
            || lines[insertAt].contains(LayoutDictionary.endMarker) {
          insertAt += 1
          continue
        }
        if lines[insertAt].isEmpty || lines[insertAt].hasPrefix(" ") || lines[insertAt].hasPrefix("\t") {
          insertAt += 1
        } else {
          break
        }
      }
      lines.insert(contentsOf: nestedBlock.components(separatedBy: "\n"), at: insertAt)
      return lines.joined(separator: "\n")
    }
    var result = content
    if !result.hasSuffix("\n") { result += "\n" }
    result += "\n" + fullBlock + "\n"
    return result
  }
}
