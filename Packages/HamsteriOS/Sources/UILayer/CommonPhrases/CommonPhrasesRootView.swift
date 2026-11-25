//
//  CommonPhrasesRootView.swift
//
//
//  Created by Hamster on 2026/11/23.
//

import HamsterUIKit
import UIKit

/// 常用语设置页根视图: 顶部添加栏 (文本框 + 添加按钮), 下方列表。
/// 点一行编辑 (弹窗), 左滑删除。数据存在共享 UserDefaults 的 commonPhrases key,
/// 键盘工具栏的常用语面板直接读同一个 key。
class CommonPhrasesRootView: NibLessView {
  private var phrases: [String] = []

  /// 添加一条常用语
  var onAdd: ((String) -> Void)?
  /// 点一行: 编辑
  var onEdit: ((Int) -> Void)?
  /// 左滑删除
  var onDelete: ((Int) -> Void)?

  private lazy var phraseTextField: UITextField = {
    let textField = UITextField()
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.placeholder = "输入常用语"
    textField.borderStyle = .roundedRect
    textField.returnKeyType = .done
    textField.delegate = self
    return textField
  }()

  private lazy var addButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("添加", for: .normal)
    button.titleLabel?.font = .boldSystemFont(ofSize: 17)
    button.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
    return button
  }()

  private lazy var addBarView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(phraseTextField)
    view.addSubview(addButton)
    NSLayoutConstraint.activate([
      phraseTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      phraseTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      phraseTextField.heightAnchor.constraint(equalToConstant: 36),
      addButton.leadingAnchor.constraint(equalTo: phraseTextField.trailingAnchor, constant: 12),
      addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      addButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      addButton.widthAnchor.constraint(equalToConstant: 52),
    ])
    return view
  }()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CommonPhraseCell")
    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundColor = SettingsAppearance.pageBackgroundColor
    return tableView
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(addBarView)
    addSubview(tableView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      addBarView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      addBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
      addBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
      addBarView.heightAnchor.constraint(equalToConstant: 52),
      tableView.topAnchor.constraint(equalTo: addBarView.bottomAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemGroupedBackground
  }

  func reload(with phrases: [String]) {
    self.phrases = phrases
    tableView.reloadData()
  }

  @objc private func addButtonTapped() {
    guard let text = phraseTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
    phraseTextField.text = nil
    phraseTextField.resignFirstResponder()
    onAdd?(text)
  }
}

extension CommonPhrasesRootView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    phrases.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CommonPhraseCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = phrases[indexPath.row]
    cell.contentConfiguration = content
    return cell
  }

  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      onDelete?(indexPath.row)
    }
  }
}

extension CommonPhrasesRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onEdit?(indexPath.row)
  }
}

extension CommonPhrasesRootView: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    addButtonTapped()
    return true
  }
}
