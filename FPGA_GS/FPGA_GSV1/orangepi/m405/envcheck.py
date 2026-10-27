import importlib.util
for x in ['torch','scipy','onnx','tqdm','fast_histogram','psutil']:
 print(x,bool(importlib.util.find_spec(x)))
