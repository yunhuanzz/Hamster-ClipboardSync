//
//  FuzzyPinyinCleanup.swift
//  HamsterKit
//
//  一次性迁移清理: 模糊音功能已删除 (2026-11-28)。
//  删的原因: 12 条 derive/ 模糊规则把模糊读法存成了正常拼写
//  (derive 只做正则替换, 不打 kFuzzySpelling 标记、不扣分),
//  导致打 xian 时引擎分不清 xian/xiang, Poet 的 beam 被
//  xiang 开头的词占满, 正确的 xian 句连候选列表都进不去。
//
//  本文件只做一件事: 删掉设备上残留的 "# BEGIN/END
//  hamster-fuzzy-pinyin" 标记块 (rime_ice.custom.yaml /
//  t9.custom.yaml, 沙盒 + App Group 两份)。它永远不再插入规则,
//  也没有任何开关。等所有设备都在删除后的版本上部署过至少一次,
//  本文件就可以连同调用处一起删掉。
//

import Foundation

/// 模糊音残留块清理 (一次性迁移, 不是功能)。
public enum FuzzyPinyinCleanup {
  /// 残留标记块的起止行 (与已删除的 FuzzyPinyin.swift 相同)。
  public static let beginMarker = "# BEGIN hamster-fuzzy-pinyin (模糊音开关管理, 请勿手动改这段)"
  public static let endMarker = "# END hamster-fuzzy-pinyin"

  /// 要清理的方案文件 (26 键雾凇拼音 + 九宫格 t9, 两边都要)。
  public static let schemaFileNames = ["rime_ice.custom.yaml", "t9.custom.yaml"]

  /// 删掉内容里的残留模糊音块 (BEGIN 行到 END 行, 含两行本身);
  /// 没有标记块时原样返回 (不改内容、不碰 mtime)。
  public static func removingStaleBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    lines.removeSubrange(begin...end)
    return lines.joined(separator: "\n")
  }

  /// 从两个用户数据目录 (沙盒 + App Group) 的两份 custom.yaml 里
  /// 删掉残留模糊音块。文件没变就不重写; 内容删空了就删文件。
  public static func removeFromUserData() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      for fileName in schemaFileNames {
        let fileURL = dir.appendingPathComponent(fileName)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let cleaned = removingStaleBlock(from: content)
        guard cleaned != content else { continue }
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          try? FileManager.default.removeItem(at: fileURL)
          continue
        }
        try cleaned.write(to: fileURL, atomically: true, encoding: .utf8)
      }
    }
  }
}
