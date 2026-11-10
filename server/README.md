# 轻聊 · Go 消息内核（一期本地后端）

Telegram 手感方向的独立聊天项目，不接 Telegram 服务器。本目录是可运行的 Go 后端内测基座，不是已完成的聊天 App。Go 1.27.3 + modernc.org/sqlite（CGO-free）+ gorilla/websocket + bcrypt；一进程、SQLite WAL、云端明文聊天（无 E2EE）。

## 本地运行

```bash
cd /workspace/tg-chat/server
mkdir -p secrets
umask 077
openssl rand -hex 24 > secrets/bootstrap_password
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o bin/quietchat ./cmd/server
CHAT_ADMIN_HANDLE=admin CHAT_ADMIN_PASSWORD_FILE="$PWD/secrets/bootstrap_password" \
CHAT_ADDR=127.0.0.1:8088 CHAT_ORIGIN=http://localhost:4318 ./bin/quietchat
```

密码只在本地 secret 文件；不要把密码/token 发到聊天、Git 或镜像中。首次引导后保持数据卷，环境变量不会重置管理员密码。停止服务 SIGTERM。

```bash
go test ./... -count=1 -cover
go test -race ./... -count=1
go vet ./...
go build -o bin/loadtest ./cmd/loadtest
python3 scripts/measure.py
```
压测脚本只绑定 loopback 18088，创建隔离数据库和随机测试密码，结束会停止测试服务。结果写 artifacts/memory.json、load.log。不要对生产地址跑压测。

## Docker Compose（待 Docker 环境实测）

```bash
cp .env.example .env
mkdir -p secrets
umask 077
openssl rand -hex 24 > secrets/bootstrap_password
# secret 内容不输出；非 root 容器需要能读取 bind-mounted secret。
# Compose 本地 file secret 的 mode/uid 不一定重映射；私有目录 0700 + 文件0444：
chmod 700 secrets
chmod 444 secrets/bootstrap_password
docker compose up -d --build
docker compose logs --tail 50 chat
```
Compose 限内存128m、Go软内存64MiB、CPU0.75、非 root、只读根文件系统、cap_drop ALL。数据/附件在 named volume chat-data；没有 Redis/PostgreSQL/媒体转码。scratch 镜像只含静态程序、公开 CA、空数据目录。构建镜像/compose 启动尚未在本 box 验证（无 Docker 可执行程序），不要把二进制大小当已测镜像大小。

Traefik 用 `compose.traefik.example.yml` 作为**待核对**覆盖文件：填写现有网络、resolver、域名及 CHAT_ORIGIN，再合并；本次没有访问香港服务器、没有改现有 Traefik、没有部署或推 GitHub。端口默认只映射本地127.0.0.1；公开必须 HTTPS/WSS。

文件 secret 示例针对 Linux Compose bind mount；生产推荐管理者显式配置 secret 权限/uid（65532）。启动前检查容器确实可读 bootstrap，之后移除 bootstrap。Xiaomi API key 配置留空，不要把真实 `.env` 提交。

## 功能与协议

邀请注册/会话撤销/设备推送 token；用户资料头像；双人/群/角色；文字图片语音文件、回复编辑撤回反应；会话 seq/幂等发送；按用户持久事件补齐、WS ACK、typing/presence；已读/未读；鉴权媒体、磁盘配额；事务型离线推送作业和小米 HTTP 模块；Bot 扩展契约（仅接口）；UTF-16富文本/内联键盘、多置顶、SSRF防护链接预览、群审核/审计；跨设备未读/@提醒/文件夹/置顶归档/静音/草稿；已读全局+个人互惠开关。投票/回调仅 schema、校验和501 stub，不是假装已实现。

推送接入：[docs/push.md](docs/push.md)（MiPush/FCM已编码、无凭据禁用；无真实送达实测）。

新增功能协议：[docs/extensions.md](docs/extensions.md)（富文本、审核、列表状态、已读隐私；投票与Bot回调明确501）。

完整中文协议：[docs/api.md](docs/api.md)。实测报告：[docs/verification.md](docs/verification.md)。Flutter接线：[docs/flutter.md](docs/flutter.md)。

## 持久化与备份

生产必须先做恢复演练。本地阶段可**停服务**后备份整个 data 卷（DB、WAL、SHM、media 一起），不要热拷贝单个 chat.db。无自动保留/清理、无线上备份工具；媒体配额不包含 DB/events，需额外磁盘监控。多实例部署、E2EE、R2预签名、真正小米推送/Android UI都不是已完成能力。
