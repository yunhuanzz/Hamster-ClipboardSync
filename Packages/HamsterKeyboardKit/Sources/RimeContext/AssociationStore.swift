//
//  AssociationStore.swift
//
//  第 15 轮第 2 项 (a) 联想词: 客户端“上一段 -> 下一段”联想表。
//
//  为什么要有这一层 (活验证, 见 Docs/round15-association-design.md §1):
//  引擎侧 (无论有无 octagram) 都出不了零输入的下一句——octagram 只能给
//  已经打出来的输入的候选重排序, 而用户提交“大江东去”后什么都没输时,
//  候选栏是空的; 只打一半 langtao 时浪淘尽根本不在候选里 (NOT FOUND)。
//  所以联想必须在引擎之外做: 提交后按“上一段”查表, 直接出下一句。
//
//  数据两层:
//  - 内置表: 手选名篇名句的链 (公有领域古诗文, 不用授权、不用下载)。
//    锚点诗《念奴娇·赤壁怀古》按 gushiwen.cn 全文核对过;
//    其余是课本级名篇。异文见注释 (樯橹/强虏, 尊/樽)。
//  - 学到的对子: 用户自己连续提交的两段, 记在 App Group UserDefaults
//    (见 UserDefaults.hamster.learnedAssociations), 展示时只取出现过
//    >= 2 次的。
//  扩充内置表的正规路: 从开源古诗文集 (如 GitHub chinese-poetry,
//  公有领域) 按“句 -> 下一句”自动抽表替换 seed, 不用改机制。
//

import Foundation
import HamsterKit

/// 候选栏里“不是 RIME 引擎给的”那类建议 (第 15 轮)。
/// 联想词和英文纠错共用这一套状态机: 它们都只在没有组字时出现,
/// 都复用同一套候选 cell/样式, 都不能按引擎下标选。
public enum ExternalSuggestionKind: Equatable {
  /// 没有外部建议: 候选栏显示引擎建议 (或空)。
  case none
  /// 联想词: 上一段提交的下一句。
  case association
  /// 英文纠错: UITextChecker 给当前英文词的纠错/补全。
  case englishCorrection
}

/// 联想词数据源 (纯逻辑, 不碰 UIKit、不碰 RIME)。
public enum AssociationStore {
  /// 一次最多展示几条联想。
  public static let maxSuggestions = 5

  /// 学到的对子要出现几次才展示 (一次可能是两句不相干的话恰好连着打)。
  public static let minLearnedCount = 2

  /// 内置联想链: 每条链按顺序读, 相邻两句就是一对联想。
  /// 句一律不带标点 (用户提交的段本身也不带标点, 标点是另一次提交)。
  private static let chains: [[String]] = [
    // 念奴娇·赤壁怀古 (苏轼, 按 gushiwen.cn 全文核对;
    // “樯橹”一作“强虏”, “一尊”一作“一樽”, 这里取通行本)。
    ["大江东去", "浪淘尽", "千古风流人物", "故垒西边", "人道是", "三国周郎赤壁",
     "乱石穿空", "惊涛拍岸", "卷起千堆雪", "江山如画", "一时多少豪杰",
     "遥想公瑾当年", "小乔初嫁了", "雄姿英发", "羽扇纶巾", "谈笑间",
     "樯橹灰飞烟灭", "故国神游", "多情应笑我", "早生华发", "人生如梦", "一尊还酹江月"],
    // 静夜思 (李白)
    ["床前明月光", "疑是地上霜", "举头望明月", "低头思故乡"],
    // 春晓 (孟浩然)
    ["春眠不觉晓", "处处闻啼鸟", "夜来风雨声", "花落知多少"],
    // 登鹳雀楼 (王之涣)
    ["白日依山尽", "黄河入海流", "欲穷千里目", "更上一层楼"],
    // 相思 (王维)
    ["红豆生南国", "春来发几枝", "愿君多采撷", "此物最相思"],
    // 山居秋暝 (王维)
    ["空山新雨后", "天气晚来秋", "明月松间照", "清泉石上流"],
    // 水调歌头·明月几时有 (苏轼)
    ["明月几时有", "把酒问青天", "不知天上宫阙", "今夕是何年",
     "我欲乘风归去", "又恐琼楼玉宇", "高处不胜寒"],
    // 望月怀远 (张九龄)
    ["海上生明月", "天涯共此时", "情人怨遥夜", "竟夕起相思"],
    // 九月九日忆山东兄弟 (王维)
    ["独在异乡为异客", "每逢佳节倍思亲", "遥知兄弟登高处", "遍插茱萸少一人"],
    // 悯农 (李绅)
    ["锄禾日当午", "汗滴禾下土", "谁知盘中餐", "粒粒皆辛苦"],
    // 赋得古原草送别 (白居易)
    ["离离原上草", "一岁一枯荣", "野火烧不尽", "春风吹又生"],
    // 春望 (杜甫)
    ["国破山河在", "城春草木深", "感时花溅泪", "恨别鸟惊心"],
    // 绝句 (杜甫)
    ["两个黄鹂鸣翠柳", "一行白鹭上青天", "窗含西岭千秋雪", "门泊东吴万里船"],
    // 江雪 (柳宗元)
    ["千山鸟飞绝", "万径人踪灭", "孤舟蓑笠翁", "独钓寒江雪"],
    // 天净沙·秋思 (马致远)
    ["枯藤老树昏鸦", "小桥流水人家", "古道西风瘦马", "夕阳西下", "断肠人在天涯"],
    // 夜雨寄北 (李商隐)
    ["君问归期未有期", "巴山夜雨涨秋池", "何当共剪西窗烛", "却话巴山夜雨时"],
    // 送杜少府之任蜀州 (王勃, 只有一对, 链到此结束)
    ["海内存知己", "天涯若比邻"],
  ]

  /// 内置表: 上一句 -> 下一句列表 (一条链里相邻两句成一对;
  /// 同一句在多条链里出现时, 下一句按首次出现的链的顺序排)。
  public static let bundledNextLines: [String: [String]] = {
    var table: [String: [String]] = [:]
    for chain in chains {
      for (prev, next) in zip(chain, chain.dropFirst()) {
        if table[prev]?.contains(next) != true {
          table[prev, default: []].append(next)
        }
      }
    }
    return table
  }()

  /// 给定刚提交的文字, 返回联想的下一句列表 (最多 maxSuggestions 条)。
  /// 先精确匹配整段; 没有则取提交文字的最长后缀 (>= 2 字) 匹配——
  /// 用户一段提交里可能含多个分句 (一次上屏整句), 后缀能接上链。
  /// 内置表在前, 学到的对子在后 (按出现次数倒序), 去重。
  public static func suggestions(after committedText: String) -> [String] {
    guard isCJKText(committedText) else { return [] }
    let key = lookupKey(for: committedText)
    guard let key else { return [] }
    var result: [String] = bundledNextLines[key] ?? []
    let learned = learnedNextLines(for: key)
    for next in learned where !result.contains(next) {
      result.append(next)
    }
    return Array(result.prefix(maxSuggestions))
  }

  /// 记一对学习联想 (上一段 -> 这段): 两段都得是中文才记,
  /// 计数与持久化见 UserDefaults.hamster.recordLearnedAssociation。
  public static func recordLearnedPair(previous prev: String, next: String) {
    guard isCJKText(prev), isCJKText(next), prev != next else { return }
    UserDefaults.hamster.recordLearnedAssociation(previous: prev, next: next)
  }

  // MARK: - private

  /// 查表用的 key: 整段优先, 否则最长后缀。
  private static func lookupKey(for committedText: String) -> String? {
    if bundledNextLines[committedText] != nil
      || UserDefaults.hamster.learnedAssociations.contains(where: { $0.prev == committedText && $0.count >= minLearnedCount }) {
      return committedText
    }
    let chars = Array(committedText)
    guard chars.count > 2 else { return nil }
    for length in (2..<chars.count).reversed() {
      let suffix = String(chars.suffix(length))
      if bundledNextLines[suffix] != nil
        || UserDefaults.hamster.learnedAssociations.contains(where: { $0.prev == suffix && $0.count >= minLearnedCount }) {
        return suffix
      }
    }
    return nil
  }

  /// 学到的下一句 (出现 >= minLearnedCount 次的, 按次数倒序)。
  private static func learnedNextLines(for key: String) -> [String] {
    UserDefaults.hamster.learnedAssociations
      .filter { $0.prev == key && $0.count >= minLearnedCount }
      .sorted { $0.count > $1.count }
      .map { $0.next }
  }

  /// 是不是中文段 (>= 2 字且含 CJK 字符; 字母/数字/符号提交不触发联想)。
  static func isCJKText(_ text: String) -> Bool {
    guard text.count >= 2 else { return false }
    return text.unicodeScalars.contains {
      (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
    }
  }
}
