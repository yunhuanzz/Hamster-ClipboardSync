//
//  ClassifySymbolKeyboardStyle.swift
//
//
//  Created by morse on 2023/10/20.
//

import UIKit

/// 非标准键盘样式（适用与分类符号键盘/Emoji键盘等）
public struct NonStandardKeyboardStyle {
  /// 背景色
  public var backgroundColor: UIColor?

  /// 按下时背景色
  public var pressedBackgroundColor: UIColor?

  /// 前景色
  public var foregroundColor: UIColor?

  /// 按下时前景色
  public var pressedForegroundColor: UIColor

  /// 边框颜色
  public var borderColor: UIColor?

  /// 底部阴影颜色
  public var shadowColor: UIColor

  /// 圆角半径
  public var cornerRadius: CGFloat

  /// 符号格白键底色 (第 11 轮第 3 条: 微信符号菜单的键是白色圆角键,
  /// 不是扁平文字; 旧 backgroundColor 是功能键灰, 不能复用)。
  /// nil 时 SymbolCell 回退到 backgroundColor。
  public var keyBackgroundColor: UIColor?

  /// 符号格白键按下时的底色。nil 时回退到 pressedBackgroundColor。
  public var keyPressedBackgroundColor: UIColor?

  init(
    backgroundColor: UIColor? = nil,
    pressedBackgroundColor: UIColor? = nil,
    foregroundColor: UIColor? = nil,
    pressedForegroundColor: UIColor,
    borderColor: UIColor? = nil,
    shadowColor: UIColor,
    cornerRadius: CGFloat,
    keyBackgroundColor: UIColor? = nil,
    keyPressedBackgroundColor: UIColor? = nil
  ) {
    self.backgroundColor = backgroundColor
    self.pressedBackgroundColor = pressedBackgroundColor
    self.foregroundColor = foregroundColor
    self.pressedForegroundColor = pressedForegroundColor
    self.borderColor = borderColor
    self.shadowColor = shadowColor
    self.cornerRadius = cornerRadius
    self.keyBackgroundColor = keyBackgroundColor
    self.keyPressedBackgroundColor = keyPressedBackgroundColor
  }
}
