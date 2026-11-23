//
//  KeyboardToolbarMenuPanelView.swift
//
//  键盘内功能菜单面板 (仿微信输入法): 全宽面板 + 4 列图标+文字宫格, 不是系统 UIMenu 列表。
//  点格子执行对应功能并关闭面板; 点右上角关闭按钮关闭面板。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//  第 7 轮: 格子加到 8 个一页、横向分页 (UIPageControl, 多页时才显示圆点;
//  目前 7 个格子只有 1 页, 圆点隐藏); 格子加高到 68pt、图标 26pt、
//  文字 13pt, 比原来更接近微信功能面板。打开动画 (0.2s 淡入+上滑)
//  在调用方 KeyboardToolbarView.showMenuPanel 里做, 不在这里。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 键盘内功能菜单面板: 标题 + 关闭按钮 + 4 列宫格 (分页)。
/// 格子 (id, 标题, SF Symbol 名) 由调用方传入, 点格子时通过 onSelect 回传 id。
class KeyboardToolbarMenuPanelView: NibLessView {
  /// 点某个格子时的回调 (格子 id), 由调用方执行对应功能并关闭面板。
  var onSelect: ((String) -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 格子: (id, 标题, SF Symbol 名)。由调用方传入。
  private var tiles: [(id: String, title: String, systemImage: String)] = []

  /// 每页格子数: 2 行 x 4 列 = 8。
  private static let tilesPerPage = 8

  /// 覆盖式面板底色: 透明。
  /// 面板是盖在键盘根视图按键区上的覆盖层 (顶贴工具栏底边, 不盖工具栏);
  /// 打开面板时调用方 (KeyboardToolbarView) 会把下面的按键容器隐藏,
  /// 露出键盘根视图自身的底色 (appearance.backgroundStyle),
  /// 与键盘本体绝对是同一块颜色, 不可能再有色差——不要再写死色值
  /// (第 4 轮的 #D5D6DD/#2C2C2C 在真机上比系统键盘灰深, 用户图2)。
  /// 注意: 第 3 轮的透明修法之所以错, 是因为当时没藏按键, 格子浮在
  /// ABC/DEF 键上; 现在按键藏了, 透明才是对的。
  /// 工具栏不藏 (第 7 轮): 格子图标要能再点一下关闭菜单, ⌄ 要能在
  /// 菜单开着时收键盘, 工具栏必须保持可见可点。
  var panelBackgroundColor: UIColor = .clear {
    didSet { backgroundColor = panelBackgroundColor }
  }

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

  /// 分页滚动容器: 每页一个 4 列宫格, 横向滑动换页。
  private lazy var pagingScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.isPagingEnabled = true
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    return scrollView
  }()

  /// 各页横向排列 (每页宽 = 滚动容器宽)。
  private lazy var pagesStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 页点: 只有多页时显示 (目前 7 个格子 = 1 页, 隐藏)。
  private lazy var pageControl: UIPageControl = {
    let control = UIPageControl()
    control.translatesAutoresizingMaskIntoConstraints = false
    control.currentPageIndicatorTintColor = .secondaryLabel
    control.pageIndicatorTintColor = .tertiaryLabel
    control.addTarget(self, action: #selector(pageControlChanged(_:)), for: .valueChanged)
    return control
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
    addSubview(pagingScrollView)
    pagingScrollView.addSubview(pagesStackView)
    addSubview(pageControl)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      pagingScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
      pagingScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      pagingScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      pagingScrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),

      pageControl.leadingAnchor.constraint(equalTo: leadingAnchor),
      pageControl.trailingAnchor.constraint(equalTo: trailingAnchor),
      pageControl.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
      pageControl.heightAnchor.constraint(equalToConstant: 20),

      // 横向分页的标准约束: 内容栈贴 contentLayoutGuide,
      // 高度等于 frame 高度 (每页高与容器同高)。
      pagesStackView.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
      pagesStackView.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
      pagesStackView.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
      pagesStackView.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
      pagesStackView.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  override func setupAppearance() {
    // 透明: 面板打开时下面的按键容器被隐藏 (见 KeyboardToolbarView
    // hideKeyboardContentForOverlayPanel), 露出的是键盘根视图自身的底色,
    // 与键盘本体同一块颜色; 深色模式同样成立 (根视图底色随外观走)。
    // 工具栏不藏 (在面板上方保持可见可点), 见 panelBackgroundColor 注释。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新格子 (按 4 列分行, 每 8 个一页)。
  func reload(with tiles: [(id: String, title: String, systemImage: String)]) {
    self.tiles = tiles
    // 旧页必须先从 arrangedSubviews 里摘掉再移出层级: 只调
    // removeFromSuperview 不会把它从 arrangedSubviews 摘掉, 旧页的约束
    // (页宽 == 滚动容器宽) 会残留, 下次 reload 再加一页就多一套,
    // pageControl 的页数也会数上已删的旧页。
    pagesStackView.arrangedSubviews.forEach {
      pagesStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    var pageTiles: [(id: String, title: String, systemImage: String)] = []
    for tile in tiles {
      pageTiles.append(tile)
      if pageTiles.count == Self.tilesPerPage {
        addPage(with: pageTiles)
        pageTiles = []
      }
    }
    if !pageTiles.isEmpty {
      addPage(with: pageTiles)
    }
    let pageCount = max(pagesStackView.arrangedSubviews.count, 1)
    pageControl.numberOfPages = pageCount
    // 只有多页时显示圆点; 单页时留 20pt 空位 (与多页时对齐, 不跳动)。
    pageControl.isHidden = pageCount <= 1
    pageControl.currentPage = 0
    pagingScrollView.setContentOffset(.zero, animated: false)
  }

  /// 建一页并挂进横向内容栈。页宽约束必须在 addArrangedSubview 之后
  /// 再激活: 之前 makePage 里在页还没进层级时就激活
  /// page.width == pagingScrollView.frameLayoutGuide.width,
  /// 两边没有共同祖先, UIKit 在激活时直接抛 NSException
  /// (-[NSLayoutConstraint _setActive:mutuallyExclusiveConstraints:]),
  /// 点菜单格子图标就闪退 (第 8 轮崩溃日志根因, 连续崩 4 次)。
  /// 挂进栈之后页的祖先链是 page -> pagesStackView -> pagingScrollView,
  /// 与 frameLayoutGuide 有共同祖先 pagingScrollView, 可以正常安装。
  private func addPage(with tiles: [(id: String, title: String, systemImage: String)]) {
    let page = makePage(with: tiles)
    pagesStackView.addArrangedSubview(page)
    page.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor).isActive = true
  }

  /// 一页宫格 (2 行 x 4 列): 宽 = 滚动容器宽, 高与容器同高。
  private func makePage(with tiles: [(id: String, title: String, systemImage: String)]) -> UIView {
    let page = UIView()
    page.translatesAutoresizingMaskIntoConstraints = false
    // 注意: 页宽约束不在这里激活 (见 addPage 注释): 页还没进层级时激活
    // 会因没有共同祖先而抛异常导致闪退。
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    page.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: page.topAnchor),
      stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor),
    ])
    var rowTiles: [(id: String, title: String, systemImage: String)] = []
    for tile in tiles {
      rowTiles.append(tile)
      if rowTiles.count == 4 {
        stack.addArrangedSubview(makeRow(with: rowTiles))
        rowTiles = []
      }
    }
    if !rowTiles.isEmpty {
      stack.addArrangedSubview(makeRow(with: rowTiles))
    }
    return page
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

  @objc private func pageControlChanged(_ sender: UIPageControl) {
    let x = CGFloat(sender.currentPage) * pagingScrollView.bounds.width
    pagingScrollView.setContentOffset(CGPoint(x: x, y: 0), animated: true)
  }
}

extension KeyboardToolbarMenuPanelView: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView.bounds.width > 0 else { return }
    pageControl.currentPage = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
  }
}

/// 菜单格子按钮: 图标在上、文字在下的 UIControl, 点按时有轻微高亮。
/// 每个格子自带淡淡的圆角矩形底 (仿微信白格子): 浅色模式偏白、深色模式偏深灰,
/// 不硬编码黑/白, 深色模式也不会出现黑斑。
private class MenuTileButton: UIControl {
  var tileID: String = ""

  /// 格子底色 (随深浅模式自动切换): 浅色纯白, 深色半透明白 (≈深灰)。
  private static let tileBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white
  }

  /// 点按高亮色: 浅色浅灰、深色更深一档, 在格子底色上能看出按下反馈。

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
    label.font = .systemFont(ofSize: 13)
    label.textColor = .label
    label.textAlignment = .center
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 10
    clipsToBounds = true
    backgroundColor = Self.tileBackgroundColor
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
    // 格子高 68pt 是期望值, 不是硬性: 面板矮时 (小屏/横屏) 两行 68pt +
    // 16pt 间距会超过滚动容器高; 约束用 defaultHigh 让格子可压缩,
    // 避免“无法同时满足约束”的警告, 内容 (26pt 图标 + 13pt 文字) 最低约 53pt,
    // 压不到裁切。
    let tileHeightConstraint = heightAnchor.constraint(equalToConstant: 68)
    tileHeightConstraint.priority = .defaultHigh
    NSLayoutConstraint.activate([
      tileHeightConstraint,
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String, systemImage: String) {
    titleLabel.text = title
    iconImageView.image = UIImage(
      systemName: systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 24)))
  }

  override var isHighlighted: Bool {
    didSet {
      backgroundColor = isHighlighted ? .secondarySystemBackground : Self.tileBackgroundColor
    }
  }
}
