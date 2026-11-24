//
//  SymbolsView.swift
//
//
//  Created by morse on 2023/9/5.
//

import Combine
import UIKit

/// 符号显示视图
class SymbolsView: UICollectionView {
  var style: NonStandardKeyboardStyle
  let keyboardContext: KeyboardContext
  let actionHandler: KeyboardActionHandler
  let viewModel: ClassifySymbolicViewModel
  var subscriptions = Set<AnyCancellable>()
  private var diffableDataSource: UICollectionViewDiffableDataSource<Int, Symbol>!

  init(style: NonStandardKeyboardStyle, keyboardContext: KeyboardContext, actionHandler: KeyboardActionHandler, viewModel: ClassifySymbolicViewModel) {
    self.style = style
    self.keyboardContext = keyboardContext
    self.actionHandler = actionHandler
    self.viewModel = viewModel

    let layout = {
      // 普通 flow layout: 白键网格不要行分隔线 (微信符号菜单也没有),
      // 旧 SeparatorCollectionViewFlowLayout 会在每行下面画一条横线。
      let layout = UICollectionViewFlowLayout()
      layout.scrollDirection = .vertical
      return layout
    }()

    super.init(frame: .zero, collectionViewLayout: layout)

    self.alwaysBounceVertical = true
    self.delegate = self
    self.diffableDataSource = makeDataSource()

    setupAppearance()

    // init data
    diffableDataSource.apply(makeSnapshot(symbols: viewModel.currentCategory.symbols), animatingDifferences: false)
    scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)

    combine()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setupAppearance() {
    // 背景透明, 由 ClassifySymbolicKeyboard 提供整块不透明底色
    // (第 10 轮第 5 条: 旧 style.backgroundColor 与键盘根底色深浅不一,
    // 侧栏 / 网格 / 底行渲染成三块不同深浅)。
    self.backgroundColor = .clear
  }

  func reloadDiffableData() {
    var snapshot = diffableDataSource.snapshot()
    snapshot.reloadSections([0])
    diffableDataSource.apply(snapshot)
  }

  func setStyle(_ style: NonStandardKeyboardStyle) {
    self.style = style
    setupAppearance()
    reloadDiffableData()
  }

  func combine() {
    viewModel.$currentCategory
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        diffableDataSource.apply(makeSnapshot(symbols: $0.symbols), animatingDifferences: false)
        self.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
      }
      .store(in: &subscriptions)
  }

  func makeDataSource() -> UICollectionViewDiffableDataSource<Int, Symbol> {
    let symbolCellRegistration = UICollectionView.CellRegistration<SymbolCell, Symbol> { [unowned self] cell, _, symbol in
      // TODO: 符号分类国际化
      // cell.text = KKL10n.text(forKey: symbol.rawValue, locale: keyboardContext.locale)
      cell.updateWithSymbol(
        symbol.char,
        style: style,
        // 第 12 轮第 2 条: 白键只属于符号菜单; 侧栏复用 SymbolCell 时
        // 不传此参数 (默认 false), 保持第 11 轮之前的灰底扁平样式。
        showsKeyBackground: true
      )
    }

    let dataSource = UICollectionViewDiffableDataSource<Int, Symbol>(collectionView: self) { collectionView, indexPath, symbol in
      collectionView.dequeueConfiguredReusableCell(using: symbolCellRegistration, for: indexPath, item: symbol)
    }
    return dataSource
  }

  func makeSnapshot(symbols: [Symbol]) -> NSDiffableDataSourceSnapshot<Int, Symbol> {
    var snapshot = NSDiffableDataSourceSnapshot<Int, Symbol>()
    snapshot.appendSections([0])
    snapshot.appendItems(symbols, toSection: 0)
    return snapshot
  }
}

extension SymbolsView: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    let item = diffableDataSource.snapshot(for: indexPath.section).items[indexPath.item]
    actionHandler.handle(.press, on: .symbol(item))
    return true
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let _ = collectionView.cellForItem(at: indexPath) else { return }
    let item = diffableDataSource.snapshot(for: indexPath.section).items[indexPath.item]
    collectionView.deselectItem(at: indexPath, animated: true)
    if !keyboardContext.classifySymbolKeyboardLockState {
      actionHandler.handle(.release, on: .returnLastKeyboard)
    }
    actionHandler.handle(.release, on: .symbol(item))
  }
}

extension SymbolsView: UICollectionViewDelegateFlowLayout {
  /// 网格布局 (第 12 轮第 5 条, 向微信看齐, 实测数见注释):
  /// 微信一行 10 列, 白键宽 37pt, 白键间隙约 6.7pt, 边距约 5.3pt
  /// (440pt 宽截图实测: 白键 111px, 间隙 20px, 3px = 1pt);
  /// 我们之前一行 8 列, 格子 40pt + 间距 15pt, 白键间隙约 19.3pt。
  /// 本布局: 固定 10 列, 格子宽由实测宽度反推, 行/列间距 2pt;
  /// 白键 = 格子内缩 2pt (SymbolCell), 故白键间隙 = 2 + 4 = 6pt,
  /// 与微信的 6.7pt 接近; 440pt 宽时格子 41pt、白键 37pt, 与微信一致。
  private enum SymbolGridLayout {
    static let columns: CGFloat = 10
    static let interitemSpacing: CGFloat = 2
    static let lineSpacing: CGFloat = 2
    static let horizontalInset: CGFloat = 6
    static let verticalInset: CGFloat = 6
    static let fallbackItemSize = CGSize(width: 40, height: 40)
  }

  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    .horizontal(SymbolGridLayout.horizontalInset, vertical: SymbolGridLayout.verticalInset)
  }

  // 询问委托一个部分连续的行或列之间的间距。
  // 对于一个垂直滚动的网格，这个值表示连续的行之间的最小间距。
  // 对于一个水平滚动的网格，这个值代表连续的列之间的最小间距。
  // 这个间距不应用于标题和第一行之间的空间或最后一行和页脚之间的空间。
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    return SymbolGridLayout.lineSpacing
  }

  // 向委托询问某部分的行或列中连续项目之间的间距。
  // 你对这个方法的实现可以返回一个固定的值或者为每个部分返回不同的间距值。
  // 对于一个垂直滚动的网格，这个值代表了同一行中项目之间的最小间距。
  // 对于一个水平滚动的网格，这个值代表同一列中项目之间的最小间距。
  // 这个间距是用来计算单行可以容纳多少个项目的，但是在确定了项目的数量之后，实际的间距可能会被向上调整。
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
    return SymbolGridLayout.interitemSpacing
  }

  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    // 格子宽按实测宽度反推, 保证恰好 10 列 (不 floor: 余量不足 1pt,
    // 向下取整会在行尾攒出不对称空隙); 布局未就绪时回退到旧 40x40。
    let availableWidth = collectionView.bounds.width - SymbolGridLayout.horizontalInset * 2
    guard availableWidth > 0 else { return SymbolGridLayout.fallbackItemSize }
    let width = (availableWidth - SymbolGridLayout.interitemSpacing * (SymbolGridLayout.columns - 1)) / SymbolGridLayout.columns
    guard width > 0 else { return SymbolGridLayout.fallbackItemSize }
    return CGSize(width: width, height: width)
  }
}
