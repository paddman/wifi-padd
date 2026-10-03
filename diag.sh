#!/usr/bin/env bash
set -Eeuo pipefail

SECONDS_TO_SAMPLE="${1:-5}"
[[ "$SECONDS_TO_SAMPLE" =~ ^[0-9]+$ ]] || { echo "usage: wifi-cpu-diag [seconds]" >&2; exit 2; }

echo "=== wifi-cpu-balance status ==="
wifi-cpu-balance status || true

echo
echo "=== per-CPU utilization (${SECONDS_TO_SAMPLE}s) ==="
if command -v mpstat >/dev/null 2>&1; then
  mpstat -P ALL 1 "$SECONDS_TO_SAMPLE"
else
  echo "mpstat not installed; install sysstat for per-CPU utilization."
fi

echo
echo "=== softnet_stat ==="
cat /proc/net/softnet_stat

echo
echo "=== conntrack ==="
for p in \
  /proc/sys/net/netfilter/nf_conntrack_count \
  /proc/sys/net/netfilter/nf_conntrack_max
do
  [[ -r "$p" ]] && printf '%s = %s\n' "$p" "$(cat "$p")"
done

echo
echo "=== NIC counters ==="
for p in /sys/class/net/*; do
  iface="${p##*/}"
  [[ -e "$p/device" ]] || continue
  [[ "$(cat "$p/operstate" 2>/dev/null || true)" == "up" ]] || continue
  echo "--- $iface ---"
  ip -s link show dev "$iface" || true
  if command -v ethtool >/dev/null 2>&1; then
    ethtool -S "$iface" 2>/dev/null | grep -Ei \
      'drop|miss|error|timeout|no.?buffer|rx_queue|tx_queue' | head -n 120 || true
  fi
done
