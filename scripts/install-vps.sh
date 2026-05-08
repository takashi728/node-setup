#!/usr/bin/env bash
# =============================================================================
# install-vps.sh — One-shot Remnawave Node VPS deployment
#
# Usage:
#   sudo ./install-vps.sh --role edge --domain vps1.example.com --secret-key <KEY>
#   sudo ./install-vps.sh --role exit --secret-key <KEY>
#
# What it does:
#   1. Installs Docker + dependencies
#   2. Edge only: obtains SSL cert via acme.sh
#   3. Writes /opt/remnanode/docker-compose.yml
#   4. Starts Remnanode
#   5. Configures UFW firewall
#
# Prerequisites:
#   - Ubuntu 22.04+ / Debian 11+
#   - Domain A-record pointing to VPS IP (edge only)
#   - SECRET_KEY from Remnawave panel (Nodes → Create Node)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---- defaults ----
ROLE=""
DOMAIN=""
SECRET_KEY=""
NODE_PORT=2222
REMNANODE_DIR="/opt/remnanode"

usage() {
    cat <<EOF
Usage: sudo $0 --role <edge|exit> [--domain <domain>] --secret-key <KEY>

Options:
  --role         Node role: "edge" (VPS1, with TLS cert) or "exit" (VPS2, bridge only)
  --domain       Domain name for TLS certificate (required when --role edge)
  --secret-key   SECRET_KEY from Remnawave panel
  --node-port    Remnanode communication port (default: 2222)
EOF
    exit 1
}

# ---- parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --role)       ROLE="$2";       shift 2 ;;
        --domain)     DOMAIN="$2";     shift 2 ;;
        --secret-key) SECRET_KEY="$2"; shift 2 ;;
        --node-port)  NODE_PORT="$2";  shift 2 ;;
        *)            usage ;;
    esac
done

if [[ "$ROLE" != "edge" && "$ROLE" != "exit" ]]; then
    echo -e "${RED}ERROR: --role must be 'edge' or 'exit'${NC}"
    usage
fi

if [[ -z "$SECRET_KEY" ]]; then
    echo -e "${RED}ERROR: --secret-key is required${NC}"
    usage
fi

if [[ "$ROLE" == "edge" && -z "$DOMAIN" ]]; then
    echo -e "${RED}ERROR: --domain is required for edge nodes${NC}"
    usage
fi

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}ERROR: must run as root (sudo)${NC}"
    exit 1
fi

echo "============================================="
echo -e "  Remnawave Node Installer"
echo "  Role:       ${GREEN}${ROLE}${NC}"
[[ -n "$DOMAIN" ]] && echo "  Domain:     ${GREEN}${DOMAIN}${NC}"
echo "  Secret Key: ${GREEN}${SECRET_KEY:0:8}...${NC}"
echo "============================================="
echo ""

# ============================================================================
# Step 1 — Install Docker + dependencies
# ============================================================================
echo -e "${GREEN}[1/6] Installing Docker + dependencies${NC}"

if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

apt-get update -qq
apt-get install -y -qq cron socat curl ufw

# ============================================================================
# Step 2 — Firewall (pre-open ports before services start)
# ============================================================================
echo -e "${GREEN}[2/6] Configuring firewall${NC}"

ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "${NODE_PORT}/tcp"
ufw --force enable

# ============================================================================
# Step 3 — SSL certificate (edge only)
# ============================================================================
if [[ "$ROLE" == "edge" ]]; then
    echo -e "${GREEN}[3/6] Obtaining SSL certificate for ${DOMAIN}${NC}"

    CERT_DIR="${REMNANODE_DIR}/certs"
    mkdir -p "$CERT_DIR"

    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi

    alias acme.sh=~/.acme.sh/acme.sh
    acme.sh --upgrade --auto-upgrade
    acme.sh --set-default-ca --server letsencrypt

    acme.sh --issue --standalone -d "$DOMAIN" \
        --keylength ec-256 \
        --key-file "${CERT_DIR}/privkey.key" \
        --fullchain-file "${CERT_DIR}/fullchain.pem"

    chmod 644 "${CERT_DIR}/fullchain.pem"
    chmod 600 "${CERT_DIR}/privkey.key"

    echo -e "  ${GREEN}Certificate installed to ${CERT_DIR}${NC}"
else
    echo -e "${GREEN}[3/6] Skipping SSL (exit node doesn't serve TLS)${NC}"
fi

# ============================================================================
# Step 4 — Write docker-compose.yml for Remnanode
# ============================================================================
echo -e "${GREEN}[4/6] Writing Remnanode configuration${NC}"

mkdir -p "$REMNANODE_DIR"

cat > "${REMNANODE_DIR}/docker-compose.yml" <<DOCKEREOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
DOCKEREOF

# Mount SSL certs for edge nodes
if [[ "$ROLE" == "edge" ]]; then
    cat >> "${REMNANODE_DIR}/docker-compose.yml" <<DOCKEREOF
    volumes:
      - ${CERT_DIR}/fullchain.pem:/etc/nginx/certs/fullchain.pem:ro
      - ${CERT_DIR}/privkey.key:/etc/nginx/certs/privkey.key:ro
DOCKEREOF
fi

echo -e "  ${GREEN}saved to ${REMNANODE_DIR}/docker-compose.yml${NC}"

# ============================================================================
# Step 5 — Start Remnanode
# ============================================================================
echo -e "${GREEN}[5/6] Starting Remnanode${NC}"

cd "$REMNANODE_DIR" && docker compose up -d

echo "  Waiting for node to initialize..."
sleep 5

if docker ps | grep -q remnanode; then
    echo -e "  ${GREEN}Remnanode is running${NC}"
else
    echo -e "  ${RED}Remnanode failed to start — check logs:${NC}"
    echo "    docker logs remnanode"
fi

# ============================================================================
# Step 6 — Summary
# ============================================================================
echo ""
echo "============================================="
echo -e "  ${GREEN}Installation complete${NC}"
echo "============================================="
echo ""
echo "  Role:       ${ROLE}"
echo "  Node Port:  ${NODE_PORT}"
[[ -n "$DOMAIN" ]] && echo "  Domain:     ${DOMAIN}"
echo ""
echo "  Next steps:"
echo "  1. Go to Remnawave Panel → Nodes → Management"
echo "  2. Click 'Create new node'"
echo "  3. Set address to this VPS IP, port ${NODE_PORT}"
echo "  4. When the node connects (green), select your Config Profile"
echo "  5. Activate the relevant inbounds"
echo ""
echo "  Useful commands:"
echo "    docker logs remnanode                    # view Remnanode logs"
echo "    docker exec remnanode tail -f /var/log/supervisor/xray.out.log  # Xray logs"
echo "    cd ${REMNANODE_DIR} && docker compose restart   # restart"
echo ""
