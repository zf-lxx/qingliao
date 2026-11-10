# Telegram 手感研究：流畅来自整条链路

调研日期：2026-11-10（Asia/Shanghai）。仅研究与设计，不连接 Telegram 账号，不部署服务器，不推送仓库。

## 0. 结论与证据边界

- 建议自建中心化服务，Flutter 优先；这符合小圈子产品和现有经验，但普通聊天组件不会自动获得 Telegram 手感。
- Telegram 各端并非“一套自研渲染器”：Android 是原生 View/RecyclerView 加自绘消息单元；iOS 是 UIKit/CALayer、AsyncDisplayKit 加自定义列表；Desktop 基于 Qt；Web A/K 是 Web 技术。学习工程原则，而非迷信语言/私有协议。
- 即时本地回显、稳定列表、可中断手势、预解码/缓存、低端降级，比换接口框架更重要。
- 推送和前台 WebSocket 是不同系统。前台快不保证进程被杀后有通知；厂商推送必须进第一期。
- 对此前 Matrix 解释应纠偏：卡顿/延迟不能仅归因于协议，也不是每条消息都携带完整房间状态。客户端、同步、加密、部署、网络和推送都可能相关。中心化是缩小范围、提高可控性，并非证明所有 Matrix 实现必然慢。

方法：读取公开 README、少数明确源文件、官方格式文档与公开分析。未克隆 Telegram，未运行 Telegram benchmark，未逐帧录制真机。下列“源码实证”仅针对对应路径；其余参数均为本项目建议或待验证估计。master/dev 链接会变动，不是版本锁定。

## 1. 各端的工程路线

| 客户端 | 已核实事实与来源 | 可借鉴方向 / 边界 |
|---|---|---|
| Android | [DrKLO/Telegram](https://github.com/DrKLO/Telegram)，`org/telegram/ui/recyclerview/ChatListItemAnimator.java` 继承 DefaultItemAnimator，操作 RecyclerView、ChatMessageCell、TextMessageEnterTransition | 复用列表、自绘减少层级、协调几何变化、低端降级；不是所有页面绕开系统 |
| iOS | [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)，`Display/Source/ContainedViewLayoutTransition.swift` 有可控进度、presentation layer 接续、曲线/弹簧；[2020 源码分析](https://hubo.dev/2020-06-14-source-code-walkthrough-of-telegram-ios-part-5/)说明裁剪版 ASDK、异步布局、自定义 ListView | 离主线程做昂贵布局/图片处理、控制图层、大小屏统一容器；历史文章不是最新所有页面的实现声明 |
| Desktop | [tdesktop README](https://raw.githubusercontent.com/telegramdesktop/tdesktop/dev/README.md)列出 Qt 5/6、Opus、FFmpeg、WebRTC | 学习键盘导航、密集信息、媒体缓存、窗口布局；本次未深入其逐项动画实现，不引用固定时长 |
| Web A | [README](https://raw.githubusercontent.com/Ajaxy/telegram-tt/master/README.md)：Teact、Worker/WASM、多级缓存、乐观/渐进式界面、CSS/Canvas/SVG 动画、tlottie | 网络/解析与 UI 隔离；Teact 不是标准 React；网页帧率不能代表 App |
| Web K | [README](https://raw.githubusercontent.com/morethanwords/tweb/master/README.md)：Solid、tlottie、fflate、cryptography、opus-recorder 等 | 素材播放器、压缩、录音、媒体模块化；未验证完整 Worker 路径或每项曲线 |

授权注意：Android 文件标 GPL v2 或以后；Web K/A 项目声明 GPL v3，Desktop GPL v3 with OpenSSL exception。若复用代码须逐仓核实许可义务。独立实现交互更合适。贴纸、品牌和 logo 权利另算，开源客户端不意味着全部素材可任意商用。

## 2. 源码实证：不要把“TG 所有动画都是 300ms”当事实

### Android 消息进入

[ChatListItemAnimator.java](https://raw.githubusercontent.com/DrKLO/Telegram/master/TMessagesProj/src/main/java/org/telegram/ui/recyclerview/ChatListItemAnimator.java)：

- `DEFAULT_DURATION = 250`（毫秒）。`getMoveDuration()` 和 `getChangeDuration()` 返回它。
- `DEFAULT_INTERPOLATOR` 为 `(0.19919472913616398, 0.010644531250000006, 0.27920937042459737, 0.91025390625)` 的三次贝塞尔。
- 普通出现路径 scale 从 0.9 到 1；列表位移与气泡/图片几何变化协调。
- 特定 **greetingsSticker** 分支用 350ms + OvershootInterpolator，不能泛化为所有贴纸发送。
- 文字发送过渡有设备性能等级与位移范围判断；低端可降级。
- [TextMessageEnterTransition.java](https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/java/org/telegram/ui/TextMessageEnterTransition.java)检索片段显示线性总进度 + DEFAULT_DURATION。不同几何属性仍可重新映射进度，不等于一个 CSS ease 完整复现。

### Android 页面与返回

[ActionBarLayout.java](https://raw.githubusercontent.com/DrKLO/Telegram/master/TMessagesProj/src/main/java/org/telegram/ui/ActionBar/ActionBarLayout.java)：

- `startLayoutAnimation()` 的默认非 preview 分支 150ms；preview 且 open 为 190ms。普通打开用 DecelerateInterpolator(1.5f)，包含 48dp 位移。Fragment 可以覆盖过渡，不能推广为所有聊天路由。
- 老式 swipe-back 条件有宽度 1/3、3500px/s；predictive back 是另一条路径。
- `animateBackEndAnimation()` 按剩余距离计算时长；旧路径完成最短 50ms、取消最短 120ms；predictive 路径另有 380/320ms 下限和 EASE_OUT_QUINT。
- 最值得复刻的是：拖动阶段进度由手指控制，松手后才是时间曲线。不是 touchend 后放一段假跟手动画。

### iOS 通用过渡

[ContainedViewLayoutTransition.swift](https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/master/submodules/Display/Source/ContainedViewLayoutTransition.swift)：

- `slide = custom(0.33, 0.52, 0.25, 0.99)`。
- customSpring 默认 mass 5、stiffness 900，damping/initialVelocity 由调用处提供。不存在所有交互通用的阻尼常量。
- 支持从 `layer.presentation()` 接续当前视觉状态；不要中断后从旧起点重播。
- 同一 frame 检查和 spring solver cache 表明：避免无意义重启动与逐帧构造也很关键。

## 3. 交互目录

以下为观察和产品实现建议，不声称各端细节完全相同。项目拟定时长见 design.md。

| 交互 | 体验要点 | 实现/风险 |
|---|---|---|
| 列表→会话 | 立即反馈、标题/头像连续、内容不等网络 | 本地缓存先显示，过渡时不解码；桌面保留左栏，手机单路由 |
| 滑动返回 | 跟手、可撤销、按速度收尾 | 边缘返回与气泡回复仲裁；Android predictive back；中断从当前姿态接续 |
| 发送气泡 | 输入区文字飞入气泡，背景变形连续 | 乐观 outbox；overlay/FLIP；动画结束只保留一个气泡；连续发送、键盘换行必须稳定 |
| 滑动回复 | 阻尼位移、箭头浮现、越阈轻反馈、松手复位 | 横纵锁向，阈值只触发一次，不与链接/附件点击冲突 |
| 长按菜单/反应条 | 气泡抬升、其余内容弱化、菜单避让 | overlay 坐标、焦点与无障碍；低端暗遮罩代替全屏实时模糊 |
| reactions burst | 点下就反馈、短暂粒子、计数更新 | 独立绘制层、限并发；失败回滚状态而不重建整个列表 |
| 回到底部 | 离底才出现、附未读数、不打断读历史 | 锚点保持；远距离先定位分页而非长时间逐条滚动 |
| typing | 小点循环、名字、短时失效 | 临时 TTL、限频、后台停止、不持久化为消息；检查成员权限 |
| 录音 | 按住录、左滑取消、上滑锁、锁定后显式发送 | 权限拒绝、来电/后台打断；取消内容不上传；不是靠录音波形判断安全 |
| 贴纸面板 | 与键盘高度连续、最近使用预取、滚动不卡 | 可见才播、首帧占位、限制解码并发与缓存总字节数 |
| 自定义 emoji | 基线稳定、文字选择正常、不满屏播放器 | 行内富文本、共享时钟、可见性；复制降级字符；逐项兼容测试 |
| 媒体查看 | pinch 缩放、缩放后拖动、未缩放时滑动关闭 | 缩放态禁页面返回，区分 pinch/dismiss，缩略图到原图无尺寸跳变 |
| 主题/壁纸 | 暗亮对比、气泡可读、动态适度 | 壁纸缓存、离屏暂停、减少动态效果；不为炫技牺牲可读性 |

## 4. 贴纸格式及授权

[官方规范](https://core.telegram.org/stickers)：

- TGS 是 gzip 压缩、基于 Lottie 的动画 JSON。动画贴纸要求 512×512、最长 3 秒、循环、60fps、渲染后不超过 64KB；限制部分 After Effects 特性。介绍中的“常见小于 30KB”不是硬上限。
- 视频贴纸是 WebM/VP9、无音轨、最长 3 秒、最高 30fps、不超过 256KB。贴纸一边恰好 512px、另一边不超过 512；视频 emoji 100×100。
- 自定义 emoji 复用静态/动画/视频技术，不是另一套神秘格式。
- 免费发送某贴纸 ≠ 允许下载后内置再分发。LottieFiles 也须逐资产记录作者和许可证。
- 演示宜用自行绘制的几何/笑脸 Lottie，或明确许可的开源素材；记录作者、许可版本、源 URL、sha256。不擅用热门 Telegram pack。

## 5. Flutter 能力与风险

- [lottie](https://pub.dev/packages/lottie)：纯 Dart，支持移动/桌面/Web；TGS 用 `LottieComposition.decodeGZip`；renderCache 用内存换重复绘制成本，禁止全部资源高分辨率逐帧缓存。
- [rive](https://pub.dev/packages/rive)：适合原创交互状态机（录音锁、空态），不负责 TGS 解码；native runtime/不同 renderer 需真机验证。普通贴纸首选 Lottie，不强行转 Rive。
- AnimationController、Tween/Curve、SpringSimulation、Overlay、GestureDetector/RawGestureDetector、CustomPainter、SliverList、RepaintBoundary 足以覆盖初期。
- RenderObject 只在 profile 证实富文本/气泡布局热点后再做。过早自绘会增加选择复制、无障碍、RTL、语义树成本。
- [Impeller 官方文档](https://docs.flutter.dev/perf/impeller)：减少运行时 shader 编译问题，但不能解决主 isolate 阻塞、过度 build、超大纹理、实时模糊。Flutter Web 当前仍是 Skia，不能拿网页 demo 声称测了移动端 Impeller。

实现原则：
1. 本地数据库先显示；历史分页、保持可变高度列表阅读锚点。
2. typing、已读、发送进度各自局部更新；稳定 key，client_id 被服务端 ID 确认后不删除重加。
3. 图片先有宽高与缩略图，按展示尺寸解码；网络/压缩/解析离开关键帧。
4. 只播可见贴纸；离屏暂停；粒子/解码/缓存均有预算。
5. 过渡可中断，拖动仅变换，松手才提交状态。
6. 低端与减少动态效果模式：模糊降遮罩、动态壁纸降静态；不降低消息可靠性。
7. 60Hz 的刷新周期约 16.7ms，120Hz 约 8.3ms；这是换算，不是实测。profile/release 真机记录 UI/raster p95/p99、掉帧、内存/耗电，网页截图不证明流畅。

## 6. 国内 Android 推送

| 路线 | 适用 | 限制 |
|---|---|---|
| FCM | GMS 可用且网络可达设备 | [官方客户端条件](https://firebase.google.com/docs/cloud-messaging/android/client)要求 Google 环境；不能假设所有国内设备都具备，也不能声称国内绝对不能用 |
| 华为/荣耀、小米、OPPO、vivo 等厂商 | 借系统通道，在 App 不运行时显示通知 | 主体资质、包签名、上架、分类/模板、隐私合规需逐厂商核实；个人开发者申请资格可能是硬门槛 |
| 个推/极光/阿里聚合 | 统一服务端接口，减少 SDK 适配 | 不能绕过厂商配额；收费与免费离线能力要看当前合同；处理 SDK 隐私声明和初始化时机 |
| UnifiedPush 开放协议 | 无 GMS 或注重隐私，可配 ntfy 等 distributor | 需要额外分发器，其连接仍受电池策略限制；不是厂商特权，不保证强杀秒到 |
| 前台服务+WS | 主动开启的可见常驻，内测补充 | 常驻通知/耗电/Android 类型及后台启动限制；不是“永不丢消息”的替代品 |

名称陷阱：[unifiedpush.org](https://unifiedpush.org/users/distributors/)是开放协议/分发器；另有同名 `taoweiji/UnifiedPush` 厂商 SDK 聚合项目，不要混淆。

2026 变更：[阿里官方汇总](https://help.aliyun.com/zh/document_detail/3010774.html)包含小米私信模板接入期限 **2026-12-31（Asia/Shanghai，公告本地日期）**、OPPO 私信模板、vivo 本地通知分类。vivo 五类系统消息模板要求明确不包括即时消息，不能概括为所有聊天都要模板。[个推限额](https://docs.getui.com/getui/mobile/vendor/qps/)与[极光限额](https://docs.jiguang.cn/jpush/client/Android/android_3rd_qps)接入时复核。

Android 13+ 需要通知授权；[Android 12+ FGS 后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)意味着不能任意后台拉起。厂商成功回执≠设备已显示≠人已读；任何路线都不承诺 100%。

iOS 需 APNs、签名和开发者账号。Web 关闭页面后需 Service Worker/Web Push，授权和平台能力另算；WebSocket 无法在浏览器关闭后继续工作。

### 待实测矩阵

- 设备：本人主力机+至少另一品牌；面向多品牌则分别覆盖。
- 状态：前台/后台/锁屏/省电/系统回收/用户强行停止/重启/通知拒绝/网络切换。
- 埋点：入库→push job→渠道接收→设备显示（如可采）→点击→客户端补齐。
- 即使没收到推送，打开 App 必须补齐；重复推送不得产生重复消息和重复本地通知。
- 静音、免打扰、多端阅读后的通知清理均有确定规则。

## 7. 先验证什么

先验证真机列表/气泡/手势，再做双设备真实消息与断网补齐，再接厂商通知并锁屏测试。不要先搭复杂分布式，也不要把通话、E2EE、大频道塞首版。

本报告没有并发容量、端到端延迟、设备帧率、推送送达率的实测数字。HK 约 190MB 可用内存是既有会话信息，非本次服务器检查。


## 决策更新（同日）
用户后续确定：HK 单机、Go net/http+coder/websocket+modernc SQLite WAL，邀请码、小米优先、v1无E2EE。此前 FastAPI/PG/新加坡是研究建议，已被 design.md 新方案替代。20–40MiB RSS 是待验证目标，不是 Go 或 VoceChat 的已测保证。
