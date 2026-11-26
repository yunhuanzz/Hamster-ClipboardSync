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
//  九宫格 (t9.schema.yaml) 的 custom_phrase translator 用的是另一份
//  user_dict: custom_phrase_t9, 编码必须是数字, 所以保存时同时写
//  custom_phrase_t9.txt (拼音码逐音节转数字码), 否则“我的词组”
//  在九宫格下不生效。
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
  /// 九宫格 t9 用的自定义词组文件 (t9.schema.yaml 的 custom_phrase
  /// translator 用 user_dict: custom_phrase_t9, 编码必须是数字):
  /// 只写 custom_phrase.txt 的话, “我的词组”在九宫格下永远不生效
  /// (九宫格只发数字 2-9 给 RIME, 字母拼音码匹配不上), 所以保存时
  /// 同时写这份数字码文件, 词组在 26 键和九宫格下都能用。
  public static let t9FileName = "custom_phrase_t9.txt"
  public static let defaultWeight = 100

  private static let fileHeader = """
  # Rime table
  #@/db_name custom_phrase.txt
  #@/db_type tabledb

  """

  /// 九宫格文件的表头 (db_name 必须是 custom_phrase_t9.txt,
  /// 与 t9.schema.yaml 的 user_dict 对应)。
  private static let t9FileHeader = """
  # Rime table
  #@/db_name custom_phrase_t9.txt
  #@/db_type tabledb

  """

  /// App Group 用户数据目录下的 custom_phrase.txt
  public static var fileURL: URL {
    FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(fileName)
  }

  /// App Group 用户数据目录下的 custom_phrase_t9.txt
  public static var t9FileURL: URL {
    FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(t9FileName)
  }

  /// 读出全部自定义词组。文件不存在时返回空数组 (不报错)。
  public static func load() -> [CustomPhrase] {
    load(from: FileManager.appGroupUserDataDirectoryURL)
  }

  /// 读出指定目录下的全部自定义词组 (供 BuiltInCustomPhrases.seed()
  /// 两目录播种用; 沙盒目录那份是部署时从 App Group 拷过去的)。
  public static func load(from directory: URL) -> [CustomPhrase] {
    guard let content = try? String(contentsOf: directory.appendingPathComponent(fileName), encoding: .utf8) else {
      return []
    }
    return parse(content)
  }

  /// 保存全部自定义词组 (覆盖写整个文件)。
  /// 同时写九宫格的 custom_phrase_t9.txt (拼音码转数字码, 见下):
  /// 转不出的词组 (如含 t9 映射表里没有的音节) 只进 26 键那份,
  /// 九宫格那份跳过, 不写错码。
  public static func save(_ phrases: [CustomPhrase]) throws {
    try save(phrases, to: FileManager.appGroupUserDataDirectoryURL)
  }

  /// 保存全部自定义词组到指定目录 (供 BuiltInCustomPhrases.seed()
  /// 两目录播种用)。
  public static func save(_ phrases: [CustomPhrase], to directory: URL) throws {
    var content = fileHeader
    for phrase in phrases {
      content += "\(phrase.word)\t\(phrase.code)\t\(phrase.weight)\n"
    }
    try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

    var t9Content = t9FileHeader
    for phrase in phrases {
      guard let digits = pinyinCodeToT9Digits(phrase.code) else { continue }
      t9Content += "\(phrase.word)\t\(digits)\t\(phrase.weight)\n"
    }
    try t9Content.write(to: directory.appendingPathComponent(t9FileName), atomically: true, encoding: .utf8)
  }

  /// 拼音码 (音节用空格分隔, 如 "ni hao") 转九宫格数字码 (如 "6426"):
  /// 逐音节查 pinyinToT9Mapping, 任一音节查不到就返回 nil (整条跳过)。
  /// 码里有大写/多余空格时先归一化成小写单空格; ü 按输入法惯例当 v 查。
  /// 例外 (第 3 项): 查不到的音节如果是纯字母 (如内置短语的首字母码
  /// "qq"/"kk"/"jd", 或 "sh s" 里的 "sh"), 按九宫格键位逐字母转
  /// (q->7, k->5, j->5/d->3, s->7/h->4), 不再整条跳过——否则 QQ
  /// 这类非拼音码永远进不了 custom_phrase_t9.txt, 九宫格下不生效。
  /// 含非字母的码 (数字、符号) 仍返回 nil。
  static func pinyinCodeToT9Digits(_ code: String) -> String? {
    let syllables = code.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
    guard !syllables.isEmpty else { return nil }
    var digits = ""
    for syllable in syllables {
      let normalized = syllable.replacingOccurrences(of: "ü", with: "v")
      if let digit = pinyinToT9Mapping[normalized] {
        digits += digit
      } else if normalized.allSatisfy({ $0.isASCII && $0.isLetter }) {
        for letter in normalized {
          guard let digit = t9Digit(for: letter) else { return nil }
          digits.append(digit)
        }
      } else {
        return nil
      }
    }
    return digits
  }

  /// 单个字母的九宫格键位 (a/b/c->2, d/e/f->3, g/h/i->4, j/k/l->5,
  /// m/n/o->6, p/q/r/s->7, t/u/v->8, w/x/y/z->9)。
  private static func t9Digit(for letter: Character) -> Character? {
    switch letter {
    case "a", "b", "c": return "2"
    case "d", "e", "f": return "3"
    case "g", "h", "i": return "4"
    case "j", "k", "l": return "5"
    case "m", "n", "o": return "6"
    case "p", "q", "r", "s": return "7"
    case "t", "u", "v": return "8"
    case "w", "x", "y", "z": return "9"
    default: return nil
    }
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
