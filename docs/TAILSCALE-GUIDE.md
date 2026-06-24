# Tailscale Guide — Modes, Pricing, and Container Deployment

Complete reference for using Tailscale with Dokploy and containers.

---

## Table of Contents

1. [Is Tailscale Free?](#is-tailscale-free)
2. [Key Types (Ephemeral vs Reusable)](#key-types-ephemeral-vs-reusable)
3. [Tailscale Modes for Containers](#tailscale-modes-for-containers)
4. [Sidecar Pattern](#sidecar-pattern)
5. [Tailscale Serve and Funnel](#tailscale-serve-and-funnel)
6. [Auth Key Guide](#auth-key-guide)
7. [Sources and Proof](#sources-and-proof)

---

## Is Tailscale Free?

**Yes.** Tailscale offers a **free Personal plan** that is free forever (not a trial).

### Personal Plan (Free)

| Feature | Limit |
|---------|-------|
| Users | Up to 6 |
| User devices | **Unlimited** |
| Tagged resources | 50 included |
| Ephemeral resources | 1,000 minutes/month |
| ACL groups | 3 |
| Features | Nearly all features included |
| Cost | **$0 forever** |

> *"For individuals who want to securely connect devices, servers, or software. Access nearly all of Tailscale's offerings and products for free, indefinitely."*
> — [Tailscale Pricing](https://tailscale.com/pricing)

### What's NOT Free

| Feature | Plan Required |
|---------|--------------|
| More than 6 users | Standard ($8/user/mo) |
| More than 3 ACL groups | Standard ($8/user/mo) |
| >1,000 ephemeral minutes/mo | Premium ($18/user/mo) |
| Advanced Tailscale SSH | Premium ($18/user/mo) |
| Network flow logs | Premium ($18/user/mo) |

For a single user managing 1-5 containers, the free plan is more than enough.

---

## Key Types (Ephemeral vs Reusable)

When generating an auth key at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys):

### Reusable Key

```
Use case: Servers, persistent containers
Behavior: Node stays in tailnet permanently
Restarts: Same node, same IP
Best for: VPS, dedicated servers, stable containers
```

### Ephemeral Key

```
Use case: CI/CD, temporary containers, auto-scaling
Behavior: Node auto-removed 30-60 min after going offline
Restarts: New node each time (unless state volume persists)
Best for: Docker containers that restart/redeploy often
```

### Recommended for Dokploy

Use a **Reusable + Ephemeral** key:

```
┌──────────────────────────────────────────────┐
│  Auth Key Settings (when generating):        │
│                                              │
│  ☑ Reusable (survives restarts)             │
│  ☑ Ephemeral (auto-removes dead nodes)      │
│                                              │
│  With persistent volume (our sidecar):       │
│  → Container restarts: same IP, same node   │
│  → Container deleted: node auto-cleaned     │
│  → No dead nodes cluttering admin panel     │
└──────────────────────────────────────────────┘
```

> Source: [Tailscale Ephemeral Nodes Docs](https://tailscale.com/docs/features/ephemeral-nodes)

---

## Tailscale Modes for Containers

### Mode 1: Kernel Mode (Full Features)

Requires `--privileged` or specific capabilities.

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    cap_add:
      - net_admin
      - sys_module
    volumes:
      - /dev/net/tun:/dev/net/tun
    devices:
      - /dev/net/tun:/dev/net/tun
```

**Pros:** Full performance, subnet routing, all features
**Cons:** Requires kernel access, security concerns

### Mode 2: Userspace Networking (Limited)

No `--privileged` needed. Runs entirely in userspace.

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    environment:
      TS_USERSPACE: "true"
```

**Pros:** No special permissions, works anywhere
**Cons:** No subnet routing, SOCKS5 proxy only, slower

### Mode 3: Sidecar (Recommended for Dokploy)

Separate Tailscale container shares network with app container.

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    hostname: my-app
    environment:
      TS_AUTHKEY: ${TS_AUTHKEY}
      TS_STATE_DIR: /var/lib/tailscale
    volumes:
      - ts-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - sys_module
    restart: unless-stopped

  app:
    image: my-app:latest
    network_mode: "service:tailscale"
    restart: unless-stopped

volumes:
  ts-state:
```

**Pros:** Clean separation, app image stays clean, full kernel mode
**Cons:** Extra container, needs `/dev/net/tun` access

---

## Sidecar Pattern

### How It Works

```
┌──────────────────────────────────────────────────────┐
│  Docker Compose with Sidecar                         │
│                                                      │
│  ┌──────────────────┐                               │
│  │  Tailscale        │  Gets IP: 100.x.x.x          │
│  │  Container        │  Connected to tailnet          │
│  │                   │  State in persistent volume    │
│  └────────┬──────────┘                               │
│           │                                          │
│           │ network_mode: "service:tailscale"        │
│           │                                          │
│  ┌────────┴──────────┐                               │
│  │  App Container    │  Shares 100.x.x.x             │
│  │                   │  Accessible via Tailscale      │
│  │  Port 3001        │  http://100.x.x.x:3001        │
│  └───────────────────┘                               │
└──────────────────────────────────────────────────────┘
```

### Key Line

```yaml
network_mode: "service:tailscale"
```

This makes the app container share the Tailscale container's network namespace. They have the same IP address.

### IP Persistence

```yaml
volumes:
  - ts-state:/var/lib/tailscale  # ← Persists node identity + IP
```

| Event | Auth key | Node | IP |
|-------|----------|------|----|
| First start | tskey-xxx | Created | 100.x.1 |
| Container restarts | tskey-xxx | Same | 100.x.1 |
| Volume persists | tskey-xxx | Same | 100.x.1 |
| Volume deleted | tskey-xxx | New | 100.x.2 |

---

## Tailscale Serve and Funnel

### Tailscale Serve

Exposes a local service to your tailnet with HTTPS.

```bash
tailscale serve 3001
# Creates: https://your-machine.tailnet.ts.net
```

- Private (only tailnet members)
- Auto HTTPS certificate
- Works for any port

> Source: [Tailscale Serve Docs](https://tailscale.com/kb/1242/tailscale-serve)

### Tailscale Funnel

Exposes a local service to the **public internet**.

```bash
tailscale funnel 3001
# Creates: https://your-machine.tailnet.ts.net (publicly accessible)
```

- Public (anyone on internet)
- Auto HTTPS certificate
- No port forwarding needed

> Source: [Tailscale Funnel Docs](https://tailscale.com/kb/1223/funnel)

**Funnel is available on the free plan** but limited to specific ports (443, 8443, 10000).

---

## Auth Key Guide

### Step-by-Step

1. **Sign up** at [login.tailscale.com/start](https://login.tailscale.com/start) (free)

2. **Go to keys**: [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)

3. **Generate auth key**:
   - Click "Generate auth key"
   - Check "Reusable" (survives restarts)
   - Check "Ephemeral" (auto-cleans dead nodes)
   - Optionally add a tag (e.g., `tag:dokploy`)
   - Copy the key (starts with `tskey-`)

4. **Use the key**:
   ```bash
   # In install script:
   sudo tailscale up --authkey tskey-xxx --accept-routes

   # In Docker compose:
   environment:
     TS_AUTHKEY: tskey-xxx
   ```

### Key Safety

> *"Be careful with auth keys! These can be very dangerous if stolen."*
> — [Tailscale Docs](https://tailscale.com/docs/features/ephemeral-nodes)

Best practices:
- Use ephemeral keys for containers
- Set expiration dates
- Revoke immediately if compromised
- Never commit to git (use env vars)
- Use [Tailscale ACLs](https://tailscale.com/kb/1018/acls) to restrict what tagged nodes can access

---

## Sources and Proof

### Pricing

- **Free plan confirmed**: [tailscale.com/pricing](https://tailscale.com/pricing)
  - "Free forever" explicitly stated
  - Personal plan: $0, up to 6 users, unlimited devices
  - Source: Tailscale official pricing page (accessed 2026)

- **Free plan blog post**: [tailscale.com/blog/free-plan](https://tailscale.com/blog/free-plan)
  - "unlimited free tier for individual use"
  - "Not a trial, a free tier"

### Ephemeral Nodes

- **Free on personal plan**: [tailscale.com/docs/features/ephemeral-nodes](https://tailscale.com/docs/features/ephemeral-nodes)
  - "Ephemeral node usage is included at no cost up to a monthly limit"
  - Personal plan: 1,000 minutes/month free
  - Auto-removed 30-60 min after going offline

### Device Limits

- **100 device limit**: [Reddit confirmation](https://www.reddit.com/r/selfhosted/comments/12qx6yy/)
  - "device cap got increased to 100"
- **6 users on free plan**: [tailscale.com/changelog](https://tailscale.com/changelog)
  - "The Personal plan provides up to six free users"

### Docker/Container Support

- **Official Tailscale Docker image**: [tailscale/tailscale on Docker Hub](https://hub.docker.com/tailscale/tailscale)
- **Sidecar pattern**: [tailscale.com/kb/1311/tailscale-docker](https://tailscale.com/kb/1311/tailscale-docker)
- **Userspace mode**: documented in [Docker image README](https://github.com/tailscale/tailscale/blob/main/dist/docker/README.md)

### Funnel (Public Access)

- **Available on free plan**: [tailscale.com/kb/1223/funnel](https://tailscale.com/kb/1223/funnel)
  - Ports 443, 8443, 10000 on free plan
