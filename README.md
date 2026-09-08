# LabHost v1.5 — Containerlab Network Swiss Army Knife

LabHost is a reusable Linux endpoint and network-test appliance for Containerlab. It is intentionally tool-heavy: the goal is to drop it into a topology and already have the troubleshooting, traffic-generation, multicast, packet-capture, service-emulation, VLAN/LAG, VRF, persistence, DHCP, endpoint-emulation, and impairment tools you need.

Version 1.5 keeps the v1.4 networking model and adds first-class managed endpoint targeting, lightweight infrastructure services, safer IPv4 replacement semantics, and hardened persistence through root-owned bind mounts.

See [`RELEASE-NOTES-1.5.md`](RELEASE-NOTES-1.5.md) for the complete v1.5 release summary.

## What changed in v1.5

- Unified managed-endpoint discovery across ordinary synthetic clients, PC endpoints, and tagged phone voice endpoints.
- Endpoint selectors such as `--all`, `--pcs`, `--phones`, `--clients`, and `--interface <iface>`.
- Endpoint-aware `iperf-*`, `path-test`, `send-tcp`, `send-udp`, and client helpers.
- Correct endpoint-aware help for `iperf-* --help` and `lab-help iperf-*`.
- Synthetic client, PC, and tagged-phone child interfaces default to MTU 1500 while physical LabHost dataplane interfaces remain jumbo-capable.
- PC and tagged-phone child interfaces use `arp_ignore=1` and `arp_announce=2`, matching ordinary synthetic-client isolation.
- Static `ip-set` now replaces unrelated prior global IPv4 addresses instead of silently accumulating them.
- First-class lightweight NTP, syslog, SNMP agent/trap, and RADIUS services.
- `lab-save` can write through a root-owned `/config` bind mount when invoked normally by the unprivileged `lab` SSH user.
- Saved startup and backup files are written as `root:root` mode `0755`, without requiring a matching `lab` user or UID on the Containerlab host.
- Synthetic-client MTU persistence is replay-safe: `clients-create` is emitted before saved `mtu-set clN ...` commands.

The automatic management VRF remains `vrf-mgmt`, routing table 4094. Management interface `eth0` is never treated as a dataplane interface.

---

# Install

## Pull the published image

For reproducible labs, prefer the versioned image:

```bash
docker pull ghcr.io/sphoffman/labhost:1.5
```

The current stable image is also available as:

```bash
docker pull ghcr.io/sphoffman/labhost:latest
```

## Build locally

```bash
git clone https://github.com/sphoffman/labhost.git
cd labhost
docker build -t labhost:1.5 .
```

Validate a local build with:

```bash
./smoke-test.sh labhost:1.5
```

## Host bonding support

Linux bonding is supplied by the Containerlab host kernel. On an Ubuntu lab server, ensure the bonding module is available:

```bash
sudo modprobe bonding
lsmod | grep bonding
```

If desired, load it at boot using `/etc/modules-load.d/bonding.conf` containing:

```text
bonding
```

---

# Required Containerlab settings

LabHost uses Linux networking features that a normal unprivileged container cannot modify by default.

Use:

```yaml
cap-add:
  - NET_ADMIN
  - NET_RAW

sysctls:
  net.ipv4.tcp_l3mdev_accept: "1"
```

Why:

- `NET_ADMIN` — interfaces, addresses, routes, VRFs, VLANs, QinQ, LAG/bonding, MTU/MAC changes, bridges, and `tc`/NetEm.
- `NET_RAW` — packet capture/generation, ping, arping, Scapy, and similar tools.
- `net.ipv4.tcp_l3mdev_accept=1` — lets wildcard TCP listeners such as SSH accept sessions arriving through the management VRF.

Supported production-style LabHost operation does **not** require `--privileged`. Some CI fixtures use privileged throwaway containers only to construct synthetic test interfaces inside GitHub Actions.

## Recommended node template

```yaml
host1:
  kind: linux
  image: ghcr.io/sphoffman/labhost:1.5
  env:
    LAB_PASSWORD: lab
  binds:
    - ./configs:/config
    - ./pcaps:/pcaps
    - ./scripts:/scripts
  cap-add:
    - NET_ADMIN
    - NET_RAW
  sysctls:
    net.ipv4.tcp_l3mdev_accept: "1"
```

The repository also includes `labhost-demo.clab.yml` as a starting point.

---

# Login and environment

Default lab credentials:

```text
Username: lab
Password: lab
```

Override the password with:

```yaml
env:
  LAB_PASSWORD: something-else
```

The `lab` account has passwordless `sudo` because LabHost is intended for isolated network-lab environments.

LabHost explicitly includes the networking administration paths:

```text
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

The full README is installed inside the container at:

```text
/usr/local/share/labhost/README.md
```

Useful help commands:

```bash
lab-help
lab-help iperf-server
iperf-server --help
lab-readme
```

---

# Management VRF design

At startup, `eth0` is dedicated to management and moved into:

```text
vrf-mgmt
table 4094
```

The management gateway is learned before the move and restored in routing table 4094. The normal Linux `main` routing table remains independent for lab-facing interfaces such as:

```text
eth1
eth2
bond0
eth1.100
...
```

This allows the management path and lab dataplane to use independent routing, including overlapping address space.

Inspect management state with:

```bash
mgmt-vrf-status
vrf-status
```

Routing table 4094 is reserved for `vrf-mgmt`.

Physical dataplane interfaces `eth1+` default to MTU 9000. Override that image-wide default with:

```text
LABHOST_DATA_MTU
```

Synthetic endpoint children default to MTU 1500.

---

# Persistence

LabHost uses one explicit persistence boundary:

```text
interactive helper
    -> current Linux state + /run/labhost/intents
    -> lab-save
    -> /config/<hostname>.sh
    -> startup replay after recreate
```

Interactive changes are not persistent until you run:

```bash
lab-save
```

Preview first with:

```bash
lab-save --dry-run
```

Inspect the saved configuration with:

```bash
lab-config
lab-config path
lab-config edit
```

For host `host1`, the saved file is:

```text
/config/host1.sh
```

An existing file is backed up as:

```text
/config/host1.sh.bak
```

## Root-owned bind mounts

The normal workflow is:

```text
SSH into LabHost as lab
    -> run lab-save
    -> controlled self-elevation only for /config writes
```

This works even when the Containerlab host repository and `configs/` directory are owned by `root`. A matching `lab` account or UID on the Containerlab host is not required.

Saved files are written as:

```text
root:root 0755
```

for both the startup file and backup.

## What `lab-save` preserves

Where reconstructable, `lab-save` preserves:

- IPv4/IPv6 addresses
- main-table routes
- VLANs and QinQ
- LAG/bonding
- user VRFs and VRF routes
- non-default MTUs
- NetEm state
- synthetic-client intent
- DHCP client intent
- DHCP pools and enabled server state
- PC/phone intent
- v1.5 lightweight service intent

For high-level objects it saves intent rather than incidental runtime state. DHCP leases, learned routes, and derived endpoint state are rebuilt rather than frozen.

Synthetic-client MTU commands are intentionally emitted after `clients-create` so startup replay never references a `clN` interface before it exists.

For lifecycle validation, use Containerlab rather than plain Docker restart:

```bash
containerlab restart -t <topology>.clab.yml --node host1
```

or for a stronger recreation test:

```bash
containerlab redeploy -t <topology>.clab.yml
```

A plain `docker restart` is not a valid dataplane-persistence test for generic Containerlab Linux nodes because Docker does not recreate Containerlab's non-`eth0` veth links.

---

# Managed endpoints

v1.5 treats three endpoint classes as first-class managed endpoints:

```text
clN                  ordinary synthetic client
pp-*-pc              PC behind the PC/phone abstraction
pp-*-v<VLAN>         tagged phone voice endpoint
```

Common selectors:

```text
--all
--pcs
--phones
--clients
--interface <iface>
```

Examples:

```bash
clients-list
clients-list --pcs
clients-list --phones
clients-list --clients
clients-status --all
clients-ping 192.0.2.1 --pcs
clients-arp --phones
```

## Ordinary synthetic clients

Create 20 deterministic macvlan endpoints starting at host offset `.10`:

```bash
clients-create eth1 20 10.100.0.0/24
```

Specify another starting host offset:

```bash
clients-create eth1 20 10.100.0.0/24 50
```

Or a literal starting IP:

```bash
clients-create eth1 20 10.100.0.0/24 10.100.0.100
```

Inspect and exercise them:

```bash
clients-list --clients
clients-status --clients
clients-arp --clients
clients-ping 10.100.0.1 --clients
clients-iperf 10.100.0.20 --clients
clients-delete
```

Client numbering continues across repeated creation commands. MAC addresses are deterministic and host-aware. Synthetic clients use:

```text
MTU 1500
arp_ignore=1
arp_announce=2
```

They remain macvlan interfaces in the same namespace; they are not independent VMs or network namespaces.

---

# PC behind LLDP-MED phone

`pc-phone-create <parent>` models a PC on the native VLAN behind an IP phone.

```bash
pc-phone-create eth1
pc-phone-status eth1
pc-phone-reprovision eth1
pc-phone-delete eth1
```

Use `--no-dhcp` when testing LLDP-MED behavior without requesting addresses:

```bash
pc-phone-create eth1 --no-dhcp
```

Bulk helpers:

```bash
pc-phones-create --all
pc-phones-create --all --no-dhcp
pc-phones-create eth1 eth3
pc-phones-status
```

The model uses deterministic PC and phone MAC addresses. The physical parent represents the phone's switch-facing identity. The PC is a macvlan child. When a tagged LLDP-MED voice VLAN is learned, the phone's tagged voice child uses the phone identity.

PC and tagged-phone child interfaces default to:

```text
MTU 1500
arp_ignore=1
arp_announce=2
```

`lab-save` persists the high-level `pc-phone-create` intent; derived LLDP/DHCP/VLAN state is rebuilt at startup.

---

# IP, routes, MAC, MTU, and failures

```bash
ip-set eth1 10.1.1.10/24
ip-set eth1 10.1.1.10/24 10.1.1.1
ip-set eth1 dhcp

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

Static `ip-set` uses replacement semantics: unrelated prior global IPv4 addresses on that interface are removed after the requested static address is successfully applied. DHCP behavior is unchanged.

---

# VLANs and QinQ

```bash
vlan-create eth1 100 10.100.0.10/24
vlan-create eth1 200 dhcp
vlan-create bond0 300 10.30.0.10/24

vlan-list
vlan-delete eth1.100

qinq-create eth1 100 200 10.20.0.10/24
qinq-delete eth1.100.200
```

---

# LAG / bonding

Create an active/fast 802.3ad LAG:

```bash
lag-create eth1 eth2
```

Named bond:

```bash
lag-create eth1 eth2 bond10
```

Alternate mode:

```bash
lag-create eth1 eth2 bond0 active-backup
```

Inspect, fail, restore, and delete:

```bash
lag-status
lag-member-down eth2
lag-member-up eth2
lag-delete bond0
capture-lacp eth1
```

---

# User VRFs

```bash
vrf-create blue 101
vlan-create eth1 100
vrf-add blue eth1.100
ip-set eth1.100 10.1.0.2/24
vrf-route-add blue default 10.1.0.1

vrf-status blue
vrf-exec blue ping 8.8.8.8
vrf-remove eth1.100
vrf-delete blue
```

The automatic management VRF is protected from normal delete/remove helpers.

---

# DHCP server and leases

IPv4 DHCP is first-class for physical and VLAN interfaces:

```bash
ip-set eth1 dhcp
vlan-create eth1 100 dhcp
```

Create one or more persistent dnsmasq pools:

```bash
dhcp-pool-create eth10.100 192.168.100.100 192.168.100.199 255.255.255.0 192.168.100.1
dhcp-pool-create eth10.200 192.168.200.100 192.168.200.199 255.255.255.0 192.168.200.1

dhcp-pool-list
dhcp-server-start
dhcp-server-status
dhcp-leases
dhcp-leases --raw
```

`lab-save` records DHCP intent and pool/server configuration, not active leases.

---

# Lightweight services

The v1.5 service helpers are lab services, not a general-purpose server distribution. They are stopped by default.

## NTP

```bash
ntp-server-start
ntp-server-start --bind eth1
ntp-server-status
ntp-query 192.0.2.10
ntp-server-stop
```

NTP uses chronyd with `-x`, so the service does not adjust the container/host kernel clock.

## Syslog

```bash
syslog-server-start --udp
syslog-server-start --bind eth1 --both
syslog-server-status
syslog-tail
syslog-clear
syslog-send 192.0.2.10 "labhost test"
syslog-server-stop
```

## SNMP agent

```bash
snmp-server-start --bind eth1 --community public
snmp-server-status
snmp-server-stop
```

SNMP client helpers remain available:

```bash
snmp-walk 10.1.1.1 public
snmp-get 10.1.1.1 1.3.6.1.2.1.1.1.0 public
```

## SNMP traps

```bash
snmp-trap-listen --bind eth1
snmp-trap-status
snmp-trap-tail
snmp-trap-stop
```

## RADIUS

```bash
radius-client-add switch1 192.0.2.2 testing123
radius-user-add labuser labpass
radius-server-start --bind eth1
radius-server-status
radius-log
radius-server-stop
```

Delete a test user with:

```bash
radius-user-delete labuser
```

`radius-server-start --bind <interface|ip>` constrains the listener to the selected endpoint/address.

RADIUS client/user intent is persisted before `radius-server-start`, so startup replay reconstructs the authentication database before the daemon starts.

Service credentials and communities saved by `lab-save` are stored in the ordinary startup shell script. Use lab/test credentials only.

Inspect or reset service state with:

```bash
services-status
services-reset
```

---

# iperf and endpoint-aware traffic

Server:

```bash
iperf-server
iperf-server --interface eth1
```

TCP:

```bash
iperf-client 10.1.1.20
iperf-client 10.1.1.20 --interface pp-eth1-pc
```

UDP:

```bash
iperf-udp 10.1.1.20 500M
iperf-udp 10.1.1.20 100M --interface pp-eth2-pc
```

Reverse, bidirectional, parallel, and source bind:

```bash
iperf-reverse 10.1.1.20 --interface pp-eth3-pc
iperf-bidir 10.1.1.20 --interface pp-eth4-pc
iperf-parallel 10.1.1.20 4 --interface pp-eth5-pc
iperf-bind 10.1.1.10 10.2.2.20 --interface eth1
iperf-test 10.1.1.20 --interface eth1
```

Run selected managed endpoints sequentially with:

```bash
clients-iperf 10.1.1.20 --pcs
```

A concurrent multi-endpoint aggregate mode is intentionally not part of v1.5.

---

# Path and port testing

```bash
path-test 10.20.30.40
path-test 10.20.30.40 --interface pp-eth1-pc
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
capture-ring eth1 long-test.pcap
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

---

# NetEm and WAN impairment

Examples:

```bash
netem eth1 delay 50ms
netem eth1 delay 50ms 10ms loss 1%
netem eth1 duplicate 1%
netem eth1 corrupt 0.1%

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

Rate limiting:

```bash
rate-limit eth1 100mbit
rate-clear eth1
```

Inline WAN emulator:

```bash
wan-create eth1 eth2
wan-impair eth1 delay 20ms loss 0.1%
wan-impair eth2 delay 80ms loss 1%
wan-status
wan-delete
```

NetEm is egress-oriented, so directions can be impaired independently.

---

# Multicast

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
mcast-send eth1 239.1.1.2 64
```

iperf2 multicast:

```bash
iperf-mcast-server 239.1.1.1
iperf-mcast-send 239.1.1.1 100M 60
```

---

# Instant application services and traffic

```bash
http-server 8080 /tmp
https-server 8443 /tmp
tcp-listen 5000
udp-listen 5000
tftp-server /tmp/tftp
```

Traffic:

```bash
send-tcp 10.1.1.20 5000 "hello"
send-tcp 10.1.1.20 5000 "test" --count 10 --interval 1
send-tcp 10.1.1.20 5000 "test" --source 10.1.1.10
send-tcp 10.1.1.20 5000 "test" --interface pp-eth1-pc

send-udp 10.1.1.20 5000 hello
send-udp 10.1.1.20 5000 hello --interface pp-eth1-pc
send-broadcast eth1 5000 hello
send-mcast eth1 239.1.1.1 5000 hello
```

---

# LLDP, ARP, and IPv6 ND

`lldpd` starts automatically.

```bash
lldp-show
lldp-stop
lldp-start

arp-watch eth1
nd-watch eth1
gratuitous-arp eth1 10.1.1.10
arp-clear eth1
```

---

# Endpoint mobility

```bash
endpoint-move eth1 eth2 10.1.1.10/24 02:00:00:00:00:10
```

This moves the IP/MAC identity and sends gratuitous ARP from the destination interface.

---

# Reset

```bash
lab-reset
labctl lab-reset
```

Reset conservatively removes derived dataplane state and unsaved runtime intent while preserving:

- physical Containerlab dataplane interfaces `eth1+`
- `eth0`, `vrf-mgmt`, and table 4094
- the management path
- `/config/<hostname>.sh`

It also restores original physical MAC addresses and normal LLDP behavior for PC/phone ports.

---

# Included tools

LabHost includes a broad set of network-lab utilities, including:

- `ip`, `ss`, `tc`, Linux VRF, bonding, bridge tools
- `ethtool`, nftables, iptables, ebtables, conntrack
- `ping`, arping, traceroute, MTR, fping, nmap
- netcat, socat, hping3
- iperf3 and iperf2
- netsniff-ng tools including trafgen and mausezahn
- Scapy and Python 3
- tcpdump, tshark, tcpreplay
- mcjoin
- dig, nslookup, drill, dnsmasq
- lldpd/lldpcli
- SNMP tools, snmpd, snmptrapd
- FreeRADIUS and RADIUS utilities
- chrony
- ndisc6
- bmon, iftop, iptraf-ng
- OpenSSH, curl, wget, TFTP, telnet/FTP clients, OpenSSL
- jq, strace, lsof, procps, psmisc, vim, nano, less

Ostinato and TRex intentionally remain separate appliances for workloads better suited to dedicated traffic generators.

---

# Notes and limitations

- Linux bonding is supplied by the host kernel.
- `vrf-mgmt` uses routing table 4094.
- NetEm applies to egress.
- Physical dataplane interfaces default to MTU 9000; synthetic child endpoints default to MTU 1500.
- `clients-create` uses macvlan rather than nested namespaces so normal operation remains within the `NET_ADMIN` + `NET_RAW` model.
- `lab-save` captures supported state and high-level intent, not arbitrary filesystem/process state.
- The startup configuration is an ordinary shell script and can be manually extended.
- Default `lab/lab` credentials are for isolated lab environments only.
- v1.5 does not include DNS record-management helpers, DHCPv6/RA helpers, wired 802.1X supplicant validation, or concurrent multi-endpoint iperf mode.
