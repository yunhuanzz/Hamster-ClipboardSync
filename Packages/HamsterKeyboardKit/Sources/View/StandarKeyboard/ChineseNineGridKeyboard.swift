//
//  ChineseNineGrid.swift
//
//
//  Created by morse on 2023/9/5.
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/// 中文九宫格键盘
public class ChineseNineGridKeyboard: KeyboardTouchView, UICollectionViewDelegate {
  // MARK: - Properties

  private let keyboardLayoutProvider: ChineseNineGridLayoutProvider
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private var keyboardContext: KeyboardContext
  private var calloutContext: KeyboardCalloutContext
  private var rimeContext: RimeContext
  private var nonStanderStyle: NonStandardKeyboardStyle

  // 屏幕方向
  private var interfaceOrientation: InterfaceOrientation

  private var userInterfaceStyle: UIUserInterfaceStyle

  // 键盘是否浮动
  private var isKeyboardFloating: Bool

  /// 符号列表视图

  private lazy var symbolsListView: SymbolsVerticalView = {
    let view = SymbolsVerticalView(
      style: nonStanderStyle,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      dataBuilder: { [unowned self] in
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(keyboardContext.symbolsOfChineseNineGridKeyboard, toSection: 0)
        $0.apply(snapshot, animatingDifferences: false)
      },
      collectionDelegateBuilder: { [unowned self] in self }
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 符号列表容器视图，为了添加 insets
  private lazy var symbolsListContainerView: UIView = {
    // 九宫格自身的 insets
    let insets = keyboardLayoutProvider.insets

    let container = UIView(frame: .zero)
    container.backgroundColor = .clear
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(symbolsListView)
    NSLayoutConstraint.activate([
      symbolsListView.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
      symbolsListView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
      symbolsListView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
      symbolsListView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
    ])
    return container
  }()

  // combine
  private var subscriptions = Set<AnyCancellable>()

  /// 缓存所有按键视图
  private var keyboardRows: [[KeyboardButton]] = []

  /// 静态视图约束，视图创建完毕后不在发生变化
  private var staticConstraints: [NSLayoutConstraint] = []

  private var dynamicHeightConstraints: [NSLayoutConstraint] = []

  // MARK: - 计算属性

  private var layout: KeyboardLayout {
    keyboardLayoutProvider.keyboardLayout(for: keyboardContext)
  }

  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  // MARK: - Initialization

  public init(
    keyboardLayoutProvider: KeyboardLayoutProvider,
    actionHandler: KeyboardActionHandler,
    appearance: KeyboardAppearance,
    keyboardContext: KeyboardContext,
    calloutContext: KeyboardCalloutContext,
    rimeContext: RimeContext
  ) {
    if let keyboardLayoutProvider = keyboardLayoutProvider as? StandardKeyboardLayoutProvider {
      self.keyboardLayoutProvider = keyboardLayoutProvider.chineseNineGridLayoutProvider
    } else {
      self.keyboardLayoutProvider = ChineseNineGridLayoutProvider()
    }
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.keyboardContext = keyboardContext
    self.calloutContext = calloutContext
    self.rimeContext = rimeContext
    self.interfaceOrientation = keyboardContext.interfaceOrientation
    self.isKeyboardFloating = keyboardContext.isKeyboardFloating
    self.nonStanderStyle = appearance.nonStandardKeyboardStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupKeyboardView()

    combine()
  }

  func combine() {
    // 屏幕方向改变重新计算动态高度
    keyboardContext.$interfaceOrientation
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        guard interfaceOrientation != $0 else { return }
        setNeedsUpdateConstraints()
      }
      .store(in: &subscriptions)

    // 屏蔽左侧候选拼音功能
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        self.refreshSidebarSymbols(userInputKey: $0)
      }
      .store(in: &subscriptions)
  }

  /// 按当前输入重算边栏列表并应用 (列表为空时回落到默认符号)。
  /// 点选被拒绝时也直接调它自愈: 列表可能是旧的 (快照过期), 同步重算
  /// 一次, 免得用户对着一个点不动的旧音节反复点 (Bug A: 点 天气 后
  /// 边栏仍显示 tian)。逻辑与原来 sink 里的一致, 只是抽出来复用。
  private func refreshSidebarSymbols(userInputKey: String) {
    var pinyinList = keyboardContext.symbolsOfChineseNineGridKeyboard
    if !userInputKey.isEmpty {
      let candidatePinyinList = rimeContext.getPinyinCandidates()
      if !candidatePinyinList.isEmpty {
        pinyinList = candidatePinyinList
      }
    }
    var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
    snapshot.appendSections([0])
    snapshot.appendItems(pinyinList, toSection: 0)
    symbolsListView.diffalbeDataSource.apply(snapshot, animatingDifferences: false)
    // 选完拼音后列表重建 (下一音节): 滚回顶部, 从头看, 不用手动滑回去。
    symbolsListView.resetScrollToTop()
  }

  // MARK: - Layout

  func setupKeyboardView() {
    backgroundColor = .clear

    constructViewHierarchy()
    activateViewConstraints()
  }

  override public func constructViewHierarchy() {
    // 添加右侧符号划动列表
    addSubview(symbolsListContainerView)

    // 添加按键
    for (rowIndex, row) in layout.itemRows.enumerated() {
      var tempRow = [KeyboardButton]()
      for (itemIndex, item) in row.enumerated() {
        let buttonItem = KeyboardButton(
          row: rowIndex,
          column: itemIndex,
          item: item,
          actionHandler: actionHandler,
          keyboardContext: keyboardContext,
          rimeContext: rimeContext,
          calloutContext: calloutContext,
          appearance: appearance
        )
        buttonItem.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonItem)
        tempRow.append(buttonItem)
      }
      keyboardRows.append(tempRow)
    }
  }

  override public func activateViewConstraints() {
    // 根据 keyboardContext 获取当前布局配置
    // 注意：临时变量缓存计算属性的值，避免重复计算
    let layoutConfig = layoutConfig

    // 键盘两侧按键宽度,其余按键平分剩余宽度
    let edgeButtonWidth = keyboardLayoutProvider.smallBottomWidth(for: keyboardContext)

    // 最后一行小的系统按键宽度
    let lowerSystemButtonWidth = keyboardLayoutProvider.lowerSystemButtonWidth(for: keyboardContext)

    // 最后一行换行键 (前往, .primary) 的宽度 (第 10 轮: 与 123/中/英
    // 分开, 微信换行比 123 宽 71px, 不能同宽)。
    let lowerReturnButtonWidth = keyboardLayoutProvider.lowerReturnButtonWidth(for: keyboardContext)

    // 暂存中间部分按键，用于平分剩余宽度
    var availableItems = [KeyboardButton]()

    // 左侧符号栏约束
    staticConstraints.append(symbolsListContainerView.topAnchor.constraint(equalTo: topAnchor))
    staticConstraints.append(symbolsListContainerView.leadingAnchor.constraint(equalTo: leadingAnchor))

    for row in keyboardRows {
      for button in row {
        // 按键高度约束（高度包含 insets 部分）
        // 仿微信: 第 3 行右列是表情键 (单行高度), 换行在底行右下角,
        // 不再有跨两行的回车键, 所以每个键都加普通高度约束。
        let heightConstant = layoutConfig.rowHeight
        let buttonHeightConstraint = button.heightAnchor.constraint(equalToConstant: heightConstant)
        buttonHeightConstraint.identifier = "\(button.row)-\(button.column)-button-height"
        // 注意：必须设置高度约束的优先级，Autolayout 会根据此约束自动更新根视图的高度，否则会与系统自动添加的约束冲突，会有错误日志输出。
        buttonHeightConstraint.priority = .defaultHigh
        dynamicHeightConstraints.append(buttonHeightConstraint)

        // 按键宽度约束
        // 注意：最后一行的第一个按钮和每行最后一个按键(除最后一行)的宽度是固定的，其他按键的宽度是平分的
        if (button.column == 0 && button.row + 1 == keyboardRows.endIndex) || (button.column + 1 == row.endIndex && button.row + 1 != keyboardRows.endIndex) {
          staticConstraints.append(button.widthAnchor.constraint(equalTo: widthAnchor, multiplier: edgeButtonWidth.percentageValue!))
        } else {
          if button.row + 1 == keyboardRows.endIndex {
            // 底行: 空格键不设宽度约束 (自适应剩余宽度); 其余系统键
            // 按 action 分宽度 (第 10 轮): 换行 (.primary) 用
            // lowerReturnButtonWidth (18%), 123/中/英用
            // lowerSystemButtonWidth (13%)。
            // 第 1 列 (符号) 在上面已拿到 edge 宽度, 不会走到这里。
            // 注意: 第 7 轮底行恢复成 5 键后, 中/英在第 3 列——
            // 旧条件 (column == 1 || 是最后一列) 只覆盖 123 和前往,
            // 中/英会没有任何宽度约束 (只剩 intrinsic 宽度, 布局不稳定),
            // 所以这里按 action 判断, 不按列号。
            if button.item.action != .space {
              let width = button.item.action.isPrimaryAction ? lowerReturnButtonWidth : lowerSystemButtonWidth
              staticConstraints.append(button.widthAnchor.constraint(equalTo: widthAnchor, multiplier: width.percentageValue!))
            }
          } else {
            availableItems.append(button)
          }
        }

        if button.row == 0 {
          // 首行添加按键相对视图的 top 约束
          staticConstraints.append(button.topAnchor.constraint(equalTo: topAnchor))
        } else {
          // 其他列添加相对上一行的符号约束
          // 其他行添加按键相对上一行按键的 top 约束
          let prevRowItem = keyboardRows[button.row - 1][0]
          staticConstraints.append(button.topAnchor.constraint(equalTo: prevRowItem.bottomAnchor))

          // 最后一行的第一列添加相对划动符号列的 top 约束
          if button.column == 0, button.row + 1 == keyboardRows.endIndex {
            staticConstraints.append(button.topAnchor.constraint(equalTo: symbolsListContainerView.bottomAnchor))
            staticConstraints.append(symbolsListContainerView.widthAnchor.constraint(equalTo: button.widthAnchor))
          }

          // 最后一行添加按键相对视图的 bottom 约束
          if button.row + 1 == keyboardRows.endIndex {
            staticConstraints.append(button.bottomAnchor.constraint(equalTo: bottomAnchor))
          }
        }

        // 首列按键添加相对划动符号视图的 leading 约束
        if button.column == 0, button.row + 1 == keyboardRows.endIndex {
          staticConstraints.append(button.leadingAnchor.constraint(equalTo: leadingAnchor))
        } else if button.column == 0 {
          staticConstraints.append(button.leadingAnchor.constraint(equalTo: symbolsListContainerView.trailingAnchor))
        } else {
          // 其他列按键添加相对与前一个按键的 leading 约束
          let prevItem = keyboardRows[button.row][button.column - 1]
          staticConstraints.append(button.leadingAnchor.constraint(equalTo: prevItem.trailingAnchor))

          // 最后一列按键添加相对行的 trailing 约束
          if button.column + 1 == row.endIndex {
            staticConstraints.append(button.trailingAnchor.constraint(equalTo: trailingAnchor))
          }
        }
      }
    }

    if let firstItem = availableItems.first {
      for item in availableItems.dropFirst() {
        staticConstraints.append(item.widthAnchor.constraint(equalTo: firstItem.widthAnchor))
      }
    }

    NSLayoutConstraint.activate(staticConstraints + dynamicHeightConstraints)
  }

  override public func layoutSubviews() {
    super.layoutSubviews()

    // 样式调整
    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      nonStanderStyle = appearance.nonStandardKeyboardStyle
      symbolsListView.setStyle(nonStanderStyle)
      keyboardRows.forEach { $0.forEach { $0.setNeedsLayout() }}
    }

    // 行高调整
    guard interfaceOrientation != keyboardContext.interfaceOrientation || isKeyboardFloating != keyboardContext.isKeyboardFloating else { return }
    interfaceOrientation = keyboardContext.interfaceOrientation
    isKeyboardFloating = keyboardContext.isKeyboardFloating

    // 根据 keyboardContext 获取当前布局配置
    // 注意：临时变量缓存计算属性的值，避免重复计算
    let layoutConfig = layoutConfig
    dynamicHeightConstraints.forEach {
      $0.constant = layoutConfig.rowHeight
    }
  }
}

public extension ChineseNineGridKeyboard {
  func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    let symbol = symbolsListView.diffalbeDataSource.snapshot(for: indexPath.section).items[indexPath.item]
    actionHandler.handle(.press, on: .symbol(.init(char: symbol)))
    return true
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)

    guard let _ = collectionView.cellForItem(at: indexPath) else { return }

    // 符号处理
    let symbol = symbolsListView.diffalbeDataSource.snapshot(for: indexPath.section).items[indexPath.item]
    // 当 symbol 非字母数字，顶码上屏 (只顶引擎候选的首选; 常用语补全项只能点选, 不顶)
    if !symbol.isMatch(regex: "\\w.*") {
      if let first = rimeContext.firstEngineSuggestion {
        keyboardContext.textDocumentProxy.insertText(first.title)
        rimeContext.reset()
      }
      keyboardContext.textDocumentProxy.insertText(symbol)
      return
    }

    // 数字候选字直接上屏
    if Int(symbol) != nil {
      keyboardContext.textDocumentProxy.insertText(symbol)
      rimeContext.reset()
      return
    }

    // 候选拼音处理: 待修改拼音音节开始位置
    // (2026-11-24 边栏 jin 重现) 提交后 getInputKeys() 仍含已提交前缀,
    // 必须只在剩余输入里找, 否则会在已提交的词里命中; 替换也只重敲剩余
    // 部分, 否则提交状态就丢了 (见 tryHandleReplaceRemainingInputTexts)。
    // (#43) 剩余输入用边栏列表生成时捕获的快照, 不要在点选时刻重读
    // preedit: 点选时刻 cached preedit 可能已失效 ("" 或只剩已提交词),
    // offset 会算成全长、剩余为空, 重敲只剩被点音节, 剩余输入整个丢掉
    // (天气没了)。快照与当前显示的列表是同一时刻的。
    let (offset, remainingKeys) = rimeContext.sidebarRemainder()
    var startPos = 0
    var inputKeys = remainingKeys
    let inputKeysCount = inputKeys.utf8.count

    if let symbolT9Pinyin = pinyinToT9Mapping[symbol] {
      while !inputKeys.isEmpty {
        if inputKeys.hasPrefix(symbolT9Pinyin) {
          break
        }
        startPos += inputKeys.first?.utf8.count ?? 0
        inputKeys = String(inputKeys.dropFirst())
      }
    }

    // 已经选择到输入拼音末尾了
    if inputKeys.isEmpty, startPos == inputKeysCount, let selectCandidatePinyin = rimeContext.selectCandidatePinyin {
      startPos = selectCandidatePinyin.1
    }

    Logger.statistics.warning("sidebar tap symbol=\(symbol) offset=\(offset) remaining='\(remainingKeys)' startPos=\(startPos) count=\(symbol.utf8.count)")
    let handle = rimeContext.tryHandleReplaceRemainingInputTexts(symbol, startPos: startPos, count: symbol.utf8.count)
    Logger.statistics.warning("change input text handle = \(handle)")
    if !handle {
      // 点选被拒绝 (剩余输入已变 / 快照过期): 列表是旧的, 按当前 preedit
      // 同步重算一次自愈, 免得用户对着一个点不动的旧音节反复点。
      refreshSidebarSymbols(userInputKey: rimeContext.userInputKey)
    }
  }
}
