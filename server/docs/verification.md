# 最终本地验收报告

完成实测：2026-11-10 22:58:33 +0800（Asia/Shanghai）。本目录为Go后端内测基座，不是已完成/公开上线的App。本次没有登录/部署HK、没有修改现有Traefik、没有修改动画demo；服务端测完已关闭。

## 1. 已实现

Go单静态二进制、modernc SQLite WAL（同步FULL、单写连接、2MiB页缓存）；邀请注册、bcrypt、撤销会话/设备、资料头像；direct/群/角色；文字图片语音文件、回复/编辑/撤回/反应、幂等client_msg_id；会话seq+每用户持久事件、WS resume/ACK/心跳/typing/presence；已读/未读。

增补已落地：UTF-16实体校验/存储、内联键盘校验/持久化、多置顶、SSRF安全OG预览/SQLite缓存；群新成员限制/关键词/用户与群限流/禁言封禁/批删与审计；单业务SQL的keyset会话分页、未读/@/总badge、聊天置顶/归档/静音到期、同步草稿与文件夹计数；全局READ_RECEIPTS_ENABLED和个人互惠隐私开关、群可见read-by-N。

推送：设备唯一主通道，MiPush HTTP + FCM HTTP v1完整编码，FCM使用服务账号RSA JWT/OAuth2及token缓存，默认无凭据禁用；按会话合并、静音/设备WS在线控制、无效设备token清理。huawei/oppo/vivo仅预留标识；none走客户端前台WS。没有真实厂商调用。

**明确不是已实现**：Poll计票/投票实时结果与Bot callback链路目前为schema+校验+成员权限测试+501 stub；via_bot_id拒绝人类伪造；R2/S3只留Storage契约；无E2EE/通话/定时发送/合法转发来源生成。

## 2. 自动测试

- 顶层31个测试（另含privacy开关子测试）；`go test ./... -count=1 -cover`通过，internal/chat覆盖率72.6%（cmd入口/压测工具0%，不宣称全仓72.6%）。
- `go test -race ./... -count=1`通过（internal/chat 83.312秒），`go vet ./...`通过。
- 测试包括：并发seq/邀请/幂等、重启消息恢复、离线分页、媒体权限/Range/配额、群角色边界、富文本UTF-16/重叠/URL、SSRF私网/重定向拒绝、OG缓存、按钮限制/501回调、置顶、投票stub、审核/限流/审计、文件夹/归档/手工未读/草稿隐私/静音到期、全局/互惠已读开关、群read-by-N；推送测试验证真实RSA签名到本地OAuth mock/FCM v1、access token缓存、MiPush错误码、唯一主通道、合并、静音、多设备及失效token清除。
- 没有真实外站抓取benchmark、锁屏送达率、手机帧率/耗电、实际音频解码、完整故障注入/恢复演练或生产安全审计。

## 3. 200连接的真实进程RSS

环境：共享box Linux x86_64、Go1.27.3、modernc/sqlite1.62.0，box约16GiB，不是HK2核1G。GOMAXPROCS=2、GOMEMLIMIT=64MiB（Go软限制，不是进程RSS上限）。每100ms读取/proc/PID/status，仅服务端进程，不含压测客户端/容器/代理；这些内核RSS字段为近似/异步计数，采样与HWM可能略有差异，报告保留原始读数。

| 指标 | 实测 |
|---|---:|
| 启动后空载RSS | 13592 KiB / 13.27 MiB |
| 采样峰值RSS | 33148 KiB / 32.37 MiB |
| 内核VmHWM | 33000 KiB / 32.23 MiB |
| 最后10秒RSS中位数 | 32992 KiB / 32.22 MiB |
| 静态amd64程序 | 12714144 bytes / 12.13 MiB |
| gzip程序（**不是镜像**） | 5395482 bytes / 5.15 MiB |

负载：200 WS连接**复用一个接收会话/账号**，另一个用户发100条文字，20000条message.created事件全部收到、错误0，另有dialog状态帧；连接保持25秒。不是200独立真实用户，也没有TLS/媒体/真实推送/大群。脚本刻意每条发送间隔10ms，发完用时不能当吞吐上限。原始记录：artifacts/memory.json、load.log（gitignored）。

早期脚本把同一用户200个resume瞬间发送，触发120帧/秒限制，12000/20000使脚本正确失败；改为建连错开12ms，**没有放宽服务端限流**，之后完整负载多次通过。20–40MiB目标在这组小负载满足，不保证所有使用场景；长历史、16KiB长消息、慢客户端/图片并发、TLS/代理和真实推送仍需测。

复跑：
```bash
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o bin/quietchat ./cmd/server
go build -o bin/loadtest ./cmd/loadtest
python3 scripts/measure.py
```

## 4. 容器边界与运行

Dockerfile为scratch多阶段静态构建，非root、公开CA、内置healthcheck；Compose128m内存硬限制、64MiB Go软限制、只读根、cap_dropALL、named数据卷、localhost端口。当前box**没有Docker可执行程序，因此镜像未实际构建、Compose未启动、镜像体积未测**。不能用程序大小冒充镜像大小；上线机器应构建后inspect镜像并测cgroup峰值/HK余量。

ELF无PT_INTERP（CGO-free静态）；SHA256 `aa85470fae486e085405efbce54bbb1a49edce5588461938936dd773dbbb046e`。

本地运行/secret引导见README；中文基础API见api.md，增补见extensions.md，推送凭据挂载见push.md，Flutter接线见flutter.md。正式部署前需核对现有Traefik网络/resolver/域名，不能直接套例子改其他服务。

## 5. 剩余工程 / Flutter优先级

先把真实Flutter登录→本地outbox→两设备文字/断网补齐/编辑撤回/隐私已读接通，再接群/媒体/列表状态，最后小米真机后台/锁屏推送与release/profile动画。不能把合成demo当真实通信测试。

上线前仍需浏览器安全会话/可信代理限流、密码轮换/禁用账号、媒体尺寸时长/缩略图API/扫描/孤儿清理、事件/审计/作业保留、备份恢复、OG图片安全代理、实际Docker和HK压力测试。无Bot token/webhook/longpoll服务，无投票计票/关闭worker，无E2EE。涉及密钥只在服务器secret或用户批准的安全渠道配置，不进Git/镜像/聊天。
