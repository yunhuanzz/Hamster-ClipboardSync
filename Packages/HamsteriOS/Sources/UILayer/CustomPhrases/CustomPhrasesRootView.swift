//
//  CustomPhrasesRootView.swift
//
//
//  Created by Hamster on 2026/11/23.
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 我的词组设置页根视图: 顶部添加栏 (词组 + 拼音 + 添加按钮),
/// 重新部署按钮, 说明文字, 下方列表 (词组 + 拼音)。
/// 点一行编辑 (弹窗, 词组和拼音都可改), 左滑删除。
/// 数据写 custom_phrase.txt (App Group 用户数据目录), 改完要点"重新部署"才生效。
class CustomPhrasesRootView: NibLessView {
  private var phrases: [CustomPhrase] = []

  /// 添加一条词组 (词组, 拼音)
  var onAdd: ((String, String) -> Void)?
  /// 点一行: 编辑
  var onEdit: ((Int) -> Void)?
  /// 左滑删除
  var onDelete: ((Int) -> Void)?
  /// 重新部署 RIME (让新词生效)
  var onDeploy: (() -> Void)?

  private lazy var wordTextField: UITextField = {
    let textField = UITextField()
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.placeholder = "词组"
    textField.borderStyle = .roundedRect
    textField.returnKeyType = .done
    textField.delegate = self
    return textField
  }()

  private lazy var codeTextField: UITextField = {
    let textField = UITextField()
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.placeholder = "拼音, 如 ni hao"
    textField.borderStyle = .roundedRect
    textField.returnKeyType = .done
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
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
    view.addSubview(wordTextField)
    view.addSubview(codeTextField)
    view.addSubview(addButton)
    NSLayoutConstraint.activate([
      wordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      wordTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      wordTextField.heightAnchor.constraint(equalToConstant: 36),
      wordTextField.widthAnchor.constraint(equalTo: codeTextField.widthAnchor),
      codeTextField.leadingAnchor.constraint(equalTo: wordTextField.trailingAnchor, constant: 8),
      codeTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      codeTextField.heightAnchor.constraint(equalToConstant: 36),
      addButton.leadingAnchor.constraint(equalTo: codeTextField.trailingAnchor, constant: 8),
      addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      addButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      addButton.widthAnchor.constraint(equalToConstant: 52),
    ])
    return view
  }()

  private lazy var deployButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("重新部署 (让新词生效)", for: .normal)
    button.titleLabel?.font = .boldSystemFont(ofSize: 16)
    button.backgroundColor = .secondarySystemBackground
    button.layer.cornerRadius = 10
    button.addTarget(self, action: #selector(deployButtonTapped), for: .touchUpInside)
    return button
  }()

  private lazy var noteLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "词组存在 custom_phrase.txt (RIME 自定义短语词库), 打字时优先出现。拼音的音节用空格分隔。改完要点\"重新部署\", 新词才会生效; 已选过的词 RIME 会自动学习加权, 不用手动维护。"
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    return label
  }()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CustomPhraseCell")
    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
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
    addSubview(deployButton)
    addSubview(noteLabel)
    addSubview(tableView)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      addBarView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      addBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
      addBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
      addBarView.heightAnchor.constraint(equalToConstant: 52),

      deployButton.topAnchor.constraint(equalTo: addBarView.bottomAnchor, constant: 4),
      deployButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      deployButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      deployButton.heightAnchor.constraint(equalToConstant: 44),

      noteLabel.topAnchor.constraint(equalTo: deployButton.bottomAnchor, constant: 8),
      noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

      tableView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemGroupedBackground
  }

  func reload(with phrases: [CustomPhrase]) {
    self.phrases = phrases
    tableView.reloadData()
  }

  @objc private func addButtonTapped() {
    let word = wordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let code = codeTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !word.isEmpty, !code.isEmpty else { return }
    wordTextField.text = nil
    codeTextField.text = nil
    wordTextField.resignFirstResponder()
    codeTextField.resignFirstResponder()
    onAdd?(word, code)
  }

  @objc private func deployButtonTapped() {
    onDeploy?()
  }
}

extension CustomPhrasesRootView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    phrases.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CustomPhraseCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = phrases[indexPath.row].word
    content.secondaryText = phrases[indexPath.row].code
    cell.contentConfiguration = content
    return cell
  }

  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      onDelete?(indexPath.row)
    }
  }
}

extension CustomPhrasesRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onEdit?(indexPath.row)
  }
}

extension CustomPhrasesRootView: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField == wordTextField {
      codeTextField.becomeFirstResponder()
    } else {
      addButtonTapped()
    }
    return true
  }
}
