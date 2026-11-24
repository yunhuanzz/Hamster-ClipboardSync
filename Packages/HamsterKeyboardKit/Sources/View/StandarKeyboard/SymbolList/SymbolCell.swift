//
//  SymbolCell.swift
//
//
//  Created by morse on 2023/9/7.
//

import UIKit

/// 扩展 UIConfigurationStateCustomKey，用来表示 state 中自定义的数据
private extension UIConfigurationStateCustomKey {
  static let classifySymbolCellText = UIConfigurationStateCustomKey("com.ihsiao.apps.hamster.keyboard.ClassifyKeyboardCell.text")
}

/// 扩展 UICellConfigurationState，添加自定义数据属性
private extension UICellConfigurationState {
  var symbol: String? {
    get {
      self[.classifySymbolCellText] as? String
    }
    set {
      self[.classifySymbolCellText] = newValue
    }
  }
}

/// 符号单元格
class SymbolCell: UICollectionViewListCell {
  public var symbol: String? = nil
  private var style: NonStandardKeyboardStyle? = nil

  /// 白色圆角键底 (第 11 轮第 3 条: 微信符号菜单的键是白色圆角键,
  /// 不是扁平文字)。格子 40x40, 键底内缩 2pt, 圆角与按键一致。
  private let keyBackgroundView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  var symbolLabel: UILabel = {
    let label = UILabel()
    label.textAlignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.numberOfLines = 1
//    label.adjustsFontSizeToFitWidth = true
//    label.minimumScaleFactor = 0.2
    label.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override var configurationState: UICellConfigurationState {
    var state = super.configurationState
    state.symbol = symbol
    return state
  }

  override init(frame: CGRect = .zero) {
    super.init(frame: frame)

    constructViewHierarchy()
    activateViewConstraints()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func constructViewHierarchy() {
    contentView.addSubview(keyBackgroundView)
    contentView.addSubview(symbolLabel)
  }

  func activateViewConstraints() {
    NSLayoutConstraint.activate([
      keyBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
      keyBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
      keyBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
      keyBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),

      symbolLabel.topAnchor.constraint(equalToSystemSpacingBelow: contentView.topAnchor, multiplier: 1.0),
      contentView.bottomAnchor.constraint(equalToSystemSpacingBelow: symbolLabel.bottomAnchor, multiplier: 1.0),
      symbolLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      symbolLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      separatorLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor)
    ])
  }

  func updateWithSymbol(
    _ symbol: String,
    style: NonStandardKeyboardStyle
  ) {
    self.symbol = symbol
    self.style = style
    // 键底圆角与键盘按键一致; 圆角只裁自己的底色, 不裁子视图。
    keyBackgroundView.layer.cornerRadius = style.cornerRadius

    setNeedsUpdateConfiguration()
  }

  override func updateConfiguration(using state: UICellConfigurationState) {
    super.updateConfiguration(using: state)

    symbolLabel.text = state.symbol
    // symbolLabel.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
    // symbolLabel.textAlignment = .center
    // symbolLabel.adjustsFontSizeToFitWidth = true

    // 格子本身透明, 白色圆角键底由 keyBackgroundView 画。
    var backgroundConfig = UIBackgroundConfiguration.clear()
    backgroundConfig.backgroundColor = .clear
    self.backgroundConfiguration = backgroundConfig

    if state.isHighlighted || state.isSelected {
      keyBackgroundView.backgroundColor = style?.keyPressedBackgroundColor ?? style?.pressedBackgroundColor
      symbolLabel.textColor = style?.pressedForegroundColor
    } else {
      keyBackgroundView.backgroundColor = style?.keyBackgroundColor ?? style?.backgroundColor
      symbolLabel.textColor = style?.foregroundColor
    }
  }

  override func prepareForReuse() {
    symbolLabel.text = ""
  }
}
