import urllib.request,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
urls={
's2tld_repo':'https://api.github.com/repos/Thinklab-SJTU/S2TLD/contents',
'rknn_repo':'https://api.github.com/repos/airockchip/rknn_model_zoo/contents/examples/yolov8',
'hf_s2tld':'https://huggingface.co/api/datasets?search=S2TLD',
}
for key,url in urls.items():
 try:
  raw=urllib.request.urlopen(url,timeout=30).read(); (root/'sources'/f'{key}.json').write_bytes(raw)
  data=json.loads(raw)
  print(key,[(x.get('name') or x.get('id'),x.get('download_url')) for x in data][:25])
 except Exception as e: print(key,repr(e))
