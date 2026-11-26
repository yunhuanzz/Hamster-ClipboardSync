//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图

 工具栏左侧菜单 (点左上角图标打开, 仿微信输入法):
 4 列宫格面板, 含剪贴板 / 常用语 / 切换26键·九宫格 /
 定制工具栏 / 设置 (共 5 格)。
 格子图标是开关: 点一下打开菜单, 再点一下关闭; 打开时有 0.2s
 淡入 + 上滑动画。⌄ 按钮只负责收起键盘。
 工具栏按钮: 6 个工具 (剪贴板 / 常用语 / 切换26键·九宫格 /
 立即同步 / 设置 / 常用语管理) 都可上栏, 通过"定制工具栏"
 自由拖动排序、⊖ 拿掉 (回工具池)、点按加入; 顺序存在共享
 UserDefaults (toolbarToolsOrder)。
 第 14 轮起"立即同步剪贴板"和"常用语管理"不在菜单宫格里
 (剪贴板面板里本来就有立即同步药丸按钮, 常用语面板里本来就
 能编辑/删除, 添加走常用语管理面板), 但仍是可上栏的工具 (工具池里还在),
 工具栏按钮与菜单格子是两套注册表, 见 menuTiles() /
 toolbarToolDefinitions()。
 每个工具还有一侧属性 (左/右, toolbarToolSides, 第 9 轮):
 长按拖到工具栏左半区进左侧、右半区进右侧, 松手保存;
 格子图标钉死最左、收起键盘 (⌄) 钉死最右。
 第 5 轮的左/中/右三分区被换掉, 是因为那版面板只是个只能排序的
 下拉列表、用户说"完全没用", 不是他不要左右摆放——这次做对:
 可视化拖动到左/右半区, 定制面板里也按左/右侧分组显示。
 收起键盘 (⌄) 是钉死在工具栏最右的固定按钮, 不参与排序、
 不在菜单格子里、也不在可定制工具里 (第 7 轮, 用户要求)。
 第 6 轮起不再用左/中/右分区 (toolbarToolZones 留着不用, 不删已存数据)。
 第 13 轮: 定制面板不再画放大的工具栏复制品, 而是顶贴工具栏底边、
 只盖住按键区; 打开面板时工具栏本身进入编辑态 (晃动 + ⊖),
 长按拖动换位/换侧、贴边吸附都在工具栏本体上 (第 12 轮面板顶行
 的那套行为搬过来), 面板只剩两行连续横滑的工具池 + ✓ + 恢复默认。
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// 常用功能项: 左上角菜单按钮 (点开宫格菜单)。点按时系统自动高亮图标。
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "square.grid.2x2"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(menuButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(menuButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 解散键盘 Button (plain 下箭头 ⌄, 与工具栏其他按钮同一套 18pt SF Symbols)。
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 剪贴板 Button (最近剪贴板历史)
  lazy var clipboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "list.bullet.clipboard"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(clipboardButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(clipboardButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 常用语 Button
  lazy var phrasesButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "quote.bubble"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(phrasesButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(phrasesButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 切换 26 键/九宫格 Button (图标与菜单格子一致: keyboard)。
  lazy var switchLayoutButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "keyboard"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(switchLayoutButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(switchLayoutButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 立即同步剪贴板 Button。
  lazy var syncNowButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(syncNowButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(syncNowButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 设置 Button (打开 App)。
  lazy var settingsButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "gear"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(settingsButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(settingsButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 常用语管理 Button (键盘内编辑常用语)。
  lazy var managePhrasesButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(managePhrasesButtonTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(managePhrasesButtonTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 微信式粘贴提示行: 剪贴板文字在左 (点按粘贴), 右侧 ⌄ 展开 + X 关闭并排。
  /// 展示时工具栏其他按钮暂时隐藏。只在未输入时显示。
  /// 行本身透明 (不要药丸底): 直接落在工具栏区域已有的键盘底色上,
  /// 文字 + ⌄ + ✕ 直接贴在灰底上 (仿微信); 白色圆角条在深浅模式都难看。
  private lazy var pasteRowView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  /// 粘贴提示行左侧标识图标: 小剪贴板 (list.bullet.clipboard, 灰色), 一眼看出
  /// 这行是剪贴板来的内容, 不是 RIME 候选词。纯展示, 不接收触摸。
  private lazy var pasteRowIconView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.image = UIImage(
      systemName: "list.bullet.clipboard",
      withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15, weight: .medium)))
    imageView.tintColor = .secondaryLabel
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = false
    return imageView
  }()

  /// 粘贴提示行右侧: 向下箭头 ⌄ (微信式, 点按展开复制内容、分段粘贴)。
  /// 注意: 微信里的这个 ⌄ 是展开复制内容、智能分段、选一段粘贴, 不是隐藏键盘
  /// (第 3 轮把它做成隐藏键盘是理解错了); 隐藏键盘只作为工具栏工具。
  private lazy var pasteRowExpandButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 16, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .secondaryLabel
    button.addTarget(self, action: #selector(pasteRowExpandTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行中间: 剪贴板文字 (单行截断, 点按粘贴)。
  /// 字号与候选栏正常候选字同级 (style.candidateTextFont, 配置 18pt),
  /// 之前 14pt 太小 (用户反馈)。
  private lazy var pasteRowTextButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.titleLabel?.font = style.candidateTextFont
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.setTitleColor(.label, for: .normal)
    button.contentHorizontalAlignment = .left
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
    button.addTarget(self, action: #selector(pasteRowTextTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行右侧: X (关闭提示, 相同内容不再重复提示)。
  private lazy var pasteRowCloseButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 14), scale: .default), forImageIn: .normal)
    button.tintColor = .secondaryLabel
    button.addTarget(self, action: #selector(pasteRowCloseTapped), for: .touchUpInside)
    return button
  }()

  /// 粘贴提示行当前展示的剪贴板文本 (nil 表示未展示)
  private var clipboardChipText: String?
  /// 当前剪贴板 changeCount (整数, 读它不弹"粘贴自xxx"横幅)。
  /// 忽略记录以它为准: 剪贴板一换内容它就移动, 忽略即失效。
  private var currentPasteboardChangeCount: Int {
    #if canImport(UIKit)
      return UIPasteboard.general.changeCount
    #else
      return -1
    #endif
  }
  /// 上次读取剪贴板内容时的 changeCount。只在 changeCount 变化时才重读剪贴板
  /// (读剪贴板会弹"粘贴自xxx"横幅), 其余时候只用缓存展示, 绝不重复读。
  /// -1 表示从未读过。
  private var lastChipChangeCount: Int = -1
  /// 上次读到的剪贴板文本缓存 (打字/输入变化时只用缓存展示, 不读剪贴板)。
  private var lastReadPasteboardText: String?
  /// 粘贴提示行是否正在展示 (展示时工具栏其他按钮暂时隐藏)。
  private var isPasteRowVisible = false

  /// 工具栏长按拖动/删除 (第 8 轮): 长按任一工具图标可横向拖动换位,
  /// 松手即保存顺序; 长按不动松手则在该图标右上角出一个红 ⊖,
  /// 点 ⊖ 把工具拿下工具栏 (回工具池, 与定制面板的 ⊖ 同一效果)。
  /// 菜单格子图标与 ⌄ 收起键盘不挂长按, 不参与拖动/删除。
  /// 第 9 轮: 长按即进定制态——全部工具图标像 iOS 主屏幕编辑态一样
  /// 晃动并显示 ⊖ (小号, 见 showToolbarDeleteBadges); 拖到工具栏
  /// 左半区进左侧、右半区进右侧, 松手保存侧 + 顺序并退出定制态;
  /// 原地长按松手留在定制态, 3 秒无操作自动退出 (点 ⊖ 删工具后
  /// 仍留在定制态, 可连续删; 点格子图标/⌄/重建工具栏也退出)。
  private var toolbarDraggedToolID: String?
  private var toolbarDragStartX: CGFloat = 0
  private var toolbarDragMoved = false
  /// 工具栏长按拖动的浮层快照 (跟手指走, 第 14 轮): .began 时从被拖按钮
  /// 拍一张, 原按钮 alpha 0 留在栈里当"活占位坑" (其余按钮随手指实时
  /// 换位), 快照中心 = 手指位置 - 抓起偏移 (不跳变); 松手时飞回按钮
  /// 落点再消失。之前没有快照, 图标只在原位放大 1.15×、不跟手指,
  /// y 还钉在行中心线上, 用户感觉"手指在哪图标不在哪"。
  private var toolbarDragSnapshot: UIView?
  /// 抓起瞬间手指相对快照中心的偏移 (拖动全程带着, 快照不跳到手指中心)。
  private var toolbarDragGrabOffset: CGPoint = .zero
  /// 定制态 (晃动 + ⊖) 是否开着。
  private var isToolbarCustomizeMode = false
  /// 定制态无操作自动退出定时器 (3 秒)。
  private var toolbarCustomizeModeTimer: Timer?
  /// 定制态下每个工具图标右上角的小红 ⊖ (toolID -> 标记按钮)。
  private var toolbarDeleteBadges: [String: UIButton] = [:]

  /// 定制面板是否开着 (第 13 轮): 开着时工具栏本身就是被编辑的那行,
  /// exitToolbarCustomizeMode() 在此期间不生效, 免得 3 秒定时器或
  /// rebuildToolbarButtons() 把编辑态关掉; 面板关闭时
  /// (dismissCustomizePanel) 先清掉这个标记再退出编辑态。
  private var customizePanelOpen = false
  /// 池子贴纸拖到真实工具栏上时的占位坑 (插进左/右组栈里表示落点)。
  private var poolDropPlaceholder: UIView?
  /// 池子贴纸拖到真实工具栏上时的落点 (侧 + 组内下标)。
  private var poolDropTarget: (isRight: Bool, index: Int)?
  /// 工具栏拖动本次进入的贴边吸附侧 (nil = 未吸附), 进区只震一次。
  private var toolbarDragSnappedRight: Bool?
  /// 工具栏拖动贴边吸附区宽度 (与第 12 轮定制面板顶行一致)。
  private static let toolbarSnapEdgeWidth: CGFloat = 48

  /// 当前展示的文本列表面板 (剪贴板 / 常用语), 覆盖在键盘根视图上
  private var textListPanel: KeyboardTextListPanelView?

  /// 当前展示的定制工具栏面板, 覆盖在键盘根视图上
  private var customizePanel: KeyboardToolbarCustomizePanelView?

  /// 当前展示的功能菜单宫格面板, 覆盖在键盘根视图上
  private var menuPanel: KeyboardToolbarMenuPanelView?

  /// 当前展示的常用语管理面板, 覆盖在键盘根视图上
  private var phrasesEditorPanel: KeyboardCommonPhrasesEditorPanelView?

  /// 当前展示的粘贴内容分段展开面板, 覆盖在键盘根视图上
  private var segmentsPanel: KeyboardPasteSegmentsPanelView?

  /// 当前展示的剪贴板全文展开视图, 覆盖在键盘根视图上 (长按剪贴板条目打开;
  /// 关闭后回到底下的剪贴板面板, 第 17 轮第 6 项)
  private var expandedClipboardView: KeyboardClipboardExpandedView?

  /// 临时复制工具图标 (第 17 轮第 5 项, 反馈修): 粘贴提示行正在展示时用户开始打字,
  /// 临时复制图标: 裸图标, 与其他工具栏工具一致 (无背景, 无边框)。
  /// 微信的白圆按钮成立, 是因为它的工具都有白色背景; 我们的工具没有背景色,
  /// 照搬白圆反而破坏统一, 所以这里只靠图标本身区分:
  /// SF `doc.on.doc` (两页纸) vs 剪贴板的 `list.bullet.clipboard`
  /// (带圆点横线的剪贴板)。第 17 轮反馈的手画图标 (文档 + 带横线剪贴板)
  /// 在真机上显臃肿、与美术不统一, 已删掉, 改回系统图标。
  /// 点按打开复制内容 (分段面板), 打开后无论粘贴与否图标都收掉 (一次性)。
  private lazy var tempCopyButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.backgroundColor = .clear
    button.isHidden = true
    button.addTarget(self, action: #selector(tempCopyButtonTapped), for: .touchUpInside)
    return button
  }()

  /// 临时复制图标的纵向锚点 (两条互斥, 见 updateTempCopyVerticalAnchor):
  /// 候选栏在展示时钉在拼音行内 (top+12, 第 17 轮设计);
  /// 工具栏在展示时与工具行垂直居中 (commonFunctionBar.centerY)。
  /// 只钉 top+12 是 build #50 的位置 bug: 打字停后候选栏收起、工具栏
  /// 回来, 图标还留在拼音行高度, 比工具行高约 13pt, 看着飘在中间。
  private var tempCopyCenterYPhoneticConstraint: NSLayoutConstraint?
  private var tempCopyCenterYToolbarConstraint: NSLayoutConstraint?

  /// 临时撤回图标 (上滑回退整段删除后出现, 防误删): 与临时复制图标
  /// 同一套瞬态模式——不在 toolbarToolDefinitions、不进菜单、不进定制池;
  /// SF `arrow.uturn.backward`, .label、裸图标。位置在右侧固定工具组左侧,
  /// 临时复制图标同时在时排在它左边 (见 updateTransientButtonsLayout)。
  /// 点按把快照文本原样插回光标处 (走 insertPastedText, 不经过 RIME)。
  private lazy var undoDeleteButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.backgroundColor = .clear
    button.isHidden = true
    button.addTarget(self, action: #selector(undoDeleteButtonTapped), for: .touchUpInside)
    return button
  }()

  /// 撤回快照的横向锚点 (两条互斥, 见 updateTransientButtonsLayout):
  /// 临时复制图标在时贴它左边, 不在时直接贴右侧工具组左边。
  private var undoTrailingToTempCopyConstraint: NSLayoutConstraint?
  private var undoTrailingToRightStackConstraint: NSLayoutConstraint?

  /// 撤回图标对应的删除快照 (与控制器里的 undoDeleteSnapshot 同步,
  /// 以控制器的通知为准; 只在图标展示时有值)。
  private var undoDeleteText: String?

  // 临时复制图标: SF `doc.on.doc` (见 tempCopyButton)。
  // 不用 `doc.on.clipboard`: 它的剪贴板底是实心黑块, 用户觉得太黑
  // (第 17 轮反馈); 手画版 (文档 + 带横线剪贴板) 在真机上显臃肿、
  // 与美术不统一, 已删掉。

  /// 折叠进临时图标的那条复制内容 (nil 表示没有折叠态)。
  private var tempCopyText: String?

  // TODO: 常用功能栏
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    return view
  }()

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    // KeyboardToolbarView 为 candidateBarStyle 样式根节点, 这里生成一次，减少计算次数
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupSubview()

    combine()

    // 同步完成 (上传/下载结束) 后刷新粘贴提示: PC 复制的内容下载到本机后也会出现。
    NotificationCenter.default.addObserver(
      self, selector: #selector(syncDidFinish),
      name: ClipboardSyncService.didFinishNotification, object: nil)

    // 上滑回退整段删除后控制器发来撤回快照变化 (出现/消失): 工具栏
    // 据此展示或收掉临时撤回图标 (不经过 RIME, 也不进工具栏菜单/定制池)。
    NotificationCenter.default.addObserver(
      self, selector: #selector(undoDeleteSnapshotDidChange(_:)),
      name: KeyboardInputViewController.didChangeUndoDeleteSnapshotNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }
  }

  /// 键盘弹出/回到窗口时刷新粘贴提示并启动定期同步;
  /// 键盘隐藏时停止定期同步并关掉覆盖面板。
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      refreshClipboardChip()
      startSyncTimer()
    } else {
      stopSyncTimer()
      // 隐藏键盘等同于忽略当前正在展示的粘贴提示: 持久化记录,
      // 下次打开不再重推同一内容, 除非剪贴板换了新内容。
      // 已折叠进临时图标的内容同理 (同一条, 只是换了个形态)。
      if let text = clipboardChipText ?? tempCopyText, !text.isEmpty {
        UserDefaults.hamster.markClipboardChipDismissed(
          hash: ClipboardSyncService.sha256(text),
          changeCount: currentPasteboardChangeCount)
      }
      hideClipboardChip()
      hideTempCopyIcon()
      // 键盘收起/关闭: 撤回快照作废 (临时撤回图标随之消失)。
      // 只清图标不够——控制器的快照是单一事实来源, 不清掉的话
      // 下次打开键盘还会把图标推出来。
      hideUndoDeleteButton()
      keyboardInputController?.invalidateUndoDeleteSnapshot()
      dismissAllPanels()
    }
  }

  /// 键盘打开期间的定期同步定时器 (每 1 秒): 键盘开着时复制的内容
  /// (本机或 PC) 不用等关闭重开就能同步, 连续复制的间隔也不再受节流拖累。
  /// 失败静默, 不阻塞打字; 键盘隐藏时停止。
  private var syncTimer: Timer?

  private func startSyncTimer() {
    stopSyncTimer()
    guard UserDefaults.hamster.clipboardSyncEnabled else { return }
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.syncTimerTick()
    }
    // .common: 打字/滑动时 (UITracking) 也照常触发
    RunLoop.main.add(timer, forMode: .common)
    syncTimer = timer
  }

  private func stopSyncTimer() {
    syncTimer?.invalidate()
    syncTimer = nil
  }

  /// 定时器每拍: 同步一次。服务内部用 changeCount 判断本机剪贴板是否真变了,
  /// 没变不读剪贴板、不弹横幅; 每拍都拉取服务器, PC 复制的内容 1 秒内到达,
  /// 到达后发通知刷新粘贴提示与状态行。
  private func syncTimerTick() {
    guard window != nil else {
      stopSyncTimer()
      return
    }
    guard UserDefaults.hamster.clipboardSyncEnabled else {
      stopSyncTimer()
      return
    }
    ClipboardSyncService.shared.syncNow()
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    setupPasteRow()
    setupTempCopyButton()
    setupUndoDeleteButton()
    rebuildToolbarButtons()
  }

  /// 临时复制图标: 钉在右侧固定工具组的左侧
  /// (2026-11-26 用户要求: 临时复制排在固定工具左侧, 右端不再贴边;
  /// 横向锚点挂在 setupToolsStackLayoutIfNeeded 里, 右侧工具组建好之后才有共同祖先)。
  /// 高 24pt。纵向锚点分两种状态 (见 updateTempCopyVerticalAnchor):
  /// 候选栏在展示时钉在拼音行内 (top+12: 拼音行默认高 15pt, 图标上下各探出几 pt,
  /// 只盖住候选字行顶缘与展开 chevron 的顶端空白, 不盖候选字本身);
  /// 工具栏在展示时与工具行垂直居中 (commonFunctionBar.centerY)。
  /// 内嵌模式下没有拼音行, 同样贴在顶部, 位置不变。
  private func setupTempCopyButton() {
    addSubview(tempCopyButton)
    tempCopyCenterYPhoneticConstraint = tempCopyButton.centerYAnchor.constraint(equalTo: topAnchor, constant: 12)
    tempCopyCenterYToolbarConstraint = tempCopyButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor)
    NSLayoutConstraint.activate([
      tempCopyCenterYPhoneticConstraint,
      tempCopyButton.heightAnchor.constraint(equalToConstant: 24),
      tempCopyButton.widthAnchor.constraint(equalToConstant: 24),
    ].compactMap { $0 })
    updateTempCopyVerticalAnchor()
  }

  /// 临时撤回图标: 钉在右侧固定工具组的左侧 (或临时复制图标左侧,
  /// 见 updateTransientButtonsLayout); 纵向与临时复制图标对齐
  /// (centerY == tempCopyButton.centerY, 所以跟它一样随状态切换锚点)。
  private func setupUndoDeleteButton() {
    addSubview(undoDeleteButton)
    NSLayoutConstraint.activate([
      undoDeleteButton.centerYAnchor.constraint(equalTo: tempCopyButton.centerYAnchor),
      undoDeleteButton.heightAnchor.constraint(equalToConstant: 24),
      undoDeleteButton.widthAnchor.constraint(equalToConstant: 24),
    ])
  }

  /// 粘贴提示行: 加入工具栏并定好内部布局 (默认隐藏)。
  /// 微信式布局: 文字在左占满剩余宽度, ⌄ 展开与 X 关闭并排在右。
  /// 粘贴行里不再放隐藏键盘——隐藏键盘只作为工具栏工具。
  private func setupPasteRow() {
    commonFunctionBar.addSubview(pasteRowView)
    pasteRowView.addSubview(pasteRowIconView)
    pasteRowView.addSubview(pasteRowExpandButton)
    pasteRowView.addSubview(pasteRowTextButton)
    pasteRowView.addSubview(pasteRowCloseButton)
    NSLayoutConstraint.activate([
      pasteRowView.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
      pasteRowView.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
      pasteRowView.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      pasteRowView.heightAnchor.constraint(equalToConstant: 30),

      pasteRowIconView.leadingAnchor.constraint(equalTo: pasteRowView.leadingAnchor, constant: 2),
      pasteRowIconView.centerYAnchor.constraint(equalTo: pasteRowView.centerYAnchor),
      pasteRowIconView.widthAnchor.constraint(equalToConstant: 18),
      pasteRowIconView.heightAnchor.constraint(equalToConstant: 18),

      pasteRowTextButton.leadingAnchor.constraint(equalTo: pasteRowIconView.trailingAnchor, constant: 6),
      pasteRowTextButton.trailingAnchor.constraint(equalTo: pasteRowExpandButton.leadingAnchor),
      pasteRowTextButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowTextButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),

      pasteRowExpandButton.trailingAnchor.constraint(equalTo: pasteRowCloseButton.leadingAnchor),
      pasteRowExpandButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowExpandButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),
      pasteRowExpandButton.widthAnchor.constraint(equalToConstant: 30),

      pasteRowCloseButton.trailingAnchor.constraint(equalTo: pasteRowView.trailingAnchor),
      pasteRowCloseButton.topAnchor.constraint(equalTo: pasteRowView.topAnchor),
      pasteRowCloseButton.bottomAnchor.constraint(equalTo: pasteRowView.bottomAnchor),
      pasteRowCloseButton.widthAnchor.constraint(equalToConstant: 30),
    ])
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  override func setupAppearance() {
    // 与键盘本体同一块背景: KeyboardRootView 用的就是
    // appearance.backgroundStyle.backgroundColor (无配色方案时接近透明,
    // 透出系统键盘底色; 有配色方案时用该方案的 backColor)。
    // 之前这里用 .systemBackground, 深色模式是纯黑, 与下方深灰键盘底色
    // 割裂成一块黑斑; 改成同一颜色后浅色/深色模式都与按键区一致。
    // 深浅切换时 layoutSubviews 会重新跑这里。
    backgroundColor = appearance.backgroundStyle.backgroundColor
    self.style = appearance.candidateBarStyle
    if keyboardContext.displayAppIconButton {
      iconButton.tintColor = style.toolbarButtonFrontColor
    }
    // 收起键盘是一级工具, 永远在工具列表里 (不再受 YAML 的
    // displayKeyboardDismissButton 开关影响——那个开关在老用户已保存的
    // 配置里是关的, 之前导致收起键盘在工具栏上根本不出现)。
    dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    clipboardButton.tintColor = style.toolbarButtonFrontColor
    phrasesButton.tintColor = style.toolbarButtonFrontColor
  }

  /// 覆盖式面板用的不透明键盘底色: 有配色方案时用方案的 backColor
  /// (appearance.backgroundStyle.backgroundColor 已是不透明);
  /// 无配色方案时该颜色接近透明 (alpha 0.001), 改用系统键盘标准底色
  /// (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 第 3 轮直接把 backgroundStyle 颜色给面板是错的——面板是全屏覆盖层,
  /// 透明底会让按键从格子/列表后面透出来; 工具栏那条细条透一下没事,
  /// 全屏面板必须不透明。
  private var opaquePanelBackgroundColor: UIColor {
    if let bg = appearance.backgroundStyle.backgroundColor, bg.cgColor.alpha > 0.5 { return bg }
    return HamsterUIColor.shared.standardKeyboardBackground
  }

  func combine() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        self.updateCandidateBar(inputText: $0)
      }
      .store(in: &subscriptions)

    // 常用语补全 (英文/数字键盘): 打字不走 RIME, userInputKey 为空,
    // 候选栏只认 phraseCompletionInput 才会在 123/英文键盘上出现。
    // 不需要新 UI, 复用同一条候选栏; 显隐条件与上面共用
    // updateCandidateBar (两者谁后触发都算同一条规则, 不打架)。
    rimeContext.phraseCompletionPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self = self else { return }
        self.updateCandidateBar(inputText: self.rimeContext.userInputKey)
      }
      .store(in: &subscriptions)

    // 外部建议 (第 15 轮: 联想词 / 英文纠错): 出现时 userInputKey 是空的,
    // 上面的 sink 会把候选栏藏起来, 这里再把它打开 (工具栏让位);
    // kind 回 .none 时按 userInputKey 的老逻辑恢复 (组字态显示候选栏,
    // 否则显示工具栏)。两个 sink 只在各自的信号变化时跑, 不会互相打架:
    // 打字开始时 kind 已被 setEngineSuggestions 置回 .none, 栏由
    // userInputKey 接管; 联想/纠错出现时 userInputKey 不动, 只这里跑。
    rimeContext.$externalSuggestionsKind
      .receive(on: DispatchQueue.main)
      .sink { [weak self] kind in
        guard let self = self else { return }
        let showCandidateBar = kind != .none || !self.rimeContext.userInputKey.isEmpty
        self.commonFunctionBar.isHidden = showCandidateBar
        self.candidateBarView.isHidden = !showCandidateBar
        // 临时图标的纵向锚点跟随当前在展示的是工具栏还是候选栏
        // (build #50 反馈: 只钉拼音行时, 栏收起后图标飘在工具行上方)。
        self.updateTempCopyVerticalAnchor()
        if showCandidateBar, self.candidateBarView.superview == nil {
          candidateBarView.setStyle(self.style)
          addSubview(candidateBarView)
          candidateBarView.fillSuperview()
        }
        // 联想链走完、栏收起后回到“没输入”态, 粘贴提示按老逻辑恢复
        // (折叠态在时不收图标、不恢复提示行, 第 17 轮反馈修)。
        if !showCandidateBar, self.rimeContext.userInputKey.isEmpty {
          if self.tempCopyText == nil {
            self.hideTempCopyIcon()
            self.showClipboardChipFromCache()
          }
        } else if showCandidateBar {
          // 联想/纠错出现 (或正在输入): 工具栏收起, 粘贴提示行随之收起,
          // 折成临时复制图标 (第 17 轮第 5 项)。
          self.collapsePasteRowToTempIconIfNeeded()
          self.hideClipboardChip()
          // 有输入/联想出现时文档要么已变、要么将变: 撤回快照作废
          // (hideUndoIfDocumentChanged 用光标前文字比对, 不会误伤
          // 删除批次自己的回声)。
          self.hideUndoIfDocumentChanged()
        }
      }
      .store(in: &subscriptions)
  }

  /// 候选栏显隐 + 拼音行: 输入为空且没有常用语补全在展示时隐藏
  /// (同时恢复工具栏与粘贴提示); 否则显示, 拼音行显示当前输入
  /// (补全展示时显示已输入的前缀)。
  private func updateCandidateBar(inputText: String) {
    let isEmpty = inputText.isEmpty && rimeContext.phraseCompletionInput.isEmpty && rimeContext.externalSuggestionsKind == .none
    self.commonFunctionBar.isHidden = !isEmpty
    self.candidateBarView.isHidden = isEmpty

    // 临时图标纵向锚点跟随当前栏 (build #50 反馈);
    // 撤回快照在文档变化后作废 (光标前文字比对, 不误伤删除回声)。
    updateTempCopyVerticalAnchor()
    hideUndoIfDocumentChanged()

    if self.candidateBarView.superview == nil {
      candidateBarView.setStyle(self.style)
      addSubview(candidateBarView)
      candidateBarView.fillSuperview()
    }

    // 未输入时用缓存展示粘贴提示 (绝不读剪贴板, 打字不再弹"粘贴自xxx"横幅);
    // 开始输入后工具栏隐藏, 提示随之隐藏 (折成临时复制图标, 第 17 轮第 5 项)。
    if isEmpty {
      // 折叠态在时不收图标、不恢复提示行 (第 17 轮反馈修): 打字后
      // 提示行不再弹出来, 图标一直留着直到点开。
      if self.tempCopyText == nil {
        self.hideTempCopyIcon()
        self.showClipboardChipFromCache()
      }
    } else {
      self.collapsePasteRowToTempIconIfNeeded()
      self.hideClipboardChip()
    }

    // 检测是否启用内嵌编码
    guard !keyboardContext.enableEmbeddedInputMode else { return }
    if self.keyboardContext.keyboardType.isChineseNineGrid {
      // Debug
      // self.phoneticArea.text = inputKeys + " | " + self.rimeContext.t9UserInputKey
      candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
    } else if !inputText.isEmpty {
      candidateBarView.phoneticLabel.text = inputText
    } else {
      candidateBarView.phoneticLabel.text = rimeContext.phraseCompletionInput
    }
  }

  @objc func menuButtonTouchDownAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  /// 格子图标是菜单开关 (第 7 轮): 点一下打开工具菜单,
  /// 再点一下关闭。⌄ 按钮只负责收起键盘, 不再是菜单的关闭入口。
  /// 点它也退出工具栏定制态 (第 9 轮: 晃动 + ⊖ 不留到菜单里)。
  @objc func menuButtonTouchUpAction() {
    iconButton.backgroundColor = style.toolbarButtonBackgroundColor
    exitToolbarCustomizeMode()
    if menuPanel != nil {
      dismissMenuPanel()
    } else {
      showMenuPanel()
    }
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    // 点 ⌄ 收键盘也退出工具栏定制态 (第 9 轮)。
    exitToolbarCustomizeMode()
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func clipboardButtonTouchDownAction() {
    clipboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func clipboardButtonTouchUpAction() {
    clipboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    showClipboardHistoryPanel()
  }

  @objc func phrasesButtonTouchDownAction() {
    phrasesButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func phrasesButtonTouchUpAction() {
    phrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
    showCommonPhrasesPanel()
  }

  @objc func switchLayoutButtonTouchDownAction() {
    switchLayoutButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func switchLayoutButtonTouchUpAction() {
    switchLayoutButton.backgroundColor = style.toolbarButtonBackgroundColor
    handleMenuSelection("switchLayout")
  }

  @objc func syncNowButtonTouchDownAction() {
    syncNowButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func syncNowButtonTouchUpAction() {
    syncNowButton.backgroundColor = style.toolbarButtonBackgroundColor
    handleMenuSelection("syncNow")
  }

  @objc func settingsButtonTouchDownAction() {
    settingsButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func settingsButtonTouchUpAction() {
    settingsButton.backgroundColor = style.toolbarButtonBackgroundColor
    handleMenuSelection("settings")
  }

  @objc func managePhrasesButtonTouchDownAction() {
    managePhrasesButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func managePhrasesButtonTouchUpAction() {
    managePhrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
    handleMenuSelection("managePhrases")
  }

  @objc func touchCancel() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    iconButton.backgroundColor = style.toolbarButtonBackgroundColor
    clipboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    phrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
    switchLayoutButton.backgroundColor = style.toolbarButtonBackgroundColor
    syncNowButton.backgroundColor = style.toolbarButtonBackgroundColor
    settingsButton.backgroundColor = style.toolbarButtonBackgroundColor
    managePhrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
  }

  // MARK: - 左上角菜单 (宫格面板, 仿微信输入法)

  /// 菜单宫格: 5 格 (第 14 轮: "立即同步剪贴板"和"常用语管理"
  /// 已拿掉——剪贴板面板里本来就有立即同步药丸按钮, 常用语面板里
  /// 本来就能编辑/删除 (第 15 轮: 面板底部的添加行已删, 添加走
  /// 常用语管理面板); 这两个功能仍是可上栏的工具, 见 toolbarToolDefinitions())。
  /// 切换 26 键/九宫格的标题随当前中文主键盘布局而变, 面板每次打开时现算。
  /// 共 5 格, 没有"收起键盘" (第 7 轮移出菜单: 它只保留在工具栏最右的
  /// 固定 ⌄ 按钮上, 放菜单里毫无意义)。
  private func menuTiles() -> [(id: String, title: String, systemImage: String)] {
    let layoutTitle = currentChineseLayoutIsNineGrid ? "切换26键" : "切换九宫格"
    return [
      (id: "clipboard", title: "剪贴板", systemImage: "list.bullet.clipboard"),
      (id: "phrases", title: "常用语", systemImage: "quote.bubble"),
      (id: "switchLayout", title: layoutTitle, systemImage: "keyboard"),
      (id: "customize", title: "定制工具栏", systemImage: "slider.horizontal.3"),
      (id: "settings", title: "设置", systemImage: "gear"),
    ]
  }

  /// 打开功能菜单宫格面板 (覆盖在键盘根视图上, 工具栏下方)。
  /// 5 个格子永远全部显示 (第 10 轮: 菜单格子开关已删, 不再过滤)。
  /// 面板本身透明: 打开前先把下面的按键容器隐藏, 露出键盘根视图
  /// 自身的底色 (与键盘本体同一块系统底色, 不可能有色差); 关闭时恢复。
  /// 面板顶贴工具栏底边、不盖住工具栏 (透明面板盖住工具栏会让标题
  /// 叠在工具栏图标上); 工具栏保持可见可点, 格子图标才能再点一下
  /// 关闭菜单, ⌄ 才能在菜单开着时收键盘 (第 7 轮)。
  /// 打开动画 (第 7 轮): 0.2s 淡入 + 轻微上滑, 不要夸张。
  private func showMenuPanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    hideKeyboardContentForOverlayPanel()
    let panel = KeyboardToolbarMenuPanelView()
    panel.onSelect = { [weak self] tileID in
      self?.dismissMenuPanel()
      self?.handleMenuSelection(tileID)
    }
    panel.onClose = { [weak self] in self?.dismissMenuPanel() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    NSLayoutConstraint.activate([
      panel.topAnchor.constraint(equalTo: bottomAnchor),
      panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      panel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    panel.reload(
      with: menuTiles(),
      // 第 15 轮: 菜单格子永远不绿。绿只留在定制工具栏的池子里
      // (绿 = 在工具栏上, 见 customizeOnToolbarIDs); 菜单里的绿
      // 之前按 toolbarUserAddedToolIDs 上色, 用户反馈截图里
      // 剪贴板/常用语两格绿得不对——菜单格子只是入口, 不是状态。
      // toolbarUserAddedToolIDs 数据本身留着不动 (定制流程还用它)。
      activeIDs: [])
    menuPanel = panel
    panel.alpha = 0
    panel.transform = CGAffineTransform(translationX: 0, y: 12)
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
      panel.alpha = 1
      panel.transform = .identity
    }
  }

  private func dismissMenuPanel() {
    menuPanel?.removeFromSuperview()
    menuPanel = nil
    restoreKeyboardContentForOverlayPanel()
  }

  /// 覆盖面板打开时隐藏键盘内容: 容器 (键盘根视图) 里除覆盖面板外、
  /// 除工具栏自身外的视图, 即按键容器。面板透明, 露出的就是根视图自身的底色,
  /// 与键盘本体绝对一致 (深色模式同样成立)。
  /// 注意: 工具栏不藏——菜单面板是透明的, 只能盖住按键区 (面板顶贴工具栏底边,
  /// 见 showMenuPanel); 工具栏保持可见可点, 格子图标才能再点一下关闭菜单,
  /// ⌄ 才能在菜单开着时收键盘 (第 7 轮)。恢复时机: 面板关闭
  /// (dismissMenuPanel) 与键盘隐藏 (didMoveToWindow -> dismissAllPanels),
  /// 两处都调恢复, 不会藏住。
  private var overlayHiddenViews: [UIView] = []

  private func hideKeyboardContentForOverlayPanel() {
    guard let container = superview, overlayHiddenViews.isEmpty else { return }
    // show 前已调 dismissAllPanels, 此时容器里没有残留面板;
    // 只跳过已知的覆盖面板类 (防御性, 正常情况下一个都没有)。
    // self 是工具栏自身, 不藏 (见上面注释)。
    var hidden: [UIView] = []
    for view in container.subviews where !isOverlayPanelView(view) && view !== self {
      view.isHidden = true
      hidden.append(view)
    }
    overlayHiddenViews = hidden
  }

  private func restoreKeyboardContentForOverlayPanel() {
    overlayHiddenViews.forEach { $0.isHidden = false }
    overlayHiddenViews.removeAll()
  }

  private func isOverlayPanelView(_ view: UIView) -> Bool {
    view is KeyboardToolbarMenuPanelView
      || view is KeyboardTextListPanelView
      || view is KeyboardToolbarCustomizePanelView
      || view is KeyboardCommonPhrasesEditorPanelView
      || view is KeyboardPasteSegmentsPanelView
  }

  /// 点宫格后的动作。
  /// "syncNow" / "managePhrases" 不在菜单宫格里了 (第 14 轮),
  /// 但仍是工具栏按钮的 id, 点工具栏上的同步/常用语管理按钮还走这里。
  /// 没有 "dismiss": 收起键盘不在菜单里, 只在工具栏最右的固定 ⌄ 按钮上。
  private func handleMenuSelection(_ tileID: String) {
    switch tileID {
    case "clipboard":
      showClipboardHistoryPanel()
    case "phrases":
      showCommonPhrasesPanel()
    case "switchLayout":
      toggleChineseKeyboardLayout()
    case "customize":
      showToolbarCustomizePanel()
    case "syncNow":
      ClipboardSyncService.shared.syncNow()
    case "settings":
      // 跳回主 App 设置首页: HamsterConstants.appURL 与 Info.plist
      // 里注册的 hamster scheme 一致 (不要手写 scheme 字符串);
      // /main 由 SceneDelegate 接住后 navigation(.main) 回到设置首页。
      actionHandler.handle(.release, on: .url(URL(string: HamsterConstants.appURL + "/main"), id: "openHamster"))
    case "managePhrases":
      showCommonPhrasesEditorPanel()
    default:
      break
    }
  }

  /// 关掉所有覆盖面板 (打开任一面板前先调, 同一时间只展示一个)。
  /// 全文展开视图不走这里 (它盖在剪贴板面板之上, 关掉它应回到面板)。
  private func dismissAllPanels() {
    dismissTextListPanel()
    dismissCustomizePanel()
    dismissMenuPanel()
    dismissPhrasesEditorPanel()
    dismissSegmentsPanel()
    dismissExpandedClipboardView()
  }

  // MARK: - 常用语管理面板 (键盘内编辑, 不离开键盘)

  /// 打开常用语管理面板 (覆盖在键盘根视图上): 增删改常用语,
  /// 读写与主 App 设置页同一个共享 UserDefaults commonPhrases。
  private func showCommonPhrasesEditorPanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardCommonPhrasesEditorPanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onClose = { [weak self] in self?.dismissPhrasesEditorPanel() }
    panel.onOpenApp = { [weak self] in
      guard let self else { return }
      self.dismissPhrasesEditorPanel()
      self.actionHandler.handle(.release, on: .url(URL(string: HamsterConstants.appURL + "/main"), id: "openHamster"))
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload()
    phrasesEditorPanel = panel
  }

  private func dismissPhrasesEditorPanel() {
    phrasesEditorPanel?.removeFromSuperview()
    phrasesEditorPanel = nil
  }

  // MARK: - 切换 26 键 / 九宫格

  /// 当前中文主键盘是否为九宫格。当前就在中文主键盘上时以屏幕上的类型为准
  /// (用户可能用地球键临时切换过); 否则用保存过的选择; 从未保存过时看当前类型。
  private var currentChineseLayoutIsNineGrid: Bool {
    let type = keyboardContext.keyboardType
    if type.isChineseNineGrid || type.isChinesePrimaryKeyboard {
      return type.isChineseNineGrid
    }
    if let saved = UserDefaults.hamster.chinesePrimaryKeyboardIsNineGrid {
      return saved
    }
    return type.isChineseNineGrid
  }

  /// 在中文九宫格与 26 键全键盘之间切换, 并持久化选择 (下次打开键盘保持)。
  /// 用现有的 setKeyboardType 机制切换, KeyboardRootView 监听到类型变化后重建键盘,
  /// 不需要重启键盘。菜单宫格每次打开时现算标题, 不需要刷新。
  private func toggleChineseKeyboardLayout() {
    let toNineGrid = !currentChineseLayoutIsNineGrid
    UserDefaults.hamster.chinesePrimaryKeyboardIsNineGrid = toNineGrid
    keyboardContext.setKeyboardType(toNineGrid ? .chineseNineGrid : .chinese(.lowercased))
    // 布局→方案绑定 (第 10 轮, 保险): 九宫格只能用 t9 (数字字母表 +
    // t9_processor, rime_ice 收不到数字); 切到九宫格时若当前方案不是
    // t9, 强制切到 t9 (并记进 selectSchemas, 下次部署的 schema_list
    // 补齐也能看到它), 否则九宫格打数字只进边栏、不出候选。
    // 26 键不强制 (rime_ice/t9 都能出字, 不动用户在 RIME 设置里的选择)。
    // 注意: 设置页里改布局不走这里, 但方案是持久化的, 一旦切到 t9 就
    // 一直是 t9, 直到用户在 RIME 设置里另选。
    if toNineGrid, rimeContext.currentSchema?.schemaId != "t9" {
      let t9 = rimeContext.schemas.first { $0.schemaId == "t9" }
        ?? RimeSchema(schemaId: "t9", schemaName: "中文九键")
      if !rimeContext.selectSchemas.contains(t9) {
        rimeContext.appendSelectSchema(t9)
      }
      rimeContext.setCurrentSchema(t9)
      rimeContext.setupRimeInputSchema()
      Logger.statistics.info("切换九宫格: 输入方案强制切到 t9")
    }
  }

  // MARK: - 工具栏按钮重建 (定制工具栏, 自由顺序)

  /// 工具栏左侧工具容器: 侧属性为左的工具按顺序从左往右紧凑排列,
  /// 间距固定 12pt, 不均分、不拉伸 (distribution .fill)。
  /// 菜单按钮 (iconButton) 固定最左, 不参与排序。
  private lazy var leftToolsStackView: UIStackView = makeToolsStackView()

  /// 工具栏右侧工具容器: 侧属性为右的工具按顺序从左往右紧凑排列,
  /// 靠右贴着收起键盘 (⌄); 间距与左侧一致 (12pt)。
  private lazy var rightToolsStackView: UIStackView = makeToolsStackView()

  private func makeToolsStackView() -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.alignment = .center
    stack.distribution = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  /// 工具栏按钮布局 (只建一次): 菜单按钮固定最左, 左侧工具容器跟在它
  /// 后面, 右侧工具容器贴着最右的收起键盘 (⌄); 收起键盘 (⌄) 固定最右
  /// (第 7 轮: 它是固定按钮, 不进工具容器、不参与排序和定制;
  /// 尺寸与左侧菜单按钮同一套, 宽由图标 intrinsic 决定)。
  /// 左右容器之间不强制贴边: 工具少时中间留白, 工具多时两边向中间伸展。
  private var toolsStackLayoutSetup = false

  private func setupToolsStackLayoutIfNeeded() {
    guard !toolsStackLayoutSetup else { return }
    toolsStackLayoutSetup = true
    commonFunctionBar.addSubview(iconButton)
    commonFunctionBar.addSubview(leftToolsStackView)
    commonFunctionBar.addSubview(rightToolsStackView)
    commonFunctionBar.addSubview(dismissKeyboardButton)
    // 临时撤回图标的横向锚点 (两条互斥): 临时复制图标在时贴它左边,
    // 不在时直接贴右侧工具组左边。这里只创建不激活——激活由
    // updateTransientButtonsLayout 按当前状态切换 (同时只激活一条)。
    undoTrailingToTempCopyConstraint = undoDeleteButton.trailingAnchor.constraint(equalTo: tempCopyButton.leadingAnchor, constant: -12)
    undoTrailingToRightStackConstraint = undoDeleteButton.trailingAnchor.constraint(equalTo: rightToolsStackView.leadingAnchor, constant: -12)
    NSLayoutConstraint.activate([
      iconButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
      iconButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      iconButton.heightAnchor.constraint(equalTo: iconButton.widthAnchor),
      iconButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: iconButton.bottomAnchor),

      leftToolsStackView.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 12),
      leftToolsStackView.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      // 左容器不盖住右容器 (工具太多时向中间伸展, 这条是保险)。
      leftToolsStackView.trailingAnchor.constraint(lessThanOrEqualTo: rightToolsStackView.leadingAnchor, constant: -12),

      rightToolsStackView.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      // 右容器不盖住左容器, 也不盖住右边的收起键盘
      // (小屏 6 个工具约 280pt, 仍在栏宽内; 这两条是保险)。
      rightToolsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leftToolsStackView.trailingAnchor, constant: 12),
      rightToolsStackView.trailingAnchor.constraint(equalTo: dismissKeyboardButton.leadingAnchor, constant: -12),
      // 临时复制图标钉在右侧工具组左侧 (2026-11-26 用户要求: 临时复制排在固定工具左侧)。
      tempCopyButton.trailingAnchor.constraint(equalTo: rightToolsStackView.leadingAnchor, constant: -12),

      dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
      dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
      dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
    ])
    // 工具组建好后把临时图标的横向锚点按当前状态落一次
    // (撤回通知可能比工具组建好先到)。
    updateTransientButtonsLayout()
  }

  /// 按左右侧重建工具栏按钮: 左侧菜单按钮常驻 (配置开启时),
  /// 永远在最左, 不参与排序; 6 个工具按 toolbarToolsOrder 的顺序、
  /// 按各自侧属性 (toolbarToolSides) 分进左右两个容器,
  /// 每组内从左往右紧凑排列 (12pt)。
  /// 收起键盘 (⌄) 不在容器里: 它是钉死在工具栏最右的固定按钮
  /// (见 setupToolsStackLayoutIfNeeded), 不再受 YAML 的
  /// displayKeyboardDismissButton 开关影响——那个开关在老用户
  /// 已保存的配置里是关的, 之前导致收起键盘在工具栏上根本不出现。
  /// 重建时退出定制态 (晃动 + ⊖ 一并清掉)。
  func rebuildToolbarButtons() {
    // 一次性迁移: 分区顺序展平成自由顺序 (只跑一次, 见 UserDefaults+)。
    UserDefaults.hamster.migrateToolbarToolsOrderFromZonesIfNeeded()
    // 一次性迁移 (第 12 轮): 默认工具误记进"亲手加上去"集合的清掉 (只跑一次)。
    UserDefaults.hamster.migrateToolbarUserAddedDefaultsIfNeeded()
    // 一次性迁移 (2026-11-24 B2): 已存常用语里混有的旧内置 10 条默认
    // 短语删掉, 用户自己加的短语保留 (只跑一次)。
    UserDefaults.hamster.migrateCommonPhrasesRemoveBuiltinsIfNeeded()
    setupToolsStackLayoutIfNeeded()
    // 退出定制态: 晃动停掉, ⊖ 标记清掉 (重建后位置/归属可能已变)。
    exitToolbarCustomizeMode()
    for stackView in [leftToolsStackView, rightToolsStackView] {
      stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
    }

    // 工具 id -> 按钮 (6 个, 与 toolbarToolDefinitions() 一一对应)。
    func buttonForTool(_ toolID: String) -> UIButton? {
      switch toolID {
      case "clipboard": return clipboardButton
      case "phrases": return phrasesButton
      case "switchLayout": return switchLayoutButton
      case "syncNow": return syncNowButton
      case "settings": return settingsButton
      case "managePhrases": return managePhrasesButton
      default: return nil
      }
    }

    // 在顺序里的工具按顺序、按侧上栏 (可见开关与顺序保持同步, 见定制面板回调)。
    for toolID in UserDefaults.hamster.toolbarToolsOrder where UserDefaults.hamster.isToolbarToolVisible(toolID) {
      guard let button = buttonForTool(toolID) else { continue }
      button.isHidden = isPasteRowVisible
      attachToolbarToolLongPress(to: button)
      if UserDefaults.hamster.toolbarToolSide(for: toolID) == .right {
        rightToolsStackView.addArrangedSubview(button)
      } else {
        leftToolsStackView.addArrangedSubview(button)
      }
    }

    // 收起键盘固定在最右, 粘贴行出现时同样隐藏。
    dismissKeyboardButton.isHidden = isPasteRowVisible
    iconButton.isHidden = !keyboardContext.displayAppIconButton || isPasteRowVisible
  }

  /// 当前工具栏上的工具按钮 (左右容器里的全部, 按栏上顺序:
  /// 先左组、后右组; 晃动/⊖/拖动都用这份列表, 不用再分开拼)。
  private var toolbarToolButtons: [UIButton] {
    let left = leftToolsStackView.arrangedSubviews.compactMap { $0 as? UIButton }
    let right = rightToolsStackView.arrangedSubviews.compactMap { $0 as? UIButton }
    return left + right
  }

  /// 按当前两个容器的实际排列保存整栏布局 (左组 id + 右组 id,
  /// 见 UserDefaults.saveToolbarLayout: 顺序 + 两侧属性一起写盘,
  /// 藏起来的工具保持原相对顺序跟在最后、不丢)。
  private func saveToolbarLayoutFromStacks() {
    let leftIDs = leftToolsStackView.arrangedSubviews.compactMap { ($0 as? UIButton).flatMap { toolID(for: $0) } }
    let rightIDs = rightToolsStackView.arrangedSubviews.compactMap { ($0 as? UIButton).flatMap { toolID(for: $0) } }
    UserDefaults.hamster.saveToolbarLayout(leftIDs: leftIDs, rightIDs: rightIDs)
  }

  /// 给工具按钮挂一次长按手势 (rebuild 会反复调, 只挂一次)。
  /// 菜单格子图标与 ⌄ 收起键盘不在这里, 不挂长按。
  /// 哪个工具由回调里的 toolID(for:) 按按钮实例反查。
  private func attachToolbarToolLongPress(to button: UIButton) {
    if button.gestureRecognizers?.contains(where: { $0 is UILongPressGestureRecognizer }) == true { return }
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(toolbarToolLongPressed(_:)))
    recognizer.minimumPressDuration = 0.5
    // 长按一旦识别就取消按钮的触摸, 松手后不会再触发点按动作
    // (拖完/删完不会顺手打开该工具的面板)。
    recognizer.cancelsTouchesInView = true
    button.addGestureRecognizer(recognizer)
  }

  /// 工具按钮实例 -> toolID (6 个按钮与 toolID 一一对应)。
  private func toolID(for button: UIButton) -> String? {
    if button === clipboardButton { return "clipboard" }
    if button === phrasesButton { return "phrases" }
    if button === switchLayoutButton { return "switchLayout" }
    if button === syncNowButton { return "syncNow" }
    if button === settingsButton { return "settings" }
    if button === managePhrasesButton { return "managePhrases" }
    return nil
  }

  /// 工具栏长按: 拖动换位/换侧, 或原地长按进定制态 (晃动 + ⊖)。
  /// 拖动时快照跟手指走 (x 和 y 都跟, 不钉在行中心线; 抓起偏移一直
  /// 带着, 快照不跳变), 原按钮 alpha 0 留在栈里当"活占位坑",
  /// 其余按钮随手指实时换位; 松手时快照飞回按钮落点再消失,
  /// 落点按"其余按钮中点为界" (中线分侧, 见 toolbarInsertionTarget,
  /// 即离哪侧近进哪侧)。
  /// 拖动时按手指 x 实时换位并写盘 (侧 + 顺序), 松手即保存并退出定制态;
  /// 手指在工具栏左半区 → 左侧容器, 右半区 → 右侧容器 (第 9 轮);
  /// 组内位置按“去掉被拖按钮后的其余按钮中点”为界, 不会错一位。
  /// 靠近左右边缘 48pt 时吸附到该侧端点 (第 13 轮, 第 12 轮定制面板
  /// 顶行同款, 进区轻震一次)。
  /// 原地长按松手则留在定制态 (全部图标晃动 + ⊖), 3 秒无操作自动退出。
  @objc private func toolbarToolLongPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard let button = recognizer.view as? UIButton,
          let toolID = toolID(for: button) else { return }
    switch recognizer.state {
    case .began:
      // 开始拖动: 进定制态 (晃动 + 全部 ⊖) + 震动一下 + 提起快照
      // 表示“拎起来了”; touchDown 留下的按压底色要清掉, 否则松手后按钮一直亮着。
      enterToolbarCustomizeMode()
      toolbarDraggedToolID = toolID
      toolbarDragStartX = recognizer.location(in: commonFunctionBar).x
      toolbarDragMoved = false
      toolbarDragSnappedRight = nil
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      button.backgroundColor = style.toolbarButtonBackgroundColor
      // 上一次拖动的快照若还在飞 (0.15s 落下动画没跑完就又抓起来),
      // 先拿掉, 免得两个快照叠在一起 (旧动画的 completion 里有
      // toolbarDraggedToolID 守卫, 不会把这次的按钮 alpha 改回去)。
      toolbarDragSnapshot?.removeFromSuperview()
      toolbarDragSnapshot = nil
      toolbarDragGrabOffset = .zero
      // 提起快照跟手指走 (第 14 轮, 与池子贴纸同款 1.15× + 阴影):
      // 先藏起被拖按钮自己的 ⊖ 再拍, 否则 ⊖ 会跟着快照一起飞;
      // 原按钮 alpha 0 留在栈里当"活占位坑"。
      toolbarDeleteBadges[toolID]?.isHidden = true
      if let snapshot = button.snapshotView(afterScreenUpdates: true) {
        snapshot.frame = button.convert(button.bounds, to: commonFunctionBar)
        snapshot.isUserInteractionEnabled = false
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0.25
        snapshot.layer.shadowRadius = 8
        snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
        snapshot.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        commonFunctionBar.addSubview(snapshot)
        toolbarDragSnapshot = snapshot
        let finger = recognizer.location(in: commonFunctionBar)
        toolbarDragGrabOffset = CGPoint(x: finger.x - snapshot.center.x, y: finger.y - snapshot.center.y)
        button.alpha = 0
      } else {
        // 快照失败时回退到旧行为: 原按钮放大表示拎起来了。
        UIView.animate(withDuration: 0.15) {
          button.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
          button.alpha = 0.85
        }
      }
    case .changed:
      guard toolbarDraggedToolID == toolID else { return }
      // 快照跟手指走 (x 和 y 都跟, 不钉在行中心线): 抓起偏移一直带着;
      // y 夹在工具栏上下各 12pt 内, 手指甩出栏外图标不飞走。
      // 放在 12pt 移动阈值判断之前: 没开始换位时图标也要跟着手指微动。
      if let snapshot = toolbarDragSnapshot {
        let finger = recognizer.location(in: commonFunctionBar)
        var center = CGPoint(x: finger.x - toolbarDragGrabOffset.x, y: finger.y - toolbarDragGrabOffset.y)
        center.y = min(max(center.y, commonFunctionBar.bounds.minY - 12), commonFunctionBar.bounds.maxY + 12)
        snapshot.center = center
      }
      let x = recognizer.location(in: commonFunctionBar).x
      if abs(x - toolbarDragStartX) > 12 { toolbarDragMoved = true }
      guard toolbarDragMoved else { return }
      restartToolbarCustomizeModeTimer()
      // 落点: 左右边缘 48pt 内吸附到该侧端点 (左组首位/右组末位,
      // 第 12 轮定制面板顶行同款, 进区轻震一次); 中间区域按其余按钮
      // 中点算位置 (与原来一致: 手指在哪半区进哪侧容器)。
      let target: (isRight: Bool, index: Int)
      if x <= Self.toolbarSnapEdgeWidth {
        if toolbarDragSnappedRight != false {
          toolbarDragSnappedRight = false
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        target = (false, 0)
      } else if x >= commonFunctionBar.bounds.width - Self.toolbarSnapEdgeWidth {
        if toolbarDragSnappedRight != true {
          toolbarDragSnappedRight = true
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        let rightCount = rightToolsStackView.arrangedSubviews.compactMap { $0 as? UIButton }.filter { $0 !== button }.count
        target = (true, rightCount)
      } else {
        toolbarDragSnappedRight = nil
        target = toolbarInsertionTarget(forX: x, excluding: button)
      }
      let targetStackView = target.isRight ? rightToolsStackView : leftToolsStackView
      let targetIndex = target.index
      let currentStackView = button.superview as? UIStackView
      guard let currentIndex = currentStackView?.arrangedSubviews.firstIndex(of: button),
            currentStackView !== targetStackView || currentIndex != targetIndex else { return }
      currentStackView?.removeArrangedSubview(button)
      targetStackView.insertArrangedSubview(button, at: min(targetIndex, targetStackView.arrangedSubviews.count))
      saveToolbarLayoutFromStacks()
      // 注意 (第 12 轮): 拖动换位/换侧不再记为"亲手加上去"——绿格子只表示
      // "在定制面板池子里点按加入过"。已经在栏上的工具 (尤其是默认的
      // 剪贴板/常用语) 只是挪了个位置, 不是加上去的; 旧规则 (第 10 轮)
      // 把拖动也算亲手加, 长按拖一下就把默认工具记进来, 菜单里一直绿着。
    case .ended, .cancelled:
      guard toolbarDraggedToolID == toolID else { return }
      toolbarDraggedToolID = nil
      toolbarDragSnappedRight = nil
      // 恢复被拖按钮自己的 ⊖ (快照时藏起来了, 不然会跟着快照飞)。
      toolbarDeleteBadges[toolID]?.isHidden = false
      // 快照飞回按钮落点、缩回原大、淡出后消失, 原按钮恢复显示
      // (快照是按钮的替身, 松手时两者重合, 不闪一下);
      // completion 里只在"当前没有新拖动"时恢复 alpha——
      // 若 0.15s 内又抓起同一按钮, 新拖动拥有该按钮的 alpha。
      // 没快照 (创建失败回退到旧行为) 时直接恢复原按钮。
      if let snapshot = toolbarDragSnapshot {
        toolbarDragSnapshot = nil
        toolbarDragGrabOffset = .zero
        let targetFrame = button.convert(button.bounds, to: commonFunctionBar)
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        UIView.animate(withDuration: 0.15, animations: {
          snapshot.center = targetCenter
          snapshot.transform = .identity
          snapshot.alpha = 0
        }, completion: { [weak self] _ in
          snapshot.removeFromSuperview()
          if self?.toolbarDraggedToolID == nil {
            button.alpha = 1.0
          }
        })
      } else {
        UIView.animate(withDuration: 0.15) {
          button.transform = .identity
          button.alpha = 1.0
        }
      }
      // 拖动过: 位置已实时保存, 松手退出定制态。
      // 没拖动过 (原地长按松手): 留在定制态 (晃动 + ⊖), 3 秒无操作自动退出;
      // 取消手势直接退出, 不留定制态。
      if toolbarDragMoved || recognizer.state == .cancelled {
        exitToolbarCustomizeMode()
      } else if recognizer.state == .ended {
        restartToolbarCustomizeModeTimer()
      }
    default:
      break
    }
  }

  /// 手指 x (commonFunctionBar 坐标系) 对应的落点: 哪侧容器、组内第几个。
  /// 以工具栏中线分侧, 组内位置按其余按钮中点为界 (池子贴纸拖入时也用
  /// 同一套算法, 见 poolDragHover; excluding 为 nil 时不排除任何按钮)。
  private func toolbarInsertionTarget(forX x: CGFloat, excluding draggedButton: UIButton?) -> (isRight: Bool, index: Int) {
    let targetStackView = x > commonFunctionBar.bounds.midX ? rightToolsStackView : leftToolsStackView
    let isRight = targetStackView === rightToolsStackView
    let others = targetStackView.arrangedSubviews.compactMap { $0 as? UIButton }.filter { $0 !== draggedButton }
    var targetIndex = others.count
    for (index, other) in others.enumerated() {
      // 按钮中点换算到 commonFunctionBar 坐标系再比较 (两个容器坐标系不同)。
      let otherCenterX = commonFunctionBar.convert(other.center, from: other.superview).x
      if x < otherCenterX {
        targetIndex = index
        break
      }
    }
    return (isRight, targetIndex)
  }

  // MARK: - 工具栏定制态 (第 9 轮: 晃动 + ⊖)

  /// 进定制态: 全部工具图标像 iOS 主屏幕编辑态一样晃动,
  /// 每个图标右上角出一个小红 ⊖ (点它拿掉工具, 仍留在定制态)。
  /// 格子图标与 ⌄ 收起键盘不晃动、没有 ⊖。
  private func enterToolbarCustomizeMode() {
    // 幂等: 每次都重跑一遍晃动 + ⊖, 新上栏的工具 (池子点按/拖入加入的)
    // 也能拿到晃动和 ⊖; 已在晃动的按钮 startToolbarWiggle 会跳过,
    // ⊖ 先清后重建, 不会重复叠加。3 秒定时器也每次重计。
    isToolbarCustomizeMode = true
    startToolbarWiggle()
    showToolbarDeleteBadges()
    restartToolbarCustomizeModeTimer()
  }

  /// 退出定制态: 晃动停掉, ⊖ 全部清掉, 定时器停掉。
  /// 工具栏重建 / 点格子图标 / 点 ⌄ 时都调这里。
  private func exitToolbarCustomizeMode() {
    guard isToolbarCustomizeMode else { return }
    // 定制面板开着时不退出: 工具栏本身就是被编辑的那行, 3 秒无操作
    // 定时器和 rebuild 都不应该把它关掉; 面板关闭时 dismissCustomizePanel
    // 先清 customizePanelOpen 再调这里。
    guard !customizePanelOpen else { return }
    isToolbarCustomizeMode = false
    toolbarCustomizeModeTimer?.invalidate()
    toolbarCustomizeModeTimer = nil
    stopToolbarWiggle()
    hideToolbarDeleteBadges()
  }

  /// 定制态 3 秒无操作自动退出 (拖动/点 ⊖ 会重新计时)。
  private func restartToolbarCustomizeModeTimer() {
    guard isToolbarCustomizeMode else { return }
    toolbarCustomizeModeTimer?.invalidate()
    toolbarCustomizeModeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
      self?.exitToolbarCustomizeMode()
    }
  }

  /// iOS 主屏幕编辑态式晃动: 绕中心小幅左右摇 (±0.02 弧度),
  /// 0.25 秒一摇、无限循环; 拖动时的放大 (view.transform) 与它
  /// 不冲突 (晃动走 layer 的 rotation.z 动画)。
  private func startToolbarWiggle() {
    for button in toolbarToolButtons {
      guard button.layer.animation(forKey: "toolbarWiggle") == nil else { continue }
      let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
      animation.values = [-0.02, 0.02, -0.02]
      animation.duration = 0.25
      animation.repeatCount = .infinity
      animation.isRemovedOnCompletion = false
      button.layer.add(animation, forKey: "toolbarWiggle")
    }
  }

  private func stopToolbarWiggle() {
    for button in toolbarToolButtons {
      button.layer.removeAnimation(forKey: "toolbarWiggle")
    }
  }

  /// 定制态下每个工具图标右上角的小红 ⊖ (点它删除该工具)。
  /// 第 9 轮已缩过一次 (22pt 标记配 20pt 符号 -> 13pt 符号配 20pt 轻触区);
  /// 但 build #36 实测仍显大: 反馈图里红圆直径约 39px ≈ 11.5pt,
  /// 占 ~30pt 工具图标近四成, 视觉上压住了图标。
  /// 第 14 轮再小一档: 11pt 符号 (渲染红圆约 9.7pt),
  /// 轻触区保持 20×20pt (还能点中), 偏移保持 -4/+4。
  /// 定制面板里和键盘主界面长按编辑时共用这一处实现 (都是工具栏本体的
  /// 编辑态), 改一处两处都生效。
  private func showToolbarDeleteBadges() {
    hideToolbarDeleteBadges()
    for button in toolbarToolButtons {
      guard let toolID = toolID(for: button) else { continue }
      let badge = UIButton(type: .custom)
      badge.translatesAutoresizingMaskIntoConstraints = false
      badge.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
      badge.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 11), scale: .default), forImageIn: .normal)
      badge.tintColor = .systemRed
      badge.backgroundColor = .clear
      badge.accessibilityIdentifier = toolID
      badge.addTarget(self, action: #selector(toolbarDeleteBadgeTapped(_:)), for: .touchUpInside)
      button.addSubview(badge)
      NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: 20),
        badge.heightAnchor.constraint(equalToConstant: 20),
        badge.topAnchor.constraint(equalTo: button.topAnchor, constant: -4),
        badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 4),
      ])
      toolbarDeleteBadges[toolID] = badge
    }
  }

  private func hideToolbarDeleteBadges() {
    toolbarDeleteBadges.values.forEach { $0.removeFromSuperview() }
    toolbarDeleteBadges.removeAll()
  }

  @objc private func toolbarDeleteBadgeTapped(_ sender: UIButton) {
    guard let toolID = sender.accessibilityIdentifier, !toolID.isEmpty else { return }
    removeToolbarToolFromBar(toolID)
  }

  /// 从工具栏拿掉一个工具 (⊖ / 池子绿贴纸点按关掉共用, 同一语义):
  /// 顺序里删掉 + 隐藏 (回工具池) + 清掉"亲手加上去"标记。
  /// 留在定制态 (可连续删几个), 重新计时 3 秒自动退出;
  /// 定制面板开着时被删的工具回池, 池子里它的绿底跟着去掉。
  private func removeToolbarToolFromBar(_ toolID: String) {
    var order = UserDefaults.hamster.toolbarToolsOrder
    order.removeAll { $0 == toolID }
    UserDefaults.hamster.toolbarToolsOrder = order
    UserDefaults.hamster.setToolbarToolVisible(toolID, visible: false)
    UserDefaults.hamster.unmarkToolbarToolUserAdded(toolID)
    rebuildToolbarButtons()
    // rebuild 会退出定制态 (面板没开时); 若栏上还有工具, 重新进定制态 (继续删)。
    if !toolbarToolButtons.isEmpty {
      enterToolbarCustomizeMode()
    }
    // 定制面板开着时: 被删的工具回池, 池子里它的绿底要跟着去掉。
    if customizePanel != nil {
      customizePanel?.reload(allTools: customizeAllTools(), onToolbarIDs: customizeOnToolbarIDs())
    }
  }

  /// 统一工具注册表: 全部 6 个可上工具栏的工具 (id, 标题, 图标)。
  /// 第 14 轮起不再从 menuTiles() 派生: 菜单宫格只有 5 格
  /// (立即同步 / 常用语管理已从菜单拿掉), 但这两个仍是可上栏的工具
  /// (工具池里还在、工具栏按钮还在), 注册表必须保持 6 个,
  /// 与 UserDefaults.toolbarToolAllIDs 一一对应。
  /// "定制工具栏"本身是入口, 不上栏; "收起键盘"是固定按钮, 也不在内。
  /// 标题/图标与 menuTiles() 同一套, 切换 26 键/九宫格的标题随当前布局而变。
  private func toolbarToolDefinitions() -> [(id: String, title: String, systemImage: String)] {
    let layoutTitle = currentChineseLayoutIsNineGrid ? "切换26键" : "切换九宫格"
    return [
      (id: "clipboard", title: "剪贴板", systemImage: "list.bullet.clipboard"),
      (id: "phrases", title: "常用语", systemImage: "quote.bubble"),
      (id: "switchLayout", title: layoutTitle, systemImage: "keyboard"),
      (id: "syncNow", title: "立即同步剪贴板", systemImage: "arrow.triangle.2.circlepath"),
      (id: "settings", title: "设置", systemImage: "gear"),
      (id: "managePhrases", title: "常用语管理", systemImage: "square.and.pencil"),
    ]
  }

  /// 当前在工具栏上的工具 (按保存的顺序, 只含实际在栏上的工具)。
  /// 第 13 轮起只用来算池子绿底 (customizeOnToolbarIDs)。
  /// 注意: 老模型下藏起来的工具仍在顺序里 (可见开关关着), 这里按可见性过滤,
  /// 让它回到工具池、可以点按重新上栏, 而不是卡在"当前工具栏"里却不在栏上。
  private func customizeTools() -> [(id: String, title: String, systemImage: String)] {
    let definitions = toolbarToolDefinitions()
    return UserDefaults.hamster.toolbarToolsOrder.compactMap { id in
      guard UserDefaults.hamster.isToolbarToolVisible(id) else { return nil }
      return definitions.first { $0.id == id }
    }
  }

  /// 定制面板工具池列出的全部工具 (第 13 轮: 池子显示全部 6 个,
  /// 不再只列不在栏上的; 注册表顺序与菜单宫格一致)。
  private func customizeAllTools() -> [(id: String, title: String, systemImage: String)] {
    toolbarToolDefinitions()
  }

  /// 工具池里带绿底的工具 id: 当前在工具栏上的 (可见的) 工具。
  /// 注意: 池子绿底只表示"在栏上", 与菜单绿格的"亲手加上去"
  /// (toolbarUserAddedToolIDs) 不是同一回事。
  private func customizeOnToolbarIDs() -> Set<String> {
    Set(customizeTools().map { $0.id })
  }

  /// 打开定制工具栏面板 (第 13 轮: 就地编辑)。
  /// 面板顶贴工具栏底边、只盖住按键区, 真实工具栏露在上面进入编辑态
  /// (晃动 + ⊖, 见 enterToolbarCustomizeMode): 被编辑的那行就是键盘
  /// 界面上的那行、图标就是真实大小, 不再是面板里放大的复制品。
  /// 面板本身不透明 (opaquePanelBackgroundColor), 不用像菜单面板那样
  /// 先藏按键区——按键本来就被不透明面板盖住、点不到。
  /// 面板开着期间工具栏不退出编辑态 (见 exitToolbarCustomizeMode 里
  /// 的 customizePanelOpen 保护; 3 秒定时器、rebuild 都关不掉它),
  /// 直到面板关闭 (dismissCustomizePanel)。
  private func showToolbarCustomizePanel() {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardToolbarCustomizePanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onClose = { [weak self] in self?.dismissCustomizePanel() }
    // 点按加入: 从工具池放回工具栏, 追加到左侧末尾 (默认左;
    // 收起键盘是固定按钮, 不在顺序里, 不用再"插在它前面")。
    // 拖动可再调位置/换侧。老模型下藏起来的工具仍在顺序里:
    // 只需重新置为显示, 不用再插一次。
    panel.onAddTool = { [weak self] toolID in
      var order = UserDefaults.hamster.toolbarToolsOrder
      if !order.contains(toolID) {
        order.append(toolID)
        UserDefaults.hamster.toolbarToolsOrder = order
      }
      // 从池里加入默认放左侧 (想要放右侧再拖过去, 侧属性以这次写入为准)。
      UserDefaults.hamster.setToolbarToolSide(toolID, side: .left)
      UserDefaults.hamster.setToolbarToolVisible(toolID, visible: true)
      // 亲手在定制里加上去的, 菜单里该工具上色 (第 10 轮)。
      // 标记只在这里 (第 12 轮规则): 池子拖入也走这里 (见 poolDragDrop),
      // 工具栏长按拖动换位/换侧不走这里、不标记。
      UserDefaults.hamster.markToolbarToolUserAdded(toolID)
      self?.rebuildToolbarButtons()
      // 新上栏的工具也要进编辑态 (晃动 + ⊖), 否则它光秃秃地站在栏上。
      self?.enterToolbarCustomizeMode()
      self?.customizePanel?.reload(
        allTools: self?.customizeAllTools() ?? [],
        onToolbarIDs: self?.customizeOnToolbarIDs() ?? [])
    }
    // 点按已在栏上的绿贴纸: 开关的"关"——从工具栏拿掉
    // (与 ⊖ 同一语义, 见 removeToolbarToolFromBar)。
    panel.onRemoveTool = { [weak self] toolID in
      self?.removeToolbarToolFromBar(toolID)
    }
    // 池子贴纸拖到真实工具栏上: 悬停时在栏上插占位坑并返回坑中心
    // (容器坐标系), 供面板的快照落下动画用; 手指不在工具栏上时
    // 返回 nil (占位坑已拿掉)。
    panel.onPoolDragHover = { [weak self] pointInContainer in
      self?.poolDragHover(pointInContainer: pointInContainer) ?? nil
    }
    // 池子贴纸按占位坑落进真实工具栏 (见 poolDragDrop)。
    panel.onPoolDragDrop = { [weak self] toolID in
      self?.poolDragDrop(toolID: toolID)
    }
    // 池子拖动取消/没放进工具栏: 拿掉栏上的占位坑。
    panel.onPoolDragCancel = { [weak self] in
      self?.removePoolDropPlaceholder()
    }
    panel.onReset = { [weak self] in
      UserDefaults.hamster.resetToolbarToolsOrder()
      self?.rebuildToolbarButtons()
      self?.enterToolbarCustomizeMode()
      self?.customizePanel?.reload(
        allTools: self?.customizeAllTools() ?? [],
        onToolbarIDs: self?.customizeOnToolbarIDs() ?? [])
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    NSLayoutConstraint.activate([
      panel.topAnchor.constraint(equalTo: bottomAnchor),
      panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      panel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    panel.reload(allTools: customizeAllTools(), onToolbarIDs: customizeOnToolbarIDs())
    customizePanel = panel
    // 面板开着时工具栏本身进入编辑态 (晃动 + ⊖)。
    customizePanelOpen = true
    enterToolbarCustomizeMode()
  }

  private func dismissCustomizePanel() {
    removePoolDropPlaceholder()
    customizePanel?.removeFromSuperview()
    customizePanel = nil
    // 先清标记再退出编辑态, 否则 exit 里的保护会把它拦住。
    customizePanelOpen = false
    exitToolbarCustomizeMode()
  }

  // MARK: - 池子贴纸拖到真实工具栏上 (第 13 轮)

  /// 池子贴纸拖到真实工具栏上方时: 手指在容器坐标系里的位置 ->
  /// 在对应组里插占位坑 (灰圆, 与工具按钮同大), 返回坑中心
  /// (容器坐标系) 供面板的快照落下动画用; 手指不在工具栏上时
  /// 拿掉占位坑并返回 nil。
  /// 落点算法与工具栏长按拖动同一套 (中线分侧 + 其余按钮中点定组内
  /// 位置, 左右边缘 48pt 吸附到端点, 见 toolbarInsertionTarget)。
  func poolDragHover(pointInContainer: CGPoint) -> CGPoint? {
    guard let container = superview else { return nil }
    let pointInBar = commonFunctionBar.convert(pointInContainer, from: container)
    let barFrame = commonFunctionBar.bounds.insetBy(dx: -8, dy: -12)
    guard barFrame.contains(pointInBar) else {
      removePoolDropPlaceholder()
      return nil
    }
    let x = pointInBar.x
    let target: (isRight: Bool, index: Int)
    if x <= Self.toolbarSnapEdgeWidth {
      target = (false, 0)
    } else if x >= commonFunctionBar.bounds.width - Self.toolbarSnapEdgeWidth {
      let rightCount = rightToolsStackView.arrangedSubviews.compactMap { $0 as? UIButton }.count
      target = (true, rightCount)
    } else {
      target = toolbarInsertionTarget(forX: x, excluding: nil)
    }
    if let current = poolDropTarget, current.isRight == target.isRight, current.index == target.index,
       poolDropPlaceholder != nil {
      return poolDropPlaceholderCenterInContainer()
    }
    removePoolDropPlaceholder()
    let placeholder = makeToolbarDropPlaceholderView()
    let targetStack = target.isRight ? rightToolsStackView : leftToolsStackView
    targetStack.insertArrangedSubview(placeholder, at: min(target.index, targetStack.arrangedSubviews.count))
    poolDropPlaceholder = placeholder
    poolDropTarget = target
    return poolDropPlaceholderCenterInContainer()
  }

  /// 池子贴纸按占位坑落进真实工具栏: 先走 onAddTool (与点按加入同一入口:
  /// 标记为亲手加上去的 + 追加到左组末尾 + 重建 + 池子刷新), 再按落点
  /// 纠正布局 (onAddTool 只认左组末尾) 并重建; 最后刷新池子绿底。
  /// 没占位坑时什么都不做 (面板只在有落点时调这里)。
  func poolDragDrop(toolID: String) {
    guard let target = poolDropTarget else { return }
    removePoolDropPlaceholder()
    var leftIDs = leftToolsStackView.arrangedSubviews.compactMap { ($0 as? UIButton).flatMap { self.toolID(for: $0) } }
    var rightIDs = rightToolsStackView.arrangedSubviews.compactMap { ($0 as? UIButton).flatMap { self.toolID(for: $0) } }
    if target.isRight {
      rightIDs.insert(toolID, at: min(target.index, rightIDs.count))
    } else {
      leftIDs.insert(toolID, at: min(target.index, leftIDs.count))
    }
    // 1) 走 onAddTool: 标记 + 上栏 (标记只在这里, 见 UserDefaults+;
    // 拖动换位/换侧本身不标记, 池子拖入是"加入", 与点按同一入口)。
    customizePanel?.onAddTool?(toolID)
    // 2) 按落点纠正布局并重建 (onAddTool 只追加到左组末尾)。
    UserDefaults.hamster.saveToolbarLayout(leftIDs: leftIDs, rightIDs: rightIDs)
    rebuildToolbarButtons()
    enterToolbarCustomizeMode()
    customizePanel?.reload(allTools: customizeAllTools(), onToolbarIDs: customizeOnToolbarIDs())
  }

  /// 占位坑中心 (容器坐标系): 坑在左/右组栈里, 先换算到工具栏坐标系,
  /// 再换算到容器坐标系 (面板拿它当快照落下动画的目标点)。
  private func poolDropPlaceholderCenterInContainer() -> CGPoint? {
    guard let placeholder = poolDropPlaceholder,
          let placeholderSuperview = placeholder.superview,
          let container = superview else { return nil }
    let centerInBar = commonFunctionBar.convert(placeholder.center, from: placeholderSuperview)
    return convert(centerInBar, to: container)
  }

  /// 栏上的放下占位坑: 灰圆, 与工具按钮同大 (一眼能看出"贴纸会落在这里")。
  private func makeToolbarDropPlaceholderView() -> UIView {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .tertiarySystemFill
    let buttonHeight = toolbarToolButtons.first?.bounds.height ?? 0
    let diameter: CGFloat = buttonHeight > 0 ? buttonHeight : 30
    view.layer.cornerRadius = diameter / 2
    view.alpha = 0.7
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: diameter),
      view.heightAnchor.constraint(equalToConstant: diameter),
    ])
    return view
  }

  /// 拿掉栏上的放下占位坑 (拖出工具栏 / 放下提交 / 取消 / 面板关闭时)。
  private func removePoolDropPlaceholder() {
    guard let placeholder = poolDropPlaceholder else { return }
    if let stack = placeholder.superview as? UIStackView {
      stack.removeArrangedSubview(placeholder)
    }
    placeholder.removeFromSuperview()
    poolDropPlaceholder = nil
    poolDropTarget = nil
  }

  // MARK: - 粘贴提示行 (微信式: 文字在左, ⌄ 展开 + X 并排在右)

  /// 刷新粘贴提示: 仅在未输入 (工具栏显示) 时, 若剪贴板有未提示过的新内容则显示。
  /// iPhone 上复制的和 PC 同步过来的内容都会出现 (同步完成后会收到通知再刷新一次)。
  /// (第 17 轮第 7 项) 经 ClipboardSyncService.cachedPasteboardText() 读剪贴板:
  /// changeCount 未变时用持久化缓存, 不读 UIPasteboard、不弹"粘贴自xxx"横幅,
  /// 只有内容真的变了才读一次; 新内容到来时旧的临时折叠态失效 (内容已换)。
  func refreshClipboardChip() {
    #if canImport(UIKit)
      guard !commonFunctionBar.isHidden else {
        hideClipboardChip()
        return
      }
      let currentChangeCount = UIPasteboard.general.changeCount
      if currentChangeCount != lastChipChangeCount {
        hideTempCopyIcon()
      }
      lastChipChangeCount = currentChangeCount
      lastReadPasteboardText = ClipboardSyncService.cachedPasteboardText()?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if lastReadPasteboardText?.isEmpty == true {
        lastReadPasteboardText = nil
      }
      showClipboardChipFromCache()
    #endif
  }

  /// 用缓存的剪贴板文本展示粘贴提示 (打字/输入变化时调用)。
  /// 只读 changeCount (整数, 不弹横幅) 判断缓存是否过期:
  /// 若剪贴板已变, 缓存过期, 不展示旧内容 (等下一次同步/定时检查刷新),
  /// 绝不在此读剪贴板内容。所以打字时不会再弹"粘贴自xxx"横幅。
  /// (第 17 轮第 7 项) 新视图实例的内存记录是 -1 时, 以持久化记录为准
  /// 恢复缓存文本, 同样不读剪贴板 (键盘扩展进程重建后也不重弹横幅)。
  func showClipboardChipFromCache() {
    guard !commonFunctionBar.isHidden else {
      hideClipboardChip()
      return
    }
    #if canImport(UIKit)
      if lastChipChangeCount == -1 {
        lastChipChangeCount = UserDefaults.hamster.clipboardLastSeenChangeCount
        lastReadPasteboardText = UserDefaults.hamster.clipboardLastSeenText?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if lastReadPasteboardText?.isEmpty == true {
          lastReadPasteboardText = nil
        }
      }
      guard UIPasteboard.general.changeCount == lastChipChangeCount else {
        hideClipboardChip()
        return
      }
    #endif
    guard let text = lastReadPasteboardText, !text.isEmpty else {
      hideClipboardChip()
      return
    }
    // 打字折进临时图标的内容: 键盘重建后图标还在, 提示行不再重推同一条
    // 内容 (第 17 轮反馈修)。
    #if canImport(UIKit)
      if let folded = UserDefaults.hamster.tempCopyFoldedText,
         folded == text,
         UserDefaults.hamster.tempCopyFoldedChangeCount == UIPasteboard.general.changeCount
      {
        tempCopyText = folded
        showTempCopyIcon()
        return
      }
    #endif
    // 已粘贴/忽略过的内容不再重复提示, 直到剪贴板换成新内容。
    // 忽略记录持久化在共享 UserDefaults 里, 键盘重建 (隐藏再打开) 也不会丢。
    #if canImport(UIKit)
      if UserDefaults.hamster.isClipboardChipDismissed(
        hash: ClipboardSyncService.sha256(text),
        changeCount: UIPasteboard.general.changeCount)
      {
        hideClipboardChip()
        return
      }
    #endif
    // 已在展示同一内容时不重复布局
    if text == clipboardChipText, isPasteRowVisible {
      return
    }
    clipboardChipText = text
    displayPasteRow(text: text)
  }

  /// 显示微信式粘贴提示行 (文字 + ⌄ 展开 + X), 并暂时隐藏工具栏其他按钮。
  private func displayPasteRow(text: String) {
    // 单行显示, 换行符转空格, 超长由 label 截断
    let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    pasteRowTextButton.setTitle(singleLine, for: .normal)
    pasteRowView.isHidden = false
    isPasteRowVisible = true
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.isHidden = true }
  }

  private func hideClipboardChip() {
    pasteRowView.isHidden = true
    isPasteRowVisible = false
    clipboardChipText = nil
    // 恢复工具栏按钮 (不在布局里的按钮改 isHidden 也没影响)
    [iconButton, clipboardButton, phrasesButton, dismissKeyboardButton].forEach { $0.isHidden = false }
  }

  /// 点粘贴提示行右侧 ⌄: 展开复制内容、分段粘贴 (仿微信)。
  /// 不是隐藏键盘 (第 3 轮理解错了); 隐藏键盘只作为工具栏工具。
  @objc private func pasteRowExpandTapped() {
    guard let text = clipboardChipText, !text.isEmpty else { return }
    showPasteSegmentsPanel(text: text)
  }

  /// 点临时复制图标 (第 17 轮第 5 项): 打开折叠的那条复制内容 (分段面板);
  /// 打开后无论粘贴与否图标都收掉 (一次性)。
  @objc private func tempCopyButtonTapped() {
    guard let text = tempCopyText, !text.isEmpty else {
      hideTempCopyIcon()
      return
    }
    hideTempCopyIcon()
    // 点开以后不管粘不粘贴都不再显示 (第 17 轮反馈修): 先把这条内容
    // 记为已忽略, 关面板不粘贴也不会让提示行把它重新推出来。
    UserDefaults.hamster.markClipboardChipDismissed(
      hash: ClipboardSyncService.sha256(text),
      changeCount: currentPasteboardChangeCount)
    showPasteSegmentsPanel(text: text)
  }

  /// 粘贴提示行正在展示时用户开始打字: 把提示行折叠成临时复制图标
  /// (第 17 轮第 5 项), 内容留在 tempCopyText 里, 提示行本身随即收掉。
  /// 只折叠一次 (已折叠时不再重复); 提示行没在展示时什么都不做。
  private func collapsePasteRowToTempIconIfNeeded() {
    guard tempCopyText == nil, isPasteRowVisible, let text = clipboardChipText, !text.isEmpty else { return }
    tempCopyText = text
    // 折叠态持久化 (第 17 轮反馈修): 输入清空、键盘重建后图标都还在,
    // 提示行不再把同一条内容重新推出来。
    UserDefaults.hamster.tempCopyFoldedText = text
    UserDefaults.hamster.tempCopyFoldedChangeCount = currentPasteboardChangeCount
    showTempCopyIcon()
  }

  /// 显示临时复制图标 (钉在候选栏拼音行右端, 打字时够得着;
  /// 候选栏是后加的子视图, 需提到最前才不会被盖住)。
  /// 纵向锚点与横向排布按当前状态落一次 (见 updateTempCopyVerticalAnchor
  /// 与 updateTransientButtonsLayout)。
  private func showTempCopyIcon() {
    tempCopyButton.isHidden = false
    bringSubviewToFront(tempCopyButton)
    updateTempCopyVerticalAnchor()
    updateTransientButtonsLayout()
  }

  /// 收掉临时复制图标并清掉折叠的内容 (内存 + 持久化折叠态)。
  private func hideTempCopyIcon() {
    tempCopyButton.isHidden = true
    tempCopyText = nil
    UserDefaults.hamster.tempCopyFoldedText = nil
    UserDefaults.hamster.tempCopyFoldedChangeCount = -1
    // 撤回图标若在显示, 它的横向锚点要从"贴临时复制图标"改回"贴工具组"。
    updateTransientButtonsLayout()
  }

  /// 临时复制图标的纵向锚点 (两条互斥, build #50 反馈修):
  /// 候选栏在展示 (commonFunctionBar 隐藏) 时钉拼音行内 (top+12);
  /// 工具栏在展示时与工具行垂直居中 (commonFunctionBar.centerY)。
  /// build #50 只钉 top+12: 打字停后候选栏收起、工具栏回来,
  /// 图标还留在拼音行高度, 比工具行高约 13pt, 看着飘在中间偏上。
  /// 撤回图标 centerY 钉在临时复制图标上, 跟着一起切换, 不用单独处理。
  private func updateTempCopyVerticalAnchor() {
    let typing = commonFunctionBar.isHidden
    tempCopyCenterYPhoneticConstraint?.isActive = typing
    tempCopyCenterYToolbarConstraint?.isActive = !typing
  }

  /// 两个临时图标的横向排布 (只在图标显隐变化时调, 约束切换本身便宜):
  /// 撤回图标在时, 临时复制图标在 → 撤回贴它左边 (-12);
  /// 临时复制图标不在 → 撤回直接贴右侧工具组左边 (-12)。
  /// 两条约束同时只激活一条, 且始终有一条激活: 撤回不在时也保持
  /// 右锚点激活, 否则撤回按钮横向位置无约束 (布局歧义)。
  /// 工具组还没建好时 (setupToolsStackLayoutIfNeeded 未跑) 约束是 nil,
  /// 直接返回, 建好后那头会补调一次。
  private func updateTransientButtonsLayout() {
    guard undoTrailingToTempCopyConstraint != nil,
          undoTrailingToRightStackConstraint != nil else { return }
    let undoVisible = undoDeleteText != nil
    let tempCopyVisible = !tempCopyButton.isHidden
    undoTrailingToTempCopyConstraint?.isActive = undoVisible && tempCopyVisible
    undoTrailingToRightStackConstraint?.isActive = !(undoVisible && tempCopyVisible)
  }

  /// 撤回快照变化 (控制器发来的通知): 有快照 → 展示撤回图标;
  /// 快照没了 → 收掉图标。
  @objc private func undoDeleteSnapshotDidChange(_ notification: Notification) {
    if let text = notification.userInfo?["text"] as? String, !text.isEmpty {
      undoDeleteText = text
      showUndoDeleteButton()
    } else {
      hideUndoDeleteButton()
    }
  }

  /// 显示临时撤回图标 (钉在右侧固定工具组左侧, 或临时复制图标左侧)。
  private func showUndoDeleteButton() {
    undoDeleteButton.isHidden = false
    bringSubviewToFront(undoDeleteButton)
    updateTransientButtonsLayout()
  }

  /// 收掉临时撤回图标并清掉本地快照 (不碰控制器的快照——控制器
  /// 那头是单一事实来源, 它发通知时这里也会收到)。
  private func hideUndoDeleteButton() {
    undoDeleteButton.isHidden = true
    undoDeleteText = nil
    updateTransientButtonsLayout()
  }

  /// 撤回快照的失效兜底 (选词/输入/粘贴后文档变了): 光标前文字
  /// 非空、且与快照不同 → 说明是删除之后的改动, 快照作废。
  /// 删除批次自己的回声不会误判: "" 回声在第一批删除前到达,
  /// 那时光标前仍等于快照全文; 删完后光标前是空的。
  /// 比对失败时不主动清控制器快照——控制器的 textDidChange 兜底
  /// 与各入口的直接失效会处理; 这里只负责收图标。
  private func hideUndoIfDocumentChanged() {
    guard let snapshot = undoDeleteText, !snapshot.isEmpty else { return }
    let before = keyboardContext.textDocumentProxy.documentContextBeforeInput ?? ""
    if !before.isEmpty && before != snapshot {
      hideUndoDeleteButton()
    }
  }

  /// 点按临时撤回图标: 把快照文本原样插回光标处 (走控制器的
  /// restoreDeletedTextBeforeCursor → insertPastedText, 不经过 RIME),
  /// 图标随快照清除而消失 (通知回路)。
  @objc private func undoDeleteButtonTapped() {
    keyboardInputController?.restoreDeletedTextBeforeCursor()
  }

  /// 经 actionHandler 拿到控制器 (与 insertPanelText 同一路)。
  private var keyboardInputController: KeyboardController? {
    (actionHandler as? StandardKeyboardActionHandler)?.keyboardController
  }

  /// 打开粘贴内容分段展开面板 (覆盖在键盘根视图上):
  /// 把给定的剪贴板内容按行、句读标点切成片段, 点某段只粘贴那段,
  /// 顶部"粘贴全部"粘贴全部内容, 上方另有链接 / 验证码提取药丸
  /// (点药丸只粘贴该部分, 第 17 轮第 6 项)。面板关闭方式: 右上角"关闭"。
  /// text 既可是粘贴提示行的内容, 也可是临时复制图标里折叠的内容。
  private func showPasteSegmentsPanel(text: String) {
    guard !text.isEmpty else { return }
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardPasteSegmentsPanelView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onSelectSegment = { [weak self] segment in
      guard let self else { return }
      self.dismissSegmentsPanel()
      self.markPasteContentDismissed(text)
      self.insertPanelText(segment)
      UserDefaults.hamster.recordClipboardHistory(segment)
    }
    panel.onSelectAll = { [weak self] in
      guard let self else { return }
      self.dismissSegmentsPanel()
      self.markPasteContentDismissed(text)
      self.insertPanelText(text)
      UserDefaults.hamster.recordClipboardHistory(text)
    }
    panel.onSelectExtractedItem = { [weak self] part in
      guard let self else { return }
      self.dismissSegmentsPanel()
      self.markPasteContentDismissed(text)
      self.insertPanelText(part)
      UserDefaults.hamster.recordClipboardHistory(part)
    }
    panel.onClose = { [weak self] in self?.dismissSegmentsPanel() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: text)
    segmentsPanel = panel
  }

  private func dismissSegmentsPanel() {
    segmentsPanel?.removeFromSuperview()
    segmentsPanel = nil
  }

  /// 把一条粘贴内容标记为已忽略 (SHA-256 持久化) 并隐藏提示行与临时图标。
  /// (分段面板的粘贴入口用: 面板里的内容既可能是提示行的, 也可能是
  /// 临时图标里折叠的, 不能只认 clipboardChipText。)
  private func markPasteContentDismissed(_ text: String) {
    guard !text.isEmpty else { return }
    UserDefaults.hamster.markClipboardChipDismissed(
      hash: ClipboardSyncService.sha256(text),
      changeCount: currentPasteboardChangeCount)
    hideClipboardChip()
    hideTempCopyIcon()
  }

  /// 把当前粘贴提示内容标记为已忽略 (SHA-256 持久化) 并隐藏提示行。
  private func markClipboardChipDismissedAndHide() {
    if let text = clipboardChipText, !text.isEmpty {
      markPasteContentDismissed(text)
    } else {
      hideClipboardChip()
      hideTempCopyIcon()
    }
  }

  /// 点粘贴提示行文字: 把剪贴板内容输入到当前输入框, 之后不再重复提示同一内容。
  @objc private func pasteRowTextTapped() {
    guard let text = clipboardChipText, !text.isEmpty else { return }
    UserDefaults.hamster.markClipboardChipDismissed(
      hash: ClipboardSyncService.sha256(text),
      changeCount: currentPasteboardChangeCount)
    hideClipboardChip()
    hideTempCopyIcon()
    insertPanelText(text)
    UserDefaults.hamster.recordClipboardHistory(text)
  }

  /// 点粘贴提示行右侧 X: 关闭提示, 相同内容不再重复提示 (直到剪贴板换成新内容)。
  @objc private func pasteRowCloseTapped() {
    if let text = clipboardChipText, !text.isEmpty {
      UserDefaults.hamster.markClipboardChipDismissed(
        hash: ClipboardSyncService.sha256(text),
        changeCount: currentPasteboardChangeCount)
    }
    hideClipboardChip()
    hideTempCopyIcon()
  }

  /// 同步完成 (上传/下载结束) 后刷新粘贴提示: PC 复制的内容下载到本机后会出现。
  @objc private func syncDidFinish() {
    refreshClipboardChip()
  }

  // MARK: - 文本列表面板 (剪贴板 / 常用语)

  /// 把面板文本输入到当前输入框。优先走 KeyboardController.insertPastedText,
  /// 拿不到 controller 时直接写 documentProxy。失败静默。
  /// 注意: 不能走 controller.insertText——那是单字符按键入口, 中文键盘下会
  /// 把整段文本当一次按键喂给 RIME (processKey 只取首字节), 剪贴板文本进不了
  /// 文档, 候选栏反而出现一个奇怪的数字/符号候选 (Bug C)。
  private func insertPanelText(_ text: String) {
    guard !text.isEmpty else { return }
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController {
      controller.insertPastedText(text)
      return
    }
    keyboardContext.textDocumentProxy.insertText(text)
  }

  /// 在键盘根视图上覆盖展示剪贴板 / 常用语二合一面板 (仿微信: 顶部
  /// [剪贴板 | 常用语] 分段切换, 每条一张白底圆角卡片, 右上角 ⋮ 菜单)。
  /// 两个页面各接自己的数据与回调, 互不串味: 剪贴板页读写 clipboardHistory,
  /// 常用语页读写 commonPhrases; 切段只换数据源, 不重建面板。
  private func showClipboardPhrasesPanel(initialPage: KeyboardTextListPanelView.Page) {
    dismissAllPanels()
    guard let container = superview else { return }
    let panel = KeyboardTextListPanelView(initialPage: initialPage)
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onSelectClipboardText = { [weak self] text in
      self?.insertPanelText(text)
      self?.dismissTextListPanel()
    }
    panel.onSelectExtractedItem = { [weak self] part in
      // 第 17 轮第 6 项: 卡片内的链接 / 验证码药丸, 点按只粘贴该部分。
      self?.insertPanelText(part)
      self?.dismissTextListPanel()
      UserDefaults.hamster.recordClipboardHistory(part)
    }
    panel.onExpandClipboardItem = { [weak self] text in
      // 第 17 轮第 6 项: 长按剪贴板条目展开全文 (可长按拖选一段粘贴)。
      self?.showClipboardExpandedView(text: text)
    }
    panel.onSelectPhrase = { [weak self] text in
      self?.insertPanelText(text)
      self?.dismissTextListPanel()
    }
    panel.onDeleteClipboardItem = { [weak self] index in
      var history = UserDefaults.hamster.clipboardHistory
      guard history.indices.contains(index) else { return }
      history.remove(at: index)
      UserDefaults.hamster.clipboardHistory = history
      self?.refreshClipboardPhrasesPanel()
    }
    panel.onDeletePhrase = { [weak self] index in
      var phrases = UserDefaults.hamster.commonPhrases
      guard phrases.indices.contains(index) else { return }
      phrases.remove(at: index)
      UserDefaults.hamster.commonPhrases = phrases
      self?.refreshClipboardPhrasesPanel()
    }
    panel.onAddClipboardToPhrases = { [weak self] text in
      guard !text.isEmpty else { return }
      var phrases = UserDefaults.hamster.commonPhrases
      guard !phrases.contains(text) else { return }
      phrases.append(text)
      UserDefaults.hamster.commonPhrases = phrases
      self?.refreshClipboardPhrasesPanel()
    }
    panel.onEditPhrase = { [weak self] index in
      guard let self else { return }
      self.dismissTextListPanel()
      self.showCommonPhrasesEditorPanel()
      self.phrasesEditorPanel?.beginEditingPhrase(at: index)
    }
    panel.onManagePhrases = { [weak self] in
      guard let self else { return }
      self.dismissTextListPanel()
      self.showCommonPhrasesEditorPanel()
    }
    panel.onClose = { [weak self] in self?.dismissTextListPanel() }
    panel.onSyncNow = {
      ClipboardSyncService.shared.syncNow()
    }
    panel.onSyncFinished = { [weak self] in
      #if canImport(UIKit)
        // 第 17 轮第 7 项: 经统一门读剪贴板——内容没变时用缓存记历史,
        // 不重读 UIPasteboard、不弹"粘贴自xxx"横幅。
        if let text = ClipboardSyncService.cachedPasteboardText() {
          UserDefaults.hamster.recordClipboardHistory(text)
        }
      #endif
      self?.refreshClipboardPhrasesPanel()
    }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(clipboardItems: UserDefaults.hamster.clipboardHistory, phrases: UserDefaults.hamster.commonPhrases)
    textListPanel = panel
  }

  /// 面板开着时从共享 UserDefaults 重读两页数据并刷新 (删条、同步完成时调用)。
  private func refreshClipboardPhrasesPanel() {
    textListPanel?.reload(clipboardItems: UserDefaults.hamster.clipboardHistory, phrases: UserDefaults.hamster.commonPhrases)
  }

  private func dismissTextListPanel() {
    textListPanel?.removeFromSuperview()
    textListPanel = nil
  }

  // MARK: - 剪贴板全文展开视图 (长按剪贴板条目, 第 17 轮第 6 项)

  /// 打开剪贴板条目全文展开视图 (盖在剪贴板面板之上; 关闭后回到面板,
  /// 面板本身不关)。全文可长按任意字符后拖动选一段, 再点"粘贴选中"只粘那段。
  private func showClipboardExpandedView(text: String) {
    guard !text.isEmpty else { return }
    dismissExpandedClipboardView()
    guard let container = superview else { return }
    let panel = KeyboardClipboardExpandedView()
    panel.panelBackgroundColor = opaquePanelBackgroundColor
    panel.onPasteSelection = { [weak self] selected in
      guard let self else { return }
      self.dismissExpandedClipboardView()
      self.dismissTextListPanel()
      self.insertPanelText(selected)
      UserDefaults.hamster.recordClipboardHistory(selected)
    }
    panel.onClose = { [weak self] in self?.dismissExpandedClipboardView() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    panel.fillSuperview()
    panel.reload(with: text)
    expandedClipboardView = panel
  }

  private func dismissExpandedClipboardView() {
    expandedClipboardView?.removeFromSuperview()
    expandedClipboardView = nil
  }

  /// 剪贴板历史: 打开时先触发一次同步 (上传本机剪贴板、下载服务器最新内容),
  /// 再把当前剪贴板记入历史, 展示最近 20 条。面板顶部显示最近一次同步结果,
  /// 并有"立即同步"药丸按钮; 同步完成后列表会自动刷新。
  /// 无 Full Access 或剪贴板为空时静默, 只显示已有历史。
  /// 打开在剪贴板分段页; 顶栏切到常用语即是常用语页, 同一个面板。
  private func showClipboardHistoryPanel() {
    // 打开面板即同步一次 (跳过节流), 让 PC 复制的内容尽快出现
    ClipboardSyncService.shared.syncNow()
    #if canImport(UIKit)
      // 第 17 轮第 7 项: 经统一门读剪贴板——内容没变时用缓存记历史,
      // 不重读 UIPasteboard、不弹"粘贴自xxx"横幅。
      if let text = ClipboardSyncService.cachedPasteboardText() {
        UserDefaults.hamster.recordClipboardHistory(text)
      }
    #endif
    showClipboardPhrasesPanel(initialPage: .clipboard)
    // 同步状态行 + 立即同步按钮 (仅剪贴板页显示)
    textListPanel?.showSyncRow(statusText: UserDefaults.hamster.clipboardSyncLastStatusText)
  }

  /// 常用语: 打开在常用语分段页 (与剪贴板同一个面板)。
  /// 点一条粘贴上屏; ⋮ 菜单可编辑 / 删除; 操作行有"管理常用语"入口。
  private func showCommonPhrasesPanel() {
    showClipboardPhrasesPanel(initialPage: .phrases)
  }
}
