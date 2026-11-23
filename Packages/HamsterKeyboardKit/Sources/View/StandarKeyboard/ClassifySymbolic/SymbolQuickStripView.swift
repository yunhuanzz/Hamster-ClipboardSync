//
//  SymbolQuickStripView.swift
//
//
//  Created by round10-part3 on 2026/11/24.
//

import HamsterUIKit
import UIKit

/// 顶部快符条 (第 10 轮第 5 条: 仿微信符号菜单顶部的符号条)。
///
/// 一行常用符号, 横向滚动, 点按直接上屏, 动作与网格点按完全一致
/// (press .symbol → 未锁定时 release .returnLastKeyboard → release .symbol;
/// release .symbol 会把该符号登记进最近使用)。
/// 微信顶部条同款内容: “ ” + - . % × / … , 后面再补几个中文常用标点,
/// 滑到头可见。符号本身是固定文案, 不走 SymbolCell / 分类数据。
class SymbolQuickStripView: NibLessView {
  private var style: NonStandardKeyboardStyle
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext

  /// 顶部条符号 (微信同款顺序)。
  static let quickSymbols = ["“", "”", "+", "-", ".", "%", "×", "/", "…", "，", "。", "？", "！", "、", "：", "；"]

  /// 符号字号与网格 SymbolCell 一致 (17pt), 但这里是 UIButton 显式指定。
  private static let symbolFont = UIFont.systemFont(ofSize: 17)

  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  private lazy var stackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private var symbolButtons: [UIButton] = []

  init(style: NonStandardKeyboardStyle, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext) {
    self.style = style
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext

    super.init(frame: .zero)

    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  /// 构建视图层次
  override func constructViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(stackView)

    for symbol in Self.quickSymbols {
      let button = UIButton(type: .system)
      button.setTitle(symbol, for: .normal)
      button.titleLabel?.font = Self.symbolFont
      button.setTitleColor(style.foregroundColor, for: .normal)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = Self.quickSymbols.firstIndex(of: symbol) ?? 0
      button.addTarget(self, action: #selector(symbolTouchDown(_:)), for: .touchDown)
      button.addTarget(self, action: #selector(symbolTouchUp(_:)), for: .touchUpInside)
      button.addTarget(self, action: #selector(symbolTouchCancelled(_:)), for: [.touchUpOutside, .touchCancel, .touchDragExit])
      button.widthAnchor.constraint(equalToConstant: 40).isActive = true
      button.heightAnchor.constraint(equalToConstant: 32).isActive = true
      symbolButtons.append(button)
      stackView.addArrangedSubview(button)
    }
  }

  /// 激活视图约束
  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  override func setupAppearance() {
    // 背景透明, 由 ClassifySymbolicKeyboard 提供整块不透明底色。
    backgroundColor = .clear
    for button in symbolButtons {
      button.setTitleColor(style.foregroundColor, for: .normal)
    }
  }

  func setStyle(_ style: NonStandardKeyboardStyle) {
    self.style = style
    setupAppearance()
  }
}

extension SymbolQuickStripView {
  /// 按下: 与 SymbolsView 的 shouldSelectItemAt 相同, 先发 press。
  @objc private func symbolTouchDown(_ sender: UIButton) {
    sender.backgroundColor = style.pressedBackgroundColor
    let symbol = Symbol(char: Self.quickSymbols[sender.tag])
    actionHandler.handle(.press, on: .symbol(symbol))
  }

  /// 松开: 与 SymbolsView 的 didSelectItemAt 相同, 未锁定时先回键盘再上屏。
  @objc private func symbolTouchUp(_ sender: UIButton) {
    sender.backgroundColor = .clear
    let symbol = Symbol(char: Self.quickSymbols[sender.tag])
    if !keyboardContext.classifySymbolKeyboardLockState {
      actionHandler.handle(.release, on: .returnLastKeyboard)
    }
    actionHandler.handle(.release, on: .symbol(symbol))
  }

  @objc private func symbolTouchCancelled(_ sender: UIButton) {
    sender.backgroundColor = .clear
  }
}
