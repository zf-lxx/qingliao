# 香港部署（轻聊内测）

核验日期：2026-11-10 23:52（Asia/Shanghai，北京时间）。这是已部署的独立聊天服务，不连接 Telegram；无 E2EE，仅供邀请制内测。APK/真机推送不属于本页已验证内容。

## 线上地址

- App 的服务器地址填 `https://qingliao.zhufu.de5.net`，不要加 `/v1` 或 `/ws`。
- HTTP API：`https://qingliao.zhufu.de5.net/v1`；WebSocket：`wss://qingliao.zhufu.de5.net/v1/ws`。
- 健康检查例外：`GET /healthz`（不是 `/v1/healthz`）。
- DNS A：`189.1.229.227`，对应 HW_HK。`chat.zhufu.de5.net` 当前 CNAME 到第三方 CDN，不能用它直连本机；此次未修改 DNS。
- 使用现有 Traefik 外部网络 `traefik`、HTTPS entrypoint `https`、resolver `le`。公网验证返回有效的 Let's Encrypt `*.zhufu.de5.net` 证书（复用现有通配符证书，并非声称新签了一张）；证书到期 2027-01-08 10:13:56（Asia/Shanghai）。HTTP 重定向到 HTTPS，服务容器不映射宿主机公网端口。

## 服务布局与权限

- 宿主机：HW_HK（x86_64）；目录 `/opt/qingliao`，权限 0700。
- Compose：`/opt/qingliao/docker-compose.yml`；服务名 `chat`，容器 `qingliao`。
- 环境配置与初始管理员密码：`/opt/qingliao/.env`，root:root 0600。首次管理员 handle 为 `admin`，密码只从该文件的引导字段读取，不写进文档或 Git。
- 引导完成后已从 Compose 的容器环境中移除 `CHAT_ADMIN_PASSWORD`；重建不重新创建或重置管理员。`.env` 中的原始引导字段仅留作管理员本地取用。
- 管理员初始配置的 box 副本：`/workspace/tg-chat-secrets/admin.env`，0600；目录 0700。用户应仅在受信任终端本地打开，不通过聊天发送内容。
- 邀请码：香港 `/opt/qingliao/invites.txt`；box `/workspace/tg-chat-secrets/invites.txt`，均 0600。5 个未使用、每个限一次、有效期 720 小时；管理员登录后可调用 `POST /v1/invites` 另行生成。不要提交这些文件。
- 持久卷 `qingliao_chat-data` -> `/data`，保存 SQLite/WAL 和媒体。以 UID/GID 65532 非 root 运行，只读根文件系统、无额外 capabilities、no-new-privileges。
- restart `unless-stopped`；内存硬上限 96MiB，`GOMEMLIMIT=48MiB`，`GOMAXPROCS=2`，CPU 0.75，pids_limit 100。
- 媒体配额 536870912 字节（512MiB）；单文件上限 20971520 字节（20MiB）。配额不包括 SQLite、持久事件和 Docker 日志，仍需磁盘监控。
- `READ_RECEIPTS_ENABLED=true`；Mi Push/FCM 未配置、未启用；没有真实手机锁屏推送验收。

## 本次产物与验证

- 部署源码提交：`b07a28b55ba283ae04e069179ced4dac541fd0d3`。运行镜像 `qingliao:20261110-b07a28b`，镜像大小 12,936,217 字节；镜像 ID `sha256:633bb9aa4d01965c948df940da142d7a083e0d21da2ddfc01705a2de6ca554e6`。
- box 无 Docker，在 box 以 CGO_ENABLED=0、GOOS=linux、GOARCH=amd64 编译，用 CA bundle + scratch 最小上下文在香港构建；不在小内存 VPS 上运行 Go 编译器。
- 编译包传输两端 SHA256 相同：`b091a802be9e472b20d5ca96c273b49858588abd202119032fc7549613598575`。
- 公网 HTTPS `GET /healthz` -> 200 `{"ok":true}`；证书验证通过。直接指向香港 IP 并保留域名 SNI 的请求也通过。
- 两个额外邀请码注册了两个明确标注为“部署测试账号（非真人）”的账号，未消耗上述 5 个用户邀请码。
- 两个带 Bearer 鉴权的公网 WSS 连接均返回 HTTP 101 + hello；A 通过 WS 发送，收到 stored ACK，B 实时收到同一 message ID。
- B 断线后发送另一条消息，B 重连通过 sync.resume 补到同一 message ID。
- 容器移除引导密码并重建后，原账号可登录，会话和两条消息仍存在。测试账号保留明确标签，所有验证会话已注销，没有删除用户数据。
- 空闲 `docker stats --no-stream` 实测约 6.871MiB / 96MiB（7.16%），启动瞬间曾为 8.129MiB；这不是压测峰值或长期容量承诺。Docker 健康状态 healthy。

## 更新流程

1. 在可信构建机确认 Git 工作区与待部署提交一致，先运行 `go test ./...` 与 `go vet ./...`。不要将其他并行客户端改动混入服务端提交；遵循仓库协作约定。
2. 从 server 目录交叉编译：

   ```sh
   CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o /path/to/build/quietchat ./cmd/server
   ```

3. 将静态二进制、公开 CA bundle、空 data 目录和下面的 Dockerfile 打包，通过已有受权 Komari admin task exec 文件传输至 `/opt/qingliao/build/`，两端比对 SHA256。不把 `.env`、邀请码、SQLite 或媒体放进构建上下文。

   ```dockerfile
   FROM scratch
   COPY ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
   COPY quietchat /quietchat
   COPY --chown=65532:65532 data /data
   USER 65532:65532
   ENTRYPOINT ["/quietchat"]
   HEALTHCHECK --interval=30s --timeout=3s --start-period=15s CMD ["/quietchat","healthcheck"]
   ```

4. 维护窗口先停服务，再备份**整个** `qingliao_chat-data`（DB、WAL、SHM、media 一起），以及单独安全备份 `.env` 和 Compose；备份权限 0600。不要热拷贝单个数据库文件，不要 `docker compose down -v`。本次未实施自动备份或恢复演练，开放更多用户前应补做恢复演练。
5. 香港 `docker build -t qingliao:<date>-<sha> /opt/qingliao/build`；仅替换 `/opt/qingliao/.env` 的 `CHAT_IMAGE`，保留其他配置及 0600 权限。不要重新启用引导密码环境变量。
6. `cd /opt/qingliao && docker compose up -d --pull never`，确认 healthy。保留上一版镜像用于回滚，不做未获授权的镜像清理。
7. 从外网检查 `curl -f https://qingliao.zhufu.de5.net/healthz`、登录、WSS 101/hello、双账号消息/离线补齐；查看 `docker stats --no-stream qingliao`。使用单独测试邀请码，不消耗用户邀请码。
8. 如需回滚，将 `CHAT_IMAGE` 改回旧 tag 后重建；若 schema 不兼容则必须使用经过验证的完整备份恢复，不能假定降级二进制足够。

## 当前边界

- Traefik 后的应用不信任 X-Forwarded-For，应用层登录/注册限额会共享代理 IP（20 次/分钟）；目前小圈子内测可用，大规模开放前补可信代理和边缘限流，不能直接信任任意转发头。
- 当前无密码重置、无 E2EE、无事件日志清理/自动媒体孤儿清理、无正式备份恢复演练；禁用推送不代表已有厂商送达保证。请结合 `api.md`、`verification.md` 查看实现限制。
