# Security Monitoring with CrowdSec

How to integrate CrowdSec security events into the monitor-stack.

## Overview

[CrowdSec](https://github.com/crowdsecurity/crowdsec) is a collaborative intrusion prevention system. It detects attacks, blocks malicious IPs, and shares threat intelligence with the community. The monitor-stack provides a data schema and integration path for surfacing CrowdSec metrics alongside your uptime and performance dashboards.

## Architecture

```
┌─────────────┐     cscli      ┌──────────────────┐     webhook     ┌─────────────┐
│  CrowdSec   │ ──────────────▶│  Collection      │ ──────────────▶│  Alert       │
│  (on node)  │                │  Script/Endpoint │                │  Channel     │
└─────────────┘                └──────────────────┘                └──────────────┘
       │                              │
       │ decisions list               │ metrics JSON
       ▼                              ▼
┌─────────────┐              ┌──────────────────┐
│  Blocked IPs│              │  Uptime Kuma     │
│  Dashboard  │              │  HTTP Monitor    │
└─────────────┘              └──────────────────┘
```

## Step 1 — Install CrowdSec

You have two deployment options.

### Option A: Docker (recommended for monitor-stack users)

A ready-to-use docker-compose template ships at `compose/crowdsec.yml`. It runs
the CrowdSec detection engine plus a firewall bouncer, with pinned image tags
and persistent storage under `/data/crowdsec`.

```bash
# 1. Create the data directories
sudo mkdir -p /data/crowdsec/db /data/crowdsec/config

# 2. Start CrowdSec first so the LAPI is up
sudo docker compose -f compose/crowdsec.yml up -d crowdsec

# 3. Register a bouncer and copy the printed key
docker exec crowdsec cscli bouncers add mb-firewall -o raw

# 4. Put the key into compose/.env as CROWDSEC_BOUNCER_KEY, then start the bouncer
sudo docker compose -f compose/crowdsec.yml up -d crowdsec-bouncer
```

The bouncer configuration lives at `agents/crowdsec-bouncer.conf` and is
bind-mounted into the bouncer container. Edit it to switch between the
`nftables` and `iptables` backends depending on your host firewall.

### Option B: Native package (for nodes without Docker)

On each node you want to protect:

```bash
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
sudo apt install crowdsec
```

For other distributions, see the [CrowdSec installation docs](https://doc.crowdsec.net/docs/getting_started/installation).

## Step 2 — Verify CrowdSec is running

```bash
sudo cscli metrics
sudo cscli decisions list
sudo cscli alerts list
```

## Step 3 — Use the dashboard schema

The file `dashboards/crowdsec-dashboard.json` defines a data schema with four key fields:

| Field | Description | Collection Method |
|-------|-------------|-------------------|
| `blocked_ips_today` | Number of IPs blocked today | `cscli decisions list --json` |
| `top_attacker_countries` | Top countries by attack volume | Parse decision metadata |
| `attack_types` | Detected attack scenarios | `cscli alerts list --json` |
| `alerts_last_24h` | Security alerts in last 24 hours | `cscli alerts list --json` |

This is a **data schema**, not a Grafana dashboard. Use it as a contract for any script or service that collects and displays CrowdSec metrics.

## Step 4 — Create a metrics endpoint (optional)

To surface CrowdSec metrics in Uptime Kuma, create a simple script that outputs JSON:

```bash
#!/usr/bin/env bash
# /usr/local/bin/crowdsec-metrics.sh
set -euo pipefail

DECISIONS_COUNT=$(sudo cscli decisions list -o json 2>/dev/null | jq 'length' || echo 0)
ALERTS_COUNT=$(sudo cscli alerts list -o json 2>/dev/null | jq 'length' || echo 0)

cat <<EOF
{
  "blocked_ips_today": ${DECISIONS_COUNT},
  "alerts_last_24h": ${ALERTS_COUNT},
  "status": "ok"
}
EOF
```

Serve it via a lightweight HTTP server or Caddy, then add an HTTP monitor in Uptime Kuma pointing to this endpoint.

## Step 5 — Configure CrowdSec notifications

CrowdSec can send notifications directly to your alert channels.

### Telegram

1. Edit `/etc/crowdsec/notifications/telegram.yaml`:
   ```yaml
   type: telegram
   format: |
     🚨 CrowdSec Alert
     Scenario: {{.Scenario}}
     IP: {{.Source.IP}}
     Country: {{.Source.Country}}
   api_key: "YOUR_TELEGRAM_BOT_TOKEN"
   chat_id: "YOUR_CHAT_ID"
   ```

2. Enable the plugin:
   ```bash
   sudo cscli bouncers list
   sudo cscli notifications enable telegram
   sudo systemctl reload crowdsec
   ```

### Discord / Slack

CrowdSec supports HTTP webhook notifications. Configure the webhook URL in the notification plugin YAML and enable it with `cscli`.

See the [CrowdSec notification docs](https://doc.crowdsec.net/docs/notifications/) for all supported plugins.

## Step 6 — Monitor with the CLI

```bash
sudo ./mb monitor security-dashboard
```

This command checks if CrowdSec is installed and displays current metrics, recent decisions, and alerts.

## Useful cscli commands

| Command | Description |
|---------|-------------|
| `cscli metrics` | Show parser and router metrics |
| `cscli decisions list` | List active IP bans |
| `cscli decisions list -o json` | Same, as JSON |
| `cscli alerts list` | Show recent alerts |
| `cscli alerts list -o json` | Same, as JSON |
| `cscli collections list` | List installed detection scenarios |
| `cscli bouncers list` | List active bouncers (firewall, nginx, etc.) |
| `cscli hub update` | Update the hub index |
| `cscli hub upgrade` | Upgrade installed collections |

## auditd log forwarding

Beyond CrowdSec's own detections, you may want to stream kernel-level audit
events (logins, privilege escalations, file tampering) into the monitor-stack's
log layer for long-term retention and correlation.

A ready-to-use rsyslog template ships at `agents/auditd-exporter.conf`. It
tails `/var/log/audit/audit.log`, enriches each event with host + timestamp as
JSON, and writes a structured stream that Promtail (for Loki) or rsyslog's
`omelasticsearch` module can pick up.

Quick start on a monitored node:

```bash
sudo apt install -y rsyslog auditd
sudo cp agents/auditd-exporter.conf /etc/rsyslog.d/60-auditd-exporter.conf
sudo mkdir -p /var/log/auditd-exporter
sudo chown syslog:adm /var/log/auditd-exporter
sudo systemctl restart rsyslog
```

Then point Promtail at `/var/log/auditd-exporter/auditd.jsonl` with a static
`job=auditd` label, or uncomment the `omelasticsearch` block in the template
to ship directly to Elasticsearch/OpenSearch.

## Best practices

- **Install bouncers**: CrowdSec detects attacks, but you need a bouncer (e.g. `cscli bouncers add`) to actually block IPs at the firewall level.
- **Install collections**: Add detection scenarios for your services: `cscli collections install crowdsecurity/nginx crowdsecurity/sshd`.
- **Monitor the metrics endpoint**: Add an Uptime Kuma HTTP monitor to your CrowdSec metrics script so you get alerted if CrowdSec stops working.
- **Share intelligence**: CrowdSec shares blocked IPs with the community by default. This strengthens everyone's defense.
- **Regular updates**: Run `cscli hub update && cscli hub upgrade` periodically to get new detection rules.
