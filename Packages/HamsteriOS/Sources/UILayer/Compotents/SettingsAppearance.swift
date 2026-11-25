//
//  SettingsAppearance.swift
//  Hamster
//
//  round 16 item 3: App 设置页扁平化共用外观 (仿微信设置)。
//  微信绿 #07C160 作强调色, 浅绿底 + 白卡片; 深色模式用系统分组底色。
//  只改外观, 不改任何设置项的键、取值范围与默认值。
//

import UIKit

/// App 设置页扁平化外观 token。
public enum SettingsAppearance {
  /// 微信绿 #07C160: 滑块轨道/滑块、开关、选中态强调色。
  public static let weChatGreen = UIColor(red: 0x07 / 255.0, green: 0xC1 / 255.0, blue: 0x60 / 255.0, alpha: 1.0)

  /// 设置页底色: 浅色淡绿 (与设置首页一致), 深色用系统分组底色。
  public static let pageBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.systemGroupedBackground
      : UIColor(red: 0.92, green: 0.96, blue: 0.93, alpha: 1.0)
  }

  /// 卡片/分组底色: 浅色白, 深色用二级系统背景。
  public static let cardBackgroundColor = UIColor { trait in
    trait.userInterfaceStyle == .dark
      ? UIColor.secondarySystemBackground
      : UIColor.white
  }

  /// 行主标题字号 (统一 17)。
  public static let rowTitleFont = UIFont.systemFont(ofSize: 17)

  /// 行数值/副标题字号 (统一 15, 灰色)。
  public static let rowSecondaryFont = UIFont.systemFont(ofSize: 15)

  /// 扁平化列表: 淡绿底 + 细分隔线 + 自动行高 (滑块行约 76, 普通行约 44)。
  public static func apply(to tableView: UITableView) {
    tableView.backgroundColor = pageBackgroundColor
    tableView.separatorStyle = .singleLine
    tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 52
  }

  /// 开关强调色: 微信绿。
  public static func tint(_ switchView: UISwitch) {
    switchView.onTintColor = weChatGreen
  }

  /// 分段选择器: 选中段微信绿底 + 白字, 未选中段系统文字色。
  public static func tint(_ segmentedControl: UISegmentedControl) {
    segmentedControl.selectedSegmentTintColor = weChatGreen
    segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
  }
}
