# Alert Configuration

How to configure alert channels for the monitor-stack.

## Overview

The monitor-stack supports four alert channels:

| Channel | Delivery Method | Use Case |
|---------|----------------|----------|
| Telegram | Bot API | Instant mobile notifications |
| Discord | Webhook | Team chat notifications |
| Email | SMTP | Formal incident records |
| Slack | Webhook | Team collaboration alerts |

Alert configurations are stored as JSON files in `/data/monitor-alerts/` with `0600` file permissions.

## Setup

### Interactive setup

```bash
sudo ./mb monitor alert setup
```

The CLI will:

1. Display available channels.
2. Prompt you to choose one.
3. Ask for the required configuration values.
4. Write the config to `/data/monitor-alerts/<channel>.json`.
5. Set file permissions to `0600`.

### Send a test alert

```bash
sudo ./mb monitor alert test
```

### List configured channels

```bash
sudo ./mb monitor alert list
```

## Channel-specific guides

### Telegram

1. Create a bot via [@BotFather](https://t.me/BotFather):
   - Send `/newbot` to BotFather
   - Follow the prompts to name it
   - Copy the **bot token**

2. Get your chat ID:
   - Add the bot to a group or start a private chat
   - Send a message to the bot
   - Visit `https://api.telegram.org/bot<TOKEN>/getUpdates`
   - Find `"chat":{"id":XXXXXXXXX}` in the response

3. Run the setup:
   ```bash
   sudo ./mb monitor alert setup
   # Choose: telegram
   # Enter bot token and chat ID
   ```

### Discord

1. Create a webhook in your Discord server:
   - Go to **Server Settings → Integrations → Webhooks**
   - Click **New Webhook**
   - Choose a channel and copy the **Webhook URL**

2. Run the setup:
   ```bash
   sudo ./mb monitor alert setup
   # Choose: discord
   # Enter the webhook URL
   ```

### Email

1. Prepare your SMTP credentials:
   - SMTP host and port (e.g. `smtp.gmail.com:587`)
   - Username and password (use an app password for Gmail)
   - From and To addresses

2. Run the setup:
   ```bash
   sudo ./mb monitor alert setup
   # Choose: email
   # Enter SMTP details
   ```

3. For testing, install an SMTP client:
   ```bash
   sudo apt install swaks  # Debian/Ubuntu
   ```

4. Test manually:
   ```bash
   swaks --to admin@example.com --from alerts@example.com \
         --server smtp.example.com:587 --auth LOGIN \
         --body "Test alert from monitor-stack"
   ```

### Slack

1. Create an incoming webhook:
   - Go to **https://api.slack.com/messaging/webhooks**
   - Create a new webhook for your workspace
   - Choose a channel (e.g. `#alerts`)
   - Copy the **Webhook URL**

2. Run the setup:
   ```bash
   sudo ./mb monitor alert setup
   # Choose: slack
   # Enter the webhook URL and channel name
   ```

## Configuration file format

Each channel stores its config as JSON. Example (Telegram):

```json
{
  "channel": "telegram",
  "enabled": true,
  "config": {
    "bot_token": "123456:ABC-DEF...",
    "chat_id": "-1001234567890"
  },
  "message_template": {
    "text": "🔔 *{{alert_type}}*\n*Service:* {{service_name}}\n*Status:* {{status}}\n*Time:* {{timestamp}}\n*Message:* {{message}}"
  }
}
```

### Template variables

| Variable | Description |
|----------|-------------|
| `{{alert_type}}` | Type of alert (e.g. `down`, `up`, `degraded`) |
| `{{service_name}}` | Name of the monitored service |
| `{{status}}` | Current status (e.g. `DOWN`, `UP`) |
| `{{timestamp}}` | ISO 8601 timestamp of the event |
| `{{message}}` | Alert message body |

## Uptime Kuma notification integration

After configuring alert channels in monitor-stack, also set up notifications directly in Uptime Kuma:

1. Open Uptime Kuma → **Settings → Notifications**.
2. Add a new notification matching your channel type.
3. Enter the same credentials from your `/data/monitor-alerts/<channel>.json`.
4. Assign the notification to your monitors.

This ensures Uptime Kuma sends alerts through your configured channel when a monitor goes down.

## Security notes

- Alert config files are stored with `0600` permissions (root read/write only).
- The `/data/monitor-alerts/` directory is not exposed by any container.
- SMTP passwords and bot tokens are stored in plaintext in the JSON files — protect your VPS access accordingly.
- Consider using app-specific passwords (Gmail, Outlook) rather than primary account passwords.
