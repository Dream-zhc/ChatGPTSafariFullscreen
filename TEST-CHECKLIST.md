# iOS 16.1 / RootHide 测试清单

## 安装前

- 删除之前的 ChatGPT Web Clip 描述文件。
- 卸载旧 WebGPT 测试 App，避免误判。
- 在 Choicy 中先仅允许本 tweak 注入 Safari，暂时关闭其他 Safari tweak。

## 基础

1. 彻底结束 Safari后重新打开。
2. 访问普通网站，确认地址栏正常显示。
3. 访问 `https://chatgpt.com/`，等待 1 秒，确认工具栏隐藏。
4. 三指双击，确认工具栏显示；再次三指双击，确认隐藏。
5. 打开 Google/Apple/OpenAI 登录页，确认工具栏恢复。
6. 登录回到 ChatGPT，确认自动隐藏。

## 性能

1. 打开一个很长的对话。
2. 快速上下滚动 30 秒。
3. 连续输入、发送消息。
4. 切到桌面 1 分钟后返回。
5. 对比未启用 tweak 时 Safari 的滚动、输入和长任务表现。

## 异常

如果进入 Safe Mode 或 Safari 闪退：

- 立即卸载 tweak。
- 收集 `/var/mobile/Library/Logs/CrashReporter/` 下最新 MobileSafari 日志。
- 同时收集带 `[ChatGPTSafariFullscreen]` 的系统日志。
