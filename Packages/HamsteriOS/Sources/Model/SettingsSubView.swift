//
//  File.swift
//
//
//  Created by morse on 2023/7/7.
//

import Foundation

/// 主页设置子页面
public enum SettingsSubView: String {
  /// 输入方案页面
  case inputSchema
  
  /// 输入方案上传页面
  case uploadInputSchema
  
  /// 文件管理页面
  case finder
  
  /// 键盘设置页面
  case keyboardSettings
  
  /// 键盘配色页面
  case colorSchema
  
  /// 反馈设置页面
  case feedback
  
  /// iCloud页面
  case iCloud
  
  /// 备份页面
  case backup
  
  /// RIME 页面
  case rime
  
  /// 常用语页面
  case commonPhrases

  /// 我的词组页面
  case customPhrases

  /// 键盘管理页面 (九宫格/全键盘选择)
  case keyboardManagement

  /// 布局和显示页面 (候选字大小、拼音显示位置、数字输入方式等)
  case layoutDisplay

  /// 跨设备粘贴传送页面 (剪贴板同步设置)
  case clipboardSync

  /// 定制工具栏页面 (候选栏设置)
  case toolbarSettings

  /// 更多设置页面 (首页卡片之外的其余设置, 原有列表)
  case more

  /// 关于页面
  case about

  /// 主页面
  case main


  /// 空页面
  case none
}
