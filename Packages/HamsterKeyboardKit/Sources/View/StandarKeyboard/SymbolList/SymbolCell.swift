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
  /// 第 12 轮第 2 条: 白键只属于符号菜单 (SymbolsView); 九宫格左侧
  /// 符号栏 (SymbolsVerticalView) 复用本 cell, 默认不画白键, 保持
  /// 第 11 轮之前的透明扁平样式 (底色由列表背景透出来)。
  private let keyBackgroundView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  /// 是否画白色圆角键底。默认 false (第 11 轮之前的外观); 符号菜单
  /// 经 updateWithSymbol(_:style:showsKeyBackground:) 显式传 true。
  private var showsKeyBackground = false {
    didSet {
      keyBackgroundView.isHidden = !showsKeyBackground
    }
  }

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
    style: NonStandardKeyboardStyle,
    showsKeyBackground: Bool = false
  ) {
    self.symbol = symbol
    self.style = style
    self.showsKeyBackground = showsKeyBackground
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

    if showsKeyBackground {
      // 符号菜单: 格子本身透明, 白色圆角键底由 keyBackgroundView 画。
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
    } else {
      // 九宫格左侧符号栏 (第 11 轮之前原样): 格子透明, 底色由列表背景
      // 透出来; 按下时整格变色。不要画 keyBackgroundView, 否则侧栏
      // 会被漂白 (第 12 轮第 2 条回归)。
      keyBackgroundView.backgroundColor = .clear

      var backgroundConfig = UIBackgroundConfiguration.listGroupedCell()

      if state.isHighlighted || state.isSelected {
        backgroundConfig.backgroundColor = style?.pressedBackgroundColor
        symbolLabel.textColor = style?.pressedForegroundColor
      } else {
        // backgroundConfig.backgroundColor = style?.backgroundColor
        backgroundConfig.backgroundColor = .clear
        symbolLabel.textColor = style?.foregroundColor
      }

      self.backgroundConfiguration = backgroundConfig
    }
  }

  override func prepareForReuse() {
    symbolLabel.text = ""
    showsKeyBackground = false
  }
}
