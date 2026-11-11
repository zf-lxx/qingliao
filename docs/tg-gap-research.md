# 为什么 Telegram Android 开源，轻聊还是差一截

调研日期：2026-11-11（Asia/Shanghai）。只读分析 [DrKLO/Telegram](https://github.com/DrKLO/Telegram) `master` 公开文件与本仓库实现；**没有把 Telegram 源码/素材拷进仓库**。上游会变，行号仅作当日证据。

## 0. 先回答两个问题

**Telegram Android 是开源的。** 官方仓 `DrKLO/Telegram`，许可证 **GPL v2 or later**。README 明确欢迎基于 API 做自己的应用，但要求：自备 `api_id`、不要用 Telegram 名称误导、不要用官方纸飞机 logo、遵守安全指南、**衍生代码也要开源**。贴纸/品牌图/TGS 资源另算版权，开源客户端 ≠ 素材可商用。

**开源帮不上「直接变顺」。** 轻聊用户策略已经禁止复制 GPL 实现和素材，只能读尺寸/曲线/时长/交互再 Flutter 重写。即便允许复制，也复制不来：官方 Android 是 12 年原生自绘引擎，不是一套 CubicBezier 常量。

轻聊 0.2.0 已经把不少 **数字** 对齐了（250ms 消息曲线、220ms 标题、320ms tab、80/350ms 按下回弹、EASE_OUT_QUINT）。文档自己也写了：这些数字不等于手感。差的是 **谁在画、画几层、手势谁接管、列表怎么协调几何变化**。

## 1. 体量对照（当日实测）

| 模块 | Telegram Android | 轻聊 Flutter |
|---|---|---|
| 聊天页控制器 | `ChatActivity.java` **48,317 行 / 2.5 MiB** | `main.dart` 把登录/列表/聊天/气泡/压缩全塞一起，**3,162 行** |
| 气泡单元 | `ChatMessageCell.java` **24,168 行**，几乎整页 `onDraw` | `Bubble` ≈ 400 行 `Container` + `ShapeDecoration` + `FutureBuilder` |
| 输入栏 | `ChatActivityEnterView.java` **15,999 行**（录音圈、波形、面板、键盘） | 一行 `Row`：emoji + TextField + 附件 + camera/send 切换 |
| 会话行 | `DialogCell.java` **6,596 行**，自绘名称/草稿/双勾/未读动画 | 组合 Material 组件 |
| 导航栈 | `ActionBarLayout.java` **3,738 行**，多分支返回（48dp / 跟手 / predictive） | `TgPageRoute` ≈ 130 行，整屏滑入 + 自选 1/4 视差 |
| 图片管线 | `ImageReceiver.java` **3,441 行** | `ChatApi.media()` 整文件下载进内存，气泡里 `Image.memory` |
| 发送飞入 | `TextMessageEnterTransition.java` **885 行** + `VoiceMessageEnterTransition` 185 行 | `TweenAnimationBuilder`：自己的 pending 气泡从 +92dp / +20dp 淡入 |
| 气泡背景 | `MessageDrawable.java` **908 行** 路径/渐变/选中/尾巴 | `TgBubbleShape` 圆角矩形 + 二次贝塞尔小三角 |
| 客户端合计 | 十年原生工程（JNI/FFmpeg/Opus/WebRTC/tgnet…） | `client/lib` **15 个 Dart 文件 / 6,537 行** |

数字本身不证明「行数=品质」，但说明 TG 把「看起来简单的一条气泡」做成了独立渲染器。轻聊目前是 **能工作的聊天产品壳 + 抽过参数的 Material 动画**。

## 2. 差在五层，不是差在「动画库」

### 2.1 绘制模型：自绘 Cell vs Widget 树

Telegram 消息不是套 `LinearLayout`。`ChatMessageCell` 自己算文本 `StaticLayout`、回复条、媒体矩形、时间戳占位、反应、转发头、选中遮罩，最后一次 `onDraw`。气泡外形是 `MessageDrawable`，尾巴和圆角随「是否分组 / 发出 / 选中」改路径，不是给 `Container` 换 `BorderRadius`。

轻聊气泡是：

- `Align` + `Container` + `TgBubbleShape`
- 时间戳单独一行 `Row` 垫在底部（规范要求短文本与时间 **同行避让**，此项未做）
- 图片 `FutureBuilder<Uint8List>`，没有固定宽高占位，加载完成会撑开列表
- 每条消息一个 `TweenAnimationBuilder(begin:0,end:1)`：widget 重建就会重新播入场

结果：图层多、布局多次、列表锚点容易跳、入场动画会在滚动回收后重放。TG 的流畅首先来自 **少合成、少 relayout、几何预先知道**。

### 2.2 发送动画：几何变形 vs 整泡位移

TG 自己发文字时走 `TextMessageEnterTransition`：

1. 从输入框截当前文字 `StaticLayout`（必要时栅格成 bitmap）
2. 在 `MessageEnterTransitionContainer` 覆盖层按进度插值：输入框圆角半径 → 气泡半径、颜色、文本位置、回复引用条
3. `ChatListItemAnimator`（`DEFAULT_DURATION=250`，那条著名三次贝塞尔）同时把 **邻居消息** 往上挤
4. 语音另有 `VoiceMessageEnterTransition`，不是复用文字淡入

轻聊文档已经写明现状：pending 自有消息 92dp/20dp 上移入场，**不是匹配输入框形状的 MessageEnterTransition**。用户看到的是「一条新气泡从下方冒出来」，不是「输入框里的字飞进气泡」。这是观感差距最大的单点。

`client-demo` 做过一版 overlay 飞入（本地假数据）。正式客户端为了接真实 outbox / 可变高度历史，把这条链路丢掉了，只留淡入。

### 2.3 手势与导航：手指驱动 vs 路由动画

TG `ActionBarLayout` 不是单一 PageRoute：

- 拖动阶段 **进度=手指**，不先套缓动
- 松手按时长公式：完成 `max(200×剩余/宽, 50)ms`，取消 `max(320×距离/宽, 120)ms`；predictive back 还有 380/320ms 下限 + `EASE_OUT_QUINT`
- 背后那页是 **还活着的上一个 Fragment**，有独立视差和 scrim（所查分支 scrim 最大约 96/255，不是 50% 黑）
- Android 12+ 还有系统 predictive 的缩放形变分支

轻聊 `TgPageRoute`：`opaque: true` 的整屏滑入、背景 1/4 屏视差和 30% 遮罩是 **轻聊自己的参数**（`tg_motion.dart` 注释已声明）。边缘热区 24dp。没有系统 predictive 缩放，取消/完成阈值是 700 px/s 和 0.65，不是上游公式。

手感差一半来自「松手后播放一段假跟手」，一半来自「背后不是真列表」。

### 2.4 列表协调：ItemAnimator vs 每条自己 animate

TG `ChatListItemAnimator` 继承 `DefaultItemAnimator`，但：

- `alwaysCreateMoveAnimationIfPossible = true`
- 底部插入走 `runMessageEnterTransition()`，其它走 alpha
- 分组相册会改 `GroupedMessages` 几何而不是删了再建
- 每帧回调 `activity.onListItemAnimatorTick()` 让输入栏/浮钮跟着列表走

轻聊 `ListView.builder` + 消息自己的 `TweenAnimationBuilder`。新消息出现时邻居没有连续 reflow；多选 35dp 右移是行级 `AnimatedContainer`，不是 cell 内部 checkbox 层与气泡层分轨。

会话列表同理：TG `DialogsItemAnimator` 180ms 把一条会话 **移到顶部**；轻聊刷新后往往是重建顺序。未读数字 TG 有「从无到有 220ms Overshoot / 有→有 430ms 换数字」；轻聊 `TgUnreadBadge` 做了 AnimatedSwitcher，但会话行本身仍不是自绘 DialogCell。

### 2.5 性能策略：设备分级 vs 无档位

TG `SharedConfig`：

- `PERFORMANCE_CLASS_LOW / AVERAGE / HIGH`，按 CPU 核数、最大频率、`memoryClass` 估算
- `canBlurChat()`：Android 12 以下默认要 HIGH 才模糊，12+ AVERAGE 即可
- `LiteMode` 独立开关聊天模糊、自动播放、重特效
- 低端发送过渡会降级（research.md 已记）

轻聊玻璃头/输入栏用 `TgGlass`（sigma 12 的 blur）。没有性能档、没有 LiteMode、没有 120Hz 真机 FrameTiming。0.2.0 验证文档写得很清楚：**不能宣称 120Hz 无掉帧**。在中端机上实时 blur + 每条气泡重建，观感会先于「曲线不准」被用户感知。

图片路径也不对等。TG `ImageReceiver` 按显示尺寸解码、共享缓存、分层缩略图。轻聊上传已做 1600px/q82 去 EXIF，下载却是鉴权后整文件进 `Uint8List`，气泡写死 `width: 240`。大图、连刷、旋转都会卡主 isolate。

## 3. 已经对齐了什么，以及为什么仍「看起来不像」

0.1.1 / 0.2.0 **确实**做对了一批可核验细节：

- 标题 220ms ±20dp 交叉、省略点时间表
- 图片 Hero 200ms、缩放回弹 250ms Decelerate(1.5)、跟手拖关
- 回复引用、未读分隔、日期胶囊、到底部按钮
- camera↔send 220ms QuINT
- 多选 200ms / 35dp
- 按下 80ms、释放 350ms Overshoot(1.5)
- 消息默认贝塞尔常量与上游 `ChatListItemAnimator.DEFAULT_INTERPOLATOR` 一致

这些让「慢放录屏对参数」能过。对不上的是 **连续性**：

| 用户实际看见 | TG | 轻聊现在 |
|---|---|---|
| 点发送 | 输入框文字/圆角连续变成气泡，列表上挤 | 输入框清空，下方冒出一条新气泡 |
| 进聊天 | 背后列表还在、视差、标题/头像几何连续 | 整页盖上来，背景是路由算出来的幻影 |
| 气泡外形 | 路径随分组/选中变尾巴和圆角 | 近似三角形尾巴，时间戳不嵌入右下 |
| 长按 | 气泡抬起、周围压暗、反应条独立 overlay | 模糊+菜单级联，反应爆发未做 |
| 录音 | 按住变圆、波形、上滑锁、左滑取消 | **没有 mic**，空输入仍是相机 |
| 列表滚动 | 同一套 cell 回收，图片/贴纸可见才画 | widget 重建，入场动画可能重播 |
| 低端机 | 关模糊、简化过渡 | 所有人同一套 blur |

另外还有产品完整度：语音/视频/文件/组图、云端搜索、block/清空/举报都还没接。缺功能会被感知成「山寨」，和动画是两件事，但会叠在同一句「差太多」里。

## 4. 法律与工程约束（必须写死）

1. **不要 copy-paste Java。** GPL 会传染整个客户端；用户也明确禁止。本仓库只允许「读参数 → 独立 Dart 重写」。
2. **不要搬图标、壁纸、TGS、反应 Lottie。** 开源的是客户端程序，不是 Telegram 品牌包。
3. **不要做 Telegram 第三方套壳。** 轻聊是自有协议；官方 README 禁止用 Telegram 名和纸飞机误导。
4. Flutter **可以**逼近手感，但路径是 CustomPainter / Overlay / Sliver / 手势自己吃进度，而不是给 `AnimatedContainer` 填 TG 时长。官方 Impeller 只解决 shader 编译，不解决主 isolate 解码和过深 widget 树。
5. `client-demo` 证明「假数据下 overlay 飞入能做」。正式客户端要把这条接回 **真实 outbox + 稳定 key + 可变高度列表**，不能为动画牺牲消息可靠性。

## 5. 若要把观感差距收窄：建议顺序

不要按路线图从语音一次性铺开。手感债和功能债要分开还。

**A. 绘制与发送（观感收益最大）**

1. 把 `Bubble` 收成独立 `ChatMessage`：预先量文本/时间同行、固定媒体宽高、分组改路径；入场动画移到列表层，禁止每条 widget 自己 `begin:0`。
2. 实现轻聊版 `MessageEnterTransition`：发送瞬间在 Overlay 里插值 composer → 气泡 rect（文字先，语音/图片后）。demo 可参考，协议层仍先写 outbox。
3. 列表用协调过的 insert/move（邻居 translationY），不要整表 setState。

**B. 导航与手势**

4. `TgPageRoute` 改为非 opaque、背后真页视差；松手时长改剩余距离公式；补 Android predictive back 缩放（规格已标未做）。
5. 滑动回复从「整泡 clamp 0–70」改成阻尼 + 箭头层 + 阈值只震一次。

**C. 性能**

6. 设备三档 + 低端关 blur / 简化过渡。
7. 媒体：显示尺寸解码、磁盘缓存、缩略图；下载与气泡解码离开动画帧。
8. 真机 60/120Hz FrameTiming 再谈「顺」。

**D. 输入栏（和 0.2 媒体一起）**

9. 空输入 mic、按住录音几何（不要先做占位 mic）。
10. 附件菜单 / 相册组图走同一套 morph，避免图标突变。

**E. 明确不在这条路上做的**

- 为了「更像」去 fork DrKLO 或嵌官方 so。
- 把 `ChatActivity.java` 5 万行翻译成 Dart。
- 在没有真机帧数据时写「已对齐 TG 120Hz」。

## 6. 一句话

Telegram Android 开源，开的是一座 **自绘即时通讯引擎**（单气泡 2 万行、单聊天页 4.8 万行），外加十年性能分级和手势栈。轻聊一天内把协议、可靠性、以及一批 **动画常数** 做出来了，渲染仍停在 Flutter 默认组件。

所以不是「没读开源」或「曲线抄错」，是 **还没开始做 Telegram 真正在做的那一层：自己画消息、自己协调列表、手指驱动过渡**。常数已经够用；缺的是 MessageCell / EnterTransition / ImageReceiver / 设备档位这四件套的独立实现。
