# LabHost v1.5 Release Notes

LabHost v1.5 extends the v1.4 network-lab appliance with first-class endpoint targeting, lightweight infrastructure services, safer IPv4 semantics, and hardened persistence.

## Highlights

### Unified managed endpoints

Client-oriented helpers now discover and target:

- `clN` synthetic clients created by `clients-create`
- `pp-*-pc` PC endpoints created by the PC/phone abstraction
- tagged phone voice endpoints learned from authoritative PC/phone state

Selectors include:

```text
--all
--pcs
--phones
--clients
--interface <iface>
```

Endpoint-aware helpers include `clients-list`, `clients-status`, `clients-arp`, `clients-ping`, `clients-traffic`, `clients-iperf`, `path-test`, `send-tcp`, `send-udp`, and the unicast `iperf-*` helpers.

Synthetic client, PC, and tagged-phone child interfaces default to MTU 1500 while physical LabHost dataplane interfaces remain jumbo-capable. Synthetic PC/phone children also use `arp_ignore=1` and `arp_announce=2`, matching the existing independent-host behavior of ordinary synthetic clients.

### Endpoint-aware iperf and help

The unicast iperf helpers accept `--interface <iface>` and bind traffic to the selected endpoint. `iperf-* --help` and `lab-help iperf-*` now show the endpoint-aware syntax instead of interpreting `--help` as a port or positional argument.

### Static IPv4 replacement semantics

Static `ip-set` is replacement-oriented. For example:

```bash
ip-set eth1 10.10.10.20/24
```

leaves the requested static address as the interface's global IPv4 address instead of silently retaining unrelated prior global IPv4 addresses. DHCP behavior is unchanged.

### Lightweight network services

v1.5 adds first-class lab services for:

- NTP
- syslog
- SNMP agent
- SNMP trap receiver
- RADIUS clients/users/server

These services are stopped by default and are intended for isolated network labs rather than as general-purpose server roles.

Examples:

```bash
ntp-server-start --bind eth1
ntp-query 192.0.2.10

syslog-server-start --bind eth1 --both
syslog-send 192.0.2.10 "labhost test"

snmp-server-start --bind eth1 --community public
snmp-trap-listen --bind eth1

radius-client-add switch1 192.0.2.2 testing123
radius-user-add labuser labpass
radius-server-start --bind eth1
```

NTP uses chronyd with `-x`, so it does not adjust the container/host kernel clock. RADIUS bind selection can use an interface or IP address.

## Persistence hardening

`lab-save` now generates the complete startup configuration as the invoking user and uses controlled self-elevation only for writes into `/config`.

This allows an SSH session running as the normal unprivileged `lab` account to save through a root-owned host bind mount without requiring a matching `lab` user or UID on the Containerlab host.

Saved files are written as:

```text
root:root 0755
```

for both `<hostname>.sh` and `<hostname>.sh.bak`.

Synthetic-client MTU commands are also ordered after `clients-create`, preventing startup replay from referencing a client before that interface exists.

Service intent is reconstructed during `lab-save`. RADIUS client/user configuration is emitted before `radius-server-start` so the authentication database is complete before the daemon starts.

## Validation

The v1.5 release candidate passed automated checks covering:

- shell and Python syntax
- helper availability and endpoint-aware help
- endpoint discovery
- static `ip-set` replacement semantics
- synthetic-client MTU and ARP defaults
- synthetic-client save/delete/replay persistence
- root-owned `/config` persistence invoked as `lab`
- PC endpoint MTU and ARP defaults
- tagged-phone endpoint MTU and ARP defaults
- syslog runtime and persistence
- SNMP runtime and persistence
- NTP response and persistence
- RADIUS Access-Accept, bind behavior, deterministic persistence ordering

Manual Containerlab testing also verified synthetic-client persistence across `containerlab restart`, including IPv4 address, MTU 1500, and ARP isolation state.

## Compatibility and scope

- Physical dataplane interfaces `eth1+` remain jumbo-capable, default MTU 9000 unless overridden by `LABHOST_DATA_MTU`.
- The management interface remains `eth0` in `vrf-mgmt`, routing table 4094.
- The image continues to require only `NET_ADMIN`, `NET_RAW`, and `net.ipv4.tcp_l3mdev_accept=1` for the supported Containerlab deployment model; production LabHost operation does not require `--privileged`.
- The `lab` account remains the intended interactive SSH user.
- NCE-specific TCP checksum/performance investigation remains separate from this release because the standalone LabHost-to-LabHost control path validated cleanly.

## Deferred work

Not included in v1.5:

- DNS record-management helpers
- DHCPv6 and router-advertisement helpers
- wired 802.1X supplicant validation
- concurrent multi-endpoint iperf mode
