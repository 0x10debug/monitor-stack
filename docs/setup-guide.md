# Setup Guide

Complete step-by-step instructions for deploying the monitor-stack on your VPS.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| OS | Linux (Ubuntu 22.04+ recommended, Debian 12+, CentOS 8+) |
| Docker | Docker Engine 20.10+ and Docker Compose v2+ |
| RAM | 512 MB minimum (1 GB recommended) |
| Disk | 2 GB minimum for data |
| Network | A domain name pointing to your server (for HTTPS) |
| Access | Root or sudo privileges |

### Install Docker (if not already installed)

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# Log out and back in for the group change to take effect
```

## Step 1 — Clone the repository

```bash
git clone https://github.com/0x10debug/monitor-stack.git
cd monitor-stack
```

## Step 2 — Deploy the stack

```bash
sudo ./mb monitor deploy
```

The CLI will:

1. **Create the `mb-proxy` Docker network** — an external network shared with your reverse proxy.
2. **Generate a `.env` file** — prompts you for your monitoring domain (e.g. `monitor.example.com`).
3. **Copy the compose file** to `/opt/mb-monitor/compose.yml`.
4. **Create data directories** at `/data/uptime-kuma` and `/data/beszel`.
5. **Start the containers** with `docker compose up -d`.

## Step 3 — Configure the reverse proxy

### Using Caddy (recommended)

1. Copy the example Caddyfile:

```bash
sudo cp compose/Caddyfile.example /etc/caddy/conf.d/monitor.caddy
```

2. Edit the file and replace `MONITOR_DOMAIN` and `status.MONITOR_DOMAIN` with your actual domains:

```bash
sudo nano /etc/caddy/conf.d/monitor.caddy
```

3. Reload Caddy:

```bash
sudo systemctl reload caddy
```

Caddy will automatically provision TLS certificates via Let's Encrypt.

### Using nginx

Create a server block that reverse-proxies to `uptime-kuma:3001` and `beszel-hub:8090`. Ensure nginx is on the same Docker network or can reach the containers by IP.

## Step 4 — Set up Uptime Kuma

1. Open `https://monitor.example.com` (or `http://localhost:3001`).
2. Create your admin account on first visit.
3. Go to **Settings → Appearance** to customize the dashboard.
4. Add your first monitor (see [Adding Hosts](add-hosts.md)).

## Step 5 — Set up Beszel Hub

1. Open `https://monitor.example.com:8090` (or `http://localhost:8090`).
2. Register a new account.
3. Go to **Settings → Add System** to generate an agent key.
4. Use `mb monitor add-host` to install the agent on remote nodes.

## Step 6 — Configure alerts

```bash
sudo ./mb monitor alert setup
sudo ./mb monitor alert test
```

See [Alert Configuration](alert-configuration.md) for details.

## Verify the deployment

```bash
sudo ./mb monitor status
```

You should see both `uptime-kuma` and `beszel-hub` containers running.

## Data locations

| Service | Path |
|---------|------|
| Uptime Kuma data | `/data/uptime-kuma` |
| Beszel Hub data | `/data/beszel` |
| Alert configs | `/data/monitor-alerts` |
| Deploy directory | `/opt/mb-monitor` |

## Next steps

- [Add remote hosts](add-hosts.md)
- [Configure alert channels](alert-configuration.md)
- [Integrate CrowdSec security monitoring](security-monitoring.md)
- Deploy the [status page](../dashboards/status-page.html)
