# ChatGPT Safari Fullscreen — RootHide / iOS 16

一个仅注入 `com.apple.mobilesafari` 的轻量 tweak。它不创建 WKWebView、不改网页 DOM、不做后台保活，也不注入 WebContent 进程。

## 行为

- 当前页面是 `chatgpt.com` 或旧域名 `chat.openai.com` 时，自动请求 Safari 隐藏顶部/底部工具栏。
- 进入 OpenAI、Google、Apple、Microsoft、Cloudflare 等登录/验证域名时，自动恢复工具栏。
- 三指双击任意位置：手动切换工具栏显示/隐藏。
- 切换到其他网站：恢复 Safari 工具栏。
- 上滑结束 Safari：正常结束，不做守护或复活。

## 构建

项目已包含 GitHub Actions。上传到 GitHub 后：

1. 打开 Actions。
2. 运行 `Build RootHide DEB`。
3. 下载 `ChatGPTSafariFullscreen-RootHide` artifact。
4. 解压后，用 Sileo/Zebra/Filza 安装 `.deb`。
5. 安装后彻底退出 Safari，再重新打开；必要时在 RootHide Manager 中执行用户空间重启。

本地构建：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## 安全范围

Filter 只包含：

```text
com.apple.mobilesafari
```

不会注入：

```text
com.apple.WebKit.WebContent
com.apple.WebKit.Networking
SpringBoard
```

因此不会扫描 ChatGPT 的长对话 DOM，也不会参与网页绘制、流式传输或网络请求。

## 日志

若未自动隐藏，SSH 后运行：

```bash
log stream --style compact --level debug \
  --predicate 'eventMessage CONTAINS "[ChatGPTSafariFullscreen]"'
```

然后：

1. 打开 Safari。
2. 访问 `https://chatgpt.com/`。
3. 在 ChatGPT 和登录页面之间切换。
4. 发送日志。

## 卸载与安全模式

如果 Safari 异常：

1. 进入安全模式或通过 SSH。
2. 用 Sileo/Zebra 卸载 `ChatGPT Safari Fullscreen`。
3. 用户空间重启。

这是首个针对 iOS 16.1 MobileSafari 私有界面的实验版本。Safari 私有类在不同系统小版本可能不同；代码包含多级兼容路径，但必须真机测试才能确认哪条路径在你的 16.1 上生效。
