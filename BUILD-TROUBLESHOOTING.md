# GitHub Actions 构建排错

## 已修复：`api.github.com request failed?!`

旧工作流调用 RootHide 的 `install-theos`。该脚本还会执行 Theos 的 `install-sdk`，通过 GitHub Releases API 查询 SDK 下载地址。GitHub Runner 遇到 API 限流或临时异常时会以退出码 8 终止。

v0.1.1 不再调用该安装器：

1. 直接递归克隆 `roothide/theos`。
2. 读取 Runner 已安装 Xcode 的 iPhoneOS SDK。
3. 将该 SDK 链接到 `$THEOS/sdks`。
4. 构建 RootHide `iphoneos-arm64e` DEB。

本 tweak 只链接 UIKit 和 WebKit，不链接 Safari 私有 Framework，所以 Xcode 自带 SDK 足够。

## 使用方式

将压缩包内容完整覆盖仓库，尤其是：

```text
.github/workflows/build.yml
control
README.md
```

然后在 Actions 中重新运行 `Build RootHide DEB`。
