
//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (仿微信输入法, 第 12 轮按微信模型重做):
//  顶行就是真实的工具栏 (不是复制品): 左侧绿色 ✓ 圆钮 + 左组工具
//  贴左、右组工具贴右 (中间是弹性空位, 不是占位文字), 工具是小圆图标
//  (白底圆, 右上角灰色 ⊖); 长按提起 (快照放大 + 阴影跟手指走,
//  原格子留在栈里当半透明坑位), 松手落下; 靠近最左/最右边缘时
//  吸附到该侧端点 (左组首位/右组末位, 进区轻震一次)。
//  下半工具池是“一长张纸”: 白色圆角容器里的可选工具是纸上的贴纸
//  (小圆图标 + 名称, 4 列, 横向翻页滑动 + 页点), 点按即加入
//  (进左侧末尾); 长按可把贴纸拿起来, 拖到顶行上放下 (等同于点按
//  添加); 直接滑动纸张翻页浏览不同位置的贴纸 (按住不动才拿起,
//  一滑就翻页, 两者靠长按的移动容限区分)。
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
//  绿格 (菜单里“用户亲手加上去的工具变绿”) 不归面板管: 面板里没有任何
//  对 toolbarUserAddedToolIDs 的读写。标记只发生在调用方:
//  点按添加 / 池子拖入顶行 → onAddTool (调用方标记);
//  顶行内拖动换位/换侧 → onReorder (只保存布局, 不标记; 第 12 轮规则:
//  拖动 ≠ 添加, 只有池子加入才记)。
//
//  拖动实现: 不用 UICollectionView 拖拽 API——顶行是两组 UIStackView、
//  池子是分页 UIScrollView, 全部重写成 CollectionView 的改动量远大于
//  在现有长按手势上扩展, 且会动到调用方的 reload 契约。
//  两处拖动都用 UILongPressGestureRecognizer + 浮层快照:
//  · 顶行: 长按提起本行格子的快照, 栈内原格子当坑位实时换位;
//    松手时快照飞回坑位再消失, 再按栈回写并回传 onReorder。
//  · 池子: 长按提起贴纸快照, 拖进顶行区域时在目标组里插一个占位坑
//    (56 白圆灰底), 松手放下 = 按坑位加入, 走 onAddTool (标记) +
//    onReorder (保存落点处的准确布局, 因为 onAddTool 只追加到左组末尾),
//    再按本地数组重建面板把显示纠回落点; 没放进顶行则飞回源格子。
//  工具池分页复用菜单面板的横向分页模式 (UIScrollView + pagesStackView +
//  UIPageControl): 页宽约束必须在 addArrangedSubview 之后再激活,
//  否则没有共同祖先会抛异常闪退 (第 8 轮崩溃根因)。
//

import HamsterUIKit
import UIKit

/// 定制工具栏面板: 绿色 ✓ 圆钮 + 当前工具栏小圆图标行
/// (灰 ⊖ 删除/长按拖拽排序/拖过中线换侧) + 白色圆角容器里的
/// 可选工具池小圆图标宫格 (左右翻页 + 页点, 点按加入) + 恢复默认。
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
  /// 顶部一排的格高 (圆图标 56pt + 上下余量)。
  private static let toolCellHeight: CGFloat = 62
  /// 顶部圆图标直径 (微信式小圆按钮)。
  private static let topRowIconDiameter: CGFloat = 56
  /// 工具池格高: 圆图标 52pt + 名称 (7 字名如“立即同步剪贴板”要放得下
  /// 两行, 52+4+28=84; 76 会把第二行压没只剩“立即同步剪…”);
  /// PoolToolView 的格高约束也用这个值 (fileprivate, 同文件共享)。
  /// 两排时 84*2+10=178pt。
  fileprivate static let poolCellHeight: CGFloat = 84
  /// 工具池圆图标直径。
  private static let poolCircleDiameter: CGFloat = 52
  /// 工具池容器圆角 (微信式白色大圆角容器)。
  private static let poolContainerCornerRadius: CGFloat = 16
  /// 工具池容器内边距。
  private static let poolContainerPadding: CGFloat = 12
  /// 顶行边缘吸附区宽度: 手指贴到顶行可视区最左/最右这个距离内,
  /// 拖动的工具直接吸到该侧端点 (左组首位 / 右组末位)。
  private static let topRowSnapEdgeWidth: CGFloat = 48
  /// 池子长按拿起的按住时长: 0.35 秒 (比默认 0.5 秒灵敏一点,
  /// 拿贴纸的手感更跟手; 手指直接滑动时翻页手势先走, 长按因移动
  /// 超限自动失败, 不会误拿)。
  private static let poolLongPressDuration: TimeInterval = 0.35

  /// 工具池容器底色: 浅色纯白, 深色半透明白 (≈深灰), 与菜单格子一致。
  static let poolContainerBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white
  }

  /// 工具池圆图标底色: 白容器里要有对比——浅色用浅灰, 深色用更亮的半透明白。
  static let poolCircleBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.30)
      : UIColor.systemGray6
  }

  /// 顶部一排圆图标底色: 灰色面板底上用白圆 (与菜单格子一致)。
  static let topRowCircleBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white
  }

  /// ✓ 关闭圆钮: 微信定制面板左上角的绿色实心圆 + 白色 ✓。
  private lazy var checkmarkCircleButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "checkmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 22, weight: .bold), scale: .default), forImageIn: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemGreen
    button.layer.cornerRadius = Self.topRowIconDiameter / 2
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  /// 工具池白色圆角容器 (微信式)。
  private lazy var poolContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Self.poolContainerBackgroundColor
    view.layer.cornerRadius = Self.poolContainerCornerRadius
    view.clipsToBounds = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
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

  /// 顶行弹性空位 (分隔线与右组之间): 工具少时把它撑开, 右组贴到
  /// 顶行最右端 (微信的真实工具栏就是左组贴左、右组贴右, 中间留空);
  /// 工具多到超宽时它先压到 0, 再横向滚动。左右组本身不设占位文字,
  /// 空组就是 0 宽, 微信的空侧也只是一片空, 不是一行字。
  private lazy var topRowSpacerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    view.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
    return view
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
  private var containerHeightConstraint: NSLayoutConstraint?
  private var poolEmptyHeightConstraint: NSLayoutConstraint?
  private var pageControlHeightConstraint: NSLayoutConstraint?

  /// 拖动中的工具格 (长按拖动时)。
  private var draggedToolView: CurrentToolView?
  /// 顶行拖动中的浮层快照 (提起动画: 放大 + 阴影, 跟着手指走);
  /// 原格子留在栈里当“坑位” (alpha 0.25), 松手时快照落回坑位。
  private var toolbarDragSnapshot: UIView?
  /// 顶行拖动本次进入的吸附侧 (nil = 未吸附), 用于进区时只震一次。
  private var toolbarDragSnappedSide: ToolbarSide?
  /// 本次长按是否真的拖动过 (只原地长按松手不算拖动, 不回传 onReorder)。
  private var toolbarDragMoved = false
  /// 本次长按起始 x (currentStackView 坐标系)。
  private var toolbarDragStartX: CGFloat = 0

  /// 池子长按拖出的贴纸快照 (提起动画), 跟手指走; 原格子 alpha 0.35。
  private var poolDragSnapshot: UIView?
  /// 本次池子拖动拿起的工具。
  private var poolDragTool: Tool?
  /// 本次池子拖动的源格子 (取消时飞回 / 恢复透明用)。
  private var poolDragSourceTile: PoolToolView?
  /// 池子拖动时顶行里的占位坑 (56 白圆灰底), 表示放下后的位置;
  /// 手指不在顶行上时为 nil。
  private var poolDropPlaceholder: UIView?
  /// 池子拖动放下时的目标侧 + 组内下标 (占位坑所在位置)。
  private var poolDropTarget: (side: ToolbarSide, index: Int)?
  /// 上一次池子拖动结束的时间戳 (秒): 长按识别后格子的点按手势
  /// 原则上会被取消, 但为防点按在松手后仍触发, 拖动结束 0.5 秒内
  /// 的池子点按直接忽略 (见 makePoolRow 的 onTap)。
  private var poolDragEndedAt: TimeInterval = 0

  /// 顶行左右分区。
  private enum ToolbarSide {
    case left
    case right
  }

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
    addSubview(checkmarkCircleButton)
    addSubview(currentScrollView)
    currentScrollView.addSubview(currentStackView)
    currentStackView.addArrangedSubview(leftStackView)
    currentStackView.addArrangedSubview(sideDividerView)
    currentStackView.addArrangedSubview(topRowSpacerView)
    currentStackView.addArrangedSubview(rightStackView)
    addSubview(poolContainerView)
    poolContainerView.addSubview(pagingScrollView)
    pagingScrollView.addSubview(pagesStackView)
    addSubview(poolEmptyLabel)
    addSubview(pageControl)
    addSubview(resetButton)
    // 当前工具栏长按拖动排序/换侧 (见 handleCurrentLongPress)。
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCurrentLongPress(_:)))
    currentScrollView.addGestureRecognizer(longPress)
    // 工具池长按拿起贴纸、拖到顶行放下 (见 handlePoolLongPress);
    // 与翻页手势并存 (见 gestureRecognizer:shouldRecognizeSimultaneouslyWith:)。
    let poolLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePoolLongPress(_:)))
    poolLongPress.minimumPressDuration = Self.poolLongPressDuration
    poolLongPress.delegate = self
    pagingScrollView.addGestureRecognizer(poolLongPress)
  }

  override func activateViewConstraints() {
    poolHeightConstraint = pagingScrollView.heightAnchor.constraint(equalToConstant: Self.poolCellHeight)
    // 面板矮时池高可压缩 (defaultHigh), 不报无法满足约束的警告;
    // 压掉的是第二行格子的高度, 第一行不受影响。
    poolHeightConstraint?.priority = .defaultHigh
    containerHeightConstraint = poolContainerView.heightAnchor.constraint(equalToConstant: Self.poolCellHeight + Self.poolContainerPadding * 2)
    containerHeightConstraint?.priority = .defaultHigh
    poolEmptyHeightConstraint = poolEmptyLabel.heightAnchor.constraint(equalToConstant: 0)
    pageControlHeightConstraint = pageControl.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      checkmarkCircleButton.centerYAnchor.constraint(equalTo: currentScrollView.centerYAnchor),
      checkmarkCircleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      checkmarkCircleButton.widthAnchor.constraint(equalToConstant: Self.topRowIconDiameter),
      checkmarkCircleButton.heightAnchor.constraint(equalToConstant: Self.topRowIconDiameter),

      currentScrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
      currentScrollView.leadingAnchor.constraint(equalTo: checkmarkCircleButton.trailingAnchor, constant: 12),
      currentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      currentScrollView.heightAnchor.constraint(equalToConstant: Self.toolCellHeight),

      // 横向滚动容器的标准约束: 内容栈贴 contentLayoutGuide,
      // 高度等于 frame 高度 (一排小图标)。
      // 内容栈宽至少等于可视宽: 工具少时弹性空位把它撑满, 右组贴到
      // 最右端 (真实工具栏的样子); 工具多时内容超宽, 正常横滑。
      currentStackView.topAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.topAnchor),
      currentStackView.bottomAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.bottomAnchor),
      currentStackView.leadingAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.leadingAnchor),
      currentStackView.trailingAnchor.constraint(equalTo: currentScrollView.contentLayoutGuide.trailingAnchor),
      currentStackView.heightAnchor.constraint(equalTo: currentScrollView.frameLayoutGuide.heightAnchor),
      currentStackView.widthAnchor.constraint(greaterThanOrEqualTo: currentScrollView.frameLayoutGuide.widthAnchor),

      sideDividerView.widthAnchor.constraint(equalToConstant: 1),
      sideDividerView.heightAnchor.constraint(equalToConstant: 40),

      poolContainerView.topAnchor.constraint(equalTo: currentScrollView.bottomAnchor, constant: 12),
      poolContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      poolContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      containerHeightConstraint!,

      pagingScrollView.topAnchor.constraint(equalTo: poolContainerView.topAnchor, constant: Self.poolContainerPadding),
      pagingScrollView.leadingAnchor.constraint(equalTo: poolContainerView.leadingAnchor, constant: Self.poolContainerPadding),
      pagingScrollView.trailingAnchor.constraint(equalTo: poolContainerView.trailingAnchor, constant: -Self.poolContainerPadding),
      poolHeightConstraint!,

      poolEmptyLabel.topAnchor.constraint(equalTo: poolContainerView.bottomAnchor),
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

  /// 按 leftTools/rightTools 重建两组小图标行。
  /// 空组就是 0 宽 (微信的空侧只是一片空, 不写“左侧暂无工具”这种字)。
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
  }

  private func makeCurrentToolView(_ tool: Tool) -> CurrentToolView {
    let view = CurrentToolView(tool: tool)
    view.onRemove = { [weak self] in self?.removeTool(id: tool.id) }
    return view
  }

  /// 某侧栈里的工具格 (按栈内顺序)。占位坑 (池子拖动时的灰圆)
  /// 是普通 UIView, 不算在内; 顶行拖动时的坑位就是原格子本身。
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

  /// 长按提起顶行工具拖动 (只在工具格上): 提起时原格子留在栈里当
  /// 半透明坑位, 快照放大 + 阴影浮起来跟着手指走 (y 钉在顶行中线上);
  /// 移动中坑位实时换位, 可跨组换侧; 靠近最左/最右边缘时吸附到该侧
  /// 端点 (左组首位/右组末位, 进区轻震一次); 松手时快照飞回坑位再
  /// 消失, 按栈内实际排列回传 onReorder; 取消则按保存的数组重建回
  /// 拖动前的位置。算法与工具栏本体
  /// (KeyboardToolbarView.toolbarToolLongPressed) 一致:
  /// 手指在哪半区、工具就进哪侧容器, 组内位置按其余格子中点为界。
  /// 拖动时关掉横向滚动, 免得滚动手势抢走手指。
  /// 注意: 顶行内拖动只是换位/换侧, 只走 onReorder (保存布局),
  /// 不走 onAddTool、不做“添加”标记 (第 12 轮规则: 拖动 ≠ 添加)。
  @objc private func handleCurrentLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      let pointInStack = gesture.location(in: currentStackView)
      guard let hitView = currentStackView.hitTest(pointInStack, with: nil),
            let toolView = ancestorToolView(of: hitView),
            draggedToolView == nil,
            let snapshot = toolView.snapshotView(afterScreenUpdates: true) else { return }
      draggedToolView = toolView
      toolbarDragMoved = false
      toolbarDragSnappedSide = nil
      toolbarDragStartX = pointInStack.x
      currentScrollView.isScrollEnabled = false
      // 提起动画: 原格子当坑位 (半透明), 快照放大 + 阴影浮起来。
      toolView.alpha = 0.25
      snapshot.frame = convert(toolView.bounds, from: toolView)
      snapshot.layer.shadowColor = UIColor.black.cgColor
      snapshot.layer.shadowOpacity = 0.25
      snapshot.layer.shadowRadius = 8
      snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
      snapshot.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
      addSubview(snapshot)
      toolbarDragSnapshot = snapshot
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .changed:
      guard let toolView = draggedToolView, let snapshot = toolbarDragSnapshot else { return }
      // 快照跟着手指走, y 钉在顶行中线上 (只在顶行这条“轨道”上拖)。
      let topRowCenterY = convert(currentScrollView.bounds, from: currentScrollView).midY
      snapshot.center = CGPoint(x: gesture.location(in: self).x, y: topRowCenterY)
      let x = gesture.location(in: currentStackView).x
      if abs(x - toolbarDragStartX) > 12 { toolbarDragMoved = true }
      guard toolbarDragMoved else { return }
      // 边缘吸附: 手指贴到可视区最左/最右, 坑位直接吸到该侧端点;
      // 中间区域按其余格子中点算位置 (与原来一致)。
      let visibleX = gesture.location(in: currentScrollView).x
      let target: (side: ToolbarSide, index: Int)
      if visibleX <= Self.topRowSnapEdgeWidth {
        if toolbarDragSnappedSide != .left {
          toolbarDragSnappedSide = .left
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        target = (.left, 0)
      } else if visibleX >= currentScrollView.bounds.width - Self.topRowSnapEdgeWidth {
        if toolbarDragSnappedSide != .right {
          toolbarDragSnappedSide = .right
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        target = (.right, toolViews(in: rightStackView).filter { $0 !== toolView }.count)
      } else {
        toolbarDragSnappedSide = nil
        target = insertionTarget(forX: x, excluding: toolView)
      }
      moveDraggedToolView(toolView, to: target)
    case .ended, .cancelled:
      guard let toolView = draggedToolView else { return }
      let snapshot = toolbarDragSnapshot
      let wasMoved = toolbarDragMoved
      let ended = gesture.state == .ended
      draggedToolView = nil
      toolbarDragSnapshot = nil
      toolbarDragSnappedSide = nil
      currentScrollView.isScrollEnabled = true
      // 松手落下: 快照飞回坑位、缩回原大、淡出, 再消失。
      let targetFrame = convert(toolView.bounds, from: toolView)
      UIView.animate(withDuration: 0.18, animations: {
        snapshot?.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        snapshot?.transform = .identity
        snapshot?.alpha = 0
      }, completion: { [weak self] _ in
        snapshot?.removeFromSuperview()
        if ended {
          toolView.alpha = 1.0
        } else {
          // 取消: 栈里已挪过的坑位作废, 按保存的数组重建回拖动前的位置
          // (原格子在重建里会被新格子替换, 这里不用再恢复它的 alpha)。
          self?.rebuildCurrentStrip()
        }
      })
      guard ended, wasMoved else { return }
      // 栈里已经是拖完的排列, 这里只按栈回写数组并回传, 不重建——
      // 重建会把正在做落下动画的拖动格子从层级里摘掉, 动画直接消失。
      syncToolsFromStacks()
      onReorder?(leftTools.map { $0.id }, rightTools.map { $0.id })
    default:
      break
    }
  }

  /// 手指 x (currentStackView 坐标系) 对应的落点: 哪侧组、组内第几个。
  /// 以内容栈中线分侧, 组内位置按其余格子中点为界 (与工具栏本体一致)。
  /// excluding 为 nil 时不排除任何格子 (池子拖入时用: 拖的贴纸不在栈里)。
  private func insertionTarget(forX x: CGFloat, excluding draggedView: CurrentToolView?) -> (side: ToolbarSide, index: Int) {
    let targetStack = x > currentStackView.bounds.midX ? rightStackView : leftStackView
    let side: ToolbarSide = targetStack === rightStackView ? .right : .left
    let others = toolViews(in: targetStack).filter { $0 !== draggedView }
    var targetIndex = others.count
    for (index, other) in others.enumerated() {
      // 格子中点换算到 currentStackView 坐标系再比较 (两个组坐标系不同)。
      let otherCenterX = currentStackView.convert(other.center, from: other.superview).x
      if x < otherCenterX {
        targetIndex = index
        break
      }
    }
    return (side, targetIndex)
  }

  /// 把栈里的工具格 (顶行拖动的坑位) 移到目标组的目标下标;
  /// 已在该位置时不动 (避免无谓的布局抖动)。
  private func moveDraggedToolView(_ toolView: CurrentToolView, to target: (side: ToolbarSide, index: Int)) {
    let targetStack = target.side == .right ? rightStackView : leftStackView
    let currentStack = toolView.superview as? UIStackView
    guard let currentIndex = currentStack?.arrangedSubviews.firstIndex(of: toolView),
          currentStack !== targetStack || currentIndex != target.index else { return }
    currentStack?.removeArrangedSubview(toolView)
    targetStack.insertArrangedSubview(toolView, at: min(target.index, targetStack.arrangedSubviews.count))
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

  /// 视图 -> 最近的 PoolToolView 祖先 (含自己): 池子长按 hitTest 找到的
  /// 可能是格子本身 (图标/文字都关了交互), 沿 superview 链往上找贴纸格。
  private func ancestorPoolTile(of view: UIView) -> PoolToolView? {
    var current: UIView? = view
    while let candidate = current {
      if let tile = candidate as? PoolToolView { return tile }
      current = candidate.superview
    }
    return nil
  }

  // MARK: - 工具池长按拖动 (贴纸拿起 -> 拖到顶行放下)

  /// 池子贴纸长按拖动: 按住不动 0.35 秒提起贴纸快照 (放大 + 阴影),
  /// 拖进顶行区域时在目标组里插一个占位坑表示放下位置, 松手放下 =
  /// 按坑位加入顶行; 没放进顶行则飞回源格子, 什么都不改。
  /// 拖动时关掉池子翻页滚动; 手指直接滑动时翻页手势先走, 长按因
  /// 移动超限自动失败, 所以“滑动翻页”和“按住拿起”不会打架。
  @objc private func handlePoolLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      let point = gesture.location(in: pagingScrollView)
      guard let hitView = pagingScrollView.hitTest(point, with: nil),
            let tile = ancestorPoolTile(of: hitView),
            poolDragSnapshot == nil,
            let snapshot = tile.snapshotView(afterScreenUpdates: true) else { return }
      poolDragTool = tile.tool
      poolDragSourceTile = tile
      pagingScrollView.isScrollEnabled = false
      // 提起动画: 原格子半透明, 快照放大 + 阴影浮起来跟手指走。
      tile.alpha = 0.35
      snapshot.frame = convert(tile.bounds, from: tile)
      snapshot.layer.shadowColor = UIColor.black.cgColor
      snapshot.layer.shadowOpacity = 0.25
      snapshot.layer.shadowRadius = 8
      snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
      snapshot.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
      addSubview(snapshot)
      poolDragSnapshot = snapshot
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .changed:
      guard let snapshot = poolDragSnapshot, poolDragTool != nil else { return }
      let pointInSelf = gesture.location(in: self)
      snapshot.center = pointInSelf
      updatePoolDropPlaceholder(forFingerPoint: pointInSelf)
    case .ended, .cancelled:
      guard let snapshot = poolDragSnapshot, let tool = poolDragTool else { return }
      let ended = gesture.state == .ended
      let dropTarget = poolDropTarget
      let sourceTile = poolDragSourceTile
      poolDragSnapshot = nil
      poolDragTool = nil
      poolDragSourceTile = nil
      poolDropTarget = nil
      pagingScrollView.isScrollEnabled = true
      poolDragEndedAt = Date().timeIntervalSince1970
      if ended, let dropTarget {
        // 放下进顶行: 占位坑先拿掉, 再按坑位提交 (见 commitPoolDrop)。
        removePoolDropPlaceholder()
        commitPoolDrop(tool: tool, to: dropTarget)
        // 快照飞向刚落位的格子、缩到顶行格大小、淡出, 再消失。
        let stack = dropTarget.side == .right ? rightStackView : leftStackView
        let targetView = toolViews(in: stack).first { $0.tool.id == tool.id }
        let landingScale = Self.topRowIconDiameter / max(snapshot.bounds.height, 1)
        let targetCenter: CGPoint
        if let targetView {
          let frame = convert(targetView.bounds, from: targetView)
          targetCenter = CGPoint(x: frame.midX, y: frame.midY)
        } else {
          targetCenter = snapshot.center
        }
        UIView.animate(withDuration: 0.18, animations: {
          snapshot.center = targetCenter
          snapshot.transform = CGAffineTransform(scaleX: landingScale, y: landingScale)
          snapshot.alpha = 0
        }, completion: { _ in snapshot.removeFromSuperview() })
      } else {
        // 没放进顶行 (取消 / 松手时不在顶行上): 占位坑拿掉,
        // 快照飞回源格子, 源格子恢复, 什么都不改。
        removePoolDropPlaceholder()
        let targetCenter: CGPoint
        if let sourceTile {
          let frame = convert(sourceTile.bounds, from: sourceTile)
          targetCenter = CGPoint(x: frame.midX, y: frame.midY)
        } else {
          targetCenter = snapshot.center
        }
        UIView.animate(withDuration: 0.18, animations: {
          snapshot.center = targetCenter
          snapshot.transform = .identity
          snapshot.alpha = 1
        }, completion: { _ in
          snapshot.removeFromSuperview()
          sourceTile?.alpha = 1.0
        })
      }
    default:
      break
    }
  }

  /// 手指在面板里的位置 -> 顶行落点: 进入顶行区域 (上下各放宽 12pt)
  /// 才显示占位坑; 左右边缘 48pt 内吸附到该侧端点, 中间按格子中点
  /// 算位置 (与顶行拖动同一套 insertionTarget)。位置没变时不动坑。
  private func updatePoolDropPlaceholder(forFingerPoint point: CGPoint) {
    let topRowFrame = currentScrollView.frame.insetBy(dx: -8, dy: -12)
    guard topRowFrame.contains(point) else {
      removePoolDropPlaceholder()
      return
    }
    let xInStack = convert(point, to: currentStackView).x
    let visibleX = convert(point, to: currentScrollView).x
    let target: (side: ToolbarSide, index: Int)
    if visibleX <= Self.topRowSnapEdgeWidth {
      target = (.left, 0)
    } else if visibleX >= currentScrollView.bounds.width - Self.topRowSnapEdgeWidth {
      target = (.right, toolViews(in: rightStackView).count)
    } else {
      target = insertionTarget(forX: xInStack, excluding: nil)
    }
    if let current = poolDropTarget, current.side == target.side, current.index == target.index,
       poolDropPlaceholder != nil {
      return
    }
    removePoolDropPlaceholder()
    let placeholder = makeDropPlaceholderView()
    let targetStack = target.side == .right ? rightStackView : leftStackView
    targetStack.insertArrangedSubview(placeholder, at: min(target.index, targetStack.arrangedSubviews.count))
    poolDropPlaceholder = placeholder
    poolDropTarget = target
  }

  /// 顶行里的放下占位坑: 56 白圆灰底 (与工具格同大, 颜色比白圆深一级,
  /// 一眼能看出“贴纸会落在这里”)。
  private func makeDropPlaceholderView() -> UIView {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .tertiarySystemFill
    view.layer.cornerRadius = Self.topRowIconDiameter / 2
    view.alpha = 0.7
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: Self.topRowIconDiameter),
      view.heightAnchor.constraint(equalToConstant: Self.topRowIconDiameter),
    ])
    return view
  }

  /// 拿掉顶行里的放下占位坑 (拖出顶行 / 放下提交 / 取消时)。
  private func removePoolDropPlaceholder() {
    guard let placeholder = poolDropPlaceholder else { return }
    if let stack = placeholder.superview as? UIStackView {
      stack.removeArrangedSubview(placeholder)
    }
    placeholder.removeFromSuperview()
    poolDropPlaceholder = nil
    poolDropTarget = nil
  }

  /// 池子贴纸按占位坑落进顶行, 等同于点按添加:
  /// 先走 onAddTool (调用方把该工具记为用户亲手加上去的, 菜单里变绿),
  /// 再走 onReorder 把落点处的准确布局 (侧 + 位置) 存盘——onAddTool
  /// 只会追加到左组末尾, 不认落点; onReorder 只保存布局, 不做
  /// “添加”标记 (第 12 轮规则: 拖动 ≠ 添加, 只有池子加入才记)。
  /// 最后按本地数组重建面板, 把 onAddTool 的 reload 造成的
  /// “左组末尾”显示纠回落点。两个回调都是同步的, 中间不会闪屏。
  private func commitPoolDrop(tool: Tool, to target: (side: ToolbarSide, index: Int)) {
    guard let poolIndex = poolTools.firstIndex(where: { $0.id == tool.id }) else { return }
    poolTools.remove(at: poolIndex)
    let finalLeft: [Tool]
    let finalRight: [Tool]
    if target.side == .right {
      var right = rightTools
      right.insert(tool, at: min(target.index, right.count))
      finalRight = right
      finalLeft = leftTools
    } else {
      var left = leftTools
      left.insert(tool, at: min(target.index, left.count))
      finalLeft = left
      finalRight = rightTools
    }
    leftTools = finalLeft
    rightTools = finalRight
    onAddTool?(tool.id)
    onReorder?(finalLeft.map { $0.id }, finalRight.map { $0.id })
    // onAddTool 触发的 reload 会先把面板按调用方算出的数组
    // (“左组末尾”) 重建一次, 这里按落点纠回。
    leftTools = finalLeft
    rightTools = finalRight
    rebuildCurrentStrip()
    rebuildPoolPages()
  }

  // MARK: - 可选工具池 (下半: 小图标宫格, 横向翻页)

  /// 按 poolTools 重建分页宫格。页高自适应: 池里 ≤4 个工具时一排 (84pt),
  /// 5~8 个时两排 (178pt); 池空时分页容器收起, 只显示提示文字。
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
      poolContainerView.isHidden = true
      poolEmptyLabel.isHidden = false
      poolHeightConstraint?.constant = 0
      containerHeightConstraint?.constant = 0
      poolEmptyHeightConstraint?.constant = 40
      pageControl.numberOfPages = 1
      pageControl.isHidden = true
      pageControlHeightConstraint?.constant = 0
      pageControl.currentPage = 0
      return
    }
    pagingScrollView.isHidden = false
    poolContainerView.isHidden = false
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
    // 一排 84pt, 两排 84*2+10=178pt; 容器再加上下各 12pt 内边距。
    let poolHeight = maxToolsOnPage > Self.poolColumns
      ? Self.poolCellHeight * 2 + 10
      : Self.poolCellHeight
    poolHeightConstraint?.constant = poolHeight
    containerHeightConstraint?.constant = poolHeight + Self.poolContainerPadding * 2
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
      tile.onTap = { [weak self] in
        guard let self else { return }
        // 刚结束池子拖动 0.5 秒内的点按是长按松手带出来的, 忽略
        // (长按识别后点按手势原则上会被取消, 这里是双保险)。
        if Date().timeIntervalSince1970 - self.poolDragEndedAt < 0.5 { return }
        self.addTool(id: tool.id)
      }
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

// MARK: - UIGestureRecognizerDelegate (池子长按与翻页并存)

extension KeyboardToolbarCustomizePanelView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // 只放行池子长按 + 翻页手势并存: 手指按住不动 0.35 秒 → 长按触发、
    // 关掉滚动开始拖贴纸; 手指直接滑动 → 翻页手势先走、长按因移动超限
    // 自动失败。其他手势组合一律不并存 (顶行长按仍独占, 不变)。
    otherGestureRecognizer == pagingScrollView.panGestureRecognizer
  }
}

// MARK: - 小圆图标格子

/// 当前工具栏格子: 白底小圆图标 + 右上角灰色 ⊖ (微信式)。
/// 点 ⊖ 拿掉回池; 长按拖动排序 (手势在 currentScrollView 上, 不在格子上)。
private class CurrentToolView: UIView {
  let tool: (id: String, title: String, systemImage: String)

  var onRemove: (() -> Void)?

  /// 白底圆 (微信式小圆按钮)。
  private let circleView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = KeyboardToolbarCustomizePanelView.topRowCircleBackgroundColor
    return view
  }()

  private let iconImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .label
    return imageView
  }()

  private lazy var removeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    // 微信的 ⊖ 是灰的, 不是红的。
    button.tintColor = .systemGray
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
    return button
  }()

  init(tool: (id: String, title: String, systemImage: String)) {
    self.tool = tool
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(circleView)
    circleView.addSubview(iconImageView)
    addSubview(removeButton)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 56),
      heightAnchor.constraint(equalToConstant: 56),

      circleView.topAnchor.constraint(equalTo: topAnchor),
      circleView.leadingAnchor.constraint(equalTo: leadingAnchor),
      circleView.trailingAnchor.constraint(equalTo: trailingAnchor),
      circleView.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
      iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),

      // ⊖ 钉在格子右上角, 半压在圆角上 (微信式)。
      removeButton.topAnchor.constraint(equalTo: topAnchor, constant: -2),
      removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
      removeButton.widthAnchor.constraint(equalToConstant: 20),
      removeButton.heightAnchor.constraint(equalToConstant: 20),
    ])
    circleView.layer.cornerRadius = 28
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

/// 工具池格子: 小圆图标 + 名称 (微信式), 点按加入。
/// 圆底在白容器里用浅灰 (浅色) / 半透明白 (深色) 才看得出;
/// 微信的池子里没有 + 标记, 点按即加入, 这里也不加。
private class PoolToolView: UIView {
  let tool: (id: String, title: String, systemImage: String)

  var onTap: (() -> Void)?

  /// 圆图标底。
  private let circleView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = KeyboardToolbarCustomizePanelView.poolCircleBackgroundColor
    view.layer.cornerRadius = 26
    return view
  }()

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

  init(tool: (id: String, title: String, systemImage: String)) {
    self.tool = tool
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    // 关键: UIStackView 默认可交互, 会盖住整个格子并在 hit-test 时抢走触摸,
    // 点按手势挂在格子自己身上时子视图必须关掉交互 (菜单面板同款注释)。
    isUserInteractionEnabled = true
    addSubview(circleView)
    circleView.addSubview(iconImageView)
    addSubview(titleLabel)
    iconImageView.isUserInteractionEnabled = false
    titleLabel.isUserInteractionEnabled = false
    // 格子高与 poolCellHeight 一致 (84pt: 圆 52 + 间距 4 + 两行名称);
    // 是期望值, 不是硬性: 面板矮时 (小屏/横屏) 可压缩,
    // 避免“无法同时满足约束”的警告 (菜单面板 MenuTileButton 同款)。
    let tileHeightConstraint = heightAnchor.constraint(equalToConstant: KeyboardToolbarCustomizePanelView.poolCellHeight)
    tileHeightConstraint.priority = .defaultHigh
    NSLayoutConstraint.activate([
      tileHeightConstraint,

      circleView.topAnchor.constraint(equalTo: topAnchor),
      circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
      circleView.widthAnchor.constraint(equalToConstant: 52),
      circleView.heightAnchor.constraint(equalToConstant: 52),

      iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
      iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 26),
      iconImageView.widthAnchor.constraint(equalToConstant: 26),

      titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 4),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
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
