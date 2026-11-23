//
//  CustomPhrasesViewController.swift
//
//
//  Created by Hamster on 2026/11/23.
//

import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

/// 我的词组设置页: 增 / 改 / 删自定义词组。
/// 数据写 App Group 用户数据目录下的 custom_phrase.txt
/// (RIME table, 词组<TAB>拼音<TAB>权重), 部署时编进 custom_phrase.userdb,
/// 打字时优先出现。改完要点"重新部署"才生效 (按钮在页面顶部)。
class CustomPhrasesViewController: NibLessViewController {
  private lazy var rootView = CustomPhrasesRootView()

  override func loadView() {
    title = "我的词组"
    view = rootView
    rootView.onAdd = { [weak self] word, code in self?.addPhrase(word: word, code: code) }
    rootView.onEdit = { [weak self] index in self?.editPhrase(at: index) }
    rootView.onDelete = { [weak self] index in self?.deletePhrase(at: index) }
    rootView.onDeploy = { [weak self] in self?.deploy() }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reload()
  }

  private func reload() {
    rootView.reload(with: CustomPhraseStore.load())
  }

  private func addPhrase(word: String, code: String) {
    var phrases = CustomPhraseStore.load()
    phrases.append(CustomPhrase(word: word, code: code))
    save(phrases)
  }

  private func deletePhrase(at index: Int) {
    var phrases = CustomPhraseStore.load()
    guard phrases.indices.contains(index) else { return }
    phrases.remove(at: index)
    save(phrases)
  }

  /// 点一行: 弹窗编辑词组和拼音, 预填当前内容, 保存后写回文件。
  private func editPhrase(at index: Int) {
    let phrases = CustomPhraseStore.load()
    guard phrases.indices.contains(index) else { return }
    let alert = UIAlertController(title: "编辑词组", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.text = phrases[index].word
      textField.placeholder = "词组"
    }
    alert.addTextField { textField in
      textField.text = phrases[index].code
      textField.placeholder = "拼音, 如 ni hao"
      textField.autocapitalizationType = .none
      textField.autocorrectionType = .no
    }
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
      guard let fields = alert?.textFields, fields.count >= 2 else { return }
      let word = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let code = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !word.isEmpty, !code.isEmpty else { return }
      var updated = CustomPhraseStore.load()
      guard updated.indices.contains(index) else { return }
      updated[index] = CustomPhrase(word: word, code: code, weight: updated[index].weight)
      self?.save(updated)
    })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    present(alert, animated: true)
  }

  private func save(_ phrases: [CustomPhrase]) {
    do {
      try CustomPhraseStore.save(phrases)
      reload()
    } catch {
      ProgressHUD.failed(error, interaction: false, delay: 3)
    }
  }

  /// 重新部署 RIME, 让新词生效 (复用 RIME 页面的部署流程)。
  private func deploy() {
    Task {
      await HamsterAppDependencyContainer.shared.rimeViewModel.rimeDeploy()
    }
  }
}
