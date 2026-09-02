# Self-Hosted Monitoring Stack for VPS — Uptime, Metrics & Alerts

A complete self-hosted monitoring solution for VPS servers, integrating **Uptime Kuma** for availability monitoring, **Beszel** for performance metrics collection, **CrowdSec** integration for security event tracking, **Loki + Promtail** for log aggregation, **Blackbox Exporter** for active endpoint probing (HTTP/TCP/ICMP) with Prometheus alert rules, **Grafana** dashboard templates for visualizing system/security/availability/log metrics, and **Alertmanager** for multi-channel alert notifications (Telegram, Slack, Discord) with severity-based routing, inhibition rules, and silencing management. Deploy everything with Docker in minutes, configure alerts via Telegram, Discord, Email, or Slack, and monitor unlimited remote nodes from a single dashboard. No SaaS dependencies, no monthly fees — full control over your VPS monitoring.

> Part of the [0x10debug](https://github.com/0x10debug) VPS tool suite.

## What's Included

| Component | Purpose | Port | Data Path |
|------|------|------|----------|
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Availability and uptime monitoring | 3001 | `/data/uptime-kuma` |
| [Beszel Hub](https://github.com/henrygd/beszel) | Performance metrics and system resource monitoring | 8090 | `/data/beszel` |
| [CrowdSec](https://github.com/crowdsecurity/crowdsec) | Security monitoring (integration) | — | data template |
| [Loki](https://github.com/grafana/loki) + [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log aggregation (syslog, auth, auditd, docker) | 3100 | `/data/loki` |
| [Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) | Availability probing (HTTP/TCP/ICMP) + Prometheus alert rules | 9115 | config-only |
| [Grafana](https://github.com/grafana/grafana) | Dashboard templates: VPS, security, availability, logs | 3000 | `/data/grafana` |
| [Alertmanager](https://github.com/prometheus/alertmanager) | Alert notifications: Telegram, Slack, Discord | 9093 | `/data/alertmanager` |
| Alert templates | Telegram, Discord, Email, Slack | — | `/data/monitor-alerts` |
| Status page | Self-contained HTML status page | — | configurable |

## Quick Start

### Prerequisites

- A VPS running Linux (Ubuntu 22.04+ recommended)
- Docker and Docker Compose installed
- A domain name pointing to your server (for HTTPS via Caddy)
- Root or sudo access

### 1. Clone the repository

```bash
git clone https://github.com/0x10debug/monitor-stack.git
cd monitor-stack
```

### 2. Deploy the monitoring stack

```bash
sudo ./mb monitor deploy
```

The CLI will automatically:
- Create the `mb-proxy` Docker network
- Generate a `.env` file (prompts for your domain)
- Start Uptime Kuma and Beszel Hub containers
- Create data directories under `/data/`

### 3. Set up your admin account

Open Uptime Kuma at `http://localhost:3001` on first visit to create your admin account.

Open Beszel Hub at `http://localhost:8090` to register and start adding systems.

### 4. Add remote nodes

```bash
sudo ./mb monitor add-host
```

Follow the prompts to install the Beszel agent on any remote server.

### 5. Configure alerts

```bash
sudo ./mb monitor alert setup
sudo ./mb monitor alert test
```

## Usage

All operations are handled through the `mb` CLI:

```bash
# Deploy the monitoring stack
mb monitor deploy

# Check stack status
mb monitor status

# Add a remote monitoring node
mb monitor add-host

# View instructions for adding monitors in Uptime Kuma
mb monitor add-service

# Configure alert channels (telegram / discord / email / slack)
mb monitor alert setup

# Send a test alert
mb monitor alert test

# List configured alert channels
mb monitor alert list

# Deploy the public status page
mb monitor status-page

# View CrowdSec security integration instructions
mb monitor security-dashboard

# View Loki + Promtail log aggregation status and queries
mb monitor logs

# View Blackbox Exporter availability probing status
mb monitor availability

# View Alertmanager alert notification status and configuration guide
mb monitor alerts

# Update all services to latest images
mb monitor update

# Show help
mb monitor help
```

## Alert Channels

Pre-configured templates are provided in the `alerts/` directory:

| Channel | Template | Config Fields |
|------|----------|----------|
| Telegram | `alerts/telegram.json` | `bot_token`, `chat_id` |
| Discord | `alerts/discord.json` | `webhook_url` |
| Email | `alerts/email.json` | `smtp_host`, `smtp_port`, `username`, `password`, `from`, `to` |
| Slack | `alerts/slack.json` | `webhook_url`, `channel` |

Configurations are stored in `/data/monitor-alerts/<channel>.json` with `0600` permissions.

## Status Page

A self-contained HTML status page template is included at `dashboards/status-page.html`. It uses vanilla CSS with no external dependencies and can be served standalone:

```bash
sudo ./mb monitor status-page
```

Edit the file to replace `{{SERVICE_NAME}}` and customize service entries with your real status data.

## CrowdSec Integration

The `dashboards/crowdsec-dashboard.json` file defines a data schema for displaying CrowdSec security metrics:

- **blocked_ips_today** — IPs blocked today
- **top_attacker_countries** — Countries ranked by attack volume
- **attack_types** — Detected attack scenarios
- **alerts_last_24h** — Security alerts in the last 24 hours

Run `mb monitor security-dashboard` for integration instructions.

## Log Aggregation

A Loki + Promtail docker-compose template ships at `compose/loki.yml`. Promtail tails host syslog, auth.log, the auditd JSON stream (from `agents/auditd-exporter.conf`), and optionally Docker container logs, then ships them to Loki for querying from Grafana with LogQL.

- **Loki** — log store, port 3100, data at `/data/loki`, 14-day default retention
- **Promtail** — log shipper with regex + JSON pipeline stages and labels (`job`, `host`, `program`, `container`)

Run `mb monitor logs` for status and example queries. See [Log Aggregation](docs/logging-stack.md) for the full deployment guide and LogQL examples.

## Availability Monitoring

A Blackbox Exporter docker-compose template ships at `compose/blackbox.yml`. It performs active probing of endpoints over HTTP (2xx + SSL cert expiry), TCP (port connectivity), and ICMP (ping), and exposes the results as Prometheus metrics (`probe_success`, `probe_duration_seconds`, `probe_ssl_earliest_cert_expiry`, `probe_http_status_code`).

- **Blackbox Exporter** — probe runner, port 9115, config-only (no persistent data), pinned `prom/blackbox-exporter:v0.25.0`
- **Probe modules** — `http_2xx`, `http_post_2xx`, `tcp_connect`, `icmp` (defined in `agents/blackbox.yml`)
- **Prometheus scrape configs** — `agents/prometheus-blackbox-targets.yml` (example HTTP/TCP/ICMP targets)
- **Alert rules** — `agents/prometheus-blackbox-rules.yml`: service down (2m), SSL cert expiring (<7d), high latency (>2s), HTTP status anomaly (≥400)

Run `mb monitor availability` for status and integration instructions. See [Availability Monitoring](docs/availability-monitoring.md) for the full deployment guide, Prometheus wiring, and Grafana dashboard setup.

## Grafana Dashboards

Four Grafana dashboard JSON templates ship in `dashboards/`, plus auto-provisioning configs in `agents/` and a docker-compose template in `compose/grafana.yml`. Grafana loads dashboards and data sources (Prometheus + Loki) automatically on startup — no manual UI configuration needed.

- **VPS Overview** (`vps-overview.json`) — CPU, memory, disk, network, load, processes, Docker containers (Prometheus / node_exporter)
- **Security Overview** (`security-overview.json`) — CrowdSec decisions/alerts, auditd audit, Falco events, SSH logins (Loki + Prometheus)
- **Availability Overview** (`availability-overview.json`) — HTTP/TCP/ICMP probes, SSL certificate expiry, response time, packet loss (Prometheus / blackbox_exporter)
- **Logs Overview** (`logs-overview.json`) — Log volume trends, error/warning counts, per-service rates, Promtail status (Loki + Prometheus)

Run `mb monitor dashboards` for Grafana status and import instructions. See [Dashboards README](dashboards/README.md) for panel details, customization guide, and API import examples.

## Alert Notifications

A Prometheus Alertmanager docker-compose template ships at `compose/alertmanager.yml`. It receives firing alerts from Prometheus, groups them by alertname + service + severity, applies inhibition rules (critical suppresses warning), and dispatches notifications to Telegram, Slack, and Discord.

- **Alertmanager** — notification router, port 9093, data at `/data/alertmanager`, pinned `prom/alertmanager:v0.27.0`
- **Routing config** — `alerts/alertmanager-rules.yml`: critical → Telegram + Slack, warning → Slack, info → Slack only
- **Message templates** — `alerts/alert-templates.tmpl`: Telegram (Markdown), Slack (Block Kit), Discord (embed), with colour coding and runbook links
- **Alert rules** — `agents/prometheus-alert-rules.yml`: NodeDown, HighCPUUsage, HighMemoryUsage, DiskSpaceLow, ServiceDown, CrowdSecAlerts, SSLCertExpiring, ProbeFailed, HighLogRate
- **Inhibition** — critical suppresses warning/info for the same service; NodeDown suppresses service-level alerts for the same instance
- **Silencing** — runtime silences via `amtool` or the Alertmanager web UI

| Severity | Channels | Repeat interval |
|----------|----------|----------|
| critical | Telegram + Slack (+ Discord) | 1h |
| warning | Slack (+ Discord) | 4h |
| info | Slack only | 12h |

Run `mb monitor alerts` for Alertmanager status and configuration instructions. See [Alert Notifications](docs/alerting.md) for the full deployment guide, channel setup, and runbook.

## FAQ

### Can I use a different reverse proxy instead of Caddy?

Yes. The stack joins an external Docker network called `mb-proxy`. Any reverse proxy (nginx, Traefik, Caddy) that can route to the `uptime-kuma:3001` and `beszel-hub:8090` containers will work. A Caddyfile example is provided in `compose/Caddyfile.example`.

### How do I monitor servers behind a firewall?

For Uptime Kuma, ensure the monitored ports are accessible from the Uptime Kuma host. For Beszel, the agent initiates an outbound connection to the hub, so no inbound firewall rules are needed on the monitored node — only the hub needs to be reachable.

### Is my data stored locally?

Yes. All data is stored on your VPS under `/data/uptime-kuma` and `/data/beszel`. No data is sent to third-party services. Alert configurations are stored in `/data/monitor-alerts/`.

### How many nodes can I monitor?

There is no hard limit. Uptime Kuma and Beszel are lightweight. In practice, a single VPS can monitor dozens of nodes. For large deployments, consider increasing the VPS resources.

### How do I back up the monitoring data?

Back up the data directories:

```bash
sudo tar -czf monitor-backup-$(date +%F).tar.gz /data/uptime-kuma /data/beszel /data/monitor-alerts
```

Store the archive off-site (e.g., to S3 or another server).

## Documentation

- [Setup Guide](docs/setup-guide.md) — Step-by-step deployment instructions
- [Adding Hosts](docs/add-hosts.md) — How to add remote servers for monitoring
- [Alert Configuration](docs/alert-configuration.md) — How to configure alert channels
- [Security Monitoring](docs/security-monitoring.md) — How to integrate CrowdSec
- [Log Aggregation](docs/logging-stack.md) — How to deploy Loki + Promtail and query logs with LogQL
- [Availability Monitoring](docs/availability-monitoring.md) — How to deploy Blackbox Exporter and wire it into Prometheus + Grafana
- [Alert Notifications](docs/alerting.md) — How to deploy Alertmanager and configure Telegram/Slack/Discord notifications

## Related Repositories

- [0x10debug/vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — VPS initial setup and hardening
- [0x10debug/compose-recipes](https://github.com/0x10debug/compose-recipes) — Docker Compose recipes for common services
- [0x10debug/network-toolkit](https://github.com/0x10debug/network-toolkit) — Network diagnostics and testing tools
- [0x10debug/security-audit](https://github.com/0x10debug/security-audit) — Security audit and hardening scripts

## License

[MIT](LICENSE) — Copyright (c) 2026 [0x10debug](https://github.com/0x10debug)
