//
//  EmojisKeyboard.swift
//
//  表情面板 (仿微信输入法 emoji 界面):
//  顶部: 分类标题 + “✨定制表情” + “···”
//  中间: emoji 网格 (每行 9 个, 可滚动)
//  底部: 分类切换栏 — 绿色返回箭头 (回键盘) | 分类图标 | ⌫ 删除
//  点按插入 emoji 文本; ⌫ 删一个字符; 绿色箭头回到键盘。
//  先做“表情符号与人物”+ 最近使用, 其他分类图标先摆出来,
//  点按后若暂无内容显示提示 (绝不点按无反应)。
//  底色取 appearance.backgroundStyle.backgroundColor (与键盘本体同一块
//  系统底色, 不写死色值, 深色模式同样一致)。
//  九宫格右列第三行的 😊 键经 .keyboardType(.emojis) 切到本面板;
//  .emojis 不是主键盘 (不进 primaryKeyboardStack), 绿色箭头用
//  returnKeyboardType() 回到九宫格。

import HamsterKit
import HamsterUIKit
import UIKit

/// 表情面板的分类: 图标与数据一一对应 EmojiCategory。
/// frequent 每次选中时重新读 (最近使用会随点按更新)。
private enum EmojiPanelCategory: CaseIterable {
  case frequent
  case smileys
  case animals
  case foods
  case activities
  case symbols
  case flags

  /// 底部栏图标 (symbols 分类没有合适的单个 emoji, 用文字 “T&%”)。
  var icon: String {
    switch self {
    case .frequent: return "🕐"
    case .smileys: return "😊"
    case .animals: return "🌸"
    case .foods: return "🎂"
    case .activities: return "⚽"
    case .symbols: return "T&%"
    case .flags: return "🏳"
    }
  }

  /// 顶部标题。
  var title: String {
    switch self {
    case .frequent: return "最近使用"
    case .smileys: return "表情符号与人物"
    case .animals: return "动物与自然"
    case .foods: return "食物与饮料"
    case .activities: return "活动"
    case .symbols: return "符号"
    case .flags: return "旗帜"
    }
  }

  var emojis: [Emoji] {
    switch self {
    case .frequent: return EmojiCategory.frequent.emojis
    case .smileys: return EmojiCategory.smileys.emojis
    case .animals: return EmojiCategory.animals.emojis
    case .foods: return EmojiCategory.foods.emojis
    case .activities: return EmojiCategory.activities.emojis
    case .symbols: return EmojiCategory.symbols.emojis
    case .flags: return EmojiCategory.flags.emojis
    }
  }

  /// 空分类的提示 (点按后显示, 不让分类栏看起来没反应)。
  var emptyHint: String {
    switch self {
    case .frequent: return "还没有用过的表情\n点过的表情会出现在这里"
    default: return "该分类暂无表情"
    }
  }
}

class EmojisKeyboard: NibLessView {
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private let keyboardContext: KeyboardContext
  private let rimeContext: RimeContext

  private var selectedCategory: EmojiPanelCategory = .smileys
  private var currentEmojis: [Emoji] = EmojiCategory.smileys.emojis

  /// “定制表情 / ···” 的短暂提示任务 (1.5 秒后自动消失, 恢复空分类提示)。
  private var toastWorkItem: DispatchWorkItem?

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = EmojiPanelCategory.smileys.title
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var customEmojiButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("✨定制表情", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(customEmojiTapped), for: .touchUpInside)
    return button
  }()

  private lazy var moreButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("···", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    return button
  }()

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 0
    layout.minimumLineSpacing = 4
    layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.showsVerticalScrollIndicator = false
    view.translatesAutoresizingMaskIntoConstraints = false
    view.dataSource = self
    view.delegate = self
    view.register(EmojiGridCell.self, forCellWithReuseIdentifier: EmojiGridCell.reuseIdentifier)
    return view
  }()

  /// 空分类 / 短暂提示: 居中显示在网格区。
  private lazy var hintLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 14)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 绿色返回箭头: 回到键盘 (九宫格)。
  private lazy var backButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemGreen
    button.layer.cornerRadius = 8
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    return button
  }()

  /// ⌫ 删除: 删一个字符。
  private lazy var deleteButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "delete.left"), for: .normal)
    button.tintColor = .label
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    return button
  }()

  /// 分类切换栏: 返回箭头 + 分类图标 + 删除, 间距均分。
  private lazy var categoryBar: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.distribution = .equalSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 分类按钮 (与 EmojiPanelCategory.allCases 一一对应)。
  private var categoryButtons: [UIButton] = []

  init(actionHandler: KeyboardActionHandler, appearance: KeyboardAppearance, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(titleLabel)
    addSubview(customEmojiButton)
    addSubview(moreButton)
    addSubview(collectionView)
    addSubview(hintLabel)
    addSubview(categoryBar)

    categoryBar.addArrangedSubview(backButton)
    for category in EmojiPanelCategory.allCases {
      let button = UIButton(type: .system)
      button.setTitle(category.icon, for: .normal)
      // “T&%” 是文字图标, 字号小一点; 其余是 emoji, 字号大一点。
      button.titleLabel?.font = category == .symbols
        ? .systemFont(ofSize: 12, weight: .bold)
        : .systemFont(ofSize: 20)
      button.setTitleColor(.label, for: .normal)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = EmojiPanelCategory.allCases.firstIndex(of: category) ?? 0
      button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
      categoryButtons.append(button)
      categoryBar.addArrangedSubview(button)
    }
    categoryBar.addArrangedSubview(deleteButton)
    updateCategorySelection()
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      moreButton.widthAnchor.constraint(equalToConstant: 28),

      customEmojiButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      customEmojiButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),

      collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: categoryBar.topAnchor),

      hintLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
      hintLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
      hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: collectionView.leadingAnchor, constant: 32),
      hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: collectionView.trailingAnchor, constant: -32),

      categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      categoryBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      categoryBar.heightAnchor.constraint(equalToConstant: 44),

      backButton.widthAnchor.constraint(equalToConstant: 36),
      backButton.heightAnchor.constraint(equalToConstant: 36),
      deleteButton.widthAnchor.constraint(equalToConstant: 36),
      deleteButton.heightAnchor.constraint(equalToConstant: 36),
    ])
    // 分类按钮 30pt 宽: 7 个分类 + 返回 + 删除共 278pt,
    // 窄屏 (320pt, 栏宽 296pt) 也放得下。
    for button in categoryButtons {
      button.widthAnchor.constraint(equalToConstant: 30).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
  }

  override func setupAppearance() {
    // 与键盘本体同一块系统底色, 不写死色值 (深色模式同样一致)。
    backgroundColor = appearance.backgroundStyle.backgroundColor
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      setupAppearance()
    }
  }

  // MARK: - 分类切换

  private func updateCategorySelection() {
    for (index, button) in categoryButtons.enumerated() {
      let selected = EmojiPanelCategory.allCases[index] == selectedCategory
      button.backgroundColor = selected ? .systemFill : .clear
      button.layer.cornerRadius = 8
    }
  }

  private func selectCategory(_ category: EmojiPanelCategory) {
    toastWorkItem?.cancel()
    toastWorkItem = nil
    selectedCategory = category
    titleLabel.text = category.title
    // 最近使用每次选中时重新读 (点过的 emoji 会立刻出现)。
    currentEmojis = category.emojis
    updateCategorySelection()
    reloadGrid()
  }

  private func reloadGrid() {
    collectionView.reloadData()
    hintLabel.isHidden = !currentEmojis.isEmpty
    if currentEmojis.isEmpty {
      hintLabel.text = selectedCategory.emptyHint
    }
  }

  /// 短暂提示 (定制表情 / ···): 显示 1.5 秒后消失, 网格非空时藏起,
  /// 空分类时恢复该分类的空提示。
  private func showToast(_ text: String) {
    toastWorkItem?.cancel()
    hintLabel.text = text
    hintLabel.isHidden = false
    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if self.currentEmojis.isEmpty {
        self.hintLabel.text = self.selectedCategory.emptyHint
      } else {
        self.hintLabel.isHidden = true
      }
    }
    toastWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
  }

  // MARK: - 动作

  @objc private func categoryTapped(_ sender: UIButton) {
    let category = EmojiPanelCategory.allCases[sender.tag]
    selectCategory(category)
  }

  @objc private func backTapped() {
    // .emojis 不进主键盘栈, returnKeyboardType() 弹回切换前的九宫格。
    keyboardContext.setKeyboardType(keyboardContext.returnKeyboardType())
  }

  @objc private func deleteTapped() {
    // 删一个字符 (退格键的按压动作)。
    actionHandler.handle(.press, on: .backspace)
  }

  @objc private func customEmojiTapped() {
    showToast("定制表情暂未开放")
  }

  @objc private func moreTapped() {
    showToast("更多表情设置即将推出")
  }

  /// 点按插入 emoji: 先把未上屏的拼音候选顶上去 (与符号键 insertSymbol
  /// 同款处理), 再经 actionHandler 走标准释放动作插 emoji 文本;
  /// tryRegisterEmoji 会自动把该 emoji 登记到最近使用。
  private func insertEmoji(_ emoji: Emoji) {
    if !rimeContext.userInputKey.isEmpty {
      if let first = rimeContext.suggestions.first {
        keyboardContext.textDocumentProxy.insertText(first.text)
      }
      rimeContext.reset()
    }
    actionHandler.handle(.release, on: .emoji(emoji))
    // 刚插的 emoji 进了最近使用: 若当前在“最近使用”分类, 立刻刷新网格。
    if selectedCategory == .frequent {
      currentEmojis = selectedCategory.emojis
      reloadGrid()
    }
  }
}

// MARK: - UICollectionViewDataSource / Delegate

extension EmojisKeyboard: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    currentEmojis.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiGridCell.reuseIdentifier, for: indexPath) as! EmojiGridCell
    cell.configure(with: currentEmojis[indexPath.item])
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    // 每行 9 个 (仿微信), 行高 44。
    // 首次布局时 bounds 可能还是 0, 下限 28 避免负尺寸。
    let width = max(28, floor((collectionView.bounds.width - 16) / 9))
    return CGSize(width: width, height: 44)
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: false)
    insertEmoji(currentEmojis[indexPath.item])
  }
}

/// 表情网格的格子: 一个居中的 emoji (28pt)。
private class EmojiGridCell: UICollectionViewCell {
  static let reuseIdentifier = "EmojiGridCell"

  private let emojiLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 28)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(emojiLabel)
    NSLayoutConstraint.activate([
      emojiLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      emojiLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with emoji: Emoji) {
    emojiLabel.text = emoji.char
  }
}
