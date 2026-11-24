//
//  CandidateLongPressMenuView.swift
//
//  长按候选词弹出的菜单 (第 14 轮第 5 项 b/c)。
//
//  注意 (热修复 2026-11-24): 这里原来用的是 UIAlertController (actionSheet),
//  但 UIAlertController 在键盘扩展进程里不可用——创建时
//  _UIApplicationAssertForExtensionType 直接抛异常, 键盘闪退 (EXC_CRASH /
//  SIGABRT, 2026-11-24 14:48 崩溃日志)。所以菜单必须是键盘内的自定义 UIView,
//  盖在键盘根视图上, 绝不能再用 UIAlertController / present。
//

import UIKit

/// 长按候选词的自定义菜单: 遮罩 + 居中卡片 (标题 = 候选词; 忘记记忆 / 置顶或
/// 取消置顶 / 取消)。点遮罩或取消收掉; 点功能键先收菜单再执行操作。
final class CandidateLongPressMenuView: UIView {
  private let onForget: () -> Void
  private let onTogglePin: () -> Void

  private let dimView = UIButton(type: .custom)
  private let cardView = UIView()
  private let titleLabel = UILabel()

  /// 在 sourceView 所在的键盘根视图上弹出菜单。已有菜单先收掉。
  static func show(
    from sourceView: UIView,
    text: String,
    pinned: Bool,
    onForget: @escaping () -> Void,
    onTogglePin: @escaping () -> Void
  ) {
    // 找到键盘根视图 (最顶层 superview, 不含 UIWindow), 菜单盖在整个键盘上。
    var container: UIView = sourceView
    while let superview = container.superview, !(superview is UIWindow) {
      container = superview
    }
    container.subviews.compactMap { $0 as? CandidateLongPressMenuView }.forEach { $0.dismiss() }
    let menu = CandidateLongPressMenuView(text: text, pinned: pinned, onForget: onForget, onTogglePin: onTogglePin)
    menu.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(menu)
    NSLayoutConstraint.activate([
      menu.topAnchor.constraint(equalTo: container.topAnchor),
      menu.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      menu.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      menu.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    menu.animateIn()
  }

  init(text: String, pinned: Bool, onForget: @escaping () -> Void, onTogglePin: @escaping () -> Void) {
    self.onForget = onForget
    self.onTogglePin = onTogglePin
    super.init(frame: .zero)
    setup(text: text, pinned: pinned)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup(text: String, pinned: Bool) {
    backgroundColor = .clear

    dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    dimView.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    dimView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(dimView)
    NSLayoutConstraint.activate([
      dimView.topAnchor.constraint(equalTo: topAnchor),
      dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
      dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
      dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    cardView.backgroundColor = UIColor.systemBackground
    cardView.layer.cornerRadius = 14
    cardView.layer.shadowColor = UIColor.black.cgColor
    cardView.layer.shadowOpacity = 0.2
    cardView.layer.shadowRadius = 12
    cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
    cardView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(cardView)
    NSLayoutConstraint.activate([
      cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
      cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
      cardView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
      cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
    ])
    // 首选宽度 280pt (低优先级): 窄屏时让给上面两条上限约束, 不冲突。
    let preferredWidth = cardView.widthAnchor.constraint(equalToConstant: 280)
    preferredWidth.priority = .defaultHigh
    preferredWidth.isActive = true

    titleLabel.text = text
    titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
    titleLabel.textColor = UIColor.label
    titleLabel.textAlignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let forgetButton = makeButton(title: "忘记记忆", color: UIColor.systemRed, action: #selector(forgetTapped))
    let pinButton = makeButton(title: pinned ? "取消置顶" : "置顶", color: UIColor.label, action: #selector(pinTapped))
    let cancelButton = makeButton(title: "取消", color: UIColor.systemBlue, action: #selector(dismissTapped))

    let stack = UIStackView(arrangedSubviews: [titleLabel, makeSeparator(), forgetButton, makeSeparator(), pinButton, makeSeparator(), cancelButton])
    stack.axis = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    cardView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: cardView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
      titleLabel.heightAnchor.constraint(equalToConstant: 52),
      forgetButton.heightAnchor.constraint(equalToConstant: 48),
      pinButton.heightAnchor.constraint(equalToConstant: 48),
      cancelButton.heightAnchor.constraint(equalToConstant: 48),
    ])
  }

  private func makeButton(title: String, color: UIColor, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(color, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 17)
    button.addTarget(self, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  private func makeSeparator() -> UIView {
    let view = UIView()
    view.backgroundColor = UIColor.separator
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    return view
  }

  private func animateIn() {
    dimView.alpha = 0
    cardView.alpha = 0
    cardView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
      self.dimView.alpha = 1
      self.cardView.alpha = 1
      self.cardView.transform = .identity
    }
  }

  func dismiss() {
    removeFromSuperview()
  }

  @objc private func dismissTapped() {
    dismiss()
  }

  @objc private func forgetTapped() {
    dismiss()
    onForget()
  }

  @objc private func pinTapped() {
    dismiss()
    onTogglePin()
  }
}
