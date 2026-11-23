//
//  File.swift
//
//
//  Created by morse on 2023/7/5.
//

import Combine
import HamsterUIKit
import UIKit

protocol SubViewControllerFactory {
  func makeSettingsViewController() -> SettingsViewController
  func makeInputSchemaViewController() -> InputSchemaViewController
  func makeFinderViewController() -> FinderViewController
  func makeKeyboardSettingsViewController() -> KeyboardSettingsViewController
  func makeKeyboardColorViewController() -> KeyboardColorViewController
  func makeKeyboardFeedbackViewController() -> KeyboardFeedbackViewController
  func makeUploadInputSchemaViewController() -> UploadInputSchemaViewController
  func makeAppleCloudViewController() -> AppleCloudViewController
  func makeBackupViewController() -> BackupViewController
  func makeAboutViewController() -> AboutViewController
  func makeRimeViewController() -> RimeViewController
  func makeCommonPhrasesViewController() -> CommonPhrasesViewController
  func makeCustomPhrasesViewController() -> CustomPhrasesViewController
  /// 键盘管理页 (复用键盘布局页: 九宫格/全键盘选择)
  func makeKeyboardLayoutViewController() -> KeyboardLayoutViewController
  /// 布局和显示页
  func makeLayoutDisplayViewController() -> LayoutDisplayViewController
  /// 跨设备粘贴传送页 (剪贴板同步设置)
  func makeClipboardSyncSettingsViewController() -> ClipboardSyncSettingsViewController
  /// 定制工具栏页 (复用候选栏设置页)
  func makeToolbarSettingsViewController() -> ToolbarSettingsViewController
  /// 更多设置页 (首页卡片之外的其余设置)
  func makeMoreSettingsViewController() -> MoreSettingsViewController
}

open class MainViewController: UISplitViewController {
  private let mainViewModel: MainViewModel
  private let subViewControllerFactory: SubViewControllerFactory
  private let settingsViewController: SettingsViewController

  private lazy var inputSchemaViewController: InputSchemaViewController
    = subViewControllerFactory.makeInputSchemaViewController()

  private lazy var finderViewController: FinderViewController
    = subViewControllerFactory.makeFinderViewController()

  private lazy var keyboardSettingsViewController: KeyboardSettingsViewController
    = subViewControllerFactory.makeKeyboardSettingsViewController()

  private lazy var keyboardColorViewController: KeyboardColorViewController
    = subViewControllerFactory.makeKeyboardColorViewController()

  private lazy var keyboardFeedbackViewController: KeyboardFeedbackViewController
    = subViewControllerFactory.makeKeyboardFeedbackViewController()

  private lazy var uploadInputSchemaViewController: UploadInputSchemaViewController
    = subViewControllerFactory.makeUploadInputSchemaViewController()

  private lazy var rimeViewController: RimeViewController
    = subViewControllerFactory.makeRimeViewController()

  private lazy var backupViewController: BackupViewController
    = subViewControllerFactory.makeBackupViewController()

  private lazy var iCloudViewController: AppleCloudViewController
    = subViewControllerFactory.makeAppleCloudViewController()

  private lazy var aboutViewController: AboutViewController
    = subViewControllerFactory.makeAboutViewController()

  private lazy var commonPhrasesViewController: CommonPhrasesViewController
    = subViewControllerFactory.makeCommonPhrasesViewController()

  private lazy var customPhrasesViewController: CustomPhrasesViewController
    = subViewControllerFactory.makeCustomPhrasesViewController()

  /// 键盘管理页 (复用键盘布局页)
  private lazy var keyboardManagementViewController: KeyboardLayoutViewController
    = subViewControllerFactory.makeKeyboardLayoutViewController()

  private lazy var layoutDisplayViewController: LayoutDisplayViewController
    = subViewControllerFactory.makeLayoutDisplayViewController()

  private lazy var clipboardSyncSettingsViewController: ClipboardSyncSettingsViewController
    = subViewControllerFactory.makeClipboardSyncSettingsViewController()

  /// 定制工具栏页 (复用候选栏设置页)
  private lazy var toolbarSettingsViewController: ToolbarSettingsViewController
    = subViewControllerFactory.makeToolbarSettingsViewController()

  /// 更多设置页 (首页卡片之外的其余设置)
  private lazy var moreSettingsViewController: MoreSettingsViewController
    = subViewControllerFactory.makeMoreSettingsViewController()

  private lazy var primaryNavigationViewController: UINavigationController = {
    let vc = UINavigationController(rootViewController: settingsViewController)
    return vc
  }()

  private lazy var secondaryNavigationViewController: UINavigationController = {
    let vc = UINavigationController(rootViewController: aboutViewController)
    return vc
  }()

  private var subscriptions = Set<AnyCancellable>()

  init(mainViewModel: MainViewModel, subViewControllerFactory: SubViewControllerFactory) {
    self.mainViewModel = mainViewModel
    self.subViewControllerFactory = subViewControllerFactory
    self.settingsViewController = subViewControllerFactory.makeSettingsViewController()

    super.init(style: .doubleColumn)
    self.delegate = self
    // primary 视图始终可见
    self.presentsWithGesture = false
    self.preferredDisplayMode = .twoBesideSecondary
    self.preferredSplitBehavior = .tile
    self.displayModeButtonVisibility = .never
    self.showsSecondaryOnlyButton = false
    self.setViewController(primaryNavigationViewController, for: .primary)
    self.setViewController(secondaryNavigationViewController, for: .secondary)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - override UIViewController

extension MainViewController {
  override open func viewDidLoad() {
    super.viewDidLoad()

    /// 动态控制导航
    mainViewModel.subViewPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        self.navigationResponse(to: $0)
      }
      .store(in: &subscriptions)

    mainViewModel.shortcutItemTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] type in
        Task {
          switch type {
          case .rimeDeploy:
            await rimeViewController.rimeViewModel.rimeDeploy()
          case .rimeSync:
            await rimeViewController.rimeViewModel.rimeSync()
          default:
            break
          }
        }
      }
      .store(in: &subscriptions)
  }
}

// MARK: - implementation UISplitViewControllerDelegate

extension MainViewController: UISplitViewControllerDelegate {
  public func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
    /// 首选显示 primary 列
    return .primary
  }
}

// MARK: - custom method

extension MainViewController {
  func navigationResponse(to subView: SettingsSubView) {
    switch subView {
    case .inputSchema:
      presentInputSchemaViewController()
    case .finder:
      presentFinderViewController()
    case .uploadInputSchema:
      presentUploadInputSchemaViewController()
    case .keyboardSettings:
      presentKeyboardSettingsViewController()
    case .colorSchema:
      presentKeyboardColorViewController()
    case .feedback:
      presentKeyboardFeedbackViewController()
    case .rime:
      presentRimeViewController()
    case .backup:
      presentBackupViewController()
    case .iCloud:
      presentAppleCloudViewController()
    case .about:
      presentAboutViewController()
    case .commonPhrases:
      presentCommonPhrasesViewController()
    case .customPhrases:
      presentCustomPhrasesViewController()
    case .keyboardManagement:
      presentKeyboardManagementViewController()
    case .layoutDisplay:
      presentLayoutDisplayViewController()
    case .clipboardSync:
      presentClipboardSyncSettingsViewController()
    case .toolbarSettings:
      presentToolbarSettingsViewController()
    case .more:
      presentMoreSettingsViewController()
    case .main:
      presentMainViewController()
    default:
      return
    }
  }

  func presentMainViewController() {
    primaryNavigationViewController.popToRootViewController(animated: false)
  }

  func presentInputSchemaViewController() {
    presentViewController(inputSchemaViewController)
  }

  func presentFinderViewController() {
    presentViewController(finderViewController)
  }

  func presentUploadInputSchemaViewController() {
    presentViewController(uploadInputSchemaViewController)
  }

  func presentKeyboardSettingsViewController() {
    presentViewController(keyboardSettingsViewController)
  }

  func presentKeyboardColorViewController() {
    presentViewController(keyboardColorViewController)
  }

  func presentKeyboardFeedbackViewController() {
    presentViewController(keyboardFeedbackViewController)
  }

  func presentRimeViewController() {
    presentViewController(rimeViewController)
  }

  func presentBackupViewController() {
    presentViewController(backupViewController)
  }

  func presentAppleCloudViewController() {
    presentViewController(iCloudViewController)
  }

  func presentAboutViewController() {
    presentViewController(aboutViewController)
  }

  func presentCommonPhrasesViewController() {
    presentViewController(commonPhrasesViewController)
  }

  func presentCustomPhrasesViewController() {
    presentViewController(customPhrasesViewController)
  }

  func presentKeyboardManagementViewController() {
    presentViewController(keyboardManagementViewController)
  }

  func presentLayoutDisplayViewController() {
    presentViewController(layoutDisplayViewController)
  }

  func presentClipboardSyncSettingsViewController() {
    presentViewController(clipboardSyncSettingsViewController)
  }

  func presentToolbarSettingsViewController() {
    presentViewController(toolbarSettingsViewController)
  }

  func presentMoreSettingsViewController() {
    presentViewController(moreSettingsViewController)
  }

  private func presentViewController(_ vc: UIViewController) {
    if isCollapsed {
      // iPhone (单列): 把目标页压到当前页上面, 不要先 popToRoot。
      // 之前每次导航都先 popToRoot 再 push, 从“更多”点进子设置时,
      // 更多页先被弹出 (闪回主设置页), 子设置压在主设置上面,
      // 返回就直接回主设置、跳过了更多 (第 8 轮)。
      // 各子页都是懒加载单例: 同一个实例已在栈里时不能再 push
      // (UIKit 会抛异常), 这种情况才 pop 回它; 不在栈里就直接 push。
      if primaryNavigationViewController.viewControllers.contains(vc) {
        primaryNavigationViewController.popToViewController(vc, animated: true)
      } else {
        primaryNavigationViewController.pushViewController(vc, animated: true)
      }
      return
    }
    secondaryNavigationViewController.viewControllers = [vc]
  }
}
