//
//  KeyboardToolbarCustomizePanelView.swift
//
//  键盘内"定制工具栏"面板 (第 13 轮: 就地编辑):
//  面板不再自己画一排放大的工具栏复制品, 而是贴在真实工具栏下方
//  (顶贴工具栏底边); 打开面板时真实工具栏进入编辑态 (晃动 + ⊖,
//  见 KeyboardToolbarView.enterToolbarCustomizeMode), 被编辑的那行
//  就是键盘界面上的那行、图标就是真实大小 (~24pt 按钮, 不是 56pt 圆)。
//  工具栏上的长按拖动换位/换侧、贴边吸附、提起动画都在工具栏本体上
//  (toolbarToolLongPressed), 面板只负责下面的工具池 + ✓ + 恢复默认。
//  下半工具池是两行、连续横向滑动的长条 (不要离散分页+页点):
//  贴纸按行优先排布, 每列最多 2 个 (池子只有两行高), 列数随工具数
//  增长: 9 个工具 = 5 列, 内容 468pt, 在 390pt 屏上可视 338pt,
//  可滑 130pt, 第 4 列露半边、提示可以左滑; 显示全部 9 个工具,
//  已在栏上的带绿底 (绿 = 在栏上, 与菜单绿格的"亲手加上去"不是同一回事)。
//  池子点按加入 (进左侧末尾, 可再拖); 点按已在栏上的绿贴纸是开关
//  (第 14 轮): 点一下从工具栏拿掉 (与 ⊖ 同一语义, 同时清掉
//  "亲手加上去"标记), 再点一下重新加入 (与点按加入同一入口 onAddTool)。
//  之前点绿的只给一个轻微缩放反馈, 没有实现开关。
//  池子贴纸也可以长按拿起、拖到真实工具栏上放下 (落点由调用方在栏上
//  插占位坑表示, 见 onPoolDragHover/onPoolDragDrop)。
//  "恢复默认"与 ✓ 同排放在面板顶行右侧, 省出纵向空间给两行池子
//  (面板只盖住按键区, 纵向比原来全屏时少 55pt 工具栏高度)。
//  没有上下滚动: 内容按行排布, 面板矮时 (小屏/横屏) 池高约束可压缩,
//  不报无法满足约束的警告 (与菜单面板 MenuTileButton 的 defaultHigh
//  格子高同理)。
//  工具注册表共 9 个 (剪贴板/常用语/切换26键·九宫格/立即同步剪贴板/
//  设置/常用语管理/粘贴/左移/右移, 后 3 个是第 15 轮加的;
//  "定制工具栏"本身是入口、不上栏, "收起键盘"是固定按钮、
//  也不上栏), 由调用方 (KeyboardToolbarView) 传入; 面板不自己决定有哪些工具。
//  菜单格子开关 (第 10 轮已删): 5 个菜单格子永远全部显示, 面板里不再有
//  开关, reload 也没有 tiles 参数。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上 (顶贴工具栏底边)。
//
//  绿底 (池子里"已在栏上变绿") 不归面板管: 面板只按调用方给的
//  onToolbarIDs 显示绿底, 自己不读写任何 UserDefaults。
//  标记规则 (第 12 轮已定): 标记只发生在调用方: 点按添加 / 池子拖入顶行
//  → onAddTool (调用方标记); 工具栏本体拖动换位/换侧 → 直接保存布局,
//  不走 onAddTool、不做"添加"标记 (拖动 ≠ 添加)。
//
//  拖动实现: 不用 UICollectionView 拖拽 API——池子是横向 UIScrollView,
//  用 UILongPressGestureRecognizer + 浮层快照:
//  · 池子: 长按提起贴纸快照, 拖进真实工具栏区域时调用方在栏上插占位坑
//    (见 onPoolDragHover), 松手放下 = 按坑位加入, 走 onPoolDragDrop
//    (调用方内部走 onAddTool 标记 + 按落点保存布局); 没放进工具栏则飞回源格子。
//  · 工具栏本体上的拖动不在这里 (见 KeyboardToolbarView.toolbarToolLongPressed)。
//  直接滑动池子横滑浏览 (按住不动才拿起, 一滑就滚动, 两者靠长按的移动
//  容限区分)。
//

import HamsterUIKit
import UIKit

/// 定制工具栏面板: 绿色 ✓ 圆钮 + "定制工具栏"标题 + 恢复默认
/// (顶行) + 白色圆角容器里的两行工具池 (连续横向滑动, 显示全部工具,
/// 已在栏上的带绿底, 点按加入) 。被编辑的工具栏是面板上方真实的
/// 键盘工具栏 (晃动 + ⊖), 不在面板里。
class KeyboardToolbarCustomizePanelView: NibLessView {
  /// 某一池中工具被点按加入时的回调 (toolID), 由调用方加进顺序并重建工具栏。
  /// 灰贴纸点按走这里 (与拖入同一入口, 标记为亲手加上去)。
  var onAddTool: ((String) -> Void)?
  /// 已在栏上的绿贴纸被点按时的回调 (toolID): 开关的"关"——
  /// 由调用方从工具栏拿掉 (与 ⊖ 同一语义: 顺序里删掉 + 隐藏 +
  /// 清掉"亲手加上去"标记), 池子绿底跟着去掉。灰贴纸不走这里。
  var onRemoveTool: ((String) -> Void)?
  /// 点"恢复默认"时的回调 (由调用方恢复默认顺序并全部显示, 再刷新列表)。
  var onReset: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?
  /// 池子贴纸拖到真实工具栏上方时: 手指在容器坐标系里的位置 ->
  /// 占位坑中心 (容器坐标系), 供快照落下动画用; 手指不在工具栏上时
  /// 返回 nil (调用方已把占位坑拿掉)。
  var onPoolDragHover: ((CGPoint) -> CGPoint?)?
  /// 池子贴纸按占位坑落进真实工具栏时的回调 (toolID), 由调用方按坑位
  /// 提交 (内部走 onAddTool 标记 + 按落点保存布局)。
  var onPoolDragDrop: ((String) -> Void)?
  /// 池子拖动取消/没放进工具栏时的回调: 调用方拿掉栏上的占位坑。
  var onPoolDragCancel: (() -> Void)?

  /// 工具元组 (id, 显示名, 图标)。
  private typealias Tool = (id: String, title: String, systemImage: String)

  /// 全部工具 (注册表顺序, 调用方传入)。
  private var allTools: [Tool] = []

  /// 当前在工具栏上的工具 id (池子里这些带绿底)。
  private var onToolbarIDs: Set<String> = []

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 注意: 不能用 .clear——第 3 轮的透明修法是错的, 面板是全屏覆盖层,
  /// 透明底会让键盘按键从列表后面透出来。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
    }
  }

  /// 每列贴纸数 (池子只有两行高, 每列最多 2 个; 列数 = 工具数向上取整
  /// 除以 2, 见 rebuildPool)。9 个工具 = 5 列, 内容 5*84+4*12=468pt;
  /// 390pt 屏上池子可视宽 342pt (屏宽 - 两侧 16pt 边距 - 两侧 8pt
  /// 内边距), 可滑 468-342=126pt, 第 4 列露半边、提示可以左滑。
  /// 之前列数固定封顶 4 列、6 个工具时内容只有 372pt、可滑约 34pt
  /// (不到半列), 用户说的"几乎滑不动"就是这个数。
  private static let poolRowsPerColumn = 2
  /// 每列宽度 (贴纸宽)。
  private static let poolColumnWidth: CGFloat = 84
  /// 工具池格高: 圆图标 36pt + 间距 3pt + 名称 11pt 两行 (26.4pt)
  /// + 底边 6pt = 71.4, 取整 72。
  /// 7 字名如“立即同步剪贴板”在 11pt 下一行放得下 (7×11=77 < 列宽
  /// 84 − 两侧 2pt), 两行是给更长名字的兜底; 格内留给名称的空间
  /// 是 72−36−3−6=27pt ≥ 两行 26.4pt, 不会把第二行挤掉。
  /// PoolToolView 的格高约束也用这个值 (fileprivate, 同文件共享)。
  /// 两排时 72*2+8=152pt。
  /// (build #51 反馈: 面板实测只有 223.7pt 高, 顶行 44pt + 底边 6pt,
  /// 容器最多 173.7pt; 旧格高 78 时容器要 186pt, 被压到 161.7pt,
  /// 第二行贴纸的文字被白卡下沿切掉。池子改紧凑后容器 152+16=168pt,
  /// 余 5.7pt。)
  fileprivate static let poolCellHeight: CGFloat = 72
  /// 工具池圆图标直径 (PoolToolView 也用这个值, 同文件共享)。
  /// 46 -> 36 (build #51 反馈: 池子改紧凑, 见 poolCellHeight)。
  static let poolCircleDiameter: CGFloat = 36
  /// 两行池高: 72*2+8=152pt (8 是列内两行间距, 见 makePoolColumn)。
  private static let poolHeight: CGFloat = poolCellHeight * 2 + 8
  /// 工具池容器圆角 (微信式白色大圆角容器)。
  private static let poolContainerCornerRadius: CGFloat = 16
  /// 工具池容器内边距 (10 -> 8, build #51 反馈: 池子改紧凑)。
  private static let poolContainerPadding: CGFloat = 8
  /// ✓ 确认圆钮直径 (与真实工具栏按钮同级大小, 不是原来 56pt 的大圆)。
  /// 32 -> 28 (build #51 反馈: 顶行省 4pt 给池子)。
  private static let checkmarkDiameter: CGFloat = 28
  /// 池子长按拿起的按住时长: 0.35 秒 (比默认 0.5 秒灵敏一点,
  /// 拿贴纸的手感更跟手; 手指直接滑动时滚动手势先走, 长按因移动
  /// 超限自动失败, 不会误拿)。
  private static let poolLongPressDuration: TimeInterval = 0.35
  /// 池子贴纸落到真实工具栏上时的缩放: 贴纸格 72pt 高, 落到 ~30pt
  /// 的工具按钮上约缩到一半。
  private static let poolDropLandingScale: CGFloat = 0.5

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

  /// 已在栏上的贴纸绿底 (与菜单格子 activeTileBackgroundColor 同一套绿,
  /// 浅色 12% / 深色 20% 透明度)。
  static let onToolbarTileBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor(red: 0.03, green: 0.76, blue: 0.38, alpha: 0.20)
      : UIColor(red: 0.03, green: 0.76, blue: 0.38, alpha: 0.12)
  }

  /// 已在栏上的贴纸图标绿 (与菜单格子 activeIconColor 同一套绿)。
  static let onToolbarIconColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor(red: 0.20, green: 0.85, blue: 0.50, alpha: 1)
      : UIColor(red: 0.03, green: 0.76, blue: 0.38, alpha: 1)
  }

  /// ✓ 关闭圆钮: 微信定制面板左上角的绿色实心圆 + 白色 ✓。
  private lazy var checkmarkCircleButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "checkmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 17, weight: .bold), scale: .default), forImageIn: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemGreen
    button.layer.cornerRadius = Self.checkmarkDiameter / 2
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  /// 顶行标题: 点开定制时一眼看出是在定制工具栏。
  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "定制工具栏"
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
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

  /// 工具池横向滚动容器: 连续滑动 (不要离散分页), 不显示滚动条。
  /// 内容比可视区宽半列, 下一列露半边、提示可以左滑。
  private lazy var poolScrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.isPagingEnabled = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.delaysContentTouches = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  /// 各列横向排列 (每列宽 84pt, 列内上下两行贴纸)。
  private lazy var poolColumnsStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private var poolHeightConstraint: NSLayoutConstraint?
  private var containerHeightConstraint: NSLayoutConstraint?

  /// 池子长按拖出的贴纸快照 (提起动画), 跟手指走; 原格子 alpha 0.35。
  private var poolDragSnapshot: UIView?
  /// 抓起瞬间手指相对快照中心的偏移 (第 14 轮: 拖动全程带着,
  /// 快照不跳到手指中心; 之前没有偏移, 第一次移动时快照会跳变)。
  private var poolDragGrabOffset: CGPoint = .zero
  /// 本次池子拖动拿起的工具。
  private var poolDragTool: Tool?
  /// 本次池子拖动的源格子 (取消时飞回 / 恢复透明用)。
  private var poolDragSourceTile: PoolToolView?
  /// 本次池子拖动放下时的落点中心 (面板坐标系, 由 onPoolDragHover 返回
  /// 的占位坑中心换算而来); nil 表示手指不在真实工具栏上。
  private var poolDropLandingCenter: CGPoint?
  /// 上一次池子拖动结束的时间戳 (秒): 长按识别后格子的点按手势
  /// 原则上会被取消, 但为防点按在松手后仍触发, 拖动结束 0.5 秒内
  /// 的池子点按直接忽略 (守卫在 makePoolTile 的 onTap 里)。
  private var poolDragEndedAt: TimeInterval = 0

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
    addSubview(titleLabel)
    addSubview(resetButton)
    addSubview(poolContainerView)
    poolContainerView.addSubview(poolScrollView)
    poolScrollView.addSubview(poolColumnsStackView)
    // 工具池长按拿起贴纸、拖到真实工具栏上放下 (见 handlePoolLongPress);
    // 与横滑手势并存 (见 gestureRecognizer:shouldRecognizeSimultaneouslyWith:)。
    let poolLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePoolLongPress(_:)))
    poolLongPress.minimumPressDuration = Self.poolLongPressDuration
    poolLongPress.delegate = self
    poolScrollView.addGestureRecognizer(poolLongPress)
  }

  override func activateViewConstraints() {
    poolHeightConstraint = poolScrollView.heightAnchor.constraint(equalToConstant: Self.poolHeight)
    // 面板矮时池高可压缩 (defaultHigh), 不报无法满足约束的警告;
    // 压掉的是第二行格子的高度, 第一行不受影响。
    poolHeightConstraint?.priority = .defaultHigh
    containerHeightConstraint = poolContainerView.heightAnchor.constraint(equalToConstant: Self.poolHeight + Self.poolContainerPadding * 2)
    containerHeightConstraint?.priority = .defaultHigh
    NSLayoutConstraint.activate([
      checkmarkCircleButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      checkmarkCircleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      checkmarkCircleButton.widthAnchor.constraint(equalToConstant: Self.checkmarkDiameter),
      checkmarkCircleButton.heightAnchor.constraint(equalToConstant: Self.checkmarkDiameter),

      titleLabel.leadingAnchor.constraint(equalTo: checkmarkCircleButton.trailingAnchor, constant: 10),
      titleLabel.centerYAnchor.constraint(equalTo: checkmarkCircleButton.centerYAnchor),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -8),

      resetButton.centerYAnchor.constraint(equalTo: checkmarkCircleButton.centerYAnchor),
      resetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      resetButton.heightAnchor.constraint(equalToConstant: 32),

      poolContainerView.topAnchor.constraint(equalTo: checkmarkCircleButton.bottomAnchor, constant: 8),
      poolContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      poolContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      containerHeightConstraint!,
      // 容器底钉在面板底边 −6, 不要钉安全区底边: 面板底 = 键盘底,
      // 安全区底边比面板底高约 24pt (Home Indicator 区), required 的
      // 底约束会与 defaultHigh 的容器高打架。
      // build #51 实测: 面板高只有 223.7pt (九宫格竖屏, 17 Pro Max),
      // 顶行 8+28+8=44pt + 底边 6pt, 容器最多 173.7pt; 旧容器
      // 186pt 时被压到 161.7pt, 第二行贴纸的文字被白卡下沿切掉。
      // 池子改紧凑后容器 168pt, 余 5.7pt, 不再顶着底约束。
      // 面板是盖在按键区上的覆盖层, 容器底落在键盘底部留白区, 不压按键。
      poolContainerView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),

      poolScrollView.topAnchor.constraint(equalTo: poolContainerView.topAnchor, constant: Self.poolContainerPadding),
      poolScrollView.leadingAnchor.constraint(equalTo: poolContainerView.leadingAnchor, constant: Self.poolContainerPadding),
      poolScrollView.trailingAnchor.constraint(equalTo: poolContainerView.trailingAnchor, constant: -Self.poolContainerPadding),
      poolHeightConstraint!,

      // 横向连续滚动的标准约束: 内容栈贴 contentLayoutGuide,
      // 高度等于 frame 高度 (两行贴纸同高)。
      poolColumnsStackView.topAnchor.constraint(equalTo: poolScrollView.contentLayoutGuide.topAnchor),
      poolColumnsStackView.bottomAnchor.constraint(equalTo: poolScrollView.contentLayoutGuide.bottomAnchor),
      poolColumnsStackView.leadingAnchor.constraint(equalTo: poolScrollView.contentLayoutGuide.leadingAnchor),
      poolColumnsStackView.trailingAnchor.constraint(equalTo: poolScrollView.contentLayoutGuide.trailingAnchor),
      poolColumnsStackView.heightAnchor.constraint(equalTo: poolScrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来 (第 3 轮改成 .clear 是错的)。
    // 深色模式下底色是深灰 (#2C2C2C), 不是纯黑, 所以不会再出现黑斑。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新工具池: 全部工具 (注册表顺序) + 已在栏上的 id 集合 (绿底)。
  /// 注意: 参数写完整元组类型, 不用上面私有的 Tool 别名——reload 是
  /// 跨文件调用的内部方法, 签名里用私有别名编译不过。
  func reload(allTools: [(id: String, title: String, systemImage: String)], onToolbarIDs: Set<String>) {
    self.allTools = allTools
    self.onToolbarIDs = onToolbarIDs
    rebuildPool()
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func resetTapped() {
    onReset?()
  }

  // MARK: - 工具池长按拖动 (贴纸拿起 -> 拖到真实工具栏上放下)

  /// 池子贴纸长按拖动: 按住不动 0.35 秒提起贴纸快照 (放大 + 阴影),
  /// 拖进真实工具栏区域时调用方在栏上插占位坑 (onPoolDragHover 返回
  /// 坑中心供快照落下动画用), 松手放下 = 按坑位加入工具栏
  /// (onPoolDragDrop, 调用方内部走 onAddTool 标记 + 按落点保存布局);
  /// 没放进工具栏则飞回源格子, 什么都不改。
  /// 拖动时关掉池子横滑滚动; 手指直接滑动时滚动手势先走, 长按因
  /// 移动超限自动失败, 所以“滑动浏览”和“按住拿起”不会打架。
  /// 已在栏上的绿贴纸拿不起来 (拖进工具栏没有意义); 点按是开关的"关"
  /// (见 PoolToolView.tapped -> onToggleOff -> onRemoveTool)。
  @objc private func handlePoolLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      let point = gesture.location(in: poolScrollView)
      guard let hitView = poolScrollView.hitTest(point, with: nil),
            let tile = ancestorPoolTile(of: hitView),
            !tile.isOnToolbar,
            poolDragSnapshot == nil,
            let snapshot = tile.snapshotView(afterScreenUpdates: true) else { return }
      poolDragTool = tile.tool
      poolDragSourceTile = tile
      poolDropLandingCenter = nil
      poolScrollView.isScrollEnabled = false
      // 提起动画: 原格子半透明, 快照放大 + 阴影浮起来跟手指走;
      // 抓起偏移一直带着, 快照不跳到手指中心。
      tile.alpha = 0.35
      snapshot.frame = convert(tile.bounds, from: tile)
      snapshot.isUserInteractionEnabled = false
      snapshot.layer.shadowColor = UIColor.black.cgColor
      snapshot.layer.shadowOpacity = 0.25
      snapshot.layer.shadowRadius = 8
      snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
      snapshot.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
      addSubview(snapshot)
      poolDragSnapshot = snapshot
      let fingerInSelf = gesture.location(in: self)
      poolDragGrabOffset = CGPoint(x: fingerInSelf.x - snapshot.center.x, y: fingerInSelf.y - snapshot.center.y)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .changed:
      guard let snapshot = poolDragSnapshot, poolDragTool != nil else { return }
      let pointInSelf = gesture.location(in: self)
      // 快照跟手指走 (x 和 y 都跟, 抓起偏移一直带着, 不跳变)。
      snapshot.center = CGPoint(x: pointInSelf.x - poolDragGrabOffset.x, y: pointInSelf.y - poolDragGrabOffset.y)
      // 手指在容器坐标系里的位置 -> 调用方在真实工具栏上插占位坑,
      // 返回坑中心 (容器坐标系); 不在工具栏上时返回 nil (坑已拿掉)。
      // 注意: onPoolDragHover 返回的是 CGPoint? (坑中心), 而闭包本身
      // 也是可选的, 可选链会包两层 Optional, 用 ?? nil 压回一层。
      if let container = superview, let landingInContainer = onPoolDragHover?(convert(pointInSelf, to: container)) ?? nil {
        poolDropLandingCenter = convert(landingInContainer, from: container)
      } else {
        poolDropLandingCenter = nil
      }
    case .ended, .cancelled:
      guard let snapshot = poolDragSnapshot, let tool = poolDragTool else { return }
      let ended = gesture.state == .ended
      let landingCenter = poolDropLandingCenter
      let sourceTile = poolDragSourceTile
      poolDragSnapshot = nil
      poolDragTool = nil
      poolDragSourceTile = nil
      poolDropLandingCenter = nil
      poolDragGrabOffset = .zero
      poolScrollView.isScrollEnabled = true
      poolDragEndedAt = Date().timeIntervalSince1970
      if ended, let landingCenter {
        // 放下进真实工具栏: 调用方按占位坑提交 (走 onAddTool 标记 +
        // 按落点保存布局, 见 KeyboardToolbarView.poolDragDrop)。
        onPoolDragDrop?(tool.id)
        // 快照飞向栏上的落点、缩到工具按钮大小、淡出, 再消失。
        UIView.animate(withDuration: 0.18, animations: {
          snapshot.center = landingCenter
          snapshot.transform = CGAffineTransform(scaleX: Self.poolDropLandingScale, y: Self.poolDropLandingScale)
          snapshot.alpha = 0
        }, completion: { _ in snapshot.removeFromSuperview() })
      } else {
        // 没放进工具栏 (取消 / 松手时不在工具栏上): 占位坑拿掉,
        // 快照飞回源格子, 源格子恢复, 什么都不改。
        onPoolDragCancel?()
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

  // MARK: - 可选工具池 (下半: 两行贴纸, 连续横向滑动)

  /// 按 allTools 重建两行横滑长条: 行优先排布 (每列最多 2 个贴纸),
  /// 9 个工具 = 5 列, 内容 468pt, 比 390pt 屏上 338pt 可视区宽 130pt。
  /// 全部工具都显示, 已在栏上的带绿底 (不隐藏、不进"已上栏就消失"的旧逻辑)。
  /// 旧算法列数固定封顶 4 列 (index % 4): 9 个工具时第 0 列会塞进
  /// 3 个贴纸 (0、4、8 号), 把列撑出两行高; 现在列数 = 工具数
  /// 向上取整除以 2, 每列最多 2 个, 不会再撑出池高。
  private func rebuildPool() {
    // 旧列必须先从 arrangedSubviews 里摘掉再移出层级: 只调
    // removeFromSuperview 不会把它从 arrangedSubviews 摘掉, 旧列的约束
    // (列宽 84) 会残留 (菜单面板第 8 轮同款修法)。
    poolColumnsStackView.arrangedSubviews.forEach {
      poolColumnsStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    guard !allTools.isEmpty else { return }
    let columnCount = (allTools.count + Self.poolRowsPerColumn - 1) / Self.poolRowsPerColumn
    var columns: [[Tool]] = Array(repeating: [], count: columnCount)
    for (index, tool) in allTools.enumerated() {
      columns[index % columnCount].append(tool)
    }
    for columnTools in columns {
      poolColumnsStackView.addArrangedSubview(makePoolColumn(with: columnTools))
    }
  }

  /// 一列 (上下两行贴纸, 列宽 84pt)。
  private func makePoolColumn(with tools: [Tool]) -> UIStackView {
    let column = UIStackView()
    column.axis = .vertical
    column.spacing = 8
    column.translatesAutoresizingMaskIntoConstraints = false
    column.widthAnchor.constraint(equalToConstant: Self.poolColumnWidth).isActive = true
    for tool in tools {
      column.addArrangedSubview(makePoolTile(tool))
    }
    // 不满 2 个时用空白占位补齐, 保持列高等 (否则单贴纸的列会被纵向拉伸)。
    while column.arrangedSubviews.count < 2 {
      let spacer = UIView()
      spacer.translatesAutoresizingMaskIntoConstraints = false
      column.addArrangedSubview(spacer)
    }
    return column
  }

  private func makePoolTile(_ tool: Tool) -> PoolToolView {
    let tile = PoolToolView(tool: tool, isOnToolbar: onToolbarIDs.contains(tool.id))
    tile.onTap = { [weak self] in
      guard let self else { return }
      // 刚结束池子拖动 0.5 秒内的点按是长按松手带出来的, 忽略
      // (长按识别后点按手势原则上会被取消, 这里是双保险)。
      if Date().timeIntervalSince1970 - self.poolDragEndedAt < 0.5 { return }
      self.onAddTool?(tool.id)
    }
    tile.onToggleOff = { [weak self] in
      guard let self else { return }
      // 与加入同一道守卫: 刚结束拖动 0.5 秒内的点按忽略, 免得
      // 长按松手把刚拖过的绿贴纸又关掉。
      if Date().timeIntervalSince1970 - self.poolDragEndedAt < 0.5 { return }
      self.onRemoveTool?(tool.id)
    }
    return tile
  }
}

// MARK: - UIGestureRecognizerDelegate (池子长按与横滑并存)

extension KeyboardToolbarCustomizePanelView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // 只放行池子长按 + 横滑手势并存: 手指按住不动 0.35 秒 → 长按触发、
    // 关掉滚动开始拖贴纸; 手指直接滑动 → 横滑手势先走、长按因移动超限
    // 自动失败。其他手势组合一律不并存。
    otherGestureRecognizer == poolScrollView.panGestureRecognizer
  }
}

// MARK: - 工具池格子

/// 工具池格子: 小圆图标 + 名称 (微信式), 点按加入 / 点绿拿掉。
/// 圆底在白容器里用浅灰 (浅色) / 半透明白 (深色) 才看得出;
/// 已在栏上的带绿底 + 绿图标 (只表示在栏上)。
/// 微信的池子里没有 + 标记, 点按即加入, 这里也不加。
private class PoolToolView: UIView {
  let tool: (id: String, title: String, systemImage: String)

  /// 是否已在工具栏上: 是则绿底, 点按 = 开关关掉 (onToggleOff),
  /// 长按不拿起 (已在栏上, 拖进工具栏没有意义)。
  let isOnToolbar: Bool

  var onTap: (() -> Void)?
  /// 已在栏上的绿贴纸被点按时的回调 (开关关掉, 见面板的 onRemoveTool)。
  var onToggleOff: (() -> Void)?

  /// 圆图标底。
  private let circleView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = KeyboardToolbarCustomizePanelView.poolCircleBackgroundColor
    view.layer.cornerRadius = KeyboardToolbarCustomizePanelView.poolCircleDiameter / 2
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
    label.font = .systemFont(ofSize: 11)
    label.textColor = .label
    label.textAlignment = .center
    // 7 字工具名 ("立即同步剪贴板") 在列宽 84 的格子里也可能折行, 允许两行。
    label.numberOfLines = 2
    return label
  }()

  init(tool: (id: String, title: String, systemImage: String), isOnToolbar: Bool) {
    self.tool = tool
    self.isOnToolbar = isOnToolbar
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
    // 已在栏上的绿底 + 绿图标 (只表示在栏上, 与"亲手加上去"无关)。
    if isOnToolbar {
      circleView.backgroundColor = KeyboardToolbarCustomizePanelView.onToolbarTileBackgroundColor
      iconImageView.tintColor = KeyboardToolbarCustomizePanelView.onToolbarIconColor
    }
    // 格子高与 poolCellHeight 一致 (72pt: 圆 36 + 间距 3 + 两行名称 11pt);
    // 是期望值, 不是硬性: 面板矮时 (小屏/横屏) 可压缩,
    // 避免“无法同时满足约束”的警告 (菜单面板 MenuTileButton 同款)。
    let tileHeightConstraint = heightAnchor.constraint(equalToConstant: KeyboardToolbarCustomizePanelView.poolCellHeight)
    tileHeightConstraint.priority = .defaultHigh
    NSLayoutConstraint.activate([
      tileHeightConstraint,

      circleView.topAnchor.constraint(equalTo: topAnchor),
      circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
      circleView.widthAnchor.constraint(equalToConstant: KeyboardToolbarCustomizePanelView.poolCircleDiameter),
      circleView.heightAnchor.constraint(equalToConstant: KeyboardToolbarCustomizePanelView.poolCircleDiameter),

      iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
      iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
      iconImageView.heightAnchor.constraint(equalToConstant: 22),
      iconImageView.widthAnchor.constraint(equalToConstant: 22),

      titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 3),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      // 第 14 轮: 底边留 6pt (原来 -2pt): 面板矮时格高被压缩
      // (格高约束是 defaultHigh), 文字底边会被压到离白框底边只剩
      // 约 1.5pt (build #36 实测); -6pt 保证压缩后文字与底框
      // 仍有 6pt 间隔, 不贴边。未压缩时文字位置由 top 锚定, 不变。
      titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
    ])
    titleLabel.text = tool.title
    iconImageView.image = UIImage(
      systemName: tool.systemImage,
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 20)))
    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    addGestureRecognizer(tap)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func tapped() {
    if isOnToolbar {
      // 已在栏上: 点按是开关的"关"——从工具栏拿掉 (调用方走
      // onRemoveTool, 与 ⊖ 同一语义 + 清掉"亲手加上去"标记);
      // 拿掉后池子重建, 这格变回灰色 (反馈就是颜色本身)。
      onToggleOff?()
      return
    }
    onTap?()
  }
}
