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

  /// 模糊音开关 (默认开): 开启后, 拼音输入时 zh/z、ch/c、sh/s、n/l、
  /// h/f、an/ang、en/eng、in/ing 可互相混输 (福建用户常见混淆)。
  /// 未设置过 (老用户首次升级) 视为开, 与默认值一致。
  var fuzzyPinyinEnabled: Bool {
    get {
      if object(forKey: Self.fuzzyPinyinEnabledKey) != nil {
        return bool(forKey: Self.fuzzyPinyinEnabledKey)
      }
      return true
    }
    set {
      set(newValue, forKey: Self.fuzzyPinyinEnabledKey)
      Logger.statistics.debug("save fuzzyPinyinEnabled: \(newValue)")
    }
  }

  /// 每布局词库绑定 (第 10 轮第 7 条): App 设置 -> 键盘布局里给
  /// 26 键 (rime_ice) / 9 键 (t9) 各选一个词库, 存的是 patch 值
  /// (用户数据目录下的相对路径去 ".dict.yaml", 如 "rime_ice"、
  /// "cn_dicts/base"), 不是 dict 文件里的 name: 字段。
  /// 没设过就是默认 "rime_ice" (雾凇拼音大词库)。
  var layoutDictionaryRimeIce: String {
    get {
      string(forKey: Self.layoutDictionaryRimeIceKey) ?? LayoutDictionary.defaultDictionaryId
    }
    set {
      set(newValue, forKey: Self.layoutDictionaryRimeIceKey)
      Logger.statistics.debug("save layoutDictionaryRimeIce: \(newValue)")
    }
  }

  var layoutDictionaryT9: String {
    get {
      string(forKey: Self.layoutDictionaryT9Key) ?? LayoutDictionary.defaultDictionaryId
    }
    set {
      set(newValue, forKey: Self.layoutDictionaryT9Key)
      Logger.statistics.debug("save layoutDictionaryT9: \(newValue)")
    }
  }

  /// 上次部署时生效的词库绑定 (nil = 这功能上线前就部署过,
  /// 部署时按现状算, 不删 prism)。
  var deployedLayoutDictionaryRimeIce: String? {
    get {
      string(forKey: Self.deployedLayoutDictionaryRimeIceKey)
    }
    set {
      set(newValue, forKey: Self.deployedLayoutDictionaryRimeIceKey)
    }
  }

  var deployedLayoutDictionaryT9: String? {
    get {
      string(forKey: Self.deployedLayoutDictionaryT9Key)
    }
    set {
      set(newValue, forKey: Self.deployedLayoutDictionaryT9Key)
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

  /// 内置剪贴板同步服务器 (用户家里的 SyncClipboard 服务器, 局域网地址,
  /// 仅在家里 WiFi 下可达; 公司电脑在别的网络上够不着它)。
  /// 仅作为"无已存值时"的默认值: 读不到已存值 (或已存值为空) 时返回这里;
  /// 一旦用户在设置页改过 (非空), 永远读改过的值, 启动时绝不覆盖, 改密码不会被重置。
  /// 注意: 仓库与 Release 是公开的, 这三项会随源码/IPA 公开, 任何人下载都能看到;
  /// 用户本人知情并接受 (2026-11-24 "公开也无所谓了")。
  /// 历史: 2026-11-22 起默认值是 BWG 服务器 https://95-181-188-70.sslip.io:8444,
  /// 2026-11-24 用户改走局域网同步、BWG 服务器已拆除, 默认值随之改成本地值;
  /// 已存了旧 BWG 地址的设备由 migrateClipboardSyncServerFromBWGToLAN() 一次性迁移。
  private static let defaultClipboardSyncServerURL = "http://192.168.50.29:5033"
  private static let defaultClipboardSyncUsername = "yunhuan"
  private static let defaultClipboardSyncPassword = "qwe130308"

  /// 旧的 BWG 同步服务器地址 (第 14 轮第 7 项迁移用): 2026-11-24 用户改
  /// 走局域网同步, BWG 服务器已拆除。仅用于判断“存着的还是旧地址”。
  private static let legacyClipboardSyncServerURL = "https://95-181-188-70.sslip.io:8444"

  /// 一次性迁移 (第 14 轮第 7 项): 存着的服务器地址恰好是旧 BWG 地址时,
  /// 把地址、用户名、密码三个存值都换成本地局域网值; 存的是别的地址
  /// (用户自己改过) 时一律不动; 从未存过值时也不动 (getter 已返回新默认值)。
  /// 幂等: 迁完后存值不再是旧 BWG 地址, 再调也不会重复触发。
  /// 调用点: 每次同步主流程开头 (App 与键盘都走这里) + App 启动时,
  /// 保证设置页在同步跑起来之前就显示本地值。
  public func migrateClipboardSyncServerFromBWGToLAN() {
    guard let stored = string(forKey: Self.clipboardSyncServerURLKey) else { return }
    let normalizedStored = stored.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard normalizedStored == Self.legacyClipboardSyncServerURL else { return }
    clipboardSyncServerURL = Self.defaultClipboardSyncServerURL
    clipboardSyncUsername = Self.defaultClipboardSyncUsername
    clipboardSyncPassword = Self.defaultClipboardSyncPassword
    Logger.statistics.info("clipboard sync server migrated from BWG to LAN defaults")
  }

  /// 是否启用剪贴板同步 (默认关闭)
  var clipboardSyncEnabled: Bool {
    get { bool(forKey: Self.clipboardSyncEnabledKey) }
    set { set(newValue, forKey: Self.clipboardSyncEnabledKey) }
  }

  /// 剪贴板同步服务器地址, 如 https://example.com:8444 (留空表示未配置)
  /// 未配过时返回内置默认值 (见上)。
  var clipboardSyncServerURL: String {
    get {
      if let stored = string(forKey: Self.clipboardSyncServerURLKey), !stored.isEmpty { return stored }
      return Self.defaultClipboardSyncServerURL
    }
    set { set(newValue, forKey: Self.clipboardSyncServerURLKey) }
  }

  /// 剪贴板同步用户名 (可空, 留空则不做 Basic Auth)
  /// 未配过时返回内置默认值 (见上)。
  var clipboardSyncUsername: String {
    get {
      if let stored = string(forKey: Self.clipboardSyncUsernameKey), !stored.isEmpty { return stored }
      return Self.defaultClipboardSyncUsername
    }
    set { set(newValue, forKey: Self.clipboardSyncUsernameKey) }
  }

  /// 剪贴板同步密码 (可空)
  /// 注意: 与仓内其他配置一样保存在 App Group UserDefaults 中, 未使用 Keychain。
  /// 未配过时返回内置默认值 (见上)。
  var clipboardSyncPassword: String {
    get {
      if let stored = string(forKey: Self.clipboardSyncPasswordKey), !stored.isEmpty { return stored }
      return Self.defaultClipboardSyncPassword
    }
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

  // MARK: - 粘贴提示已忽略内容 (点 X / 粘贴 / 隐藏键盘)

  /// 点 X / 粘贴 / 隐藏键盘时忽略过的粘贴提示内容 SHA-256 (完整剪贴板文本的哈希)。
  /// 之前只存在内存里, 键盘重建 (隐藏再打开) 就丢了, 同一条内容永远重推。
  /// 改为持久化在共享 UserDefaults 里, 最多保留 20 条。
  var clipboardChipDismissedHashes: [String] {
    get { array(forKey: Self.clipboardChipDismissedHashesKey) as? [String] ?? [] }
    set { set(Array(newValue.prefix(Self.clipboardChipDismissedMaxCount)), forKey: Self.clipboardChipDismissedHashesKey) }
  }

  /// 记录忽略时的 UIPasteboard.changeCount。忽略只在剪贴板未变化时生效:
  /// 剪贴板一换内容 (changeCount 移动) 忽略记录即失效, 新内容仍会正常提示;
  /// 重新复制同一内容 (changeCount 也移动) 同样会再次提示。
  var clipboardChipDismissedChangeCount: Int {
    get { integer(forKey: Self.clipboardChipDismissedChangeCountKey) }
    set { set(newValue, forKey: Self.clipboardChipDismissedChangeCountKey) }
  }

  /// 忽略一条粘贴提示内容 (hash 为完整剪贴板文本的 SHA-256)。
  func markClipboardChipDismissed(hash: String, changeCount: Int) {
    guard !hash.isEmpty else { return }
    var hashes = clipboardChipDismissedHashes.filter { $0 != hash }
    hashes.append(hash)
    clipboardChipDismissedHashes = hashes
    clipboardChipDismissedChangeCount = changeCount
  }

  /// 该内容当前是否处于忽略状态: 哈希在忽略列表里, 且剪贴板自忽略后没换过内容。
  func isClipboardChipDismissed(hash: String, changeCount: Int) -> Bool {
    guard !hash.isEmpty, changeCount == clipboardChipDismissedChangeCount else { return false }
    return clipboardChipDismissedHashes.contains(hash)
  }

  // MARK: - 剪贴板读取门 (第 17 轮第 7 项: 修"每次打开键盘都弹粘贴横幅")

  /// 上次 (自动) 读取剪贴板时的 UIPasteboard.changeCount, 持久化在共享 defaults。
  /// 根因: 同步服务与粘贴提示之前都只把 changeCount 记在内存里, 键盘扩展进程
  /// 每次弹出都可能重建, 内存记录一丢, 每次打开都以为"剪贴板变了"而重读,
  /// iOS 便每次都在顶部弹"粘贴自 xxx"横幅。持久化后只有内容真的变了才读一次,
  /// 横幅最多随一次真正的新复制出现一次, 再也不会在每次打开键盘时出现。
  /// -1 表示从未读过。
  var clipboardLastSeenChangeCount: Int {
    get {
      // 未存过返回 -1 (不是 integer(forKey:) 默认的 0: changeCount 本身
      // 从 0 起计, 0 是合法值, 不能拿它当"从未读过")。
      guard object(forKey: Self.clipboardLastSeenChangeCountKey) != nil else { return -1 }
      return integer(forKey: Self.clipboardLastSeenChangeCountKey)
    }
    set { set(newValue, forKey: Self.clipboardLastSeenChangeCountKey) }
  }

  /// 与上次 changeCount 对应的剪贴板文本原文 (读剪贴板时一并存下)。
  /// changeCount 未变时, 各处 (粘贴提示、粘贴键、常用语粘贴按钮、剪贴板面板)
  /// 直接用这份缓存展示 / 粘贴, 不读 UIPasteboard、不弹横幅。
  /// 超长文本不存 (见 clipboardLastSeenTextTruncated), 避免共享 defaults 被撑爆。
  var clipboardLastSeenText: String? {
    get { string(forKey: Self.clipboardLastSeenTextKey) }
    set {
      if let newValue {
        set(newValue, forKey: Self.clipboardLastSeenTextKey)
      } else {
        removeObject(forKey: Self.clipboardLastSeenTextKey)
      }
    }
  }

  /// 上次 changeCount 对应的剪贴板文本是否因超长而未缓存。
  /// 为真时缓存为空不代表"剪贴板为空", 调用方 (cachedPasteboardText)
  /// 应直接读一次剪贴板 (横幅一次, 极少见), 而不是当成空剪贴板。
  var clipboardLastSeenTextTruncated: Bool {
    get { bool(forKey: Self.clipboardLastSeenTextTruncatedKey) }
    set { set(newValue, forKey: Self.clipboardLastSeenTextTruncatedKey) }
  }

  // MARK: - 临时复制图标折叠态 (第 17 轮反馈修: 打字后折叠的图标不再消失)

  /// 打字时折进临时复制图标的那条剪贴板文本 (持久化)。
  /// 用户一打字, 粘贴提示行就折成图标; 之后输入清空、键盘重建,
  /// 图标都还在, 提示行不再把同一条内容重新推出来; 直到点开图标、
  /// 粘贴、忽略, 或剪贴板换了新内容, 折叠态才清掉。
  var tempCopyFoldedText: String? {
    get { string(forKey: Self.tempCopyFoldedTextKey) }
    set {
      if let newValue {
        set(newValue, forKey: Self.tempCopyFoldedTextKey)
      } else {
        removeObject(forKey: Self.tempCopyFoldedTextKey)
      }
    }
  }

  /// 折叠时对应的 UIPasteboard.changeCount: 剪贴板一换内容折叠态即失效。
  /// -1 表示没有折叠态。
  var tempCopyFoldedChangeCount: Int {
    get {
      guard object(forKey: Self.tempCopyFoldedChangeCountKey) != nil else { return -1 }
      return integer(forKey: Self.tempCopyFoldedChangeCountKey)
    }
    set { set(newValue, forKey: Self.tempCopyFoldedChangeCountKey) }
  }

  /// 剪贴板文本缓存的字符数上限 (超长不存, 只记 truncated 标记)。
  static let clipboardLastSeenTextMaxLength = 262_144

  /// 更新"上次读到的剪贴板"记录 (count + 文本缓存): 读到文本时调;
  /// 剪贴板里是图片 / 空内容时传 nil (缓存清空, 计数值照常更新)。
  /// 文本超长时只记 count 与 truncated 标记, 不存文本。
  func recordLastSeenPasteboard(changeCount: Int, text: String?) {
    clipboardLastSeenChangeCount = changeCount
    if let text, text.count <= Self.clipboardLastSeenTextMaxLength {
      clipboardLastSeenText = text
      clipboardLastSeenTextTruncated = false
    } else {
      clipboardLastSeenText = nil
      clipboardLastSeenTextTruncated = text != nil
    }
  }

  // MARK: - 置顶候选 (第 14 轮第 5 项 c)

  /// 一条置顶记录: code 是原始输入键 (九宫格数字串 / 全键盘字母串, 与
  /// userdb 的学习键一致), text 是候选文字。列表按最近置顶在前。
  /// 置顶只在显示层生效 (syncContext 里把列表里有的候选挪到前面),
  /// 不动 userdb、不写学习, 所以重装/换设备后置顶还在 (UserDefaults
  /// 在 App Group 里), 忘掉 (b) 时同 (code, text) 的置顶一并清除。
  public struct PinnedCandidate: Codable, Equatable {
    public var code: String
    public var text: String
  }

  /// 置顶候选列表, 最多保留 50 条 (最近置顶在前)。
  public var pinnedCandidates: [PinnedCandidate] {
    get {
      if let data = data(forKey: Self.pinnedCandidatesKey),
         let array = try? JSONDecoder().decode([PinnedCandidate].self, from: data) {
        return array
      }
      return []
    }
    set {
      if let data = try? JSONEncoder().encode(Array(newValue.prefix(Self.pinnedCandidatesMaxCount))) {
        set(data, forKey: Self.pinnedCandidatesKey)
      }
    }
  }

  /// 置顶 (code, text): 已在列表里的移到最前, 否则插到最前。
  public func pinCandidate(code: String, text: String) {
    guard !code.isEmpty, !text.isEmpty else { return }
    var list = pinnedCandidates.filter { !($0.code == code && $0.text == text) }
    list.insert(PinnedCandidate(code: code, text: text), at: 0)
    pinnedCandidates = list
  }

  /// 取消置顶 (code, text)。
  public func unpinCandidate(code: String, text: String) {
    pinnedCandidates = pinnedCandidates.filter { !($0.code == code && $0.text == text) }
  }

  /// (code, text) 是否已置顶。
  public func isCandidatePinned(code: String, text: String) -> Bool {
    pinnedCandidates.contains { $0.code == code && $0.text == text }
  }

  // MARK: - 联想词学习对子 (第 15 轮第 2 项 a)

  /// 一条学到的联想: 上一段提交 prev 之后, 用户接着提交了 next (count 次)。
  /// 只记中文 (两段都是 >=2 字的中文, 见 AssociationStore.recordLearnedPair
  /// 的 guard), 最多保留 50 条; 展示时只取 count >= 2 的 (同一接续打过
  /// 两次才算信号, 一次可能是两句不相干的话恰好连着打)。
  public struct LearnedAssociation: Codable, Equatable {
    public var prev: String
    public var next: String
    public var count: Int
  }

  /// 学到的联想对子列表, 最多保留 50 条 (最近记的在前)。
  public var learnedAssociations: [LearnedAssociation] {
    get {
      if let data = data(forKey: Self.learnedAssociationsKey),
         let array = try? JSONDecoder().decode([LearnedAssociation].self, from: data) {
        return array
      }
      return []
    }
    set {
      if let data = try? JSONEncoder().encode(Array(newValue.prefix(Self.learnedAssociationsMaxCount))) {
        set(data, forKey: Self.learnedAssociationsKey)
      }
    }
  }

  /// 记一次 (prev -> next): 已有就 count+1 并移到最前, 否则插到最前。
  public func recordLearnedAssociation(previous prev: String, next: String) {
    guard !prev.isEmpty, !next.isEmpty, prev != next else { return }
    let count = (learnedAssociations.first { $0.prev == prev && $0.next == next }?.count ?? 0) + 1
    var list = learnedAssociations.filter { !($0.prev == prev && $0.next == next) }
    list.insert(LearnedAssociation(prev: prev, next: next, count: count), at: 0)
    learnedAssociations = list
  }

  // MARK: - 英文纠错忽略词 (第 15 轮第 2 项 b)

  /// 用户点“忽略”的英文纠错词: provider 不再为它出纠错候选。
  /// 与 UITextChecker.learnWord (系统级生词) 不同, 这是本键盘自己的忽略表。
  public var ignoredEnglishWords: [String] {
    get { stringArray(forKey: Self.ignoredEnglishWordsKey) ?? [] }
    set { set(newValue, forKey: Self.ignoredEnglishWordsKey) }
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

  /// 工具栏工具顺序: 在工具栏上的工具 id 按显示顺序排列 (不在顺序里的工具
  /// 在定制面板的工具池里, 点按加入)。未设置过时默认 ["clipboard", "phrases"]。
  /// 这个顺序是工具栏成员的唯一事实来源 (ITEM 2 修复):
  /// 工具在不在栏上只看它在不在这个顺序里, 不再另由 toolbarVisibleTools
  /// 集合决定——两个键必须时刻一致, 一旦其中一个丢了/旧了, 被拿掉的工具
  /// 就会借另一个键复活。拿掉 = 从这个顺序里删掉 (单键写盘),
  /// 加回 = 显式点按加入 / 池子拖入 / 点"恢复默认" (见 resetToolbarToolsOrder)。
  /// 左侧菜单按钮本身不可隐藏 (它是打开菜单/恢复显示的入口), 不在列表里。
  /// 收起键盘 (⌄) 不在列表里: 第 7 轮起它是钉死在工具栏最右的固定按钮,
  /// 不再是可定制工具 (用户: 放菜单/定制里毫无意义); 已存顺序里的
  /// "dismiss" 会被下面的 toolbarToolAllIDs 过滤掉, 自动清理。
  var toolbarToolsOrder: [String] {
    get {
      if let array = array(forKey: Self.toolbarToolsOrderKey) as? [String] {
        // 只过滤未知 id, 不再补齐漏掉的已知工具: 工具栏上有哪些工具
        // 完全由这个顺序决定, 不在顺序里的工具在定制面板的工具池里
        // (第 6 轮改成微信式自由拖动后, 新工具默认进池、不自动上栏;
        // 以前自动补齐会把新工具强行塞进用户工具栏)。
        return array.filter { Self.toolbarToolAllIDs.contains($0) }
      }
      return Self.toolbarToolDefaultOrder
    }
    set {
      // 同上: 只存调用方给的顺序, 不自动补齐。
      set(newValue.filter { Self.toolbarToolAllIDs.contains($0) }, forKey: Self.toolbarToolsOrderKey)
    }
  }

  /// 工具栏默认顺序: 剪贴板、常用语 (收起键盘是固定按钮, 不在顺序里)。
  static let toolbarToolDefaultOrder: [String] = ["clipboard", "phrases"]

  /// 工具栏工具可见性 (旧模型遗留的镜像集合, 仅作兼容保留):
  /// 存放"显示"的工具 id 集合。未设置过时全部显示。
  /// 注意 (ITEM 2 修复): 渲染与池子绿底不再读这个集合——成员唯一看
  /// toolbarToolsOrder (见 isToolbarToolVisible)。旧模型下被拿掉的工具
  /// 仍留在顺序里、只靠这个集合藏起来, 一旦这个键丢了/没写盘,
  /// 它的 getter 就回落到"全部显示", 藏着的工具会自己回到工具栏上;
  /// 新模型下拿掉即从顺序里删掉, 这个集合只是同步写一份、永不作为
  /// 渲染依据, 丢了也不影响。调用方仍可通过 setToolbarToolVisible
  /// 读写它, 但是否显示以顺序为准。
  /// 工具 id: "clipboard"(剪贴板)、"phrases"(常用语)。
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

  /// 全部工具栏工具 id (与 KeyboardToolbarView.toolbarToolDefinitions() 一一对应):
  /// 剪贴板、常用语、切换26键/九宫格、立即同步剪贴板、设置、常用语管理 (共 6 个)。
  /// "定制工具栏"本身是入口, 不上工具栏; "收起键盘"是固定按钮, 不上工具栏
  /// (第 7 轮移出可定制工具; 已存数据里的 "dismiss" 由读写两端的
  /// toolbarToolAllIDs 过滤自动清理)。
  static let toolbarToolAllIDs: [String] = [
    "clipboard", "phrases", "switchLayout",
    "syncNow", "settings", "managePhrases",
  ]

  /// 用户亲手加到工具栏上的工具 id 集合 (第 10 轮)。
  /// 菜单格子是否上色 (绿) 只看这个集合, 不看 toolbarToolsOrder:
  /// 旧逻辑把"在栏上"当成了"用户加上去的", 所以默认工具
  /// (剪贴板/常用语) 从没开过定制也是绿的。默认工具不算亲手加,
  /// 只有在定制面板点池子加入 (或把池子里的贴纸拖到工具栏上) 才记进来;
  /// 工具栏长按拖动换位/换侧不算 (第 12 轮: 旧规则把拖动也算亲手加,
  /// 拖一下默认工具就被误记进来, 菜单里一直绿着)。
  /// 未设置过时为空集: 从没开过定制 → 菜单里一个绿格子都没有。
  /// 注意: 老用户以前在定制里加过的工具, 升级后不会自动进这个集合
  /// (旧数据里分不出来); 绿格子会在他下次亲手加工具时重新出现。
  var toolbarUserAddedToolIDs: Set<String> {
    get {
      if let array = array(forKey: Self.toolbarUserAddedToolIDsKey) as? [String] {
        return Set(array.filter { Self.toolbarToolAllIDs.contains($0) })
      }
      return []
    }
    set { set(Array(newValue), forKey: Self.toolbarUserAddedToolIDsKey) }
  }

  /// 把某个工具记为用户亲手加上去的 (定制面板点池子加入 /
  /// 把池子里的贴纸拖到工具栏上时调用; 工具栏长按拖动换位不算,
  /// 见第 12 轮)。
  func markToolbarToolUserAdded(_ toolID: String) {
    guard Self.toolbarToolAllIDs.contains(toolID) else { return }
    var ids = toolbarUserAddedToolIDs
    ids.insert(toolID)
    toolbarUserAddedToolIDs = ids
  }

  /// 把某个工具从"亲手加上去"里拿掉 (⊖ 从工具栏拿掉时调用,
  /// 否则删掉的工具再加回来之前一直留在集合里)。
  func unmarkToolbarToolUserAdded(_ toolID: String) {
    var ids = toolbarUserAddedToolIDs
    ids.remove(toolID)
    toolbarUserAddedToolIDs = ids
  }

  /// 某个工具栏工具是否显示: 只看它在不在 toolbarToolsOrder 里
  /// (ITEM 2 修复: 顺序是成员的唯一事实来源; 不再读 toolbarVisibleTools
  /// 集合——那个集合未设置过时默认"全部显示", 会把已拿掉的工具复活)。
  func isToolbarToolVisible(_ toolID: String) -> Bool {
    toolbarToolsOrder.contains(toolID)
  }

  /// 设置某个工具栏工具是否显示 (只同步写旧模型的镜像集合,
  /// 见 toolbarVisibleTools; 是否显示以 toolbarToolsOrder 为准,
  /// 调用方加/拿工具时须同时改顺序, 见 KeyboardToolbarView 的
  /// onAddTool / removeToolbarToolFromBar)。
  func setToolbarToolVisible(_ toolID: String, visible: Bool) {
    var tools = toolbarVisibleTools
    if visible {
      tools.insert(toolID)
    } else {
      tools.remove(toolID)
    }
    toolbarVisibleTools = tools
  }

  // MARK: - 工具栏工具左右摆放 (第 9 轮)

  /// 工具栏工具所在侧: 只有左/右两档 (没有中)。
  /// 第 5 轮的左/中/右三分区被第 6 轮换掉, 是因为那版定制面板只是个
  /// 只能排序的下拉列表、用户说"完全没用", 不是他不要左右摆放;
  /// 现在他明确要左右放, 这次做对: 每工具一侧属性 + 可视化拖动。
  /// 与旧的 toolbarToolZones 键无关 (那键留着, 不删已存数据, 也不再读)。
  public enum ToolbarToolSide: String, Codable {
    case left, right
  }

  /// 各工具所在侧 (toolID -> left/right)。未设置过时全部默认右
  /// (2026-11-26 用户要求: 所有工具默认排在工具栏右侧)。
  var toolbarToolSides: [String: ToolbarToolSide] {
    get {
      if let dict = dictionary(forKey: Self.toolbarToolSidesKey) as? [String: String] {
        var sides: [String: ToolbarToolSide] = [:]
        for id in Self.toolbarToolAllIDs {
          sides[id] = dict[id].flatMap(ToolbarToolSide.init(rawValue:)) ?? .right
        }
        return sides
      }
      return Dictionary(uniqueKeysWithValues: Self.toolbarToolAllIDs.map { ($0, ToolbarToolSide.right) })
    }
    set {
      set(newValue.mapValues { $0.rawValue }, forKey: Self.toolbarToolSidesKey)
    }
  }

  /// 某个工具所在侧 (未设置过默认右)。
  func toolbarToolSide(for toolID: String) -> ToolbarToolSide {
    toolbarToolSides[toolID] ?? .right
  }

  /// 设置某个工具所在侧 (写盘)。
  func setToolbarToolSide(_ toolID: String, side: ToolbarToolSide) {
    var sides = toolbarToolSides
    sides[toolID] = side
    toolbarToolSides = sides
  }

  /// 一次保存整栏布局 (拖动换侧 / 定制面板拖拽后调用):
  /// 左组 id + 右组 id 按组内顺序拼成 toolbarToolsOrder,
  /// 两侧属性同步写盘。调用方不用再分开写顺序和侧。
  /// 注意 (ITEM 2 修复): 只存栏上这两个组, 不再把"顺序里有、栈里没有"
  /// 的工具跟在最后 (旧逻辑 "藏起来的工具不丢")——顺序是成员的唯一
  /// 事实来源, 跟在最后的藏起来的工具就是还没删干净的已拿掉工具,
  /// 下次重建/迁移会把它当成栏上工具复活。不在栈里的工具一律回工具池,
  /// 只能由显式点按加入 / 池子拖入 / "恢复默认" 加回来。
  func saveToolbarLayout(leftIDs: [String], rightIDs: [String]) {
    // 只存栏上的工具: 不在栈里的不写进顺序 (见上面注释)。
    toolbarToolsOrder = leftIDs + rightIDs
    var sides = toolbarToolSides
    for id in leftIDs { sides[id] = .left }
    for id in rightIDs { sides[id] = .right }
    toolbarToolSides = sides
  }

  /// 移动工具栏工具顺序 (拖拽排序后调用): from/to 为全部工具顺序中的下标。
  func moveToolbarTool(from source: Int, to destination: Int) {
    var order = toolbarToolsOrder
    guard order.indices.contains(source), order.indices.contains(destination), source != destination else { return }
    let tool = order.remove(at: source)
    order.insert(tool, at: destination)
    toolbarToolsOrder = order
  }

  /// 恢复默认顺序并全部显示 (工具栏工具恢复默认; 菜单格子开关
  /// 第 10 轮已删, 5 个格子永远全显, 这里不再管菜单格子)。
  /// 默认两工具 (剪贴板/常用语) 不是亲手加的, 亲手加的集合也清空。
  /// 注意 (ITEM 2 修复): 这是唯一能把已拿掉的工具加回来的非显式加入
  /// 路径——重建 / 迁移 / 拖动保存一律不复活已拿掉的工具。
  func resetToolbarToolsOrder() {
    toolbarToolsOrder = Self.toolbarToolDefaultOrder
    toolbarVisibleTools = Set(Self.toolbarToolDefaultOrder)
    toolbarUserAddedToolIDs = []
    // 左右摆放也恢复默认 (全部回右侧)。
    removeObject(forKey: Self.toolbarToolSidesKey)
    // 分区也恢复默认 (剪贴板左、常用语左)。
    removeObject(forKey: Self.toolbarToolZonesKey)
  }

  /// 一次性迁移 (ITEM 2 修复: 旧模型残留 -> 顺序唯一事实来源):
  /// 旧模型下被拿掉的工具仍留在 toolbarToolsOrder 里、只靠
  /// toolbarVisibleTools 集合藏起来; 渲染改成只看顺序后, 这些残留
  /// 会直接回到工具栏上, 所以先按已存的可见集合把顺序里藏着的工具
  /// 一次性清掉 (清掉 = 回工具池, 点按可再加回来, 不是删除数据)。
  /// 只有可见集合键真实存在时才清: 从未设置过表示用户从没定制过,
  /// 默认全部显示, 没有什么可清的。跑过一次后写 flag, 不重复跑。
  /// 注意: 显式 public——调用方在 HamsterKeyboardKit 模块 (跨模块)。
  public func migrateToolbarOrderPruneHiddenIfNeeded() {
    guard object(forKey: Self.toolbarOrderHiddenPrunedMigrationKey) == nil else { return }
    set(true, forKey: Self.toolbarOrderHiddenPrunedMigrationKey)
    guard object(forKey: Self.toolbarVisibleToolsKey) != nil else { return }
    let visible = toolbarVisibleTools
    toolbarToolsOrder = toolbarToolsOrder.filter { visible.contains($0) }
  }

  /// 一次性迁移 (第 6 轮, 分区模型 -> 自由拖动模型): 把现有的分区顺序
  /// 展平成一个总顺序 (左组 -> 中组 -> 右组), 组内保持 toolbarToolsOrder
  /// 的相对顺序, 不丢用户现有的排列。分区键本身留着 (不删已存数据),
  /// 只是以后不再用。跑过一次后写 flag, 不重复跑。
  /// 注意: 显式 public——调用方在 HamsterKeyboardKit 模块 (跨模块,
  /// build #23 就是死在跨模块 internal 上)。
  public func migrateToolbarToolsOrderFromZonesIfNeeded() {
    guard object(forKey: Self.toolbarOrderFreeMigrationKey) == nil else { return }
    set(true, forKey: Self.toolbarOrderFreeMigrationKey)
    let raw = (array(forKey: Self.toolbarToolsOrderKey) as? [String]) ?? Self.toolbarToolDefaultOrder
    let zones = toolbarToolZones
    func rank(_ id: String) -> Int {
      switch zones[id] ?? Self.toolbarToolDefaultZone[id] ?? .left {
      case .left: return 0
      case .center: return 1
      case .right: return 2
      }
    }
    // sorted(by:) 是稳定排序, 只按分区排, 组内相对顺序原样保留。
    toolbarToolsOrder = raw.sorted { rank($0) < rank($1) }
  }

  /// 一次性迁移 (第 12 轮): 把两个默认工具 (剪贴板/常用语) 从"亲手加上去"
  /// 的集合里清掉。它们是默认就在栏上的, 从没通过定制加上去; 旧规则把
  /// "工具栏长按拖动摆放过"也算亲手加, 拖动过的默认工具被误记进来, 菜单里
  /// 一直绿着 (build #33 反馈)。第 12 轮起拖动不再记, 这次迁移把误记的
  /// 两个默认 ID 清掉; 以后用户在池子里点按添加 (或把贴纸拖到栏上) 会
  /// 重新标记。跑过一次后写 flag, 不重复跑。
  public func migrateToolbarUserAddedDefaultsIfNeeded() {
    guard object(forKey: Self.toolbarUserAddedDefaultsMigrationKey) == nil else { return }
    set(true, forKey: Self.toolbarUserAddedDefaultsMigrationKey)
    var ids = toolbarUserAddedToolIDs
    ids.remove("clipboard")
    ids.remove("phrases")
    toolbarUserAddedToolIDs = ids
  }

  // MARK: - 工具栏工具位置分区 (左/中/右)

  /// 工具栏工具所在分区。工具栏分左、中、右三组排布, 每组内按
  /// toolbarToolsOrder 的相对顺序紧凑排列 (组内间距 12pt, 不均分);
  /// 左侧菜单按钮 (格子图标) 不参与分区, 永远在最左。
  public enum ToolbarToolZone: String, Codable, CaseIterable {
    case left, center, right

    public var title: String {
      switch self {
      case .left: return "左"
      case .center: return "中"
      case .right: return "右"
      }
    }
  }

  /// 工具默认分区: 全部右
  /// (2026-11-26 用户要求: 所有工具默认排在工具栏右侧)。
  static let toolbarToolDefaultZone: [String: ToolbarToolZone] = [
    "clipboard": .right, "phrases": .right, "switchLayout": .right,
    "syncNow": .right, "settings": .right, "managePhrases": .right,
  ]

  /// 各工具的分区 (toolID -> 分区)。未设置过时全部归右区
  /// (2026-11-26 用户要求: 所有工具默认排在工具栏右侧)。
  /// 一旦用户在定制面板里改过任一工具的分区, 即写盘, 此后以保存值为准。
  var toolbarToolZones: [String: ToolbarToolZone] {
    get {
      if let dict = dictionary(forKey: Self.toolbarToolZonesKey) as? [String: String] {
        var zones: [String: ToolbarToolZone] = [:]
        for id in Self.toolbarToolAllIDs {
          zones[id] = dict[id].flatMap(ToolbarToolZone.init(rawValue:))
            ?? Self.toolbarToolDefaultZone[id] ?? .right
        }
        return zones
      }
      var zones: [String: ToolbarToolZone] = [:]
      let order = toolbarToolsOrder
      for id in order {
        zones[id] = .right
      }
      for id in Self.toolbarToolAllIDs where zones[id] == nil {
        zones[id] = Self.toolbarToolDefaultZone[id] ?? .left
      }
      return zones
    }
    set {
      set(newValue.mapValues { $0.rawValue }, forKey: Self.toolbarToolZonesKey)
    }
  }

  /// 某个工具的分区 (未设置过按上面规则推导)。
  func toolbarToolZone(for toolID: String) -> ToolbarToolZone {
    toolbarToolZones[toolID] ?? Self.toolbarToolDefaultZone[toolID] ?? .left
  }

  /// 设置某个工具的分区 (写盘, 此后以保存值为准)。
  func setToolbarToolZone(_ toolID: String, zone: ToolbarToolZone) {
    var zones = toolbarToolZones
    zones[toolID] = zone
    toolbarToolZones = zones
  }

  // MARK: - 菜单宫格格子显隐 (工具面板) —— 第 10 轮已删
  //
  // "菜单格子"开关整段删掉: 7 个菜单格子永远全部显示, 不再逐个控制显隐。
  // 旧的访问器 (menuTileAllIDs / menuVisibleTiles / isMenuTileVisible /
  // setMenuTileVisible) 已删除。已存数据的键
  // "com.ihsiao.apps.Hamster.UserDefault.keys.menuVisibleTiles" 本身留着,
  // 不删除用户设备上的旧数据, 只是不再读取。

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

  /// 2026-11-24 (B2) 之前内置的 10 条默认常用语, 已全部下线,
  /// 不再作为默认值返回。仅供 migrateCommonPhrasesRemoveBuiltinsIfNeeded()
  /// 用: 已存列表里若混有这些句子就整句删掉 (精确匹配), 用户自己
  /// 加的短语一律保留。
  static let legacyBuiltinCommonPhrases: [String] = [
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

  /// 一次性迁移 (2026-11-24 B2): 用户说“默认常用语全部删掉, 我不需要”。
  /// 已存常用语里若混有旧内置 10 条就整句删掉 (精确匹配, 只删这 10 条);
  /// 用户自己加的短语 (如邮箱/手机号/你好) 一律保留; 从未存过值时
  /// getter 已返回空, 无事可做。幂等: 标记 key 保证只跑一次,
  /// 跑完后列表里不再有旧内置句子, 再调也不会重复触发。
  /// 注意: 显式 public——调用方在 HamsterKeyboardKit 模块与主 App
  /// (跨模块, build #23 就是死在跨模块 internal 上)。
  /// 调用点: App 启动时 + 键盘工具栏初始化时 (与 toolbar 迁移同处)。
  public func migrateCommonPhrasesRemoveBuiltinsIfNeeded() {
    guard object(forKey: Self.commonPhrasesBuiltinsRemovedMigrationKey) == nil else { return }
    set(true, forKey: Self.commonPhrasesBuiltinsRemovedMigrationKey)
    guard object(forKey: Self.commonPhrasesKey) != nil else { return }
    var phrases = array(forKey: Self.commonPhrasesKey) as? [String] ?? []
    let beforeCount = phrases.count
    phrases.removeAll { Self.legacyBuiltinCommonPhrases.contains($0) }
    guard phrases.count != beforeCount else { return }
    set(phrases, forKey: Self.commonPhrasesKey)
    Logger.statistics.info("common phrases migrated: removed \(beforeCount - phrases.count) builtin defaults, kept \(phrases.count) user phrases")
  }

  /// 常用语列表。未设置过时返回空 (2026-11-24 B2: 默认常用语全部
  /// 下线, 不再内置任何句子); 设置过后返回保存的值
  /// (即使删空也返回保存的空数组, 不会重置回内置)。
  /// App 设置页可通过此属性增删; 键盘内长按可删除单条。
  var commonPhrases: [String] {
    get {
      if object(forKey: Self.commonPhrasesKey) != nil {
        return array(forKey: Self.commonPhrasesKey) as? [String] ?? []
      }
      return []
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
  private static let fuzzyPinyinEnabledKey = "com.ihsiao.apps.Hamster.UserDefault.keys.fuzzyPinyinEnabled"
  private static let layoutDictionaryRimeIceKey = "com.ihsiao.apps.Hamster.UserDefault.keys.layoutDictionaryRimeIce"
  private static let layoutDictionaryT9Key = "com.ihsiao.apps.Hamster.UserDefault.keys.layoutDictionaryT9"
  private static let deployedLayoutDictionaryRimeIceKey = "com.ihsiao.apps.Hamster.UserDefault.keys.deployedLayoutDictionaryRimeIce"
  private static let deployedLayoutDictionaryT9Key = "com.ihsiao.apps.Hamster.UserDefault.keys.deployedLayoutDictionaryT9"
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
  private static let clipboardChipDismissedHashesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardChipDismissedHashes"
  private static let clipboardChipDismissedChangeCountKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardChipDismissedChangeCount"
  private static let clipboardLastSeenChangeCountKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardLastSeenChangeCount"
  private static let clipboardLastSeenTextKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardLastSeenText"
  private static let clipboardLastSeenTextTruncatedKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardLastSeenTextTruncated"
  private static let tempCopyFoldedTextKey = "com.ihsiao.apps.Hamster.UserDefault.keys.tempCopyFoldedText"
  private static let tempCopyFoldedChangeCountKey = "com.ihsiao.apps.Hamster.UserDefault.keys.tempCopyFoldedChangeCount"
  private static let pinnedCandidatesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.pinnedCandidates"
  private static let pinnedCandidatesMaxCount = 50
  private static let learnedAssociationsKey = "com.ihsiao.apps.Hamster.UserDefault.keys.learnedAssociations"
  private static let learnedAssociationsMaxCount = 50
  private static let ignoredEnglishWordsKey = "com.ihsiao.apps.Hamster.UserDefault.keys.ignoredEnglishWords"
  private static let clipboardChipDismissedMaxCount = 20
  private static let chinesePrimaryKeyboardIsNineGridKey = "com.ihsiao.apps.Hamster.UserDefault.keys.chinesePrimaryKeyboardIsNineGrid"
  private static let toolbarVisibleToolsKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarVisibleTools"
  private static let toolbarToolsOrderKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarToolsOrder"
  private static let toolbarToolZonesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarToolZones"
  private static let toolbarOrderFreeMigrationKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarOrderMigratedToFreeOrder"
  private static let toolbarToolSidesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarToolSides"
  private static let toolbarUserAddedToolIDsKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarUserAddedToolIDs"
  private static let toolbarUserAddedDefaultsMigrationKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarUserAddedDefaultsMigrated"
  private static let toolbarOrderHiddenPrunedMigrationKey = "com.ihsiao.apps.Hamster.UserDefault.keys.toolbarOrderHiddenPruned"

  // MARK: - 剪贴板历史 / 常用语

  private static let clipboardHistoryKey = "com.ihsiao.apps.Hamster.UserDefault.keys.clipboardHistory"
  private static let clipboardHistoryMaxCount = 20
  private static let commonPhrasesKey = "com.ihsiao.apps.Hamster.UserDefault.keys.commonPhrases"
  private static let commonPhrasesBuiltinsRemovedMigrationKey = "com.ihsiao.apps.Hamster.UserDefault.keys.commonPhrasesBuiltinsRemoved"

  // MARK: - 补丁

  public static let patch_2_65 = "com.ihsiao.apps.Hamster.patchState.2.0.0-65"
}
