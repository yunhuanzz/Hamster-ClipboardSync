//
//  KeyboardImagePastePanelView.swift
//
//  "拷贝的图片"面板 (仿微信输入法):
//  剪贴板里有图片 (电脑同步下来 / 本机复制) 时, 工具栏左侧先出
//  图标+文字的粘贴提示行; 没马上查看时提示行折成右侧临时图片图标;
//  点图标/提示行打开本面板: 左上角返回箭头 (裸图标, 无白圆),
//  中间是白色圆角卡片里的小图预览 (尺寸封顶, 不会撑满整个键盘),
//  下面是提示文字, 底部是"复制到剪贴板"文字按钮。
//  点小图查看大图 (全屏黑底, 双指自由缩放、双击切换缩放、
//  点一下空白处返回、向下拖动时背景渐透明、拖过阈值松手退出)。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// "拷贝的图片"面板: 返回箭头 + 图片卡片 (小图预览) + 提示 + 复制按钮, 点小图看大图。
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

  /// 图片小图: 点一下查看大图。宽高由 reload(with:) 按原图比例
  /// 算出并封顶后写入约束, 不用 intrinsic 尺寸 (大图 intrinsic
  /// 尺寸会把卡片撑爆)。
  private lazy var imageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.isUserInteractionEnabled = true
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
    view.addGestureRecognizer(tap)
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

  /// 大图 (全屏查看): 黑底 + 自由缩放 + 点按返回 + 拖动退出。
  private lazy var zoomView: KeyboardImageZoomView = {
    let view = KeyboardImageZoomView()
    view.isHidden = true
    view.translatesAutoresizingMaskIntoConstraints = false
    view.onDismiss = { [weak self] in self?.hideZoom() }
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

      zoomView.topAnchor.constraint(equalTo: topAnchor),
      zoomView.leadingAnchor.constraint(equalTo: leadingAnchor),
      zoomView.trailingAnchor.constraint(equalTo: trailingAnchor),
      zoomView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从卡片后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新图片: 把剪贴板里的图片放进小图 (大图共用同一张)。
  /// 小图尺寸按原图比例算出并封顶 (宽 ≤ 屏幕宽 - 64, 高 ≤ 150),
  /// 写进显式宽高约束——不用 UIImageView 的 intrinsic 尺寸,
  /// 大截图的 intrinsic 尺寸会把卡片撑满整个键盘。
  func reload(with image: UIImage) {
    imageView.image = image
    zoomView.reload(with: image)
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

  /// 点小图: 全屏看大图 (黑底, 双指缩放、点按返回、拖动退出)。
  @objc private func imageTapped() {
    zoomView.isHidden = false
    bringSubviewToFront(zoomView)
  }

  /// 大图退出 (点按空白处 / 拖动过阈值松手): 回到小图。
  private func hideZoom() {
    zoomView.isHidden = true
    zoomView.resetForReuse()
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

// MARK: - 全屏大图查看器

/// 全屏大图查看器: 纯黑底, 图片居中。
/// - 双指捏合自由缩放 (1x–4x), 双击切换 1x/2.5x;
/// - 点一下任意处返回 (空白处和图片上都可以, 单击等双击失败后再触发);
/// - 未放大时向下拖动图片: 图片跟手下移并略缩小, 黑底随拖动渐透明,
///   拖过阈值或快速下甩松手即退出, 否则弹回原位。
class KeyboardImageZoomView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  /// 退出大图时的回调 (由面板关闭大图层)。
  var onDismiss: (() -> Void)?

  private static let maxZoomScale: CGFloat = 4.0
  private static let doubleTapZoomScale: CGFloat = 2.5
  private static let dismissThreshold: CGFloat = 140
  private static let dismissVelocity: CGFloat = 800

  private lazy var scrollView: UIScrollView = {
    let view = UIScrollView()
    view.backgroundColor = .clear
    view.minimumZoomScale = 1.0
    view.maximumZoomScale = Self.maxZoomScale
    view.showsVerticalScrollIndicator = false
    view.showsHorizontalScrollIndicator = false
    view.delegate = self
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var zoomImageView: UIImageView = {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var singleTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(singleTapFired))
    tap.numberOfTapsRequired = 1
    tap.delegate = self
    return tap
  }()

  private lazy var doubleTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTapFired))
    tap.numberOfTapsRequired = 2
    tap.delegate = self
    return tap
  }()

  private lazy var dismissPan: UIPanGestureRecognizer = {
    let pan = UIPanGestureRecognizer(target: self, action: #selector(dismissPanFired))
    pan.delegate = self
    return pan
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    addSubview(scrollView)
    scrollView.addSubview(zoomImageView)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    singleTap.require(toFail: doubleTap)
    addGestureRecognizer(singleTap)
    addGestureRecognizer(doubleTap)
    addGestureRecognizer(dismissPan)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutZoomImage()
  }

  /// 换图 / 尺寸变化时把图片按比例放进当前视图 (仅在未放大时重算,
  /// 避免打断用户正在进行的缩放)。
  func reload(with image: UIImage) {
    zoomImageView.image = image
    scrollView.zoomScale = 1.0
    scrollView.transform = .identity
    backgroundColor = .black
    setNeedsLayout()
  }

  /// 面板重用大图层前复位 (缩放、位移、底色都回到初始态)。
  func resetForReuse() {
    scrollView.zoomScale = 1.0
    scrollView.transform = .identity
    backgroundColor = .black
    layoutZoomImage()
  }

  private func layoutZoomImage() {
    guard let image = zoomImageView.image else { return }
    let boundsSize = scrollView.bounds.size
    guard boundsSize.width > 0, boundsSize.height > 0 else { return }
    let imageSize = image.size
    guard imageSize.width > 0, imageSize.height > 0 else { return }
    guard scrollView.zoomScale == 1.0 else { return }
    let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
    let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    zoomImageView.frame = CGRect(
      x: (boundsSize.width - fitted.width) / 2,
      y: (boundsSize.height - fitted.height) / 2,
      width: fitted.width, height: fitted.height)
    scrollView.contentSize = fitted
    centerZoomImage()
  }

  /// 图片比可视区小时把它居中 (缩放后也保持居中)。
  private func centerZoomImage() {
    let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
    let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
    zoomImageView.center = CGPoint(
      x: scrollView.contentSize.width * 0.5 + offsetX,
      y: scrollView.contentSize.height * 0.5 + offsetY)
  }

  // MARK: UIScrollViewDelegate

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    zoomImageView
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    centerZoomImage()
  }

  // MARK: 手势

  /// 点一下任意处 (空白处或图片上): 退出大图。
  @objc private func singleTapFired() {
    onDismiss?()
  }

  /// 双击: 在 1x 与 2.5x 之间切换, 以点按位置为中心缩放。
  @objc private func doubleTapFired(_ gesture: UITapGestureRecognizer) {
    if scrollView.zoomScale > 1.0 {
      scrollView.setZoomScale(1.0, animated: true)
      return
    }
    let point = gesture.location(in: zoomImageView)
    let scale = Self.doubleTapZoomScale
    let size = CGSize(
      width: scrollView.bounds.width / scale,
      height: scrollView.bounds.height / scale)
    let origin = CGPoint(
      x: point.x - size.width / 2,
      y: point.y - size.height / 2)
    scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
  }

  /// 向下拖动退出: 未放大时才生效; 图片跟手下移并略缩小,
  /// 黑底随拖动渐透明; 拖过阈值或快速下甩松手即退出, 否则弹回原位。
  @objc private func dismissPanFired(_ gesture: UIPanGestureRecognizer) {
    guard scrollView.zoomScale == 1.0 else { return }
    let translation = gesture.translation(in: self)
    switch gesture.state {
    case .changed:
      let dragY = max(0, translation.y)
      let progress = min(dragY / Self.dismissThreshold, 1.0)
      let scale = 1.0 - 0.1 * progress
      scrollView.transform = CGAffineTransform(translationX: 0, y: dragY).scaledBy(x: scale, y: scale)
      backgroundColor = UIColor.black.withAlphaComponent(1.0 - 0.7 * progress)
    case .ended, .cancelled:
      let dragY = max(0, translation.y)
      let velocity = gesture.velocity(in: self).y
      if dragY > Self.dismissThreshold || velocity > Self.dismissVelocity {
        UIView.animate(withDuration: 0.25, animations: {
          self.scrollView.transform = CGAffineTransform(translationX: 0, y: self.bounds.height).scaledBy(x: 0.9, y: 0.9)
          self.backgroundColor = UIColor.black.withAlphaComponent(0)
        }, completion: { _ in
          self.onDismiss?()
        })
      } else {
        UIView.animate(
          withDuration: 0.3, delay: 0,
          usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
          options: [], animations: {
            self.scrollView.transform = .identity
            self.backgroundColor = .black
          })
      }
    default:
      break
    }
  }

  // MARK: UIGestureRecognizerDelegate

  /// 拖动退出只在未放大时开始 (放大后拖动交给 scrollView 滚动)。
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === dismissPan {
      return scrollView.zoomScale == 1.0
    }
    return true
  }

  /// 拖动退出与 scrollView 的滚动手势可同时识别 (未放大时 scrollView
  /// 本来也滚不动, 不冲突; 放大后本手势根本不开始)。
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    gestureRecognizer === dismissPan
  }
}
