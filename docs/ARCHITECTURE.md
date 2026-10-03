# Architecture

## Datapath goal

Keep packet work on CPUs local to the NIC's PCIe NUMA node and spread queue work predictably. The tool does not try to make every CPU exactly equal at every instant. Flow hashing means some variance is normal; the goal is to remove pathological hotspots caused by queue/IRQ placement.

Packet path, simplified:

~~~text
NIC RX queue
  -> MSI-X IRQ on NUMA-local CPU
  -> NAPI poll / NET_RX softirq
  -> optional RPS/RFS
  -> bridge/routing/nftables/conntrack/NAT
  -> socket or forward path
  -> XPS-selected TX queue
  -> NIC
~~~

## Policy

### IRQ affinity

The physical NIC's MSI/MSI-X interrupts are distributed over eligible CPUs. CPU 0-3 are reserved by default.

### NUMA

When `/sys/class/net/<iface>/device/numa_node` is valid, only CPUs from that NUMA node are selected. Cross-socket packet processing can cost noticeably more memory bandwidth and cache traffic on large dual-socket gateways.

### RSS

The balancer asks `ethtool -X <iface> equal <rx-queues>` to spread the NIC RSS indirection table across the RX queues. Unsupported drivers are left unchanged.

### RPS/RFS

`RPS_MODE=auto` enables RPS only when RX queue count is below eligible CPU count. Each RX queue receives a partition of the CPU set instead of one giant all-CPU mask. This limits pointless cache bouncing.

RFS entries are distributed across RX queues and the global socket flow table is sized separately.

### XPS

Each TX queue receives a partition of the eligible CPUs so transmit queue selection is distributed instead of collapsing onto a small number of queues.

### Conntrack

`CONNTRACK_MAX=auto` scales with RAM and CPU and is capped at 8,388,608 entries. The hash table is targeted at roughly one bucket per four maximum entries when the kernel allows runtime hash-size changes.

Do not interpret a large conntrack maximum as a capacity guarantee. NAT capacity still depends on flow rate, packet size, NIC driver, firewall ruleset, memory latency and timeout profile.

## What to watch under load

A healthy test should show:

- `NET_RX` softirq counters increasing on many intended dataplane CPUs.
- no small set of NIC IRQs dominating all packet work.
- `/proc/net/softnet_stat` dropped/time-squeeze fields staying low.
- NIC driver `rx_*drop*` and `*_no_buffer*` counters staying flat or near-flat.
- conntrack count comfortably below maximum.
- p95/p99 latency remaining stable as CCU rises.

A single `iperf3` stream is not representative because RSS hashes one flow consistently. Test many concurrent source/destination/port tuples.

## Important `/16` limitation

A `/16` client subnet means up to 65,534 host addresses, but the practical problem is not the address count alone. A large shared L2 segment can generate excessive ARP, broadcasts, DHCP churn and client-to-client visibility. CPU balancing does not isolate those clients.

If the service contract requires one logical VLAN, isolation can still be introduced below or around it using access-point client isolation, private VLAN/port isolation, EVPN/VXLAN segmentation, routed access, or proxy ARP depending on the switching/WLAN design.
