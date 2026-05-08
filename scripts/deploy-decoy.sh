#!/usr/bin/env bash
# =============================================================================
# deploy-decoy.sh — Deploy Nginx decoy container for VPS1 fallback
#
# Usage:
#   ./deploy-decoy.sh
#
# Deploys a lightweight Nginx container serving a clean-looking static site.
# This is the website shown when someone visits your VPS1 domain without
# the VLESS+XHTTP handshake — makes the server look legitimate.
#
# Requires: docker (preinstalled by install-vps.sh)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

DECOY_DIR="/opt/remnanode/decoy"
SCRIPT_DIR="$(dirname "$0")"

echo -e "${GREEN}Deploying Nginx decoy service...${NC}"

mkdir -p "${DECOY_DIR}/html"

# ---- Create a realistic-looking index page ----
cat > "${DECOY_DIR}/html/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Welcome</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         max-width: 720px; margin: 60px auto; padding: 0 20px; color: #333; line-height: 1.6; }
  h1 { font-weight: 600; }
  p { color: #555; }
</style>
</head>
<body>
<h1>Site under maintenance</h1>
<p>We'll be back shortly. Thank you for your patience.</p>
</body>
</html>
HTML

# ---- Copy nginx config ----
cp "${SCRIPT_DIR}/../configs/nginx-vps1.conf" "${DECOY_DIR}/nginx.conf"

# ---- docker-compose for decoy Nginx ----
cat > "${DECOY_DIR}/docker-compose.yml" <<DCOMPOSE
services:
  nginx-decoy:
    container_name: nginx-decoy
    image: nginx:alpine
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./html:/usr/share/nginx/html:ro
DCOMPOSE

cd "$DECOY_DIR" && docker compose up -d

echo -e "${GREEN}Decoy Nginx running (host port 8080)${NC}"
echo "  Visit http://<VPS1-IP>:8080 to verify."
