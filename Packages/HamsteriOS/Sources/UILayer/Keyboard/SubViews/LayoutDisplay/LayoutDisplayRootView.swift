//
//  LayoutDisplayRootView.swift
//
//  布局和显示子页的根视图: insetGrouped 列表, 行由
//  KeyboardSettingsViewModel.layoutDisplaySettings 提供。
//  行类型只有两种: .step (步进器, 候选字号/高度等) 与 toggle (开关,
//  拼音显示位置、26 键数字输入方式), 渲染方式与候选栏设置页一致。
//

import HamsterUIKit
import UIKit

class LayoutDisplayRootView: NibLessView {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 44
    tableView.register(SettingTableViewCell.self, forCellReuseIdentifier: SettingTableViewCell.identifier)
    tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.identifier)
    tableView.register(StepperTableViewCell.self, forCellReuseIdentifier: StepperTableViewCell.identifier)
    return tableView
  }()

  init(frame: CGRect = .zero, keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel

    super.init(frame: frame)

    setupView()
  }

  func setupView() {
    addSubview(tableView)
    tableView.fillSuperview()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if let _ = window {
      tableView.reloadData()
    }
  }
}

extension LayoutDisplayRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    keyboardSettingsViewModel.layoutDisplaySettings.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    keyboardSettingsViewModel.layoutDisplaySettings[section].items.count
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    keyboardSettingsViewModel.layoutDisplaySettings[section].title
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    keyboardSettingsViewModel.layoutDisplaySettings[section].footer
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let setting = keyboardSettingsViewModel.layoutDisplaySettings[indexPath.section].items[indexPath.row]
    if setting.type == .step {
      let cell = tableView.dequeueReusableCell(withIdentifier: StepperTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? StepperTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    }

    let cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableViewCell.identifier, for: indexPath)
    guard let cell = cell as? ToggleTableViewCell else { return cell }
    cell.updateWithSettingItem(setting)
    return cell
  }
}

extension LayoutDisplayRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
  }
}
