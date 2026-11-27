//
//  KeyboardImagePastePanelView.swift
//
//  "拷贝的图片"面板 (仿微信输入法):
//  剪贴板里有图片 (电脑同步下来 / 本机复制) 时, 工具栏亮起图片图标;
//  点图标打开本面板: 顶部 [图片图标 拷贝的图片 | X], 中间是图片缩略图,
//  点图片后收起面板 (图片已在系统剪贴板, 长按输入框粘贴)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// "拷贝的图片"面板: 标题 + 图片缩略图 + 提示。
class KeyboardImagePastePanelView: NibLessView {
  /// 点图片时的回调, 由调用方收起面板 (图片已在剪贴板, 用户长按输入框粘贴)。
  var onTapImage: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
    }
  }

  private lazy var titleIconView: UIImageView = {
    let view = UIImageView(image: UIImage(systemName: "photo"))
    view.tintColor = .label
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "拷贝的图片"
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.tintColor = .label
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  private lazy var imageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.backgroundColor = .systemBackground
    view.layer.cornerRadius = 8
    view.clipsToBounds = true
    view.isUserInteractionEnabled = true
    view.translatesAutoresizingMaskIntoConstraints = false
    let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
    view.addGestureRecognizer(tap)
    return view
  }()

  private lazy var hintLabel: UILabel = {
    let label = UILabel()
    label.text = "轻点图片后, 长按输入框粘贴"
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  init() {
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(titleIconView)
    addSubview(titleLabel)
    addSubview(closeButton)
    addSubview(imageView)
    addSubview(hintLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleIconView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
      titleIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleIconView.widthAnchor.constraint(equalToConstant: 20),
      titleIconView.heightAnchor.constraint(equalToConstant: 20),

      titleLabel.centerYAnchor.constraint(equalTo: titleIconView.centerYAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: titleIconView.trailingAnchor, constant: 6),

      closeButton.centerYAnchor.constraint(equalTo: titleIconView.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      closeButton.widthAnchor.constraint(equalToConstant: 28),
      closeButton.heightAnchor.constraint(equalToConstant: 28),

      imageView.topAnchor.constraint(equalTo: titleIconView.bottomAnchor, constant: 12),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
      imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -100),
      imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
      imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

      hintLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
      hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
      hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从图片后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新图片: 把剪贴板里的图片放进缩略图。
  func reload(with image: UIImage) {
    imageView.image = image
  }

  @objc private func imageTapped() {
    onTapImage?()
  }

  @objc private func closeTapped() {
    onClose?()
  }
}
