# Adding Hosts

How to add remote servers for monitoring with the Beszel agent.

## Overview

The monitor-stack uses [Beszel](https://github.com/henrygd/beszel) for performance monitoring. The architecture is hub-and-spoke:

- **Beszel Hub** runs on your monitoring server (deployed with the stack).
- **Beszel Agent** runs on each remote node and reports metrics to the hub.

The agent initiates an **outbound** connection to the hub, so remote nodes behind a firewall or NAT do not need any inbound ports opened — only the hub must be reachable from the node.

## Prerequisites on the remote node

- Linux (amd64 or arm64)
- systemd
- root or sudo access
- curl
- Network access to the Beszel Hub (port 8090 by default)

## Step 1 — Generate an agent key in Beszel Hub

1. Open the Beszel Hub web UI at `http://your-monitor-server:8090`.
2. Log in and go to **Settings → Add System**.
3. Enter a name for the remote node.
4. Copy the generated **agent key** and the **hub URL**.

## Step 2 — Install the agent

### Option A: Using the CLI (recommended)

From your monitoring server:

```bash
sudo ./mb monitor add-host
```

The CLI will prompt for:

| Field | Description |
|-------|-------------|
| Hub URL | The Beszel Hub address (e.g. `http://monitor.example.com:8090`) |
| Agent key | The key generated in Step 1 |
| Node name | Display name for the node |
| SSH target | `user@ip` of the remote server |

The CLI copies the agent script to the remote node via SCP and runs it via SSH.

### Option B: Manual installation on the remote node

Download and run the agent script directly on the remote server:

```bash
# On the remote node
curl -fsSL https://raw.githubusercontent.com/0x10debug/monitor-stack/main/agents/beszel-agent.sh -o beszel-agent.sh
chmod +x beszel-agent.sh
sudo ./beszel-agent.sh \
    --hub-url http://monitor.example.com:8090 \
    --key YOUR_AGENT_KEY \
    --node-name my-server-01
```

## Step 3 — Verify the connection

1. Return to the Beszel Hub web UI.
2. The new node should appear in the systems list with live metrics.
3. If it does not appear, check the agent logs on the remote node:

```bash
sudo journalctl -u beszel-agent -f
```

## Managing agents

### Check agent status

```bash
sudo systemctl status beszel-agent
```

### View agent logs

```bash
sudo journalctl -u beszel-agent -n 50
```

### Restart the agent

```bash
sudo systemctl restart beszel-agent
```

### Remove an agent

```bash
sudo systemctl stop beszel-agent
sudo systemctl disable beszel-agent
sudo rm /etc/systemd/system/beszel-agent.service
sudo rm /usr/local/bin/beszel-agent
sudo systemctl daemon-reload
```

Then remove the system from the Beszel Hub UI.

## Idempotency

The `beszel-agent.sh` script is idempotent. If the agent is already running and connected to the same hub URL, the script exits cleanly without reinstalling. If the hub URL differs, it reconfigures the existing installation.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent does not connect | Verify the hub URL is reachable: `curl http://hub-url:8090` |
| Wrong architecture | The script auto-detects amd64/arm64. Check `uname -m` on the node. |
| Permission denied | Ensure the script runs as root: `sudo ./beszel-agent.sh ...` |
| Firewall blocking | The agent makes outbound connections only. Check outbound rules on the node. |
| Key rejected | Regenerate the key in Beszel Hub and reinstall the agent. |
