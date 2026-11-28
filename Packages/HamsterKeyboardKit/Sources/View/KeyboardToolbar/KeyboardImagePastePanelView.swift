//
//  KeyboardImagePastePanelView.swift
//
//  "拷贝的图片"面板 (仿微信输入法):
//  剪贴板里有图片 (电脑同步下来 / 本机复制) 时, 工具栏左侧先出
//  图标+文字的粘贴提示行; 没马上查看时提示行折成右侧临时图片图标;
//  点图标/提示行打开本面板: 左上角返回箭头 (裸图标, 无白圆),
//  中间是白色圆角卡片里的小图预览 (尺寸封顶, 不会撑满整个键盘),
//  下面是提示文字, 底部是"复制到剪贴板"文字按钮。
//  点小图不做任何事 (2026-11-28 用户决定不要放大功能:
//  键盘扩展画不出键盘外, 放大图只能框在键盘里, 不如不要)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// "拷贝的图片"面板: 返回箭头 + 图片卡片 (小图预览) + 提示 + 复制按钮。
/// 点小图不做任何事 (放大功能已删除, 见文件头)。
class KeyboardImagePastePanelView: NibLessView {
  /// 点"复制到剪贴板"时的回调, 由调用方把图片放进系统剪贴板并关闭面板。
  var onCopy: (() -> Void)?
  /// 点返回箭头时的回调, 由调用方关闭面板。
  var onClose: (() -> Void)?

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
    }
  }

  /// 预览小图尺寸上限: 宽不超过屏幕宽 - 64, 高不超过 150。
  /// 小图是预览, 不是全屏展示——之前不限尺寸, 大截图的 intrinsic
  /// 尺寸把卡片撑满整个键盘 (用户 2026-11-27 反馈 "界面都成这样了")。
  private static let previewMaxWidthMargin: CGFloat = 64
  private static let previewMaxHeight: CGFloat = 150

  /// 左上角返回箭头: 裸图标 (与临时复制图标同款——无背景、无白圆、
  /// 无边框, 只靠图标本身; 美术统一, 见用户 2026-11-27 纠正)。
  private lazy var backButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(systemName: "chevron.up"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default), forImageIn: .normal)
    button.tintColor = .label
    button.backgroundColor = .clear
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    return button
  }()

  /// 白色圆角卡片 (仿微信): 图片小图放在卡片里, 四周留白。
  /// 卡片尺寸由小图决定 (小图宽高有显式约束封顶), 不随面板拉伸。
  private lazy var cardView: UIView = {
    let view = UIView()
    view.backgroundColor = .systemBackground
    view.layer.cornerRadius = 16
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 图片小图: 点一下不做任何事 (放大功能已删除)。
  /// 宽高由 reload(with:) 按原图比例算出并封顶后写入约束,
  /// 不用 intrinsic 尺寸 (大图 intrinsic 尺寸会把卡片撑爆)。
  private lazy var imageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }()

  /// 小图宽高约束 (reload 时按原图比例封顶后写入)。
  private var imageWidthConstraint: NSLayoutConstraint?
  private var imageHeightConstraint: NSLayoutConstraint?

  /// 提示文字 (仿微信"可在关联设备粘贴"的灰字)。
  private lazy var hintLabel: UILabel = {
    let label = UILabel()
    label.text = "长按输入框粘贴图片"
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 底部复制按钮: 文字按钮 (用户 2026-11-27: 不能直接发送就改成
  /// 复制到剪贴板, 直接改成文字)。点一下把图片放进系统剪贴板。
  private lazy var copyButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("复制到剪贴板", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16)
    button.setTitleColor(.label, for: .normal)
    button.backgroundColor = .clear
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
    return button
  }()

  init() {
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(backButton)
    addSubview(cardView)
    cardView.addSubview(imageView)
    addSubview(hintLabel)
    addSubview(copyButton)
  }

  override func activateViewConstraints() {
    imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 0)
    imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      backButton.widthAnchor.constraint(equalToConstant: 32),
      backButton.heightAnchor.constraint(equalToConstant: 32),

      cardView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
      cardView.centerXAnchor.constraint(equalTo: centerXAnchor),

      imageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
      imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
      imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
      imageWidthConstraint!,
      imageHeightConstraint!,

      hintLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 10),
      hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

      copyButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
      copyButton.centerXAnchor.constraint(equalTo: centerXAnchor),
      copyButton.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从卡片后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新图片: 把剪贴板里的图片放进小图。
  /// 小图尺寸按原图比例算出并封顶 (宽 ≤ 屏幕宽 - 64, 高 ≤ 150),
  /// 写进显式宽高约束——不用 UIImageView 的 intrinsic 尺寸,
  /// 大截图的 intrinsic 尺寸会把卡片撑满整个键盘。
  func reload(with image: UIImage) {
    imageView.image = image
    let size = image.size
    guard size.width > 0, size.height > 0 else {
      imageWidthConstraint?.constant = 0
      imageHeightConstraint?.constant = 0
      return
    }
    let maxWidth = UIScreen.main.bounds.width - Self.previewMaxWidthMargin
    let scale = min(maxWidth / size.width, Self.previewMaxHeight / size.height, 1.0)
    imageWidthConstraint?.constant = max(1, size.width * scale)
    imageHeightConstraint?.constant = max(1, size.height * scale)
  }

  /// 点"复制到剪贴板": 把图片放进系统剪贴板 (由调用方处理并关闭面板)。
  @objc private func copyTapped() {
    onCopy?()
  }

  /// 点左上角返回箭头: 关闭面板。
  @objc private func backTapped() {
    onClose?()
  }
}
