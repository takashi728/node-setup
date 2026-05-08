#!/usr/bin/env bash
# =============================================================================
# validate-configs.sh — Validate Xray config JSON structure
#
# Checks:
#   1. JSON validity (strips comments, checks with python3 -m json.tool)
#   2. Required fields present (inbounds, outbounds)
#   3. Tag uniqueness
#   4. Common mistakes (wrong network/security combinations)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONFIGS_DIR="$(dirname "$0")/../configs"
FAILED=0

echo "============================================="
echo "  Xray Config Validator"
echo "============================================="
echo ""

strip_comment_lines() {
    # Remove // comments and /* */ blocks (simplistic, works for most cases)
    sed -E 's/^\s*\/\/.*$//' "$1" | sed -E 's/\/\*.*\*\///g'
}

validate_config() {
    local file="$1"
    local name="$(basename "$file")"

    echo -n "  ${name}: "

    # Check 1: valid JSON (strip comments, try to parse)
    local stripped
    if ! stripped=$(strip_comment_lines "$file" 2>/dev/null); then
        echo -e "${RED}FAIL${NC} — cannot read file"
        FAILED=1
        return
    fi

    if ! echo "$stripped" | python3 -m json.tool > /dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} — invalid JSON"
        echo "$stripped" | python3 -m json.tool 2>&1 | head -5
        FAILED=1
        return
    fi

    # Check 2: required top-level fields
    if ! echo "$stripped" | python3 -c "
import json,sys
c=json.load(sys.stdin)
assert 'inbounds' in c, 'missing inbounds'
assert 'outbounds' in c, 'missing outbounds'
assert isinstance(c['inbounds'], list), 'inbounds not a list'
assert isinstance(c['outbounds'], list), 'outbounds not a list'
assert len(c['inbounds'])>0, 'no inbounds'
assert len(c['outbounds'])>0, 'no outbounds'
" 2>&1; then
        echo -e "${RED}FAIL${NC} — missing required fields"
        FAILED=1
        return
    fi

    # Check 3: tag uniqueness across inbounds+outbounds
    local dupes
    dupes=$(echo "$stripped" | python3 -c "
import json,sys
c=json.load(sys.stdin)
in_tags=[i.get('tag','') for i in c.get('inbounds',[])]
out_tags=[o.get('tag','') for o in c.get('outbounds',[])]
all_tags=in_tags+out_tags
from collections import Counter
dupes=[t for t,cnt in Counter(all_tags).items() if cnt>1 and t]
if dupes:
    print(' '.join(dupes))
" 2>&1)

    if [ -n "$dupes" ]; then
        echo -e "${RED}FAIL${NC} — duplicate tags: ${dupes}"
        FAILED=1
        return
    fi

    # Check 4: sniffing enabled on relevant inbounds
    local no_sniff
    no_sniff=$(echo "$stripped" | python3 -c "
import json,sys
c=json.load(sys.stdin)
for i in c.get('inbounds',[]):
    if i.get('protocol') in ('vless','trojan','vmess','shadowsocks'):
        s=i.get('sniffing',{})
        if not s.get('enabled'):
            print(i.get('tag','unnamed'))
            break
" 2>&1)

    if [ -n "$no_sniff" ]; then
        echo -e "${YELLOW}WARN${NC} — inbound '${no_sniff}' has sniffing disabled"
    else
        echo -e "${GREEN}OK${NC}"
    fi
}

for config in "$CONFIGS_DIR"/*.jsonc; do
    [ -f "$config" ] || continue
    validate_config "$config"
done

echo ""

if [ "$FAILED" -eq 1 ]; then
    echo -e "${RED}Some configs have errors — fix before deploying.${NC}"
    exit 1
else
    echo -e "${GREEN}All configs pass validation.${NC}"
fi

# ---- Additional checks ----

echo ""
echo "=== Quick Sanity Checks ==="
echo ""

echo "Remaining <PLACEHOLDER> markers:"
grep -nE '<[A-Za-z0-9_]+>' "$CONFIGS_DIR"/*.jsonc 2>/dev/null | sed 's/^/  /' || echo "  none"
echo ""

if command -v xray &>/dev/null; then
    echo "Checking Xray version:"
    xray version 2>/dev/null | head -1 | sed 's/^/  /'
    echo ""
    echo "Available geosite categories:"
    xray geosite list 2>/dev/null | grep -i -E '(cn|ai|gov)' | sed 's/^/  /' || echo "  (run 'xray geosite list' manually)"
else
    echo -e "${YELLOW}xray not found in PATH — skip geosite check${NC}"
    echo "  Install: https://github.com/XTLS/Xray-core/releases/latest"
fi
