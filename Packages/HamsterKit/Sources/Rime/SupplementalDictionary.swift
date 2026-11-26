//
//  SupplementalDictionary.swift
//  HamsterKit
//
//  补充词典 (build #53 回归修复第 3 项: QQ 走正经词典机制)。
//
//  问题: QQ 在 en.dict 里有词条 (QQ QQ, 无权重), 但 t9 的 melt_eng
//  是注释掉的, 且英文词条是大写码、无权重, 数字派生规则又是小写,
//  77 永远推不出它 (rig: 77 / 26 键 qq 都是 NOT FOUND)。
//  #53 用 custom_phrase 种子补位 (initial_quality 99) 把它钉在 #1,
//  代价是种子压过一切词典词和用户学习 (96 在哪盖住“我”)——
//  种子已下线 (见 BuiltInCustomPhrases.swift 的留档说明)。
//
//  做法 (不改上游仓库本身, 不改大词典权重):
//  随安装包下发两个小文件 (Resources/SharedSupport/ 里的散文件,
//  跟 .gram 同款投递, 不进 SharedSupport.zip——zip 只在首次运行/
//  重置时才解压, 老用户升级收不到):
//    hamster_supplemental.dict.yaml    (QQ qq 1000000, 真实权重)
//    hamster_supplemental.schema.yaml  (只为让部署器编译词库 + prism,
//                                       不作为输入方案)
//  运行时 ensureFiles() 把它们拷进两个用户数据目录 (沙盒 + App Group),
//  apply() 把翻译器补丁打进 rime_ice.custom.yaml / t9.custom.yaml:
//    engine/translators/@before 0: table_translator@hamster_supplemental
//    hamster_supplemental:
//      dictionary: hamster_supplemental
//      enable_completion: false
//      enable_sentence: false
//      initial_quality: 1.2
//  部署时 RimeContext 的 schema_list 补齐逻辑 (第 10 轮) 会自动把
//  hamster_supplemental 并进 schema_list (只加不减), 部署器随即
//  编译 hamster_supplemental.table.bin + .prism.bin。
//
//  为什么翻译器要排在列表最前 (@before 0), 不能 @next 追加:
//  librime 的 MergedTranslation::Elect() 不是全局按 quality 取最大,
//  而是按翻译器顺序找第一个“头候选不比下一个差”的 (局部最大)。
//  26 键 qq 有 700 多个 q 首字母候选, 前面的 script/main 翻译器
//  各有几百条, 排在末尾的补充翻译器要等它们全耗尽才轮到——
//  QQ 权重从 1M 提到 100M、initial_quality 提到 10 都纹丝不动,
//  一直 #283。排到最前 + 权重 1M 后, QQ 直接 #1 (rig 实测)。
//  t9 的 77 本来 @next 也能 #1 (对手只有事实/商品 ~500k), 但统一
//  @before 0 更稳 (对手再大也不怕被前面的翻译器挡住)。
//  权重 1000000: 77 的顶栏对手事实 510349 / 商品 502008,
//  1M 刚好压过; 26 键靠排位, 不靠权重。
//  initial_quality 1.2: 跟 rime_ice 主翻译器一致
//  (“拼音的权重应该比英文大”), 不搞特殊值。
//
//  为什么 schema 文件里 translator/prism 必须显式写自己的名字:
//  补充方案 __include t9, 不写 prism 就会继承 t9 的 prism: t9,
//  部署器编译时把 t9.prism.bin 覆盖成 1440 字节
//  (77 只剩 A / 🅰️ 两个候选, r53 rig 实测)。
//
//  melt_eng 为什么不行 (r53 rig 实测, 已否决):
//  t9.schema.yaml:54 取消注释 + 配套 melt_eng.custom.yaml 补丁后,
//  77 仍是 NOT FOUND (log: melt_eng made a futile translation)。
//  根因: en.dict 的 QQ 是大写码、无权重, 数字派生规则全是小写,
//  prism 永远推不出 77; 即使配上, 权重 0 的 quality ≈ 1.1 也排在末尾。
//
//  活验证 (librime 1.8.5 真实构建 + 真实词库, Linux, 2026-11-26,
//  rig ~/workspace/r53rig/qq_app, custom.yaml 补丁机制, 非直接改 schema):
//  77 QQ #1 (事实 #2, 商品 #3); 26 键 qq QQ #1 (全球 #2, 请求 #3);
//  96 我 #1; 4263 好的 #1; 644 你好 #5 (基线, 非回归);
//  44 哈哈 #26; 94266 小鸟 #48; 539 可以 #1, 59 可以 #4;
//  脑子里全是你 #1; 26 键 q QQ NOT FOUND (补位不污染单字母);
//  nihao 你好 #1, quanqiu 全球 #1; t9.prism.bin 372368 字节 (未被覆盖)。
//  33 都得 #187 (种子拿掉后的原位, 见 BuiltInCustomPhrases 的说明)。
//
//  文件更新方式: 只动标记块 (BEGIN/END hamster-supplemental-dict 之间),
//  文件其余内容原样保留; 文件里已有 patch: 顶级键时, 补丁挂在它下面
//  (不再另起一个 patch:, 否则 YAML 重复键会丢掉用户原有的 patch 内容)。
//  常开, 不跟任何开关走。改完需要点「重新部署」才生效 (librime 要重新编译方案)。
//  部署时 RimeContext.deployment()/syncRime()/restRime() 会重打一次补丁、
//  重拷一次文件, 所以文件丢了也能在下次部署时恢复。
//

import Foundation

/// 补充词典 (QQ 走正经词典权重) 补丁 + 词典/方案文件投递 (常开, 两方案都写)。
public enum SupplementalDictionary {
  /// 词典文件名 (安装包 SharedSupport/ 里的散文件, 也是用户数据目录里的文件名)。
  public static let dictFileName = "hamster_supplemental.dict.yaml"

  /// 方案文件名 (安装包 SharedSupport/ 里的散文件, 也是用户数据目录里的文件名)。
  public static let schemaFileName = "hamster_supplemental.schema.yaml"

  /// 要打补丁的方案文件 (26 键雾凇拼音 + 九宫格 t9, 两边都要)。
  public static let schemaFileNames = ["rime_ice.custom.yaml", "t9.custom.yaml"]

  /// 补丁行 (已含缩进, 直接拼进块里; 注意 hamster_supplemental: 下面 4 空格)。
  static let patchLines: [String] = [
    "engine/translators/@before 0: table_translator@hamster_supplemental",
    "hamster_supplemental:",
    "  dictionary: hamster_supplemental",
    "  enable_completion: false",
    "  enable_sentence: false",
    "  initial_quality: 1.2",
  ]

  /// 补丁块的标记 (文件里只改这一段)。
  static let beginMarker = "# BEGIN hamster-supplemental-dict (补充词典: QQ 走正经词典权重, 请勿手动改这段)"
  static let endMarker = "# END hamster-supplemental-dict"

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static var fullBlock: String {
    ([beginMarker, "patch:"] + patchLines.map { "  " + $0 } + [endMarker])
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static var nestedBlock: String {
    ([("  " + beginMarker)] + patchLines.map { "  " + $0 } + [("  " + endMarker)])
      .joined(separator: "\n")
  }

  /// 写补丁: 两份文件都带上补充词典翻译器补丁 (常开, 不跟任何开关走)。
  /// 两份用户数据目录都写 (沙盒 + App Group): 沙盒那份供下次部署时
  /// librime 编译, App Group 那份供部署前的拷回与键盘扩展直接读取。
  public static func apply() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      for fileName in schemaFileNames {
        try apply(to: dir.appendingPathComponent(fileName))
      }
    }
  }

  /// 更新单个 custom.yaml 文件 (文件不存在时视为 "")。
  static func apply(to fileURL: URL) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    content = removingSupplementalBlock(from: content)
    content = insertingSupplementalBlock(into: content)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 删掉标记块 (BEGIN 行到 END 行, 含两行本身); 没有标记块时原样返回。
  static func removingSupplementalBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    lines.removeSubrange(begin...end)
    return lines.joined(separator: "\n")
  }

  /// 插入标记块: 文件里已有 patch: 顶级键时挂在它下面,
  /// 否则在文件末尾追加完整的 patch: 块。
  static func insertingSupplementalBlock(into content: String) -> String {
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullBlock + "\n"
    }
    var lines = content.components(separatedBy: .newlines)
    // 顶级 patch: 键 (行首无缩进; 带行内注释的也算, flow 写法除外, 这里不会出现)。
    if let patchIndex = lines.firstIndex(where: { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }) {
      lines.insert(contentsOf: nestedBlock.components(separatedBy: "\n"), at: patchIndex + 1)
      return lines.joined(separator: "\n")
    }
    var result = content
    if !result.hasSuffix("\n") { result += "\n" }
    result += "\n" + fullBlock + "\n"
    return result
  }

  /// 把安装包里的补充词典 + 方案文件拷进两个用户数据目录
  /// (沙盒 + App Group, 内容一样才不重拷; 文件很小, 按内容比对)。
  /// 安装包里没有这两个文件时抛错 (构建时确认它们进了 Copy Rime SharedSupport)。
  public static func ensureFiles() throws {
    for fileName in [dictFileName, schemaFileName] {
      let src = FileManager.appSharedSupportDirectory.appendingPathComponent(fileName)
      guard let data = try? Data(contentsOf: src) else {
        throw NSError(
          domain: "com.ihsiao.apps.hamster.SupplementalDictionary",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "安装包里缺少补充词典文件 \(fileName), 请确认它进了 Copy Rime SharedSupport"])
      }
      for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
        try FileManager.createDirectory(override: false, dst: dir)
        let dst = dir.appendingPathComponent(fileName)
        if let existing = try? Data(contentsOf: dst), existing == data {
          continue
        }
        if FileManager.default.fileExists(atPath: dst.path) {
          try FileManager.default.removeItem(at: dst)
        }
        try data.write(to: dst, options: .atomic)
      }
    }
  }
}
