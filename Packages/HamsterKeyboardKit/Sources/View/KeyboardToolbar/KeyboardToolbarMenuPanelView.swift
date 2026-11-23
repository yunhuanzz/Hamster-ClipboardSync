//
//  KeyboardToolbarMenuPanelView.swift
//
//  键盘内功能菜单面板 (仿微信输入法): 全宽面板 + 4 列图标+文字宫格, 不是系统 UIMenu 列表。
//  点格子执行对应功能并关闭面板; 点右上角关闭按钮关闭面板。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 键盘内功能菜单面板: 标题 + 关闭按钮 + 4 列宫格。
/// 格子 (id, 标题, SF Symbol 名) 由调用方传入, 点格子时通过 onSelect 回传 id。
class KeyboardToolbarMenuPanelView: NibLessView {
  /// 点某个格子时的回调 (格子 id), 由调用方执行对应功能并关闭面板。
  var onSelect: ((String) -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 格子: (id, 标题, SF Symbol 名)。由调用方传入。
  private var tiles: [(id: String, title: String, systemImage: String)] = []

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "工具"
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

  /// 宫格容器 (纵向): 每行 4 个格子。
  private lazy var gridStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
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
    addSubview(gridStackView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      gridStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
      gridStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      gridStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      gridStackView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
  }

  override func setupAppearance() {
    // 透明: 面板是盖在键盘根视图上的全屏覆盖层, 透出根视图的背景,
    // 即与键盘本体同一块底色 (浅色/深色模式都一致, 配色方案的渐变/图片也一样透出)。
    // 之前用 .systemBackground, 深色模式是纯黑, 与深灰键盘底色割裂成黑斑。
    backgroundColor = .clear
  }

  /// 刷新格子 (按 4 列分行)。
  func reload(with tiles: [(id: String, title: String, systemImage: String)]) {
    self.tiles = tiles
    gridStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    var rowTiles: [(id: String, title: String, systemImage: String)] = []
    for tile in tiles {
      rowTiles.append(tile)
      if rowTiles.count == 4 {
        gridStackView.addArrangedSubview(makeRow(with: rowTiles))
        rowTiles = []
      }
    }
    if !rowTiles.isEmpty {
      gridStackView.addArrangedSubview(makeRow(with: rowTiles))
    }
  }

  private func makeRow(with tiles: [(id: String, title: String, systemImage: String)]) -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.spacing = 12
    for tile in tiles {
      row.addArrangedSubview(makeTile(tile))
    }
    // 不满 4 个时用空白占位补齐, 保持每列等宽
    while row.arrangedSubviews.count < 4 {
      let spacer = UIView()
      spacer.translatesAutoresizingMaskIntoConstraints = false
      row.addArrangedSubview(spacer)
    }
    return row
  }

  /// 单个格子: 图标在上、文字在下的按钮。
  private func makeTile(_ tile: (id: String, title: String, systemImage: String)) -> UIControl {
    let button = MenuTileButton()
    button.tileID = tile.id
    button.configure(title: tile.title, systemImage: tile.systemImage)
    button.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
    return button
  }

  @objc private func tileTapped(_ sender: MenuTileButton) {
    onSelect?(sender.tileID)
  }

  @objc private func closeTapped() {
    onClose?()
  }
}

/// 菜单格子按钮: 图标在上、文字在下的 UIControl, 点按时有轻微高亮。
private class MenuTileButton: UIControl {
  var tileID: String = ""

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
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 8
    clipsToBounds = true
    let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
    stack.axis = .vertical
    stack.spacing = 6
    stack.alignment = .center
    // 关键: UIStackView 默认可交互, 会盖住整个按钮并在 hit-test 时抢走触摸,
    // 导致按钮永远收不到 touchUpInside (格子点按无反应)。图标/文字本身不可交互,
    // 这里也必须关掉, 触摸才能落到按钮自己身上。
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 60),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 24),
      iconImageView.widthAnchor.constraint(equalToConstant: 24),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, systemImage: String) {
    titleLabel.text = title
    iconImageView.image = UIImage(
      systemName: systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 22)))
  }

  override var isHighlighted: Bool {
    didSet { backgroundColor = isHighlighted ? .secondarySystemBackground : .clear }
  }
}
