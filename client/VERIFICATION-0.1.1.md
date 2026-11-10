# 轻聊 0.1.1 验收记录

2026-11-11，中国标准时间 UTC+8。此记录区分自动化验证与真机验证。

## 安装包
- `/workspace/qingliao-0.1.1-arm64.apk`
- 18,552,288 bytes = 18.55 MB / 17.69 MiB。
- SHA-256：`13bf927ce418369969a6c5e29000afedf392e95e98b7fd14994f30d5d9e888d8`
- `xyz.qingliao.app`，versionName `0.1.1` / versionCode `2`，唯一 ABI `arm64-v8a`。
- `apksigner verify` 成功，证书与 0.1.0 完全一致，可覆盖升级（仍是现有内测 debug 证书，不冒称正式商店发布签名）。
- 不含中文/彩色表情字体；只有 Flutter 裁剪后的 MaterialIcons。

## 已运行
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --concurrency=1 --reporter expanded`：13 项通过；默认跳过 1 项需要本机测试凭据的公网测试。
- 单独设置本机 `QINGLIAO_TEST_CREDENTIALS` 运行 `public_connection_probe_test.dart`：香港生产站 REST + WSS + hello/resume，全流程通过。
- `go test ./...`：通过。
- ARM64 obfuscate/strip release 构建成功；符号文件只保留在仓库外 secrets 目录。

覆盖：真实 Go 双账号收发/断线补发/幂等/草稿/媒体；WS 升级后无 hello、无 resume result 的期限与自动重连；URL/Auth；连接标题1秒去抖和220ms替换；图片回复摘要和有效性；图片Hero/双击缩放/工具栏/拖动退出；未读首次定位、分隔条、回到底部和重新进入；UTC+8分天。

## 已知边界
- 没有在 Xiaomi 真机运行本版；不能宣称真机连接故障被唯一定位，亦不能宣称120Hz无掉帧。
- Android相册保存、系统分享、原生网络回调已编译，但仍需真机操作验证。
- 0.1.1不是整个界面的TG重设计。完整动画参数、菜单、多选、浮动头部/输入栏等见 `../docs/tg-style-spec.md`。
- 本次没有修改/重新部署生产后端。连接取证与不能下定论的部分见 `../docs/connection-0.1.1.md`。
