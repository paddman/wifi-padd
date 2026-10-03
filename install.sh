#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run as root" >&2; exit 1; }

install -m 0755 "$ROOT_DIR/wifi-cpu-balance" /usr/local/sbin/wifi-cpu-balance
install -m 0755 "$ROOT_DIR/diag.sh" /usr/local/sbin/wifi-cpu-diag
install -m 0644 "$ROOT_DIR/wifi-cpu-balance.service" /etc/systemd/system/wifi-cpu-balance.service

if [[ ! -e /etc/wifi-cpu-balance.conf ]]; then
  install -m 0644 "$ROOT_DIR/wifi-cpu-balance.conf.example" /etc/wifi-cpu-balance.conf
  echo "created /etc/wifi-cpu-balance.conf"
else
  echo "kept existing /etc/wifi-cpu-balance.conf"
fi

systemctl daemon-reload
systemctl enable wifi-cpu-balance.service

cat <<'EOF'
Installed.

Before applying on a live gateway:
  1. Edit /etc/wifi-cpu-balance.conf
  2. wifi-cpu-balance plan
  3. wifi-cpu-balance status
  4. sudo systemctl start wifi-cpu-balance
  5. wifi-cpu-diag 5

For deterministic IRQ pinning, disable irqbalance after validating the plan:
  sudo systemctl disable --now irqbalance
EOF
