# 轻聊（暂名）

邀请制、小圈子自用的即时通讯工具。

- `server/`：Go 后端（单二进制、SQLite WAL、WebSocket、推送插件：小米 / FCM）
- `app/`：当前发行用的 Flutter 客户端。纯 Dart 适配器对接轻聊后端，不内置 libtdjson。Android applicationId 为 `xyz.qingliao.app`，可覆盖安装既有 0.x 版本。适配覆盖见 `docs/adapter-coverage.md`。上游版权说明见 `NOTICE` 与 `LICENSE`（BSD-3-Clause）。
- `client/`：0.2 及更早的 Flutter Android 内测客户端，本分支不再作为发行构建入口，仅作对照。
- `client-demo/`：Flutter 动效演示（聊天列表、开聊转场、滑返、发送气泡、滑动回复、长按菜单与表情回应、Lottie 贴纸）
- `docs/`：调研、设计方案，以及客户端适配覆盖表

状态：后端已部署；Android 内测客户端持续迭代。发行包见 GitHub Releases：https://github.com/zf-lxx/qingliao/releases
