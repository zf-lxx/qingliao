# 轻聊（暂名）

参照 Telegram 交互与动效的自建即时通讯工具。邀请制，小圈子自用。

- `server/`：Go 后端（单二进制、SQLite WAL、WebSocket、推送插件：小米 / FCM）
- `app/`：`mithka` 分支的新客户端（基于 [Mithka](https://github.com/iebb/mithka)，BSD-3-Clause）。纯 Dart 适配器对接轻聊后端，不再内置 libtdjson。Android applicationId 仍为 `xyz.qingliao.app`。适配覆盖见 `docs/mithka-adapter.md`。
- `client/`：0.2 及更早的 Flutter Android 内测客户端，本分支不再作为发行构建入口，仅作对照。
- `client-demo/`：Flutter 动效演示（聊天列表、开聊转场、滑返、发送气泡、滑动回复、长按菜单与表情回应、Lottie 贴纸）
- `docs/`：调研（research.md）与设计方案（design.md），以及 mithka 适配覆盖表

状态：后端一期完成，Android 内测客户端开发/验收中；未部署。
