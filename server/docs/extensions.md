# 一期增补协议（实际实现 / 阶段二边界）

2026-11-10，Asia/Shanghai。基础认证/消息见 api.md。数据库自动幂等升级到 user_version=3（已有v1表增列，不重建/丢数据），单进程。所有下述接口仍需Bearer；持久事件统一通过 `/sync` 或 WS `event` 发出，event_seq 仍为当前用户事件游标。

## 1. 纯文本 + UTF-16 entities

消息正文**不是HTML/Markdown**。Send 和 PATCH `/messages/{id}` 支持：
```json
{"client_msg_id":"uuid","kind":"text","text":"hello 😀","entities":[{"type":"bold","offset":0,"length":5},{"type":"custom_emoji","offset":6,"length":2,"custom_emoji_id":"placeholder"}]}
```
实体 offset/length 使用 UTF-16 **code units**，如 😀 长度2；边界不能切开代理对。最多128实体；服务端校验并规范排序，避免同一client id因实体排序改变而重复。支持：bold、italic、underline、strikethrough、code、pre（language可选，最长32字节）、blockquote、spoiler、text_link（url）、url、mention、hashtag、custom_emoji（custom_emoji_id占位）。

重叠规则：允许完整包含（如bold内italic），禁止交叉相交；code/pre不能和其他实体重叠；链接/mention/hashtag相互不能重叠；blockquote不能嵌同类型；相同type+区间重复拒绝。URL只允许http/https、有host、无userinfo；禁止javascript/file/data/tg等scheme。custom_emoji只是数据占位，未接真实贴纸资源/授权。

PATCH编辑可带 text/entities/link_preview_id/reply_markup；省略 entities/markup/preview表示清除，客户端应提交完整编辑后内容。服务端记录edited_at，编辑同样经过关键词、新成员限制、禁言、限流。文本及实体一起影响发送幂等hash。

## 2. reply_markup / via_bot_id（安全预留）

```json
{"reply_markup":{"inline_keyboard":[[{"text":"网页","url":"https://example.com/"},{"text":"操作","callback_data":"action:1"}]]}}
```
每按钮必须且只能有url或callback_data；URL同安全scheme限制；callback_data非空且≤64 **字节**；文字≤256字节，最多8行×8按钮，总64。人类消息可以存按钮；**via_bot_id 目前只能为空，伪造机器人署名403**，以后由单独Bot身份授权写入，不能信任客户端传的via_bot_id。

POST `/messages/{id}/callback` `{callback_data:"action:1"}`：验证会话/历史可见范围、消息未删除、数据确实对应该消息按钮；返回 **501 bot_callbacks_phase2**，不会发假回调。后续Bot工作流：生成callback_query id→投递授权Bot webhook/getUpdates→answerCallbackQuery（有时效/去重）→Bot权限验证后编辑原消息。未实现Bot token/投递/answer逻辑。

`forward_origin_json` 数据列和消息 forward_origin 字段预留，普通发送不接受任意伪造来源。以后转发必须服务端查源与授权生成来源快照。计划发送建议独立scheduled/outbox表，**到期发送才分配conversation_seq**；目前没有定时发送API，不会收schedule参数后立即误发送。

## 3. 多条置顶消息

- GET `/conversations/{id}/pins` → `{messages:[完整Message]}`，只返回该成员可见的未删除消息。
- PUT 同路径 `{message_id,remove:false}` 置顶，remove:true取消；最多50条。群仅owner/admin；direct任一成员可操作。
- 持久事件 `message.pinned / message.unpinned`，data含message_id/actor_id；撤回/批量清理发`pins.changed`供刷新。置顶操作写audit。

## 4. 链接预览（明确同意抓取、缓存、SSRF）

POST `/link-previews` `{url:"https://example.com/"}` → `{id,url,title,description,image,site_name,fetched_at}`；缓存SQLite 24小时，每用户10次/分钟；同URL缓存命中不重复抓取。发消息 `link_preview_id` 引用缓存；必须正文或text_link实体真实含该URL，否则400。Message返回嵌套link_preview快照（编辑/缓存刷新不会悄悄改旧消息）。

- 客户端建议先显示“生成链接预览”开关；该接口会让目标站知道服务器IP。没有静默自动抓所有消息链接。
- 超时5秒、header/TLS3秒、正文最大512KiB、title500/description1500/site_name200字节，最多3跳；仅http(s)、80/443，禁止userinfo、本地host。
- 不走环境代理；自定义Dial在**每次连接**解析DNS，拒绝任意私有/环回/链路本地/保留/多播地址、混合公私DNS结果、IPv4映射与非全球IPv6，然后直接拨已校验IP，阻止DNS重绑定；重定向再次验证。超大压缩响应在解压后同样受读取上限。
- HTML用解析器读OG meta/title，返回纯文本，不能当HTML插入客户端。image仅存解析后的URL；拒绝私有/无效地址，并校验解析IP；**未下载/转码/缓存图片字节、未做安全图片代理**。客户端不要自动直连任意OG图片（跟踪/重绑定风险），图片代理是上线前待办。
- tests只用本地缓存/纯HTML解析及IP/DNS拒绝检查，不抓取真实外站、不访问元数据地址。

## 5. 群反垃圾 / 审核

权限仅group owner/admin；admin不能对owner或其他admin做惩罚操作，owner不可被禁言/封禁；普通成员只有自删自己消息的权限。

GET/PUT `/conversations/{id}/settings`：
```json
{"new_member_hours":24,"user_rate_per_min":120,"chat_rate_per_min":300,"keywords":["spamword"]}
```
- new_member_hours 0–720（默认0，不限制）；从joined_at算，迁移旧成员joined_at=0视为既有可信成员。时限内普通新成员不能发链接、按钮、媒体；媒体上传到该会话也拒绝；owner/admin免新成员限制。
- 消息全局每用户120/分钟，另有每会话成员默认120/分钟、会话总300/分钟（group可调）；编辑也限流。固定窗口允许小突发，不是承诺成熟反滥用算法；重试相同client_msg_id不重复消耗消息额度。429不应自动狂重试。
- keywords最多100、每项100字节，大小写不敏感子串过滤；链接检测含域名/http/www及实体链接。不是完整混淆字符/机器垃圾识别，不声称防所有绕过。过滤适用于新发与编辑。

POST `/conversations/{id}/moderation`：
```json
{"action":"mute","user_id":"u2","duration_minutes":60,"reason":"spam"}
```
action：mute（1–43200分钟）、unmute、ban（移出群+禁再加入）、unban（只解封，不自动加回）、delete_all（该用户在本群所有消息tombstone，不碰其他群）。单条删除沿用DELETE /messages/{id}。管理员禁言`muted_until`与用户自己的通知静音`notification_mute_until`不同。

事件：moderation.updated、membership.changed（ban）、messages.deleted（sender_id/through_seq，客户端按条件tombstone）、pins.changed、dialog.updated/removed。GET `/conversations/{id}/audit` 仅管理员，最近100条，包含actor/action/target/details/created；设置、成员管理、置顶、管理员删除/封禁/禁言/批删均记录。无自动审计保留/合规导出，生产需补。

## 6. 会话列表、未读/@、草稿、归档、静音

GET `/conversations?limit=50&cursor=...&archived=all&folder_id=...`：
- 默认不含归档；archived=true仅归档，all包含全部。
- **列表业务一条SQL**（认证另查session）：未读范围聚合CTE（索引只扫read_seq/joined_seq之后）、总badge、最后消息索引查询、角色/个性状态、keyset分页；无逐会话HTTP查询。置顶聊天先按pinned_order升序，其余按last_activity降序、id稳定打破同时间，cursor为opaque base64 JSON。
- `{conversations:[...],total_unread_badge,next_cursor,has_more}`；limit默认50/最大100。即使当前页/归档筛选为空，也返回全局badge。
- 每项：unread_count、unread_mention_count、manual_unread、last_read_seq、last_message（含text/kind/seq/sender/deleted/edited_at）、last_message_read_count/recipient_count、read_receipts_visible、draft、archived、pinned_order、notification_mute_until。
- @badge为正文中的本群有效@handle（大小写不敏感、不能是email中间），不计自己/已读/已删；编辑重建mention索引。未做“所有人@all”权限/通知。

PATCH `/conversations/{id}/state`（只改当前用户、各字段可独立省略）：
```json
{"archived":true,"pinned_order":1,"mute_until":"forever","mark_unread":true,"draft":{"text":"草稿","entities":[],"reply_to":"m1"}}
```
- pinned_order=0取消；1–1000决定顺序（允许同序，稳定按活动/id）。这是**聊天置顶**，与消息pins不同。
- mute_until可为RFC3339绝对时间、"forever"（存极远未来）、""取消。未读数仍可见，但静音消息不计总badge/文件夹badge，不推送。解静音后历史未读重新计入；有限静音到期由每秒有界worker清除并发本人状态事件。
- mark_unread=true只设手工标记，不回退read_seq，badge至少1；false将读位推进到当前last_seq，发隐私允许的read.updated。普通/read也会清手工标记。
- draft纯文本/entities/reply_to，本人多端同步；clear_draft=true清草稿。当前按最后提交到服务器覆盖，无协同合并；发送后客户端显式clear_draft，不擅自覆盖另端新草稿。
- 个性变更只给本人设备持久dialog.updated；读位更新还给隐私允许的其他成员更新列表。draft不发给别人。

实时 `dialog.updated`：该人的未读/@/全局badge、folder_unread_counts、个性状态/草稿、最后消息预览和可见已读统计；`dialog.removed`退群/封禁后移除并更新badge。客户端按seq/upsert，不把每个状态事件新增成聊天消息。

文件夹：GET/POST `/folders`，PATCH/DELETE `/folders/{id}`，仅当前用户（最多20个）。
```json
{"name":"未读群","sort_order":1,"filter":{"include_chat_ids":[],"exclude_chat_ids":[],"types":["group"],"unread_only":true}}
```
include与types取并集（均空=所有）；exclude始终优先；unread_only最后应用，手动未读也匹配。include/exclude各最多200 id。GET返回各文件夹unread_count（去掉静音），不同文件夹可重复计同一聊天。事件folder.updated/deleted同步定义；消息/读位/静音变化通过dialog.updated.folder_unread_counts刷新计数。文件夹筛选含归档，但列表显示仍受archived参数影响。

## 7. 已读隐私：全局 + 个人互惠

- 环境 `READ_RECEIPTS_ENABLED=true` 默认开启；false服务端仍保存自己的read_seq来计算未读，但不向别人发read.updated，不在列表/成员接口泄露他人的阅读位置。重启关闭时持久旧read事件通过sync也会替换为privacy.redacted（保留seq不造缺口）。
- GET `/me/privacy` 返回个人开关、global_read_receipts_enabled、effective；PUT `{read_receipts_enabled:false}`，默认true。
- 个人关闭是**互惠**：不向别人显示自己的已读，也看不到别人的已读。只有全局开且viewer与reader均开启时可见；任意关闭时不能用“0”冒充未读，整体不可见时last_message_read_count为null，read_receipts_visible=false。开启的viewer看隐私关闭者时，不计入可见read_count；成员last_read_seq为null。
- direct：stored=单勾，只有可见的对方read_seq到达才可双勾；**没有独立delivered回执**。group：read_by_N为last_message_read_count，只含允许公开的读者，配recipient_count，不能把一人读了画成全群全读。当前未提供逐人reader名单，可之后给小群加权限保护的列表。
- 自己的last_read_seq永远可用于未读；自己仍可收到自己的read.updated，其他人不会。privacy.updated同步自己的选择；切换后dialog.updated使显示失效/刷新。历史曾合法公开的回执不承诺从接收者设备/备份擦除。

## 8. Polls：schema/校验完成，功能明确阶段二

建好polls / poll_options / poll_votes，含question、single/multi、anonymous/public、quiz/correct_option、closes_at/closed、creator/chat/message关联。校验2–10选项、问题/选项长度、quiz必须单选且正确索引有效、关闭时间未来≤365天、client_msg_id。

以下**返回501 polls_phase2，无投票/假结果落库**，且先校验成员权限；创建会校验PollSpec：
- POST `/conversations/{id}/polls` `{question,options,multiple_choice,anonymous,quiz,correct_option?,closes_at?,client_msg_id}`
- GET `/conversations/{id}/polls/{poll_id}`
- POST `.../{poll_id}/vote`（阶段二请求方案 `{option_ids:[0],client_vote_id}`）
- POST `.../{poll_id}/close`（阶段二creator或管理员）

阶段二实现约定：投票变更事务化、单选替换/多选去重、关闭时间强制检查、匿名不泄露投票身份、公开名单按成员权限；quiz正确答案只在策略允许时揭示。持久事件poll.created/poll.updated/poll.closed带票数聚合，匿名不得带user_id；每人的选择通过私人事件同步。当前没有自动关闭worker、计票或推送更新，不把这些预留当一期完成。
