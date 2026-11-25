//
//  BottomRowView.swift
//
//
//  Created by morse on 2023/9/5.
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/// 底部类别条 (第 10 轮第 5 条: 仿微信符号菜单底部栏重排)。
///
/// 自左而右: 绿色 ← 返回 | 横向滚动的类别按钮 (全部 16 个分类) | 锁定 | ⌫。
/// 类别按钮是 UIButton + 显式 15pt 字体, 不再复用 SymbolCell 做分类标签
/// —— 旧左侧栏 ClassifyView 里 "特殊"一栏在列表 cell 中被缩成约 40%
/// 的部首簇 (乱码观感) 的根因就是列表 cell 的渲染, 新按钮与之无关。
/// 第 5 个分类 (特殊) 仍在类别条里, 横向滚动可达。
///
/// 返回 / 锁定 / 退格 (含上滑清全部) 的动作与原来一致,
/// 只把返回由文字 "返回" 改成微信同款绿色 ← 按钮。
class BottomRowView: NibLessView {
  private var style: NonStandardKeyboardStyle
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private let viewModel: ClassifySymbolicViewModel
  private var subscriptions = Set<AnyCancellable>()

  /// 类别按钮显式字体: 写死 15pt, 不经过 SymbolCell / 列表 cell 的
  /// 自动字号, 杜绝 "特殊"一栏那种缩小渲染再次出现。
  private static let categoryFont = UIFont.systemFont(ofSize: 15)

  /// 绿色 ← 返回 (仿微信 / 与 EmojisKeyboard 的返回键同款)。
  lazy var returnButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemGreen
    button.layer.cornerRadius = 8
    button.addTarget(self, action: #selector(returnKeyboardPressHandled(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(returnKeyboardReleaseHandled(_:)), for: .touchUpInside)
    button.addTarget(self, action: #selector(returnKeyboardCancelled(_:)), for: [.touchUpOutside, .touchCancel])
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  /// 类别横向滚动条 (16 个分类放不下时可左右滑, 仿微信底部类别条)。
  private lazy var categoryScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  private lazy var categoryStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 类别按钮 (与 SymbolCategory.all 一一对应, 顺序与旧左侧栏一致)。
  private var categoryButtons: [UIButton] = []

  // 锁定状态
  lazy var lockStateButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(systemName: keyboardContext.classifySymbolKeyboardLockState ? "lock" : "lock.open"), for: .normal)
    button.addTarget(self, action: #selector(lockStatePressHandled(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(lockStateReleaseHandled(_:)), for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  lazy var backspaceButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(systemName: "delete.left"), for: .normal)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .label
    button.addTarget(self, action: #selector(backspacePressHandled(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(backspaceReleaseHandled(_:)), for: .touchUpInside)
    // 上滑回退键清空全部已输入内容。
    // 符号键盘的回退键是独立 UIButton, 不走 KeyboardButton 的 itemSwipes,
    // 所以这里单独加一个上滑手势。
    let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(backspaceSwipeUpHandled(_:)))
    swipeUp.direction = .up
    button.addGestureRecognizer(swipeUp)
    return button
  }()

  init(
    style: NonStandardKeyboardStyle,
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext,
    viewModel: ClassifySymbolicViewModel
  ) {
    self.style = style
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.viewModel = viewModel

    super.init(frame: .zero)

    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    setInitialCategory()
    combine()
  }

  /// 初始分类: 点符号默认进“常用”, 不再按中文/英文区分。
  private func setInitialCategory() {
    viewModel.currentCategory = .frequent
    updateCategorySelection()
    scrollSelectedCategoryIntoView(animated: false)
  }

  func combine() {
    // 分类可能从别处被改 (目前只有本栏改), 跟随 viewModel 刷新高亮。
    viewModel.$currentCategory
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateCategorySelection()
      }
      .store(in: &subscriptions)
  }

  /// 构建视图层次
  override func constructViewHierarchy() {
    addSubview(returnButton)
    addSubview(categoryScrollView)
    categoryScrollView.addSubview(categoryStackView)
    addSubview(lockStateButton)
    addSubview(backspaceButton)

    for category in SymbolCategory.all {
      let button = UIButton(type: .system)
      button.setTitle(category.string, for: .normal)
      // 显式字体 (见 categoryFont 注释): 分类标签不再走 SymbolCell。
      button.titleLabel?.font = Self.categoryFont
      button.setTitleColor(.label, for: .normal)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = SymbolCategory.all.firstIndex(of: category) ?? 0
      button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
      // 按钮宽 = 文字实测宽 + 两侧各 8pt 内边距 (不用 contentEdgeInsets,
      // 该 API 已废弃; 也不依赖 intrinsicContentSize 猜宽度)。
      let textWidth = (category.string as NSString).size(withAttributes: [.font: Self.categoryFont]).width
      button.widthAnchor.constraint(equalToConstant: ceil(textWidth) + 16).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
      categoryButtons.append(button)
      categoryStackView.addArrangedSubview(button)
    }
  }

  /// 激活视图约束
  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      returnButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      returnButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      returnButton.widthAnchor.constraint(equalToConstant: 36),
      returnButton.heightAnchor.constraint(equalToConstant: 36),

      categoryScrollView.leadingAnchor.constraint(equalTo: returnButton.trailingAnchor, constant: 8),
      categoryScrollView.trailingAnchor.constraint(equalTo: lockStateButton.leadingAnchor, constant: -8),
      categoryScrollView.centerYAnchor.constraint(equalTo: centerYAnchor),
      categoryScrollView.heightAnchor.constraint(equalToConstant: 36),

      categoryStackView.topAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.topAnchor),
      categoryStackView.bottomAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.bottomAnchor),
      categoryStackView.leadingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.leadingAnchor),
      categoryStackView.trailingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.trailingAnchor),
      categoryStackView.heightAnchor.constraint(equalTo: categoryScrollView.frameLayoutGuide.heightAnchor),

      lockStateButton.trailingAnchor.constraint(equalTo: backspaceButton.leadingAnchor, constant: -4),
      lockStateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      lockStateButton.widthAnchor.constraint(equalToConstant: 36),
      lockStateButton.heightAnchor.constraint(equalToConstant: 36),

      backspaceButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      backspaceButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      backspaceButton.widthAnchor.constraint(equalToConstant: 36),
      backspaceButton.heightAnchor.constraint(equalToConstant: 36),
    ])
  }

  override func setupAppearance() {
    // 本栏背景透明, 由 ClassifySymbolicKeyboard 提供整块不透明底色。
    backgroundColor = .clear
    lockStateButton.tintColor = style.foregroundColor
    backspaceButton.tintColor = style.foregroundColor
  }

  func setStyle(_ style: NonStandardKeyboardStyle) {
    self.style = style
    setupAppearance()
  }

  // MARK: - 分类切换

  private func updateCategorySelection() {
    for (index, button) in categoryButtons.enumerated() {
      let selected = SymbolCategory.all[index] == viewModel.currentCategory
      button.backgroundColor = selected ? .systemFill : .clear
      button.layer.cornerRadius = 8
    }
  }

  private func scrollSelectedCategoryIntoView(animated: Bool) {
    guard let index = SymbolCategory.all.firstIndex(of: viewModel.currentCategory),
          categoryButtons.indices.contains(index) else { return }
    let button = categoryButtons[index]
    // 按钮 frame 在 stackView 坐标系下即 scrollView 的 content 坐标系
    // (stackView 原点就是 content 原点), 可直接用于 scrollRectToVisible。
    categoryScrollView.scrollRectToVisible(button.frame.insetBy(dx: -8, dy: 0), animated: animated)
  }

  @objc private func categoryTapped(_ sender: UIButton) {
    let category = SymbolCategory.all[sender.tag]
    viewModel.currentCategory = category
    updateCategorySelection()
    scrollSelectedCategoryIntoView(animated: true)
  }
}

extension BottomRowView {
  @objc func returnKeyboardPressHandled(_ button: UIButton) {
    // 绿色按钮不换底色, 按下时半透明反馈 (与原来按压变色等价的视觉反馈)。
    button.alpha = 0.6
    actionHandler.handle(.press, on: .returnLastKeyboard)
  }

  @objc func returnKeyboardReleaseHandled(_ button: UIButton) {
    button.alpha = 1.0
    actionHandler.handle(.release, on: .returnLastKeyboard)
  }

  @objc func returnKeyboardCancelled(_ button: UIButton) {
    button.alpha = 1.0
  }

  @objc func lockStatePressHandled(_ button: UIButton) {
    actionHandler.handle(.press, on: .none)
  }

  @objc func lockStateReleaseHandled(_ button: UIButton) {
    let state = keyboardContext.classifySymbolKeyboardLockState
    button.setImage(UIImage(systemName: state ? "lock.open" : "lock"), for: .normal)
    keyboardContext.classifySymbolKeyboardLockState = !state
  }

  @objc func backspacePressHandled(_ button: UIButton) {
    button.backgroundColor = style.pressedBackgroundColor
    actionHandler.handle(.press, on: .backspace)
  }

  @objc func backspaceReleaseHandled(_ button: UIButton) {
    button.backgroundColor = .clear
    actionHandler.handle(.release, on: .backspace)
  }

  @objc func backspaceSwipeUpHandled(_ gesture: UISwipeGestureRecognizer) {
    guard gesture.state == .ended else { return }
    let swipe = KeySwipe(direction: .up, action: .backspace, processByRIME: false, display: false, label: .empty)
    actionHandler.handle(.swipeUp(swipe), on: .backspace)
  }
}
