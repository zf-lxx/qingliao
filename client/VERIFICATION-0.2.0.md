# 0.2.0 阶段包验证

日期：2026-11-11（中国标准时间 UTC+8）。**这不是整个0.2范围全部完工。** 实际源码节点 `bf8172e4a3441e337e9f487271439764bde98b5d`；后续仅补验证文档/性能测试host driver。

## APK
- `/workspace/qingliao-0.2.0-arm64.apk`
- 18,620,292 bytes（18.62 MB / 17.76 MiB），低于50MB目标。
- SHA-256：`528931d05efd2a4932fb61a472faee1482891f1b6918adce6e443184d80ac64f`
- `xyz.qingliao.app`，versionName `0.2.0` / versionCode `3`；minSdk24 / targetSdk36；仅 `arm64-v8a`。
- apksigner验证通过，与0.1.1签名完全一致：`6ecfda4d6452b40e2bf56c4f164d6a66c29233470f2d513291ce63f808ee5650`。沿用原内测debug签名，未换成正式商店签名。
- release + obfuscate + strip，符号保留在仓库外。APK不进入Git。
- 字体检查仅有tree-shaken MaterialIcons-Regular.otf（9,880 bytes）；没有打包自定义中文/emoji大字体，Android用系统字体。没有Telegram素材。

## 实际执行
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=1 --reporter expanded`：18通过，默认跳过1个需要凭据的生产连接探针。
- 随后显式启用凭据文件的生产连接探针：1通过（约4秒测试运行时间，不等同测得的连接时延）。凭据未打印、未入Git。
- 追加资料页导航/Hero返回/缓存统计提示断言后，chat_redesign_test三项复跑通过。
- 新增覆盖：按下/释放/取消；边缘返回取消/速度完成；菜单外点关闭；多选切换/权限/返回先退出；窄屏大未读数不溢出；资料即时打开和返回。
- 既有真实Go服务端UI收发/离线补发、握手恢复、引用图片、Hero查看器、未读定位等回归通过。
- `go test -count=1 ./...`：通过（非缓存）。
- 线上 `/healthz` 返回 `{"ok":true}`；正式客户端engine的公开WSS连接通过。
- 后端未修改、未部署，生产数据卷未触碰；没有声称新增API已上线。
- `client/shots/0.2/` 三张截图为自动化桌面渲染器输出，不是真机实拍；详见该目录README。

## 性能：没有伪造120Hz结果
- Android保留SDK默认Impeller策略，未设置禁用；实际小米设备采用何种GPU后端需要设备日志确认。参考 https://docs.flutter.dev/perf/impeller 。
- `adb devices -l` 没有连接的设备，因此没有小米120Hz实测。
- Linux profile构建所需pkg-config/GTK/clang/cmake/ninja等缺失；尝试安装时Debian镜像HTTP500导致apt签名检查失败，未关闭签名校验或换危险途径绕过。
- 因此**本轮没有Linux profile的FrameTiming p50/p95/p99数据，也没有可宣称的120fps/无掉帧结论**。headless widget测试不是GPU性能测试。
- 新增 `integration_test/motion_profile_test.dart` 和 `test_driver/motion_profile_driver.dart`。这是不联网的组件合成场景（列表→聊天→popup→滑回，12轮），输出build/raster/total p50/p95/p99及单阶段>8,333µs的帧数；不是网络/数据库全链路benchmark。
- 可在具备Linux工程/依赖或连接Android设备的环境运行（本轮未执行）：

```sh
flutter drive --profile -d <设备ID> \
  --driver=test_driver/motion_profile_driver.dart \
  --target=integration_test/motion_profile_test.dart
```

## 构建警告
Gradle成功（最终增量构建约26秒），但device_info_plus旧Kotlin Gradle Plugin兼容性有将来迁移警告；Flutter文件watcher有“Already watching path”非致命输出。本次退出码0并成功校验APK，不把这些警告说成已修复。

## 未完成（继续留在0.2）
完整范围见 `../docs/0.2-status.md` / `../docs/tg-style-spec.md`：语音/视频/文件/相册、云端FTS中文搜索、block/clear/report、服务端媒体索引/月桶，转发/拖选、资料全幅头像/快滚/捏合换列、发送形态连续变换与反应爆发、浅色主题和剩余旧设置页面重绘等均未完成。
