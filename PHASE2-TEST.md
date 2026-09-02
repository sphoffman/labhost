# labhost v1.4-dev3 — Phase 2 DHCP Server Test

This test is self-contained inside one labhost. It validates persistent DHCP pools,
multiple pools, dnsmasq service control, leases, and lab-save intent.

## 1. Build/deploy

Build as `labhost:1.4-dev3` and deploy one test node.

## 2. Create two isolated server/client veth paths

```bash
sudo ip link add srv100 type veth peer name cli100
sudo ip link add srv200 type veth peer name cli200
sudo ip link set srv100 up
sudo ip link set cli100 up
sudo ip link set srv200 up
sudo ip link set cli200 up
sudo ip addr add 192.0.2.1/24 dev srv100
sudo ip addr add 198.51.100.1/24 dev srv200
```

## 3. Create two persistent pools

```bash
dhcp-pool-create srv100 192.0.2.100 192.0.2.150 255.255.255.0 192.0.2.1 192.0.2.1 1h
dhcp-pool-create srv200 198.51.100.100 198.51.100.150 255.255.255.0 198.51.100.1 198.51.100.1 1h
dhcp-pool-list
```

Expected: both pools are listed.

## 4. Start server

```bash
dhcp-server-start
dhcp-server-status
```

Expected: `DHCP server: RUNNING` and two configured pools.

## 5. Acquire leases

```bash
ip-set cli100 dhcp
ip-set cli200 dhcp
ip -4 -br addr show cli100
ip -4 -br addr show cli200
dhcp-server-status
```

Expected:
- cli100 receives 192.0.2.100-150/24
- cli200 receives 198.51.100.100-150/24
- status shows both leases

## 6. Verify persistence intent

```bash
lab-save --dry-run | grep -E 'dhcp-pool|dhcp-server|ip-set cli'
```

Expected to include equivalent high-level intent:

```text
dhcp-pool-create srv100 192.0.2.100 192.0.2.150 255.255.255.0 192.0.2.1 192.0.2.1 1h
dhcp-pool-create srv200 198.51.100.100 198.51.100.150 255.255.255.0 198.51.100.1 198.51.100.1 1h
dhcp-server-start
ip-set cli100 dhcp
ip-set cli200 dhcp
```

It must NOT save the leased client addresses as static `ip-set` commands.

## 7. Stop/restart

```bash
dhcp-server-stop
dhcp-server-status
dhcp-server-start
dhcp-server-status
```

Expected: STOPPED, then RUNNING.

## 8. Cleanup

```bash
dhcp-server-stop
dhcp-pool-delete srv100
dhcp-pool-delete srv200
sudo ip link del srv100
sudo ip link del srv200
```

Note: these veths are temporary test interfaces. Do not run a non-dry-run `lab-save`
while you want to keep this test setup out of the real startup script.

## Process-management regression check

After `dhcp-server-start` reports RUNNING, run it a second time:

```bash
dhcp-server-start
```

It should report that the DHCP server is already running and must not create a second dnsmasq process.

Verify:

```bash
ps -ef | grep '[d]nsmasq.*labhost/dhcp-server/dnsmasq.conf'
```

There should be exactly one matching process.
