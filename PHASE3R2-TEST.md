# labhost v1.4-dev6 — Phase 3r2 LLDP correctness test

This checkpoint fixes the simulated phone LLDP frame itself. The previous frame used a malformed System Capabilities TLV (2 bytes instead of 4), advertised Station Only instead of Telephone, and advertised zero LLDP-MED capabilities. Junos could see the Ethernet frame but did not install it as an LLDP neighbor.

## 1. Recreate the phone endpoint

```bash
pc-phone-delete eth1 2>/dev/null || true
pc-phone-create eth1 --no-dhcp
```

Wait 5-10 seconds.

## 2. Validate the transmitted phone LLDP frame

```bash
sudo tcpdump -eni eth1 -vvv 'ether proto 0x88cc' -c 3
```

For the frame sourced by the phone MAC, verify that tcpdump decodes **System Capabilities** as Telephone and that the frame continues through the LLDP-MED capabilities TLV without truncation/malformed output.

## 3. Validate Junos neighbor learning

On the attached Junos switch:

```text
show lldp neighbors interface ge-0/0/2
```

Expected phone identity:

```text
System Name:      host1-phone-eth1
Chassis ID:       <deterministic phone MAC>
Port Description: host1-phone-eth1 phone uplink
```

The normal `host1` LLDP identity should not be transmitted on the pc-phone parent interface.

## 4. Validate LLDP-MED provisioning

```bash
pc-phone-status eth1
ip -br link show | grep 'pp-eth1'
```

Expected: Voice Network Policy is learned and the tagged voice interface uses the same deterministic phone MAC.

## 5. Validate native/voice MAC learning

If persistent MAC learning is enabled on Junos, clear the old persistent entry for the container parent MAC before judging this test; otherwise it may remain from the previous build even though the parent no longer originates endpoint traffic. Then check:

```text
show ethernet-switching table interface ge-0/0/2
```

Target:

```text
native VLAN: PC MAC + PHONE MAC
voice VLAN:  PHONE MAC
```
