//
//  ClipboardSyncService.swift
//  HamsterKit
//
//  跨设备剪贴板同步服务（键盘触发式，类似微信输入法的做法）:
//
//  触发时机: 键盘每次弹出时 (KeyboardInputViewController.viewWillAppear)。
//  流程:
//    1. 读取本机剪贴板 (UIPasteboard)，若与上次同步内容不同则上传到服务器;
//    2. 从服务器下载最新一条剪贴板，若与本机不同则写回本机剪贴板。
//  因此另一台设备打开键盘时，就能拿到这边复制的内容。
//
//  服务器协议 (极简 HTTP, 任何能实现 GET/PUT 的服务器都能用):
//    上传: PUT {serverURL}, Body 为纯文本剪贴板内容
//    下载: GET {serverURL}, 响应 Body 为纯文本; 若为 JSON 则解析 {"text": "..."}
//    鉴权: 若配置了用户名/密码, 则附加 HTTP Basic Auth
//    服务器只需保存"最新一条"剪贴板内容即可, 仓库 Tools/ 下附了一个
//    极简参考服务端 (clipboard-sync-server.py)。
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

  /// 每次键盘弹出后最短同步间隔 (秒), 避免快速切换键盘时频繁请求
  private static let minSyncInterval: TimeInterval = 10

  /// 单次网络请求超时 (秒)
  private static let requestTimeout: TimeInterval = 3

  /// 串行队列, 避免并发读写剪贴板
  private let queue = DispatchQueue(label: "dev.fuxiao.app.Hamster.ClipboardSync", qos: .utility)

  private var lastAttempt: Date?

  private init() {}

  // MARK: - 入口

  /// 键盘弹出时调用: 先上传本机剪贴板, 再下载服务器最新内容。
  /// 内部节流、异步执行、失败静默, 不会阻塞键盘与打字。
  public func syncOnKeyboardAppear() {
    queue.async { [weak self] in
      guard let self = self else { return }
      let now = Date()
      if let last = self.lastAttempt, now.timeIntervalSince(last) < Self.minSyncInterval {
        return
      }
      self.lastAttempt = now
      self.sync()
    }
  }

  // MARK: - 同步主流程

  private func sync() {
    let defaults = UserDefaults.hamster
    guard defaults.clipboardSyncEnabled else { return }
    guard let serverURL = URL(string: defaults.clipboardSyncServerURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      serverURL.scheme == "http" || serverURL.scheme == "https"
    else { return }

    let username = defaults.clipboardSyncUsername
    let password = defaults.clipboardSyncPassword
    let lastHash = defaults.clipboardSyncLastHash

    // 1. 上传本机剪贴板 (若与上次同步内容不同)
    #if canImport(UIKit)
      let localText = UIPasteboard.general.string
      if let localText = localText, !localText.isEmpty, Self.sha256(localText) != lastHash {
        if upload(text: localText, to: serverURL, username: username, password: password) {
          defaults.clipboardSyncLastHash = Self.sha256(localText)
        }
      }
    #endif

    // 2. 下载服务器最新内容 (若与本机不同则写回)
    guard let remoteText = download(from: serverURL, username: username, password: password),
      !remoteText.isEmpty
    else { return }
    let remoteHash = Self.sha256(remoteText)
    guard remoteHash != defaults.clipboardSyncLastHash else { return }

    #if canImport(UIKit)
      let currentLocal = UIPasteboard.general.string
      if currentLocal != remoteText {
        UIPasteboard.general.string = remoteText
      }
    #endif
    defaults.clipboardSyncLastHash = remoteHash
  }

  // MARK: - 网络

  /// PUT 纯文本到服务器, 成功返回 true
  private func upload(text: String, to url: URL, username: String, password: String) -> Bool {
    var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
    request.httpMethod = "PUT"
    request.httpBody = text.data(using: .utf8)
    request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var succeeded = false
    URLSession.shared.dataTask(with: request) { _, response, _ in
      if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
        succeeded = true
      }
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + Self.requestTimeout + 1)
    return succeeded
  }

  /// GET 服务器最新剪贴板 (纯文本, 或 {"text": "..."} JSON)
  private func download(from url: URL, username: String, password: String) -> String? {
    var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
    request.httpMethod = "GET"
    applyBasicAuth(to: &request, username: username, password: password)

    let semaphore = DispatchSemaphore(value: 0)
    var result: String?
    URLSession.shared.dataTask(with: request) { data, response, _ in
      defer { semaphore.signal() }
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
        let data = data, !data.isEmpty
      else { return }
      // 先尝试 JSON {"text": "..."}, 否则按纯文本处理
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let text = json["text"] as? String
      {
        result = text
      } else {
        result = String(data: data, encoding: .utf8)
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

  static func sha256(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
