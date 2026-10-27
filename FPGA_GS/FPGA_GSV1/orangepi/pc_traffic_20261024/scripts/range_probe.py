import urllib.request,concurrent.futures,time,json
u='https://download.pytorch.org/whl/cu124/torch-2.5.1%2Bcu124-cp311-cp311-win_amd64.whl'
def test(i):
 t=time.time();req=urllib.request.Request(u+'?pc_preflight_range='+str(i),headers={'Range':f'bytes={i*1048576}-{(i+1)*1048576-1}'})
 with urllib.request.urlopen(req,timeout=30) as r:
  data=r.read();return i,r.status,r.headers.get('Content-Range'),len(data),round(time.time()-t,2)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as e:
 for x in e.map(test,range(4)):print(x,flush=True)
