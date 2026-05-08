#!/usr/bin/env bash
# =============================================================================
# generate-keys.sh — Generate all cryptographic keys for the Xray multi-hop setup
#
# Prerequisites: xray binary in PATH
#   curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
#
# Usage:
#   chmod +x generate-keys.sh
#   ./generate-keys.sh
#
# Outputs keys for:
#   1. VLESS UUIDs (VPS2 bridge user + client user)
#   2. PQC decryption string for VPS2 inbound (`xray vlessenc`)
#   3. PQC encryption string for VPS1→VPS2 bridge outbound (`xray vlessenc -c`)
#   4. X25519 keypair (optional, for REALITY usage)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v xray &>/dev/null; then
    echo -e "${RED}ERROR: xray not found in PATH${NC}"
    echo "Download: https://github.com/XTLS/Xray-core/releases/latest"
    exit 1
fi

echo "============================================="
echo "  Xray Multi-Hop Key Generator"
echo "============================================="
echo ""

# ---- 1. VLESS UUIDs ----
echo -e "${GREEN}=== VLESS UUIDs ===${NC}"
echo ""

BRIDGE_UUID=$(xray uuid 2>/dev/null)
CLIENT_UUID=$(xray uuid 2>/dev/null)

echo "VPS2 Bridge User UUID:"
echo -e "  ${YELLOW}${BRIDGE_UUID}${NC}"
echo ""
echo "Client User UUID:"
echo -e "  ${YELLOW}${CLIENT_UUID}${NC}"
echo ""

# ---- 2. PQC server-side decryption for VPS2 inbound ----
echo -e "${GREEN}=== VLESS Encryption (PQC) — VPS2 Server ===${NC}"
echo ""

SERVER_DECRYPT=$(xray vlessenc 2>/dev/null)

echo "Paste this into vps2-exit-node.jsonc → settings.decryption:"
echo -e "  ${YELLOW}${SERVER_DECRYPT}${NC}"
echo ""

# ---- 3. PQC client-side encryption for VPS1→VPS2 bridge outbound ----
echo -e "${GREEN}=== VLESS Encryption (PQC) — VPS1 Bridge Client ===${NC}"
echo ""

BRIDGE_ENCRYPT=$(xray vlessenc -c 2>/dev/null)

echo "Paste this into vps1-edge-node.jsonc → VLESS_TO_VPS2.users[0].encryption:"
echo -e "  ${YELLOW}${BRIDGE_ENCRYPT}${NC}"
echo ""

# ---- 4. X25519 keys (optional, for REALITY fallback) ----
echo -e "${GREEN}=== X25519 Keypair (optional) ===${NC}"
echo ""

X25519_OUTPUT=$(xray x25519 2>/dev/null)

echo "For REALITY usage (if needed):"
echo -e "  ${YELLOW}${X25519_OUTPUT}${NC}"
echo ""

# ---- 5. ML-KEM-768 keys (info) ----
echo -e "${GREEN}=== ML-KEM-768 Keys ===${NC}"
echo ""
echo "To generate ML-KEM-768 keys manually:"
echo "  xray mlkem768"
echo ""

# ---- Save to file ----
OUTPUT_FILE=~/Documents/Xray-core/configs/generated-keys.txt
cat > "$OUTPUT_FILE" <<EOF
Generated: $(date)
=============================================

VPS2 Bridge User UUID:
${BRIDGE_UUID}

Client User UUID:
${CLIENT_UUID}

VPS2 Server decryption (paste into vps2-exit-node.jsonc → decryption):
${SERVER_DECRYPT}

VPS1 Bridge Client encryption (paste into vps1-edge-node.jsonc → VLESS_TO_VPS2.users[0].encryption):
${BRIDGE_ENCRYPT}

X25519 Keys:
${X25519_OUTPUT}
EOF

echo -e "${GREEN}Keys saved to: ${OUTPUT_FILE}${NC}"
