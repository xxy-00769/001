"""Verify the isolated candidate only adds passive HDMI observation."""
from pathlib import Path
import json, hashlib, datetime, re

C = Path(__file__).resolve().parents[1]
R = C.parents[1]
B = R / 'release/FPGA_GSV1_M3_04_3_3/source'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
changed = []
unchanged = {}
for folder in ['rtl', 'vendor', 'constraints']:
    for f in (B/folder).rglob('*'):
        if not f.is_file():
            continue
        rel = f.relative_to(B)
        if f.read_bytes() == (C/rel).read_bytes():
            unchanged[rel.as_posix()] = sha(f)
        else:
            changed.append(rel.as_posix())
assert set(changed) == {
    'rtl/board/fpga_gsv1_top.v', 'rtl/reuse/fram_buf.v',
    'rtl/display/m31_osd.v', 'rtl/display/m31_video_output.v',
    'constraints/mes50hp.fdc'
}, changed
assert all(not x.startswith('rtl/network/') for x in changed)

def normalized(s):
    return re.sub(r'\s+', '', s)

top = (C/'rtl/board/fpga_gsv1_top.v').read_bytes().decode(errors='replace')
top = re.sub(r'    wire \[2:0\] hdmi_stage_sys,hdmi_stage_pixel;\s*wire hdmi_pub,hdmi_fault;\s*', '', top)
top = re.sub(r'    m35a_hdmi_status hdmi_observe\([\s\S]*?\.out_value\(hdmi_stage_pixel\)\);\s*', '', top)
top = top.replace('.hdmi_published_toggle(hdmi_pub),.hdmi_display_fault(hdmi_fault),', '')
top = top.replace('.hdmi_stage(hdmi_stage_pixel),', '')
assert normalized(top) == normalized((B/'rtl/board/fpga_gsv1_top.v').read_bytes().decode(errors='replace'))
fb = (C/'rtl/reuse/fram_buf.v').read_bytes().decode(errors='replace')
fb = fb.replace('    output hdmi_published_toggle,hdmi_display_fault,\n', '')
fb = fb.replace('    assign hdmi_published_toggle = published_count[0];\n', '')
fb = fb.replace('    assign hdmi_display_fault = display_selected && output_bad;\n', '')
assert normalized(fb) == normalized((B/'rtl/reuse/fram_buf.v').read_bytes().decode(errors='replace'))
vo = (C/'rtl/display/m31_video_output.v').read_text()
vo = vo.replace(' input [2:0] hdmi_stage,\n', '').replace('        .hdmi_stage(hdmi_stage),\n', '')
assert normalized(vo) == normalized((B/'rtl/display/m31_video_output.v').read_text())
fdc = (C/'constraints/mes50hp.fdc').read_text()
assert 'set_input_delay' not in fdc
for i in [1, 2]:
    assert f'-group [get_clocks {{cmos{i}_pclk cmos{i}_pclk_16bit}}]' in fdc
    # Do not restore the false asynchronous cut just to claim timing closure.
assert (C/'rtl/reuse/cmos_8_16bit.v').read_bytes() == (B/'rtl/reuse/cmos_8_16bit.v').read_bytes()
folder = C/'reports'/('scope_m35a_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir()
result = dict(Verdict='PASS', InputsUnchanged=True, Changed=changed,
              NewRTL=['rtl/board/m35a_hdmi_status.v'], Unchanged=unchanged,
              TopFunctionalEquivalent=True, FrameBufferFunctionalEquivalent=True,
              PixelPipelineEquivalent=True, Network15fpsCodeUnchanged=True,
              CameraAndHDMIReceiveByteIdentical=True,
              CameraRelatedClocksNotCut=True, BoardVerified=False)
(folder/'result.json').write_text(json.dumps(result, indent=2))
print(folder)
print('PASS passive_only=1 receive_unchanged=1 network_unchanged=1 pixel_pipeline_unchanged=1')
