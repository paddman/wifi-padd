# wifi-padd

NUMA-aware Linux CPU/NIC queue balancer for high-CCU WiFi hotspot gateways.

The problem this repo targets is the common x86 hotspot failure mode where a 25/40/100G NIC has many queues, but IRQ/softirq work still piles onto a small set of CPU cores. Adding more cores does not fix bad queue/IRQ placement by itself. Silicon is annoyingly literal.

## What it balances

- NIC MSI/MSI-X IRQ affinity across CPUs local to the NIC's NUMA node.
- Hardware RSS indirection across existing RX queues.
- RPS only when hardware RX queues are fewer than usable CPUs.
- XPS so transmit queue selection is spread across CPU groups.
- RFS flow table sizing for better socket/flow locality.
- `netdev` backlog/budget and conntrack capacity for hotspot/NAT workloads.
- Keeps a reserved CPU set for OS, routing daemons, RADIUS, DHCP and control-plane work.

This does **not** replace L2 design. A single giant `/16` broadcast domain can still drown in ARP/broadcast/client churn even with perfect CPU balancing. CPU balancing fixes CPU/queue concentration, not a broadcast-domain architecture problem.

## Quick start

Ubuntu/Debian dependencies:

~~~bash
sudo apt update
sudo apt install -y ethtool sysstat
git clone https://github.com/paddman/wifi-padd.git
cd wifi-padd
sudo ./install.sh
~~~

Edit:

~~~bash
sudo nano /etc/wifi-cpu-balance.conf
~~~

For a gateway with two physical 25G ports:

~~~bash
INTERFACES="ens3f0np0 ens3f1np1"
RESERVED_CPUS="0-3"
USE_NUMA_LOCAL=1
MANAGE_CHANNELS=0
RPS_MODE="auto"
~~~

Inspect before touching a live dataplane:

~~~bash
sudo wifi-cpu-balance plan
sudo wifi-cpu-balance status
~~~

Apply:

~~~bash
sudo systemctl start wifi-cpu-balance
sudo wifi-cpu-diag 10
~~~

After validating the CPU plan, stop `irqbalance` so it does not later overwrite explicit IRQ pinning:

~~~bash
sudo systemctl disable --now irqbalance
sudo systemctl restart wifi-cpu-balance
~~~

## Production rollout order

1. Start with `MANAGE_CHANNELS=0`. Use the NIC's current queue count.
2. Reserve 2-4 housekeeping CPUs per socket/host depending on control-plane load.
3. Verify every NIC is mapped to the correct NUMA node.
4. Apply IRQ/RSS/RPS/XPS tuning.
5. Load test with real hotspot flows, not only `iperf3` from one client.
6. Check `NET_RX` softirq spread, `/proc/net/softnet_stat`, packet drops, conntrack count and per-core CPU.
7. Only then consider increasing NIC combined channels during a maintenance window.

## Why `RPS_MODE=auto`

If the NIC already exposes enough hardware RX queues to cover the selected CPUs, hardware RSS is cheaper and usually better than pushing packets through software RPS again. If the NIC exposes fewer queues than usable CPUs, RPS can fan receive processing out further.

## Useful checks

~~~bash
wifi-cpu-balance status
wifi-cpu-diag 10
grep NET_RX /proc/softirqs
cat /proc/net/softnet_stat
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
ethtool -l ens3f0np0
ethtool -x ens3f0np0
~~~

## 60,000-client note

For tens of thousands of WiFi clients, the CPU balancer is only one layer. The gateway should also be checked for:

- DHCP lease/churn rate and DHCP service architecture.
- ARP/broadcast containment.
- RADIUS latency and DB pool sizing.
- conntrack occupancy and NAT port pressure.
- per-NIC RX/TX drops.
- bridge/netfilter path cost.
- captive-portal session table design.
- traffic shaping implementation. Per-client qdisc structures can become expensive at large CCU.

See `docs/ARCHITECTURE.md`.
