#!/usr/bin/env bash
# Fix dual-IP and ensure 80/443 for public HTTPS (ai.knonix.com).
set -euo pipefail
if [[ "$(id -u)" -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

echo "==> Prefer single LAN IP 192.168.0.2 (DMZ target)"
if [[ -f /home/knonix/apply-dmz-ip.sh ]]; then
  bash /home/knonix/apply-dmz-ip.sh || true
fi

# Open ports if ufw active
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi active; then
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 443/udp || true
  echo "    UFW: allowed 22/80/443"
fi

echo "==> Addresses:"
ip -4 addr show enp0s1 | sed 's/^/  /'
echo
echo "Router checklist:"
echo "  - DMZ or port-forward 80+443 TCP (and 443 UDP for HTTP/3) -> 192.168.0.2"
echo "  - DNS A record ai.knonix.com -> your public IP"
echo "  - Test from phone LTE (not Wi-Fi): curl -fsS https://ai.knonix.com/api/knonix/health"
