# 轻聊 Android · 0.1 内测

独立云端聊天，非 Telegram 客户端，无 E2EE。包名 `xyz.qingliao.app`。

```bash
export PATH=/home/box/sdk/flutter/bin:$PATH
export JAVA_HOME=/home/box/sdk/jdk21
export ANDROID_HOME=/home/box/sdk/android
flutter pub get
flutter analyze
flutter test test/engine_live_test.dart
flutter test
flutter build apk --release --target-platform android-arm64
```

登录页服务器地址默认为空，生产只允许 HTTPS 根地址。HTTP 仅允许 localhost、127.0.0.1 和 Android 模拟器宿主 10.0.2.2。应用不预装任何账号/邀请码/服务器密码。

令牌保存于 flutter_secure_storage（Android 加密存储）。消息缓存和 outbox 为应用私有 SQLite，未另行加密；事件与游标同事务落盘后 ACK。当前单个账号一个 JSON 快照事务，是内测正确性基线，不是大规模历史存储设计。退出清理缓存及 outbox，注销失败时默认不静默丢弃本地消息。

## 实现范围

- 邀请注册、登录；真实会话分页快照及 WS 事件；稳定 UUID outbox、断线指数退避重连、同游标离线补齐、失败手动重试。
- 会话未读/@、置顶、归档、免打扰、草稿；文件夹读取/筛选和新建“未读”文件夹。
- 私聊/群聊创建、用户搜索、昵称修改；文字、回复、编辑、撤回、反应、消息置顶。
- UTF-16 富文本、内联 URL 按钮、文字链接需点击确认；Bot callback 按钮明确提示二期。
- 本地图片选取，1600px/82% JPEG 压缩、移除 EXIF、鉴权上传和鉴权图片下载/缩放查看。
- 阅读只有聊天页在前台、底部可见时上报；遵守全局/个人回执隐私。stored 单勾，已读双勾，不伪造 delivered。
- 沿用 demo 深色配色、字体、250ms 消息动效与 Cubic(.33,.52,.25,.99) 聊天切页；边缘滑动返回、滑动回复和长按反应菜单。

## 明确未完成

厂商 Push SDK/凭据/通知权限、真实 GMS 能力探测、后台前台服务、头像上传 UI、完整文件夹编辑器、投票/Bot/语音/文件发送、可发送动态贴纸、全文搜索 UI、链接预览生成开关、真机 60/120Hz 性能验收。MiPush 仅设备品牌建议，其他设备 FCM 仅候选标识；没有伪装注册/送达。没有后台/强停秒达保证。

Release 暂用 box 的 Android debug keystore（`~/.android/debug.keystore`，不入 Git），仅供内测；正式分发须更换并安全备份固定签名，换签需卸载重装。

## 验收复现

`flutter test test/engine_live_test.dart` 自动编译/启动隔离的本地 Go 服务，生成随机临时 bootstrap，使用两账号真实 HTTP/WS；结束停止服务并删除测试数据。会输出不含凭据的 `artifacts/screens-state.json`，仅供后续截图（Git 忽略）。

`flutter test test/ui_live_test.dart` 使用 LiveTestWidgetsFlutterBinding（Linux Flutter 桌面渲染器），真实点击输入框/发送按钮，第二账号独立 WS 收到消息并回复，验证气泡出现；离线在 UI 发送，恢复连接补齐且服务器只有一个 UUID。产出 `shots/05-chat-live-desktop.png` 是**真实连接时**截图，不是 Android 截图。

`flutter test test/screenshots_test.dart` 由 Linux Flutter headless 桌面渲染器生成 `shots/*-desktop.png`，展示上个真实会话的**离线缓存**，不是 Android 真机/模拟器截图。没有 fixture 时该测试跳过。

`python3 scripts/android_acceptance.py` 为 Android 集成测试驱动（登录 UI、双账号、重连、截图）；要求已正常启动的 Android 模拟器，可通过 TEST_DEVICE 指定。此次 box 模拟器初始化挂起，未能完成此项，不能据此声称 Android UI/Keystore/相册插件已实测。

Flutter 同目录的 analyze/test/build **串行**运行，避免插件注册生成文件与 release build 发生竞态。

验收和 APK 信息见 `VERIFICATION.md`（完成后补齐）；代码未部署 HK。
