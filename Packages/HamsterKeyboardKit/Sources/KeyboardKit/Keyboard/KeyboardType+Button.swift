//
//  KeyboardType+Button.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-01-09.
//  Copyright © 2021-2023 Daniel Saidi. All rights reserved.
//

import UIKit

public extension KeyboardType {
  /**
   The keyboard type's standard button image.

   键盘类型的标准按键图像。
   */
  var standardButtonImage: UIImage? {
    switch self {
    case .email: return HamsterUIImage.shared.keyboardEmail
    case .emojis: return HamsterUIImage.shared.keyboardEmoji
    case .images: return HamsterUIImage.shared.keyboardImages
    case .alphabetic: return HamsterUIImage.shared.keyboardStateChinese
    // 英文侧返回主键盘的键 (iPhoneKeyboardLayoutProvider.bottomActions
    // 里是 .keyboardType(selectKeyboard)): 主键盘是中文 26 键时是
    // .chinese, 是九宫格/自定义中文键盘时是 .chineseNineGrid/.custom,
    // 都要显示中/英切换形式的 englishState 图标 (大"英"+小"中"),
    // 不能只显示纯文本"中" (第 11 轮第 5 条: 之前 .chineseNineGrid /
    // .custom 没有映射, standardButtonImage 返回 nil, 按键回退到
    // standardButtonText 的"中")。9 键/26 键中文侧的键是
    // .keyboardType(.alphabetic) -> chineseState, 不动。
    case .chinese, .chineseNineGrid, .custom: return HamsterUIImage.shared.keyboardStateEnglish
    default: return nil
    }
  }

  var chineseImage: UIImage {
    HamsterUIImage.shared.keyboardStateChinese
  }

  var englishImage: UIImage {
    HamsterUIImage.shared.keyboardStateEnglish
  }

  /**
   The keyboard type's standard button text.

   键盘类型的标准按钮文本。
   */
  func standardButtonText(for context: KeyboardContext) -> String? {
    switch self {
    case .chinese, .chineseNineGrid: return "中"
    case .classifySymbolic, .classifySymbolicOfLight: return "符号"
    case .alphabetic: return "ABC"
    case .numeric: return "123"
    case .numericNineGrid: return "123"
    case .chineseNumeric: return "123"
    case .symbolic: return "#+="
    case .chineseSymbolic: return "#+="
    case .custom: return "中"
    default: return nil
//    case .alphabetic: return KKL10n.keyboardTypeAlphabetic.text(for: context)
//    case .numeric: return KKL10n.keyboardTypeNumeric.text(for: context)
//    case .symbolic: return KKL10n.keyboardTypeSymbolic.text(for: context)
    }
  }
}
