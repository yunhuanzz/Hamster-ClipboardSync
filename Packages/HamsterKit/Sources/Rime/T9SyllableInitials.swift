//
//  T9SyllableInitials.swift
//  HamsterKit
//
//  九宫格常用音节首字母拼写 (第 13 轮第 3 项 a 小点)。
//
//  问题: 九宫格打 4263 应该是“好的” (hao + d 缩写), 实际候选里根本
//  没有“好的” (200 个候选里都找不到); 单按 3 也出不了“的/得/地”。
//  同类: 9434 出不了“这个”、4266 出不了“好吗/好呢”、74366 出不了
//  “什么”、7446 出不了“是你”、9246 出不了“在哪”、94 出不了“这”,
//  6968 出不了“没有”、7443 出不了“是的”。
//
//  根因 (librime 1.8.5 源码 + 真机同款 deployer/驱动活验证, 不是猜的):
//  1. 方案自带的超级简拼是 abbrev 规则 (t9.schema.yaml:
//     abbrev/^([a-z]).+$/$1/): “de”能派生出“d”, 但派生出的拼写类型是
//     kAbbreviation。
//  2. 查询时 syllabifier.cc 的 BuildSyllableGraph 在清理音节图:
//     只要存在一条全是普通拼写的路径走到输入末尾, last_type 就定成
//     kFuzzySpelling, 所有 kAbbreviation 音节一律从图里删掉
//     (“remove disqualified syllables when there is a path of more
//     favored type”)。九宫格数字太粗, 几乎任何数字串都有一条全普通
//     拼写的切分 (4263 能切成 42|63 ga|le), 所以缩写读法系统性被剪掉;
//     26 键 "haod" 能出“好的”, 只是因为它没有全普通切分、缩写边活下来了。
//  3. derive 规则派生的拼写保持 kNormalSpelling 类型 (calculus.h:
//     Derivation 不改类型, 只有 Fuzzing/Abbreviation 才改),
//     不会被清理剪掉。所以把常用功能音节的首字母形式改写成 derive
//     规则, 就能让它以普通拼写活下来。
//
//  做法 (不改上游仓库本身, 不改大词典权重): 只给 t9.custom.yaml 打
//  补丁, 在 speller/algebra 里加 76 条 derive 规则, 其中 1 条是通用规则
//  (≥3 字母音节取首字母), 其余 75 条各针对一个常用音节
//  (整音节锚定 ^...$, 不会误伤别的音节):
//    de->d (的/得/地: 好的/是的), ge->g (个: 这个),
//    ne->n (呢: 好呢), na->n (那/哪: 在哪),
//    ma->m (吗: 好吗), me->m (么: 什么), ni->n (你: 是你),
//    zhe->zh (这), shi->sh (是), chi->ch (吃), mei->m (没: 没有)。
//    yi->y (以/意/一: 可以), dou->d (都: 都得), dian->d (点: 买点)。
//    ha->h (哈: 哈哈), he->h (呵: 呵呵), hei->h (嘿: 嘿嘿),
//    heng->h (哼: 哼哼), hu->h (呼: 呼呼), hao->h (好: 好的/好吗/好呢),
//    xi->x (嘻: 嘻嘻; 西: 东西), wu->w (呜: 呜呜), xie->x (谢: 谢谢),
//    xiang->x (想: 想想), zou->z (走: 走走), wang->w (汪: 汪汪),
//    wei->w (微: 微信), xin->x (信: 微信), xian->x (现: 现在),
//    zai->z (在: 在哪/现在), zen->z (怎: 怎么),
//    en->e (嗯: 嗯嗯), deng->d (等: 等等),
//    bai->b (拜: 拜拜), cai->c (猜: 猜猜), bao->b (抱: 抱抱/淘宝),
//    mo->m (摸: 摸摸), miao->m (喵: 喵喵),
//    jin->j (今: 今天), tian->t (天: 今天/明天), ming->m (明: 明天),
//    dong->d (东: 东西/京东), jing->j (京: 京东),
//    tao->t (淘: 淘宝), wo->w (我: 我们),
//    shen->sh (什: 什么), qing->q (情: 事情), qin->q (亲: 亲亲),
//    zhi->zh (知: 知道),
//    kan->k (看: 看看), la->l (啦: 啦啦), ku->k (哭: 哭哭)。
//  其中 shi->sh、chi->ch 在模糊音开着时是冗余的 (“shi”能经模糊规则
//  derive 成“si”, “chi”能成“ci”, 都是普通类型, 74 是 #1、24 吃 #7
//  本来就成立); 留着它们是让缩写不依赖模糊音开关——实测模糊音全关
//  时 74 是、24 吃仍成立, 4263 好的、9434 这个、64426 你好也都成立。
//
//  序号: 沿用模糊音块的 @before 标量写法 (第 11 轮实测结论, 列表写法
//  会清空整个 algebra), 从 12 开始排 (模糊音占 00..11), 保证两边都
//  插在方案自带规则之前、数字映射规则之前: 模糊音先在字母拼写上派生,
//  再由本块给出首字母形式, 最后数字映射规则把字母拼写转成数字码。
//  模糊音关掉时本块序号仍有效: @before 12..87 落在自带规则
//  [iu]a 之后、数字映射之前, 顺序不变。
//  只写 t9.custom.yaml (26 键 "haod" 本来就能出“好的”, 不需要)。
//  常开, 不跟模糊音开关走。
//
//  活验证 (librime 1.8.5 真实 deployer + 驱动, 干净无学习词库):
//  改前 4263 的“好的”在 200 候选里 NOT FOUND, 单 3 的“的”在 43 候选里
//  NOT FOUND, 9434 的“这个”、4266 的“好吗/好呢”、74366 的“什么”,
//  7446 的“是你”、9246 的“在哪”、94 的“这”、6968 的“没有”全部
//  NOT FOUND; 改后 4263 好的 #1、9434 这个 #2、4266 好吗 #2/好呢 #8、
//  74366 什么 #1、7446 是你 #15、94 这 #3、74 是 #1、24 吃 #7、
//  6968 没有 #1、7443 是的 #4; 回归: 64426 你好 #1、42633 好的 #1、
//  4265 好了 #4 不变, (a)(b)(c) 三个长句首选不变,
//  26 键 haod 好的 #1、wozaitiaowaimaizhong 我在条外卖中不变。
//  单键行为变化 (实测, 补全机制本来就会给单键出补全候选, 所以变化很小):
//  单 3 由 饿/呃/恶… 变成 的/地/得/德/饿…, 单 6 由 哦/噢/喔… 变成
//  那/吗/没/里…, 单 4 首选仍是个、单 5/单 7 与改前完全相同。
//  例外: 9246 的“在哪”改后只排 #109——找得到但太靠后, 是它本身词频
//  低 (89000, 对比 这个 503750、好的 500784), 不是缩写问题, 不修权重。
//
//  2026-11-26 扩展 (+3 条: yi->y, dou->d, dian->d; 原因见下):
//  9 键 539/59 的“可以”改前在 3000 候选里 NOT FOUND——“yi”是 2 字母
//  缩写读法, 被 round-17 的 IsShortAbbrevTail 跳过 (它只放过 derive
//  成普通拼写的音节); “dou”“dian”同理 (33 都得 NOT FOUND)。
//  改后 539 可以 #1、59 可以 #4、33 都得 #29 (可选中, 再由学习接管);
//  回归 r17-verify.sh PASS=14 FAIL=0 (644 你好 #4、94266 小鸟 #44、
//  笑尿学习、haod/4263/64426/脑子里全是你均不变)。
//  336243743663744468 的“分别什么时候”仍 NOT FOUND——那是 Poet
//  beam (kMaxLineCandidates=7) 在第 3 音节处剪掉了 fen|bie 路径,
//  不是权重/.gram 问题 (26 键全拼 fenbieshenmeshihou 是 #1);
//  需另做引擎改动, 不在本批。
//
//  2026-11-26 扩展 (第 3 项: 44 哈哈 / 77 QQ 的系统性修复):
//  用户报 9 键 44 不出“哈哈” ( sidebar 锁 h h 也不出; 反复打全拼
//  haha 后学习词库才给出来), 77 不出“QQ”, 要求彻底的常用词权重优化,
//  不是只补一个词。活验证 (librime rig, 干净无学习词库):
//  哈哈在 cn_dicts/base.dict.yaml:152930, ha ha, 权重 500363——
//  不是权重低 (好的 500784、这个 503750 同级); 全拼 4242 哈哈 #2,
//  缩写 44 在 80 候选里 NOT FOUND。呵呵 (500636) 同样 44 NOT FOUND,
//  而 各个 (ge ge, 500349) 44 #1——差别只在 ge 有 derive 规则、
//  ha/he 没有: 缩写读法在中间音节边上被 syllabifier 清理剪掉,
//  2 字母尾音节还会被 IsShortAbbrevTail 跳过; 学习词组豁免这两处,
//  所以反复打全拼后才出来。26 键全拼对照全部 #1 (呵呵/谢谢/看看/
//  知道/京东/哭哭/哈哈/听听), 证明词都在词库里, 只是 9 键机制问题。
//  所以这批不碰权重 (见下), 只按同一机制补规则: 首批 42 条覆盖
//  一组日常词的最短 9 键码 (2 字词取首字母, 如 44 哈哈/呵呵/嘿嘿/
//  哼哼/呼呼、99 谢谢/想想/微信/现在、55 看看、33 等等/嗯嗯、
//  22 拜拜/猜猜/抱抱、58 今天、68 明天、96 我们/怎么/在哪、
//  82 淘宝、53 京东、746 什么、747 事情、943 知道、64 你好、
//  43 好的、46 好吗/好呢、69 没有、743 是的、944 这个、
//  88 听听、7474 说说、86 他们——后 3 个是首批漏补、复测才发现的,
//  同机制, 见 rules 末尾“补遗”)。
//  注意翻转效应: 一条规则给某数字键造出第一条正常拼写路径后,
//  该键参与的输入会新激活缩写清理——原来靠“无正常路径、缩写存活”
//  出候选的词会被剪掉, 除非它的音节也在本批里。已闭包处理:
//  jin/jing (5) 翻转 55, 故同步补 kan/la/ku (看看/啦啦/哭哭);
//  qing/qin (7) 翻转 77, 故 亲亲 (qin) 与 事情 (qing) 同批;
//  5/7/8 首现正常码还会翻转 45/54/57/75/78/87 等输入, 回归时用
//  64 个 2 位输入改前 top-50 逐项比对 (见 /tmp/item3-before),
//  丢了常用词就补它的音节规则, 再验证。QQ 不走这条路: QQ 在
//  en_dicts/en.dict.yaml:16469 有词条 (QQ QQ, 无权重), 但 t9
//  的 melt_eng 翻译器是注释掉的, 26 键小写 qq 也找不到它
//  (大写 QQ 才 #1); QQ 见 BuiltInCustomPhrases.swift (自定义短语
//  补位, 不是词典改权重)。权重结论: 本批词典权重都不低
//  (500k 级为主), 只有 哭哭 3280、啦啦 5555、嗯嗯/哦哦 9999、
//  京东 11290、汪汪 11100、喵喵 11090、猜猜 17630、拜拜 18950
//  是真低——这些走 BuiltInCustomPhrases 的定向补位, 不改
//  base.dict.yaml (见该文件; 各词补位后的实测排名以 rig 为准)。
//
//  同日精炼 (终版 76 条: 1 通用 + 75 定向):
//  首批 42 条 (后补到 56 条: 听听/说说/他们/可以的 ke) 上 rig 后,
//  59 可以一度 NOT FOUND——jin/jing 给 5 号键造了正常路径,
//  59 新激活缩写清理, ke 只剩缩写读法被剪掉; 补 ke->k 恢复 (#4)。
//  但 64 个 2 位输入改前 top-50 的逐项比对 (rig 实测) 显示翻转
//  的代价远不止 59: 25 北京/不能、35 很快/大家、75 时间、
//  77 事实/事情、79 实现/使用、95 研究、99 已有…共 600 个
//  改前 top-50 的词在改后 top-50 里消失, 其中 560 个是真丢失
//  (NOT FOUND, 其余只是被挤出 top-50)。原因是逐音节补规则给
//  5/7/8 号键造了首条正常路径后, 所有 2 位输入都有了正常路径,
//  中间音节只剩缩写读法的词全被剪掉; 闭包要补 181 个首音节。
//  逐音节补不下去: @before 序号是 2 位零填充、按字典序应用,
//  总条目 (模糊音 12 + 本块) 必须 ≤100, 否则 3 位序号打乱顺序
//  (ConfigList::Insert 在序号超长时还会补 null 项)。
//  试过 1 条全通用规则 derive/^([a-z]).+$/$1/ (全部音节取首字母):
//  600 个词全回来 (北京 25 #1、不能 #3、很快 #20、事情 77 #13),
//  但 r17-verify.sh 13/14——4263 好的 #1 被 方法 #1 顶掉
//  (方法 502196 > 好的 500784; 尾音节 fa 变正常拼写后,
//  IsShortAbbrevTail 再也拦不住它, 正是 round-17 预言过的回归)。
//  终版是两者折中: 通用规则只取 ≥3 字母音节的首字母
//  derive/^([a-z]).{2,}$/$1/ (2 字母音节不受影响, 尾音节 fa
//  留在缩写类型, IsShortAbbrevTail 继续拦 方法); 定向规则补
//  通用规则够不到的: 6 条 zh/ch/sh 的 2 字母读法、20 条 2 字母音节
//  首字母、37 条回归闭包的 2 字母首音节、3 条模糊音变体首字母
//  (hu->f / he->f / ni->l, 救 互联/河南/湖南/你就/你是)。
//  fa->f 故意不补 (见 rules 注释)。终版实测: r17-verify.sh
//  PASS=14 FAIL=0; 600 个丢失词复测 (见下); 呼呼曾因重构时漏了
//  hu->h 一度仍 NOT FOUND, 补回后恢复 (教训: 重构后要全量复测)。
//  代价: 候选池变大, 部分词排名比 56 条版深 (如 哈哈 44 #13->#23,
//  谢谢 99 #24->#76, 看看 55 #3->#34)——找得到比排第一位重要,
//  低权重词另有 BuiltInCustomPhrases 补位。
//  同日补遗 (e 组 9 条): 精炼版复测 64 个 2 位输入改前 top-50,
//  仍有 33 个词 NOT FOUND——15 个在 747 (虽然/商品/搜索/水平/
//  随时/三是/上升/上市/上述/双手/手术/损失/授权/税收/设施),
//  2 个在 65 (路口/路径), 14 个在 29 (阿伟/阿星等名字)。
//  747/65 的原因是: 这些词的首音节要占 2 位 (74/65 的前 2 位
//  是 "sh"/"n"), 而 "sh"/"n" 本是缩写类型, 通用规则造出首字母
//  正常路径后被清理剪掉 (见 (e) 注释)。(e) 组把这 9 个 2 字母
//  读法写成正常拼写, 复测后 16 个全回来了 (设施除外, 见下)。
//  设施 (she->sh) 是第 10 条: 加上它时长句 脑子里全是你 从 #1
//  掉到 NOT FOUND (poet beam 挤兑, 见 (e) 注释), 所以 she->sh
//  不补, 设施走 BuiltInCustomPhrases 补位 (747)。29 的 14 个名字是另
//  一回事: 它们不依赖缩写边 (a 本就是整音节、wei->w 是通用规则
//  给的正常边), 只是权重低、候选池变大后被挤到 3000 名开外
//  (深度问题, 不是机制问题); 名字不值得逐个补位, 接受残留。
//
//  补丁写法复用第 5/10 轮的 marker-block 做法: 只动
//  "# BEGIN/END hamster-t9-syllable-initials" 标记块, 与模糊音块、
//  词库块共存于同一个顶级 patch: 键下 (三块是兄弟关系, 互不嵌套)。
//  插入点取 patch: 映射的末尾 (模糊音块、词库块的 END 行之后),
//  模糊音块是 full block 形态时先把它改成 nested 形态
//  (与 LayoutDictionary.insertingDictionaryBlock 同款处理)。
//  删除本块时若块里嵌着别人的块, 原样保留 (防御性, 正常流程不会发生)。
//  改完需要点「重新部署」才生效 (librime 要重新编译方案)。
//  部署/同步/重置时 RimeContext 会重打一次, 文件丢了也能恢复。
//

import Foundation
import OSLog

/// 九宫格常用音节首字母拼写 (常开, 只写 t9)。
public enum T9SyllableInitials {
  /// 76 条 derive 规则: 常用音节首字母拼写 (普通拼写类型, 不会被
  /// syllabifier 的缩写清理剪掉)。顺序即 @before 序号顺序。
  /// 第 13/17 轮的 14 条已并入下面的结构 (见 (a)(b)); 本块共 76 条,
  /// @before 12..87。
  /// 顺序即 @before 序号顺序 (12..87; 模糊音块占 00..11, 见文件头)。
  /// 结构 (第 3 项终版, 见文件头“2026-11-26 扩展”后的
  /// “同日精炼”一段): 1 条通用规则 (≥3 字母音节取首字母) + 75 条定向规则。
  /// 通用规则覆盖全部 ≥3 字母音节 (含 zh/ch/sh 的 1 字母读法
  /// shi->s / zhi->z 等); 定向规则只补通用规则够不到的:
  /// (a) 6 条 zh/ch/sh 的 2 字母读法 (zhe->zh 等, 供 74x 输入);
  /// (b) 20 条 2 字母音节的首字母 (de->d 等, 通用规则要求 ≥3 字母);
  /// (c) 37 条回归闭包补的 2 字母音节首字母 (bu->b 等, 见下);
  /// (d) 3 条模糊音变体的首字母 (hu->f / he->f / ni->l);
  /// (e) 9 条 2 字母读法 (shang->sh 等, 供 74x/65 输入, 见 (e) 注释)。
  /// 注意: fa->f 故意不补——它会让 方法 (fang fa) 的尾音节变正常拼写,
  /// IsShortAbbrevTail 再也拦不住它, 4263 好的 #1 会被 方法 #1 顶掉
  /// (方法 502196 > 好的 500784, 全通用规则实测已验证);
  /// 罚款 (fa kuan, 35) 因此仍不出, 代价 1 个词, 换 4263 #1。
  /// 另注意: @before 序号是 2 位零填充、按字典序应用, 总条目
  /// (模糊音 12 + 本块 67 = 79) 必须 ≤100, 否则 3 位序号会打乱顺序
  /// (ConfigList::Insert 在序号超长时会补 null 项, 见
  /// librime config_data.cc); 所以覆盖面不能再靠逐音节加规则——
  /// 通用规则就是为此存在的。
  public static let rules: [String] = [
    // 通用规则: ≥3 字母音节取首字母 (普通拼写)。^([a-z]).{2,}$ 只匹配
    // 长度 ≥3 的拼写, 2 字母音节 (fa/de/bu…) 不受它影响——这是故意的:
    // 2 字母尾音节 (如 方法的 fa) 必须留在缩写类型, IsShortAbbrevTail
    // 才能把它拦在 好的 后面 (见 4263 一节)。
    "derive/^([a-z]).{2,}$/$1/",
    // (a) zh/ch/sh 的 2 字母读法 (供 74x/94x/24x 输入; 通用规则只给
    // 1 字母读法 shi->s, 2 字母读法要另补)。
    "derive/^zhe$/zh/", // 这
    "derive/^shi$/sh/", // 是
    "derive/^chi$/ch/", // 吃
    "derive/^shen$/sh/", // 什: 什么
    "derive/^zhi$/zh/", // 知: 知道
    "derive/^shuo$/sh/", // 说: 说说
    // (b) 2 字母音节的首字母 (第 13/17 轮 + 第 3 项首批)。
    "derive/^de$/d/", // 的/得/地
    "derive/^ge$/g/", // 个
    "derive/^ne$/n/", // 呢
    "derive/^na$/n/", // 那/哪
    "derive/^ma$/m/", // 吗
    "derive/^me$/m/", // 么
    "derive/^ni$/n/", // 你
    "derive/^ha$/h/", // 哈: 哈哈
    "derive/^he$/h/", // 呵: 呵呵
    "derive/^hu$/h/", // 呼: 呼呼
    "derive/^yi$/y/", // 以/意/一: 可以
    "derive/^xi$/x/", // 嘻: 嘻嘻; 西: 东西
    "derive/^wu$/w/", // 呜: 呜呜
    "derive/^wo$/w/", // 我: 我们
    "derive/^en$/e/", // 嗯: 嗯嗯
    "derive/^mo$/m/", // 摸: 摸摸
    "derive/^la$/l/", // 啦: 啦啦
    "derive/^ku$/k/", // 哭: 哭哭
    "derive/^ta$/t/", // 他: 他们
    "derive/^ke$/k/", // 可: 可以
    // (c) 回归闭包: 逐音节加规则翻转了 5/7/8 号键的清理行为后,
    // 原来靠“无正常路径、缩写存活”出候选的常用词 (北京/不能/很快…)
    // 在 64 个 2 位输入的改前 top-50 里共丢了 600 个词;
    // 通用规则救回其中 ≥3 字母首音节的 427 个,
    // 这里补剩下的 2 字母首音节 (37 条, fa 除外, 见上)。
    "derive/^ai$/a/",
    "derive/^an$/a/",
    "derive/^bi$/b/",
    "derive/^bo$/b/",
    "derive/^bu$/b/", // 不: 不能/不是/北京
    "derive/^ce$/c/",
    "derive/^ci$/c/",
    "derive/^cu$/c/",
    "derive/^da$/d/", // 大: 大家
    "derive/^er$/e/",
    "derive/^fo$/f/",
    "derive/^fu$/f/",
    "derive/^gu$/g/",
    "derive/^ji$/j/", // 今: 今天 (ji 系)
    "derive/^ju$/j/",
    "derive/^li$/l/", // 力: 力量
    "derive/^lu$/l/",
    "derive/^lv$/l/",
    "derive/^mu$/m/",
    "derive/^nv$/n/",
    "derive/^pi$/p/",
    "derive/^po$/p/",
    "derive/^qi$/q/",
    "derive/^qu$/q/",
    "derive/^re$/r/",
    "derive/^ri$/r/",
    "derive/^ru$/r/",
    "derive/^si$/s/",
    "derive/^su$/s/",
    "derive/^te$/t/", // 特: 特别
    "derive/^ti$/t/", // 提: 提高
    "derive/^tu$/t/", // 图: 图片
    "derive/^xu$/x/",
    "derive/^ye$/y/",
    "derive/^yu$/y/",
    "derive/^ze$/z/",
    "derive/^zi$/z/",
    // (d) 模糊音变体的首字母 (互联/河南/湖南走 hu->fu->f,
    // 你就/你是走 ni->li->l; 模糊派生本身是普通类型,
    // 只有最后的缩写一步是缩写类型, 所以直接给变体首字母)。
    "derive/^hu$/f/", // 互: 互联 (经 fu)
    "derive/^he$/f/", // 河: 河南 (经 fe)
    "derive/^ni$/l/", // 你: 你就/你是 (经 li)
    // (e) 2 字母读法 (供 74x/65 这种“首音节占 2 位”的输入):
    // 通用规则只给首字母 (shang->s), 但 747 这类输入里首音节要占
    // 前 2 位 (74), 得靠 2 字母读法 "sh"; 而 "sh" 本是缩写类型,
    // 通用规则造出首字母正常路径后, 它在中间音节边上会被清理剪掉
    // (改前 top-50 里 747 丢了 15 个词、65 丢了 2 个, 都是这原因)。
    // 前 4 条是 sh 系音节自己的 2 字母读法; 后 4 条是 s 系音节经
    // s<->sh 模糊音变体 (san->shan 等) 的 2 字母读法; 最后 1 条是
    // lu 经 n<->l 模糊音变体 (lu->nu) 的首字母。
    // 注意: 只补残留清单要用的 9 条, 不把全部 sh/ch/zh 音节都列出来
    // (@before 总条目 88, 离 100 上限只剩 12 个; 其余 sh 系词改前
    // 本就不在 top-50, 不算回归)。
    // 更要注意: she->sh 故意不补——(e) 组加到第 10 条 (she) 时,
    // 长句 6269454782674464 脑子里全是你 从 #1 掉到 NOT FOUND
    // (poet beam 只有 7 宽; 第 10 个 "sh" 音节在 74 位置造出的
    // 竞争路径把 是 的路径挤出了 beam, 实测 9 条安全、10 条必掉)。
    // 设施 (she shi) 因此走 BuiltInCustomPhrases 补位 (747), 不走规则。
    "derive/^shang$/sh/", // 上: 上升/上市/上述/商品
    "derive/^shuang$/sh/", // 双: 双手
    "derive/^shou$/sh/", // 手/授: 手术/授权
    "derive/^shui$/sh/", // 水/税: 水平/税收
    "derive/^san$/sh/", // 三: 三是 (经 shan)
    "derive/^sun$/sh/", // 损: 损失 (经 shun)
    "derive/^sou$/sh/", // 搜: 搜索 (经 shou)
    "derive/^sui$/sh/", // 虽/随: 虽然/随时 (经 shui)
    "derive/^lu$/n/", // 路: 路口/路径 (经 nu)
  ]

  /// @before 序号从 12 起 (模糊音块占 00..11), 零填充到两位,
  /// 保证 ConfigMap 按字母序应用时顺序是 12..87 (共 76 条)。
  /// 每行值是单个规则字符串 (标量), 绝不能写成列表
  /// (见 FuzzyPinyin.swift 文件头: 列表会被 SetAt 原样塞进
  /// algebra[0], 导致整个 projection 被清空)。
  static var algebraPatchLines: [String] {
    rules.enumerated().map { index, rule in
      "speller/algebra/@before \(String(format: "%02d", index + 12)): \(rule)"
    }
  }

  /// 只打补丁的方案文件 (中文 9 键 t9)。
  public static let schemaFileName = "t9.custom.yaml"

  /// 补丁块的标记 (文件里只改这一段)。
  static let beginMarker = "# BEGIN hamster-t9-syllable-initials (九宫格常用音节首字母拼写, 请勿手动改这段)"
  static let endMarker = "# END hamster-t9-syllable-initials"

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static var fullBlock: String {
    ([beginMarker, "patch:"] + algebraPatchLines.map { "  " + $0 } + [endMarker])
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static var nestedBlock: String {
    ([("  " + beginMarker)] + algebraPatchLines.map { "  " + $0 } + [("  " + endMarker)])
      .joined(separator: "\n")
  }

  /// 把补丁打进两个用户数据目录 (沙盒 + App Group, 与
  /// FuzzyPinyin.apply 同款); 失败由调用方记日志、不阻断部署。
  public static func apply() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      try apply(to: dir.appendingPathComponent(schemaFileName))
    }
  }

  /// 更新单个 custom.yaml 文件 (文件不存在时视为 ""; 内容没变不重写,
  /// 不碰 mtime, 免得下次部署误判配置变了; 内容为空时删文件)。
  static func apply(to fileURL: URL) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    let updated = insertingBlock(into: removingBlock(from: content))
    if updated == content {
      return
    }
    if updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? FileManager.default.removeItem(at: fileURL)
      return
    }
    try updated.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 删掉本块 (BEGIN 行到 END 行, 含两行本身); 没有本块时原样返回。
  /// 例外: 块里嵌着别人的块 (模糊音/词库) 时原样保留并还挂在
  /// patch: 下面——本块是 full block 时 patch: 行在本块里, 要留一行
  /// patch: 给它; 本块是 nested 时 patch: 行本来就在块外, 不用留。
  /// (防御性: 正常流程里别的块不会嵌进本块, 见 insertingBlock。)
  static func removingBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    // BEGIN/END 在同一行 (手写文件才有): 直接删这一行。
    if begin == end {
      lines.remove(at: begin)
      return lines.joined(separator: "\n")
    }
    let inner = Array(lines[(begin + 1)..<end])
    var foreign: [String] = []
    for (foreignBeginMarker, foreignEndMarker) in [
      (FuzzyPinyin.beginMarker, FuzzyPinyin.endMarker),
      (LayoutDictionary.beginMarker, LayoutDictionary.endMarker),
    ] {
      if let foreignBegin = inner.firstIndex(where: { $0.contains(foreignBeginMarker) }),
         let foreignEnd = inner.firstIndex(where: { $0.contains(foreignEndMarker) }),
         foreignBegin <= foreignEnd {
        foreign += Array(inner[foreignBegin...foreignEnd])
      }
    }
    if foreign.isEmpty {
      lines.removeSubrange(begin...end)
    } else {
      let patchLineInside = inner.contains { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }
      let replacement = (patchLineInside ? ["patch:"] : []) + foreign
      lines.replaceSubrange(begin...end, with: replacement)
    }
    return lines.joined(separator: "\n")
  }

  /// 插入本块: 文件里已有 patch: 顶级键时挂在 patch: 映射的末尾
  /// (模糊音块、词库块的 END 行之后), 三块是 patch: 下面的兄弟关系,
  /// 互不嵌套; 模糊音块是 full block 形态 (BEGIN 行在 patch: 行正上方)
  /// 时先把它改成 nested 形态再插 (与 LayoutDictionary 同款处理,
  /// 否则本块插到它 END 行之后仍在它标记范围内,
  /// 下次关模糊音会连本块一起删掉)。
  /// 没有 patch: 键时在文件末尾追加完整的 patch: 块。
  static func insertingBlock(into content: String) -> String {
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullBlock + "\n"
    }
    var lines = content.components(separatedBy: .newlines)
    // 顶级 patch: 键 (行首无缩进; 带行内注释的也算, flow 写法除外, 这里不会出现)。
    if var patchIndex = lines.firstIndex(where: { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }) {
      // 模糊音块是 full block 形态时先改成 nested 形态
      // (BEGIN 行缩进 2 格挪到 patch: 下面, END 行若在行首也缩进
      // 2 格): 只挪注释行, 模糊音内容与标记本身不动; FuzzyPinyin
      // 按 contains() 找标记, 缩进不影响它, 下次它重打时也会
      // 按自己的写法恢复成 nested 块。
      if patchIndex > 0, lines[patchIndex - 1].contains(FuzzyPinyin.beginMarker) {
        lines.remove(at: patchIndex - 1)
        patchIndex -= 1
        lines.insert("  " + FuzzyPinyin.beginMarker, at: patchIndex + 1)
        if let fuzzyEnd = lines.firstIndex(where: { $0.contains(FuzzyPinyin.endMarker) }),
           !lines[fuzzyEnd].hasPrefix(" "), !lines[fuzzyEnd].hasPrefix("\t") {
          lines[fuzzyEnd] = "  " + lines[fuzzyEnd]
        }
      }
      // 插到 patch: 映射的末尾: 最后一个缩进行之后; 已知的块 END 行
      // 即使因手写文件在行首, 也要越过它再停 (它只是注释行),
      // 否则会插进那个块的标记范围里。
      var insertAt = patchIndex + 1
      while insertAt < lines.count {
        if lines[insertAt].contains(FuzzyPinyin.endMarker)
            || lines[insertAt].contains(LayoutDictionary.endMarker) {
          insertAt += 1
          continue
        }
        if lines[insertAt].isEmpty || lines[insertAt].hasPrefix(" ") || lines[insertAt].hasPrefix("\t") {
          insertAt += 1
        } else {
          break
        }
      }
      lines.insert(contentsOf: nestedBlock.components(separatedBy: "\n"), at: insertAt)
      return lines.joined(separator: "\n")
    }
    var result = content
    if !result.hasSuffix("\n") { result += "\n" }
    result += "\n" + fullBlock + "\n"
    return result
  }
}
