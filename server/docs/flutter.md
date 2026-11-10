# Flutter 接线清单（不修改动效 demo）

1. **先真实双设备文字**：用独立 API repository/transport，保持现有 motion/UI 不依赖网络；邀请登录页调用 `/auth/*`，保管 token/device_id；请求错误统一映射可重试/无权限/会话过期。Flutter Web 用 `/ws-ticket`，Android 握手可传 Bearer。
2. **本地优先**：Drift/SQLite 存 messages、conversation read state、event_cursor、outbox。按 client_msg_id 维持气泡稳定 key；点击发送先落 outbox/即时回显，再后台 POST/WS 发送；失败重发原 UUID。ACK 返回 stored 才显示“已发送”。先不要做“对方已送达”标记（服务端没有 delivered.updated）；read.updated 才是阅读证据。
3. **同步**：从本地游标 `sync.resume`；每个 event 与游标同本地事务入库，成功后 event.ack；消息按 (chat_id,seq)/id upsert，删/改/反应同样处理。断线指数退避带随机抖动，重连用最后落盘游标，不用最后“收到但没落盘”的序号。首次拉会话快照、成员、分页历史；新成员不看加入前历史。
4. **分页与状态**：REST 历史倒序，before 取最小已加载 seq；列表按正序展示/保持阅读锚点。read_seq 只在用户实际可见阅读后上报，不能收到消息就报读。typing 约2s限频，临时5s到期；presence 只作连接提示。
5. **附件**：移动压缩/去EXIF/生成本地缩略图；raw body POST /media + X-Conversation-ID，成功再发消息。文件失败重试与消息发送分开。鉴权下载+缓存，不将 Bearer 放 URL；Web 鉴权 fetch 后 Blob。现阶段需先补服务端尺寸/时长/thumbnail 元数据API，避免永久把这些塞正文。
6. **群/权限**：member/admin/owner UI 根据 `/members`，但不以 UI 禁用替代后端鉴权；退群/踢出清掉活动订阅和媒体入口。收到 membership.changed 后刷新会话快照。反应是服务器 upsert/删除，以事件校准乐观 UI。
7. **Android 通知**：先拿到合法小米开发者主体、包名/签名/模板配置，再接 SDK，登录后绑定 `/devices/current/push`；退出/撤销清 token。通知只用 id 拉取消息；前台/后台/锁屏/省电/强停/重启矩阵实测。前台服务是显式可见的可选fallback，不承诺强停后秒达，不拿推送渠道成功当已读。
8. **验收先于动画承诺**：两台设备交叉发送、飞行模式、ACK丢失重试、编辑撤回、退出/重进群、媒体越权、重启恢复。再在真实小米 release/profile 测60/120Hz帧耗时。Web demo流畅不等于手机已验证。

本版是 TLS 云端聊天，设置页明确“服务器可访问消息内容”；不要出现端到端加密徽章。以后 E2EE 应独立设计密钥/多设备迁移，不在现有明文 payload 上随意加一个 encrypted=true。
