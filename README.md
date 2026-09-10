# codex-newapi

一套可迁移的 Docker Compose 部署方案，包含：

- WireGuard VPN（固定服务器出口 IP）
- CLIProxyAPI（Codex OAuth → OpenAI 兼容接口）
- NewAPI（统一 API 网关、用户与额度管理）
- PostgreSQL + Redis
- Nginx HTTPS：博客首页与 `/v1/*` API 路由
- 初始化、备份、恢复和升级脚本

## 架构

```text
WireGuard 客户端 ── UDP 51820 ── WireGuard ── 固定服务器出口

OpenCode / SDK ── HTTPS/HTTP 3000 ── NewAPI
                                      ├── PostgreSQL
                                      ├── Redis
                                      └── CLIProxyAPI ── Codex OAuth
```

## 快速开始

```bash
git clone https://github.com/it-worker-tango/codex-newapi.git
cd codex-newapi
cp .env.example .env
```

编辑 `.env`，至少填写：

- `SERVER_PUBLIC_IP`：新服务器公网 IP
- `TZ`：时区
- WireGuard 客户端数量、DNS 等参数

然后执行：

```bash
./scripts/init.sh
docker compose pull
docker compose up -d
sudo ./scripts/setup-nginx.sh
docker compose ps
```

初始化脚本会自动生成数据库、Redis、NewAPI 会话、CPA API 和管理密钥。真实密钥只写入本机 `.env` 与 `data/`，不会进入 Git。

详细操作见 [迁移与部署教程](docs/DEPLOYMENT.md)。

## 教程目录

- [当前部署与迁移指南](docs/DEPLOYMENT.md)：适用于本仓库的 WireGuard + CPA + NewAPI 一体化方案。
- [CLIProxyAPI + NewAPI 首次部署教程](docs/archive/CLIProxyAPI-NewAPI教程.md)：之前编写的详细操作记录，包含渠道设置、授权、接口测试和运维说明；使用独立的旧版 Compose 布局。公开版已去除包含个人信息的截图。

## 默认端口

| 端口 | 协议 | 服务 | 建议 |
|---:|---|---|---|
| 51820 | UDP | WireGuard | 云安全组放行 |
| 80/443 | TCP | Nginx | 博客首页与 HTTPS API；云安全组放行 |
| 3000 | TCP | NewAPI | 仅绑定 `127.0.0.1`，不对公网开放 |
| 8317 | TCP | CLIProxyAPI | 仅绑定 `127.0.0.1`，不对公网开放 |
| 8085/1455/54545/51121/11451 | TCP | OAuth 回调 | 仅授权期间按需放行 |

## 备份与恢复

```bash
./scripts/backup.sh
sudo ./scripts/restore.sh backups/codex-newapi-YYYYMMDD-HHMMSS.tar.gz
```

备份包含数据库、OAuth 凭据、WireGuard 配置及本机密钥，务必加密保存，禁止提交到 GitHub。

## 安全提醒

- 不要提交 `.env`、`data/`、`backups/` 或 OAuth JSON。
- 生产环境应为 NewAPI 配置域名和 HTTPS。
- CPA 8317 不应直接暴露公网。
- SSH 建议使用密钥登录并关闭密码认证。
- 使用前请遵守云厂商、上游账号和所在地的适用条款。
