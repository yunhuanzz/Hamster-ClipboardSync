//
//  SettingsRootView.swift
//
//
//  Created by morse on 2023/7/5.
//

import Combine
import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

public class SettingsRootView: NibLessView {
  // MARK: properties

  let settingsViewModel: SettingsViewModel
  let rimeViewModel: RimeViewModel
  let backupViewModel: BackupViewModel

  lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(SettingTableViewCell.self, forCellReuseIdentifier: SettingTableViewCell.identifier)
    tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: ButtonTableViewCell.identifier)
    tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.identifier)
    tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
    tableView.contentInsetAdjustmentBehavior = .automatic
    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
    return tableView
  }()

  private var subscriptions = Set<AnyCancellable>()

  // MARK: method

  init(frame: CGRect = .zero, settingsViewModel: SettingsViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.settingsViewModel = settingsViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel

    super.init(frame: frame)

    setupView()
    combine()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func setupView() {
//    backgroundColor = UIColor.secondarySystemBackground
    constructViewHierarchy()
    activateViewConstraints()
  }

  override public func constructViewHierarchy() {
    addSubview(tableView)
  }

  override public func activateViewConstraints() {
    tableView.fillSuperview()
  }

  func combine() {
    UserDefaults.favoriteButtonSubject
      .eraseToAnyPublisher()
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] favoriteButtons in
        // 注意: 这里使用了集合的第一个元素类型收来判断是否已经存在收藏按钮 section
        // 因为收藏按钮始终添加在第 0 个 section
        let sectionsContainerFavoriteButtons = settingsViewModel.sections[0].items[0].type == .button

        // 收藏按钮为空，但集合中却包含，则删除
        if favoriteButtons.isEmpty {
          if sectionsContainerFavoriteButtons {
            settingsViewModel.sections.remove(at: 0)
            tableView.reloadData()
          }
          return
        }

        let favoriteButtonSectionItems = settingsViewModel.getFavoriteButtons(buttons: favoriteButtons)
        if sectionsContainerFavoriteButtons {
          settingsViewModel.sections[0].items = favoriteButtonSectionItems
        } else {
          settingsViewModel.sections = [SettingSectionModel(items: favoriteButtonSectionItems)] + settingsViewModel.sections
        }
        tableView.reloadData()
      }
      .store(in: &subscriptions)

    settingsViewModel.tableReloadPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] _ in
        tableReload()
      }
      .store(in: &subscriptions)

    // 剪贴板同步完成 (上传/下载结束) 后刷新表格, 让"上次同步"状态行实时更新
    NotificationCenter.default.addObserver(
      self, selector: #selector(syncDidFinish),
      name: ClipboardSyncService.didFinishNotification, object: nil)
  }

  /// 剪贴板同步完成 (上传/下载结束) 后刷新表格
  @objc private func syncDidFinish() {
    tableReload()
  }
}

// MARK: override UIView

public extension SettingsRootView {
  func tableReload() {
    settingsViewModel.reloadFavoriteButton()
    tableView.reloadData()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if let _ = window {
      tableReload()
    }
  }
}

extension SettingsRootView: UITableViewDelegate {
  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: false)
    let setting = settingsViewModel.sections[indexPath.section].items[indexPath.row]
    if setting.type == .navigation {
      setting.navigationAction?()
    }
  }

//  public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
//    let setting = settingsViewModel.sections[section].items[0]
//    if setting.type == .button {
//      return Self.favoriteRemark
//    }
//    return nil
//  }
}

extension SettingsRootView: UITableViewDataSource {
  public func numberOfSections(in tableView: UITableView) -> Int {
    return settingsViewModel.sections.count
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return settingsViewModel.sections[section].items.count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let settings = settingsViewModel.sections[indexPath.section].items[indexPath.row]

    if settings.type == .textField {
      let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? TextFieldTableViewCell else { return cell }
      cell.updateWithSettingItem(settings)
      return cell
    }

    if settings.type == .button {
      let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ButtonTableViewCell else { return cell }
      cell.updateWithSettingItem(settings)
      return cell
    }

    if settings.type == .navigation {
      let cell = tableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SettingTableViewCell else { return cell }
      cell.updateWithSettingItem(settings)
      return cell
    }

    // .toggle 及其他默认使用开关单元格
    let cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableViewCell.identifier, for: indexPath)
    guard let cell = cell as? ToggleTableViewCell else { return cell }
    cell.updateWithSettingItem(settings)
    return cell
  }
}

extension SettingsRootView {
  static let favoriteRemark = """
  长按按钮可添加或移除快捷区域
  """
}
