# Availability Monitoring with Blackbox Exporter

How to deploy the Blackbox Exporter for active endpoint probing and wire it into Prometheus and Grafana.

## Overview

[Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) is a Prometheus exporter that performs blackbox probing of endpoints over HTTP, HTTPS, TCP, and ICMP. Unlike Node Exporter (which reports metrics about the host it runs on), Blackbox Exporter probes external targets from the outside — exactly the way your users reach them — and exposes the results as Prometheus metrics: `probe_success`, `probe_duration_seconds`, `probe_ssl_earliest_cert_expiry`, `probe_http_status_code`, and more.

The monitor-stack ships a ready-to-use docker-compose template at `compose/blackbox.yml`. It runs the exporter with a pinned image tag, a healthcheck, and the probe modules defined in `agents/blackbox.yml`. Prometheus scrape configs and alert rules are provided as drop-in examples so you can wire the exporter into an existing Prometheus instance without writing config from scratch.

## Architecture

```
┌───────────────┐   probe    ┌─────────────────────┐   scrape   ┌──────────────┐   alert   ┌──────────────┐
│  HTTP / TCP / │ ─────────▶ │ Blackbox Exporter   │ ─────────▶ │ Prometheus   │ ────────▶ │ Alertmanager │
│  ICMP targets │            │  (port 9115)        │            │  (scrape +   │           │  (notify)    │
└───────────────┘            └─────────────────────┘            │   rules)    │           └──────────────┘
                                  ▲                            └──────┬──────┘
                                  │                                   │ query
                                  │                              ┌────▼─────┐
                                  └── /probe?target=...&module=.. │ Grafana  │
                                                                 └──────────┘
```

Prometheus scrapes the exporter's `/probe` endpoint with the target encoded as a query parameter. The exporter performs the probe and returns metrics. The original endpoint is preserved on the `instance` label so alerts and dashboards show the probed URL, not the exporter address.

## Probe modules

`agents/blackbox.yml` defines four named modules. Each is a self-contained probe profile selected via the `module` query parameter.

| Module | Prober | What it checks | Use case |
|--------|--------|----------------|----------|
| `http_2xx` | HTTP | GET, expect 2xx, follow redirects, record SSL cert expiry | Web endpoints, API health checks |
| `http_post_2xx` | HTTP | POST with JSON body, expect 2xx | API endpoints that reject GET |
| `tcp_connect` | TCP | TCP port accepts a connection | Database/cache ports (5432, 3306, 6379) |
| `icmp` | ICMP | Host responds to ping | Gateway/router reachability, host-up checks |

ICMP probing requires the `NET_RAW` capability, which `compose/blackbox.yml` grants to the container. On some kernels you may also need to widen `net.ipv4.ping_group_range` so the container's GID can send raw ping packets.

## Step 1 — Deploy the exporter

The Blackbox Exporter is a standalone compose template. Deploy it alongside the main stack:

```bash
# Option A: run alongside the main monitor-stack
sudo docker compose -f compose/compose.yml -f compose/blackbox.yml up -d

# Option B: run the exporter on its own
sudo docker compose -f compose/blackbox.yml up -d
```

The exporter joins the `mb-proxy` external network so Prometheus (running in the main stack or a sibling stack) can reach it at `http://blackbox-exporter:9115`.

## Step 2 — Verify the exporter

```bash
# The exporter should report "OK"
curl -s http://127.0.0.1:9115/-/healthy

# Test a probe manually — look for probe_success="1" in the output
curl -s 'http://127.0.0.1:9115/probe?target=https://example.com&module=http_2xx' | grep probe_success

# Container status
sudo docker compose -f compose/blackbox.yml ps
```

The healthcheck in `compose/blackbox.yml` hits `/-/healthy` every 30s, so `docker ps` will show the container as healthy once it is ready.

## Step 3 — Wire the exporter into Prometheus

Append the scrape configs from `agents/prometheus-blackbox-targets.yml` to the `scrape_configs` list in your `prometheus.yml`, then add the alert rules file to `rule_files`:

```yaml
# prometheus.yml (excerpt)
rule_files:
  - /etc/prometheus/prometheus-blackbox-rules.yml

scrape_configs:
  # ... your existing scrape configs ...
  # Append the contents of agents/prometheus-blackbox-targets.yml here.
```

If your Prometheus runs outside the `mb-proxy` Docker network, replace `blackbox-exporter:9115` with `127.0.0.1:9115` in the `replacement` fields of the relabel configs (the port is published on localhost).

Reload Prometheus after editing:

```bash
# Send a reload signal, or restart the container
sudo docker kill -s SIGHUP prometheus
```

Confirm the targets are up in the Prometheus UI at **Status → Targets** — the `blackbox_*` jobs should show state `UP`.

## Step 4 — Add Prometheus as a Grafana data source

1. Open Grafana (or deploy it — see the main setup guide).
2. Go to **Connections → Data sources → Add data source**.
3. Select **Prometheus**.
4. Set the URL to `http://prometheus:9090` (the in-network service name).
5. Click **Save & test**. Grafana should report "Data source is working."

## Step 5 — Build a Blackbox dashboard in Grafana

There is no pre-built dashboard JSON shipped with this stack (the probe metrics are simple enough to build ad-hoc panels). Here are the panels that cover the alert rules:

| Panel | Query | Visualization |
|-------|-------|---------------|
| Service up/down | `probe_success` | Stat (green=1, red=0) |
| Probe latency | `probe_duration_seconds` | Time series |
| SSL cert days to expiry | `(probe_ssl_earliest_cert_expiry - time()) / 86400` | Stat / gauge |
| HTTP status code | `probe_http_status_code` | Stat |
| Probe failures (last 1h) | `sum by (instance) (probe_success == 0)` | Table |

To create the dashboard:

1. Open Grafana → **Dashboards → New → New Dashboard**.
2. Add a panel for each query above, selecting the Prometheus data source.
3. For the up/down stat panel, set **Value mappings**: 1 → "Up" (green), 0 → "Down" (red).
4. For the SSL panel, set a threshold at 7 days (warning) and 0 days (critical) so the gauge turns yellow/red before expiry.
5. Save the dashboard as "Blackbox Availability".

If you want a ready-made dashboard, the Prometheus community maintains one at [grafana.com dashboards](https://grafana.com/grafana/dashboards/) — search for "blackbox exporter". Import it by ID and point it at your Prometheus data source.

## Alert rules

`agents/prometheus-blackbox-rules.yml` defines four alerts. Tune the `for` durations and severity labels to match your on-call expectations.

| Alert | Expression | For | Severity | Meaning |
|-------|-----------|-----|----------|---------|
| `BlackboxProbeFailed` | `probe_success == 0` | 2m | critical | A probe has failed continuously for 2 minutes — the service is down. |
| `BlackboxSslCertificateExpiringSoon` | `probe_ssl_earliest_cert_expiry - time() < 7d` | 5m | warning | The SSL certificate for a probed HTTPS endpoint expires in less than 7 days. |
| `BlackboxProbeHighLatency` | `probe_duration_seconds > 2` | 5m | warning | A probe is taking longer than 2 seconds — the endpoint is slow. |
| `BlackboxProbeHttpStatusAnomaly` | `probe_http_status_code >= 400` | 2m | warning | The probed endpoint returned a 4xx/5xx status code. |

The 2-minute `for` buffer on `BlackboxProbeFailed` absorbs transient network blips and single scrape failures without paging. Lower it to 30s if you want faster notification at the cost of more noise.

## Step 6 — Monitor with the CLI

```bash
sudo ./mb monitor availability
```

This command checks whether the Blackbox Exporter is running, reports container status and health, and prints the probe module list and example scrape config snippets.

## Configuration files

| File | Purpose |
|------|---------|
| `compose/blackbox.yml` | docker-compose template for the Blackbox Exporter |
| `agents/blackbox.yml` | Probe module definitions (http_2xx, http_post_2xx, tcp_connect, icmp) — bind-mounted |
| `agents/prometheus-blackbox-targets.yml` | Example Prometheus scrape configs for HTTP/TCP/ICMP probes |
| `agents/prometheus-blackbox-rules.yml` | Prometheus alert rules (down, SSL expiry, latency, status anomaly) |
| `compose/.env.example` | Optional `BLACKBOX_PORT` override |

## Best practices

- **Pin image tags**: the template pins `prom/blackbox-exporter:v0.25.0`. Bump tags deliberately after testing.
- **Bind to localhost**: the template publishes port 9115 on `127.0.0.1` only. Do not expose it publicly — the `/probe` endpoint can be abused as an open redirect / SSRF vector if it is reachable from the internet.
- **Keep probe targets in version control**: store your real targets in `prometheus-blackbox-targets.yml` (or a generated config) so changes are reviewable. The shipped file is an example — replace the placeholder endpoints with your own.
- **Pair with Uptime Kuma**: Uptime Kuma gives you a user-facing status page and push notifications; Blackbox Exporter gives you Prometheus-native metrics and alert rules. Together they cover both human-facing and machine-facing availability monitoring.
- **Tune the SSL threshold**: the 7-day warning gives you lead time for manual renewal. If you use automated renewal (acme.sh, certbot), lower it to 3 days so the alert only fires when automation has actually failed.
- **Watch ICMP permissions**: if ICMP probes fail with permission errors, widen `net.ipv4.ping_group_range` on the host or run the exporter with `--privileged` (less secure — prefer the GID range fix).
