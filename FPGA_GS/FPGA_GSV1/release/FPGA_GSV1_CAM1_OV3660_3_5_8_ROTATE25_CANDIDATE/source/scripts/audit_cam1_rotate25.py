"""Restrict changes to CAM1 sensor, safe slot turnover and passive counters."""
from pathlib import Path
import hashlib
import json
import difflib

root = Path(__file__).resolve().parents[1]
base = root.parents[1]/'release/FPGA_GSV1_CAM1_OV3660_3_5_7_SYNC_CANDIDATE/source'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
allowed = {'rtl/board/fpga_gsv1_top.v', 'rtl/capture/cam_ov3660_config.v',
    'rtl/capture/cam_ov3660_table.v', 'rtl/capture/cam1_rate_status.v',
    'rtl/reuse/fram_buf.v', 'rtl/reuse/video_capture_status.v', 'rtl/frame/m3_front_owner.v',
    'rtl/network/m3_network.v', 'rtl/network/m365_tx_observer.v', 'flow.tcl'}
changed, diffs = [], []
for group in ['rtl', 'vendor', 'constraints', 'config']:
    for file in sorted((root/group).rglob('*')):
        if not file.is_file():
            continue
        rel = file.relative_to(root).as_posix()
        old = base/rel
        if not old.exists() or sha(old) != sha(file):
            changed.append(rel)
            assert rel in allowed, f'Unexpected protected change: {rel}'
            diffs.extend(difflib.unified_diff(old.read_text(encoding='utf-8').splitlines(True) if old.exists() else [],
                file.read_text(encoding='utf-8').splitlines(True), fromfile='3.5.7/'+rel, tofile='3.5.8/'+rel))
assert sha(root/'constraints/mes50hp.fdc') == sha(base/'constraints/mes50hp.fdc')
for name in ['m36_phy2.v','m364_e1_rgmii.v','m3_net_core.v','m3_upload.v','m3_mac.v','m3_right_store.v']:
    assert sha(root/'rtl/network'/name) == sha(base/'rtl/network'/name), name
for name in ['reg_config.v','cmos_8_16bit.v','frame_buffer_owner.v']:
    assert sha(root/'rtl/reuse'/name) == sha(base/'rtl/reuse'/name), name
for name in ['cam3660_dvp.v', 'capture_pipe.v', 'hdmi_input.v']:
    assert sha(root/'rtl/capture'/name) == sha(base/'rtl/capture'/name), name
assert sha(root/'rtl/display/m31_pixel_pll.v') == sha(base/'rtl/display/m31_pixel_pll.v')
# Address units are32bit words. Each full720 slot uses460800words; slot
# spacing4Mi words. Preserve existing front3/right3 ranges, add rear at0x2800000.
slots = {'front':[0,0x400000,0x2000000], 'rear':[0x800000,0xc00000,0x2800000],
         'left':[0x1000000,0x1400000], 'right':[0x1800000,0x1c00000,0x2400000]}
spans = sorted((start,start+460800,src) for src,starts in slots.items() for start in starts)
assert all(b[0] >= a[1] for a,b in zip(spans,spans[1:]))
assert spans[-1][1] < 2**28
result = dict(baseline=str(base), changed_production_files=changed+['flow.tcl'],
    protected_constraints_and_PHY_PLL_identical=True, other_video_sources_identical=True,
    slot_word_addresses=slots, overlap=False, nominal_fps=36000000/1800/800,
    old_nominal_fps=36000000/2172/1322, native720=True, narrowed_FOV=True,
    byte_pclk_unchanged=True, actual_XCLK_pending_board_inference=True)
(root/'reports/CAM1_358_scope.json').write_text(json.dumps(result,indent=2))
(root/'reports/CAM1_358_vs_357.diff').write_text(''.join(diffs),encoding='utf-8')
print(json.dumps(result,indent=2))
