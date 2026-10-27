import ctypes,json,sys,platform,importlib.metadata as m
from pathlib import Path
r=Path(__file__).resolve().parents[1];out={'python':sys.version,'executable':sys.executable,'platform':platform.platform(),'driver_only_probe':True,'pytorch_cuda_validated':False}
try:
 c=ctypes.WinDLL('nvcuda.dll');v=ctypes.c_int();n=ctypes.c_int();dev=ctypes.c_int();name=ctypes.create_string_buffer(256);total=ctypes.c_size_t();ctx=ctypes.c_void_p();ptr=ctypes.c_uint64();free=ctypes.c_size_t();allmem=ctypes.c_size_t()
 calls=[]
 def ok(name,*args):
  result=getattr(c,name)(*args);calls.append({'call':name,'return':result});assert result==0,(name,result)
 ok('cuInit',0);ok('cuDriverGetVersion',ctypes.byref(v));ok('cuDeviceGetCount',ctypes.byref(n));ok('cuDeviceGet',ctypes.byref(dev),0);ok('cuDeviceGetName',name,256,dev);ok('cuDeviceTotalMem_v2',ctypes.byref(total),dev)
 ok('cuCtxCreate_v2',ctypes.byref(ctx),0,dev)
 try:
  ok('cuMemGetInfo_v2',ctypes.byref(free),ctypes.byref(allmem));ok('cuMemAlloc_v2',ctypes.byref(ptr),ctypes.c_size_t(64*1024*1024))
  try:ok('cuMemsetD8_v2',ptr,123,ctypes.c_size_t(64*1024*1024));ok('cuCtxSynchronize')
  finally:ok('cuMemFree_v2',ptr)
 finally:ok('cuCtxDestroy_v2',ctx)
 out.update({'passed':True,'cuda_driver_api_version':v.value,'device_count':n.value,'name':name.value.decode(),'total_bytes':total.value,'free_bytes_at_probe':free.value,'probe':'allocate, memset, synchronize, free 64MiB; not a Torch training test','calls':calls})
except Exception as e:out.update({'passed':False,'error':repr(e)})
(r/'reports/cuda_driver_probe.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2))
