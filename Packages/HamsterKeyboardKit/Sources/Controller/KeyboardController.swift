//
//  KeyboardActionTrigger.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2023-01-23.
//  Copyright © 2020-2023 Daniel Saidi. All rights reserved.
//

import Foundation

/**
  This protocol is used to make using the keyboard input view
  controller more abstract and available to more platforms.

  该协议用于使 InputViewController 使用更加抽象，并适用于更多平台。

  ``KeyboardInputViewController`` implements this protocol by
  calling itself, its document proxy, or its keyboard context.

 `` KeyboardInputViewController`` 通过调用自身、document proxy 或键盘 context 来实现此协议。

  The protocol currently defines what's currently required to
  trigger controller-specific actions within the library, but
  it may add functionality over time. Note that this protocol
  should only specify operations and not state.

  该协议目前定义了在程序库中触发控制器特定操作所需的内容，但随着时间的推移可能会增加功能。
  请注意，该协议只能指定操作，而不能指定状态。
  */
public protocol KeyboardController: AnyObject {
  /**
   Adjust the text input cursor position.

   调整文字输入光标位置。
   */
  func adjustTextPosition(byCharacterOffset: Int)

  /**
   Delete backwards.

   向后删除。
   */
  func deleteBackward()

  /**
   Delete backwards a certain number of times.

   向后删除一定次数。
   */
  func deleteBackward(times: Int)

  /**
   Delete all text before the cursor (swipe up on backspace).
   Text after the cursor is kept.

   删除光标前的全部文字（上滑回退键）, 光标后的文字保留。
   */
  func deleteTextBeforeCursor()

  /**
   Restore the text deleted by the last swipe-up delete-all
   (deleteTextBeforeCursor), inserting the snapshot back at the
   cursor without going through RIME. Does nothing when there
   is no snapshot.

   恢复上一次上滑整段删除删掉的文字 (快照原样插回光标处, 不经过
   RIME)。没有快照时什么都不做。
   */
  func restoreDeletedTextBeforeCursor()

  /**
   Drop the swipe-delete snapshot (the temporary undo icon goes
   away with it). Called when the user types, deletes, picks a
   candidate, or the keyboard hides.

   丢掉上滑删除的快照 (临时撤回图标随之消失)。用户输入、删除、
   选词或键盘收起时调用。
   */
  func invalidateUndoDeleteSnapshot()

  /**
   Dismiss the keyboard.

   关闭键盘。
   */
  func dismissKeyboard()

  /**
   Insert the provided autocomplete suggestion.

   插入所提供的自动完成建议。
   */
  func insertAutocompleteSuggestion(_ suggestion: AutocompleteSuggestion)

  /**
   Insert the provided text.

   插入提供的文本。
   */
  func insertText(_ text: String)

  /**
   Insert a whole pasted text (clipboard item, phrase, paste row/segment)
   directly into the document, bypassing the RIME engine.

   整段粘贴文本 (剪贴板条目、常用语、粘贴提示行/分段) 直接写入文档,
   不走 RIME 引擎。insertText 是单字符按键入口: 整段文本走它会被
   当成一次按键喂给引擎 (processKey 只取字符串首字节), 其余丢掉,
   候选栏还会出现引擎的残余候选。
   */
  func insertPastedText(_ text: String)

  /// 插入符号
  func insertSymbol(_ symbol: Symbol)

  /// 快捷指令
  func tryHandleShortcutCommand(_ command: ShortcutCommand)

  /**
   Perform an autocomplete operation.

   执行自动完成操作。
   */
  func performAutocomplete()

  /**
   Perform a keyboard-initiated dictation operation.

   执行键盘启动的听写操作。
   */
  // func performDictation()

  /**
   Perform a text context sync.

   执行文本上下文同步。
   */
  func performTextContextSync()

  /**
   Reset the current autocomplete state.

   重置当前的自动完成状态。
   */
  func resetAutocomplete()

  /**
   Select the next keyboard, if any.

   选择下一个键盘（如果有）。
   */
  func selectNextKeyboard()

  /**
   Select the next locale, if any.

   选择下一个语言环境（如果有）。
   */
  func selectNextLocale()

  /**
   Set a certain keyboard type.

   设置某种键盘类型。
   */
  func setKeyboardType(_ type: KeyboardType)

  /**
   设置键盘大小写
   */
  func setKeyboardCase(_ casing: KeyboardCase)

  /**
   Open a certain URL

   打开某个 URL
   */
  func openUrl(_ url: URL?)

  /// 重置输入法引擎
  func resetInputEngine()

  /**
   插入 RIME 引擎可识别的编码
   */
  func insertRimeKeyCode(_ keyCode: Int32)

  /**
   次选候选字
   */
  func selectSecondaryCandidate()

  /// 返回上一次的键盘
  func returnLastKeyboard()
}
