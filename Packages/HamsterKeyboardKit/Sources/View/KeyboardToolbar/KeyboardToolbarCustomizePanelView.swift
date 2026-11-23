//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法):
//  第 1 节: 工具栏上的工具, 逐个开关显示/隐藏, 每行可改分区 (左/中/右,
//    分段选择器) 与组内上下移动, 也可拖拽排序 (拖拽改的是全部顺序,
//    组内相对顺序以它为准)。
//  第 2 节: 菜单宫格里的格子, 逐个开关显示/隐藏。
//  开关/分区/顺序存在 App Group 共享 UserDefaults (toolbarVisibleTools /
//  toolbarToolZones / toolbarToolsOrder) 里; 工具栏渲染时只显示开关打开的
//  工具, 按分区 (左/中/右) 分组、组内按顺序紧凑排列。
//  左侧菜单按钮本身不可隐藏 (它是打开菜单/恢复显示的入口), 所以不在列表里。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 定制工具栏面板: 标题 + 关闭按钮 + 工具开关列表 (可拖拽排序/左右移) +
/// 菜单格子开关列表 + 恢复默认。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一工具开关变化时的回调 (toolID, 是否显示), 由调用方写 UserDefaults 并重建工具栏。
  var onToggle: ((String, Bool) -> Void)?
  /// 某一工具分区变化时的回调 (toolID, 新分区), 由调用方保存分区、重建工具栏并刷新本面板。
  var onZoneChange: ((String, UserDefaults.ToolbarToolZone) -> Void)?
  /// 拖拽/上下移排序后的回调 (新的全部工具 id 顺序), 由调用方保存顺序并重建工具栏。
  /// 面板内已自行调整顺序并刷新, 调用方不需要再 reload。
  var onReorder: (([String]) -> Void)?
  /// 某一菜单格子开关变化时的回调 (tileID, 是否显示), 由调用方写 UserDefaults。
  var onTileToggle: ((String, Bool) -> Void)?
  /// 点"恢复默认"时的回调 (由调用方恢复默认顺序并全部显示, 再刷新列表)。
  var onReset: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 工具 id -> 行首图标 (与工具栏按钮同一套细线 SF Symbols)。
  /// 收起键盘是 plain 下箭头 chevron.down (不是 keyboard.chevron.compact.down)。
  private static let toolIcons: [String: String] = [
    "clipboard": "list.clipboard",
    "phrases": "quote.bubble",
    "dismiss": "chevron.down",
  ]

  /// 工具列表: (id, 显示名, 是否显示, 分区)。由调用方传入 (收起键盘永远在列,
  /// 不再受 YAML 的 displayKeyboardDismissButton 开关影响——那个开关
  /// 在老用户已保存的配置里是关的, 之前导致收起键盘在工具栏和本面板里
  /// 根本不出现, 排序也只能在剪贴板/常用语之间换一下)。
  /// 顺序即工具栏上的全局顺序 (toolbarToolsOrder); 同区内的相对顺序就是
  /// 组内顺序, 上下移只在同区内换位。
  private var tools: [(id: String, title: String, visible: Bool, zone: UserDefaults.ToolbarToolZone)] = []

  /// 菜单格子列表: (id, 显示名, 是否显示)。由调用方传入 menuTiles()。
  private var tiles: [(id: String, title: String, visible: Bool)] = []

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
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = 52
    // 不透明: 面板本身已是不透明底色, 列表用同一颜色, 按键透不出来;
    // 深色模式下是深灰, 不是纯黑, 不会出现黑斑。
    tableView.backgroundColor = panelBackgroundColor
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ToolbarToolCell")
    // 常驻编辑模式: 显示右侧拖拽手柄 (排序用), 左侧不显示删除控件。
    // 开关仍可用 (未设置 editingAccessoryView 时 accessoryView 会继续显示)。
    tableView.isEditing = true
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
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来 (第 3 轮改成 .clear 是错的)。
    // 深色模式下底色是深灰 (#2C2C2C), 不是纯黑, 所以不会再出现黑斑。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新工具 + 菜单格子列表
  func reload(with tools: [(id: String, title: String, visible: Bool, zone: UserDefaults.ToolbarToolZone)], tiles: [(id: String, title: String, visible: Bool)]) {
    self.tools = tools
    self.tiles = tiles
    tableView.reloadData()
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func resetTapped() {
    onReset?()
  }

  /// 通过控件在 tableView 中的位置找行 (拖拽排序后 tag 可能过期, 不用 tag)。
  private func indexPath(for control: UIView) -> IndexPath? {
    let point = control.convert(CGPoint.zero, to: tableView)
    return tableView.indexPathForRow(at: point)
  }

  @objc private func switchChanged(_ sender: UISwitch) {
    guard let indexPath = indexPath(for: sender) else { return }
    if indexPath.section == 0 {
      let tool = tools[indexPath.row]
      // 同步本地状态, 否则之后 reload 会显示旧的开关状态。
      tools[indexPath.row].visible = sender.isOn
      onToggle?(tool.id, sender.isOn)
    } else {
      let tile = tiles[indexPath.row]
      tiles[indexPath.row].visible = sender.isOn
      onTileToggle?(tile.id, sender.isOn)
    }
  }

  /// 上移按钮: 工具在同区内往上挪一位 (组内顺序)。
  @objc private func moveUpTapped(_ sender: UIButton) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 0 else { return }
    moveToolWithinZone(at: indexPath.row, by: -1)
  }

  /// 下移按钮: 工具在同区内往下挪一位 (组内顺序)。
  @objc private func moveDownTapped(_ sender: UIButton) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 0 else { return }
    moveToolWithinZone(at: indexPath.row, by: 1)
  }

  /// 组内移动: 与同区最近的邻位换位 (flat 顺序里找同区邻居, 换位后组内
  /// 相对顺序即变, 跨区不动); 同区没有邻位时不动 (按钮置灰, 点不到)。
  private func moveToolWithinZone(at index: Int, by offset: Int) {
    guard tools.indices.contains(index) else { return }
    let zone = tools[index].zone
    let neighbor: Int?
    if offset < 0 {
      neighbor = (0..<index).reversed().first { tools[$0].zone == zone }
    } else {
      neighbor = ((index + 1)..<tools.count).first { tools[$0].zone == zone }
    }
    guard let neighbor else { return }
    tools.swapAt(index, neighbor)
    tableView.reloadData()
    onReorder?(tools.map { $0.id })
  }

  /// 同区内是否有上/下邻位 (决定上下移按钮是否可用)。
  private func hasZoneNeighbor(at index: Int, offset: Int) -> Bool {
    guard tools.indices.contains(index) else { return false }
    let zone = tools[index].zone
    if offset < 0 {
      return (0..<index).reversed().contains { tools[$0].zone == zone }
    }
    return ((index + 1)..<tools.count).contains { tools[$0].zone == zone }
  }

  /// 分区选择器 (左/中/右三段)。改分区后行会留在原位 (flat 顺序不变),
  /// 只换组, 工具栏上立刻进新组; 上下移可用性随之刷新。
  private func zoneSegmentedControl(for tool: (id: String, title: String, visible: Bool, zone: UserDefaults.ToolbarToolZone)) -> UISegmentedControl {
    let control = UISegmentedControl(items: UserDefaults.ToolbarToolZone.allCases.map { $0.title })
    control.selectedSegmentIndex = UserDefaults.ToolbarToolZone.allCases.firstIndex(of: tool.zone) ?? 0
    control.addTarget(self, action: #selector(zoneChanged(_:)), for: UIControl.Event.valueChanged)
    return control
  }

  @objc private func zoneChanged(_ sender: UISegmentedControl) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 0,
          sender.selectedSegmentIndex >= 0,
          sender.selectedSegmentIndex < UserDefaults.ToolbarToolZone.allCases.count else { return }
    let zone = UserDefaults.ToolbarToolZone.allCases[sender.selectedSegmentIndex]
    let tool = tools[indexPath.row]
    guard tool.zone != zone else { return }
    tools[indexPath.row].zone = zone
    tableView.reloadData()
    onZoneChange?(tool.id, zone)
  }

  /// 上移/下移小按钮 (16pt 细线箭头)。到头时置灰不可点。
  private func moveButton(systemImage: String, enabled: Bool, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 16), scale: .default), forImageIn: .normal)
    button.tintColor = enabled ? .label : .tertiaryLabel
    button.isEnabled = enabled
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? tools.count : tiles.count
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    section == 0 ? "工具栏工具" : "菜单格子"
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "ToolbarToolCell", for: indexPath)
    let isToolSection = indexPath.section == 0
    let title: String
    let iconName: String?
    let visible: Bool
    if isToolSection {
      let tool = tools[indexPath.row]
      title = tool.title
      iconName = Self.toolIcons[tool.id]
      visible = tool.visible
    } else {
      let tile = tiles[indexPath.row]
      title = tile.title
      iconName = nil
      visible = tile.visible
    }
    var content = cell.defaultContentConfiguration()
    content.text = title
    if let iconName {
      content.image = UIImage(systemName: iconName)
      content.imageProperties.maximumSize = CGSize(width: 22, height: 22)
      content.imageProperties.tintColor = .label
    }
    cell.contentConfiguration = content
    // 列表是不透明底色, cell 本身透明即可 (透出列表底色, 不透出按键)。
    cell.backgroundColor = .clear
    cell.selectionStyle = .none

    let toggle = UISwitch()
    toggle.isOn = visible
    toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)

    if isToolSection {
      // 分区选择器 (左/中/右) + 同区内上下移按钮 + 开关
      // (拖拽之外的显式排序操作; 拖拽改全局顺序, 上下移只在同区内换位)。
      let zoneControl = zoneSegmentedControl(for: tools[indexPath.row])
      let up = moveButton(systemImage: "chevron.up", enabled: hasZoneNeighbor(at: indexPath.row, offset: -1), action: #selector(moveUpTapped(_:)))
      let down = moveButton(systemImage: "chevron.down", enabled: hasZoneNeighbor(at: indexPath.row, offset: 1), action: #selector(moveDownTapped(_:)))
      let stack = UIStackView(arrangedSubviews: [zoneControl, up, down, toggle])
      stack.axis = .horizontal
      stack.spacing = 6
      stack.alignment = .center
      cell.accessoryView = stack
    } else {
      cell.accessoryView = toggle
    }
    return cell
  }

  /// 只有工具栏工具一节可拖拽排序; 菜单格子一节只开关显隐, 不排序。
  func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    indexPath.section == 0
  }

  /// 拖拽排序: 调整本地顺序并通知调用方保存。
  func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    guard sourceIndexPath.section == 0, destinationIndexPath.section == 0 else { return }
    let tool = tools.remove(at: sourceIndexPath.row)
    tools.insert(tool, at: destinationIndexPath.row)
    onReorder?(tools.map { $0.id })
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
  }

  /// 编辑模式下不显示左侧删除/插入控件, 只有右侧拖拽手柄。
  func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
    .none
  }

  /// 编辑模式下内容不缩进。
  func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
    false
  }
}
