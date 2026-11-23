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

  /// 同步端点路径: 真实 SyncClipboard 服务器固定为 /SyncClipboard.json
  private static let syncEndpointPath = "SyncClipboard.json"

  private static let statusTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  /// 串行队列, 避免并发读写剪贴板
  private let queue = DispatchQueue(label: "dev.fuxiao.app.Hamster.ClipboardSync", qos: .utility)

  private var lastAttempt: Date?

  /// 是否正在同步 (只在串行队列上读写)。定时器每 1 秒调一次 syncNow(),
  /// 若上一次同步 (弱网时最多等 4 秒) 还没结束, 新的直接跳过, 不堆积。
  private var isSyncing = false

  /// 服务最后一次读写剪贴板时的 changeCount (只在串行队列上读写)。
  /// 读剪贴板会弹"粘贴自xxx"横幅, 所以上传前先比 changeCount:
  /// 没变说明本机剪贴板还是上次同步过的内容, 直接跳过读取 (不弹横幅);
  /// 写回服务器内容后也更新它, 避免下次误以为本机剪贴板变了而重读。
  /// nil 表示从未读写过 (首次同步一定读)。
  private var lastSeenPasteboardChangeCount: Int?

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

  // MARK: - 同步主流程

  private func sync() {
    let defaults = UserDefaults.hamster
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
    #if canImport(UIKit)
      // 只有剪贴板真的变了 (changeCount 移动) 才读内容; 没变直接跳过读取,
      // 否则定时器每 1 秒调一次就会每 1 秒弹一次横幅。
      // changeCount 是个整数, 读它不弹横幅。
      let currentChangeCount = UIPasteboard.general.changeCount
      if currentChangeCount != lastSeenPasteboardChangeCount {
        lastSeenPasteboardChangeCount = currentChangeCount
        let localText = UIPasteboard.general.string
        if let localText = localText, !localText.isEmpty, Self.sha256(localText) != lastHash {
          let result = upload(text: localText, to: endpointURL, username: username, password: password)
          if result.success {
            defaults.clipboardSyncLastHash = Self.sha256(localText)
          } else {
            failureReason = failureReasonText(operation: "上传", result: result, passwordLength: password.count)
          }
        }
      }
    #endif

    // 2. 下载服务器最新内容 (若与本机不同则写回)
    let downloadResult = download(from: endpointURL, username: username, password: password)
    if failureReason == nil, !downloadResult.success {
      failureReason = failureReasonText(operation: "下载", result: downloadResult, passwordLength: password.count)
    }
    if let remoteText = downloadResult.text, !remoteText.isEmpty {
      let remoteHash = Self.sha256(remoteText)
      if remoteHash != defaults.clipboardSyncLastHash {
        #if canImport(UIKit)
          // 不读本机剪贴板比较 (读会弹横幅): lastHash 已是上次同步内容的哈希,
          // 与它不同即说明服务器内容是新的, 直接写回即可。
          UIPasteboard.general.string = remoteText
          // 写完后 changeCount 会变, 记下新值, 避免下次误以为本机剪贴板变了而重读
          lastSeenPasteboardChangeCount = UIPasteboard.general.changeCount
        #endif
        defaults.clipboardSyncLastHash = remoteHash
      }
    }

    if let failureReason {
      recordStatus(failureReason)
    } else {
      recordStatus("同步成功")
    }
    notifyFinished()
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

  /// GET 服务器最新剪贴板 (纯文本, 或 {"text": "..."} JSON)
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
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let text = json["text"] as? String
      {
        result.text = text
      } else {
        result.text = String(data: data, encoding: .utf8)
      }
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.requestTimeout + 1)
    return result
  }

  private func applyBasicAuth(to request: inout URLRequest, username: String, password: String) {
    guard !username.isEmpty else { return }
    let credentials = "\(username):\(password)"
    guard let data = credentials.data(using: .utf8) else { return }
    request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
  }

  // MARK: - 工具

  /// 文本的 SHA-256 (公开, 供工具栏用内容哈希去重: 相同内容不再重复提示)。
  public static func sha256(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
