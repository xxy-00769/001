"""Decode C0O9 read-only OV5640 baseline. No sensor or host writes."""
import argparse
import json
from pathlib import Path

REGS = [0x300a,0x300b,0x3034,0x3035,0x3036,0x3037,0x3108,0x3039,
        0x3500,0x3501,0x3502,0x3500,0x3501,0x3503,0x350a,0x350b,
        0x350c,0x350d,0x380c,0x380d,0x380e,0x380f,0x3a00,0x3a02,
        0x3a03,0x3a14,0x3a15,0x3a18,0x3a19,0x3a08,0x3a09,0x3a0a,
        0x3a0b,0x3a0d,0x3a0e,0x3c00,0x3c01,0x3c0c,0x3824,0x460c,
        0x5000,0x5001,0x5308,0x5306]

def decode(w):
    b = b''.join(v.to_bytes(4,'big') for v in w[29:40])
    r = dict(zip(REGS,b))
    # First and second reads of high bytes must agree; do not report a torn
    # 20-bit exposure as a physical measurement. Fraction is the first low byte.
    coherent = b[8:10] == b[11:13]
    valid = bool(w[22] & (1<<26))
    ticks = w[28] >> 16
    row_ms = ticks/50000 if ticks else None
    exp = ((b[8]&15)<<16) | (b[9]<<8) | b[10]
    val16 = lambda hi: (r[hi]<<8) | r[hi+1]
    return dict(tag='C0O9', initialized=bool(w[22] & (1<<25)),
        read_valid=valid, last_nack=(w[22]>>28)&15,
        last_timeout=bool(w[22] & (1<<27)),
        read_sequence=(w[28]>>8)&255, read_errors=w[28]&255,
        pixels=w[21],rows=w[22]&65535,geometry_errors=(w[22]>>16)&255,
        capture_good=w[23]&65535,capture_bad=w[23]>>16,
        capture_start_ms=w[24],ddr_published=w[25]>>16,
        displayed_new=w[25]&65535,reference_ms=w[26],byte_pclk_hz=w[27],
        row_period_ms=row_ms, sensor_id=f'{val16(0x300a):04x}' if valid else None,
        exposure_coherent=coherent,
        exposure_lines=exp/16 if valid and coherent else None,
        exposure_ms=(exp/16*row_ms) if valid and coherent and row_ms else None,
        gain_x=(((r[0x350a]&3)<<8)|r[0x350b])/16 if valid else None,
        gain_ceiling_x=(((r[0x3a18]&3)<<8)|r[0x3a19])/16 if valid else None,
        hts=val16(0x380c) if valid else None,vts=val16(0x380e) if valid else None,
        extra_vts=val16(0x350c) if valid else None,
        vts_row_rate_fps=1000/(val16(0x380e)*row_ms) if valid and row_ms and val16(0x380e) else None,
        hts_inferred_sysclk_hz=val16(0x380c)*1000/row_ms if valid and row_ms else None,
        aec_auto=not bool(r[0x3503]&1) if valid else None,
        agc_auto=not bool(r[0x3503]&2) if valid else None,
        night_mode=bool(r[0x3a00]&4) if valid else None,
        exposure_cap_60_lines=val16(0x3a02) if valid else None,
        exposure_cap_50_lines=((r[0x3a14]&15)<<8|r[0x3a15]) if valid else None,
        band_50_ms=(((r[0x3a08]&3)<<8)|r[0x3a09])*row_ms if valid and row_ms else None,
        band_60_ms=(((r[0x3a0a]&3)<<8)|r[0x3a0b])*row_ms if valid and row_ms else None,
        registers={f'{k:04x}':f'{v:02x}' for k,v in r.items()} if valid else {})

def summarize(records,minimum_window=7):
    result=dict(completed=False,tag='C0O9',records=len(records),snapshots=records,
        notes=['Exposure ms = 3500..3502 /16 * measured physical row interval.',
               'Row interval averages256 consecutive HREF intervals against50MHz; excludes VS gap.',
               'HTS/row time infers sensor timing clock; PCLK is measured separately, not assumed equal.',
               'Registers are a successful sequential read sweep, not a frame-latched ISP snapshot.',
               'Exposure high bytes are re-read; a torn update has exposure_ms=null.',
               'Display count requires CAM0 visible, full output rows, no underflow, distinct source ID.',
               'Local CAM0 fps is separate from unchanged network2 upload request15fps.',
               'This readback build changes no exposure, gain, ISP, sensor PLL or frame ownership.'])
    if len(records)<2:
        result['error']='采样未完成：缺少两条完整C0O9记录；3.5.8不包含CAM0读回。'
        return result
    f,z=records[0],records[-1]
    dt=((z['reference_ms']-f['reference_ms'])&0xffffffff)/1000
    ct=((z['capture_start_ms']-f['capture_start_ms'])&0xffffffff)/1000
    delta=lambda key:(z[key]-f[key])&65535
    epoch=all(0<((v['reference_ms']-u['reference_ms'])&0xffffffff)<=5000 for u,v in zip(records,records[1:]))
    fresh=any(v['read_sequence']!=u['read_sequence'] for u,v in zip(records,records[1:]))
    good=all(r['initialized'] and r['read_valid'] and r['sensor_id']=='5640'
             and r['last_nack']==0 and not r['last_timeout'] and r['row_period_ms'] for r in records)
    result.update(reference_window_seconds=dt,capture_window_seconds=ct,
        capture_fps=delta('capture_good')/ct if ct else None,
        ddr_publish_fps=delta('ddr_published')/dt if dt else None,
        display_new_fps=delta('displayed_new')/dt if dt else None,
        capture_bad_delta=delta('capture_bad'),read_errors_delta=(z['read_errors']-f['read_errors'])&255,
        geometry_ok=all(r['pixels']==921600 and r['rows']==720 and not r['geometry_errors'] for r in records),
        fresh_readbacks=fresh,completed=bool(epoch and dt>=minimum_window and ct>0 and fresh and good))
    exps=[r['exposure_ms'] for r in records if r['exposure_ms'] is not None]
    result['exposure_ms_range']=[min(exps),max(exps)] if exps else None
    if not result['completed']:
        result['error']='采样未完成：请查看串口版本、读回ACK/超时、完整采样窗及读回序号。'
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('capture',type=Path)
    p.add_argument('--output',type=Path);p.add_argument('--minimum-window',type=float,default=7)
    a=p.parse_args();records=[]
    for line in a.capture.read_text(encoding='utf-8-sig').splitlines():
        if not line.startswith('N2 35O '):continue
        try:w=[int(v,16) for v in line.split()[2:]]
        except ValueError:continue
        if len(w)==40 and w[20]==0x43304f39:records.append(decode(w))
    result=summarize(records,a.minimum_window);out=json.dumps(result,ensure_ascii=False,indent=2)
    if a.output:a.output.write_text(out+'\n',encoding='utf-8')
    print(out);raise SystemExit(0 if result['completed'] else 2)
if __name__=='__main__':main()
