//
//  KeyboardPasteSegmentsPanelView.swift
//
//  粘贴行 ⌄ 的展开视图 (仿微信输入法):
//  微信里复制内容在候选栏时, ⌄ 不是隐藏键盘, 而是展开复制内容、智能分段,
//  让用户选其中一段粘贴。本面板把剪贴板内容按行、再按句读标点切成片段,
//  每段一行可点 (点某段只粘贴那段并关闭); 顶部一行"粘贴全部"。
//  由 KeyboardToolbarView 以覆盖层方式展示在键盘根视图上。
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 剪贴板内容分段展开面板: 标题 + 关闭按钮 + "粘贴全部" + 分段列表。
class KeyboardPasteSegmentsPanelView: NibLessView {
  /// 点某一段时的回调 (只粘贴该段), 由调用方输入文本并关闭面板。
  var onSelectSegment: ((String) -> Void)?
  /// 点"粘贴全部"时的回调, 由调用方粘贴全部内容并关闭面板。
  var onSelectAll: (() -> Void)?
  /// 关闭按钮回调
  var onClose: (() -> Void)?

  /// 分段结果 (上限 20 段)。
  private var segments: [String] = []

  /// 覆盖式面板底色: 调用方 (KeyboardToolbarView) 传入与键盘本体一致的不透明颜色;
  /// 默认用系统键盘标准底色 (浅色 #D5D6DD / 深色 #2C2C2C, 不透明)。
  var panelBackgroundColor: UIColor = HamsterUIColor.shared.standardKeyboardBackground {
    didSet {
      backgroundColor = panelBackgroundColor
      tableView.backgroundColor = panelBackgroundColor
    }
  }

  private lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "复制内容"
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

  /// 顶部"粘贴全部"行: 点按粘贴全部剪贴板内容。
  private lazy var pasteAllButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("粘贴全部", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.contentHorizontalAlignment = .left
    button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(pasteAllTapped), for: .touchUpInside)
    return button
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
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PasteSegmentCell")
    return tableView
  }()

  private lazy var emptyLabel: UILabel = {
    let label = UILabel()
    label.text = "没有可分段的内容"
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
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
    addSubview(pasteAllButton)
    addSubview(tableView)
    addSubview(emptyLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      pasteAllButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      pasteAllButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      pasteAllButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      pasteAllButton.heightAnchor.constraint(equalToConstant: 44),

      tableView.topAnchor.constraint(equalTo: pasteAllButton.bottomAnchor, constant: 4),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])
  }

  override func setupAppearance() {
    // 不透明: 面板是盖在键盘根视图上的全屏覆盖层, 必须用与键盘本体一致的
    // 不透明底色, 否则按键会从列表后面透出来。
    backgroundColor = panelBackgroundColor
  }

  /// 刷新分段列表: 把剪贴板内容切成片段 (上限 20 段)。
  func reload(with text: String) {
    segments = Self.segments(from: text)
    emptyLabel.isHidden = !segments.isEmpty
    tableView.reloadData()
  }

  /// 按行、再按句读标点把文本切成片段, 去空、上限 20 段。
  /// 句读标点: 。！？；，、.!?; (含换行, 换行先按行切)。
  /// 没有标点的内容 (如单个词、URL) 就是一段。
  static func segments(from text: String) -> [String] {
    var result: [String] = []
    let separators = CharacterSet(charactersIn: "。！？；，、.!?;")
    for line in text.components(separatedBy: .newlines) {
      var current = ""
      for ch in line {
        current.append(ch)
        if String(ch).rangeOfCharacter(from: separators) != nil {
          let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty { result.append(trimmed) }
          current = ""
          if result.count >= 20 { return result }
        }
      }
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { result.append(trimmed) }
      if result.count >= 20 { return Array(result.prefix(20)) }
    }
    return Array(result.prefix(20))
  }

  @objc private func closeTapped() {
    onClose?()
  }

  @objc private func pasteAllTapped() {
    onSelectAll?()
  }
}

extension KeyboardPasteSegmentsPanelView: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    segments.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "PasteSegmentCell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = segments[indexPath.row]
    content.textProperties.numberOfLines = 2
    content.textProperties.lineBreakMode = .byTruncatingTail
    cell.contentConfiguration = content
    // 列表是不透明底色, cell 本身透明即可 (透出列表底色, 不透出按键)。
    cell.backgroundColor = .clear
    return cell
  }
}

extension KeyboardPasteSegmentsPanelView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onSelectSegment?(segments[indexPath.row])
  }
}
