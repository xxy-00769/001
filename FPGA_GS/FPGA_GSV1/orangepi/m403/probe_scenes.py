import cv2,numpy as np,pathlib
r=pathlib.Path(__file__).resolve().parents[1];out=r/'m403/evidence'
cap=cv2.VideoCapture(str(r/'media/SC_YJ.mp4'));tiles=[]
for sec in range(40,131,5):
 cap.set(0 if False else cv2.CAP_PROP_POS_MSEC,sec*1000);ok,im=cap.read()
 if not ok:continue
 h,w=im.shape[:2];view=im[int(h*.32):int(h*.57),int(w*.44):int(w*.76)]
 tile=cv2.resize(view,(480,240));cv2.putText(tile,f'{sec}s',(8,24),0,.7,(255,255,255),2);tiles.append(tile)
 cv2.imwrite(str(out/f'YJ_scene_{sec}.jpg'),im)
while len(tiles)%3:tiles.append(np.zeros_like(tiles[0]))
cv2.imwrite(str(out/'YJ_signal_timeline.jpg'),np.vstack([np.hstack(tiles[i:i+3]) for i in range(0,len(tiles),3)]))
cap.release()
