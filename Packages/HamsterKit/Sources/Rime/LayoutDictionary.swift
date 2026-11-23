//
//  LayoutDictionary.swift
//  HamsterKit
//
//  每布局词库绑定 (第 10 轮第 7 条): App 设置 -> 键盘布局里,
//  给中文 26 键 (rime_ice 方案) 和中文 9 键 (t9 方案) 各选一个词库。
//
//  背景: 用户说的"词库"是字典文件 (.dict.yaml), 不是输入方案。
//  App 自带 11 个 .dict.yaml, 全在 rime-ice 里 (rime-prelude 一个没有):
//  - rime_ice.dict.yaml (主词库, merged, import 8105/base/ext/tencent/others;
//    cn_dicts/41448 在 import_tables 里被注释掉了, 默认不启用)
//  - cn_dicts/8105、41448、base、ext、tencent、others (6 个中文组件)
//  - en_dicts/en、en_ext (英文)、melt_eng (英文合并, import en_ext + en)
//  - radical_pinyin (部首拼音, 码是带调拼音如 heng2)
//  诚实结论: 真正能当拼音主词库的只有一个大的合并词库 rime_ice
//  (加它的 6 个组件); 其余是英文/部首辅助。花样主要在输入方案,
//  不在词库; 自定义词库以后靠导入 (.dict.yaml 放进 Rime 用户数据目录)。
//  注意: tencent.dict.yaml 没有注音列 (columns 只有 text/weight,
//  词条是"词 + 权重", 读音靠 8105 字表在编译时自动注音——
//  entry_collector.cc: 无码词条进 encode_queue, 由 encoder 拆字
//  查已收集的单字读音来注音)。单挂它时没有任何单字读音可查,
//  全部 Encode failure, 等于空词库, 所以九宫格不列它;
//  九宫格拼音词库是 rime_ice + 8105/41448/base/ext/others 共 6 个,
//  不是 7 个 (任务原先数的 7 个把 tencent 也算进去了, 是错的)。
//  26 键仍列全部 11 个 (含 tencent, 只是别指望它单挂能出候选)。
//
//  机制 (librime 1.8.5 源码核对过, 不是猜的):
//  - 词库是方案通过 translator/dictionary 挂的: rime_ice.schema.yaml
//    的 translator 有 dictionary: rime_ice; t9.schema.yaml 只有
//    translator/prism: t9, 没有 dictionary, 是经 __include
//    rime_ice.schema.yaml:/ 从 rime_ice 继承来的。
//    换词库 = 给方案写 <schema>.custom.yaml, patch 里盖掉
//    translator/dictionary。落点只写各方案自己的文件:
//    26 键 -> rime_ice.custom.yaml, 9 键 -> t9.custom.yaml。
//  - 为什么只写自己的文件就够 (config_compiler.cc):
//    __include 的解析是 "*target = included; 再把本文件的字面量
//    MergeTree 合并上去", 本文件优先; 而补丁 (auto_patch_config_plugin,
//    <资源>.custom:/patch) 的优先级 kPatch(2) 高于包含 kInclude(1),
//    解析顺序是先包含后补丁。所以 t9.custom.yaml 里的
//    translator/dictionary 一定盖掉从 rime_ice 继承来的值;
//    反过来, 只写 rime_ice.custom.yaml 也会影响 t9 (继承),
//    但会被 t9 自己的绑定盖掉。两布局绑不同词库时互不干扰。
//    另外注意: 加载 t9 时 auto-patch 会同时对 t9 和被包含的
//    rime_ice 两个资源生效, 所以两个 custom.yaml 都可能被读到,
//    各自只改自己的资源, 不冲突。
//  - 词库名写的是相对路径去扩展名, 不是 dict 文件里的 name: 字段:
//    dict_compiler.cc 用 ResolvePath(dict_name + ".dict.yaml") 找文件,
//    所以 cn_dicts/8105.dict.yaml 的写法是 cn_dicts/8105
//    (rime_ice.dict.yaml 的 import_tables 就是这么写的);
//    只写 8105 会找不到顶层的 8105.dict.yaml 而部署失败。
//  - 改完要重新部署才生效。部署时 ConfigNeedsUpdate 靠
//    __build_info/timestamps (build_info_plugin 记录了编译涉及的
//    全部资源文件, 含 .custom.yaml 的 mtime) 发现 custom.yaml 变了,
//    重新编译方案; SchemaUpdate 再按编译后的 translator/dictionary
//    去编词库。词库换了, dict_file_checksum (dict_compiler.cc,
//    对 import_tables 的文件集算 checksum) 一定变, 旧 table/prism
//    复用不上, 会自动重建; 另外部署时还会删一次对应方案的 prism
//    (见 RimeContext.deployment, 与 part-1 新补方案删 prism 同款
//    双保险)。所以不要手动去删 table/prism, 也不用改 .schema.yaml。
//  - 补丁写法复用第 5 轮 FuzzyPinyin 的 marker-block 做法:
//    只动 "# BEGIN/END hamster-layout-dictionary" 标记块,
//    文件里已有 patch: 顶级键时挂在它下面 (不再另起一个 patch:,
//    否则 YAML 重复键会丢内容); 绑回默认 (rime_ice) 时只删标记块,
//    文件删到只剩空白就删文件。改完按开关重打的部署逻辑也在
//    RimeContext.deployment()/syncRime()/restRime() 里,
//    绑定存在共享 UserDefaults, 是事实来源, 文件丢了也能恢复。
//  - 与模糊音块共存 (同一文件、同一个顶级 patch: 键下两个块):
//    本块插入时插到 patch: 映射的末尾、模糊音块的 END 行之后,
//    不插在 patch: 行正下方, 所以不会插进模糊音块里; 模糊音块
//    是 full block 形态 (BEGIN 行在 patch: 行正上方、patch:
//    被包在它标记里) 时, 插入前先把它改成 nested 形态 (BEGIN 行
//    缩进 2 格挪到 patch: 下面), 否则本块仍落在它标记范围内。
//    反方向只在"本块是 full block 且模糊音后打进来"时才会把
//    模糊音块嵌进本块里, 那种情况只发生在用户先绑了词库、再去
//    RIME 页开模糊音开关的瞬间, 且下次部署会自愈 (见
//    removingDictionaryBlock 的注释)。
//    删除本块时, 若块里嵌着模糊音块, 把它原样保留并还挂在
//    patch: 下面, 绝不连模糊音块一起删。
//    (模拟验证过: 两块以任意顺序打补丁/开关/绑回默认,
//    YAML 始终合法, 且删一块不会带走另一块。)
//

import Foundation
import OSLog

/// 每布局词库绑定。
public enum LayoutDictionary {
  /// 默认词库: 雾凇拼音大词库。
  public static let defaultDictionaryId = "rime_ice"

  /// 可绑词库的布局 (以方案 id 标识; 自定义布局用自己的方案, 不参与)。
  public enum Layout: String, CaseIterable {
    /// 中文 26 键, rime_ice 方案。
    case rimeIce = "rime_ice"
    /// 中文 9 键, t9 方案。
    case t9 = "t9"

    /// 该布局的补丁文件。
    var customFileName: String { rawValue + ".custom.yaml" }
  }

  /// 一个可选词库。
  public struct DictionaryOption: Hashable, Identifiable {
    /// patch 值: 用户数据目录下的相对路径去 ".dict.yaml",
    /// 如 "rime_ice"、"cn_dicts/base"。
    public let id: String
    /// 列表里显示的名字。
    public let displayName: String
    /// 补充说明 (版本/规模/用途)。
    public let detail: String
    /// 码是不是拼音 (九宫格只列这个为 true 的:
    /// 数字要先拼出拼音音节才能出候选, 纯字母词库没候选)。
    public let isPinyinCapable: Bool

    public init(id: String, displayName: String, detail: String, isPinyinCapable: Bool) {
      self.id = id
      self.displayName = displayName
      self.detail = detail
      self.isPinyinCapable = isPinyinCapable
    }
  }

  /// 自带词库的展示信息 (逐个核对过 /tmp/rime-ice-check 里的文件头;
  /// version 是各文件自己的 version 字段; 词条数是 "..." 之后
  /// 含 tab 的非注释行数, rime_ice 本身只有 A-Z 26 个单字母,
  /// 词汇全靠 import_tables 的 5 个组件)。
  /// key 是 patch 值 (相对路径去扩展名), 不是文件里的 name: 字段
  /// (cn_dicts 下文件的 name: 只有 8105/base 这种短名, 不带目录)。
  static let bundledMetadata: [String: (displayName: String, detail: String, isPinyinCapable: Bool)] = [
    "rime_ice": ("雾凇拼音 (默认)", "大词库, 8105 + 基础 + 扩展 + 腾讯 + 杂项合并, 2026-01-26", true),
    "cn_dicts/8105": ("通用规范汉字表 8105 字", "字表, 约 8.8k 字, 2026-08-16", true),
    "cn_dicts/41448": ("大字表 41448", "单字表, 约 46k 字 (含生僻字), 默认不并入主词库, 2026-07-01", true),
    "cn_dicts/base": ("基础词库", "常用词, 约 543k 条, 2026-11-01", true),
    "cn_dicts/ext": ("扩展词库", "三字以上词, 约 339k 条, 2026-11-01", true),
    "cn_dicts/tencent": ("腾讯词向量", "大词库, 约 982k 条, 无注音列 (读音靠字表自动注音), 单挂基本没候选, 2026-11-01", false),
    "cn_dicts/others": ("杂项", "容错读音等, 约 0.6k 条, 2026-08-08", true),
    "en_dicts/en": ("英文主词库", "约 21k 常见单词, 2026-10-01", false),
    "en_dicts/en_ext": ("英文补充", "缩写/网络词, 约 2.6k 条, 2026-10-29", false),
    "melt_eng": ("英文合并", "en + en_ext, 无自有词条, 2023-05-09", false),
    "radical_pinyin": ("部首拼音", "部件反查, 码带声调 (如 heng2), 约 132k 条, 2026.06.18", false),
  ]

  /// 补丁块的标记 (文件里只改这一段, 与模糊音块各管各的)。
  static let beginMarker = "# BEGIN hamster-layout-dictionary (布局词库管理, 请勿手动改这段)"
  static let endMarker = "# END hamster-layout-dictionary"

  // MARK: - 绑定读写 (事实来源是共享 UserDefaults)

  /// 当前绑定的词库 id (没设过就是默认 rime_ice)。
  public static func binding(for layout: Layout) -> String {
    switch layout {
    case .rimeIce: return UserDefaults.hamster.layoutDictionaryRimeIce
    case .t9: return UserDefaults.hamster.layoutDictionaryT9
    }
  }

  /// 生效的绑定: 存的值对应的文件还在才算, 文件没了 (删了导入的词库)
  /// 就回退默认, 避免部署时因找不到词库文件而失败。
  public static func effectiveBinding(for layout: Layout) -> String {
    let id = binding(for: layout)
    if id == defaultDictionaryId || dictionaryFileExists(id: id) {
      return id
    }
    return defaultDictionaryId
  }

  /// 改绑定: 存 UserDefaults + 立刻把补丁写进两个用户数据目录
  /// (沙盒 + App Group, 与 FuzzyPinyin.apply 同款);
  /// 仍要点「重新部署」才生效, 部署时还会按绑定重打一次。
  public static func setBinding(_ dictionaryId: String, for layout: Layout) {
    switch layout {
    case .rimeIce: UserDefaults.hamster.layoutDictionaryRimeIce = dictionaryId
    case .t9: UserDefaults.hamster.layoutDictionaryT9 = dictionaryId
    }
    do {
      try apply()
    } catch {
      Logger.statistics.error("layout dictionary patch error \(error.localizedDescription)")
    }
  }

  /// 上次部署时生效的绑定 (nil = 这功能上线前就部署过, 按现状算, 不删 prism)。
  public static func deployedBinding(for layout: Layout) -> String? {
    switch layout {
    case .rimeIce: return UserDefaults.hamster.deployedLayoutDictionaryRimeIce
    case .t9: return UserDefaults.hamster.deployedLayoutDictionaryT9
    }
  }

  public static func recordDeployedBinding(_ dictionaryId: String, for layout: Layout) {
    switch layout {
    case .rimeIce: UserDefaults.hamster.deployedLayoutDictionaryRimeIce = dictionaryId
    case .t9: UserDefaults.hamster.deployedLayoutDictionaryT9 = dictionaryId
    }
  }

  // MARK: - 扫描可选词库

  /// 运行时扫描用户数据目录里的 *.dict.yaml (沙盒优先,
  /// 沙盒里没有才看 App Group, 两边都取并去重)。
  /// 不写死成只能选自带的 11 个: 以后导入的自定义词库文件
  /// (.dict.yaml 放进 Rime 用户数据目录) 也会出现在列表里。
  /// 九宫格 (pinyinCapableOnly == true) 只列拼音词库。
  public static func availableDictionaries(pinyinCapableOnly: Bool) -> [DictionaryOption] {
    var found: [String: URL] = [:]
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      for (id, url) in scanDictionaries(in: dir) {
        if found[id] == nil {
          found[id] = url
        }
      }
    }
    var options = found.map { id, url in
      option(for: id, fileURL: url)
    }
    if pinyinCapableOnly {
      options = options.filter { $0.isPinyinCapable }
    }
    // 默认置顶, 其余按 id 排 (cn_dicts/* 在 en_dicts/* 前面,
    // 与 rime_ice.dict.yaml 的 import 顺序一致)。
    options.sort {
      if $0.id == defaultDictionaryId { return true }
      if $1.id == defaultDictionaryId { return false }
      return $0.id < $1.id
    }
    // 目录还没解压 (首次启动前) 时扫描为空, 至少给一个默认选项,
    // picker 不会空着; 部署后下次打开列表就全了。
    if options.isEmpty {
      let meta = bundledMetadata[defaultDictionaryId]!
      return [DictionaryOption(id: defaultDictionaryId, displayName: meta.displayName, detail: meta.detail, isPinyinCapable: meta.isPinyinCapable)]
    }
    return options
  }

  /// 列表里显示的名字 (找不到就原样显示 id, 不造名字)。
  public static func displayName(for dictionaryId: String) -> String {
    availableDictionaries(pinyinCapableOnly: false).first { $0.id == dictionaryId }?.displayName ?? dictionaryId
  }

  /// 扫描一个用户数据目录下的 *.dict.yaml,
  /// 返回 patch 值 (相对路径去 ".dict.yaml") -> 文件 URL。
  /// 跳过 build/ (编译输出目录, 不放词库源文件)。
  static func scanDictionaries(in dir: URL) -> [String: URL] {
    var result: [String: URL] = [:]
    guard let enumerator = FileManager.default.enumerator(
      at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return result }
    for case let fileURL as URL in enumerator {
      guard fileURL.lastPathComponent.hasSuffix(".dict.yaml") else { continue }
      let relative = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
      guard !relative.hasPrefix("build/") else { continue }
      let id = String(relative.dropSuffix(".dict.yaml"))
      result[id] = fileURL
    }
    return result
  }

  static func dictionaryFileExists(id: String) -> Bool {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      if FileManager.default.fileExists(atPath: dir.appendingPathComponent(id + ".dict.yaml").path) {
        return true
      }
    }
    return false
  }

  /// 自带的有现成说明; 自定义的读文件头的 name: 当名字,
  /// 没有就用相对路径, 并用抽样判断码是不是拼音。
  static func option(for id: String, fileURL: URL) -> DictionaryOption {
    if let meta = bundledMetadata[id] {
      return DictionaryOption(id: id, displayName: meta.displayName, detail: meta.detail, isPinyinCapable: meta.isPinyinCapable)
    }
    let headerName = dictionaryHeaderName(fileURL: fileURL)
    return DictionaryOption(
      id: id,
      displayName: headerName ?? id,
      detail: "自定义词库",
      isPinyinCapable: sniffPinyinCapable(fileURL: fileURL)
    )
  }

  /// 读 dict 文件头的 name: 字段 (如 name: mydict)。
  static func dictionaryHeaderName(fileURL: URL) -> String? {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
    for line in content.components(separatedBy: .newlines).prefix(40) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("name:") {
        let name = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if !name.isEmpty {
          return name
        }
      }
      if trimmed == "..." { break }
    }
    return nil
  }

  /// 抽样判断词库码是不是拼音: 取 "..." 之后的词条行, 在全文件里
  /// 等距抽最多 300 行, 要求 >=80% 的码全由小写字母+空格组成,
  /// 且抽样里至少出现一个无歧义常用拼音音节。只用小写字母不够:
  /// 英文词库的码也是小写字母 (hello/the), 所以要加音节探针
  /// (de/shi/ni/hao/zhong/guo/ren/wo/ta/zhe/jiu/kan 都不是
  /// 常见英文单词); 带声调的码 (heng2) 直接因含数字被排除。
  /// 大文件 (>20MB, 如腾讯词向量) 不读, 按"不是拼音"算——
  /// 自带的都在 bundledMetadata 里, 不走这条路。
  static func sniffPinyinCapable(fileURL: URL) -> Bool {
    guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue,
          size < 20 * 1024 * 1024,
          let content = try? String(contentsOf: fileURL, encoding: .utf8)
    else { return false }
    let lines = content.components(separatedBy: .newlines)
    guard let bodyStart = lines.firstIndex(where: { $0 == "..." }),
          bodyStart + 1 < lines.count else { return false }
    let entries = lines[(bodyStart + 1)...].filter { line in
      !line.isEmpty && !line.hasPrefix("#") && line.contains("\t")
    }
    guard !entries.isEmpty else { return false }
    let sampleCount = min(300, entries.count)
    let step = max(1, entries.count / sampleCount)
    var checked = 0
    var pinyinLike = 0
    var sawProbeSyllable = false
    let probeSyllables: Set<String> = ["de", "shi", "ni", "hao", "zhong", "guo", "ren", "wo", "ta", "zhe", "jiu", "kan"]
    var index = 0
    while index < entries.count && checked < sampleCount {
      let fields = entries[index].components(separatedBy: "\t")
      if fields.count >= 2 {
        let code = fields[1].trimmingCharacters(in: .whitespaces)
        checked += 1
        let tokens = code.split(separator: " ")
        if !tokens.isEmpty, tokens.allSatisfy({ $0.allSatisfy { $0.isLowercase && $0.isLetter } }) {
          pinyinLike += 1
          if tokens.contains(where: { probeSyllables.contains(String($0)) }) {
            sawProbeSyllable = true
          }
        }
      }
      index += step
    }
    guard checked > 0 else { return false }
    return sawProbeSyllable && Double(pinyinLike) / Double(checked) >= 0.8
  }

  // MARK: - 打补丁 (与 FuzzyPinyin 同款 marker-block 写法)

  /// 按当前绑定把补丁打进两个用户数据目录 (沙盒 + App Group)。
  /// 绑默认时只删本块 (不写 translator/dictionary, 走方案自带的);
  /// 文件内容没变就不重写 (不碰 mtime, 免得下次部署误判配置变了)。
  public static func apply() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      for layout in Layout.allCases {
        try apply(to: dir.appendingPathComponent(layout.customFileName), dictionaryId: effectiveBinding(for: layout))
      }
    }
  }

  /// 更新单个 custom.yaml 文件。
  static func apply(to fileURL: URL, dictionaryId: String) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    let updated = insertingDictionaryBlock(into: removingDictionaryBlock(from: content), dictionaryId: dictionaryId)
    if updated == content {
      return
    }
    if updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? FileManager.default.removeItem(at: fileURL)
      return
    }
    try updated.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static func fullBlock(dictionaryId: String) -> String {
    [beginMarker, "patch:", "  translator/dictionary: \(dictionaryId)", endMarker]
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static func nestedBlock(dictionaryId: String) -> String {
    [("  " + beginMarker), "  translator/dictionary: \(dictionaryId)", ("  " + endMarker)]
      .joined(separator: "\n")
  }

  /// 删掉本块 (BEGIN 行到 END 行, 含两行本身); 没有本块时原样返回。
  /// 例外: 块里嵌着模糊音块时 (见文件头注释, 只发生在用户先绑词库、
  /// 再去 RIME 页开模糊音开关的瞬间), 把模糊音块原样保留并还挂在
  /// patch: 下面——本块是 full block 时 patch: 行在本块里, 要留一行
  /// patch: 给它; 本块是 nested 时 patch: 行本来就在块外, 不用留。
  /// 这样删词库绑定永远不会把模糊音补丁一起删掉; 下次部署时
  /// FuzzyPinyin.apply 会先把模糊音块摘出来重打, 本块再按绑定重打,
  /// 两块回到并排的正常形态 (自愈)。
  static func removingDictionaryBlock(from content: String) -> String {
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
    if let fuzzyBegin = inner.firstIndex(where: { $0.contains(FuzzyPinyin.beginMarker) }),
       let fuzzyEnd = inner.firstIndex(where: { $0.contains(FuzzyPinyin.endMarker) }),
       fuzzyBegin <= fuzzyEnd {
      foreign = Array(inner[fuzzyBegin...fuzzyEnd])
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

  /// 插入本块: 绑默认时不插 (调用方先调 removingDictionaryBlock 删过,
  /// 这里直接返回删完的内容); 否则文件里已有 patch: 顶级键时挂在
  /// patch: 映射的末尾、模糊音块的 END 行之后, 两块是 patch: 下面的
  /// 兄弟关系, 互不嵌套; 模糊音块是 full block 形态 (BEGIN 行在
  /// patch: 行正上方) 时先把它改成 nested 形态再插 (见函数内注释)。
  /// 没有 patch: 键时在文件末尾追加完整的 patch: 块。
  static func insertingDictionaryBlock(into content: String, dictionaryId: String) -> String {
    guard dictionaryId != defaultDictionaryId else { return content }
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullBlock(dictionaryId: dictionaryId) + "\n"
    }
    var lines = content.components(separatedBy: .newlines)
    // 顶级 patch: 键 (行首无缩进; 带行内注释的也算, flow 写法除外, 这里不会出现)。
    if var patchIndex = lines.firstIndex(where: { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }) {
      // 模糊音块是 full block 形态时 (它的 BEGIN 行在 patch: 行正上方,
      // patch: 被包在它的标记里), 先把它改成 nested 形态
      // (BEGIN 行缩进 2 格挪到 patch: 下面, END 行若在行首也缩进
      // 2 格): 否则本块插到它 END 行之后仍在它标记范围内,
      // 下次关模糊音会连本块一起删掉。
      // 只挪注释行, 模糊音内容与标记本身不动; FuzzyPinyin
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
      // 插到 patch: 映射的末尾: 最后一个缩进行之后, 但不能越过
      // 模糊音块的 END 行——END 行本身也是缩进的, 越过它就插进了
      // 模糊音块的标记范围里 (关模糊音会连本块一起删); 停在
      // END 行之后一位, 两块就是 patch: 下面的兄弟关系。
      // END 行即使因手写文件在行首, 也要越过它再停 (它只是注释行)。
      var insertAt = patchIndex + 1
      while insertAt < lines.count {
        if lines[insertAt].contains(FuzzyPinyin.endMarker) {
          insertAt += 1
          break
        }
        if lines[insertAt].isEmpty || lines[insertAt].hasPrefix(" ") || lines[insertAt].hasPrefix("\t") {
          insertAt += 1
        } else {
          break
        }
      }
      lines.insert(contentsOf: nestedBlock(dictionaryId: dictionaryId).components(separatedBy: .newlines), at: insertAt)
      return lines.joined(separator: "\n")
    }
    var result = content
    if !result.hasSuffix("\n") { result += "\n" }
    result += "\n" + fullBlock(dictionaryId: dictionaryId) + "\n"
    return result
  }
}

private extension String {
  func dropSuffix(_ suffix: String) -> String {
    hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }
}
