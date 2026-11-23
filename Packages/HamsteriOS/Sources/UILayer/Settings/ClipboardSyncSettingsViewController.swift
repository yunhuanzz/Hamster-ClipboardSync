//
//  ClipboardSyncSettingsViewController.swift
//
//  跨设备粘贴传送子页 (仿微信输入法"跨设备粘贴传送"): 剪贴板同步的全部设置,
//  即原来设置首页 inline 的"剪贴板同步"那一节, 原样搬进子页
//  (SettingsViewModel.clipboardSyncSettings, 与 sections 共用同一批 item)。
//  同步 URL/账号/密码原样保留, 不做数据迁移。由设置首页卡片进入。
//

import HamsterUIKit
import UIKit

public class ClipboardSyncSettingsViewController: NibLessViewController {
  private let settingsViewModel: SettingsViewModel

  init(settingsViewModel: SettingsViewModel) {
    self.settingsViewModel = settingsViewModel

    super.init()
  }

  override public func loadView() {
    title = "跨设备粘贴传送"
    view = ClipboardSyncSettingsRootView(settingsViewModel: settingsViewModel)
  }
}
