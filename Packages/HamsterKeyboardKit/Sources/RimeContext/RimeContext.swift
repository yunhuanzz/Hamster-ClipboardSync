//
//  RimeContext.swift
//
//
//  Created by morse on 2023/6/30.
//

import Combine
import Foundation
import HamsterKit
import OSLog
import RimeKit

/// RIME 运行时上下文
public class RimeContext {
  /// 最大候选词数量
  public private(set) lazy var maximumNumberOfCandidateWords: Int = 100

  /// 是否使用 IRimeContext 中分页信息
  public private(set) lazy var useContextPaging = false

  /// rime 输入方案列表
  public private(set) lazy var schemas: [RimeSchema] = UserDefaults.hamster.schemas {
    didSet {
      UserDefaults.hamster.schemas = self.schemas
    }
  }

  /// rime 用户选择方案列表
  public lazy var selectSchemas: [RimeSchema] = UserDefaults.hamster.selectSchemas {
    didSet {
      UserDefaults.hamster.selectSchemas = self.selectSchemas.sorted()
    }
  }

  /// 当前输入方案
  public lazy var currentSchema: RimeSchema? = UserDefaults.hamster.currentSchema {
    didSet {
      // 注意：如果没有完全访问权限，UserDefaults.hamster 会保存失败
      UserDefaults.hamster.currentSchema = currentSchema
    }
  }

  /// 上次使用输入方案
  public lazy var latestSchema: RimeSchema? = UserDefaults.hamster.latestSchema {
    didSet {
      UserDefaults.hamster.currentSchema = currentSchema
    }
  }

  /// 用户输入键值
  public var userInputKey: String = "" {
    didSet {
      userInputKeySubject.send(userInputKey)
    }
  }

  private let userInputKeySubject = PassthroughSubject<String, Never>()
  public var userInputKeyPublished: AnyPublisher<String, Never> {
    userInputKeySubject.eraseToAnyPublisher()
  }

  /// 待上屏文字
  public private(set) lazy var commitText: String = ""

  /// T9拼音，将用户T9拼音输入还原为正常的拼音
  @MainActor
  public var t9UserInputKey: String {
    var preview = rimeContext?.composition.preedit ?? ""
    if let highlightIndex = rimeContext?.menu.highlightedCandidateIndex,
       let candidates = rimeContext?.menu.candidates,
       highlightIndex < candidates.count
    {
      let candidate = candidates[Int(highlightIndex)]
      preview = preview.t9pinyinToPinyin(comment: candidate.comment ?? "")
    }
    return preview.replaceT9pinyin
  }

  /// rime option 选项对应的值的缓存
  private var optionValueCache: [String: [Bool: String]] = [:]

  /// flushUserDictionary() 的重入守卫 (落盘键本身不触发 syncContext,
  /// 这里只是防御未来 processor 变化导致递归)。
  private var isFlushingUserDictionary = false

  /// 用户选择的候选拼音
  /// 注意：只保存最近一次选择的拼音和拼音开始位置及长度
  public lazy var selectCandidatePinyin: (String, Int, Int)? = nil

  /// 字母模式
  @MainActor
  public lazy var asciiMode: Bool = false

  /// 候选字
  @MainActor @Published
  public var suggestions: [CandidateSuggestion] = []

  /// 前缀候选模式: 引擎对完整九宫格输入给不出候选时, 展示最长合法前缀的候选。
  /// (用户乱按的长串常常整体切不全, 但前半段是合法音节; 微信会给前缀候选,
  /// 我们之前只显示一串字母。) 引擎输入始终保持完整串, 只有候选列表来自前缀;
  /// 选词时先把引擎换回前缀再选, 选完把尾巴数字重新敲回去。
  /// 为 true 时, suggestions 属于 prefixCandidateInput, 不是完整输入。
  @MainActor
  var isShowingPrefixCandidates = false

  /// 前缀候选对应的输入 (最长合法前缀, 全数字串)。
  @MainActor
  private var prefixCandidateInput = ""

  /// 前缀之后的尾巴数字 (选词后要重新敲回引擎的新输入)。
  @MainActor
  private var prefixCandidateTail = ""

  /// 展示前缀候选时引擎里实际的完整输入 (全数字串)。
  @MainActor
  private var prefixCandidateFullInput = ""

  /// 最近一次提交 (第 14 轮第 5 项 a): (提交时的原始输入码, 提交的文字)。
  /// 仅在“刚提交、还没输别的”期间有效; 退格删掉这段文字时用来撤销学习。
  @MainActor
  public var lastCommit: (code: String, text: String)?

  /// 本次引擎操作开始前的原始输入码 (提交归属用): tryHandleInputText /
  /// tryHandleInputCode / selectCandidate 在调引擎前快照, syncContext 在
  /// 出现 commitText 时把它和文字一起记进 lastCommit。
  @MainActor
  private var pendingCommitCode = ""

  @MainActor @Published
  public var rimeContext: IRimeContext? = nil

  /// rime option
  @MainActor @Published
  public var optionState: String? = nil

  /// 划动分页模式下，当前页码，从 0 开始
  public lazy var pageIndex: Int = 0

  /// 根据页码计算首个候选文字索引
  public var candidateIndex: Int {
    pageIndex * maximumNumberOfCandidateWords
  }

  /// switcher hotkeys
  /// 默认值为 F4，但 RIME 重新部署时会根据当前配置加载此值
  public lazy var hotKeys = UserDefaults.hamster.hotKeys {
    didSet {
      UserDefaults.hamster.hotKeys = hotKeys
    }
  }

  public init() {}

  func setMaximumNumberOfCandidateWords(_ count: Int) {
    self.maximumNumberOfCandidateWords = count
  }

  func setUseContextPaging(_ state: Bool) {
    self.useContextPaging = state
  }
}

// MARK: methods

public extension RimeContext {
  /// RIME Context 状态重置
  @MainActor
  func reset() {
    self.pageIndex = 0
    self.userInputKey = ""
    self.selectCandidatePinyin = nil
    self.suggestions.removeAll(keepingCapacity: false)
    self.isShowingPrefixCandidates = false
    self.prefixCandidateInput = ""
    self.prefixCandidateTail = ""
    self.prefixCandidateFullInput = ""
    Rime.shared.cleanComposition()
  }

  func resetCommitText() {
    self.commitText = ""
  }

  /// 选择输入方案后重置当前输入方案
  /// 注意：仅限内部调用
  private func resetCurrentSchema() {
    // 默认当前方案为输入方案中的第一个输入方案
    // 注意：当前方案可能为空，所以不能用 contains() 判断
    let firstInputSchema = selectSchemas.first { self.currentSchema == $0 }
    if firstInputSchema == nil, !selectSchemas.isEmpty {
      self.currentSchema = selectSchemas[0]
    }
    Logger.statistics.debug("current schema: \(self.currentSchema?.schemaId ?? "") \(self.currentSchema?.schemaName ?? "")")
  }

  /// 选择输入方案后重置
  /// 注意：仅限内部调用
  private func resetLatestSchema() {
    // 默认最近一个输入方案为方案输入列表中的第二位
    let schemas = selectSchemas
      .filter { $0.schemaId != self.currentSchema?.schemaId }

    if self.latestSchema == nil, !schemas.isEmpty {
      self.latestSchema = schemas[0]
    } else if let latestSchema = self.latestSchema, !schemas.contains(latestSchema) {
      self.latestSchema = schemas.isEmpty ? nil : schemas[0]
    }
    Logger.statistics.debug("latest schema: \(self.latestSchema?.schemaId ?? "") \(self.latestSchema?.schemaName ?? "")")
  }

  func appendSelectSchema(_ schema: RimeSchema) {
    self.selectSchemas.append(schema)
    self.selectSchemas.sort()
    resetCurrentSchema()
    resetLatestSchema()
  }

  func removeSelectSchema(_ schema: RimeSchema) {
    self.selectSchemas.removeAll(where: { $0 == schema })
    self.selectSchemas.sort()
    resetCurrentSchema()
    resetLatestSchema()
  }

  func setCurrentSchema(_ schema: RimeSchema?) {
    self.latestSchema = self.currentSchema
    self.currentSchema = schema
  }

  @MainActor
  func setAsciiMode(_ model: Bool) {
    self.asciiMode = model
  }

  /// RIME 启动
  /// 注意：仅用于键盘扩展调用
  func start(hasFullAccess: Bool) async {
    Rime.shared.setNotificationDelegate(self)

    // 启动
    Rime.shared.start(Rime.createTraits(
      sharedSupportDir: FileManager.appGroupSharedSupportDirectoryURL.path,
      userDataDir: hasFullAccess ? FileManager.appGroupUserDataDirectoryURL.path : FileManager.sandboxUserDataDirectory.path
    ))

    // 设置初始输入方案
    setupRimeInputSchema()

    // 中英状态同步
    await setAsciiMode(Rime.shared.isAsciiMode())
  }

  /// RIME 关闭
  /// 注意：仅用于键盘扩展调用
  func shutdown() {
    // 先落盘: 否则最后一次提交的学习还只在内存事务里, 随 session 一起丢掉
    // (第 12 轮第 1 项)。
    flushUserDictionary()
    Rime.shared.shutdown()
  }

  /// 把待提交的用户词典学习落盘 (第 12 轮第 1 项)。
  ///
  /// 根因 (librime 1.8.5 源码 + 活验证):
  /// 选词提交只把学习写进一个打开的 LevelDB 事务 (内存里的 WriteBatch),
  /// 真正写盘要等下一次翻译 Query 开头的 Memory::FinishSession()
  /// (script_translator.cc:184) 或一个未处理按键的 OnUnhandledKey。
  /// iOS 键盘扩展随时会被系统杀掉; 如果提交是被杀前的最后一个引擎动作,
  /// 这次学习就全丢——实测: 无后续按键直接退出进程, 再打同一串数字,
  /// 首选仍是旧句子, 磁盘上的 rime_ice.userdb 里没有新词条;
  /// 而提交后多按一次键再退出, 新进程里该词组直接排第一。
  /// 所以每次观测到提交就立刻发一个引擎不认的键 (F24, 没有任何
  /// processor/key_binder 认领它, 也不像裸 Shift 那样会留一个 500ms
  /// 的中英切换窗口), 让它走到 OnUnhandledKey → FinishSession →
  /// CommitTransaction, 学习当场写盘。无待提交事务时
  /// CommitPendingTransaction 直接返回 false, 开销可忽略。
  /// 注意: 不能用 RimeSyncUserData() 来落盘——它先 CleanupAllSessions
  /// 销毁 session/引擎, 待提交事务随引擎一起丢掉, 反而丢学习。
  func flushUserDictionary() {
    guard isRunning, !isFlushingUserDictionary else { return }
    isFlushingUserDictionary = true
    _ = Rime.shared.inputKeyCode(XK_F24)
    isFlushingUserDictionary = false
  }

  /// RIME 部署
  /// 注意：仅可用于主 App 调用
  func deployment(configuration: inout HamsterConfiguration) throws {
    // 如果开启 iCloud，则先将 iCloud 下文件增量复制到 Sandbox
    if let enableAppleCloud = configuration.general?.enableAppleCloud, enableAppleCloud == true {
      let regex = configuration.general?.regexOnCopyFile ?? []
      do {
        try FileManager.copyAppleCloudSharedSupportDirectoryToSandbox(regex)
        try FileManager.copyAppleCloudUserDataDirectoryToSandbox(regex)
      } catch {
        Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
        throw error
      }
    }

    // 自定义词组 (custom_phrase.txt / custom_phrase_t9.txt) 永远保留:
    // 部署前先从 App Group 拷回沙盒, 不受 overrideDictFiles 影响,
    // 否则用户在"我的词组"里加的词会被部署覆盖。
    // 文件不存在时 copyAppGroupUserDict 是空操作, 不会抛错。
    do {
      try FileManager.copyAppGroupUserDict(["custom_phrase[.]txt$", "custom_phrase_t9[.]txt$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 用户词典学习成果 (*.userdb) 永远保留, 不受 overrideDictFiles 影响:
    // userdb 是运行时学出来的数据 (选词加权、造词), 不是随方案下发的词库文件,
    // 部署时拿沙盒里的空库把它盖掉, 就是“越用越准”失效的根因。
    // (之前只在 overrideDictFiles == false 时拷回; 已装配置里的这个值
    // 是旧默认值 true, 所以学习成果每次部署都被清空。)
    do {
      try FileManager.copyAppGroupUserDict(["^.*[.]userdb.*$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 模糊音补丁文件 (rime_ice.custom.yaml / t9.custom.yaml) 永远保留,
    // 不受 overrideDictFiles 影响 (不然开关一开、下次部署就把补丁丢了)。
    do {
      try FileManager.copyAppGroupUserDict(["rime_ice[.]custom[.]yaml$", "t9[.]custom[.]yaml$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 判断是否需要覆盖键盘词库文件，如果为否，则先copy键盘词库文件至应用目录
    // 注意: 这里只管用户导入的 .txt 词库文件, userdb 与“我的词组”
    // 已在上面无条件拷回, 不再受这个开关影响。
    if let overrideDictFiles = configuration.rime?.overrideDictFiles, overrideDictFiles == false {
      let regex = configuration.rime?.regexOnOverrideDictFiles ?? []
      do {
        try FileManager.copyAppGroupUserDict(regex)
      } catch {
        Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
        throw error
      }
    }

    // 检测文件目录是否存在不存在，新建
    try FileManager.createDirectory(override: false, dst: FileManager.sandboxSharedSupportDirectory)
    try FileManager.createDirectory(override: false, dst: FileManager.sandboxUserDataDirectory)

    // 模糊音: 按开关把补丁打进用户数据目录 (文件丢了也能在这里恢复;
    // 开关关着时这里会把补丁去掉)。失败不阻断部署, 只记日志, 下次部署再试。
    do {
      try FuzzyPinyin.apply(enabled: UserDefaults.hamster.fuzzyPinyinEnabled)
    } catch {
      Logger.statistics.error("RIME deploy fuzzy pinyin patch error \(error.localizedDescription)")
    }

    // 每布局词库 (第 10 轮第 7 条): 按绑定把 translator/dictionary
    // 补丁打进 rime_ice.custom.yaml / t9.custom.yaml (理由同模糊音)。
    // 绑定变了就删对应方案的 prism, 强制重建——librime 的
    // dict_file_checksum 本来也会因词库文件集变化而触发重建,
    // 这里是双保险, 与下面新补方案删 prism 的做法一致;
    // 没变时不删, 避免每次部署都重编大词库。
    // 注意 prism 文件名按方案 id 取 <schemaId>.prism.bin
    // (t9 的 translator/prism: t9; rime_ice 默认用词库名,
    // 绑默认 rime_ice 时就是 rime_ice.prism.bin);
    // 绑到 cn_dicts/* 时新词库的 prism 文件本来就不存在,
    // checksum 重建路径会编它, 这里删旧文件只是顺手清理。
    do {
      try LayoutDictionary.apply()
      for layout in LayoutDictionary.Layout.allCases {
        let current = LayoutDictionary.effectiveBinding(for: layout)
        if let deployed = LayoutDictionary.deployedBinding(for: layout) {
          if deployed != current {
            for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
              let prism = dir.appendingPathComponent("\(layout.rawValue).prism.bin")
              if FileManager.default.fileExists(atPath: prism.path) {
                try? FileManager.default.removeItem(at: prism)
                Logger.statistics.info("rime deploy: 词库绑定变化 (\(layout.rawValue): \(deployed) -> \(current)), 删除残留 prism \(prism.path), 强制重建")
              }
            }
            LayoutDictionary.recordDeployedBinding(current, for: layout)
          }
        } else {
          LayoutDictionary.recordDeployedBinding(current, for: layout)
        }
      }
    } catch {
      Logger.statistics.error("RIME deploy layout dictionary patch error \(error.localizedDescription)")
    }

    // 九宫格首字母拼写 (第 13 轮第 3 项 a 小点): 把 11 个常用音节的
    // 首字母形式以 derive 规则打进 t9.custom.yaml (常开, 只写 t9)。
    // 不写成 abbrev——abbrev 派生是 kAbbreviation 类型, 查询时
    // syllabifier 只要见到全普通拼写的切分就把它剪掉, 4263 就永远
    // 出不了“好的”; derive 保持普通类型, 活验证 4263 好的 #1。
    // 失败不阻断部署, 只记日志, 下次部署再试。
    do {
      try T9SyllableInitials.apply()
    } catch {
      Logger.statistics.error("RIME deploy t9 syllable initials patch error \(error.localizedDescription)")
    }

    if !isRunning {
      Rime.shared.start(Rime.createTraits(
        sharedSupportDir: FileManager.sandboxSharedSupportDirectory.path,
        userDataDir: FileManager.sandboxUserDataDirectory.path
      ), maintenance: true, fullCheck: true)
    }
    // 此 API 根据用户配置的 scheme_list 参数获取列表，当方案不提供 schema_list 参数时，获取为空
    var schemas = Rime.shared.getSchemas().sorted()
    if schemas.isEmpty {
      // 检测 default.custom.yaml 文件是否存在，后面解析 schema_list 需要存在此文件
      let defaultCustomFilePath = FileManager.sandboxUserDataDefaultCustomYaml.path
      var createDefaultCustomFileHandle = false
      if !FileManager.default.fileExists(atPath: defaultCustomFilePath) {
        let handled = FileManager.default.createFile(atPath: defaultCustomFilePath, contents: nil)
        Logger.statistics.debug("create file \(defaultCustomFilePath), handled: \(handled)")
        createDefaultCustomFileHandle = handled
      }

      // 此 API 可获取全部方案列表，不经过 schema_list 参数
      schemas = Rime.shared.getAvailableRimeSchemas().sorted()
      // 只有新建 default.custom.yaml 文件才会写 schema_list 参数，方案如果已存在则不写，因为复写文件会导致文件中的注释信息丢失。
      if createDefaultCustomFileHandle {
        let result = Rime.shared.selectRimeSchemas(schemas.map { $0.schemaId })
        if !result {
          Logger.statistics.warning("rime set select rime schemas false")
        } else {
          // 写完 schema_list 参数后需要重新编译方案词库文件
          Rime.shared.shutdown()
          Rime.shared.start(Rime.createTraits(
            sharedSupportDir: FileManager.sandboxSharedSupportDirectory.path,
            userDataDir: FileManager.sandboxUserDataDirectory.path
          ), maintenance: true, fullCheck: true)
        }
      }
    }

    // 九宫格修复 (第 10 轮, 补第 9 轮的漏洞): 部署器 (librime UpdateSchemas)
    // 只给 schema_list (default.custom.yaml) 里的方案编译词库/prism,
    // 而 App 里的方案勾选 (selectSchemas) 从不写 schema_list。
    // 第 9 轮只把"已选且存在"的方案并进 schema_list, 但 selectSchemas
    // 默认只有 rime_ice (首次启动写死, SettingsViewModel), 用户只有在
    // 输入方案页亲手勾了 t9 才会进 selectSchemas; 他若从未勾过, t9
    // 就进不了 schema_list, t9.prism.bin 仍不编译 → 数字继续零候选
    // (build #28 现状: 词库"编出来了"只是 rime_ice 的, 手动选边栏
    // 音节走字母能出字, 数字直输仍为空)。
    // 改成: 把"全部存在"的方案并进 schema_list (只加不减) —— 键盘
    // 运行时能切到任一存在方案 (setSchema 不查 schema_list), 所以
    // 每个存在方案都必须编好 prism; 这也是首次部署本来的行为。
    // 另外: 新补进来的方案先删掉可能残留的旧 prism (librime 的
    // checksum 机制会复用"看起来没变"的旧文件, 坏的 prism 会被一直
    // 沿用), 强制干净重建; 部署后逐个核对 prism 是否存在并记日志
    // (下次出问题先看这行日志, 不用再猜)。
    // 注意: prism 文件名按 bundled 方案取 <schemaId>.prism.bin
    // (t9 的 translator/prism: t9, rime_ice 默认用词库名, 都与
    // schemaId 一致); 自定义方案若在 translator 里另设 prism 名,
    // 这里删不到它, 但 checksum 重建路径仍对它生效。
    do {
      let availableIDs = Set(Rime.shared.getAvailableRimeSchemas().map { $0.schemaId })
      let listedIDs = Set(schemas.map { $0.schemaId })
      let missingIDs = availableIDs.subtracting(listedIDs)
      if !missingIDs.isEmpty {
        let mergedIDs = listedIDs.union(availableIDs).sorted()
        if Rime.shared.selectRimeSchemas(mergedIDs) {
          Logger.statistics.info("rime deploy: scheme_list 缺方案 \(missingIDs), 已补齐并重新编译")
          for schemaId in missingIDs {
            for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
              let prism = dir.appendingPathComponent("\(schemaId).prism.bin")
              if FileManager.default.fileExists(atPath: prism.path) {
                try? FileManager.default.removeItem(at: prism)
                Logger.statistics.info("rime deploy: 删除残留 prism \(prism.path), 强制重建")
              }
            }
          }
          Rime.shared.shutdown()
          Rime.shared.start(Rime.createTraits(
            sharedSupportDir: FileManager.sandboxSharedSupportDirectory.path,
            userDataDir: FileManager.sandboxUserDataDirectory.path
          ), maintenance: true, fullCheck: true)
          schemas = Rime.shared.getSchemas().sorted()
        } else {
          Logger.statistics.warning("rime deploy: scheme_list 补齐失败: \(missingIDs)")
        }
      }
      for schema in schemas {
        let prism = FileManager.sandboxUserDataDirectory.appendingPathComponent("\(schema.schemaId).prism.bin")
        Logger.statistics.info("rime deploy: prism \(schema.schemaId): \(FileManager.default.fileExists(atPath: prism.path) ? "存在" : "缺失")")
      }
    }

    // 提前在部署阶段加载 RimeSwitch hotKey, 此步骤放在键盘启动阶段会减慢启动速度
    // 加载Switcher切换键
    let hotKeys = Rime.shared.getHotkeys()
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    if !hotKeys.isEmpty {
      self.hotKeys = hotKeys
    }
    Logger.statistics.info("rime switcher hotkeys: \(hotKeys)")

    Rime.shared.shutdown()

    // 当用户选择输入方案如果不为空时，则取与输入方案列表的交集
    var selectSchemas = self.selectSchemas
    if !selectSchemas.isEmpty {
      // 取交集
      let intersection = Set(schemas).intersection(selectSchemas)
      if !intersection.isEmpty {
        selectSchemas = Array(intersection).sorted()
      } else {
        if !schemas.isEmpty {
          selectSchemas = [schemas[0]]
        }
      }
    } else {
      if !schemas.isEmpty {
        selectSchemas = [schemas[0]]
      }
    }

    self.schemas = schemas
    self.selectSchemas = selectSchemas
    resetCurrentSchema()
    resetLatestSchema()

    configuration = try HamsterConfigurationRepositories.shared.loadConfiguration()

    // 键盘重新同步文件标志
    UserDefaults.hamster.overrideRimeDirectory = true

    // 保存配置至 build/hamster.yaml
    // try? HamsterConfigurationRepositories.shared.saveToYAML(config: configuration, path: FileManager.hamsterConfigFileOnBuild)
//    try? HamsterConfigurationRepositories.shared.saveToJSON(
//      config: configuration,
//      path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.json")
//    )
    try? HamsterConfigurationRepositories.shared.saveToPropertyList(
      config: configuration,
      path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.plist")
    )

    // 将 Sandbox 目录下方案复制到AppGroup下
    try FileManager.syncSandboxSharedSupportDirectoryToAppGroup()
    try FileManager.syncSandboxUserDataDirectoryToAppGroup()
  }

  /// RIME 同步
  /// 注意：仅可用于主 App 调用
  func syncRime(configuration: HamsterConfiguration) throws {
    // 检测文件目录是否存在不存在，新建
    try FileManager.createDirectory(override: false, dst: FileManager.sandboxSharedSupportDirectory)
    try FileManager.createDirectory(override: false, dst: FileManager.sandboxUserDataDirectory)

    // 自定义词组 (custom_phrase.txt / custom_phrase_t9.txt) 永远保留,
    // 不受 overrideDictFiles 影响。
    // 文件不存在时 copyAppGroupUserDict 是空操作, 不会抛错。
    do {
      try FileManager.copyAppGroupUserDict(["custom_phrase[.]txt$", "custom_phrase_t9[.]txt$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 用户词典学习成果 (*.userdb) 永远保留, 不受 overrideDictFiles 影响
    // (理由同 deployment: userdb 是学出来的数据, 不是下发的词库文件)。
    do {
      try FileManager.copyAppGroupUserDict(["^.*[.]userdb.*$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 模糊音补丁文件 (rime_ice.custom.yaml / t9.custom.yaml) 永远保留,
    // 不受 overrideDictFiles 影响。
    do {
      try FileManager.copyAppGroupUserDict(["rime_ice[.]custom[.]yaml$", "t9[.]custom[.]yaml$"])
    } catch {
      Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
      throw error
    }

    // 判断是否需要覆盖键盘词库文件，如果为否，则先copy键盘词库文件至应用目录
    // 注意: 这里只管用户导入的 .txt 词库文件, userdb 与“我的词组”
    // 已在上面无条件拷回, 不再受这个开关影响。
    if let overrideDictFiles = configuration.rime?.overrideDictFiles, overrideDictFiles == false {
      let regex = configuration.rime?.regexOnOverrideDictFiles ?? []
      do {
        try FileManager.copyAppGroupUserDict(regex)
      } catch {
        Logger.statistics.error("RIME deploy error \(error.localizedDescription)")
        throw error
      }
    }

    // 模糊音: 按开关把补丁打进用户数据目录 (理由同 deployment)。
    // 失败不阻断同步, 只记日志, 下次部署再试。
    do {
      try FuzzyPinyin.apply(enabled: UserDefaults.hamster.fuzzyPinyinEnabled)
    } catch {
      Logger.statistics.error("RIME sync fuzzy pinyin patch error \(error.localizedDescription)")
    }

    // 每布局词库 (第 10 轮第 7 条): 按绑定重打补丁 (理由同模糊音)。
    // 同步本身不编译词库, 换词库仍要点「重新部署」才生效。
    do {
      try LayoutDictionary.apply()
    } catch {
      Logger.statistics.error("RIME sync layout dictionary patch error \(error.localizedDescription)")
    }

    // 九宫格首字母拼写 (第 13 轮第 3 项 a 小点, 理由同 deployment)。
    // 失败不阻断同步, 只记日志, 下次部署再试。
    do {
      try T9SyllableInitials.apply()
    } catch {
      Logger.statistics.error("RIME sync t9 syllable initials patch error \(error.localizedDescription)")
    }

    if !isRunning {
      Rime.shared.start(Rime.createTraits(
        sharedSupportDir: FileManager.sandboxSharedSupportDirectory.path,
        userDataDir: FileManager.sandboxUserDataDirectory.path
      ), maintenance: true, fullCheck: true)
    }
    let handled = Rime.shared.API().syncUserData()
    Logger.statistics.info("RIME sync userData handled: \(handled)")
    Rime.shared.shutdown()

    // 键盘重新同步文件标志
    UserDefaults.hamster.overrideRimeDirectory = true

    // 保存配置至 build/hamster.yaml
    // try? HamsterConfigurationRepositories.shared.saveToYAML(config: configuration, path: FileManager.hamsterConfigFileOnBuild)
//    try? HamsterConfigurationRepositories.shared.saveToJSON(
//      config: configuration,
//      path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.json")
//    )
    try? HamsterConfigurationRepositories.shared.saveToPropertyList(
      config: configuration,
      path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.plist")
    )

    // 将 Sandbox 目录下方案复制到AppGroup下
    try FileManager.syncSandboxSharedSupportDirectoryToAppGroup()
    try FileManager.syncSandboxUserDataDirectoryToAppGroup()
  }

  /// RIME 重置
  /// 注意：仅可用于主 App 调用
  func restRime() throws {
    // 重置输入方案目录
    do {
      try FileManager.initSandboxSharedSupportDirectory(override: true)
      try FileManager.initSandboxUserDataDirectory(override: true, unzip: true)
    } catch {
      Logger.statistics.error("rime init file directory error: \(error.localizedDescription)")
      throw error
    }

    Rime.shared.shutdown()
    Rime.shared.start(Rime.createTraits(
      sharedSupportDir: FileManager.sandboxSharedSupportDirectory.path,
      userDataDir: FileManager.sandboxUserDataDirectory.path
    ), maintenance: true, fullCheck: true)

    let schemas = Rime.shared.getSchemas().sorted()

    Rime.shared.shutdown()

    // 当用户选择输入方案如果不为空时，则取与输入方案列表的交集
    var selectSchemas = self.selectSchemas
    if !selectSchemas.isEmpty {
      // 取交集
      let intersection = Set(schemas).intersection(selectSchemas)
      if !intersection.isEmpty {
        selectSchemas = Array(intersection).sorted()
      } else {
        if !schemas.isEmpty {
          selectSchemas = [schemas[0]]
        }
      }
    } else {
      if !schemas.isEmpty {
        selectSchemas = [schemas[0]]
      }
    }

    /// 切换 Main 线程 修改 @MainActor 标记的属性值
    if !schemas.isEmpty {
      self.schemas = schemas
      self.selectSchemas = selectSchemas
      resetCurrentSchema()
      resetLatestSchema()
    }

    // 键盘重新同步文件标志
    UserDefaults.hamster.overrideRimeDirectory = true

    // 模糊音: 重置清空了沙盒用户数据目录, 按开关把补丁打回来,
    // 否则下面沙盒 -> App Group 的同步会把 App Group 里的补丁也删掉。
    // (重置本身是有意的: 用户词典学习成果这次会被清空, 从下次部署起重新学习。)
    do {
      try FuzzyPinyin.apply(enabled: UserDefaults.hamster.fuzzyPinyinEnabled)
    } catch {
      Logger.statistics.error("RIME reset fuzzy pinyin patch error \(error.localizedDescription)")
    }

    // 每布局词库 (第 10 轮第 7 条): 重置清空了沙盒用户数据目录,
    // 按绑定把补丁打回来 (绑定存在 UserDefaults, 重置丢不掉),
    // 否则下面沙盒 -> App Group 的同步会把 App Group 里的补丁也删掉。
    do {
      try LayoutDictionary.apply()
    } catch {
      Logger.statistics.error("RIME reset layout dictionary patch error \(error.localizedDescription)")
    }

    // 九宫格首字母拼写 (第 13 轮第 3 项 a 小点): 重置清空了沙盒用户
    // 数据目录, 把补丁打回来 (常开, 不跟开关走), 否则下面沙盒 ->
    // App Group 的同步会把 App Group 里的补丁也删掉。
    do {
      try T9SyllableInitials.apply()
    } catch {
      Logger.statistics.error("RIME reset t9 syllable initials patch error \(error.localizedDescription)")
    }

    // 部署后将方案copy至AppGroup下供keyboard使用
    // (第 14 轮第 1 项: 重置是显式清空学习的操作, 传 includeUserDB: true
    // 保留“重置清空学习”的语义; deployment/syncRime 走默认 false。)
    try FileManager.syncSandboxSharedSupportDirectoryToAppGroup()
    try FileManager.syncSandboxUserDataDirectoryToAppGroup(includeUserDB: true)
  }

  var isRunning: Bool {
    Rime.shared.isRunning()
  }
}

// MARK: - RIME 引擎相关操作

public extension RimeContext {
  /// 设置用户输入方案
  func setupRimeInputSchema() {
    let schema: RimeSchema
    if let currentSchema = currentSchema {
      schema = currentSchema
    } else {
      guard let currentSchema = selectSchemas.first else {
        Logger.statistics.error("rime select schemas is empty.")
        return
      }
      schema = currentSchema
    }
    let handle = Rime.shared.setSchema(schema.schemaId)
    Logger.statistics.info("self.rimeEngine set schema: \(schema.schemaName), handle = \(handle)")
  }

  /// 切换最近一次输入方案
  @MainActor
  func switchLatestInputSchema() {
    let latestSchema: RimeSchema
    if let schema = self.latestSchema {
      latestSchema = schema
    } else {
      // 过滤掉当前输入方案，取第一个方案为上个方案
      let selectSchemas = selectSchemas.filter { $0.schemaId != self.currentSchema?.schemaId }
      guard selectSchemas.count > 0 else {
        Logger.statistics.error("rime select schemas count less than 1.")
        return
      }
      latestSchema = selectSchemas[0]
    }
    let handle = Rime.shared.setSchema(latestSchema.schemaId)
    Logger.statistics.info("self.rimeEngine set latest schema: \(latestSchema.schemaName), handle = \(handle)")
    if handle {
      self.latestSchema = self.currentSchema
      self.currentSchema = latestSchema
    }
    self.reset()
  }

  /// 触发 RIME 的 switcher
  @MainActor
  func switcher() {
    guard !hotKeys.isEmpty else { return }
    let hotkey = hotKeys[0] // 取第一个
    let hotKeyCode = RimeContext.hotKeyCodeMapping[hotkey, default: XK_F4]
    let hotKeyModifier = RimeContext.hotKeyCodeModifiersMapping[hotkey, default: Int32(0)]
    Logger.statistics.info("rimeSwitcher hotkey = \(hotkey), hotkeyCode = \(hotKeyCode), modifier = \(hotKeyModifier)")
    _ = Rime.shared.inputKeyCode(hotKeyCode, modifier: hotKeyModifier)
    syncContext()
  }

  /// 根据索引选择候选字
  @MainActor
  func selectCandidate(index: Int) {
    // 候选栏可能因置顶重排过显示顺序: 显示下标 -> 引擎下标 (见
    // applyPinnedCandidates; 未置顶时两者相同)。必须在序幕前算好,
    // 序幕会刷新 suggestions。
    let engineIndex = engineIndexForDisplayIndex(index)
    // 刚提交的归属: 选词前快照输入码并清掉旧的 lastCommit (新操作开始)。
    // 前缀模式下快照的是前缀码 (序幕换回前缀之后, 见下)。
    if !isShowingPrefixCandidates {
      pendingCommitCode = Rime.shared.getInputKeys()
      lastCommit = nil
    }
    // 前缀候选模式: 屏幕上显示的是最长合法前缀的候选, 引擎里却是完整输入
    // (菜单为空)。先把引擎换回前缀, 选词上屏, 再把尾巴数字重新敲回去当新输入
    // (微信行为: 选了前缀词, 剩下的数字继续拼)。
    if isShowingPrefixCandidates {
      let prefix = prefixCandidateInput
      let tail = prefixCandidateTail
      let fullLength = prefixCandidateFullInput.count
      isShowingPrefixCandidates = false
      prefixCandidateInput = ""
      prefixCandidateTail = ""
      prefixCandidateFullInput = ""
      guard Rime.shared.replaceInputKeys(prefix, startPos: 0, count: fullLength) else {
        // 换不回去就照常同步一次: syncContext 会重新算前缀候选并恢复状态,
        // 显示不变, 只是这次选词没生效。
        syncContext()
        return
      }
      syncContext()
      pendingCommitCode = Rime.shared.getInputKeys()
      lastCommit = nil
      _ = Rime.shared.selectCandidate(index: engineIndex)
      syncContext()
      for digit in tail {
        _ = Rime.shared.inputKey(String(digit))
      }
      syncContext()
      return
    }
    _ = Rime.shared.selectCandidate(index: engineIndex)
    syncContext()
  }

  // 同步中文简繁状态
  func syncTraditionalSimplifiedChineseMode(simplifiedModeKey: String) {
    // 获取运行时状态
    let simplifiedModeValue = Rime.shared.simplifiedChineseMode(key: simplifiedModeKey)

    // 获取文件中保存状态
    let value = Rime.shared.API().getCustomize("patch/\(simplifiedModeKey)") ?? ""
    if value.isEmpty {
      // 首次加载保存简繁状态
      let handled = Rime.shared.API().customize(simplifiedModeKey, stringValue: String(simplifiedModeValue))
      Logger.statistics.info("syncTraditionalSimplifiedChineseMode() first save. key: \(simplifiedModeKey), value: \(simplifiedModeValue), handled: \(handled)")
    } else {
//      let handled = Rime.shared.setSimplifiedChineseMode(key: simplifiedModeKey, value: (value as NSString).boolValue)
//      Logger.statistics.info("syncTraditionalSimplifiedChineseMode() set runtime state. key: \(simplifiedModeKey), value: \(value), handled: \(handled)")
    }
  }

  /// rime 中文简繁状态切换
  func switchTraditionalSimplifiedChinese(_ simplifiedModeKey: String) {
    let simplifiedModeValue = Rime.shared.simplifiedChineseMode(key: simplifiedModeKey)

    // 设置运行时状态
    Rime.shared.setSimplifiedChineseMode(key: simplifiedModeKey, value: !simplifiedModeValue)
    Logger.statistics.info("switchTraditionalSimplifiedChinese key: \(simplifiedModeKey), value: \(!simplifiedModeValue)")

    // 保存运行时状态
    let handled = Rime.shared.API().customize(simplifiedModeKey, stringValue: String(!simplifiedModeValue))
    Logger.statistics.info("switchTraditionalSimplifiedChinese save file state. key: \(simplifiedModeKey), value: \(!simplifiedModeValue), handled: \(handled)")
  }

  /// 中英切换
  @MainActor
  func switchEnglishChinese() {
    self.reset()
    self.asciiMode.toggle()
    Rime.shared.asciiMode(asciiMode)
  }
}

// MARK: implementation IRimeNotificationDelegate

extension RimeContext: IRimeNotificationDelegate {
  public func onDeployStart() {
    Logger.statistics.info("HamsterRimeNotification: onDeployStart")
  }

  public func onDeploySuccess() {
    Logger.statistics.info("HamsterRimeNotification: onDeploySuccess")
  }

  public func onDeployFailure() {
    Logger.statistics.info("HamsterRimeNotification: onDeployFailure")
  }

  @MainActor
  public func onChangeMode(_ option: String) {
    Logger.statistics.info("HamsterRimeNotification: onChangeMode, mode: \(option)")

    let optionState = !option.hasPrefix("!")
    let optionName = optionState ? option : String(option.dropFirst())

    if optionValueCache[optionName] == nil {
      optionValueCache[optionName] = [
        true: Rime.shared.getStateLabel(option: optionName, state: true, abbreviated: true),
        false: Rime.shared.getStateLabel(option: optionName, state: false, abbreviated: true),
      ]
    }

    // 中英模式
    if option.hasSuffix("ascii_mode") {
      self.setAsciiMode(optionState)
    }

    // 设置 rime option 对应的值
    self.optionState = optionValueCache[optionName]?[optionState]
  }

  @MainActor
  public func onLoadingSchema(_ loadSchema: String) {
    Logger.statistics.info("HamsterRimeNotification: onLoadingSchema, schema: \(loadSchema)")
    Task {
      let currentSchema = self.currentSchema
      let schemaID = loadSchema.split(separator: "/").map { String($0) }[0]
      guard !schemaID.isEmpty, currentSchema?.schemaId != schemaID else { return }
      // 从当前全部方案列表中获取
      guard let changeSchema = self.schemas.first(where: { $0.schemaId == schemaID }) else { return }
      self.setCurrentSchema(changeSchema)
      self.optionState = changeSchema.schemaName
      Logger.statistics.info("loading schema callback: currentSchema = \(changeSchema.schemaName), latestSchema = \(currentSchema?.schemaName)")
    }
  }
}

// MARK: - 文字输入处理

public extension RimeContext {
  /**
   RIME引擎尝试处理输入文字
   */
  @MainActor
  func tryHandleInputText(_ text: String) -> Bool {
    // 刚提交的归属 (第 14 轮第 5 项 a): 先快照输入码、清掉旧的 lastCommit,
    // 再让引擎处理; 这次按键若提交, syncContext 会用快照记下 (码, 词)。
    pendingCommitCode = Rime.shared.getInputKeys()
    lastCommit = nil
    // 由rime处理全部符号
    let handled = Rime.shared.inputKey(text)

    // 处理失败则返回 inputText
    guard handled else { return false }

    self.syncContext()

    return true
  }

  @MainActor
  func tryHandleReplaceInputTexts(_ text: String, startPos: Int, count: Int) -> Bool {
    guard Rime.shared.replaceInputKeys(text, startPos: startPos, count: count) else { return false }
    self.selectCandidatePinyin = (text, startPos, count)
    self.syncContext()
    return true
  }

  func getInputKeys() -> String {
    Rime.shared.getInputKeys()
  }

  /**
   RIME引擎尝试处理输入编码
   */
  @MainActor
  func tryHandleInputCode(_ code: Int32, modifier: Int32 = 0) -> Bool {
    pendingCommitCode = Rime.shared.getInputKeys()
    lastCommit = nil
    // 由rime处理全部符号
    let handled = Rime.shared.inputKeyCode(code, modifier: modifier)
    // 处理失败则返回 inputText
    guard handled else { return false }

    self.syncContext()

    return true
  }

  /// 同步context: 主要是获取当前引擎提供的候选文字, 同时更新rime published属性 userInputKey
  @MainActor
  func syncContext() {
    self.pageIndex = 0
    self.rimeContext = Rime.shared.context()
    let userInputText = rimeContext?.composition?.preedit ?? ""
    let commitText = Rime.shared.getCommitText()
    var candidates = [CandidateSuggestion]()
    if !useContextPaging {
      var highlightIndex = 0
      if let menu = rimeContext?.menu {
        highlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
      }
      candidates = self.candidateListLimit(index: candidateIndex, highlightIndex: highlightIndex, count: maximumNumberOfCandidateWords)
    }

    // Logger.statistics.debug("syncContext: userInputText = \(userInputText), commitText = \(commitText)")

    // 查看输入法状态
    let status = Rime.shared.status()

    // 注意：commitText 值的修改需要在修改 userInputKey 之前，
    // 因为 userInputKey 是 @Published，观测其值时会用到 commitText，所以如果 commitText 值修改滞后，会造成读取 commitText 不正确

    // 如果输入状态不是待组字阶段, 则重置输入法
    if !status.isComposing {
      self.commitText = commitText
      // 刚提交了一次选词: 立刻把用户词典学习落盘, 否则这次学习只在
      // 内存事务里, 键盘进程被系统杀掉就丢了 (第 12 轮第 1 项)。
      // 注意 getCommitText() 读一次就清 (RimeGetCommit 会 ResetCommitText),
      // 所以 commitText 非空只会在刚提交的这一次同步里出现, 不会重复落盘。
      if !commitText.isEmpty {
        // (第 14 轮第 5 项 a) 记下这次提交的 (输入码, 文字), 供退格撤销学习用。
        if !pendingCommitCode.isEmpty {
          lastCommit = (pendingCommitCode, commitText)
        }
        flushUserDictionary()
      }
      self.reset()
      return
    }

    // 注意赋值顺序
    self.userInputKey = userInputText
    self.commitText = commitText
    // 九宫格前缀候选 (第 8 轮): 引擎对完整输入一个候选都不给时,
    // 试试最长合法前缀 (见 prefixCandidatesForUnsegmentableT9Input)。
    // 正常有候选时不走这条路; 任何没拿到前缀候选的情况都清掉旧的前缀状态。
    // useContextPaging 模式下候选栏不走 suggestions, 这里也不跑。
    if !useContextPaging, candidates.isEmpty {
      if let prefixCandidates = self.prefixCandidatesForUnsegmentableT9Input(preedit: userInputText) {
        // 前缀候选也走置顶显示重排 (只重排显示; 引擎里是完整输入、菜单为
        // 空, 高亮无处可移, 不动引擎)。
        self.suggestions = applyPinnedCandidates(prefixCandidates, code: prefixCandidateInput, moveHighlight: false)
        return
      }
    }
    self.isShowingPrefixCandidates = false
    self.prefixCandidateInput = ""
    self.prefixCandidateTail = ""
    self.prefixCandidateFullInput = ""
    self.suggestions = applyPinnedCandidates(candidates, code: Rime.shared.getInputKeys(), moveHighlight: true)
  }

  /// 分页：下一页
  @MainActor
  func nextPage() {
    self.pageIndex += 1
    var highlightIndex = 0
    if let menu = rimeContext?.menu {
      highlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
    }
    let candidates = self.candidateListLimit(index: candidateIndex, highlightIndex: highlightIndex, count: maximumNumberOfCandidateWords)
    if !candidates.isEmpty {
      self.suggestions.append(contentsOf: candidates)
    } else {
      self.pageIndex -= 1
    }
  }

  /// 获取候选列表
  func candidateListLimit(index: Int, highlightIndex: Int, count: Int) -> [CandidateSuggestion] {
    // TODO: 最大候选文字数量
    let candidates = Rime.shared.candidateListWithIndex(index: index, andCount: count)
    var result: [CandidateSuggestion] = []
    // 候选文字首个索引
    let candidateIndex = self.candidateIndex
    for (index, candidate) in candidates.enumerated() {
      let index = candidateIndex + index
      let suggestion = CandidateSuggestion(
        index: index,
        label: "\(index + 1)",
        text: candidate.text,
        title: candidate.text,
        isAutocomplete: index == highlightIndex,
        subtitle: candidate.comment
      )
      result.append(suggestion)
    }
    return result
  }

  @MainActor
  func deleteBackward() {
    _ = Rime.shared.inputKeyCode(XK_BackSpace)
    self.syncContext()
  }

  /// 删除用户输入，且不需要同步 RIME 上下文
  /// 注意：此方法是 T9 拼音用来做删除操作的
  @MainActor
  func deleteBackwardNotSync() {
    _ = Rime.shared.inputKeyCode(XK_BackSpace)
  }

  @MainActor
  func inputKeyNotSync(_ text: String) -> Bool {
    Rime.shared.inputKey(text)
  }

  @MainActor
  func getCaretPosition() -> Int {
    Rime.shared.getCaretPosition()
  }

  @MainActor
  func setCaretPosition(_ position: Int) {
    Rime.shared.setCaretPosition(position)
  }

  @MainActor
  func getContext() -> IRimeContext {
    Rime.shared.context()
  }
}

// MARK: - 记忆管理 (第 14 轮第 5 项)

public extension RimeContext {
  /// 当前显示的候选对应的原始输入码: 前缀候选模式用 prefixCandidateInput,
  /// 否则用引擎当前输入键 (原始键串, 不是分段后的 preedit)。
  @MainActor
  var effectiveCandidateCode: String {
    isShowingPrefixCandidates ? prefixCandidateInput : Rime.shared.getInputKeys()
  }

  /// 显示下标 -> 引擎下标: 候选栏可能因置顶重排过显示顺序, 点选时必须用
  /// 每个候选自带的 engine index (CandidateSuggestion.index) 去选引擎,
  /// 否则点到的是另一个词。未置顶时两者相同。
  @MainActor
  func engineIndexForDisplayIndex(_ displayIndex: Int) -> Int {
    guard displayIndex >= 0, displayIndex < suggestions.count else { return displayIndex }
    return suggestions[displayIndex].index
  }

  /// 长按候选词 -> 忘掉 (b): 删掉 text 在 userdb 里的学习记录。
  /// index 是当前 suggestions 里的显示下标。成功返回 true。
  /// 语义 (librime 源码 + 活验证): delete_candidate 删的是当前高亮
  /// (selected_index) 的候选, 不是 index 参数本身——所以先用 Down 键
  /// 把高亮移到目标上 (Down 只改 selected_index, 不提交、不学习),
  /// 再双重核对 (绝对下标 + 文字) 无误后才删; 删完 F24 落盘, 再 reset +
  /// 重输原输入码恢复打字状态。删的是 userdb 里的学习分, 词典原词不受
  /// 影响 (如 好的 的 #1 来自词典 + derive 规则, 忘不掉它); 忘掉后
  /// 再选一次同一词会重新学回来。
  @MainActor
  func forgetCandidateAt(index: Int) -> Bool {
    guard index >= 0, index < suggestions.count else { return false }
    let text = suggestions[index].text
    let code = effectiveCandidateCode
    let fullInput = isShowingPrefixCandidates ? prefixCandidateFullInput : Rime.shared.getInputKeys()
    // 前缀候选模式: 屏幕上的候选属于前缀, 引擎里却是完整输入 (菜单为空)。
    // 先把引擎换回前缀 (与 selectCandidate 同款序幕), 再在前缀菜单里忘。
    if isShowingPrefixCandidates {
      let prefix = prefixCandidateInput
      let fullLength = prefixCandidateFullInput.count
      isShowingPrefixCandidates = false
      prefixCandidateInput = ""
      prefixCandidateTail = ""
      prefixCandidateFullInput = ""
      guard Rime.shared.replaceInputKeys(prefix, startPos: 0, count: fullLength) else {
        syncContext()
        return false
      }
      syncContext()
    }
    return forgetCandidateInCurrentMenu(text: text, code: code, fullInput: fullInput)
  }

  /// 退格撤销上次提交的学习 (a): 刚提交的词又被退格删掉时调用。
  /// 把提交时的输入码重新敲进引擎, 找到刚提交的文字, 走忘掉流程。
  /// 找不到 (如多段提交拼不出单条候选) 就只清记录, 不报错。成功返回 true。
  /// 注意: 调用方 (退格键) 须先确认文档里刚删掉的正是 lastCommit.text,
  /// 这里只负责引擎侧的撤销。
  @MainActor
  func undoLastCommit() -> Bool {
    guard let commit = lastCommit else { return false }
    lastCommit = nil
    reset()
    for key in commit.code {
      _ = Rime.shared.inputKey(String(key))
    }
    syncContext()
    guard suggestions.contains(where: { $0.text == commit.text }) else {
      Logger.statistics.info("undoLastCommit: '\(commit.text)' not in menu for code '\(commit.code)', only cleared record")
      reset()
      syncContext()
      return false
    }
    return forgetCandidateInCurrentMenu(text: commit.text, code: commit.code, fullInput: commit.code)
  }

  /// 长按候选词 -> 置顶 (c): 把 (当前输入码, 该候选) 记进置顶列表
  /// (最近置顶在前), 下次同步时它排到候选最前面。只影响显示, 不动
  /// userdb、不写学习。成功返回 true。
  @MainActor
  func pinCandidateAt(index: Int) -> Bool {
    guard index >= 0, index < suggestions.count else { return false }
    let text = suggestions[index].text
    UserDefaults.hamster.pinCandidate(code: effectiveCandidateCode, text: text)
    syncContext()
    return true
  }

  /// 取消置顶 (c): 把 (当前输入码, 该候选) 从置顶列表去掉, 候选恢复
  /// 引擎原顺序。成功返回 true。
  @MainActor
  func unpinCandidateAt(index: Int) -> Bool {
    guard index >= 0, index < suggestions.count else { return false }
    let text = suggestions[index].text
    UserDefaults.hamster.unpinCandidate(code: effectiveCandidateCode, text: text)
    syncContext()
    return true
  }

  /// 该显示下标的候选当前是否已置顶 (供长按菜单显示“置顶/取消置顶”)。
  @MainActor
  func isCandidatePinnedAt(index: Int) -> Bool {
    guard index >= 0, index < suggestions.count else { return false }
    return UserDefaults.hamster.isCandidatePinned(code: effectiveCandidateCode, text: suggestions[index].text)
  }

  /// 在当前菜单里忘掉 text 的学习记录 (核心流程, 调用前引擎须已显示
  /// 该 text 所在的菜单)。fullInput 是忘完后要重输恢复的完整输入码。
  @MainActor
  private func forgetCandidateInCurrentMenu(text: String, code: String, fullInput: String) -> Bool {
    // 在当前菜单里找到 text 的下标 (前缀序幕后菜单变了, 下标可能变)。
    guard let displayIndex = suggestions.firstIndex(where: { $0.text == text }) else {
      Logger.statistics.info("forgetCandidate: '\(text)' not in current menu, nothing to forget")
      restoreInput(fullInput)
      return false
    }
    // delete_candidate 删的是高亮候选: 把高亮绝对移到目标的引擎下标上。
    // 注意显示下标 ≠ 引擎下标 (置顶会重排显示), 目标用候选自带的 engine index。
    let targetEngineIndex = suggestions[displayIndex].index
    let landed = moveEngineHighlightTo(targetEngineIndex)
    // 双重核对: 高亮绝对下标 + 高亮文字都对得上才删, 绝不删错词。
    let highlightedText: String? = landed >= 0 ? Rime.shared.candidateListWithIndex(index: landed, andCount: 1).first?.text : nil
    guard landed == targetEngineIndex, highlightedText == text else {
      Logger.statistics.info("forgetCandidate: highlight mismatch (want \(targetEngineIndex) '\(text)', got \(landed) '\(highlightedText ?? "")'), abort")
      restoreInput(fullInput)
      return false
    }
    guard Rime.shared.deleteCandidate(index: targetEngineIndex) else {
      Logger.statistics.info("forgetCandidate: delete_candidate unavailable or failed for '\(text)'")
      restoreInput(fullInput)
      return false
    }
    // 删除写进同一批事务, 不 F24 会被下一批吞掉/丢掉; 同 (code, text)
    // 的置顶一并清除 (忘掉的词不应还置顶)。
    flushUserDictionary()
    UserDefaults.hamster.unpinCandidate(code: code, text: text)
    restoreInput(fullInput)
    Logger.statistics.info("forgetCandidate: forgot '\(text)' for code '\(code)'")
    return true
  }

  /// 忘/删操作后恢复打字状态: 清掉当前组字, 把原输入码重新敲回去, 同步一次。
  @MainActor
  private func restoreInput(_ fullInput: String) {
    reset()
    for key in fullInput {
      _ = Rime.shared.inputKey(String(key))
    }
    syncContext()
  }

  /// 置顶只在显示层生效: 把当前候选里属于同一输入码的置顶词按最近置顶
  /// 在前挪到最前面, 其余顺序不动。
  /// moveHighlight 为 true 时 (正常候选栏), 还会把引擎高亮绝对移到
  /// 置顶词上 (Home 回 0 再 Down, 见 moveEngineHighlightTo), 这样空
  /// 格上屏的也是置顶词 (只改高亮, 不提交、不学习)。没置顶时原样返回,
  /// 不碰引擎。
  /// 前缀候选模式传 moveHighlight: false: 引擎里是完整输入、菜单为空,
  /// 高亮无处可移。
  @MainActor
  private func applyPinnedCandidates(_ candidates: [CandidateSuggestion], code: String, moveHighlight: Bool) -> [CandidateSuggestion] {
    guard !code.isEmpty, !candidates.isEmpty else { return candidates }
    let pinnedTexts = UserDefaults.hamster.pinnedCandidates.filter { $0.code == code }.map { $0.text }
    guard !pinnedTexts.isEmpty else { return candidates }
    var rest = candidates
    var pinned: [CandidateSuggestion] = []
    for text in pinnedTexts {
      if let i = rest.firstIndex(where: { $0.text == text }) {
        pinned.append(rest.remove(at: i))
      }
    }
    guard !pinned.isEmpty else { return candidates }
    var ordered = pinned + rest
    if moveHighlight {
      let target = ordered[0].index
      if target != 0 {
        let landed = moveEngineHighlightTo(target)
        if landed == target {
          // 高亮标志按移动后的结果重算 (原来按旧高亮算的已经过期)。
          ordered = ordered.map { suggestion in
            var s = suggestion
            s.isAutocomplete = (s.index == target)
            return s
          }
        } else {
          Logger.statistics.info("pin: highlight move to \(target) failed (landed \(landed)), display reordered only")
        }
      }
    }
    return ordered
  }

  /// 把引擎高亮绝对移到 target (只改高亮, 不提交、不学习):
  /// 高亮不在 0 时先按 Home 回 0 (Home 在高亮已是 0 时会落到导航器去动
  /// 光标, 所以高亮已是 0 时不按), 再按 Down×target。
  /// 返回移动后的高亮绝对下标 (读不到菜单时 -1)。
  @MainActor
  private func moveEngineHighlightTo(_ target: Int) -> Int {
    let menu = Rime.shared.context().menu
    let current = menu.map { Int($0.pageSize * $0.pageNo + $0.highlightedCandidateIndex) } ?? -1
    if current != 0, current >= 0 {
      _ = Rime.shared.inputKeyCode(XK_Home)
    }
    for _ in 0..<target {
      _ = Rime.shared.inputKeyCode(XK_Down)
    }
    let landedMenu = Rime.shared.context().menu
    return landedMenu.map { Int($0.pageSize * $0.pageNo + $0.highlightedCandidateIndex) } ?? -1
  }
}

// MARK: - static properties

public extension RimeContext {
  /// switcher hotkeys 键值映射
  static let hotKeyCodeMapping = [
    "f4": XK_F4,
    "control+grave": Int32("`".utf8.first!),
    "control+shift+grave": Int32("`".utf8.first!),
  ]

  static let hotKeyCodeModifiersMapping = [
    "f4": Int32(0),
    "control+grave": RimeModifier.kControlMask,
    "control+shift+grave": RimeModifier.kControlMask | RimeModifier.kShiftMask,
  ]

  static let keyCodeMapping: [String: Int32] = [
    "0": XK_0,
    "1": XK_1,
    "2": XK_2,
    "3": XK_3,
    "4": XK_4,
    "5": XK_5,
    "6": XK_6,
    "7": XK_7,
    "8": XK_8,
    "9": XK_9,

    "A": XK_A,
    "B": XK_B,
    "C": XK_C,
    "D": XK_D,
    "E": XK_E,
    "F": XK_F,
    "J": XK_J,
    "H": XK_H,
    "I": XK_I,
    "G": XK_G,
    "K": XK_K,
    "L": XK_L,
    "M": XK_M,
    "N": XK_N,
    "O": XK_O,
    "P": XK_P,
    "Q": XK_Q,
    "R": XK_R,
    "S": XK_S,
    "T": XK_T,
    "U": XK_U,
    "V": XK_V,
    "W": XK_W,
    "X": XK_X,
    "Y": XK_Y,
    "Z": XK_Z,

    "a": XK_a,
    "b": XK_b,
    "c": XK_c,
    "d": XK_d,
    "e": XK_e,
    "f": XK_f,
    "j": XK_j,
    "h": XK_h,
    "i": XK_i,
    "g": XK_g,
    "k": XK_k,
    "l": XK_l,
    "m": XK_m,
    "n": XK_n,
    "o": XK_o,
    "p": XK_p,
    "q": XK_q,
    "r": XK_r,
    "s": XK_s,
    "t": XK_t,
    "u": XK_u,
    "v": XK_v,
    "w": XK_w,
    "x": XK_x,
    "y": XK_y,
    "z": XK_z,

    "f1": XK_F1,
    "F1": XK_F1,
    "f2": XK_F2,
    "F2": XK_F2,
    "f3": XK_F3,
    "F3": XK_F3,
    "f4": XK_F4,
    "F4": XK_F4,
    "f5": XK_F5,
    "F5": XK_F5,
    "f6": XK_F6,
    "F6": XK_F6,
    "f7": XK_F7,
    "F7": XK_F7,
    "f8": XK_F8,
    "F8": XK_F8,
    "f9": XK_F9,
    "F9": XK_F9,
    "f10": XK_F10,
    "F10": XK_F10,
    "f11": XK_F11,
    "F11": XK_F11,
    "f12": XK_F12,
    "F12": XK_F12,
    "f13": XK_F13,
    "F13": XK_F13,
    "f14": XK_F14,
    "F14": XK_F14,

    "home": XK_Home,
    "Home": XK_Home,
    "pageup": XK_Page_Up,
    "page_up": XK_Page_Up,
    "pagedown": XK_Page_Down,
    "page_down": XK_Page_Down,
    "begin": XK_Begin,
    "Begin": XK_Begin,
    "end": XK_End,
    "End": XK_End,
    "left": XK_Left,
    "Left": XK_Left,
    "right": XK_Right,
    "Right": XK_Right,
    "Prior": XK_Prior,
    "prior": XK_Prior,
    "Next": XK_Next,
    "next": XK_Next,
    "up": XK_Up,
    "Up": XK_Up,
    "down": XK_Down,
    "Down": XK_Down,
    "tab": XK_Tab,
    "Tab": XK_Tab,
    "space": XK_space,
    "Space": XK_space,
    "return": XK_Return,
    "Return": XK_Return,
    "delete": XK_Delete,
    "Delete": XK_Delete,
    "backspace": XK_BackSpace,
    "Backspace": XK_BackSpace,
    "esc": XK_Escape,
    "Esc": XK_Escape,
    "ESC": XK_Escape,
    "shift_l": XK_Shift_L,
    "shift_r": XK_Shift_R,
    // "enter": XK_KP_Enter, // 小键盘的 enter 键
    "minus": XK_minus, // 减号 -
    "-": XK_minus, // 减号 -
    "equal": XK_equal, // 等号 =
    "=": XK_equal, // 等号 =
    "comma": XK_comma, // 逗号 ,
    ",": XK_comma, // 逗号 ,
    "period": XK_period, // 句号 .
    ".": XK_period, // 句号 .
    "semicolon": XK_semicolon, // 分号 ;
    ";": XK_semicolon,

    "grave": XK_grave, // 反引号 backtick quotes
    "`": XK_grave,

    "backslash": XK_backslash, // \
    "\\": XK_backslash,

    "bracketleft": XK_bracketleft, // [
    "[": XK_bracketleft,

    "bracketright": XK_bracketright, // ]
    "]": XK_bracketright,

    "apostrophe": XK_apostrophe, // ' 所有格符号, 单词内部的省略
    "'": XK_apostrophe,
  ]

  static let modifierMapping: [String: Int32] = [
    "shift": RimeModifier.kShiftMask,
    "Shift": RimeModifier.kShiftMask,
    "Control": RimeModifier.kControlMask,
    "control": RimeModifier.kControlMask,
    "ctrl": RimeModifier.kControlMask,
    "alt": RimeModifier.kAltMask,
    "Alt": RimeModifier.kAltMask,
    "command": RimeModifier.kSuperMask,
    "cmd": RimeModifier.kSuperMask,
    "capslock": RimeModifier.kLockMask,
    "cap": RimeModifier.kLockMask,
  ]
}

// MARK: - T9 拼音处理

public extension RimeContext {
  /// 九宫格 t9 输入的最长合法拼音前缀长度 (动态规划)。
  /// 一段数字是合法音节, 当且仅当它在 t9ToPinyinMapping 里对应至少一个
  /// 真实拼音音节: 长度 >= 2 的字母串, 或单字母 a/e/o (o/e/a 是合法单音节;
  /// j/w/p/m 等单个字母不是拼音音节, 不能算, 否则任意数字串都能“切全”)。
  /// 返回 0 表示没有任何合法前缀。已用 Python 在同一张映射表上验证:
  /// 664646468686868353558686866868646497979 -> 18,
  /// 44476766383835295 -> 0, 64426/9264/42/66 -> 全串。
  @MainActor
  func longestValidT9PrefixLength(_ digits: String) -> Int {
    let chars = Array(digits)
    let count = chars.count
    guard count > 0 else { return 0 }
    var reachable = [Bool](repeating: false, count: count + 1)
    reachable[0] = true
    for end in 1 ... count {
      for start in 0 ..< end where reachable[start] {
        let span = String(chars[start ..< end])
        guard let values = t9ToPinyinMapping[span] else { continue }
        let isSyllable = values.contains { value in
          value == "a" || value == "e" || value == "o"
            || (value.count >= 2 && value.allSatisfy { $0.isLetter })
        }
        if isSyllable {
          reachable[end] = true
          break
        }
      }
    }
    return (0 ... count).reversed().first { reachable[$0] } ?? 0
  }

  /// 九宫格前缀候选: 完整 t9 输入在引擎里一个候选都没有时, 用最长合法前缀
  /// 影子查一次引擎, 有候选就拿来展示 (微信行为), 没有则说明 t9 翻译已死。
  /// 返回 nil 时不展示任何候选 (调用方照常显示空列表)。
  /// 注意: 只在 preedit 全是数字时触发; 26 键的 preedit 是字母, 不会进这里。
  /// 影子查询全程不发 sync, 引擎输入在查完后立刻恢复成完整串, 显示的
  /// userInputKey / 边栏音节仍是完整输入; 只有 suggestions 来自前缀。
  @MainActor
  func prefixCandidatesForUnsegmentableT9Input(preedit: String) -> [CandidateSuggestion]? {
    // 全数字、至少 2 位才有前缀可言 (1 位数字的候选就是它自己, 没意义)。
    guard preedit.count >= 2, preedit.allSatisfy({ $0.isNumber }) else { return nil }
    let prefixLength = longestValidT9PrefixLength(preedit)
    // 整串本身就能切全却零候选: 不是“切不全”, 是 t9 翻译根本没返回
    // (词库/棱镜没加载或方案不对)。影子查同一串也一样是空, 直接记日志,
    // 让调用方知道这是部署问题、不是输入问题。
    guard prefixLength >= 2, prefixLength < preedit.count else {
      if prefixLength == preedit.count {
        Logger.statistics.error("t9 translation dead: fully segmentable input \"\(preedit)\" yields zero candidates; redeploy RIME in the app.")
      }
      return nil
    }
    let prefix = String(preedit.prefix(prefixLength))
    let tail = String(preedit.dropFirst(prefixLength))
    // 影子查前缀: 把引擎输入换成前缀 (不 sync, 不动显示), 取它的候选。
    guard Rime.shared.replaceInputKeys(prefix, startPos: 0, count: preedit.count) else { return nil }
    let shadowContext = Rime.shared.context()
    var shadowHighlightIndex = 0
    if let menu = shadowContext.menu {
      shadowHighlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
    }
    let shadowCandidates = candidateListLimit(index: 0, highlightIndex: shadowHighlightIndex, count: maximumNumberOfCandidateWords)
    // 再把完整串敲回去 (同样不 sync)。恢复失败时记日志并返回 nil,
    // 显示会在下次 syncContext 时按引擎实际输入自我纠正。
    guard Rime.shared.replaceInputKeys(preedit, startPos: 0, count: prefix.count) else {
      Logger.statistics.error("t9 prefix candidates: failed to restore full input \"\(preedit)\" after shadow query for prefix \"\(prefix)\".")
      return nil
    }
    // 恢复完整串后, 缓存的 context 也要是完整串的 (边栏/拼音条读它)。
    self.rimeContext = Rime.shared.context()
    guard !shadowCandidates.isEmpty else {
      Logger.statistics.error("t9 translation dead: longest valid prefix \"\(prefix)\" of \"\(preedit)\" yields zero candidates; redeploy RIME in the app.")
      return nil
    }
    isShowingPrefixCandidates = true
    prefixCandidateInput = prefix
    prefixCandidateTail = tail
    prefixCandidateFullInput = preedit
    Logger.statistics.info("t9 prefix candidates: input \"\(preedit)\" has no candidates, showing \(shadowCandidates.count) candidates for prefix \"\(prefix)\", tail \"\(tail)\" kept.")
    return shadowCandidates
  }

  /// 获取拼音候选列表
  @MainActor
  func getPinyinCandidates() -> [String] {
    var pinyinList = [String]()
    guard let preedit = rimeContext?.composition.preedit, !preedit.isEmpty else { return pinyinList }

    // 删除音节
    var prePinypin = preedit.replacingOccurrences(of: " ", with: "")
    guard !prePinypin.isEmpty else { return pinyinList }

    // 删除开头非数字字符
    while !prePinypin.isEmpty {
      if let firstCharacter = prePinypin.first, firstCharacter.isNumber {
        break
      }
      prePinypin.removeFirst()
    }

    // 拼写区非数字情况，取最后一个音节的拼音列表
    if prePinypin.isEmpty {
      // 如果不包含 t9 拼音，则使用最后一个拼音音节
      if var lastPinyin = preedit.split(separator: " ").last {
        // 音节可能会丢失，这里需要删除非字母的字符
        // 注意: 小心死循环
        while !lastPinyin.isEmpty {
          if let first = lastPinyin.first, first.isLowercase {
            break
          }
          _ = lastPinyin.removeFirst()
        }

        if var firstT9Pinyin = pinyinToT9Mapping[String(lastPinyin)] {
          /// 遍历包含的全部拼音子串
          while !firstT9Pinyin.isEmpty {
            if let list = t9ToPinyinMapping[firstT9Pinyin] {
              pinyinList.append(contentsOf: list)
            }
            _ = firstT9Pinyin.popLast()
          }
        }
      }
    } else {
      // 使用 trie 结构判断 pre 的字符: 逐位加长前缀, 只要还是某个音节编码的
      // 前缀就继续, 是完整音节编码就把它的拼音列出来。
      // 注意 (第 13 轮): 这里必须用 hasPrefix 判断“还能不能继续”, 不能用
      // contains——contains 要求整串是一个完整 key, 而 "782"/"982" 这类中间
      // 前缀本身不是 key (只是 "7826"/"9826" 的前缀), contains 会在第 3 位
      // 就 break, 导致 7826→quan/ruan/suan、9826→xuan/yuan/zuan 永远列不
      // 出来 (用户实测: 9826 边栏只有 xu, 手动点 xu 再点 'an 才能拼出 xuan)。
      for count in 1 ... prePinypin.count {
        let sub = String(prePinypin.prefix(count))
        if !t9PinyinTrie.hasPrefix(sub) {
          break
        }
        if let subList = t9ToPinyinMapping[sub] {
          pinyinList.append(contentsOf: subList)
        }
      }
    }

    return pinyinList.sorted(by: {
      if $0.count > $1.count {
        return true
      }

      if $0.count == $1.count {
        if let _ = Int($0) {
          return false
        }

        if let _ = Int($1) {
          return false
        }

        return $0 < $1
      }

      return false
    })
  }
}
