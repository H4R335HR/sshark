#!/bin/bash
# firewall.sh — NAT, MSS clamp, kill-switch and DNS-leak guard for the gateway.
# Run once, then persist:  iptables-save > /etc/iptables/rules.v4
set -euo pipefail

LAN_IF=eth0
LAN_NET=192.168.1.0/24
SS_DNS=162.252.172.57,149.154.159.92     # must match dnsmasq-surf.conf

# NAT LAN traffic out of the tunnel; clamp MSS so large TCP packets aren't silently dropped
iptables -t nat    -A POSTROUTING -o wg0 -j MASQUERADE
iptables -t mangle -A FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Forward LAN → tunnel and replies back
iptables -A FORWARD -i "$LAN_IF" -o wg0 -s "$LAN_NET" -j ACCEPT
iptables -A FORWARD -i wg0 -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Kill-switch: anything else from the LAN is dropped (no fallback to your real IP)
iptables -A FORWARD -s "$LAN_NET" -j DROP

# Surfshark DNS never leaves outside the tunnel
iptables -A OUTPUT -d "$SS_DNS" ! -o wg0 -j DROP

iptables -L FORWARD -n -v --line-numbers
