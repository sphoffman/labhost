#!/usr/bin/env python3
"""Per-port LLDP-MED phone agent for labhost.

Sends a phone LLDP identity on a physical parent, learns an LLDP-MED Voice
Network Policy from the attached switch, and materializes the tagged voice
interface using the same deterministic phone MAC.
"""
import argparse, os, socket, struct, subprocess, time

LLDP_DST = bytes.fromhex('0180c200000e')
MED_OUI = bytes.fromhex('0012bb')

def tlv(t, value):
    h=(t<<9)|len(value)
    return struct.pack('!H',h)+value

def macb(mac): return bytes.fromhex(mac.replace(':',''))

def frame(src, ifname, sysname):
    body=b''.join([
        tlv(1, b'\x04'+macb(src)),
        tlv(2, b'\x05'+ifname.encode()),
        tlv(3, struct.pack('!H',120)),
        tlv(4, f'{sysname} phone uplink'.encode()),
        tlv(5, sysname.encode()),
        tlv(6, b'labhost simulated LLDP-MED phone'),
        tlv(7, struct.pack('!HH',0x0020,0x0020)),
        tlv(127, MED_OUI+b'\x01'+bytes.fromhex('000303')),
        tlv(0,b'')])
    return LLDP_DST+macb(src)+struct.pack('!H',0x88cc)+body

def parse_med(pkt):
    if len(pkt)<14 or pkt[:6] != LLDP_DST or pkt[12:14] != b'\x88\xcc': return None
    off=14
    while off+2<=len(pkt):
        h=struct.unpack('!H',pkt[off:off+2])[0]; off+=2
        typ=h>>9; ln=h&0x1ff
        if off+ln>len(pkt): break
        val=pkt[off:off+ln]; off+=ln
        if typ==0: break
        if typ==127 and len(val)>=8 and val[:3]==MED_OUI and val[3]==2:
            app=val[4]
            if app != 1: continue
            pol=int.from_bytes(val[5:8],'big')
            unknown=bool(pol & (1<<23)); tagged=bool(pol & (1<<22))
            vlan=(pol>>9)&0xfff; prio=(pol>>6)&0x7; dscp=pol&0x3f
            if unknown or vlan==0: continue
            return vlan, tagged, prio, dscp
    return None

def run(*args): subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def exists(dev): return subprocess.run(['ip','link','show',dev],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0

def dhcp_start(iface, mac):
    # Explicit RFC2132 Ethernet client identifier: type 1 + deterministic MAC.
    # dhcpcd otherwise derives an IAID from the VLAN ID for VLAN interfaces,
    # causing every simulated phone on the same voice VLAN to share one DHCP
    # identity and replace the previous phone's dnsmasq lease.
    client_id='01:'+mac.lower()
    subprocess.run(['dhcpcd','-4','-q','-b','-C','resolv.conf','-I',client_id,iface],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def provision(parent, phone_mac, vlan, tagged, prio, dscp, statefile, dhcp):
    voice=f'pp-{parent}-v{vlan}'[:15]
    if not tagged:
        with open(statefile,'w') as f: f.write(f'vlan={vlan}\ntagged=0\npriority={prio}\ndscp={dscp}\nvoice_iface={parent}\n')
        return
    old=None
    if os.path.exists(statefile):
        for line in open(statefile):
            if line.startswith('voice_iface='): old=line.strip().split('=',1)[1]
    if old and old != voice and old != parent and exists(old): run('ip','link','del',old)
    if not exists(voice): run('ip','link','add','link',parent,'name',voice,'type','vlan','id',str(vlan))
    run('ip','link','set',voice,'down'); run('ip','link','set',voice,'address',phone_mac); run('ip','link','set',voice,'up')
    if dhcp: dhcp_start(voice, phone_mac)
    with open(statefile,'w') as f: f.write(f'vlan={vlan}\ntagged=1\npriority={prio}\ndscp={dscp}\nvoice_iface={voice}\n')

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--parent',required=True); ap.add_argument('--mac',required=True); ap.add_argument('--name',required=True); ap.add_argument('--state',required=True); ap.add_argument('--dhcp',action='store_true'); a=ap.parse_args()
    s=socket.socket(socket.AF_PACKET,socket.SOCK_RAW,socket.htons(0x88cc)); s.bind((a.parent,0)); s.settimeout(1)
    out=frame(a.mac,a.parent,a.name); last=0; current=None
    while True:
        now=time.time()
        if now-last>=30: s.send(out); last=now
        try: pkt=s.recv(2048)
        except socket.timeout: continue
        med=parse_med(pkt)
        if med and med != current:
            provision(a.parent,a.mac,*med,a.state,a.dhcp); current=med

if __name__=='__main__': main()
