# Opting devices in

A device uses the VPN when its **default gateway** and **DNS server** are the sshark gateway. Nothing changes on the router, and each device chooses for itself.

Examples use gateway `192.168.1.50` on LAN `192.168.1.0/24`. Replace them with yours.

## Linux: NetworkManager (CLI)

Clone your normal connection into a second profile and switch between the two:

```bash
nmcli -t -f NAME,DEVICE connection show --active     # find your connection's name
nmcli connection clone "Wired connection 1" "Surfshark"
nmcli connection modify "Surfshark" \
  connection.autoconnect no \
  ipv4.never-default yes \
  ipv4.routes "0.0.0.0/0 192.168.1.50" \
  ipv4.ignore-auto-dns yes \
  ipv4.dns "192.168.1.50" \
  ipv6.method disabled

nmcli connection up "Surfshark"             # VPN on
nmcli connection up "Wired connection 1"    # VPN off
```

| Setting | Why |
| --- | --- |
| `autoconnect no` | Your normal profile stays the default; the VPN is used only when you pick it |
| `never-default` + `0.0.0.0/0` route | Keep the DHCP address, but ignore the router as gateway |
| `ignore-auto-dns` + `dns` | DNS goes to the gateway's dnsmasq, then to Surfshark through the tunnel |
| `ipv6.method disabled` | The router can't hand out an IPv6 DNS server that bypasses the tunnel |

**Keeping a route to another gateway:** add it to `ipv4.routes`. It is more specific than the default route, so it wins. For example, to keep a lab range on a separate gateway: `"0.0.0.0/0 192.168.1.50, 10.48.0.0/12 192.168.1.51"`.

## Linux: NetworkManager GUI

Open **Advanced Network Configuration** (`nm-connection-editor`, or right-click the network icon → *Edit Connections…*), click **+**, choose Ethernet or Wi-Fi, and name it `Surfshark`.

| Tab | Setting |
| --- | --- |
| Ethernet / Wi-Fi | Device: your LAN interface (Wi-Fi also needs SSID and password) |
| General | Untick **Connect automatically** |
| IPv4 Settings | Method **Automatic (DHCP) addresses only**; Additional DNS servers `192.168.1.50` |
| IPv4 Settings → Routes… | Tick **Use this connection only for resources on its network**. Add `0.0.0.0` / `0` / `192.168.1.50`. Leave *Ignore automatically obtained routes* unticked |
| IPv6 Settings | Method **Disable** |

Switch from the network icon's menu.

**Check it:** `ip route` must show exactly **one** default route, via `192.168.1.50`. If you see a second `default via <router>`, the "Use this connection only for resources on its network" box isn't ticked. With equal metrics, which route wins depends on ordering, so traffic could leave on your real IP. Also check that `ip a` shows no `inet6` addresses on the interface.

## GNOME Settings

**Settings → Network → Wired → +**, then:

- **Identity:** name it
- **IPv4:** Method *Automatic (DHCP)*; DNS *Automatic* off with `192.168.1.50`; add the `0.0.0.0 / 0 / 192.168.1.50` route; tick *Use this connection only for resources on its network*
- **IPv6:** *Disable*
- **Details:** untick *Connect automatically*

## Phones, Windows, macOS

These don't offer "keep DHCP, change only the gateway", so use a **static IP** while on the VPN:

| Field | Value |
| --- | --- |
| IP address | A free address **outside** your router's DHCP pool, e.g. `192.168.1.200` |
| Netmask / prefix | `255.255.255.0` / `24` |
| Gateway / router | `192.168.1.50` |
| DNS | `192.168.1.50` |

- **Android:** Wi-Fi network → Edit / Advanced → IP settings → Static
- **iOS:** Wi-Fi network (i) → Configure IP → Manual; Configure DNS → Manual
- **Windows:** adapter → Properties → IPv4 → Use the following IP address
- **macOS:** Network → interface → Details → TCP/IP → Manually

Switch back to DHCP to turn the VPN off.

## Verify any client

```bash
ip route                      # one default route, via the gateway
curl -s ifconfig.me; echo     # Surfshark exit IP, not yours
```

Then run the standard test at dnsleaktest.com. Only Surfshark servers should appear.
