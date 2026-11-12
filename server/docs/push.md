# 推送配置 / 主通道设计

2026-11-10，Asia/Shanghai。Mi Push 与 FCM HTTP v1 **代码已实现、本地HTTP mock已测试，尚无真实凭据/设备实测**。空配置不会读取ADC/机器元数据、不会发送假推送。华为/OPPO/vivo只是预留provider标识，尚无适配器。

## 0. 前台服务（0.4.3）

未配置 Mi Push / FCM 时，Android 客户端用前台服务保持已有 WebSocket：常驻通知「轻聊正在保持连接」，在后台或熄屏时由现有通知逻辑弹出系统通知，并遵循会话免打扰与隐私设置。不宣称厂商推送可用。小米等机会强杀后台，需要用户允许通知、将电池设为无限制，并在最近任务中锁定应用。强行停止或重启后需再次打开应用。

## 1. 每台设备只有一个主通道

登录返回device_id；在**客户端已取得SDK regId/token、用户同意通知与SDK隐私后**：

```http
PUT /v1/devices/current/push
Authorization: Bearer <会话令牌>
Content-Type: application/json

{"provider":"mipush","token":"<SDK返回regId>"}
```
provider只允许 `mipush|fcm|huawei|oppo|vivo|none`。除none外token必填，最大4096字节；none必须空token。PUT是替换，不是添加第二个通道；同一设备绝不并发Mi+FCM。原版xiaomi/空provider数据自动迁移成mipush/none，新的API不能继续传xiaomi。

none代表依赖前台服务/WebSocket，不代表后台必达。Android需要主动开启常驻通知、通知权限、电池设置；强行停止/系统回收仍可能收不到。退出/撤销设备清token；SDK更新token后重新PUT。设备列表不返回原始push token，日志不打印凭据。

## 2. 派发与去重

- 消息同事务落库push_jobs；单worker每秒取最多16个最新的(user,chat)待推作业，旧作业标记coalesced。通知指向最后一条消息，客户端用chat_id补齐全部未读，不靠通知正文保存聊天。
- 先验证仍为成员、消息未删除/未读、用户会话通知未静音。按**设备**判断WS在线：某电脑在线不自动抑制另一离线手机；同一设备在线只走WS，离线才走它登记的唯一主provider。
- 数据载荷始终有 `message_id` + `chat_id`（另保留conversation_id兼容别名），客户端以message_id去重通知/消息。标题/正文固定“你有一条新消息”，不把聊天正文送给厂商。
- 同一会话合并：MiPush使用稳定notify_id，jobkey按消息去重；FCM Android collapse_key与notification.tag按chat哈希。FCM同时可保留的collapse key有限，**合并不是送达保证**，最终消息靠持久同步。
- Provider成功只说明服务受理，不是设备显示/已读；没有凭据的已登记通道保留pending，5分钟再检查。无主通道/none跳过，不偷偷回退到另一厂商。渠道错误按1/2/4/8/16/32分钟退避，最多6次进dead-letter（done=-1）；尚无人工重放UI/通道回执统计。
- 明确无效token会清除token并置provider=none，等待客户端新注册。MiPush仅明确regId格式非法66007；**65003设备不在线不能当无效token删**。FCM UNREGISTERED 或 FcmError专属INVALID_ARGUMENT清理；普通BadRequest/认证/配额错误不清token。更新条件同时匹配旧token，避免删除刚轮换的新token。
- 重试目前是用户/会话作业级别；多设备部分成功后重试可能再发同message_id，必须客户端去重。尚无每设备投递状态表。

## 3. Mi Push 后续填写

申请合法开发者主体，创建真实Android应用、核对包名/签名、消息分类/私信模板/限额，再配SDK。服务端只需要：

```dotenv
MIPUSH_APP_SECRET=<仅在服务器本地填写，不在聊天/Git粘贴>
MIPUSH_PACKAGE=你的真实Android包名
```

默认POST `https://api.xmpush.xiaomi.com/v3/message/regid`，`Authorization: key=...`，form编码。保留旧XIAOMI_APP_SECRET/XIAOMI_PACKAGE兼容读取，建议改新名字；API设备provider仍是mipush。endpoint只作服务端受信配置，不接受客户端URL。

Compose基础文件已有这两个env入口；真实.env放服务器，chmod600、从不提交，最好后续改secret文件注入。当前没有密钥时完全不激活adapter。不能拿HTTP mock成功声称小米锁屏测试通过。

官方API与错误码：
- https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1559
- https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1560

## 4. FCM HTTP v1 后续填写

1. Firebase/Google Cloud中确认正确project，启用FCM HTTP v1 API，给专门service account最小必要的发送权限（firebasecloudmessaging.messages.create）；避免Owner全权限。
2. 通过官方管理流程生成service-account JSON，**只放服务器受限文件/secret挂载**，不要发送到聊天、Git、镜像或网页前端。Android端用Firebase客户端配置，不是服务账号私钥。
3. 原生进程：`FCM_SERVICE_ACCOUNT_FILE=/服务器受限路径/service-account.json`。空路径禁用；指定错误文件会启动失败，不回退到环境默认凭据/metadata server。
4. Docker：在服务器创建 `secrets/fcm-service-account.json`，私有目录0700；需要非root容器可读的secret挂载权限（参考README里的Compose file secret说明），使用：
   `docker compose -f docker-compose.yml -f compose.push.example.yml up -d --build`
   容器路径是`/run/secrets/fcm_service_account`。基础Compose不引用该文件，所以没JSON也能以禁用FCM状态启动。
5. 代码用JWT RS256签名→Google OAuth2 token URI换短期access token（自动缓存/刷新），scope为firebase.messaging，再POST `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`；不使用已废弃legacy server key。生产只接受Google OAuth token URI，测试才显式注入mock端点。

FCM适用于GMS/网络可达设备，不保证国内所有小米可用；小米优先mipush，用户不满足厂商条件可明确选择none前台常驻。没有权限/凭据的设备不能假装注册成功。

参考：https://firebase.google.com/docs/cloud-messaging/auth-server ； https://firebase.google.com/docs/cloud-messaging/error-codes 。

## 5. 已验证 / 未验证

自动测试覆盖真实RSA签名JWT→本地OAuth mock→FCM v1请求、access-token缓存、FCM无效token/普通参数错误区别、MiPush合并字段/66007、主通道分发、多设备、按会话合并、静音、设备失效清理，所有网络请求为本地mock，没有用真实service-account或厂商token。

仍需：开发者资质/私信模板、真SDK/签名/通知权限、前台/后台/锁屏/省电/强停/重启矩阵、失效regId定期反馈拉取、通道回执、每设备重试账本、生产告警/密钥轮换。当前未部署至HK，不能给到达率承诺。
