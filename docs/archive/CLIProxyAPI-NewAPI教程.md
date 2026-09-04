# CLIProxyAPI + NewAPI 一体化部署教程（首次部署记录）

> 本文是 2026 年 8 月首次部署时的操作记录，使用旧版目录与 Compose 布局。新服务器部署或迁移请优先使用 [当前部署迁移指南](../DEPLOYMENT.md)，不要混用两套目录和配置。
>
> 公开版不包含原始截图：截图中含账号邮箱、个人会话列表及浏览器标签信息。文字操作步骤保留；原始图文版仍保存在本地。命令和页面名称记录的是当时版本，后续版本可能不同。

本文记录在 Ubuntu 24.04 云服务器上，通过 Docker Compose 部署 CLIProxyAPI（下文简称 CPA）与 NewAPI，并使用 ChatGPT/Codex 设备码授权接入模型的完整过程。

> 本文示例使用 `YOUR_SERVER_IP` 和占位密钥。不要把真实密码、OAuth 文件、API Key 或 `.env` 上传到 GitHub。

## 一、最终架构

```text
客户端 / OpenAI SDK
        │  http://YOUR_SERVER_IP:3000/v1
        ▼
     NewAPI ───── PostgreSQL
        │        Redis
        │  Docker 内网 http://cli-proxy-api:8317
        ▼
 CLIProxyAPI ─── Codex OAuth
```

本次部署使用以下端口：

| 服务 | 端口 | 用途 |
|---|---:|---|
| NewAPI | 3000/TCP | 管理后台及对外 OpenAI 兼容 API |
| CLIProxyAPI | 8317/TCP | CPA API 与管理接口 |
| OAuth 回调 | 8085、1455、54545、51121、11451/TCP | 不同提供商可能使用的授权回调 |

PostgreSQL 和 Redis 只加入 Docker 私有网络，不映射到公网。

## 二、准备服务器

服务器建议至少 2 核、2 GB 内存，系统为 Ubuntu 22.04/24.04。先在腾讯云防火墙/安全组放行实际需要的端口，再安装 Docker：

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 openssl
sudo systemctl enable --now docker
sudo mkdir -p /opt/ai-gateway/{cliproxy/auths,cliproxy/logs,newapi/data,newapi/logs}
sudo chown -R "$USER":"$USER" /opt/ai-gateway
cd /opt/ai-gateway
```

生产环境建议只公开 80/443，并用 Nginx 或 Caddy 为 NewAPI 配置 HTTPS；8317 最好仅允许管理 IP 访问。

## 三、准备 Docker Compose

将本教程同目录中的 [compose.yaml](./compose.yaml) 上传到 `/opt/ai-gateway/compose.yaml`。

创建随机数据库密码、Redis 密码和会话密钥：

```bash
cat > .env <<EOF
POSTGRES_PASSWORD=$(openssl rand -hex 24)
REDIS_PASSWORD=$(openssl rand -hex 24)
SESSION_SECRET=$(openssl rand -hex 32)
EOF
chmod 600 .env
```

## 四、配置 CLIProxyAPI

创建 `/opt/ai-gateway/cliproxy/config.yaml`。不同版本字段可能调整，请以 CLIProxyAPI 官方示例为准：

```yaml
host: 0.0.0.0
port: 8317
auth-dir: /root/.cli-proxy-api

api-keys:
  - "替换为一段随机的上游调用密钥"

remote-management:
  allow-remote: true
  secret-key: "替换为另一段随机管理密钥"
```

可用下面的命令生成两段密钥：

```bash
openssl rand -hex 32
openssl rand -hex 32
chmod 600 cliproxy/config.yaml
```

启动全部服务：

```bash
docker compose pull
docker compose up -d
docker compose ps
```

正常情况下，`cli-proxy-api`、`new-api`、`postgres` 和 `redis` 均为 running，其中数据库与 Redis 会显示 healthy。

## 五、初始化 NewAPI

浏览器打开：

```text
http://YOUR_SERVER_IP:3000
```

按页面引导创建管理员账号并完成初始化。


完成初始化后，进入「渠道」页面，新建一个 OpenAI 类型渠道：

- 名称：`CLIProxyAPI-Codex`
- 类型：OpenAI
- Base URL：`http://cli-proxy-api:8317`
- 密钥：填写 CPA `config.yaml` 中 `api-keys` 的值
- 分组：`default`
- 测试模型：例如 `gpt-5.4-mini`
- 模型：从 CPA 的 `/v1/models` 获取，或在页面中选择实际可用模型

这里必须使用 Docker 服务名 `cli-proxy-api`，不能填写 `127.0.0.1`；因为 NewAPI 与 CPA 位于不同容器中。

## 六、完成 Codex 设备码授权

如果授权页面提示需要开启设备代码授权，请登录 ChatGPT，进入「设置 → 安全防护 → 账号安全与登录」，打开「为 Codex 启用设备代码授权」。


然后在服务器执行 CPA 的 Codex 登录命令。具体参数以当前项目 README 为准，例如：

```bash
cd /opt/ai-gateway
docker compose exec cli-proxy-api /CLIProxyAPI/CLIProxyAPI --codex-login --no-browser
```

终端会输出设备授权地址与一次性代码。在本机浏览器打开地址、输入代码并确认授权：


授权成功后，OAuth JSON 会保存在宿主机的：

```text
/opt/ai-gateway/cliproxy/auths/
```

该目录相当于账号凭据，必须限制权限并纳入加密备份，绝不能公开。

## 七、创建 NewAPI 客户端密钥并测试

在 NewAPI 后台进入「令牌/API Key」，创建一个令牌。建议按实际用途设置额度、可用模型、有效期及 IP 白名单。

客户端 Base URL：

```text
http://YOUR_SERVER_IP:3000/v1
```

客户端 API Key 使用 NewAPI 生成的 `sk-...` 密钥，而不是 CPA 的内部密钥。

用 Responses API 测试完整链路：

```bash
curl http://YOUR_SERVER_IP:3000/v1/responses \
  -H 'Authorization: Bearer sk-你的NewAPI密钥' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-5.4-mini",
    "input": "Reply with exactly OK"
  }'
```

也可用 Chat Completions 接口：

```bash
curl http://YOUR_SERVER_IP:3000/v1/chat/completions \
  -H 'Authorization: Bearer sk-你的NewAPI密钥' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-5.4-mini",
    "messages": [{"role":"user","content":"你好"}]
  }'
```

## 八、接入常见客户端

在支持自定义 OpenAI 接口的软件中填写：

- API 类型：OpenAI Compatible
- Base URL：`http://YOUR_SERVER_IP:3000/v1`
- API Key：NewAPI 创建的 `sk-...`
- Model：NewAPI 渠道中已启用的模型名

NewAPI/CPA 是 AI API 网关，不是 Clash 节点协议，因此不能作为 Clash Verge 的代理节点导入。若需要固定出口 IP 的全局网络代理，应另外部署 WireGuard、Hysteria2 或其他合规的网络隧道；两类服务用途不同。

## 九、日常运维

查看状态与日志：

```bash
cd /opt/ai-gateway
docker compose ps
docker compose logs --tail=100 new-api
docker compose logs --tail=100 cli-proxy-api
```

升级：

```bash
cd /opt/ai-gateway
docker compose pull
docker compose up -d
docker image prune
```

备份至少应包含：

```text
/opt/ai-gateway/.env
/opt/ai-gateway/compose.yaml
/opt/ai-gateway/cliproxy/config.yaml
/opt/ai-gateway/cliproxy/auths/
Docker volume: postgres-data
```

备份 PostgreSQL：

```bash
docker compose exec -T postgres pg_dump -U newapi newapi > newapi-$(date +%F).sql
```

## 十、安全清单

- 为域名配置 HTTPS，避免通过明文 HTTP 传输管理密码与 API Key。
- 云安全组只放行必需端口；CPA 8317 优先限制为服务器内网或管理 IP。
- SSH 使用密钥登录，关闭密码登录；任何曾在聊天或截图中出现的密码都应立即更换。
- CPA 内部 API Key、管理密钥、OAuth JSON 与 NewAPI 客户端 Key 分开管理。
- 为 NewAPI 用户设置额度、模型范围、IP 白名单与到期时间。
- 定期检查容器日志、调用日志、磁盘占用，并更新 Docker 镜像。
- 使用服务前确认符合云厂商、OpenAI/ChatGPT 账号及所在地的服务条款和法律要求。

## 参考资料

- [CLIProxyAPI 官方仓库](https://github.com/router-for-me/CLIProxyAPI)
- [NewAPI 官方仓库](https://github.com/QuantumNous/new-api)
- [NewAPI 官方文档](https://docs.newapi.ai/)

