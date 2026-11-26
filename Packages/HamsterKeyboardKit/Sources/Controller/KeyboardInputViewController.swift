//
//  KeyboardViewController.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2018-03-13.
//  Copyright © 2018-2023 Daniel Saidi. All rights reserved.
//

import Combine
import HamsterKit
import OSLog
import UIKit

/**
 This class extends `UIInputViewController` with KeyboardKit
 specific functionality.

 该类扩展了 `UIInputViewController` 的 KeyboardKit 特定功能。

 When you use KeyboardKit, simply inherit this class instead
 of `UIInputViewController` to extend your controller with a
 set of additional lifecycle functions, properties, services
 etc. such as ``viewWillSetupKeyboard()``, ``keyboardContext``
 and ``keyboardActionHandler``.

 当您使用 KeyboardKit 时，只需继承该类而非 `UIInputViewController` 类，
 即可使用一组附加的生命周期函数、属性、服务等来扩展您的控制器，
 例如 `viewWillSetupKeyboard()``、`keyboardContext`` 和 `keyboardActionHandler``。

 You may notice that KeyboardKit's own views use initializer
 parameters instead of environment objects. It's intentional,
 to better communicate the dependencies of each view.

 您可能会注意到，KeyboardKit 自己的视图使用初始化器参数而非环境对象。这是有意为之，以便更好地传达每个视图的依赖关系。
 */
open class KeyboardInputViewController: UIInputViewController, KeyboardController {
  /// 常用语补全点选上屏后, 文档变化会再触发一次 textDidChange:
  /// 那一次不重算补全 (否则刚插的短语尾巴, 如邮箱的 com, 可能
  /// 立刻又挂出另一条补全)。点选回调里置 true, 下次触发时消费掉。
  private var phraseCompletionSuppressNextTextChange = false

  // MARK: - View Controller Lifecycle ViewController 生命周期

  override open func viewDidLoad() {
    super.viewDidLoad()
    // setupInitialWidth()
    // setupLocaleObservation()
    // setupNextKeyboardBehavior()
    // KeyboardUrlOpener.shared.controller = self
    setupCombineRIMEInput()
  }

  override open func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    setupRIME()
    // 震动/声音设置刷新 (第 14 轮第 2 项): 若启动瞬间 plist 没读到,
    // 设置会被缓存为 .noFeedback 且永不重试; 每次弹出时重算一次,
    // 配置就位后震动随下次弹出恢复。无变化时零影响。
    refreshKeyboardFeedbackSettings()
    viewWillSetupKeyboard()
    viewWillSyncWithContext()

    // 剪贴板同步 (键盘触发式): 键盘弹出时上传本机剪贴板、下载服务器最新内容。
    // 内部节流、异步、失败静默, 不阻塞打字。需开启"允许完全访问"才生效。
    ClipboardSyncService.shared.syncOnKeyboardAppear()

    // fix: 屏幕边缘按键触摸延迟
    // https://stackoverflow.com/questions/39813245/touchesbeganwithevent-is-delayed-at-left-edge-of-screen
    // 注意：添加代码日志中会有警告
    // [Warning] Trying to set delaysTouchesBegan to NO on a system gate gesture recognizer - this is unsupported and will have undesired side effects
    // 如果后续有更好的解决方案，可以替换此方案
    view.window?.gestureRecognizers?.forEach {
      $0.delaysTouchesBegan = false
    }
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
//    viewWillHandleDictationResult()
  }

  override open func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Logger.statistics.debug("KeyboardInputViewController: viewDidLayoutSubviews()")
    keyboardContext.syncAfterLayout(with: self)
  }

  override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    // Logger.statistics.info("controller traitCollectionDidChange()")
    super.traitCollectionDidChange(previousTraitCollection)
    viewWillSyncWithContext()
  }

  /// 内存回收
//  override open func didReceiveMemoryWarning() {
//    shutdownRIME()
//    setupRIME()
//  }

  // MARK: - Keyboard View Controller Lifecycle

  /**
   This function is called whenever the keyboard view must
   be created or updated.

   每当必须创建或更新键盘视图时，都会调用该函数。

   This will by default set up a ``KeyboardRootView`` as the
   main view, but you can override it to use a custom view.

   默认情况下，这将设置一个 "KeyboardRootView"（系统键盘）作为主视图，但你可以覆盖它以使用自定义视图。
   */

  open func viewWillSetupKeyboard() {
    let keyboardRootView = KeyboardRootView(
      keyboardLayoutProvider: keyboardLayoutProvider,
      appearance: keyboardAppearance,
      actionHandler: keyboardActionHandler,
      keyboardContext: keyboardContext,
      calloutContext: calloutContext,
      rimeContext: rimeContext
    )

    // 设置键盘的View
    keyboardRootView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyboardRootView)
    NSLayoutConstraint.activate([
      keyboardRootView.topAnchor.constraint(equalTo: view.topAnchor),
      keyboardRootView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardRootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardRootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  deinit {
    view.subviews.forEach { $0.removeFromSuperview() }
  }

  /**
   This function is called whenever the controller must be
   synced with its ``keyboardContext``.

   每当 controller 必须与其 ``keyboardContext`` 同步时，就会调用此函数。

   This will by default sync with keyboard contexts if the
   ``isContextSyncEnabled`` is `true`. You can override it
   to customize syncing or sync with more contexts.

   如果 ``isContextSyncEnabled`` 为 `true`，默认情况下将与 KeyboardContext 同步。
   你可以覆盖它以自定义同步或与更多上下文同步。
   */
  open func viewWillSyncWithContext() {
    keyboardContext.sync(with: self)
    keyboardTextContext.sync(with: self)
  }

  // MARK: - Combine

  var cancellables = Set<AnyCancellable>()

  // MARK: - Properties

  /**
   The original text document proxy that was used to start
   the keyboard extension.

   用于启动键盘扩展程序的原生文本文档代理。

   This stays the same even if a ``textInputProxy`` is set,
   which makes ``textDocumentProxy`` return the custom one
   instead of the original one.

   即使设置了 ``textInputProxy`` 也不会改变，这将使 ``textDocumentProxy`` 返回自定义的文档，而不是原始文档。
   */
  open var mainTextDocumentProxy: UITextDocumentProxy {
    super.textDocumentProxy
  }

  /**
   The text document proxy to use, which can either be the
   original text input proxy or the ``textInputProxy``, if
   it is set to a custom value.

   要使用的 document proxy，可以是原生的文本输入代理，也可以是 ``textInputProxy``（如果设置为自定义值）。
   */
  override open var textDocumentProxy: UITextDocumentProxy {
//    textInputProxy ?? mainTextDocumentProxy
    mainTextDocumentProxy
  }

  /**
   A custom text input proxy to which text can be routed.

   自定义文本输入代理，可将文本传送到该代理。

   Setting the property makes ``textDocumentProxy`` return
   the custom proxy instead of the original one.

   设置该属性可使 ``textDocumentProxy`` 返回自定义代理，而不是原始代理。
   */
//  public var textInputProxy: TextInputProxy? {
//    didSet { viewWillSyncWithContext() }
//  }

  // MARK: - Observables

  /**
   The default, observable autocomplete context.

   默认的、可观察的自动完成上下文。

   This context is used as global state for the keyboard's
   autocomplete, e.g. the current suggestions.

   该上下文用作键盘自动完成的全局状态，例如当前建议。
   */
  public lazy var autocompleteContext = AutocompleteContext()

  /**
   The default, observable callout context.

   默认的可观察呼出上下文。

   This is used as global state for the callouts that show
   the currently typed character.

   这将作为显示当前键入字符的呼出的全局状态。
   */
  public lazy var calloutContext = KeyboardCalloutContext(
    action: ActionCalloutContext(
      actionHandler: keyboardActionHandler,
      actionProvider: calloutActionProvider
    ),
    input: InputCalloutContext(
      isEnabled: UIDevice.current.userInterfaceIdiom == .phone)
  )

  /**
   The default, observable dictation context.

   默认的, 可观测听写上下文。

   This is used as global dictation state and will be used
   to communicate between an app and its keyboard.

   这是全局听写状态，将用于应用程序与其键盘之间的通信。
   */
  // public lazy var dictationContext = DictationContext()

  /**
   The default, observable keyboard context.

   默认的, 可观察键盘上下文。

   This is used as global state for the keyboard's overall
   state and configuration like locale, device, screen etc.

   这是键盘整体状态和配置（如本地、设备、屏幕等）的全局状态。
   */
  public lazy var keyboardContext = KeyboardContext(controller: self)

  /**
   The default, observable feedback settings.

   默认的，可观察的反馈设置。

   This property is used as a global configuration for the
   keyboard's feedback, e.g. audio and haptic feedback.

   该属性用作键盘反馈（如音频和触觉反馈）的全局配置。
   */
  public lazy var keyboardFeedbackSettings: KeyboardFeedbackSettings = buildKeyboardFeedbackSettings()

  /// 按当前 hamsterConfiguration 算出震动/声音设置 (与旧 lazy 闭包同一算法)。
  /// (第 14 轮第 2 项: 抽出来, 供 viewWillAppear 的刷新复用, 并打日志;
  /// 震动失效时, 下次出现可从日志直接看出是配置没读到、开关关了、还是
  /// 开着却不震。)
  func buildKeyboardFeedbackSettings() -> KeyboardFeedbackSettings {
    let configMissing = keyboardContext.hamsterConfiguration == nil
    let enableAudio = keyboardContext.hamsterConfiguration?.keyboard?.enableKeySounds ?? false
    let enableHaptic = keyboardContext.hamsterConfiguration?.keyboard?.enableHapticFeedback ?? false
    let hapticFeedbackIntensity = keyboardContext.hamsterConfiguration?.keyboard?.hapticFeedbackIntensity ?? 2
    let hapticFeedback = HapticIntensity(rawValue: hapticFeedbackIntensity)?.hapticFeedback() ?? .mediumImpact
    Logger.statistics.info("keyboard feedback settings: configMissing \(configMissing), enableAudio \(enableAudio), enableHaptic \(enableHaptic), intensity \(hapticFeedbackIntensity)")
    return KeyboardFeedbackSettings(
      audioConfiguration: enableAudio ? .enabled : .noFeedback,
      hapticConfiguration: enableHaptic ? .init(
        tap: hapticFeedback,
        doubleTap: hapticFeedback,
        longPress: hapticFeedback,
        longPressOnSpace: hapticFeedback,
        repeat: .selectionChanged
      ) : .noFeedback
    )
  }

  /// 每次键盘出现时刷新震动/声音设置 (第 14 轮第 2 项)。
  /// 机制: keyboardFeedbackSettings 是 class (ObservableObject), 反馈
  /// handler 持有同一对象, 原地改 @Published 配置立即生效, 不用重建
  /// handler。只在配置确实变了时才写, 平时零影响。
  /// 触发场景: 扩展进程启动瞬间 plist 还没就位 (部署换文件窗口期) 时
  /// 配置读不到, 设置被缓存为 .noFeedback 且永不重试——这次刷新会先
  /// 重读 plist, 再把算出来的设置写回去, 震动随键盘下次弹出恢复。
  func refreshKeyboardFeedbackSettings() {
    if keyboardContext.hamsterConfiguration == nil {
      keyboardContext.reloadHamsterConfiguration()
    }
    let fresh = buildKeyboardFeedbackSettings()
    if keyboardFeedbackSettings.hapticConfiguration != fresh.hapticConfiguration
      || keyboardFeedbackSettings.audioConfiguration != fresh.audioConfiguration {
      Logger.statistics.info("keyboard feedback settings changed, refreshing in place")
      keyboardFeedbackSettings.hapticConfiguration = fresh.hapticConfiguration
      keyboardFeedbackSettings.audioConfiguration = fresh.audioConfiguration
    }
  }

  /**
   The default, observable keyboard text context.

   默认的、可观察到的键盘文本上下文。

   This is used as global state to let you observe text in
   the ``textDocumentProxy``.

   这将作为全局状态，让您观察 ``textDocumentProxy`` 中的文本。
   */
  public lazy var keyboardTextContext = KeyboardTextContext()

  // MARK: - Services

  /**
   The autocomplete provider that is used to provide users
   with autocomplete suggestions.

   用于向用户提供自动完成建议的自动完成 provider。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var autocompleteProvider: AutocompleteProvider = EnglishSpellcheckAutocompleteProvider()

  /**
   The callout action provider that is used to provide the
   keyboard with secondary callout actions.

   用于为键盘提供辅助呼出操作的呼出操作 provider。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var calloutActionProvider: CalloutActionProvider = StandardCalloutActionProvider(
    keyboardContext: keyboardContext
  ) {
    didSet { refreshProperties() }
  }

  /**
   The input set provider that is used to define the input
   keys of the keyboard.

   输入集提供程序，用于定义键盘的输入键。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var inputSetProvider: InputSetProvider = StandardInputSetProvider(
    keyboardContext: keyboardContext
  ) {
    didSet { refreshProperties() }
  }

  /**
   The action handler that will be used by the keyboard to
   handle keyboard actions.

   用于处理按键 action 的 action 处理程序。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardActionHandler: KeyboardActionHandler = StandardKeyboardActionHandler(
    controller: self,
    keyboardContext: keyboardContext,
    rimeContext: rimeContext,
    keyboardBehavior: keyboardBehavior,
    autocompleteContext: autocompleteContext,
    keyboardFeedbackHandler: keyboardFeedbackHandler,
    spaceDragGestureHandler: SpaceCursorDragGestureHandler(
      feedbackHandler: keyboardFeedbackHandler,
      sensitivity: .custom(points: keyboardContext.hamsterConfiguration?.swipe?.spaceDragSensitivity ?? 5),
      action: { [weak self] in
        guard let self = self else { return }
        let offset = self.textDocumentProxy.spaceDragOffset(for: $0)
        self.adjustTextPosition(byCharacterOffset: offset ?? $0)
      }
    )
  ) {
    didSet { refreshProperties() }
  }

  /**
   The appearance that is used to customize the keyboard's
   design, such as its colors, fonts etc.

   用于自定义键盘的外观，如颜色、字体等。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardAppearance: KeyboardAppearance = StandardKeyboardAppearance(keyboardContext: keyboardContext)

  /**
   The behavior that is used to determine how the keyboard
   should behave when certain things happen.

   用于确定在某些事情发生时键盘应表现的行为。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardBehavior: KeyboardBehavior = StandardKeyboardBehavior(keyboardContext: keyboardContext)

  /**
   The feedback handler that is used to trigger haptic and
   audio feedback.

   用于触发触觉和音频反馈的反馈处理程序。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardFeedbackHandler: KeyboardFeedbackHandler = StandardKeyboardFeedbackHandler(settings: keyboardFeedbackSettings)

  /**
   This keyboard layout provider that is used to setup the
   complete set of keys and their layout.

   此键盘布局 provider 用于设置整套键盘按键及其布局。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardLayoutProvider: KeyboardLayoutProvider = StandardKeyboardLayoutProvider(
    keyboardContext: keyboardContext,
    inputSetProvider: inputSetProvider
  )

  /**
   RIME 引擎上下文
   */
  public lazy var rimeContext = RimeContext()

  // MARK: - Text And Selection, Implementations UITextInputDelegate

  /// 当文档中的选择即将发生变化时，通知输入委托。
  override open func selectionWillChange(_ textInput: UITextInput?) {
    super.selectionWillChange(textInput)
    resetAutocomplete()
  }

  /// 当文档中的选择发生变化时，通知输入委托。
  override open func selectionDidChange(_ textInput: UITextInput?) {
    super.selectionDidChange(textInput)
    resetAutocomplete()
  }

  /// 当 Document 中的 text 即将发生变化时，通知输入委托。
  /// - parameters:
  ///   * textInput: 采用 UITextInput 协议的文档实例。
  override open func textWillChange(_ textInput: UITextInput?) {
    super.textWillChange(textInput)

    // fix: 键盘跟随环境显示数字键盘
    if let keyboardType = textDocumentProxy.keyboardType, keyboardType.isNumberType {
      keyboardContext.setKeyboardType(.numericNineGrid)
    }

    if keyboardContext.textDocumentProxy === textDocumentProxy { return }
    keyboardContext.textDocumentProxy = textDocumentProxy
  }

  /// 当 Document 中的 text 发生变化时，通知输入委托。
  /// - parameters:
  ///   * textInput: 采用 UITextInput 协议的文档实例。
  override open func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
//    performAutocomplete()
//    performTextContextSync()
//    tryChangeToPreferredKeyboardTypeAfterTextDidChange()

    // fix: 输出栏点击右侧x形按钮后, 输入法候选栏内容没有跟随输入栏一同清空
    if !self.textDocumentProxy.hasText {
      self.rimeContext.reset()
    }

    // 常用语补全 (英文/数字键盘): 打字不走 RIME, userInputKey 为空,
    // 按光标前连续的字母/数字串查常用语前缀, 挂进候选栏。
    updatePhraseCompletionForDirectInput()

    // 英文纠错 (第 15 轮第 2 项 b): 只在英文 26 键下跑 UITextChecker;
    // 中文键盘走 RIME, 绝不进这里——中文词一旦当成英文查, 会被当成错词,
    // 下一个空格就会把中文词换成英文 guess。放 textDidChange 而不是按键
    // 处理, 是因为删字/粘贴也走这里, 一处覆盖全部。
    if keyboardContext.keyboardType.isAlphabetic {
      performAutocomplete()
    }

    // 撤回快照的兜底失效 (选词/粘贴/外部改动后文档变了, 各入口的
    // 直接失效没覆盖到的情况): 删除刚完成时光标前是空的; 若光标前
    // 出现了与快照不同的文字, 说明是删除之后的改动, 快照作废。
    // 进行中标志 + 0.3s 宽限期挡住删除批次自己的回声 (回声到达时
    // 光标前仍是空的, 本来也不会误判, 标志是双保险)。
    if !isPerformingSwipeDelete, let snapshot = undoDeleteSnapshot, !snapshot.isEmpty {
      let before = textDocumentProxy.documentContextBeforeInput ?? ""
      if !before.isEmpty && before != snapshot {
        invalidateUndoDeleteSnapshot()
      }
    }
  }

  /// 直输键盘判定: 字母/数字不进 RIME 组字、直接上屏的键盘,
  /// 常用语补全只能走 textDidChange 直输路 (不走 syncContext)。
  /// 补全触发与切键盘清理共用同一判定, 否则两边口径不一。
  /// 覆盖三种情况:
  /// - .alphabetic 英文键盘 (字母直接上屏);
  /// - 数字键盘 (type.isNumber: .numeric / .chineseNumeric /
  ///   .numericNineGrid; 123 页是 .chineseNumeric, 不是 .numeric);
  /// - 中/英切换后的 asciiMode: hamster.yaml 里
  ///   displayChineseEnglishSwitchButton: false, layout 的中英切换键
  ///   是关的, 中英切换是空格上滑 shortcut (#中英切换), 只切
  ///   asciiMode 不切键盘类型 (类型仍是 .chinese / .chineseNineGrid),
  ///   字母经 RIME 直接上屏、不组字。#43 只认 .alphabetic/.numeric,
  ///   所以英文直输完全没进过补全, 这就是 Bug B 英文不触发的原因。
  private func isDirectInputKeyboard(_ type: KeyboardType) -> Bool {
    type.isAlphabetic || type.isNumber || rimeContext.asciiMode
  }

  /// 英文/数字键盘的常用语补全触发。调用点有四处, 互为备份 (幂等):
  /// textDidChange、insertTextPatch 末尾 (数字键 insertSymbol 与
  /// 英文 asciiMode 提交都走这里)、insertText 的 .alphabetic 分支、
  /// deleteBackward 无组字分支。只靠 textDidChange 在真机上不触发
  /// (build #44 回归: 类型判定修对了, 但补全始终出不来; 九宫格拼音
  /// 走 RIME syncContext 不受影响), 所以插入/删除后同步触发一次,
  /// 直接读刚写完的文档, 不依赖 textDidChange 是否回调。
  /// 数字键盘 (123 页 = .chineseNumeric / .numericNineGrid, 不是
  /// .numeric) 按光标前连续数字查; 英文直输 (.alphabetic, 或中文键盘
  /// 中/英切换后的 asciiMode) 按光标前连续字母查 (字面或拼音前缀)。
  /// 中文键盘走 RIME syncContext, 不进这里。输入为空或无匹配时清掉
  /// 之前挂的补全 (退格删回前缀内仍会继续显示)。
  private func updatePhraseCompletionForDirectInput() {
    if phraseCompletionSuppressNextTextChange {
      phraseCompletionSuppressNextTextChange = false
      return
    }
    // 有中文组字进行时候选栏归 syncContext 管, 这里不碰
    // (如 26 键组字中切到 123 页又敲数字, 拼音候选不能丢)。
    guard rimeContext.userInputKey.isEmpty else { return }
    let type = keyboardContext.keyboardType
    if type.isNumber {
      let typed = PhraseAutocomplete.trailingDigits(in: textDocumentProxy.documentContextBeforeInput ?? "")
      rimeContext.updatePhraseCompletionForDirectInput(typedInput: typed, kind: .digits)
    } else if isDirectInputKeyboard(type) {
      let typed = PhraseAutocomplete.trailingLetters(in: textDocumentProxy.documentContextBeforeInput ?? "")
      rimeContext.updatePhraseCompletionForDirectInput(typedInput: typed, kind: .latin)
    }
  }

  // MARK: - Implementations KeyboardController

  open func adjustTextPosition(byCharacterOffset offset: Int) {
    textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
  }

  open func deleteBackward() {
    // 再删任何内容, 撤回快照作废 (上滑整段删除的临时撤回图标随之消失)。
    // 与 round 14 的 undoLastCommit 互不干扰: 那是 RIME 学习层,
    // 这里只清文档层快照。
    invalidateUndoDeleteSnapshot()
    guard !rimeContext.userInputKey.isEmpty else {
      // 获取光标前后上下文，用于删除需要光标居中的符号
      let beforeInput = self.textDocumentProxy.documentContextBeforeInput ?? ""
      let afterInput = self.textDocumentProxy.documentContextAfterInput ?? ""
      // (第 14 轮第 5 项 a) 刚提交的词又被退格删掉, 就撤销它那次学习:
      // 先看光标前是不是正好是上次提交的文字, 删完文档后再撤销。
      // 只看“刚提交、还没输别的”那一次 (lastCommit), 且必须整段匹配,
      // 删一半不算 (undoLastCommit 找不到整词时只清记录)。
      let deletedLastCommit = rimeContext.lastCommit.map { beforeInput.hasSuffix($0.text) } ?? false
      let text = String(beforeInput.suffix(1) + afterInput.prefix(1))
      // 光标可以居中的符号，需要成对删除
      if keyboardContext.cursorBackOfSymbols(key: text) {
        self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        self.textDocumentProxy.deleteBackward(times: 2)
      } else {
        textDocumentProxy.deleteBackward(range: keyboardBehavior.backspaceRange)
      }
      if deletedLastCommit {
        _ = rimeContext.undoLastCommit()
      }
      // 退格后直输补全也要同步重算 (与 textDidChange 互为备份,
      // 否则只靠 textDidChange 时退格进前缀内补全不更新)。
      updatePhraseCompletionForDirectInput()
      return
    }

    // 拼音九宫格处理
    if keyboardContext.keyboardType.isChineseNineGrid {
      if let selectCandidatePinyin = rimeContext.selectCandidatePinyin {
        if let t9pinyin = pinyinToT9Mapping[selectCandidatePinyin.0] {
          let handled = rimeContext.tryHandleReplaceInputTexts(t9pinyin, startPos: selectCandidatePinyin.1, count: selectCandidatePinyin.2)
          Logger.statistics.info("change input text handled: \(handled)")
        }
        rimeContext.selectCandidatePinyin = nil
        return
      }
    }

    // 非九宫格处理
    rimeContext.deleteBackward()
  }

  open func deleteBackward(times: Int) {
    textDocumentProxy.deleteBackward(times: times)
  }

  /// 上滑回退整段删除的撤回快照 (单级、仅内存、键盘会话内有效)。
  /// 删除前取光标前文本; 上限 undoDeleteSnapshotMaxCharacters 字,
  /// 超了截断存最后这么多字, 恢复时照样插回截断后的内容。
  /// 只在上滑整段删除后出现; 普通点按退格不触发 (deleteBackward
  /// 不写它)。新的上滑整段删除替换旧快照。
  /// 与 round 14 的 undoLastCommit (RIME 学习层: 退格删掉刚上屏的
  /// 词时取消学习) 互不干扰: 恢复走 insertPastedText 直接写文档,
  /// 不经过 RIME, 也不读写 lastCommit; 全删完后光标前是空的,
  /// deleteBackward 的 hasSuffix(lastCommit) 判定也不会误触。
  static let undoDeleteSnapshotMaxCharacters = 10000

  /// 撤回快照变化通知 (userInfo["text"]: 快照文本; 无快照时无该键)。
  /// 工具栏据此展示/收掉临时撤回图标。
  static let didChangeUndoDeleteSnapshotNotification = Notification.Name("KeyboardInputViewController.didChangeUndoDeleteSnapshotNotification")

  /// 当前撤回快照 (nil 表示没有可撤回的删除)。
  private(set) var undoDeleteSnapshot: String?

  /// 整段删除的代数: 新的上滑删除 / 恢复操作使旧批次停下来
  /// (deleteTextBeforeCursorBatch 每次进入都比对, 不一致即返回)。
  private var undoDeleteGeneration = 0

  /// 整段删除进行中 (批次串行删除时为 true, 删完后 0.3s 宽限期
  /// 内也为 true): textDidChange 兜底在此期间不失效快照,
  /// 避免删除批次自己的回声把快照清掉。
  private var isPerformingSwipeDelete = false

  /// 删除前取快照并发布 (有文本才换快照; 光标前已空时不碰旧快照,
  /// 新的删除什么都没删, 旧的撤回仍有效)。
  private func takeUndoDeleteSnapshot() {
    undoDeleteGeneration += 1
    let before = textDocumentProxy.documentContextBeforeInput ?? ""
    guard !before.isEmpty else { return }
    undoDeleteSnapshot = String(before.suffix(Self.undoDeleteSnapshotMaxCharacters))
    isPerformingSwipeDelete = true
    postUndoDeleteSnapshotChanged()
  }

  /// 清掉快照并发布 (恢复 / 失效入口共用; 已空时不发通知)。
  open func invalidateUndoDeleteSnapshot() {
    guard undoDeleteSnapshot != nil else { return }
    undoDeleteSnapshot = nil
    postUndoDeleteSnapshotChanged()
  }

  /// 把快照文本原样插回光标处 (走 insertPastedText, 不经过 RIME),
  /// 然后清掉快照。恢复操作使进行中的旧删除批次停下来 (代数+1)。
  open func restoreDeletedTextBeforeCursor() {
    guard let snapshot = undoDeleteSnapshot, !snapshot.isEmpty else { return }
    undoDeleteGeneration += 1
    undoDeleteSnapshot = nil
    postUndoDeleteSnapshotChanged()
    insertPastedText(snapshot)
  }

  /// 发布快照变化通知 (工具栏的临时撤回图标据此显隐)。
  private func postUndoDeleteSnapshotChanged() {
    let userInfo: [AnyHashable: Any] = undoDeleteSnapshot.map { ["text": $0] } ?? [:]
    NotificationCenter.default.post(
      name: Self.didChangeUndoDeleteSnapshotNotification,
      object: self, userInfo: userInfo)
  }

  /// 整段删除收尾: 0.3s 宽限期后把进行中标志清掉, 期间
  /// textDidChange 的回声不失效快照。宽限期按代数认领,
  /// 新的删除开始后旧定时器不再清标志。
  private func finishSwipeDelete() {
    let generation = undoDeleteGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self, self.undoDeleteGeneration == generation else { return }
      self.isPerformingSwipeDelete = false
    }
  }

  /// 上滑回退键: 删除光标前的全部文字, 光标后的文字保留,
  /// 光标停在剩余文字的开头 (被删与保留的分界处)。
  /// 先重置 RIME (清空候选/输入状态), 再分批删光标前的文字,
  /// 每批最多 100 字, 用 main.async 串行, 避免一次删除过长阻塞键盘。
  /// 光标在文末时等同于清空全部; 光标在文首时不删除任何文字。
  open func deleteTextBeforeCursor() {
    takeUndoDeleteSnapshot()
    rimeContext.reset()
    deleteTextBeforeCursorBatch(remainingAttempts: 100, generation: undoDeleteGeneration)
  }

  private func deleteTextBeforeCursorBatch(remainingAttempts: Int, nilFallbackUsed: Bool = false, generation: Int) {
    // 旧删除的批次: 新的删除/恢复开始后停下来 (代数不一致即返回,
    // 不调 finishSwipeDelete——进行中标志归新操作管)。
    guard generation == undoDeleteGeneration else { return }
    guard remainingAttempts > 0 else {
      finishSwipeDelete()
      return
    }
    if let before = textDocumentProxy.documentContextBeforeInput {
      // 只以光标前是否还有文字为准: 光标后还有文字时 hasText 仍为
      // true, 不能用它做停止条件 (否则光标后有字就一直删到 cap)。
      guard !before.isEmpty else {
        finishSwipeDelete()
        return
      }
      let batch = min(100, before.count)
      textDocumentProxy.deleteBackward(times: batch)
      DispatchQueue.main.async { [weak self] in
        self?.deleteTextBeforeCursorBatch(remainingAttempts: remainingAttempts - 1, generation: generation)
      }
    } else if !nilFallbackUsed {
      // 拿不到前文长度: 删一批尽力而为 (无前文时 deleteBackward 是
      // 空操作); 若下一轮仍拿不到, 停止, 不空转。
      textDocumentProxy.deleteBackward(times: 100)
      DispatchQueue.main.async { [weak self] in
        self?.deleteTextBeforeCursorBatch(remainingAttempts: remainingAttempts - 1, nilFallbackUsed: true, generation: generation)
      }
    } else {
      // 两轮都拿不到前文: 停止, 不空转。
      finishSwipeDelete()
    }
  }

  open func insertSymbol(_ symbol: Symbol) {
    // 检测是否需要顶字上屏
    if !rimeContext.userInputKey.isEmpty {
      // 内嵌模式需要先清空
      if keyboardContext.enableEmbeddedInputMode {
        self.textDocumentProxy.setMarkedText("", selectedRange: NSMakeRange(0, 0))
      }
      // fix: 内嵌模式问题
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
        guard let self = self else { return }
        // 顶码上屏 (只顶引擎候选的首选; 常用语补全项只能点选, 不顶)。
        if keyboardContext.swipePaging {
          if let firstCandidate = self.rimeContext.firstEngineSuggestion {
            self.textDocumentProxy.insertText(firstCandidate.text)
          }
        } else {
          if let commit = self.rimeContext.rimeContext?.commitTextPreview {
            self.textDocumentProxy.insertText(commit)
          }
        }
        self.rimeContext.reset()
        self.insertTextPatch(symbol.char)
      }
      return
    }

    self.insertTextPatch(symbol.char)
  }

  open func insertText(_ text: String) {
    // 输入任何字符, 撤回快照作废 (上滑整段删除的临时撤回图标随之消失)。
    // 放在分支前: 英文/数字直输与中文 RIME 路都覆盖。
    invalidateUndoDeleteSnapshot()
    if keyboardContext.keyboardType.isAlphabetic {
      textDocumentProxy.insertText(text)
      // 英文键盘直输不走 RIME, 补全不能只靠 textDidChange:
      // build #44 只修了类型判定, 但真机上 textDidChange 仍没把补全
      // 带出来 (英文/123 始终不触发, 九宫格拼音走 RIME 路却正常)。
      // 插入后同步触发一次 (与 textDidChange 互为备份, 幂等重算)。
      updatePhraseCompletionForDirectInput()
      return
    }

    // 字母输入模式，不经过 rime 引擎
    // if rimeContext.asciiMode {
    //  textDocumentProxy.insertText(text)
    //  return
    // }

    // rime 引擎处理
    let handled = rimeContext.tryHandleInputText(text)
    if !handled {
      Logger.statistics.error("try handle input text: \(text), handle false")
      insertTextPatch(text)
      return
    }
  }

  /// 面板粘贴上屏 (剪贴板条目 / 常用语 / 粘贴提示行 / 分段粘贴):
  /// 整段文本直接写入文档, 不走 insertText 的单字符按键漏斗。
  /// 根因 (Bug C): insertText 在中文键盘下把文本交给
  /// rimeContext.tryHandleInputText → Rime.shared.inputKey →
  /// irime_api.processKey, 而 processKey 只取字符串的首字节
  /// ([keyCode UTF8String][0]) 当一次按键处理: 首字符是字母/数字/
  /// 符号时被引擎当成拼音按键或选词键吃掉 (syncContext 再把引擎
  /// 候选挂进候选栏, 于是出现一个奇怪的数字/符号候选词), 其余
  /// 字符全部丢掉, 剪贴板文本根本没进文档; 只有首字符是非 ASCII
  /// (如纯中文) 时 processKey 返回 false 才回退到 insertTextPatch
  /// 全文上屏。所以含字母/数字/符号的剪贴板内容点按必现此 bug。
  /// 修复与 pasteCommand / 常用语补全点选同一路: 先清未提交的组字
  /// 状态 (内嵌模式下 marked 区的 preedit 一并清掉, 避免粘贴后
  /// 残留组字态继续拼进下一键), 再 textDocumentProxy.insertText
  /// 直接插原文——不走 insertTextPatch, 避免成对符号逻辑改写
  /// 用户粘贴的文本。
  open func insertPastedText(_ text: String) {
    guard !text.isEmpty else { return }
    // 粘贴 (剪贴板/常用语/分段面板) 是删除之后的新输入, 撤回快照作废。
    // 恢复操作本身也走这里: 那时快照已在 restoreDeletedTextBeforeCursor
    // 里清掉, 这里是空操作。
    invalidateUndoDeleteSnapshot()
    if !rimeContext.userInputKey.isEmpty {
      textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      rimeContext.reset()
    }
    textDocumentProxy.insertText(text)
  }

  open func selectNextKeyboard() {
    // advanceToNextInputMode()
  }

  open func selectNextLocale() {
//    keyboardContext.selectNextLocale()
  }

  open func setKeyboardType(_ type: KeyboardType) {
    // TODO: 键盘切换
//    if !rimeContext.userInputKey.isEmpty, type.isCustom || type.isChinesePrimaryKeyboard || type.isChineseNineGrid || type.isAlphabetic {
//      textDocumentProxy.insertText(rimeContext.userInputKey)
//      rimeContext.reset()
//    }
    keyboardContext.setKeyboardType(type)
  }

  open func setKeyboardCase(_ casing: KeyboardCase) {
    if keyboardContext.keyboardType.isChinesePrimaryKeyboard {
      keyboardContext.setKeyboardType(.chinese(casing))
      return
    }

    if case .custom(let name, _) = keyboardContext.keyboardType {
      keyboardContext.setKeyboardType(.custom(named: name, case: casing))
      return
    }

    keyboardContext.setKeyboardType(.alphabetic(casing))
  }

  /// 打开 URL (如点"设置"格子跳回主 App)。
  /// 键盘扩展里没有 UIApplication, 不能走 UIApplication.shared.open:
  /// 优先用扩展上下文打开 (系统给扩展的开 URL 入口); 扩展上下文为空
  /// 或系统拒绝再回退到响应链上的 UIApplication.open (现代 API)。
  /// 根因 (第 16 轮, build #45 仍失败): 第 14 轮的两路都是死路——
  /// (1) NSExtensionContext.open 只被 Today / iMessage 扩展点支持,
  /// 在键盘扩展里直接返回 false / 什么都不做; (2) 响应链回退调的是
  /// 已废弃的 -[UIApplication openURL:], iOS 18+ 对它强制返回 false
  /// ("BUG IN CLIENT OF UIKIT ... Force returning false (NO)")。
  /// 所以点设置格子时两路都静默失败, 只剩日志。修法: 响应链回退改
  /// 走现代的 open(_:options:completionHandler:)——沿响应链找到
  /// UIApplication 实例直接调它 (不碰扩展里禁用的 UIApplication.shared),
  /// 这是键盘扩展里已知可行的路子。scheme 本身没问题:
  /// Hamster/Info.plist 注册了 hamster, HamsterConstants.appURL 一致,
  /// SceneDelegate.openURLContexts 接住 "main" 后 navigation(.main)。
  open func openUrl(_ url: URL?) {
    guard let url else { return }
    if let extensionContext {
      extensionContext.open(url) { [weak self] success in
        if success {
          Logger.statistics.info("openUrl: extensionContext 打开成功: \(url.absoluteString)")
        } else {
          Logger.statistics.error("openUrl: extensionContext 打开失败, 回退响应链: \(url.absoluteString)")
          self?.openURLViaResponderChain(url)
        }
      }
      return
    }
    Logger.statistics.error("openUrl: extensionContext 为空, 走响应链: \(url.absoluteString)")
    openURLViaResponderChain(url)
  }

  /// 响应链打开 URL: 沿 next 找到 UIApplication 实例, 调现代的
  /// open(_:options:completionHandler:) (不要用已废弃的 openURL:,
  /// iOS 18+ 对它强制返回 false)。UIApplication.shared 在扩展里
  /// 不可用, 但响应链末尾的 UIApplication 实例本身可以直接调。
  /// 找不到 UIApplication 时记日志, 不静默失败。
  private func openURLViaResponderChain(_ url: URL) {
    var responder = self as UIResponder?
    while let r = responder {
      if let app = r as? UIApplication {
        app.open(url, options: [:]) { success in
          if success {
            Logger.statistics.info("openUrl: 响应链 UIApplication.open 打开成功: \(url.absoluteString)")
          } else {
            Logger.statistics.error("openUrl: 响应链 UIApplication.open 打开失败: \(url.absoluteString)")
          }
        }
        return
      }
      responder = r.next
    }
    Logger.statistics.error("openUrl: 响应链上没有 UIApplication: \(url.absoluteString)")
  }

  open func resetInputEngine() {
    rimeContext.reset()
  }

  open func insertRimeKeyCode(_ keyCode: Int32) {
    guard rimeContext.tryHandleInputCode(keyCode) else {
      tryHandleSpecificCode(keyCode)
      return
    }
  }

  open func returnLastKeyboard() {
    keyboardContext.setKeyboardType(keyboardContext.returnKeyboardType())
  }

  // MARK: - Syncing

  /**
   Perform a text context sync.

   执行文本上下文同步。

   This is performed anytime the text is changed to ensure
   that ``keyboardTextContext`` is synced with the current
   text document context content.

   在更改文本时执行此操作，以确保 ``keyboardTextContext`` 与当前文本文档上下文内容同步。
   */
  open func performTextContextSync() {
    keyboardTextContext.sync(with: self)
  }

  // MARK: - Autocomplete

  /**
   The text that is provided to the ``autocompleteProvider``
   when ``performAutocomplete()`` is called.

   调用 ``performAutocomplete()`` 时提供给 ``autocompleteProvider`` 的文本。

   By default, the text document proxy's current word will
   be used. You can override this property to change that.

   默认情况下，将使用文本文档代理的当前单词。
   您可以覆盖此属性来更改。
   */
  open var autocompleteText: String? {
    textDocumentProxy.currentWord
  }

  /**
   Insert an autocomplete suggestion into the document.

   在文档中插入自动完成建议。

   By default, this call the `insertAutocompleteSuggestion`
   in the text document proxy, and then triggers a release
   in the keyboard action handler.

   默认情况下，这会调用文本文档代理中的 `insertAutocompleteSuggestion`，
   然后在键盘操作 handler 中触发 .release 操作。
   */
  open func insertAutocompleteSuggestion(_ suggestion: AutocompleteSuggestion) {
    textDocumentProxy.insertAutocompleteSuggestion(suggestion)
    keyboardActionHandler.handle(.release, on: .character(""))
  }

  /**
   Whether or not autocomplete is enabled.

   是否启用自动完成功能。

   By default, autocomplete is enabled as long as
   ``AutocompleteContext/isEnabled`` is `true`.

   默认情况下，只要 ``AutocompleteContext/isEnabled`` 为 `true`，自动完成功能就会启用。
   */
  open var isAutocompleteEnabled: Bool {
    autocompleteContext.isEnabled
  }

  /**
   Perform an autocomplete operation.

   执行自动完成操作。

   You can override this function to extend or replace the
   default logic. By default, it uses the `currentWord` of
   the ``textDocumentProxy`` to perform autocomplete using
   the current ``autocompleteProvider``.

   您可以重载此函数来扩展或替换默认逻辑。
   默认情况下，它会使用 ``textDocumentProxy`` 的 `currentWord`
   来使用当前的 ``autocompleteProvider`` 执行自动完成。
   */
  open func performAutocomplete() {
    guard isAutocompleteEnabled else { return }
    guard let text = autocompleteText else { return resetAutocomplete() }
    autocompleteProvider.autocompleteSuggestions(for: text) { [weak self] result in
      self?.updateAutocompleteContext(with: result)
    }
  }

  /**
   Reset the current autocomplete state.

   重置当前的自动完成状态。

   You can override this function to extend or replace the
   default logic. By default, it resets the suggestions in
   the ``autocompleteContext``.

   您可以重载此函数来扩展或替换默认逻辑。
   默认情况下，它会重置 ``autocompleteContext`` 中的 suggestion。
   */
  open func resetAutocomplete() {
    autocompleteContext.reset()
  }

  // MARK: - Dictation 听写

  /**
   The configuration to use when performing dictation from
   the keyboard extension.

   使用键盘扩展功能进行听写时要使用的配置。

   By default, this uses the `appGroupId` and `appDeepLink`
   properties from ``dictationContext``, so make sure that
   you call ``DictationContext/setup(with:)`` before using
   the dictation features in your keyboard extension.

   默认情况下，它会使用 ``dictationContext`` 中的 `appGroupId` 和 `appDeepLink` 属性，
   因此请确保在键盘扩展中使用听写功能前调用 ``DictationContext/setup(with:)` 。
   */
//  public var dictationConfig: KeyboardDictationConfiguration {
//    .init(
//      appGroupId: dictationContext.appGroupId ?? "",
//      appDeepLink: dictationContext.appDeepLink ?? ""
//    )
//  }

  /**
   Perform a keyboard-initiated dictation operation.

   执行键盘启动的听写操作。

   > Important: ``DictationContext/appDeepLink`` must have
   been set before this is called. The link must open your
   app and start dictation. See the docs for more info.

   > 重要：必须在调用此链接之前设置``DictationContext/appDeepLink``。
   > 链接必须打开主应用程序并开始听写。更多信息请参阅文档。
   */
//  public func performDictation() {
//    Task {
//      do {
//        try await dictationService.startDictationFromKeyboard(with: dictationConfig)
//      } catch {
//        await MainActor.run {
//          dictationContext.lastError = error
//        }
//      }
//    }
//  }
}

// MARK: - Private Functions

private extension KeyboardInputViewController {
  /// 刷新属性
  func refreshProperties() {
    refreshLayoutProvider()
    refreshCalloutActionContext()
  }

  /// 刷新呼出操作上下文
  func refreshCalloutActionContext() {
    calloutContext.action = ActionCalloutContext(
      actionHandler: keyboardActionHandler,
      actionProvider: calloutActionProvider
    )
  }

  /// 刷新布局 Provider
  func refreshLayoutProvider() {
    keyboardLayoutProvider.register(
      inputSetProvider: inputSetProvider
    )
  }

  /**
   Set up an initial width to avoid broken SwiftUI layouts.

   设置键盘初始宽度，以避免 SwiftUI 布局被破坏。
   */
  func setupInitialWidth() {
    view.frame.size.width = UIScreen.main.bounds.width
    Logger.statistics.debug("view frame width: \(UIScreen.main.bounds.width)")
  }

  /**
   Setup locale observation to handle locale-based changes.

   设置本地化观测，以处理基于本地化的更改。
   */
  func setupLocaleObservation() {
//    keyboardContext.$locale.sink { [weak self] in
//      guard let self = self else { return }
//      let locale = $0
//      self.primaryLanguage = locale.identifier
//      self.autocompleteProvider.locale = locale
//    }.store(in: &cancellables)
  }

  /**
   Set up the standard next keyboard button behavior.

   设置标准的下一个键盘按钮行为。
   */
  func setupNextKeyboardBehavior() {
    NextKeyboardController.shared = self
  }

  var needNumberKeyboard: Bool {
    switch textDocumentProxy.keyboardType {
    case .numbersAndPunctuation, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad: return true
    default: return false
    }
  }

  /**
   RIME 引擎设置
   */
  func setupRIME() {
    // 异步 RIME 引擎启动
    Task.detached { [unowned self] in
//      if await rimeContext.isRunning {
//        Logger.statistics.debug("shutdown rime engine")
//        // 这里关闭引擎是为了使 RIME 内存中的自造词落盘。
//        await shutdownRIME()
//      }

      // 检测是否需要覆盖 RIME 目录
      // let overrideRimeDirectory = UserDefaults.hamster.overrideRimeDirectory

      // 检测对 appGroup 路径下是否有写入权限，如果没有写入权限，则需要将 appGroup 下文件复制到键盘的 Sandbox 路径下
//      if await !self.hasFullAccess {
//        do {
//          try FileManager.syncAppGroupUserDataDirectoryToSandbox(override: overrideRimeDirectory)
//
//          // 注意：如果没有开启键盘完全访问权限，则无权对 UserDefaults.hamster 写入
//          UserDefaults.hamster.overrideRimeDirectory = false
//        } catch {
//          Logger.statistics.error("FileManager.syncAppGroupUserDataDirectoryToSandbox(override: \(overrideRimeDirectory)) error: \(error.localizedDescription)")
//        }
//      }

      guard await !rimeContext.isRunning else { return }

      if let maximumNumberOfCandidateWords = await keyboardContext.hamsterConfiguration?.rime?.maximumNumberOfCandidateWords {
        await rimeContext.setMaximumNumberOfCandidateWords(maximumNumberOfCandidateWords)
      }

      if let swipePaging = await keyboardContext.hamsterConfiguration?.toolbar?.swipePaging {
        await rimeContext.setUseContextPaging(swipePaging == false)
      }

      await rimeContext.start(hasFullAccess: true)

      let simplifiedModeKey = await keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
      await rimeContext.syncTraditionalSimplifiedChineseMode(simplifiedModeKey: simplifiedModeKey)
    }
  }

  func shutdownRIME() {
    /// 停止引擎，触发自造词等数据落盘
    rimeContext.shutdown()

    /// 重新启动引擎
    /// rimeContext.start(hasFullAccess: hasFullAccess)
  }

  /// Combine 观测 RIME 引擎中的用户输入及上屏文字
  func setupCombineRIMEInput() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] inputText in
        guard let self = self else { return }

        // 获取与清空在一起，防止重复上屏
        var commitText = self.rimeContext.commitText
        self.rimeContext.resetCommitText()

        // 写入上屏文字
        if !commitText.isEmpty {
          // 九宫格编码转换
          if keyboardContext.keyboardType.isChineseNineGrid {
            commitText = commitText.replaceT9pinyin
          }

          self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))

          // 写入 userInputKey
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            self.insertTextPatch(commitText)
          }
        }

        // 非嵌入模式在 CandidateWordsView.swift 中处理，直接输入 Label 中
        guard self.keyboardContext.enableEmbeddedInputMode else { return }

        // 写入 userInputKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
          if self.keyboardContext.keyboardType.isChineseNineGrid {
            let t9UserInputKey = self.rimeContext.t9UserInputKey
            self.textDocumentProxy.setMarkedText(t9UserInputKey, selectedRange: NSMakeRange(t9UserInputKey.utf8.count, 0))
            return
          }
          self.textDocumentProxy.setMarkedText(inputText, selectedRange: NSMakeRange(inputText.utf8.count, 0))
        }
      }
      .store(in: &cancellables)

    // 常用语补全点选上屏: RimeContext 只决定“点了哪个”, 真正写文档走这里
    // (它持有 textDocumentProxy)。
    // 中文组字时输入还在 marked 区 (deleteCount == 0): 先清 marked 再插
    // 整条短语; 英文/数字键盘输入已在文档里: 先删已输入的前缀再插。
    // 点选瞬间光标可能已移走: 只有光标前尾巴确为当初匹配的输入时才删,
    // 否则放弃上屏 (只清补全, 不插错地方)。
    rimeContext.onApplyPhraseCompletion = { [weak self] phrase, deleteCount, typedInput in
      guard let self = self else { return }
      self.phraseCompletionSuppressNextTextChange = true
      if deleteCount > 0 {
        let before = self.textDocumentProxy.documentContextBeforeInput ?? ""
        let tail = String(before.suffix(typedInput.count))
        guard tail.count == typedInput.count,
              tail.lowercased() == typedInput.lowercased() else {
          self.rimeContext.clearPhraseCompletion()
          return
        }
        self.textDocumentProxy.deleteBackward(times: deleteCount)
      } else {
        self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      }
      // 直接插原文 (不走 insertTextPatch, 避免成对符号逻辑改写用户短语)。
      self.textDocumentProxy.insertText(phrase)
    }

    // 边栏点选替换前落盘已选文字 (Bug A): 部分选词不产生引擎 commit,
    // 选定的词只在 preedit 里, 边栏替换的 reset() 会把它清掉; 替换前
    // 先把这段文字插进文档。同步执行 (RimeContext 在 reset() 前回调,
    // 插完才清组字)。与上屏 commit 同款: 先清 marked (内嵌模式下
    // preedit 正在 field 里), 再直接插原文 (不走 insertTextPatch,
    // 避免成对符号逻辑改写中文)。
    rimeContext.onFlushCommittedTextBeforeSidebarReplace = { [weak self] text in
      guard let self = self else { return }
      self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      self.textDocumentProxy.insertText(text)
    }

    // 切出直输键盘 (英文/数字, 含 asciiMode 英文与 123 页
    // .chineseNumeric) 时清掉可能残留的补全 (中文键盘的 syncContext
    // 会在下次打字时重算, 但切键盘本身不打字, 不清会留一条 stale 的在栏里)。
    // 判定与补全触发共用 isDirectInputKeyboard, 口径必须一致。
    keyboardContext.keyboardTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] type in
        guard let self = self else { return }
        guard self.isDirectInputKeyboard(type) else {
          self.rimeContext.clearPhraseCompletion()
          return
        }
      }
      .store(in: &cancellables)

    // 英文纠错候选 -> RIME 候选栏 (第 15 轮第 2 项 b): 把 KeyboardKit 的
    // autocomplete 建议映射进候选栏 (复用同一套 cell/样式/点选)。
    // 只在英文键盘下生效; 中文键盘的建议永远走 RIME 引擎。
    autocompleteContext.$suggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self = self else { return }
        guard self.keyboardContext.keyboardType.isAlphabetic else {
          if self.rimeContext.externalSuggestionsKind == .englishCorrection {
            self.rimeContext.clearExternalSuggestions()
          }
          return
        }
        let items = suggestions.prefix(5).map { suggestion in
          CandidateSuggestion(index: -1, label: "", text: suggestion.text, title: suggestion.title, isAutocomplete: suggestion.isAutocomplete)
        }
        if items.isEmpty {
          if self.rimeContext.externalSuggestionsKind == .englishCorrection {
            self.rimeContext.clearExternalSuggestions()
          }
        } else {
          self.rimeContext.showExternalSuggestions(items, kind: .englishCorrection)
        }
      }
      .store(in: &cancellables)

    // 切出英文键盘时清掉可能残留的英文纠错 (第 15 轮第 2 项 b):
    // 不清的话, stale 的纠错会在中文键盘的下一个空格被
    // tryApplyAutocompleteSuggestion 误应用到中文词上。
    // 光标移动时 resetAutocomplete 本来就会清 (selectionWillChange/
    // selectionDidChange), 这里补的是“键盘类型变了”那一路。
    keyboardContext.keyboardTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] type in
        guard let self = self else { return }
        guard !type.isAlphabetic else { return }
        self.resetAutocomplete()
        if self.rimeContext.externalSuggestionsKind == .englishCorrection {
          self.rimeContext.clearExternalSuggestions()
        }
      }
      .store(in: &cancellables)

    // 联想词点选上屏 (第 15 轮第 2 项 a) / 英文纠错点选上屏 (b):
    // RimeContext 只决定“点了哪个”, 真正写文档走这里 (它持有 proxy)。
    // 联想词原文上屏 (insertTextPatch, 不补空格, 中文没有空格);
    // 英文纠错走 insertAutocompleteSuggestion (替换当前词 + 补空格)。
    rimeContext.onApplyAssociationText = { [weak self] text in
      self?.insertTextPatch(text)
    }
    rimeContext.onApplyEnglishCorrection = { [weak self] suggestion in
      self?.insertAutocompleteSuggestion(suggestion)
    }
//    rimeContext.registryHandleUserInputKeyChanged { [weak self] inputText in
//      guard let self = self else { return }
//
//      // 获取与清空在一起，防止重复上屏
//      let commitText = self.rimeContext.commitText
//      self.rimeContext.resetCommitText()
//
//      // 写入上屏文字
//      if !commitText.isEmpty {
//        self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
//
//        // 写入 userInputKey
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
//          self.insertTextPatch(commitText)
//        }
//      }
//
//      // 非嵌入模式在 CandidateWordsView.swift 中处理，直接输入 Label 中
//      guard self.keyboardContext.enableEmbeddedInputMode else { return }
//
//      // 写入 userInputKey
//      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
//        if self.keyboardContext.keyboardType.isChineseNineGrid {
//          let t9UserInputKey = self.rimeContext.t9UserInputKey
//          self.textDocumentProxy.setMarkedText(t9UserInputKey, selectedRange: NSMakeRange(t9UserInputKey.utf8.count, 0))
//          return
//        }
//        self.textDocumentProxy.setMarkedText(inputText, selectedRange: NSMakeRange(inputText.utf8.count, 0))
//      }
//    }
  }

  /// 在 ``textDocumentProxy`` 的文本发生变化后，尝试更改为首选键盘类型
  func tryChangeToPreferredKeyboardTypeAfterTextDidChange() {
    let context = keyboardContext
    let shouldSwitch = keyboardBehavior.shouldSwitchToPreferredKeyboardTypeAfterTextDidChange()
    guard shouldSwitch else { return }
    setKeyboardType(context.preferredKeyboardType)
  }

  /**
   Update the autocomplete context with a certain result.

   根据特定结果更新自动完成的上下文。

   This is performed async to avoid that any network-based
   operations update the context from a background thread.

   这是同步执行的，需要避免任何基于网络的操作从后台线程更新上下文。
   */
  func updateAutocompleteContext(with result: AutocompleteResult) {
    DispatchQueue.main.async { [weak self] in
      guard let context = self?.autocompleteContext else { return }
      switch result {
      case .failure(let error): context.lastError = error
      case .success(let result): context.suggestions = result
      }
    }
  }

  /// 上屏补丁：增加了成对符号/光标回退/返回主键盘的支持
  func insertTextPatch(_ insertText: String) {
    // 输入任何字符 (成对符号、选词上屏都走这里), 撤回快照作废。
    invalidateUndoDeleteSnapshot()
    // 成对符号 (第 17 轮反馈): 开括号/开引号按一下时,
    // 光标后面没字 → 打一对, 光标移到中间; 光标后面有字 → 只打一边。
    // 闭符号 + 后面正好是它 → 直接越过, 不重复打。
    // 有选区时开符号包住选区 (沿用老逻辑)。
    let afterText = textDocumentProxy.documentContextAfterInput ?? ""
    let isTypeOver =
      insertText.count == 1
      && keyboardContext.isPairedSymbolCloser(insertText)
      && afterText.first.map(String.init) == insertText
    if isTypeOver {
      // 闭符号越过: 后面正好是同一个闭符号, 光标右移一位, 不插入。
      adjustTextPosition(byCharacterOffset: 1)
    } else {
      // 开符号配对: 有选区 → 包住选区; 后面没字 → 打一对; 后面有字 → 只打一边。
      let pair = keyboardContext.getPairSymbols(insertText)
      let isOpener = insertText.count == 1 && pair != insertText
      let selectedText = textDocumentProxy.selectedText ?? ""
      let text: String
      if isOpener, (!selectedText.isEmpty || afterText.isEmpty) {
        text = pair
      } else {
        text = insertText
      }

      // 检测光标是否需要回退
      if keyboardContext.cursorBackOfSymbols(key: text) {
        // 检测是否有选中的文字，可以居中的光标将自动包裹选中的文本
        if text.count > 0, text.count % 2 == 0 {
          let selectText = textDocumentProxy.selectedText ?? ""
          let halfLength = text.count / 2
          let firstHalf = String(text.prefix(halfLength))
          let secondHalf = String(text.suffix(halfLength))
          textDocumentProxy.insertText("\(firstHalf)\(selectText)\(secondHalf)")
          // 如果选中的文字为空，将光标挪到中间，否则不用移动
          let offset = selectText.count == 0 ? halfLength : 0
          self.adjustTextPosition(byCharacterOffset: -offset)
        } else {
          textDocumentProxy.insertText(text)
          self.adjustTextPosition(byCharacterOffset: -1)
        }
      } else {
        textDocumentProxy.insertText(text)
      }
    }

    // 检测是否需要返回主键盘
    let returnToPrimaryKeyboard = keyboardContext.returnToPrimaryKeyboardOfSymbols(key: insertText)
    if returnToPrimaryKeyboard {
      keyboardContext.setKeyboardType(keyboardContext.returnKeyboardType())
    }

    // 直输补全同步触发 (build #44 回归): 数字键 (insertSymbol) 与
    // 英文 asciiMode 提交 (commit sink) 都走这里直接写文档, 只靠
    // textDidChange 的话真机上不触发; 插入后立即按当前文档重算一次
    // 补全 (与 textDidChange 互为备份, 幂等)。中文组字时 userInputKey
    // 非空, 触发里的 guard 会直接返回, 不干扰 syncContext 的补全;
    // 中文选词提交后类型是 .chinese 且 asciiMode 关, 类型判定不命中,
    // 也不产生补全。
    updatePhraseCompletionForDirectInput()
  }
}

extension UIKeyboardType {
  var isNumberType: Bool {
    switch self {
    // 数字键盘
    case .numberPad, .numbersAndPunctuation, .phonePad, .decimalPad, .asciiCapableNumberPad: return true
    default: return false
    }
  }
}
