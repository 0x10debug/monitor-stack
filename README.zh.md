# VPS 自托管监控栈 — 可用性、性能与告警

一套完整的 VPS 自托管监控方案，整合 **Uptime Kuma** 实现可用性监控、**Beszel** 实现性能指标采集、**CrowdSec** 集成实现安全事件追踪。通过 Docker 几分钟内完成部署，支持 Telegram、Discord、Email、Slack 多渠道告警，可从单一面板监控无限远程节点。无 SaaS 依赖，无月费 — 完全掌控你的 VPS 监控。

> 属于 [0x10debug](https://github.com/0x10debug) VPS 工具套件的一部分。

## 包含组件

| 组件 | 用途 | 端口 | 数据路径 |
|------|------|------|----------|
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | 可用性与运行状态监控 | 3001 | `/data/uptime-kuma` |
| [Beszel Hub](https://github.com/henrygd/beszel) | 性能指标与系统资源监控 | 8090 | `/data/beszel` |
| [CrowdSec](https://github.com/crowdsecurity/crowdsec) | 安全监控（集成） | — | 数据模板 |
| 告警模板 | Telegram、Discord、Email、Slack | — | `/data/monitor-alerts` |
| 状态页 | 自包含 HTML 状态页 | — | 可配置 |

## 快速开始

### 前置条件

- 运行 Linux 的 VPS（推荐 Ubuntu 22.04+）
- 已安装 Docker 和 Docker Compose
- 指向服务器的域名（用于 Caddy 配置 HTTPS）
- Root 或 sudo 权限

### 1. 克隆仓库

```bash
git clone https://github.com/0x10debug/monitor-stack.git
cd monitor-stack
```

### 2. 部署监控栈

```bash
sudo ./mb monitor deploy
```

CLI 将自动：
- 创建 `mb-proxy` Docker 网络
- 生成 `.env` 文件（会提示输入域名）
- 启动 Uptime Kuma 和 Beszel Hub 容器
- 在 `/data/` 下创建数据目录

### 3. 设置管理员账号

首次访问 `http://localhost:3001` 打开 Uptime Kuma，创建管理员账号。

访问 `http://localhost:8090` 打开 Beszel Hub，注册并开始添加系统。

### 4. 添加远程节点

```bash
sudo ./mb monitor add-host
```

按提示在任意远程服务器上安装 Beszel agent。

### 5. 配置告警

```bash
sudo ./mb monitor alert setup
sudo ./mb monitor alert test
```

## 使用方法

所有操作通过 `mb` CLI 完成：

```bash
# 部署监控栈
mb monitor deploy

# 查看栈状态
mb monitor status

# 添加远程监控节点
mb monitor add-host

# 查看 Uptime Kuma 中添加监控的说明
mb monitor add-service

# 配置告警渠道（telegram / discord / email / slack）
mb monitor alert setup

# 发送测试告警
mb monitor alert test

# 列出已配置的告警渠道
mb monitor alert list

# 部署公开状态页
mb monitor status-page

# 查看 CrowdSec 安全集成说明
mb monitor security-dashboard

# 更新所有服务到最新镜像
mb monitor update

# 显示帮助
mb monitor help
```

## 告警渠道

`alerts/` 目录中提供了预配置模板：

| 渠道 | 模板文件 | 配置字段 |
|------|----------|----------|
| Telegram | `alerts/telegram.json` | `bot_token`、`chat_id` |
| Discord | `alerts/discord.json` | `webhook_url` |
| Email | `alerts/email.json` | `smtp_host`、`smtp_port`、`username`、`password`、`from`、`to` |
| Slack | `alerts/slack.json` | `webhook_url`、`channel` |

配置文件存储在 `/data/monitor-alerts/<channel>.json`，权限为 `0600`。

## 状态页

`dashboards/status-page.html` 提供了一个自包含的 HTML 状态页模板，使用纯 CSS，无外部依赖，可独立运行：

```bash
sudo ./mb monitor status-page
```

编辑文件，将 `{{SERVICE_NAME}}` 替换为你的服务名称，并根据实际状态数据自定义服务条目。

## CrowdSec 集成

`dashboards/crowdsec-dashboard.json` 文件定义了 CrowdSec 安全指标的数据模式：

- **blocked_ips_today** — 今日被封禁的 IP 数
- **top_attacker_countries** — 按攻击量排名的国家
- **attack_types** — 检测到的攻击场景
- **alerts_last_24h** — 过去 24 小时的安全告警

运行 `mb monitor security-dashboard` 查看集成说明。

## 常见问题

### 可以用其他反向代理替代 Caddy 吗？

可以。监控栈加入了一个名为 `mb-proxy` 的外部 Docker 网络。任何能路由到 `uptime-kuma:3001` 和 `beszel-hub:8090` 容器的反向代理（nginx、Traefik、Caddy）都可以使用。`compose/Caddyfile.example` 提供了 Caddy 配置示例。

### 如何监控防火墙后面的服务器？

Uptime Kuma 需要被监控的端口可从 Uptime Kuma 主机访问。Beszel agent 主动向 hub 发起出站连接，因此被监控节点无需入站防火墙规则 — 只需 hub 可达即可。

### 数据存储在本地吗？

是的。所有数据存储在你的 VPS 上，路径为 `/data/uptime-kuma` 和 `/data/beszel`。不会发送任何数据到第三方服务。告警配置存储在 `/data/monitor-alerts/`。

### 可以监控多少个节点？

没有硬性限制。Uptime Kuma 和 Beszel 都是轻量级服务。单台 VPS 实际可监控数十个节点。大规模部署时建议适当增加 VPS 资源。

### 如何备份监控数据？

备份数据目录：

```bash
sudo tar -czf monitor-backup-$(date +%F).tar.gz /data/uptime-kuma /data/beszel /data/monitor-alerts
```

将归档存储到异地（如 S3 或其他服务器）。

## 文档

- [部署指南](docs/setup-guide.md) — 逐步部署说明
- [添加主机](docs/add-hosts.md) — 如何添加远程服务器进行监控
- [告警配置](docs/alert-configuration.md) — 如何配置告警渠道
- [安全监控](docs/security-monitoring.md) — 如何集成 CrowdSec

## 相关仓库

- [0x10debug/vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — VPS 初始化设置与加固
- [0x10debug/compose-recipes](https://github.com/0x10debug/compose-recipes) — 常用服务的 Docker Compose 配方
- [0x10debug/network-toolkit](https://github.com/0x10debug/network-toolkit) — 网络诊断与测试工具
- [0x10debug/security-audit](https://github.com/0x10debug/security-audit) — 安全审计与加固脚本

## 许可证

[MIT](LICENSE) — Copyright (c) 2026 [0x10debug](https://github.com/0x10debug)
