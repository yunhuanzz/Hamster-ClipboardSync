//
//  SliderTableViewCell.swift
//  Hamster
//
//  round 16 item 3: 扁平化滑块行, 替代旧的 StepperTableViewCell (+/- 步进器)。
//  布局: 第一行标题 + 绿色数值, 第二行全宽滑块
//  (微信绿 #07C160 轨道/滑块, 浅灰未走完轨道)。
//  取值逻辑与旧步进器完全一致: min/max/step 全部取自 SettingItemModel,
//  拖动时按 step 取整后回调 valueChangeHandled, 显示值与旧 cell 一样是 Int。
//  不改任何设置键、范围与默认值。
//  防御: 个别 .step 项若没给合法范围 (max <= min 或 step <= 0),
//  只影响本行滑块的显示范围 (fallback 0...100 / step 1), 不碰配置值。
//

import HamsterUIKit
import UIKit

class SliderTableViewCell: NibLessTableViewCell {
  static let identifier = "SliderTableViewCell"

  // MARK: properties

  override var configurationState: UICellConfigurationState {
    var state = super.configurationState
    state.settingItemModel = self.settingItem
    return state
  }

  public var settingItem: SettingItemModel? = nil

  private let titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.font = SettingsAppearance.rowTitleFont
    label.textColor = .label
    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }()

  private let valueLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.font = .systemFont(ofSize: 17, weight: .semibold)
    label.textColor = SettingsAppearance.weChatGreen
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
  }()

  private lazy var slider: UISlider = {
    let slider = UISlider()
    slider.minimumTrackTintColor = SettingsAppearance.weChatGreen
    slider.maximumTrackTintColor = .systemFill
    slider.thumbTintColor = SettingsAppearance.weChatGreen
    slider.isContinuous = true
    slider.addTarget(
      self,
      action: #selector(sliderChanged(_:)),
      for: .valueChanged
    )
    return slider
  }()

  private lazy var titleRowView: UIStackView = {
    let stackView = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.distribution = .fill
    stackView.spacing = 8
    return stackView
  }()

  private lazy var containerView: UIStackView = {
    let stackView = UIStackView(arrangedSubviews: [titleRowView, slider])
    stackView.axis = .vertical
    stackView.alignment = .fill
    stackView.distribution = .fill
    stackView.spacing = 2
    return stackView
  }()

  // MARK: methods

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    selectionStyle = .none
    setupSliderView()
  }

  func setupSliderView() {
    contentView.addSubview(containerView)
    containerView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 10),
      containerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      slider.heightAnchor.constraint(equalToConstant: 31),
    ])
  }

  /// 与旧步进器同一语义: 按 step 取整后写回, 显示 Int 值。
  @objc func sliderChanged(_ sender: UISlider) {
    guard let item = settingItem else { return }
    let snapped = Self.snappedValue(Double(sender.value), for: item)
    sender.value = Float(snapped)
    valueLabel.text = String(Int(snapped))
    item.valueChangeHandled?(snapped)
  }

  /// 按 item 的 min/max/step 取整并夹紧 (旧步进器也是离散步进)。
  static func snappedValue(_ value: Double, for item: SettingItemModel) -> Double {
    let min = item.minValue
    let max = item.maxValue > item.minValue ? item.maxValue : item.minValue + 100
    let step = item.stepValue > 0 ? item.stepValue : 1
    var snapped = ((value - min) / step).rounded() * step + min
    snapped = Swift.min(Swift.max(snapped, min), max)
    return snapped
  }

  func updateWithSettingItem(_ item: SettingItemModel) {
    self.settingItem = item
    setNeedsUpdateConfiguration()
  }

  override func prepareForReuse() {
    super.prepareForReuse()

    titleLabel.text = ""
    valueLabel.text = ""
  }

  override func updateConfiguration(using state: UICellConfigurationState) {
    super.updateConfiguration(using: state)

    guard let item = state.settingItemModel else { return }
    titleLabel.text = item.text
    slider.accessibilityLabel = item.text

    let min = item.minValue
    let max = item.maxValue > item.minValue ? item.maxValue : item.minValue + 100
    slider.minimumValue = Float(min)
    slider.maximumValue = Float(max)

    if let text = item.textValue?(), let value = Double(text) {
      let clamped = Swift.min(Swift.max(value, min), max)
      slider.value = Float(clamped)
      valueLabel.text = String(Int(clamped))
    } else {
      slider.value = Float(min)
      valueLabel.text = String(Int(min))
    }
  }
}
