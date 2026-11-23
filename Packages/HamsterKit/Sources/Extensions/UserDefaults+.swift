//
//  UserDefaults.swift
//
//
//  Created by morse on 2023/7/3.
//

import Foundation
import OSLog
import Yams

/// UserDefault 扩展
public extension UserDefaults {
  /// AppGroup 共享 UserDefaults
  static let hamster = UserDefaults(suiteName: HamsterConstants.appGroupName)!

  // MARK: - 仓输入法 1.0 版本相关参数

  func _removeFirstRunningForV1() {
    removeObject(forKey: Self._appFirstLaunchForV1)
  }

  /// 应用首次运行检测（仓 1.0 版本）
  var _firstRunningForV1: Bool? {
    if object(forKey: Self._appFirstLaunchForV1) != nil {
      return bool(forKey: Self._appFirstLaunchForV1)
    }
    return nil
  }

  /// 是否开启划动（仓 1.0 版本）
  var _enableKeyboardSwipeGestureSymbol: Bool? {
    if object(forKey: Self._enableKeyboardSwipeGestureSymbol) != nil {
      return bool(forKey: Self._enableKeyboardSwipeGestureSymbol)
    }
    return nil
  }

  /// 划动配置参数（仓 1.0 版本）
  var _keyboardSwipeGestureSymbol: [String: String]? {
    if object(forKey: Self._keyboardSwipeGestureSymbol) != nil {
      return object(forKey: Self._keyboardSwipeGestureSymbol) as? [String: String]
    }
    return nil
  }

  /// 是否显示按键气泡（仓 1.0 版本）
  var _showKeyPressBubble: Bool? {
    if object(forKey: Self._showKeyPressBubble) != nil {
      return bool(forKey: Self._showKeyPressBubble)
    }
    return nil
  }

  /// 是否开启键盘声音（仓 1.0 版本）
  var _enableKeyboardFeedbackSound: Bool? {
    if object(forKey: Self._enableKeyboardFeedbackSound) != nil {
      return bool(forKey: Self._enableKeyboardFeedbackSound)
    }
    return nil
  }

  /// 是否开启键盘震动（仓 1.0 版本）
  var _enableKeyboardFeedbackHaptic: Bool? {
    if object(forKey: Self._enableKeyboardFeedbackHaptic) != nil {
      return bool(forKey: Self._enableKeyboardFeedbackHaptic)
    }
    return nil
  }

  /// 是否显示键盘收起按键（仓 1.0 版本）
  var _showKeyboardDismissButton: Bool? {
    if object(forKey: Self._showKeyboardDismissButton) != nil {
      return bool(forKey: Self._showKeyboardDismissButton)
    }
    return nil
  }

  /// 是否显示分号键（仓 1.0 版本）
  var _showSemicolonButton: Bool? {
    if object(forKey: Self._showSemicolonButton) != nil {
      return bool(forKey: Self._showSemicolonButton)
    }
    return nil
  }

  /// 是否显示空格左边按键（仓 1.0 版本）
  var _showSpaceLeftButton: Bool? {
    if object(forKey: Self._showSpaceLeftButton) != nil {
      return bool(forKey: Self._showSpaceLeftButton)
    }
    return nil
  }

  /// 空格左边按键键值（仓 1.0 版本）
  var _spaceLeftButtonValue: String? {
    if object(forKey: Self._spaceLeftButtonValue) != nil {
      return string(forKey: Self._spaceLeftButtonValue)
    }
    return nil
  }

  /// 是否显示空格右边按键（仓 1.0 版本）
  var _showSpaceRightButton: Bool? {
    if object(forKey: Self._showSpaceRightButton) != nil {
      return bool(forKey: Self._showSpaceRightButton)
    }
    return nil
  }

  /// 空格右边按键键值（仓 1.0 版本）
  var _spaceRightButtonValue: String? {
    if object(forKey: Self._spaceRightButtonValue) != nil {
      return string(forKey: Self._spaceRightButtonValue)
    }
    return nil
  }

  /// 是否显示空格右边中英文切换键（仓 1.0 版本）
  var _showSpaceRightSwitchLanguageButton: Bool? {
    if object(forKey: Self._showSpaceRightSwitchLanguageButton) != nil {
      return bool(forKey: Self._showSpaceRightSwitchLanguageButton)
    }
    return nil
  }

  /// 中英切换按键位于空格是否位于左侧（仓 1.0 版本）
  var _switchLanguageButtonInSpaceLeft: Bool? {
    if object(forKey: Self._switchLanguageButtonInSpaceLeft) != nil {
      return bool(forKey: Self._switchLanguageButtonInSpaceLeft)
    }
    return nil
  }

  /// rime 候选字最大数量（仓 1.0 版本）
  var _rimeMaxCandidateSize: Int? {
    if object(forKey: Self._rimeMaxCandidateSize) != nil {
      return integer(forKey: Self._rimeMaxCandidateSize)
    }
    return nil
  }

  /// rime 候选字Title字体大小（仓 1.0 版本）
  var _rimeCandidateTitleFontSize: Int? {
    if object(forKey: Self._rimeCandidateTitleFontSize) != nil {
      return integer(forKey: Self._rimeCandidateTitleFontSize)
    }
    return nil
  }

  /// rime 候选字 Comment 字体大小（仓 1.0 版本）
  var _rimeCandidateCommentFontSize: Int? {
    if object(forKey: Self._rimeCandidateCommentFontSize) != nil {
      return integer(forKey: Self._rimeCandidateCommentFontSize)
    }
    return nil
  }

  /// 候选栏高度（仓 1.0 版本）
  var _candidateBarHeight: Int? {
    if object(forKey: Self._candidateBarHeight) != nil {
      return integer(forKey: Self._candidateBarHeight)
    }
    return nil
  }

  /// RIME 简繁切换的key（仓 1.0 版本）
  var _rimeSimplifiedAndTraditionalSwitcherKey: String? {
    if object(forKey: Self._rimeSimplifiedAndTraditionalSwitcherKey) != nil {
      return string(forKey: Self._rimeSimplifiedAndTraditionalSwitcherKey)
    }
    return nil
  }

  /// 嵌入模式（仓 1.0 版本）
  var _enableInputEmbeddedMode: Bool? {
    if object(forKey: Self._enableInputEmbeddedMode) != nil {
      return bool(forKey: Self._enableInputEmbeddedMode)
    }
    return nil
  }

  /// 键盘是否自动小写（仓 1.0 版本）
  var _enableKeyboardAutomaticallyLowercase: Bool? {
    if object(forKey: Self._enableKeyboardAutomaticallyLowercase) != nil {
      return bool(forKey: Self._enableKeyboardAutomaticallyLowercase)
    }
    return nil
  }

  // MARK: - 仓输入法 2.0

  /// 应用首次运行
  var isFirstRunning: Bool {
    get {
      if object(forKey: Self.isFirstRunningOfKey) != nil {
        return bool(forKey: Self.isFirstRunningOfKey)
      }
      return true
    }
    set {
      setValue(newValue, forKey: Self.isFirstRunningOfKey)
      Logger.statistics.debug("save isFirstRunning: \(newValue)")
    }
  }

  /// 是否覆盖 RIME 的用户数据目录
  var overrideRimeDirectory: Bool {
    get {
      if object(forKey: Self.overrideRimeDirectoryOfKey) != nil {
        return bool(forKey: Self.overrideRimeDirectoryOfKey)
      }
      return true
    }
    set {
      setValue(newValue, forKey: Self.overrideRimeDirectoryOfKey)
      Logger.statistics.debug("save overrideRimeDirectory: \(newValue)")
    }
  }

  /// RIME: 输入方案列表
  var schemas: [RimeSchema] {
    get {
      // 对数组类型且为Struct值需要特殊处理
      if let data = data(forKey: Self.schemasForKey), let array = try? JSONDecoder().decode([RimeSchema].self, from: data) {
        return array
      } else {
        return []
      }
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.hamster.set(data, forKey: Self.schemasForKey)
        Logger.statistics.debug("save schemas: \(newValue)")
      }
    }
  }

  /// RIME: 用户选择输入方案列表
  var selectSchemas: [RimeSchema] {
    get {
      // 对数组类型且为Struct值需要特殊处理
      if let data = data(forKey: Self.selectSchemasForKey), let array = try? JSONDecoder().decode([RimeSchema].self, from: data) {
        return array
      } else {
        return []
      }
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.hamster.set(data, forKey: Self.selectSchemasForKey)
        Logger.statistics.debug("save selectSchemas: \(newValue)")
      }
    }
  }

  /// RIME: 当前输入方案Schema
  var currentSchema: RimeSchema? {
    get {
      // 对数组类型且为Struct值需要特殊处理
      if let data = data(forKey: Self.currentSchemaForKey), let schema = try? JSONDecoder().decode(RimeSchema.self, from: data) {
        return schema
      } else {
        return nil
      }
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.hamster.set(data, forKey: Self.currentSchemaForKey)
        Logger.statistics.debug("save currentSchema: \(data)")
      }
    }
  }

  /// RIME: 最近一次输入方案的Schema
  var latestSchema: RimeSchema? {
    get {
      // 对数组类型且为Struct值需要特殊处理
      if let data = data(forKey: Self.latestSchemaForKey), let schema = try? JSONDecoder().decode(RimeSchema.self, from: data) {
        return schema
      } else {
        return nil
      }
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.hamster.set(data, forKey: Self.latestSchemaForKey)
        Logger.statistics.debug("save latestSchema: \(data)")
      }
    }
  }

  /// RIME Switch key
  var hotKeys: [String] {
    get {
      // 对数组类型且为Struct值需要特殊处理
      if let keys = array(forKey: Self.hotKeys) as? [String] {
        return keys
      } else {
        return ["f4"]
      }
    }
    set {
      set(newValue, forKey: Self.hotKeys)
    }
  }

  // MARK: - 剪贴板同步 (ClipboardSync)

  /// 是否启用剪贴板同步 (默认关闭)
  var clipboardSyncEnabled: Bool {
    get { bool(forKey: Self.clipboardSyncEnabledKey) }
    set { set(newValue, forKey: Self.clipboardSyncEnabledKey) }
  }

  /// 剪贴板同步服务器地址, 如 https://example.com:8444 (留空表示未配置)
  var clipboardSyncServerURL: String {
    get { string(forKey: Self.clipboardSyncServerURLKey) ?? "" }
    set { set(newValue, forKey: Self.clipboardSyncServerURLKey) }
  }

  /// 剪贴板同步用户名 (可空, 留空则不做 Basic Auth)
  var clipboardSyncUsername: String {
    get { string(forKey: Self.clipboardSyncUsernameKey) ?? "" }
    set { set(newValue, forKey: Self.clipboardSyncUsernameKey) }
  }

  /// 剪贴板同步密码 (可空)
  /// 注意: 与仓内其他配置一样保存在 App Group UserDefaults 中, 未使用 Keychain。
  var clipboardSyncPassword: String {
    get { string(forKey: Self.clipboardSyncPasswordKey) ?? "" }
    set { set(newValue, forKey: Self.clipboardSyncPasswordKey) }
  }

  /// 上次同步内容的 SHA-256 (内部防回环用, 避免重复上传刚下载的内容)
  var clipboardSyncLastHash: String {
    get { string(forKey: Self.clipboardSyncLastHashKey) ?? "" }
    set { set(newValue, forKey: Self.clipboardSyncLastHashKey) }
  }

  /// 最近一次同步结果, 如 "13:20 同步成功" / "13:20 上传失败(HTTP 405)"。
  /// 由 ClipboardSyncService 在每次同步结束时写入, 供剪贴板面板与设置页展示,
  /// 同步不再是"静默"的; 未同步过时为空字符串。
  var clipboardSyncLastStatusText: String {
    get { string(forKey: Self.clipboardSyncLastStatusTextKey) ?? "" }
    set { set(newValue, forKey: Self.clipboardSyncLastStatusTextKey) }
  }

  // MARK: - 中文主键盘布局 (九宫格 / 26键)

  /// 用户通过键盘内菜单切换过的中文主键盘布局: true=九宫格, false=26键。
  /// nil 表示从未切换过, 此时以配置 (hamster.yaml 的 useKeyboardType) 为准。
  /// 切换后持久化, 下次打开键盘保持上次的选择。
  var chinesePrimaryKeyboardIsNineGrid: Bool? {
    get {
      if object(forKey: Self.chinesePrimaryKeyboardIsNineGridKey) != nil {
        return bool(forKey: Self.chinesePrimaryKeyboardIsNineGridKey)
      }
      return nil
    }
    set {
      if let newValue {
        set(newValue, forKey: Self.chinesePrimaryKeyboardIsNineGridKey)
      } else {
        removeObject(forKey: Self.chinesePrimaryKeyboardIsNineGridKey)
      }
    }
  }

  // MARK: - 工具栏自定义 (定制工具栏)

  /// 工具栏工具顺序: 全部工具 id 按显示顺序排列 (包括已隐藏的工具, 这样重新显示时
  /// 仍回到用户排好的位置)。未设置过时默认 ["clipboard", "phrases", "dismiss"]
  /// (收起键盘在最右, 方便拇指点按)。可见性仍由 toolbarVisibleTools 集合单独控制,
  /// 旧版的显示/隐藏选择不受影响, 无需迁移。
  /// 左侧菜单按钮本身不可隐藏 (它是打开菜单/恢复显示的入口), 不在列表里。
  var toolbarToolsOrder: [String] {
    get {
      if let array = array(forKey: Self.toolbarToolsOrderKey) as? [String] {
        // 过滤掉未知 id, 并补上漏掉的已知工具 (以后新增工具时默认显示在末尾)
        let known = array.filter { Self.toolbarToolAllIDs.contains($0) }
        let missing = Self.toolbarToolAllIDs.filter { !known.contains($0) }
        return known + missing
      }
      return Self.toolbarToolDefaultOrder
    }
    set {
      let ordered = newValue.filter { Self.toolbarToolAllIDs.contains($0) }
      let missing = Self.toolbarToolAllIDs.filter { !ordered.contains($0) }
      set(ordered + missing, forKey: Self.toolbarToolsOrderKey)
    }
  }

  /// 工具栏默认顺序: 剪贴板、常用语、收起键盘 (收起键盘在最右, 方便拇指点按)。
  static let toolbarToolDefaultOrder: [String] = ["clipboard", "phrases", "dismiss"]

  /// 工具栏工具可见性: 存放"显示"的工具 id 集合。
  /// 未设置过时全部显示; 工具 id: "clipboard"(剪贴板)、"phrases"(常用语)、"dismiss"(收起键盘)。
  /// 左侧菜单按钮本身不可隐藏 (它是打开菜单/恢复显示的入口)。
  var toolbarVisibleTools: Set<String> {
    get {
      if let array = array(forKey: Self.toolbarVisibleToolsKey) as? [String] {
        return Set(array)
      }
      return Set(Self.toolbarToolAllIDs)
    }
    set { set(Array(newValue), forKey: Self.toolbarVisibleToolsKey) }
  }

  /// 全部工具栏工具 id
  static let toolbarToolAllIDs: [String] = ["clipboard", "phrases", "dismiss"]

  /// 某个工具栏工具是否显示 (未设置过默认显示)
  func isToolbarToolVisible(_ toolID: String) -> Bool {
    toolbarVisibleTools.contains(toolID)
  }

  /// 设置某个工具栏工具是否显示
  func setToolbarToolVisible(_ toolID: String, visible: Bool) {
    var tools = toolbarVisibleTools
    if visible {
      tools.insert(toolID)
    } else {
      tools.remove(toolID)
    }
    toolbarVisibleTools = tools
  }

  /// 移动工具栏工具顺序 (拖拽排序后调用): from/to 为全部工具顺序中的下标。
  func moveToolbarTool(from source: Int, to destination: Int) {
    var order = toolbarToolsOrder
    guard order.indices.contains(source), order.indices.contains(destination), source != destination else { return }
    let tool = order.remove(at: source)
    order.insert(tool, at: destination)
    toolbarToolsOrder = order
  }

  /// 恢复默认顺序并全部显示。
  func resetToolbarToolsOrder() {
    toolbarToolsOrder = Self.toolbarToolDefaultOrder
    toolbarVisibleTools = Set(Self.toolbarToolAllIDs)
  }

  // MARK: - 剪贴板历史 (键盘内剪贴板按钮)

  /// 最近剪贴板文本历史, 最新在前, 最多 20 条 (只存文本)
  var clipboardHistory: [String] {
    get { array(forKey: Self.clipboardHistoryKey) as? [String] ?? [] }
    set { set(Array(newValue.prefix(Self.clipboardHistoryMaxCount)), forKey: Self.clipboardHistoryKey) }
  }

  /// 记录一条剪贴板文本到历史 (去重、置顶、截断到 20 条)
  func recordClipboardHistory(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var history = clipboardHistory
    history.removeAll { $0 == trimmed }
    history.insert(trimmed, at: 0)
    clipboardHistory = history
  }

  // MARK: - 常用语 (键盘内常用语按钮)

  /// 内置常用语 (首次使用、未自定义时返回)
  static let builtinCommonPhrases: [String] = [
    "好的",
    "收到",
    "谢谢",
    "正在忙，稍后回复",
    "好的，我知道了",
    "没问题",
    "辛苦了",
    "请稍等",
    "我看一下再回复你",
    "好的，谢谢",
  ]

  /// 常用语列表。未设置过时返回内置列表; 设置过后返回保存的值
  /// (即使删空也返回保存的空数组, 不会重置回内置)。
  /// App 设置页可通过此属性增删; 键盘内长按可删除单条。
  var commonPhrases: [String] {
    get {
      if object(forKey: Self.commonPhrasesKey) != nil {
        return array(forKey: Self.commonPhrasesKey) as? [String] ?? []
      }
      return Self.builtinCommonPhrases
    }
    set { set(newValue, forKey: Self.commonPhrasesKey) }
  }
}

extension UserDefaults {
  // MARK: - 1.0 版本

  private static let _appFirstLaunchForV1 = "app.launch.isFirst"
  // 是否显示按键气泡
  private static let _showKeyPressBubble = "view.keyboard.showKeyPressBubble"
  // 是否开启键盘声音
  private static let _enableKeyboardFeedbackSound = "app.keyboard.feedback.sound"
  // 是否开启键盘震动
  private static let _enableKeyboardFeedbackHaptic = "app.keyboard.feedback.haptic"
  // 是否显示键盘收起按键
  private static let _showKeyboardDismissButton = "app.keyboard.showDismissButton"
  // 是否显示分号键
  private static let _showSemicolonButton = "app.keyboard.showSemicolonButton"
  // 是否显示空格左边按键
  private static let _showSpaceLeftButton = "app.keyboard.showSpaceLeftButton"
  // 空格左边按键键值
  private static let _spaceLeftButtonValue = "app.keyboard.spaceLeftButtonValue"
  // 是否显示空格右边按键
  private static let _showSpaceRightButton = "app.keyboard.showSpaceRightButton"
  // 空格右边按键键值
  private static let _spaceRightButtonValue = "app.keyboard.spaceRightButtonValue"
  // 是否显示空格右边中英文切换键
  private static let _showSpaceRightSwitchLanguageButton = "app.keyboard.showSpaceRightSwitchLanguageButton"
  // 中英切换按键位于空格是否位于左侧
  private static let _switchLanguageButtonInSpaceLeft = "app.keyboard.switchLanguageButtonInSpaceLeft"
  // rime 候选字最大数量
  private static let _rimeMaxCandidateSize = "rime.maxCandidateSize"
  // rime 候选字Title字体大小
  private static let _rimeCandidateTitleFontSize = "rime.candidateTitleFontSize"
  private static let _rimeCandidateCommentFontSize = "rime.candidateCommentFontSize"
  // 候选栏高度
  private static let _candidateBarHeight = "app.keyboard.candidateBarHeight"
  // 是否开启划动手势
  private static let _enableKeyboardSwipeGestureSymbol = "keyboard.enableSwipeGestureSymbol"
  // 划动输入符号
  private static let _keyboardSwipeGestureSymbol = "keyboard.swipeGestureSymbol"
  // 简繁切换的值
  private static let _rimeSimplifiedAndTraditionalSwitcherKey = "rime.rimeSimplifiedAndTraditionalSwitcherKey"
  // 嵌入模式
  private static let _enableInputEmbeddedMode = "keyboard.enableInputEmbeddedMode"
  // Shift是否锁定
  private static let _enableKeyboardAutomaticallyLowercase = "keyboard.enableKeyboardAutomaticallyLowercase"

  // MARK: - 2.0 版本

  public static let isFirstRunningOfKey = "com.ihsiao.apps.Hamster.UserDefaults.isFirstRunning"
  private static let overrideRimeDirectoryOfKey = "com.ihsiao.apps.Hamster.UserDefaults.overrideRimeDirectory"
  private static let schemasForKey = "com.ihsiao.apps.Hamster.UserDefault.keys.schemas"
  private static let selectSchemasForKey = "com.ihsiao.apps.Hamster.UserDefault.keys.selectSchemas"
  private static let currentSchemaForKey = "com.ihsiao.apps.Hamster.UserDefault.keys.currentSchema"
  private static let latestSchemaForKey = "com.ihsiao.apps.Hamster.UserDefault.keys.latestSchemaForKey"
  private static let hotKeys = "com.ihsiao.apps.Hamster.UserDefault.keys.hotKeys"

  // MARK: - 剪贴板同步 (ClipboardSync)

  private static let clipboardSyncEnabledKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncEnabled"
  private static let clipboardSyncServerURLKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncServerURL"
  private static let clipboardSyncUsernameKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncUsername"
  private static let clipboardSyncPasswordKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncPassword"
  private static let clipboardSyncLastHashKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncLastHash"
  private static let clipboardSyncLastStatusTextKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardSyncLastStatusText"
  private static let chinesePrimaryKeyboardIsNineGridKey = "com.ihsiao.apps.Hamster.UserDefault.keys.chinesePrimaryKeyboardIsNineGrid"
  private static let toolbarVisibleToolsKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarVisibleTools"
  private static let toolbarToolsOrderKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarToolsOrder"

  // MARK: - 剪贴板历史 / 常用语

  private static let clipboardHistoryKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardHistory"
  private static let clipboardHistoryMaxCount = 20
  private static let commonPhrasesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.commonPhrases"

  // MARK: - 补丁

  public static let patch_2_65 = "com.ihsiao.apps.Hamster.patchState.2.0.0-65"
}
