//
//  ClipboardContentExtractor.swift
//
//  剪贴板内容提取 (第 17 轮第 6 项): 从一段剪贴板文本里自动提取可单独粘贴的
//  链接与验证码, 展示为可点的小条目 (剪贴板面板卡片内 + 临时复制工具内容视图);
//  点某条只粘贴那一部分, 不粘全文。
//  纯字符串逻辑, 不读剪贴板、不碰 UI, 方便单测。
//

import Foundation

/// 剪贴板内容提取: 链接 (URL) 与验证码。
enum ClipboardContentExtractor {
  /// 一条可单独粘贴的提取项。
  struct ExtractedItem: Equatable {
    enum Kind: Equatable {
      /// 链接 (http(s)://… 或 www.…)
      case url
      /// 验证码 (4–8 位数字)
      case verificationCode
    }

    let kind: Kind
    /// 只粘贴的这一部分 (链接原文 / 验证码数字串)。
    let text: String
  }

  /// 链接与验证码的关键字 (验证码优先匹配其附近的数字串)。
  private static let verificationCodeKeywords = ["验证码", "校验码", "动态码", "短信码"]

  /// 从文本中提取链接与验证码 (链接在前、验证码在后, 各最多 5 条, 去重保序)。
  static func extract(from text: String) -> [ExtractedItem] {
    guard !text.isEmpty else { return [] }
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)

    // 1. 链接: http(s)://… 或 www.…; 尾部标点 (句号/逗号/括号等) 不是链接的一部分。
    let urlRanges = urlRanges(in: nsText, fullRange: fullRange)
    var items: [ExtractedItem] = []
    var seen: Set<String> = []
    for range in urlRanges {
      let url = nsText.substring(with: range)
      guard !url.isEmpty, seen.insert(url).inserted else { continue }
      items.append(ExtractedItem(kind: .url, text: url))
      if items.count >= 5 { break }
    }

    // 2. 验证码: 先找关键字附近的数字串 (如"验证码是 123456"、"123456 是您的验证码"),
    // 再补独立的 4–8 位数字串; 链接内部的数字不算 (按链接范围排除)。
    // (?<!\d) / (?!\d) 必不可少: 没有它们, "订单号 123456789012，验证码"
    // 会从 12 位长串的尾部抠出 "56789012" 当验证码 (实测)。
    var codes: [String] = []
    let keywordPattern = "(?:\(verificationCodeKeywords.joined(separator: "|")))[^0-9]{0,8}([0-9]{4,8})(?!\\d)"
    let keywordAfterPattern = "(?<!\\d)([0-9]{4,8})[^0-9]{0,8}(?:\(verificationCodeKeywords.joined(separator: "|")))"
    for pattern in [keywordPattern, keywordAfterPattern] {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in regex.matches(in: text, range: fullRange) {
        guard match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound else { continue }
        let code = nsText.substring(with: match.range(at: 1))
        guard !code.isEmpty, !codes.contains(code) else { continue }
        // 关键字附近的数字串若落在链接里 (如短链后的数字), 仍排除。
        guard !urlRanges.contains(where: { NSIntersectionRange($0, match.range(at: 1)).length > 0 }) else { continue }
        codes.append(code)
        if codes.count >= 5 { break }
      }
      if codes.count >= 5 { break }
    }
    if codes.count < 5 {
      // 独立数字串: 取最长的连续数字段, 长度 4–8 位才算 (更长的如手机号/订单号不算)。
      guard let digitRegex = try? NSRegularExpression(pattern: "[0-9]+") else { return items }
      for match in digitRegex.matches(in: text, range: fullRange) {
        let run = nsText.substring(with: match.range)
        guard (4...8).contains(run.count), !codes.contains(run) else { continue }
        guard !urlRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
        codes.append(run)
        if codes.count >= 5 { break }
      }
    }
    items.append(contentsOf: codes.map { ExtractedItem(kind: .verificationCode, text: $0) })
    return items
  }

  /// 链接范围 (已去尾部标点)。链接字符集里直接排除中英文句末标点与中文括号:
  /// 中文文本里的链接一定在"。"、"，"、"）"等标点前结束 (如"见 https://x.cn。",
  /// 若只靠事后去尾部标点, "。"后面的正文会被一起吞进链接)。
  /// 尾部 ASCII 标点 (如句号、右括号) 再单独去掉。
  private static func urlRanges(in nsText: NSString, fullRange: NSRange) -> [NSRange] {
    guard
      let regex = try? NSRegularExpression(
        pattern: "(?:https?://|www\\.)[^\\s<>\"'\\]。、，；：！？（）【】「」『』]+")
    else { return [] }
    let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")
    return regex.matches(in: nsText as String, range: fullRange).compactMap { match in
      var range = match.range
      // 从后往前去掉尾部 ASCII 标点 (如"见 https://x.cn."里的句号);
      // 中文标点匹配时已排除, 不会进到这里。
      // 右括号 ) 只在"不成对"时去掉: 链接本身可能以成对括号结尾
      // (如 https://en.wikipedia.org/wiki/PC_Tools_(Central_Point_Software)),
      // 成对时保留, 多余的那个才去掉。
      while range.length > 0 {
        let lastChar = nsText.substring(with: NSRange(location: range.location + range.length - 1, length: 1))
        if lastChar == ")" {
          let candidate = nsText.substring(with: range)
          let openCount = candidate.filter { $0 == "(" }.count
          let closeCount = candidate.filter { $0 == ")" }.count
          guard closeCount > openCount else { break }
          range.length -= 1
        } else if lastChar.unicodeScalars.allSatisfy({ trailingPunctuation.contains($0) }) {
          range.length -= 1
        } else {
          break
        }
      }
      return range.length > 0 ? range : nil
    }
  }
}
