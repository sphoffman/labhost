FROM debian:13-slim AS mcjoin-builder

ARG MCJOIN_VERSION=2.12
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    && git clone --branch "v${MCJOIN_VERSION}" --depth 1 \
       https://github.com/troglobit/mcjoin.git /src/mcjoin \
    && cd /src/mcjoin \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install-strip


FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LABHOST_VERSION="1.4-dev12"

# Avoid interactive package prompts.
RUN echo 'wireshark-common wireshark-common/install-setuid boolean false' \
        | debconf-set-selections \
    && echo 'iperf3 iperf3/start_daemon boolean false' \
        | debconf-set-selections \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        wget \
        git \
        openssh-server \
        sudo \
        iproute2 \
        ifenslave \
        iputils-ping \
        iputils-arping \
        traceroute \
        mtr-tiny \
        ethtool \
        net-tools \
        bridge-utils \
        vlan \
        tcpdump \
        tshark \
        tcpreplay \
        netsniff-ng \
        iperf \
        iperf3 \
        hping3 \
        nmap \
        fping \
        socat \
        netcat-openbsd \
        dnsutils \
        ldnsutils \
        dnsmasq \
        dhcpcd-base \
        nftables \
        iptables \
        ebtables \
        conntrack \
        lldpd \
        snmp \
        snmpd \
        freeradius-utils \
        ndisc6 \
        bmon \
        iftop \
        iptraf-ng \
        tftp-hpa \
        telnet \
        ftp \
        openssl \
        rsync \
        jq \
        vim-tiny \
        nano \
        less \
        procps \
        psmisc \
        lsof \
        strace \
        file \
        tree \
        whois \
        ipcalc \
        python3 \
        python3-pip \
        python3-scapy \
    && rm -rf /var/lib/apt/lists/*

COPY --from=mcjoin-builder /usr/local/ /usr/local/

COPY bin/labctl /usr/local/bin/labctl
COPY bin/lab-reset /usr/local/bin/lab-reset
COPY bin/dhcp-leases /usr/local/bin/dhcp-leases
COPY bin/pc-phone-create /usr/local/bin/pc-phone-create
COPY lib/pc_phone_lldp.py /usr/local/lib/labhost/pc_phone_lldp.py
COPY entrypoint.sh /usr/local/bin/labhost-entrypoint
COPY README.md /usr/local/share/labhost/README.md
COPY motd /etc/motd

# labctl is the common implementation. Friendly command names are symlinks;
# reset, lease display, and restart-safe PC/phone creation use dedicated wrappers.
RUN chmod 0755 \
        /usr/local/bin/labctl \
        /usr/local/bin/lab-reset \
        /usr/local/bin/dhcp-leases \
        /usr/local/bin/pc-phone-create \
        /usr/local/bin/labhost-entrypoint \
        /usr/local/lib/labhost/pc_phone_lldp.py \
    && for cmd in \
        lab-help lab-status lab-save lab-config lab-readme \
        mgmt-vrf-status \
        vrf-create vrf-delete vrf-add vrf-remove vrf-status \
        vrf-route-add vrf-route-del vrf-exec \
        lag-create lag-delete lag-status lag-member-up lag-member-down \
        vlan-create vlan-delete vlan-list qinq-create qinq-delete \
        ip-set ipv6-set mac-set mtu-set mtu-all route-add route-del default-gw \
        link-up link-down link-flap \
        path-test port-test ports-scan \
        capture capture-save capture-ring capture-read \
        capture-lacp capture-igmp capture-pim capture-arp capture-nd \
        netem netem-clear netem-status netem-profile rate-limit rate-clear \
        wan-create wan-delete wan-status wan-impair \
        iperf-server iperf-client iperf-udp iperf-reverse iperf-bidir \
        iperf-parallel iperf-bind iperf-mcast-server iperf-mcast-send iperf-test \
        mcast-join mcast-send \
        http-server https-server tcp-listen udp-listen \
        dnsmasq-start dnsmasq-stop dhcp-pool-create dhcp-pool-delete dhcp-pool-list dhcp-server-start dhcp-server-stop dhcp-server-status tftp-server \
        lldp-start lldp-show lldp-stop pc-phone-delete pc-phone-status pc-phone-reprovision pc-phones-create pc-phones-status \
        radius-test snmp-walk snmp-get \
        arp-watch nd-watch gratuitous-arp arp-clear \
        clients-create clients-delete clients-list clients-status clients-arp clients-ping clients-traffic endpoint-move \
        send-tcp send-udp send-broadcast send-mcast; \
      do \
        ln -s /usr/local/bin/labctl "/usr/local/bin/$cmd"; \
      done

# Non-root interactive lab user.
RUN useradd -m -s /bin/bash lab \
    && echo 'lab ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/lab \
    && chmod 0440 /etc/sudoers.d/lab \
    && mkdir -p \
        /run/sshd \
        /run/labhost \
        /home/lab/.ssh \
        /config \
        /pcaps \
        /scripts \
    && chown -R lab:lab \
        /home/lab \
        /config \
        /pcaps \
        /scripts

# Interactive shell environment.
RUN cat >>/home/lab/.bashrc <<'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

alias ll='ls -alF'
alias ipb='ip -br addr'
alias ipr='ip route'
alias ip6r='ip -6 route'
alias neigh='ip neigh'
alias ports='ss -lntup'
EOF

# Login shells and SSH sessions must also see administrative networking tools.
RUN printf '%s\n' \
    'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
    > /etc/profile.d/labhost-path.sh \
    && chmod 0644 /etc/profile.d/labhost-path.sh

EXPOSE \
    22/tcp \
    5001/tcp \
    5001/udp \
    5201/tcp \
    5201/udp \
    8000/tcp \
    8080/tcp \
    8443/tcp

ENTRYPOINT ["/usr/local/bin/labhost-entrypoint"]
