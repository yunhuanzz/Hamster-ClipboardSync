//
//  KeyboardCommonPhrasesEditorPanelView.swift
//
//  键盘内常用语管理面板: 不离开键盘即可管理常用语。
//  列表点一条载入编辑, 左滑删除; 顶部输入框 + 添加/保存按钮。
//  读写 App Group 共享 UserDefaults 的 commonPhrases,
//  与主 App 设置页共用同一份数据, 改完立刻同步。
//
//  注意: 键盘扩展里无法把键盘按键的输入直接路由到面板内的输入框
//  (按键输入只会写到宿主 App 的输入框, 改路由要动核心输入链路且无法验证,
//  有把正常打字写错地方的风险), 所以面板内输入框的文字靠"粘贴"填入
//  (点粘贴按钮或长按输入框选粘贴); 要直接打字请点底部"在 App 中编辑"。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 键盘内常用语管理面板: 标题 + 关闭按钮 + 输入行 + 列表 + 去 App 编辑。
class KeyboardCommonPhrasesEditorPanelView: NibLessView {
  /// 关闭按钮回调
  var onClose: (() -> Void)?
  /// 点"在 App 中编辑"时的回调 (由调用方用现有 open-app 机制打开主 App)。
  var onOpenApp: (() -> Void)?

  /// 正在编辑的常用语下标 (nil 表示新增)。
  private var editingIndex: Int?

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  /// 注意: 不能用 .clear——第 3 轮的透明修法是错的, 面板是全屏覆盖层,
  /// 透明底会让键盘按键从列表后面透出来。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
      tableView.backgroundColor = panelBackgroundColor
    }
  }

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "常用语管理"
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("关闭", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    return button
  }()

  private lazy var inputTextField: UITextField = {
    let textField = UITextField()
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.placeholder = "输入常用语"
    textField.font = .systemFont(ofSize: 15)
    textField.borderStyle = .roundedRect
    textField.returnKeyType = .done
    textField.delegate = self
    textField.addTarget(self, action: #selector(inputTextChanged), for: .editingChanged)
    return textField
  }()

  /// 粘贴剪贴板内容到输入框 (用户主动点的, 是合规的剪贴板读取点)。
  private lazy var pasteButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("粘贴", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(pasteButtonTapped), for: .touchUpInside)
    return button
  }()

  private lazy var actionButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("添加", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isEnabled = false
    button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    return button
  }()

  /// 仅编辑时出现: 取消本次编辑, 清空输入框。
  private lazy var cancelButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("取消", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isHidden = true
    button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
    return button
  }()

  private lazy var hintLabel: UILabel = {
    let label = UILabel()
    label.text = "点「粘贴」从剪贴板填入; 要直接打字请去 App 中编辑。"
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .plain)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 44
    // 不透明: 面板本身已是不透明底色, 列表用同一颜色, 按键透不出来;
    // 深色模式下是深灰, 不是纯黑, 不会出现黑斑。
    tableView.backgroundColor = panelBackgroundColor
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CommonPhraseCell")
    return tableView
  }()

  private lazy var emptyLabel: UILabel = {
    let label = UILabel()
    label.text = "暂无常用语"
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 底部: 去主 App 编辑 (可直接打字)。
  private lazy var openAppButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("在 App 中编辑 (可打字)", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(openAppButtonTapped), for: .touchUpInside)
    return button
  }()

  init() {
    super.init(frame: .zero)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(titleLabel)
    addSubview(closeButton)
    addSubview(inputTextField)
    addSubview(pasteButton)
    addSubview(actionButton)
    addSubview(cancelButton)
    addSubview(hintLabel)
    addSubview(tableView)
    addSubview(emptyLabel)
    addSubview(openAppButton)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      inputTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      inputTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      inputTextField.heightAnchor.constraint(equalToConstant: 36),

      pasteButton.centerYAnchor.constraint(equalTo: inputTextField.centerYAnchor),
      pasteButton.leadingAnchor.constraint(equalTo: inputTextField.trailingAnchor, constant: 8),

      actionButton.centerYAnchor.constraint(equalTo: inputTextField.centerYAnchor),
      actionButton.leadingAnchor.constraint(equalTo: pasteButton.trailingAnchor, constant: 8),

      cancelButton.centerYAnchor.constraint(equalTo: inputTextField.centerYAnchor),
      cancelButton.leadingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: 8),
      cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      hintLabel.topAnchor.constraint(equalTo: inputTextField.bottomAnchor, constant: 6),
      hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      tableView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: openAppButton.topAnchor, constant: -8),

      emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

      openAppButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      openAppButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      openAppButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
      openAppButton.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来 (第 3 轮改成 .clear 是错的)。
    // 深色模式下底色是深灰 (#2C2C2C), 不是纯黑, 所以不会再出现黑斑。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新列表内容 (从共享 UserDefaults 读)。
  func reload() {
    let phrases = UserDefaults.hamster.commonPhrases
    emptyLabel.isHidden = !phrases.isEmpty
    tableView.reloadData()
  }

  /// 进入编辑态: 把第 index 条载入输入框 (按钮变"保存", 出现取消)。
  /// 列表点一条与剪贴板面板 ⋮→编辑共用; 下标越界时什么都不做。
  func beginEditingPhrase(at index: Int) {
    let phrases = UserDefaults.hamster.commonPhrases
    guard phrases.indices.contains(index) else { return }
    enterEditingMode(at: index, text: phrases[index])
  }

  /// 把一条载入输入框进入编辑态 (按钮变"保存", 出现取消)。
  private func enterEditingMode(at index: Int, text: String) {
    editingIndex = index
    inputTextField.text = text
    actionButton.setTitle("保存", for: .normal)
    actionButton.isEnabled = true
    cancelButton.isHidden = false
    inputTextField.becomeFirstResponder()
  }

  /// 退出编辑态 (清空输入框、按钮恢复"添加"、隐藏取消)。
  private func exitEditingMode() {
    editingIndex = nil
    inputTextField.text = ""
    actionButton.setTitle("添加", for: .normal)
    actionButton.isEnabled = false
    cancelButton.isHidden = true
    inputTextField.resignFirstResponder()
  }

  @objc private func closeTapped() {
    inputTextField.resignFirstResponder()
    onClose?()
  }

  @objc private func openAppButtonTapped() {
    inputTextField.resignFirstResponder()
    onOpenApp?()
  }

  @objc private func inputTextChanged() {
    let text = inputTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    actionButton.isEnabled = !text.isEmpty
  }

  @objc private func pasteButtonTapped() {
    #if canImport(UIKit)
      if let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        inputTextField.text = text
        inputTextChanged()
      }
    #endif
  }

  /// 添加 (新增) 或保存 (编辑): 写入共享 UserDefaults 并刷新列表。
  @objc private func actionButtonTapped() {
    let text = inputTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else { return }
    var phrases = UserDefaults.hamster.commonPhrases
    if let index = editingIndex, phrases.indices.contains(index) {
      phrases[index] = text
    } else {
      phrases.append(text)
    }
    UserDefaults.hamster.commonPhrases = phrases
    exitEditingMode()
    reload()
  }

  @objc private func cancelButtonTapped() {
    exitEditingMode()
  }

  private func deletePhrase(at index: Int) {
    var phrases = UserDefaults.hamster.commonPhrases
    guard phrases.indices.contains(index) else { return }
    phrases.remove(at: index)
    UserDefaults.hamster.commonPhrases = phrases
    // 正在编辑的正是被删的这一条时, 退出编辑态
    if editingIndex == index {
      exitEditingMode()
    } else if let editing = editingIndex, editing > index {
      editingIndex = editing - 1
    }
    reload()
  }
}

extension KeyboardCommonPhrasesEditorPanelView: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    actionButtonTapped()
    return false
  }
}

extension KeyboardCommonPhrasesEditorPanelView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    UserDefaults.hamster.commonPhrases.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CommonPhraseCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = UserDefaults.hamster.commonPhrases[indexPath.row]
    content.textProperties.numberOfLines = 2
    content.textProperties.lineBreakMode = .byTruncatingTail
    cell.contentConfiguration = content
    cell.backgroundColor = .clear
    return cell
  }
}

extension KeyboardCommonPhrasesEditorPanelView: UITableViewDelegate {
  /// 点一条: 载入输入框进入编辑态 (按钮变"保存", 出现取消)。
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let phrases = UserDefaults.hamster.commonPhrases
    guard phrases.indices.contains(indexPath.row) else { return }
    enterEditingMode(at: indexPath.row, text: phrases[indexPath.row])
  }

  /// 左滑删除。
  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      self?.deletePhrase(at: indexPath.row)
      completion(true)
    }
    return UISwipeActionsConfiguration(actions: [delete])
  }
}
