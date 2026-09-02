# labhost 1.4-dev2 — Phase 1B test

Phase 1A should already be passing. This checkpoint adds DHCP to `ip-set` and
`vlan-create`, plus DHCP-aware `lab-save` persistence.

## 1. Build

```bash
cd /storage/images/labhost-1.4-phase1b
docker build -t labhost:1.4-dev2 .
```

Point one test labhost at `labhost:1.4-dev2` and redeploy it.

Confirm the client exists:

```bash
command -v dhcpcd
dhcpcd --version | head -1
```

## 2. Self-contained DHCP test for `ip-set`

This creates a temporary veth pair entirely inside the labhost. One end is a
small dnsmasq DHCP server; the other is the DHCP client.

```bash
sudo ip link add ds0 type veth peer name dc0
sudo ip addr add 192.0.2.1/24 dev ds0
sudo ip link set ds0 up
sudo ip link set dc0 up

sudo dnsmasq \
  --port=0 \
  --interface=ds0 \
  --bind-interfaces \
  --dhcp-range=192.0.2.100,192.0.2.110,255.255.255.0,1h \
  --dhcp-option=3,192.0.2.1 \
  --pid-file=/run/labhost/dnsmasq-phase1b.pid

ip-set dc0 dhcp
ip -4 addr show dev dc0
ip route show dev dc0
```

You should see an address in `192.0.2.100-110`.

Now verify persistence:

```bash
lab-save --dry-run | grep -E 'ip-set dc0|192\.0\.2\.10'
```

Expected: `ip-set dc0 dhcp`. The leased address itself must **not** appear as a
static `ip-set` line.

Cleanup:

```bash
sudo kill "$(cat /run/labhost/dnsmasq-phase1b.pid)" 2>/dev/null || true
sudo dhcpcd -k dc0 2>/dev/null || true
sudo ip link del ds0
rm -f /config/.labhost/dhcp/dc0
```

## 3. Self-contained DHCP test for `vlan-create`

```bash
sudo ip link add vs0 type veth peer name vc0
sudo ip link set vs0 mtu 9000
sudo ip link set vc0 mtu 9000
sudo ip link set vs0 up
sudo ip link set vc0 up

sudo ip link add link vs0 name vs0.123 type vlan id 123
sudo ip addr add 198.51.100.1/24 dev vs0.123
sudo ip link set vs0.123 up

sudo dnsmasq \
  --port=0 \
  --interface=vs0.123 \
  --bind-interfaces \
  --dhcp-range=198.51.100.100,198.51.100.110,255.255.255.0,1h \
  --dhcp-option=3,198.51.100.1 \
  --pid-file=/run/labhost/dnsmasq-phase1b-vlan.pid

vlan-create vc0 123 dhcp
ip -4 addr show dev vc0.123
```

You should see an address in `198.51.100.100-110`.

Verify `lab-save` keeps the high-level command:

```bash
lab-save --dry-run | grep -E 'vlan-create vc0 123|198\.51\.100\.10'
```

Expected:

```text
vlan-create vc0 123 dhcp
```

The leased address must not be emitted as a static `ip-set vc0.123 ...` line.

Cleanup:

```bash
sudo kill "$(cat /run/labhost/dnsmasq-phase1b-vlan.pid)" 2>/dev/null || true
vlan-delete vc0.123
sudo ip link del vs0
```

## 4. Static-to-DHCP / DHCP-to-static check

If you have a real lab interface with DHCP available, also verify:

```bash
ip-set eth1 dhcp
lab-save --dry-run | grep eth1

ip-set eth1 192.168.100.10/24
lab-save --dry-run | grep eth1
```

After switching back to static, `lab-save` should contain the static address and
must no longer contain `ip-set eth1 dhcp`.

## Pass criteria

- `dhcpcd` is installed.
- `ip-set <iface> dhcp` obtains a lease.
- `vlan-create <parent> <vid> dhcp` obtains a lease on the VLAN.
- DHCP does not replace `/etc/resolv.conf` / management DNS.
- `lab-save` emits DHCP intent, not the current leased IP.
- Switching an interface from DHCP back to static removes DHCP intent.
- `vlan-delete` removes DHCP intent for the deleted VLAN.
