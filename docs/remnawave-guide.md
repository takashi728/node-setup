# Remnawave Panel Setup Guide — Multi-Hop Xray

## Terminology

| Remnawave Term | What It Is |
|---|---|
| **Node** | A VPS running `Remnawave Node` + Xray-core. You need 2: one for VPS1, one for VPS2. |
| **Config Profile** | A full Xray-core JSON config template. A node uses exactly 1 profile. |
| **Internal Squad** | Controls which inbounds a group of users can access. |
| **Host** | An entity pointing to a specific inbound on a node. Users see hosts in their subscription. |
| **Service User** | A user with unlimited traffic, used only for bridge routing (never connects directly). |

---

## Step 1 — Install Remnawave Node on Both VPSes

Follow the official guide: https://docs.rw/docs/install/remnawave-node

```bash
# On VPS1
docker exec -it remnanode tail -n +1 -f /var/log/supervisor/xray.out.log
```

---

## Step 2 — Create VPS2 (Exit Node) Config Profile

### 2.1 Navigate to Config Profiles

Go to `Config Profiles` → `Create Config Profile` → name it `VPS2 Exit Profile`.

### 2.2 Paste the VPS2 Config

Use the content from `configs/vps2-exit-node.jsonc`.

Important modifications:
- `clients[0].id` — leave empty (Remnawave auto-populates from users)
- `decryption` — paste the output of `./scripts/generate-keys.sh` (the server decryption line)

### 2.3 Save the profile

The profile should show 1 inbound (`BRIDGE_VLESS_IN`).

---

## Step 3 — Register VPS2 Node + Activate Profile

### 3.1 Add VPS2 Node

Go to `Nodes` → `Management` → `Create new node`.

Fill in:
- Country: Germany (or wherever VPS2 is)
- Internal name: `DE-Exit`
- Address: VPS2 IP address
- Port: Remnawave Node port (from installation)
- Config Profile: choose `VPS2 Exit Profile`
- Activate inbound: `BRIDGE_VLESS_IN`

### 3.2 Wait for connection

The node card should turn green after a few seconds.

---

## Step 4 — Create Bridge User on VPS2

### 4.1 Create Internal Squad for bridge

Go to `Внутренние сквады` (Internal Squads) → `+`.

Enable only the `BRIDGE_VLESS_IN` inbound.

### 4.2 Create service user

Go to `Users` → `Create user`.

- Username: `bridge_user_001`
- Data limit: **no limit** (leave empty)
- Traffic reset strategy: `No reset`
- Subscription expiry: set far in the future (e.g. 2099-12-31)
- Activate the bridge squad

### 4.3 Get bridge credentials

Open the user card → `More Actions` → `Detailed Info`.

Scroll down and copy:
- **VLESS UUID** — paste into `vps1-edge-node.jsonc` as `<BRIDGE_USER_UUID>`
- The UUID is the only thing you need from the panel.
- The PQC encryption string comes from `generate-keys.sh` output (the bridge client line).

---

## Step 5 — Create VPS1 (Edge Node) Config Profile

### 5.1 Create profile

Go to `Config Profiles` → `Create Config Profile` → name it `VPS1 Edge Profile`.

### 5.2 Paste VPS1 Config

Use the content from `configs/vps1-edge-node.jsonc`.

**Critical modifications:**

1. `inbounds[0].settings.clients[0].id` — leave empty (panel-managed)
2. `inbounds[0].streamSettings.xhttpSettings.path` — set your secret path
3. `inbounds[0].streamSettings.tlsSettings.certificates` — set certificate paths (see Step 7)
4. `outbounds[2].settings.vnext[0].address` — VPS2 IP or domain
5. `outbounds[2].settings.vnext[0].users[0].id` — paste the bridge user UUID from Step 4.3
6. `outbounds[2].settings.vnext[0].users[0].encryption` — paste the bridge client PQC string from `generate-keys.sh`

### 5.3 Routing customization

The routing rules in the config:
- Block private IPs + BitTorrent
- Block `geosite:cn` + `geoip:cn`
- Block `geosite:category-gov-cn` (Chinese government domains)
- Route `geosite:category-ai-!cn` → VPS2 (AI-related non-China services)
- Everything else → DIRECT from VPS1

> If specific geosite categories are not in your `geosite.dat`, download the latest:
> ```bash
> curl -L https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat -o /usr/local/share/xray/geosite.dat
> ```

---

## Step 6 — Register VPS1 Node + Activate Profile

Same as Step 3, but for VPS1:

- Country: Hong Kong (or wherever VPS1 is)
- Internal name: `HK-Edge`
- Address: VPS1 IP address
- Config Profile: `VPS1 Edge Profile`
- Activate inbound: `PUBLIC_XHTTP_IN`

---

## Step 7 — Set Up TLS Certificate on VPS1

Run the ACME script on VPS1:

```bash
sudo ./scripts/setup-acme.sh vps1.your-domain.com
```

This:
1. Installs acme.sh
2. Issues an ECC P-256 certificate (prime256v1)
3. Installs to `/etc/ssl/private/fullchain.cer` and `/etc/ssl/private/private.key`
4. Sets up auto-renewal

Verify the certificate:
```bash
openssl x509 -in /etc/ssl/private/fullchain.cer -text -noout | grep -E "(Subject:|DNS:|Not After)"
```

---

## Step 8 — Create Public Squad + Users on VPS1

### 8.1 Create Internal Squad

Go to `Внутренние сквады` → `+`.

Enable only the `PUBLIC_XHTTP_IN` inbound.

### 8.2 Create regular users

Go to `Users` → `Create user`.

- Username: anything without spaces
- Data limit: as needed (e.g. 100 GB)
- Traffic reset strategy: `Daily` or `Monthly`
- Subscription expiry: as needed
- Activate the public squad

### 8.3 Get subscription

Click the subscription button on the user row, or open the user card.

The subscription URL can be imported directly into:
- **v2rayN** (Windows)
- **v2rayNG** (Android)
- **Happ** (iOS/macOS)
- **Shadowrocket** (iOS)
- **Sing-box** clients

---

## Step 9 — Configure Your Client

### Using subscription (automatic)

Import the subscription URL into your client. Remnawave auto-detects the client type and serves the correct format (Base64, Xray-JSON, Mihomo, or Sing-box).

### Using manual config (manual)

Use `configs/client-template.jsonc` as a reference. Fill in:
- `address` → VPS1 domain
- `id` → your VLESS UUID
- `path` → your secret path
- `serverName` → VPS1 domain

---

## Step 10 — Verify the Setup

### Check VPS2 bridge connection

```bash
# On VPS2
docker exec -it remnanode tail -n +1 -f /var/log/supervisor/xray.out.log
```

You should see connection attempts from VPS1.

### Check VPS1 routing

```bash
# On VPS1
docker exec -it remnanode tail -n +1 -f /var/log/supervisor/xray.out.log
```

Set loglevel to `info` temporarily to debug XHTTP mode and HTTP version.

### Test from client

```bash
# Test via SOCKS5 proxy
curl --socks5-hostname 127.0.0.1:10808 https://ifconfig.me

# Test via HTTP proxy
curl --proxy http://127.0.0.1:10809 https://ifconfig.me
```

---

## Architecture Diagram

```
┌─────────────┐     XHTTP+TLS(443)     ┌──────────────┐     VLESS+PQC(9999)    ┌──────────────┐
│   Client    │ ──────────────────────→ │  VPS1 (Edge) │ ────────────────────→ │ VPS2 (Exit)  │
│  (China)    │                         │   HK/Tokyo   │                        │   DE/US      │
│             │  ←── CN traffic direct  │              │  ←── AI-non-CN traffic │              │
└─────────────┘                         └──────────────┘                        └──────┬───────┘
                                                                                       │
                                                                                  ┌────▼────┐
                                                                                  │Internet │
                                                                                  └─────────┘
```

---

## Troubleshooting

### VPS2 node not connecting to panel
- Check firewall: port for Remnawave Node must be open
- Check Node logs: `docker logs remnanode`

### Client can't connect to VPS1
- Verify TLS certificate is valid: `openssl s_client -connect vps1.domain:443 -servername vps1.domain`
- Check XHTTP path matches between client and server
- Set `"loglevel": "info"` on VPS1 to see XHTTP connection details

### Bridge traffic not reaching VPS2
- Verify outbound address/port matches VPS2 inbound
- Verify bridge user UUID matches on both sides
- Verify PQC encryption/decryption strings are generated as a matching pair

### Geosite categories not found
- Download latest geosite.dat:
  ```bash
  curl -L https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat \
    -o /usr/local/share/xray/geosite.dat
  ```
- Check available categories on VPS1:
  ```bash
  xray geosite list
  ```
