#!/bin/bash
set -euo pipefail

IMAGE="${1:-labhost:1.4}"
NAME="${LABHOST_SMOKE_NAME:-labhost-smoke}"

TMPDIR="$(mktemp -d)"
CONFIG_DIR="$TMPDIR/configs"
PCAP_DIR="$TMPDIR/pcaps"

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR" "$PCAP_DIR"

# The smoke test may be launched with sudo. The bind-mounted directories must
# remain writable by the image's unprivileged lab user.
chmod 0777 "$CONFIG_DIR" "$PCAP_DIR"

pass() {
    printf 'PASS: %s\n' "$*"
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

section() {
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

section "LABHOST v1.4 SMOKE TEST"
echo "Image: $IMAGE"

docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || fail "Docker image '$IMAGE' does not exist."

docker rm -f "$NAME" >/dev/null 2>&1 || true

docker run -d --rm \
    --name "$NAME" \
    --hostname smokehost \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --sysctl net.ipv4.tcp_l3mdev_accept=1 \
    --sysctl net.ipv4.conf.default.arp_ignore=1 \
    --sysctl net.ipv4.conf.default.arp_announce=2 \
    -p 127.0.0.1::22 \
    -v "$CONFIG_DIR:/config" \
    -v "$PCAP_DIR:/pcaps" \
    -e LAB_PASSWORD=lab \
    "$IMAGE" >/dev/null

# Give entrypoint/sshd a moment to initialize.
for _ in $(seq 1 20); do
    if docker exec "$NAME" true >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

docker exec "$NAME" true >/dev/null 2>&1 \
    || fail "Container did not remain running."

pass "Container started and remained running"

published="$(docker port "$NAME" 22/tcp | head -1)"
PORT="${published##*:}"
[[ "$PORT" =~ ^[0-9]+$ ]]     || fail "Could not determine Docker-assigned SSH port from: $published"
pass "Docker assigned localhost SSH port $PORT"

section "VERSION / PATH / CORE BINARIES"

version="$(docker exec "$NAME" sh -lc 'printf "%s" "${LABHOST_VERSION:-unknown}"')"
[[ "$version" == "1.4" ]] || fail "Expected LABHOST_VERSION=1.4, got '$version'."
pass "LABHOST_VERSION=1.4"

path_value="$(docker exec "$NAME" sh -lc 'printf "%s" "$PATH"')"
echo "PATH=$path_value"

for required_path in /usr/local/sbin /usr/sbin /sbin; do
    [[ ":$path_value:" == *":$required_path:"* ]] \
        || fail "PATH is missing $required_path"
done
pass "Administrative networking paths are present"

for cmd in \
    ip tc bridge tcpdump tshark tcpreplay iperf iperf3 mcjoin \
    trafgen mausezahn nmap lldpcli snmpwalk radclient dnsmasq scapy; do
    docker exec "$NAME" sh -lc "command -v '$cmd' >/dev/null" \
        || fail "Required binary '$cmd' was not found."
done
pass "Core networking/test binaries are present"

section "HELPER COMMANDS / SELF-DOCUMENTATION"

for cmd in \
    lab-help lab-status lab-save lab-config lab-readme \
    mgmt-vrf-status vrf-create vrf-add vrf-status vrf-route-add vrf-exec \
    lag-create vlan-create netem iperf-test mcast-send send-tcp clients-create; do
    docker exec "$NAME" sh -lc "command -v '$cmd' >/dev/null" \
        || fail "Helper '$cmd' was not found."
done
pass "v1.4 helper symlinks are present"

docker exec "$NAME" lab-help >/dev/null \
    || fail "lab-help failed."
docker exec "$NAME" lag-create --help | grep 'Usage:' >/dev/null \
    || fail "lag-create --help did not return detailed help."
docker exec "$NAME" lab-help vrf-create | grep 'table-id' >/dev/null \
    || fail "lab-help vrf-create did not return VRF help."
docker exec "$NAME" mcast-send --help | grep -Ei 'TTL.*32' >/dev/null \
    || fail "mcast-send help does not document TTL 32."
pass "Self-documenting helper behavior works"

section "AUTOMATIC MANAGEMENT VRF"

docker exec "$NAME" ip link show vrf-mgmt >/dev/null \
    || fail "vrf-mgmt was not created."

mgmt_table="$(docker exec "$NAME" sh -lc \
    "ip -d link show vrf-mgmt | sed -nE 's/.* vrf table ([0-9]+).*/\1/p' | head -1")"
[[ "$mgmt_table" == "4094" ]] \
    || fail "vrf-mgmt uses table '$mgmt_table' instead of 4094."

master="$(docker exec "$NAME" sh -lc \
    "ip -d link show eth0 | sed -nE 's/.* master ([^ ]+).*/\1/p' | head -1")"
[[ "$master" == "vrf-mgmt" ]] \
    || fail "eth0 is not attached to vrf-mgmt."

tcp_accept="$(docker exec "$NAME" sysctl -n net.ipv4.tcp_l3mdev_accept)"
[[ "$tcp_accept" == "1" ]] \
    || fail "net.ipv4.tcp_l3mdev_accept is not 1."

docker exec "$NAME" ip route show table 4094 | grep '^default ' >/dev/null \
    || fail "Management table 4094 has no default route."

docker exec "$NAME" mgmt-vrf-status >/dev/null \
    || fail "mgmt-vrf-status failed."

pass "eth0 -> vrf-mgmt/table 4094 and management default route are correct"

section "SSH"

ssh_listening=false
for _ in $(seq 1 40); do
    if docker exec "$NAME" ss -lnt | grep -E '(:22[[:space:]]|:22$)' >/dev/null; then
        ssh_listening=true
        break
    fi
    sleep 0.25
done
[[ "$ssh_listening" == true ]] || fail "sshd is not listening on TCP/22."
pass "sshd is listening on TCP/22"

# This validates that Docker can reach the wildcard SSH listener after eth0
# moved into the VRF. It is supplemental to the in-container listener check.
if command -v nc >/dev/null 2>&1; then
    ssh_reachable=false
    for _ in $(seq 1 40); do
        if nc -z -w1 127.0.0.1 "$PORT" >/dev/null 2>&1; then
            ssh_reachable=true
            break
        fi
        sleep 0.25
    done
    [[ "$ssh_reachable" == true ]] \
        || fail "Published SSH port is not reachable on localhost:$PORT"
    pass "Published SSH port is reachable on localhost:$PORT"
else
    echo "INFO: host 'nc' not installed; skipping published-port reachability test."
fi

section "LAB-STATUS DISPLAY"

status="$(docker exec "$NAME" lab-status)"
grep -q '=== Help & Documentation ===' <<<"$status" \
    || fail "lab-status is missing Help & Documentation section."
grep -q 'README:    lab-readme' <<<"$status" \
    || fail "lab-status is missing lab-readme hint."
if grep -Eq 'eth[0-9]+@if[0-9]+' <<<"$status"; then
    fail "lab-status still displays @ifXX peer suffixes."
fi
pass "lab-status output is cleaned and includes help pointers"

section "USER VRF / VLAN / NETEM"

# Create temporary lab-style interfaces for helper testing.
docker exec "$NAME" ip link add smoke0 type dummy
docker exec "$NAME" ip link set smoke0 up
docker exec "$NAME" vlan-create smoke0 100 192.0.2.10/24
docker exec "$NAME" vrf-create blue 101
docker exec "$NAME" vrf-add blue smoke0.100
docker exec "$NAME" vrf-route-add blue default 192.0.2.1 smoke0.100
docker exec "$NAME" netem smoke0 delay 10ms loss 0.1%

docker exec "$NAME" vrf-status blue | grep 'Table: 101' >/dev/null \
    || fail "User VRF table 101 was not created."
docker exec "$NAME" ip -br addr show smoke0.100 | grep '192.0.2.10/24' >/dev/null \
    || fail "VLAN address was not configured."
docker exec "$NAME" tc qdisc show dev smoke0 | grep 'netem' >/dev/null \
    || fail "NetEm qdisc was not configured."

pass "VRF, VLAN, addressing, VRF route, and NetEm helpers work"

section "CLIENT START-IP PARSING"

docker exec "$NAME" clients-create smoke0 2 198.51.100.0/24 198.51.100.100
docker exec "$NAME" clients-list | grep '198.51.100.100/24' >/dev/null \
    || fail "clients-create literal starting IP was not applied."
docker exec "$NAME" clients-list | grep '198.51.100.101/24' >/dev/null \
    || fail "clients-create did not increment literal starting IP."
docker exec "$NAME" clients-status | awk \
    '$1 ~ /^cl[0-9]+$/ && $5 == "1" && $6 == "2" { found++ } END { exit !(found == 2) }' \
    || fail "Synthetic clients do not have arp_ignore=1 and arp_announce=2."
docker exec "$NAME" clients-delete
pass "clients-create accepts a literal starting IP"

section "LAB-SAVE DRY RUN"

dry_run="$(docker exec -u lab "$NAME" lab-save --dry-run)"

grep -q '^vrf-create blue 101' <<<"$dry_run" \
    || fail "lab-save dry-run did not capture user VRF."
grep -q 'vlan-create smoke0 100' <<<"$dry_run" \
    || fail "lab-save dry-run did not capture VLAN."
grep -q 'ip-set smoke0.100 192.0.2.10/24' <<<"$dry_run" \
    || fail "lab-save dry-run did not capture IPv4 address."
grep -q 'vrf-route-add blue default 192.0.2.1 smoke0.100' <<<"$dry_run" \
    || fail "lab-save dry-run did not capture VRF default route."
grep -q 'netem smoke0' <<<"$dry_run" \
    || fail "lab-save dry-run did not capture NetEm."
if grep -q 'vrf-create mgmt 4094' <<<"$dry_run"; then
    fail "lab-save attempted to persist automatic management VRF."
fi

pass "lab-save --dry-run captures supported state and excludes automatic management VRF"

section "LAB-SAVE FILE PERSISTENCE"

docker exec -u lab "$NAME" lab-save >/dev/null

[[ -f "$CONFIG_DIR/smokehost.sh" ]] \
    || fail "lab-save did not create host-side configs/smokehost.sh."

grep -q '^vrf-create blue 101' "$CONFIG_DIR/smokehost.sh" \
    || fail "Saved startup file is missing VRF configuration."

docker exec -u lab "$NAME" lab-config path | grep '/config/smokehost.sh' >/dev/null \
    || fail "lab-config path returned an unexpected path."

docker exec -u lab "$NAME" lab-config | grep '^vrf-create blue 101' >/dev/null \
    || fail "lab-config did not display the saved startup configuration."

# Verify backup-on-save.
docker exec -u lab "$NAME" lab-save >/dev/null
[[ -f "$CONFIG_DIR/smokehost.sh.bak" ]] \
    || fail "Second lab-save did not create .bak backup."

pass "lab-save writes through bind mount, lab-config works, and backup-on-save works"

section "STARTUP CONFIG EXECUTION"

# Replace generated config with a harmless startup marker and restart container.
cat >"$CONFIG_DIR/smokehost.sh" <<'EOF'
#!/bin/bash
echo startup-ran >/config/startup-ran.txt
EOF
chmod 0755 "$CONFIG_DIR/smokehost.sh"

docker rm -f "$NAME" >/dev/null

docker run -d --rm \
    --name "$NAME" \
    --hostname smokehost \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --sysctl net.ipv4.tcp_l3mdev_accept=1 \
    --sysctl net.ipv4.conf.default.arp_ignore=1 \
    --sysctl net.ipv4.conf.default.arp_announce=2 \
    -p 127.0.0.1::22 \
    -v "$CONFIG_DIR:/config" \
    -v "$PCAP_DIR:/pcaps" \
    -e LAB_PASSWORD=lab \
    "$IMAGE" >/dev/null

published="$(docker port "$NAME" 22/tcp | head -1)"
PORT="${published##*:}"

for _ in $(seq 1 40); do
    if [[ -f "$CONFIG_DIR/startup-ran.txt" ]]; then
        break
    fi
    sleep 0.25
done

[[ -f "$CONFIG_DIR/startup-ran.txt" ]] \
    || fail "Entrypoint did not execute /config/smokehost.sh at startup."

pass "Hostname-based startup configuration executes automatically"

section "RESULT"
echo "All labhost v1.4 smoke tests passed."
echo
echo "Image size:"
docker image inspect "$IMAGE" --format '{{.Size}} bytes'
