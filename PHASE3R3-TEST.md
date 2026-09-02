# Phase 3r3 focused test — parent interface becomes the phone

This test validates that the physical parent uses PHONE_MAC while the PC/phone abstraction is active and that `pc-phone-delete` restores Containerlab's original parent MAC.

## 1. Record the original parent MAC

```bash
ORIG=$(cat /sys/class/net/eth1/address)
echo "$ORIG"
```

## 2. Create the endpoint without DHCP

```bash
pc-phone-delete eth1 2>/dev/null || true
pc-phone-create eth1 --no-dhcp
pc-phone-status eth1
```

Verify the parent and children:

```bash
ip -br link show eth1
ip -br link show | grep 'pp-eth1'
```

Expected: `eth1` and `pp-eth1-v<voice-vlan>` use PHONE_MAC; `pp-eth1-pc` uses PC_MAC. The original `aa:c1:...` parent MAC must not remain on eth1.

## 3. Confirm kernel untagged traffic no longer leaks the original MAC

```bash
sudo tcpdump -eni eth1 "ether src $ORIG" -c 1
```

Allow roughly 30 seconds. No frame should be captured. Stop with Ctrl-C if needed.

Optionally capture phone-MAC traffic instead:

```bash
PHONE=$(cat /sys/class/net/eth1/address)
sudo tcpdump -eni eth1 "ether src $PHONE" -c 3
```

## 4. Check Junos

After clearing any stale persistent entry for the old `aa:c1:...` MAC once, verify:

```text
show ethernet-switching table interface ge-0/0/2
show lldp neighbors interface ge-0/0/2
```

Target switching state:

```text
native VLAN:
  PC_MAC       SP
  PHONE_MAC    SP

voice VLAN:
  PHONE_MAC    SP
```

There should be no fourth Containerlab parent MAC.

## 5. Verify delete restores the original parent MAC

```bash
pc-phone-delete eth1
cat /sys/class/net/eth1/address
echo "$ORIG"
```

The two values must match.

## 6. Persistence sanity check

Recreate and verify high-level intent only:

```bash
pc-phone-create eth1 --no-dhcp
lab-save --dry-run | grep -E 'pc-phone|pp-eth1'
```

Expected:

```text
pc-phone-create eth1 --no-dhcp
```
