# 轻聊（暂名）

参照 Telegram 交互与动效的自建即时通讯工具。邀请制，小圈子自用。

- `server/`：Go 后端（单二进制、SQLite WAL、WebSocket、推送插件：小米 / FCM）
- `client/`：Flutter Android 内测客户端（真实登录/WS 消息、SQLite outbox、重连同步、图片；详见客户端验收记录）
- `client-demo/`：Flutter 动效演示（聊天列表、开聊转场、滑返、发送气泡、滑动回复、长按菜单与表情回应、Lottie 贴纸）
- `docs/`：调研（research.md）与设计方案（design.md）

状态：后端一期完成，Android 内测客户端开发/验收中；未部署。
