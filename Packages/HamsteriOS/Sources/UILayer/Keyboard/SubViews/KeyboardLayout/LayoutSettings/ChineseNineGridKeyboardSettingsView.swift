//
//  ChineseNineGridKeyboardSettingsView.swift
//
//
//  Created by morse on 2023/9/14.
//

import HamsterUIKit
import UIKit

/// 中文九宫格键盘布局设置
class ChineseNineGridKeyboardSettingsView: NibLessView {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel

  /// 词库标题
  private lazy var dictionaryTitleLabel: UILabel = {
    let label = UILabel()
    label.text = "词库"
    label.font = UIFont.preferredFont(forTextStyle: .body)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 词库选择按钮 (下拉菜单, 与设置表里的 PullDownMenuCell 同款:
  /// 右侧显示当前值 + 下箭头, 点开即菜单)。
  private lazy var dictionaryButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.contentHorizontalAlignment = .trailing
    button.translatesAutoresizingMaskIntoConstraints = false
    button.configuration = UIButton.Configuration.plain()
    button.configuration?.image = UIImage(systemName: "chevron.down")
    button.configuration?.imagePlacement = .trailing
    button.showsMenuAsPrimaryAction = true
    return button
  }()

  /// 词库卡片 (标题 + 选择按钮一行)。
  private lazy var dictionaryCardView: UIView = {
    let card = UIView()
    card.backgroundColor = .systemBackground
    card.layer.cornerRadius = 10
    card.translatesAutoresizingMaskIntoConstraints = false

    let stack = UIStackView(arrangedSubviews: [dictionaryTitleLabel, dictionaryButton])
    stack.axis = .horizontal
    stack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalToSystemSpacingBelow: card.topAnchor, multiplier: 1),
      card.bottomAnchor.constraint(equalToSystemSpacingBelow: stack.bottomAnchor, multiplier: 1),
      stack.leadingAnchor.constraint(equalToSystemSpacingAfter: card.leadingAnchor, multiplier: 2),
      card.trailingAnchor.constraint(equalToSystemSpacingAfter: stack.trailingAnchor, multiplier: 2),
    ])
    return card
  }()

  /// 词库说明: 九宫格只列拼音词库; 改完要点 RIME 设置里的「重新部署」。
  private lazy var dictionaryFootnoteLabel: UILabel = {
    let label = UILabel()
    label.text = "九宫格只能选拼音词库 (数字要先拼出拼音音节才能出候选)。改完要点 RIME 设置里的「重新部署」才生效。"
    label.font = UIFont.preferredFont(forTextStyle: .caption2)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 词库区 (卡片 + 说明), 在符号编辑器上面。
  private lazy var dictionarySectionView: UIView = {
    let section = UIView()
    section.translatesAutoresizingMaskIntoConstraints = false
    section.addSubview(dictionaryCardView)
    section.addSubview(dictionaryFootnoteLabel)
    NSLayoutConstraint.activate([
      dictionaryCardView.topAnchor.constraint(equalTo: section.topAnchor),
      dictionaryCardView.leadingAnchor.constraint(equalTo: section.leadingAnchor),
      dictionaryCardView.trailingAnchor.constraint(equalTo: section.trailingAnchor),
      dictionaryFootnoteLabel.topAnchor.constraint(equalToSystemSpacingBelow: dictionaryCardView.bottomAnchor, multiplier: 1),
      dictionaryFootnoteLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: section.leadingAnchor, multiplier: 2),
      section.trailingAnchor.constraint(equalToSystemSpacingAfter: dictionaryFootnoteLabel.trailingAnchor, multiplier: 2),
      section.bottomAnchor.constraint(equalTo: dictionaryFootnoteLabel.bottomAnchor),
    ])
    return section
  }()

  lazy var symbolsView: UIView = SymbolEditorView(
    headerTitle: "左侧划动符号栏",
    getSymbols: { [unowned self] in keyboardSettingsViewModel.symbolsOfChineseNineGridKeyboard },
    symbolsDidSet: { [unowned self] in
      keyboardSettingsViewModel.symbolsOfChineseNineGridKeyboard = $0
    },
    symbolTableIsEditingPublished: keyboardSettingsViewModel.$symbolsOfChineseNineGridIsEditing.eraseToAnyPublisher(),
    reloadDataPublished: keyboardSettingsViewModel.resetSignPublished,
    needRestButton: true,
    restButtonAction: { [unowned self] in
      guard let defaultConfiguration = HamsterAppDependencyContainer.shared.defaultConfiguration else {
        throw "未找到系统默认配置"
      }
      guard let defaultPairsOfSymbols = defaultConfiguration.keyboard?.symbolsOfChineseNineGridKeyboard else {
        throw "未找到默认值"
      }
      keyboardSettingsViewModel.symbolsOfChineseNineGridKeyboard = defaultPairsOfSymbols
      keyboardSettingsViewModel.resetSignSubject.send(true)
    }
  )

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel

    super.init(frame: .zero)

    backgroundColor = .secondarySystemBackground
    addSubview(dictionarySectionView)
    addSubview(symbolsView)
    symbolsView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      dictionarySectionView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      dictionarySectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      trailingAnchor.constraint(equalTo: dictionarySectionView.trailingAnchor, constant: 16),

      symbolsView.topAnchor.constraint(equalTo: dictionarySectionView.bottomAnchor, constant: 8),
      symbolsView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
      symbolsView.leadingAnchor.constraint(equalTo: leadingAnchor),
      symbolsView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    refreshDictionaryRow()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if let _ = window {
      refreshDictionaryRow()
    }
  }

  /// 刷新词库行: 按钮显示当前绑定的词库名, 菜单按当前扫描结果重建
  /// (以后导入的自定义拼音词库也会出现在这里)。
  private func refreshDictionaryRow() {
    let currentId = keyboardSettingsViewModel.nineGridDictionaryId
    dictionaryButton.setTitle(keyboardSettingsViewModel.nineGridDictionaryDisplayName, for: .normal)
    dictionaryButton.menu = UIMenu(
      title: "",
      children: keyboardSettingsViewModel.nineGridDictionaryOptions.map { option in
        UIAction(title: option.displayName, state: option.id == currentId ? .on : .off) { [unowned self] _ in
          keyboardSettingsViewModel.setNineGridDictionary(option.id)
          refreshDictionaryRow()
        }
      })
  }
}
