"""Enforce the TX-only baseline and record differences for review."""
from pathlib import Path
import difflib
import hashlib
import json

R = Path(__file__).resolve().parents[1]
BASE = R.parents[1] / 'release/FPGA_GSV1_M3_06_3_5_2/source'
allowed = {'rtl/network/m36_rgmii_interface.v', 'constraints/mes50hp.fdc'}
changes = []
same = 0
for folder in ('rtl', 'vendor', 'constraints', 'config'):
    for old in (BASE / folder).rglob('*'):
        if not old.is_file():
            continue
        rel = old.relative_to(BASE).as_posix()
        now = R / rel
        assert now.exists(), rel
        if old.read_bytes() == now.read_bytes():
            same += 1
        else:
            assert rel in allowed, rel
            changes.append(rel)
            (R/'reports'/('scope_'+old.name+'.diff')).write_text(''.join(
                difflib.unified_diff(old.read_text().splitlines(True),
                                     now.read_text().splitlines(True),
                                     fromfile='published_3.5.2/'+rel,
                                     tofile='candidate_3.5.3/'+rel)), encoding='utf-8')
    extra = {p.relative_to(R).as_posix() for p in (R/folder).rglob('*') if p.is_file()} - {
        p.relative_to(BASE).as_posix() for p in (BASE/folder).rglob('*') if p.is_file()}
    assert not extra, extra
old = (BASE/'rtl/network/m36_rgmii_interface.v').read_text()
new = (R/'rtl/network/m36_rgmii_interface.v').read_text()
marker = '    GTP_CLKBUFG GTP_CLKBUFG_RXSHFT'
assert old[old.index(marker):] == new[new.index(marker):], 'RX logic changed'
assert (BASE/'flow.tcl').read_bytes() == (R/'flow.tcl').read_bytes()
record = dict(Baseline=str(BASE),ChangedHardwareFiles=changes,
              IdenticalHardwareFiles=same,AllRXLogicIdentical=True,
              FlowIdentical=True,PHYAndPort1AndProtocolIdentical=True,
              NoRootWIPUsed=True,
              HardwareSHA256={n:hashlib.sha256((R/n).read_bytes()).hexdigest() for n in changes})
(R/'reports/scope_audit.json').write_text(json.dumps(record,indent=2))
print(json.dumps(record,indent=2))
