# 「仓」输入法

一款基于「[中州韻輸入法引擎／Rime Input Method Engine](https://github.com/rime/librime)」的 iOS 版本输入法.

# License

本项目最初采用 GPL-3.0 许可。从 v2.1.0 开始，它变更为 MIT 许可。

后续代码是否会在开源？

目前「仓」已经在做商业化的相关功能了，在没有资金的情况下，不打算在开源了。

感谢大家的支持。

# 如何编译运行

在 1.0 版本，很多伙伴 `clone` 项目后都无法直接运行，多数问题是被被卡在 `librime` 的编译下了，于是新版本将这步省略了。

目前 [LibrimeKit](https://github.com/imfuxiao/LibrimeKit) 项目，只用来作为 [librime](https://github.com/rime/librime)  的编译项目，并使用 `Github Action` 将依赖的 Framework 编译并发布 Release。大家可以下载编译好的 Framework 使用，无需在为了编译环境而困扰。

> 感谢 @amorphobia 为 LibrimeKit 提交的 Github Action 配置

1. 下载编译后的 Framework

```sh
make framework
```

2. 下载内置方案

```sh
make schema
```

3. XCode 打开项目并运行（我个人使用的开发环境 Intel X86，MacOS 14，XCode 15）

```sh
xed .
```

# 剪贴板同步 (本 fork 新增)

跨设备剪贴板同步, 机制与微信输入法相同: **键盘每次弹出时同步一次**——先把本机剪贴板上传到服务器, 再把服务器上的最新内容下载回本机剪贴板。另一台设备打开键盘时, 就能拿到这边复制的内容。

## 使用方法

1. 在主 App「设置 → 剪贴板同步」中填入服务器地址、用户名、密码, 打开开关。
   (也可以直接在 `UserDefaults.hamster` 中设置 `clipboardSyncEnabled` /
   `clipboardSyncServerURL` / `clipboardSyncUsername` / `clipboardSyncPassword`。)
2. 在系统设置中为仓输入法开启「允许完全访问」, 否则键盘无法读取剪贴板与联网。
3. Windows 端用 SyncClipboard 客户端连同一个服务器即可互相同步
   (SyncClipboard 客户端自带后台自动同步, 无需输入法)。

## 服务器协议 (极简 HTTP)

- 上传: `PUT {serverURL}`, Body 为纯文本剪贴板内容
- 下载: `GET {serverURL}`, 响应 Body 为纯文本; 若为 JSON 则解析 `{"text": "..."}`
- 鉴权: 配置了用户名/密码时附加 HTTP Basic Auth
- 服务器只需保存"最新一条"剪贴板内容即可, 仓库 `Tools/clipboard-sync-server.py`
  是一个仅依赖 Python 3 标准库的参考实现, 可直接部署在自己的 VPS 上
  (公网部署时请用 Caddy/Nginx 反代套 HTTPS, 不要直接暴露 HTTP)。

## 注意

- iOS 14 起每次读取剪贴板都会在屏幕顶部弹出提示横幅, 这是系统行为, 无法绕过。
- 键盘扩展内存上限约 50MB, 同步逻辑只用 URLSession, 失败时静默放弃, 绝不阻塞打字。
- 同步开关默认关闭; 密码保存在 App Group UserDefaults 中 (与仓内其他配置一致,
  未使用 Keychain)。
- 相关代码: `Packages/HamsterKit/Sources/ClipboardSync/ClipboardSyncService.swift`,
  钩子在 `Packages/HamsterKeyboardKit/Sources/Controller/KeyboardInputViewController.swift`
  的 `viewWillAppear`, 设置界面在
  `Packages/HamsteriOS/Sources/ViewModel/Settings/SettingsViewModel.swift`。

# 第三方库

仓输入法的功能的开发离不开这些开源项目：

* [librime](https://github.com/rime/librime) (BSD License)
* [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit.git) (MIT License)
* [Squirrel](https://github.com/rime/squirrel) (GPL-3.0 license)
* [Runestone](https://github.com/simonbs/Runestone.git) (MIT License)
* [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages.git) (MIT License)
* [ProgressHUD](https://github.com/relatedcode/ProgressHUD) (MIT License)
* [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT License)
* [Yams](https://github.com/jpsim/Yams) (MIT License)
* [GCDWebServer](https://github.com/swisspol/GCDWebServer)

# 致谢

感谢 TF 版本交流群中的 @一梦浮生，@CZ36P9z9 等等伙伴对测试版本的反馈与帮助，也感谢 @王牌饼干 为输入法制作的工具。

# 捐赠

如果「仓」对您有帮助，可以请我吃份「煎饼馃子」，感激不尽~

> 注意：不接收有偿咨询服务，请勿因此打赏，谢谢。

<img src="https://ihsiao.com/aliPay.jpeg" width="207" height="281" />
<img src="https://ihsiao.com/wechatPay.jpeg"  width="207" height="281" />


### AppStore

<a href="https://apps.apple.com/cn/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683?itscg=30200&amp;itsct=apps_box_appicon" style="width: 170px; height: 170px; border-radius: 22%; overflow: hidden; display: inline-block; vertical-align: middle;"><img src="https://is4-ssl.mzstatic.com/image/thumb/Purple126/v4/16/b3/b8/16b3b836-12aa-206a-f849-79e37bf6528c/AppIcon-0-1x_U007emarketing-0-10-0-85-220.png/540x540bb.jpg" alt="仓输入法" style="width: 170px; height: 170px; border-radius: 22%; overflow: hidden; display: inline-block; vertical-align: middle;"></a>

<a href="https://apps.apple.com/cn/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683?itsct=apps_box_badge&amp;itscg=30200" style="display: inline-block; overflow: hidden; border-radius: 13px; width: 250px; height: 83px;"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&amp;releaseDate=1680912000" alt="Download on the App Store" style="border-radius: 13px; width: 250px; height: 83px;"></a>
