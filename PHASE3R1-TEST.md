# labhost v1.4-dev5 — Phase 3r1 focused test

Goal: prove that a PC/phone port exposes only the simulated phone via LLDP and that Junos can learn the phone MAC in both the native and LLDP-MED voice VLANs.

## 1. Create the endpoint without DHCP

```bash
pc-phone-delete eth1 2>/dev/null || true
pc-phone-create eth1 --no-dhcp
pc-phone-status eth1
```

Expected: PC interface exists, phone learns the LLDP-MED voice policy, and the tagged voice interface is created.

## 2. Verify LLDP on the wire

```bash
sudo tcpdump -eni eth1 -vvv 'ether proto 0x88cc' -c 3
```

Expected: outbound labhost advertisement is `host1-phone-eth1` / deterministic PHONE_MAC. There should be no ordinary `host1` LLDP advertisement sourced by the original eth1 MAC.

On Junos:

```text
show lldp neighbors interface ge-0/0/2
```

Expected: the neighbor is `host1-phone-eth1`.

## 3. Verify MAC learning

```bash
pc-phone-status eth1
ip -br link show eth1
ip -br link show | grep 'pp-eth1'
```

On Junos, after clearing stale persistent entries if needed and recreating/reprovisioning the endpoint:

```text
show ethernet-switching table interface ge-0/0/2
```

Target state with persistent learning enabled:

```text
native VLAN: PC_MAC     SP
native VLAN: PHONE_MAC  SP
voice VLAN:  PHONE_MAC  SP
```

The original container eth1 MAC should not be newly learned from ordinary host L3/LLDP traffic after conversion to a PC/phone port. A stale persistent entry from an earlier test may need to be cleared once before validating this.

## 4. Persistence

```bash
lab-save --dry-run | grep -E 'pc-phone|pp-eth1'
```

Expected:

```text
pc-phone-create eth1 --no-dhcp
```
