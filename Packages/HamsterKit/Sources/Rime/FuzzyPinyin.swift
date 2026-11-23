
//
//  FuzzyPinyin.swift
//  HamsterKit
//
//  模糊音: 运行时往 rime_ice.custom.yaml / t9.custom.yaml 里打补丁,
//  在 speller/algebra 最前面插入 12 条福建常见混淆规则。
//
//  做法 (不改上游仓库本身): rime-ice 上游的 speller/algebra 模糊规则
//  是注释掉的, 这里用 RIME 的 patch 机制补上——custom.yaml 里的
//  `patch: speller/algebra/@before 0:` 会把规则插到 algebra 列表
//  最前面 (@before 0, librime 的 patch 语法: @before N 插到第 N 项
//  之前, @next 追加到末尾)。
//  对 t9 同样插在最前面才对: 模糊先在字母拼写上派生
//  (zhang -> zang), 后面的数字映射规则再把派生出的拼写转成数字码,
//  所以输入 9264 能命中“藏/脏”等; 如果插到数字映射后面, 规则看到
//  的是数字串, 永远匹配不上, 等于白加。
//  规则只取任务指定的 12 条 (与 rime_ice.schema.yaml 里注释掉的
//  规则一致, 不含 l/r、g/k、ian/iang 等)。
//
//  文件更新方式: 只动标记块 (BEGIN/END hamster-fuzzy-pinyin 之间),
//  文件其余内容原样保留; 文件里已有 patch: 顶级键时, 规则挂在它下面
//  (不再另起一个 patch:, 否则 YAML 重复键会丢掉用户原有的 patch 内容)。
//  关开关时只删掉标记块; 文件删到只剩空白时把文件删掉。
//  改完需要点「重新部署」才生效 (librime 要重新编译方案)。
//  部署时 RimeContext.deployment()/syncRime() 会按开关重打一次补丁,
//  所以开关状态是事实来源, 文件丢了也能在下次部署时恢复。
//

import Foundation

/// 模糊音补丁 (开关在设置 RIME 页, 默认开, 存在共享 UserDefaults)。
public enum FuzzyPinyin {
  /// 模糊规则 (12 条)。
  public static let rules: [String] = [
    "derive/^([zcs])h/$1/",
    "derive/^([zcs])([^h])/$1h$2/",
    "derive/^l/n/",
    "derive/^n/l/",
    "derive/^f/h/",
    "derive/^h/f/",
    "derive/ang$/an/",
    "derive/an$/ang/",
    "derive/eng$/en/",
    "derive/en$/eng/",
    "derive/in$/ing/",
    "derive/ing$/in/",
  ]

  /// 要打补丁的方案文件 (26 键雾凇拼音 + 九宫格 t9, 两边都要)。
  public static let schemaFileNames = ["rime_ice.custom.yaml", "t9.custom.yaml"]

  /// 补丁块的标记 (文件里只改这一段)。
  static let beginMarker = "# BEGIN hamster-fuzzy-pinyin (模糊音开关管理, 请勿手动改这段)"
  static let endMarker = "# END hamster-fuzzy-pinyin"

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static var fullBlock: String {
    ([beginMarker, "patch:", "  speller/algebra/@before 0:"] + rules.map { "    - \($0)" } + [endMarker])
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static var nestedBlock: String {
    ([("  " + beginMarker), "  speller/algebra/@before 0:"] + rules.map { "    - \($0)" } + [("  " + endMarker)])
      .joined(separator: "\n")
  }

  /// 按开关状态写补丁: 开 -> 两份文件都带上模糊规则;
  /// 关 -> 只去掉补丁块, 其余内容不动; 文件只剩空白时删掉文件。
  /// 两份用户数据目录都写 (沙盒 + App Group): 沙盒那份供下次部署时
  /// librime 编译, App Group 那份供部署前的拷回与键盘扩展直接读取。
  public static func apply(enabled: Bool) throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      for fileName in schemaFileNames {
        try apply(to: dir.appendingPathComponent(fileName), enabled: enabled)
      }
    }
  }

  /// 更新单个 custom.yaml 文件 (文件不存在时视为 ""; 关且内容为空时删文件)。
  static func apply(to fileURL: URL, enabled: Bool) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    content = removingFuzzyBlock(from: content)
    if enabled {
      content = insertingFuzzyBlock(into: content)
    }
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? FileManager.default.removeItem(at: fileURL)
      return
    }
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 删掉标记块 (BEGIN 行到 END 行, 含两行本身); 没有标记块时原样返回。
  static func removingFuzzyBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    lines.removeSubrange(begin...end)
    return lines.joined(separator: "\n")
  }

  /// 插入标记块: 文件里已有 patch: 顶级键时挂在它下面,
  /// 否则在文件末尾追加完整的 patch: 块。
  static func insertingFuzzyBlock(into content: String) -> String {
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
}
