# 轻聊 Telegram Android 风格规范（0.2 重设计验收表）

用户决定：整体沿用 Telegram Android 的视觉和交互语言；轻聊是独立协议客户端，不冒充 Telegram。用户许可策略：**禁止复制 Telegram 源码或素材（图标、壁纸、动画文件等）到本仓库**。只能阅读 DrKLO/Telegram 提取尺寸、颜色、曲线、时长和交互行为，再自行用 Flutter 重写。当前没有复制 GPL 实现，也没有打包 Telegram 素材；下一版同样遵守。

## 参考与已核对参数
- 用户聊天列表参考：`../design-refs/tg-chatlist.png`；另有 0.1.0 连接提示对照图。
- 聊天页、未读条参考原图当前未保留，以下以用户逐项描述为准，不声称逐像素复刻。
- 本次读取上游 [ActionBar.java](https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/java/org/telegram/ui/ActionBar/ActionBar.java)（2026-11-11，中国标准时间 UTC+8）：
  - `setupGlass`：圆角 23dp，padding 6dp；`dispatchDraw`：按钮主体 46dp。
  - `getCurrentActionBarHeight`：手机竖屏 56dp、横屏 48dp（平板另行适配）。
  - `setTitleOverlayText`：新标题从 -20dp 下移到 0、旧标题向 +20dp 移出，同时 alpha 交叉；时长 220ms；`EllipsizeSpanAnimator` 动态省略点。
  - glass 模式标题 17sp；非 glass 标题和副标题有横竖屏/平板分支，不能把聊天列表的大标题也统一成 17sp。
- 下轮继续逐文件核对：`DialogsActivity.java`、`Cells/DialogCell.java`、`ChatActivity.java`、`Cells/ChatMessageCell.java`、`Components/ChatActivityEnterView.java`、`PhotoViewer.java`、`ActionBar/Theme.java`。**未核实数值不得标为“TG 原值”**。
- 主题色采用 semantic token，浅/深主题各一套；以截图和 `Theme` 当前主题对应值校准，不全局硬编码单一蓝色。
- 文字气泡外形（2026-11-11 只读 `MessageDrawable.generatePath`）：`SharedConfig.bubbleRadius=17`；近邻/尾巴小圆 `min(6, bubbleRadius)`；padding 2dp；非媒体尾巴从 `right-2.6` 起，侧边内收 8dp，尾巴为 **83° arc**（发出 -83，收到 +83），不是三角形。分组时该侧底角用 6dp、无尾巴。

## 聊天列表
- [x] 标题左对齐，连接状态在标题位置替换，动态省略点；没有横幅/额外行（0.1.1）。
- [ ] 大号粗体标题、搜索框圆角及滚动收起行为与参考图一致。
- [ ] 胶囊文件夹 tabs，选中态与独立计数徽标；横向滚动、滑动切换。
- [ ] 可关闭建议卡片、归档入口行；关闭状态持久化。
- [ ] 58dp 头像（截图需求值；待 DialogCell 源码校准），名称/时间/置顶/静音/双勾/未读数对齐。
- [ ] 明确区分已读双勾、送达、待发时钟、失败；@ 标记独立于普通未读数。
- [ ] 草稿优先预览、媒体摘要、输入状态；长按与侧滑归档/静音/标记未读。
- [x] 全宽底栏：聊天 / 联系人 / 设置 / 个人资料 + 文字标签；聊天 badge（产品四栏，不是 TG 三栏）。会话行 70dp、联系人 58dp、设置单元格 50dp（DialogCell/UserCell/TextSettingsCell 只读参数）。
- [ ] Compose FAB + camera mini-FAB；滚动显隐但不覆盖最后一行。

## 聊天页
- [ ] 浮动圆角 header pill：返回、头像、名称、副标题；独立圆形菜单按钮。
- [ ] 副标题输入态：`••• 正在输入…`，三点按 TG 节奏运动；连接态仍在副标题内替换。
- [ ] 低对比图案壁纸，安全区/键盘/状态栏不露接缝；不捆绑大字体资源。
- [ ] 气泡尾巴、同发送者连续分组、间距、头像、深浅主题颜色与 TG 匹配。
- [ ] 时间 + 状态勾嵌入气泡右下角；短文本同行、长文本避让，不能遮挡正文。
- [x] 居中浮动日期胶囊，按中国标准时间 UTC+8 分天（0.1.1）。
- [x] 回复：彩色左边线、发送者第一行、文本/媒体摘要第二行；图片有缩略图；点击跳转高亮，原消息缺失时分页补取（0.1.1）。
- [x] 图片共享元素展开/收回、黑底淡入、双指/双击缩放、上下拖动关闭、点击显隐工具栏（0.1.1）。
- [x] 首条未读之前的全宽“未读消息”条；进入定位未读；当前会话保留（0.1.1）。
- [x] 上翻时显示圆形到底部按钮和未读数；未读 @ 跳转（0.1.1）。
- [ ] 浮动输入栏：emoji、附件、camera/send 形变；录音按住/锁定/取消，键盘过渡。

## 动画/验证
- [x] 标题：220ms、垂直 20dp + alpha；非连接超过 1s 才出现，防止抖动（0.1.1）。
- [x] 图片：200ms 共享元素过渡（按 PhotoViewer 主分支），缩放/回弹250ms；拖动时跟手、按距离降低背景 alpha；缩放态不误触关闭（0.1.1）。
- [ ] 0.2 对照手机录屏量测手势阈值、回弹曲线、发送/键盘/输入状态节奏；同时测 60/120Hz。
- [ ] 至少 Xiaomi 真机：首次登录、弱网、Wi-Fi/蜂窝切换、前后台、长聊天、媒体多图、回复远历史。
- [ ] 文本放大/减少动画/无障碍；截图库覆盖浅色深色和窄屏；每次发布跟踪 APK 体积（目标 ≤约 50MB）。

注意：0.1.1 先解决连接恢复和明确交互缺陷，不表示全界面已达到 TG 的视觉完成度。原生相册保存/系统分享仍需 Xiaomi 真机验收。

## 动画参数表（优先级最高）

以下来自本次实际读取的 DrKLO/Telegram `master`（2026-11-11，UTC+8）；上游会变化，下一轮实施时应锁定 commit 再量测。表内“待核”不能当作已实现/已验证。**源码仅在仓库外临时目录只读分析，绝不进入本仓库。**

曲线字典（`Components/CubicBezierInterpolator.java`）：
- DEFAULT = cubic(.25,.1,.25,1)；EASE_OUT = cubic(0,0,.58,1)；EASE_IN = cubic(.42,0,1,1)。
- EASE_OUT_QUINT = cubic(.23,1,.32,1)；Android 默认 AccelerateDecelerate 为余弦缓入缓出。
- Android Decelerate(factor) = 1 − (1−t)^(2×factor)，不是随便选择一个 cubic 的名字替代。
- 消息默认 = cubic(.19919472913616398,.010644531250000006,.27920937042459737,.91025390625)，`recyclerview/ChatListItemAnimator.java:47–48`。

| 动画 | 已核对时长/曲线 | 运动属性、源文件/类 | 轻聊进度 |
|---|---|---|---|
| 连接标题替换 | 220ms；无显式覆盖的 ViewPropertyAnimator 默认 AccelerateDecelerate | `ActionBar/ActionBar.setTitleOverlayText`：新标题 -20dp→0，旧标题 0→+20dp，alpha 同步交叉 | 0.1.1 自行重写；1s 去抖是轻聊策略，不冒称 TG 源值 |
| 标题省略点 | 第一/二/三点分别延迟 0/150/300ms 淡入，各 300ms；1000ms 时统一淡出 400ms，停 300ms 再循环；DEFAULT | `Components/EllipsizeSpanAnimator`，每点 alpha 0↔255 | 0.1.1 使用该时间表，不再阶梯闪点 |
| 图片从气泡展开/回收 | openPhoto/closePhoto 主分支 200ms，AnimatorSet **未设 interpolator**（即 AccelerateDecelerate）；zoom/animateTo 250ms、Decelerate(1.5) | `PhotoViewer.java:17808–30`：clipping/rect/scale/translation + 背景和容器 alpha。Flutter Hero 默认 `fastOutSlowIn` 会叠到 RectTween 上，必须把 Hero.curve 设成 linear，只留 ImageRectTween 的 AccelerateDecelerate | `feat/native-render-layer`：Hero.curve=linear + ImageRectTween 200ms AccelerateDecelerate；缩放/回弹仍 250ms Decelerate(1.5) |
| 图片拖动退出 | 跟手阶段不应缓动；结束后使用 closePhoto/animateTo 分支；阈值须按当前设备/source 分支复核 | `PhotoViewer`：translationY、背景 alpha、回到来源位置 | 0.1.1 已跟手及透明度、返回 Hero；阈值是轻聊值（100dp/850dp·s⁻¹），不声称与 TG 全同 |
| 打开/关闭聊天 | 当前 `ActionBarLayout` 常规动画有 200ms 分支，预测返回也有 380ms/EASE_OUT_QUINT 分支；不能混成固定 250ms | `ActionBarLayout`：前景 X、innerTranslationX、背景 parallax/阴影；需要进一步定位实际手机常规路径 | 0.2 重做；0.1.0 旧 Flutter route 并非完整 TG 动画 |
| 边缘滑回及取消 | 经典分支见 `ActionBarLayout.java:1546–1600`。predictive `drawChild` 缩放 `1 - min(0.25, 0.05 * translationX / 56dp)`，完成/取消下限 380/320ms、EASE_OUT_QUINT。`1226–1231,1721–1740` | `TgPageRoute`：经典起步/完成条件 + predictive 缩放与 380/320 下限 |
| 自己发送气泡 | animator **LinearInterpolator** 250ms。onDraw：`progress`=消息贝塞尔（Y/背景高度），`p2`=EASE_OUT_QUINT 再 `progressX`=EASE_OUT（X），`alphaProgress = p>0.4 ? 1 : p/0.4`。`TextMessageEnterTransition.java:389–390,471–475` | Overlay 按三套进度映射，并从输入框 16sp 缩到气泡 15sp（scaleFrom）。未做 bitmap crossfade / emoji-only 字号表 |
| 新收到消息插入 | 默认 250ms，ChatListItemAnimator 默认消息曲线；特殊 greeting/sticker 350ms/Overshoot | `recyclerview/ChatListItemAnimator` add/move：translationY/邻居 reflow，部分 X、alpha 分支 | 0.1.1 保留旧 250ms 进入；0.2 补邻居连续 reflow |
| 会话移到列表顶部 | `DialogsItemAnimator` move/change 180ms；Decelerate 默认（文件 sDefaultInterpolator） | `Components/DialogsItemAnimator`，行 translationX/Y，删/增 alpha、clip | 0.2；不通过重建整个列表假装动画 |
| 未读徽标数字变化 | `DialogCell`：从无到有 220ms/Overshoot；归零 150ms/DEFAULT；有→有 430ms/DEFAULT | `Cells/DialogCell` countAnimator：背景宽度、scale、数字上下替换/alpha、稳定字位不移动 | 0.2；不能全部套用 NumberTextView 150ms |
| 选择计数等通用数字 | `NumberTextView` addNumber 分支 180ms，否则 150ms；未覆盖插值器即 Android 默认 | `Components/NumberTextView`：按位 progress -1或1→0，字位上下位移和 alpha | 0.2 |
| 正在输入三点 | 三点初始延迟 0/150/300ms；每点放大 320ms + 缩小 320ms，到 800ms 重新开始；Decelerate 默认 | `Components/TypingDotsDrawable`：圆点 radius 1.33→2.33→1.33dp；中心间距 6dp，不是普通省略号闪烁 | 0.2；连接省略点和 typing dots 不混用 |
| 滑动回复 + 震动 | **左滑**（负 X）。上限 `dp(-80)`；开始跟踪：`dx <= -0.4cm` 且 `|dx|/3 > dy`（列表须 SCROLL_STATE_IDLE）。触发回复/震动 `dp(50)`，越过后再回到 50dp 内会重置震动旗标。松手回弹 180ms、`AndroidUtilities.decelerateInterpolator`（Decelerate factor 1）。箭头在 `dx <= -20dp` 出现，圆环进度 `(-x-20)/30`。发出消息箭头 X 乘 0.5。`ChatActivity.java:5067–5137,5270–5297`（2026-11-11 只读） | `feat/native-render-layer` 的 `SwipeReply` 按上述参数独立重写；禁止再使用右滑 48dp 轻聊值 |
| 长按上下文/反应条 | 通用 `ActionBarPopupWindow` 展开 = 150+16×可见项数 ms，child 项级 180ms/Decelerate；dismiss 默认 150ms。聊天 reaction 专用弹层需额外核对 | `ActionBar/ActionBarPopupWindow`：backScaleY、backAlpha、item -6dp→0/alpha 级联；reaction bar 另有缩放弹出 | 0.2；不能把此菜单参数当成所有反应条的唯一参数 |
| 反应爆发 | `ReactionsEffectOverlay`：ONLY_MOVE 350ms、其他退出 220ms；avatar particle progress 350ms；主体长度随实际动画资源时长 | `Components/Reactions/ReactionsEffectOverlay`：位置/scale/alpha，粒子独立；禁止复制 TG Lottie/TGS，需原创/许可素材 | 0.2；资源相关部分不得写成固定总时长 |
| 到底部/@浮钮显隐 | 280ms，AnimatorUtils.DECELERATE_INTERPOLATOR（其库 factor 尚待核，不能虚构 cubic）；附件按钮另 300ms/EASE_OUT_QUINT | `Components/chat/layouts/ChatActivitySideControlsButtonsLayout`：alpha 0→1、scale .7→1、Y 80dp→0；计数显示同280ms | 0.1.1 有按钮和定位功能，显隐还不是完整 TG 补间；0.2 对齐 |
| 文件夹 tab 指示器 | 320ms，EASE_OUT_QUINT；重排使用 getMoveDuration，不等同于指示器时长 | `Components/FilterTabsView`：indicator rect X/宽度/文字颜色和邻居状态 | 0.2 |
| mic/camera↔send | `ChatActivityEnterView` runningAnimation 的当前两主分支均 220ms/EASE_OUT_QUINT；周边建议按钮 320ms 独立分支 | `Components/ChatActivityEnterView.java:8137–38,8359–60`：scale/alpha/位置的分层替换，空输入 mic、有文字 send（媒体模式 camera） | 0.2；不要误用录音取消200ms分支 |
| 键盘/emoji 面板 | 250ms；`AdjustPanLayoutHelper.keyboardInterpolator = ChatListItemAnimator.DEFAULT_INTERPOLATOR`；能拿到平台 IME animation 时优先跟平台 | `ActionBar/AdjustPanLayoutHelper`、`ChatActivityEnterView.panelAnimation`：pan/translationY、面板高度/输入栏/列表联动 | 0.2；不每帧执行大规模布局或 decode 图片 |
| 滚动浮动日期标签 | show/hide 各 150ms，未显式覆盖插值器；hide 另受 hideDateDelay 控制 | `ChatActivity.java:14165–208`：floatingDateView alpha；位置随 chatListView translationY，不硬编码延迟 | 0.1.1 只有分天列表日期胶囊；0.2 加滚动浮层 |
| 多选模式行位移 | 200ms；进入 EASE_OUT、退出 EASE_IN | `Cells/ChatMessageCell.java:18007–32,23518–20,17857–58`：checkBoxTranslation 0↔35dp。仅 `!isOutOwner() \|\| hasWideCode` 的行 `updateTranslation`；勾选 21dp，bounds `dp(8-35)+translation`、底边 `bottom-8`。选中换气泡 selected drawable，不是整行半透明罩 | `feat/native-render-layer`：对方气泡右移 35dp、自己的不动；勾选 21dp 钉在行左下；气泡用 outgoingSelected/incomingSelected |
| 多选顶栏/底栏 | ActionBar show/hideActionMode 200ms，alpha/translation，默认 Android 插值器；具体 floating pill morph 是 screenshot 需求，需测独立布局分支 | `ActionBar/ActionBar.showActionMode/hideActionMode` + `ChatActivity`，选择数量按 NumberTextView；底部输入栏→回复/转发按钮 | 0.2 |

### 120Hz 性能验收（不能以桌面截图代替）
- 使用 Flutter Android release/profile + Impeller，确认设备实际 renderer（不能只因为 Flutter 默认支持就写“已验证”）。
- Xiaomi 120Hz 下 UI 和 raster 各自的帧预算 **8.33ms**；60Hz **16.67ms**。记录 FrameTiming 的 p50/p95/p99、超预算帧比例、最差帧、shader/图片首次解码耗时。
- 用 `SchedulerBinding.addTimingsCallback` 收集，DevTools Timeline/Perfetto 排查；场景：进入退出聊天×20、快速侧滑、连续收发100条、图片区查看缩放关闭×20、切tab、键盘emoji切换×20、选择20条消息。
- AnimatedBuilder 限制重建范围；图片提前解码、缩略图 cacheWidth；Hero 独立 repaint；手势阶段只改 transform/opacity；不要同步 IO 或巨大 snapshot JSON 放在动画关键帧。
- **0.1.1 未在 Android/Xiaomi/120Hz 硬件测帧，不能报告“120Hz 无掉帧”。** Widget tests 只证明状态/手势/时序，不证明帧率。

## 0.2 多选模式
- 参考本机用户截图：`../design-refs/tg-select-mode.png`。
- [ ] 长按菜单→选择；选择模式下点击任意行切换，勾选圈竖向拖动连续选择。
- [ ] header pill morph：✕ / 已选择 N 项；数量按位动画。
- [ ] 独立操作 pill：编辑（仅选1条本人消息）、复制、转发、删除；权限/撤回时限由服务端决定。
- [ ] 左侧圆形勾选框滑入；选中绿色实心勾；整行半透明高亮；气泡位移与框位移分层。
- [ ] 输入栏 morph 为“回复”（只选1条）/“转发”两个 pill；退出选中后还原草稿和焦点。
- [ ] 200ms cell selection + 200ms action mode 基线见上表；浮动 pill 的路径在实际0.2实现前再核对，不把老 ActionBar 淡出伪装成精确玻璃形变。

## 0.2 聊天右上角菜单
- 参考本机用户截图：`../design-refs/tg-chat-menu.png`。
- [ ] 右上角锚定圆角暗色卡片；从角点 scale/fade/分项级联；参数采用 ActionBarPopupWindow 分支，不写死所有菜单220ms。
- [ ] “静音 ›”子页：1小时/8小时/2天/永久/自定义；可返回。`PopupSwipeBackLayout.DURATION=300ms`，实际时长 = 300×max(.5,距离−min(.2,fling))，DEFAULT；高度适配240ms/easeInOutQuad。
- [ ] 较厚间隔后“搜索”，转入聊天内搜索框，上/下结果导航。
- [ ] “清空历史记录”确认框及双方选项；红色“举报”；红色“删除并屏蔽”。按私聊/群聊/bot及管理员权限动态显示，不展示无权限操作。
- [ ] 输入栏空时 mic、有文本时 send；媒体录制模式 camera；保留连续 morph 而非突变图标。

### 后端对接核验（以当前仓库路由为准）
- 已有静音：`PATCH /v1/conversations/{id}/state`，`mute_until` 为 RFC3339 到期时间 / `forever` / 空串取消。1h/8h/2d/custom 由客户端换算，界面展示中国标准时间 UTC+8。
- 已有单消息编辑/撤回：`PATCH/DELETE /v1/messages/{id}`；群管理 `POST /v1/conversations/{id}/moderation` 有 ban/unban 等操作，**群封禁不是私聊拉黑**。
- 当前 `server/internal/chat` 没有查到 search/FTS 路由或实现；0.4原计划仍须补后端，不能说已有 FTS 可直接接。
- 缺口：私聊 block、会话清空历史（自己/双方语义）、举报接口、批量消息删除/转发授权语义。先定义 API/权限/审计/幂等，再接菜单；不得用群 ban 假装私聊“删除并屏蔽”。

### 点击、返回和弹层：0.2 统一 motion kit

计划建立 `client/lib/ui/motion/`，从当前小型 `widgets/tg_motion.dart` 迁移为所有页面共用的 `tg_curves.dart` / `tg_durations.dart` / `PressableScale` / `TgRoute` / `TgPopup` / `TgSheet`。不得每页各选一个“差不多”的动画。

| 微交互 | 本次实际核对结果 | 实现要求 |
|---|---|---|
| 按下缩放 / 松手弹回 | `Components/ScaleStateListAnimator` 默认 scale=1−.1=.9；按下80ms（Android默认），松手350ms/Overshoot(1.5)。允许调用方覆盖 scale/tension，不是所有控件都缩到.9 | `PressableScale` 支持参数、cancel/移出恢复、禁用态、触觉与无障碍；列表整行不要过度缩放 |
| 更短按钮 bounce | `Components/ButtonBounce` 默认倍率1、overshoot=5；按下60ms/DEFAULT，释放350ms/Overshoot(5)，另有 bounce320ms/Overshoot 分支 | 按控件实际调用参数选择；不能把所有 release 都设相同回弹 |
| 涟漪 feedback | Android RippleDrawable/Theme selector 路径由系统和主题控制；**无统一固定颜色alpha/持续ms**。需继续读取所选主题 Theme.key_listSelector 及对应 selector/ripple 路径；暂不写伪造的“TG固定100ms/.12” | 浅深主题分开测；Flutter重新实现 ripple/mask，不复制drawable。记录选中主题/SDK后再核色和淡入淡出 |
| 页面返回的位移/视差/遮罩 | 当前 `ActionBarLayout` 有普通48dp slide分支、整屏跟手分支、Android12+ predictive56dp/scale分支。scrim 在所查分支为 alpha=120×clamp(widthOffset/width,0,.8)，最大96/255，而不是拍脑袋50%黑 | `TgRoute` 按当前实际手机分支复核打开与关闭；背景列表独立 parallax；不能把多个分支混拼成“精确TG” |
| 交互返回 | 手指位移直接驱动（不先缓动）；松手使用上述按剩余距离计算时长，predictive finish/cancel另有下限；当前源码还对位移作5×56dp/width变换 | `TgRoute` 要处理左边缘、速度、取消/完成、系统predictive返回、键盘/弹层优先级。精确 velocity 阈值与普通背景 parallax 系数仍待锁定实际分支量测 |
| 弹出菜单 | `ActionBarPopupWindow` 背景scaleY/alpha与项级-6dp位移；窗口150+16×可见项ms，关闭默认150ms。角点/pivot取锚点方向；子菜单300ms基线/DEFAULT | `TgPopup` 统一锚点、圆角mask、外部点击关闭和返回，不能用整页中央scale替代 |
| AlertDialog show/dismiss | `ActionBar/AlertDialog.show` 当前有自身控件scale到1的190ms/Overshoot(1.3)分支；特定样式 `DialogNoAnimation` 禁用系统窗口动画，其余由Dialog窗口主题处理；该190ms不能误称所有确认弹窗时长 | `TgDialog` 实施前区分style/progress/dialog路径，补查theme/window动画XML的实际进入退出值；目前未核实的dismiss值保持待核 |
| 底部sheet | `ActionBar/BottomSheet` 默认 openDuration400ms/EASE_OUT_QUINT，startDelay20ms（等待键盘时0）；普通dismiss250ms/EASE_OUT；右侧进入250ms，右侧dismiss200ms/DEFAULT分支；拖拽回弹250×Y/0.8cm ms/DEFAULT | `TgSheet` 跟手+遮罩+键盘联动；不是所有sheet都弹簧。若目标样式使用spring，逐个查具体sheet；不要未经核实加overshoot |
| 上下文模糊/遮罩 | `ChatActivity` 的 scrim、reaction menu 和常规菜单不同路径；Profile scrim enable150ms/disable220ms也不是通用聊天参数 | `TgPopup` 支持dim/blur分层与可关闭开关；0.2必须按聊天长按录屏对齐，当前不承诺模糊半径值 |
| 勾选框与开关 | `CheckBox2`委托 `CheckBoxBase`，默认animationDuration200ms/EASE_OUT，进度0↔1控制填充/勾线；选择行平移另200ms，不能混成一个动画。Switch自身路径仍待核 | checkbox、switch采用独立曲线/状态层；绿色已选填充、描边、勾线节奏都要测；不只换一个Material勾图标 |
| tab/文件夹切换 | FilterTabsView指示器320ms/EASE_OUT_QUINT；页面拖动进度跟手；颜色/宽度、标题位置同步 | `TgTabs`支持滑动打断、回弹、重排；不靠setState突然跳一个selected chip |
| FAB显隐 | 聊天side controls 280ms/AnimatorUtils.DECELERATE，scale .7↔1、alpha、Y80dp；资料页writeButton150ms，显/隐分别Decelerate/Accelerate；不同FAB不共享一个错误常数 | 随滚动隐藏应可打断，从当前值反向开始；把控件用途放入motion token |
| 头像/资料展开 | `ProfileActivity` `playProfileAnimation==2`为250ms/DEFAULT，否则180ms/Decelerate；下拉头像expand按剩余进度×250ms/速度倍率，分支为FastOutSlowIn或EASE_BOTH | `TgProfileRoute`共享头像/标题位置、header高度、圆角和遮罩；别只把头像放大。当前只是参数表，0.1.1未改资料页 |
| 键盘对齐面板 | `ActionBar/AdjustPanLayoutHelper` 250ms/消息默认贝塞尔；BottomSheet keyboardContentAnimator复用同组参数 | 统一 `TgKeyboardMotion`；取平台IME inset进度，键盘/emoji互换、输入栏/列表高度和浮钮位置同步，避免双重平移 |

统一手势验收：tap-down有反馈，滑出或手势取消必须恢复；返回/弹层/图片拖拽全部可被反向打断；减少动画时去位移/回弹而保留反馈和状态；120Hz真机录帧后才给“顺滑”的结论。

## 0.2 新增范围与阶段状态（以 0.2-status.md / VERIFICATION-0.2.0.md 为准）

0.2.0 是首个可安装的重设计阶段包，不等于以下清单全部完成。禁止把预留入口、缓存统计或本机过滤说成服务端完整能力。

### 共用块状设计系统
- `lib/ui/theme/tg_tokens.dart`：background/card/raised 三个表面层级，主色蓝；卡片20dp、小圆角11dp、块间距12dp、页面16dp。胶囊全圆角，浮层模糊sigma12、表面alpha .86。
- 这些是轻聊本版统一token，并非声称TG所有页面的精确尺寸。现有登录/设置/资料/弹层继承统一Theme；聊天头、输入栏、底部导航、媒体吸顶条使用TgGlass。下一步替换剩余独立硬编码常量并补浅色主题。
- 视觉块可整体动画：头部进入选择模式200ms交叉淡入+竖移；控件按下80ms、释放350ms Overshoot1.5；无网络等待后才开始导航动画的做法应避免（资料页立即打开，异步拉取内容）。

### 媒体消息（0.2 未完事项，不是0.3）
- [ ] 语音：按住mic录音，上滑锁定，左滑取消；锁定后按钮停止/发送；波形边录边更新，Opus或AAC，拖拽播放进度；申请录音权限，不把拒绝当静音成功。
- [ ] 视频：系统相册、原生平台codec压缩、封面/宽高/时长元数据、行内播放与全屏；不引入整套ffmpeg。
- [ ] 文件：系统选择器、上传/下载进度、鉴权下载到私有临时目录、系统文件打开；取消与失败重试，配额限制。
- [ ] 多图：同次发送album_id、2–10张网格、图片查看器左右切换；未上传完成不提前生成假消息。
- [ ] 服务端媒体kind/metadata校验、quota/授权回归、无权用户不可猜ID下载。总APK目标<50MB，自定义大字体与素材不打包。

录音动效只读参数摘录（DrKLO/Telegram master，2026-11-11 CST读取；未把Java代码或资源复制到仓库）：

| 交互 | 精确参数/属性 | 来源 |
|---|---|---|
| 进入录音 | 图标/输入附件150ms；recordCircle与controls缩放到1为300ms，整个组DecelerateInterpolator（默认factor1） | `Components/ChatActivityEnterView.java:9095–9134` |
| 上滑锁定 | lockAnimatedTranslation延迟100ms再350ms；snapAnimationProgress到1为250ms/EASE_OUT_QUINT；slideToCancelProgress到1为200ms；伴随触觉 | 同文件 `startLockTransition:4717–4739`；未显式设置插值的子动画按Android默认处理，不假称全部Quint |
| 左滑取消 | slideToCancelProgress到1为200ms/EASE_BOTH；lockAnimatedTranslation200ms；输入文本恢复200ms，起始延迟按分支300或700ms | 同文件 `9680–9695`；删除动画不同分支不可混为一个通用时长 |
| 录音结束回输入 | exitTransition220ms（有message transition）或360ms（无）；recordTimer150ms；输入alpha恢复200ms，延迟150/450ms | 同文件 `9774–9785` |
| mic/camera/send切换 | **220ms / EASE_OUT_QUINT**，不是录音iconChanges的150ms | 同文件runningAnimation主分支，见上表；本版已用该值做camera↔send，mic录音尚未开放 |

### 聊天资料页 / 共享媒体（ProfileActivity / SharedMediaLayout）
- [x] 点击聊天头即时打开独立资料页；头像共享元素到110dp圆头像，居中姓名/状态；消息、静音、搜索真实操作块；用户名/简介与隐私说明卡。
- [x] 媒体/链接吸顶胶囊，三列已加载图片网格，点图复用Hero查看器。**仅本机已加载消息，页面明确标注，不能当作全部历史统计。**
- [ ] 透明顶栏编辑/⋮、二维码sheet、分享、按类型加入/退出/屏蔽、收藏/文件/音频/语音/群组分页。
- [ ] 滚动折叠到姓名+全量媒体计数的紧凑头；头像下拉展开全宽，不只圆形Hero。
- [ ] 右侧可拖动快滚胶囊与跟手月份label，闲置自动淡出；按月统计/按日期偏移定位；不是线性跳到当前已缓存列表的伪实现。
- [ ] 双指2–6列网格连续变形；保持手势中心的消息锚点，不刷新到列表顶部。
- [ ] 后端：每会话按kind分页的shared-media列表、鉴权的总量/年月桶、date+id cursor；删除/清空/封锁权限一致；月份与显示时区一致；返回计数不泄露不属于自己的会话。

| 交互 | 来源精确参数/属性 | 本版/后续说明 |
|---|---|---|
| 资料打开 | `ProfileActivity.onCustomTransitionAnimation:10211,10515`：普通180ms/Decelerate；playProfileAnimation==2为250ms/DEFAULT | 本版普通资料路由180ms/Decelerate+Hero；没有宣称完整header/名称联动复刻 |
| 头像展开/收起 | `ProfileActivity:8767–8773,8861–8867`：剩余进度×250ms÷durationFactor；story分支另乘1.3、FastOutSlowIn；普通EASE_BOTH；横屏收起0ms | 待做可打断的下拉头像展开 |
| 资料header切换 | `ProfileActivity:8204–8231`：150ms/DEFAULT；header shadow后100ms | 当前SliverAppBar随滚动收缩，尚未做这一套独立名称/影子状态机 |
| 网格捏合结束归位 | `SharedMediaLayout:4049–4050`：200ms/DEFAULT，围绕pinchCenterPosition恢复偏移 | 待做，不能用整页crossfade冒充 |
| 命令式换列 | `SharedMediaLayout.animateToMediaColumnsCount:4131–4133`：延迟100ms+350ms/DEFAULT；两套布局混合进度，锚定scroll position | 待做，和捏合结束200ms不是同分支 |
| 媒体列表item动画 | `SharedMediaLayout:2621–2623`：280ms/EASE_OUT_QUINT | 待做服务端分页后增量插入 |
| 快滚显隐 | `SharedMediaLayout.updateFastScrollVisibility:671–703`：alpha↔0/1各150ms（未指定插值，Android默认） | 只有满足fastScrollEnabled且顶部吸附才显示；右侧胶囊具体绘制在RecyclerListView，尚未验证其idle延迟，不编造数字 |
| 快滚提示 | `SharedMediaLayout:4925–4928`：alpha0→1、scale .8→1，150ms | 不是闲置自动隐藏时长 |
| 日期浮层隐藏 | `SharedMediaLayout.hideFloatingDateView:4470–4476`：180ms/EASE_OUT，alpha→0、Y→-48dp+额外偏移 | 此版本showFloatingDateView为空，显示分支要继续追，不能根据hide反推出完整逻辑 |

### 后端与完整0.2验收仍未完成
- SQLite FTS5中文tokenization与云端搜索、私聊block、clear-history单方/双方、report、合法转发来源生成、完整shared-media索引与媒体新kind。
- 目前⋮仅显示已有真实能力（静音时长子菜单、本机搜索、资料），没有伪造“举报成功/已屏蔽/清空成功”。多选已有选择/回复/复制/授权撤回/单条自有编辑；转发与拖选仍未开放。
