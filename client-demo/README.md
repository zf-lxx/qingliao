# 轻聊 · 本地交互演示

Flutter Web 原型，非真实聊天服务；所有联系人/消息/输入中状态均为合成数据，不连接账号、不联网发消息、不保存会话。未推送仓库，未部署到 HK。

## 运行

当前预览：http://127.0.0.1:4329/ （box 本机）；监听 0.0.0.0:4329。用户端需通过 box 的预览/端口入口访问，本机地址不是用户电脑地址。

```bash
cd /workspace/tg-chat-research/demo
/home/box/sdk/flutter/bin/flutter pub get
/home/box/sdk/flutter/bin/flutter build web --release --no-web-resources-cdn
python3 -m http.server 4329 --bind 0.0.0.0 --directory /workspace/tg-chat-research/demo/build/web
```

## 已实现

- 深色 Telegram 风格、桌面分栏/手机单栏、会话搜索、可点击开聊滑入。
- 左缘拖动返回（拖动超过90px完成，否则复位）；滑动气泡回复、可取消回复。
- 发送文字的输入区→气泡 overlay 几何过渡，250ms；多行输入，Enter发送/Shift+Enter换行。
- 420ms 长按/鼠标右键菜单、背景模糊、选中消息预览、回复/复制、五种反应与600ms粒子 burst。
- 模拟 typing、回到底部按钮、原创 Lottie 贴纸面板与发送，3款循环笑脸。
- Esc关闭菜单/面板/会话，设置内减少动态效果与3倍慢放；桌面直接开关。
- 中文与反应 emoji 字体子集本地内置，CanvasKit本地构建，不要求素材外链。

## 验证与视觉产物

`flutter analyze` 无问题，`flutter test` 2项通过，覆盖开聊/发送/贴纸/长按回复/反应/手机左缘返回/滑动回复；Web release 构建成功。curl检查 index/main.dart.js/贴纸均200。

shots/01-desktop-welcome.png
shots/02-desktop-chat.png
shots/03-message-sent.png
shots/04-sticker-panel.png
shots/05-reactions-menu.png
shots/06-reaction-burst.png
shots/07-mobile-chat.png
shots/08-mobile-list.png
shots/09-mobile-swipe-reply.png
shots/open-send.mp4
shots/open-send.gif

**截图与视频来源**：Flutter 无头 widget test 的实际渲染（RepaintBoundary.toImage），非手绘 mock，非 Chromium 截图；视频由测试中按33ms推进的真实动画帧编码（约2.3秒，30fps采样），不是浏览器实时性能录屏。没有可调用的浏览器子代理，按 box-desktop 规则未用Shell Playwright/CDP代替。浏览器兼容、真机60/120Hz与真实耗电尚未验证。

## 明确缺口

- 没有后端/真实账号、推送、真实在线/已读、持久存储；双勾和时间仅为演示静态装饰。
- 未做语音录制、附件上传、图片查看器与通话，它们属于后续产品阶段。
- 返回收尾目前按位移，不做速度预测；回复回弹用easeOutBack近似而非最终物理模型；演示用贴纸未做复杂可见性调度。
- 回到底部按钮常驻，真实产品需按滚动距离显隐；联系人筛选“未读/群组”仅视觉标签，不是功能入口。
- 内置中文字体只覆盖演示字符，额外文字若缺字仍依赖平台回退；任意文本不能保证无外部字体下载。
- 首屏文字/布局和浏览器 CanvasKit 加载仍需真实浏览器验收，当前仅curl及Flutter渲染测试。

素材许可见 ASSET_LICENSES.md；原创贴纸CC0、Noto字体OFL、lottie MIT各自独立。
