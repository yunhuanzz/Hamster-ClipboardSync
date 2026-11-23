//
//  LayoutDisplayViewController.swift
//
//  布局和显示子页 (仿微信输入法"布局和显示"): 候选字大小、候选栏高度、
//  拼音显示位置、26 键数字输入方式。全部接到 KeyboardSettingsViewModel 的
//  真实设置项, 没有假开关 (见 layoutDisplaySettings 的注释)。
//  由设置首页"布局和显示"卡片进入。
//

import HamsterUIKit
import UIKit

public class LayoutDisplayViewController: NibLessViewController {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel

    super.init()
  }

  override public func loadView() {
    title = "布局和显示"
    view = LayoutDisplayRootView(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }
}
