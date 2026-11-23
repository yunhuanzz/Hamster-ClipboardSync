//
//  SettingViewModel.swift
//  Hamster
//
//  Created by morse on 2023/6/13.
//

import Combine
import HamsterKeyboardKit
import HamsterKit
import OSLog
import ProgressHUD
import UIKit

public class SettingsViewModel: ObservableObject {
  private var cancelable = Set<AnyCancellable>()
  private unowned let mainViewModel: MainViewModel
  private let rimeViewModel: RimeViewModel
  private let backupViewModel: BackupViewModel

  init(mainViewModel: MainViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.mainViewModel = mainViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel
  }

  public var enableColorSchema: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.enableColorSchema ?? false
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.enableColorSchema = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.keyboard?.enableColorSchema = newValue
    }
  }

  public var enableAppleCloud: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.general?.enableAppleCloud ?? false
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.general?.enableAppleCloud = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.general?.enableAppleCloud = newValue
    }
  }

  // MARK: - 剪贴板同步 (ClipboardSync)

  /// 是否启用剪贴板同步
  public var clipboardSyncEnabled: Bool {
    get { UserDefaults.hamster.clipboardSyncEnabled }
    set { UserDefaults.hamster.clipboardSyncEnabled = newValue }
  }

  /// 剪贴板同步服务器地址
  public var clipboardSyncServerURL: String {
    get { UserDefaults.hamster.clipboardSyncServerURL }
    set { UserDefaults.hamster.clipboardSyncServerURL = newValue }
  }

  /// 剪贴板同步用户名
  public var clipboardSyncUsername: String {
    get { UserDefaults.hamster.clipboardSyncUsername }
    set { UserDefaults.hamster.clipboardSyncUsername = newValue }
  }

  /// 剪贴板同步密码
  public var clipboardSyncPassword: String {
    get { UserDefaults.hamster.clipboardSyncPassword }
    set { UserDefaults.hamster.clipboardSyncPassword = newValue }
  }

  var tableReloadSubject = PassthroughSubject<Bool, Never>()
  var tableReloadPublished: AnyPublisher<Bool, Never> {
    tableReloadSubject.eraseToAnyPublisher()
  }

  func reloadFavoriteButton() {
    let favoriteButtonSettings = getFavoriteButtons(buttons: UserDefaults.standard.getFavoriteButtons())
    guard !favoriteButtonSettings.isEmpty else { return }

    let sectionsContainerFavoriteButtons = sections[0].items[0].type == .button
    if sectionsContainerFavoriteButtons {
      sections[0].items = favoriteButtonSettings
    } else {
      sections = [SettingSectionModel(items: favoriteButtonSettings)] + sections
    }
  }

  func getFavoriteButtons(buttons: [FavoriteButton]) -> [SettingItemModel] {
    // 检测是否有收藏按钮，如果有则添加到初始化数据 settingsViewModel.sections 中
    // 注意：后续的动态变化将在 combine() 方法中，通过观测 UserDefaults.favoriteButtonSubject 值完成
    guard !buttons.isEmpty else { return [] }
    return buttons
      .compactMap {
        switch $0 {
        case .rimeDeploy: return SettingItemModel(
            text: "重新部署",
            type: .button,
            buttonAction: { [weak self] in
              guard let self = self else { return }
              await rimeViewModel.rimeDeploy()
              tableReloadSubject.send(true)
            },
            favoriteButton: .rimeDeploy
          )
        case .rimeSync: return SettingItemModel(
            text: "RIME同步",
            type: .button,
            buttonAction: { [weak self] in
              guard let self = self else { return }
              await rimeViewModel.rimeSync()
            },
            favoriteButton: .rimeSync
          )
        case .appBackup: return SettingItemModel(
            text: "应用备份",
            type: .button,
            buttonAction: { [weak self] in
              guard let self = self else { return }
              await backupViewModel.backup()
            },
            favoriteButton: .rimeSync
          )
        }
      }
  }

  /// 设置选项
  /// 剪贴板同步设置 (跨设备粘贴传送子页用; 也是 sections 里"剪贴板同步"那一节
  /// 的唯一来源, 两边共用同一批 item, 数据不重复、不漂移)。
  /// 搬到子页的原因: 设置首页改成卡片宫格后不再 inline 展示这一节,
  /// 点卡片"跨设备粘贴传送"进子页改。同步 URL/账号/密码原样保留, 不迁移。
  public lazy var clipboardSyncSettings: [SettingSectionModel] = [
    SettingSectionModel(
      title: "剪贴板同步",
      footer: "键盘每次弹出时同步一次: 上传本机剪贴板, 再下载服务器最新内容。需在系统设置中为仓输入法开启「允许完全访问」, 否则无法读取剪贴板与联网。注意: iOS 14 起每次读取剪贴板都会在屏幕顶部弹出提示横幅, 这是系统行为。",
      items: [
        .init(
          icon: UIImage(systemName: "doc.on.clipboard")!,
          text: "启用剪贴板同步",
          type: .toggle,
          toggleValue: { [unowned self] in clipboardSyncEnabled },
          toggleHandled: { [unowned self] in
            clipboardSyncEnabled = $0
          }
        ),
        .init(
          icon: UIImage(systemName: "server.rack")!,
          placeholder: "服务器地址, 如 https://example.com:8444",
          type: .textField,
          textValue: { [unowned self] in clipboardSyncServerURL },
          textHandled: { [unowned self] in
            clipboardSyncServerURL = $0
          }
        ),
        .init(
          icon: UIImage(systemName: "person")!,
          placeholder: "用户名 (可空)",
          type: .textField,
          textValue: { [unowned self] in clipboardSyncUsername },
          textHandled: { [unowned self] in
            clipboardSyncUsername = $0
          }
        ),
        .init(
          icon: UIImage(systemName: "lock")!,
          placeholder: "密码 (可空)",
          type: .textField,
          textValue: { [unowned self] in clipboardSyncPassword },
          textHandled: { [unowned self] in
            clipboardSyncPassword = $0
          }
        ),
        .init(
          icon: UIImage(systemName: "info.circle")!,
          text: "上次同步",
          navigationLinkLabel: { UserDefaults.hamster.clipboardSyncLastStatusText ?? "尚未同步" }
        ),
        .init(
          text: "立即同步",
          type: .button,
          buttonAction: {
            ClipboardSyncService.shared.syncNow()
            // 同步完成后子页收到通知会刷新状态行
          }
        ),
      ]
    ),
  ]

  /// 卡片宫格首页导航入口 (mainViewModel 是 private, 首页通过这里跳转子页)。
  func navigate(to subView: SettingsSubView) {
    mainViewModel.subViewSubject.send(subView)
  }

  public lazy var sections: [SettingSectionModel] = {
    let sections = [
      SettingSectionModel(title: "输入相关", items: [
        .init(
          icon: UIImage(systemName: "highlighter")!.withTintColor(.yellow),
          text: "输入方案设置",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.inputSchema)
          }
        ),
        .init(
          icon: UIImage(systemName: "wifi")!,
          text: "Wi-Fi上传方案",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.uploadInputSchema)
          }
        ),
        .init(
          icon: UIImage(systemName: "folder")!,
          text: "文件管理",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.finder)
          }
        ),
        .init(
          icon: UIImage(systemName: "text.quote")!,
          text: "常用语",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.commonPhrases)
          }
        ),
        .init(
          icon: UIImage(systemName: "book")!,
          text: "我的词组",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.customPhrases)
          }
        ),
      ]),
      SettingSectionModel(title: "键盘相关", items: [
        .init(
          icon: UIImage(systemName: "keyboard")!,
          text: "键盘设置",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.keyboardSettings)
          }
        ),
        .init(
          icon: UIImage(systemName: "paintpalette")!,
          text: "键盘配色",
          accessoryType: .disclosureIndicator,
          navigationLinkLabel: { [unowned self] in enableColorSchema ? "启用" : "禁用" },
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.colorSchema)
          }
        ),
        .init(
          icon: UIImage(systemName: "speaker.wave.3")!,
          text: "按键音与震动",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.feedback)
          }
        ),
      ]),
      SettingSectionModel(title: "同步与备份", items: [
        .init(
          icon: UIImage(systemName: "externaldrive.badge.icloud")!,
          text: "iCloud同步",
          accessoryType: .disclosureIndicator,
          navigationLinkLabel: { [unowned self] in enableAppleCloud ? "启用" : "禁用" },
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.iCloud)
          }
        ),
        .init(
          icon: UIImage(systemName: "externaldrive.badge.timemachine")!,
          text: "软件备份",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.backup)
          }
        ),
      ]),
      clipboardSyncSettings[0],
      .init(title: "RIME", items: [
        .init(
          icon: UIImage(systemName: "r.square")!,
          text: "RIME",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.rime)
          }
        ),
      ]),
      .init(title: "关于", items: [
        .init(
          icon: UIImage(systemName: "info.circle")!,
          text: "关于",
          accessoryType: .disclosureIndicator,
          navigationAction: { [unowned self] in
            self.mainViewModel.subViewSubject.send(.about)
          }
        ),
      ]),
    ]
    return sections
  }()
}

extension SettingsViewModel {
  /// 启动加载数据
  func loadAppData() async throws {
    // PATCH: 仓1.0版本处理
    if let v1FirstRunning = UserDefaults.hamster._firstRunningForV1, v1FirstRunning == false {
      await ProgressHUD.animate("迁移 1.0 配置中……", interaction: false)

      var appConfig = HamsterAppDependencyContainer.shared.applicationConfiguration

      // 读取 1.0 配置参数
      _setupConfigurationForV1Update(configuration: &appConfig)

      // merge 1.0 配置参数
      var configuration = HamsterAppDependencyContainer.shared.configuration
      configuration = try configuration.merge(with: appConfig, uniquingKeysWith: { _, appConfig in appConfig })

      // 部署 RIME
      try rimeViewModel.rimeContext.deployment(configuration: &configuration)

      // 修改应用首次运行标志
      UserDefaults.standard.isFirstRunning = false

      /// 删除 V1 标识
      UserDefaults.hamster._removeFirstRunningForV1()

      HamsterAppDependencyContainer.shared.configuration = configuration
      HamsterAppDependencyContainer.shared.applicationConfiguration = appConfig

      await ProgressHUD.success("迁移完成", interaction: false, delay: 1.5)
      return
    }

    // 判断应用是否首次运行
    guard UserDefaults.standard.isFirstRunning else { return }

    // 判断是否首次运行
    await ProgressHUD.animate("初次启动，需要编译输入方案，请耐心等待……", interaction: false)

    // 首次启动始化输入方案目录
    do {
      try FileManager.initSandboxUserDataDirectory(override: true, unzip: true)
      try FileManager.initSandboxBackupDirectory(override: true)
    } catch {
      Logger.statistics.error("rime init file directory error: \(error.localizedDescription)")
      throw error
    }

    var configuration = HamsterAppDependencyContainer.shared.configuration

    // 部署 RIME
    try rimeViewModel.rimeContext.deployment(configuration: &configuration)

    // TODO: 内置雾凇方案，将默认选择方案改为雾凇拼音
    let rimeSchema = RimeSchema(schemaId: "rime_ice", schemaName: "雾凇拼音")
    rimeViewModel.rimeContext.selectSchemas = [rimeSchema]
    rimeViewModel.rimeContext.currentSchema = rimeSchema

    // 修改应用首次运行标志
    UserDefaults.standard.isFirstRunning = false

    HamsterAppDependencyContainer.shared.configuration = configuration

    await ProgressHUD.success("部署完成", interaction: false, delay: 1.5)
  }

  /// 仓1.0迁移配置参数
  private func _setupConfigurationForV1Update(configuration: inout HamsterConfiguration) {
    if let _showKeyPressBubble = UserDefaults.hamster._showKeyPressBubble {
      configuration.keyboard?.displayButtonBubbles = _showKeyPressBubble
    }

    if let _enableKeyboardFeedbackSound = UserDefaults.hamster._enableKeyboardFeedbackSound {
      configuration.keyboard?.enableKeySounds = _enableKeyboardFeedbackSound
    }

    if let _enableKeyboardFeedbackHaptic = UserDefaults.hamster._enableKeyboardFeedbackHaptic {
      configuration.keyboard?.enableHapticFeedback = _enableKeyboardFeedbackHaptic
    }

    if let _showKeyboardDismissButton = UserDefaults.hamster._showKeyboardDismissButton {
      configuration.toolbar?.displayKeyboardDismissButton = _showKeyboardDismissButton
    }

    if let _showSemicolonButton = UserDefaults.hamster._showSemicolonButton {
      configuration.keyboard?.displaySemicolonButton = _showSemicolonButton
    }

    if let _showSpaceLeftButton = UserDefaults.hamster._showSpaceLeftButton {
      configuration.keyboard?.displaySpaceLeftButton = _showSpaceLeftButton
    }

    if let _spaceLeftButtonValue = UserDefaults.hamster._spaceLeftButtonValue {
      configuration.keyboard?.keyValueOfSpaceLeftButton = _spaceLeftButtonValue
    }

    if let _showSpaceRightButton = UserDefaults.hamster._showSpaceRightButton {
      configuration.keyboard?.displaySpaceRightButton = _showSpaceRightButton
    }

    if let _spaceRightButtonValue = UserDefaults.hamster._spaceRightButtonValue {
      configuration.keyboard?.keyValueOfSpaceRightButton = _spaceRightButtonValue
    }

    if let _showSpaceRightSwitchLanguageButton = UserDefaults.hamster._showSpaceRightSwitchLanguageButton {
      configuration.keyboard?.displayChineseEnglishSwitchButton = _showSpaceRightSwitchLanguageButton
    }

    if let _switchLanguageButtonInSpaceLeft = UserDefaults.hamster._switchLanguageButtonInSpaceLeft {
      configuration.keyboard?.chineseEnglishSwitchButtonIsOnLeftOfSpaceButton = _switchLanguageButtonInSpaceLeft
    }

    if let _rimeMaxCandidateSize = UserDefaults.hamster._rimeMaxCandidateSize {
      configuration.rime?.maximumNumberOfCandidateWords = _rimeMaxCandidateSize
    }

    if let _rimeCandidateTitleFontSize = UserDefaults.hamster._rimeCandidateTitleFontSize {
      configuration.toolbar?.candidateWordFontSize = _rimeCandidateTitleFontSize
    }

    if let _rimeCandidateCommentFontSize = UserDefaults.hamster._rimeCandidateCommentFontSize {
      configuration.toolbar?.candidateCommentFontSize = _rimeCandidateCommentFontSize
    }

    if let _candidateBarHeight = UserDefaults.hamster._candidateBarHeight {
      configuration.toolbar?.heightOfToolbar = _candidateBarHeight
    }

    if let _rimeSimplifiedAndTraditionalSwitcherKey = UserDefaults.hamster._rimeSimplifiedAndTraditionalSwitcherKey {
      configuration.rime?.keyValueOfSwitchSimplifiedAndTraditional = _rimeSimplifiedAndTraditionalSwitcherKey
    }

    if let _enableInputEmbeddedMode = UserDefaults.hamster._enableInputEmbeddedMode {
      configuration.keyboard?.enableEmbeddedInputMode = _enableInputEmbeddedMode
    }

    if let _enableKeyboardAutomaticallyLowercase = UserDefaults.hamster._enableKeyboardAutomaticallyLowercase {
      configuration.keyboard?.lockShiftState = !_enableKeyboardAutomaticallyLowercase
    }

    if let _rimeSimplifiedAndTraditionalSwitcherKey = UserDefaults.hamster._rimeSimplifiedAndTraditionalSwitcherKey {
      configuration.rime?.keyValueOfSwitchSimplifiedAndTraditional = _rimeSimplifiedAndTraditionalSwitcherKey
    }

    if let _keyboardSwipeGestureSymbol = UserDefaults.hamster._keyboardSwipeGestureSymbol {
      let translateShortCommand = { (name: String) -> ShortcutCommand? in
        if name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
          return ShortcutCommand(rawValue: name)
        }
        return nil
      }

      var keySwipeMap = [KeyboardAction: [KeySwipe]]()
      for (fullKey, fullValue) in _keyboardSwipeGestureSymbol {
        let value = fullValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }

        var key = fullKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(key.removeLast())
        let action: KeyboardAction = .character(key.lowercased())

        var direction: KeySwipe.Direction
        switch suffix {
        case Self._SlideUp:
          direction = .up
        case Self._SlideDown:
          direction = .down
        case Self._SlideLeft:
          direction = .left
        case Self._SlideRight:
          direction = .right
        default: continue
        }

        var keySwipe: KeySwipe
        if let command = translateShortCommand(value) {
          keySwipe = KeySwipe(direction: direction, action: .shortCommand(command), label: .empty)
        } else {
          keySwipe = KeySwipe(direction: direction, action: .character(value), label: .empty)
        }

        if var value = keySwipeMap[action] {
          value.append(keySwipe)
          keySwipeMap[action] = value
        } else {
          keySwipeMap[action] = [keySwipe]
        }
      }

      let keys = keySwipeMap.map { key, value in Key(action: key, swipe: value) }
      if let index = configuration.swipe?.keyboardSwipe?.firstIndex(where: { $0.keyboardType?.isChinese ?? false }) {
        configuration.swipe?.keyboardSwipe?[index] = KeyboardSwipe(keyboardType: .chinese(.lowercased), keys: keys)
      } else {
        configuration.swipe?.keyboardSwipe?.append(KeyboardSwipe(keyboardType: .chinese(.lowercased), keys: keys))
      }
    }
  }
}

extension SettingsViewModel {
  static let _SlideUp = "↑" // 表示上滑 Upwards Arrow: https://www.compart.com/en/unicode/U+2191
  static let _SlideDown = "↓" // 表示下滑 Downwards Arrow: https://www.compart.com/en/unicode/U+2193
  static let _SlideLeft = "←" // 表示左滑 Leftwards Arrow: https://www.compart.com/en/unicode/U+2190
  static let _SlideRight = "→" // 表示右滑 Rightwards Arrow: https://www.compart.com/en/unicode/U+2192
}
