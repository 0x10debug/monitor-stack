# Grafana 仪表盘模板

monitor-stack 提供四套 Grafana 仪表盘 JSON 模板，覆盖 VPS 系统指标、安全事件、可用性探测和日志聚合。所有模板符合 Grafana 11.x schema，通过 provisioning 自动加载，也支持手动导入。

> Part of the [0x10debug](https://github.com/0x10debug) VPS tool suite.

## 仪表盘列表

| 仪表盘 | 文件 | 数据源 | 覆盖范围 |
|--------|------|--------|----------|
| VPS 总览 | `vps-overview.json` | Prometheus (node_exporter) | CPU、内存、磁盘、网络、负载、进程、Docker 容器 |
| 安全总览 | `security-overview.json` | Loki + Prometheus | CrowdSec decisions/alerts、auditd 审计、Falco 事件、SSH 登录 |
| 可用性总览 | `availability-overview.json` | Prometheus (blackbox_exporter) | HTTP/TCP/ICMP 探针、SSL 证书过期、响应时间、丢包率 |
| 日志总览 | `logs-overview.json` | Loki + Prometheus | 日志量趋势、错误/警告计数、按服务分组速率、Promtail 状态 |

## 数据源配置

仪表盘依赖两个数据源，通过 `agents/grafana-datasources.yml` 自动配置：

- **Prometheus** — UID `prometheus`，抓取 node_exporter、blackbox_exporter、crowdsec exporter、promtail 指标
- **Loki** — UID `loki`，存储 syslog、auth、auditd、docker、crowdsec、falco 日志流

如果手动配置数据源，请确保 UID 与仪表盘模板变量 `${DS_PROMETHEUS}` 和 `${DS_LOKI}` 对应，或导入后通过面板编辑器重新选择数据源。

## 自动加载（Provisioning）

`compose/grafana.yml` 启动的 Grafana 容器会挂载以下 provisioning 配置：

- `agents/grafana-datasources.yml` → `/etc/grafana/provisioning/datasources/datasources.yml`
- `agents/grafana-dashboards.yml` → `/etc/grafana/provisioning/dashboards/dashboards.yml`
- `dashboards/*.json` → `/var/lib/grafana/dashboards/`

启动后 Grafana 自动发现并加载所有仪表盘，无需手动导入。

## 手动导入

### 方式一：Grafana UI

1. 登录 Grafana（默认 `http://localhost:3000`，用户名 `admin`）。
2. 左侧菜单 → **Dashboards** → **New** → **Import**。
3. 点击 **Upload dashboard JSON file**，选择 `dashboards/` 下的 JSON 文件。
4. 在 **Prometheus** / **Loki** 下拉框中选择已配置的数据源。
5. 点击 **Import**。

### 方式二：Grafana API

```bash
# 设置 Grafana 凭据
export GRAFANA_URL="http://localhost:3000"
export GRAFANA_USER="admin"
export GRAFANA_PASS="admin"

# 导入单个仪表盘
curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -H "Content-Type: application/json" \
  -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -d @dashboards/vps-overview.json

# 批量导入
for f in dashboards/*-overview.json; do
  echo "Importing $f ..."
  curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -H "Content-Type: application/json" \
    -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -d @"$f"
done
```

> 注意：通过 API 导入时，JSON 顶层需要包裹在 `{"dashboard": { ... }, "overwrite": true}` 中。本仓库的模板文件本身就是完整仪表盘对象，可直接用于 provisioning；手动 API 导入时需手动包裹。

## 面板说明

### VPS 总览 (`vps-overview.json`)

| 面板 | 指标 | 说明 |
|------|------|------|
| CPU 使用率 | `100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])))` | 1 分钟平均，阈值 70%/90% |
| 内存使用率 | `1 - MemAvailable / MemTotal` | 阈值 75%/90% |
| 磁盘使用率 | `1 - fs_avail / fs_size` | 排除 tmpfs/overlay |
| 网络流量 | `rate(node_network_*_bytes_total[1m])` | 排除 lo/veth/docker 虚拟接口 |
| Load Average | `node_load1/5/15` | 1/5/15 分钟负载 |
| 进程总数 | `node_processes_pids` | 阈值 300/500 |
| 僵尸进程 | `node_processes_zombies` | 阈值 >0 即告警 |
| 运行中容器 | `container_last_seen` | cadvisor 指标 |
| 停止的容器 | `last_seen` 除非 `memory_usage` | 已停止但未清理的容器 |
| 容器总数 | `count(container_last_seen)` | 运行中 + 停止 |

### 安全总览 (`security-overview.json`)

| 面板 | 数据源 | 说明 |
|------|--------|------|
| 活跃 Decisions 数 | Prometheus | `crowdsec_decisions_active` |
| 最近 Alerts (1h) | Prometheus | `increase(crowdsec_alerts_total[1h])` |
| 封禁 IP 地理分布 | Loki | CrowdSec 日志按 country 聚合，geomap 可视化 |
| 最近审计事件 | Loki | `{job="auditd"}` 实时日志流 |
| 特权命令执行 | Loki | auditd EXECVE 事件按命令聚合 |
| 文件完整性告警 | Loki | 监控 passwd/shadow/sudoers/ssh_host 变更 |
| Falco CRITICAL | Loki | `{job="falco"}` 含 CRITICAL 关键字 |
| Falco WARNING | Loki | `{job="falco"}` 含 WARNING 关键字 |
| SSH 失败登录 | Loki | `{job="auth"}` 含 "Failed password" |
| SSH 成功登录 | Loki | `{job="auth"}` 含 "Accepted password/publickey" |

### 可用性总览 (`availability-overview.json`)

| 面板 | 指标 | 说明 |
|------|------|------|
| HTTP 探针状态 | `probe_success{job=~"blackbox_http.*"}` | UP/DOWN 状态面板 |
| SSL 证书过期天数 | `(probe_ssl_earliest_cert_expiry - time()) / 86400` | 阈值 7/30 天 |
| HTTP 响应时间 | `probe_duration_seconds` | 阈值 2s/5s |
| TCP 端口连通性 | `probe_success{job="blackbox_tcp"}` | OK/FAIL 状态面板 |
| ICMP Ping 延迟 | `probe_duration_seconds{job="blackbox_icmp"}` | 阈值 500ms/1s |
| ICMP 丢包率 | `100 * (1 - avg_over_time(probe_success[5m]))` | 阈值 5%/20% |

### 日志总览 (`logs-overview.json`)

| 面板 | 数据源 | 说明 |
|------|--------|------|
| 日志量趋势（按 job） | Loki | `sum by (job) (rate({job!=""} [5m]))` 堆叠图 |
| 错误日志计数 (1h) | Loki | 匹配 error/panic/fatal |
| 警告日志计数 (1h) | Loki | 匹配 warn/warning |
| 按服务分组的日志速率 | Loki | 按 program 和 container 分组 |
| Promtail 活跃 Tails | Prometheus | `promtail_active_targets` |
| Promtail 日志推送速率 | Prometheus | `rate(promtail_log_lines_total[5m])` |
| 实时日志流 | Loki | 全量日志浏览面板 |

## 自定义修改指南

### 修改面板查询

1. 在 Grafana 中打开仪表盘，点击面板标题 → **Edit**。
2. 在 **Query** 标签页修改 PromQL / LogQL 表达式。
3. 点击 **Apply** 保存。
4. 点击仪表盘顶部 **Save dashboard** 持久化到 Grafana 数据库。

### 修改模板文件

1. 编辑 `dashboards/` 下的 JSON 文件。
2. 修改 `panels` 数组中的 `targets[].expr` 查询表达式。
3. 调整 `fieldConfig.defaults.thresholds` 阈值。
4. 验证 JSON：`python3 -m json.tool dashboards/<file>.json > /dev/null`。
5. 重启 Grafana 容器或等待 provisioning 热加载。

### 添加新仪表盘

1. 在 Grafana UI 中创建新仪表盘并配置面板。
2. 点击 **Share** → **Export** → 下载 JSON。
3. 将 JSON 放入 `dashboards/` 目录。
4. 确保 JSON 包含 `uid` 字段（provisioning 用 uid 去重）。
5. 重启 Grafana，provisioning 自动加载新仪表盘。

### 修改数据源 UID

如果使用非默认的 Prometheus/Loki UID：

1. 编辑 `agents/grafana-datasources.yml` 中的 `uid` 字段。
2. 编辑仪表盘 JSON 中 `templating.list` 的 datasource 变量，或导入后在 UI 重新选择。

## 与监控组件的对应关系

| 仪表盘 | 依赖组件 | compose 模板 | 配置文件 |
|--------|----------|-------------|----------|
| VPS 总览 | node_exporter + cadvisor | （外部部署） | — |
| 安全总览 | CrowdSec + auditd + Falco + Loki | `compose/crowdsec.yml` + `compose/loki.yml` | `agents/auditd-exporter.conf`、`agents/loki-config.yml`、`agents/promtail-config.yml` |
| 可用性总览 | Blackbox Exporter + Prometheus | `compose/blackbox.yml` | `agents/blackbox.yml`、`agents/prometheus-blackbox-targets.yml`、`agents/prometheus-blackbox-rules.yml` |
| 日志总览 | Loki + Promtail | `compose/loki.yml` | `agents/loki-config.yml`、`agents/promtail-config.yml` |

## 部署 Grafana

```bash
# 启动 Grafana（含自动 provisioning）
sudo docker compose -f compose/grafana.yml up -d

# 或与主栈合并
sudo docker compose -f compose/compose.yml -f compose/grafana.yml up -d
```

Grafana 首次启动后，默认用户名 `admin`，密码通过 `GF_SECURITY_ADMIN_PASSWORD` 环境变量配置（见 `compose/.env.example`）。仪表盘和数据源会自动加载。

运行 `mb monitor dashboards` 查看 Grafana 状态和导入指引。
