# 部署、备份与迁移教程

## 1. 新服务器准备

推荐 Ubuntu 22.04/24.04。安装 Docker Engine 与 Compose 插件：

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git openssl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

重新登录 SSH，使 Docker 用户组生效。腾讯云安全组至少放行：

- `22/TCP`：SSH，建议只允许自己的 IP
- `51820/UDP`：WireGuard
- `3000/TCP`：NewAPI；配置 HTTPS 后可改为只放行 80/443

CPA 的 `8317/TCP` 默认仅绑定服务器回环地址，不应在安全组中开放。

## 2. 下载并初始化

```bash
git clone https://github.com/it-worker-tango/codex-newapi.git
cd codex-newapi
cp .env.example .env
nano .env
```

将 `SERVER_PUBLIC_IP` 改为新服务器公网 IP。`WG_PEERS` 是自动生成的 WireGuard 客户端名称，使用英文逗号分隔。

```bash
chmod +x scripts/*.sh
./scripts/init.sh
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

## 3. WireGuard 客户端

首次启动后，配置文件位于：

```text
data/wireguard/peer_macbook/peer_macbook.conf
data/wireguard/peer_iphone/peer_iphone.conf
```

显示二维码：

```bash
docker compose exec wireguard /app/show-peer macbook
```

手机使用 WireGuard 官方客户端扫码，电脑导入对应 `.conf`。连接后访问 IP 检测网站，出口应显示服务器公网 IP。

如果更换服务器公网 IP，修改 `.env` 的 `SERVER_PUBLIC_IP`，删除 `data/wireguard/wg_confs/` 后重启 WireGuard，使服务端和客户端配置重新生成。操作前先备份旧配置。

## 4. NewAPI 初始化

浏览器打开：

```text
http://服务器公网IP:3000
```

按引导创建管理员。进入「渠道」新建 OpenAI 类型渠道：

- 名称：`CLIProxyAPI-Codex`
- Base URL：`http://cli-proxy-api:8317`
- 密钥：`.env` 中的 `CPA_API_KEY`
- 分组：`default`
- 模型：以 CPA `/v1/models` 返回的实际列表为准

容器之间必须使用服务名 `cli-proxy-api`，不能使用 `127.0.0.1`。

## 5. Codex OAuth 授权

先在 ChatGPT 的安全设置中开启 Codex 设备代码授权，然后执行：

```bash
docker compose exec cli-proxy-api \
  /CLIProxyAPI/CLIProxyAPI --codex-login --no-browser
```

按照终端提示，在本地浏览器打开设备授权页面并确认。成功后的 OAuth 文件保存在：

```text
data/cliproxy/auths/
```

该目录包含账号凭据，只能放在加密备份中，不能上传 GitHub。

## 6. OpenCode 配置

在 OpenCode 执行 `/connect`，选择 `Other`，输入自定义 provider ID 和 NewAPI 生成的 `sk-...` 密钥。项目中的 `opencode.json` 可参考：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "newapi/gpt-5.4-mini",
  "provider": {
    "newapi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "My NewAPI",
      "options": {
        "baseURL": "https://你的域名/v1"
      },
      "models": {
        "gpt-5.4-mini": { "name": "GPT-5.4 Mini" },
        "gpt-5.6-sol": { "name": "GPT-5.6 Sol" }
      }
    }
  }
}
```

不要把 API Key 直接写进准备提交的配置文件。

## 7. 备份

服务运行时执行：

```bash
./scripts/backup.sh
```

备份包生成在 `backups/`，包含：

- PostgreSQL 逻辑备份
- `.env` 中的全部密钥
- CPA 配置和 Codex OAuth 文件
- WireGuard 服务端与客户端密钥
- Compose 文件

备份包本身是高度敏感的。建议使用 age、GPG 或加密磁盘保存，并另外保留一份离线副本。

## 8. 更换服务器

旧服务器：

```bash
cd codex-newapi
./scripts/backup.sh
```

将生成的备份包通过 SCP 等安全方式传到新服务器。新服务器克隆仓库后执行：

```bash
git clone https://github.com/it-worker-tango/codex-newapi.git
cd codex-newapi
chmod +x scripts/*.sh
sudo ./scripts/restore.sh /安全路径/codex-newapi-时间.tar.gz
```

恢复后检查：

```bash
docker compose ps
docker compose logs --tail=100 cli-proxy-api
docker compose logs --tail=100 new-api
```

若公网 IP 改变，还需要修改 `.env` 的 `SERVER_PUBLIC_IP` 并重新生成 WireGuard 配置。NewAPI 与 Codex OAuth 数据会随备份恢复；如果上游撤销了 refresh token，则需要重新执行设备码授权。

## 9. 更新

```bash
./scripts/update.sh
```

更新脚本先生成备份，再拉取新镜像并重建容器。生产环境建议将 `latest` 改成经过验证的固定镜像版本，以避免不兼容更新。

## 10. HTTPS 建议

不要长期通过公网 HTTP 传输 NewAPI Key。可以在宿主机或 Compose 中增加 Caddy/Nginx：

```text
api.example.com → 127.0.0.1:3000
```

配置 HTTPS 后，将 `.env` 中 `NEWAPI_BIND` 改为 `127.0.0.1`，仅由反向代理访问 NewAPI。
