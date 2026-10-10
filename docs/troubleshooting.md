# Troubleshooting

Problems hit while building and testing this. Each one cost a debugging session.

## Switching a running tunnel gives `Handshake: never`

**Symptom:** switching from a stopped tunnel works, but switching while the tunnel is up leaves the new server with no handshake.

**Cause:** this happened in early versions that used `wg syncconf wg0 <(wg-quick strip wg0)`. `syncconf` applies the config exactly as written, and the stripped config has no `FwMark`, so it cleared the mark wg-quick had set (`wg show wg0 fwmark` → `off`). wg-quick's policy routing sends every **unmarked** packet into the tunnel, including WireGuard's own handshakes, so they looped into `wg0` and never reached the server.

**Fix:** current `sshark` swaps peers with `wg set`, which leaves the rest of the interface alone, and sets `fwmark 51820` explicitly. A healthy tunnel shows:

```
$ wg show wg0 fwmark
0xca6c
```

## `systemctl start wg-quick@wg0` does nothing after `wg-quick down`

A manual `wg-quick down` takes the tunnel down behind systemd's back. The unit stays `active (exited)`, and `start` on an active unit is a no-op. Use `systemctl stop` / `systemctl restart wg-quick@wg0`, never bare `wg-quick down`, on a tunnel systemd manages. `sshark` uses `restart` for this reason.

## Watchdog failed over to the wrong country

Early versions matched filters as substrings, so `sshark best lu` (Luxembourg) picked Kuala **Lu**mpur because it had lower load. Two-letter filters are now exact codes.

## `sshark: command not found` in a Proxmox container

`pct enter` starts a shell with `PATH=/sbin:/bin:/usr/sbin:/usr/bin`, which doesn't include `/usr/local/sbin`. Add `export PATH=/usr/local/sbin:/usr/local/bin:$PATH` to `/root/.bashrc`. systemd services already include it.

## dnsmasq fails after a reboot

With `bind-interfaces`, dnsmasq can start before DHCP has assigned the LAN address and fail to bind. Use `bind-dynamic`, which picks the address up when it appears.

## `exit IP ?` although traffic passes

Some IP-echo services refuse or stall for VPN exit addresses. `sshark` tries `api.ipify.org`, then `ifconfig.me`. A `?` there doesn't mean the tunnel is broken; `Traffic: OK` comes from a separate ping test.

## "API unreachable; using cached list"

The gateway's own traffic, including the server-list download, goes through the tunnel. When the tunnel is dead, the fetch times out and the cache is used. That's expected, and it's what the watchdog relies on during failover.

## Client shows two default routes

See [clients.md](clients.md#linux-networkmanager-gui). On the profile, tick *Use this connection only for resources on its network* (`ipv4.never-default yes`).

## Is it leaking?

```bash
# on the gateway
sshark status
iptables -L FORWARD -n -v --line-numbers    # ACCEPT, ACCEPT, DROP — the DROP is the kill-switch
ip rule                                     # wg-quick's fwmark 51820 rules

# on a client
ip route                                    # one default route, via the gateway
curl -s ifconfig.me                         # Surfshark IP
```

Then run the kill-switch test from the README.
