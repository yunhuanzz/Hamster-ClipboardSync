//
//  PhraseAutocomplete.swift
//  HamsterKeyboardKit
//
//  常用语补全: 打字时按已输入的前缀, 把整条常用语挂进候选栏首位,
//  点选即上屏整条短语。
//
//  匹配规则 (前缀匹配, 不区分大小写):
//  - 英文键盘 / 26 键中文: 已输入的字母是短语字面小写形式的前缀,
//    或 (短语含汉字时) 其拼音的前缀。如常用语有 yunhuanzzz@gmail.com,
//    输入 yunh -> 补全整封邮箱; 常用语有“你好”, 输入 nih -> 补全“你好”。
//  - 九宫格: 已输入的数字 (边栏固定成拼音字母的音节先还原成数字码)
//    是短语拼音转九宫格数字码的前缀, 仅限含汉字的短语 (纯英文短语
//    不做数字->字母映射, 英文请用英文键盘输入)。
//  - 数字键盘 (123 页): 已输入的数字是短语字面的数字前缀,
//    如常用语存了手机号 13812345678, 输入 138 -> 补全整个号码。
//  - 短语与已输入完全相等时不需要补全; 输入少于 2 个字符时不触发
//    (避免每敲一个键都弹); 删掉短语即关闭它的补全。
//  - 汉字 -> 拼音用系统 CFStringTransform (mandarinToLatin, 不依赖
//    任何内置词表); 多音字取最常见读音, 错了只会导致该短语不补全,
//    不会插错字 (点选前用户能看到整条短语原文)。
//  - 默认开启, 无开关 (删短语即关)。
//
//  显示: 挂在候选栏首位, 与引擎候选并列 (不替换它们),
//  isAutocomplete = true (高亮底色) + subtitle “常用语”。
//  点选以外的入口 (空格/符号/emoji 顶字、首选/次选快捷指令、
//  长按忘词/置顶) 一律只认引擎候选, 不碰补全项。
//

import Foundation
import HamsterKit

/// 常用语补全的纯逻辑 (不碰 UIKit、不碰 RIME), 供 RimeContext 与
/// KeyboardInputViewController 共用。
public enum PhraseAutocomplete {

  /// 补全的输入种类, 决定按哪种键匹配。
  public enum Kind {
    /// 字母输入 (英文键盘 / 26 键中文): 按字面或拼音前缀匹配。
    case latin
    /// 九宫格输入 (数字, 可能含边栏固定成的拼音字母): 按拼音数字码前缀匹配。
    case t9Digits
    /// 数字键盘输入 (纯数字): 按短语字面数字前缀匹配。
    case digits
  }

  /// 触发补全的最少已输入字符数 (少于这个数不弹, 避免单键噪音)。
  public static let minimumTypedLength = 2

  // MARK: - 短语的匹配键 (按短语文本缓存, 文本不变键就不变)

  /// 一条短语的全部匹配键。
  public struct MatchKeys {
    /// 短语字面小写形式 (如 yunhuanzzz@gmail.com)。
    public let literal: String
    /// 短语的拼音 (去空格、去声调、小写, 如 nihao; 不含汉字时为 nil)。
    public let pinyin: String?
    /// 拼音转九宫格数字码 (如 64426; 不含汉字或音节切不出时为 nil)。
    public let t9Digits: String?
  }

  private static var keysCache: [String: MatchKeys] = [:]

  /// 算 (并缓存) 一条短语的匹配键。
  public static func matchKeys(for phrase: String) -> MatchKeys {
    if let cached = keysCache[phrase] { return cached }
    let keys: MatchKeys
    if phrase.containsCJK {
      let pinyin = pinyinString(for: phrase)
      keys = MatchKeys(
        literal: phrase.lowercased(),
        pinyin: pinyin,
        t9Digits: pinyin.flatMap { pinyinToT9Digits($0) }
      )
    } else {
      keys = MatchKeys(literal: phrase.lowercased(), pinyin: nil, t9Digits: nil)
    }
    keysCache[phrase] = keys
    return keys
  }

  /// 汉字短语 -> 拼音 (系统转换, 如“你好”-> nihao)。
  /// 无汉字时也可用 (拉丁字母原样返回), 但调用方只对含汉字的短语算拼音。
  public static func pinyinString(for phrase: String) -> String? {
    guard let latin = phrase.applyingTransform(.mandarinToLatin, reverse: false),
          let stripped = latin.applyingTransform(.stripDiacritics, reverse: false)
    else { return nil }
    let compact = stripped
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "ü", with: "v")
      .lowercased()
    return compact.isEmpty ? nil : compact
  }

  /// 连续拼音串 (如 nihao) -> 九宫格数字码 (如 64426)。
  /// 贪心最长音节切分 (音节表 = pinyinToT9Mapping 的键, 最长 6 字母);
  /// 任一位置切不出音节就返回 nil (整条短语跳过, 不写错码)。
  public static func pinyinToT9Digits(_ pinyin: String) -> String? {
    guard !pinyin.isEmpty else { return nil }
    var digits = ""
    var index = pinyin.startIndex
    while index < pinyin.endIndex {
      var matched: String?
      // 最长音节 6 字母 (zhuang/shuang/chuang), 从长到短试。
      for length in (1...6).reversed() {
        guard let end = pinyin.index(index, offsetBy: length, limitedBy: pinyin.endIndex) else { continue }
        let syllable = String(pinyin[index..<end])
        if pinyinToT9Mapping[syllable] != nil {
          matched = syllable
          break
        }
      }
      guard let syllable = matched, let digit = pinyinToT9Mapping[syllable] else { return nil }
      digits += digit
      index = pinyin.index(index, offsetBy: syllable.count)
    }
    return digits.isEmpty ? nil : digits
  }

  /// 九宫格九键字母 -> 数字 (2=abc, 3=def, 4=ghi, 5=jkl, 6=mno,
  /// 7=pqrs, 8=tuv, 9=wxyz; 每个字母只属于一组, 无歧义)。
  /// 非字母返回 nil。
  public static func t9Digit(for letter: Character) -> Character? {
    switch letter.lowercased() {
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

  /// 九宫格输入归一化: 数字保留, 已固定成拼音字母的音节还原成数字码
  /// (如 tian74 -> 842674)。含数字/字母以外的字符返回 nil。
  public static func normalizedT9Input(_ typed: String) -> String? {
    guard !typed.isEmpty else { return nil }
    var digits = ""
    for ch in typed {
      if ch.isNumber, ch.isASCII {
        digits.append(ch)
      } else if let digit = t9Digit(for: ch) {
        digits.append(digit)
      } else {
        return nil
      }
    }
    return digits
  }

  // MARK: - 匹配

  /// 按已输入找第一条匹配的常用语 (按列表顺序)。
  /// typed 为空、短于 minimumTypedLength、与键完全相等时返回 nil。
  /// - Parameters:
  ///   - typed: 当前已输入 (字母/数字, 未归一化也行, 内部会处理)。
  ///   - kind: 输入种类。
  ///   - phrases: 常用语列表 (UserDefaults.hamster.commonPhrases)。
  /// - Returns: 匹配到的短语原文, 或 nil。
  public static func completion(
    forTypedInput typed: String,
    kind: Kind,
    phrases: [String]
  ) -> String? {
    guard typed.count >= minimumTypedLength else { return nil }
    switch kind {
    case .latin:
      let lower = typed.lowercased()
      guard lower.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
      for phrase in phrases where !phrase.isEmpty {
        let keys = matchKeys(for: phrase)
        if lower.count < keys.literal.count, keys.literal.hasPrefix(lower) { return phrase }
        if let pinyin = keys.pinyin, lower.count < pinyin.count, pinyin.hasPrefix(lower) { return phrase }
      }
      return nil
    case .t9Digits:
      guard let digits = normalizedT9Input(typed) else { return nil }
      for phrase in phrases where !phrase.isEmpty {
        guard let code = matchKeys(for: phrase).t9Digits else { continue }
        if digits.count < code.count, code.hasPrefix(digits) { return phrase }
      }
      return nil
    case .digits:
      guard typed.allSatisfy({ $0.isNumber && $0.isASCII }) else { return nil }
      for phrase in phrases where !phrase.isEmpty {
        if typed.count < phrase.count, phrase.hasPrefix(typed) { return phrase }
      }
      return nil
    }
  }

  // MARK: - 当前输入提取

  /// 从 RIME preedit 里取当前正在输入的部分: 去空格后末尾连续的
  /// ASCII 字母/数字 (已提交的中文在前面, 遇到中文/大写/标点就停)。
  /// 如 preedit “今天8426 74 9436 426” -> “8426749436426”,
  /// “yunh” -> “yunh”。syncContext 里 preedit 是刚读的, 不是缓存。
  public static func currentTypedInput(fromPreedit preedit: String) -> String {
    let stripped = preedit.replacingOccurrences(of: " ", with: "")
    var run = ""
    for ch in stripped.reversed() {
      guard ch.isASCII, ch.isLetter || ch.isNumber else { break }
      run.insert(ch, at: run.startIndex)
    }
    return run
  }

  /// 文档光标前连续的 ASCII 字母 (英文键盘用, 如 “yunh”)。
  public static func trailingLetters(in beforeInput: String) -> String {
    var run = ""
    for ch in beforeInput.reversed() {
      guard ch.isASCII, ch.isLetter else { break }
      run.insert(ch, at: run.startIndex)
    }
    return run
  }

  /// 文档光标前连续的 ASCII 数字 (数字键盘用, 如 “138”)。
  public static func trailingDigits(in beforeInput: String) -> String {
    var run = ""
    for ch in beforeInput.reversed() {
      guard ch.isASCII, ch.isNumber else { break }
      run.insert(ch, at: run.startIndex)
    }
    return run
  }
}

private extension String {
  /// 是否含汉字。
  var containsCJK: Bool {
    unicodeScalars.contains { scalar in
      (0x3400...0x4DBF).contains(scalar.value)
        || (0x4E00...0x9FFF).contains(scalar.value)
        || (0xF900...0xFAFF).contains(scalar.value)
    }
  }
}
