# labhost v1.4 Phase 3r4 test

Build as `labhost:1.4-dev8` and deploy a labhost with multiple dataplane
interfaces (`eth1`, `eth2`, ...).

## 1. Rich single-port status

On a port already configured for native data + LLDP-MED voice:

```bash
pc-phone-create eth1
sleep 10
pc-phone-status eth1
```

Expected columns include PC MAC/IP and phone MAC/IP, learned voice VLAN,
tagging, priority, and DSCP. With the Phase 3 test topology the row should
look broadly like:

```text
PARENT  PC_IF         PC_MAC             PC_IP            PHONE_MAC          VOICE  PHONE_IP        TAG  PRI  DSCP
eth1    pp-eth1-pc    02:...             192.168.100.x    02:...             1111   192.168.111.x  yes  0    0
```

## 2. Create is idempotent

Run the same create again without deleting first:

```bash
pc-phone-create eth1
```

Expected:

```text
PC/phone already exists on eth1; no changes made.
```

The existing DHCP addresses and LLDP neighbor should remain in place. If an
intentional teardown/rebuild is wanted, use `pc-phone-reprovision eth1`.

## 3. Bulk create

For an LLDP/L2-only first pass across every dataplane port:

```bash
pc-phones-create --all --no-dhcp
```

Or, where DHCP is available on every tested port:

```bash
pc-phones-create --all
```

`--all` must select `eth1`, `eth2`, ... and must never select `eth0`.
Existing objects are deliberately left unchanged rather than torn down.

Explicit subsets are also supported:

```bash
pc-phones-create eth1 eth3
```

## 4. Bulk status

```bash
pc-phones-status
```

Expected: one row per configured parent interface. A port still waiting for
LLDP-MED should show `WAIT` for VOICE and `-` where voice IP/policy values are
not yet available.

## 5. Management exclusion

```bash
ls -1 /config/.labhost/pc-phones/
```

There must be no `eth0.conf`.

## 6. Persistence preview

```bash
lab-save --dry-run | grep 'pc-phone-create'
```

Expected: one high-level `pc-phone-create` line per configured parent; no raw
`pp-*` address or VLAN recreation commands.

## 7. Reprovision regression

```bash
pc-phone-reprovision eth1
sleep 10
pc-phone-status eth1
```

The object should be deleted/recreated using its saved high-level intent. This
also verifies the Phase 3r4 fix that preserves the intent before delete removes
the intent file.

## r1 lab-reset regression

This r1 patch restores the expected `lab-reset` behavior for physical dataplane
interfaces. It stops dataplane DHCP clients and flushes global IPv4/IPv6
addresses plus routes from `eth1`, `eth2`, ... while preserving `eth0` and
`vrf-mgmt`. Saved `/config/<hostname>.sh` is not modified.

```bash
ip-set eth1 192.168.100.10/24
ip -4 -br addr show eth1
lab-reset
ip -4 -br addr
ip route
mgmt-vrf-status
cat /config/$(hostname).sh
```

Expected: no global dataplane address remains on eth1+, management remains
reachable, and the saved startup script is unchanged.
