//
//  ClipboardSyncService.swift
//  HamsterKit
//
//  跨设备剪贴板同步服务（键盘触发式，类似微信输入法的做法）:
//
//  触发时机: 键盘每次弹出时 (KeyboardInputViewController.viewWillAppear),
//  以及键盘打开期间每 1 秒一次 (KeyboardToolbarView 的定时器, 键盘隐藏时停止)。
//  流程:
//    1. 读取本机剪贴板 (UIPasteboard)，若与上次同步内容不同则上传到服务器;
//    2. 从服务器下载最新一条剪贴板，若与本机不同则写回本机剪贴板。
//  因此另一台设备打开键盘时，就能拿到这边复制的内容；键盘开着时复制
//  (本机或 PC) 也不用等关闭重开，1 秒内就能同步到。
//
//  服务器协议 (SyncClipboard 服务器, 见 https://github.com/Jeric-X/SyncClipboard):
//    上传: PUT {serverURL}/SyncClipboard.json, Body 为 JSON
//          {"type":"Text","text":"...","hasData":false}, Content-Type: application/json
//          (纯文本 PUT 会被服务器 415 拒绝)
//    下载: GET {serverURL}/SyncClipboard.json, 响应为 SyncClipboard.json
//          (解析其中 "text" 字段; 兼容纯文本响应)
//    鉴权: 若配置了用户名/密码, 则附加 HTTP Basic Auth
//    服务器只需保存"最新一条"剪贴板内容即可, 仓库 Tools/ 下附了一个
//    极简参考服务端 (clipboard-sync-server.py, 仅支持纯文本 PUT, 与
//    真实 SyncClipboard 服务器协议不同, 仅供本地测试)。
//    注意 (2026-11-23 实测): 请求地址必须是 {serverURL}/SyncClipboard.json,
//    直接请求根路径 PUT 会返回 405, GET 根路径只返回 "Server is running."
//    (会被误当成剪贴板内容)。syncEndpointURL(for:) 负责补全该路径。
//
//  图片同步 (2026-11-24, round 16 item 4):
//    真实服务器的图片不在 JSON 里 (不是 base64), 而是单独的文件:
//    - GET /SyncClipboard.json 返回元数据, 图片时 type 为 "Image"
//      (旧版 ClipboardProfileDTO: {"clipboard": hash, "text": ..., "file": 文件名,
//       "type": "Image"}; 新版 ProfileDto: {"type": "Image", "hash": ..., "text": 文件名,
//       "hasData": true, "dataName": 文件名, "size": ...})。服务端图片文件名为
//      Image_<时间戳>.png (见上游 ImageProfile.CreateImageFileName),
//      经 GET {base}/file/{fileName} 以原始字节下载。
//    - 上传分两步: 先 PUT {base}/file/{fileName} (application/octet-stream, 原始图片字节),
//      再 PUT /SyncClipboard.json {"type":"Image","text":文件名,"file":文件名,
//      "dataName":文件名,"hasData":true}。顺序不能反: 服务器在收到元数据时会校验
//      文件已存在, 否则返回 400 (见上游 SyncClipboardController.PutSyncProfile)。
//    - 下载的图片直接以原始字节 + UTI 写进 UIPasteboard (setItems), 不解码、不转码:
//      键盘扩展不能经 textDocumentProxy 插入图片 (只支持文本), 写剪贴板是唯一正确路线,
//      宿主 App 长按粘贴即可取到图片, GIF 动图也能保留。
//    - 防回声: 图片的同步哈希是图片字节的 SHA-256 (与文本的 sha256(文本) 同一字段),
//      下载前先比远端指纹 (type + 服务器哈希), 一致时连文件都不下载;
//      下载后写剪贴板会更新 changeCount, 下次同步不再重读、也不再重传。
//    - 参考服务端 Tools/clipboard-sync-server.py 不支持图片, 只能测文本。
//
//  注意:
//  - 需要键盘开启"允许完全访问" (Hamster 已在 Info.plist 中声明
//    RequestsOpenAccess, 且 RIME 词库本身也依赖它), 否则无法读取剪贴板与联网。
//  - iOS 14 起每次读取剪贴板都会在屏幕顶部弹出横幅提示, 这是系统行为, 无法绕过。
//  - 键盘扩展内存上限约 50MB, 本服务只用 URLSession, 不引入重型依赖;
//    网络失败时静默放弃, 绝不阻塞打字。
//

import CryptoKit
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// 剪贴板同步服务 (单例, 线程安全)
public final class ClipboardSyncService {
  public static let shared = ClipboardSyncService()

  /// 同步完成通知 (主线程发出)。剪贴板面板/工具栏监听它来刷新状态行与粘贴提示。
  public static let didFinishNotification = Notification.Name("dev.fuxiao.app.Hamster.ClipboardSync.didFinish")

  /// 每次键盘弹出后最短同步间隔 (秒), 避免快速切换键盘时频繁请求。
  /// 2026-11-23 由 10 秒改为 2 秒、再改为 0.5 秒: 连续复制时两次同步之间不再有几秒的空窗。
  private static let minSyncInterval: TimeInterval = 0.5

  /// 单次网络请求超时 (秒)
  private static let requestTimeout: TimeInterval = 3

  /// 文件上传/下载超时 (秒): 图片字节比 JSON 大得多, 局域网内也应给足时间。
  private static let fileTimeout: TimeInterval = 15

  /// 图片上传上限 (字节): 超过则本次不同步 (键盘扩展内存约 50MB, 不能无上限地编解码)。
  private static let maxImageUploadBytes = 10 * 1024 * 1024

  /// 图片下载上限 (字节): 超过则本次不写剪贴板, 但记下指纹避免每秒重复下载。
  private static let maxImageDownloadBytes = 20 * 1024 * 1024

  /// 写回剪贴板 / 重编码上传时, 图片最长边的上限 (像素): 超过则等比缩小,
  /// 避免超大图在键盘扩展里解码时冲爆内存。2048px 粘贴后依然清晰。
  private static let maxImageDimension: CGFloat = 2048

  /// 同步端点路径: 真实 SyncClipboard 服务器固定为 /SyncClipboard.json
  private static let syncEndpointPath = "SyncClipboard.json"

  private static let statusTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  /// 图片文件名时间戳 (与服务端 ImageProfile.CreateImageFileName() 的 Image_<时间戳>.png 同款格式)
  private static let imageFileNameFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter
  }()

  /// 串行队列, 避免并发读写剪贴板
  private let queue = DispatchQueue(label: "dev.fuxiao.app.Hamster.ClipboardSync", qos: .utility)

  private var lastAttempt: Date?

  /// 是否正在同步 (只在串行队列上读写)。定时器每 1 秒调一次 syncNow(),
  /// 若上一次同步 (弱网时最多等 4 秒) 还没结束, 新的直接跳过, 不堆积。
  private var isSyncing = false

  #if canImport(UIKit)
    /// 读当前剪贴板文本的统一入口 (第 17 轮第 7 项, 供键盘内各处自动读取用)。
    /// changeCount 与持久化记录相同 → 返回上次读到的缓存文本, 不读
    /// UIPasteboard、不弹"粘贴自 xxx"横幅; 不同 → 读一次并更新记录与缓存
    /// (本次弹一次横幅, 内容确实是新的)。
    /// 返回当前剪贴板文本原文 (未 trim, 调用方按需处理); 空剪贴板 / 非文本
    /// 内容时返回 nil。超长文本未缓存时直接读一次 (横幅一次, 极少见),
    /// 绝不把"没缓存"当成"空剪贴板"而吞掉粘贴。
    /// 注意: 调用方若随后还要读图片, 需自己先比 changeCount——缓存只存文本。
    public static func cachedPasteboardText() -> String? {
      let defaults = UserDefaults.hamster
      let currentChangeCount = UIPasteboard.general.changeCount
      if currentChangeCount == defaults.clipboardLastSeenChangeCount {
        if let cached = defaults.clipboardLastSeenText, !cached.isEmpty {
          return cached
        }
        if !defaults.clipboardLastSeenTextTruncated {
          return nil // 空剪贴板或图片内容: 缓存为空就是对的, 不读
        }
        // 超长文本未缓存: 直接读一次 (横幅一次), 并刷新记录
      }
      let text = UIPasteboard.general.string
      defaults.recordLastSeenPasteboard(changeCount: currentChangeCount, text: text)
      return (text?.isEmpty == false) ? text : nil
    }
  #endif

  private init() {}

  // MARK: - 入口

  /// 键盘弹出时调用: 先上传本机剪贴板, 再下载服务器最新内容。
  /// 内部节流、异步执行、失败静默, 不会阻塞键盘与打字。
  public func syncOnKeyboardAppear() {
    queue.async { [weak self] in
      guard let self = self else { return }
      guard !self.isSyncing else { return }
      let now = Date()
      if let last = self.lastAttempt, now.timeIntervalSince(last) < Self.minSyncInterval {
        return
      }
      self.isSyncing = true
      defer { self.isSyncing = false }
      self.lastAttempt = now
      self.sync()
    }
  }

  /// 立即同步一次 (跳过 0.5 秒节流), 供剪贴板面板/菜单/设置/定时器手动触发。
  /// 同样异步执行、失败静默, 不阻塞打字; 完成后发 didFinishNotification。
  public func syncNow() {
    queue.async { [weak self] in
      guard let self = self else { return }
      guard !self.isSyncing else { return }
      self.isSyncing = true
      defer { self.isSyncing = false }
      self.lastAttempt = Date()
      self.sync()
    }
  }

  /// 真实 SyncClipboard 服务器的剪贴板端点固定为 {base}/SyncClipboard.json。
  /// 兼容用户输入: 末尾斜杠会被忽略; 已带 SyncClipboard.json 的地址不再重复追加。
  static func syncEndpointURL(for baseURL: URL) -> URL {
    if baseURL.lastPathComponent == syncEndpointPath {
      return baseURL
    }
    return baseURL.appendingPathComponent(syncEndpointPath)
  }

  /// 服务器上的图片/文件端点: {base}/file/{fileName}。
  /// base 即用户配置的服务器地址 (可能已带 SyncClipboard.json, 需先去掉)。
  /// 文件名含 /、\ 或 .. 时返回 nil (服务器同样会拒绝这类文件名)。
  static func fileURL(for baseURL: URL, fileName: String) -> URL? {
    guard !fileName.isEmpty,
      !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("..")
    else { return nil }
    var base = baseURL
    if base.lastPathComponent == syncEndpointPath {
      base = base.deletingLastPathComponent()
    }
    return base.appendingPathComponent("file").appendingPathComponent(fileName)
  }

  // MARK: - 同步主流程

  private func sync() {
    let defaults = UserDefaults.hamster
    // (第 14 轮第 7 项) 每次同步先跑一次性迁移: 存着旧 BWG 地址的设备
    // 换成本地局域网值, 否则只改默认值、他的键盘永远不会换过去。
    // 幂等, 存的不是旧 BWG 地址时什么都不做。
    defaults.migrateClipboardSyncServerFromBWGToLAN()
    guard defaults.clipboardSyncEnabled else {
      recordStatus("未启用")
      notifyFinished()
      return
    }
    guard let serverURL = URL(string: defaults.clipboardSyncServerURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      serverURL.scheme == "http" || serverURL.scheme == "https"
    else {
      recordStatus("服务器地址无效")
      notifyFinished()
      return
    }

    // 真实 SyncClipboard 服务器要求请求 /SyncClipboard.json, 不能直接请求根路径
    // (根路径 PUT 返回 405, GET 只返回 "Server is running.")。
    let endpointURL = Self.syncEndpointURL(for: serverURL)
    // 用户名/密码去首尾空白: 设置页粘贴时带入的尾随空格会被服务器逐字比对,
    // 导致 401 (实测: 用户名尾部多一个空格就全程 401, 服务端却正常)。
    let username = defaults.clipboardSyncUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = defaults.clipboardSyncPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    // 没配凭据就不发请求: 服务器配了 Basic Auth 时无头请求只会得到 401,
    // 直接报"凭据未设置"比 401 更明确。
    guard !username.isEmpty, !password.isEmpty else {
      recordStatus("凭据未设置")
      notifyFinished()
      return
    }
    let lastHash = defaults.clipboardSyncLastHash

    // 1. 上传本机剪贴板 (若与上次同步内容不同)
    var failureReason: String?
    var successNote: String?
    #if canImport(UIKit)
      // 文本上传 (2026-11-27 修): 经统一门 cachedPasteboardText() 读剪贴板,
      // 以内容哈希对上次同步哈希为准, 不再以 changeCount 为门。
      // 根因: 显示侧 (粘贴提示 refreshClipboardChip, 键盘弹出时
      // didMoveToWindow 同步调用) 读剪贴板会更新共享的
      // clipboardLastSeenChangeCount; 上传若还以它为门, 键盘关闭时复制的
      // 内容会被显示侧先"消费"掉, 同步看到 changeCount 没变就跳过上传,
      // 永远传不到电脑 (键盘里能看到内容, 但电脑收不到)。
      // cachedPasteboardText() 自带缓存: changeCount 未变时不读
      // UIPasteboard、不弹横幅, 所以定时器每秒调一次也不会弹横幅。
      // 注: 2026-11-27 build #56 下载引擎时正撞上 fork 新引擎上传 (clobber),
      // 404 失败, 重推一次 (与代码无关)。
      if let localText = Self.cachedPasteboardText(), !localText.isEmpty {
        if Self.sha256(localText) != lastHash {
          let result = upload(text: localText, to: endpointURL, username: username, password: password)
          if result.success {
            defaults.clipboardSyncLastHash = Self.sha256(localText)
          } else {
            failureReason = failureReasonText(operation: "上传", result: result, passwordLength: password.count)
          }
        }
        // 剪贴板里有文本时只同步文本, 一次同步只传一项 (即使同时含图片也不再传图片)。
      } else {
        // 无文本: 可能是图片。只在 changeCount 移动时才读图片 (读会弹横幅),
        // 用同步自己的"上次检查 changeCount"判断, 不用显示侧共享的那一个
        // (同样会被显示侧先"消费"掉, 图片也传不上去)。
        let currentChangeCount = UIPasteboard.general.changeCount
        if currentChangeCount != defaults.clipboardSyncLastCheckedChangeCount {
          defaults.clipboardSyncLastCheckedChangeCount = currentChangeCount
          if let encoded = Self.localImageData() {
            // 本机剪贴板没有文本, 但有图片: 按服务器图片格式上传 (先传文件, 再传元数据)。
            if Self.sha256(encoded.data) != lastHash {
              let fileName = Self.imageFileName(fileExtension: encoded.fileExtension)
              let fileResult = uploadFile(
                data: encoded.data, fileName: fileName, to: serverURL, username: username, password: password)
              if !fileResult.success {
                failureReason = failureReasonText(operation: "上传", result: fileResult, passwordLength: password.count)
              } else {
                let metaResult = uploadImageMetadata(
                  fileName: fileName, to: endpointURL, username: username, password: password)
                if metaResult.success {
                  defaults.clipboardSyncLastHash = Self.sha256(encoded.data)
                  successNote = "图片已上传"
                } else {
                  failureReason = failureReasonText(operation: "上传", result: metaResult, passwordLength: password.count)
                }
              }
            }
          } else if UIPasteboard.general.image != nil {
            // 有图片, 但编码后仍超过上限 (或编码失败): 本次不同步, 也不反复重试。
            failureReason = "图片过大,未上传"
          }
        }
      }
    #endif

    // 2. 下载服务器最新内容 (若与本机不同则写回)
    let downloadResult = download(from: endpointURL, username: username, password: password)
    if failureReason == nil, !downloadResult.success {
      failureReason = failureReasonText(operation: "下载", result: downloadResult, passwordLength: password.count)
    }
    if let remote = downloadResult.remote {
      // 有附加文件 (图片 / 大文本 / 文件): 先把文件字节下载下来, 再按内容决定怎么放进剪贴板。
      // 旧版 DTO 没有 hasData 字段, 所以只有明确 hasData == false 时才跳过文件下载。
      if let fileName = remote.fileName, !fileName.isEmpty, remote.hasData != false {
        // 远端指纹一致说明已是最新, 连文件都不用下载 (刚上传完的图片只会多取一次文件, 随后记下指纹)。
        if remote.marker == nil || remote.marker != defaults.clipboardSyncLastHash {
          let fileResult = downloadFile(fileName: fileName, from: serverURL, username: username, password: password)
          if !fileResult.success {
            if failureReason == nil {
              failureReason = failureReasonText(operation: "下载", result: fileResult, passwordLength: password.count)
            }
          } else if let fileData = fileResult.data, !fileData.isEmpty {
            if let note = applyDownloadedFile(
              fileData, fileName: fileName, remote: remote, failureReason: &failureReason)
            {
              successNote = note
            }
          }
        }
      } else if let remoteText = remote.text, !remoteText.isEmpty {
        _ = applyRemoteText(remoteText)
      }
    } else if let remoteText = downloadResult.text, !remoteText.isEmpty {
      // 纯文本响应 (参考服务端) 或非 JSON 响应: 沿用旧逻辑。
      _ = applyRemoteText(remoteText)
    }

    if let failureReason {
      recordStatus(failureReason)
    } else if let successNote {
      recordStatus(successNote)
    } else {
      recordStatus("同步成功")
    }
    notifyFinished()
  }

  /// 把远端文本写回本机剪贴板 (哈希与上次同步不同时才写), 返回是否写入。
  /// 不读本机剪贴板比较 (读会弹横幅): lastHash 已是上次同步内容的哈希,
  /// 与它不同即说明服务器内容是新的, 直接写回即可。
  private func applyRemoteText(_ text: String) -> Bool {
    let defaults = UserDefaults.hamster
    let remoteHash = Self.sha256(text)
    guard remoteHash != defaults.clipboardSyncLastHash else { return false }
    #if canImport(UIKit)
      UIPasteboard.general.string = text
      // 写完后 changeCount 会变, 记下新值, 避免下次误以为本机剪贴板变了而重读;
      // 文本一并存进持久化缓存 (第 17 轮第 7 项), 粘贴提示直接用缓存展示。
      defaults.recordLastSeenPasteboard(changeCount: UIPasteboard.general.changeCount, text: text)
    #endif
    defaults.clipboardSyncLastHash = remoteHash
    return true
  }

  /// 处理从服务器下载的文件字节, 返回成功提示 (仅图片写回成功时返回 "图片已同步")。
  /// - 图片字节 → 以原始字节 + UTI 写进剪贴板, 宿主 App 长按即可粘贴;
  /// - 能解码为 UTF-8 文本 → 当文本写回 (超过 10KB 的大文本走的就是这条路);
  /// - 其他二进制 (文件/压缩包等) → 键盘无法粘贴成文件, 只记指纹防重复下载, 状态行说明。
  /// 哈希一律取文件字节的 SHA-256 (上传侧同理), 除非远端给了指纹 (type + 服务器哈希),
  /// 那就记指纹, 下次下载前先比指纹、一致时连文件都不下载。
  private func applyDownloadedFile(
    _ fileData: Data, fileName: String, remote: RemoteClipboard, failureReason: inout String?
  ) -> String? {
    let defaults = UserDefaults.hamster
    let contentHash = Self.sha256(fileData)
    if contentHash == defaults.clipboardSyncLastHash {
      // 字节与上次同步一致 (刚上传完又下载回来): 记下远端指纹, 下次直接跳过下载。
      if let marker = remote.marker {
        defaults.clipboardSyncLastHash = marker
      }
      return nil
    }
    if fileData.count > Self.maxImageDownloadBytes {
      // 已下载完才知道超大: 记下指纹, 避免每秒重复下载一次; 下次内容变了再试。
      defaults.clipboardSyncLastHash = remote.marker ?? contentHash
      if failureReason == nil {
        failureReason = remote.isImageType ? "图片过大,未下载" : "文件过大,未下载"
      }
      return nil
    }
    #if canImport(UIKit)
      if Self.writeImageToPasteboard(fileData, fileName: fileName) {
        // 图片写回: 计数值更新, 文本缓存清空 (剪贴板里是图片, 不是文本)。
        defaults.recordLastSeenPasteboard(changeCount: UIPasteboard.general.changeCount, text: nil)
        defaults.clipboardSyncLastHash = remote.marker ?? contentHash
        return "图片已同步"
      }
    #endif
    if let fileText = String(data: fileData, encoding: .utf8), !fileText.isEmpty {
      #if canImport(UIKit)
        UIPasteboard.general.string = fileText
        defaults.recordLastSeenPasteboard(changeCount: UIPasteboard.general.changeCount, text: fileText)
      #endif
      // 文件字节本身就是这段文本的 UTF-8 编码, 所以记字节哈希与记文本哈希是同一值,
      // 上传侧比 sha256(文本) 也能对上, 不会回声重传。
      defaults.clipboardSyncLastHash = remote.marker ?? contentHash
      return nil
    }
    // 非图片、非文本的二进制: 键盘无法粘贴; 只记指纹, 避免每秒重复下载。
    defaults.clipboardSyncLastHash = remote.marker ?? Self.sha256("remote-file:" + fileName)
    if failureReason == nil {
      failureReason = "收到文件,暂不支持粘贴"
    }
    return nil
  }

  /// 记录最近一次同步结果 (时间 + 成功/失败 + 简短原因), 供剪贴板面板与设置页展示。
  /// 失败只记录状态, 绝不弹框、不阻塞打字。
  private func recordStatus(_ result: String) {
    let time = Self.statusTimeFormatter.string(from: Date())
    UserDefaults.hamster.clipboardSyncLastStatusText = "\(time) \(result)"
  }

  /// 同步失败原因文字。401 时附上密码长度 (仅整数, 绝不含凭据的任何内容):
  /// 服务器对"请求头缺失/格式错"和"用户名或密码错"都返回同一个 401,
  /// 只看 401 无法区分; 密码长度能帮用户判断是不是凭据本身的问题
  /// (例如设置页粘贴时多带了空格, 去空格后长度就对上了)。
  private func failureReasonText(operation: String, result: NetworkResult, passwordLength: Int) -> String {
    if result.statusCode == 401 {
      return "\(operation)失败(HTTP 401, 密码长度 \(passwordLength))"
    }
    return "\(operation)失败(\(result.shortReason))"
  }

  /// 同步结束 (无论成功失败) 后在主线程发通知, 供界面刷新状态行与粘贴提示。
  private func notifyFinished() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: Self.didFinishNotification, object: nil)
    }
  }

  // MARK: - 网络

  /// 单次网络请求的结果 (成功与否 + 文本 + 简短失败原因, 供状态行展示)。
  private struct NetworkResult {
    var success: Bool
    var text: String?
    var statusCode: Int?
    var error: NSError?
    /// 文件下载时返回的原始字节 (仅 downloadFile 填充)。
    var data: Data?
    /// 元数据下载时解析出的远端剪贴板 (仅 download 填充)。
    var remote: RemoteClipboard?

    /// 简短失败原因, 如 "HTTP 405"、"无网络"、"超时"。
    var shortReason: String {
      if let statusCode, !(200...299).contains(statusCode) {
        return "HTTP \(statusCode)"
      }
      if let error {
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
          return "无网络"
        case NSURLErrorTimedOut:
          return "超时"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
          return "找不到服务器"
        default:
          return "网络错误"
        }
      }
      return "未知错误"
    }
  }

  /// 服务器返回的剪贴板元数据 (GET SyncClipboard.json)。
  /// 兼容两种形态 (键名不区分大小写):
  /// - 旧版 ClipboardProfileDTO: {"clipboard": hash, "text": ..., "file": 文件名, "type": "Image"}
  /// - 新版 ProfileDto: {"type": "Image", "hash": ..., "text": 文件名,
  ///   "hasData": true, "dataName": 文件名, "size": ...}
  /// 图片本体永远不在 JSON 里 (不是 base64), 而是单独的文件, 用 GET {base}/file/{fileName} 下载。
  private struct RemoteClipboard {
    var type: String?
    var text: String?
    var fileName: String?
    /// nil 表示服务器没给这个字段 (旧版 DTO 就没有); 只有明确为 false 时才说明没有附加文件。
    var hasData: Bool?
    var hash: String?

    var isImageType: Bool { type?.lowercased() == "image" }

    /// 远端内容的稳定指纹 (type + 服务器哈希): 下载前先比它, 一致时连文件都不用下载。
    /// 注意它与"内容字节哈希"不是同一套值: 上传侧记的是字节哈希, 下载侧记的是这个指纹;
    /// 刚上传完的图片下一次下载会多取一次文件 (随后记下指纹, 不再重复取)。
    var marker: String? {
      guard let hash, !hash.isEmpty else { return nil }
      return ClipboardSyncService.sha256("remote:" + (type ?? "") + ":" + hash)
    }

    static func parse(_ json: [String: Any]) -> RemoteClipboard {
      let lowercased = Dictionary(
        json.map { ($0.key.lowercased(), $0.value) },
        uniquingKeysWith: { first, _ in first })
      // type 可能是字符串 ("Image"/"image"); 若是数字 (C# 枚举默认序列化),
      // 不做硬编码映射, 靠文件名 + 内容嗅探决定。
      let typeString = lowercased["type"] as? String
      return RemoteClipboard(
        type: typeString,
        text: lowercased["text"] as? String,
        fileName: (lowercased["file"] as? String) ?? (lowercased["dataname"] as? String),
        hasData: lowercased["hasdata"] as? Bool,
        hash: (lowercased["hash"] as? String) ?? (lowercased["clipboard"] as? String)
      )
    }
  }

  /// PUT SyncClipboard.json (JSON) 到服务器, 成功返回 true。
  /// 真实 SyncClipboard 服务器只接受 JSON (纯文本会被 415 拒绝),
  /// body 格式: {"type":"Text","text":"...","hasData":false}
  private func upload(text: String, to url: URL, username: String, password: String) -> NetworkResult {
    var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
    request.httpMethod = "PUT"
    let payload: [String: Any] = ["type": "Text", "text": text, "hasData": false]
    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result = NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let http = response as? HTTPURLResponse {
        result.statusCode = http.statusCode
        result.success = (200...299).contains(http.statusCode)
      }
      result.error = error as NSError?
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.requestTimeout + 1)
    return result
  }

  /// PUT 图片元数据到 SyncClipboard.json (JSON)。
  /// body 同时带旧版字段 ("file") 与新版字段 ("dataName"/"hasData"),
  /// 服务器不认识的字段会被忽略; "type" 用 PascalCase "Image",
  /// 与已验证的文本上传 ("Text") 同款写法, 与 C# 枚举名一致。
  /// 不带哈希字段: 服务器收到后会自己算 (带错了反而会在校验时 400)。
  private func uploadImageMetadata(fileName: String, to url: URL, username: String, password: String) -> NetworkResult {
    var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
    request.httpMethod = "PUT"
    let payload: [String: Any] = [
      "type": "Image",
      "text": fileName,
      "file": fileName,
      "dataName": fileName,
      "hasData": true,
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result = NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let http = response as? HTTPURLResponse {
        result.statusCode = http.statusCode
        result.success = (200...299).contains(http.statusCode)
      }
      result.error = error as NSError?
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.requestTimeout + 1)
    return result
  }

  /// PUT 原始文件字节到 {base}/file/{fileName} (Content-Type: application/octet-stream)。
  /// 真实服务器要求先传文件、再传 SyncClipboard.json (后者会校验文件已存在, 否则 400)。
  private func uploadFile(data: Data, fileName: String, to baseURL: URL, username: String, password: String) -> NetworkResult {
    guard let url = Self.fileURL(for: baseURL, fileName: fileName) else {
      return NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    }
    var request = URLRequest(url: url, timeoutInterval: Self.fileTimeout)
    request.httpMethod = "PUT"
    request.httpBody = data
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result = NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let http = response as? HTTPURLResponse {
        result.statusCode = http.statusCode
        result.success = (200...299).contains(http.statusCode)
      }
      result.error = error as NSError?
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.fileTimeout + 1)
    return result
  }

  /// GET 服务器最新剪贴板 (纯文本, 或 {"text": "..."} JSON, 或含 file/dataName 的图片元数据)
  private func download(from url: URL, username: String, password: String) -> NetworkResult {
    var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
    request.httpMethod = "GET"
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result = NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let http = response as? HTTPURLResponse {
        result.statusCode = http.statusCode
        result.success = (200...299).contains(http.statusCode)
      }
      result.error = error as NSError?
      guard result.success, let data = data, !data.isEmpty else { return }
      // 先尝试 JSON {"text": "..."}, 否则按纯文本处理
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let remote = RemoteClipboard.parse(json)
        result.remote = remote
        result.text = remote.text
      } else {
        result.text = String(data: data, encoding: .utf8)
      }
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.requestTimeout + 1)
    return result
  }

  /// GET {base}/file/{fileName}, 返回原始文件字节 (图片 / 大文本 / 文件共用)。
  private func downloadFile(fileName: String, from baseURL: URL, username: String, password: String) -> NetworkResult {
    guard let url = Self.fileURL(for: baseURL, fileName: fileName) else {
      return NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    }
    var request = URLRequest(url: url, timeoutInterval: Self.fileTimeout)
    request.httpMethod = "GET"
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result = NetworkResult(success: false, text: nil, statusCode: nil, error: nil)
    URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let http = response as? HTTPURLResponse {
        result.statusCode = http.statusCode
        result.success = (200...299).contains(http.statusCode)
      }
      result.error = error as NSError?
      guard result.success, let data = data, !data.isEmpty else { return }
      result.data = data
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.fileTimeout + 1)
    return result
  }

  private func applyBasicAuth(to request: inout URLRequest, username: String, password: String) {
    guard !username.isEmpty else { return }
    let credentials = "\(username):\(password)"
    guard let data = credentials.data(using: .utf8) else { return }
    request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
  }

  // MARK: - 图片编解码 (仅 UIKit)

  #if canImport(UIKit)
    /// 图片文件名: 与服务端 ImageProfile.CreateImageFileName() 的 Image_<时间戳>.png 同款格式。
    private static func imageFileName(fileExtension: String) -> String {
      "Image_\(imageFileNameFormatter.string(from: Date())).\(fileExtension)"
    }

    /// 读取本机剪贴板里的图片, 返回 (原始字节, 扩展名)。
    /// 优先直接取剪贴板里的原始图片字节 (public.png/public.jpeg/public.heic):
    /// 不解码、不重编码, 不丢画质、不丢动图, 内存也安全;
    /// 只有取不到原始字节时才走 UIImage 重编码 (超大图先缩到 2048px 再编码)。
    /// 原始字节过大时改走重编码 + 缩放路线; 重编码后仍超上限则返回 nil。
    private static func localImageData() -> (data: Data, fileExtension: String)? {
      for (uti, ext) in [("public.png", "png"), ("public.jpeg", "jpg"), ("public.heic", "heic")] {
        if let data = UIPasteboard.general.data(forPasteboardType: uti), !data.isEmpty {
          if data.count <= Self.maxImageUploadBytes {
            return (data, ext)
          }
          break // 原始字节过大, 改走重编码 + 缩放路线
        }
      }
      guard let image = UIPasteboard.general.image else { return nil }
      let scaled = downscaled(image)
      if imageHasAlpha(scaled) {
        if let png = scaled.pngData(), !png.isEmpty, png.count <= Self.maxImageUploadBytes {
          return (png, "png")
        }
        // PNG 太大 (带透明通道的大图): 退回 JPEG (丢透明, 但能同步); 仍太大则放弃
        if let jpg = scaled.jpegData(compressionQuality: 0.85), !jpg.isEmpty,
          jpg.count <= Self.maxImageUploadBytes
        {
          return (jpg, "jpg")
        }
        return nil
      }
      if let jpg = scaled.jpegData(compressionQuality: 0.85), !jpg.isEmpty,
        jpg.count <= Self.maxImageUploadBytes
      {
        return (jpg, "jpg")
      }
      if let png = scaled.pngData(), !png.isEmpty, png.count <= Self.maxImageUploadBytes {
        return (png, "png")
      }
      return nil
    }

    /// 图片是否有透明通道 (取不到 CGImage 时按有透明通道处理, 走 PNG, 更安全)。
    private static func imageHasAlpha(_ image: UIImage) -> Bool {
      guard let alphaInfo = image.cgImage?.alphaInfo else { return true }
      switch alphaInfo {
      case .none, .noneSkipFirst, .noneSkipLast:
        return false
      default:
        return true
      }
    }

    /// 超大图等比缩小到最长边 2048px (键盘扩展内存约 50MB, 不能全尺寸解码);
    /// 不超则原样返回。
    private static func downscaled(_ image: UIImage) -> UIImage {
      let pixelWidth: CGFloat
      let pixelHeight: CGFloat
      if let cgImage = image.cgImage {
        pixelWidth = CGFloat(cgImage.width)
        pixelHeight = CGFloat(cgImage.height)
      } else {
        pixelWidth = image.size.width * image.scale
        pixelHeight = image.size.height * image.scale
      }
      let maxSide = max(pixelWidth, pixelHeight)
      guard maxSide > Self.maxImageDimension else { return image }
      let scale = Self.maxImageDimension / maxSide
      let targetSize = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = false
      return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }
    }

    /// 把图片字节写到本机剪贴板, 供宿主 App 长按粘贴。返回是否成功写成图片。
    /// 优先用原始字节 + UTI (setItems): 不解码、不转码, 零内存尖峰, GIF 动图也能保留;
    /// 只有文件头和扩展名都认不出的格式才返回 false (由调用方按文本/不支持处理),
    /// 避免在键盘扩展里对超大图做全尺寸解码。
    /// 键盘扩展不能经 textDocumentProxy 插入图片 (只支持文本), 写剪贴板是唯一正确路线。
    private static func writeImageToPasteboard(_ data: Data, fileName: String?) -> Bool {
      guard let uti = imagePasteboardType(for: data, fileName: fileName) else { return false }
      UIPasteboard.general.setItems([[uti: data]])
      return true
    }

    /// 按文件头 (最可靠) 其次按扩展名, 判断图片字节对应的剪贴板 UTI。
    /// 认不出的格式返回 nil (例如 webp: iOS 原生解码也不支持, 粘贴了也没用)。
    private static func imagePasteboardType(for data: Data, fileName: String?) -> String? {
      if data.count >= 4 {
        let header = [UInt8](data.prefix(4))
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
          return "public.png"
        }
        if header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
          return "public.jpeg"
        }
        if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x38 {
          return "com.compuserve.gif"
        }
      }
      if data.count >= 12 {
        let bytes = [UInt8](data.prefix(12))
        // ftyp box: 第 5~8 字节为 "ftyp", 随后是品牌 (heic/heix/mif1/...)
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
          let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
          if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) {
            return "public.heic"
          }
        }
      }
      guard let fileName else { return nil }
      switch (fileName as NSString).pathExtension.lowercased() {
      case "png": return "public.png"
      case "jpg", "jpeg": return "public.jpeg"
      case "gif": return "com.compuserve.gif"
      case "heic", "heif": return "public.heic"
      default: return nil
      }
    }
  #endif

  // MARK: - 工具

  /// 文本的 SHA-256 (公开, 供工具栏用内容哈希去重: 相同内容不再重复提示)。
  public static func sha256(_ text: String) -> String {
    sha256(Data(text.utf8))
  }

  /// 字节的 SHA-256 (公开, 与文本版同一格式): 图片同步的防回声哈希即取图片字节的 SHA-256。
  public static func sha256(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
