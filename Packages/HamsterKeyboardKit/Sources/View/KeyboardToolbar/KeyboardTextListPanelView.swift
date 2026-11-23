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
  }

  override func constructViewHierarchy() {
    addSubview(titleLabel)
    addSubview(closeButton)
    addSubview(tableView)
    addSubview(emptyLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
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

  @objc private func closeTapped() {
    onClose?()
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
