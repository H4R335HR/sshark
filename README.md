# sshark

**See every Surfshark location with its live load, and hot-swap your WireGuard tunnel to any of them, from the command line or over HTTP.**

`sshark` turns a small Linux box (a Proxmox LXC in the reference build) into a Surfshark VPN gateway for your LAN. Devices opt in by pointing their gateway at it. No VPN client on any device, one tunnel for everyone, and the server is yours to pick:

```
$ sshark list india
  LOAD             HOST                       COUNTRY              CITY                 TAGS
    8% #           in-mum                     India                Mumbai               virtual,p2p
   47% #####       in-del                     India                Delhi                virtual,p2p

$ sshark connect in-mum
Mumbai, India — load 8%
Switching to in-mum … up. Exit IP: 203.0.113.42
```

## Why

Surfshark's manual WireGuard setup gives you one config file for one location. Switching means going back to the dashboard and downloading another file. The official Linux app needs a desktop environment and manages the routing and firewall of the machine it runs on, so it doesn't fit a headless router.

The key observation: **your WireGuard key pair belongs to your account, not to a server.** Every location's config shares the same `[Interface]` (your private key and address); only the `[Peer]` (server public key and endpoint) differs. Surfshark publishes every location's public key and current load in the same server list its own apps use. So one downloaded config is enough, and `sshark` builds the peer for any location on demand.

## What's in the box

| File | Purpose |
| --- | --- |
| [`sshark`](sshark) | Server browser and switcher (bash, needs `jq`, `curl`, `wireguard-tools`) |
| [`sshark-web`](sshark-web) | Tiny HTTP wrapper: the URL path is the `sshark` command line |
| [`gateway/firewall.sh`](gateway/firewall.sh) | NAT, MSS clamp, kill-switch, DNS-leak guard |
| [`gateway/dnsmasq-surf.conf`](gateway/dnsmasq-surf.conf) | DNS forwarder so clients use the gateway, which forwards to Surfshark through the tunnel |
| [`gateway/vpn-watchdog`](gateway/vpn-watchdog) + `.service` / `.timer` | Every 2 min: if the tunnel is dead, fail over to the least-loaded location in the same country |
| [`gateway/sshark-web.service`](gateway/sshark-web.service) | systemd unit for `sshark-web` |
| [`docs/clients.md`](docs/clients.md) | Opting devices in: NetworkManager (CLI and GUI), GNOME, phones, Windows |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Gotchas found while building this |

## Usage

```
sshark list [filter]       every location, live load %, least loaded first, * = active
sshark regions             location count and average load per region
sshark ping <filter>       latency from your connection to matching endpoints
sshark connect <target>    switch to a location: code (sg-sng), city or country
sshark best [filter]       switch to the least-loaded match right now
sshark status              location, its current load, handshake age, transfer, exit IP
```

Filters match country, city, region or hostname as a case-insensitive substring. A **two-letter filter is a code** and matches exactly: `lu` is Luxembourg (not Kuala **Lu**mpur), `uk` and `gb` both find UK hosts.

Over HTTP with `sshark-web`:

```
curl <gateway-ip>/status
curl <gateway-ip>/list/japan
curl <gateway-ip>/connect/sg-sng
curl <gateway-ip>/best/asia%20pacific
```

### How switching works

- If `wg0` is up, `sshark` **hot-swaps the peer** with `wg set` (old peer removed, new peer added, fwmark re-asserted). The interface, routes and kill-switch never go down; clients see a pause of a second or two.
- If `wg0` is down, it runs `systemctl restart wg-quick@wg0`.
- The server list is cached in `/var/cache/sshark/servers.json`. If the API is unreachable (for example because the tunnel is dead), the cache is used.

## Architecture

```
                 Internet
                    │
            ┌───────┴───────┐
            │    Router     │ 192.168.1.1
            └───────┬───────┘
                    │ LAN 192.168.1.0/24
       ┌────────────┴─────────────┐
       │                          │
┌──────┴───────┐          ┌───────┴──────────┐
│ Opted-in     │          │ Gateway          │
│ device       │─────────▶│ eth0 .50         │
│ gw  = .50    │          │ wg0  (Surfshark) │
│ dns = .50    │          │ dnsmasq, NAT,    │
└──────────────┘          │ kill-switch      │
                          └───────┬──────────┘
 Other devices: untouched         │ WireGuard UDP 51820
 (gateway = router)        Surfshark location
```

All addresses in this repo are examples. Replace `192.168.1.50` (gateway), `192.168.1.1` (router) and `192.168.1.0/24` (LAN) with yours.

## Setup (Proxmox LXC reference build)

Any Debian-like box works. These steps use an unprivileged Debian 13 container on Proxmox VE.

### 1. Host: load WireGuard and create the container

Containers can't load kernel modules, so the host does:

```bash
modprobe wireguard
echo wireguard > /etc/modules-load.d/wireguard.conf

pct create <CTID> local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname surf-gw --cores 1 --memory 128 --swap 128 \
  --unprivileged 1 --features nesting=1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --onboot 1 --rootfs local-lvm:4
pct start <CTID>
```

Inside the container, confirm WireGuard works unprivileged:

```bash
ip link add wgtest type wireguard && echo "WG OK" && ip link del wgtest
```

Give the container a fixed IP (a DHCP reservation on your router is easiest). Clients will use it as their gateway.

### 2. Container: packages and forwarding

```bash
apt update
apt install -y wireguard-tools iptables iptables-persistent jq curl dnsmasq
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-forward.conf
sysctl --system
```

### 3. Your Surfshark key

In the Surfshark dashboard: **VPN → Manual setup → Router → WireGuard**, generate a key pair, then download the config for **any** location. Keep only the `[Interface]` part:

```bash
mkdir -p /etc/wireguard
awk '/^\[Peer\]/{exit} !/^DNS/' downloaded.conf > /etc/wireguard/ss-base.conf
chmod 600 /etc/wireguard/ss-base.conf
grep '^DNS' downloaded.conf      # note these resolvers for dnsmasq / firewall
rm downloaded.conf
```

`ss-base.conf` should contain just `PrivateKey` and `Address`. It never leaves the gateway.

### 4. Install sshark and connect

```bash
install -m 755 sshark /usr/local/sbin/sshark
sshark list india
sshark ping asia pacific
sshark connect sg-sng
systemctl enable wg-quick@wg0
```

On Proxmox, `pct enter` gives a minimal `PATH` without `/usr/local/sbin`. Add it to `/root/.bashrc` or use the full path.

### 5. Firewall, DNS, watchdog

```bash
# edit LAN_NET / SS_DNS first
bash gateway/firewall.sh
iptables-save > /etc/iptables/rules.v4

# edit listen-address and the local-domain line first
cp gateway/dnsmasq-surf.conf /etc/dnsmasq.d/surf.conf
systemctl restart dnsmasq

install -m 755 gateway/vpn-watchdog /usr/local/sbin/vpn-watchdog
cp gateway/vpn-watchdog.{service,timer} /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now vpn-watchdog.timer
```

### 6. Optional: sshark-web

```bash
apt install -y python3
install -m 755 sshark-web /usr/local/sbin/sshark-web
cp gateway/sshark-web.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now sshark-web
```

> ⚠️ **`sshark-web` has no authentication.** Anyone who can reach port 80 can switch the tunnel, and any web page opened on your LAN could trigger a switch with a plain GET request (CSRF). Arguments are passed as a list, never through a shell, so URL contents can't inject commands. Still, use it only on a LAN you trust, and never expose it beyond that. Hardening ideas: POST plus a token header for `connect`/`best`, an argument allowlist, a firewall rule limiting port 80 to your LAN, rate limiting.

### 7. Opt a device in

See [`docs/clients.md`](docs/clients.md). The short version for NetworkManager:

```bash
nmcli connection clone "Wired connection 1" "Surfshark"
nmcli connection modify "Surfshark" \
  connection.autoconnect no \
  ipv4.never-default yes \
  ipv4.routes "0.0.0.0/0 192.168.1.50" \
  ipv4.ignore-auto-dns yes \
  ipv4.dns "192.168.1.50" \
  ipv6.method disabled
nmcli connection up "Surfshark"
```

Then check `curl ifconfig.me` and run a DNS leak test.

### Verify the kill-switch

On a client, run `while true; do curl -s --max-time 3 ifconfig.me || echo BLOCKED; echo; sleep 2; done`, then on the gateway run `systemctl stop wg-quick@wg0`. The client must show `BLOCKED`, never your real IP. Bring it back with `systemctl restart wg-quick@wg0`.

## Caveats

- **The server-list API is undocumented.** `sshark` uses `https://api.surfshark.com/v4/server/clusters/generic`, which Surfshark's own apps use. It could change without notice.
- **Load is per location, not per physical server.** Each hostname is a cluster spread across several machines by DNS. A plain restart re-resolves and can land you on a different server in the same location, which is often a quick fix for congestion.
- **Load isn't latency.** Use `sshark ping` to see the real round trip from your connection.
- **`virtual`** locations give you an IP from that country on hardware located elsewhere.
- Only standard ("generic") locations are covered, not MultiHop or static-IP.
- If every location stops handshaking, your key was probably revoked or expired. Generate a new one and update `PrivateKey` in `ss-base.conf`.

## Disclaimer

**Things can change at any time, and this tool may stop working without notice.**

- `sshark` depends on Surfshark's **undocumented** server-list API (`api.surfshark.com/v4/server/clusters/generic`). Its address, fields or availability can change or disappear whenever Surfshark updates its apps.
- Server hostnames, WireGuard public keys, DNS resolver addresses, ports, the manual-setup flow in the dashboard, and key validity are all controlled by Surfshark and may change without warning.
- Values in this repo (Surfshark DNS IPs, example addresses, load figures, command output) were accurate when written and are examples only. Verify them against your own downloaded config.
- Behaviour was tested on one setup (Proxmox VE 9, Debian 13 unprivileged LXC, WireGuard kernel module). Other kernels, distributions and NetworkManager versions may differ.

This project is **not affiliated with, endorsed by, or supported by Surfshark**. You need your own Surfshark subscription, and you are responsible for using it within Surfshark's terms of service and the laws where you live.

It is provided as-is, without warranty of any kind. It changes routing and firewall rules: test the kill-switch yourself before relying on it for anything that matters.

## License

[MIT](LICENSE)
