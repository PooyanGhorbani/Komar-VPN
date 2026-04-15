# Komar-VPN 0.10

Multi-mode tunnel manager with:
- Quick Tunnel for testing
- Permanent Cloudflare Tunnel via Tunnel Token
- Multi-user management (per-user link, expiry, quota, usage sync)

## Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PooyanGhorbani/Komar-VPN/main/komar-vpn.sh)
```

## Main modes

1. **Quick Tunnel for testing**  
   Creates a temporary `trycloudflare.com` tunnel and prints a test link.

2. **Permanent token tunnel**  
   Uses a Cloudflare Tunnel Token and runs `cloudflared` as a systemd service.

3. **User management**  
   Add users, set expiry, set quota, show links, and sync usage.

## One-time Cloudflare setup for permanent mode

Before using mode 2, do this once in Cloudflare:

1. Create a **remotely-managed** Cloudflare Tunnel in the dashboard.
2. Create a **Public Hostname** for your domain, for example `vpn.example.com`.
3. Point that hostname to your local service target, for example:
   - `http://localhost:18080`
4. Copy the **Tunnel Token** from the `cloudflared` install command.
5. Run `komar-vpn.sh`, choose mode **2**, and paste:
   - your domain
   - the tunnel token
   - local port (default `18080`)

After that, the service runs automatically with systemd and does not need browser authorization again.

## Installed paths

- App dir: `/opt/komar-vpn`
- Manager command: `/usr/bin/komar-vpn`
- Database: `/opt/komar-vpn/data/users.db`
- Tunnel token file: `/opt/komar-vpn/data/tunnel.token`

## Notes

- Quick Tunnel is for testing only.
- For permanent mode, Cloudflare dashboard configuration must already exist.
- Usage sync runs every minute via `komar-vpn-sync.timer`.
