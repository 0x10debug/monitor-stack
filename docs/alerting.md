# Alert Notifications with Alertmanager

How to deploy Prometheus Alertmanager for multi-channel alert notifications (Telegram, Slack, Discord) and wire it into the monitor-stack.

## Overview

The monitor-stack alerting layer sits on top of the existing monitoring components (CrowdSec, Loki, Blackbox Exporter, Grafana) and turns their metrics into actionable notifications. Prometheus evaluates alert rules and sends firing alerts to Alertmanager, which groups, inhibits, and dispatches them to your notification channels.

```
┌─────────────┐   fire alert   ┌──────────────┐   route + group   ┌──────────────────────────────────┐
│ Prometheus  │ ─────────────▶ │ Alertmanager │ ────────────────▶ │  Telegram  │  Slack  │  Discord  │
│ (rules)     │                │  (port 9093) │                   └──────────────────────────────────┘
└──────┬──────┘                └──────┬───────┘
       │ scrape                       │ inhibit + silence
       ▼                              ▼
┌──────────────────────────────────────────────┐
│  node_exporter │ Blackbox │ Loki │ CrowdSec  │
└──────────────────────────────────────────────┘
```

## Architecture

1. **Prometheus** scrapes metrics from node_exporter, Blackbox Exporter, Loki, and CrowdSec exporters. It evaluates the alert rules in `agents/prometheus-alert-rules.yml` (plus `agents/prometheus-blackbox-rules.yml` for Blackbox-specific alerts).

2. **Alertmanager** receives firing alerts from Prometheus, groups them by `alertname + service + severity`, applies inhibition rules (critical suppresses warning for the same service), and dispatches notifications to the configured receivers.

3. **Receivers** deliver the notification to your channels:
   - **Telegram** — via a webhook relay that translates the Alertmanager payload into a Telegram `sendMessage` API call (Alertmanager has no native Telegram support).
   - **Slack** — via Alertmanager's native `slack_config` (incoming webhook).
   - **Discord** — via Alertmanager's `slack_config` using Discord's Slack-compatible webhook endpoint (`/slack` appended to the webhook URL).

## Files

| File | Purpose |
|------|---------|
| `compose/alertmanager.yml` | Docker Compose template for Alertmanager (pinned `v0.27.0`, port 9093, healthcheck) |
| `alerts/alertmanager-rules.yml` | Main Alertmanager config: route tree, receivers, inhibition, mute intervals |
| `alerts/alert-templates.tmpl` | Go message templates for Telegram (Markdown), Slack (Block Kit), Discord (embed) |
| `alerts/telegram.yml` | Standalone Telegram receiver snippet (reference) |
| `alerts/slack.yml` | Standalone Slack receiver snippet (reference) |
| `alerts/discord.yml` | Standalone Discord receiver snippet (reference) |
| `agents/prometheus-alert-rules.yml` | Prometheus alert rules for all monitor-stack components |

## Step 1 — Configure notification channels

Set the webhook URLs and bot tokens in `compose/.env`:

```bash
cp compose/.env.example compose/.env
# Edit .env and fill in:
#   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../...
#   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/<id>/<token>
#   TELEGRAM_BOT_TOKEN=123456:ABC-DEF...   (for the Telegram relay)
#   TELEGRAM_CHAT_ID=-1001234567890         (for the Telegram relay)
```

### Slack setup

1. Go to <https://api.slack.com/apps> and create a new app (or use an existing one).
2. Enable **Incoming Webhooks** under Features.
3. Add webhook URLs for each channel: `#alerts-critical`, `#alerts-warning`, `#alerts-info`.
4. Paste the URL into `compose/.env` as `SLACK_WEBHOOK_URL`.

### Discord setup

1. Open your server → **Channel Settings** → **Integrations** → **Webhooks**.
2. Create a webhook for each channel (or use a single webhook).
3. Copy the webhook URL and paste it into `compose/.env` as `DISCORD_WEBHOOK_URL`.
4. Alertmanager appends `/slack` to the URL automatically (configured in `alerts/alertmanager-rules.yml`) to use Discord's Slack-compatible mode.

### Telegram setup

Alertmanager has no native Telegram support. You need a small relay that:
1. Receives the Alertmanager webhook payload.
2. Renders the `telegram_default` template from `alert-templates.tmpl`.
3. POSTs the rendered message to `https://api.telegram.org/bot<TOKEN>/sendMessage`.

You can use any Telegram-Alertmanager bridge (e.g. `telegram-alertmanager-bot`, a Cloudflare Worker, or a simple Python/Go relay). Set the relay URL as `RELAY_URL` in `compose/.env` and pass `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` to the relay container.

To get your bot token and chat ID:
1. Create a bot via [@BotFather](https://t.me/BotFather) and copy the token.
2. Add the bot to your channel/group.
3. Get the chat ID by sending a message and visiting `https://api.telegram.org/bot<TOKEN>/getUpdates`.

## Step 2 — Deploy Alertmanager

```bash
# Option A: run alongside the main monitor-stack
sudo docker compose -f compose/compose.yml -f compose/alertmanager.yml up -d

# Option B: run Alertmanager on its own
sudo docker compose -f compose/alertmanager.yml up -d
```

Alertmanager joins the `mb-proxy` external network so Prometheus can reach it at `http://alertmanager:9093`.

## Step 3 — Wire Prometheus to Alertmanager

Add the alert rules and Alertmanager endpoint to your `prometheus.yml`:

```yaml
rule_files:
  - /etc/prometheus/prometheus-alert-rules.yml
  - /etc/prometheus/prometheus-blackbox-rules.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

Reload Prometheus:

```bash
sudo docker kill -s SIGHUP prometheus
```

## Step 4 — Verify

```bash
# Alertmanager should report "OK"
curl -s http://127.0.0.1:9093/-/healthy

# Check loaded config
curl -s http://127.0.0.1:9093/api/v2/status | python3 -m json.tool

# View active alerts
curl -s http://127.0.0.1:9093/api/v2/alerts | python3 -m json.tool

# Or use the mb CLI:
sudo ./mb monitor alerts
```

## Alert rules

The rules in `agents/prometheus-alert-rules.yml` cover all monitor-stack components:

| Alert | Severity | Condition | `for` | Source |
|-------|----------|-----------|-------|--------|
| `NodeDown` | critical | `up{job="node"} == 0` | 1m | node_exporter |
| `NodeUp` | info | `up{job="node"} == 1` | 1m | node_exporter |
| `HighCPUUsage` | warning | CPU > 80% | 5m | node_exporter |
| `HighMemoryUsage` | warning | memory > 90% | 5m | node_exporter |
| `DiskSpaceLow` | warning | free disk < 10% | 5m | node_exporter |
| `ServiceDown` | critical | container not seen for 2m | 2m | cAdvisor / docker_exporter |
| `CrowdSecAlerts` | warning | > 5 new decisions in 5m | 1m | CrowdSec exporter |
| `SSLCertExpiring` | warning | cert < 14 days | 5m | Blackbox Exporter |
| `ProbeFailed` | critical | `probe_success == 0` | 2m | Blackbox Exporter |
| `HighLogRate` | warning | error log rate > 10/sec | 5m | Loki |

Additional Blackbox-specific rules (service down, SSL < 7d, high latency, HTTP status anomaly) are in `agents/prometheus-blackbox-rules.yml`.

## Routing

Alerts are routed by severity in `alerts/alertmanager-rules.yml`:

| Severity | Channels | `group_wait` | `repeat_interval` |
|----------|----------|-------------|-------------------|
| critical | Telegram + Slack (+ Discord) | 10s | 1h |
| warning | Slack (+ Discord) | 30s | 4h |
| info | Slack only | 5m | 12h |

Alerts are grouped by `alertname + service + severity` so alerts that fire together arrive in a single notification.

## Message templates

`alerts/alert-templates.tmpl` defines platform-specific message formats:

- **Telegram** — Markdown format with emoji severity indicators (🔴/🟡/🔵/✅), alert name, instance, summary, start time, description, and runbook link.
- **Slack** — Attachment format with colour-coded bars (red=critical, yellow=warning, green=resolved), per-alert details, and action buttons (Runbook, Silence).
- **Discord** — Embed-style text via Slack-compat mode, with the same colour coding as Slack.
- **Email** — Plain-text format (for operators who add an email receiver).

Common fields in every template: alert name, status (firing/resolved), instance, labels, annotations, start/end time, runbook URL, and Alertmanager UI link.

To customize a template, edit `alerts/alert-templates.tmpl` and restart Alertmanager. See the [Prometheus template reference](https://prometheus.io/docs/alerting/latest/notifications/) for the template syntax.

## Inhibition

Inhibition rules suppress lower-severity alerts when a higher-severity alert is already firing for the same service:

- **critical** suppresses **warning** and **info** (same `alertname + service`)
- **warning** suppresses **info** (same `alertname + service`)
- **NodeDown** suppresses `ServiceDown`, `HighCPUUsage`, `HighMemoryUsage`, `DiskSpaceLow` (same `instance`)

This prevents alert storms when a node goes down — you get one "NodeDown" page instead of dozens of individual service-down alerts.

## Silencing

Silences are created at runtime via the Alertmanager API or `amtool`. They temporarily suppress matching alerts without changing the config.

```bash
# Silence all warning alerts for 8 hours (maintenance window)
amtool --alertmanager.url=http://localhost:9093 silence create \
  severity=warning \
  --duration=8h \
  --comment="Maintenance window — warnings silenced"

# Silence a specific alert
amtool --alertmanager.url=http://localhost:9093 silence create \
  alertname=HighCPUUsage \
  --duration=2h \
  --comment="Investigating CPU spike"

# List active silences
amtool --alertmanager.url=http://localhost:9093 silence query

# Expire a silence by ID
amtool --alertmanager.url=http://localhost:9093 silence expire <silence-id>
```

You can also create silences from the Alertmanager web UI at `http://localhost:9093`.

## Quiet hours (mute time intervals)

`alerts/alertmanager-rules.yml` defines an `off-hours` mute interval (22:00–08:00, `Asia/Shanghai`). To apply it to warning/info routes, add `mute_time_intervals: ['off-hours']` to the route:

```yaml
route:
  routes:
    - matchers: ['severity = "warning"']
      receiver: slack-warning
      mute_time_intervals: ['off-hours']
```

Critical alerts are never muted — they always page.

## Runbook

Each alert includes a `runbook_url` annotation linking back to this section. Below are the recommended remediation steps for each alert.

### NodeDown
- SSH into the host and check if it is powered on and networked.
- Verify node_exporter is running: `systemctl status node_exporter`.
- Check firewall rules between Prometheus and the node.

### NodeUp
- Informational — no action needed. The node has recovered from a previous NodeDown.

### HighCPUUsage
- Identify the top CPU process: `top -o %CPU` or `ps aux --sort=-%cpu | head`.
- Check for runaway processes, backup jobs, or compilation.
- Consider scaling up the VPS or moving workloads.

### HighMemoryUsage
- Identify the top memory process: `top -o %MEM` or `ps aux --sort=-%mem | head`.
- Check for memory leaks in long-running services.
- Review swap usage: `free -h`. If swap is full, the OOM killer may activate.

### DiskSpaceLow
- Identify large files: `du -sh /* 2>/dev/null | sort -rh | head`.
- Clean up old logs: `journalctl --vacuum-time=7d`.
- Prune Docker images: `docker system prune -a --volumes`.
- Expand the volume if growth is expected.

### ServiceDown
- Check the container: `docker ps -a | grep <name>` and `docker logs <name>`.
- Restart the container: `docker compose up -d <service>`.
- Check for OOM kills: `dmesg | grep -i oom`.

### CrowdSecAlerts
- Review decisions: `cscli decisions list -o human`.
- Check alerts: `cscli alerts list -o human`.
- Review the attack source and consider extending bouncer rules.

### SSLCertExpiring
- Identify the certificate: check the Blackbox target URL.
- Renew via certbot: `certbot renew` (or your CA's renewal process).
- Verify renewal: `curl -sI https://<domain>` and check the cert.

### ProbeFailed
- Check if the target is reachable: `curl -I <url>` or `nc -zv <host> <port>`.
- Verify the Blackbox module matches the target type (http/tcp/icmp).
- Check if the target service is running.

### HighLogRate
- Query Loki for the offending job: `{job="<job>"} |= "error"`.
- Identify the error pattern and check the service logs.
- Look for recent deployments or config changes that may have introduced errors.

## Integration with existing components

| Component | Alert rule(s) | Metric source |
|-----------|---------------|---------------|
| node_exporter | NodeDown, NodeUp, HighCPUUsage, HighMemoryUsage, DiskSpaceLow | `up`, `node_cpu_seconds_total`, `node_memory_*`, `node_filesystem_*` |
| Docker / cAdvisor | ServiceDown | `container_last_seen` |
| CrowdSec | CrowdSecAlerts | `crowdsec_decisions_total` (requires exporter) |
| Blackbox Exporter | ProbeFailed, SSLCertExpiring | `probe_success`, `probe_ssl_earliest_cert_expiry` |
| Loki | HighLogRate | LogQL metric query via Loki ruler or Prometheus |

## CLI

```bash
# Check Alertmanager status and view alert config guide
sudo ./mb monitor alerts
```
