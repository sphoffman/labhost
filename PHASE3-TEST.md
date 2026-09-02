# labhost v1.4 Phase 3 test — PC behind LLDP-MED phone

This checkpoint validates deterministic endpoint identities, native PC creation,
phone LLDP emission, LLDP-MED Voice Network Policy learning, tagged voice
materialization, and high-level persistence.

## 1. Build and deploy

Build as `labhost:1.4-dev4` and attach `eth1` to a switch port configured as a
normal data/native VLAN plus LLDP-MED voice VLAN. For the first test, use
`--no-dhcp` so DHCP cannot hide an LLDP issue.

    pc-phone-create eth1 --no-dhcp
    pc-phone-status eth1
    ip -br link show | grep 'pp-eth1'

Expected initially: `pp-eth1-pc` exists and status shows `WAITING` until the
switch advertises a Voice Network Policy.

## 2. Verify phone LLDP reaches the switch

On the attached Junos switch, use the normal LLDP neighbor detail command for
the connected port. The neighbor system name should be:

    <labhost-hostname>-phone-eth1

The advertised chassis ID is the deterministic phone MAC shown by
`pc-phone-status`.

## 3. Verify LLDP-MED policy learning

Once the switch advertises a tagged Voice Network Policy, run:

    pc-phone-status eth1
    ip -d link show type vlan | grep 'pp-eth1-v'

Expected: status changes from WAITING to the learned voice VLAN and displays
tagged state, 802.1p priority, and DSCP. A `pp-eth1-v<VLAN>` interface exists
with that VLAN ID.

Confirm the phone MAC is used on the tagged voice interface:

    ip -br link show | grep 'pp-eth1-v'

## 4. Verify deterministic MACs

Record the PC and phone MACs, then:

    pc-phone-delete eth1
    pc-phone-create eth1 --no-dhcp
    pc-phone-status eth1

The PC and phone MACs must be identical to the first run.

## 5. Verify persistence

    lab-save --dry-run | grep -E 'pc-phone|pp-eth1'

Expected high-level output only:

    pc-phone-create eth1 --no-dhcp

There should be no standalone `vlan-create`, `ip-set`, or `mtu-set` commands for
`pp-eth1-*` runtime interfaces.

## 6. DHCP integration

After LLDP-only behavior passes, delete/recreate with DHCP enabled:

    pc-phone-delete eth1
    pc-phone-create eth1

With working DHCP on the native/data and learned voice VLANs, verify:

    ip -br addr show | grep 'pp-eth1'

The PC interface should receive data-VLAN DHCP and the voice interface should
receive voice-VLAN DHCP.
