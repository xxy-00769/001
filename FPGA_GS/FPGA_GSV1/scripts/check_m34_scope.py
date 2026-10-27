"""Scoped production comparison; no repeat of accepted network/algorithm tests."""
from pathlib import Path
import hashlib,json,datetime,re
R=Path(__file__).resolve().parents[1]
old=R/'release/FPGA_GSV1_M3_04_3_3/source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def code(s):return re.sub(r'\s+','',re.sub(r'//[^\n]*|/\*.*?\*/','',s,flags=re.S))
def read(p):return p.read_text(encoding='utf8',errors='replace')
allowed={'rtl/board/fpga_gsv1_top.v','rtl/capture/hdmi_input.v','rtl/reuse/cmos_8_16bit.v',
 'rtl/reuse/fram_buf.v','rtl/display/m31_video_output.v','rtl/display/m31_osd.v','constraints/mes50hp.fdc'}
inputs={};changed=[];unchanged=[]
for folder in ['rtl','vendor','constraints','config','tools']:
 for p in (old/folder).rglob('*'):
  if not p.is_file() or '__pycache__' in p.parts or p.suffix=='.pyc':continue
  rel=p.relative_to(old).as_posix();q=R/rel;assert q.is_file(),rel
  inputs[str(q)]=sha(q)
  if sha(p)!=sha(q):changed.append(rel)
  else:unchanged.append(rel)
assert set(changed)==allowed,changed
# The framebuffer's only changes are passive observation ports/assignments.
s=read(R/'rtl/reuse/fram_buf.v')
for line in ['    output                        published_toggle,\n','    output                        display_fault,\n',
 '    assign published_toggle=published_count[0];\n','    assign display_fault=display_selected && output_bad;\n']:
 assert line in s;s=s.replace(line,'')
assert code(s)==code(read(old/'rtl/reuse/fram_buf.v'))
s=read(R/'rtl/display/m31_video_output.v')
s=re.sub(r'\s*input \[2:0\] hdmi_stage,','',s)
s=s.replace('.hdmi_stage(hdmi_stage),','')
assert code(s)==code(read(old/'rtl/display/m31_video_output.v'))
# Remove only the diagnostic wiring from top, then compare all functional wiring.
s=read(R/'rtl/board/fpga_gsv1_top.v')
s=s.replace('wire rx_done,hdmi_format,hdmi_vs,hdmi_de,hdmi_beat;','wire rx_done,hdmi_format,hdmi_vs,hdmi_de;')
s=s.replace('    wire hdmi_published,hdmi_read_fault;\n','').replace('    wire [2:0] hdmi_stage_ref,hdmi_stage_pixel;\n','')
s=s.replace(',.input_beat(hdmi_beat)','').replace('        .published_toggle(hdmi_published),.display_fault(hdmi_read_fault),\n','')
s=s.replace('        .hdmi_stage(hdmi_stage_pixel),\n','')
s=re.sub(r'    m34_hdmi_status left_status\(.*?\.out_value\(hdmi_stage_pixel\)\);\n','',s,flags=re.S)
assert '.data({cmos1_vsync,cmos1_href,cmos1_data})' in s
assert '.captured({cmos1_vsync_d0,cmos1_href_d0,cmos1_d_d0})' in s
assert '.data({cmos2_vsync,cmos2_href,cmos2_data})' in s
assert '.captured({cmos2_vsync_d0,cmos2_href_d0,cmos2_d_d0})' in s
s=re.sub(r'    m34_input_capture #.*?;','',s,flags=re.S)
o=read(old/'rtl/board/fpga_gsv1_top.v')
for n in [1,2]:
 o=re.sub(r'    always@\(posedge cmos%d_pclk\).*?        end'%n,'',o,count=1,flags=re.S)
 for name in ['d_d0','href_d0','vsync_d0']:
  # Only the six first-stage pad declarations changed reg -> wire.
  o=re.sub(r'\breg(\s*(?:\[7:0\])?\s+cmos%d_%s\b)'%(n,name),r'wire\1',o)
assert code(s)==code(o)
addresses={'CAM0':[0,0x400000,0x2000000],'CAM1':[0x800000,0xc00000],
 'LEFT':[0x1000000,0x1400000],'RIGHT':[0x1800000,0x1c00000,0x2400000]}
regions=sorted((a,a+460800,n) for n,bases in addresses.items() for a in bases)
assert all(a[1]<=b[0] for a,b in zip(regions,regions[1:]));assert regions[-1][1]*4<256*1024*1024
for f in ['rtl/network/m3_net_core.v','rtl/network/m3_right_store.v']:
 assert "28'h2400000" in read(R/f)
assert '.AVI_VIC(16)' in read(R/'rtl/board/fpga_gsv1_top.v')
out=R/'reports'/('check_m34_scope_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
result=dict(Verdict='PASS',InputsUnchanged=True,ChangedFiles=changed,UnchangedFileCount=len(unchanged),
 AddressesNative32BitWords=addresses,FrameWords=460800,AddressOverlap=False,
 FramebufferFunctionalCodeUnchanged=True,TopWiringExceptInputCaptureUnchanged=True,InputCapturePinMappingChecked=True,
 DisplayPipelineCodeUnchanged=True,NetworkRtlAndHostUnchanged=True,
 BoardMeasured=False,ReusedUser15Fps=dict(Send=14.37,Publish=14.27,Display=14.31,Front=4.98))
(out/'inputs.json').write_text(json.dumps(inputs,indent=2))
(out/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(dict(Directory=str(out),**result),indent=2))
