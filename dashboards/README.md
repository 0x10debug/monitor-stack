# Grafana Dashboard Templates

monitor-stack provides four Grafana dashboard JSON templates covering VPS system metrics, security events, availability probing, and log aggregation. All templates conform to the Grafana 11.x schema, are auto-loaded via provisioning, and also support manual import.

> Part of the [0x10debug](https://github.com/0x10debug) VPS tool suite.

## Dashboard List

| Dashboard | File | Data Source | Coverage |
|--------|------|--------|----------|
| VPS Overview | `vps-overview.json` | Prometheus (node_exporter) | CPU, memory, disk, network, load, processes, Docker containers |
| Security Overview | `security-overview.json` | Loki + Prometheus | CrowdSec decisions/alerts, auditd audit, Falco events, SSH logins |
| Availability Overview | `availability-overview.json` | Prometheus (blackbox_exporter) | HTTP/TCP/ICMP probes, SSL certificate expiry, response time, packet loss |
| Logs Overview | `logs-overview.json` | Loki + Prometheus | Log volume trends, error/warning counts, per-service rates, Promtail status |

## Data Source Configuration

The dashboards depend on two data sources, auto-configured via `agents/grafana-datasources.yml`:

- **Prometheus** — UID `prometheus`, scrapes node_exporter, blackbox_exporter, crowdsec exporter, promtail metrics
- **Loki** — UID `loki`, stores syslog, auth, auditd, docker, crowdsec, falco log streams

If configuring data sources manually, ensure the UIDs match the dashboard template variables `${DS_PROMETHEUS}` and `${DS_LOKI}`, or re-select data sources via the panel editor after import.

## Auto-loading (Provisioning)

The Grafana container started by `compose/grafana.yml` mounts the following provisioning configs:

- `agents/grafana-datasources.yml` → `/etc/grafana/provisioning/datasources/datasources.yml`
- `agents/grafana-dashboards.yml` → `/etc/grafana/provisioning/dashboards/dashboards.yml`
- `dashboards/*.json` → `/var/lib/grafana/dashboards/`

On startup, Grafana automatically discovers and loads all dashboards — no manual import needed.

## Manual Import

### Method 1: Grafana UI

1. Log in to Grafana (default `http://localhost:3000`, username `admin`).
2. Left menu → **Dashboards** → **New** → **Import**.
3. Click **Upload dashboard JSON file**, select a JSON file from `dashboards/`.
4. Select the configured data source in the **Prometheus** / **Loki** dropdown.
5. Click **Import**.

### Method 2: Grafana API

```bash
# Set Grafana credentials
export GRAFANA_URL="http://localhost:3000"
export GRAFANA_USER="admin"
export GRAFANA_PASS="admin"

# Import a single dashboard
curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -H "Content-Type: application/json" \
  -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -d @dashboards/vps-overview.json

# Batch import
for f in dashboards/*-overview.json; do
  echo "Importing $f ..."
  curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -H "Content-Type: application/json" \
    -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -d @"$f"
done
```

> Note: When importing via API, the JSON top level needs to be wrapped in `{"dashboard": { ... }, "overwrite": true}`. The template files in this repository are complete dashboard objects and can be used directly for provisioning; for manual API import, you need to wrap them manually.

## Panel Details

### VPS Overview (`vps-overview.json`)

| Panel | Metric | Description |
|------|------|------|
| CPU Usage | `100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])))` | 1-minute average, thresholds 70%/90% |
| Memory Usage | `1 - MemAvailable / MemTotal` | Thresholds 75%/90% |
| Disk Usage | `1 - fs_avail / fs_size` | Excludes tmpfs/overlay |
| Network Traffic | `rate(node_network_*_bytes_total[1m])` | Excludes lo/veth/docker virtual interfaces |
| Load Average | `node_load1/5/15` | 1/5/15-minute load |
| Total Processes | `node_processes_pids` | Thresholds 300/500 |
| Zombie Processes | `node_processes_zombies` | Alert when >0 |
| Running Containers | `container_last_seen` | cadvisor metrics |
| Stopped Containers | `last_seen` unless `memory_usage` | Stopped but not cleaned up containers |
| Total Containers | `count(container_last_seen)` | Running + stopped |

### Security Overview (`security-overview.json`)

| Panel | Data Source | Description |
|------|--------|------|
| Active Decisions | Prometheus | `crowdsec_decisions_active` |
| Recent Alerts (1h) | Prometheus | `increase(crowdsec_alerts_total[1h])` |
| Banned IP Geo Distribution | Loki | CrowdSec logs aggregated by country, geomap visualization |
| Recent Audit Events | Loki | `{job="auditd"}` real-time log stream |
| Privileged Command Execution | Loki | auditd EXECVE events aggregated by command |
| File Integrity Alerts | Loki | Monitors passwd/shadow/sudoers/ssh_host changes |
| Falco CRITICAL | Loki | `{job="falco"}` containing CRITICAL keyword |
| Falco WARNING | Loki | `{job="falco"}` containing WARNING keyword |
| SSH Failed Logins | Loki | `{job="auth"}` containing "Failed password" |
| SSH Successful Logins | Loki | `{job="auth"}` containing "Accepted password/publickey" |

### Availability Overview (`availability-overview.json`)

| Panel | Metric | Description |
|------|------|------|
| HTTP Probe Status | `probe_success{job=~"blackbox_http.*"}` | UP/DOWN status panel |
| SSL Certificate Expiry Days | `(probe_ssl_earliest_cert_expiry - time()) / 86400` | Thresholds 7/30 days |
| HTTP Response Time | `probe_duration_seconds` | Thresholds 2s/5s |
| TCP Port Connectivity | `probe_success{job="blackbox_tcp"}` | OK/FAIL status panel |
| ICMP Ping Latency | `probe_duration_seconds{job="blackbox_icmp"}` | Thresholds 500ms/1s |
| ICMP Packet Loss | `100 * (1 - avg_over_time(probe_success[5m]))` | Thresholds 5%/20% |

### Logs Overview (`logs-overview.json`)

| Panel | Data Source | Description |
|------|--------|------|
| Log Volume Trend (by job) | Loki | `sum by (job) (rate({job!=""} [5m]))` stacked chart |
| Error Log Count (1h) | Loki | Matches error/panic/fatal |
| Warning Log Count (1h) | Loki | Matches warn/warning |
| Log Rate by Service | Loki | Grouped by program and container |
| Promtail Active Tails | Prometheus | `promtail_active_targets` |
| Promtail Log Push Rate | Prometheus | `rate(promtail_log_lines_total[5m])` |
| Real-time Log Stream | Loki | Full log browsing panel |

## Customization Guide

### Modifying Panel Queries

1. Open the dashboard in Grafana, click the panel title → **Edit**.
2. Modify the PromQL / LogQL expression in the **Query** tab.
3. Click **Apply** to save.
4. Click **Save dashboard** at the top to persist to the Grafana database.

### Modifying Template Files

1. Edit the JSON file under `dashboards/`.
2. Modify the `targets[].expr` query expressions in the `panels` array.
3. Adjust `fieldConfig.defaults.thresholds` threshold values.
4. Validate JSON: `python3 -m json.tool dashboards/<file>.json > /dev/null`.
5. Restart the Grafana container or wait for provisioning hot-reload.

### Adding New Dashboards

1. Create a new dashboard in the Grafana UI and configure panels.
2. Click **Share** → **Export** → download JSON.
3. Place the JSON in the `dashboards/` directory.
4. Ensure the JSON contains a `uid` field (provisioning uses uid for deduplication).
5. Restart Grafana; provisioning auto-loads the new dashboard.

### Modifying Data Source UIDs

If using non-default Prometheus/Loki UIDs:

1. Edit the `uid` field in `agents/grafana-datasources.yml`.
2. Edit the datasource variables in `templating.list` in the dashboard JSON, or re-select in the UI after import.

## Mapping to Monitoring Components

| Dashboard | Dependent Components | Compose Template | Config Files |
|--------|----------|-------------|----------|
| VPS Overview | node_exporter + cadvisor | (externally deployed) | — |
| Security Overview | CrowdSec + auditd + Falco + Loki | `compose/crowdsec.yml` + `compose/loki.yml` | `agents/auditd-exporter.conf`, `agents/loki-config.yml`, `agents/promtail-config.yml` |
| Availability Overview | Blackbox Exporter + Prometheus | `compose/blackbox.yml` | `agents/blackbox.yml`, `agents/prometheus-blackbox-targets.yml`, `agents/prometheus-blackbox-rules.yml` |
| Logs Overview | Loki + Promtail | `compose/loki.yml` | `agents/loki-config.yml`, `agents/promtail-config.yml` |

## Deploy Grafana

```bash
# Start Grafana (with auto provisioning)
sudo docker compose -f compose/grafana.yml up -d

# Or merge with the main stack
sudo docker compose -f compose/compose.yml -f compose/grafana.yml up -d
```

After Grafana first starts, the default username is `admin`, password configured via the `GF_SECURITY_ADMIN_PASSWORD` environment variable (see `compose/.env.example`). Dashboards and data sources are auto-loaded.

Run `mb monitor dashboards` to view Grafana status and import instructions.
