
//
//  KeyboardClipboardExpandedView.swift
//
//  剪贴板条目长按展开视图 (第 17 轮第 6 项, 展开页改版见第 17 轮反馈):
//  在键盘根视图上盖住剪贴板面板, 以全文展示一条剪贴板内容。
//  - 文本区是不可编辑、可选中 (selectable) 的 UITextView: 长按任意字符后
//    拖动即可自由选中一段, 选中范围由系统以背景高亮标出 (与系统选词同一套);
//    系统编辑菜单 (复制/粘贴气泡) 被禁掉, 免得跟面板自己的粘贴按钮打架。
//  - 正文装在白色气泡里 (与剪贴板卡片、提取药丸同一套白底 + 细边线),
//    字体 18, 比原来大一点, 好读也好选。
//  - 顶栏右侧两颗纯图标按钮: 打钩 = 粘贴选中 (只有选中了非空范围时才可用),
//    下箭头 = 关闭。没有"粘贴全部"——返回剪贴板点一下卡片就是贴全部,
//    这个按钮是多余的 (用户确认)。右上角"关闭"只关本视图,
//    底下的剪贴板面板还在。
//  自定义键盘内 UIView, 不用 UIAlertController (键盘扩展里会闪退,
//  见 CandidateLongPressMenuView.swift 的注释)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 剪贴板条目全文展开视图: 标题 + 打钩 (粘贴选中) + 下箭头 (关闭) + 白底气泡全文 (可长按拖选)。
class KeyboardClipboardExpandedView: NibLessView {
  /// 点打钩时的回调 (只粘选中的那段), 由调用方输入文本并关闭面板。
  var onPasteSelection: ((String) -> Void)?
  /// 关闭按钮回调 (只关本视图)。
  var onClose: (() -> Void)?

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
    }
  }

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "剪贴板内容"
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 打钩 = 粘贴选中: 只有选中了非空范围时才可用。
  /// 用 semibold 粗细——用户说打钩不要太细; 纯图标, 不带字。
  private lazy var confirmButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "checkmark"), for: .normal)
    button.setPreferredSymbolConfiguration(
      .init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(pasteSelectionTapped), for: .touchUpInside)
    return button
  }()

  /// 下箭头 = 关闭: 与键盘上收键盘的 ⌄ 同一套语言。
  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(
      .init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  /// 白底气泡: 装全文的卡片, 与剪贴板卡片、提取药丸同一套
  /// 白底 (.systemBackground) + 1pt 细边线 (systemGray4)。
  private lazy var bubbleView: UIView = {
    let view = UIView()
    view.backgroundColor = .systemBackground
    view.layer.cornerRadius = 12
    view.layer.borderWidth = 1
    view.layer.borderColor = UIColor.systemGray4.cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 全文展示区: 不可编辑、可选中; 长按任意字符后拖动自由选区,
  /// 系统给选中范围上背景高亮。编辑菜单已禁 (见 NoMenuTextView)。
  /// 背景透明, 白底由外面的气泡给。
  private lazy var textView: NoMenuTextView = {
    let textView = NoMenuTextView()
    textView.font = .systemFont(ofSize: 18)
    textView.textColor = .label
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    textView.delegate = self
    textView.translatesAutoresizingMaskIntoConstraints = false
    return textView
  }()

  init() {
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    updateConfirmButton()
  }

  override func constructViewHierarchy() {
    addSubview(titleLabel)
    addSubview(confirmButton)
    addSubview(closeButton)
    bubbleView.addSubview(textView)
    addSubview(bubbleView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      confirmButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      confirmButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),

      bubbleView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
      bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      bubbleView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),

      textView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
      textView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
      textView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 载入一条剪贴板全文 (打开时调一次)。
  func reload(with text: String) {
    textView.text = text
    // 打开时不预选: 用户长按任意字符后拖动才产生选区。
    textView.selectedRange = NSRange(location: 0, length: 0)
    updateConfirmButton()
  }

  /// 当前选中的文本 (无选区时为空字符串)。
  private var selectedText: String {
    let range = textView.selectedRange
    guard range.length > 0,
          let text = textView.text as NSString?,
          range.location + range.length <= text.length
    else { return "" }
    return text.substring(with: range)
  }

  /// 打钩只在选中了非空范围时可用 (没选时置灰)。
  private func updateConfirmButton() {
    confirmButton.isEnabled = !selectedText.isEmpty
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func pasteSelectionTapped() {
    let text = selectedText
    guard !text.isEmpty else { return }
    onPasteSelection?(text)
  }
}

extension KeyboardClipboardExpandedView: UITextViewDelegate {
  /// 选区变化 (长按拖选进行中 / 松手后) 即刷新打钩可用态。
  func textViewDidChangeSelection(_ textView: UITextView) {
    updateConfirmButton()
  }
}

/// 禁掉系统编辑菜单的 UITextView 子类: 长按拖选只产生选区与背景高亮,
/// 不弹"复制/粘贴/全选"气泡 (气泡会盖住面板自己的粘贴按钮, 也会在键盘
/// 扩展里跟宿主 App 的菜单抢焦点)。
private final class NoMenuTextView: UITextView {
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    false
  }
}
