# Xray Multi-Hop — Stealth Anti-GFW Configuration

Two-hop proxy setup using Xray-core with VLESS+XHTTP+TLS (edge) + VLESS+PQC+XTLS-Vision (bridge).

## Directory Layout

```
.
├── configs/
│   ├── vps2-exit-node.jsonc     # VPS2: PQC bridge inbound + Freedom exit
│   ├── vps1-edge-node.jsonc     # VPS1: XHTTP+TLS inbound + bridge outbound + routing
│   ├── client-template.jsonc    # Local: SOCKS/HTTP inbounds + XHTTP outbound
│   ├── custom-domains.txt       # Reference: AI-non-CN + CN-gov domain lists
│   ├── nginx-vps1.conf          # Nginx decoy fallback config for VPS1
│   └── docker-compose.node.yml  # Remnanode deployment template
├── scripts/
│   ├── install-vps.sh           # One-shot VPS deployment (installs Remnanode + Docker)
│   ├── setup-acme.sh            # Obtain TLS cert for VPS1 (steal oneself)
│   ├── deploy-decoy.sh          # Deploy Nginx decoy container for VPS1 fallback
│   ├── generate-keys.sh         # Generate VLESS PQC key pair for the bridge
│   └── validate-configs.sh      # Validate JSON and check for common mistakes
├── docs/
│   └── remnawave-guide.md       # Step-by-step Remnawave panel setup
└── README.md                    # This file
```

## Architecture

```
Client ──[VLESS + XHTTP + TLS]──→ VPS1 ──[VLESS + PQC + XTLS-Vision]──→ VPS2 ──→ Internet
  │                                  │
  └── CN traffic direct              ├── Block CN / CN-gov
                                     ├── AI-non-CN → VPS2
                                     └── Everything else → direct
```

## Quick Start

### 1. Deploy Nodes to VPSes

```bash
# VPS2 (exit node) — no domain needed
sudo ./scripts/install-vps.sh --role exit --secret-key "<VPS2_SECRET_KEY>"

# VPS1 (edge node) — domain required for TLS
sudo ./scripts/install-vps.sh --role edge --domain vps1.example.com --secret-key "<VPS1_SECRET_KEY>"

# VPS1 only: deploy the decoy fallback site
./scripts/deploy-decoy.sh
```

Get `SECRET_KEY` from the Remnawave panel: Nodes → Create Node → copy key.

### 2. Generate PQC Keys

```bash
# Install xray binary if needed:
# curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
# unzip xray.zip && chmod +x xray && sudo mv xray /usr/local/bin/

chmod +x scripts/generate-keys.sh
./scripts/generate-keys.sh
# Output saved to configs/generated-keys.txt
```

### 3. Configure Panel

Upload Config Profiles, create the bridge service user, assign squads.
Full walkthrough: [docs/remnawave-guide.md](docs/remnawave-guide.md)

### 4. Validate Configs

```bash
./scripts/validate-configs.sh
# Checks JSON validity, tag uniqueness, sniffing settings, and remaining placeholders.
```

### 5. Configure Client

**Option A — Use Remnawave subscription (recommended):**
After creating a user in the panel, import the subscription URL into your client.

**Option B — Manual config:**
Edit `configs/client-template.jsonc` and deploy to your Xray client.

## How Stealth Works

| Layer | Mechanism |
|---|---|
| Transport | **XHTTP**: looks like standard HTTP/2 streams. packet-up chunks data into POST requests with randomized `Referer` padding. XMUX rotates connections periodically to avoid fingerprinting. |
| Encryption | **TLS 1.3** with real certificate (steal oneself). SNI matches server hostname — no impersonation, less suspicious. uTLS `chrome` fingerprint mimics real browser. |
| Bridge | **VLESS PQC**: Post-quantum ML-KEM-768 key exchange + X25519. 0-RTT session resumption. XTLS-Vision for zero-copy forwarding. Native appearance (TLSv1.3 AEAD header). |
| Routing | Client → CN sites go direct (no proxy). VPS1 blocks China-origin traffic from exiting its IP. AI-related international traffic cascades through VPS2. |

## Requirements

- Xray-core >= v26.x (for VLESS PQC + XHTTP)
- VPS1: domain + TLS certificate (acme.sh)
- VPS2: reachable IP, port 9999 (or custom) open
- Remnawave Panel

## References

- [XHTTP: Beyond REALITY](https://github.com/XTLS/Xray-core/discussions/4113)
- [VLESS Post-Quantum Encryption](https://github.com/XTLS/Xray-core/pull/5067)
- [XTLS Vision](https://github.com/XTLS/Xray-core/discussions/1295)
- [Xray Configuration Docs](https://xtls.github.io/en/config/)
- [Remnawave Docs](https://docs.rw)
