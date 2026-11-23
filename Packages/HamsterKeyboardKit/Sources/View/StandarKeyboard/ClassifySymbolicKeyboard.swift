//
//  ClassifySymbolicKeyboard.swift
//
//
//  Created by morse on 2023/9/5.
//

import HamsterUIKit
import UIKit

/// 分类符号键盘 (第 10 轮第 5 条: 仿微信符号菜单重排)。
///
/// 布局 (自上而下, 与微信输入法符号菜单一致):
///   顶部快符条 (SymbolQuickStripView) + 符号网格 (SymbolsView, 全宽)
///   + 底部类别条 (BottomRowView: 绿 ← 返回 + 横向滚动的类别按钮 + 锁定 + ⌫)。
/// 左侧分类栏 ClassifyView 已删: 它复用 SymbolCell 做分类标签,
/// "特殊"一栏在列表 cell 里被缩成约 40% 的部首簇 (乱码观感),
/// 新的底部类别条用 UIButton + 显式 15pt 字体, 不再经过 SymbolCell。
///
/// 背景: 整块用 HamsterUIColor.shared.standardKeyboardBackground
/// (浅色 #D5D6DD / 深色 #2C2C2C, 均不透明), 子视图一律 .clear,
/// 不再是之前三块深浅不一的 style.backgroundColor
/// (standardDarkButtonBackground) 与近乎透明的键盘根底色混搭。
class ClassifySymbolicKeyboard: NibLessView {
  private let keyboardContext: KeyboardContext
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private let layoutProvider: KeyboardLayoutProvider
  private var symbolsViewHeightConstraint: NSLayoutConstraint?
  private var bottomRowViewHeightConstraint: NSLayoutConstraint?

  // 屏幕方向
  private var interfaceOrientation: InterfaceOrientation
  private var userInterfaceStyle: UIUserInterfaceStyle

  private var style: NonStandardKeyboardStyle

  // 键盘是否浮动
  private var isKeyboardFloating: Bool

  private lazy var viewModel: ClassifySymbolicViewModel = {
    let vm = ClassifySymbolicViewModel()
    return vm
  }()

  /// 顶部快符条: 常用符号横向滚动, 点按直接上屏。
  private lazy var quickStripView: SymbolQuickStripView = {
    let view = SymbolQuickStripView(style: style, actionHandler: actionHandler, keyboardContext: keyboardContext)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 符号网格 (全宽, 复用 SymbolsView; 分类切换由 viewModel 驱动)。
  private lazy var symbolsView: SymbolsView = {
    let view = SymbolsView(style: style, keyboardContext: keyboardContext, actionHandler: actionHandler, viewModel: viewModel)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 底部类别条: 绿 ← 返回 + 横向滚动的类别按钮 + 锁定 + ⌫。
  private lazy var bottomRow: BottomRowView = {
    let view = BottomRowView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      viewModel: viewModel)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  // MARK: - 计算属性

  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  // MARK: - Initailization

  init(actionHandler: KeyboardActionHandler, appearance: KeyboardAppearance, layoutProvider: KeyboardLayoutProvider, keyboardContext: KeyboardContext) {
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.layoutProvider = layoutProvider
    self.keyboardContext = keyboardContext
    self.interfaceOrientation = keyboardContext.interfaceOrientation
    self.isKeyboardFloating = keyboardContext.isKeyboardFloating
    self.userInterfaceStyle = keyboardContext.colorScheme
    self.style = appearance.nonStandardKeyboardStyle

    super.init(frame: .zero)

    setupAppearance()
    constructViewHierarchy()
    activateViewConstraints()
  }

  override func setupAppearance() {
    // 与定制面板同款的不透明键盘底色 (浅色 #D5D6DD / 深色 #2C2C2C,
    // asset 自带深浅两套值, 不写死色值); 子视图背景均为 .clear,
    // 整块底色只有这一处来源, 不透出后面 App 的内容。
    backgroundColor = HamsterUIColor.shared.standardKeyboardBackground
  }

  // MARK: - Layout

  /// 构建视图层次
  override func constructViewHierarchy() {
    addSubview(quickStripView)
    addSubview(symbolsView)
    addSubview(bottomRow)
  }

  /// 激活视图约束
  override func activateViewConstraints() {
    let layoutConfig = layoutConfig
    let symbolViewHeight = layoutConfig.rowHeight * 3

    bottomRowViewHeightConstraint = bottomRow.heightAnchor.constraint(equalToConstant: layoutConfig.rowHeight)
    bottomRowViewHeightConstraint?.priority = .defaultHigh
    symbolsViewHeightConstraint = symbolsView.heightAnchor.constraint(equalToConstant: symbolViewHeight)
    symbolsViewHeightConstraint?.priority = .defaultHigh

    NSLayoutConstraint.activate([
      quickStripView.topAnchor.constraint(equalTo: topAnchor),
      quickStripView.leadingAnchor.constraint(equalTo: leadingAnchor),
      quickStripView.trailingAnchor.constraint(equalTo: trailingAnchor),
      quickStripView.heightAnchor.constraint(equalToConstant: 40),

      symbolsView.topAnchor.constraint(equalTo: quickStripView.bottomAnchor),
      symbolsView.leadingAnchor.constraint(equalTo: leadingAnchor),
      symbolsView.trailingAnchor.constraint(equalTo: trailingAnchor),

      bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor),
      bottomRow.trailingAnchor.constraint(equalTo: trailingAnchor),
      bottomRow.topAnchor.constraint(equalTo: symbolsView.bottomAnchor),
      bottomRow.bottomAnchor.constraint(equalTo: bottomAnchor),

      bottomRowViewHeightConstraint!,
      symbolsViewHeightConstraint!
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      style = appearance.nonStandardKeyboardStyle
      setupAppearance()
      quickStripView.setStyle(style)
      symbolsView.setStyle(style)
      bottomRow.setStyle(style)
    }

    guard interfaceOrientation != keyboardContext.interfaceOrientation || isKeyboardFloating != keyboardContext.isKeyboardFloating else { return }
    interfaceOrientation = keyboardContext.interfaceOrientation
    isKeyboardFloating = keyboardContext.isKeyboardFloating

    let layoutConfig = layoutConfig
    let symbolViewHeight = layoutConfig.rowHeight * 3
    symbolsViewHeightConstraint?.constant = symbolViewHeight
    bottomRowViewHeightConstraint?.constant = layoutConfig.rowHeight
  }
}
