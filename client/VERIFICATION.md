# 轻聊 Android 0.1.0 内测验收

验收：2026-11-10 23:43:28 CST (UTC+8)。所有服务仅运行在 box loopback，未部署 HW_HK 或任何远程服务器。

## 交付 APK

- 文件：`/workspace/qingliao-0.1.0-arm64.apk`（仓库内构建路径 `client/build/app/outputs/flutter-apk/app-release.apk`）。
- 大小：**43,618,559 bytes**（43.62 MB / 41.60 MiB）。
- 包名：`xyz.qingliao.app`；版本 `0.1.0+1`；仅 `arm64-v8a`；最低 Android 7.0 / API24，target36。
- SHA256：`8f2f126bd2602d9938e95e5b0d66e949a32677acea7dd01966fb7f70bb57d7b5`。
- `apksigner verify --verbose`：Verifies，APK Signature Scheme v2=true。
- 内测使用 box 的 Android debug keystore（`/home/box/.android/debug.keystore`），未入 Git；正式分发需固定正式签名。APK 本身与 build/ 也未入 Git。
- 未内置服务器地址、账号、邀请码或凭据；登录页地址默认为空。生产必须 HTTPS。

## 自动验收（真实结果）

`flutter analyze` → **No issues found**。

`flutter test --concurrency=1 --reporter expanded` → **5 项全部通过**：

1. HTTPS/根地址校验，拒绝 URL 内账号密码、query、fragment、公网明文 HTTP。
2. 中文 / emoji UTF-16 offset、嵌套 bold+italic 渲染；忽略拆分代理对的恶意范围。
3. 同一套 Flutter 页面桌面光栅截图：登录、真实会话的离线缓存、聊天和资料（不是人工填充假会话）。
4. **真实 UI 链路**：启动隔离 Go 服务，邀请注册两个账号；桌面 Flutter 页面中输入并点击发送 → 第二账号独立 WS 收到；第二账号 WS 回复 → 界面气泡出现；断开连接后在 UI 发送并收集本地 outbox → 重新连接补齐双方消息，服务端同 UUID 只有一条。
5. **协议/持久化回归**：真实 HTTP/WS 双向收发、离线消息补齐、引擎重建恢复 SQLite 游标/outbox、ACK 丢失式重复发送 UUID 去重、离线草稿同步、编辑/撤回/反应/置顶、会话状态与 @ 群消息、JPEG 1600px 压缩+去 EXIF、原始媒体上传和另一账号鉴权下载、个人已读互惠关闭、退出清缓存。测试仅使用临时随机账号密码，结束停止后端并删除数据。

`go test ./... -count=1` → **通过**（此次未改后端业务代码）。

`flutter build apk --release --target-platform android-arm64` → **成功**；`aapt dump badging` 核验标签“轻聊”、包名、版本、SDK、**唯一 ABI arm64-v8a**；`apksigner` 核验签名。完整本地构建/测试状态元数据见 Git 忽略的 `client/artifacts/verification.json`。

## 截图

以下均由 Linux Flutter 桌面渲染器生成，**不是 Android 真机/模拟器截图**：

- `client/shots/01-login-desktop.png`
- `client/shots/02-dialogs-desktop.png`（真实测试会话的离线缓存，含未读/@/置顶/免打扰/草稿）
- `client/shots/03-chat-desktop.png`（真实测试历史缓存，含富文本/表情反应/置顶）
- `client/shots/04-profile-desktop.png`
- `client/shots/05-chat-live-desktop.png`（**真实 Go 服务连接中**，由实际点击发送及第二账号回复生成）

## 未验证与明确边界

- Android 34 x86_64 模拟器在 box 初始化挂起：修复最小 /dev/kvm 用户权限，尝试已有 AVD/隔离新 AVD、无快照/无音频/禁用可选遥测和蓝牙后，仍未进入 ADB 可用状态；已停止挂起进程。公开排障参考 https://stackoverflow.com/questions/9220410/android-emulator-wont-start-in-linux ，未据此编造启动成功。
- 因此 **Android 真机运行、Android Keystore 恢复、原生相册选择器、Android 锁屏/后台网络、60/120Hz 动效性能尚未实测**。保留 `integration_test/app_test.dart` 和 `scripts/android_acceptance.py` 供后续正常模拟器/真机复验。
- 图片的 Dart 压缩/鉴权上传/下载链路已测；Android 原生选择器未测。未实现上传失败独立持久队列；上传错误需重新选图，上传完成后消息进入持久 outbox。
- MiPush / FCM 只有通道接口与候选检测，**没有 SDK/凭据/真推送**；无常驻前台服务；不承诺锁屏或强停送达。非小米的 FCM 仅候选，不是已验证 GMS 可用。
- Polls/Bot callback/语音/文件/可发送 Lottie 贴纸、完整文件夹编辑、全文搜索 UI、主动生成链接预览、头像上传 UI 未做。服务端富文本/按钮/链接预览数据可渲染，链接点击需确认；不自动加载 OG 图片。
- 无 E2EE；云端可读消息。本地令牌在平台加密存储；消息缓存 SQLite 未另加密。为防 Android 自动备份迁出密钥依赖的缓存，allowBackup=false。
- 内测本地库采用每账号 JSON 快照事务，确保事件/游标/outbox 一起提交；大规模历史存储需后续改为索引消息表并加入保留策略。

## 已同步里程碑

- `c24c5cb`：客户端真实协议、UI 和持久 outbox 首版。
- `e8aa50e`：真实双账号/UI/离线回归、离线草稿与完整字体、五张界面截图。
- 后续验收记录提交仅补充本文，不改变 APK 对应业务代码。
