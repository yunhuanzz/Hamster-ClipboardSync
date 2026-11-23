
//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法, 第 10 轮重写为微信式):
//  顶部: 标题 + 绿色 ✓ 关闭 (微信的 ✓ 是绿的)。
//  上半: 当前工具栏——一排小图标 (左侧组 + 分隔线 + 右侧组),
//    每个右上角带 ⊖ 红色删除标记, 点按拿掉回池里;
//    长按拖动图标自由排序, 也可拖过中线换到另一侧 (第 9 轮左右分区保留)。
//  下半: 可选工具池——小图标宫格, 4 列, 左右翻页滑动 (UIPageControl 页点),
//    点按加入工具栏 (进左侧末尾)。
//  底部: "恢复默认"。
//  没有上下滚动: 内容按行排布, 工具池按页高自适应 (1 行/2 行);
//  面板矮时 (小屏/横屏) 池高约束可压缩, 不报无法满足约束的警告
//  (与菜单面板 MenuTileButton 的 defaultHigh 格子高同理)。
//  工具注册表共 6 个 (剪贴板/常用语/切换26键·九宫格/立即同步剪贴板/
//  设置/常用语管理; "定制工具栏"本身是入口、不上栏, "收起键盘"是固定按钮、
//  也不上栏), 由调用方 (KeyboardToolbarView) 传入; 面板不自己决定有哪些工具。
//  菜单格子开关 (第 10 轮已删): 7 个菜单格子永远全部显示, 面板里不再有
//  开关, reload 也没有 tiles 参数; 旧的 TileToggleCell / onTileToggle /
//  customizeTiles() 一并删除。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//
//  拖动实现 (上半当前工具栏): 长按 + 手动换位, 不用 UICollectionView
//  交互式移动——这里只有一排图标, 两组 (左/右) 各是一个 UIStackView,
//  手动在栈之间移动视图更直接, 算法与工具栏本体的长按拖动
//  (KeyboardToolbarView.toolbarToolLongPressed) 完全一致:
//  手指在哪半区、工具就进哪侧容器, 组内位置按其余按钮中点为界;
//  拖动时关掉横向滚动, 松手后按栈内实际排列回传 onReorder。
//  工具池分页复用菜单面板的横向分页模式 (UIScrollView + pagesStackView +
//  UIPageControl): 页宽约束必须在 addArrangedSubview 之后再激活,
//  否则没有共同祖先会抛异常闪退 (第 8 轮崩溃根因)。
//

import HamsterUIKit
import UIKit

/// 定制工具栏面板: 标题 + 绿色 ✓ 关闭 + 当前工具栏小图标行
/// (⊖ 删除/长按拖拽排序/拖过中线换侧) + 可选工具池小图标宫格
/// (左右翻页 + 页点, 点按加入) + 恢复默认。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一工具被 ⊖ 拿掉时的回调 (toolID), 由调用方从顺序里删掉并重建工具栏。
  var onRemoveTool: ((String) -> Void)?
  /// 某一池中工具被点按加入时的回调 (toolID), 由调用方加进顺序并重建工具栏。
  var onAddTool: ((String) -> Void)?
  /// 拖拽排序/换侧后的回调 (新的左侧 id 顺序, 新的右侧 id 顺序),
  /// 面板内已自行调整顺序并刷新, 这里只保存新布局并重建工具栏。
  /// 调用方不需要再 reload。
  var onReorder: (([String], [String]) -> Void)?
  /// 点"恢复默认"时的回调 (由调用方恢复默认顺序并全部显示, 再刷新列表)。
  var onReset: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 工具元组 (id, 显示名, 图标)。
  private typealias Tool = (id: String, title: String, systemImage: String)

  /// 工具栏左侧的工具: (id, 显示名, 图标)。顺序即栏上左侧顺序。
  private var leftTools: [Tool] = []

  /// 工具栏右侧的工具: (id, 显示名, 图标)。顺序即栏上右侧顺序。
  private var rightTools: [Tool] = []

  /// 可选工具池: 注册表里不在工具栏上的工具 (点按加入, 进左侧末尾)。
  private var poolTools: [Tool] = []

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 注意: 不能用 .clear——第 3 轮的透明修法是错的, 面板是全屏覆盖层,
  /// 透明底会让键盘按键从列表后面透出来。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
    }
  }

  /// 每页格子数: 2 行 x 4 列 = 8 (池里最多 6 个工具, 现在只有 1 页)。
  private static let poolToolsPerPage = 8
  /// 每页每行格子数。
  private static let poolColumns = 4
  /// 小图标格高 (当前工具栏格子与工具池格子同高)。
  private static let toolCellHeight: CGFloat = 62

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "定制工具栏"
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// ✓ 关闭: 微信的 ✓ 是绿的, 这里也用绿色 (第 10 轮)。
  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "checkmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .systemGreen
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  private lazy var toolbarSectionLabel: UILabel = {
    let label = UILabel()
    label.text = "工具栏"
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 当前工具栏横向滚动容器 (6 个工具一排正好放下, 超宽时可横滑)。
  private lazy var currentScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.delaysContentTouches = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  /// 当前工具栏内容: 左组 + 分隔线 + 右组 (横向一排)。
  private lazy var currentStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 左侧组 (横向一排小图标)。
  private lazy var leftStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 右侧组 (横向一排小图标)。
  private lazy var rightStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  /// 左右组之间的分隔线。
  private lazy var sideDividerView: UIView = {
    let view = UIView()
    view.backgroundColor = .separator
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var poolSectionLabel: UILabel = {
    let label = UILabel()
    label.text = "可选工具"
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 工具池分页滚动容器: 每页一个 4 列宫格, 横向滑动换页。
  private lazy var pagingScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.isPagingEnabled = true
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.delaysContentTouches = false
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

  /// 工具池为空时的提示 (代替分页容器)。
  private lazy var poolEmptyLabel: UILabel = {
    let label = UILabel()
    label.text = "全部工具都已在工具栏上"
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 页点: 只有多页时显示 (目前池里最多 6 个工具 = 1 页, 隐藏)。
  /// 单页时高度压到 0 (不留空位)。
  private lazy var pageControl: UIPageControl = {
    let control = UIPageControl()
    control.translatesAutoresizingMaskIntoConstraints = false
    control.currentPageIndicatorTintColor = .secondaryLabel
    control.pageIndicatorTintColor = .tertiaryLabel
    control.addTarget(self, action: #selector(pageControlChanged(_:)), for: .valueChanged)
    return control
  }()

  private var poolHeightConstraint: NSLayoutConstraint?
  private var poolEmptyHeightConstraint: NSLayoutConstraint?
  private var pageControlHeightConstraint: NSLayoutConstraint?

  /// 拖动中的工具格 (长按拖动时)。
  private var draggedToolView: CurrentToolView?
  /// 本次长按是否真的拖动过 (只原地长按松手不算拖动, 不回传 onReorder)。
  private var toolbarDragMoved = false
  /// 本次长按起始 x (currentStackView 坐标系)。
  private var toolbarDragStartX: CGFloat = 0

  private lazy var resetButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("恢复默认", for: .normal)
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
    addSubview(toolbarSectionLabel)
    addSubview(currentScrollView)
    currentScrollView.addSubview(currentStackView)
    currentStackView.addArrangedSubview(leftStackView)
    currentStackView.addArrangedSubview(sideDividerView)
    currentStackView.addArrangedSubview(rightStackView)
    addSubview(poolSectionLabel)
    addSubview(pagingScrollView)
    pagingScrollView.addSubview(pagesStackView)
    addSubview(poolEmptyLabel)
    addSubview(pageControl)
    addSubview(resetButton)
    // 当前工具栏长按拖动排序/换侧 (见 handleCurrentLongPress)。
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCurrentLongPress(_:)))
    currentScrollView.addGestureRecognizer(longPress)
  }

  override func activateViewConstraints() {
    poolHeightConstraint = pagingScrollView.heightAnchor.constraint(equalToConstant: Self.toolCellHeight)
    // 面板矮时池高可压缩 (defaultHigh), 不报无法满足约束的警告;
    // 压掉的是第二行格子的高度, 第一行不受影响。
    poolHeightConstraint?.priority = .defaultHigh
    poolEmptyHeightConstraint = poolEmptyLabel.heightAnchor.constraint(equalToConstant: 0)
    pageControlHeightConstraint = pageControl.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      toolbarSectionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      toolbarSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      currentScrollView.topAnchor.constraint(equalTo: toolbarSectionLabel.bottomAnchor, constant: 6),
      currentScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      currentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      currentScrollView.heightAnchor.constraint(equalToConstant: Self.toolCellHeight),

      // 横向滚动容器的标准约束: 内容栈贴 contentLayoutGuide,
      // 高度等于 frame 高度 (一排小图标)。
      currentStackView.topAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.topAnchor),
      currentStackView.bottomAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.bottomAnchor),
      currentStackView.leadingAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.leadingAnchor),
      currentStackView.trailingAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.trailingAnchor),
      currentStackView.heightAnchor.constraint(equalTo: currentScrollView.frameLayoutGuide.heightAnchor),

      sideDividerView.widthAnchor.constraint(equalToConstant: 1),
      sideDividerView.heightAnchor.constraint(equalToConstant: 40),

      poolSectionLabel.topAnchor.constraint(equalTo: currentScrollView.bottomAnchor, constant: 10),
      poolSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      pagingScrollView.topAnchor.constraint(equalTo: poolSectionLabel.bottomAnchor, constant: 6),
      pagingScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      pagingScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      poolHeightConstraint!,

      poolEmptyLabel.topAnchor.constraint(equalTo: pagingScrollView.bottomAnchor),
      poolEmptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      poolEmptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      poolEmptyHeightConstraint!,

      // 横向分页的标准约束: 内容栈贴 contentLayoutGuide,
      // 高度等于 frame 高度 (每页高与容器同高)。
      pagesStackView.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
      pagesStackView.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
      pagesStackView.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
      pagesStackView.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
      pagesStackView.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),

      pageControl.topAnchor.constraint(equalTo: poolEmptyLabel.bottomAnchor, constant: 4),
      pageControl.leadingAnchor.constraint(equalTo: leadingAnchor),
      pageControl.trailingAnchor.constraint(equalTo: trailingAnchor),
      pageControlHeightConstraint!,

      resetButton.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 8),
      resetButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      resetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      resetButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
      resetButton.heightAnchor.constraint(equalToConstant: 36),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来 (第 3 轮改成 .clear 是错的)。
    // 深色模式下底色是深灰 (#2C2C2C), 不是纯黑, 所以不会再出现黑斑。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新左/右侧工具 + 工具池。
  /// 注意: 参数写完整元组类型, 不用上面私有的 Tool 别名——reload 是
  /// 跨文件调用的内部方法, 签名里用私有别名编译不过。
  func reload(leftTools: [(id: String, title: String, systemImage: String)], rightTools: [(id: String, title: String, systemImage: String)], poolTools: [(id: String, title: String, systemImage: String)]) {
    self.leftTools = leftTools
    self.rightTools = rightTools
    self.poolTools = poolTools
    rebuildCurrentStrip()
    rebuildPoolPages()
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func resetTapped() {
    onReset?()
  }

  @objc private func pageControlChanged(_ sender: UIPageControl) {
    let x = CGFloat(sender.currentPage) * pagingScrollView.bounds.width
    pagingScrollView.setContentOffset(CGPoint(x: x, y: 0), animated: true)
  }

  // MARK: - 当前工具栏 (上半: 小图标行)

  /// 按 leftTools/rightTools 重建两组小图标行 (含空组占位文字)。
  private func rebuildCurrentStrip() {
    for stack in [leftStackView, rightStackView] {
      stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
    for tool in leftTools {
      leftStackView.addArrangedSubview(makeCurrentToolView(tool))
    }
    for tool in rightTools {
      rightStackView.addArrangedSubview(makeCurrentToolView(tool))
    }
    refreshSidePlaceholders()
  }

  private func makeCurrentToolView(_ tool: Tool) -> CurrentToolView {
    let view = CurrentToolView(tool: tool)
    view.onRemove = { [weak self] in self?.removeTool(id: tool.id) }
    return view
  }

  /// 空组显示占位文字 ("左侧暂无工具" / "右侧暂无工具"), 有工具时去掉。
  private func refreshSidePlaceholders() {
    refreshSidePlaceholder(in: leftStackView, text: "左侧暂无工具")
    refreshSidePlaceholder(in: rightStackView, text: "右侧暂无工具")
  }

  private func refreshSidePlaceholder(in stack: UIStackView, text: String) {
    let hasTool = stack.arrangedSubviews.contains { $0 is CurrentToolView }
    let placeholder = stack.arrangedSubviews.compactMap { $0 as? UILabel }.first
    if hasTool {
      if let placeholder {
        stack.removeArrangedSubview(placeholder)
        placeholder.removeFromSuperview()
      }
    } else if placeholder == nil {
      let label = UILabel()
      label.text = text
      label.font = .systemFont(ofSize: 12)
      label.textColor = .secondaryLabel
      label.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(label)
    }
  }

  /// 某侧栈里的工具格 (按栈内顺序)。
  private func toolViews(in stack: UIStackView) -> [CurrentToolView] {
    stack.arrangedSubviews.compactMap { $0 as? CurrentToolView }
  }

  /// 按两组栈内实际排列回写 leftTools/rightTools。
  private func syncToolsFromStacks() {
    leftTools = toolViews(in: leftStackView).map { $0.tool }
    rightTools = toolViews(in: rightStackView).map { $0.tool }
  }

  /// ⊖ 删除: 把工具从工具栏拿掉 (回工具池)。先本地改状态并刷新,
  /// 再通知调用方保存 (调用方随后 reload, 数据与这里一致)。
  private func removeTool(id: String) {
    if let index = leftTools.firstIndex(where: { $0.id == id }) {
      let tool = leftTools.remove(at: index)
      poolTools.append(tool)
    } else if let index = rightTools.firstIndex(where: { $0.id == id }) {
      let tool = rightTools.remove(at: index)
      poolTools.append(tool)
    } else {
      return
    }
    rebuildCurrentStrip()
    rebuildPoolPages()
    onRemoveTool?(id)
  }

  /// 池中工具加入工具栏: 本地先追加到左侧末尾 (默认左, 调用方也按左保存),
  /// 再通知调用方保存。
  private func addTool(id: String) {
    guard let index = poolTools.firstIndex(where: { $0.id == id }) else { return }
    let tool = poolTools.remove(at: index)
    leftTools.append(tool)
    rebuildCurrentStrip()
    rebuildPoolPages()
    onAddTool?(tool.id)
  }

  // MARK: - 当前工具栏长按拖动排序/换侧

  /// 长按开始拖动 (只在工具格上); 移动中更新目标位置 (可跨组换侧);
  /// 松手提交; 其他状态取消。算法与工具栏本体
  /// (KeyboardToolbarView.toolbarToolLongPressed) 一致:
  /// 手指在哪半区、工具就进哪侧容器, 组内位置按其余格子中点为界。
  /// 拖动时关掉横向滚动, 免得滚动手势抢走手指。
  @objc private func handleCurrentLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      let point = gesture.location(in: currentStackView)
      guard let hitView = currentStackView.hitTest(point, with: nil),
            let toolView = ancestorToolView(of: hitView),
            draggedToolView == nil else { return }
      draggedToolView = toolView
      toolbarDragMoved = false
      toolbarDragStartX = point.x
      currentScrollView.isScrollEnabled = false
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      UIView.animate(withDuration: 0.15) {
        toolView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        toolView.alpha = 0.85
      }
    case .changed:
      guard let toolView = draggedToolView else { return }
      let x = gesture.location(in: currentStackView).x
      if abs(x - toolbarDragStartX) > 12 { toolbarDragMoved = true }
      guard toolbarDragMoved else { return }
      // 手指在哪半区, 工具就进哪侧容器 (以内容栈中线为界)。
      let targetStack = x > currentStackView.bounds.midX ? rightStackView : leftStackView
      // 目标组若是空组, 占位文字还在栈里: 下面按工具格算位置 (others 只含
      // CurrentToolView), 插入位置 0 会落到占位文字前面, 随后
      // refreshSidePlaceholders() 把占位文字清掉。
      let others = toolViews(in: targetStack).filter { $0 !== toolView }
      var targetIndex = others.count
      for (index, other) in others.enumerated() {
        // 格子中点换算到 currentStackView 坐标系再比较 (两个组坐标系不同)。
        let otherCenterX = currentStackView.convert(other.center, from: other.superview).x
        if x < otherCenterX {
          targetIndex = index
          break
        }
      }
      let currentStack = toolView.superview as? UIStackView
      guard let currentIndex = currentStack?.arrangedSubviews.firstIndex(of: toolView),
            currentStack !== targetStack || currentIndex != targetIndex else { return }
      currentStack?.removeArrangedSubview(toolView)
      targetStack.insertArrangedSubview(toolView, at: min(targetIndex, targetStack.arrangedSubviews.count))
      refreshSidePlaceholders()
    case .ended, .cancelled:
      guard let toolView = draggedToolView else { return }
      draggedToolView = nil
      currentScrollView.isScrollEnabled = true
      UIView.animate(withDuration: 0.15) {
        toolView.transform = .identity
        toolView.alpha = 1.0
      }
      guard gesture.state == .ended, toolbarDragMoved else { return }
      // 栈里已经是拖完的排列 (占位文字也在 .changed 里处理过了),
      // 这里只按栈回写数组并回传, 不重建——重建会把正在做恢复动画的
      // 拖动格子从层级里摘掉, 动画直接消失。
      syncToolsFromStacks()
      onReorder?(leftTools.map { $0.id }, rightTools.map { $0.id })
    default:
      break
    }
  }

  /// 视图 -> 最近的 CurrentToolView 祖先 (含自己): 长按 hitTest 找到的
  /// 可能是图标/文字/⊖ 按钮, 沿 superview 链往上找工具格。
  private func ancestorToolView(of view: UIView) -> CurrentToolView? {
    var current: UIView? = view
    while let candidate = current {
      if let toolView = candidate as? CurrentToolView { return toolView }
      current = candidate.superview
    }
    return nil
  }

  // MARK: - 可选工具池 (下半: 小图标宫格, 横向翻页)

  /// 按 poolTools 重建分页宫格。页高自适应: 池里 ≤4 个工具时一排 (62pt),
  /// 5~8 个时两排 (134pt); 池空时分页容器收起, 只显示提示文字。
  private func rebuildPoolPages() {
    // 旧页必须先从 arrangedSubviews 里摘掉再移出层级: 只调
    // removeFromSuperview 不会把它从 arrangedSubviews 摘掉, 旧页的约束
    // (页宽 == 滚动容器宽) 会残留, 下次 reload 再加一页就多一套,
    // pageControl 的页数也会数上已删的旧页 (菜单面板第 8 轮同款修法)。
    pagesStackView.arrangedSubviews.forEach {
      pagesStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    if poolTools.isEmpty {
      pagingScrollView.isHidden = true
      poolEmptyLabel.isHidden = false
      poolHeightConstraint?.constant = 0
      poolEmptyHeightConstraint?.constant = 40
      pageControl.numberOfPages = 1
      pageControl.isHidden = true
      pageControlHeightConstraint?.constant = 0
      pageControl.currentPage = 0
      return
    }
    pagingScrollView.isHidden = false
    poolEmptyLabel.isHidden = true
    poolEmptyHeightConstraint?.constant = 0
    var pageTools: [Tool] = []
    var maxToolsOnPage = 0
    for tool in poolTools {
      pageTools.append(tool)
      if pageTools.count == Self.poolToolsPerPage {
        addPoolPage(with: pageTools)
        maxToolsOnPage = max(maxToolsOnPage, pageTools.count)
        pageTools = []
      }
    }
    if !pageTools.isEmpty {
      addPoolPage(with: pageTools)
      maxToolsOnPage = max(maxToolsOnPage, pageTools.count)
    }
    // 一排 62pt, 两排 62*2+10=134pt。
    poolHeightConstraint?.constant = maxToolsOnPage > Self.poolColumns
      ? Self.toolCellHeight * 2 + 10
      : Self.toolCellHeight
    let pageCount = max(pagesStackView.arrangedSubviews.count, 1)
    pageControl.numberOfPages = pageCount
    // 只有多页时显示圆点; 单页时隐藏并把高度压到 0 (不留空位)。
    pageControl.isHidden = pageCount <= 1
    pageControlHeightConstraint?.constant = pageCount <= 1 ? 0 : 20
    pageControl.currentPage = 0
    pagingScrollView.setContentOffset(.zero, animated: false)
  }

  /// 建一页并挂进横向内容栈。页宽约束必须在 addArrangedSubview 之后
  /// 再激活: 页还没进层级时激活 page.width == pagingScrollView.frameLayoutGuide.width,
  /// 两边没有共同祖先, UIKit 在激活时直接抛 NSException 导致闪退
  /// (菜单面板第 8 轮崩溃日志根因, 同款修法)。
  private func addPoolPage(with tools: [Tool]) {
    let page = makePoolPage(with: tools)
    pagesStackView.addArrangedSubview(page)
    page.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor).isActive = true
  }

  /// 一页宫格 (最多 2 行 x 4 列): 宽 = 滚动容器宽, 高与容器同高。
  private func makePoolPage(with tools: [Tool]) -> UIView {
    let page = UIView()
    page.translatesAutoresizingMaskIntoConstraints = false
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    page.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: page.topAnchor),
      stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor),
    ])
    var rowTools: [Tool] = []
    for tool in tools {
      rowTools.append(tool)
      if rowTools.count == Self.poolColumns {
        stack.addArrangedSubview(makePoolRow(with: rowTools))
        rowTools = []
      }
    }
    if !rowTools.isEmpty {
      stack.addArrangedSubview(makePoolRow(with: rowTools))
    }
    return page
  }

  private func makePoolRow(with tools: [Tool]) -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.spacing = 12
    for tool in tools {
      let tile = PoolToolView(tool: tool)
      tile.onTap = { [weak self] in self?.addTool(id: tool.id) }
      row.addArrangedSubview(tile)
    }
    // 不满 4 个时用空白占位补齐, 保持每列等宽。
    while row.arrangedSubviews.count < Self.poolColumns {
      let spacer = UIView()
      spacer.translatesAutoresizingMaskIntoConstraints = false
      row.addArrangedSubview(spacer)
    }
    return row
  }
}

// MARK: - UIScrollViewDelegate (工具池翻页)

extension KeyboardToolbarCustomizePanelView: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === pagingScrollView, scrollView.bounds.width > 0 else { return }
    pageControl.currentPage = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
  }
}

// MARK: - 小图标格子

/// 当前工具栏格子: 图标 + 名称, 右上角 ⊖ (红色实心减号, 微信式)。
/// 点 ⊖ 拿掉回池; 长按拖动排序 (手势在 currentScrollView 上, 不在格子上)。
private class CurrentToolView: UIView {
  let tool: (id: String, title: String, systemImage: String)

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

  init(tool: (id: String, title: String, systemImage: String)) {
    self.tool = tool
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconImageView)
    addSubview(titleLabel)
    addSubview(removeButton)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 56),
      heightAnchor.constraint(equalToConstant: 62),

      iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),

      titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 2),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),

      // ⊖ 钉在格子右上角, 半压在图标角上 (微信式)。
      removeButton.topAnchor.constraint(equalTo: topAnchor, constant: -2),
      removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
      removeButton.widthAnchor.constraint(equalToConstant: 20),
      removeButton.heightAnchor.constraint(equalToConstant: 20),
    ])
    titleLabel.text = tool.title
    iconImageView.image = UIImage(
      systemName: tool.systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 24)))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func removeTapped() {
    onRemove?()
  }
}

/// 工具池格子: 白色圆角底 + 图标 + 名称 + 右上角绿色 + 标记 (点按加入)。
/// 底色随深浅模式自动切换 (与菜单格子 MenuTileButton 同一套颜色)。
private class PoolToolView: UIView {
  let tool: (id: String, title: String, systemImage: String)

  var onTap: (() -> Void)?

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

  init(tool: (id: String, title: String, systemImage: String)) {
    self.tool = tool
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 10
    clipsToBounds = true
    backgroundColor = Self.tileBackgroundColor
    // 关键: UIStackView 默认可交互, 会盖住整个格子并在 hit-test 时抢走触摸,
    // 点按手势挂在格子自己身上时子视图必须关掉交互 (菜单面板同款注释)。
    isUserInteractionEnabled = true
    addSubview(iconImageView)
    addSubview(titleLabel)
    addSubview(addBadgeImageView)
    iconImageView.isUserInteractionEnabled = false
    titleLabel.isUserInteractionEnabled = false
    addBadgeImageView.isUserInteractionEnabled = false
    // 格子高 62pt 是期望值, 不是硬性: 面板矮时 (小屏/横屏) 可压缩,
    // 避免“无法同时满足约束”的警告 (菜单面板 MenuTileButton 同款)。
    let tileHeightConstraint = heightAnchor.constraint(equalToConstant: 62)
    tileHeightConstraint.priority = .defaultHigh
    NSLayoutConstraint.activate([
      tileHeightConstraint,

      iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),

      titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 2),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

      // + 标记钉在格子右上角。
      addBadgeImageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      addBadgeImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      addBadgeImageView.widthAnchor.constraint(equalToConstant: 16),
      addBadgeImageView.heightAnchor.constraint(equalToConstant: 16),
    ])
    titleLabel.text = tool.title
    iconImageView.image = UIImage(
      systemName: tool.systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 24)))
    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    addGestureRecognizer(tap)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func tapped() {
    onTap?()
  }
}
