//
//  BuiltInCustomPhrases.swift
//  HamsterKit
//
//  内置自定义短语 (第 3 项: 44 哈哈 / 77 QQ 的系统性修复):
//  一组日常词, 靠 T9SyllableInitials 的 derive 规则出不来
//  (不是权重低, 是机制问题——见下), 所以走 custom_phrase 补位。
//
//  为什么是补位、不是改大词典权重:
//  这些词在 cn_dicts/base.dict.yaml 里的权重本来就低, 但改大词典
//  不是办法: (1) rime-ice.zip 是上游原样克隆, 打补丁改它会被下次
//  同步覆盖; (2) 权重是全局的, 改了会影响 26 键全拼的排序。
//  custom_phrase 是 schema 本来就加载的机制 (rime_ice/t9 两个 schema
//  都有 table_translator@custom_phrase, user_dict 分别是
//  custom_phrase / custom_phrase_t9, initial_quality: 99),
//  词组只在自己的编码下出现, 不影响别的输入。
//
//  权重为什么不起作用 (实测结论, 别再调权重):
//  .txt 的权重列在 librime 里不是直接当权重用的——
//  table_db.cc 的 rime_table_entry_parser 把它当 commits,
//  dee 固定为 (commits+1)/1e8 ≈ 0; user_dictionary.cc 的
//  CreateDictEntry 再算 e->weight = log(formula_p(...)) + 1.0,
//  dee≈0 时 quality ≈ initial_quality (99) + 约 0。
//  rig 实测: 权重 0 / 12 / 1000 三档, 同一词的排名完全一样
//  (QQ 77 #1、哼哼 44 #2、哭哭 55 #1、汪汪 99 #4)。
//  所以补位是二元的: 播进去就落在该编码的前 ~1-7 名, 不播就没有。
//  这里的 weight 统一用 CustomPhraseStore.defaultWeight (100),
//  只当个标记, 别指望调它改排名。
//
//  播哪些词 (rig 实测, 干净无学习词库; 排名是补位后的):
//  QQ (77 #1): en_dicts/en.dict.yaml:16469 有词条, 但 t9 的
//    melt_eng 翻译器是注释掉的, 26 键小写 qq 也找不到它——
//    9 键根本没有英文路径, 只能补位。用户点名要的。
//  哼哼/呼呼 (44 #2/#1)、嘻嘻/呜呜 (99 #2/#1)、嗯嗯 (33 #1)、
//  哦哦 (66 #1)、摸摸/喵喵 (66 #4/#2)、拜拜/猜猜/抱抱/啊啊
//  (22 #5/#7/#2/#1)、啦啦/哭哭 (55 #2/#1)、京东 (53 #1)、
//  好吗/好呢 (46 #1/#2)、在哪 (96 #1)、亲亲 (77 #2):
//    都是词典权重真低 (<150k) 又在最短 9 键码下排 30 名开外
//    (如 哭哭 3280 / 55 #2091、汪汪 11100 / 99 #2902、
//    啦啦 5555 / 55 #1666、嗯嗯 9999 / 33 #974) 的日常词,
//    derive 规则只能让它们“找得到”, 排不到前面, 所以补位。
//  设施 (747): derive 规则本可以救它 (she->sh), 但 (e) 组加到
//    第 10 条时, 长句 6269454782674464 脑子里全是你 从 #1 掉到
//    NOT FOUND (poet beam 只有 7 宽, 第 10 个 "sh" 音节挤掉了
//    是 的路径); 所以 she->sh 不补, 设施走这里补位 (747)。
//    它的 26 键码写 "sh s" (不是 "ss"), 这样 t9 码是 747
//    (sh->74, s->7); 写 "ss" 的话 t9 码会变成 77, 747 就不出。
//  不播的: 走走/汪汪 (99 #1346/#2902, 也是低权重日常词, 但
//    99 的顶栏已经有 微信/谢谢/现在, 再播两个会把 微信 挤到
//    第 2 页; 取舍后接受它们留在深处)。
//  29 的 14 个阿字名字 (阿伟/阿星等): 权重低、候选池变大后被挤到
//    3000 名开外, 是深度问题不是机制问题, 名字不值得逐个补位。
//
//  行为:
//  seed() 在部署/同步/重置时由 RimeContext 调用 (跟
//  T9SyllableInitials.apply() 同位置), 把缺失的内置词写进两个
//  用户数据目录 (沙盒 + App Group) 的 custom_phrase.txt, 再由
//  CustomPhraseStore.save() 同步生成 custom_phrase_t9.txt。
//  已存在的词 (用户改过码/权重, 或用户自己加过同名) 不动;
//  用户删掉的内置词下次部署会回来 (按词名合并, 无法区分“没播过”
//  和“用户删了”——接受这点, 这些词本来就是用户要的)。
//  内容没变不重写 (不碰 mtime, 免得下次部署误判配置变了)。
//  失败由调用方记日志、不阻断部署 (跟 T9SyllableInitials 同款)。
//  改完需要点「重新部署」才生效 (跟“我的词组”一样)。
//  注意: 播进去的词在 26 键下也生效 (同名同码): 如 26 键 qq
//  出 QQ #1、kk 出 哭哭 #1, 是同一批词, 不是两套。
//

import Foundation

/// 内置自定义短语 (第 3 项补位)。code 是首字母码
/// (设施例外, 见上); weight 只是标记, 不影响排名。
public enum BuiltInCustomPhrases {
  public static let phrases: [CustomPhrase] = [
    CustomPhrase(word: "QQ", code: "qq"),
    CustomPhrase(word: "哼哼", code: "hh"),
    CustomPhrase(word: "呼呼", code: "hh"),
    CustomPhrase(word: "嘻嘻", code: "xx"),
    CustomPhrase(word: "呜呜", code: "ww"),
    CustomPhrase(word: "嗯嗯", code: "ee"),
    CustomPhrase(word: "哦哦", code: "oo"),
    CustomPhrase(word: "摸摸", code: "mm"),
    CustomPhrase(word: "喵喵", code: "mm"),
    CustomPhrase(word: "拜拜", code: "bb"),
    CustomPhrase(word: "猜猜", code: "cc"),
    CustomPhrase(word: "抱抱", code: "bb"),
    CustomPhrase(word: "啊啊", code: "aa"),
    CustomPhrase(word: "啦啦", code: "ll"),
    CustomPhrase(word: "哭哭", code: "kk"),
    CustomPhrase(word: "京东", code: "jd"),
    CustomPhrase(word: "好吗", code: "hm"),
    CustomPhrase(word: "好呢", code: "hn"),
    CustomPhrase(word: "在哪", code: "zn"),
    CustomPhrase(word: "亲亲", code: "qq"),
    CustomPhrase(word: "设施", code: "sh s"),
    // 都得 (33): 词典权重 104790 (dou dei), 改前 33 #29,
    // 通用规则把 33 的候选池撑大后掉到 #187 (出 top-50, 任务里
    // 的 must-not-regress 项), 所以补位 (33 #1-2, 与 嗯嗯 并列顶栏)。
    CustomPhrase(word: "都得", code: "dd"),
  ]

  /// 把缺失的内置词播进两个用户数据目录 (沙盒 + App Group),
  /// 与 T9SyllableInitials.apply() 同款两目录写法。
  public static func seed() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      var existing = CustomPhraseStore.load(from: dir)
      var changed = false
      for phrase in phrases where !existing.contains(where: { $0.word == phrase.word }) {
        existing.append(phrase)
        changed = true
      }
      if changed {
        try CustomPhraseStore.save(existing, to: dir)
      }
    }
  }
}
