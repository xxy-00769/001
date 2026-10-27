from pathlib import Path
root=Path(__file__).resolve().parents[1];one=root/'oneclick'
p=one/'demo_launcher.ps1';s=p.read_text(encoding='utf-8-sig').replace("'m405r2/demo_ops.py'))", "'m405r2/demo_ops.py','m406/demo_ops.py'))").replace("else{'M4-04-r1'}", "elseif($cfg.demo_ops -eq 'm406/demo_ops.py'){'M4-06-r1'}else{'M4-04-r1'}");p.write_text(s,encoding='utf-8-sig')
p=one/'set_demo_version.ps1';s=p.read_text(encoding='utf-8-sig').replace("'m405','m405r2')", "'m405','m405r2','m406')");p.write_text(s,encoding='utf-8-sig')
for name,v in [('切回M4-06-r1交通灯.cmd','m406'),('回退M4-05-r2车道结构.cmd','m405r2')]:
 (one/name).write_text('@echo off\nchcp 65001 >nul\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0set_demo_version.ps1" -Version '+v+'\n',encoding='utf-8')
p=root/'m406/index.html';s=p.read_text(encoding='utf8').replace('交通灯 CPU自动灯壳/灯色','交通灯 NPU灯体 + CPU灯壳/灯色').replace('Hz / 目标8Hz','Hz / 交通灯目标4Hz');p.write_text(s,encoding='utf8')
p=root/'m406/demo.py';s=p.read_text(encoding='utf8').replace('error=self.last_error,','error=self.last_error or self.lights.error,');p.write_text(s,encoding='utf8')
p=root/'m406/demo_ops.py';s=p.read_text(encoding='utf8').replace("get('completed',0)>0:","get('completed',0)>0 and s.get('data',{}).get('traffic',{}).get('completed',0)>0:");p.write_text(s,encoding='utf8')
