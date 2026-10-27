from pathlib import Path
p=Path(__file__).parent/'index.html';s=p.read_text(encoding='utf-8')
start=s.index('<div class="row"><span>定位真实片段：');end=s.index('<div class="panel">',start)
s=s[:start]+'''<div class="row"><span>本轮观察片段：</span><button data-scene="clear">日间实虚线 26秒</button><button data-scene="solid">日间道路 32秒</button><button data-scene="junction">路口 8秒</button><button data-scene="occluded">黄昏遮挡 12秒</button><button data-scene="weak">夜间标线 150秒</button><button data-scene="curve">高架轻弯 50秒</button></div>'''+s[end:]
start=s.index('const scenes=');end=s.index("document.querySelectorAll('[data-scene]')",start)
s=s[:start]+'''const scenes={clear:{video:'SC_BT.mp4',seek:26,mode:'lane'},solid:{video:'SC_BT.mp4',seek:32,mode:'lane'},junction:{video:'SC_BT.mp4',seek:8,mode:'lane'},occluded:{video:'SC_BT2.mp4',seek:12,mode:'lane'},weak:{video:'SC_YJ.mp4',seek:150,mode:'lane'},curve:{video:'SC_YJ2.mp4',seek:50,mode:'lane'}};
'''+s[end:]
s=s.replace("(label[ls[k]?.state]||'未知')+' / 相邻车道 '","(label[ls[k]?.state]||'未知')+(ls[k]?.ownership==='CANDIDATE_NOT_PAIRED'?'（归属待确认）':'')+' / 相邻车道 '")
s=s.replace('虚线框为短时光流延续，最长350ms','目标虚线框为短时光流延续，最长350ms')
p.write_text(s,encoding='utf-8')
