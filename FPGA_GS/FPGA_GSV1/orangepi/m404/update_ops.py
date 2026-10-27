from pathlib import Path
import json
r=Path('orangepi');p=r/'m404'
s=(r/'m403/demo_ops.py').read_text(encoding='utf-8').replace("['.venv/bin/python','m403/demo.py'","['.venv404/bin/python','m404/demo.py'").replace("ROOT/'m403/state'","ROOT/'m404/state'").replace("=='M4-03-demo-r1'","=='M4-04-r1'").replace('查看m403/state/','查看m404/state/')
(p/'demo_ops.py').write_text(s,encoding='utf-8')
f=r/'oneclick/demo_launcher.ps1';s=f.read_text(encoding='utf-8-sig').replace("version='M4-03-demo-r1'","version='M4-04-r1'")
s=s.replace('$b64=[Convert]',"if(!$cfg.demo_ops){$cfg|Add-Member demo_ops 'm404/demo_ops.py'}\n $b64=[Convert]")
s=s.replace('m403/demo_ops.py $($Action.ToLower())','$($cfg.demo_ops) $($Action.ToLower())')
s=s.replace("$child=Start-Process $ssh -ArgumentList $args -PassThru -WindowStyle Normal","$child=Start-Process $ssh -ArgumentList $args -PassThru -WindowStyle Hidden")
f.write_text(s,encoding='utf-8-sig')
f=r/'oneclick/config.json';cfg=json.loads(f.read_text(encoding='utf-8-sig'));cfg['demo_ops']='m404/demo_ops.py';cfg['demo_preview_width']=640
f.write_text(json.dumps(cfg,ensure_ascii=False,indent=2),encoding='utf-8')
