//
//  CustomPhraseStore.swift
//  HamsterKit
//
//  自定义词组 (我的词组): RIME 自定义短语词库 custom_phrase.txt 的读写。
//
//  格式 (RIME table, 与 rime-ice 的 table_translator@custom_phrase 对应):
//    # Rime table
//    #@/db_name custom_phrase.txt
//    #@/db_type tabledb
//    词组<TAB>拼音<TAB>权重
//  拼音用空格分隔音节, 如 "ni hao"; 权重越大候选越靠前, 默认 100。
//  rime_ice.schema.yaml 已包含 table_translator@custom_phrase
//  (user_dict: custom_phrase, db_class: stabledb, initial_quality: 99),
//  所以此文件里的词组会在部署时编进 custom_phrase.userdb, 打字时优先出现。
//  RIME 的用户词典学习 (enable_user_dict) 默认就是开启的, 选过的词会自动加权,
//  不需要额外配置。
//
//  文件位置: App Group 用户数据目录 (FileManager.appGroupUserDataDirectoryURL)。
//  部署时 RimeContext.deployment 会先把它从 App Group 拷回沙盒
//  (不受 overrideDictFiles 影响), 编完再同步回 App Group,
//  所以用户加的词组不会被部署覆盖; 键盘扩展 (Full Access 开启时) 直接读 App Group。
//  注意: 改完词组后需要在设置里点"重新部署" (或在 RIME 页面点重新部署),
//  新词才会生效。
//

import Foundation

/// 一条自定义词组
public struct CustomPhrase: Equatable {
  public let word: String
  /// 拼音, 音节用空格分隔, 如 "ni hao"
  public let code: String
  public let weight: Int

  public init(word: String, code: String, weight: Int = CustomPhraseStore.defaultWeight) {
    self.word = word
    self.code = code
    self.weight = weight
  }
}

public enum CustomPhraseStore {
  public static let fileName = "custom_phrase.txt"
  public static let defaultWeight = 100

  private static let fileHeader = """
  # Rime table
  #@/db_name custom_phrase.txt
  #@/db_type tabledb

  """

  /// App Group 用户数据目录下的 custom_phrase.txt
  public static var fileURL: URL {
    FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(fileName)
  }

  /// 读出全部自定义词组。文件不存在时返回空数组 (不报错)。
  public static func load() -> [CustomPhrase] {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return []
    }
    return parse(content)
  }

  /// 保存全部自定义词组 (覆盖写整个文件)。
  public static func save(_ phrases: [CustomPhrase]) throws {
    var content = fileHeader
    for phrase in phrases {
      content += "\(phrase.word)\t\(phrase.code)\t\(phrase.weight)\n"
    }
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 解析 RIME table 文本: 跳过 # 开头的注释行和空行,
  /// 每行 "词组<TAB>拼音[<TAB>权重]", 权重缺省时为 defaultWeight。
  static func parse(_ content: String) -> [CustomPhrase] {
    var phrases: [CustomPhrase] = []
    for rawLine in content.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      let fields = rawLine.components(separatedBy: "\t")
      guard fields.count >= 2 else { continue }
      let word = fields[0].trimmingCharacters(in: .whitespaces)
      let code = fields[1].trimmingCharacters(in: .whitespaces)
      guard !word.isEmpty, !code.isEmpty else { continue }
      let weight = fields.count >= 3 ? Int(fields[2].trimmingCharacters(in: .whitespaces)) ?? defaultWeight : defaultWeight
      phrases.append(CustomPhrase(word: word, code: code, weight: weight))
    }
    return phrases
  }
}
