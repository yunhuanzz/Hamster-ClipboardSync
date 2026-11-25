//
//  LanguageModel.swift
//  HamsterKit
//
//  本地语言模型 (第 15 轮第 1 项, RIME octagram)。
//
//  做法 (不改上游仓库本身): 往 rime_ice.custom.yaml / t9.custom.yaml 里打补丁,
//  配上随安装包下发的 zh-hans-t-essay-bgw.gram。补丁内容照
//  lotem/rime-octagram-data 的 grammar.yaml 的 hans: 段原样抄:
//
//    grammar/language: zh-hans-t-essay-bgw
//    translator/contextual_suggestions: true
//    translator/max_homophones: 7
//    translator/max_homographs: 7
//
//  为什么是这 4 行: grammar/language 告诉 octagram 插件去加载同名 .gram
//  (资源类型 gram_db, 用户目录优先、共享目录后备); contextual_suggestions
//  让下一段输入参考已上屏的文字; max_homophones/max_homographs 7 是上游
//  grammar.yaml 里配套的值。注意 max_homophones 会改变进入词图的同音字数量,
//  短输入也可能受影响——第 15 轮活验证过 4263 好的 #1、64426 你好 #1 不变。
//
//  .gram 文件本身不在这里: 它是 40,925,228 字节 (约 39MB), 构建时由
//  InputSchemaBuild.sh 从 lotem/rime-octagram-data 的 hans 分支下载并校验
//  SHA256, 以散文件放进安装包的 SharedSupport/ (不进 git, 不在
//  SharedSupport.zip 里——zip 只在首次运行/重置时才解压, 老用户升级收不到)。
//  运行时 ensureGramFile() 把它拷进沙盒 SharedSupport, 部署末尾现成的
//  syncSandboxSharedSupportDirectoryToAppGroup() 再同步到 App Group, 键盘
//  扩展从 App Group 读。
//
//  活验证 (librime 1.8.5 真实构建 + 真实词库, Linux, 2026-11-24):
//  4263 好的 #1、64426 你好 #1 不变; 6269454782674464 脑子里全是你由
//  #1 脑子里软实力翻正为 #1; 但 96924842692462494664 我在挑外卖中、
//  3687443342628426 都是湿的好不好、3687447443342628426 都是屁格调不高
//  仍未翻正——beam 探针证实目标路径在 Poet 的 7 条 beam 里半路就被剪掉了
//  (kMaxLineCandidates = 7, librime 写死), 不是接线问题。字模型 bgc
//  (10MB) 实测把造句质量拉垮, 已否决, 不要换。
//  内存: .gram 是 mmap 只读映射 (不是全量读入), Linux 实测短输入 +0.2MB,
//  长句九宫格 +约 24MB 常驻; 真机峰值需 Xcode + 真机实测, 本轮没法验。
//
//  文件更新方式: 只动标记块 (BEGIN/END hamster-language-model 之间),
//  文件其余内容原样保留; 文件里已有 patch: 顶级键时, 补丁挂在它下面
//  (不再另起一个 patch:, 否则 YAML 重复键会丢掉用户原有的 patch 内容)。
//  常开, 不跟任何开关走。改完需要点「重新部署」才生效 (librime 要重新编译方案)。
//  部署时 RimeContext.deployment()/syncRime() 会重打一次补丁、重拷一次 .gram,
//  所以文件丢了也能在下次部署时恢复。
//

import Foundation

/// 本地语言模型 (octagram) 补丁 + .gram 文件投递 (常开, 两方案都写)。
public enum LanguageModel {
  /// 模型文件名 (安装包 SharedSupport/ 里的散文件, 也是共享数据目录里的文件名)。
  public static let gramFileName = "zh-hans-t-essay-bgw.gram"

  /// 模型文件实测大小 (字节, 2026-11-24 下载实测; 不是方案里写的约 10MB)。
  public static let gramByteSize = 40925228

  /// 模型文件 SHA256 (2026-11-24 下载实测; InputSchemaBuild.sh 下载时校验,
  /// 这里只留作核对, 拷文件时以大小为准)。
  public static let gramSHA256 = "d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e"

  /// 补丁行 (照 lotem/rime-octagram-data grammar.yaml 的 hans: 段原样抄)。
  public static let patchLines: [String] = [
    "grammar/language: zh-hans-t-essay-bgw",
    "translator/contextual_suggestions: true",
    "translator/max_homophones: 7",
    "translator/max_homographs: 7",
  ]

  /// 要打补丁的方案文件 (26 键雾凇拼音 + 九宫格 t9, 两边都要)。
  public static let schemaFileNames = ["rime_ice.custom.yaml", "t9.custom.yaml"]

  /// 补丁块的标记 (文件里只改这一段)。
  static let beginMarker = "# BEGIN hamster-language-model (本地语言模型 octagram, 请勿手动改这段)"
  static let endMarker = "# END hamster-language-model"

  /// 完整补丁块 (文件里没有 patch: 键时追加用)。
  static var fullBlock: String {
    ([beginMarker, "patch:"] + patchLines.map { "  " + $0 } + [endMarker])
      .joined(separator: "\n")
  }

  /// 挂在已有 patch: 键下面的补丁块 (2 空格缩进)。
  static var nestedBlock: String {
    ([("  " + beginMarker)] + patchLines.map { "  " + $0 } + [("  " + endMarker)])
      .joined(separator: "\n")
  }

  /// 写补丁: 两份文件都带上语言模型补丁 (常开, 不跟任何开关走)。
  /// 两份用户数据目录都写 (沙盒 + App Group): 沙盒那份供下次部署时
  /// librime 编译, App Group 那份供部署前的拷回与键盘扩展直接读取。
  public static func apply() throws {
    for dir in [FileManager.sandboxUserDataDirectory, FileManager.appGroupUserDataDirectoryURL] {
      try FileManager.createDirectory(override: false, dst: dir)
      for fileName in schemaFileNames {
        try apply(to: dir.appendingPathComponent(fileName))
      }
    }
  }

  /// 更新单个 custom.yaml 文件 (文件不存在时视为 "")。
  static func apply(to fileURL: URL) throws {
    var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    content = removingLanguageModelBlock(from: content)
    content = insertingLanguageModelBlock(into: content)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// 删掉标记块 (BEGIN 行到 END 行, 含两行本身); 没有标记块时原样返回。
  static func removingLanguageModelBlock(from content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    guard let begin = lines.firstIndex(where: { $0.contains(beginMarker) }),
          let end = lines.firstIndex(where: { $0.contains(endMarker) }),
          begin <= end else { return content }
    lines.removeSubrange(begin...end)
    return lines.joined(separator: "\n")
  }

  /// 插入标记块: 文件里已有 patch: 顶级键时挂在它下面,
  /// 否则在文件末尾追加完整的 patch: 块。
  static func insertingLanguageModelBlock(into content: String) -> String {
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return fullBlock + "\n"
    }
    var lines = content.components(separatedBy: .newlines)
    // 顶级 patch: 键 (行首无缩进; 带行内注释的也算, flow 写法除外, 这里不会出现)。
    if let patchIndex = lines.firstIndex(where: { $0 == "patch:" || $0.hasPrefix("patch: ") || $0.hasPrefix("patch:\t") }) {
      lines.insert(contentsOf: nestedBlock.components(separatedBy: "\n"), at: patchIndex + 1)
      return lines.joined(separator: "\n")
    }
    var result = content
    if !result.hasSuffix("\n") { result += "\n" }
    result += "\n" + fullBlock + "\n"
    return result
  }

  /// 把安装包里的 .gram 拷进沙盒 SharedSupport (部署/同步时调, 仅主 App)。
  /// 缺失或大小不对才拷 (41MB 的文件, 别每次都重拷); 拷完部署末尾现成的
  /// syncSandboxSharedSupportDirectoryToAppGroup() 会同步到 App Group。
  /// 安装包里没有这个文件时抛错 (构建时 InputSchemaBuild.sh 负责下载)。
  public static func ensureGramFile() throws {
    let src = FileManager.appSharedSupportDirectory.appendingPathComponent(gramFileName)
    let dst = FileManager.sandboxSharedSupportDirectory.appendingPathComponent(gramFileName)
    try FileManager.createDirectory(override: false, dst: FileManager.sandboxSharedSupportDirectory)
    if FileManager.default.fileExists(atPath: dst.path),
       let attributes = try? FileManager.default.attributesOfItem(atPath: dst.path),
       let size = attributes[.size] as? Int,
       size == gramByteSize {
      return
    }
    guard FileManager.default.fileExists(atPath: src.path) else {
      throw NSError(
        domain: "com.ihsiao.apps.hamster.LanguageModel",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "安装包里缺少语言模型文件 \(gramFileName), 请先跑 InputSchemaBuild.sh 下载"])
    }
    if FileManager.default.fileExists(atPath: dst.path) {
      try FileManager.default.removeItem(at: dst)
    }
    try FileManager.default.copyItem(at: src, to: dst)
  }
}
