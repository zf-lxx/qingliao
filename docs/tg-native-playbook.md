# 若要达到 Telegram 原生客户端效果，需要做什么

日期：2026-11-11（Asia/Shanghai）。配套阅读：[tg-gap-research.md](tg-gap-research.md)、[tg-style-spec.md](tg-style-spec.md)、[research.md](research.md)。

本页是工程路径，不是再解释「为什么不像」。默认法律约束：不复制 DrKLO Java/资源，不冒充 Telegram，只读参数后独立实现。若考虑「直接用开源代码」，见第 8 节——那是另一条产品，不是给轻聊 Go 后端换皮。

## 0. 先把目标说死

「TG 原生效果」不是一个开关。分三档，混在一起会永远觉得差：

| 档 | 用户怎么验 | 现实 |
|---|---|---|
| **A. 看起来像** | 静帧截图：颜色、间距、气泡尾巴、字体、未读胶囊、玻璃头 | 几周到两三个月能逼近。你们 0.2 已经做了一半视觉 token |
| **B. 用起来像** | 跟手返回、发送文字从输入框飞进气泡、录音锁/取消、列表插入邻居上挤、长按反应、键盘/emoji 连动 | 这是 TG 真正贵的一层。按正式客户端 + 真消息，大约 **一个专职客户端组 6–12 个月** |
| **C. 跑起来像** | 小米 120Hz 连续收发/狂滑不掉帧，弱网不卡手势，千条历史滚动锚点不跳，低端机关特效仍顺 | 必须有 `ImageReceiver` 级缓存、设备分档、主线程零 IO。没有真机 FrameTiming 不许宣称达标 |

官方 Android 是 **12 年原生自绘引擎**（单聊天页 4.8 万行、单气泡 2.4 万行）。「像素级无法区分 + 全功能对等」包含通话、贴纸生态、千万级对话、E2EE 云、Bot 平台——那是产品公司规模，不是本仓库下一阶段。

**建议你们把目标写成：在小圈子 Android 上，核心聊天路径达到 B，并在指定小米机上用数据证明 C 的聊天/列表/发送三项。** 不要写「全面达到 TG」。

达不到 C 的 B，用户仍会说卡。只做 A，用户仍会说假。

## 1. 必须换掉的架构（不换就不可能像）

现在这条链路到不了 B：

```
ListView.builder
  → Bubble(Container + ShapeDecoration)
  → 每条 TweenAnimationBuilder(begin:0)
  → 图片 FutureBuilder(整文件 Uint8List)
  → TgPageRoute(opaque 整屏滑入)
  → 输入栏 Row(emoji + TextField + 图标)
```

要换成这条：

```
ChatViewport（自管滚动、锚点、插入/move 协调）
  → ChatMessageRenderObject（一次 layout + 一次 paint）
  → MessageEnterOverlay（composer → 气泡几何插值）
  → MediaCache（按显示尺寸解码、磁盘分层、可见才绑纹理）
  → GestureNavHost（手指=进度，背后真页，predictive back）
  → Composer（同一套 morph：mic/camera/send/录音圈/面板高度=键盘）
```

Flutter **可以**走这条路（`RenderBox` / `Sliver` / `Overlay` / `Listener`）。默认 `Material` + `AnimatedContainer` **不可以**。这是二选一，不是逐步美化。

两条技术路线，选一个，不要混：

| | Flutter 自绘引擎 | Android 原生重写 |
|---|---|---|
| 做什么 | 在现有 Dart 协议/outbox 上重建渲染层 | Kotlin + 自绘 View，协议层可继续 Go |
| 优点 | 保住现有登录/同步/测试；以后 iOS/桌面同逻辑 | 更接近 TG 的 View 模型、系统 predictive back、厂商 ROM |
| 代价 | 要写自己的 RenderObject 聊天列表，等于自研一套 IM UI 框架 | 现有 Flutter UI 作废；iOS 再写一遍 |
| 何时选 | 要继续一套代码打多端 | 只做 Android，且接受 0.2 UI 作废 |

**不建议**：fork `DrKLO/Telegram` 改成轻聊协议。GPL 传染、包名/推送/签名全是 Telegram 的、素材不能用，最后得到一个违法又难维护的套壳。

下面默认走 **Flutter 自绘引擎**（与当前仓库一致）。若改原生，工作项同名，只是实现语言换成 View/RecyclerView。

## 2. 六条工作流（按收益排序）

每条都有「完成定义」。没有真机录屏 + 帧数据，不算完成。

### W1. 消息是 RenderObject，不是 Widget 树

拆 `main.dart` 里的 `Bubble`。一条消息只做两件事：`performLayout` 量出气泡路径/文本/媒体盒/时间戳避让；`paint` 一次画完。

必须包含：

- 短文本与时间戳 **同一行避让**，长文本时间戳右下角嵌入，不另起一行把泡撑高
- 尾巴是路径的一部分，分组时圆角 17→5，不是叠一个三角形
- 选中态、回复条、反应、失败重试都在同一 paint，不套一层 `AnimatedContainer`
- **入场动画不在消息 widget 内部** `begin:0`。插入由列表层驱动 translation/alpha；滚动回收不得重播
- 媒体盒 **先有宽高**。没下载完也占位，禁止 `Image.memory` 加载后撑开导致列表跳

验收：千条历史快速滑动，锚点不变；旋转屏幕气泡宽度重算但不闪；同一条消息 `build` 次数在滚动中接近 0（用 timeline：只有 visible 绑定纹理）。

### W2. MessageEnterTransition（观感最大单点）

点发送时：

1. 先持久化 outbox（现有可靠性不能丢）
2. Overlay 捕获 composer 文字的 layout/位置/圆角/颜色
3. 250ms 内插值到目标气泡 rect；列表邻居同步上移
4. 动画结束只留列表里那一条，overlay 销毁
5. 可打断：动画中再发第二条，从当前几何接续，不从 0 重来
6. 多行文本、回复引用、键盘高度变化都要测

语音/图片后续各做专用过渡（TG 就是分开的）。先做文字。

验收：慢放录屏，输入框内容连续变成气泡，中间没有「清空再冒出来」。`client-demo` 可参考思路，但必须接真实 `client_msg_id`。

### W3. 手势导航 = 手指，不是路由动画

替换 `TgPageRoute`：

- `opaque: false`，背后是 **还活着的聊天列表**，不是截图像素
- 拖动阶段 `progress = dx / width`，无缓动
- 松手：完成 `max(200×剩余/宽, 50)ms`，取消 `max(320×距离/宽, 120)ms`；接入系统 predictive back 的缩放分支
- scrim 跟 TG 所核分支走（约 `120×clamp(offset/width,0,.8)`，最大 ~96/255），不要 30% 拍脑袋黑
- 边缘热区、速度阈值、与气泡右滑回复仲裁（横向锁向）

验收：慢滑可停可退；快甩能出；从聊天滑回时列表滚动位置还在。

### W4. 媒体管线（不做 C 就永远卡）

对标 `ImageReceiver` 的职责，不必对标其代码：

- 磁盘缓存：原图 / 显示尺寸解码结果分开
- 只按气泡宽（如 240dp×dpr）解码，禁止全分辨率进 GPU
- 并发上限（例如 2 个 decode isolate）
- 离屏暂停、可见再绑
- 上传继续现有 1600px/q82 去 EXIF
- 下载 Range + 进度；语音/视频另档，不走「整段变图片」

服务端补齐：`kind=video`、宽高/时长/thumbnail_id、shared-media 分页。没有元数据，客户端无法稳定占位。

验收：连续打开 30 张图再滑回聊天，RSS 不线性涨；滚动时无主 isolate 解码尖峰。

### W5. Composer 是状态机，不是一排 Icon

输入栏五种互斥形态，同一套 220ms EASE_OUT_QUINT morph，禁止图标突变：

1. 空：mic（按住录音）+ 附件 + emoji
2. 有字：send
3. 媒体模式：camera
4. 录音中：波形 / 上滑锁 / 左滑取消（参数见 spec 已摘录）
5. emoji/键盘：高度跟 IME inset，列表 `padding` 跟手，不双重平移

录音权限拒绝要失败可见，不能装成功。

验收：空→打字→清空，按钮连续形变；录音三手势可撤销；来电/后台中断丢弃未发送文件。

### W6. 性能分档 + 真机账本

`SharedConfig` 那套三档必须有轻聊自己的实现：

- LOW：关 blur、关壁纸动态、发送只用 alpha、列表动画缩短
- AVERAGE：静态墙纸 + 轻过渡
- HIGH：玻璃、完整 EnterTransition、反应粒子（原创，不搬 TG Lottie）

每个版本在 **指定小米 120Hz** 上跑固定剧本，记下 UI/raster p50/p95/p99、超 8.33ms 帧比例：

- 进/出聊天 ×20
- 连发 20 条文字
- 狂滑 1000 条
- 打开/关闭图片 ×20
- 录音锁/取消 ×10

没有这张表，不得写「已达原生流畅」。

## 3. 功能完整度（不像的另一半）

手感做到 B，功能仍缺，用户还是会说山寨。0.2 未完项要当产品做完，但 **不要和 W1–W3 抢同一迭代**：

- 语音/视频/文件/组图（协议已有 voice/file，缺 video 元数据与客户端）
- 云端 FTS、block、清空历史、举报、合法转发
- 资料页快滚/月桶/捏合换列
- 浅色主题、设置页按 TG 信息架构重绘
- 推送常驻（0.3）：没有后台到达，前台再顺也是「假 IM」

通话、贴纸商店、Bot 生态、E2EE 不是「像 TG」的前提，是另一个产品。

## 4. 组织方式：别再在 `main.dart` 里堆

建议拆仓内模块（仍一个 app）：

```
client/lib/
  protocol/     # 已有 api/engine/storage，少动
  media/        # cache, decode, upload
  compositor/   # ChatViewport, item animator, enter transition
  cells/        # message/dialog painter + layout
  composer/     # 输入态机、录音、面板
  navigation/   # 手势栈
  chrome/       # 列表页、资料页、设置（可以继续用 Widget）
```

协议层（Go + outbox + WS）是你们已经超前的部分，**不要推倒重来**。推倒的是 UI 绘制模型。

人力（经验值，小圈子质量，不是官方客户端）：

| 角色 | 投入 |
|---|---|
| 客户端（Flutter RenderObject / 手势） | 1 人全职 6–9 个月到 B；C 再加 2–3 个月真机打磨 |
| 客户端（媒体/录音/相册） | 0.5–1 人并行 3 个月 |
| 后端（media metadata、shared-media、FTS、block） | 0.5 人 2–3 个月 |
| 设计验收 | 固定一台小米 + 录屏对照清单，每周一次，不要靠桌面截图 |

一个人兼职「顺便把动画调一调」到不了 B。

## 5. 前 8 周（若现在开工）

只做能被录屏证伪的事：

1. **W1 骨架**：一条文本气泡 RenderObject + 时间戳同行 + 列表插入不重播入场。旧 `Bubble` 可并存，新路径先走文本。
2. **W2 文字飞入**：只覆盖自己发送的纯文本，无回复、无键盘变化也可先做，但必须接 outbox。
3. **W4 最小缓存**：图片按 240dp 解码 + 磁盘缓存，去掉气泡内整文件 `Image.memory`。
4. **W6 仪表**：profile 驱动在真机跑通，产出第一张帧表（现在没有设备就先把脚本稳定，数字留空）。
5. 禁止：新贴纸、新主题、新设置页、抄更多曲线常量、为「像」去加 blur。

8 周结束的判断：发送一条中文，慢放像飞入；滑 200 条不跳；APK 仍 <50MB。不像就停功能开发，继续打这一条。

## 6. 不要做的事

- 继续给 `AnimatedContainer` / `Hero` 填 TG 时长，以为能逼近 B
- fork 官方仓或翻译 `ChatActivity.java`
- 把 Lottie/TGS/图标搬进 APK
- 在 Linux 桌面截图上写「已对齐 120Hz」
- 用占位 mic 假装能录音
- 为动画牺牲 outbox：发送必须先落盘再开 overlay
- 同时开通话/Bot/E2EE「显得更完整」

## 7. 一句话

要达到 TG 原生效果，不是把轻聊「做得更精致」，而是 **把聊天 UI 从组件拼装升级成自研渲染引擎**：自己 layout/paint 消息、自己协调列表插入、手指驱动导航、按显示尺寸管媒体、按设备降级。协议你们已经有了；缺的是官方用十二年写完的那一层。选 Flutter 或原生都可以，但不选「继续堆 Widget」。目标写成 B+部分 C，并用小米真机帧表验收，否则会永远觉得差一截。

## 8. 「直接用 Telegram 开源代码」是什么意思

开源的是 **客户端**，不是服务端。官方仓没有聊天服务器。Android 连的是 MTProto：Java `ConnectionsManager` 约 1600 行，其中 **39 个 native 方法** 进 `jni/tgnet`；业务在 `MessagesController.java`（约 **2.6 万行**）。气泡、输入栏、导航全部假设消息是 `MessageObject` / `TLRPC.*`，不是轻聊的 JSON `kind/text/media_id`。

所以「直接用源码」只有四条路，没有「换个 base URL 接到 `qingliao/server`」。

### 路 1：官方客户端 + 官方云（编译 DrKLO）

README 要求：自备 `api_id`、Firebase、自己的 release keystore、填 `BuildVars.java`。能得到 **真·原生手感**，因为跑的就是 Telegram。

- 数据在 Telegram 服务器，不是你们的 SQLite/邀请码/香港机
- 不能当「轻聊」发：官方禁止用 Telegram 名和纸飞机误导；应用商店会打非官方客户端
- GPL：分发 APK 必须提供对应源码
- 贴纸/品牌图即使仓里有文件，也不等于你们可商用
- 国内推送、登录风控、验证码、封号，全是 Telegram 的问题，不是你们能改协议解决的

这是「用 Telegram」，不是「轻聊达到 TG 效果」。

### 路 2：fork 客户端，把 MTProto 换成轻聊 HTTP/WS

这是「直接用源码接自己后端」的字面意思，也是最常被低估的。

要动的不是换 `ChatMessageCell` 里几个颜色，而是：

- 重写 `tgnet` / `ConnectionsManager` / `FileLoader` / 更新层
- 把 `TLRPC` 结构映射到轻聊消息（无 `peer`/`pts`/`qts`/`channelDifference`，有 `event_seq`/`client_msg_id`）
- `MessagesController` 2.6 万行里每一处 `TLRPC.Message` 分支（服务消息、相册组、转发源、付费媒体、todo、stories…）要么实现，要么删并修编译
- JNI：`tgnet`、`voip`/`tgcalls`、`ffmpeg`、`lottie`/`rlottie`、`sqlite` 包装、OpenSSL。APK 会立刻超过你们 **50MB** 预算（官方包是百兆级，还含 so）
- 推送从 FCM/官方渠道改成你们的小米/FCM 模块
- GPL **传染整个 App**：轻聊 Flutter/Go 若链进同一分发物，源码义务覆盖面要律师看；至少 Android 客户端必须开源

工作量不是「省下 6–9 个月 Flutter 自绘」，而是 **18–36 个月改一台与官方同步的巨型分叉**，且每次上游更新都是合并地狱。官方一周可以改 `ChatActivity` 里任意私有假设。你们接的是 JSON 聊天，不是 MTProto。

结论：比独立写 RenderObject **更贵、更脏、APK 更大、法律更紧**。只有在「放弃轻聊协议、改做 Telegram 第三方」时才合理，而那又撞路 1 的品牌禁令。

### 路 3：只抽引擎，不抽协议（理论上的「借手感」）

想借的是：`ChatMessageCell` 绘制、`ChatListItemAnimator`、`TextMessageEnterTransition`、`ActionBarLayout`、`ImageReceiver`。

它们 **不是库**。Cell 直接调 `MessageObject`、`Theme`、`UserConfig`、`ImageReceiver`、`SharedConfig`、emoji 资源 ID。剪出来等于再实现一整套 stub，最后还是在重写，并且剪出来的 Java 仍是 GPL，进 Flutter 工程还会变成双栈。

独立重写这些类的 **行为参数**（你们正在做的）合法；剪文件进仓库不合法也不省事。

### 路 4：自己的 API_ID + 官方云，做「轻聊皮的 Telegram 客户端」

手感立刻满分，后端你们可以扔掉。产品变成 Telegram 第三方：

- 用户必须能登录 Telegram（验证码、+86 风控、被封）
- 小圈子邀请制、自建香港、消息在自己磁盘上——这些目标全部反向
- 仍要换名换图标，仍要开源

若目标已变成「我们就要官方云」，应直接让圈子用官方 App，不要维护分叉。

### 对照

| 做法 | 手感 | 数据在哪 | 和现有 Go/Flutter | 法律 | 现实工期 |
|---|---|---|---|---|---|
| 继续轻聊，自研绘制层 | 做到 B/C 看投入 | 你们的服务器 | 保留 | 干净 | 6–12 月 B |
| 编译官方仓连 Telegram | 立刻满分 | Telegram | 现有代码作废 | GPL + 品牌限制 | 周级能编过，产品不是轻聊 |
| fork 后接轻聊协议 | 前期像，后期分叉腐烂 | 你们的服务器 | Flutter 作废，Go 要模拟 TL | GPL 传染，50MB 破 | 以年计 |
| 剪 Cell/Animator 进 Flutter | 假想 | 你们 | 双栈 | GPL | 并不比自写短 |

**建议**：不要把官方仓当轻聊客户端用。开源的价值是 **只读参数、看架构、对照验收**（research / spec / gap 已经在用）。手感要靠第 2 节那六条工作流，用自己的协议画自己的像素。
