//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法, 第 7 轮重写为网格):
//  第 0 节: 当前工具栏——横向一排工具图标 (每个右上角带 ⊖ 红色删除标记,
//    点按拿掉回池里); 长按拖动图标自由排序。
//  第 1 节: 可选工具池——4 列网格 (图标 + 名称), 点按加入工具栏 (追加到末尾)。
//  第 2 节: 菜单格子——2 列开关, 逐个控制菜单宫格里格子的显示/隐藏。
//  右上角 ✓ 关闭; 底部"恢复默认"恢复默认顺序并全部显示。
//  工具注册表共 6 个 (剪贴板/常用语/切换26键·九宫格/立即同步剪贴板/
//  设置/常用语管理; "定制工具栏"本身是入口、不上栏, "收起键盘"是固定按钮、
//  也不上栏), 由调用方 (KeyboardToolbarView) 传入; 面板不自己决定有哪些工具。
//  位置完全由拖动顺序决定 (拖到中间就是中间), 第 5 轮的左/中/右分区
//  模型已取消 (toolbarToolZones 键留着不用, 不删已存数据)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上;
//  内容是可纵向滚动的单个 UICollectionView, 面板只有键盘那么高时
//  工具池也能滚到, 不会被截断 (第 6 轮的问题之一)。
//
//  为什么第 6 轮的面板不像微信 (根因, 见用户图2):
//  1. 它根本就是个 UITableView 列表 (行 = 图标+文字), 不是网格——
//     再怎么调样式也不可能长成微信的图标阵列。
//  2. ⊖ 从没渲染出来: ⊖ 是挂在 cell.accessoryView 上的, 但列表常驻
//     编辑模式 (isEditing = true), 编辑模式下 UIKit 显示的是
//     editingAccessoryView (这里是 nil), 普通 accessoryView 不显示;
//     所以只剩右侧 ≡ 拖动手柄, 用户看不到任何删除入口。
//  3. 工具池那节被截断: 面板只有键盘根视图那么高 (~310pt), 3 节
//     52pt 的行加起来要 ~800pt, 工具池在首屏下面, 没有任何滚到
//     下面去的提示, 用户以为它不存在。
//  拖动实现 (第 7 轮选型): 长按 + UICollectionView 交互式移动
//  (beginInteractiveMovementForItem / updateInteractiveMovementTargetPosition /
//  endInteractiveMovement), 不用 drag & drop 标准 API——交互式移动
//  只需要 moveItemAt 一个数据源方法, 不需要 UIDragItem / NSItemProvider /
//  drop proposal, 在键盘扩展里更稳, 且拖动只在面板内部 (不跨 App),
//  用不到 drag & drop 的跨进程能力。
//

import HamsterUIKit
import UIKit

/// 定制工具栏面板: 标题 + ✓ 关闭 + 当前工具栏 (⊖ 删除/长按拖拽排序) +
/// 可选工具池 (网格点按加入) + 菜单格子开关 + 恢复默认。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一工具被 ⊖ 拿掉时的回调 (toolID), 由调用方从顺序里删掉并重建工具栏。
  var onRemoveTool: ((String) -> Void)?
  /// 某一池中工具被点按加入时的回调 (toolID), 由调用方加进顺序并重建工具栏。
  var onAddTool: ((String) -> Void)?
  /// 拖拽排序后的回调 (新的全部工具 id 顺序), 由调用方保存顺序并重建工具栏。
  /// 面板内已自行调整顺序, 调用方不需要再 reload。
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

  /// 网格: 3 节 (当前工具栏 / 可选工具池 / 菜单格子), 纵向滚动。
  /// 面板只有键盘根视图那么高 (~310pt), 内容超出时靠滚动到达,
  /// 不会被截断; 第 0 节 (当前工具栏) 和第 1 节首行在首屏内。
  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    layout.minimumInteritemSpacing = 12
    layout.minimumLineSpacing = 12
    layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    // 面板本身已是不透明底色, 列表透明即可 (透出面板底色, 不透出按键)。
    collectionView.backgroundColor = .clear
    collectionView.showsVerticalScrollIndicator = true
    collectionView.delaysContentTouches = false
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.register(CurrentToolCell.self, forCellWithReuseIdentifier: CurrentToolCell.reuseIdentifier)
    collectionView.register(PoolToolCell.self, forCellWithReuseIdentifier: PoolToolCell.reuseIdentifier)
    collectionView.register(TileToggleCell.self, forCellWithReuseIdentifier: TileToggleCell.reuseIdentifier)
    collectionView.register(PlaceholderCell.self, forCellWithReuseIdentifier: PlaceholderCell.reuseIdentifier)
    collectionView.register(
      SectionHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: SectionHeaderView.reuseIdentifier)
    // 长按拖动排序 (第 0 节): 交互式移动, 见 handleLongPress。
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    collectionView.addGestureRecognizer(longPress)
    return collectionView
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
    addSubview(collectionView)
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

      collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -8),

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
    collectionView.reloadData()
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func resetTapped() {
    onReset?()
  }

  // MARK: - 长按拖动排序 (第 0 节, 交互式移动)

  /// 长按开始拖动 (只在第 0 节); 移动中更新目标位置; 松手提交;
  /// 其他状态取消。交互式移动不需要 drag & drop 的 item provider,
  /// 拖动只在面板内部, 见文件头选型注释。
  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
            indexPath.section == 0, !tools.isEmpty else { return }
      _ = collectionView.beginInteractiveMovementForItem(at: indexPath)
    case .changed:
      collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: collectionView))
    case .ended:
      collectionView.endInteractiveMovement()
    default:
      collectionView.cancelInteractiveMovement()
    }
  }

  /// ⊖ 删除: 把工具从工具栏拿掉 (回工具池)。先本地改状态并刷新,
  /// 再通知调用方保存 (调用方随后 reload, 数据与这里一致)。
  private func removeTool(id: String) {
    guard let index = tools.firstIndex(where: { $0.id == id }) else { return }
    let tool = tools.remove(at: index)
    poolTools.append(tool)
    collectionView.reloadData()
    onRemoveTool?(tool.id)
  }

  /// 池中工具加入工具栏: 本地先追加到末尾 (收起键盘是固定按钮,
  /// 不在顺序里, 不用再"插在它前面"), 再通知调用方保存。
  private func addTool(at index: Int) {
    guard poolTools.indices.contains(index) else { return }
    let tool = poolTools.remove(at: index)
    tools.append(tool)
    collectionView.reloadData()
    onAddTool?(tool.id)
  }

  /// 网格列数: 第 1 节 4 列, 第 2 节 2 列; 第 0 节是横向一排,
  /// 每格固定 56pt (6 个工具 6x56+5x12=396pt, 在 440pt 栏宽
  /// 减去左右各 16pt 的 sectionInset 后剩 408pt 内, 不换行;
  /// 60pt 的话要 420pt 会折到第二行)。
  private func contentWidth() -> CGFloat {
    let width = collectionView.bounds.width
    return width > 0 ? width : UIScreen.main.bounds.width
  }
}

// MARK: - UICollectionViewDataSource

extension KeyboardToolbarCustomizePanelView: UICollectionViewDataSource {
  func numberOfSections(in collectionView: UICollectionView) -> Int {
    3
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    switch section {
    case 0: return tools.isEmpty ? 1 : tools.count
    case 1: return poolTools.isEmpty ? 1 : poolTools.count
    default: return tiles.count
    }
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    switch indexPath.section {
    case 0:
      guard !tools.isEmpty else {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PlaceholderCell.reuseIdentifier, for: indexPath) as! PlaceholderCell
        cell.configure(text: "工具栏为空, 在下方点按加入工具")
        return cell
      }
      let tool = tools[indexPath.item]
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CurrentToolCell.reuseIdentifier, for: indexPath) as! CurrentToolCell
      cell.configure(title: tool.title, systemImage: tool.systemImage)
      cell.onRemove = { [weak self] in self?.removeTool(id: tool.id) }
      return cell
    case 1:
      guard !poolTools.isEmpty else {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PlaceholderCell.reuseIdentifier, for: indexPath) as! PlaceholderCell
        cell.configure(text: "全部工具都已在工具栏上")
        return cell
      }
      let tool = poolTools[indexPath.item]
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PoolToolCell.reuseIdentifier, for: indexPath) as! PoolToolCell
      cell.configure(title: tool.title, systemImage: tool.systemImage)
      return cell
    default:
      let tile = tiles[indexPath.item]
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TileToggleCell.reuseIdentifier, for: indexPath) as! TileToggleCell
      cell.configure(title: tile.title, isOn: tile.visible)
      cell.onToggle = { [weak self] isOn in self?.onTileToggle?(tile.id, isOn) }
      return cell
    }
  }

  func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
    let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuseIdentifier, for: indexPath) as! SectionHeaderView
    switch indexPath.section {
    case 0: header.configure(title: "当前工具栏")
    case 1: header.configure(title: "可选工具")
    default: header.configure(title: "菜单格子")
    }
    return header
  }

  /// 只有"当前工具栏"一节可拖拽排序; 工具池 (点按加入) 和菜单格子 (只开关) 不排序。
  func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
    indexPath.section == 0 && !tools.isEmpty
  }

  /// 拖拽排序提交: 调整本地顺序并通知调用方保存。
  /// (交互式移动结束时调, 这里不要 reloadData——UIKit 自己处理拖动动画。)
  func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    guard sourceIndexPath.section == 0, destinationIndexPath.section == 0,
          tools.indices.contains(sourceIndexPath.item),
          destinationIndexPath.item >= 0,
          destinationIndexPath.item < tools.count else { return }
    let tool = tools.remove(at: sourceIndexPath.item)
    tools.insert(tool, at: destinationIndexPath.item)
    onReorder?(tools.map { $0.id })
  }
}

// MARK: - UICollectionViewDelegate

extension KeyboardToolbarCustomizePanelView: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)
    // 工具池点按 = 加入工具栏 (与 + 标记相同); 占位行 (池空时) 不处理。
    // 第 0 节点按图标本身无动作 (删除用右上角 ⊖, 排序用长按拖动);
    // 第 2 节用开关, 点按整行无动作。
    if indexPath.section == 1, !poolTools.isEmpty {
      addTool(at: indexPath.item)
    }
  }

  /// 拖动目标限制在第 0 节内: 不允许把工具拖进工具池或菜单格子节。
  func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath, toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
    guard proposedIndexPath.section == 0 else { return originalIndexPath }
    let last = max(tools.count - 1, 0)
    return IndexPath(item: min(proposedIndexPath.item, last), section: 0)
  }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension KeyboardToolbarCustomizePanelView: UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let width = contentWidth()
    let horizontalInset: CGFloat = 32 // sectionInset 左右各 16
    switch indexPath.section {
    case 0:
      // 占位行通栏; 工具格固定 56x72 (6 个 396pt, 见 contentWidth 注释)。
      if tools.isEmpty { return CGSize(width: width - horizontalInset, height: 40) }
      return CGSize(width: 56, height: 72)
    case 1:
      // 占位行通栏; 工具池 4 列。
      if poolTools.isEmpty { return CGSize(width: width - horizontalInset, height: 40) }
      let itemWidth = (width - horizontalInset - 3 * 12) / 4
      return CGSize(width: itemWidth, height: 80)
    default:
      // 菜单格子开关 2 列。
      let itemWidth = (width - horizontalInset - 12) / 2
      return CGSize(width: itemWidth, height: 44)
    }
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
    CGSize(width: contentWidth(), height: 26)
  }
}

// MARK: - 网格 cell

/// 节标题 (13pt 半粗体灰字)。
private class SectionHeaderView: UICollectionReusableView {
  static let reuseIdentifier = "ToolbarCustomizeSectionHeader"

  private let label: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(label)
    NSLayoutConstraint.activate([
      // 与格子左缘对齐 (sectionInset 左 16pt)。
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: trailingAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String) {
    label.text = title
  }
}

/// 当前工具栏格子: 图标 + 名称, 右上角 ⊖ (红色实心减号, 微信式)。
/// 点 ⊖ 拿掉回池; 长按拖动排序 (手势在 collectionView 上, 不在 cell 上)。
private class CurrentToolCell: UICollectionViewCell {
  static let reuseIdentifier = "ToolbarCustomizeCurrentToolCell"

  var onRemove: (() -> Void)?

  private let iconImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .label
    return imageView
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 11)
    label.textColor = .label
    label.textAlignment = .center
    // 56pt 格子放不下 7 字工具名 ("立即同步剪贴板"), 允许折两行。
    label.numberOfLines = 2
    return label
  }()

  private lazy var removeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = .systemRed
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
    return button
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(iconImageView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(removeButton)
    NSLayoutConstraint.activate([
      iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
      iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 28),
      iconImageView.widthAnchor.constraint(equalToConstant: 28),

      titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),

      // ⊖ 钉在格子右上角, 半压在图标角上 (微信式)。
      removeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -2),
      removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 2),
      removeButton.widthAnchor.constraint(equalToConstant: 20),
      removeButton.heightAnchor.constraint(equalToConstant: 20),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, systemImage: String) {
    titleLabel.text = title
    iconImageView.image = UIImage(
      systemName: systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 26)))
  }

  @objc private func removeTapped() {
    onRemove?()
  }
}

/// 工具池格子: 白色圆角底 + 图标 + 名称 + 右上角绿色 + 标记 (点按加入)。
/// 底色随深浅模式自动切换 (与菜单格子 MenuTileButton 同一套颜色)。
private class PoolToolCell: UICollectionViewCell {
  static let reuseIdentifier = "ToolbarCustomizePoolToolCell"

  /// 格子底色: 浅色纯白, 深色半透明白 (≈深灰), 与菜单格子一致。
  private static let tileBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white
  }

  private let iconImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .label
    return imageView
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12)
    label.textColor = .label
    label.textAlignment = .center
    // 7 字工具名 ("立即同步剪贴板") 在 4 列格子里也可能折行, 允许两行。
    label.numberOfLines = 2
    return label
  }()

  private let addBadgeImageView: UIImageView = {
    let imageView = UIImageView(image: UIImage(systemName: "plus.circle.fill"))
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .systemGreen
    return imageView
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.layer.cornerRadius = 10
    contentView.clipsToBounds = true
    contentView.backgroundColor = Self.tileBackgroundColor
    contentView.addSubview(iconImageView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(addBadgeImageView)
    NSLayoutConstraint.activate([
      iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 30),
      iconImageView.widthAnchor.constraint(equalToConstant: 30),

      titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),

      // + 标记钉在格子右上角。
      addBadgeImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      addBadgeImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
      addBadgeImageView.widthAnchor.constraint(equalToConstant: 16),
      addBadgeImageView.heightAnchor.constraint(equalToConstant: 16),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, systemImage: String) {
    titleLabel.text = title
    iconImageView.image = UIImage(
      systemName: systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 28)))
  }
}

/// 菜单格子开关行: 白色圆角底 + 名称 + UISwitch。
private class TileToggleCell: UICollectionViewCell {
  static let reuseIdentifier = "ToolbarCustomizeTileToggleCell"

  var onToggle: ((Bool) -> Void)?

  private static let tileBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white
  }

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14)
    label.textColor = .label
    return label
  }()

  private lazy var toggle: UISwitch = {
    let toggle = UISwitch()
    toggle.translatesAutoresizingMaskIntoConstraints = false
    toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
    return toggle
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.layer.cornerRadius = 10
    contentView.clipsToBounds = true
    contentView.backgroundColor = Self.tileBackgroundColor
    contentView.addSubview(titleLabel)
    contentView.addSubview(toggle)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

      toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, isOn: Bool) {
    titleLabel.text = title
    toggle.isOn = isOn
  }

  @objc private func switchChanged(_ sender: UISwitch) {
    onToggle?(sender.isOn)
  }
}

/// 占位行 (工具栏空 / 工具池空时): 灰色提示文字, 通栏。
private class PlaceholderCell: UICollectionViewCell {
  static let reuseIdentifier = "ToolbarCustomizePlaceholderCell"

  private let label: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(text: String) {
    label.text = text
  }
}
