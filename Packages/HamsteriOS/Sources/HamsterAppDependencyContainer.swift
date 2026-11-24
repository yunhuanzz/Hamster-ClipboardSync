//
//  HamsterAppDependencyContainer.swift
//
//
//  Created by morse on 2023/7/5.
//

import Foundation
import HamsterKeyboardKit
import HamsterKit
import OSLog
import UIKit

/// Hamster 应用依赖注入容器
/// 通过此容器，为对象注入依赖
open class HamsterAppDependencyContainer {
  /// 单例
  public static let shared = HamsterAppDependencyContainer()

  // MARK: Long-lived 依赖属性

  public let rimeContext: RimeContext
  public let mainViewModel: MainViewModel

  public lazy var settingsViewModel: SettingsViewModel = {
    let vm = SettingsViewModel(
      mainViewModel: mainViewModel,
      rimeViewModel: rimeViewModel,
      backupViewModel: backupViewModel
    )
    return vm
  }()

  public lazy var rimeViewModel: RimeViewModel = {
    let vm = RimeViewModel(rimeContext: rimeContext)
    return vm
  }()

  public lazy var backupViewModel: BackupViewModel = {
    let vm = BackupViewModel(fileBrowserViewModel: makeFileBrowserViewModel(rootURL: FileManager.sandboxBackupDirectory))
    return vm
  }()

  public lazy var inputSchemaViewModel: InputSchemaViewModel = {
    let vm = InputSchemaViewModel(rimeContext: rimeContext)
    return vm
  }()

  public lazy var keyboardSettingsViewModel: KeyboardSettingsViewModel = {
    let vm = KeyboardSettingsViewModel()
    return vm
  }()

  /// 应用配置
  public var configuration: HamsterConfiguration {
    didSet {
      Task {
        do {
          Logger.statistics.debug("hamster configuration didSet")
          try HamsterConfigurationRepositories.shared.saveToUserDefaults(configuration)
          // try HamsterConfigurationRepositories.shared.saveToYAML(config: configuration, path: FileManager.hamsterConfigFileOnBuild)
//          try HamsterConfigurationRepositories.shared.saveToJSON(
//            config: configuration,
//            path: FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.json")
//          )
          try HamsterConfigurationRepositories.shared.saveToPropertyList(
            config: configuration,
            path: FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.plist")
          )
        } catch {
          Logger.statistics.error("hamster configuration didSet error: \(error.localizedDescription)")
        }
      }
    }
  }

  /// 在 app 内设置的的配置项
  /// 用于在重新部署时，覆盖 hamster.custom.yaml 配置
  /// 配置优先级：应用UI操作配置（存储在 UserDefaults 中） > Rime/hamster.custom.yaml > Rime/hamster.yaml > 默认配置(SharedSupport/hamster.yaml)
  public var applicationConfiguration: HamsterConfiguration = {
    if let config = try? HamsterConfigurationRepositories.shared.loadAppConfigurationFromUserDefaults() {
      return config
    }
    return HamsterConfiguration(
      general: GeneralConfiguration(),
      toolbar: KeyboardToolbarConfiguration(),
      keyboard: KeyboardConfiguration(),
      rime: RimeConfiguration(),
      swipe: KeyboardSwipeConfiguration(),
      keyboards: nil
    )
  }() {
    didSet {
      do {
        try HamsterConfigurationRepositories.shared.saveAppConfigurationToUserDefaults(applicationConfiguration)
      } catch {
        Logger.statistics.error("hamster app configuration set error: \(error.localizedDescription)")
      }
    }
  }

  // 应用默认配置（计算属性）
  // 注意：此配置用于还原系统默认配置
  public var defaultConfiguration: HamsterConfiguration? {
    do {
      return try HamsterConfigurationRepositories.shared.loadFromUserDefaultsOnDefault()
    } catch {
      Logger.statistics.error("loadFromUserDefaultsOnDefault() error: \(error)")
      return nil
    }
  }

  private init() {
    // (第 14 轮第 7 项) App 启动先跑一次性迁移: 存着旧 BWG 同步地址的
    // 设备换成本地局域网值, 保证设置页在同步跑起来之前就显示本地值。
    // 幂等, 存的不是旧 BWG 地址时什么都不做。
    UserDefaults.hamster.migrateClipboardSyncServerFromBWGToLAN()

    // (2026-11-24 B2) App 启动先跑一次性迁移: 已存常用语里混有的
    // 旧内置 10 条默认短语删掉, 用户自己加的短语保留; 幂等。
    UserDefaults.hamster.migrateCommonPhrasesRemoveBuiltinsIfNeeded()

    // 创建 long-lived 属性
    self.rimeContext = RimeContext()
    self.mainViewModel = MainViewModel()

    // 判断应用是否首次运行
    // 注意: 首次运行标志（UserDefaults.standard.isFirstRunning）在 SettingsViewModel 的 loadAppData() 方法内重置
    if UserDefaults.standard.isFirstRunning {
      do {
        // 首次运行解压 zip 文件（包含应用内置输入方案及配置文件）
        try FileManager.initSandboxSharedSupportDirectory(override: true)

        // 读取 SharedSupport/hamster.yaml, 生成默认应用配置
        let hamsterConfiguration = try HamsterConfigurationRepositories.shared.loadFromYAML(FileManager.hamsterConfigFileOnSandboxSharedSupport)

        // 作为应用的默认配置，可从默认值中恢复
        try HamsterConfigurationRepositories.shared.saveToUserDefaultsOnDefault(hamsterConfiguration)

        self.configuration = hamsterConfiguration

      } catch {
        self.configuration = HamsterConfiguration()
        Logger.statistics.error("init SharedSupport error: \(error.localizedDescription)")
      }
      return
    }

    // 非首次启动从 UserDefault 文件中加载
    do {
      self.configuration = try HamsterConfigurationRepositories.shared.loadFromUserDefaults()

      // PATCH
      if !FileManager.default.fileExists(atPath: FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.plist").path) {
        try HamsterConfigurationRepositories.shared.saveToPropertyList(
          config: configuration,
          path: FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.plist")
        )
      }
    } catch {
      Logger.statistics.error("load configuration from UserDefault error: \(error.localizedDescription)")
      // 如果从 UserDefaults 加载失败，则尝试从配置文件中加载一次
      if let hamsterConfiguration = try? HamsterConfigurationRepositories.shared.loadFromYAML(FileManager.hamsterConfigFileOnSandboxSharedSupport) {
        self.configuration = hamsterConfiguration
      } else {
        self.configuration = HamsterConfiguration()
      }
    }

    // 一次性迁移 (第 5 轮): 把已装配置里的 rime.overrideDictFiles 强制改成 false
    // (见 migrateUserDictProtection; 首次运行分支已提前 return, 到不了这里)。
    migrateUserDictProtection()
  }

  /// 一次性迁移 (第 5 轮): 已装配置里的 rime.overrideDictFiles 还是旧默认值
  /// true, 而内置 hamster.yaml 早已改成 false; App 只在首次运行读一次 YAML,
  /// 之后都从 UserDefaults 加载, 所以 YAML 的修正永远到不了已装的配置,
  /// 导致每次部署都清空用户词典学习成果。这里强制改成 false 并显式持久化
  /// (init 内赋值不触发 didSet, 所以必须手动保存)。
  /// 改完一次后下次启动看到的已是 false, 不再重复写; 用户仍可在 RIME 页
  /// 开关里自己改回去——部署时 userdb 已无条件保留 (见 RimeContext),
  /// 那个开关现在只影响用户导入的 .txt 词库文件。
  private func migrateUserDictProtection() {
    if configuration.rime?.overrideDictFiles != false {
      if configuration.rime == nil {
        configuration.rime = RimeConfiguration(overrideDictFiles: false)
      } else {
        configuration.rime?.overrideDictFiles = false
      }
      do {
        try HamsterConfigurationRepositories.shared.saveToUserDefaults(configuration)
      } catch {
        Logger.statistics.error("migrateUserDictProtection save configuration error: \(error.localizedDescription)")
      }
    }
    if applicationConfiguration.rime?.overrideDictFiles != false {
      if applicationConfiguration.rime == nil {
        applicationConfiguration.rime = RimeConfiguration(overrideDictFiles: false)
      } else {
        applicationConfiguration.rime?.overrideDictFiles = false
      }
      do {
        try HamsterConfigurationRepositories.shared.saveAppConfigurationToUserDefaults(applicationConfiguration)
      } catch {
        Logger.statistics.error("migrateUserDictProtection save applicationConfiguration error: \(error.localizedDescription)")
      }
    }
  }

  /// 重置应用配置
  public func resetAppConfiguration() {
    HamsterConfigurationRepositories.shared.resetAppConfiguration()
    HamsterAppDependencyContainer.shared.applicationConfiguration = HamsterConfiguration(
      general: GeneralConfiguration(),
      toolbar: KeyboardToolbarConfiguration(),
      keyboard: KeyboardConfiguration(),
      rime: RimeConfiguration(),
      swipe: KeyboardSwipeConfiguration(),
      keyboards: nil
    )

    // 删除 UserDefaults 中的 UI 操作配置
    if let configuration = try? HamsterConfigurationRepositories.shared.loadConfiguration() {
      HamsterAppDependencyContainer.shared.configuration = configuration
    }
  }

  /// 重置应用配置
  public func resetHamsterConfiguration() {
    HamsterConfigurationRepositories.shared.resetConfiguration()
  }
}

extension HamsterAppDependencyContainer {
  func makeZipDocumentPickerViewController() -> UIDocumentPickerViewController {
    let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])
    if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
      vc.directoryURL = iCloudURL
    } else {
      vc.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    return vc
  }
}

extension HamsterAppDependencyContainer: UploadInputSchemaViewModelFactory {
  func makeUploadInputSchemaViewModel() -> UploadInputSchemaViewModel {
    return UploadInputSchemaViewModel()
  }
}

extension HamsterAppDependencyContainer: FinderViewModelFactory {
  func makeFinderViewModel() -> FinderViewModel {
    return FinderViewModel()
  }
}

extension HamsterAppDependencyContainer: KeyboardSettingsSubViewControllerFactory {
  func makeNumberNineGridSettingsViewController() -> NumberNineGridSettingsViewController {
    NumberNineGridSettingsViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeSymbolSettingsViewController() -> SymbolSettingsViewController {
    SymbolSettingsViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeSymbolKeyboardSettingsViewController() -> SymbolKeyboardSettingsViewController {
    SymbolKeyboardSettingsViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeToolbarSettingsViewController() -> ToolbarSettingsViewController {
    ToolbarSettingsViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeKeyboardLayoutViewController() -> KeyboardLayoutViewController {
    KeyboardLayoutViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeSpaceSettingsViewController() -> SpaceSettingsViewController {
    SpaceSettingsViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }
}

extension HamsterAppDependencyContainer: KeyboardColorViewModelFactory {
  func makeKeyboardColorViewModel() -> KeyboardColorViewModel {
    KeyboardColorViewModel()
  }
}

extension HamsterAppDependencyContainer: KeyboardFeedbackViewModelFactory {
  func makeKeyboardFeedbackViewModel() -> KeyboardFeedbackViewModel {
    KeyboardFeedbackViewModel()
  }
}

extension HamsterAppDependencyContainer: FileBrowserViewModelFactory {
  func makeFileBrowserViewModel(rootURL: URL) -> FileBrowserViewModel {
    let fileBrowserViewModel = FileBrowserViewModel(rootURL: rootURL)
    return fileBrowserViewModel
  }
}

extension HamsterAppDependencyContainer: AppleCloudViewModelFactory {
  func makeAppleCloudViewModel() -> AppleCloudViewModel {
    return AppleCloudViewModel(settingsViewModel: settingsViewModel)
  }
}

extension HamsterAppDependencyContainer: AboutViewModelFactory {
  func makeAboutViewModel() -> AboutViewModel {
    return AboutViewModel()
  }
}

extension HamsterAppDependencyContainer: OpenSourceViewControllerFactory {
  func makeOpenSourceViewController() -> OpenSourceViewController {
    return OpenSourceViewController(openSourceViewModelFactory: self)
  }
}

extension HamsterAppDependencyContainer: OpenSourceViewModelFactory {
  func makeOpenSourceViewModel() -> OpenSourceViewModel {
    return OpenSourceViewModel()
  }
}

extension HamsterAppDependencyContainer: SubViewControllerFactory {
  public func makeRootController() -> MainViewController {
    let navigationController = MainViewController(mainViewModel: mainViewModel, subViewControllerFactory: self)
    return navigationController
  }

  public func makeSettingsViewController() -> SettingsViewController {
    let settingViewController = SettingsViewController(settingsViewModel: settingsViewModel, rimeViewModel: rimeViewModel, backupViewModel: backupViewModel)
    return settingViewController
  }

  func makeInputSchemaViewController() -> InputSchemaViewController {
    let inputSchemaViewController = InputSchemaViewController(
      inputSchemaViewModel: inputSchemaViewModel,
      documentPickerViewController: makeZipDocumentPickerViewController()
    )
    return inputSchemaViewController
  }

  func makeUploadInputSchemaViewController() -> UploadInputSchemaViewController {
    let uploadInputSchemaViewController = UploadInputSchemaViewController(
      uploadInputSchemaViewModelFactory: self
    )
    return uploadInputSchemaViewController
  }

  func makeFinderViewController() -> FinderViewController {
    let finderViewController = FinderViewController(finderViewModelFactory: self, fileBrowserViewModelFactory: self)
    return finderViewController
  }

  func makeKeyboardSettingsViewController() -> KeyboardSettingsViewController {
    let keyboardSettingsViewController = KeyboardSettingsViewController(
      keyboardSettingsViewModel: keyboardSettingsViewModel,
      keyboardSettingsSubViewControllerFactory: self
    )
    return keyboardSettingsViewController
  }

  func makeKeyboardColorViewController() -> KeyboardColorViewController {
    KeyboardColorViewController(keyboardColorViewModelFactory: self)
  }

  func makeKeyboardFeedbackViewController() -> KeyboardFeedbackViewController {
    KeyboardFeedbackViewController(keyboardFeedbackViewModelFactory: self)
  }

  func makeAppleCloudViewController() -> AppleCloudViewController {
    let iCloudViewController = AppleCloudViewController(appleCloudViewModelFactory: self)
    return iCloudViewController
  }

  func makeRimeViewController() -> RimeViewController {
    let rimeViewController = RimeViewController(rimeViewModel: rimeViewModel)
    return rimeViewController
  }

  func makeBackupViewController() -> BackupViewController {
    let backupViewController = BackupViewController(backupViewModel: backupViewModel)
    return backupViewController
  }

  func makeAboutViewController() -> AboutViewController {
    let aboutViewController = AboutViewController(
      aboutViewModelFactory: self,
      openSourceViewControllerFactory: self
    )
    return aboutViewController
  }

  func makeCommonPhrasesViewController() -> CommonPhrasesViewController {
    CommonPhrasesViewController()
  }

  func makeCustomPhrasesViewController() -> CustomPhrasesViewController {
    CustomPhrasesViewController()
  }

  func makeLayoutDisplayViewController() -> LayoutDisplayViewController {
    LayoutDisplayViewController(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  func makeClipboardSyncSettingsViewController() -> ClipboardSyncSettingsViewController {
    ClipboardSyncSettingsViewController(settingsViewModel: settingsViewModel)
  }

  func makeMoreSettingsViewController() -> MoreSettingsViewController {
    MoreSettingsViewController(settingsViewModel: settingsViewModel)
  }
}
