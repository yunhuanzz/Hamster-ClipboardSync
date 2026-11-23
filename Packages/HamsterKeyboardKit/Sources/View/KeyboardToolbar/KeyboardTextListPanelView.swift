//
//  KeyboardTextListPanelView.swift
//
//  键盘内文本列表面板 (剪贴板历史 / 常用语共用)。
//  点一条把文本输入到当前输入框; 长按一条删除该条。
//  所有失败静默处理, 不弹框、不阻塞打字。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 键盘内文本列表面板: 标题 + 关闭按钮 + 列表。
/// 由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
class KeyboardTextListPanelView: NibLessView {
  /// 选中一条时的回调 (由调用方负责把文本输入到输入框并关闭面板)
  var onSelect: ((String) -> Void)?
  /// 长按删除一条时的回调 (由调用方负责从存储中删除并刷新列表)
  var onDelete: ((Int) -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?
  /// 点"立即同步"时的回调 (仅剪贴板面板使用)
  var onSyncNow: (() -> Void)?
  /// 同步完成时的回调 (仅剪贴板面板使用, 供调用方刷新列表)
  var onSyncFinished: (() -> Void)?

  private var items: [String] = []

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("关闭", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  /// 同步状态文字 (仅剪贴板面板使用): 显示最近一次同步结果, 如 "13:20 同步成功"。
  private lazy var statusLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 立即同步按钮 (仅剪贴板面板使用): 手动触发一次同步, 跳过 2 秒节流。
  private lazy var syncNowButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("立即同步", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(syncNowTapped), for: .touchUpInside)
    return button
  }()

  /// 同步状态行容器 (仅剪贴板面板使用)。隐藏时高度为 0, 不占位置。
  private lazy var syncRowView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  private var syncRowHeightConstraint: NSLayoutConstraint?

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .plain)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 44
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TextListCell")
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

  init(title: String) {
    super.init(frame: .zero)
    titleLabel.text = title
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()

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
    addSubview(titleLabel)
    addSubview(closeButton)
    syncRowView.addSubview(statusLabel)
    syncRowView.addSubview(syncNowButton)
    addSubview(syncRowView)
    addSubview(tableView)
    addSubview(emptyLabel)
  }

  override func activateViewConstraints() {
    syncRowHeightConstraint = syncRowView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      syncRowView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      syncRowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      syncRowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      syncRowHeightConstraint!,

      statusLabel.leadingAnchor.constraint(equalTo: syncRowView.leadingAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: syncRowView.centerYAnchor),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: syncNowButton.leadingAnchor, constant: -8),

      syncNowButton.trailingAnchor.constraint(equalTo: syncRowView.trailingAnchor),
      syncNowButton.centerYAnchor.constraint(equalTo: syncRowView.centerYAnchor),

      tableView.topAnchor.constraint(equalTo: syncRowView.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
  }

  /// 刷新列表内容
  func reload(with items: [String]) {
    self.items = items
    emptyLabel.isHidden = !items.isEmpty
    tableView.reloadData()
  }

  /// 显示同步状态行 (仅剪贴板面板调用): 左侧最近一次同步结果, 右侧"立即同步"按钮。
  func showSyncRow(statusText: String) {
    syncRowView.isHidden = false
    syncRowHeightConstraint?.constant = 28
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

  /// 同步完成: 刷新状态文字, 并通知调用方刷新列表 (下载的新内容可能已写入剪贴板)。
  @objc private func syncDidFinish() {
    guard !syncRowView.isHidden else { return }
    setStatusText(UserDefaults.hamster.clipboardSyncLastStatusText)
    onSyncFinished?()
  }

  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    let point = gesture.location(in: tableView)
    guard let indexPath = tableView.indexPathForRow(at: point) else { return }
    onDelete?(indexPath.row)
  }
}

extension KeyboardTextListPanelView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "TextListCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = items[indexPath.row]
    content.textProperties.numberOfLines = 2
    content.textProperties.lineBreakMode = .byTruncatingTail
    cell.contentConfiguration = content
    cell.backgroundColor = .clear
    return cell
  }
}

extension KeyboardTextListPanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onSelect?(items[indexPath.row])
  }
}
