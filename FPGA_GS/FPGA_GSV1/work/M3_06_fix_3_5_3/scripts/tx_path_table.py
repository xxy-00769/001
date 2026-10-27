"""Keep raw full paths and extract per-edge TX window evidence, without rerouting."""
import argparse
import json
from pathlib import Path
import re


def paths(file):
    text = Path(file).read_text(errors='replace')
    out = []
    for match in re.finditer(r'^Startpoint\s*:(.*?)(?=^Startpoint\s*:|\Z)',text,re.M|re.S):
        block = match[0]
        if not re.search(r'^Endpoint\s*:\s*rgmii2_tx',block,re.M):
            continue
        def field(pattern):
            m = re.search(pattern,block,re.M)
            return m[1].strip() if m else None
        rec = dict(line=text.count('\n',0,match.start())+1,
                   startpoint=field(r'^Startpoint\s*:\s*(.*)'),
                   endpoint=field(r'^Endpoint\s*:\s*(\S+)'),
                   type=field(r'^Path Type\s*:\s*(.*)'),
                   launch_edge=field(r'^ Clock (?!eth2_phy_tx_capture)(\S+ \([^)]+\))'),
                   capture_edge=field(r'^ Clock eth2_phy_tx_capture \(([^)]+)\)'),
                   launch_clock_ns=field(r'^\s*Launch Clock Delay\s*:\s*([-\d.]+)'),
                   capture_clock_ns=field(r'^\s*Capture Clock Delay\s*:\s*([-\d.]+)'),
                   cpr_ns=field(r'^\s*Clock Pessimism Removal\s*:\s*([-\d.]+)'),
                   data_arrival_ns=field(r'^ Data arrival time\s+([-\d.]+)'),
                   data_required_ns=field(r'^ Data required time\s+([-\d.]+)'),
                   slack_ns=field(r'^ Slack \([^)]+\)\s+([-\d.]+)'))
        for k in list(rec):
            if k.endswith('_ns') and rec[k] is not None:
                rec[k] = float(rec[k])
        out.append(rec)
    return out


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('input');p.add_argument('prefix')
    a = p.parse_args()
    all_paths = paths(a.input)
    worst = {}
    for r in all_paths:
        if r['slack_ns'] is None:
            continue
        key = (r['endpoint'],r['type'],r['capture_edge'])
        if key not in worst or r['slack_ns'] < worst[key]['slack_ns']:
            worst[key] = r
    result = dict(source=str(Path(a.input).resolve()),all_paths=all_paths,
                  worst_per_pin_corner_check_edge=list(worst.values()))
    Path(a.prefix+'.json').write_text(json.dumps(result,indent=2))
    lines=['|引脚|检查/角|PHY采样沿|数据到达 ns|要求 ns|裕量 ns|原报告行|',
           '|---|---|---|---:|---:|---:|---:|']
    for r in worst.values():
        lines.append('|{endpoint}|{type}|{capture_edge}|{data_arrival_ns}|{data_required_ns}|{slack_ns}|{line}|'.format(**r))
    Path(a.prefix+'.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('Parsed',len(all_paths),'paths;',len(worst),'pin/corner/check/edge windows')
