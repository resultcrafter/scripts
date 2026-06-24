# ResultCrafter Scripts

Utility scripts for deploying and managing Dokploy + Tailscale infrastructure.

## Scripts

### install-dokploy-tailscale.sh

One-command installer that sets up Dokploy and Tailscale on any Linux server.

```bash
# Interactive (prompts for Tailscale key):
curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash

# Non-interactive (Tailscale key as argument):
curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash -s -- --ts-key tskey-xxx

# Skip Tailscale entirely:
curl -sSL https://scripts.resultcrafter.com/install-dokploy-tailscale.sh | sudo bash -s -- --no-tailscale
```

**What it does:**
1. Detects OS (macOS → Multipass guide, Windows → WSL guide, Linux/WSL → proceeds)
2. Checks prerequisites (RAM, disk, ports)
3. Installs Docker (if missing)
4. Installs Dokploy
5. Waits for Dokploy to be ready (health check)
6. Installs Tailscale
7. Connects to your Tailscale network
8. Prints access URL with Tailscale IP

**Requirements:**
- Linux server (or WSL/Multipass VM)
- 2 GB RAM minimum
- 30 GB disk minimum
- Ports 80, 443, 3000 available
- Tailscale account (free — [sign up](https://login.tailscale.com/start))

## Hosting

These scripts are served via Cloudflare Pages at `scripts.resultcrafter.com`.

## License

MIT
