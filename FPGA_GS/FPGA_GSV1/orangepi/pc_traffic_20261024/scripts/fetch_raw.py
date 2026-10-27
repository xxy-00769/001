import urllib.request,concurrent.futures
from pathlib import Path
root=Path(__file__).resolve().parents[1]
urls={
's2tld_readme':'https://raw.githubusercontent.com/Thinklab-SJTU/S2TLD/master/README.md',
's2tld_license':'https://raw.githubusercontent.com/Thinklab-SJTU/S2TLD/master/LICENSE',
'rknn_yolov8_readme':'https://raw.githubusercontent.com/airockchip/rknn_model_zoo/main/examples/yolov8/README.md',
'rknn_toolkit_readme':'https://raw.githubusercontent.com/airockchip/rknn-toolkit2/master/README.md',
'rknn_supported_ops':'https://raw.githubusercontent.com/airockchip/rknn-toolkit2/master/doc/RKNNToolKit2_OP_Support-v2.3.2.md',
}
def get(kv):
 k,u=kv
 try:
  raw=urllib.request.urlopen(u,timeout=30).read();(root/'sources'/f'{k}.txt').write_bytes(raw);print(k,raw.decode()[:10500],flush=True)
 except Exception as e:print(k,repr(e),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as e:list(e.map(get,urls.items()))
