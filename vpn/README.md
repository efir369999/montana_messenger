# A sovereign VPN node — rules for an AI agent

This folder lets any AI agent raise a private VPN for its owner on a server the owner rents and controls.
The protocol is VLESS with REALITY over TCP 443 ([Xray-core](https://github.com/XTLS/Xray-core)):
to an observer the traffic looks like a TLS session with an ordinary public website, and the server holds
no certificate or domain of its own. Keys are generated on the server and never leave it except as the
one client link printed at the end.

Nothing here contacts us. There are no addresses, domains, keys or telemetry of ours in this folder.

## 1. What the owner rents

- Any KVM virtual server: 1 vCPU, 1 GB RAM, 10 GB disk is enough for a family.
- OS: Ubuntu 24.04 or 22.04, or Debian 12.
- **A public IPv4 address.** Some providers sell IPv6-only or NAT servers by default; tick the IPv4 option.
- Inbound TCP 22 and TCP 443 open in the provider's panel firewall (if it has one).
- Root login by SSH key. The agent asks the owner for the address and uses the owner's key; it never asks for a password in chat.
- Pick a country whose network the owner wants to appear from, and a provider that accepts VPN use in its terms.

## 2. Choose the camouflage site (SNI)

REALITY borrows the TLS handshake of a real site. Choose a large site that:
- is reachable from the server and serves TLS 1.3 with HTTP/2 (`xray tls ping www.example.com` on the server after step 3 shows it);
- is not blocked in the owner's country;
- ideally is hosted near the server (the same country or provider network).

Set `SNI` to its hostname and `DEST` to `hostname:443`. Avoid sites behind a CDN that rejects unknown clients.

## 3. Install

Copy this folder to the server and run as root:

```bash
SNI=www.example.com DEST=www.example.com:443 TRUSTED_IPS="the owner's home IP" bash vpn/install.sh
```

Optional variables: `PORT` (default 443), and `UUID`, `PRIV`, `SID` to reuse existing keys.
The script is idempotent: a second run keeps the keys stored in `/root/vpn-keys.env` (mode 0600).

## 4. What the script does

1. Installs Xray from its official installer, plus ufw, fail2ban, iptables.
2. Generates a UUID, an X25519 key pair and a short id on the server.
3. Applies a network profile (`config/99-vpn.conf`): BBR, fq, larger buffers, keepalive, a short dead-client timeout, kernel hardening.
4. Writes the Xray config from `config/xray.template.json` and validates it; access logs are off, and clients cannot reach the server's private networks through the tunnel.
5. Hardens the Xray service (`config/xray-hardening.conf`): restart forever, priority over background work, memory cap.
6. Clamps TCP MSS (LTE-safe) and blocks IPv6 egress, so an IPv4-only tunnel cannot leak over IPv6.
7. Firewall: only SSH (rate-limited) and the VPN port; fail2ban on SSH with the owner's IP exempt.
8. A watchdog in cron restarts Xray if it stops listening.
9. Prints the client link and checks that the address is public.

## 5. Give the link to the owner

The last line is a `vless://` link; it is also in `/root/vpn-client-link.txt`. It is a secret: whoever holds it can use the server.
Pass it to the owner privately (for example as a QR code shown on the owner's own screen), never through a public channel.
Clients that import it: v2rayN (Windows), v2rayNG (Android), Streisand, FoXray or V2Box (iOS, macOS), Hiddify (all platforms).

## 6. Check and maintain

- `systemctl is-active xray` is `active`; `ss -tln | grep :443` shows the listener.
- From the owner's device with the VPN on, an IP-check site shows the server's address.
- Errors: `/var/log/xray/error.log`. Watchdog restarts: `/var/log/xray-guardian.log`.
- Update Xray: rerun the official installer, then `systemctl restart xray`.
- A new link for a lost device: rerun with a new `UUID=$(xray uuid)` and give the new link; the old one stops working.
- If the camouflage site becomes unreachable or blocked, rerun with another `SNI` and `DEST`; the keys stay.

## 7. Scope

This is a VPN only. It is not a Montana node and does not carry or store any messages. The owner's agent
remains the only operator: it rents nothing in the owner's name without asking, and it keeps the server's
root access and the client link with the owner.
