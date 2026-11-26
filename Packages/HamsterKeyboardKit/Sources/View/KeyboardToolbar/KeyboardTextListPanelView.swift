//
//  KeyboardTextListPanelView.swift
//
//  键盘内剪贴板 / 常用语二合一面板 (仿微信输入法剪贴板工具, 第 13 轮重做)。
//  顶部是 [剪贴板 | 常用语] 分段切换 (UISegmentedControl), 两页共用一个面板:
//  每条内容一张白底圆角卡片 (浅色下 .systemBackground 白底、圆角 12pt),
//  每条右上角 ⋮ 菜单 (粘贴 / 删除; 常用语页另有编辑)。
//  点卡片把文本输入到当前输入框 (并关闭面板); 剪贴板页保留同步状态行
//  ("11:03 同步成功" + "立即同步"药丸按钮, 不再是两行裸链接); 常用语页
//  的操作行是"管理常用语"药丸按钮 (打开键盘内常用语管理面板)。
//  第 15 轮删掉了常用语页底部的添加行 (输入框 + 粘贴 + 添加):
//  面板是盖住按键区的全屏覆盖层, 键盘按键够不着面板内的输入框
//  (按键输入只会写到宿主 App 的输入框), 输入框里根本打不出字,
//  粘贴添加也不好用, 不如不要; 添加常用语走键盘内常用语管理面板
//  或主 App 设置页 (同一条 commonPhrases 保存路径)。
//  长按剪贴板条目展开全文 (第 17 轮第 6 项, 可长按拖选一段粘贴);
//  长按常用语条目仍是删除。删除剪贴板条目走卡片右上角 ⋮ 菜单。
//  两个页面各接自己的数据与回调, 互不串味: 剪贴板页读写 clipboardHistory,
//  常用语页读写 commonPhrases; 切段只换数据源, 不重建面板。
//  所有失败静默处理, 不弹框、不阻塞打字。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 键盘内剪贴板 / 常用语面板: 分段切换 + 卡片列表 + 操作行。
class KeyboardTextListPanelView: NibLessView {
  /// 面板内的两个分段页。
  enum Page {
    case clipboard
    case phrases
  }

  /// 选中剪贴板页的一条时的回调 (由调用方把文本输入到输入框并关闭面板)。
  var onSelectClipboardText: ((String) -> Void)?
  /// 点剪贴板卡片内的提取条目 (链接 / 验证码) 时的回调 (只粘贴该部分),
  /// 由调用方把该部分输入到输入框并关闭面板 (第 17 轮第 6 项)。
  var onSelectExtractedItem: ((String) -> Void)?
  /// 长按剪贴板页的一条时的回调 (由调用方打开全文展开视图; 第 17 轮第 6 项)。
  /// 长按不再是删除 (删除仍在卡片右上角 ⋮ 菜单里)。
  var onExpandClipboardItem: ((String) -> Void)?
  /// 剪贴板页删一条时的回调 (由调用方从存储中删除并刷新列表, 面板保持打开)。
  var onDeleteClipboardItem: ((Int) -> Void)?
  /// 选中常用语页的一条时的回调 (由调用方把文本输入到输入框并关闭面板)。
  var onSelectPhrase: ((String) -> Void)?
  /// 常用语页删一条时的回调 (由调用方从存储中删除并刷新列表, 面板保持打开)。
  var onDeletePhrase: ((Int) -> Void)?
  /// 常用语页 ⋮→编辑时的回调 (由调用方打开常用语管理面板并载入该条)。
  var onEditPhrase: ((Int) -> Void)?
  /// 常用语页点"管理常用语"时的回调 (由调用方打开常用语管理面板)。
  var onManagePhrases: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?
  /// 点"立即同步"时的回调 (仅剪贴板页使用)
  var onSyncNow: (() -> Void)?
  /// 同步完成时的回调 (仅剪贴板页使用, 供调用方刷新列表)
  var onSyncFinished: (() -> Void)?

  /// 当前显示的分段页。
  private var currentPage: Page
  private var clipboardItems: [String] = []
  private var phraseItems: [String] = []

  /// 当前页的数据源 (切段时换, 回调按页分流, 不会串味)。
  private var currentItems: [String] {
    switch currentPage {
    case .clipboard: return clipboardItems
    case .phrases: return phraseItems
    }
  }

  /// 调用方是否打开了同步状态行 (仅剪贴板页显示; 默认不开)。
  private var isSyncRowEnabled = false

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 注意: 不能用 .clear——第 3 轮的透明修法是错的, 面板是全屏覆盖层,
  /// 透明底会让键盘按键从列表后面透出来。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
      tableView.backgroundColor = panelBackgroundColor
    }
  }

  /// 顶部 [剪贴板 | 常用语] 分段切换 (仿微信剪贴板工具顶栏的灰底药丸分段条)。
  private lazy var segmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["剪贴板", "常用语"])
    control.selectedSegmentIndex = self.currentPage == .clipboard ? 0 : 1
    // 灰底药丸 + 白底选中段: 浅色下与微信的分段条一致, 深色下自动变深。
    control.backgroundColor = .systemGray5
    control.selectedSegmentTintColor = .systemBackground
    control.translatesAutoresizingMaskIntoConstraints = false
    control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    return control
  }()

  /// 左上角 ⌃ 收起按钮 = 关闭面板 (与功能菜单面板的 ⌃ 收起同一套入口)。
  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "chevron.up"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  /// 同步状态文字 (仅剪贴板页使用): 显示最近一次同步结果, 如 "11:03 同步成功"。
  private lazy var statusLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 立即同步药丸按钮 (仅剪贴板页使用): 手动触发一次同步, 跳过 0.5 秒节流。
  private lazy var syncNowButton: UIButton = {
    let button = Self.makePillButton(title: "立即同步")
    button.addTarget(self, action: #selector(syncNowTapped), for: .touchUpInside)
    return button
  }()

  /// 常用语页的操作行提示 (仅常用语页使用)。
  private lazy var phrasesHintLabel: UILabel = {
    let label = UILabel()
    label.text = "点 ⋮ 可编辑、删除"
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 管理常用语药丸按钮 (仅常用语页使用): 打开键盘内常用语管理面板。
  private lazy var manageButton: UIButton = {
    let button = Self.makePillButton(title: "管理常用语")
    button.addTarget(self, action: #selector(manageTapped), for: .touchUpInside)
    return button
  }()

  /// 操作行容器: 剪贴板页放同步状态 + 立即同步, 常用语页放提示 + 管理常用语。
  /// 剪贴板页未启用同步行时高度为 0, 不占位置。
  private lazy var actionRowView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  private var actionRowHeightConstraint: NSLayoutConstraint?

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .plain)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    // 卡片之间用 cell 内的留白分隔, 不用系统分割线。
    tableView.separatorStyle = .none
    // 不透明: 面板本身已是不透明底色, 列表用同一颜色, 按键透不出来;
    // 深色模式下是深灰, 不是纯黑, 不会出现黑斑。
    tableView.backgroundColor = panelBackgroundColor
    tableView.register(KeyboardTextListCardCell.self, forCellReuseIdentifier: "TextListCardCell")
    return tableView
  }()

  private lazy var emptyLabel: UILabel = {
    let label = UILabel()
    label.text = "暂无内容"
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 浅灰药丸按钮 (同步行 / 管理行共用): 旧"立即同步"文字链的样式收进药丸里。
  /// 键盘走白灰极简, 不用彩色。
  private static func makePillButton(title: String) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(.label, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
    button.backgroundColor = UIColor.systemGray6
    button.layer.cornerRadius = 13
    button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  init(initialPage: Page = .clipboard) {
    currentPage = initialPage
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    updateActionRow()

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    tableView.addGestureRecognizer(longPress)

    NotificationCenter.default.addObserver(
      self, selector: #selector(syncDidFinish),
      name: ClipboardSyncService.didFinishNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func constructViewHierarchy() {
    addSubview(closeButton)
    addSubview(segmentedControl)
    actionRowView.addSubview(statusLabel)
    actionRowView.addSubview(syncNowButton)
    actionRowView.addSubview(phrasesHintLabel)
    actionRowView.addSubview(manageButton)
    addSubview(actionRowView)
    addSubview(tableView)
    addSubview(emptyLabel)
  }

  override func activateViewConstraints() {
    actionRowHeightConstraint = actionRowView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      closeButton.widthAnchor.constraint(equalToConstant: 32),
      closeButton.heightAnchor.constraint(equalToConstant: 32),

      segmentedControl.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
      segmentedControl.widthAnchor.constraint(equalToConstant: 200),
      segmentedControl.heightAnchor.constraint(equalToConstant: 30),

      actionRowView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
      actionRowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      actionRowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      actionRowHeightConstraint!,

      statusLabel.leadingAnchor.constraint(equalTo: actionRowView.leadingAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: actionRowView.centerYAnchor),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: syncNowButton.leadingAnchor, constant: -8),

      syncNowButton.trailingAnchor.constraint(equalTo: actionRowView.trailingAnchor),
      syncNowButton.centerYAnchor.constraint(equalTo: actionRowView.centerYAnchor),

      phrasesHintLabel.leadingAnchor.constraint(equalTo: actionRowView.leadingAnchor),
      phrasesHintLabel.centerYAnchor.constraint(equalTo: actionRowView.centerYAnchor),
      phrasesHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: manageButton.leadingAnchor, constant: -8),

      manageButton.trailingAnchor.constraint(equalTo: actionRowView.trailingAnchor),
      manageButton.centerYAnchor.constraint(equalTo: actionRowView.centerYAnchor),

      tableView.topAnchor.constraint(equalTo: actionRowView.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),

      emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来 (第 3 轮改成 .clear 是错的)。
    // 深色模式下底色是深灰 (#2C2C2C), 不是纯黑, 所以不会再出现黑斑。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新两页内容 (调用方从共享 UserDefaults 重读后传入)。
  func reload(clipboardItems: [String], phrases: [String]) {
    self.clipboardItems = clipboardItems
    phraseItems = phrases
    reloadCurrentPage()
  }

  /// 刷新当前页的列表与空态 (切段 / 数据变化时调用)。
  private func reloadCurrentPage() {
    emptyLabel.text = currentPage == .clipboard ? "暂无剪贴板内容" : "暂无常用语"
    emptyLabel.isHidden = !currentItems.isEmpty
    tableView.reloadData()
  }

  /// 按当前页配置操作行:
  /// 剪贴板页显示同步状态 + 立即同步 (未启用同步行时整行隐藏);
  /// 常用语页显示提示 + 管理常用语。
  private func updateActionRow() {
    switch currentPage {
    case .clipboard:
      statusLabel.isHidden = false
      syncNowButton.isHidden = false
      phrasesHintLabel.isHidden = true
      manageButton.isHidden = true
      actionRowView.isHidden = !isSyncRowEnabled
      actionRowHeightConstraint?.constant = isSyncRowEnabled ? 28 : 0
    case .phrases:
      statusLabel.isHidden = true
      syncNowButton.isHidden = true
      phrasesHintLabel.isHidden = false
      manageButton.isHidden = false
      actionRowView.isHidden = false
      actionRowHeightConstraint?.constant = 28
    }
  }

  /// 显示同步状态行 (仅剪贴板页调用): 左侧最近一次同步结果, 右侧"立即同步"药丸按钮。
  func showSyncRow(statusText: String) {
    isSyncRowEnabled = true
    updateActionRow()
    setStatusText(statusText)
  }

  /// 更新同步状态文字 (同步完成通知到达时调用)。
  func setStatusText(_ text: String) {
    statusLabel.text = text.isEmpty ? "未同步过" : text
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func syncNowTapped() {
    onSyncNow?()
  }

  @objc private func manageTapped() {
    onManagePhrases?()
  }

  @objc private func segmentChanged() {
    currentPage = segmentedControl.selectedSegmentIndex == 0 ? .clipboard : .phrases
    updateActionRow()
    reloadCurrentPage()
  }

  /// 点卡片 / ⋮→粘贴的公共入口: 按当前页分流到各自的选中回调。
  private func selectItem(at row: Int) {
    let items = currentItems
    guard items.indices.contains(row) else { return }
    switch currentPage {
    case .clipboard:
      onSelectClipboardText?(items[row])
    case .phrases:
      onSelectPhrase?(items[row])
    }
  }

  /// ⋮ 菜单点下时按当前 cell 反查行号: 列表在菜单打开期间被同步刷新重排过
  /// 也能拿到最新行号; 再用建菜单时记下的文本比对一次, 对不上就什么都不做
  /// (宁可不执行, 也不对错一条——剪贴板里可能有重复文本)。
  private func resolveRow(for cell: UITableViewCell, expectedText: String) -> Int? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    let items = currentItems
    guard items.indices.contains(indexPath.row), items[indexPath.row] == expectedText else { return nil }
    return indexPath.row
  }

  /// 某条卡片的 ⋮ 菜单: 粘贴 / 删除; 常用语页另有编辑。
  /// 行号不在建菜单时定死, 点下时按 cell 反查最新行号 (见 resolveRow)。
  private func moreMenu(for cell: KeyboardTextListCardCell, text: String) -> UIMenu {
    let paste = UIAction(title: "粘贴", image: UIImage(systemName: "doc.on.clipboard")) { [weak self, weak cell] _ in
      guard let self, let cell, let row = self.resolveRow(for: cell, expectedText: text) else { return }
      self.selectItem(at: row)
    }
    let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self, weak cell] _ in
      guard let self, let cell, let row = self.resolveRow(for: cell, expectedText: text) else { return }
      switch self.currentPage {
      case .clipboard:
        self.onDeleteClipboardItem?(row)
      case .phrases:
        self.onDeletePhrase?(row)
      }
    }
    switch currentPage {
    case .clipboard:
      return UIMenu(title: "", children: [paste, delete])
    case .phrases:
      let edit = UIAction(title: "编辑", image: UIImage(systemName: "square.and.pencil")) { [weak self, weak cell] _ in
        guard let self, let cell, let row = self.resolveRow(for: cell, expectedText: text) else { return }
        self.onEditPhrase?(row)
      }
      return UIMenu(title: "", children: [paste, edit, delete])
    }
  }

  /// 同步完成: 刷新状态文字, 并通知调用方刷新列表 (下载的新内容可能已写入剪贴板)。
  /// 注意: 不再像旧版那样"操作行隐藏时直接 return"——面板现在同时管两页,
  /// 常用语页开着时同步完成也要刷新剪贴板数据, 否则切回剪贴板页看到的是旧列表。
  @objc private func syncDidFinish() {
    setStatusText(UserDefaults.hamster.clipboardSyncLastStatusText)
    onSyncFinished?()
  }

  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    let point = gesture.location(in: tableView)
    guard let indexPath = tableView.indexPathForRow(at: point) else { return }
    switch currentPage {
    case .clipboard:
      // 第 17 轮第 6 项: 长按剪贴板条目展开全文 (可长按拖选一段粘贴),
      // 不再是删除——删除仍在卡片右上角 ⋮ 菜单里。
      let items = currentItems
      guard items.indices.contains(indexPath.row) else { return }
      onExpandClipboardItem?(items[indexPath.row])
    case .phrases:
      onDeletePhrase?(indexPath.row)
    }
  }
}

extension KeyboardTextListPanelView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    currentItems.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "TextListCardCell", for: indexPath)
    guard let cardCell = cell as? KeyboardTextListCardCell else { return cell }
    let text = currentItems[indexPath.row]
    cardCell.contentLabel.text = text
    // 剪贴板页: 卡片内出提取条目药丸 (链接 / 验证码, 第 17 轮第 6 项);
    // 常用语页没有提取项。
    if currentPage == .clipboard {
      cardCell.setExtractedItems(ClipboardContentExtractor.extract(from: text))
    } else {
      cardCell.setExtractedItems([])
    }
    cardCell.onExtractedItemTap = { [weak self] itemText in
      self?.onSelectExtractedItem?(itemText)
    }
    // ⋮ 菜单按当前行现建 (复用时重建, 不会串到上一行); 点下时再反查最新行号。
    cardCell.moreButton.menu = moreMenu(for: cardCell, text: text)
    return cardCell
  }
}

extension KeyboardTextListPanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    selectItem(at: indexPath.row)
  }
}

/// 卡片式列表行: 白底圆角卡片 + 内容文字 + 右上角 ⋮ 按钮。
/// 卡片与面板底色拉开层次 (浅色下白卡片配灰底, 与微信剪贴板工具一致);
/// 深色下 .systemBackground 自动变深, 不会刺眼。
/// 剪贴板页的卡片在内容下方另有一行提取条目药丸 (链接 / 验证码,
/// 第 17 轮第 6 项), 点药丸只粘贴该部分; 无提取项时该行高度为 0。
private final class KeyboardTextListCardCell: UITableViewCell {
  /// 点卡片内提取条目药丸时的回调 (只粘贴该部分), 由面板在 cellForRowAt 里接上。
  var onExtractedItemTap: ((String) -> Void)?

  let cardView: UIView = {
    let view = UIView()
    // 浅色白底、深色自动变深; 圆角 12pt 向微信/菜单宫格看齐。
    view.backgroundColor = .systemBackground
    view.layer.cornerRadius = 12
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  let contentLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 16)
    label.textColor = .label
    label.numberOfLines = 2
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 提取条目药丸行 (横向, 最多 5+5 项; 无提取项时高度约束为 0)。
  private lazy var extractedStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 6
    stack.alignment = .center
    stack.distribution = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private var extractedStackHeightConstraint: NSLayoutConstraint?

  /// 提取条目小气泡: 白底 + 细边框, 与正文用间距隔开, 不用背景色区分;
  /// 网址/验证码用图标区分 (link / key.fill) + 截断文字; 点按只粘贴该部分。
  private func makeExtractedChip(for item: ClipboardContentExtractor.ExtractedItem) -> UIButton {
    let button = UIButton(type: .system)
    let iconName = item.kind == .url ? "link" : "key.fill"
    let displayText: String
    if item.kind == .url {
      displayText = item.text.count > 28
        ? String(item.text.prefix(20)) + "…" + String(item.text.suffix(6)) : item.text
    } else {
      displayText = item.text
    }
    button.setTitle(displayText, for: .normal)
    button.setImage(UIImage(systemName: iconName), for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 11, weight: .medium), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.backgroundColor = UIColor.systemBackground
    button.layer.cornerRadius = 11
    button.layer.borderColor = UIColor.systemGray4.cgColor
    button.layer.borderWidth = 1
    button.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(extractedChipTapped(_:)), for: .touchUpInside)
    return button
  }

  @objc private func extractedChipTapped(_ sender: UIButton) {
    // 药丸按提取项下标编号 (tag), 点按时取对应项的原文。
    guard extractedItems.indices.contains(sender.tag) else { return }
    onExtractedItemTap?(extractedItems[sender.tag].text)
  }

  private var extractedItems: [ClipboardContentExtractor.ExtractedItem] = []

  /// 按提取结果重建卡片内的药丸行 (复用时重建, 不会串到上一行)。
  func setExtractedItems(_ items: [ClipboardContentExtractor.ExtractedItem]) {
    extractedItems = items
    extractedStackView.arrangedSubviews.forEach {
      extractedStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    for (index, item) in items.enumerated() {
      let chip = makeExtractedChip(for: item)
      chip.tag = index
      extractedStackView.addArrangedSubview(chip)
    }
    extractedStackView.isHidden = items.isEmpty
    extractedStackHeightConstraint?.constant = items.isEmpty ? 0 : 22
  }

  /// 右上角 ⋮: 点按弹出菜单 (UIMenu, iOS 14+; 部署目标 15.0)。
  /// 菜单由面板在 cellForRowAt 里按当前行现建。
  let moreButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("⋮", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.showsMenuAsPrimaryAction = true
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    selectionStyle = .none
    contentView.addSubview(cardView)
    cardView.addSubview(contentLabel)
    cardView.addSubview(extractedStackView)
    cardView.addSubview(moreButton)
    extractedStackHeightConstraint = extractedStackView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

      contentLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      contentLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
      contentLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -4),
      // 内容底边: 药丸行在时贴药丸行, 无药丸时贴卡片底 (两条 <=, 紧的那条生效)。
      contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: extractedStackView.topAnchor, constant: -6),
      contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),

      extractedStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      extractedStackView.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -4),
      extractedStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),
      extractedStackHeightConstraint!,

      moreButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
      moreButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: 32),
      moreButton.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    contentLabel.text = nil
    moreButton.menu = nil
    setExtractedItems([])
    onExtractedItemTap = nil
  }
}
