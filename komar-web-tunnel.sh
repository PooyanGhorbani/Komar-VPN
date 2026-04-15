#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Komar Web Tunnel"
APP_VERSION="0.12"
APP_DIR="/opt/komar-web-tunnel"
STATE_FILE="$APP_DIR/state.env"
ENV_FILE_DEFAULT="$APP_DIR/.env"
TOKEN_FILE="$APP_DIR/tunnel.token"
UNIT_FILE="/etc/systemd/system/komar-web-tunnel.service"

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLU}[*]${NC} $*"; }
ok() { echo -e "${GRN}[+]${NC} $*"; }
warn() { echo -e "${YEL}[!]${NC} $*"; }
err() { echo -e "${RED}[x]${NC} $*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<EOF
$APP_NAME $APP_VERSION

Usage:
  sudo bash $0 install [env-file]
  sudo bash $0 sync [env-file]
  sudo bash $0 uninstall [env-file]
  sudo bash $0 state

Environment / .env values:
  CF_API_TOKEN=...
  ACCOUNT_ID=...
  ZONE_ID=...
  TUNNEL_NAME=komar-web
  HOSTNAME_MAP=app.example.com=http://localhost:8080;api.example.com=http://localhost:3000

Single-host convenience variables are also supported:
  DOMAIN=example.com
  SUBDOMAIN=app
  LOCAL_SERVICE=http://localhost:8080

Notes:
  - install: create or reuse tunnel from state, configure ingress, upsert DNS, install systemd service
  - sync: update ingress + DNS from .env or state, then restart service
  - uninstall: remove service; if API token is available, also delete managed DNS records and the tunnel
  - state: print saved state summary
EOF
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Please run as root: sudo bash $0"
  fi
}

os_id() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  log "Loading settings from $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" != *=* ]] && continue
    local key="${line%%=*}"
    local val="${line#*=}"
    key="$(trim "$key")"
    val="$(trim "$val")"
    if [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val:1:-1}"
    elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val:1:-1}"
    fi
    export "$key=$val"
  done < "$file"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    return 0
  fi
  return 1
}

shell_escape() {
  printf '%q' "$1"
}

save_state() {
  mkdir -p "$APP_DIR"
  chmod 700 "$APP_DIR"
  cat > "$STATE_FILE" <<STATE
APP_NAME=$(shell_escape "$APP_NAME")
APP_VERSION=$(shell_escape "$APP_VERSION")
ACCOUNT_ID=$(shell_escape "$ACCOUNT_ID")
ZONE_ID=$(shell_escape "$ZONE_ID")
TUNNEL_NAME=$(shell_escape "$TUNNEL_NAME")
TUNNEL_ID=$(shell_escape "$TUNNEL_ID")
TUNNEL_TOKEN=$(shell_escape "$TUNNEL_TOKEN")
HOSTNAME_MAP=$(shell_escape "$HOSTNAME_MAP")
SOURCE_ENV_FILE=$(shell_escape "${SOURCE_ENV_FILE:-}")
STATE
  chmod 600 "$STATE_FILE"
  printf '%s' "$TUNNEL_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  ok "State saved to $STATE_FILE"
}

install_pkg_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl jq ca-certificates
}

install_pkg_rhel() {
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl jq ca-certificates
  else
    yum install -y curl jq ca-certificates
  fi
}

install_pkg_alpine() {
  apk add --no-cache curl jq ca-certificates
}

ensure_base_deps() {
  local id
  id="$(os_id)"
  if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ok "curl and jq are present"
    return
  fi
  log "Installing base dependencies"
  case "$id" in
    ubuntu|debian) install_pkg_debian ;;
    centos|rhel|rocky|almalinux|fedora) install_pkg_rhel ;;
    alpine) install_pkg_alpine ;;
    *) die "Unsupported OS for automatic dependency install: $id" ;;
  esac
}

cloudflared_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l) echo "arm" ;;
    i386|i686) echo "386" ;;
    *) die "Unsupported architecture for cloudflared: $(uname -m)" ;;
  esac
}

install_cloudflared() {
  if command -v cloudflared >/dev/null 2>&1; then
    ok "cloudflared is already installed"
    return
  fi
  local arch tmp
  arch="$(cloudflared_arch)"
  tmp="$(mktemp)"
  log "Installing cloudflared binary (${arch})"
  curl --fail --show-error --location \
    --output "$tmp" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"
  install -m 0755 "$tmp" /usr/local/bin/cloudflared
  rm -f "$tmp"
  command -v cloudflared >/dev/null 2>&1 || die "cloudflared installation failed"
  ok "cloudflared installed"
}

api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local url="https://api.cloudflare.com/client/v4${endpoint}"
  if [[ -n "$data" ]]; then
    curl --silent --show-error --fail-with-body "$url" \
      --request "$method" \
      --header "Authorization: Bearer $CF_API_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$data"
  else
    curl --silent --show-error --fail-with-body "$url" \
      --request "$method" \
      --header "Authorization: Bearer $CF_API_TOKEN"
  fi
}

verify_token() {
  log "Verifying Cloudflare API token"
  local resp success
  resp="$(curl --silent --show-error --fail-with-body \
    https://api.cloudflare.com/client/v4/user/tokens/verify \
    --request GET \
    --header "Authorization: Bearer $CF_API_TOKEN")"
  success="$(jq -r '.success' <<<"$resp")"
  [[ "$success" == "true" ]] || die "Cloudflare API token verification failed"
  ok "API token verified"
}

prompt_nonempty() {
  local var_name="$1" prompt="$2" default="${3:-}" value=""
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "$prompt [$default]: " value || true
      value="${value:-$default}"
    else
      read -r -p "$prompt: " value || true
    fi
    if [[ -n "$value" ]]; then
      printf -v "$var_name" '%s' "$value"
      return
    fi
  done
}

prompt_secret() {
  local var_name="$1" prompt="$2" value=""
  while true; do
    read -r -s -p "$prompt: " value || true
    echo
    if [[ -n "$value" ]]; then
      printf -v "$var_name" '%s' "$value"
      return
    fi
  done
}

compose_hostname_map_if_needed() {
  if [[ -z "${HOSTNAME_MAP:-}" && -n "${DOMAIN:-}" && -n "${SUBDOMAIN:-}" && -n "${LOCAL_SERVICE:-}" ]]; then
    HOSTNAME_MAP="${SUBDOMAIN}.${DOMAIN}=${LOCAL_SERVICE}"
  fi
}

prompt_inputs_if_needed() {
  compose_hostname_map_if_needed
  if [[ -z "${CF_API_TOKEN:-}" ]]; then
    prompt_secret CF_API_TOKEN "Cloudflare API Token"
  fi
  if [[ -z "${ACCOUNT_ID:-}" ]]; then
    prompt_nonempty ACCOUNT_ID "Cloudflare Account ID"
  fi
  if [[ -z "${ZONE_ID:-}" ]]; then
    prompt_nonempty ZONE_ID "Cloudflare Zone ID"
  fi
  if [[ -z "${TUNNEL_NAME:-}" ]]; then
    prompt_nonempty TUNNEL_NAME "Tunnel name" "komar-web"
  fi
  if [[ -z "${HOSTNAME_MAP:-}" ]]; then
    prompt_nonempty DOMAIN "Base domain (example.com)"
    prompt_nonempty SUBDOMAIN "Subdomain" "app"
    prompt_nonempty LOCAL_SERVICE "Local service URL" "http://localhost:8080"
    HOSTNAME_MAP="${SUBDOMAIN}.${DOMAIN}=${LOCAL_SERVICE}"
  fi
}

declare -a HOSTNAMES=()
declare -a SERVICES=()

parse_hostname_map() {
  HOSTNAMES=()
  SERVICES=()
  [[ -n "${HOSTNAME_MAP:-}" ]] || die "HOSTNAME_MAP is empty"
  local entry host service oldifs
  oldifs="$IFS"
  IFS=';'
  read -r -a entries <<< "$HOSTNAME_MAP"
  IFS="$oldifs"
  for entry in "${entries[@]}"; do
    entry="$(trim "$entry")"
    [[ -z "$entry" ]] && continue
    [[ "$entry" == *=* ]] || die "Invalid HOSTNAME_MAP item: $entry"
    host="$(trim "${entry%%=*}")"
    service="$(trim "${entry#*=}")"
    [[ -n "$host" && -n "$service" ]] || die "Invalid HOSTNAME_MAP item: $entry"
    HOSTNAMES+=("$host")
    SERVICES+=("$service")
  done
  [[ ${#HOSTNAMES[@]} -gt 0 ]] || die "No valid hostnames parsed from HOSTNAME_MAP"
}

create_tunnel() {
  log "Creating remotely-managed tunnel"
  local payload resp success
  payload="$(jq -nc --arg name "$TUNNEL_NAME" '{name:$name,config_src:"cloudflare"}')"
  resp="$(api POST "/accounts/${ACCOUNT_ID}/cfd_tunnel" "$payload")"
  success="$(jq -r '.success' <<<"$resp")"
  [[ "$success" == "true" ]] || die "Failed to create tunnel: $(jq -c '.errors' <<<"$resp")"
  TUNNEL_ID="$(jq -r '.result.id' <<<"$resp")"
  ok "Tunnel created: $TUNNEL_ID"
}

ensure_tunnel_id() {
  if [[ -n "${TUNNEL_ID:-}" ]]; then
    ok "Reusing tunnel from state: $TUNNEL_ID"
  else
    create_tunnel
  fi
}

build_ingress_json() {
  local i ingress='[]'
  for i in "${!HOSTNAMES[@]}"; do
    ingress="$(jq -c --arg hostname "${HOSTNAMES[$i]}" --arg service "${SERVICES[$i]}" \
      '. + [{hostname:$hostname,service:$service,originRequest:{}}]' <<<"$ingress")"
  done
  ingress="$(jq -c '. + [{service:"http_status:404"}]' <<<"$ingress")"
  printf '%s' "$ingress"
}

configure_tunnel() {
  log "Uploading tunnel ingress configuration"
  local ingress payload resp success
  ingress="$(build_ingress_json)"
  payload="$(jq -nc --argjson ingress "$ingress" '{config:{ingress:$ingress}}')"
  resp="$(api PUT "/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$payload")"
  success="$(jq -r '.success' <<<"$resp")"
  [[ "$success" == "true" ]] || die "Failed to configure tunnel: $(jq -c '.errors' <<<"$resp")"
  ok "Tunnel configuration uploaded"
}

upsert_dns_record() {
  local hostname="$1" target existing_resp existing_id payload resp success
  target="${TUNNEL_ID}.cfargotunnel.com"
  log "Creating or updating proxied CNAME for ${hostname}"
  existing_resp="$(api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&name=${hostname}")"
  existing_id="$(jq -r '.result[0].id // empty' <<<"$existing_resp")"
  payload="$(jq -nc --arg type "CNAME" --arg name "$hostname" --arg content "$target" '{type:$type,proxied:true,name:$name,content:$content}')"
  if [[ -n "$existing_id" ]]; then
    resp="$(api PUT "/zones/${ZONE_ID}/dns_records/${existing_id}" "$payload")"
  else
    resp="$(api POST "/zones/${ZONE_ID}/dns_records" "$payload")"
  fi
  success="$(jq -r '.success' <<<"$resp")"
  [[ "$success" == "true" ]] || die "Failed to create/update DNS record for ${hostname}: $(jq -c '.errors' <<<"$resp")"
  ok "DNS ready: ${hostname}"
}

sync_all_dns_records() {
  local host
  for host in "${HOSTNAMES[@]}"; do
    upsert_dns_record "$host"
  done
}

get_tunnel_token() {
  log "Retrieving tunnel token"
  local resp
  resp="$(api GET "/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token")"
  TUNNEL_TOKEN="$(jq -r '.result' <<<"$resp")"
  [[ -n "$TUNNEL_TOKEN" && "$TUNNEL_TOKEN" != "null" ]] || die "Failed to retrieve tunnel token"
  ok "Tunnel token received"
}

write_systemd_unit() {
  mkdir -p "$APP_DIR"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=$APP_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token-file $TOKEN_FILE
Restart=on-failure
RestartSec=5s
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable komar-web-tunnel.service >/dev/null 2>&1 || true
  systemctl restart komar-web-tunnel.service
  ok "Systemd service installed: komar-web-tunnel.service"
}

show_summary() {
  echo
  ok "Finished"
  echo "Tunnel name:   $TUNNEL_NAME"
  echo "Tunnel ID:     $TUNNEL_ID"
  echo "State file:    $STATE_FILE"
  echo "Token file:    $TOKEN_FILE"
  echo "Hostnames:"
  local i
  for i in "${!HOSTNAMES[@]}"; do
    echo "  - ${HOSTNAMES[$i]}  ->  ${SERVICES[$i]}"
  done
  echo
  echo "Useful commands:"
  echo "  systemctl status komar-web-tunnel"
  echo "  journalctl -u komar-web-tunnel -n 100 --no-pager"
  for i in "${!HOSTNAMES[@]}"; do
    echo "  curl -I https://${HOSTNAMES[$i]}"
  done
  echo
}

delete_dns_record() {
  local hostname="$1" resp record_id del_resp success
  resp="$(api GET "/zones/${ZONE_ID}/dns_records?name=${hostname}")"
  record_id="$(jq -r '.result[0].id // empty' <<<"$resp")"
  if [[ -z "$record_id" ]]; then
    warn "DNS record not found for ${hostname}; skipping"
    return
  fi
  del_resp="$(api DELETE "/zones/${ZONE_ID}/dns_records/${record_id}")"
  success="$(jq -r '.success' <<<"$del_resp")"
  [[ "$success" == "true" ]] || warn "Could not delete DNS record for ${hostname}: $(jq -c '.errors' <<<"$del_resp")"
}

delete_tunnel_remote() {
  [[ -n "${TUNNEL_ID:-}" ]] || return
  log "Deleting remote tunnel ${TUNNEL_ID}"
  local resp success
  resp="$(api DELETE "/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}")"
  success="$(jq -r '.success' <<<"$resp")"
  [[ "$success" == "true" ]] || warn "Could not delete remote tunnel: $(jq -c '.errors' <<<"$resp")"
}

remove_service() {
  if systemctl list-unit-files | grep -q '^komar-web-tunnel.service'; then
    systemctl stop komar-web-tunnel.service >/dev/null 2>&1 || true
    systemctl disable komar-web-tunnel.service >/dev/null 2>&1 || true
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    ok "Removed systemd service"
  else
    warn "Systemd service not found; skipping"
  fi
}

install_or_sync() {
  require_root
  ensure_base_deps
  install_cloudflared
  load_state || true
  prompt_inputs_if_needed
  parse_hostname_map
  verify_token
  ensure_tunnel_id
  configure_tunnel
  sync_all_dns_records
  get_tunnel_token
  save_state
  write_systemd_unit
  show_summary
}

show_state() {
  load_state || die "No state file found at $STATE_FILE"
  echo "$APP_NAME $APP_VERSION"
  echo "Tunnel name:   ${TUNNEL_NAME:-}"
  echo "Tunnel ID:     ${TUNNEL_ID:-}"
  echo "State file:    $STATE_FILE"
  echo "Managed map:   ${HOSTNAME_MAP:-}"
  if systemctl list-unit-files | grep -q '^komar-web-tunnel.service'; then
    systemctl --no-pager --plain --full status komar-web-tunnel.service || true
  fi
}

uninstall_all() {
  require_root
  ensure_base_deps
  load_state || warn "No saved state found; will remove only local service/files"
  if [[ -f "${1:-}" ]]; then
    SOURCE_ENV_FILE="$1"
    load_env_file "$1" || true
  fi
  remove_service
  if [[ -n "${CF_API_TOKEN:-}" && -n "${ACCOUNT_ID:-}" && -n "${ZONE_ID:-}" ]]; then
    verify_token
    if [[ -n "${HOSTNAME_MAP:-}" ]]; then
      parse_hostname_map
      local host
      for host in "${HOSTNAMES[@]}"; do
        delete_dns_record "$host"
      done
    fi
    delete_tunnel_remote
  else
    warn "CF_API_TOKEN / ACCOUNT_ID / ZONE_ID not available; remote tunnel and DNS were not deleted"
  fi
  rm -rf "$APP_DIR"
  ok "Local files removed"
}

main() {
  local action="${1:-install}" env_arg="${2:-}"
  case "$action" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  local explicit_env=""
  if [[ -n "$env_arg" ]]; then
    explicit_env="$env_arg"
  elif [[ -n "${ENV_FILE:-}" ]]; then
    explicit_env="$ENV_FILE"
  elif [[ -f ./.env ]]; then
    explicit_env="./.env"
  elif [[ -f "$ENV_FILE_DEFAULT" ]]; then
    explicit_env="$ENV_FILE_DEFAULT"
  fi

  if [[ -n "$explicit_env" && -f "$explicit_env" ]]; then
    SOURCE_ENV_FILE="$explicit_env"
    load_env_file "$explicit_env"
  fi

  case "$action" in
    install|sync)
      install_or_sync
      ;;
    uninstall)
      uninstall_all "$explicit_env"
      ;;
    state)
      show_state
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
