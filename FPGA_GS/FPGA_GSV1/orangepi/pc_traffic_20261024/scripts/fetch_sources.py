import urllib.request,json,concurrent.futures,base64
from pathlib import Path
root=Path(__file__).resolve().parents[1]
urls={
's2tld_readme':'https://api.github.com/repos/Thinklab-SJTU/S2TLD/contents/README.md',
's2tld_license':'https://api.github.com/repos/Thinklab-SJTU/S2TLD/contents/LICENSE',
'rknn_yolov8_readme':'https://api.github.com/repos/airockchip/rknn_model_zoo/contents/examples/yolov8/README.md',
'rknn_toolkit_readme':'https://api.github.com/repos/airockchip/rknn-toolkit2/contents/README.md',
'hf_s2tld_tree':'https://huggingface.co/api/datasets/yangxue/S2TLD/tree/main?recursive=true',
'hf_s2tld_readme':'https://huggingface.co/datasets/yangxue/S2TLD/raw/main/README.md',
}
def get(item):
 key,url=item
 try:
  raw=urllib.request.urlopen(url,timeout=40).read()
  if 'api.github.com' in url:
   obj=json.loads(raw); raw=base64.b64decode(obj['content'])
  (root/'sources'/f'{key}.txt').write_bytes(raw)
  print(key,raw.decode()[:6500],flush=True)
 except Exception as e: print(key,repr(e),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:list(ex.map(get,urls.items()))
