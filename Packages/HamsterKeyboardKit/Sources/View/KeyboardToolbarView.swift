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
 4 列宫格面板, 含剪贴板 / 常用语 / 收起键盘 / 切换26键·九宫格 /
 定制工具栏 / 立即同步 / 设置 / 常用语管理。
 工具栏按钮可通过"定制工具栏"逐个隐藏/显示并拖拽排序
 (顺序存在共享 UserDefaults, 收起键盘默认在最右)。
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

  /// 常用功能项: 左上角菜单按钮 (点开宫格菜单)。点按时系统自动高亮图标。
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "square.grid.2x2"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(menuButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(menuButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 解散键盘 Button (plain 下箭头 ⌄, 与工具栏其他按钮同一套 18pt SF Symbols)。
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
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
    button.setImage(UIImage(systemName: "list.clipboard"), for: .normal)
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
    button.setImage(UIImage(systemName: "quote.bubble"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(phrasesButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(phrasesButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 微信式粘贴提示行: 剪贴板文字在左 (点按粘贴), 右侧 ⌄ 展开 + X 关闭并排。
  /// 展示时工具栏其他按钮暂时隐藏。只在未输入时显示。
  /// 行本身透明 (不要药丸底): 直接落在工具栏区域已有的键盘底色上,
  /// 文字 + ⌄ + ✕ 直接贴在灰底上 (仿微信); 白色圆角条在深浅模式都难看。
  private lazy var pasteRowView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  /// 粘贴提示行右侧: 向下箭头 ⌄ (微信式, 点按展开复制内容、分段粘贴)。
  /// 注意: 微信里的这个 ⌄ 是展开复制内容、智能分段、选一段粘贴, 不是隐藏键盘
  /// (第 3 轮把它做成隐藏键盘是理解错了); 隐藏键盘只作为工具栏工具。
  private lazy var pasteRowExpandButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 16, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .secondaryLabel
    button.addTarget(self, action: #selector(pasteRowExpandTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行中间: 剪贴板文字 (单行截断, 点按粘贴)。
  private lazy var pasteRowTextButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.titleLabel?.font = .systemFont(ofSize: 14)
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.setTitleColor(.label, for: .normal)
    button.contentHorizontalAlignment = .left
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
    button.addTarget(self, action: #selector(pasteRowTextTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行右侧: X (关闭提示, 相同内容不再重复提示)。
  private lazy var pasteRowCloseButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 14), scale: .default), forImageIn: .normal)
    button.tintColor = .secondaryLabel
    button.addTarget(self, action: #selector(pasteRowCloseTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行当前展示的剪贴板文本 (nil 表示未展示)
  private var clipboardChipText: String?
  /// 当前剪贴板 changeCount (整数, 读它不弹"粘贴自xxx"横幅)。
  /// 忽略记录以它为准: 剪贴板一换内容它就移动, 忽略即失效。
  private var currentPasteboardChangeCount: Int {
    #if canImport(UIKit)
      return UIPasteboard.general.changeCount
    #else
      return -1
    #endif
  }
  /// 上次读取剪贴板内容时的 changeCount。只在 changeCount 变化时才重读剪贴板
  /// (读剪贴板会弹"粘贴自xxx"横幅), 其余时候只用缓存展示, 绝不重复读。
  /// -1 表示从未读过。
  private var lastChipChangeCount: Int = -1
  /// 上次读到的剪贴板文本缓存 (打字/输入变化时只用缓存展示, 不读剪贴板)。
  private var lastReadPasteboardText: String?
  /// 粘贴提示行是否正在展示 (展示时工具栏其他按钮暂时隐藏)。
  private var isPasteRowVisible = false

  /// 当前展示的文本列表面板 (剪贴板 / 常用语), 覆盖在键盘根视图上
  private var textListPanel: KeyboardTextListPanelView?

  /// 当前展示的定制工具栏面板, 覆盖在键盘根视图上
  private var customizePanel: KeyboardToolbarCustomizePanelView?

  /// 当前展示的功能菜单宫格面板, 覆盖在键盘根视图上
  private var menuPanel: KeyboardToolbarMenuPanelView?

  /// 当前展示的常用语管理面板, 覆盖在键盘根视图上
  private var phrasesEditorPanel: KeyboardCommonPhrasesEditorPanelView?

  /// 当前展示的粘贴内容分段展开面板, 覆盖在键盘根视图上
  private var segmentsPanel: KeyboardPasteSegmentsPanelView?

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

  /// 键盘弹出/回到窗口时刷新粘贴提示并启动定期同步;
  /// 键盘隐藏时停止定期同步并关掉覆盖面板。
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      refreshClipboardChip()
      startSyncTimer()
    } else {
      stopSyncTimer()
      // 隐藏键盘等同于忽略当前正在展示的粘贴提示: 持久化记录,
      // 下次打开不再重推同一内容, 除非剪贴板换了新内容。
      if let text = clipboardChipText, !text.isEmpty {
        UserDefaults.hamster.markClipboardChipDismissed(
          hash: ClipboardSyncService.sha256(text),
          changeCount: currentPasteboardChangeCount)
      }
      hideClipboardChip()
      dismissAllPanels()
    }
  }

  /// 键盘打开期间的定期同步定时器 (每 1 秒): 键盘开着时复制的内容
  /// (本机或 PC) 不用等关闭重开就能同步, 连续复制的间隔也不再受节流拖累。
  /// 失败静默, 不阻塞打字; 键盘隐藏时停止。
  private var syncTimer: Timer?

  private func startSyncTimer() {
    stopSyncTimer()
    guard UserDefaults.hamster.clipboardSyncEnabled else { return }
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.syncTimerTick()
    }
    // .common: 打字/滑动时 (UITracking) 也照常触发
    RunLoop.main.add(timer, forMode: .common)
    syncTimer = timer
  }

  private func stopSyncTimer() {
    syncTimer?.invalidate()
    syncTimer = nil
  }

  /// 定时器每拍: 同步一次。服务内部用 changeCount 判断本机剪贴板是否真变了,
  /// 没变不读剪贴板、不弹横幅; 每拍都拉取服务器, PC 复制的内容 1 秒内到达,
  /// 到达后发通知刷新粘贴提示与状态行。
  private func syncTimerTick() {
    guard window != nil else {
      stopSyncTimer()
      return
    }
    guard UserDefaults.hamster.clipboardSyncEnabled else {
      stopSyncTimer()
      return
    }
    ClipboardSyncService.shared.syncNow()
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    setupPasteRow()
    rebuildToolbarButtons()
  }

  /// 粘贴提示行: 加入工具栏并定好内部布局 (默认隐藏)。
  /// 微信式布局: 文字在左占满剩余宽度, ⌄ 展开与 X 关闭并排在右。
  /// 粘贴行里不再放隐藏键盘——隐藏键盘只作为工具栏工具。
  private func setupPasteRow() {
    commonFunctionBar.addSubview(pasteRowView)
    pasteRowView.addSubview(pasteRowExpandButton)
    pasteRowView.addSubview(pasteRowTextButton)
    pasteRowView.addSubview(pasteRowCloseButton)
    NSLayoutConstraint.activate([
      pasteRowView.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
      pasteRowView.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
      pasteRowView.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      pasteRowView.heightAnchor.constraint(equalToConstant: 30),

      pasteRowTextButton.leadingAnchor.constraint(equalTo: pasteRowView.leadingAnchor),
      pasteRowTextButton.trailingAnchor.constraint(equalTo: pasteRowExpandButton.leadingAnchor),
      pasteRowTextButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowTextButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),

      pasteRowExpandButton.trailingAnchor.constraint(equalTo: pasteRowCloseButton.leadingAnchor),
      pasteRowExpandButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowExpandButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),
      pasteRowExpandButton.widthAnchor.constraint(equalToConstant: 30),

      pasteRowCloseButton.trailingAnchor.constraint(equalTo: pasteRowView.trailingAnchor),
      pasteRowCloseButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowCloseButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),
      pasteRowCloseButton.widthAnchor.constraint(equalToConstant: 30),
    ])
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
    // 与键盘本体同一块背景: KeyboardRootView 用的就是
    // appearance.backgroundStyle.backgroundColor (无配色方案时接近透明,
    // 透出系统键盘底色; 有配色方案时用该方案的 backColor)。
    // 之前这里用 .systemBackground, 深色模式是纯黑, 与下方深灰键盘底色
    // 割裂成一块黑斑; 改成同一颜色后浅色/深色模式都与按键区一致。
    // 深浅切换时 layoutSubviews 会重新跑这里。
    backgroundColor = appearance.backgroundStyle.backgroundColor
    self.style = appearance.candidateBarStyle
    if keyboardContext.displayAppIconButton {
      iconButton.tintColor = style.toolbarButtonFrontColor
    }
    // 收起键盘是一级工具, 永远在工具列表里 (不再受 YAML 的
    // displayKeyboardDismissButton 开关影响——那个开关在老用户已保存的
    // 配置里是关的, 之前导致收起键盘在工具栏上根本不出现)。
    dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    clipboardButton.tintColor = style.toolbarButtonFrontColor
    phrasesButton.tintColor = style.toolbarButtonFrontColor
  }

  /// 覆盖式面板用的不透明键盘底色: 有配色方案时用方案的 backColor
  /// (appearance.backgroundStyle.backgroundColor 已是不透明);
  /// 无配色方案时该颜色接近透明 (alpha 0.001), 改用系统键盘标准底色
  /// (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 第 3 轮直接把 backgroundStyle 颜色给面板是错的——面板是全屏覆盖层,
  /// 透明底会让按键从格子/列表后面透出来; 工具栏那条细条透一下没事,
  /// 全屏面板必须不透明。
  private var opaquePanelBackgroundColor: UIColor {
    if let bg = appearance.backgroundStyle.backgroundColor, bg.cgColor.alpha > 0.5 { return bg }
    return HamsterUIColor.shared.standardKeyboardBackground
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

        // 未输入时用缓存展示粘贴提示 (绝不读剪贴板, 打字不再弹"粘贴自xxx"横幅);
        // 开始输入后工具栏隐藏, 提示随之隐藏。
        if isEmpty {
          self.showClipboardChipFromCache()
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

  @objc func menuButtonTouchDownAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func menuButtonTouchUpAction() {
    iconButton.backgroundColor = style.toolbarButtonBackgroundColor
    showMenuPanel()
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

  // MARK: - 左上角菜单 (宫格面板, 仿微信输入法)

  /// 菜单宫格: 与旧版 UIMenu 同样的功能项, 另加"常用语管理"。
  /// 切换 26 键/九宫格的标题随当前中文主键盘布局而变, 面板每次打开时现算。
  private func menuTiles() -> [(id: String, title: String, systemImage: String)] {
    let layoutTitle = currentChineseLayoutIsNineGrid ? "切换26键" : "切换九宫格"
    return [
      (id: "clipboard", title: "剪贴板", systemImage: "list.clipboard"),
      (id: "phrases", title: "常用语", systemImage: "quote.bubble"),
      (id: "dismiss", title: "收起键盘", systemImage: "chevron.down"),
      (id: "switchLayout", title: layoutTitle, systemImage: "keyboard"),
      (id: "customize", title: "定制工具栏", systemImage: "slider.horizontal.3"),
      (id: "syncNow", title: "立即同步剪贴板", systemImage: "arrow.triangle.2.circlepath"),
      (id: "settings", title: "设置", systemImage: "gear"),
      (id: "managePhrases", title: "常用语管理", systemImage: "square.and.pencil"),
    ]
  }

  /// 打开功能菜单宫格面板 (覆盖在键盘根视图上)。
  /// 只显示定制里开关打开的格子 (menuVisibleTiles)。
  private func showMenuPanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardToolbarMenuPanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onSelect = { [weak self] tileID in
      self?.dismissMenuPanel()
      self?.handleMenuSelection(tileID)
    }
    panel.onClose = { [weak self] in self?.dismissMenuPanel() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: menuTiles().filter { UserDefaults.hamster.isMenuTileVisible($0.id) })
    menuPanel = panel
  }

  private func dismissMenuPanel() {
    menuPanel?.removeFromSuperview()
    menuPanel = nil
  }

  /// 点宫格后的动作 (与旧版 UIMenu 的各项一一对应)。
  private func handleMenuSelection(_ tileID: String) {
    switch tileID {
    case "clipboard":
      showClipboardHistoryPanel()
    case "phrases":
      showCommonPhrasesPanel()
    case "dismiss":
      actionHandler.handle(.release, on: .dismissKeyboard)
    case "switchLayout":
      toggleChineseKeyboardLayout()
    case "customize":
      showToolbarCustomizePanel()
    case "syncNow":
      ClipboardSyncService.shared.syncNow()
    case "settings":
      actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
    case "managePhrases":
      showCommonPhrasesEditorPanel()
    default:
      break
    }
  }

  /// 关掉所有覆盖面板 (打开任一面板前先调, 同一时间只展示一个)。
  private func dismissAllPanels() {
    dismissTextListPanel()
    dismissCustomizePanel()
    dismissMenuPanel()
    dismissPhrasesEditorPanel()
    dismissSegmentsPanel()
  }

  // MARK: - 常用语管理面板 (键盘内编辑, 不离开键盘)

  /// 打开常用语管理面板 (覆盖在键盘根视图上): 增删改常用语,
  /// 读写与主 App 设置页同一个共享 UserDefaults commonPhrases。
  private func showCommonPhrasesEditorPanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardCommonPhrasesEditorPanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onClose = { [weak self] in self?.dismissPhrasesEditorPanel() }
    panel.onOpenApp = { [weak self] in
      guard let self else { return }
      self.dismissPhrasesEditorPanel()
      self.actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload()
    phrasesEditorPanel = panel
  }

  private func dismissPhrasesEditorPanel() {
    phrasesEditorPanel?.removeFromSuperview()
    phrasesEditorPanel = nil
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
  /// 不需要重启键盘。菜单宫格每次打开时现算标题, 不需要刷新。
  private func toggleChineseKeyboardLayout() {
    let toNineGrid = !currentChineseLayoutIsNineGrid
    UserDefaults.hamster.chinesePrimaryKeyboardIsNineGrid = toNineGrid
    keyboardContext.setKeyboardType(toNineGrid ? .chineseNineGrid : .chinese(.lowercased))
  }

  // MARK: - 工具栏按钮重建 (定制工具栏)

  /// 按配置 + 用户开关/顺序重建工具栏按钮。左侧菜单按钮常驻 (配置开启时);
  /// 剪贴板/常用语/收起键盘按共享 UserDefaults 里的顺序 (toolbarToolsOrder,
  /// 仅显示开关打开的工具) 从左到右排列, 其中顺序里的最后一个工具固定在最右侧
  /// (默认是收起键盘, 方便拇指点按); 其余工具依次排在菜单按钮之后。
  /// 左侧菜单按钮不参与排序。
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

    /// 固定在工具栏最右侧的按钮 (顺序里的最后一个工具)。
    func pinButtonToTrailingEdge(_ button: UIButton) {
      commonFunctionBar.addSubview(button)
      constraints.append(contentsOf: [
        button.heightAnchor.constraint(equalTo: button.widthAnchor),
        button.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        button.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: button.bottomAnchor),
        button.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    // 工具 id -> 按钮。收起键盘永远在工具列表里 (不再受 YAML 的
    // displayKeyboardDismissButton 开关影响——那个开关在老用户已保存的
    // 配置里是关的, 之前导致收起键盘在工具栏上根本不出现, 显隐只由
    // 定制开关 (toolbarVisibleTools) 控制, 默认显示)。
    func buttonForTool(_ toolID: String) -> UIButton? {
      switch toolID {
      case "clipboard": return clipboardButton
      case "phrases": return phrasesButton
      case "dismiss": return dismissKeyboardButton
      default: return nil
      }
    }

    if keyboardContext.displayAppIconButton {
      placeButton(iconButton, after: nil)
      previousButton = iconButton
    }

    // 可见工具按保存的顺序排列: 除最后一个外依次排在左侧, 最后一个固定在最右侧
    let orderedButtons = UserDefaults.hamster.toolbarToolsOrder
      .filter { UserDefaults.hamster.isToolbarToolVisible($0) }
      .compactMap(buttonForTool)
    for (index, button) in orderedButtons.enumerated() {
      if index == orderedButtons.count - 1 {
        pinButtonToTrailingEdge(button)
      } else {
        placeButton(button, after: previousButton)
        previousButton = button
      }
    }

    toolbarButtonConstraints = constraints
    NSLayoutConstraint.activate(constraints)

    // 粘贴提示行展示时, 工具栏其他按钮暂时隐藏 (提示行盖住整个工具栏);
    // 提示行隐藏时恢复显示。
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.isHidden = isPasteRowVisible }
  }

  /// 定制工具栏面板要列出的工具 (按保存的顺序, 包括已隐藏的工具;
  /// 收起键盘永远在列, 不再受 YAML 的 displayKeyboardDismissButton 开关影响)。
  private func customizeTools() -> [(id: String, title: String, visible: Bool)] {
    let titles = ["clipboard": "剪贴板", "phrases": "常用语", "dismiss": "收起键盘"]
    return UserDefaults.hamster.toolbarToolsOrder.compactMap { id in
      guard let title = titles[id] else { return nil }
      return (id: id, title: title, visible: UserDefaults.hamster.isToolbarToolVisible(id))
    }
  }

  /// 定制工具栏面板要列出的菜单格子 (按菜单顺序, 包括已隐藏的格子)。
  private func customizeTiles() -> [(id: String, title: String, visible: Bool)] {
    menuTiles().map { tile in
      (id: tile.id, title: tile.title, visible: UserDefaults.hamster.isMenuTileVisible(tile.id))
    }
  }

  /// 打开定制工具栏面板 (覆盖在键盘根视图上)。
  private func showToolbarCustomizePanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardToolbarCustomizePanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onClose = { [weak self] in self?.dismissCustomizePanel() }
    panel.onToggle = { [weak self] toolID, visible in
      UserDefaults.hamster.setToolbarToolVisible(toolID, visible: visible)
      self?.rebuildToolbarButtons()
    }
    // 拖拽/左右移排序: 面板内已调整顺序并刷新, 这里只保存新顺序并重建工具栏
    panel.onReorder = { [weak self] orderedIDs in
      UserDefaults.hamster.toolbarToolsOrder = orderedIDs
      self?.rebuildToolbarButtons()
    }
    panel.onTileToggle = { tileID, visible in
      UserDefaults.hamster.setMenuTileVisible(tileID, visible: visible)
    }
    panel.onReset = { [weak self] in
      UserDefaults.hamster.resetToolbarToolsOrder()
      self?.rebuildToolbarButtons()
      self?.customizePanel?.reload(with: self?.customizeTools() ?? [], tiles: self?.customizeTiles() ?? [])
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: customizeTools(), tiles: customizeTiles())
    customizePanel = panel
  }

  private func dismissCustomizePanel() {
    customizePanel?.removeFromSuperview()
    customizePanel = nil
  }

  // MARK: - 粘贴提示行 (微信式: 文字在左, ⌄ 展开 + X 并排在右)

  /// 刷新粘贴提示: 仅在未输入 (工具栏显示) 时, 若剪贴板有未提示过的新内容则显示。
  /// iPhone 上复制的和 PC 同步过来的内容都会出现 (同步完成后会收到通知再刷新一次)。
  /// 只在 UIPasteboard.changeCount 变化时才读一次剪贴板内容 (读会弹"粘贴自xxx"横幅),
  /// 其余时候只用缓存展示, 绝不重复读; 打字/输入变化时不走这里 (走 showClipboardChipFromCache)。
  func refreshClipboardChip() {
    #if canImport(UIKit)
      guard !commonFunctionBar.isHidden else {
        hideClipboardChip()
        return
      }
      // changeCount 是个整数, 读它不弹横幅; 只有内容真的变了才读一次剪贴板
      let currentChangeCount = UIPasteboard.general.changeCount
      if currentChangeCount != lastChipChangeCount {
        lastChipChangeCount = currentChangeCount
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastReadPasteboardText = (text?.isEmpty == false) ? text : nil
      }
      showClipboardChipFromCache()
    #endif
  }

  /// 用缓存的剪贴板文本展示粘贴提示 (打字/输入变化时调用)。
  /// 只读 changeCount (整数, 不弹横幅) 判断缓存是否过期:
  /// 若剪贴板已变, 缓存过期, 不展示旧内容 (等下一次同步/定时检查刷新),
  /// 绝不在此读剪贴板内容。所以打字时不会再弹"粘贴自xxx"横幅。
  func showClipboardChipFromCache() {
    guard !commonFunctionBar.isHidden else {
      hideClipboardChip()
      return
    }
    #if canImport(UIKit)
      guard UIPasteboard.general.changeCount == lastChipChangeCount else {
        hideClipboardChip()
        return
      }
    #endif
    guard let text = lastReadPasteboardText, !text.isEmpty else {
      hideClipboardChip()
      return
    }
    // 已粘贴/忽略过的内容不再重复提示, 直到剪贴板换成新内容。
    // 忽略记录持久化在共享 UserDefaults 里, 键盘重建 (隐藏再打开) 也不会丢。
    #if canImport(UIKit)
      if UserDefaults.hamster.isClipboardChipDismissed(
        hash: ClipboardSyncService.sha256(text),
        changeCount: UIPasteboard.general.changeCount)
      {
        hideClipboardChip()
        return
      }
    #endif
    // 已在展示同一内容时不重复布局
    if text == clipboardChipText, isPasteRowVisible {
      return
    }
    clipboardChipText = text
    displayPasteRow(text: text)
  }

  /// 显示微信式粘贴提示行 (文字 + ⌄ 展开 + X), 并暂时隐藏工具栏其他按钮。
  private func displayPasteRow(text: String) {
    // 单行显示, 换行符转空格, 超长由 label 截断
    let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    pasteRowTextButton.setTitle(singleLine, for: .normal)
    pasteRowView.isHidden = false
    isPasteRowVisible = true
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.isHidden = true }
  }

  private func hideClipboardChip() {
    pasteRowView.isHidden = true
    isPasteRowVisible = false
    clipboardChipText = nil
    // 恢复工具栏按钮 (不在布局里的按钮改 isHidden 也没影响)
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.isHidden = false }
  }

  /// 点粘贴提示行右侧 ⌄: 展开复制内容、分段粘贴 (仿微信)。
  /// 不是隐藏键盘 (第 3 轮理解错了); 隐藏键盘只作为工具栏工具。
  @objc private func pasteRowExpandTapped() {
    showPasteSegmentsPanel()
  }

  /// 打开粘贴内容分段展开面板 (覆盖在键盘根视图上):
  /// 把当前剪贴板内容按行、句读标点切成片段, 点某段只粘贴那段,
  /// 顶部"粘贴全部"粘贴全部内容。面板关闭方式: 右上角"关闭"。
  private func showPasteSegmentsPanel() {
    guard let text = clipboardChipText, !text.isEmpty else { return }
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardPasteSegmentsPanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onSelectSegment = { [weak self] segment in
      guard let self else { return }
      self.dismissSegmentsPanel()
      self.markClipboardChipDismissedAndHide()
      self.insertPanelText(segment)
      UserDefaults.hamster.recordClipboardHistory(segment)
    }
    panel.onSelectAll = { [weak self] in
      guard let self else { return }
      self.dismissSegmentsPanel()
      self.pasteRowTextTapped()
    }
    panel.onClose = { [weak self] in self?.dismissSegmentsPanel() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: text)
    segmentsPanel = panel
  }

  private func dismissSegmentsPanel() {
    segmentsPanel?.removeFromSuperview()
    segmentsPanel = nil
  }

  /// 把当前粘贴提示内容标记为已忽略 (SHA-256 持久化) 并隐藏提示行。
  private func markClipboardChipDismissedAndHide() {
    if let text = clipboardChipText, !text.isEmpty {
      UserDefaults.hamster.markClipboardChipDismissed(
        hash: ClipboardSyncService.sha256(text),
        changeCount: currentPasteboardChangeCount)
    }
    hideClipboardChip()
  }

  /// 点粘贴提示行文字: 把剪贴板内容输入到当前输入框, 之后不再重复提示同一内容。
  @objc private func pasteRowTextTapped() {
    guard let text = clipboardChipText, !text.isEmpty else { return }
    UserDefaults.hamster.markClipboardChipDismissed(
      hash: ClipboardSyncService.sha256(text),
      changeCount: currentPasteboardChangeCount)
    hideClipboardChip()
    insertPanelText(text)
    UserDefaults.hamster.recordClipboardHistory(text)
  }

  /// 点粘贴提示行右侧 X: 关闭提示, 相同内容不再重复提示 (直到剪贴板换成新内容)。
  @objc private func pasteRowCloseTapped() {
    if let text = clipboardChipText, !text.isEmpty {
      UserDefaults.hamster.markClipboardChipDismissed(
        hash: ClipboardSyncService.sha256(text),
        changeCount: currentPasteboardChangeCount)
    }
    hideClipboardChip()
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
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardTextListPanelView(title: title)
    panel.panelBackgroundColor = opaquePanelBackgroundColor
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
