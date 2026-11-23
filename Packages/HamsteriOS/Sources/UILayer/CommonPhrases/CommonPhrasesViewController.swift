//
//  CommonPhrasesViewController.swift
//
//
//  Created by Hamster on 2026/11/23.
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 常用语设置页: 增 / 改 / 删常用语。
/// 数据存在共享 UserDefaults 的 commonPhrases key (键盘工具栏的常用语面板读同一个 key),
/// 所以这里改完, 键盘里的常用语面板立刻同步。
/// 注意: 一旦这个 key 被写过 (哪怕删到空), 就不再恢复 10 条内置常用语。
class CommonPhrasesViewController: NibLessViewController {
  private lazy var rootView = CommonPhrasesRootView()

  override func loadView() {
    title = "常用语"
    view = rootView
    rootView.onAdd = { [weak self] text in self?.addPhrase(text) }
    rootView.onEdit = { [weak self] index in self?.editPhrase(at: index) }
    rootView.onDelete = { [weak self] index in self?.deletePhrase(at: index) }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reload()
  }

  private func reload() {
    rootView.reload(with: UserDefaults.hamster.commonPhrases)
  }

  private func addPhrase(_ text: String) {
    var phrases = UserDefaults.hamster.commonPhrases
    phrases.append(text)
    UserDefaults.hamster.commonPhrases = phrases
    reload()
  }

  private func deletePhrase(at index: Int) {
    var phrases = UserDefaults.hamster.commonPhrases
    guard phrases.indices.contains(index) else { return }
    phrases.remove(at: index)
    UserDefaults.hamster.commonPhrases = phrases
    reload()
  }

  /// 点一行: 弹窗编辑, 预填当前内容, 保存后写回。
  private func editPhrase(at index: Int) {
    let phrases = UserDefaults.hamster.commonPhrases
    guard phrases.indices.contains(index) else { return }
    let alert = UIAlertController(title: "编辑常用语", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.text = phrases[index]
    }
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
      guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
      var updated = UserDefaults.hamster.commonPhrases
      guard updated.indices.contains(index) else { return }
      updated[index] = text
      UserDefaults.hamster.commonPhrases = updated
      self?.reload()
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    present(alert, animated: true)
  }
}
