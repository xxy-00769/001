from pathlib import Path
p=Path('orangepi/oneclick/demo_launcher.ps1');s=p.read_text(encoding='utf-8-sig')
s=s.replace("Write-Host '复用已有本项目SSH转发。'",'''foreach($own in $known){
   if($own.CommandLine -notmatch ([regex]::Escape($target)+'(?:\\s|$)')){
    Stop-Process -Id $own.ProcessId
    Write-Host '已关闭身份核实的旧地址项目转发，按集中配置重建。'
   }
  }
  $listeners=@(Get-NetTCPConnection -LocalPort $cfg.local_port -State Listen -ErrorAction SilentlyContinue)
  if($listeners.Count){Write-Host '复用已有本项目SSH转发。'}''')
p.write_text(s,encoding='utf-8-sig')
p=Path('orangepi/m404/overlay.py');s=p.read_text(encoding='utf-8')
s=s.replace("[('left',.39),('straight',.5),('right',.61)]","[('left',.08),('straight',.17),('right',.26)]").replace('y=int(hh*.72)','y=int(hh*.78)')
s=s.replace(" for obj,tx,ty in targets:\n", " occupied=[]\n for obj,tx,ty in targets:\n")
s=s.replace("(' 跟踪' if obj['source']!='detection' else '')", "('·续' if obj['source']!='detection' else '')")
s=s.replace("im=tile(label,round(13*s),(255,255,255));bg=", "im=tile(label,round(13*s),(255,255,255))\n  for delta in [0,-18,18,-36,36,-54,54]:\n   yy=max(round(100*s),min(hh-round(82*s),ty+round(delta*s)));bb=(tx,yy,tx+im.width,yy+im.height)\n   if not any(bb[0]<a[2] and bb[2]>a[0] and bb[1]<a[3] and bb[3]>a[1] for a in occupied):ty=yy;break\n  occupied.append((tx,ty,tx+im.width,ty+im.height))\n  bg=")
p.write_text(s,encoding='utf-8')
