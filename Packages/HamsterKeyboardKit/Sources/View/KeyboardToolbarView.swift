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

 工具栏左侧菜单 (点左上角图标打开, 仿微信输入法):
 剪贴板 / 常用语 / 收起键盘 / 切换26键·九宫格 / 定制工具栏 / 立即同步 / 设置。
 工具栏按钮可通过"定制工具栏"逐个隐藏/显示 (开关存在共享 UserDefaults)。
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

  /// 常用功能项: 左上角菜单按钮 (点开工具栏菜单)。点按时系统自动高亮图标。
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "r.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    // iOS 14+: 点按直接弹出系统菜单 (自动处理关闭/点外面关闭/高亮状态)
    button.showsMenuAsPrimaryAction = true
    button.menu = makeToolbarMenu()
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

  /// 剪贴板粘贴提示 chip (仿微信输入法): 键盘弹出/同步完成后, 若剪贴板有新内容,
  /// 在工具栏右侧显示一条可点按粘贴的提示, 点后粘贴并消失。只在未输入时显示。
  private lazy var clipboardChipButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = .secondarySystemBackground
    button.layer.cornerRadius = 8
    button.layer.masksToBounds = true
    button.titleLabel?.font = .systemFont(ofSize: 14)
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.setTitleColor(.label, for: .normal)
    button.contentHorizontalAlignment = .left
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
    button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
    button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
    button.tintColor = .secondaryLabel
    button.addTarget(self, action: #selector(clipboardChipTapped), for: .touchUpInside)
    button.isHidden = true
    return button
  }()

  /// chip 当前展示的剪贴板文本 (nil 表示未展示)
  private var clipboardChipText: String?
  /// 已粘贴/忽略过的剪贴板文本: 相同内容不再重复提示, 直到剪贴板换成新内容
  private var clipboardChipDismissedText: String?
  private var clipboardChipConstraints: [NSLayoutConstraint] = []

  /// 当前展示的文本列表面板 (剪贴板 / 常用语), 覆盖在键盘根视图上
  private var textListPanel: KeyboardTextListPanelView?

  /// 当前展示的定制工具栏面板, 覆盖在键盘根视图上
  private var customizePanel: KeyboardToolbarCustomizePanelView?

  /// 工具栏按钮约束 (重建工具栏按钮时先停用旧约束)
  private var toolbarButtonConstraints: [NSLayoutConstraint] = []

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

    // 同步完成 (上传/下载结束) 后刷新粘贴提示: PC 复制的内容下载到本机后也会出现。
    NotificationCenter.default.addObserver(
      self, selector: #selector(syncDidFinish),
      name: ClipboardSyncService.didFinishNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
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

  /// 键盘弹出/回到窗口时刷新粘贴提示 (键盘每次弹出都会触发)。
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      refreshClipboardChip()
    }
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    commonFunctionBar.addSubview(clipboardChipButton)
    rebuildToolbarButtons()
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  override func setupAppearance() {
    // 微信风格: 工具栏/候选栏区域用干净的浅色 (浅色模式白色、深色模式黑色),
    // 与下方浅灰键盘背景区分开。
    backgroundColor = .systemBackground
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

        // 未输入时刷新粘贴提示; 开始输入后工具栏隐藏, 提示随之隐藏。
        if isEmpty {
          self.refreshClipboardChip()
        } else {
          self.hideClipboardChip()
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

  // MARK: - 左上角菜单 (UIMenu, 系统菜单)

  /// 生成工具栏菜单。切换 26 键/九宫格的标题随当前中文主键盘布局而变,
  /// 切换后需调用 rebuildToolbarMenu() 刷新。
  private func makeToolbarMenu() -> UIMenu {
    let clipboard = UIAction(title: "剪贴板", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
      self?.showClipboardHistoryPanel()
    }
    let phrases = UIAction(title: "常用语", image: UIImage(systemName: "text.quote")) { [weak self] _ in
      self?.showCommonPhrasesPanel()
    }
    let dismiss = UIAction(title: "收起键盘", image: UIImage(systemName: "chevron.down.circle")) { [weak self] _ in
      guard let self else { return }
      self.actionHandler.handle(.release, on: .dismissKeyboard)
    }
    let layoutTitle = currentChineseLayoutIsNineGrid ? "切换26键" : "切换九宫格"
    let switchLayout = UIAction(title: layoutTitle, image: UIImage(systemName: "keyboard")) { [weak self] _ in
      self?.toggleChineseKeyboardLayout()
    }
    let customize = UIAction(title: "定制工具栏", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
      self?.showToolbarCustomizePanel()
    }
    let syncNow = UIAction(title: "立即同步剪贴板", image: UIImage(systemName: "arrow.triangle.2.circlepath")) { _ in
      ClipboardSyncService.shared.syncNow()
    }
    let settings = UIAction(title: "设置", image: UIImage(systemName: "gear")) { [weak self] _ in
      guard let self else { return }
      self.actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
    }
    return UIMenu(title: "", children: [clipboard, phrases, dismiss, switchLayout, customize, syncNow, settings])
  }

  /// 刷新菜单 (主要用于切换 26 键/九宫格后更新菜单项标题)。
  private func rebuildToolbarMenu() {
    iconButton.menu = makeToolbarMenu()
  }

  // MARK: - 切换 26 键 / 九宫格

  /// 当前中文主键盘是否为九宫格。当前就在中文主键盘上时以屏幕上的类型为准
  /// (用户可能用地球键临时切换过); 否则用保存过的选择; 从未保存过时看当前类型。
  private var currentChineseLayoutIsNineGrid: Bool {
    let type = keyboardContext.keyboardType
    if type.isChineseNineGrid || type.isChinesePrimaryKeyboard {
      return type.isChineseNineGrid
    }
    if let saved = UserDefaults.hamster.chinesePrimaryKeyboardIsNineGrid {
      return saved
    }
    return type.isChineseNineGrid
  }

  /// 在中文九宫格与 26 键全键盘之间切换, 并持久化选择 (下次打开键盘保持)。
  /// 用现有的 setKeyboardType 机制切换, KeyboardRootView 监听到类型变化后重建键盘,
  /// 不需要重启键盘。
  private func toggleChineseKeyboardLayout() {
    let toNineGrid = !currentChineseLayoutIsNineGrid
    UserDefaults.hamster.chinesePrimaryKeyboardIsNineGrid = toNineGrid
    keyboardContext.setKeyboardType(toNineGrid ? .chineseNineGrid : .chinese(.lowercased))
    rebuildToolbarMenu()
  }

  // MARK: - 工具栏按钮重建 (定制工具栏)

  /// 按配置 + 用户开关重建工具栏按钮。左侧菜单按钮常驻 (配置开启时);
  /// 剪贴板/常用语/收起键盘按共享 UserDefaults 里的开关显示或隐藏。
  func rebuildToolbarButtons() {
    NSLayoutConstraint.deactivate(toolbarButtonConstraints)
    toolbarButtonConstraints.removeAll()
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.removeFromSuperview() }

    var constraints: [NSLayoutConstraint] = []
    // 左侧依次排列的按钮 (图标、剪贴板、常用语)
    var previousButton: UIButton?

    func placeButton(_ button: UIButton, after previous: UIButton?) {
      commonFunctionBar.addSubview(button)
      if let previous {
        constraints.append(button.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 8))
      } else {
        constraints.append(button.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor))
      }
      constraints.append(contentsOf: [
        button.heightAnchor.constraint(equalTo: button.widthAnchor),
        button.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: button.bottomAnchor),
        button.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    if keyboardContext.displayAppIconButton {
      placeButton(iconButton, after: nil)
      previousButton = iconButton
    }
    if UserDefaults.hamster.isToolbarToolVisible("clipboard") {
      placeButton(clipboardButton, after: previousButton)
      previousButton = clipboardButton
    }
    if UserDefaults.hamster.isToolbarToolVisible("phrases") {
      placeButton(phrasesButton, after: previousButton)
      previousButton = phrasesButton
    }

    // 收起键盘按钮固定在最右侧 (配置开启且开关打开时才显示)
    if keyboardContext.displayKeyboardDismissButton, UserDefaults.hamster.isToolbarToolVisible("dismiss") {
      commonFunctionBar.addSubview(dismissKeyboardButton)
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
        dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    toolbarButtonConstraints = constraints
    NSLayoutConstraint.activate(constraints)

    // 按钮重建后, 粘贴提示 chip 的位置也要跟着重算 (它锚在最后一个左侧按钮之后)。
    layoutClipboardChip()
  }

  /// 定制工具栏面板要列出的工具 (收起键盘仅在配置开启时才列出)。
  private func customizeTools() -> [(id: String, title: String, visible: Bool)] {
    var tools: [(id: String, title: String, visible: Bool)] = [
      (id: "clipboard", title: "剪贴板", visible: UserDefaults.hamster.isToolbarToolVisible("clipboard")),
      (id: "phrases", title: "常用语", visible: UserDefaults.hamster.isToolbarToolVisible("phrases")),
    ]
    if keyboardContext.displayKeyboardDismissButton {
      tools.append((id: "dismiss", title: "收起键盘", visible: UserDefaults.hamster.isToolbarToolVisible("dismiss")))
    }
    return tools
  }

  /// 打开定制工具栏面板 (覆盖在键盘根视图上)。
  private func showToolbarCustomizePanel() {
    dismissTextListPanel()
    dismissCustomizePanel()
    guard let container = superview else { return }
    let panel = KeyboardToolbarCustomizePanelView()
    panel.onClose = { [weak self] in self?.dismissCustomizePanel() }
    panel.onToggle = { [weak self] toolID, visible in
      UserDefaults.hamster.setToolbarToolVisible(toolID, visible: visible)
      self?.rebuildToolbarButtons()
    }
    panel.onReset = { [weak self] in
      UserDefaults.hamster.toolbarVisibleTools = Set(UserDefaults.toolbarToolAllIDs)
      self?.rebuildToolbarButtons()
      self?.customizePanel?.reload(with: self?.customizeTools() ?? [])
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: customizeTools())
    customizePanel = panel
  }

  private func dismissCustomizePanel() {
    customizePanel?.removeFromSuperview()
    customizePanel = nil
  }

  // MARK: - 剪贴板粘贴提示 chip

  /// 刷新粘贴提示: 仅在未输入 (工具栏显示) 时, 若剪贴板有未提示过的新内容则显示。
  /// iPhone 上复制的和 PC 同步过来的内容都会出现 (同步完成后会收到通知再刷新一次)。
  func refreshClipboardChip() {
    #if canImport(UIKit)
      guard !commonFunctionBar.isHidden else {
        hideClipboardChip()
        return
      }
      guard let text = UIPasteboard.general.string,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        hideClipboardChip()
        return
      }
      // 已粘贴/忽略过的内容不再重复提示, 直到剪贴板换成新内容
      if text == clipboardChipDismissedText {
        hideClipboardChip()
        return
      }
      // 已在展示同一内容时不重复布局
      if text == clipboardChipText, !clipboardChipButton.isHidden {
        return
      }
      clipboardChipText = text
      // 单行显示, 换行符转空格, 超长由 label 截断
      let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
      clipboardChipButton.setTitle(singleLine, for: .normal)
      clipboardChipButton.isHidden = false
      layoutClipboardChip()
    #endif
  }

  /// 按当前工具栏按钮布局, 把 chip 放在右侧空闲处。
  private func layoutClipboardChip() {
    NSLayoutConstraint.deactivate(clipboardChipConstraints)
    clipboardChipConstraints.removeAll()
    guard !clipboardChipButton.isHidden else { return }

    // chip 左侧锚点: 最后一个可见的左侧按钮之后 (都没有时贴工具栏左沿)
    let lastLeftButton: UIView? = {
      if phrasesButton.superview != nil { return phrasesButton }
      if clipboardButton.superview != nil { return clipboardButton }
      if iconButton.superview != nil { return iconButton }
      return nil
    }()
    var constraints: [NSLayoutConstraint] = [
      clipboardChipButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      clipboardChipButton.heightAnchor.constraint(equalToConstant: 30),
    ]
    if let lastLeftButton {
      constraints.append(clipboardChipButton.leadingAnchor.constraint(greaterThanOrEqualTo: lastLeftButton.trailingAnchor, constant: 8))
    } else {
      constraints.append(clipboardChipButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor, constant: 8))
    }
    if dismissKeyboardButton.superview != nil {
      constraints.append(clipboardChipButton.trailingAnchor.constraint(equalTo: dismissKeyboardButton.leadingAnchor, constant: -8))
    } else {
      constraints.append(clipboardChipButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor, constant: -8))
    }
    clipboardChipConstraints = constraints
    NSLayoutConstraint.activate(constraints)
  }

  private func hideClipboardChip() {
    clipboardChipButton.isHidden = true
    clipboardChipText = nil
    NSLayoutConstraint.deactivate(clipboardChipConstraints)
    clipboardChipConstraints.removeAll()
  }

  /// 点 chip: 把剪贴板内容输入到当前输入框, 之后不再重复提示同一内容。
  @objc private func clipboardChipTapped() {
    guard let text = clipboardChipText, !text.isEmpty else { return }
    clipboardChipDismissedText = text
    hideClipboardChip()
    insertPanelText(text)
    UserDefaults.hamster.recordClipboardHistory(text)
  }

  /// 同步完成 (上传/下载结束) 后刷新粘贴提示: PC 复制的内容下载到本机后会出现。
  @objc private func syncDidFinish() {
    refreshClipboardChip()
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
    dismissCustomizePanel()
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

  /// 剪贴板历史: 打开时先触发一次同步 (上传本机剪贴板、下载服务器最新内容),
  /// 再把当前剪贴板记入历史, 展示最近 20 条。面板顶部显示最近一次同步结果,
  /// 并有"立即同步"按钮; 同步完成后列表会自动刷新。
  /// 无 Full Access 或剪贴板为空时静默, 只显示已有历史。
  private func showClipboardHistoryPanel() {
    // 打开面板即同步一次 (跳过节流), 让 PC 复制的内容尽快出现
    ClipboardSyncService.shared.syncNow()
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
    // 同步状态行 + 立即同步按钮
    textListPanel?.onSyncNow = {
      ClipboardSyncService.shared.syncNow()
    }
    textListPanel?.onSyncFinished = { [weak self] in
      #if canImport(UIKit)
        if let text = UIPasteboard.general.string, !text.isEmpty {
          UserDefaults.hamster.recordClipboardHistory(text)
        }
      #endif
      self?.textListPanel?.reload(with: UserDefaults.hamster.clipboardHistory)
    }
    textListPanel?.showSyncRow(statusText: UserDefaults.hamster.clipboardSyncLastStatusText)
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
