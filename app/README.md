# 轻聊客户端

这是轻聊的 Flutter 客户端（Android 为当前发行目标）。它通过纯 Dart 适配器与轻聊后端通信，不连接第三方即时通讯网络，也不内置 `libtdjson`。

构建 Android arm64 发行包（在 `app/` 目录）：

```sh
source ~/sdk/env.sh
flutter build apk --release --target-platform android-arm64
```

- 应用名：轻聊
- applicationId：`xyz.qingliao.app`（可覆盖安装既有 0.x）
- 无 `android/key.properties` 时使用 `~/.android/debug.keystore`，与此前内测包一致
- 发行页：[zf-lxx/qingliao releases](https://github.com/zf-lxx/qingliao/releases)

版权与第三方声明见仓库根目录的 `LICENSE` 和 `NOTICE`。
