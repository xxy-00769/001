"""Read-only network configuration; 10 raw ARP probes to a selected FPGA port.
Run on OrangePi: sudo python3 net2_tx_compare.py --port 1
This does not add an IP, neighbor, route, dependency, or change PHY settings.
"""
import argparse, json, socket, struct, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--port',type=int,choices=[1,2],required=True);p.add_argument('--interface',default='eth0');a=p.parse_args()
s=socket.socket(socket.AF_PACKET,socket.SOCK_RAW,socket.htons(0x0806));s.bind((a.interface,0));s.settimeout(.2)
mac=s.getsockname()[4];subnet=50 if a.port==1 else 60
src=socket.inet_aton('192.168.%d.1'%subnet);dst=socket.inet_aton('192.168.%d.2'%subnet)
def stats():
 try:
  t=subprocess.check_output(['ethtool','-S',a.interface],text=True)
  return {k.strip():int(v.strip()) for line in t.splitlines() if ':' in line for k,v in [line.split(':',1)] if k.strip() in ['mmc_rx_framecount_gb','mmc_rx_crc_error','mmc_rx_octetcount_g','rx_pkt_n']}
 except (OSError,subprocess.CalledProcessError):return {}
request=b'\xff'*6+mac+b'\x08\x06'+struct.pack('!HHBBH',1,0x0800,6,4,1)+mac+src+b'\0'*6+dst
before=stats();replies=[]
for i in range(10):
 s.send(request);end=time.monotonic()+.5
 while time.monotonic()<end:
  try:r=s.recv(2048)
  except socket.timeout:continue
  if len(r)>=42 and r[12:14]==b'\x08\x06' and r[20:22]==b'\0\x02' and r[28:32]==dst:
   replies.append(dict(length=len(r),destination_matches=r[:6]==mac,target_matches=r[32:38]==mac and r[38:42]==src,source_mac=r[6:12].hex(':'),hex=r.hex()))
after=stats();s.close()
print(json.dumps(dict(port=a.port,host_mac=mac.hex(':'),requests=10,valid_arp_replies=len(replies),first_reply=replies[:1],before=before,after=after,delta={k:after[k]-before[k] for k in before if k in after}),indent=2))
