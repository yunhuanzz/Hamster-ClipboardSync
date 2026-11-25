
//
//  MoreSettingsRootView.swift
//
//  "更多"设置页的根视图: insetGrouped 列表, 行由
//  SettingsViewModel.moreSections 提供, 即原有 sections 减去首页卡片
//  已覆盖的项 (常用语 / 我的词组 / 按键效果 / 剪贴板同步一节 /
//  收藏的快捷操作一节)。
//  行渲染方式与旧的设置首页表格一致 (navigation/toggle/textField/
//  button/pullDown/settings/step); 点按跳转在下面的 didSelectRowAt 里
//  调 setting.navigationAction (与 KeyboardSettingsRootView /
//  RimeRootView / AboutRootView 同一写法)。注意: SettingTableViewCell
//  是普通 UITableViewCell, 内部不处理点按——第 5 轮这里只 deselect
//  不调 navigationAction, 是整页点不动的断点。
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

class MoreSettingsRootView: NibLessView {
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

extension MoreSettingsRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    settingsViewModel.moreSections.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    settingsViewModel.moreSections[section].items.count
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    settingsViewModel.moreSections[section].title
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    settingsViewModel.moreSections[section].footer
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let setting = settingsViewModel.moreSections[indexPath.section].items[indexPath.row]

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
      // 注意: SliderTableViewCell 继承 NibLessTableViewCell, 不是
      // SettingTableViewCell 的子类, 以前这里强转 SettingTableViewCell
      // 恒失败, step 行直接返回未配置的空 cell (round 16 item 3 已改对)。
      guard let cell = cell as? SliderTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    }
  }
}

extension MoreSettingsRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    // 整页点不动的断点就在这里: 第 5 轮只 deselect, 从不调 navigationAction。
    // More 页的项本身都带 navigationAction (输入方案设置 -> .inputSchema,
    // Wi-Fi上传方案 -> .uploadInputSchema, 文件管理 -> .finder,
    // 键盘设置 -> .keyboardSettings, 键盘配色 -> .colorSchema,
    // iCloud同步 -> .iCloud, 软件备份 -> .backup, RIME -> .rime,
    // 关于 -> .about), MainViewController.navigationResponse 也全都处理,
    // 只差这一行调用。非 navigation 行 (toggle/textField/button) 的
    // navigationAction 是 nil, 调了也没事。
    let setting = settingsViewModel.moreSections[indexPath.section].items[indexPath.row]
    setting.navigationAction?()
  }
}
