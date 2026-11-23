
//
//  MoreSettingsViewController.swift
//
//  "更多"设置页: 设置首页卡片之外的其余设置, 原有列表
//  (SettingsViewModel.moreSections), 不删任何功能。
//  由设置首页"更多"卡片进入。
//

import HamsterUIKit
import UIKit

public class MoreSettingsViewController: NibLessViewController {
  private let settingsViewModel: SettingsViewModel

  init(settingsViewModel: SettingsViewModel) {
    self.settingsViewModel = settingsViewModel

    super.init()
  }

  override public func loadView() {
    title = "更多"
    view = MoreSettingsRootView(settingsViewModel: settingsViewModel)
  }
}
