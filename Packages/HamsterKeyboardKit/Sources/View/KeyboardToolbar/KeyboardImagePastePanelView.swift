//
//  KeyboardImagePastePanelView.swift
//
//  "拷贝的图片"面板 (仿微信输入法):
//  剪贴板里有图片 (电脑同步下来 / 本机复制) 时, 工具栏亮起图片图标;
//  点图标打开本面板: 左上角返回箭头 (^ 白圆钮), 中间是白色圆角卡片里的
//  图片小图, 下面是提示文字, 底部是发送图标 (点一下粘贴到输入框)。
//  点小图查看大图 (全屏, 再点一下返回小图)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// "拷贝的图片"面板: 返回箭头 + 图片卡片 + 提示 + 发送图标, 点小图看大图。
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

  /// 是否正在看大图 (全屏): 是则只显示大图, 点一下返回小图。
  private var isZoomed = false

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
  private lazy var cardView: UIView = {
    let view = UIView()
    view.backgroundColor = .systemBackground
    view.layer.cornerRadius = 16
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 图片小图: 点一下查看大图。
  private lazy var imageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.isUserInteractionEnabled = true
    view.translatesAutoresizingMaskIntoConstraints = false
    let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
    view.addGestureRecognizer(tap)
    return view
  }()

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

  /// 大图 (全屏查看): 黑底, 图片居中, 点一下返回小图。
  private lazy var zoomView: UIView = {
    let view = UIView()
    view.backgroundColor = .black
    view.isHidden = true
    view.translatesAutoresizingMaskIntoConstraints = false
    let tap = UITapGestureRecognizer(target: self, action: #selector(zoomTapped))
    view.addGestureRecognizer(tap)
    return view
  }()

  private lazy var zoomImageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
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
    addSubview(zoomView)
    zoomView.addSubview(zoomImageView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      backButton.widthAnchor.constraint(equalToConstant: 32),
      backButton.heightAnchor.constraint(equalToConstant: 32),

      cardView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 16),
      cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      cardView.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -12),

      imageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
      imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
      imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

      hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      hintLabel.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

      copyButton.centerXAnchor.constraint(equalTo: centerXAnchor),
      copyButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),

      zoomView.topAnchor.constraint(equalTo: topAnchor),
      zoomView.leadingAnchor.constraint(equalTo: leadingAnchor),
      zoomView.trailingAnchor.constraint(equalTo: trailingAnchor),
      zoomView.bottomAnchor.constraint(equalTo: bottomAnchor),

      zoomImageView.topAnchor.constraint(equalTo: zoomView.topAnchor),
      zoomImageView.leadingAnchor.constraint(equalTo: zoomView.leadingAnchor),
      zoomImageView.trailingAnchor.constraint(equalTo: zoomView.trailingAnchor),
      zoomImageView.bottomAnchor.constraint(equalTo: zoomView.bottomAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从卡片后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新图片: 把剪贴板里的图片放进小图 (大图共用同一张)。
  func reload(with image: UIImage) {
    imageView.image = image
    zoomImageView.image = image
  }

  /// 点小图: 全屏看大图 (黑底, 点一下返回)。
  @objc private func imageTapped() {
    isZoomed = true
    zoomView.isHidden = false
    bringSubviewToFront(zoomView)
  }

  /// 大图状态下点一下: 返回小图。
  @objc private func zoomTapped() {
    isZoomed = false
    zoomView.isHidden = true
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
