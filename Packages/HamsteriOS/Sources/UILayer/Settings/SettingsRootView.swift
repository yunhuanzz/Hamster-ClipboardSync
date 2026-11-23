//
//  SettingsRootView.swift
//
//  设置首页 (仿微信输入法): 浅绿底 + 两列卡片宫格, 每卡图标 + 标题 + 一行小字说明。
//  卡片只进真实存在的子页 (没有的功能不做假卡片):
//  布局和显示 / 按键效果 / 键盘管理 / 定制工具栏 / 跨设备粘贴传送 /
//  常用语 / 我的词组 / 输入方案设置 / Wi-Fi上传方案 / 文件管理 /
//  键盘设置 / 键盘配色 / iCloud同步 / 软件备份 / RIME / 关于。
//  顶部是收藏的快捷操作 (重新部署 / RIME同步 / 应用备份, 点按执行, 长按移除),
//  添加入口在 RIME/备份子页的按钮长按菜单里 (ButtonTableViewCell, 未动)。
//  旧的 inline 表格 (含剪贴板同步一节) 已拆走: 同步设置在"跨设备粘贴传送"子页。
//

import Combine
import HamsterUIKit
import UIKit

public class SettingsRootView: NibLessView {
  // MARK: properties

  let settingsViewModel: SettingsViewModel
  let rimeViewModel: RimeViewModel
  let backupViewModel: BackupViewModel

  /// 浅绿底 (仿微信设置首页): 浅色模式淡绿, 深色模式用系统背景。
  private static let homeBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.systemBackground
      : UIColor(red: 0.92, green: 0.96, blue: 0.93, alpha: 1)
  }

  /// 卡片底色: 浅色白、深色用二级系统背景 (卡片按钮类也用, 所以是 internal)。
  static let cardBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.secondarySystemBackground
      : UIColor.white
  }

  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  private lazy var contentStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 快捷操作区 (收藏的按钮): 横向滚动的一排药丸按钮, 有收藏时才显示。
  private lazy var quickRowScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  private lazy var quickRowStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private lazy var quickRowLabel: UILabel = {
    let label = UILabel()
    label.text = "快捷操作 (长按移除)"
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 当前展示的快捷操作按钮 (与 quickRowStackView 的子视图一一对应)。
  private var favoriteButtonItems: [SettingItemModel] = []

  private var subscriptions = Set<AnyCancellable>()

  /// 卡片: (图标, 图标色, 标题, 一行小字说明, 点按动作)。
  private var cards: [(icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)] {
    // 已有入口: 复用 sections 里对应项的图标与跳转动作 (不另写一份)。
    let navItems = settingsViewModel.sections.flatMap { $0.items }
    func navItem(_ text: String) -> SettingItemModel? {
      navItems.first { $0.text == text }
    }
    func card(_ text: String, tint: UIColor, subtitle: String) -> (icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)? {
      guard let item = navItem(text), let action = item.navigationAction else { return nil }
      return (icon: item.icon, tint: tint, title: text, subtitle: subtitle, action: action)
    }

    var result: [(icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)] = []
    // 新卡片 (子页是本轮新增/新接线的)。
    result.append((icon: UIImage(systemName: "textformat.size"), tint: .systemBlue, title: "布局和显示", subtitle: "候选字大小、拼音显示等", action: { [unowned self] in settingsViewModel.navigate(to: .layoutDisplay) }))
    result.append((icon: UIImage(systemName: "slider.horizontal.3"), tint: .systemPurple, title: "定制工具栏", subtitle: "工具显示、排序、菜单格子", action: { [unowned self] in settingsViewModel.navigate(to: .toolbarSettings) }))
    result.append((icon: UIImage(systemName: "keyboard"), tint: .systemGreen, title: "键盘管理", subtitle: "九宫格、全键盘", action: { [unowned self] in settingsViewModel.navigate(to: .keyboardManagement) }))
    result.append((icon: UIImage(systemName: "doc.on.clipboard"), tint: .systemTeal, title: "跨设备粘贴传送", subtitle: "剪贴板同步到电脑", action: { [unowned self] in settingsViewModel.navigate(to: .clipboardSync) }))
    // 已有入口的卡片 (图标与跳转复用 sections)。
    if let c = card("按键音与震动", tint: .systemOrange, subtitle: "按键音、触感、按键气泡") { result.append(c) }
    if let c = card("常用语", tint: .systemPink, subtitle: "管理常用语") { result.append(c) }
    if let c = card("我的词组", tint: .systemIndigo, subtitle: "自定义词组") { result.append(c) }
    if let c = card("输入方案设置", tint: .systemYellow, subtitle: "雾凇拼音、方案管理") { result.append(c) }
    if let c = card("Wi-Fi上传方案", tint: .systemBlue, subtitle: "上传输入方案") { result.append(c) }
    if let c = card("文件管理", tint: .systemOrange, subtitle: "浏览方案文件") { result.append(c) }
    if let c = card("键盘设置", tint: .systemGray, subtitle: "按键、划动、候选栏等") { result.append(c) }
    if let c = card("键盘配色", tint: .systemPink, subtitle: "键盘颜色方案") { result.append(c) }
    if let c = card("iCloud同步", tint: .systemBlue, subtitle: "用 iCloud 同步配置") { result.append(c) }
    if let c = card("软件备份", tint: .systemPurple, subtitle: "备份与恢复") { result.append(c) }
    if let c = card("RIME", tint: .systemRed, subtitle: "部署、同步、词库") { result.append(c) }
    if let c = card("关于", tint: .systemGray, subtitle: "版本与开源") { result.append(c) }
    return result
  }

  // MARK: method

  init(frame: CGRect = .zero, settingsViewModel: SettingsViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.settingsViewModel = settingsViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel

    super.init(frame: frame)

    setupView()
    combine()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func setupView() {
    backgroundColor = Self.homeBackgroundColor
    constructViewHierarchy()
    activateViewConstraints()
    buildCardGrid()
  }

  override public func constructViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(contentStackView)
    contentStackView.addArrangedSubview(quickRowLabel)
    contentStackView.addArrangedSubview(quickRowScrollView)
    quickRowScrollView.addSubview(quickRowStackView)
  }

  override public func activateViewConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

      contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

      quickRowScrollView.heightAnchor.constraint(equalToConstant: 36),
      quickRowStackView.topAnchor.constraint(equalTo: quickRowScrollView.contentLayoutGuide.topAnchor),
      quickRowStackView.bottomAnchor.constraint(equalTo: quickRowScrollView.contentLayoutGuide.bottomAnchor),
      quickRowStackView.leadingAnchor.constraint(equalTo: quickRowScrollView.contentLayoutGuide.leadingAnchor),
      quickRowStackView.trailingAnchor.constraint(equalTo: quickRowScrollView.contentLayoutGuide.trailingAnchor),
      quickRowStackView.heightAnchor.constraint(equalTo: quickRowScrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  /// 按两列搭卡片宫格 (每行两个卡片, 不满两个时补空白占位)。
  private func buildCardGrid() {
    var rowCards: [(icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)] = []
    for card in cards {
      rowCards.append(card)
      if rowCards.count == 2 {
        contentStackView.addArrangedSubview(makeCardRow(with: rowCards))
        rowCards = []
      }
    }
    if !rowCards.isEmpty {
      contentStackView.addArrangedSubview(makeCardRow(with: rowCards))
    }
  }

  private func makeCardRow(with cards: [(icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)]) -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.spacing = 12
    for card in cards {
      row.addArrangedSubview(makeCardButton(card))
    }
    // 不满 2 个时用空白占位补齐, 保持每列等宽
    while row.arrangedSubviews.count < 2 {
      let spacer = UIView()
      spacer.translatesAutoresizingMaskIntoConstraints = false
      row.addArrangedSubview(spacer)
    }
    return row
  }

  /// 单个卡片: 图标 + 标题 + 一行小字说明 (纵向)。
  private func makeCardButton(_ card: (icon: UIImage?, tint: UIColor, title: String, subtitle: String, action: () -> Void)) -> UIControl {
    let button = SettingsHomeCardButton()
    button.configure(icon: card.icon, tint: card.tint, title: card.title, subtitle: card.subtitle)
    button.onTap = card.action
    button.heightAnchor.constraint(equalToConstant: 100).isActive = true
    return button
  }

  func combine() {
    // 收藏按钮变化时刷新快捷操作行 (添加/删除都走这里)。
    UserDefaults.favoriteButtonSubject
      .eraseToAnyPublisher()
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] favoriteButtons in
        self.reloadFavoriteButtonsRow(with: favoriteButtons)
      }
      .store(in: &subscriptions)

    settingsViewModel.tableReloadPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] _ in
        tableReload()
      }
      .store(in: &subscriptions)
  }

  /// 刷新快捷操作行 (点按执行, 长按移除)。无收藏时整行隐藏。
  private func reloadFavoriteButtonsRow(with favoriteButtons: [FavoriteButton]? = nil) {
    let buttons = favoriteButtons ?? UserDefaults.standard.getFavoriteButtons()
    favoriteButtonItems = settingsViewModel.getFavoriteButtons(buttons: buttons)
    quickRowStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for item in favoriteButtonItems {
      let button = UIButton(type: .system)
      button.setTitle(item.text, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
      button.backgroundColor = Self.cardBackgroundColor
      button.layer.cornerRadius = 18
      button.clipsToBounds = true
      button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalToConstant: 36).isActive = true
      button.addTarget(self, action: #selector(favoriteButtonTapped(_:)), for: .touchUpInside)
      let longPress = UILongPressGestureRecognizer(target: self, action: #selector(favoriteButtonLongPressed(_:)))
      button.addGestureRecognizer(longPress)
      quickRowStackView.addArrangedSubview(button)
    }
    let hasFavorites = !favoriteButtonItems.isEmpty
    quickRowLabel.isHidden = !hasFavorites
    quickRowScrollView.isHidden = !hasFavorites
  }

  @objc private func favoriteButtonTapped(_ sender: UIButton) {
    guard let index = quickRowStackView.arrangedSubviews.firstIndex(of: sender),
          favoriteButtonItems.indices.contains(index),
          let action = favoriteButtonItems[index].buttonAction else { return }
    Task {
      try? await action()
    }
  }

  /// 长按快捷操作按钮: 弹出菜单, 可从快捷区域移除 (与旧表格长按菜单同一行为)。
  @objc private func favoriteButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began,
          let button = gesture.view as? UIButton,
          let index = quickRowStackView.arrangedSubviews.firstIndex(of: button),
          favoriteButtonItems.indices.contains(index),
          let favoriteButton = favoriteButtonItems[index].favoriteButton else { return }
    let alert = UIAlertController(title: favoriteButtonItems[index].text, message: "从快捷区域移除?", preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "移除", style: .destructive) { _ in
      UserDefaults.standard.removeFavoriteButton(button: favoriteButton)
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    // actionSheet 在 iPad 上需要 anchor。
    if let popover = alert.popoverPresentationController {
      popover.sourceView = button
      popover.sourceRect = button.bounds
    }
    window?.rootViewController?.present(alert, animated: true)
  }
}

// MARK: override UIView

public extension SettingsRootView {
  func tableReload() {
    reloadFavoriteButtonsRow()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if let _ = window {
      tableReload()
    }
  }
}

/// 设置首页卡片按钮: 图标在上、标题 + 一行小字说明在下, 点按时轻微变暗。
private class SettingsHomeCardButton: UIControl {
  var onTap: (() -> Void)?

  private let iconImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    return imageView
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.numberOfLines = 1
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 12
    clipsToBounds = true
    backgroundColor = SettingsRootView.cardBackgroundColor
    let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 4
    stack.alignment = .leading
    // 图标/文字本身不可交互, 关掉后触摸才能落到按钮自己身上。
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),
    ])
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(icon: UIImage?, tint: UIColor, title: String, subtitle: String) {
    iconImageView.image = icon?.withRenderingMode(.alwaysTemplate)
    iconImageView.tintColor = tint
    titleLabel.text = title
    subtitleLabel.text = subtitle
  }

  @objc private func tapped() {
    onTap?()
  }

  override var isHighlighted: Bool {
    didSet {
      // 点按时轻微变暗 (用 systemFill, 深浅模式都看得出)。
      backgroundColor = isHighlighted ? .systemFill : SettingsRootView.cardBackgroundColor
    }
  }
}
