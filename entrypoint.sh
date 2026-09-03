#!/bin/bash
set -e

LAB_PASSWORD="${LAB_PASSWORD:-lab}"

echo "lab:${LAB_PASSWORD}" | chpasswd

ssh-keygen -A

cat >/etc/ssh/sshd_config.d/labhost.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
EOF

if [ -f /home/lab/.ssh/authorized_keys ]; then
    chown lab:lab /home/lab/.ssh/authorized_keys
    chmod 600 /home/lab/.ssh/authorized_keys
fi

chmod 700 /home/lab/.ssh
chown lab:lab /home/lab/.ssh

# Runtime intent is working metadata used by lab-save. It intentionally lives
# under /run so interactive configuration is not persistent until lab-save
# writes /config/<hostname>.sh.
mkdir -p /run/labhost/intents
chown -R lab:lab /run/labhost/intents

#
# labhost v1.3 management VRF
#
# eth0 remains the Containerlab management interface, but is moved
# into vrf-mgmt so the main routing table can be used independently
# by the lab-facing interfaces.
#

MGMT_IF="${LABHOST_MGMT_IF:-eth0}"
MGMT_VRF="${LABHOST_MGMT_VRF:-vrf-mgmt}"
MGMT_TABLE="${LABHOST_MGMT_TABLE:-4094}"

if ip link show "$MGMT_IF" >/dev/null 2>&1; then
    MGMT_GATEWAY="$(
        ip -4 route show default dev "$MGMT_IF" |
        awk '/default/ {print $3; exit}'
    )"

    if ! ip link show "$MGMT_VRF" >/dev/null 2>&1; then
        ip link add "$MGMT_VRF" type vrf table "$MGMT_TABLE"
    fi

    ip link set "$MGMT_VRF" up

    if ! ip -d link show "$MGMT_IF" | grep -q "master $MGMT_VRF"; then
        ip link set "$MGMT_IF" master "$MGMT_VRF"
    fi

    ip link set "$MGMT_IF" up

    TCP_L3MDEV_ACCEPT="$(
        sysctl -n net.ipv4.tcp_l3mdev_accept 2>/dev/null || echo 0
    )"

    if [ "$TCP_L3MDEV_ACCEPT" != "1" ]; then
        echo "labhost: WARNING: net.ipv4.tcp_l3mdev_accept is not 1." >&2
        echo "labhost: SSH through vrf-mgmt may not work." >&2
        echo "labhost: Add this to the Containerlab node:" >&2
        echo "labhost:   sysctls:" >&2
        echo "labhost:     net.ipv4.tcp_l3mdev_accept: 1" >&2
    fi

    if [ -n "$MGMT_GATEWAY" ]; then
        ip route replace \
            table "$MGMT_TABLE" \
            default via "$MGMT_GATEWAY" \
            dev "$MGMT_IF"
    fi
fi

DATA_MTU="${LABHOST_DATA_MTU:-9000}"

while read -r iface; do
    iface="${iface%@*}"

    [[ -n "$iface" ]] || continue
    [[ "$iface" == "$MGMT_IF" ]] && continue

    if [[ "$iface" =~ ^eth[0-9]+$ ]]; then
        ip link set "$iface" mtu "$DATA_MTU" 2>/dev/null || true
    fi

done < <(
    ip -o link show |
    awk -F': ' '{print $2}' |
    cut -d@ -f1
)

lldpd >/dev/null 2>&1 || true

STARTUP_CONFIG="/config/$(hostname -s).sh"

if [ -f "$STARTUP_CONFIG" ]; then
    echo "labhost: applying startup configuration: $STARTUP_CONFIG"

    if ! bash "$STARTUP_CONFIG"; then
        echo "labhost: WARNING: startup configuration failed: $STARTUP_CONFIG" >&2
    fi
fi

# Startup replay runs as root. Commands such as dhcp-pool-create therefore
# create runtime intent subdirectories/files as root. Hand ownership back to
# the interactive lab user after replay so later helper commands can modify
# the same runtime intent state.
chown -R lab:lab /run/labhost/intents 2>/dev/null || true

exec /usr/sbin/sshd -D -e
