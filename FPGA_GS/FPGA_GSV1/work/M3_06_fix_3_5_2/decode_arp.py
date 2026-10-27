from pathlib import Path
p=Path('tools/m3/decode_net2_diag.py');s=p.read_text().replace('import json,re,sys','import json,re,sys,zlib,socket')
s=s.replace("if len(fields)!=24 or fields[:2] not in (['N2','351'],['N2','352']) or any", "if len(fields) not in (24,42) or fields[:2] not in (['N2','351'],['N2','352']) or any")
s=s.replace("w=[int(v,16) for v in fields[2:]];f=w[3]&65535", "w=[int(v,16) for v in fields[2:24]];f=w[3]&65535")
s=s.replace("    del d['arp_hello']", '''    if len(fields)==42:
        raw=bytes.fromhex(''.join(fields[24:]))
        d['last_mac_tx_arp_hex']=raw.hex()
        d['arp_record_present']=any(raw)
        if any(raw):
            e=raw[8:]
            d['last_mac_tx_arp']=dict(preamble_valid=raw[:8]==b'\\x55'*7+b'\\xd5',
                destination_mac=e[:6].hex(':'),source_mac=e[6:12].hex(':'),
                ethertype=e[12:14].hex(),opcode=int.from_bytes(e[20:22],'big'),
                sender_mac=e[22:28].hex(':'),sender_ip=socket.inet_ntoa(e[28:32]),
                target_mac=e[32:38].hex(':'),target_ip=socket.inet_ntoa(e[38:42]),
                zero_padding=e[42:60]==bytes(18),
                fcs_received=e[60:64].hex(),fcs_expected=zlib.crc32(e[:60]).to_bytes(4,'little').hex(),
                fcs_valid=zlib.crc32(e[:60]).to_bytes(4,'little')==e[60:64])
    del d['arp_hello']''')
s=s.replace('No valid N2 351 line (22 words expected)', 'No valid N2 351/352 line (22 or 40 words expected)')
p.write_text(s)
# Record exact values from user-provided transcript, not a fabricated raw file.
Path('reports/orangepi_stats_delta.json').write_text(json.dumps(dict(source='User SSH transcript, 2026-10-22 14:31:36..14:31:46 CST',first=dict(mmc_rx_framecount_gb=2014495,mmc_rx_crc_error=2014495,mmc_rx_octetcount_gb=2763421047,mmc_rx_octetcount_g=0),last=dict(mmc_rx_framecount_gb=2014505,mmc_rx_crc_error=2014505,mmc_rx_octetcount_gb=2763421687,mmc_rx_octetcount_g=0),software_RX_packets=0,hardware_delta_bad_frames=10,hardware_delta_bytes=640),indent=2))
