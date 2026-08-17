#!/usr/bin/env bash
# alert.sh — Alert channel configuration functions for monitor-stack.
# Part of the 0x10debug VPS tool suite.
# https://github.com/0x10debug/monitor-stack

# Prevent direct execution — this file is sourced.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "alert.sh is meant to be sourced, not executed." >&2; exit 1; }

# Requires: common.sh sourced first (for MB_ALERT_CONFIG_DIR and logging functions)

# ─── Ensure config directory exists ──────────────────────────
_mb_alert_ensure_dir() {
    mkdir -p "$MB_ALERT_CONFIG_DIR" 2>/dev/null || true
}

# ─── Setup a single alert channel ────────────────────────────
mb_alert_setup() {
    _mb_alert_ensure_dir

    mb_step "Alert Channel Setup"

    local channels="telegram discord email slack"
    mb_info "Available channels:"
    mb_detail "  telegram  — Telegram bot notifications"
    mb_detail "  discord   — Discord webhook notifications"
    mb_detail "  email     — SMTP email notifications"
    mb_detail "  slack     — Slack webhook notifications"
    echo

    local channel
    channel="$(mb_ask_value "Which channel to configure" "")"
    [[ -n "$channel" ]] || mb_die "No channel specified."

    # Validate channel name
    local valid=0
    local c
    for c in $channels; do
        [[ "$channel" == "$c" ]] && { valid=1; break; }
    done
    [[ "$valid" -eq 1 ]] || mb_die "Unknown channel: $channel (valid: telegram, discord, email, slack)"

    local config_file="${MB_ALERT_CONFIG_DIR}/${channel}.json"

    case "$channel" in
        telegram)
            local bot_token chat_id
            bot_token="$(mb_ask_secret "Telegram bot token")"
            chat_id="$(mb_ask_value "Telegram chat ID" "")"
            [[ -n "$bot_token" ]] || mb_die "Bot token is required."
            [[ -n "$chat_id" ]]   || mb_die "Chat ID is required."
            cat > "$config_file" <<EOF
{
  "channel": "telegram",
  "enabled": true,
  "config": {
    "bot_token": "${bot_token}",
    "chat_id": "${chat_id}"
  },
  "message_template": {
    "text": "🔔 *{{alert_type}}*\n*Service:* {{service_name}}\n*Status:* {{status}}\n*Time:* {{timestamp}}\n*Message:* {{message}}"
  }
}
EOF
            ;;
        discord)
            local webhook_url
            webhook_url="$(mb_ask_value "Discord webhook URL" "")"
            [[ -n "$webhook_url" ]] || mb_die "Webhook URL is required."
            cat > "$config_file" <<EOF
{
  "channel": "discord",
  "enabled": true,
  "config": {
    "webhook_url": "${webhook_url}"
  },
  "message_template": {
    "embeds": [
      {
        "title": "{{alert_type}} — {{service_name}}",
        "description": "**Status:** {{status}}\n**Time:** {{timestamp}}\n**Message:** {{message}}",
        "color": 16711680
      }
    ]
  }
}
EOF
            ;;
        email)
            local smtp_host smtp_port username password from to
            smtp_host="$(mb_ask_value "SMTP host" "")"
            smtp_port="$(mb_ask_value "SMTP port" "587")"
            username="$(mb_ask_value "SMTP username" "")"
            password="$(mb_ask_secret "SMTP password")"
            from="$(mb_ask_value "From address" "")"
            to="$(mb_ask_value "To address" "")"
            [[ -n "$smtp_host" ]] || mb_die "SMTP host is required."
            [[ -n "$from" ]]      || mb_die "From address is required."
            [[ -n "$to" ]]        || mb_die "To address is required."
            cat > "$config_file" <<EOF
{
  "channel": "email",
  "enabled": true,
  "config": {
    "smtp_host": "${smtp_host}",
    "smtp_port": ${smtp_port},
    "username": "${username}",
    "password": "${password}",
    "from": "${from}",
    "to": "${to}"
  },
  "message_template": {
    "subject_template": "[{{alert_type}}] {{service_name}} is {{status}}",
    "body_template": "Alert Type: {{alert_type}}\nService: {{service_name}}\nStatus: {{status}}\nTime: {{timestamp}}\n\nMessage:\n{{message}}"
  }
}
EOF
            ;;
        slack)
            local webhook_url slack_channel
            webhook_url="$(mb_ask_value "Slack webhook URL" "")"
            slack_channel="$(mb_ask_value "Slack channel" "#alerts")"
            [[ -n "$webhook_url" ]] || mb_die "Webhook URL is required."
            cat > "$config_file" <<EOF
{
  "channel": "slack",
  "enabled": true,
  "config": {
    "webhook_url": "${webhook_url}",
    "channel": "${slack_channel}"
  },
  "message_template": {
    "text": ":rotating_light: *{{alert_type}}* — \`{{service_name}}\` is *{{status}}*\n> {{message}}\n_Time: {{timestamp}}_"
  }
}
EOF
            ;;
    esac

    chmod 600 "$config_file" 2>/dev/null || true
    mb_success "Alert channel '$channel' configured at $config_file"
    mb_detail "Run 'mb monitor alert test' to send a test notification."
}

# ─── Send a test alert ───────────────────────────────────────
mb_alert_test() {
    _mb_alert_ensure_dir

    local channels=()
    local f
    for f in "$MB_ALERT_CONFIG_DIR"/*.json; do
        [[ -f "$f" ]] && channels+=("$(basename "$f" .json)")
    done

    if [[ ${#channels[@]} -eq 0 ]]; then
        mb_die "No alert channels configured. Run 'mb monitor alert setup' first."
    fi

    mb_step "Test Alert"

    local channel
    mb_info "Configured channels: ${channels[*]}"
    channel="$(mb_ask_value "Which channel to test" "${channels[0]}")"

    local config_file="${MB_ALERT_CONFIG_DIR}/${channel}.json"
    [[ -f "$config_file" ]] || mb_die "No config found for channel '$channel'."

    mb_detail "Sending test alert via $channel..."

    local test_msg="This is a test alert from monitor-stack (channel: $channel)."
    local success=0

    case "$channel" in
        telegram)
            local bot_token chat_id
            bot_token="$(grep -oP '(?<="bot_token": ")[^"]*' "$config_file" 2>/dev/null || true)"
            chat_id="$(grep -oP '(?<="chat_id": ")[^"]*' "$config_file" 2>/dev/null || true)"
            if [[ -n "$bot_token" && -n "$chat_id" ]]; then
                curl -fsSL -X POST \
                    "https://api.telegram.org/bot${bot_token}/sendMessage" \
                    -d "chat_id=${chat_id}" \
                    -d "text=${test_msg}" >/dev/null 2>&1 && success=1
            fi
            ;;
        discord)
            local webhook_url
            webhook_url="$(grep -oP '(?<="webhook_url": ")[^"]*' "$config_file" 2>/dev/null || true)"
            if [[ -n "$webhook_url" ]]; then
                curl -fsSL -X POST "$webhook_url" \
                    -H "Content-Type: application/json" \
                    -d "{\"content\":\"${test_msg}\"}" >/dev/null 2>&1 && success=1
            fi
            ;;
        email)
            mb_warn "Email test requires an SMTP client (e.g. swaks or mailutils)."
            mb_detail "Config is stored at $config_file — use it with your mailer."
            mb_detail "Example: swaks --to <to> --from <from> --server <smtp_host>:<smtp_port> --body '$test_msg'"
            success=1  # Mark as informational success
            ;;
        slack)
            local webhook_url
            webhook_url="$(grep -oP '(?<="webhook_url": ")[^"]*' "$config_file" 2>/dev/null || true)"
            if [[ -n "$webhook_url" ]]; then
                curl -fsSL -X POST "$webhook_url" \
                    -H "Content-Type: application/json" \
                    -d "{\"text\":\"${test_msg}\"}" >/dev/null 2>&1 && success=1
            fi
            ;;
        *)
            mb_warn "Unknown channel type: $channel"
            ;;
    esac

    if [[ "$success" -eq 1 ]]; then
        mb_success "Test alert sent via $channel"
    else
        mb_die "Failed to send test alert via $channel — check your config and network."
    fi
}

# ─── List configured alert channels ──────────────────────────
mb_alert_list() {
    _mb_alert_ensure_dir

    mb_step "Configured Alert Channels"

    local found=0
    local f
    for f in "$MB_ALERT_CONFIG_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        found=1
        local name
        name="$(basename "$f" .json)"
        local enabled
        enabled="$(grep -oP '(?<="enabled": )(true|false)' "$f" 2>/dev/null || echo "unknown")"
        if [[ "$enabled" == "true" ]]; then
            mb_success "$name — enabled"
        else
            mb_detail "$name — disabled"
        fi
        mb_detail "  config: $f"
    done

    if [[ "$found" -eq 0 ]]; then
        mb_warn "No alert channels configured."
        mb_detail "Run 'mb monitor alert setup' to configure one."
    fi
}
