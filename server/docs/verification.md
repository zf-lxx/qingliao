# 本地验收与资源实测

实测完成：2026-11-10 22:28:53 +0800（Asia/Shanghai）。仅在共享 box 的 Linux x86_64 上运行，没有登录 HK，没有部署/推仓库，没有修改 Flutter demo。

## 自动测试

- 15 个集成/核心测试，`go test ./... -count=1 -cover` 通过；internal/chat 覆盖率见 test.log（本次 72.4%，cmd 入口/压测程序不计入该覆盖数字）。
- `go test -race ./... -count=1` 通过（约36.7秒）；`go vet ./...` 通过。
- 覆盖：邀请/登录/设备撤销、单次邀请并发、direct幂等、40并发消息seq、编辑/撤回/反应/已读、群角色/新加入历史边界、媒体越权/Range/大小配额/头像、WS重连与ACK/一次性ticket/Origin、离线分页与消息重启幂等、图片/语音/文件类型、无密钥推送作业留存、小米本地HTTP mock。
- **没有**真实小米推送测试，没有声称语音能被各端解码（测试Ogg仅校验MIME路径），没有手机帧率/功耗、生产故障注入/备份恢复、完整安全审计。

## RSS（不是Go堆，不是容器内存）

命令：`CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o bin/quietchat ./cmd/server && go build -o bin/loadtest ./cmd/loadtest && python3 scripts/measure.py`

环境：Go1.27.3、modernc SQLite1.62.0、GOMAXPROCS=2、GOMEMLIMIT=64MiB；box约16GiB物理内存，共享机器，不是HK那台2核1G。`/proc/PID/status`每100ms采样，数据库/压测客户端独立进程；DB启用WAL、synchronous=FULL、单连接、2MiB页缓存。

| 指标 | 实测 |
|---|---:|
| 空载启动后RSS | 11648 KiB / 11.38 MiB |
| 200 WS + 100条文字的采样峰值RSS | 30676 KiB / 29.96 MiB |
| 内核VmHWM | 30684 KiB / 29.96 MiB |
| 最后10秒RSS中位数 | 30672 KiB / 29.95 MiB |
| 静态amd64程序 | 11985056 bytes / 11.43 MiB |
| 同程序gzip（不是镜像） | 5154278 bytes / 4.92 MiB |

实际负载：**200条WebSocket复用同一个接收账号/会话**，不是200个独立真实用户；另一个账号发100条文字，全部20000次扇出事件收到，错误0，连接保持25秒。loopback、无TLS、无媒体、无真实推送；约1.25秒内发完100条（包括脚本每条sleep10ms），不能解释成吞吐极限或公网延迟。

第一次用同一用户瞬间发200个resume触发120帧/秒保护，只收到12000/20000，压测正确失败；已将压测建连错开12ms，**未放宽服务端限流**，之后完整200连接两轮通过。实际数据在 artifacts/memory.json 和 load.log，可复跑；测试服务已正常停止。

## 镜像 / 部署边界

- Dockerfile scratch、多阶段CGO_ENABLED=0、非root、公开CA、内置healthcheck；Compose128m硬限制/64MiB Go软限制，named volume持久化，localhost端口。
- 当前box没有Docker可执行程序，所以 **Docker镜像未构建、compose未启动、镜像大小未实测**。11.43MiB是程序大小，不冒充镜像大小；预计scratch接近程序加CA/层开销，仅是估算。上线机器应执行 `docker compose build` 后 `docker image inspect quietchat:local --format '{{.Size}}'`，再实测容器峰值与HK余量。
- ELF程序头无PT_INTERP（静态），二进制SHA256：`b31aa0e1c67e900d947c47f35fd4c6c60c9e282c280e50891a8eeab8fef9cbc5`。
- 内存目标20–40MiB在这组小负载下满足，但未给出容量保证。SQLite串行写、事件日志无限保留/作业积累、媒体并发/网络慢消费者、TLS/代理开销均需后续测。

## 剩余工程

这是一期开源前的本地消息内核，不是可直接公开上线的成品：R2/S3只留接口（未知storage配置明确拒绝）、Bot仅接口、无E2EE/通话；小米模板/资质/签名待真实接入；浏览器安全会话、可信代理限流、密码轮换/账号禁用、媒体尺寸/时长/缩略图元数据/安全扫描、事件/孤儿/作业清理、数据库/附件备份恢复和容器构建均待补齐。

Flutter下一步见 flutter.md：先接邀请登录→持久outbox→双机文字→重连补齐/已读，再接群/媒体，再在小米真机锁屏测推送和release/profile帧耗时。不能用当前合成动画演示代替这些验收。
