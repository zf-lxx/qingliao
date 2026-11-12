# 轻聊 Go 后端 API v1（本地实现）

2026-11-10，Asia/Shanghai。本文是 `/workspace/tg-chat/server` 已实现协议，优先于仍在更新的早期 Python/PG 研究草案。Go + modernc SQLite/WAL，单进程。不是 Telegram 客户端/协议实现；没有 E2EE，服务器可读内容。

> 增补功能与优先协议：[extensions.md](extensions.md)：UTF-16富文本/按钮、置顶、OG预览、审核、分页会话/文件夹/草稿、全局与个人互惠已读隐私；投票/回调仅501阶段二stub。以下旧版基础说明与增补冲突时以增补为准。

## 1. 通用约定与认证

- 基础路径 `/v1`，JSON UTF-8；API 时间 UTC RFC3339，客户端转换 Asia/Shanghai。ID 为服务端随机字符串；seq 为 64 位整数，JS 长期接入应处理安全整数边界。
- 除注册、登录、健康检查外需 `Authorization: Bearer <access_token>`。本版用**随机不透明会话令牌，不是 JWT**：256 位随机数、数据库只存 SHA256，默认 30 天；退出/设备撤销立即失效。无独立 refresh token，过期重新登录；不能宣传已有 refresh rotation。
- 登录每次生成新 device_id，需持久保存返回的 token/device_id，不要每次启动重新登录。移动端 Keystore/Keychain；浏览器暂用内存，不建议 localStorage 长期持有；HttpOnly cookie/BFF 属于上线前待办。
- 成功通常 200，创建用户/邀请/会话/媒体 201。失败 `{"error":"forbidden"}`；400 参数，401 认证，403 权限，409 幂等或引用冲突，413 文件过大，429 限流，507 媒体配额，500 内部错误（不回传 SQL/密码）。
- JSON 请求最大 64KiB，未知 JSON 字段拒绝。CORS/WS Origin 仅允许精确 `CHAT_ORIGIN`；无 Origin 的移动客户端允许。
- 默认限流：同直连 IP 的登录/注册/退出合计 20 次/分钟，其他 HTTP 600 次/分钟；WS 同一用户 120 帧/秒；typing 同人同会话 2 秒一次。**不信任 X-Forwarded-For**，反代下这些 HTTP 限额目前会共享；正式部署要加可信代理范围/边缘限流，不能直接信任任意转发头。
- 当前最多 512 WS 连接、每用户 256（是保护阈值，不是容量承诺）；单群最多 100 人（初始创建检查；成员新增同样受限）。会话列表现为keyset分页，默认50、上限100，置顶排序优先，再按last_activity；详见增补。

## 2. 账号 / 设备 / 资料

| 方法 / 路径 | 请求 / 响应要点 |
|---|---|
| GET `/healthz` | `{ok:true}`，检查数据库连接 |
| POST `/auth/register` | `{handle,password,invite_code,display_name?,platform?}`；仅有效未过期邀请，原子扣次数；handle 3–32 字母数字下划线，自动小写；password 12–72 **字节**，bcrypt |
| POST `/auth/login` | `{handle,password,platform?}` |
| POST `/auth/logout` | 撤销当前 session 并关闭对应 WS |
| POST `/invites` | 仅系统管理员；`{uses:1,expires_hours:24}`，次数 1–100、有效期 1–720 小时；返回一次性明文 `invite_code`，数据库只存 hash |
| GET `/me` / GET `/users/{id}` | 用户 id、handle、display_name、avatar_media_id、online、last_seen |
| PATCH `/me` | `{display_name,avatar_media_id}`；头像必须本人上传的受支持图片；空字符串清头像 |
| GET `/users?q=bo` | 已登录用户搜索 handle，至少 2 字符，最多 30 条（小圈子目录，不是匿名全网搜索） |
| GET `/devices` | 自己的设备、platform、revoked、last_persisted_event_seq、current；不返回 push token |
| PUT `/devices/current/push` | 主通道`mipush/fcm/huawei/oppo/vivo/none`，none+空token清除；详见push.md |
| DELETE `/devices/{id}` | 仅本人设备，撤销该设备的所有会话，并关闭 WS |

注册/登录返回：
```json
{"access_token":"<仅示例占位>","token_type":"Bearer","expires_at":"2026-12-10T14:00:00Z","device_id":"d1","user_id":"u1"}
```
管理员只可首次引导：`CHAT_ADMIN_HANDLE` + `CHAT_ADMIN_PASSWORD_FILE`（优先）或 `CHAT_ADMIN_PASSWORD`。已有管理员后环境变量不会覆盖密码；生产应移除 bootstrap secret。没有忘记密码/密码修改/UI 管理后台。

## 3. 会话、成员、消息

| 方法 / 路径 | 内容 |
|---|---|
| POST `/conversations` | `{kind:"direct"或"group"或"channel",title?,member_ids:["u2"]}`；包含自己；direct 双人 pair 唯一，重复返回同 id；group 至少 2 人、最多 100 人；channel 必须有标题，成员可仅创建者（订阅者），只有 owner/admin 可发消息 |
| GET `/conversations` | `{conversations:[{id,kind,title,avatar_media_id,last_seq,last_read_seq,role,unread_count,...}]}`；unread 统计自己未读、别人发送、未删除消息 |
| GET `/conversations/{id}/members` | 成员 user_id、role、joined_seq、last_read_seq |
| POST `/conversations/{id}/members` | `{user_id,action:"add"或"remove"或"role",role?:"admin"或"member"}` |
| GET `/conversations/{id}/messages?before=100&limit=50` | 按 conversation_seq **倒序**；before 严格小于，上限 100；返回 `{messages:[]}` |
| POST `/conversations/{id}/messages` | 见下文 Send；返回完整已落库消息，只有成功 COMMIT 才算 stored |
| PATCH `/messages/{id}` | 作者可编辑 `{text}`；本版改文字/附件说明，不替换附件 |
| DELETE `/messages/{id}` | 作者或会话 owner/admin 可撤回；保留 seq、id、deleted tombstone，清正文和 media_id |
| PUT `/messages/{id}/reactions` | `{emoji:"👍",remove:false}`；每用户每消息最多 8 种，每种最多 32 字节 |
| GET `/messages/{id}/reactions` | `{reactions:[{user_id,emoji}]}` |
| POST `/conversations/{id}/read` | `{last_read_seq:42}`，只增不减，不能超过会话 last_seq；产生 read.updated |
| PATCH `/conversations/{id}` | `{title?,avatar_media_id?}`；group/channel 的 owner/admin 可改标题和头像 |
| GET `/conversations/{id}/search?q=&before=&limit=` | 中文 FTS5（`qing_tokens`：单字 Han + 拉丁词）；`before` 为 conversation_seq；返回 `{messages:[]}` |
| GET `/conversations/{id}/media?kind=image\|video\|file\|voice\|link\|all&before=&before_date=&limit=` | 共享媒体。`counts` 按 kind 统计全历史；`months` 按 Asia/Shanghai 月桶（count/first_seq/last_seq）；列表按 seq 倒序，`before`/`before_date`（RFC3339 或 YYYY-MM-DD）分页，`has_more`/`next_before` |
| POST `/conversations/{id}/clear` | `{both:false}`；默认只对自己隐藏到当前 last_seq（抬高 joined_seq）。`both:true` 在群/频道需 owner/admin，会标记已有消息删除并通知所有成员 |
| POST `/conversations/{id}/report` | `{message_id?,reason}`；reason 1–2000 字；201 `{id,status:"submitted"}`。管理员 `GET /admin/reports` |
| PUT `/users/{id}/block` | `{blocked:true\|false}` |
| GET `/me/blocks` | `{user_ids:[]}` |
| POST `/messages/{id}/forward` | `{conversation_id,client_msg_id}`；服务端写入 `forward_origin`（不可伪造），复用同一 `media_id` |
| GET `/conversations/{id}/pins` | `{messages:[]}` 当前置顶（最多 50） |
| PUT `/conversations/{id}/pins` | `{message_id,remove:false}`；群/频道需 owner/admin |

角色：群 owner 可增删成员/设置 admin，admin 可增删普通成员但不能踢 owner 或其他 admin；普通成员可自己退出，owner 暂不能退出/转让。direct 不改成员。**本版新加入/重新加入者只能读取 joined_seq 之后的新消息**，不能看加入前历史；退群后不能读历史和附件（自己拥有的附件除外）。小圈子一期策略，不等于所有聊天产品通用策略。

发送：
```json
{"client_msg_id":"持久随机 UUID","kind":"text","text":"你好","media_id":"","reply_to":""}
```
kind 支持 `text/image/voice/file/video`。text 不可空白；其余需先上传并引用本人的、绑定当前会话的 media_id；image/voice/video 检查检测 MIME（video 识别 MP4 `ftyp` 盒）。可选 `album_id`（`[A-Za-z0-9_-]{1,64}`）把多条消息编成相册。text 字段最长 16KiB。reply_to 必须是本会话、当前可见、未删除消息。返回含 `media`（width/height/duration_ms/waveform/file_name/thumbnail_id）、`album_id`、`forward_origin`、`reply_to_seq`。

返回：
```json
{"id":"m1","conversation_id":"c1","conversation_seq":1,"sender_id":"u1","client_msg_id":"uuid","kind":"text","text":"你好","created_at":"2026-11-10T14:00:00Z","deleted":false}
```
`(sender,client_msg_id)` 唯一。相同 id、相同规范化 payload 返回原消息；同 id 改内容/改会话返回 409。保存 outbox 后重试**不能重建 client_msg_id**。编辑/删除不更改最初发送的幂等 hash；重试返回消息当前状态。

## 4. 持久事件 / 离线补齐

GET `/sync?after=0&limit=100`，最大 200：
```json
{"events":[{"v":1,"op":"event","event_seq":1,"type":"message.created","conversation_id":"c1","data":{"id":"m1"}}],"next_cursor":1,"high_watermark":1,"has_more":false}
```
示例 data 是缩略，message.* 事件实际上带完整 Message。事件游标是**每用户单独**的连续序号；消息 seq 是会话内序号，不能混用。after<0 或超过当前最高值返回 400。

持久事件：`conversation.created`、`membership.changed`、`message.created/edited/deleted`、`reaction.updated`、`read.updated`、`message.pinned`/`message.unpinned`、`conversation.cleared`、`block.updated`、`dialog.updated`。成员变化和消息、用户事件、推送作业同 SQLite 事务；WS 直接从持久事件拉取，不把内存广播当唯一消息源。

当前事件**不裁剪**，因此没有游标过期/reset 实现；不能先删 events 再假装游标完整。后续必须补保留策略、reset/snapshot 和清理。退出会话之前合法收到的历史事件不会抹除；撤回不是安全抹除（事件日志、备份中仍可能保留原文）。

## 5. WebSocket

移动：GET `/ws` 握手用 Bearer header。浏览器：POST `/ws-ticket` 获取 30 秒、单次 ticket，再连 `/ws?ticket=...`；反代访问日志必须隐藏 query。**禁止把长期 access token 放 query**。ticket 重启后失效。

服务端先发：
```json
{"v":1,"op":"hello","device_id":"d1","resume_required":true}
```
然后客户端**每连接仅一次** resume，游标来自本地 DB：
```json
{"v":1,"op":"sync.resume","req_id":"r1","after_event_seq":0}
```
返回 `op:"result",req_id:"r1",data:{high_watermark,after_event_seq}`。随后统一事件流从游标继续；补齐与实时共用持久源，事件按 event_seq 递增；允许 ACK/result 与事件交错，不依赖先后做 UI。

发送：
```json
{"v":1,"op":"message.send","req_id":"s1","conversation_id":"c1","client_msg_id":"uuid","payload":{"kind":"text","text":"hello"}}
```
服务端：`{"v":1,"op":"message.ack","req_id":"s1","data":<完整Message>}`，其含义是 **stored**，不是对方已送达/已读。

客户端先把事件写入本地数据库，再 ACK：
```json
{"v":1,"op":"event.ack","req_id":"a1","last_persisted_event_seq":10}
```
不能 ACK 超过当前连接已经投递的最大 seq。设备游标取 max；**本版尚未把设备 ACK 聚合为发件人侧 delivered.updated 状态**，客户端不要用单勾/双勾臆造“对方已送达”。阅读状态以 read.updated/成员 last_read_seq 为准。

其他客户端帧：
```json
{"v":1,"op":"read.update","req_id":"r2","conversation_id":"c1","last_read_seq":42}
{"v":1,"op":"typing","req_id":"t1","conversation_id":"c1","typing":true}
{"v":1,"op":"ping","req_id":"p1"}
```
响应通常 `result`；ping 返回 `pong`。失败 `{"v":1,"op":"error","req_id":"...","error":"forbidden"}`。

临时事件：`op:typing`（conversation_id,user_id,typing,expires_in:5）；`op:presence`（user_id,online,last_seen），只发共同会话成员。presence 是连接聚合近似状态，不证明人在看屏幕。服务端 WebSocket ping 25s，pong/read 超时 70s；客户端需响应协议 pong。

投递：事务提交即时唤醒，300ms 定时补漏；每轮最多 100 事件。单连接临时/响应队列 32，写超时 5 秒，慢消费者断开后客户端重连补齐，不无限堆内存。生产要进一步做会话级定向唤醒和数据库读取复用。

## 6. 媒体

1. POST `/media`，Bearer；**原始二进制请求体**（不是 multipart），会话附件加 `X-Conversation-ID: c1`。头像可不带会话。可选元数据头：`X-Media-Width`、`X-Media-Height`、`X-Media-Duration-Ms`、`X-Media-Waveform`（Base64，解码后 ≤256 字节）、`X-Media-Filename`、`X-Thumbnail-ID`（须为本会话已有媒体）。MIME 由前 512 字节检测，不信扩展名/声明（MP4 看 `ftyp`）。返回 `{id,mime,bytes,sha256,storage:"local",width,height,duration_ms,waveform,file_name,thumbnail_id}`。
2. 发消息引用 media_id。未绑定到会话的头像不能直接发作会话附件，需另传。
3. GET `/media/{id}`，Bearer，支持 HTTP Range；仅所有者、合法消息所属会话中有权看该消息的成员，或已登录用户读取被设置为头像的图片。默认 attachment + nosniff + CSP sandbox；网页端请鉴权 fetch 成 Blob 播放，不往 URL 塞 token。
4. DELETE `/media/{id}`，仅所有者，尚有消息/头像引用则 409；取消上传/撤回后可以清孤儿。

默认配额 **512MiB（仅媒体目录，含孤儿/临时文件；不是整个数据库配额）**；每文件 20MiB。串行流式上传保护额度，内存不整文件缓冲；超过返回 413/507。媒体 ID 随机固定格式，不能路径穿越。媒体上传接口不抓取外部 URL；独立链接预览接口会受限抓取公开HTTP页面（SSRF防护详见增补），不做 ffmpeg/转码，不内嵌 HTML/SVG。

Storage 接口含 Put/Open/Delete/Usage/PresignUpload，local 实现可用；`CHAT_STORAGE=local`。其他值明确报“不支持”，**R2/S3 适配器和预签名上传流程尚未实现**，不是现在改个 key 就能切换。将来先建 R2 adapter，再做 upload-init/finalize/对象校验。

客户端负责压缩、去 EXIF 和缩略图生成；服务端保存客户端上报的尺寸/时长/波形/文件名和缩略图引用，不做 ffmpeg/转码，也不做病毒扫描或超大图片像素检测。服务器只存原始已压缩字节，不宣称已有安全转码。自动孤儿清理仍未实现。

## 7. 推送与 Bot 边界

> 推送代码已更新为可插拔MiPush+FCM HTTP v1，请以[push.md](push.md)为准；以下早期单小米作业描述不再完整。

- 提交消息时，同事务为每个其他成员建 push_jobs。worker 每秒取最多 16 个作业，离线、仍是成员、仍有未读才推；在线跳过。HTTP API 成功不是设备收到，更不是已读。
- 配置 `XIAOMI_APP_SECRET / XIAOMI_PACKAGE`；默认接口 `https://api.xmpush.xiaomi.com/v3/message/regid`。无配置时作业保留，5 分钟后再检查，不发送假推送；token 无效/渠道失败指数重试，最多 6 次后 dead-letter `done=-1`。当前每作业多设备失败会整体重试，jobkey 尽量去重。
- 通知只含“你有一条新消息”及 conversation/message id，不发正文。MiPush 私信模板、开发者主体、包名签名、SDK 通知权限和当前政策仍需真接入核对；当前只做本地 mock HTTP 合约测试，**未连接真实小米账号/设备、未测锁屏推送**。
- 参考官方： https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1559 。Android 前台常驻 fallback 是客户端后续任务，服务端此处没有伪装实现。
- Bot：`internal/chat/bot.go` 仅接口定义（AuthenticateBot/GetUpdates/SetWebhook/SendMessage），用户事件游标与 client_msg_id 可复用；没有公开 Bot 路由、bot token 表或 webhook 任务。正式做时单独 token/hash/scopes、限制会话权限、防 webhook SSRF、签名、重试/幂等、long polling；机器人代码可运行外部机器。

## 8. 上线前必须补齐

密码更改/账号禁用与会话轮换、可信代理限流、浏览器安全会话策略、设备数量限制、媒体元数据/扫描/保留清理、事件/推送作业保留、备份恢复演练、崩溃故障注入、更多离线多设备/群边界测试、真实厂商推送、容器构建/实际 HK 资源测试。单 SQLite 写连接不是横向扩展方案；不支持多个实例共享一个文件广播。E2EE/音视频通话/机器人平台都不在本版。

## P3 / 动态扩展

所有路径仍在 `/v1`，需登录。schema `PRAGMA user_version=7`。

- 联系人：`GET /v1/me/contacts`，`PUT/DELETE /v1/me/contacts/{id}`
- 通知范围：`GET /v1/me/notification-scopes`，`PUT /v1/me/notification-scopes/{private|group|channel}`（`mute_until` unix，`show_preview`）
- 隐私规则：`GET /v1/me/privacy/rules?setting=`，`PUT /v1/me/privacy/rules`（规则数组按 TDLib `userPrivacySettingRule*` 原样存储）。已有的 `GET/PUT /v1/me/privacy` 仍只管已读回执。
- 贴纸：`GET /v1/sticker-packs`，`GET /v1/sticker-packs/{id}`，`POST /v1/sticker-packs`，`POST /v1/sticker-packs/{id}/stickers`，`GET /v1/sticker-files/{id}`，`GET /v1/stickers?q=`，`GET /v1/me/sticker-favorites`，`PUT /v1/me/sticker-favorites/{id}`。内置包 `qingliao-basic`（8 张程序生成的 PNG，不是 Telegram 资源）。`kind=sticker` 的消息用 `sticker_id` 发送。
- 投票：`POST /v1/conversations/{id}/polls`（201 + 消息），`GET .../polls/{poll_id}`，`POST .../vote`（`option_ids`），`POST .../close`。最多 10 个选项。
- 清单：`POST /v1/conversations/{id}/checklists`，`GET/PATCH /v1/messages/{id}/checklist`，`POST .../checklist/tasks`，`POST .../checklist/done`（`done_task_ids` / `undone_task_ids`）。
- 文件夹、链接预览：沿用已有 ` /v1/folders` 与 `POST /v1/link-previews`。文件夹 `types` 现允许 `direct|group|channel`。
- 动态 / 故事：`POST /v1/stories`（`media_id`, `kind=photo|video`, `caption`, `privacy`），`GET /v1/stories/active`，`GET/PATCH/DELETE /v1/stories/{author}/{no}`，`POST .../open`，`PUT .../privacy`，`PUT .../reaction`，`GET .../interactions`，`POST .../report`，`GET /v1/users/{id}/stories?archived=&from_no=`。默认 24 小时过期。无直播/RTMP。
- 富文本实体在原有加粗/斜体等之外，允许 `cashtag`、`email`、`phone`、`bot_command`、`text_mention`（`user_id`）。
