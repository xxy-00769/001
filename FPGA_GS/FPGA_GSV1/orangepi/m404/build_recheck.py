from pathlib import Path
s=Path('orangepi/m404/final_preview.cjs').read_text(encoding='utf-8')
s=s.replace("'evidence/final'","'evidence/recheck'")
s=s.replace("[['SC_BT.mp4',51,640],['SC_BT2.mp4',8,640],['SC_YJ.mp4',93,640],['SC_YJ2.mp4',16,640],['SC_BT.mp4',50,1280],['SC_YJ.mp4',70,1280]]","[['SC_YJ2.mp4',16,640],['SC_BT.mp4',50,1280]]")
Path('orangepi/m404/recheck_preview.cjs').write_text(s,encoding='utf-8')
