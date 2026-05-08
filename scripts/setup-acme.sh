#!/usr/bin/env bash
# =============================================================================
# setup-acme.sh — Obtain real TLS certificate for VPS1 (steal oneself)
#
# Prerequisites:
#   - A domain name pointed to VPS1 IP (A record)
#   - Port 80 reachable (firewall open)
#   - Nothing else listening on port 80 during certificate issue
#
# Usage:
#   chmod +x setup-acme.sh
#   sudo ./setup-acme.sh <your-domain>
#
# Example:
#   sudo ./setup-acme.sh vps1.example.com
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}ERROR: Domain name required${NC}"
    echo "Usage: sudo $0 <your-domain>"
    echo "Example: sudo $0 vps1.example.com"
    exit 1
fi

echo "============================================="
echo "  ACME TLS Certificate Setup for: ${DOMAIN}"
echo "============================================="
echo ""

# ---- 1. Install acme.sh if not present ----
if [ ! -f ~/.acme.sh/acme.sh ]; then
    echo -e "${GREEN}[1/5] Installing acme.sh${NC}"
    apt install -y socat curl
    curl https://get.acme.sh | sh
fi

alias acme.sh=~/.acme.sh/acme.sh

# ---- 2. Configure acme.sh ----
echo -e "${GREEN}[2/5] Configuring acme.sh${NC}"
acme.sh --upgrade --auto-upgrade
acme.sh --set-default-ca --server letsencrypt

# ---- 3. Issue ECC P-256 certificate ----
echo -e "${GREEN}[3/5] Issuing ECC P-256 certificate${NC}"
echo "  This will listen on port 80 — make sure nothing else uses it."

SSL_DIR="/etc/ssl/private"
mkdir -p "$SSL_DIR"

acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256

# ---- 4. Install certificate to /etc/ssl/private/ ----
echo -e "${GREEN}[4/5] Installing certificate to ${SSL_DIR}${NC}"
acme.sh --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "${SSL_DIR}/fullchain.cer" \
    --key-file "${SSL_DIR}/private.key"

chown -R nobody:nogroup "$SSL_DIR" 2>/dev/null || true

# ---- 5. Verify ----
echo -e "${GREEN}[5/5] Verifying${NC}"
echo ""

echo "Certificate:"
openssl x509 -in "${SSL_DIR}/fullchain.cer" -text -noout | grep -E "(Subject:|DNS:|Not After)" || true
echo ""

echo -e "${GREEN}Done.${NC}"
echo ""
echo "Certificate files:"
echo "  fullchain: ${YELLOW}${SSL_DIR}/fullchain.cer${NC}"
echo "  key:       ${YELLOW}${SSL_DIR}/private.key${NC}"
echo ""
echo "Auto-renewal: acme.sh handles this (runs via cron)."
echo "  Manual force-renew: acme.sh --renew -d ${DOMAIN} --force --ecc"
