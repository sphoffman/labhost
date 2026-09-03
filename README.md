# labhost v1.4 — Containerlab Network Swiss Army Knife

`labhost` is a reusable Linux endpoint/test appliance for Containerlab. It is intentionally tool-heavy: the goal is to drop it into a topology and already have the troubleshooting, traffic-generation, multicast, packet-capture, service-emulation, VLAN/LAG, VRF, persistence, and impairment tools you need.

## What changed in v1.4

v1.4 keeps the v1.3 networking, capture, traffic-generation, impairment, VRF,
VLAN, QinQ, LAG, multicast, and service helpers, and adds:

- Deterministic, host-aware synthetic clients with continuation numbering,
  per-client ARP isolation, status, ARP, ping, and traffic helpers.
- First-class DHCP client intent for physical and VLAN interfaces.
- Persistent multi-pool dnsmasq DHCP server helpers and a readable
  `dhcp-leases` viewer.
- PC-behind-LLDP-MED-phone emulation with deterministic PC/phone identities,
  voice-VLAN discovery, bulk creation, and rich status.
- Hardened `lab-reset` behavior that removes derived dataplane state without
  deleting physical Containerlab dataplane interfaces.
- Runtime high-level intent under `/run/labhost/intents`, converted by
  `lab-save` into the sole persistent authority,
  `/config/<hostname>.sh`.
- A default MTU of 9000 on physical dataplane interfaces (`eth1+`), with
  `LABHOST_DATA_MTU` available as an override.

The automatic management VRF remains `vrf-mgmt`, routing table 4094. The
management interface `eth0` is never treated as a dataplane interface.

---

# Build

The canonical image source is `/storage/Labs/images/labhost/`. Build from
the repository root so the Docker context is correct:

```bash
cd /storage/Labs
git switch labhost-phase3r4-r3
git pull --ff-only
docker build -t labhost:1.4-dev22 images/labhost
```

Do not replace `labhost:latest`, build the final `labhost:1.4` image, merge
to `main`, or create the `labhost-v1.4` tag until final regression and
release verification have passed.

## Host bonding support

Linux bonding is provided by the Ubuntu host kernel.

The lab server should have:

```bash
cat /etc/modules-load.d/bonding.conf
```

with:

```text
bonding
```

Load it immediately if needed:

```bash
sudo modprobe bonding
```

Verify:

```bash
lsmod | grep bonding
```

Because bonding is loaded by the host kernel, every labhost container can use LACP/bonding without loading a kernel module inside the container.

## Quick validation

```bash
images/labhost/smoke-test.sh labhost:1.4-dev22
```

---

# PATH behavior

Debian normally omits `/usr/sbin` and `/sbin` from a non-root user's SSH PATH. Several lab tools live there, including:

- `tc`
- `trafgen`
- `mausezahn`

labhost sets the networking PATH in the Docker image, interactive shell, and login-shell environment:

```text
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Verify:

```bash
echo $PATH
which tc
which trafgen
which mausezahn
```

---

# Documentation inside the container

The complete README is installed at:

```text
/usr/local/share/labhost/README.md
```

Open it with:

```bash
lab-readme
```

For a concise helper inventory:

```bash
lab-help
```

For detailed command-specific help:

```bash
lab-help lag-create
lag-create --help
netem --help
vrf-create --help
```

---

# Login

The container starts OpenSSH automatically.

Default credentials:

```text
Username: lab
Password: lab
```

Override the password in Containerlab:

```yaml
env:
  LAB_PASSWORD: something-else
```

The `lab` account has passwordless `sudo` because this image is intended for isolated network labs.

---

# Required runtime permissions

labhost uses Linux networking features that a normal unprivileged container cannot modify by default.

The required Containerlab settings are:

```yaml
cap-add:
  - NET_ADMIN
  - NET_RAW

sysctls:
  net.ipv4.tcp_l3mdev_accept: "1"
```

These are required for the following reasons:

- `NET_ADMIN` — interface configuration, routes, VRFs, VLANs, QinQ, LAG/bonding, bridges, MTU/MAC changes, and `tc`/NetEm.
- `NET_RAW` — raw packet operations used by tools such as packet capture/generation, ping, arping, Scapy, and related utilities.
- `net.ipv4.tcp_l3mdev_accept=1` — allows wildcard TCP listeners such as SSH to accept connections arriving through the automatic management VRF.

The container intentionally does **not** require `--privileged` or broader capabilities such as `SYS_ADMIN`.

# Recommended Containerlab node template

A reusable labhost node should look like:

```yaml
host4:
  kind: linux
  image: labhost:1.4-dev22
  binds:
    - ./configs:/config
    - ./pcaps:/pcaps
  cap-add:
    - NET_ADMIN
    - NET_RAW
  sysctls:
    net.ipv4.tcp_l3mdev_accept: "1"
```

The bind mounts provide:

```text
./configs -> /config   Persistent labhost startup configuration
./pcaps   -> /pcaps    Packet captures stored outside the container
```

The management VRF setup depends on the sysctl above. Without it, `vrf-mgmt` can still be created, but SSH through the management interface may not work correctly.

## Running outside Containerlab

The same image can be run directly with Docker.

Create persistent directories first:

```bash
mkdir -p ./configs ./pcaps
```

Then start the container:

```bash
docker run -d \
  --name labhost-test \
  --hostname labhost-test \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --sysctl net.ipv4.tcp_l3mdev_accept=1 \
  -p 127.0.0.1::22 \
  -v "$(pwd)/configs:/config" \
  -v "$(pwd)/pcaps:/pcaps" \
  -e LAB_PASSWORD=lab \
  labhost:1.4-dev22
```

Docker will choose an available localhost port for SSH. Find it with:

```bash
docker port labhost-test 22/tcp
```

For example, Docker may return:

```text
127.0.0.1:32789
```

Then connect with:

```bash
ssh -p 32789 lab@127.0.0.1
```

Using `127.0.0.1::22` instead of a fixed host port avoids collisions with other containers and keeps the temporary SSH service bound only to localhost.

Recommended VS Code interface pattern:

```text
eth{n:1}
```

Containerlab uses `eth0` for management. Lab-facing interfaces begin with:

```text
eth1
eth2
eth3
...
```

`NET_ADMIN` enables VLAN/LAG creation, bridges, VRFs, routes, `tc`/NetEm, MAC/MTU changes, and similar operations.

`NET_RAW` enables raw packet operations such as packet capture/generation, ping, arping, and Scapy-style testing.

## Persistent lab directories

`labmgmt apply` creates:

```text
<lab>/configs/
<lab>/pcaps/
```

The lab topology bind-mounts:

```text
./configs -> /config
./pcaps   -> /pcaps
```

Startup scripts under `configs/` belong in Git.

Packet captures under `pcaps/` are intentionally ignored by the lab repository `.gitignore`, except for `.gitkeep`.

---

# Management VRF design

labhost v1.4 automatically treats `eth0` as management-only.

At startup:

```text
eth0
  |
vrf-mgmt
table 4094
```

The entrypoint:

1. learns the Containerlab management gateway before moving `eth0`;
2. creates `vrf-mgmt`;
3. uses routing table `4094`;
4. moves `eth0` into the management VRF;
5. restores the management default route in table `4094`;
6. sets:

```bash
net.ipv4.tcp_l3mdev_accept=1
```

so wildcard TCP listeners such as SSH can receive connections through the VRF.

The normal Linux `main` routing table remains available for lab interfaces:

```text
main
  eth1
  eth2
  bond0
  eth1.100
  ...
```

This allows a management default route and an independent lab default route at the same time, including overlapping IP prefixes between the home network and a lab.

Inspect management VRF state:

```bash
mgmt-vrf-status
```

Or:

```bash
vrf-status
```

Routing table `4094` is reserved for `vrf-mgmt`.

---

# User-created VRFs

Linux VRFs provide routing-instance-like behavior.

Create VRFs:

```bash
vrf-create blue 101
vrf-create red 102
```

Create VLAN subinterfaces:

```bash
vlan-create eth1 100
vlan-create eth1 200
```

Place each VLAN into a different VRF:

```bash
vrf-add blue eth1.100
vrf-add red eth1.200
```

Assign addresses:

```bash
ip-set eth1.100 10.1.0.2/24
ip-set eth1.200 10.2.0.2/24
```

Add independent defaults:

```bash
vrf-route-add blue default 10.1.0.1
vrf-route-add red default 10.2.0.1
```

The resulting model is:

```text
                 eth1
                  |
             802.1Q trunk
             /          \
       eth1.100      eth1.200
          |              |
       vrf-blue        vrf-red
       table 101       table 102
```

Inspect:

```bash
vrf-status
vrf-status blue
vrf-status red
```

Run applications in a VRF:

```bash
vrf-exec blue ping 8.8.8.8
vrf-exec blue traceroute 10.50.0.1
vrf-exec red iperf3 -c 10.60.0.10
vrf-exec red curl http://10.2.0.20/
```

Remove an interface from a VRF:

```bash
vrf-remove eth1.100
```

Delete:

```bash
vrf-delete blue
```

The automatic management VRF is protected from normal delete/remove helpers.

---

# Configuration persistence

Containerlab destroys and recreates generic Linux containers. labhost therefore
uses one deliberately simple persistence boundary:

```text
interactive helper
    -> current Linux state + /run/labhost/intents
    -> lab-save
    -> /config/<hostname>.sh
    -> startup replay after recreate
```

`/config/<hostname>.sh` is the **only authoritative persistent
configuration**. High-level working intent is kept under
`/run/labhost/intents`; it is runtime state and disappears with the
container. The obsolete `/config/.labhost` tree is not read and must not
influence behavior.

Interactive changes are not persistent until you run `lab-save`.

## Preview, save, and inspect

```bash
lab-save --dry-run
lab-save
lab-config
lab-config path
lab-config edit
```

For host `host1`, `lab-save` writes `/config/host1.sh`. With the
recommended bind mount, that is `<lab>/configs/host1.sh` on the Containerlab
host. An existing script is backed up as `host1.sh.bak`.

At startup the entrypoint executes `/config/<hostname>.sh`. High-level
commands in that script recreate both the live object and its runtime intent,
so a later `lab-save` continues to preserve the abstraction.

## What lab-save preserves

`lab-save` reconstructs supported state including IPv4/IPv6 addresses,
routes, VLANs, QinQ, LAGs, user VRFs and VRF routes, non-default MTUs, NetEm
state, synthetic clients, DHCP client intent, DHCP pools/server state, and
PC/phone intent.

For high-level or dynamic objects, it saves intent rather than incidental
derived state:

- DHCP is saved as `ip-set <iface> dhcp` or
  `vlan-create <parent> <vid> dhcp`; leases and learned routes are not frozen.
- DHCP pool definitions and enabled server state are saved; active leases are
  not.
- Synthetic clients and PC/phone objects are saved as their creation commands,
  not as derived macvlan/VLAN/DHCP state.
- MTU 9000 is the dataplane default and is omitted; only deviations are saved.

The entrypoint recreates `vrf-mgmt` and table 4094, so management state is
not written into the startup script. Runtime services such as
`iperf-server`, `mcast-join`, and `http-server` are not inferred; add
such commands manually to the startup script only when deliberately desired.

---

# Helper commands

Run:

```bash
lab-help
```

for the compact inventory.

All helpers support command-specific assistance where applicable:

```bash
lab-help vlan-create
vlan-create --help
vlan-create -h
```

If a required argument is omitted, the helper prints its useful syntax rather than only returning a cryptic shell error.

The helpers document likely/common options. Use the underlying Linux tool directly for advanced usage.

---

# General

## lab-status

```bash
lab-status
```

Shows:

- hostname
- interfaces
- addresses
- main IPv4/IPv6 routes
- neighbors
- VRFs
- bonds
- VLANs
- qdisc/NetEm state
- listening ports
- help/documentation shortcuts

Containerlab peer suffixes such as:

```text
eth1@if57
```

are cosmetically displayed as:

```text
eth1
```

The actual Linux interface name remains `eth1`.

At the bottom:

```text
=== Help & Documentation ===
Commands:  lab-help
README:    lab-readme
```

## lab-reset

```bash
lab-reset
```

Conservatively removes test-created state while preserving the Containerlab management path and automatic management VRF.

---

# LACP / LAG

Create active/fast 802.3ad:

```bash
lag-create eth1 eth2
```

Inspect:

```bash
lag-status
```

Named bond:

```bash
lag-create eth1 eth2 bond10
```

Alternate Linux bonding mode:

```bash
lag-create eth1 eth2 bond0 active-backup
```

Failure testing:

```bash
lag-member-down eth2
lag-member-up eth2
```

Delete:

```bash
lag-delete bond0
```

Capture LACP:

```bash
capture-lacp eth1
```

---

# VLANs and QinQ

Create VLAN:

```bash
vlan-create eth1 100 10.100.0.10/24
```

On a bond:

```bash
vlan-create bond0 200 10.200.0.10/24
```

Inspect/delete:

```bash
vlan-list
vlan-delete bond0.200
```

QinQ / 802.1ad:

```bash
qinq-create eth1 100 200 10.20.0.10/24
qinq-delete eth1.100.200
```

---

# IP, routes, MAC, MTU, and failures

```bash
ip-set eth1 10.1.1.10/24 10.1.1.1
ipv6-set eth1 2001:db8:1::10/64 2001:db8:1::1

route-add 10.20.0.0/16 10.1.1.1 eth1
route-del 10.20.0.0/16
default-gw 10.1.1.1 eth1

mac-set eth1 02:00:00:00:00:10
mtu-set eth1 1500
mtu-all 9000

link-down eth1
link-up eth1
link-flap eth1 5
```

`eth1` and higher physical dataplane interfaces default to MTU 9000.
Override the image-wide default with `LABHOST_DATA_MTU`. `lab-save` omits
interfaces at the default and records only MTU deviations.

`link-flap` is useful for LACP, EVPN, BFD, redundancy, and convergence demonstrations.

---

# Path and port testing

```bash
path-test 10.20.30.40
port-test 10.20.30.40 443
ports-scan 10.20.30.40
```

`path-test` combines route lookup, ping, traceroute, MTR, and neighbor-table display.

---

# Packet capture

Interactive:

```bash
capture eth1
capture eth1 tcp port 443
```

Save to `/pcaps`:

```bash
capture-save eth1 problem.pcap
capture-save eth1 multicast.pcap host 239.1.1.1
```

Rotating capture:

```bash
capture-ring eth1 long-test.pcap
```

Read:

```bash
capture-read problem.pcap
```

Protocol shortcuts:

```bash
capture-lacp eth1
capture-igmp eth1
capture-pim eth1
capture-arp eth1
capture-nd eth1
```

The bind mount:

```yaml
- ./pcaps:/pcaps
```

keeps captures outside the disposable container.

---

# NetEm impairment

Arbitrary NetEm:

```bash
netem eth1 delay 50ms
netem eth1 delay 50ms 10ms loss 1%
netem eth1 delay 40ms 10ms loss 0.5% reorder 2%
netem eth1 duplicate 1%
netem eth1 corrupt 0.1%
```

Inspect/remove:

```bash
netem-status eth1
netem-clear eth1
```

Profiles:

```bash
netem-profile eth1 wan
netem-profile eth1 bad-wan
netem-profile eth1 satellite
netem-profile eth1 lossy
netem-profile eth1 mobile
netem-profile eth1 clean
```

These are convenient lab presets, not claims of exact carrier behavior.

Rate limiting:

```bash
rate-limit eth1 100mbit
rate-clear eth1
```

## Inline WAN emulator

```bash
wan-create eth1 eth2
```

Model:

```text
router-A --- eth1 [ labhost / br-wan ] eth2 --- router-B
```

Independent egress impairment:

```bash
wan-impair eth1 delay 20ms loss 0.1%
wan-impair eth2 delay 80ms loss 1%
```

Inspect/delete:

```bash
wan-status
wan-delete
```

NetEm is egress-oriented, so each direction can be impaired independently.

---

# iperf

Server:

```bash
iperf-server
```

TCP:

```bash
iperf-client 10.1.1.20
```

UDP:

```bash
iperf-udp 10.1.1.20 500M
```

Reverse/bidirectional:

```bash
iperf-reverse 10.1.1.20
iperf-bidir 10.1.1.20
```

Parallel streams:

```bash
iperf-parallel 10.1.1.20 16
```

Bind source:

```bash
iperf-bind 10.1.1.10 10.2.2.20
```

Quick suite:

```bash
iperf-test 10.1.1.20
```

This runs short TCP forward, TCP reverse, four-stream TCP, and 100 Mbps UDP tests.

## Multicast with iperf2

Receiver:

```bash
iperf-mcast-server 239.1.1.1
```

Sender:

```bash
iperf-mcast-send 239.1.1.1 100M 60
```

Optional TTL:

```bash
iperf-mcast-send 239.1.1.1 100M 60 64
```

`iperf3` is preferred for ordinary unicast testing. `iperf`/iperf2 remains installed for multicast UDP.

---

# Multicast / mcjoin

ASM join:

```bash
mcast-join eth1 239.1.1.1
```

SSM join:

```bash
mcast-join eth1 232.1.1.1 10.1.1.10
```

Send:

```bash
mcast-send eth1 239.1.1.2
```

Default TTL is:

```text
32
```

Override:

```bash
mcast-send eth1 239.1.1.2 64
```

Observe:

```bash
capture-igmp eth1
capture-pim eth1
```

---

# Instant services and simple traffic

HTTP:

```bash
http-server 8080 /tmp
```

HTTPS:

```bash
https-server 8443 /tmp
```

TCP listener:

```bash
tcp-listen 5000
```

UDP listener:

```bash
udp-listen 5000
```

Send TCP:

```bash
send-tcp 10.1.1.20 5000 "hello"
```

Repeated TCP:

```bash
send-tcp 10.1.1.20 5000 "test" --count 10 --interval 1
```

Bind TCP source:

```bash
send-tcp 10.1.1.20 5000 "test" --source 10.1.1.10
```

Send UDP:

```bash
send-udp 10.1.1.20 5000 hello
```

Broadcast:

```bash
send-broadcast eth1 5000 hello
```

Multicast UDP:

```bash
send-mcast eth1 239.1.1.1 5000 hello
```

Other services:

```bash
tftp-server /tmp/tftp
dnsmasq-start eth1
dnsmasq-stop
```

---

# LLDP

`lldpd` starts automatically.

```bash
lldp-show
lldp-stop
lldp-start
```

---

# SNMP / RADIUS

```bash
snmp-walk 10.1.1.1 public
snmp-get 10.1.1.1 1.3.6.1.2.1.1.1.0 public

radius-test 10.1.1.50 testuser testpassword sharedsecret
```

---

# ARP / IPv6 ND

```bash
arp-watch eth1
nd-watch eth1
gratuitous-arp eth1 10.1.1.10
arp-clear eth1
```

Useful for EVPN ARP suppression, MAC/IP mobility, HA, and first-hop redundancy testing.

---

# Multiple emulated clients

Create 20 macvlan endpoints using the default starting host offset `.10`:

```bash
clients-create eth1 20 10.100.0.0/24
```

Explicit host offset:

```bash
clients-create eth1 20 10.100.0.0/24 50
```

Literal starting IP:

```bash
clients-create eth1 20 10.100.0.0/24 10.100.0.100
```

Inspect and exercise them:

```bash
clients-list
clients-status
clients-arp
clients-ping
clients-traffic
clients-delete
```

Each client is a unique macvlan interface with a deterministic, host-aware MAC
and its own IP in the same Linux namespace. Numbering continues across repeated
creation commands. Per-client ARP controls reduce Linux weak-host/ARP-flux
behavior so the interfaces act like independent endpoints during switching and
EVPN tests.

It is not equivalent to independent VMs or separate network namespaces.

---

# Endpoint mobility

```bash
endpoint-move eth1 eth2 10.1.1.10/24 02:00:00:00:00:10
```

Moves the IP/MAC identity and sends gratuitous ARP from the destination interface.

---

# Included tools — what they do

## Core Linux networking

**iproute2 (`ip`, `ss`, `tc`)** — primary Linux interface, address, route, neighbor, VRF, socket, and traffic-control toolkit.

Useful raw commands:

```bash
ip -br addr
ip -d link show
ip route get 10.1.1.1
ip vrf show
ss -lntup
tc -s qdisc show dev eth1
```

**Linux VRF** — separate routing tables associated with VRF devices. Useful for routing-instance-like endpoint behavior and overlapping address space.

**Linux bonding / ifenslave** — bonding/LAG support including 802.3ad/LACP and active/standby modes.

**bridge / bridge-utils** — Ethernet bridge and forwarding-database inspection. Useful for inline WAN emulation and L2 experiments.

**ethtool** — link properties, driver details, counters, and offload settings.

**nftables / iptables / ebtables** — Linux L3/L4 and Ethernet filtering/NAT.

**conntrack** — inspect Linux stateful flow tracking.

## Reachability and diagnostics

**ping / arping** — ICMP reachability and ARP/GARP testing.

**traceroute / MTR** — path discovery and repeated hop-by-hop latency/loss testing.

**fping** — efficient reachability testing across many IPs.

**nmap** — port and service discovery/scanning.

**netcat / socat** — flexible TCP/UDP clients, listeners, relays, and quick application testing.

**hping3** — custom TCP/IP packet generation for firewall/path behavior testing.

## Throughput and traffic generation

**iperf3** — unicast TCP/UDP throughput, loss, jitter, parallel streams, reverse tests, and bidirectional tests.

**iperf2 (`iperf`)** — retained mainly for multicast UDP.

**netsniff-ng suite** — high-performance Linux packet toolkit:

- `trafgen` — packet generator
- `mausezahn` / `mz` — packet crafting
- `netsniff-ng` — capture/replay
- `ifpps` — interface performance statistics
- `flowtop` — flow viewer

**Scapy** — Python packet crafting/dissection. Excellent for precise Ethernet/IP/ARP/ICMP/IGMP/IPv6/VLAN packets and custom automation.

Example:

```bash
sudo scapy
```

Then:

```python
p = IP(dst="192.168.2.10")/ICMP()
p.show()
r = sr1(p)
r.show()
```

**tcpreplay** — replay a saved PCAP onto an interface.

## Packet analysis

**tcpdump** — fast command-line capture with BPF filters.

**tshark** — command-line Wireshark protocol dissector.

## Multicast

**mcjoin** — multicast sender/receiver and IGMP/MLD test utility for ASM/SSM and IPv4/IPv6 multicast validation.

**iperf2** — measurable multicast UDP streams.

**tcpdump/tshark** — inspect IGMP, MLD, PIM, and multicast data-plane traffic.

## DNS / DHCP

**dig / nslookup (`dnsutils`)** — DNS queries and troubleshooting.

**drill (`ldnsutils`)** — alternate detailed DNS query utility.

**dnsmasq** — lightweight DNS forwarder/cache and DHCP server.

## L2 and management protocols

**lldpd / lldpcli** — advertise and inspect LLDP neighbors.

**SNMP utilities / snmpd** — SNMP gets/walks and an SNMP agent.

**FreeRADIUS utilities** — includes `radclient` for RADIUS requests.

**ndisc6** — IPv6 Neighbor Discovery/router-discovery utilities.

## Interactive monitoring

**bmon** — terminal interface bandwidth monitor.

**iftop** — bandwidth usage by IP flow.

**iptraf-ng** — interactive LAN/protocol statistics.

## Application/file services

**OpenSSH** — SSH/SCP/SFTP access.

**curl / wget** — HTTP/HTTPS and general URL/application tests.

**TFTP client/server** — file-transfer and device-service testing.

**telnet / FTP clients** — legacy service testing.

**OpenSSL** — TLS handshake/certificate testing and temporary certificate generation.

## Scripting / system troubleshooting

**Python 3 + Scapy** — automation and custom network testing.

**jq** — JSON parsing.

**strace / lsof / procps / psmisc** — process/socket/system troubleshooting.

**vim / nano / less** — editing and inspection.

---

# Useful raw commands

```bash
ip -br addr
ip -d link show
ip route
ip route get 10.1.1.1
ip vrf show
ss -lntup

bridge fdb show
ethtool -S eth1

tc -s qdisc show dev eth1

tcpdump -enni eth1
tshark -i eth1

trafgen --help
mausezahn --help
tcpreplay --help

python3 -c 'from scapy.all import *; print(conf.version)'
```

---

# Ostinato and TRex

They intentionally remain separate appliances.

Use **Ostinato** for sophisticated multi-port stream construction and statistics.

Use **TRex** when the goal becomes serious packet-rate/performance generation.

`labhost` remains the everyday endpoint, test instrument, and troubleshooting appliance.

---

# Notes / limitations

- Linux bonding is supplied by the host kernel.
- `vrf-mgmt` automatically uses routing table `4094`.
- NetEm applies to egress.
- `clients-create` uses macvlan rather than nested namespaces so the container can remain limited to `NET_ADMIN` + `NET_RAW`.
- `lab-save` captures supported state and high-level intent, not arbitrary filesystem/process state.
- The startup configuration is an ordinary shell script and may be manually extended.
- `lab-reset` is intentionally conservative and preserves the management VRF/path.
- Default `lab/lab` credentials are intended only for isolated lab environments.


## DHCP clients, server, and leases

IPv4 DHCP is a first-class mode for physical and 802.1Q VLAN interfaces:

```bash
ip-set eth1 dhcp
vlan-create eth1 100 dhcp
```

Dataplane DHCP does not overwrite management DNS configuration. `lab-save`
records DHCP intent, not the current lease, address, or learned routes.

Create one or more dnsmasq pools and explicitly start the server:

```bash
dhcp-pool-create eth10.100 192.168.100.100 192.168.100.199 255.255.255.0 192.168.100.1
dhcp-pool-create eth10.200 192.168.200.100 192.168.200.199 255.255.255.0 192.168.200.1
dhcp-pool-list
dhcp-server-start
dhcp-server-status
dhcp-leases
dhcp-leases --raw
```

`dhcp-leases` displays active leases in a readable, numerically IP-sorted
table with formatted expiry times. `--raw` prints the dnsmasq lease file.
Pool definitions and server enabled state persist through `lab-save`; leases
do not.

## PC behind an LLDP-MED phone

`pc-phone-create <parent>` models a PC on the native VLAN behind an IP phone.
It creates deterministic PC and phone MACs, runs a per-port phone LLDP agent,
learns the LLDP-MED voice policy, and creates the tagged voice interface. DHCP
runs on the PC and phone sides by default:

```bash
pc-phone-create eth1
pc-phone-status eth1
pc-phone-reprovision eth1
pc-phone-delete eth1
```

Use `--no-dhcp` to test LLDP-MED without requesting leases:

```bash
pc-phone-create eth1 --no-dhcp
```

Bulk operations are also available:

```bash
pc-phones-create --all
pc-phones-create --all --no-dhcp
pc-phones-create eth1 eth3
pc-phones-status
```

`--all` selects physical dataplane interfaces `eth1+` and always excludes
management `eth0`. Creation is idempotent; use reprovision only for an
intentional teardown/rebuild.

While active, the parent uses the deterministic phone MAC, ordinary lldpd is
suppressed on that port, and the learned tagged voice identity uses the same
phone MAC. The PC macvlan has its own deterministic PC MAC. Delete/reset
restores the original parent MAC and normal lldpd behavior.

The dhcpcd shim supplies stable Ethernet Client-ID `01:<MAC>` for simulated
PCs and phones, while preserving an explicitly supplied Client-ID. This keeps
DHCP identity deterministic across recreation.

`lab-save` persists the high-level `pc-phone-create` command. Derived VLAN,
agent, and lease state are rebuilt at startup rather than frozen.

## Hardened lab-reset

```bash
lab-reset
labctl lab-reset
```

Reset removes current derived dataplane state and unsaved high-level intent,
including PC/phone objects, synthetic clients, DHCP client/server intent,
VLANs, bonds, user VRFs, NetEm, and MTU overrides. It preserves:

- physical Containerlab dataplane interfaces `eth1+`;
- `eth0`, `vrf-mgmt`, table 4094, and the management path;
- `/config/<hostname>.sh`.

It restores original physical MAC addresses and normal LLDP behavior. Because
the saved startup script remains, a later recreate can restore the last
configuration explicitly captured with `lab-save`.

