"""Compare this camera checkpoint with the frozen, hardware-accepted TXDET1."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parents[1] / 'release/FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE/source'
PROTECTED = [
    'rtl/reuse/reg_config.v', 'rtl/reuse/i2c_com.v',
    'rtl/reuse/cmos_8_16bit.v', 'rtl/reuse/power_on_delay.v',
    'rtl/network/m36_phy2.v', 'rtl/network/m364_e1_rgmii.v',
    'rtl/network/m3_eth_pll.v', 'rtl/network/m3_mac.v',
    'rtl/network/m3_net_core.v', 'rtl/network/m3_upload.v',
    'rtl/capture/hdmi_input.v', 'rtl/board/m364_ref_dividers.v',
    'rtl/reuse/fram_buf.v', 'constraints/mes50hp.fdc',
]
for name in PROTECTED:
    assert (BASE / name).read_bytes() == (ROOT / name).read_bytes(), name
name = 'rtl/network/m3_network.v'
old = (BASE / name).read_text()
new = (ROOT / name).read_text()
new = new.replace(
    'input [255:0] rdata,input rvalid,rlast,upload_rvalid,upload_rlast,\n input [127:0] camera_diagnostics);',
    'input [255:0] rdata,input rvalid,rlast,upload_rvalid,upload_rlast);')
new = new.replace(
    '.txv(tx_valid),.txd(tx_data),.camera_diagnostics(camera_diagnostics),.uart_tx(diagnostic_tx));',
    '.txv(tx_valid),.txd(tx_data),.uart_tx(diagnostic_tx));')
assert old == new, 'network change beyond passive diagnostic forwarding'
report = dict(protected_equal=PROTECTED, network_only_passive_forwarding=True)
allowed_changes = {'rtl/board/fpga_gsv1_top.v', 'rtl/network/m3_network.v',
                   'rtl/network/m365_tx_observer.v', 'flow.tcl'}
changed = []
for directory in ['rtl', 'vendor', 'constraints', 'config']:
    for file in (BASE / directory).rglob('*'):
        if file.is_file():
            relative = file.relative_to(BASE).as_posix()
            assert (ROOT / relative).is_file(), f'deleted production input: {relative}'
            if file.read_bytes() != (ROOT / relative).read_bytes():
                assert relative in allowed_changes, f'out-of-scope production change: {relative}'
                changed.append(relative)
old_top = (BASE / 'rtl/board/fpga_gsv1_top.v').read_text()
new_top = (ROOT / 'rtl/board/fpga_gsv1_top.v').read_text()
for start, end in [('//CMOS1 Camera', '//CMOS2 Camera'),
                   ('//CMOS1\n', '//CMOS2\n'),
                   ('    wire pipe_rst0, verdict_valid0;', '    wire pipe_rst1, verdict_valid1;')]:
    # Original initialization uses //CMOS2 Camera; adapted CAM1 now has a
    # different explanatory comment. Compare the actual CAM0 instance only.
    if start == '//CMOS1 Camera':
        a=old_top.split(start,1)[1].split('    );',1)[0]
        b=new_top.split(start,1)[1].split('    );',1)[0]
    else:
        a=old_top.split(start,1)[1].split(end,1)[0]
        b=new_top.split(start,1)[1].split(end,1)[0]
    assert a == b, f'CAM0 changed in top: {start}'
report['all_changed_existing_production_files'] = changed
report['cam0_top_init_sampler_upload_chain_equal'] = True
(ROOT / 'reports/protected_scope_check.json').write_text(
    json.dumps(report, indent=2), encoding='utf-8')
print('PASS scope: camera0/PHY/PLL/RGMII/MAC/protocol/HDMI/DDR/constraints unchanged; network only forwards UART camera status')
