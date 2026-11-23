//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法, 第 6 轮重构):
//  第 0 节: 当前工具栏——横向顺序即工具栏上的顺序, 每行右上角 ⊖ 点按删除
//    (只是从工具栏拿掉、回工具池, 不是删除功能), 可拖拽排序 (UITableView
//    标准 reorder, 拖动后顺序立即保存)。
//  第 1 节: 可选工具池——注册表里不在工具栏上的工具, 点按加入工具栏
//    (新工具插在收起键盘前面, 保证收起键盘仍默认在最右)。
//  第 2 节: 菜单宫格里的格子, 逐个开关显示/隐藏。
//  工具注册表共 7 个 (剪贴板/常用语/收起键盘/切换26键·九宫格/
//  立即同步剪贴板/设置/常用语管理, "定制工具栏"本身是入口、不上栏),
//  由调用方 (KeyboardToolbarView) 传入; 面板不自己决定有哪些工具。
//  位置完全由拖动顺序决定 (拖到中间就是中间), 第 5 轮的左/中/右分区
//  模型已取消 (toolbarToolZones 键留着不用, 不删已存数据)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterUIKit
import UIKit

/// 定制工具栏面板: 标题 + ✓ 关闭 + 当前工具栏 (⊖ 删除/拖拽排序) +
/// 可选工具池 (点按加入) + 菜单格子开关 + 恢复默认。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一工具被 ⊖ 拿掉时的回调 (toolID), 由调用方从顺序里删掉并重建工具栏。
  var onRemoveTool: ((String) -> Void)?
  /// 某一池中工具被点按加入时的回调 (toolID), 由调用方加进顺序并重建工具栏。
  var onAddTool: ((String) -> Void)?
  /// 拖拽排序后的回调 (新的全部工具 id 顺序), 由调用方保存顺序并重建工具栏。
  /// 面板内已自行调整顺序并刷新, 调用方不需要再 reload。
  var onReorder: (([String]) -> Void)?
  /// 某一菜单格子开关变化时的回调 (tileID, 是否显示), 由调用方写 UserDefaults。
  var onTileToggle: ((String, Bool) -> Void)?
  /// 点"恢复默认"时的回调 (由调用方恢复默认顺序并全部显示, 再刷新列表)。
  var onReset: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 当前工具栏上的工具: (id, 显示名, 图标)。顺序即工具栏上的顺序。
  private var tools: [(id: String, title: String, systemImage: String)] = []

  /// 可选工具池: 注册表里不在工具栏上的工具 (点按加入)。
  private var poolTools: [(id: String, title: String, systemImage: String)] = []

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
    button.setImage(UIImage(systemName: "checkmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default), forImageIn: .normal)
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
    // 常驻编辑模式: 显示右侧拖拽手柄 (排序用), 左侧不显示删除控件
    // (editingStyleForRowAt 返回 .none; 删除用每行自己的 ⊖ 按钮)。
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
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

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

  /// 刷新当前工具 + 工具池 + 菜单格子列表
  func reload(currentTools: [(id: String, title: String, systemImage: String)], poolTools: [(id: String, title: String, systemImage: String)], tiles: [(id: String, title: String, visible: Bool)]) {
    self.tools = currentTools
    self.poolTools = poolTools
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

  /// ⊖ 删除: 把工具从工具栏拿掉 (回工具池)。先本地改状态并刷新,
  /// 再通知调用方保存 (调用方随后 reload, 数据与这里一致)。
  @objc private func removeToolTapped(_ sender: UIButton) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 0,
          tools.indices.contains(indexPath.row) else { return }
    let tool = tools.remove(at: indexPath.row)
    poolTools.append(tool)
    tableView.reloadData()
    onRemoveTool?(tool.id)
  }

  /// 池中工具加入工具栏: 本地先按调用方同一规则改状态 (插在收起键盘前面,
  /// 保证收起键盘仍默认在最右; 没有收起键盘时追加到末尾), 再通知调用方保存。
  private func addTool(at index: Int) {
    guard poolTools.indices.contains(index) else { return }
    let tool = poolTools.remove(at: index)
    if let dismissIndex = tools.firstIndex(where: { $0.id == "dismiss" }) {
      tools.insert(tool, at: dismissIndex)
    } else {
      tools.append(tool)
    }
    tableView.reloadData()
    onAddTool?(tool.id)
  }

  @objc private func addToolTapped(_ sender: UIButton) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 1 else { return }
    addTool(at: indexPath.row)
  }

  /// 菜单格子开关
  @objc private func switchChanged(_ sender: UISwitch) {
    guard let indexPath = indexPath(for: sender), indexPath.section == 2 else { return }
    let tile = tiles[indexPath.row]
    tiles[indexPath.row].visible = sender.isOn
    onTileToggle?(tile.id, sender.isOn)
  }

  /// ⊖ 删除按钮 (红色实心减号, 微信式)。只做删除, 不做显隐开关——
  /// 在栏上就是显示, 拿掉就是隐藏, 不需要第二套开关。
  private func removeButton() -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 22), scale: .default), forImageIn: .normal)
    button.tintColor = .systemRed
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    button.addTarget(self, action: #selector(removeToolTapped(_:)), for: .touchUpInside)
    return button
  }

  /// + 加入按钮 (绿色加号)。点按效果与点按整行相同。
  private func addButton() -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "plus.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 22), scale: .default), forImageIn: .normal)
    button.tintColor = .systemGreen
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    button.addTarget(self, action: #selector(addToolTapped(_:)), for: .touchUpInside)
    return button
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    3
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return tools.isEmpty ? 1 : tools.count
    case 1: return poolTools.isEmpty ? 1 : poolTools.count
    default: return tiles.count
    }
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch section {
    case 0: return "当前工具栏"
    case 1: return "可选工具"
    default: return "菜单格子"
    }
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch section {
    case 0: return "点 ⊖ 把工具拿回工具池; 拖动右侧手柄自由排序"
    case 1: return "点按加入工具栏"
    default: return nil
    }
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "ToolbarToolCell", for: indexPath)
    // 列表是不透明底色, cell 本身透明即可 (透出列表底色, 不透出按键)。
    cell.backgroundColor = .clear
    cell.selectionStyle = .none

    switch indexPath.section {
    case 0:
      guard !tools.isEmpty else {
        var content = cell.defaultContentConfiguration()
        content.text = "工具栏为空, 在下方点按加入工具"
        content.textProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryView = nil
        return cell
      }
      let tool = tools[indexPath.row]
      var content = cell.defaultContentConfiguration()
      content.text = tool.title
      content.image = UIImage(systemName: tool.systemImage)
      content.imageProperties.maximumSize = CGSize(width: 22, height: 22)
      content.imageProperties.tintColor = .label
      cell.contentConfiguration = content
      cell.accessoryView = removeButton()
      return cell
    case 1:
      guard !poolTools.isEmpty else {
        var content = cell.defaultContentConfiguration()
        content.text = "全部工具都已在工具栏上"
        content.textProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryView = nil
        return cell
      }
      let tool = poolTools[indexPath.row]
      var content = cell.defaultContentConfiguration()
      content.text = tool.title
      content.image = UIImage(systemName: tool.systemImage)
      content.imageProperties.maximumSize = CGSize(width: 22, height: 22)
      content.imageProperties.tintColor = .label
      cell.contentConfiguration = content
      cell.accessoryView = addButton()
      return cell
    default:
      let tile = tiles[indexPath.row]
      var content = cell.defaultContentConfiguration()
      content.text = tile.title
      cell.contentConfiguration = content
      let toggle = UISwitch()
      toggle.isOn = tile.visible
      toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
      cell.accessoryView = toggle
      return cell
    }
  }

  /// 只有"当前工具栏"一节可拖拽排序; 工具池 (点按加入) 和菜单格子 (只开关) 不排序。
  func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    indexPath.section == 0 && !tools.isEmpty
  }

  /// 拖拽排序: 调整本地顺序并通知调用方保存。
  /// 目标位置是移动后的最终下标, 有效范围 0...(N-1); 先校验再移动,
  /// 避免非法目标导致工具被删掉。
  func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    guard sourceIndexPath.section == 0, destinationIndexPath.section == 0,
          tools.indices.contains(sourceIndexPath.row),
          destinationIndexPath.row >= 0,
          destinationIndexPath.row < tools.count else { return }
    let tool = tools.remove(at: sourceIndexPath.row)
    tools.insert(tool, at: destinationIndexPath.row)
    onReorder?(tools.map { $0.id })
  }
}

extension KeyboardToolbarCustomizePanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    // 工具池点按整行 = 加入工具栏 (与 + 按钮相同); 占位行 (池空时) 不处理。
    if indexPath.section == 1, !poolTools.isEmpty {
      addTool(at: indexPath.row)
    }
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
