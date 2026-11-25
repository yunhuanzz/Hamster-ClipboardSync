//
//  ClipboardSyncSettingsRootView.swift
//
//  跨设备粘贴传送子页的根视图: insetGrouped 列表, 行由
//  SettingsViewModel.clipboardSyncSettings 提供 (开关 + 文本框 +
//  上次同步状态行 + 立即同步按钮)。同步完成时收到通知刷新状态行。
//  行渲染方式与旧的设置首页表格一致 (navigation/toggle/textField/
//  button/pullDown/settings/step)。
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

class ClipboardSyncSettingsRootView: NibLessView {
  private var subscriptions = Set<AnyCancellable>()
  private let settingsViewModel: SettingsViewModel

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 44
    tableView.register(SettingTableViewCell.self, forCellReuseIdentifier: SettingTableViewCell.identifier)
    tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.identifier)
    tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
    tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: ButtonTableViewCell.identifier)
    tableView.register(PullDownMenuCell.self, forCellReuseIdentifier: PullDownMenuCell.identifier)
    tableView.register(SliderTableViewCell.self, forCellReuseIdentifier: SliderTableViewCell.identifier)
    SettingsAppearance.apply(to: tableView)
    return tableView
  }()

  init(frame: CGRect = .zero, settingsViewModel: SettingsViewModel) {
    self.settingsViewModel = settingsViewModel

    super.init(frame: frame)

    setupView()
    combine()
  }

  func setupView() {
    addSubview(tableView)
    tableView.fillSuperview()
  }

  func combine() {
    // 同步完成时刷新状态行 (上次同步文字)。
    NotificationCenter.default.publisher(for: ClipboardSyncService.didFinishNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.tableView.reloadData()
      }
      .store(in: &subscriptions)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if let _ = window {
      tableView.reloadData()
    }
  }
}

extension ClipboardSyncSettingsRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    settingsViewModel.clipboardSyncSettings.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    settingsViewModel.clipboardSyncSettings[section].items.count
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    settingsViewModel.clipboardSyncSettings[section].title
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    settingsViewModel.clipboardSyncSettings[section].footer
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let setting = settingsViewModel.clipboardSyncSettings[indexPath.section].items[indexPath.row]

    switch setting.type {
    case .navigation:
      let cell = tableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SettingTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .toggle:
      let cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ToggleTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .textField:
      let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? TextFieldTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .button:
      let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ButtonTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .pullDown:
      let cell = tableView.dequeueReusableCell(withIdentifier: PullDownMenuCell.identifier, for: indexPath)
      guard let cell = cell as? PullDownMenuCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .settings:
      let cell = tableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SettingTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .step:
      let cell = tableView.dequeueReusableCell(withIdentifier: SliderTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SliderTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    }
  }
}

extension ClipboardSyncSettingsRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
  }
}
