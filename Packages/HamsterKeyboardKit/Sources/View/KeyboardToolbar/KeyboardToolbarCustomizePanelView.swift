//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法): 逐个开关工具栏上的工具。
//  开关状态存在 App Group 共享 UserDefaults (toolbarVisibleTools) 里,
//  工具栏渲染时只显示开关打开的工具。左侧菜单按钮本身不可隐藏
//  (它是打开菜单/恢复显示的入口), 所以不在列表里。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 定制工具栏面板: 标题 + 关闭按钮 + 工具开关列表 + 恢复默认。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一工具开关变化时的回调 (toolID, 是否显示), 由调用方写 UserDefaults 并重建工具栏。
  var onToggle: ((String, Bool) -> Void)?
  /// 点"恢复默认"时的回调 (由调用方恢复全部显示并刷新列表)。
  var onReset: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 工具列表: (id, 显示名, 是否显示)。由调用方传入 (收起键盘仅在配置开启时才列出)。
  private var tools: [(id: String, title: String, visible: Bool)] = []

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "定制工具栏"
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
    tableView.rowHeight = 52
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ToolbarToolCell")
    return tableView
  }()

  private lazy var resetButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("恢复默认 (全部显示)", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
    return button
  }()

  init() {
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(titleLabel)
    addSubview(closeButton)
    addSubview(tableView)
    addSubview(resetButton)
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
      tableView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -8),

      resetButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      resetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      resetButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
      resetButton.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
  }

  /// 刷新工具列表
  func reload(with tools: [(id: String, title: String, visible: Bool)]) {
    self.tools = tools
    tableView.reloadData()
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func resetTapped() {
    onReset?()
  }

  @objc private func switchChanged(_ sender: UISwitch) {
    let tool = tools[sender.tag]
    onToggle?(tool.id, sender.isOn)
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    tools.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "ToolbarToolCell", for: indexPath)
    let tool = tools[indexPath.row]
    var content = cell.defaultContentConfiguration()
    content.text = tool.title
    cell.contentConfiguration = content
    cell.backgroundColor = .clear
    cell.selectionStyle = .none
    let toggle = UISwitch()
    toggle.isOn = tool.visible
    toggle.tag = indexPath.row
    toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
    cell.accessoryView = toggle
    return cell
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
  }
}
