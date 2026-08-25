# Log Aggregation with Loki + Promtail

How to deploy the Loki + Promtail log aggregation stack and query logs from Grafana.

## Overview

[Loki](https://github.com/grafana/loki) is a horizontally scalable, highly available log aggregation system inspired by Prometheus. [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) is its log shipper: it tails local log files, enriches them with labels, and pushes them to Loki. Unlike Elasticsearch, Loki only indexes labels (not the full log body), which keeps its storage footprint small enough to run on a single VPS.

The monitor-stack ships a ready-to-use docker-compose template at `compose/loki.yml`. It runs Loki (the log store) and Promtail (the shipper) with pinned image tags, healthchecks, and persistent storage under `/data/loki` and `/data/promtail`.

## Architecture

```
┌─────────────┐    tail     ┌─────────────┐    push     ┌─────────────┐    query    ┌─────────┐
│ /var/log    │ ──────────▶ │  Promtail   │ ──────────▶ │   Loki      │ ──────────▶ │ Grafana │
│  syslog     │             │  (labels +  │             │  (label     │             │ (LogQL) │
│  auth.log   │             │   pipeline) │             │   index)    │             │         │
│  auditd     │             └─────────────┘             └─────────────┘             └─────────┘
│  docker     │                   ▲
└─────────────┘                   │
                            /var/run/docker.sock
```

Promtail collects four log sources:

| Source | Path | Labels |
|--------|------|--------|
| Host syslog | `/var/log/syslog` | `job=syslog`, `source=host`, `host`, `program` |
| Auth log | `/var/log/auth.log` | `job=auth`, `source=host`, `host`, `program` |
| auditd JSON | `/var/log/auditd-exporter/auditd.jsonl` | `job=auditd`, `source=host`, `host`, `program` |
| Docker containers | via Docker socket | `job=docker`, `container`, `image`, `stream` |

The auditd stream is produced by `agents/auditd-exporter.conf` (see [Security Monitoring](security-monitoring.md#auditd-log-forwarding)). Promtail and CrowdSec are complementary: CrowdSec detects and blocks attackers, while Promtail ships the raw auth/auditd logs to Loki for long-term retention and forensic queries in Grafana.

## Step 1 — Create data directories

```bash
sudo mkdir -p /data/loki /data/promtail /var/log/auditd-exporter
sudo chown -R 10001:10001 /data/loki
```

If you forward auditd events, also set up the rsyslog template (see [Security Monitoring](security-monitoring.md#auditd-log-forwarding)) so `/var/log/auditd-exporter/auditd.jsonl` exists and is writable by rsyslog.

## Step 2 — Deploy the stack

The Loki stack is a standalone compose template. Deploy it alongside the main stack:

```bash
# Option A: run alongside the main monitor-stack
sudo docker compose -f compose/compose.yml -f compose/loki.yml up -d

# Option B: run the logging stack on its own
sudo docker compose -f compose/loki.yml up -d
```

Both Loki and Promtail join the `mb-proxy` external network so Grafana (running in the main stack) can reach Loki at `http://loki:3100`.

## Step 3 — Verify the stack

```bash
# Loki should report "ready"
curl -s http://127.0.0.1:3100/ready

# Promtail metrics — look for promtail_targets_active > 0
curl -s http://127.0.0.1:9080/metrics | grep promtail_targets_active

# Container status
sudo docker compose -f compose/loki.yml ps
```

## Step 4 — Add Loki as a Grafana data source

1. Open Grafana (or deploy it — see the main setup guide).
2. Go to **Connections → Data sources → Add data source**.
3. Select **Loki**.
4. Set the URL to `http://loki:3100` (the in-network service name).
5. Leave the other fields at their defaults and click **Save & test**. Grafana should report "Data source connected and labels found."

If Grafana runs outside the `mb-proxy` Docker network, use `http://127.0.0.1:3100` instead and make sure the Loki port is published (it is, bound to localhost).

## Step 5 — Query logs with LogQL

[LogQL](https://grafana.com/docs/loki/latest/logql/) is Loki's query language. It has two modes: **log queries** (return raw log lines) and **metric queries** (aggregate logs into time series).

Open Grafana → **Explore** → select the Loki data source, then try these examples:

### Log queries (raw lines)

```logql
# All syslog lines
{job="syslog"}

# sshd auth events only
{job="auth", program="sshd"}

# Failed SSH logins
{job="auth", program="sshd"} |= "Failed password"

# auditd events from a specific host
{job="auditd", host="web-01"}

# Docker container logs for a named container
{job="docker", container="uptime-kuma"}

# Errors across all sources in the last 5 minutes
{job=~"syslog|auth|auditd|docker"} |= "error" |= "ERROR"
```

### Metric queries (aggregations)

```logql
# Count of failed SSH logins per minute
sum(rate({job="auth", program="sshd"} |= "Failed password" [5m])) by (host)

# Top containers by log volume over the last hour
sum(count_over_time({job="docker"} [1h])) by (container)

# Number of auditd events per host per minute
sum(rate({job="auditd"} [5m])) by (host)
```

### Useful filter operators

| Operator | Meaning |
|----------|---------|
| `\|= "foo"` | line contains "foo" |
| `!= "foo"` | line does not contain "foo" |
| `\|~ "regex"` | line matches regex |
| `!~ "regex"` | line does not match regex |
| `\| json` | parse line as JSON and expose fields |
| `\| line_format "{{.field}}"` | reformat the output line |

## Step 6 — Enable Docker container logs (optional)

By default Promtail ships host logs (syslog, auth, auditd). To also collect Docker container logs, append the scrape config from `agents/promtail-docker.yml` to the `scrape_configs` list in `agents/promtail-config.yml`, then recreate the promtail container:

```bash
# Append the docker scrape block (see agents/promtail-docker.yml for the
# exact contents) to agents/promtail-config.yml under scrape_configs, then:
sudo docker compose -f compose/loki.yml up -d promtail --force-recreate
```

Container logs will appear with the `job="docker"` label and `container`/`image` labels for filtering.

## Step 7 — Tune retention

Loki deletes log streams older than the retention window. The default is 14 days (`336h`), set in `agents/loki-config.yml`. To change it:

1. Edit `agents/loki-config.yml` and set `limits_config.retention_period` to your desired window (e.g. `720h` for 30 days, `0s` to disable).
2. Recreate Loki:
   ```bash
   sudo docker compose -f compose/loki.yml up -d loki --force-recreate
   ```

The compactor runs in the background and removes expired chunks. Monitor disk usage under `/data/loki` and adjust retention to fit your budget.

## Step 8 — Monitor with the CLI

```bash
sudo ./mb monitor logs
```

This command checks whether the Loki stack is running and prints the container status, readiness, and a few example LogQL queries.

## Configuration files

| File | Purpose |
|------|---------|
| `compose/loki.yml` | docker-compose template for Loki + Promtail |
| `agents/loki-config.yml` | Loki single-node configuration (bind-mounted) |
| `agents/promtail-config.yml` | Promtail scrape config for host logs (bind-mounted) |
| `agents/promtail-docker.yml` | Example scrape config for Docker container logs |
| `compose/.env.example` | Optional `LOKI_PORT` and `LOKI_RETENTION` overrides |

## Best practices

- **Pin image tags**: the template pins `grafana/loki:3.2.1` and `grafana/promtail:3.2.1`. Bump tags deliberately after testing.
- **Bind Loki to localhost**: the template publishes port 3100 on `127.0.0.1` only. Do not expose it publicly — Loki has no built-in auth.
- **Use labels sparingly**: Loki indexes labels, not log bodies. Keep the label cardinality low (host, program, job) to avoid index explosion.
- **Pair with CrowdSec**: CrowdSec blocks attackers in real time; Loki retains the logs for post-incident forensics. Together they give you both prevention and auditability.
- **Monitor disk usage**: Loki is disk-bound on a single VPS. Watch `/data/loki` and tighten retention before it fills up.
- **Back up `/data/loki`**: include it in your monitor-stack backup tarball so historical logs survive a host rebuild.
