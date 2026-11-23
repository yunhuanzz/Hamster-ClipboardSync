//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// 常用功能项: 仓输入法App
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "r.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(openHamsterAppTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(openHamsterAppTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)

    return button
  }()

  /// 解散键盘 Button
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 剪贴板 Button (最近剪贴板历史)
  lazy var clipboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(clipboardButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(clipboardButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 常用语 Button
  lazy var phrasesButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "text.quote"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(phrasesButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(phrasesButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 当前展示的文本列表面板 (剪贴板 / 常用语), 覆盖在键盘根视图上
  private var textListPanel: KeyboardTextListPanelView?

  // TODO: 常用功能栏
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    return view
  }()

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    // KeyboardToolbarView 为 candidateBarStyle 样式根节点, 这里生成一次，减少计算次数
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupSubview()

    combine()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    if keyboardContext.displayAppIconButton {
      commonFunctionBar.addSubview(iconButton)
    }
    commonFunctionBar.addSubview(clipboardButton)
    commonFunctionBar.addSubview(phrasesButton)
    if keyboardContext.displayKeyboardDismissButton {
      commonFunctionBar.addSubview(dismissKeyboardButton)
    }
  }

  override func activateViewConstraints() {
    var constraints: [NSLayoutConstraint] = [
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ]

    if keyboardContext.displayAppIconButton {
      constraints.append(contentsOf: [
        iconButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
        iconButton.heightAnchor.constraint(equalTo: iconButton.widthAnchor),
        iconButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: iconButton.bottomAnchor),
        iconButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    if keyboardContext.displayKeyboardDismissButton {
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
        dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    // 剪贴板按钮: 在 App 图标按钮右侧 (若无图标按钮则在最左侧)
    if keyboardContext.displayAppIconButton {
      constraints.append(clipboardButton.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 8))
    } else {
      constraints.append(clipboardButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor, constant: 8))
    }
    constraints.append(contentsOf: [
      clipboardButton.heightAnchor.constraint(equalTo: clipboardButton.widthAnchor),
      clipboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: clipboardButton.bottomAnchor),
      clipboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),

      // 常用语按钮: 在剪贴板按钮右侧
      phrasesButton.leadingAnchor.constraint(equalTo: clipboardButton.trailingAnchor, constant: 8),
      phrasesButton.heightAnchor.constraint(equalTo: phrasesButton.widthAnchor),
      phrasesButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: phrasesButton.bottomAnchor),
      phrasesButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
    ])

    NSLayoutConstraint.activate(constraints)
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    if keyboardContext.displayAppIconButton {
      iconButton.tintColor = style.toolbarButtonFrontColor
    }
    if keyboardContext.displayKeyboardDismissButton {
      dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    }
    clipboardButton.tintColor = style.toolbarButtonFrontColor
    phrasesButton.tintColor = style.toolbarButtonFrontColor
  }

  func combine() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        let isEmpty = $0.isEmpty
        self.commonFunctionBar.isHidden = !isEmpty
        self.candidateBarView.isHidden = isEmpty

        if self.candidateBarView.superview == nil {
          candidateBarView.setStyle(self.style)
          addSubview(candidateBarView)
          candidateBarView.fillSuperview()
        }

        // 检测是否启用内嵌编码
        guard !keyboardContext.enableEmbeddedInputMode else { return }
        if self.keyboardContext.keyboardType.isChineseNineGrid {
          // Debug
          // self.phoneticArea.text = inputKeys + " | " + self.rimeContext.t9UserInputKey
          candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
        } else {
          candidateBarView.phoneticLabel.text = $0
        }
      }
      .store(in: &subscriptions)
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func openHamsterAppTouchDownAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func openHamsterAppTouchUpAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
    actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
  }

  @objc func clipboardButtonTouchDownAction() {
    clipboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func clipboardButtonTouchUpAction() {
    clipboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    showClipboardHistoryPanel()
  }

  @objc func phrasesButtonTouchDownAction() {
    phrasesButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func phrasesButtonTouchUpAction() {
    phrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
    showCommonPhrasesPanel()
  }

  @objc func touchCancel() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    iconButton.backgroundColor = style.toolbarButtonBackgroundColor
    clipboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    phrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
  }

  // MARK: - 文本列表面板 (剪贴板 / 常用语)

  /// 把面板文本输入到当前输入框。优先走 KeyboardController.insertText,
  /// 拿不到 controller 时直接写 documentProxy。失败静默。
  private func insertPanelText(_ text: String) {
    guard !text.isEmpty else { return }
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController {
      controller.insertText(text)
      return
    }
    keyboardContext.textDocumentProxy.insertText(text)
  }

  /// 在键盘根视图上覆盖展示一个文本列表面板
  private func showTextListPanel(title: String, items: [String], onSelect: @escaping (String) -> Void, onDelete: @escaping (Int) -> Void) {
    dismissTextListPanel()
    guard let container = superview else { return }
    let panel = KeyboardTextListPanelView(title: title)
    panel.onSelect = { [weak self] text in
      onSelect(text)
      self?.dismissTextListPanel()
    }
    panel.onDelete = onDelete
    panel.onClose = { [weak self] in self?.dismissTextListPanel() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: items)
    textListPanel = panel
  }

  private func dismissTextListPanel() {
    textListPanel?.removeFromSuperview()
    textListPanel = nil
  }

  /// 剪贴板历史: 打开时先读当前剪贴板记入历史, 再展示最近 20 条。
  /// 无 Full Access 或剪贴板为空时静默, 只显示已有历史。
  private func showClipboardHistoryPanel() {
    #if canImport(UIKit)
      if let text = UIPasteboard.general.string, !text.isEmpty {
        UserDefaults.hamster.recordClipboardHistory(text)
      }
    #endif
    showTextListPanel(title: "剪贴板", items: UserDefaults.hamster.clipboardHistory, onSelect: { [weak self] text in
      self?.insertPanelText(text)
    }, onDelete: { [weak self] index in
      var history = UserDefaults.hamster.clipboardHistory
      guard history.indices.contains(index) else { return }
      history.remove(at: index)
      UserDefaults.hamster.clipboardHistory = history
      self?.textListPanel?.reload(with: history)
    })
  }

  /// 常用语: 展示内置/自定义列表。长按删除单条。
  private func showCommonPhrasesPanel() {
    showTextListPanel(title: "常用语", items: UserDefaults.hamster.commonPhrases, onSelect: { [weak self] text in
      self?.insertPanelText(text)
    }, onDelete: { [weak self] index in
      var phrases = UserDefaults.hamster.commonPhrases
      guard phrases.indices.contains(index) else { return }
      phrases.remove(at: index)
      UserDefaults.hamster.commonPhrases = phrases
      self?.textListPanel?.reload(with: phrases)
    })
  }
}
