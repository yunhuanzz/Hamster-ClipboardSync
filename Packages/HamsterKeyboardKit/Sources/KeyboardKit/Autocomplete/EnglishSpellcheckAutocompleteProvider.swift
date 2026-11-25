//
//  EnglishSpellcheckAutocompleteProvider.swift
//
//  第 15 轮第 2 项 (b) 英文纠错: UITextChecker 做的英文纠错/补全 provider。
//
//  可行性 (见 Docs/round15-association-design.md §3):
//  UITextChecker 是 UIKit 自带拼写检查 (系统词典, 扩展内存成本 0),
//  在自定义键盘扩展里可用——ansonl/ios-uitextchecker-autocorrect 就是给
//  “iOS app 或 custom keyboard extension”写的, Combo Keyboard 扩展在用;
//  另一家 iOS 键盘 Dictus 的 2026 架构文档也是 UITextChecker 做补全/纠错。
//  已知 quirks (照抄进实现):
//  - iOS 上 guesses 的顺序接近字母序而非概率序 (文档说按概率, 实测不是):
//    只信首个 guess 做空格自动纠正, 其余只当点选候选。
//  - completions 在 iOS 上也是字母序: 只当点选补全, 不自动上屏。
//  - 25+ 字母的词会被当成没错: 词长上限 24, 直接不查。
//  - 本机无 iOS 运行时, guesses 的具体内容与排序无法活验证, 见设计文档 §6;
//    防御已收敛: 词典缺失时返回 []、词长 2–24、只认字母/撇号、猜测只取
//    前 4 且过滤多词、补全只点选。
//
//  接线: KeyboardInputViewController.autocompleteProvider 换成这个;
//  触发只在英文键盘下 (textDidChange 里 guard isAlphabetic),
//  显示复用 RIME 候选栏 (kind == .englishCorrection, 见 RimeContext)。
//  中文键盘永远不跑这个 provider, 行为不变。
//

import Foundation
import HamsterKit
import UIKit

/// UITextChecker 的英文纠错/补全, 实现 KeyboardKit 的 AutocompleteProvider。
public class EnglishSpellcheckAutocompleteProvider: AutocompleteProvider {
  /// AutocompleteProvider 要求的 locale; 本 provider 只服务英文键盘,
  /// 查词固定用 en_US, 改 locale 不影响查词语言。
  public var locale: Locale = Locale(identifier: "en_US")

  /// UITextChecker 查词用的语言 (系统词典)。
  private let language = "en_US"

  /// 纠错候选最多几条 (首个是空格自动纠正的那个)。
  private let maxCorrectionSuggestions = 4

  /// 补全候选最多几条 (全部只点选, 空格不应用)。
  private let maxCompletionSuggestions = 3

  /// 补全最短词长: "a"/"ab" 的补全全是噪音, 不补。
  private let minCompletionLength = 3

  /// 词长上限: UITextChecker 会把 25+ 字母的词当成没错, 查了也白查。
  private let maxWordLength = 24

  private let textChecker = UITextChecker()

  public init() {}

  public func autocompleteSuggestions(
    for text: String,
    completion: @escaping AutocompleteCompletion
  ) {
    // UITextChecker 是同步的进程内词典查询 (单个词, 毫秒级), 直接在调用
    // 线程上跑, 不另起队列; KeyboardInputViewController.performAutocomplete
    // 本来就在主线程调这里。
    completion(.success(suggestions(for: text)))
  }

  // MARK: - AutocompleteProvider (学习/忽略词)

  /// 生词走系统级: UITextChecker.learnWord 全系统生效。
  public var canLearnWords: Bool { true }

  /// 忽略词走本键盘自己的表 (UserDefaults.hamster.ignoredEnglishWords)。
  public var canIgnoreWords: Bool { true }

  /// UITextChecker 没有“列出全部生词”的 API, 只能逐个查, 这里返回 []。
  public var ignoredWords: [String] {
    UserDefaults.hamster.ignoredEnglishWords
  }

  /// 同上: 无法枚举系统生词表。
  public var learnedWords: [String] { [] }

  public func hasIgnoredWord(_ word: String) -> Bool {
    UserDefaults.hamster.ignoredEnglishWords.contains(word.lowercased())
  }

  public func hasLearnedWord(_ word: String) -> Bool {
    UITextChecker.hasLearnedWord(word)
  }

  public func ignoreWord(_ word: String) {
    var list = UserDefaults.hamster.ignoredEnglishWords
    let lower = word.lowercased()
    guard !list.contains(lower) else { return }
    list.append(lower)
    UserDefaults.hamster.ignoredEnglishWords = list
  }

  public func learnWord(_ word: String) {
    UITextChecker.learnWord(word)
  }

  public func removeIgnoredWord(_ word: String) {
    UserDefaults.hamster.ignoredEnglishWords = UserDefaults.hamster.ignoredEnglishWords.filter { $0 != word.lowercased() }
  }

  public func unlearnWord(_ word: String) {
    UITextChecker.unlearnWord(word)
  }

  // MARK: - private

  /// 给定当前英文词, 返回纠错/补全候选 (AutocompleteSuggestion)。
  /// - 拼错: guesses 前 4, 首个 isAutocomplete=true (空格自动纠正它)。
  /// - 拼对: completions 前 3, 全部 isAutocomplete=false (只点选)。
  /// - 其他情况 (太短/太长/含非字母/无词典): []。
  private func suggestions(for text: String) -> [AutocompleteSuggestion] {
    guard text.count >= 2, text.count <= maxWordLength else { return [] }
    // 只认字母和词中撇号 (don't); 含数字/标点的不查 (那不是英文词)。
    guard text.allSatisfy({ $0.isLetter || $0 == "'" }) else { return [] }
    // 词典没装 (如设备上没有 en_US 词典) 时静默返回 [], 不崩、不出垃圾候选。
    guard UITextChecker.availableLanguages.contains(language) else { return [] }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let misspelledRange = textChecker.rangeOfMisspelledWord(
      in: text, range: range, startingAt: 0, wrap: false, language: language)

    if misspelledRange.location != NSNotFound {
      let guesses = textChecker.guesses(forWordRange: misspelledRange, in: text, language: language) ?? []
      return guesses
        .filter { !$0.isEmpty }
        // 多词猜测 ("hip star") 替换当前词会变两个词, 键盘纠错只换一个词。
        .filter { !$0.contains(" ") }
        .filter { $0.lowercased() != text.lowercased() }
        .filter { !hasIgnoredWord($0) }
        .prefix(maxCorrectionSuggestions)
        .enumerated()
        .map { AutocompleteSuggestion(text: $0.element, isAutocomplete: $0.offset == 0) }
    }

    // 拼对了: 只给补全 (词长 >= 3), 全部只点选。
    guard text.count >= minCompletionLength else { return [] }
    let completions = textChecker.completions(forPartialWordRange: range, in: text, language: language) ?? []
    return completions
      .filter { !$0.isEmpty }
      .filter { $0.lowercased() != text.lowercased() }
      .filter { !hasIgnoredWord($0) }
      .prefix(maxCompletionSuggestions)
      .map { AutocompleteSuggestion(text: $0, isAutocomplete: false) }
  }
}
