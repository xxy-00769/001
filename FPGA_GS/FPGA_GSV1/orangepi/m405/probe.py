import onnxruntime as o,cv2,numpy as np,time,json
opt=o.SessionOptions();opt.intra_op_num_threads=3;opt.inter_op_num_threads=1
s=o.InferenceSession('m405/yolop.onnx',opt,providers=['CPUExecutionProvider'])
print([(x.name,x.shape) for x in s.get_inputs()],[(x.name,x.shape) for x in s.get_outputs()],flush=True)
c=cv2.VideoCapture('media/SC_BT.mp4');c.set(0,0);c.set(cv2.CAP_PROP_POS_MSEC,32000);ok,im=c.read();cv2.imwrite('m405/evidence/probe_raw.jpg',im)
x=cv2.cvtColor(cv2.resize(im,(640,360)),cv2.COLOR_BGR2RGB)/255.;x=(x-np.array([.485,.456,.406]))/np.array([.229,.224,.225]);x=np.pad(x,((140,140),(0,0),(0,0))).astype('float32').transpose(2,0,1)[None]
for i in range(4):
 t=time.perf_counter();r=s.run(['drive_area_seg','lane_line_seg'],{'images':x});print('ms',1000*(time.perf_counter()-t),[(z.shape,float(z.min()),float(z.max())) for z in r],flush=True)
np.savez_compressed('m405/evidence/probe.npz',road=r[0],lane=r[1]);cv2.imwrite('m405/evidence/probe_road.png',(r[0][0].argmax(0)*255).astype('uint8'));cv2.imwrite('m405/evidence/probe_lane.png',(r[1][0].argmax(0)*255).astype('uint8'))
