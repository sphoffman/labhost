# Phase 3r4-r2 lab-reset regression test

This patch makes `lab-reset` clear both runtime dataplane state and the unsaved high-level intent used to reconstruct that runtime state. `/config/<hostname>.sh` is deliberately preserved.

## Test

Create representative state, then run:

```bash
lab-reset
```

Verify:

```bash
pc-phones-status
clients-status
ip -4 -br addr
ip -d -br link
ps -ef | grep -E '[d]hcpcd|[d]nsmasq' || true
find /config/.labhost -maxdepth 2 -type f -print | sort
cat /config/$(hostname -s).sh
mgmt-vrf-status
```

Expected:
- no `pp-*` phone/PC interfaces or PC/phone intent
- no `cl###` clients or client intent
- no DHCP clients, DHCP server, DHCP-interface intent, or DHCP-pool intent
- helper-created VLANs/bonds/VRFs removed
- physical dataplane `eth1+` has no global IPv4/IPv6 addresses or dataplane routes
- physical dataplane MTU restored to the configured labhost default (9000 unless overridden)
- `eth0` / `vrf-mgmt` management remains reachable
- `/config/<hostname>.sh` is unchanged, so a later container restart can restore the last `lab-save`
