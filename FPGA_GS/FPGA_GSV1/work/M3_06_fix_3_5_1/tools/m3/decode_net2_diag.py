"""Decode the passive 3.5.1 serial channel. Does not open network sockets."""
import json,re,sys
from pathlib import Path

def decode(line):
    fields=line.strip().split()
    # Prefix consists of N2 and 351; it is followed by 22 hexadecimal words.
    if len(fields)!=24 or fields[:2]!=['N2','351'] or any(not re.fullmatch('[0-9A-Fa-f]{8}',v) for v in fields[2:]):
        return None
    w=[int(v,16) for v in fields[2:]];f=w[3]&65535
    names=['raw_rx_frames','bridge_rx_frames','mac_valid_frames','mac_crc_or_length_errors',
           'mac_overruns','tx_pin_frames','mac_reset_epochs','bridge_rx_bytes',
           'core_packets','core_bad_packets','arp_hello','session','upload_frames','upload_aborts',
           'tx_requests','tx_completions','core_flags','reset_flags']
    d=dict(zip(names,w[4:]))
    d.update(phy_id1=f'{w[0]>>16:04X}',phy_id2=f'{w[0]&65535:04X}',
        delay_register=f'{w[1]>>16:04X}',mdio_no_ack=w[1]&65535,
        phy_wrong_id=w[2]>>16,delay_readback_fail=w[2]&65535,
        phy_status=f'{w[3]>>16:04X}',phy_configured=bool(f&0x8000),phy_ready=bool(f&0x4000),
        rx_clock_alive=bool(f&0x2000),phy_step=(f>>8)&15,phy_address=f&31,
        arp_accept=w[14]>>16,hello_accept=w[14]&65535,online=bool(w[20]&16),
        phy_reset_released=bool(w[21]&4),core_ready=bool(w[21]&2),mac_ready=bool(w[21]&1))
    del d['arp_hello']
    return d

if __name__=='__main__':
    lines=Path(sys.argv[1]).read_text(encoding='utf-8-sig').splitlines()
    decoded=[d for line in lines if (d:=decode(line)) is not None]
    if not decoded:raise SystemExit('No valid N2 351 line (22 words expected)')
    print(json.dumps(dict(first=decoded[0],last=decoded[-1],lines=len(decoded)),ensure_ascii=False,indent=2))
