# labhost 1.4-dev1 checkpoint

Build without replacing 1.3/latest:

```bash
cd /storage/images/labhost-1.4-phase1a
docker build -t labhost:1.4-dev1 .
```

Use one test labhost node with `image: labhost:1.4-dev1`.

## MTU

```bash
ip -br link
mtu-all 8000
ip -o link show | grep -E 'mtu (8000|9000)'
mgmt-vrf-status
lab-save --dry-run | grep -E 'mtu-all|mtu-set'
mtu-all 9000
```

Expected: eth0/vrf-mgmt are preserved; lab-facing interfaces change. `lab-save --dry-run` records `mtu-all 8000` while 8000 is active.

## Multiple client groups

```bash
clients-delete
clients-create eth1 50 192.168.100.0/24 50
clients-create eth1 10 192.168.100.0/24 150
clients-status
```

Expected: first group is cl001-cl050, second is cl051-cl060. `clients-status` shows arp_ignore=1 and arp_announce=2.

## Persistence output

```bash
lab-save --dry-run | grep -E 'clients-create|ip-set cl'
```

Expected: two `clients-create` lines and NO `ip-set cl###` lines.

## Deterministic MAC check

Record:

```bash
ip link show cl001 | grep link/ether
```

Then save/redeploy the node and verify cl001 gets the same MAC after the startup script recreates the client groups.
