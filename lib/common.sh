#!/usr/bin/env bash
# common.sh — Shared functions for the monitor-stack CLI.
# Part of the 0x10debug VPS tool suite.
# https://github.com/0x10debug/monitor-stack

# Prevent direct execution — this file is sourced.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "common.sh is meant to be sourced, not executed." >&2; exit 1; }

# ─── Version ─────────────────────────────────────────────────
MB_MONITOR_VERSION="1.0.0"

# ─── Paths ───────────────────────────────────────────────────
MB_MONITOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # used by mb CLI when sourced
MB_COMPOSE_DIR="${MB_MONITOR_DIR}/compose"
# shellcheck disable=SC2034 # used by mb CLI when sourced
MB_DEPLOY_DIR="/opt/mb-monitor"
# shellcheck disable=SC2034 # used by alert.sh when sourced
MB_ALERT_CONFIG_DIR="/data/monitor-alerts"

# ─── Colors ──────────────────────────────────────────────────
if [[ -t 1 ]]; then
    MB_C_RESET="\033[0m"
    MB_C_BOLD="\033[1m"
    MB_C_RED="\033[31m"
    MB_C_GREEN="\033[32m"
    MB_C_YELLOW="\033[33m"
    MB_C_BLUE="\033[34m"
    MB_C_GRAY="\033[90m"
else
    MB_C_RESET=""; MB_C_BOLD=""; MB_C_RED=""; MB_C_GREEN=""
    MB_C_YELLOW=""; MB_C_BLUE=""; MB_C_GRAY=""
fi

# ─── Logging ─────────────────────────────────────────────────
mb_step()   { printf "\n${MB_C_BOLD}${MB_C_BLUE}▶ %s${MB_C_RESET}\n" "$*"; }
mb_info()   { printf "${MB_C_BOLD}%s${MB_C_RESET}\n" "$*"; }
mb_detail() { printf "  ${MB_C_GRAY}%s${MB_C_RESET}\n" "$*"; }
mb_success() { printf "${MB_C_GREEN}✓ %s${MB_C_RESET}\n" "$*"; }
mb_warn()   { printf "${MB_C_YELLOW}⚠ %s${MB_C_RESET}\n" "$*" >&2; }
mb_error()  { printf "${MB_C_RED}✗ %s${MB_C_RESET}\n" "$*" >&2; }
mb_die()    { mb_error "$*"; exit 1; }

# ─── Interactive helpers ─────────────────────────────────────
mb_ask() {
    # mb_ask "Prompt" -> returns 0 for yes, 1 for no
    local prompt="$1"
    local reply
    read -rp "$(printf "${MB_C_BOLD}?${MB_C_RESET} %s [y/N] " "$prompt")" reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

mb_ask_value() {
    # mb_ask_value "Prompt" "default" -> echoes the value
    local prompt="$1"
    local default="${2:-}"
    local reply
    if [[ -n "$default" ]]; then
        read -rp "$(printf "${MB_C_BOLD}?${MB_C_RESET} %s [${default}]: " "$prompt")" reply
        echo "${reply:-$default}"
    else
        read -rp "$(printf "${MB_C_BOLD}?${MB_C_RESET} %s: " "$prompt")" reply
        echo "$reply"
    fi
}

mb_ask_secret() {
    # mb_ask_secret "Prompt" -> echoes the value (hidden input)
    local prompt="$1"
    local reply
    read -rsp "$(printf "${MB_C_BOLD}?${MB_C_RESET} %s: " "$prompt")" reply
    printf '\n'
    echo "$reply"
}

# ─── Checks ──────────────────────────────────────────────────
mb_check_command() {
    # mb_check_command "docker" "curl" -> dies if any missing
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            mb_die "Required command not found: $cmd"
        fi
    done
}

mb_check_docker() {
    mb_check_command "docker"
    if ! docker info >/dev/null 2>&1; then
        mb_die "Docker daemon is not running. Start it with: sudo systemctl start docker"
    fi
}

mb_check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        mb_die "This command requires root privileges. Run with sudo."
    fi
}

# ─── Docker network helpers ──────────────────────────────────
mb_ensure_proxy_network() {
    local network="${1:-mb-proxy}"
    if ! docker network inspect "$network" >/dev/null 2>&1; then
        mb_step "Creating Docker network: $network"
        if docker network create "$network" >/dev/null 2>&1; then
            mb_success "Network '$network' created"
        else
            mb_die "Failed to create network '$network'"
        fi
    else
        mb_detail "Network '$network' already exists"
    fi
}

# ─── Misc ────────────────────────────────────────────────────
mb_version() {
    printf "monitor-stack v%s\n" "$MB_MONITOR_VERSION"
}

mb_confirm_or_die() {
    # mb_confirm_or_die "Are you sure?" -> dies on no
    local prompt="${1:-Proceed?}"
    mb_ask "$prompt" || mb_die "Aborted by user."
}
